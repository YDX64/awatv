import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/series_item.dart';
import 'package:awatv_core/src/models/vod_item.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Client for the Stalker / Ministra portal protocol used by Mag-style
/// set-top boxes (Infomir Mag-200 / 250 / 254 / 322 etc.) and the
/// commercial-Ministra and many community-Stalker panels.
///
/// Endpoint shape: `<server>/portal.php?type=...&action=...&JsHttpRequest=1-xml`.
///
/// Auth model: cookie-based MAC binding. Each request carries a
/// `Cookie:` header with the device MAC (in the standard
/// `00:1A:79:XX:XX:XX` form) plus a stb_lang and timezone hint. Once a
/// MAC is whitelisted by the panel operator, the `handshake` action
/// returns a `token` which subsequent calls echo as `Authorization: Bearer`.
///
/// Live URLs come back as raw player commands (e.g. `ffrt http://.../`)
/// in a `cmd` field. We strip the prefix and surface the URL only;
/// playback URLs that start with `/play/` need to be expanded against
/// the portal root. For VOD/series the portal can return either
/// pre-resolved URLs or `cmd` placeholders requiring a separate
/// `create_link` round-trip — we cover both shapes here.
class StalkerClient {
  StalkerClient({
    required String portalUrl,
    required String macAddress,
    String? timezone,
    String language = 'en',
    Dio? dio,
  })  : _portal = _normalisePortal(portalUrl),
        _mac = normaliseMac(macAddress),
        _tz = timezone ?? 'UTC',
        _lang = language,
        _dio = dio ?? _defaultDio() {
    if (!isValidMac(_mac)) {
      throw const StalkerAuthException(
        'Gecersiz MAC adresi. Format: 00:1A:79:XX:XX:XX',
      );
    }
  }

  /// Portal base URL, without trailing slash.
  final String _portal;

  /// Device MAC address in the canonical colon-separated form.
  final String _mac;

  /// Time-zone string the portal uses for its EPG; defaults to UTC.
  final String _tz;

  /// stb_lang hint sent with every request.
  final String _lang;

  final Dio _dio;

  /// Bearer token returned by [handshake]. Populated on first auth and
  /// re-used by subsequent calls.
  String? _token;

  /// Stable id for this Stalker source (used as a parent prefix on the
  /// produced `Channel` / `VodItem` / `SeriesItem` ids).
  late final String _sourceId = 'stalker:${_mac.replaceAll(':', '')}@'
      '${Uri.parse(_portal).host}';

  static final AwatvLogger _log = AwatvLogger(tag: 'StalkerClient');

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  static String _normalisePortal(String url) {
    var s = url.trim();
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (s.endsWith('/portal.php')) {
      s = s.substring(0, s.length - '/portal.php'.length);
    }
    if (s.endsWith('/stalker_portal/server/load.php')) {
      s = s.substring(0, s.length - '/stalker_portal/server/load.php'.length);
    }
    return s;
  }

  /// Validates that [s] looks like a MAC address. We accept colon-, dash-
  /// or dot-separated 12-hex-digit strings.
  static bool isValidMac(String s) {
    final hex = s.replaceAll(RegExp(r'[:\-\.]'), '');
    if (hex.length != 12) return false;
    return RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(hex);
  }

  /// Reformats a MAC into the colon-separated canonical form. Returns
  /// the input unchanged if it cannot be normalised — the caller can
  /// then route through [isValidMac] to surface an error.
  static String normaliseMac(String s) {
    final hex = s.trim().replaceAll(RegExp(r'[:\-\.]'), '').toUpperCase();
    if (hex.length != 12) return s.trim();
    final buf = StringBuffer();
    for (var i = 0; i < hex.length; i += 2) {
      if (i > 0) buf.write(':');
      buf.write(hex.substring(i, i + 2));
    }
    return buf.toString();
  }

  /// Stable id for this source (mirrors `XtreamClient._sourceId`).
  String get sourceId => _sourceId;

  /// Portal endpoint URI for [params].
  Uri _api(Map<String, String> params) {
    final qp = <String, String>{
      'JsHttpRequest': '1-xml',
      ...params,
    };
    return Uri.parse('$_portal/portal.php')
        .replace(queryParameters: qp);
  }

  /// Cookie + Authorization headers for every authenticated call.
  Map<String, String> _headers() {
    final cookie = 'mac=${Uri.encodeComponent(_mac)}; '
        'stb_lang=$_lang; '
        'timezone=${Uri.encodeComponent(_tz)}';
    final h = <String, String>{
      'Cookie': cookie,
      'X-User-Agent': 'Model: MAG250; Link: WiFi',
      'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 '
          '(KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 250 Safari/533.3',
    };
    final tok = _token;
    if (tok != null && tok.isNotEmpty) {
      h['Authorization'] = 'Bearer $tok';
    }
    return h;
  }

