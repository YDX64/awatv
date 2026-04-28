import 'dart:async';
import 'dart:convert';

import 'package:awatv_core/awatv_core.dart';
import 'package:hive/hive.dart';

/// Per-profile favourites + history persistence.
///
/// AGENT.md forbids touching `packages/awatv_core/`, so instead of adding
/// a `profileId` arg to [FavoritesService] / [HistoryService] we open a
/// distinct Hive box per profile right here in the mobile layer:
///
///   * `favorites:profile:<id>`   `Box<int>` — set semantics, value is
///     always 1, key is the channel id.
///   * `history:profile:<id>`     `Box<String>` — JSON-serialised
///     [HistoryEntry] records keyed by item id.
///
/// The default profile keeps using the legacy `favorites` / `history`
/// boxes opened by `AwatvStorage.init` so existing data is not orphaned
/// when the profiles feature ships — see [migrateLegacyDataIntoProfile].
class ProfileScopedStorage {
  const ProfileScopedStorage._();

  static const String _legacyFavoritesBox = AwatvStorage.boxFavorites;
  static const String _legacyHistoryBox = AwatvStorage.boxHistory;
  static const String _defaultProfileSentinelId = '__default__';

  static String favoritesBoxName(String profileId) =>
      profileId == _defaultProfileSentinelId
          ? _legacyFavoritesBox
          : 'favorites:profile:$profileId';

  static String historyBoxName(String profileId) =>
      profileId == _defaultProfileSentinelId
          ? _legacyHistoryBox
          : 'history:profile:$profileId';

  /// Open the per-profile boxes (idempotent). Called by the active
  /// profile switcher right before favourites/history providers are
  /// invalidated — guarantees the boxes exist before the new providers
  /// query Hive.
  static Future<void> openBoxesFor(String profileId) async {
    if (profileId == _defaultProfileSentinelId) {
      // Legacy boxes already opened by AwatvStorage.init.
      return;
    }
    final favName = favoritesBoxName(profileId);
    if (!Hive.isBoxOpen(favName)) {
      await Hive.openBox<int>(favName);
    }
    final histName = historyBoxName(profileId);
    if (!Hive.isBoxOpen(histName)) {
      await Hive.openBox<String>(histName);
    }
  }

  /// Sentinel id treated as "use the legacy un-scoped boxes". The
  /// default profile created on first boot uses this id so users
  /// upgrading from a pre-profiles build keep their data.
  static String get defaultProfileId => _defaultProfileSentinelId;

  /// Erase the profile's per-profile boxes from disk. Called by
  /// [ProfileController.deleteProfile] to keep storage tidy. The
  /// default profile's legacy boxes are never deleted — they belong to
  /// the device, not a profile.
  static Future<void> deleteBoxesFor(String profileId) async {
    if (profileId == _defaultProfileSentinelId) return;
    for (final name in <String>[
      favoritesBoxName(profileId),
      historyBoxName(profileId),
    ]) {
      try {
        if (Hive.isBoxOpen(name)) {
          await Hive.box<dynamic>(name).close();
        }
        await Hive.deleteBoxFromDisk(name);
      } on Object {
        // Best-effort cleanup; corrupt boxes simply remain on disk.
      }
    }
  }
}

/// Profile-scoped favourites — same semantics as [FavoritesService] but
/// reads/writes the box for [profileId]. Created fresh by Riverpod every
/// time the active profile changes; the previous instance disposes its
/// stream controller via [dispose].
class ProfileFavoritesService {
  ProfileFavoritesService({required this.profileId});

  final String profileId;
  final StreamController<Set<String>> _ctrl =
      StreamController<Set<String>>.broadcast();
  StreamSubscription<BoxEvent>? _hiveSub;

  Box<int> get _box {
    final name = ProfileScopedStorage.favoritesBoxName(profileId);
    if (!Hive.isBoxOpen(name)) {
      throw StateError(
        'Favorites box for profile "$profileId" not opened. Did you '
        'forget to call ProfileScopedStorage.openBoxesFor($profileId)?',
      );
    }
    return Hive.box<int>(name);
  }

  Future<void> toggle(String channelId) async {
    final box = _box;
    if (box.containsKey(channelId)) {
      await box.delete(channelId);
    } else {
      await box.put(channelId, 1);
    }
  }

  Future<bool> isFavorite(String channelId) async {
    return _box.containsKey(channelId);
  }

  Future<Set<String>> all() async => _currentSet();

  Stream<Set<String>> watch() async* {
    yield _currentSet();
    yield* _box.watch().map((_) => _currentSet());
  }

  Set<String> _currentSet() => _box.keys.cast<String>().toSet();

  Future<void> dispose() async {
    await _hiveSub?.cancel();
    await _ctrl.close();
  }
}

/// Profile-scoped history. Mirrors [HistoryService]'s public surface.
class ProfileHistoryService {
  ProfileHistoryService({required this.profileId});

  final String profileId;

  Box<String> get _box {
    final name = ProfileScopedStorage.historyBoxName(profileId);
    if (!Hive.isBoxOpen(name)) {
      throw StateError(
        'History box for profile "$profileId" not opened. Did you '
        'forget to call ProfileScopedStorage.openBoxesFor($profileId)?',
      );
    }
    return Hive.box<String>(name);
  }

  Future<void> markPosition(
    String itemId,
    Duration position,
    Duration total, {
    HistoryKind kind = HistoryKind.live,
  }) async {
    final entry = HistoryEntry(
      itemId: itemId,
      kind: kind,
      position: position,
      total: total,
      watchedAt: DateTime.now().toUtc(),
    );
    await _box.put(entry.itemId, jsonEncode(entry.toJson()));
  }

  Future<List<HistoryEntry>> recent({int limit = 50}) async {
    final out = <HistoryEntry>[];
    for (final v in _box.values) {
      try {
        out.add(HistoryEntry.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Object {
        // Skip corrupt rows.
      }
    }
    out.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    if (out.length > limit) return out.sublist(0, limit);
    return out;
  }

  Future<Duration?> resumeFor(String itemId) async {
    final raw = _box.get(itemId);
    if (raw == null) return null;
    try {
      final entry =
          HistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (entry.total.inSeconds == 0) return entry.position;
      if (entry.position.inSeconds < 30) return null;
      if (entry.total.inSeconds - entry.position.inSeconds < 30) return null;
      return entry.position;
    } on Object {
      return null;
    }
  }
}
