import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lookup TMDB credits (cast + crew) for a single tmdb id.
///
/// Wraps `MetadataService.credits` which itself caches the response on
/// disk for 24 h via the `boxMetadata` Hive box. The provider keeps the
/// result alive for an hour after its last listener so that re-opening
/// the same detail screen within the session doesn't refetch from disk.
///
/// Returns `TmdbCredits.empty` when:
///   * `tmdbId` is `null` or `<= 0` (caller passes a sentinel)
///   * `Env.tmdbApiKey` is not configured
///   * the TMDB call fails — the metadata service swallows the error and
///     emits `TmdbCredits.empty` so the cast row simply hides itself.
///
/// Family parameter is the TMDB id; the keep-alive timer resets for each
/// distinct id so navigating between two films ages the previous family
/// member out independently.
final vodCreditsProvider =
    FutureProvider.autoDispose.family<TmdbCredits, int?>(
  (ref, tmdbId) async {
    // Hold the result for 1h after the listener disconnects — same-session
    // re-opens stay snappy without forcing the disk cache to be re-read.
    final keepAlive = ref.keepAlive();
    unawaited(
      Future<void>.delayed(const Duration(hours: 1)).then((_) {
        keepAlive.close();
      }),
    );

    if (tmdbId == null || tmdbId <= 0) return TmdbCredits.empty;
    if (!Env.hasTmdb) return TmdbCredits.empty;

    final svc = ref.watch(metadataServiceProvider);
    return svc.credits(tmdbId);
  },
);

/// TMDB `/movie/{id}/similar` lookup — returns up to 10 tmdb ids of
/// titles TMDB considers similar to `tmdbId`.
///
/// The detail screen merges these with the local genre-overlap scoring
/// (top 5 of each, deduped by tmdbId) so the row is populated even when
/// the user's catalogue is sparse. Returns an empty list when the TMDB
/// key is absent or the call fails — the screen falls back to its
/// existing local-only ranking.
final vodSimilarTmdbIdsProvider =
    FutureProvider.autoDispose.family<List<int>, int?>(
  (ref, tmdbId) async {
    final keepAlive = ref.keepAlive();
    unawaited(
      Future<void>.delayed(const Duration(hours: 1)).then((_) {
        keepAlive.close();
      }),
    );

    if (tmdbId == null || tmdbId <= 0) return const <int>[];
    if (!Env.hasTmdb) return const <int>[];

    final svc = ref.watch(metadataServiceProvider);
    return svc.similarTmdbIds(tmdbId);
  },
);
