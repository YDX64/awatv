import 'dart:async';
import 'dart:convert';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/sync/device_fingerprint.dart';
import 'package:awatv_mobile/src/shared/sync/sync_envelope.dart';
import 'package:awatv_mobile/src/shared/sync/sync_error.dart';
import 'package:awatv_mobile/src/shared/sync/sync_queue.dart';
import 'package:awatv_mobile/src/shared/sync/sync_status.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Cross-device sync orchestrator.
///
/// Lifecycle (driven by `cloudSyncEnginePulseProvider`):
///   activate   — premium + signed-in + Supabase configured
///   deactivate — sign-out, downgrade, or backend missing
///
/// On activate the engine:
///   1. Pulls every owned row in `favorites` / `watch_history` /
///      `playlist_sources` and merges into Hive (last-writer-wins).
///   2. Pushes any local row newer than the latest remote one.
///   3. Subscribes to Realtime postgres_changes for those tables
///      filtered to the live `user_id`. Inserts/updates merge into
///      Hive; deletes drop the local copy (RLS guarantees only the
///      owning user can fire a delete).
///   4. Hooks into the storage box `watch` streams so any local
///      mutation produces an outgoing upsert.
///
/// On deactivate every subscription is cancelled and the queue
/// is left intact so a future reconnect drains it.
///
/// **Schema gaps** (flagged for the coordinator):
///   * `favorites` and `playlist_sources` have no `updated_at` column
///     — the engine derives a comparable timestamp from `added_at` and
///     `last_sync_at` respectively, but a future migration adding a
///     proper `updated_at` (with a trigger) would simplify this.
///   * No soft-delete column anywhere — the engine relies on Realtime
///     DELETE events. RLS makes this safe; if Realtime ever drops a
///     DELETE the local row will be re-pushed on next activation.
class CloudSyncEngine {
  CloudSyncEngine({
    required AwatvStorage storage,
    required SyncQueue queue,
    supa.SupabaseClient? client,
  })  : _storage = storage,
        _queue = queue,
        _client = client;

  final AwatvStorage _storage;
  final SyncQueue _queue;

  /// Optional Supabase client. Null on builds where the developer hasn't
  /// configured `SUPABASE_URL` / `SUPABASE_ANON_KEY`. Every consumer of
  /// `_client` early-returns when null so the engine becomes a polite
  /// no-op rather than throwing a LateInitializationError on access of
  /// `Supabase.instance` (which is itself a `late final`).
  final supa.SupabaseClient? _client;

  /// Hive prefs key for the last successful pull/push timestamp. Used
  /// for "Senkron — son güncelleme: 2 dakika önce" copy.
  static const String _kLastSyncAtKey = 'sync:last_sync_at';

  /// Cached pulled-row timestamps so we know when a local change is
  /// truly newer than the latest server copy. Keyed per-table inside
  /// the prefs box as JSON.
  static const String _kRemoteFavStateKey = 'sync:remote_fav_at';
  static const String _kRemoteHistoryStateKey = 'sync:remote_history_at';
  static const String _kRemoteSourceStateKey = 'sync:remote_source_at';

  // -- Live state ------------------------------------------------------------
  String? _userId;
  DeviceFingerprint? _fingerprint;
  String? _deviceRowId;
  bool _activating = false;
  bool _active = false;

  supa.RealtimeChannel? _channel;
  StreamSubscription<BoxEvent>? _favBoxSub;
  StreamSubscription<BoxEvent>? _historyBoxSub;
  StreamSubscription<BoxEvent>? _sourceBoxSub;
  Timer? _drainTicker;
  Timer? _heartbeatTicker;

  // History pushes are debounced per-item so a 5s player tick doesn't
  // flood the network. Map of itemId → (pendingTimer, latestEntry).
  final Map<String, Timer> _historyDebounces = <String, Timer>{};

  // ---------------------------------------------------------------------------
  // Remote-origin guard — prevents push/subscribe loops.
  //
  // When the engine receives a Realtime change it writes to Hive; the Hive
  // listener would normally fire and re-enqueue the same row as a local
  // mutation, which produces a forever loop. The guard records the (table,
  // key) combo for a short TTL so the listener can recognise its own
  // remote-applied write and skip the outgoing push.
  // ---------------------------------------------------------------------------
  final Map<String, DateTime> _remoteOriginUntil = <String, DateTime>{};
  static const Duration _remoteOriginTtl = Duration(seconds: 5);

  /// Cached most recent successful sync timestamp. Pulled from prefs on
  /// activate so a sign-in/out round-trip keeps the value across cold
  /// boots. The settings row reads it via [lastSyncAt].
  DateTime? _lastSyncAt;

  final StreamController<SyncStatus> _statusCtrl =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _status = const SyncDisabled();
  SyncStatus get status => _status;
  Stream<SyncStatus> watchStatus() async* {
    yield _status;
    yield* _statusCtrl.stream;
  }

