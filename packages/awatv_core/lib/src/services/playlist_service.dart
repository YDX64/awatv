import 'dart:async';

import 'package:awatv_core/src/clients/xtream_client.dart';
import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/episode.dart';
import 'package:awatv_core/src/models/playlist_source.dart';
import 'package:awatv_core/src/models/series_item.dart';
import 'package:awatv_core/src/models/tmdb_models.dart';
import 'package:awatv_core/src/models/vod_item.dart';
import 'package:awatv_core/src/parsers/m3u_parser.dart';
import 'package:awatv_core/src/services/metadata_service.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Coordinates downloading, parsing, and persisting playlists. Triggers
/// metadata enrichment as a fire-and-forget background task.
class PlaylistService {
  PlaylistService({
    required AwatvStorage storage,
    required Dio dio,
    MetadataService? metadata,
  })  : _storage = storage,
        _dio = dio,
        _metadata = metadata;

  final AwatvStorage _storage;
  final Dio _dio;
  final MetadataService? _metadata;

  static final AwatvLogger _log = AwatvLogger(tag: 'PlaylistService');

  /// Add a playlist source. Persists, then runs the first refresh.
  ///
  /// On Xtream, also runs metadata enrichment in the background.
  Future<PlaylistSource> add(PlaylistSource src) async {
    await _storage.putSource(src);
    await refresh(src.id);
    return src.copyWith(lastSyncAt: DateTime.now().toUtc());
  }

  /// (Re-)pull the source. For Xtream: hits API and replaces the channels
  /// box. For M3U: downloads body and re-parses.
  Future<void> refresh(String sourceId) async {
    final src = await _storage.getSource(sourceId);
    if (src == null) {
      throw StorageException('Unknown source $sourceId');
    }

    switch (src.kind) {
      case PlaylistKind.m3u:
        await _refreshM3u(src);
      case PlaylistKind.xtream:
        await _refreshXtream(src);
    }

    final updated = src.copyWith(lastSyncAt: DateTime.now().toUtc());
    await _storage.putSource(updated);
  }

  Future<List<PlaylistSource>> list() => _storage.listSources();

  Future<void> remove(String sourceId) => _storage.deleteSource(sourceId);

  /// Reactive view onto channels for a source.
  Stream<List<Channel>> watchChannels(String sourceId) {
    return _storage.watchChannels(sourceId);
  }

  /// Snapshot of channels for one source (no reactive stream).
  Future<List<Channel>> channels(String sourceId) =>
      _storage.listChannels(sourceId);

  /// Snapshot of VOD items persisted for [sourceId].
  Future<List<VodItem>> vodItems(String sourceId) =>
      _storage.listVod(sourceId);

  /// Snapshot of series items persisted for [sourceId].
  Future<List<SeriesItem>> series(String sourceId) =>
      _storage.listSeries(sourceId);

  /// Episodes for a given series + season number. Currently only Xtream
  /// sources can resolve episodes — M3U doesn't carry per-episode metadata.
  Future<List<Episode>> episodes(String seriesId, int season) async {
    final sources = await list();
    for (final src in sources) {
      if (src.kind != PlaylistKind.xtream) continue;
      if (src.username == null || src.password == null) continue;

      final allSeries = await _storage.listSeries(src.id);
      final match = allSeries
          .where((SeriesItem s) => s.id == seriesId)
          .cast<SeriesItem?>()
          .firstWhere(
            (SeriesItem? _) => true,
            orElse: () => null,
          );
      if (match == null) continue;

      // Series id format: "$sourceId::$xtreamSeriesId" (set in xtream_client).
      // Fall back to raw int parse for other shapes.
      final raw = seriesId.contains('::')
          ? seriesId.split('::').last
          : seriesId;
      final xtreamId = int.tryParse(raw);
      if (xtreamId == null) continue;

      final client = XtreamClient(
        server: src.url,
        username: src.username!,
        password: src.password!,
        dio: _dio,
      );
      final all = await client.seriesEpisodes(xtreamId);
      return all.where((Episode e) => e.season == season).toList();
    }
    return const <Episode>[];
  }

  // -- internal --------------------------------------------------------------

  Future<void> _refreshM3u(PlaylistSource src) async {
    final body = await _downloadString(src.url);
    final channels = M3uParser.parse(body, src.id);
    await _storage.putChannels(src.id, channels);
    _log.info('M3U ${src.name}: ${channels.length} channels');
  }

  Future<void> _refreshXtream(PlaylistSource src) async {
    final user = src.username;
    final pass = src.password;
    if (user == null || pass == null) {
      throw const XtreamAuthException('Xtream source missing credentials');
    }

    final client = XtreamClient(
      server: src.url,
      username: user,
      password: pass,
      dio: _dio,
    );

    await client.authenticate();

    final live = await client.liveChannels();
    await _storage.putChannels(src.id, live);

    final vod = await client.vodItems();
    await _storage.putVod(src.id, vod);

    final series = await client.series();
    await _storage.putSeries(src.id, series);

    _log.info(
      'Xtream ${src.name}: ${live.length} live, ${vod.length} VOD, '
      '${series.length} series',
    );

    final meta = _metadata;
    if (meta != null) {
      // Background enrichment — do not block return.
      unawaited(_enrich(meta, vod.map((v) => v.title).toList(), MediaType.movie));
      unawaited(
        _enrich(meta, series.map((s) => s.title).toList(), MediaType.series),
      );
    }
  }

  Future<void> _enrich(
    MetadataService meta,
    List<String> titles,
    MediaType kind,
  ) async {
    for (final title in titles) {
      try {
        if (kind == MediaType.movie) {
          await meta.movieByTitle(title);
        } else {
          await meta.seriesByTitle(title);
        }
      } on Exception catch (e) {
        _log.warn('metadata enrichment failed for $title: $e');
      }
    }
  }

  Future<String> _downloadString(String url) async {
    try {
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'application/x-mpegurl,*/*'},
        ),
      );
      final code = resp.statusCode;
      if (code == null || code < 200 || code >= 300) {
        throw NetworkException(
          'Playlist download failed',
          statusCode: code,
          retryable: (code ?? 0) >= 500,
        );
      }
      return (resp.data ?? '').toString();
    } on DioException catch (e) {
      throw NetworkException(
        e.message ?? 'Playlist download failed',
        statusCode: e.response?.statusCode,
        retryable: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout,
      );
    }
  }
}
