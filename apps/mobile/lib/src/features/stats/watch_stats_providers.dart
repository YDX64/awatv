import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/stats/watch_stats_models.dart';
import 'package:awatv_mobile/src/features/stats/watch_stats_service.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'watch_stats_providers.g.dart';

/// Singleton [WatchStatsService] — keeps a stable identity so that
/// the screen's `FutureProvider` can re-run cheaply when the user
/// pulls to refresh. Lookups are routed back through the per-feature
/// "by id" providers so a freshly-installed playlist immediately
/// shows up in the leaderboards.
@Riverpod(keepAlive: true)
WatchStatsService watchStatsService(Ref ref) {
  return WatchStatsService(
    history: ref.watch(historyServiceProvider),
    channelLookup: (String id) => ref.read(channelByIdProvider(id).future),
    vodLookup: (String id) => ref.read(vodByIdProvider(id).future),
    seriesLookup: (String id) => ref.read(seriesByIdProvider(id).future),
  );
}

/// Aggregated watch-time summary. Computed on demand and re-runs only
/// when invalidated — the screen invalidates manually on pull-to-
/// refresh, and the bottom sheet invalidates after a "share" so the
/// next tap reflects any new history rows that landed mid-share.
@Riverpod(keepAlive: false)
Future<WatchStatsSummary> watchStatsSummary(Ref ref) async {
  final svc = ref.watch(watchStatsServiceProvider);
  return svc.compute();
}