  /// Public introspection for the manage-devices screen.
  String? get deviceRowId => _deviceRowId;

  /// Most recent successful pull-or-push round-trip. `null` until the
  /// engine has activated and finished its first reconcile. Settings UI
  /// surfaces this as "Son güncelleme: 5 dakika önce".
  DateTime? get lastSyncAt => _lastSyncAt;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Bring the engine online for [userId]. Idempotent — re-calling for
  /// the same user is a no-op; calling for a different user implicitly
  /// deactivates the previous session first.
  Future<void> activate({required String userId}) async {
    if (_client == null) {
      _setStatus(const SyncDisabled());
      return;
    }
    if (_active && _userId == userId) return;
    if (_activating) return;
    _activating = true;
    try {
      if (_active) await deactivate();
      _userId = userId;
      _setStatus(const SyncBootstrapping());

      // Open the queue early so we can flush anything pending from a
      // previous session before we start subscribing.
      await _queue.ensureOpen();

      // Restore the persisted last-sync timestamp so the settings row
      // can render "5 dakika önce" immediately on activate, before the
      // first network round-trip lands.
      final persistedRaw = _storage.prefsBox.get(_kLastSyncAtKey);
      if (persistedRaw is String) {
        _lastSyncAt = DateTime.tryParse(persistedRaw);
      }

      _fingerprint = DeviceFingerprint.resolve(_storage);

      // 1) Pull-down. Failures here must not stop the engine — we go
      //    online with what we have and let Realtime fill in gaps.
      try {
        await _pull();
      } on Object catch (e, st) {
        _log('pull failed: $e\n$st');
        // Fall through — push + subscribe still useful.
      }

      // 2) Push-up: any local row newer than its remote counterpart.
      try {
        await _initialPush();
      } on Object catch (e) {
        _log('initial push failed: $e');
      }

      // 3) Subscribe to live changes.
      _subscribeRealtime();

      // 4) Hook local box mutations.
      _subscribeLocalChanges();

      // 5) Heartbeat + queue drain timers.
      _heartbeatTicker?.cancel();
      _heartbeatTicker = Timer.periodic(const Duration(minutes: 15), (_) {
        unawaited(_heartbeat());
      });
      _drainTicker?.cancel();
      _drainTicker = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_drainQueue());
      });

      // 6) Stamp our device row.
      await _heartbeat();

      _active = true;
      await _stampLastSync();
      _setStatus(SyncIdle(lastSyncAt: DateTime.now().toUtc()));
    } finally {
      _activating = false;
    }
  }

  /// Tear down subscriptions and timers. Leaves the queue intact so
  /// pending mutations survive a sign-out → sign-in round-trip.
  Future<void> deactivate({String? reason}) async {
    if (_client == null) return;
    _active = false;
    _userId = null;
    _deviceRowId = null;
    _heartbeatTicker?.cancel();
    _heartbeatTicker = null;
    _drainTicker?.cancel();
    _drainTicker = null;
    for (final t in _historyDebounces.values) {
      t.cancel();
    }
    _historyDebounces.clear();
    await _favBoxSub?.cancel();
    _favBoxSub = null;
    await _historyBoxSub?.cancel();
    _historyBoxSub = null;
    await _sourceBoxSub?.cancel();
    _sourceBoxSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _client?.removeChannel(ch);
      } on Object {
        // Best-effort.
      }
    }
    _setStatus(SyncDisabled(reason));
  }

  Future<void> dispose() async {
    await deactivate();
    await _statusCtrl.close();
  }

  /// Force a manual reconcile: pull-down → drain queue → push-up. Wired
  /// to the "Şimdi senkronize et" tile in settings so the user can verify
  /// the cross-device round-trip on demand instead of waiting for the
  /// 30-second drain ticker.
  ///
  /// Idempotent — safe to call while a tick is already running. Returns
  /// once the round-trip completes (or fails). Surfaces failures via
  /// [SyncStatus] rather than throwing so the UI never has to wrap the
  /// call in a try/catch.
  Future<void> syncNow() async {
    if (_client == null) return;
    if (!_active || _userId == null) return;
    _setStatus(const SyncPulling());
    try {
      await _pull();
      await _drainQueue();
      await _initialPush();
      await _stampLastSync();
      _setStatus(SyncIdle(lastSyncAt: _lastSyncAt ?? DateTime.now().toUtc()));
    } on Object catch (e) {
      _log('syncNow failed: $e');
      _setStatus(SyncFailed(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Public mutation entry points (called by hooks on top of services)
  // ---------------------------------------------------------------------------

  /// Push a favourite toggle to the queue. [added] determines whether
  /// the item is being added (`true`) or removed (`false`).
  Future<void> upsertFavorite(
    String itemId, {
    required bool added,
    HistoryKind kind = HistoryKind.live,
  }) async {
    final user = _userId;
    if (!_active || user == null) return;
    final now = DateTime.now().toUtc();
    final event = added
        ? FavoriteUpserted(
            userId: user,
            updatedAt: now,
            itemId: itemId,
            itemKind: FavoriteItemKind.fromHistoryKind(kind),
          )
        : FavoriteRemoved(userId: user, updatedAt: now, itemId: itemId);
    await _enqueueAndDrain(event);
  }

  /// Debounced history push. Coalesces rapid 5s ticks into one upsert
  /// per item per [debounce] window — the schema's `position_seconds`
  /// column intentionally only needs a low-frequency snapshot.
  void scheduleHistoryUpsert(
    HistoryEntry entry, {
    Duration debounce = const Duration(seconds: 10),
  }) {
    final user = _userId;
    if (!_active || user == null) return;
    _historyDebounces.remove(entry.itemId)?.cancel();
    _historyDebounces[entry.itemId] = Timer(debounce, () async {
      _historyDebounces.remove(entry.itemId);
      await _enqueueAndDrain(
        HistoryUpserted(
          userId: user,
          updatedAt: DateTime.now().toUtc(),
          entry: entry,
        ),
      );
    });
  }

  /// Push immediately (no debounce). Used for explicit `delete` flows.
  Future<void> upsertHistory(HistoryEntry entry) async {
    final user = _userId;
    if (!_active || user == null) return;
    await _enqueueAndDrain(
      HistoryUpserted(
        userId: user,
        updatedAt: DateTime.now().toUtc(),
        entry: entry,
      ),
    );
  }

  Future<void> upsertPlaylistSource(PlaylistSource src) async {
    final user = _userId;
    if (!_active || user == null) return;
    await _enqueueAndDrain(
      PlaylistSourceUpserted(
        userId: user,
        updatedAt: DateTime.now().toUtc(),
        clientId: src.id,
        name: src.name,
        kind: src.kind,
        addedAt: src.addedAt.toUtc(),
        lastSyncAt: src.lastSyncAt?.toUtc(),
      ),
    );
  }

  Future<void> removePlaylistSource(String clientId) async {
    final user = _userId;
    if (!_active || user == null) return;
    await _enqueueAndDrain(
      PlaylistSourceRemoved(
        userId: user,
        updatedAt: DateTime.now().toUtc(),
        clientId: clientId,
      ),
    );
  }

  /// List the user's `device_sessions` rows. The manage-devices screen
  /// renders this directly — bypassing the engine queue keeps the read
  /// path zero-side-effect even when offline (a thrown error is fine —
  /// the screen surfaces a retry).
  Future<List<DeviceSessionRow>> listDevices() async {
    if (_client == null) return const <DeviceSessionRow>[];
    final user = _userId;
    if (user == null) {
      throw const SyncError(
        'Not signed in.',
        retryable: false,
      );
    }
    final rows = await _client
        .from('device_sessions')
        .select()
        .eq('user_id', user)
        .order('last_seen_at', ascending: false);
    return rows
        .map((dynamic r) => DeviceSessionRow._fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Sign out a remote device. Implemented as a hard delete because
  /// the schema doesn't carry a soft-delete column — the user re-opens
  /// the app on that device, the heartbeat re-creates the row.
  Future<void> revokeDevice(String rowId) async {
    if (_client == null) return;
    final user = _userId;
    if (user == null) {
      throw const SyncError('Not signed in.', retryable: false);
    }
    try {
      await _client
          .from('device_sessions')
          .delete()
          .eq('user_id', user)
          .eq('id', rowId);
    } on Object catch (e) {
      throw SyncError('Cihaz kaldırılamadı: $e', cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Realtime
  // ---------------------------------------------------------------------------

  void _subscribeRealtime() {
    if (_client == null) return;
    final user = _userId;
    if (user == null) return;
    final filter = supa.PostgresChangeFilter(
      type: supa.PostgresChangeFilterType.eq,
      column: 'user_id',
      value: user,
    );
    final ch = _client!.channel('cloud-sync:$user')
      ..onPostgresChanges(
        event: supa.PostgresChangeEvent.all,
        schema: 'public',
        table: 'favorites',
        filter: filter,
        callback: _onFavoriteChange,
      )
      ..onPostgresChanges(
        event: supa.PostgresChangeEvent.all,
        schema: 'public',
        table: 'watch_history',
        filter: filter,
        callback: _onHistoryChange,
      )
      ..onPostgresChanges(
        event: supa.PostgresChangeEvent.all,
        schema: 'public',
        table: 'playlist_sources',
        filter: filter,
        callback: _onSourceChange,
      );
    ch.subscribe((status, [error]) {
      if (status == supa.RealtimeSubscribeStatus.subscribed) {
        _setStatus(SyncIdle(lastSyncAt: DateTime.now().toUtc()));
      } else if (status == supa.RealtimeSubscribeStatus.channelError ||
          status == supa.RealtimeSubscribeStatus.timedOut) {
        _setStatus(const SyncOffline());
      }
    });
    _channel = ch;
  }

  void _onFavoriteChange(supa.PostgresChangePayload payload) {
    final box = _storage.favoritesBox;
    final newRow = payload.newRecord;
    final oldRow = payload.oldRecord;
    switch (payload.eventType) {
      case supa.PostgresChangeEvent.delete:
        final id = oldRow['item_id'] as String?;
        if (id != null) {
          // Mark BEFORE the box mutation so the watch() listener sees the
          // flag when Hive synchronously fires the BoxEvent.
          _markRemoteOrigin('favorites', id);
          unawaited(box.delete(id));
        }
      case supa.PostgresChangeEvent.insert:
      case supa.PostgresChangeEvent.update:
        final id = newRow['item_id'] as String?;
        if (id != null && !box.containsKey(id)) {
          _markRemoteOrigin('favorites', id);
          unawaited(box.put(id, 1));
        }
        _rememberRemoteFavoriteAt(
          id ?? '',
          DateTime.tryParse(
                newRow['updated_at'] as String? ??
                    newRow['added_at'] as String? ??
                    '',
              ) ??
              DateTime.now().toUtc(),
        );
      case supa.PostgresChangeEvent.all:
        // Reserved by the SDK enum but never delivered for actual events.
        break;
    }
    unawaited(_stampLastSync());
  }

  void _onHistoryChange(supa.PostgresChangePayload payload) {
    final box = _storage.historyBox;
    final newRow = payload.newRecord;
    final oldRow = payload.oldRecord;
    switch (payload.eventType) {
      case supa.PostgresChangeEvent.delete:
        final id = oldRow['item_id'] as String?;
        if (id != null) {
          _markRemoteOrigin('watch_history', id);
          unawaited(box.delete(id));
        }
      case supa.PostgresChangeEvent.insert:
      case supa.PostgresChangeEvent.update:
        final entry = _historyFromRemote(newRow);
        if (entry == null) break;
        final remoteAt = entry.watchedAt;
        final local = _localHistory(entry.itemId);
        if (local == null || remoteAt.isAfter(local.watchedAt.toUtc())) {
          _markRemoteOrigin('watch_history', entry.itemId);
          unawaited(_storage.putHistory(entry));
        }
        _rememberRemoteHistoryAt(entry.itemId, remoteAt);
      case supa.PostgresChangeEvent.all:
        break;
    }
    unawaited(_stampLastSync());
  }

  void _onSourceChange(supa.PostgresChangePayload payload) {
    final newRow = payload.newRecord;
    final oldRow = payload.oldRecord;
    switch (payload.eventType) {
      case supa.PostgresChangeEvent.delete:
        final clientId = oldRow['client_id'] as String?;
        if (clientId != null) {
          _markRemoteOrigin('playlist_sources', clientId);
          unawaited(_storage.deleteSource(clientId));
        }
      case supa.PostgresChangeEvent.insert:
      case supa.PostgresChangeEvent.update:
        final clientId = newRow['client_id'] as String?;
        if (clientId == null) break;
        // Prefer the new updated_at column, fall back to last_sync_at /
        // added_at for rows written by builds running pre-migration.
        final remoteAt = DateTime.tryParse(
              newRow['updated_at'] as String? ?? '',
            ) ??
            DateTime.tryParse(newRow['last_sync_at'] as String? ?? '') ??
            DateTime.tryParse(newRow['added_at'] as String? ?? '') ??
            DateTime.now().toUtc();
        _markRemoteOrigin('playlist_sources', clientId);
        unawaited(_mergeRemoteSource(newRow, clientId));
        _rememberRemoteSourceAt(clientId, remoteAt);
      case supa.PostgresChangeEvent.all:
        break;
    }
    unawaited(_stampLastSync());
  }

  Future<void> _mergeRemoteSource(
    Map<String, dynamic> remote,
    String clientId,
  ) async {
    // The server NEVER stores URL/credentials, so a fresh remote row
    // can't materialise into a usable PlaylistSource on its own. We
    // only patch local rows that already exist (rename + last_sync_at)
    // — first-time syncs require the user to add the source on this
    // device with the credentials.
    final local = await _storage.getSource(clientId);
    if (local == null) return;
    final patched = local.copyWith(
      name: (remote['name'] as String?) ?? local.name,
      lastSyncAt: DateTime.tryParse(
            remote['last_sync_at'] as String? ?? '',
          ) ??
          local.lastSyncAt,
    );
    await _storage.putSource(patched);
  }

  // ---------------------------------------------------------------------------
  // Pull-down (initial sync)
  // ---------------------------------------------------------------------------

  Future<void> _pull() async {
    if (_client == null) return;
    final user = _userId;
    if (user == null) return;
    _setStatus(const SyncPulling());

    // Favorites ------------------------------------------------------
    final favs = await _client
        .from('favorites')
        .select()
        .eq('user_id', user)
        .order('added_at', ascending: false);
    final box = _storage.favoritesBox;
    final remoteFavIds = <String>{};
    for (final row in favs) {
      final id = row['item_id'] as String?;
      // Prefer updated_at (added in 20260428000001) over the
      // immutable added_at so re-toggle resolution stays correct.
      final updatedAt = DateTime.tryParse(
            row['updated_at'] as String? ??
                row['added_at'] as String? ??
                '',
          ) ??
          DateTime.now().toUtc();
      if (id == null) continue;
      remoteFavIds.add(id);
      if (!box.containsKey(id)) {
        _markRemoteOrigin('favorites', id);
        await box.put(id, 1);
      }
      _rememberRemoteFavoriteAt(id, updatedAt);
    }
    // We do NOT remove local favourites that aren't on the server —
    // the user might have just added them on this device pre-pull. The
    // initial push step propagates them up.

    // Watch history --------------------------------------------------
    final history = await _client
        .from('watch_history')
        .select()
        .eq('user_id', user)
        .order('watched_at', ascending: false);
    for (final row in history) {
      final entry = _historyFromRemote(row);
      if (entry == null) continue;
      final local = _localHistory(entry.itemId);
      if (local == null || entry.watchedAt.isAfter(local.watchedAt.toUtc())) {
        _markRemoteOrigin('watch_history', entry.itemId);
        await _storage.putHistory(entry);
      }
      _rememberRemoteHistoryAt(entry.itemId, entry.watchedAt);
    }

    // Playlist sources ----------------------------------------------
    final sources = await _client
        .from('playlist_sources')
        .select()
        .eq('user_id', user);
    for (final row in sources) {
      final clientId = row['client_id'] as String?;
      if (clientId == null) continue;
      _markRemoteOrigin('playlist_sources', clientId);
      await _mergeRemoteSource(row, clientId);
      final remoteAt = DateTime.tryParse(
            row['updated_at'] as String? ?? '',
          ) ??
          DateTime.tryParse(row['last_sync_at'] as String? ?? '') ??
          DateTime.tryParse(row['added_at'] as String? ?? '') ??
          DateTime.now().toUtc();
      _rememberRemoteSourceAt(clientId, remoteAt);
    }
  }

  // ---------------------------------------------------------------------------
  // Push-up (initial reconciliation)
  // ---------------------------------------------------------------------------

  Future<void> _initialPush() async {
    if (_client == null) return;
    final user = _userId;
    if (user == null) return;
    _setStatus(const SyncPushing());

    // Local favourites not in remote: enqueue an upsert.
    final favBox = _storage.favoritesBox;
    final remoteFavMap = _readRemoteFavMap();
    for (final key in favBox.keys.cast<String>()) {
      final remoteAt = remoteFavMap[key];
      if (remoteAt == null) {
        await _enqueueAndDrain(
          FavoriteUpserted(
            userId: user,
            updatedAt: DateTime.now().toUtc(),
            itemId: key,
            itemKind: FavoriteItemKind.live,
          ),
        );
      }
    }

    // Local history newer than remote.
    final localEntries = await _storage.listHistory(limit: 1000);
    final remoteHistoryMap = _readRemoteHistoryMap();
    for (final entry in localEntries) {
      final remoteAt = remoteHistoryMap[entry.itemId];
      if (remoteAt == null || entry.watchedAt.toUtc().isAfter(remoteAt)) {
        await _enqueueAndDrain(
          HistoryUpserted(
            userId: user,
            updatedAt: DateTime.now().toUtc(),
            entry: entry,
          ),
        );
      }
    }

    // Local sources newer than remote (or absent).
    final localSources = await _storage.listSources();
    final remoteSourceMap = _readRemoteSourceMap();
    for (final src in localSources) {
      final remoteAt = remoteSourceMap[src.id];
      final localAt = src.lastSyncAt?.toUtc() ?? src.addedAt.toUtc();
      if (remoteAt == null || localAt.isAfter(remoteAt)) {
        await _enqueueAndDrain(
          PlaylistSourceUpserted(
            userId: user,
            updatedAt: DateTime.now().toUtc(),
            clientId: src.id,
            name: src.name,
            kind: src.kind,
            addedAt: src.addedAt.toUtc(),
            lastSyncAt: src.lastSyncAt?.toUtc(),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Local box → outgoing event hooks
  // ---------------------------------------------------------------------------

  void _subscribeLocalChanges() {
    final user = _userId;
    if (user == null) return;

    // Favorites box. Enqueue on every key change. The Supabase row is
    // upserted by the same caller path (see toggleFavoriteSynced in
    // sync_hooks.dart), but we keep this listener for paths that bypass
    // the helper (settings, tests, …).
    _favBoxSub = _storage.favoritesBox.watch().listen((BoxEvent ev) {
      if (!_active || _userId == null) return;
      final id = ev.key as String?;
      if (id == null) return;
      // Loop guard: if this BoxEvent came from a remote-applied write,
      // _markRemoteOrigin was just stamped — short-circuit so we don't
      // ping-pong the same row back to the server.
      if (_isRemoteOrigin('favorites', id)) return;
      final added = !ev.deleted;
      unawaited(upsertFavorite(id, added: added));
    });

    // Watch history box. Decode each new value and schedule a debounced
    // push so a 5s player tick doesn't hammer the network.
    _historyBoxSub = _storage.historyBox.watch().listen((BoxEvent ev) {
      if (!_active || _userId == null) return;
      if (ev.deleted) {
        final id = ev.key as String?;
        if (id == null) return;
        if (_isRemoteOrigin('watch_history', id)) return;
        unawaited(
          _enqueueAndDrain(
            HistoryRemoved(
              userId: user,
              updatedAt: DateTime.now().toUtc(),
              itemId: id,
            ),
          ),
        );
        return;
      }
      final raw = ev.value;
      if (raw is! String) return;
      try {
        final entry = HistoryEntry.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (_isRemoteOrigin('watch_history', entry.itemId)) return;
        scheduleHistoryUpsert(entry);
      } on Object {
        // Skip corrupt history rows.
      }
    });

    // Playlist sources box. The sources box stores Box<String>; we
    // decode and enqueue an upsert on changes.
    const sourcesBoxName = AwatvStorage.boxSources;
    if (Hive.isBoxOpen(sourcesBoxName)) {
      _sourceBoxSub =
          Hive.box<String>(sourcesBoxName).watch().listen((BoxEvent ev) {
        if (!_active || _userId == null) return;
        final id = ev.key as String?;
        if (id == null) return;
        if (_isRemoteOrigin('playlist_sources', id)) return;
        if (ev.deleted) {
          unawaited(removePlaylistSource(id));
          return;
        }
        final raw = ev.value;
        if (raw is! String) return;
        try {
          final src = PlaylistSource.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          unawaited(upsertPlaylistSource(src));
        } on Object {
          // Skip corrupt source row.
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Heartbeat — `device_sessions` upsert
  // ---------------------------------------------------------------------------

  Future<void> _heartbeat() async {
    if (_client == null) return;
    final user = _userId;
    final fp = _fingerprint;
    if (user == null || fp == null) return;
    try {
      final row = await _client
          .from('device_sessions')
          .upsert(<String, dynamic>{
            'user_id': user,
            'device_id': fp.deviceId,
            'device_kind': fp.kind.wire,
            'platform': fp.platform,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
            if (fp.userAgent != null) 'user_agent': fp.userAgent,
          }, onConflict: 'user_id,device_id')
          .select()
          .maybeSingle();
      _deviceRowId = row?['id'] as String?;
    } on Object catch (e) {
      _log('heartbeat failed: $e');
      _setStatus(const SyncOffline());
    }
  }

  // ---------------------------------------------------------------------------
  // Queue draining
  // ---------------------------------------------------------------------------

  Future<void> _enqueueAndDrain(SyncEvent event) async {
    await _queue.enqueue(event);
    await _drainQueue();
  }

  Future<void> _drainQueue() async {
    if (!_active) return;
    _setStatus(const SyncPushing());
    try {
      await _queue.drain(_pushOne);
      await _stampLastSync();
      _setStatus(SyncIdle(lastSyncAt: DateTime.now().toUtc()));
    } on Object catch (e) {
      // Drain failures already bumped the queue's backoff; surface to
      // status so the settings row reflects connectivity issues.
      _setStatus(const SyncOffline());
      _log('drain failed: $e');
    }
  }

  Future<void> _pushOne(SyncEvent event) async {
    if (_client == null) return;
    final user = _userId;
    if (user == null || event.userId != user) {
      // Queue carries an event for a different user — drop.
      throw SyncQueue.nonRetryable(event, 'user mismatch');
    }
    try {
      // Every upsert below stamps `updated_at` explicitly so the server's
      // last-writer-wins rule sees our exact mutation time, not the
      // trigger's now() (which would be slightly later than the local
      // clock and thus drift across devices).
      final mutationAt = event.updatedAt.toUtc().toIso8601String();
      switch (event) {
        case FavoriteUpserted():
          await _client!.from('favorites').upsert(<String, dynamic>{
            'user_id': user,
            'item_id': event.itemId,
            'item_kind': event.itemKind.wire,
            'added_at': event.updatedAt.toUtc().toIso8601String(),
            'updated_at': mutationAt,
          }, onConflict: 'user_id,item_id');
          _rememberRemoteFavoriteAt(event.itemId, event.updatedAt.toUtc());
        case FavoriteRemoved():
          await _client
              .from('favorites')
              .delete()
              .eq('user_id', user)
              .eq('item_id', event.itemId);
          _forgetRemoteFavorite(event.itemId);
        case HistoryUpserted():
          await _client!.from('watch_history').upsert(<String, dynamic>{
            'user_id': user,
            'item_id': event.entry.itemId,
            'item_kind': _historyKindWire(event.entry.kind),
            'position_seconds': event.entry.position.inSeconds,
            'total_seconds': event.entry.total.inSeconds,
            'watched_at': event.entry.watchedAt.toUtc().toIso8601String(),
            'updated_at': mutationAt,
          }, onConflict: 'user_id,item_id');
          _rememberRemoteHistoryAt(
            event.entry.itemId,
            event.entry.watchedAt.toUtc(),
          );
        case HistoryRemoved():
          await _client
              .from('watch_history')
              .delete()
              .eq('user_id', user)
              .eq('item_id', event.itemId);
          _forgetRemoteHistory(event.itemId);
        case PlaylistSourceUpserted():
          await _client!.from('playlist_sources').upsert(<String, dynamic>{
            'user_id': user,
            'name': event.name,
            'kind': event.kind.name,
            'client_id': event.clientId,
            'added_at': event.addedAt.toUtc().toIso8601String(),
            'updated_at': mutationAt,
            if (event.lastSyncAt != null)
              'last_sync_at': event.lastSyncAt!.toUtc().toIso8601String(),
          }, onConflict: 'user_id,client_id');
          _rememberRemoteSourceAt(
            event.clientId,
            event.lastSyncAt?.toUtc() ?? event.addedAt.toUtc(),
          );
        case PlaylistSourceRemoved():
          await _client
              .from('playlist_sources')
              .delete()
              .eq('user_id', user)
              .eq('client_id', event.clientId);
          _forgetRemoteSource(event.clientId);
        case DeviceSessionUpserted():
          await _client!.from('device_sessions').upsert(<String, dynamic>{
            'user_id': user,
            'device_id': event.deviceId,
            'device_kind': event.deviceKind.wire,
            'platform': event.platform,
            'last_seen_at': event.updatedAt.toUtc().toIso8601String(),
            if (event.userAgent != null) 'user_agent': event.userAgent,
          }, onConflict: 'user_id,device_id');
        case DeviceSessionRemoved():
          await _client
              .from('device_sessions')
              .delete()
              .eq('user_id', user)
              .eq('id', event.rowId);
      }
    } on supa.PostgrestException catch (e) {
      // 401/403 → permanent (user lost access). 4xx generally permanent.
      // 5xx → transient.
      final code = int.tryParse(e.code ?? '');
      final retryable = code == null || code >= 500;
      if (!retryable) {
        throw SyncQueue.nonRetryable(event, e);
      }
      throw SyncError(
        e.message,
        cause: e,
        statusCode: code,
      );
    } on Object catch (e) {
      // Network / unknown errors are retryable.
      throw SyncError('Push failed: $e', cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  HistoryEntry? _historyFromRemote(Map<String, dynamic> row) {
    try {
      return HistoryEntry(
        itemId: row['item_id'] as String,
        kind: _historyKindFromWire(row['item_kind'] as String?),
        position: Duration(
          seconds: (row['position_seconds'] as num? ?? 0).toInt(),
        ),
        total: Duration(
          seconds: (row['total_seconds'] as num? ?? 0).toInt(),
        ),
        watchedAt: DateTime.tryParse(row['watched_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );
    } on Object {
      return null;
    }
  }

  HistoryEntry? _localHistory(String itemId) {
    final raw = _storage.historyBox.get(itemId);
    if (raw == null) return null;
    try {
      return HistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  String _historyKindWire(HistoryKind k) => switch (k) {
        HistoryKind.live => 'live',
        HistoryKind.vod => 'vod',
        HistoryKind.series => 'series',
      };

  HistoryKind _historyKindFromWire(String? raw) => switch (raw) {
        'vod' => HistoryKind.vod,
        'series' => HistoryKind.series,
        _ => HistoryKind.live,
      };

  Map<String, DateTime> _readRemoteFavMap() => _decodeMap(_kRemoteFavStateKey);
  Map<String, DateTime> _readRemoteHistoryMap() =>
      _decodeMap(_kRemoteHistoryStateKey);
  Map<String, DateTime> _readRemoteSourceMap() =>
      _decodeMap(_kRemoteSourceStateKey);

  Map<String, DateTime> _decodeMap(String key) {
    final raw = _storage.prefsBox.get(key);
    if (raw is! String || raw.isEmpty) return <String, DateTime>{};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return <String, DateTime>{
        for (final e in json.entries)
          if (e.value is String) e.key: DateTime.tryParse(e.value as String) ??
              DateTime.fromMillisecondsSinceEpoch(0),
      };
    } on Object {
      return <String, DateTime>{};
    }
  }

  void _writeMap(String key, Map<String, DateTime> map) {
    final json = <String, String>{
      for (final e in map.entries) e.key: e.value.toUtc().toIso8601String(),
    };
    unawaited(_storage.prefsBox.put(key, jsonEncode(json)));
  }

  void _rememberRemoteFavoriteAt(String id, DateTime at) {
    final m = _readRemoteFavMap()..[id] = at;
    _writeMap(_kRemoteFavStateKey, m);
  }

  void _forgetRemoteFavorite(String id) {
    final m = _readRemoteFavMap()..remove(id);
    _writeMap(_kRemoteFavStateKey, m);
  }

  void _rememberRemoteHistoryAt(String id, DateTime at) {
    final m = _readRemoteHistoryMap()..[id] = at;
    _writeMap(_kRemoteHistoryStateKey, m);
  }

  void _forgetRemoteHistory(String id) {
    final m = _readRemoteHistoryMap()..remove(id);
    _writeMap(_kRemoteHistoryStateKey, m);
  }

  void _rememberRemoteSourceAt(String id, DateTime at) {
    final m = _readRemoteSourceMap()..[id] = at;
    _writeMap(_kRemoteSourceStateKey, m);
  }

  void _forgetRemoteSource(String id) {
    final m = _readRemoteSourceMap()..remove(id);
    _writeMap(_kRemoteSourceStateKey, m);
  }

  Future<void> _stampLastSync() async {
    final now = DateTime.now().toUtc();
    _lastSyncAt = now;
    await _storage.prefsBox.put(_kLastSyncAtKey, now.toIso8601String());
  }

  void _setStatus(SyncStatus next) {
    _status = next;
    if (!_statusCtrl.isClosed) _statusCtrl.add(next);
  }

  // ---------------------------------------------------------------------------
  // Remote-origin guard
  // ---------------------------------------------------------------------------

  /// Mark a `(table, key)` combo as "just applied from remote" for the
  /// next [_remoteOriginTtl] window. The local-box listener uses
  /// [_isRemoteOrigin] before enqueuing an outgoing event, breaking the
  /// realtime → Hive → listener → push loop.
  void _markRemoteOrigin(String table, String key) {
    final composite = '$table:$key';
    _remoteOriginUntil[composite] =
        DateTime.now().toUtc().add(_remoteOriginTtl);
    // Lazy GC: every mark also evicts entries that have aged past the TTL
    // so the map can't grow unbounded if Realtime delivers a flood without
    // any local mutations to flush it.
    _gcRemoteOrigin();
  }

  /// `true` if `(table, key)` was marked as remote-origin within the TTL.
  /// Side-effect: a positive hit also clears the entry so a *second* local
  /// write to the same key (genuine new mutation) is treated as local.
  bool _isRemoteOrigin(String table, String key) {
    final composite = '$table:$key';
    final until = _remoteOriginUntil[composite];
    if (until == null) return false;
    if (DateTime.now().toUtc().isAfter(until)) {
      _remoteOriginUntil.remove(composite);
      return false;
    }
    _remoteOriginUntil.remove(composite);
    return true;
  }

  void _gcRemoteOrigin() {
    final now = DateTime.now().toUtc();
    _remoteOriginUntil.removeWhere((_, until) => now.isAfter(until));
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[CloudSyncEngine] $msg');
  }
}

/// Plain DTO for the manage-devices screen. Shape matches `device_sessions`
/// minus the user_id (already known by virtue of being signed in).
class DeviceSessionRow {
  const DeviceSessionRow({
    required this.id,
    required this.deviceId,
    required this.kind,
    required this.platform,
    required this.lastSeenAt,
    this.userAgent,
  });

  factory DeviceSessionRow._fromMap(Map<String, dynamic> row) {
    return DeviceSessionRow(
      id: row['id'] as String,
      deviceId: row['device_id'] as String,
      kind: DeviceKind.values.firstWhere(
        (k) => k.wire == row['device_kind'],
        orElse: () => DeviceKind.phone,
      ),
      platform: row['platform'] as String? ?? 'unknown',
      lastSeenAt:
          DateTime.tryParse(row['last_seen_at'] as String? ?? '') ??
              DateTime.now().toUtc(),
      userAgent: row['user_agent'] as String?,
    );
  }

  final String id;
  final String deviceId;
  final DeviceKind kind;
  final String platform;
  final DateTime lastSeenAt;
  final String? userAgent;
}
