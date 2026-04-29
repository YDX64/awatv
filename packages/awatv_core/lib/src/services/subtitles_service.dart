import 'dart:convert';
import 'dart:io';

import 'package:awatv_core/src/clients/opensubtitles_client.dart';
import 'package:awatv_core/src/models/episode.dart';
import 'package:awatv_core/src/models/series_item.dart';
import 'package:awatv_core/src/models/vod_item.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';

/// Cached wrapper around [OpenSubtitlesClient]. Two layers of caching:
///
/// 1. Search results — hashed by `(kind, identifier, lang)` and parked
///    in `metadata` box for 1 hour. Most users request the same content
///    multiple times in a single sitting (open detail → preview → play),
///    so 1 hour is a sensible compromise between freshness and bandwidth.
/// 2. Downloaded SRT bodies — keyed by `(fileId, lang)` for 24 hours.
///    Re-resolving the same SRT every time the user re-opens the player
///    burns the rate limit; 24 h matches the way OpenSubtitles itself
///    issues short-lived download links.
///
/// When the API key is empty (free build / dev environment), every
/// `searchFor*` returns an empty list and `fetchSrt` throws. UI calls
/// already null-check the list and display "no results" so this works
/// without further changes.
class SubtitlesService {
  SubtitlesService({
    required AwatvStorage storage,
    OpenSubtitlesClient? client,
    Duration searchTtl = const Duration(hours: 1),
    Duration srtTtl = const Duration(hours: 24),
  })  : _storage = storage,
        _client = client,
        _searchTtl = searchTtl,
        _srtTtl = srtTtl;

  final AwatvStorage _storage;
  final OpenSubtitlesClient? _client;
  final Duration _searchTtl;
  final Duration _srtTtl;

  static final AwatvLogger _log = AwatvLogger(tag: 'SubtitlesService');

  /// True when the underlying client has an API key. UI uses this to
  /// hide the "OpenSubtitles" section when nothing can ever come back.
  bool get isAvailable => _client != null;

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  Future<List<SubtitleResult>> searchFor(
    VodItem v, {
    String lang = 'tr',
  }) async {
    final client = _client;
    if (client == null) return const <SubtitleResult>[];
    final cacheKey =
        'opensubs:movie:${v.id}:${v.title.toLowerCase()}:${v.year ?? ''}:$lang';
    final cached = await _readSearchCache(cacheKey);
    if (cached != null) return cached;

    try {
      final results = await client.searchByTitle(
        v.title,
        language: lang,
        year: v.year,
      );
      await _writeSearchCache(cacheKey, results);
      return results;
    } on Object catch (e) {
      _log.warn('search failed for ${v.title}: $e');
      return const <SubtitleResult>[];
    }
  }

  Future<List<SubtitleResult>> searchForEpisode(
    SeriesItem s,
    Episode e, {
    String lang = 'tr',
  }) async {
    final client = _client;
    if (client == null) return const <SubtitleResult>[];
    final cacheKey =
        'opensubs:series:${s.id}:s${e.season}e${e.number}:$lang';
    final cached = await _readSearchCache(cacheKey);
    if (cached != null) return cached;

    try {
      final results = await client.searchByEpisode(
        query: s.title,
        season: e.season,
        episode: e.number,
        language: lang,
      );
      await _writeSearchCache(cacheKey, results);
      return results;
    } on Object catch (err) {
      _log.warn('episode search failed for ${s.title} S${e.season}E${e.number}: $err');
      return const <SubtitleResult>[];
    }
  }

  /// Free-form search — used by the "ara" textfield in the picker so the
  /// user can correct an auto-search miss without leaving the player.
  Future<List<SubtitleResult>> searchByQuery(
    String query, {
    String lang = 'tr',
    int? year,
  }) async {
    final client = _client;
    if (client == null) return const <SubtitleResult>[];
    if (query.trim().isEmpty) return const <SubtitleResult>[];
    try {
      return await client.searchByTitle(query, language: lang, year: year);
    } on Object catch (e) {
      _log.warn('manual search failed for $query: $e');
      return const <SubtitleResult>[];
    }
  }

  // -------------------------------------------------------------------------
  // Download
  // -------------------------------------------------------------------------

  /// Resolve a `file_id` to the SRT body. Cached for 24 h.
  Future<String> fetchSrt(int fileId, {String lang = 'tr'}) async {
    final client = _client;
    if (client == null) {
      throw StateError('OpenSubtitles client not configured');
    }
    final cacheKey = 'opensubs:srt:$fileId:$lang';
    final cached = await _storage.getMetadataJson(cacheKey, ttl: _srtTtl);
    if (cached != null) {
      final body = cached['body'] as String?;
      if (body != null && body.isNotEmpty) return body;
    }
    final body = await client.downloadByFileId(fileId);
    await _storage.putMetadataJson(cacheKey, <String, dynamic>{'body': body});
    return body;
  }

  /// Write an in-memory SRT body to a temporary file and return a
  /// `file://` URI suitable for `SubtitleTrack.uri`.
  ///
  /// Mobile + desktop only — on web the platform has no notion of a
  /// writable temp directory. The caller should branch on `kIsWeb`
  /// before reaching here.
  Future<String> writeToTempFile(
    String srtBody, {
    String prefix = 'awatv_sub',
    String extension = 'srt',
  }) async {
    final dir = Directory.systemTemp;
    final ts = DateTime.now().microsecondsSinceEpoch;
    final file = File(
      '${dir.path}${Platform.pathSeparator}${prefix}_$ts.$extension',
    );
    await file.writeAsString(srtBody, flush: true);
    return file.uri.toString();
  }

  // -------------------------------------------------------------------------
  // Cache helpers
  // -------------------------------------------------------------------------

  Future<List<SubtitleResult>?> _readSearchCache(String key) async {
    try {
      final raw = await _storage.getMetadataJson(key, ttl: _searchTtl);
      if (raw == null) return null;
      final list = raw['results'];
      if (list is! List) return null;
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SubtitleResult.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false);
    } on Object catch (e) {
      _log.warn('subtitle cache decode failed for $key: $e');
      return null;
    }
  }

  Future<void> _writeSearchCache(
    String key,
    List<SubtitleResult> results,
  ) async {
    try {
      await _storage.putMetadataJson(key, <String, dynamic>{
        'results': results.map((r) => r.toJson()).toList(),
      });
    } on Object catch (e) {
      _log.warn('subtitle cache write failed for $key: $e');
    }
  }

  /// Diagnostic helper used by tests — exposes the cache key so unit
  /// tests can assert on miss/hit transitions without poking Hive.
  // ignore: unused_element, document_ignores
  String _debugKeyFor(String s) => base64.encode(utf8.encode(s));
}
