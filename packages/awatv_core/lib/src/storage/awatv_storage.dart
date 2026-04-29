import 'dart:convert';

import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/download_task.dart';
import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/models/history_entry.dart';
import 'package:awatv_core/src/models/playlist_source.dart';
import 'package:awatv_core/src/models/recording_task.dart';
import 'package:awatv_core/src/models/series_item.dart';
import 'package:awatv_core/src/models/vod_item.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:hive/hive.dart';

/// Hive-backed persistence layer.
///
/// All complex objects are serialized as JSON strings — we don't ship
/// Hive `TypeAdapter`s for two reasons:
/// 1. Models change shape frequently and freezed-generated `fromJson`
///    handles missing/extra fields gracefully.
/// 2. Inspecting raw boxes during dev is much easier with JSON.
class AwatvStorage {
  AwatvStorage({AwatvLogger? logger})
      : _log = logger ?? AwatvLogger(tag: 'AwatvStorage');

  /// Singleton accessor used by Riverpod providers / app boot.
  /// First access creates a default-configured instance; explicit
  /// `AwatvStorage(...)` constructors stay supported for tests.
  static AwatvStorage? _singleton;
  static AwatvStorage get instance => _singleton ??= AwatvStorage();

  final AwatvLogger _log;
  bool _initialized = false;

  // Box names ---------------------------------------------------------------
  static const String boxSources = 'sources';
  static const String boxEpg = 'epg';
  static const String boxMetadata = 'metadata';
  static const String boxFavorites = 'favorites';
  static const String boxHistory = 'history';
  static const String boxPrefs = 'prefs';
  static const String boxRecordings = 'recordings';
  static const String boxDownloads = 'downloads';
  static const String boxReminders = 'reminders';
  static const String boxWatchlist = 'watchlist';

  static String channelsBoxName(String sourceId) => 'channels:$sourceId';
  static String vodBoxName(String sourceId) => 'vod:$sourceId';
  static String seriesBoxName(String sourceId) => 'series:$sourceId';

  /// Initialize Hive. [subDir] should be an absolute path — apps in Flutter
  /// pass `path_provider`'s `getApplicationDocumentsDirectory().path`.
  /// Pure-Dart users (tests) can pass a tmp dir.
  Future<void> init({String? subDir}) async {
    if (_initialized) return;
    try {
      if (subDir != null) {
        Hive.init(subDir);
      }
      // Open the always-on boxes lazily on first use; keep init cheap.
      await Hive.openBox<String>(boxSources);
      await Hive.openBox<String>(boxEpg);
      await Hive.openBox<String>(boxMetadata);
      await Hive.openBox<int>(boxFavorites);
      await Hive.openBox<String>(boxHistory);
      await Hive.openBox<dynamic>(boxPrefs);
      await Hive.openBox<String>(boxRecordings);
      await Hive.openBox<String>(boxDownloads);
      await Hive.openBox<String>(boxReminders);
      await Hive.openBox<String>(boxWatchlist);
      _initialized = true;
      _log.info('storage initialised at ${subDir ?? "<default>"}');
    } on Exception catch (e) {
      throw StorageException('Hive init failed: $e');
    }
  }

  Future<void> close() async {
    await Hive.close();
    _initialized = false;
  }

  void _assertInit() {
    if (!_initialized) {
      throw const StorageException('AwatvStorage.init() not called');
    }
  }

  // Sources -----------------------------------------------------------------
  Future<void> putSource(PlaylistSource src) async {
    _assertInit();
    final box = Hive.box<String>(boxSources);
    await box.put(src.id, jsonEncode(src.toJson()));
  }

  Future<void> deleteSource(String sourceId) async {
    _assertInit();
    final box = Hive.box<String>(boxSources);
    await box.delete(sourceId);
    await _safeDeleteBox(channelsBoxName(sourceId));
    await _safeDeleteBox(vodBoxName(sourceId));
    await _safeDeleteBox(seriesBoxName(sourceId));
  }

