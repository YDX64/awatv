import 'dart:convert';

import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Result row from the OpenSubtitles `/subtitles` endpoint, flattened
/// into a single object the UI can render directly.
///
/// Field semantics:
/// - [fileId]: numeric `file_id` from the `files` array. Pass to
///   [OpenSubtitlesClient.downloadByFileId] to fetch the SRT body.
/// - [language]: ISO-639-1 two-letter code (e.g. `tr`, `en`).
/// - [release]: free-form release name from upstream
///   (e.g. `Movie.2024.1080p.WEB-DL.H264-XYZ`).
/// - [downloadCount]: heuristic for ranking — higher is more popular.
/// - [rating]: 0..10 average user rating; 0 when not available.
/// - [hi]: hearing-impaired (CC) variant.
/// - [fromTrusted]: uploaded by a trusted/verified contributor.
class SubtitleResult {
  const SubtitleResult({
    required this.fileId,
    required this.language,
    required this.release,
    required this.downloadCount,
    required this.rating,
    required this.hi,
    required this.fromTrusted,
    this.releaseGroup,
  });

  factory SubtitleResult.fromJson(Map<String, dynamic> json) {
    return SubtitleResult(
      fileId: (json['fileId'] as num).toInt(),
      language: json['language'] as String? ?? '',
      release: json['release'] as String? ?? '',
      releaseGroup: json['releaseGroup'] as String?,
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      hi: json['hi'] as bool? ?? false,
      fromTrusted: json['fromTrusted'] as bool? ?? false,
    );
  }

  final int fileId;
  final String language;
  final String release;
  final String? releaseGroup;
  final int downloadCount;
  final double rating;
  final bool hi;
  final bool fromTrusted;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fileId': fileId,
        'language': language,
        'release': release,
        if (releaseGroup != null) 'releaseGroup': releaseGroup,
        'downloadCount': downloadCount,
        'rating': rating,
        'hi': hi,
        'fromTrusted': fromTrusted,
      };
}

/// Thin client over the OpenSubtitles REST API v1.
///
/// Auth: every request must carry an `Api-Key` header and a custom
/// `User-Agent` (OpenSubtitles enforces both). The free tier is rate-
/// limited but otherwise unrestricted for personal use.
///
/// Construction is cheap; instantiate once per app and reuse. All
/// network errors are wrapped in [NetworkException] so callers can
/// degrade gracefully without depending on Dio types directly.
class OpenSubtitlesClient {
  OpenSubtitlesClient({
    required this.apiKey,
    Dio? dio,
    String? userAgent,
  })  : _dio = dio ?? _defaultDio(),
        // OpenSubtitles asks every integration to identify itself with a
        // real product version in the User-Agent — keep this in lockstep
        // with `pubspec.yaml` (`version:` field) on every release bump.
        _userAgent = userAgent ?? 'AWAtv v0.5.8';

  static const String _base = 'https://api.opensubtitles.com/api/v1';

  final String apiKey;
  final String _userAgent;
  final Dio _dio;

