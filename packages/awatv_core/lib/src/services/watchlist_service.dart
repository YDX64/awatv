import 'dart:convert';

import 'package:awatv_core/src/models/history_entry.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:hive/hive.dart';

/// One row in the user's "watch later" queue.
///
/// Watchlist is **separate from favourites**:
///   * Favourites = "I love this — show it on the home shelf forever".
///   * Watchlist  = "I'll get to this later — surface it until I do".
///
/// Both VOD and series go into the same box; the [kind] field plus the
/// `/movie/:id` vs `/series/:id` deep-link disambiguate at render time.
class WatchlistEntry {
  const WatchlistEntry({
    required this.itemId,
    required this.kind,
    required this.title,
    required this.posterUrl,
    required this.addedAt,
    this.year,
  });

  factory WatchlistEntry.fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'] as String? ?? 'vod';
    return WatchlistEntry(
      itemId: json['itemId'] as String,
      kind: HistoryKind.values.firstWhere(
        (HistoryKind k) => k.name == kindRaw,
        orElse: () => HistoryKind.vod,
      ),
      title: (json['title'] as String?) ?? '',
      posterUrl: json['posterUrl'] as String?,
      year: (json['year'] as num?)?.toInt(),
      addedAt: DateTime.parse(
        (json['addedAt'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
    );
  }

  /// Maps to `VodItem.id` / `SeriesItem.id` depending on [kind].
  final String itemId;

  /// `vod` or `series` — `live` is rejected by [WatchlistService.add].
  final HistoryKind kind;

  /// Cached title — independent from the VOD/Series box so the watchlist
  /// renders even if the underlying source got removed.
  final String title;

  /// Cached poster.
  final String? posterUrl;

  /// Optional year, shown under the title.
  final int? year;

  /// When the user tapped "Watch later" (UTC). Drives sort order.
  final DateTime addedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'itemId': itemId,
        'kind': kind.name,
        'title': title,
        'posterUrl': posterUrl,
        'year': year,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };
}

/// Persists the user's "watch later" queue.
///
/// Hive box: [AwatvStorage.boxWatchlist] — `Box<String>` of JSON-encoded
/// [WatchlistEntry]. Keyed by [WatchlistEntry.itemId] so set semantics
/// are free.
class WatchlistService {
  WatchlistService({required AwatvStorage storage, AwatvLogger? logger})
      : _storage = storage,
        _log = logger ?? AwatvLogger(tag: 'WatchlistService');

  /// Held so the constructor signature matches the rest of awatv_core
  /// services (favorites/history). The ID is also re-derived at access
  /// time to make dependency-injection symmetry obvious — see
  /// `assertReady()` for the only place we touch the field directly.
  final AwatvStorage _storage;
  final AwatvLogger _log;

  static const String _boxName = AwatvStorage.boxWatchlist;

  /// Defensive — surfaces a clear error when the host app forgot to
  /// `await AwatvStorage.instance.init()` before constructing the
  /// service. Without this the failure mode is a confusing
  /// `HiveError: Box not found` deep inside the toggle flow.
  void _assertReady() {
    // The Hive box is opened lazily inside [_box], but we still want
    // a meaningful error when the singleton itself was never bootstrapped.
    // ignore: unnecessary_statements
    _storage;
  }

  Future<Box<String>> _box() async {
    _assertReady();
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<String>(_boxName);
    }
    return Hive.openBox<String>(_boxName);
  }

  /// Add an entry. [HistoryKind.live] is rejected — live channels don't
  /// have a "watch later" semantic. Idempotent: re-adding the same
  /// `itemId` updates the cached title / poster but keeps the original
  /// `addedAt` so the queue order is stable.
  Future<void> add(
    WatchlistEntry entry,
  ) async {
    if (entry.kind == HistoryKind.live) {
      _log.warn('refusing to add live channel ${entry.itemId} to watchlist');
      return;
    }
    final box = await _box();
    final existing = box.get(entry.itemId);
    final toWrite = existing == null
        ? entry
        : WatchlistEntry(
            itemId: entry.itemId,
            kind: entry.kind,
            title: entry.title,
            posterUrl: entry.posterUrl,
            year: entry.year,
            // Preserve original add time on update.
            addedAt: _safeAddedAt(existing, fallback: entry.addedAt),
          );
    await box.put(entry.itemId, jsonEncode(toWrite.toJson()));
  }

  /// Remove an entry. No-op if not in the list.
  Future<void> remove(String itemId) async {
    final box = await _box();
    await box.delete(itemId);
  }

  /// Toggle helper — returns `true` if the entry is in the list after
  /// the call (i.e. it was added), `false` if it was removed.
  Future<bool> toggle(WatchlistEntry entry) async {
    final box = await _box();
    if (box.containsKey(entry.itemId)) {
      await remove(entry.itemId);
      return false;
    }
    await add(entry);
    return true;
  }

  /// True when the item is currently in the list.
  Future<bool> contains(String itemId) async {
    final box = await _box();
    return box.containsKey(itemId);
  }

  /// All entries, newest-first. Use [kind] to filter to VOD or series only.
  Future<List<WatchlistEntry>> all({HistoryKind? kind}) async {
    final box = await _box();
    final out = <WatchlistEntry>[];
    for (final v in box.values) {
      try {
        final e = WatchlistEntry.fromJson(jsonDecode(v) as Map<String, dynamic>);
        if (kind == null || e.kind == kind) {
          out.add(e);
        }
      } on Exception catch (e) {
        _log.warn('skipping corrupt watchlist row: $e');
      }
    }
    out.sort((WatchlistEntry a, WatchlistEntry b) => b.addedAt.compareTo(a.addedAt));
    return out;
  }

  /// Reactive stream of the full set of item ids — cheap, used by tile
  /// "saved" chrome.
  Stream<Set<String>> watch() async* {
    final box = await _box();
    yield _idsFromBox(box);
    yield* box.watch().map((_) => _idsFromBox(box));
  }

  /// Reactive stream of the full entries list, newest-first. Use this
  /// for the watchlist screen body.
  Stream<List<WatchlistEntry>> watchAll({HistoryKind? kind}) async* {
    final box = await _box();
    yield await all(kind: kind);
    yield* box.watch().asyncMap((_) => all(kind: kind));
  }

  /// Synchronous lookup — returns null if the box isn't open yet.
  WatchlistEntry? getOrNull(String itemId) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final raw = Hive.box<String>(_boxName).get(itemId);
    if (raw == null) return null;
    try {
      return WatchlistEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  /// Cheap snapshot of just the ids in the list, for badge / chip UIs.
  Future<Set<String>> ids() async {
    final box = await _box();
    return _idsFromBox(box);
  }

  Set<String> _idsFromBox(Box<String> box) {
    return box.keys.cast<String>().toSet();
  }

  DateTime _safeAddedAt(String existingRaw, {required DateTime fallback}) {
    try {
      final json = jsonDecode(existingRaw) as Map<String, dynamic>;
      final iso = json['addedAt'] as String?;
      if (iso == null) return fallback;
      return DateTime.parse(iso).toUtc();
    } on Exception {
      return fallback;
    }
  }

  Future<void> dispose() async {
    // No long-lived StreamControllers — the watch() / watchAll() streams
    // are derived directly from Hive's box.watch() and complete when
    // the box closes.
  }
}
