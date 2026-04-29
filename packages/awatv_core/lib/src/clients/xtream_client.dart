import 'dart:convert';

import 'package:awatv_core/src/clients/provider_intel.dart';
import 'package:awatv_core/src/models/catchup_programme.dart';
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
        ),
      );

  static String _composeSourceId(String server, String username) {
    return 'xtream:$username@${Uri.parse(server).host}';
  }

  String get _normalizedServer {
    final s = server.endsWith('/') ? server.substring(0, server.length - 1) : server;
    return s;
  }

  /// Cached host of [server], used to look up the provider fingerprint.
  /// Cached because every channel/VOD/episode mapping consults it and
  /// re-parsing the server URL per row is wasteful.
  late final String _serverHost = () {
    try {
      return Uri.parse(_normalizedServer).host;
    } on FormatException {
      return '';
    }
  }();

  /// The provider fingerprint inferred from [_serverHost]. Used to pick
  /// the right URL templates so we don't hardcode `/movie/` or `/series/`
  /// — letting per-host recipes override.
  late final ProviderFingerprint _fingerprint = ProviderIntel.match(_serverHost);

  /// Renders a stream URL for [kind] using the matched fingerprint's
  /// first template. Falls back to the generic Xtream layout when the
  /// fingerprint doesn't define templates for that kind.
  String _streamUrl({
    required StreamKind kind,
    required String id,
    required String ext,
  }) {
    final templates = _fingerprint.templatesFor(kind);
    if (templates.isEmpty) {
      // Generic fallback (matches historical behaviour).
      switch (kind) {
        case StreamKind.live:
          return '$_normalizedServer/$username/$password/$id.$ext';
        case StreamKind.vod:
          return '$_normalizedServer/movie/$username/$password/$id.$ext';
        case StreamKind.series:
          return '$_normalizedServer/series/$username/$password/$id.$ext';
      }
    }
    return _fingerprint.render(
      template: templates.first,
      server: _normalizedServer,
      user: username,
      pass: password,
      id: id,
      ext: ext,
    );
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
    // Resolve category id → human-readable name (and parent chain) up front
    // so each channel's `groups` ends up readable ("TR | Spor") rather
    // than a numeric id ("12") in the UI.
    final cats = await _safeCategories('get_live_categories');
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
          streamUrl: _streamUrl(
            kind: StreamKind.live,
            id: streamId,
            ext: ext,
          ),
          groups: _resolveGroups(groupId, cats),
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
    final cats = await _safeCategories('get_vod_categories');
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
      final groupId = m['category_id']?.toString();

      // Genres come either as a comma/pipe-delimited string or a list.
      // Prepend the resolved category chain so users can browse by panel
      // category alongside any tmdb-style genres.
      final categoryChain = _resolveGroups(groupId, cats);
      final genreField = m['genre'];
      final genres = <String>[
        ...categoryChain,
        if (genreField is String)
          ...genreField
              .split(RegExp('[,|/]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
        else if (genreField is List)
          for (final g in genreField)
            if (g is String && g.trim().isNotEmpty) g.trim(),
      ];

      out.add(
        VodItem(
          id: '$_sourceId::vod::$streamId',
          sourceId: _sourceId,
          title: title,
          year: year,
          plot: (m['plot'] as String?)?.trim(),
          posterUrl: (poster == null || poster.isEmpty) ? null : poster,
          rating: rating,
          streamUrl: _streamUrl(
            kind: StreamKind.vod,
            id: streamId,
            ext: extResolved,
          ),
          containerExt: extResolved,
          tmdbId: tmdbId,
          genres: genres,
        ),
      );
    }
    return out;
  }

  /// Series headers (no episodes; call [seriesEpisodes] for those).
  Future<List<SeriesItem>> series() async {
    final cats = await _safeCategories('get_series_categories');
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
      final groupId = m['category_id']?.toString();

      final categoryChain = _resolveGroups(groupId, cats);
      final genreField = m['genre'];
      final genres = <String>[
        ...categoryChain,
        if (genreField is String)
          ...genreField
              .split(RegExp('[,|/]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
        else if (genreField is List)
          for (final g in genreField)
            if (g is String && g.trim().isNotEmpty) g.trim(),
      ];

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
          genres: genres,
        ),
      );
    }
    return out;
  }

  /// Live category map: id → display name, with parent chain prepended
  /// when the panel exposes a `parent_id`. Empty when the panel does not
  /// expose categories (older Xtream forks).
  Future<Map<String, String>> liveCategories() =>
      _fetchCategories('get_live_categories');

  /// VOD category map: id → display name (with parent chain prepended).
  Future<Map<String, String>> vodCategories() =>
      _fetchCategories('get_vod_categories');

  /// Series category map: id → display name (with parent chain prepended).
  Future<Map<String, String>> seriesCategories() =>
      _fetchCategories('get_series_categories');

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
            streamUrl: _streamUrl(
              kind: StreamKind.series,
              id: id,
              ext: extResolved,
            ),
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

  // --- catchup / archive ----------------------------------------------------

  /// Programmes that the panel marked as recordable / catchup-available.
  ///
  /// Backed by `get_simple_data_table` with `stream_id`. Each row carries
  /// `epg_id`, `title`, `start_timestamp`, `stop_timestamp`,
  /// `now_playing` and `has_archive`. Rows whose `has_archive == 0`
  /// stay in the result so the UI can decide whether to grey them out
  /// versus surface a CTA.
  Future<List<CatchupProgramme>> catchupForChannel(int streamId) async {
    final data = await _getJson(_api({
      'action': 'get_simple_data_table',
      'stream_id': '$streamId',
    }));
    if (data is! Map) return const <CatchupProgramme>[];

    final listings = data['epg_listings'];
    if (listings is! List) return const <CatchupProgramme>[];

    final out = <CatchupProgramme>[];
    for (final raw in listings) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final start = _xtreamTime(m['start_timestamp']) ?? _xtreamTime(m['start']);
      final stop = _xtreamTime(m['stop_timestamp']) ?? _xtreamTime(m['end']);
      if (start == null || stop == null) continue;
      final hasArchiveRaw = m['has_archive'] ?? m['hasArchive'];
      final hasArchive = hasArchiveRaw == 1 ||
          hasArchiveRaw == '1' ||
          hasArchiveRaw == true;
      out.add(
        CatchupProgramme(
          streamId: streamId,
          epgId: (m['id'] ?? m['epg_id'])?.toString(),
          title: _decodeMaybeBase64(m['title']) ?? '',
          description: _decodeMaybeBase64(m['description']),
          start: start,
          stop: stop,
          nowPlaying: m['now_playing'] == 1 || m['now_playing'] == '1',
          hasArchive: hasArchive,
        ),
      );
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// Build a catchup playback URL.
  ///
  /// Xtream timeshift URL pattern (de-facto standard):
  /// `{server}/timeshift/{user}/{pass}/{durationMinutes}/{yyyy-MM-dd:HH-mm}/{streamId}.{ext}`.
  ///
  /// Some forks expose `streaming/timeshift.php?...&start=...&duration=...`
  /// — we surface the canonical timeshift path here and let the player
  /// fall back to alternate forms via the candidate system if needed.
  String catchupUrl({
    required int streamId,
    required DateTime start,
    required Duration duration,
    String container = 'ts',
  }) {
    final utc = start.toUtc();
    final yyyy = utc.year.toString().padLeft(4, '0');
    final mm = utc.month.toString().padLeft(2, '0');
    final dd = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mi = utc.minute.toString().padLeft(2, '0');
    final stamp = '$yyyy-$mm-$dd:$hh-$mi';
    final mins = duration.inMinutes;
    return '$_normalizedServer/timeshift/$username/$password/$mins/$stamp/$streamId.$container';
  }

  // --- categories -----------------------------------------------------------

  /// Fetches a category map for [action] without throwing on transport
  /// errors. Older Xtream forks ship without category endpoints; we want a
  /// missing/erroring categories call to degrade silently to "no names",
  /// not to abort the whole catalog load.
  Future<Map<String, _CategoryInfo>> _safeCategories(String action) async {
    try {
      return await _fetchCategoriesRaw(action);
    } on Object {
      return const <String, _CategoryInfo>{};
    }
  }

  /// Public-facing variant: id → resolved display name (parent chain
  /// joined with " > " when available).
  Future<Map<String, String>> _fetchCategories(String action) async {
    final raw = await _safeCategories(action);
    return <String, String>{
      for (final entry in raw.entries)
        entry.key: _renderName(entry.key, raw),
    };
  }

  Future<Map<String, _CategoryInfo>> _fetchCategoriesRaw(String action) async {
    final data = await _getJson(_api({'action': action}));
    if (data is! List) return const <String, _CategoryInfo>{};
    final out = <String, _CategoryInfo>{};
    for (final raw in data) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = m['category_id']?.toString();
      final name = (m['category_name'] as String?)?.trim();
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      final parent = m['parent_id'];
      final parentId = (parent == null ||
              parent.toString().isEmpty ||
              parent.toString() == '0')
          ? null
          : parent.toString();
      out[id] = _CategoryInfo(name: name, parentId: parentId);
    }
    return out;
  }

  /// Renders the parent chain for [id] as `parent > child`, falling back
  /// to the leaf name when no parent is set or to the raw id when the
  /// category is unknown.
  String _renderName(String id, Map<String, _CategoryInfo> cats) {
    final info = cats[id];
    if (info == null) return id;
    final parts = <String>[info.name];
    var pid = info.parentId;
    final seen = <String>{id};
    while (pid != null && !seen.contains(pid)) {
      seen.add(pid);
      final parent = cats[pid];
      if (parent == null) break;
      parts.insert(0, parent.name);
      pid = parent.parentId;
    }
    return parts.join(' > ');
  }

  /// Returns the `groups` list for an item: each parent name as its own
  /// entry (so chip filters can match either the parent or the leaf),
  /// and a final "parent > leaf" entry when there's a chain. Falls back
  /// to `[groupId]` when the category is unknown — preserving old
  /// behaviour for panels without category endpoints.
  List<String> _resolveGroups(
    String? groupId,
    Map<String, _CategoryInfo> cats,
  ) {
    if (groupId == null || groupId.isEmpty) return const <String>[];
    final info = cats[groupId];
    if (info == null) return <String>[groupId];

    // Walk the parent chain, collecting names from root to leaf.
    final names = <String>[info.name];
    var pid = info.parentId;
    final seen = <String>{groupId};
    while (pid != null && !seen.contains(pid)) {
      seen.add(pid);
      final parent = cats[pid];
      if (parent == null) break;
      names.insert(0, parent.name);
      pid = parent.parentId;
    }
    if (names.length == 1) return <String>[names.first];
    return <String>[...names, names.join(' > ')];
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

/// Internal record of a panel category, used to resolve `category_id`
/// references in stream / VOD / series payloads back to readable names.
class _CategoryInfo {
  const _CategoryInfo({required this.name, this.parentId});
  final String name;
  final String? parentId;
}