  Future<List<PlaylistSource>> listSources() async {
    _assertInit();
    final box = Hive.box<String>(boxSources);
    final out = <PlaylistSource>[];
    for (final v in box.values) {
      try {
        out.add(
          PlaylistSource.fromJson(
            jsonDecode(v) as Map<String, dynamic>,
          ),
        );
      } on Exception catch (e) {
        _log.warn('skipping corrupt source record: $e');
      }
    }
    out.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return out;
  }

  Future<PlaylistSource?> getSource(String sourceId) async {
    _assertInit();
    final raw = Hive.box<String>(boxSources).get(sourceId);
    if (raw == null) return null;
    try {
      return PlaylistSource.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception catch (e) {
      _log.warn('corrupt source record $sourceId: $e');
      return null;
    }
  }

  // Channels ----------------------------------------------------------------
  Future<void> putChannels(String sourceId, List<Channel> channels) async {
    _assertInit();
    final box = await _openIfNeeded<String>(channelsBoxName(sourceId));
    await box.clear();
    final entries = <String, String>{
      for (final ch in channels) ch.id: jsonEncode(ch.toJson()),
    };
    await box.putAll(entries);
  }

  Future<List<Channel>> listChannels(String sourceId) async {
    _assertInit();
    final box = await _openIfNeeded<String>(channelsBoxName(sourceId));
    final out = <Channel>[];
    for (final v in box.values) {
      try {
        out.add(Channel.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception {
        // Skip corrupt channel.
      }
    }
    return out;
  }

  Stream<List<Channel>> watchChannels(String sourceId) async* {
    _assertInit();
    final box = await _openIfNeeded<String>(channelsBoxName(sourceId));
    yield await listChannels(sourceId);
    yield* box.watch().asyncMap((_) => listChannels(sourceId));
  }

  // VOD ---------------------------------------------------------------------
  Future<void> putVod(String sourceId, List<VodItem> items) async {
    _assertInit();
    final box = await _openIfNeeded<String>(vodBoxName(sourceId));
    await box.clear();
    await box.putAll({
      for (final v in items) v.id: jsonEncode(v.toJson()),
    });
  }

  Future<List<VodItem>> listVod(String sourceId) async {
    _assertInit();
    final box = await _openIfNeeded<String>(vodBoxName(sourceId));
    final out = <VodItem>[];
    for (final v in box.values) {
      try {
        out.add(VodItem.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception {
        // Skip.
      }
    }
    return out;
  }

  // Series ------------------------------------------------------------------
  Future<void> putSeries(String sourceId, List<SeriesItem> items) async {
    _assertInit();
    final box = await _openIfNeeded<String>(seriesBoxName(sourceId));
    await box.clear();
    await box.putAll({
      for (final v in items) v.id: jsonEncode(v.toJson()),
    });
  }

  Future<List<SeriesItem>> listSeries(String sourceId) async {
    _assertInit();
    final box = await _openIfNeeded<String>(seriesBoxName(sourceId));
    final out = <SeriesItem>[];
    for (final v in box.values) {
      try {
        out.add(SeriesItem.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception {
        // Skip.
      }
    }
    return out;
  }

  // EPG ---------------------------------------------------------------------
  Future<void> putEpg(String tvgId, List<EpgProgramme> programmes) async {
    _assertInit();
    final box = Hive.box<String>(boxEpg);
    await box.put(
      tvgId,
      jsonEncode(programmes.map((p) => p.toJson()).toList()),
    );
  }

  Future<List<EpgProgramme>> getEpg(String tvgId) async {
    _assertInit();
    final raw = Hive.box<String>(boxEpg).get(tvgId);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => EpgProgramme.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception catch (e) {
      _log.warn('corrupt EPG cache for $tvgId: $e');
      return const [];
    }
  }

  // Metadata ----------------------------------------------------------------
  Future<void> putMetadataJson(String key, Map<String, dynamic> json) async {
    _assertInit();
    final wrapper = {
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'value': json,
    };
    await Hive.box<String>(boxMetadata).put(key, jsonEncode(wrapper));
  }

  Future<Map<String, dynamic>?> getMetadataJson(
    String key, {
    Duration ttl = const Duration(days: 30),
  }) async {
    _assertInit();
    final raw = Hive.box<String>(boxMetadata).get(key);
    if (raw == null) return null;
    try {
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(wrapper['savedAt'] as String);
      if (DateTime.now().toUtc().difference(savedAt) > ttl) return null;
      return (wrapper['value'] as Map).cast<String, dynamic>();
    } on Exception {
      return null;
    }
  }

  // Favorites ---------------------------------------------------------------
  Box<int> get favoritesBox {
    _assertInit();
    return Hive.box<int>(boxFavorites);
  }

  // History -----------------------------------------------------------------
  Future<void> putHistory(HistoryEntry entry) async {
    _assertInit();
    await Hive.box<String>(boxHistory)
        .put(entry.itemId, jsonEncode(entry.toJson()));
  }

  Future<HistoryEntry?> getHistory(String itemId) async {
    _assertInit();
    final raw = Hive.box<String>(boxHistory).get(itemId);
    if (raw == null) return null;
    try {
      return HistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  Future<List<HistoryEntry>> listHistory({int limit = 50}) async {
    _assertInit();
    final box = Hive.box<String>(boxHistory);
    final out = <HistoryEntry>[];
    for (final v in box.values) {
      try {
        out.add(HistoryEntry.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception {
        // Skip.
      }
    }
    out.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    if (out.length > limit) return out.sublist(0, limit);
    return out;
  }

  Box<String> get historyBox {
    _assertInit();
    return Hive.box<String>(boxHistory);
  }

  // Prefs -------------------------------------------------------------------
  Box<dynamic> get prefsBox {
    _assertInit();
    return Hive.box<dynamic>(boxPrefs);
  }

  // Recordings --------------------------------------------------------------
  Future<void> putRecording(RecordingTask t) async {
    _assertInit();
    await Hive.box<String>(boxRecordings).put(t.id, jsonEncode(t.toJson()));
  }

  Future<void> deleteRecording(String id) async {
    _assertInit();
    await Hive.box<String>(boxRecordings).delete(id);
  }

  Future<List<RecordingTask>> listRecordings() async {
    _assertInit();
    final box = Hive.box<String>(boxRecordings);
    final out = <RecordingTask>[];
    for (final v in box.values) {
      try {
        out.add(RecordingTask.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception catch (e) {
        _log.warn('skipping corrupt recording record: $e');
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Stream<List<RecordingTask>> watchRecordings() async* {
    _assertInit();
    final box = Hive.box<String>(boxRecordings);
    yield await listRecordings();
    yield* box.watch().asyncMap((_) => listRecordings());
  }

  // Downloads ---------------------------------------------------------------
  Future<void> putDownload(DownloadTask t) async {
    _assertInit();
    await Hive.box<String>(boxDownloads).put(t.id, jsonEncode(t.toJson()));
  }

  Future<void> deleteDownload(String id) async {
    _assertInit();
    await Hive.box<String>(boxDownloads).delete(id);
  }

  Future<DownloadTask?> getDownload(String id) async {
    _assertInit();
    final raw = Hive.box<String>(boxDownloads).get(id);
    if (raw == null) return null;
    try {
      return DownloadTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  Future<List<DownloadTask>> listDownloads() async {
    _assertInit();
    final box = Hive.box<String>(boxDownloads);
    final out = <DownloadTask>[];
    for (final v in box.values) {
      try {
        out.add(DownloadTask.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception catch (e) {
        _log.warn('skipping corrupt download record: $e');
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Stream<List<DownloadTask>> watchDownloads() async* {
    _assertInit();
    final box = Hive.box<String>(boxDownloads);
    yield await listDownloads();
    yield* box.watch().asyncMap((_) => listDownloads());
  }

  // Helpers -----------------------------------------------------------------
  Future<Box<E>> _openIfNeeded<E>(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<E>(name);
    return Hive.openBox<E>(name);
  }

  Future<void> _safeDeleteBox(String name) async {
    try {
      if (Hive.isBoxOpen(name)) {
        // All channels/vod/series boxes are opened as Box<String>; close
        // with the same type to avoid Hive's type-mismatch guard.
        await Hive.box<String>(name).close();
      }
      await Hive.deleteBoxFromDisk(name);
    } on Exception catch (e) {
      _log.warn('could not delete box $name: $e');
    }
  }
}
