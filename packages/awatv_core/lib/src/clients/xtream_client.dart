import 'dart:convert';

import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/models/episode.dart';
import 'package:awatv_core/src/models/series_item.dart';
import 'package:awatv_core/src/models/vod_item.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Client for the de-facto-standard Xtream Codes player API.
///
/// Endpoint: `{server}/player_api.php?username=&password=&action=...`
///
/// Stream URL formats:
/// - Live: `{server}/{username}/{password}/{streamId}.{ext}`
/// - VOD:  `{server}/movie/{username}/{password}/{streamId}.{ext}`
/// - Series episode: `{server}/series/{username}/{password}/{streamId}.{ext}`
class XtreamClient {
  XtreamClient({
    required this.server,
    required this.username,
    required this.password,
    Dio? dio,
  })  : _dio = dio ?? _defaultDio(),
        _sourceId = _composeSourceId(server, username);

  final String server;
  final String username;
  final String password;
  final Dio _dio;
  final String _sourceId;

  static final AwatvLogger _log = AwatvLogger(tag: 'XtreamClient');

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
        ),
      );

  static String _composeSourceId(String server, String username) {
    return 'xtream:$username@${Uri.parse(server).host}';
  }

  String get _normalizedServer {
    final s = server.endsWith('/') ? server.substring(0, server.length - 1) : server;
    return s;
  }

  Uri _api(Map<String, String> action) {
    final params = <String, String>{
      'username': username,
      'password': password,
      ...action,
    };
    return Uri.parse('$_normalizedServer/player_api.php')
        .replace(queryParameters: params);
  }

  /// Light auth check. Hits `player_api.php` with no `action`, which returns
  /// `user_info`/`server_info`. Throws [XtreamAuthException] when credentials
  /// are wrong.
  Future<bool> authenticate() async {
    final data = await _getJson(_api(const {}));
    if (data is! Map<String, dynamic>) {
      throw const XtreamAuthException('Unexpected auth response shape');
    }

    final userInfo = data['user_info'];
    if (userInfo is Map &&
        (userInfo['auth'] == 0 ||
            userInfo['auth'] == '0' ||
            (userInfo['status'] is String &&
                (userInfo['status'] as String).toLowerCase() == 'banned'))) {
      throw const XtreamAuthException('Credentials rejected by panel');
    }
    return true;
  }

  /// Live channels.
  Future<List<Channel>> liveChannels() async {
    final data = await _getJson(_api({'action': 'get_live_streams'}));
    if (data is! List) return const <Channel>[];

    final out = <Channel>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final streamId = (m['stream_id'] ?? m['streamId']).toString();
      if (streamId.isEmpty || streamId == 'null') continue;
      final ext = (m['stream_type'] == 'live'
              ? (m['container_extension'] as String?)
              : null) ??
          'ts';
      final name = (m['name'] as String?)?.trim() ?? 'Channel $streamId';
      final tvgId = (m['epg_channel_id'] as String?)?.trim();
      final logo = (m['stream_icon'] as String?)?.trim();
      final groupId = m['category_id']?.toString();

      out.add(
        Channel(
          id: Channel.buildId(
            sourceId: _sourceId,
            tvgId: tvgId,
            streamId: streamId,
            name: name,
          ),
          sourceId: _sourceId,
          name: name,
          tvgId: (tvgId == null || tvgId.isEmpty) ? null : tvgId,
          logoUrl: (logo == null || logo.isEmpty) ? null : logo,
          streamUrl:
              '$_normalizedServer/$username/$password/$streamId.$ext',
          groups: groupId == null ? const [] : [groupId],
          kind: ChannelKind.live,
          extras: <String, String>{
            if (m['added'] != null) 'added': m['added'].toString(),
          },
        ),
      );
    }
    return out;
  }

  /// VOD movies.
  Future<List<VodItem>> vodItems() async {
    final data = await _getJson(_api({'action': 'get_vod_streams'}));
    if (data is! List) return const <VodItem>[];

    final out = <VodItem>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final streamId = (m['stream_id'] ?? m['vod_id']).toString();
      if (streamId.isEmpty || streamId == 'null') continue;
      final ext = (m['container_extension'] as String?)?.trim();
      final extResolved = (ext == null || ext.isEmpty) ? 'mp4' : ext;
      final title = (m['name'] as String?)?.trim() ?? 'VOD $streamId';
      final poster = (m['stream_icon'] as String?)?.trim();
      final rating = _toDouble(m['rating']);
      final year = _yearFromDate((m['releaseDate'] ?? m['releasedate']) as String?);
      final tmdbId = _toInt(m['tmdb_id'] ?? m['tmdb']);

      out.add(
        VodItem(
          id: '$_sourceId::vod::$streamId',
          sourceId: _sourceId,
          title: title,
          year: year,
          plot: (m['plot'] as String?)?.trim(),
          posterUrl: (poster == null || poster.isEmpty) ? null : poster,
          rating: rating,
          streamUrl:
              '$_normalizedServer/movie/$username/$password/$streamId.$extResolved',
          containerExt: extResolved,
          tmdbId: tmdbId,
        ),
      );
    }
    return out;
  }

  /// Series headers (no episodes; call [seriesEpisodes] for those).
  Future<List<SeriesItem>> series() async {
    final data = await _getJson(_api({'action': 'get_series'}));
    if (data is! List) return const <SeriesItem>[];

    final out = <SeriesItem>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final seriesId = m['series_id']?.toString();
      if (seriesId == null || seriesId.isEmpty || seriesId == 'null') {
        continue;
      }
      final title = (m['name'] as String?)?.trim() ?? 'Series $seriesId';
      final poster = (m['cover'] as String?)?.trim();
      final rating = _toDouble(m['rating'] ?? m['rating_5based']);
      final year =
          _yearFromDate((m['releaseDate'] ?? m['releasedate']) as String?);
      final tmdbId = _toInt(m['tmdb'] ?? m['tmdb_id']);

      out.add(
        SeriesItem(
          id: '$_sourceId::series::$seriesId',
          sourceId: _sourceId,
          title: title,
          plot: (m['plot'] as String?)?.trim(),
          posterUrl: (poster == null || poster.isEmpty) ? null : poster,
          rating: rating,
          year: year,
          tmdbId: tmdbId,
        ),
      );
    }
    return out;
  }

  /// Episodes for one series.
  Future<List<Episode>> seriesEpisodes(int seriesId) async {
    final data = await _getJson(_api({
      'action': 'get_series_info',
      'series_id': '$seriesId',
    }));
    if (data is! Map) return const <Episode>[];

    final episodes = data['episodes'];
    if (episodes is! Map) return const <Episode>[];

    final out = <Episode>[];
    final seriesInternalId = '$_sourceId::series::$seriesId';

    for (final entry in episodes.entries) {
      final season = int.tryParse('${entry.key}') ?? 0;
      final list = entry.value;
      if (list is! List) continue;
      for (final raw in list) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final id = m['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final number = _toInt(m['episode_num']) ?? 0;
        final title = (m['title'] as String?)?.trim() ??
            'S${season}E$number';
        final ext = (m['container_extension'] as String?)?.trim();
        final extResolved = (ext == null || ext.isEmpty) ? 'mp4' : ext;
        final info = m['info'];
        final infoMap =
            info is Map ? info.cast<String, dynamic>() : <String, dynamic>{};
        final durationSec = _toInt(infoMap['duration_secs']);
        final durationMin = durationSec == null ? null : (durationSec ~/ 60);

        out.add(
          Episode(
            id: '$seriesInternalId::s${season}e$number::$id',
            seriesId: seriesInternalId,
            season: season,
            number: number,
            title: title,
            plot: (infoMap['plot'] as String?)?.trim(),
            durationMin: durationMin,
            posterUrl: (infoMap['movie_image'] as String?)?.trim(),
            streamUrl:
                '$_normalizedServer/series/$username/$password/$id.$extResolved',
            containerExt: extResolved,
          ),
        );
      }
    }
    return out;
  }

  /// Short EPG window for one stream id (typically next ~4 entries).
  Future<List<EpgProgramme>> shortEpg(String streamId) async {
    final data = await _getJson(_api({
      'action': 'get_short_epg',
      'stream_id': streamId,
    }));
    if (data is! Map) return const <EpgProgramme>[];

    final listings = data['epg_listings'];
    if (listings is! List) return const <EpgProgramme>[];

    final out = <EpgProgramme>[];
    for (final raw in listings) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final start = _xtreamTime(m['start']);
      final stop = _xtreamTime(m['end']);
      if (start == null || stop == null) continue;
      out.add(
        EpgProgramme(
          channelTvgId: streamId,
          start: start,
          stop: stop,
          title: _decodeMaybeBase64(m['title']) ?? '',
          description: _decodeMaybeBase64(m['description']),
        ),
      );
    }
    return out;
  }

  // --- helpers --------------------------------------------------------------

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final resp = await _dio.getUri<dynamic>(uri);
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const XtreamAuthException('HTTP auth rejected');
      }
      if (resp.statusCode == null ||
          resp.statusCode! < 200 ||
          resp.statusCode! >= 300) {
        throw NetworkException(
          'Xtream API returned status',
          statusCode: resp.statusCode,
          retryable: (resp.statusCode ?? 0) >= 500,
        );
      }
      return resp.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const XtreamAuthException('HTTP auth rejected');
      }
      _log.warn('Dio error: ${e.message}');
      throw NetworkException(
        e.message ?? 'Network failure',
        statusCode: e.response?.statusCode,
        retryable: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout,
      );
    }
  }

  static double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static int? _yearFromDate(String? s) {
    if (s == null || s.isEmpty) return null;
    final y = int.tryParse(s.substring(0, s.length >= 4 ? 4 : s.length));
    return y;
  }

  /// Xtream `start`/`end` come either as `YYYY-MM-DD HH:mm:ss` or as a
  /// unix-timestamp string. Tolerate both.
  static DateTime? _xtreamTime(Object? v) {
    if (v == null) return null;
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000, isUtc: true);
    }
    final s = v.toString();
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
    }
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  /// EPG titles/descriptions are usually base64-encoded by Xtream panels.
  /// Decode opportunistically; fall back to the raw string if it doesn't
  /// look like valid base64 UTF-8.
  static String? _decodeMaybeBase64(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;

    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=\s]+$');
    if (s.length % 4 == 0 && base64Pattern.hasMatch(s)) {
      try {
        final bytes = base64.decode(s.replaceAll(RegExp(r'\s+'), ''));
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        // Not actually base64 — return raw.
      }
    }
    return s;
  }
}