  /// Performs the Stalker handshake: hits `type=stb&action=handshake`
  /// and stashes the returned bearer token. Returns `true` when the
  /// portal accepted our MAC.
  Future<bool> handshake() async {
    final data = await _getJson(_api(const {
      'type': 'stb',
      'action': 'handshake',
    }));
    if (data is! Map<String, dynamic>) {
      throw const StalkerAuthException('Handshake yaniti bekleneni vermedi');
    }
    final js = data['js'];
    if (js is! Map) {
      throw const StalkerAuthException('Handshake gecersiz: js eksik');
    }
    final tok = js['token']?.toString() ?? '';
    if (tok.isEmpty) {
      throw const StalkerAuthException(
        'Token alinamadi - MAC portalda yetkili degil',
      );
    }
    _token = tok;

    // Some panels require a profile-load round-trip before they answer
    // catalog queries. Fire it best-effort and ignore failures.
    try {
      await _getJson(_api(const {
        'type': 'stb',
        'action': 'get_profile',
      }));
    } on Object catch (e) {
      _log.warn('get_profile after handshake failed: $e');
    }
    return true;
  }

  /// All live channels.
  ///
  /// Endpoint: `type=itv&action=get_all_channels`. Older portals don't
  /// expose `get_all_channels` and require paginating
  /// `action=get_ordered_list&genre=*&p=1...N`. We try the all-in-one
  /// shape first and fall back to the paginated one.
  Future<List<Channel>> liveChannels() async {
    await _ensureToken();
    final out = <Channel>[];

    // 1. Resolve genres → display name map up front so each channel's
    //    groups list ends up readable.
    final genres = await _liveGenres();

    final tryAllInOne = await _tryGetJson(_api(const {
      'type': 'itv',
      'action': 'get_all_channels',
    }));
    final raw = _extractDataArray(tryAllInOne);
    if (raw != null && raw.isNotEmpty) {
      out.addAll(_mapLiveRows(raw, genres));
      return out;
    }

    // Fallback: paginated walk.
    var page = 1;
    while (page <= 50) {
      final body = await _tryGetJson(_api({
        'type': 'itv',
        'action': 'get_ordered_list',
        'genre': '*',
        'p': '$page',
      }));
      final rows = _extractDataArray(body);
      if (rows == null || rows.isEmpty) break;
      out.addAll(_mapLiveRows(rows, genres));
      // Heuristic stop: if the panel returned fewer than ~14 rows we
      // assume we've drained the queue (Stalker default page size).
      if (rows.length < 14) break;
      page += 1;
    }
    return out;
  }