  static final AwatvLogger _log = AwatvLogger(tag: 'OpenSubtitlesClient');

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 25),
          // Don't rely on Dio's default 200..299 — OpenSubtitles returns
          // 4xx with a JSON error body that we want to surface.
          validateStatus: (int? s) => s != null && s < 500,
        ),
      );

  Map<String, String> get _headers => <String, String>{
        'Api-Key': apiKey,
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };

  /// Search subtitles by IMDb id (with or without the `tt` prefix).
  /// Returns up to ~50 entries sorted by upstream popularity.
  Future<List<SubtitleResult>> searchByImdbId(
    String imdbId, {
    String language = 'tr',
  }) async {
    if (apiKey.isEmpty) return const <SubtitleResult>[];
    final id = imdbId.startsWith('tt') ? imdbId.substring(2) : imdbId;
    if (id.trim().isEmpty) return const <SubtitleResult>[];
    final params = <String, String>{
      'imdb_id': id,
      'languages': language,
      'order_by': 'download_count',
    };
    return _runSearch(params);
  }

  /// Search subtitles by free-form title. Pass [year] to disambiguate
  /// remakes (TMDB titles often share strings).
  Future<List<SubtitleResult>> searchByTitle(
    String query, {
    String language = 'tr',
    int? year,
  }) async {
    if (apiKey.isEmpty) return const <SubtitleResult>[];
    if (query.trim().isEmpty) return const <SubtitleResult>[];
    final params = <String, String>{
      'query': query.trim(),
      'languages': language,
      'order_by': 'download_count',
      if (year != null) 'year': '$year',
    };
    return _runSearch(params);
  }

  /// Search subtitles for a TV episode. Both [season] and [episode]
  /// are 1-indexed.
  Future<List<SubtitleResult>> searchByEpisode({
    required String query,
    required int season,
    required int episode,
    String language = 'tr',
  }) async {
    if (apiKey.isEmpty) return const <SubtitleResult>[];
    if (query.trim().isEmpty) return const <SubtitleResult>[];
    final params = <String, String>{
      'query': query.trim(),
      'season_number': '$season',
      'episode_number': '$episode',
      'languages': language,
      'order_by': 'download_count',
    };
    return _runSearch(params);
  }

  Future<List<SubtitleResult>> _runSearch(Map<String, String> params) async {
    final uri =
        Uri.parse('$_base/subtitles').replace(queryParameters: params);
    final data = await _getJson(uri);
    if (data is! Map) return const <SubtitleResult>[];

    final results = data['data'];
    if (results is! List) return const <SubtitleResult>[];
    final out = <SubtitleResult>[];
    for (final r in results) {
      if (r is! Map) continue;
      final attrs = r['attributes'];
      if (attrs is! Map) continue;
      final attributes = attrs.cast<String, dynamic>();

      // OpenSubtitles ships the file id inside `files[0].file_id`. A
      // single subtitle entry may have multiple files (e.g. CD1/CD2);
      // we only surface the first since 99% of releases ship as one.
      final files = attributes['files'];
      if (files is! List || files.isEmpty) continue;
      final firstFile = files.first;
      if (firstFile is! Map) continue;
      final fileMap = firstFile.cast<String, dynamic>();
      final fileId = (fileMap['file_id'] as num?)?.toInt();
      if (fileId == null) continue;

      final lang = (attributes['language'] as String?)?.trim() ?? '';
      final release = (attributes['release'] as String?)?.trim() ??
          (fileMap['file_name'] as String?)?.trim() ??
          'subtitle';
      final downloadCount =
          (attributes['download_count'] as num?)?.toInt() ?? 0;
      final rating = (attributes['ratings'] as num?)?.toDouble() ?? 0;
      final hi = attributes['hearing_impaired'] == true;
      final trusted = attributes['from_trusted'] == true;

      // `release_group_name` lives under feature_details on TV episodes
      // and is sometimes a sibling field. Read both forms.
      String? releaseGroup;
      final fd = attributes['feature_details'];
      if (fd is Map) {
        final group = fd['release_group_name'];
        if (group is String && group.isNotEmpty) releaseGroup = group;
      }
      releaseGroup ??= attributes['release_group_name'] as String?;

      out.add(
        SubtitleResult(
          fileId: fileId,
          language: lang,
          release: release,
          releaseGroup: releaseGroup,
          downloadCount: downloadCount,
          rating: rating,
          hi: hi,
          fromTrusted: trusted,
        ),
      );
    }
    return out;
  }

  /// Resolve a `file_id` to its raw SRT/VTT body. The endpoint first
  /// returns a temporary download URL (with single-use token); we
  /// follow it and return the decoded body verbatim.
  Future<String> downloadByFileId(int fileId) async {
    if (apiKey.isEmpty) {
      throw const NetworkException('OpenSubtitles API key not configured');
    }
    final uri = Uri.parse('$_base/download');
    try {
      final resp = await _dio.postUri<dynamic>(
        uri,
        data: jsonEncode(<String, dynamic>{'file_id': fileId}),
        options: Options(
          headers: <String, String>{
            ..._headers,
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );
      final status = resp.statusCode;
      final data = resp.data;
      if (status == null || status < 200 || status >= 300) {
        final msg = data is Map && data['message'] is String
            ? data['message'] as String
            : 'OpenSubtitles download failed';
        throw NetworkException(
          msg,
          statusCode: status,
          retryable: (status ?? 0) >= 500 || status == 429,
        );
      }
      if (data is! Map) {
        throw const NetworkException('OpenSubtitles: unexpected payload');
      }
      final url = data['link'] as String?;
      if (url == null || url.isEmpty) {
        throw const NetworkException('OpenSubtitles: missing link in payload');
      }
      final body = await _dio.getUri<String>(
        Uri.parse(url),
        options: Options(
          // The signed download URL doesn't need the API key/UA, but we
          // ask for a string body so Dio decodes UTF-8 charsets cleanly.
          responseType: ResponseType.plain,
          headers: <String, String>{'User-Agent': _userAgent},
        ),
      );
      final str = body.data;
      if (str == null || str.isEmpty) {
        throw const NetworkException('OpenSubtitles: empty subtitle body');
      }
      return str;
    } on DioException catch (e) {
      _log.warn('OpenSubtitles download error: ${e.message}');
      throw NetworkException(
        e.message ?? 'OpenSubtitles download failed',
        statusCode: e.response?.statusCode,
        retryable: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout,
      );
    }
  }

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final resp = await _dio.getUri<dynamic>(
        uri,
        options: Options(headers: _headers, responseType: ResponseType.json),
      );
      final status = resp.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw NetworkException(
          'OpenSubtitles returned status',
          statusCode: status,
          retryable: (status ?? 0) >= 500 || status == 429,
        );
      }
      return resp.data;
    } on DioException catch (e) {
      _log.warn('OpenSubtitles Dio error: ${e.message}');
      throw NetworkException(
        e.message ?? 'OpenSubtitles request failed',
        statusCode: e.response?.statusCode,
        retryable: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout,
      );
    }
  }
}
