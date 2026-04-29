import 'package:awatv_core/src/clients/xtream_client.dart';
import 'package:awatv_core/src/models/catchup_programme.dart';
import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/models/playlist_source.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Resolves catchup / archive playback for live channels.
///
/// Backed by Xtream `get_simple_data_table` (which lists past programmes
/// with `has_archive` flags) and the `/timeshift/...` URL pattern.
///
/// Stalker / Ministra portal catchup is deferred to a future wave;
/// the service surface stays the same, only the wiring for non-Xtream
/// sources is missing.
class CatchupService {
  CatchupService({
    required AwatvStorage storage,
    required Dio dio,
  })  : _storage = storage,
        _dio = dio;

  final AwatvStorage _storage;
  final Dio _dio;

  static final AwatvLogger _log = AwatvLogger(tag: 'CatchupService');

  /// Catchup programmes for [channel]. Returns an empty list for
  /// non-Xtream sources or when the panel doesn't expose archive data.
  ///
  /// The Xtream `get_simple_data_table` endpoint accepts a numeric
  /// `stream_id`. We extract that from the channel id by scanning the
  /// trailing component of the composite id (e.g. `xtream:foo@host::123`
  /// → `123`).
  Future<List<CatchupProgramme>> programmesFor(Channel channel) async {
    final source = await _resolveXtreamSource(channel);
    if (source == null) return const <CatchupProgramme>[];
    final streamId = _extractStreamId(channel);
    if (streamId == null) return const <CatchupProgramme>[];

    try {
      final client = XtreamClient(
        server: source.url,
        username: source.username!,
        password: source.password!,
        dio: _dio,
      );
      return await client.catchupForChannel(streamId);
    } on Object catch (e, st) {
      _log.warn('catchup fetch failed for ${channel.id}: $e\n$st');
      return const <CatchupProgramme>[];
    }
  }

  /// Build the catchup URL for an [EpgProgramme] on [channel].
  /// Returns null when the channel can't be played back via timeshift
  /// (non-Xtream source, missing credentials, unparseable id).
  Future<String?> urlForEpg(Channel channel, EpgProgramme programme) async {
    final source = await _resolveXtreamSource(channel);
    if (source == null) return null;
    final streamId = _extractStreamId(channel);
    if (streamId == null) return null;
    final client = XtreamClient(
      server: source.url,
      username: source.username!,
      password: source.password!,
      dio: _dio,
    );
    return client.catchupUrl(
      streamId: streamId,
      start: programme.start,
      duration: programme.stop.difference(programme.start),
    );
  }

  /// Build the catchup URL for a [CatchupProgramme] (the same channel
  /// that produced it).
  Future<String?> urlForCatchup(
    Channel channel,
    CatchupProgramme programme,
  ) async {
    final source = await _resolveXtreamSource(channel);
    if (source == null) return null;
    final client = XtreamClient(
      server: source.url,
      username: source.username!,
      password: source.password!,
      dio: _dio,
    );
    return client.catchupUrl(
      streamId: programme.streamId,
      start: programme.start,
      duration: programme.stop.difference(programme.start),
    );
  }

  /// Channels (across all Xtream sources) whose source supports
  /// catchup. We optimistically include every Xtream channel — the
  /// final `has_archive` flag comes back per programme from
  /// `get_simple_data_table`. Calling this before that round-trip lets
  /// the UI render the full list without an n+1 fetch.
  Future<List<Channel>> channelsWithCatchup() async {
    final sources = await _storage.listSources();
    final out = <Channel>[];
    for (final src in sources) {
      if (src.kind != PlaylistKind.xtream) continue;
      if (src.username == null || src.password == null) continue;
      final channels = await _storage.listChannels(src.id);
      for (final ch in channels) {
        if (ch.kind != ChannelKind.live) continue;
        out.add(ch);
      }
    }
    return out;
  }

  /// Lookup the Xtream source backing [channel]. Returns null when the
  /// channel was imported from an M3U or when the source is missing
  /// credentials.
  Future<PlaylistSource?> _resolveXtreamSource(Channel channel) async {
    final src = await _storage.getSource(channel.sourceId);
    if (src == null) return null;
    if (src.kind != PlaylistKind.xtream) return null;
    if (src.username == null || src.password == null) return null;
    return src;
  }

  /// Channel ids carry `${sourceId}::${tvgId ?? streamId ?? name}` —
  /// when the trailing token is a number, that's the Xtream `stream_id`
  /// we need for the timeshift URL.
  int? _extractStreamId(Channel channel) {
    final parts = channel.id.split('::');
    if (parts.isEmpty) return null;
    final tail = parts.last;
    return int.tryParse(tail);
  }
}