  /// Resolves the live-channel genre id → human-readable name table.
  /// Empty when the panel doesn't expose genres.
  Future<Map<String, String>> _liveGenres() async {
    final body = await _tryGetJson(_api(const {
      'type': 'itv',
      'action': 'get_genres',
    }));
    final rows = _extractDataArray(body);
    if (rows == null) return const <String, String>{};
    final out = <String, String>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = m['id']?.toString();
      final title = (m['title'] as String?)?.trim();
      if (id == null || id.isEmpty || title == null || title.isEmpty) {
        continue;
      }
      out[id] = title;
    }
    return out;
  }

  List<Channel> _mapLiveRows(
    List<dynamic> rows,
    Map<String, String> genres,
  ) {
    final out = <Channel>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = (m['id'] ?? m['ch_id'])?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = (m['name'] as String?)?.trim() ??
          (m['title'] as String?)?.trim() ??
          'Channel $id';
      final tvgId = (m['xmltv_id'] as String?)?.trim();
      final logo = (m['logo'] as String?)?.trim();
      final cmd = (m['cmd'] as String?)?.trim() ?? '';
      final genreId = m['tv_genre_id']?.toString();
      final genreName = genreId == null ? null : genres[genreId];

      out.add(
        Channel(
          id: '$_sourceId::live::$id',
          sourceId: _sourceId,
          name: name,
          tvgId: (tvgId == null || tvgId.isEmpty) ? null : tvgId,
          logoUrl: (logo == null || logo.isEmpty) ? null : logo,
          streamUrl: streamUrlFromCmd(cmd, channelId: id),
          groups: <String>[
            if (genreName != null && genreName.isNotEmpty) genreName,
          ],
          kind: ChannelKind.live,
          extras: <String, String>{
            'stalker.cmd': cmd,
            'stalker.id': id,
            if (m['number'] != null) 'stalker.number': m['number'].toString(),
            if (m['archive'] != null)
              'stalker.archive': m['archive'].toString(),
            if (m['tv_archive_duration'] != null)
              'stalker.archive_duration':
                  m['tv_archive_duration'].toString(),
          },
        ),
      );
    }
    return out;
  }

  /// All VOD items.
  ///
  /// Endpoint flow:
  ///   1. `type=vod&action=get_categories`
  ///   2. For each category: `type=vod&action=get_ordered_list&category=ID&p=1..N`
  Future<List<VodItem>> vodItems() async {
    await _ensureToken();
    final cats = await _vodCategories();
    final out = <VodItem>[];

    // Treat "*" as "all categories" too — many panels accept it.
    final iterable =
        cats.isEmpty ? <_StalkerCategory>[const _StalkerCategory(id: '*', title: '')] : cats;

    for (final cat in iterable) {
      var page = 1;
      while (page <= 50) {
        final body = await _tryGetJson(_api({
          'type': 'vod',
          'action': 'get_ordered_list',
          'category': cat.id,
          'p': '$page',
        }));
        final rows = _extractDataArray(body);
        if (rows == null || rows.isEmpty) break;
        out.addAll(_mapVodRows(rows, cat.title));
        if (rows.length < 14) break;
        page += 1;
      }
    }
    return out;
  }

  Future<List<_StalkerCategory>> _vodCategories() async {
    final body = await _tryGetJson(_api(const {
      'type': 'vod',
      'action': 'get_categories',
    }));
    final rows = _extractDataArray(body);
    if (rows == null) return const <_StalkerCategory>[];
    final out = <_StalkerCategory>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = m['id']?.toString();
      final title = (m['title'] as String?)?.trim() ?? '';
      if (id == null || id.isEmpty || title.isEmpty) continue;
      out.add(_StalkerCategory(id: id, title: title));
    }
    return out;
  }

  List<VodItem> _mapVodRows(List<dynamic> rows, String categoryTitle) {
    final out = <VodItem>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final title = (m['name'] as String?)?.trim() ??
          (m['o_name'] as String?)?.trim() ??
          'VOD $id';
      final cmd = (m['cmd'] as String?)?.trim() ?? '';
      final poster = (m['screenshot_uri'] as String?)?.trim() ??
          (m['cover'] as String?)?.trim() ??
          (m['logo'] as String?)?.trim();
      final year = _toInt(m['year']) ?? _yearFromString(m['year']);
      final ratingRaw =
          m['rating_imdb'] ?? m['rating_kinopoisk'] ?? m['rating'];
      final rating = _toDouble(ratingRaw);

      out.add(
        VodItem(
          id: '$_sourceId::vod::$id',
          sourceId: _sourceId,
          title: title,
          year: year,
          plot: (m['description'] as String?)?.trim(),
          posterUrl: (poster == null || poster.isEmpty) ? null : poster,
          rating: rating,
          streamUrl: streamUrlFromCmd(cmd, channelId: id, kind: 'vod'),
          containerExt: 'mp4',
          genres: <String>[
            if (categoryTitle.isNotEmpty) categoryTitle,
            if (m['genres_str'] is String &&
                (m['genres_str'] as String).trim().isNotEmpty)
              ...(m['genres_str'] as String)
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty),
          ],
        ),
      );
    }
    return out;
  }

  /// All series.
  Future<List<SeriesItem>> series() async {
    await _ensureToken();
    final cats = await _seriesCategories();
    final out = <SeriesItem>[];
    final iterable = cats.isEmpty
        ? <_StalkerCategory>[const _StalkerCategory(id: '*', title: '')]
        : cats;

    for (final cat in iterable) {
      var page = 1;
      while (page <= 50) {
        final body = await _tryGetJson(_api({
          'type': 'series',
          'action': 'get_ordered_list',
          'category': cat.id,
          'p': '$page',
        }));
        final rows = _extractDataArray(body);
        if (rows == null || rows.isEmpty) break;
        out.addAll(_mapSeriesRows(rows, cat.title));
        if (rows.length < 14) break;
        page += 1;
      }
    }
    return out;
  }

  Future<List<_StalkerCategory>> _seriesCategories() async {
    final body = await _tryGetJson(_api(const {
      'type': 'series',
      'action': 'get_categories',
    }));
    final rows = _extractDataArray(body);
    if (rows == null) return const <_StalkerCategory>[];
    final out = <_StalkerCategory>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = m['id']?.toString();
      final title = (m['title'] as String?)?.trim() ?? '';
      if (id == null || id.isEmpty || title.isEmpty) continue;
      out.add(_StalkerCategory(id: id, title: title));
    }
    return out;
  }

  List<SeriesItem> _mapSeriesRows(List<dynamic> rows, String categoryTitle) {
    final out = <SeriesItem>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final title = (m['name'] as String?)?.trim() ?? 'Series $id';
      final poster = (m['screenshot_uri'] as String?)?.trim() ??
          (m['cover'] as String?)?.trim();
      final year = _toInt(m['year']) ?? _yearFromString(m['year']);
      final rating = _toDouble(
        m['rating_imdb'] ?? m['rating_kinopoisk'] ?? m['rating'],
      );

      out.add(
        SeriesItem(
          id: '$_sourceId::series::$id',
          sourceId: _sourceId,
          title: title,
          plot: (m['description'] as String?)?.trim(),
          posterUrl: (poster == null || poster.isEmpty) ? null : poster,
          rating: rating,
          year: year,
          genres: <String>[
            if (categoryTitle.isNotEmpty) categoryTitle,
          ],
        ),
      );
    }
    return out;
  }

  /// Builds a playable URL for a Stalker `cmd` payload.
  ///
  /// Stalker `cmd` strings look like one of:
  ///   * `ffmpeg http://stream.example/live/123.ts`
  ///   * `ffrt http://stream.example/...`
  ///   * `auto http://stream.example/...`
  ///   * `/play/cmd?id=123` (relative — expand against the portal root)
  ///   * `http://stream.example/...` (already a URL)
  ///
  /// We strip the leading player tag and absolutise relative paths.
  String streamUrlFromCmd(
    String cmd, {
    required String channelId,
    String kind = 'live',
  }) {
    var s = cmd.trim();
    if (s.isEmpty) {
      // Synthesise a fallback /play/<id> URL the portal can usually
      // resolve; the player will fail loudly if it can't.
      return '$_portal/play/$kind/$channelId';
    }
    // Strip a leading "ffmpeg " / "ffrt " / "auto " / "mpeg2 " tag.
    final spaceIdx = s.indexOf(' ');
    if (spaceIdx > 0 && spaceIdx <= 8) {
      final prefix = s.substring(0, spaceIdx).toLowerCase();
      const tags = {'ffmpeg', 'ffrt', 'auto', 'mpeg2', 'live'};
      if (tags.contains(prefix)) {
        s = s.substring(spaceIdx + 1).trim();
      }
    }
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '$_portal$s';
    return '$_portal/$s';
  }

  // --- helpers --------------------------------------------------------------

  Future<void> _ensureToken() async {
    if (_token != null && _token!.isNotEmpty) return;
    await handshake();
  }

  /// Fetches JSON, returning `null` instead of throwing on transport
  /// failures. Some Stalker portals 404 unsupported actions instead of
  /// returning `{js:[]}` — this lets the caller fall through cleanly to
  /// alternative endpoints.
  Future<dynamic> _tryGetJson(Uri uri) async {
    try {
      return await _getJson(uri);
    } on StalkerAuthException {
      rethrow;
    } on Object catch (e) {
      _log.warn('stalker GET soft-failed: $e');
      return null;
    }
  }

  /// `{js: {data: [...]}}` is the canonical shape but some panels return
  /// `{js: [...]}` directly. Cover both.
  List<dynamic>? _extractDataArray(dynamic body) {
    if (body is! Map) return null;
    final js = body['js'];
    if (js is List) return js;
    if (js is Map) {
      final data = js['data'];
      if (data is List) return data;
      // Some forks wrap in `total_items` + numbered keys; fall through.
    }
    return null;
  }

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final resp = await _dio.getUri<dynamic>(
        uri,
        options: Options(headers: _headers()),
      );
      final code = resp.statusCode;
      if (code == 401 || code == 403) {
        throw const StalkerAuthException('Portal MAC adresimizi reddetti');
      }
      if (code == null || code < 200 || code >= 300) {
        throw NetworkException(
          'Stalker API returned status',
          statusCode: code,
          retryable: (code ?? 0) >= 500,
        );
      }
      return resp.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const StalkerAuthException('HTTP auth rejected');
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

  static int? _yearFromString(Object? v) {
    if (v is String) {
      final m = RegExp(r'(\d{4})').firstMatch(v);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }
}

class _StalkerCategory {
  const _StalkerCategory({required this.id, required this.title});
  final String id;
  final String title;
}
