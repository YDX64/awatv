import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/service_providers.dart';
import '../playlists/playlist_providers.dart';

part 'series_providers.g.dart';

/// All series, merged across sources.
@Riverpod(keepAlive: true)
Future<List<SeriesItem>> allSeries(Ref ref) async {
  final sources = await ref.watch(playlistsProvider.future);
  final svc = ref.watch(playlistServiceProvider);
  final out = <SeriesItem>[];
  for (final s in sources) {
    final list = await svc.series(s.id);
    out.addAll(list);
  }
  return out;
}

@Riverpod(keepAlive: false)
Future<SeriesItem?> seriesById(Ref ref, String id) async {
  final all = await ref.watch(allSeriesProvider.future);
  for (final s in all) {
    if (s.id == id) return s;
  }
  return null;
}

/// Episodes for a given series + season number.
@Riverpod(keepAlive: false)
Future<List<Episode>> seriesEpisodes(
  Ref ref,
  String seriesId,
  int season,
) async {
  final svc = ref.watch(playlistServiceProvider);
  return svc.episodes(seriesId, season);
}
