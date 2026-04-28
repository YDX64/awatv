// Legacy Netflix-style row providers replaced by the category-tree home
// in v0.4. Kept around so any out-of-tree consumer still resolves; the
// internal cross-references (e.g. `heroSlotsProvider` -> the row
// providers) would otherwise trigger their own deprecation warnings.
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/home/home_row_item.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod providers that synthesise data for each row of the home
/// screen.
///
/// All providers return `AsyncValue<List<HomeRowItem>>` — the screen
/// renders a shimmer placeholder during `AsyncLoading`, hides itself
/// when data is empty, and swaps in cards once data lands.
///
/// We deliberately avoid `@riverpod` codegen here so the home rows can
/// ship without re-running build_runner.

const int _kHomeRowMax = 24;
const Duration _kRecencyWindow = Duration(days: 90);

/// Continue Watching — recent `HistoryEntry`s where `progress < 0.95`,
/// decorated with the originating VOD / Series / Channel object.
@Deprecated('Replaced by category-tree home in v0.4')
final continueWatchingProvider =
    FutureProvider<List<HomeRowItem>>((Ref ref) async {
  final history = ref.watch(historyServiceProvider);
  final entries = await history.recent(limit: 60);
  if (entries.isEmpty) return const <HomeRowItem>[];

  // Index VOD / Series / Channel by id once — `entries` may reference any
  // of the three buckets and we don't want N round-trips for N entries.
  final vodFuture = ref.watch(allVodProvider.future);
  final seriesFuture = ref.watch(allSeriesProvider.future);
  final channelsFuture = ref.watch(allChannelsProvider.future);
  final vod = await vodFuture;
  final series = await seriesFuture;
  final channels = await channelsFuture;

  final vodById = <String, VodItem>{for (final v in vod) v.id: v};
  final seriesById = <String, SeriesItem>{for (final s in series) s.id: s};
  final channelById = <String, Channel>{for (final c in channels) c.id: c};

  final out = <HomeRowItem>[];
  for (final e in entries) {
    final progress = _progressOf(e);
    if (progress >= 0.95) continue;

    switch (e.kind) {
      case HistoryKind.vod:
        final v = vodById[e.itemId];
        if (v != null) {
          out.add(MovieRowItem(vod: v, progress: progress));
        }
      case HistoryKind.series:
        // History.itemId for series points at an episode id of the form
        // "$seriesId::$season::$episode" — strip the trailing parts back
        // to the series so the row can show the series poster.
        final seriesId = _seriesIdFromEpisodeId(e.itemId);
        final s = seriesById[seriesId];
        if (s != null) {
          out.add(SeriesRowItem(series: s, progress: progress));
        }
      case HistoryKind.live:
        final c = channelById[e.itemId];
        if (c != null) {
          // Live progress doesn't really apply but we surface the resume
          // anyway so users can quickly tap back into a channel they
          // were watching.
          out.add(ChannelRowItem(channel: c, progress: progress));
        }
    }
    if (out.length >= _kHomeRowMax) break;
  }
  return out;
});

double _progressOf(HistoryEntry e) {
  final total = e.total.inSeconds;
  if (total <= 0) return 0;
  return (e.position.inSeconds / total).clamp(0.0, 1.0);
}

String _seriesIdFromEpisodeId(String itemId) {
  // Episode id format: "$seriesId::$season::$episode"; series id format:
  // "$sourceId::$xtreamSeriesId". We want the first two `::`-segments.
  final parts = itemId.split('::');
  if (parts.length <= 2) return itemId;
  return '${parts[0]}::${parts[1]}';
}

/// Trending — channels that are currently live and have an EPG programme
/// airing whose category/title hints at trending topics. Falls back to
/// "first 24 live channels" when no EPG is available so the row never
/// reads as empty for a brand-new install.
@Deprecated('Replaced by category-tree home in v0.4')
final trendingNowProvider =
    FutureProvider<List<HomeRowItem>>((Ref ref) async {
  final channels = await ref.watch(liveChannelsProvider.future);
  if (channels.isEmpty) return const <HomeRowItem>[];

  final epg = ref.watch(epgServiceProvider);
  final now = DateTime.now();

  final scored = <_ScoredChannel>[];
  for (final c in channels) {
    final tvgId = c.tvgId;
    EpgProgramme? current;
    if (tvgId != null && tvgId.isNotEmpty) {
      try {
        final list = await epg.programmesFor(tvgId, around: now);
        for (final p in list) {
          if (p.start.isBefore(now) && p.stop.isAfter(now)) {
            current = p;
            break;
          }
        }
      } on Exception {
        // EPG miss is fine — we just won't have a subtitle.
      }
    }
    scored.add(
      _ScoredChannel(
        channel: c,
        current: current,
        score: _trendingScore(c, current),
      ),
    );
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored
      .take(_kHomeRowMax)
      .map<HomeRowItem>(
        (s) => ChannelRowItem(channel: s.channel, currentProgramme: s.current),
      )
      .toList(growable: false);
});

class _ScoredChannel {
  _ScoredChannel({
    required this.channel,
    required this.current,
    required this.score,
  });

  final Channel channel;
  final EpgProgramme? current;
  final int score;
}

const Set<String> _kTrendingKeywords = <String>{
  'trending',
  'breaking',
  'live',
  'final',
  'finale',
  'premiere',
  'premier',
  'derby',
  'derbi',
  'sport',
  'spor',
  'futbol',
  'super lig',
  'champions',
  'world cup',
  'bundesliga',
  'la liga',
  'haber',
};

int _trendingScore(Channel c, EpgProgramme? current) {
  var score = 0;
  if (current != null) {
    score += 10; // Has live programme info at all -> floor of 10.
    final hay = '${current.title} ${current.description ?? ''} '
            '${current.category ?? ''}'
        .toLowerCase();
    for (final kw in _kTrendingKeywords) {
      if (hay.contains(kw)) {
        score += 5;
      }
    }
  }
  // Boost channels whose group hints at sports/news (the categories that
  // tend to be "trending" on linear TV).
  for (final g in c.groups) {
    final gl = g.toLowerCase();
    if (gl.contains('spor') ||
        gl.contains('sport') ||
        gl.contains('news') ||
        gl.contains('haber')) {
      score += 3;
    }
  }
  // Tiebreak deterministically by id so the row order is stable across
  // rebuilds when scores are equal.
  return score + (c.id.hashCode & 0x7);
}

/// New movies — VOD items whose TMDB `releaseDate` is within the last 90
/// days, sorted by date desc. Falls back to the most recently parsed VOD
/// (no enrichment) so we still show *something* when no TMDB key is set.
@Deprecated('Replaced by category-tree home in v0.4')
final newMoviesProvider = FutureProvider<List<HomeRowItem>>((Ref ref) async {
  final vod = await ref.watch(allVodProvider.future);
  if (vod.isEmpty) return const <HomeRowItem>[];

  final now = DateTime.now();
  final cutoff = now.subtract(_kRecencyWindow);

  final withRelease = <_DatedVod>[];
  for (final v in vod) {
    final release = await _resolveMovieReleaseDate(ref, v);
    if (release != null && release.isAfter(cutoff) && !release.isAfter(now)) {
      withRelease.add(_DatedVod(v, release));
    }
  }
  if (withRelease.isNotEmpty) {
    withRelease.sort((a, b) => b.date.compareTo(a.date));
    return withRelease
        .take(_kHomeRowMax)
        .map<HomeRowItem>((d) => MovieRowItem(vod: d.vod))
        .toList(growable: false);
  }

  // No release-date metadata at all — fall back to "by year, desc". Year
  // alone isn't precise enough to filter to "last 90 days" but it does
  // give a useful "newest in the catalog" surface.
  final byYear = vod.toList()
    ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
  return byYear
      .take(_kHomeRowMax)
      .map<HomeRowItem>((v) => MovieRowItem(vod: v))
      .toList(growable: false);
});

class _DatedVod {
  _DatedVod(this.vod, this.date);
  final VodItem vod;
  final DateTime date;
}

class _DatedSeries {
  _DatedSeries(this.series, this.date);
  final SeriesItem series;
  final DateTime date;
}

Future<DateTime?> _resolveMovieReleaseDate(Ref ref, VodItem v) async {
  // Provider may already carry a year — synthesise a January-1 date so
  // the cutoff still applies.
  if (v.year != null) {
    return DateTime(v.year!);
  }
  // Try the cached TMDB metadata next (no network if it's already there).
  final meta = ref.read(metadataServiceProvider);
  try {
    final m = await meta.movieByTitle(v.title);
    return m?.releaseDate;
  } on Exception {
    return null;
  }
}

Future<DateTime?> _resolveSeriesReleaseDate(Ref ref, SeriesItem s) async {
  if (s.year != null) {
    return DateTime(s.year!);
  }
  final meta = ref.read(metadataServiceProvider);
  try {
    final m = await meta.seriesByTitle(s.title);
    return m?.releaseDate;
  } on Exception {
    return null;
  }
}

/// New series — same shape as new movies.
@Deprecated('Replaced by category-tree home in v0.4')
final newSeriesProvider = FutureProvider<List<HomeRowItem>>((Ref ref) async {
  final series = await ref.watch(allSeriesProvider.future);
  if (series.isEmpty) return const <HomeRowItem>[];

  final now = DateTime.now();
  final cutoff = now.subtract(_kRecencyWindow);

  final withRelease = <_DatedSeries>[];
  for (final s in series) {
    final release = await _resolveSeriesReleaseDate(ref, s);
    if (release != null && release.isAfter(cutoff) && !release.isAfter(now)) {
      withRelease.add(_DatedSeries(s, release));
    }
  }
  if (withRelease.isNotEmpty) {
    withRelease.sort((a, b) => b.date.compareTo(a.date));
    return withRelease
        .take(_kHomeRowMax)
        .map<HomeRowItem>((d) => SeriesRowItem(series: d.series))
        .toList(growable: false);
  }

  final byYear = series.toList()
    ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
  return byYear
      .take(_kHomeRowMax)
      .map<HomeRowItem>((s) => SeriesRowItem(series: s))
      .toList(growable: false);
});

/// Favorites — surfaces all favorited channels/movies/series as a row.
@Deprecated('Replaced by category-tree home in v0.4')
final homeFavoritesProvider =
    StreamProvider<List<HomeRowItem>>((Ref ref) async* {
  final favs = ref.watch(favoritesServiceProvider);
  // Initial snapshot of catalogues — we re-resolve them every time the
  // favorites set changes (cheap, all in-memory).
  await for (final ids in favs.watch()) {
    if (ids.isEmpty) {
      yield const <HomeRowItem>[];
      continue;
    }
    final channels = await ref.read(allChannelsProvider.future);
    final vod = await ref.read(allVodProvider.future);
    final series = await ref.read(allSeriesProvider.future);

    final byChannelId = <String, Channel>{for (final c in channels) c.id: c};
    final byVodId = <String, VodItem>{for (final v in vod) v.id: v};
    final bySeriesId = <String, SeriesItem>{for (final s in series) s.id: s};

    final out = <HomeRowItem>[];
    for (final id in ids) {
      final v = byVodId[id];
      if (v != null) {
        out.add(MovieRowItem(vod: v));
        continue;
      }
      final s = bySeriesId[id];
      if (s != null) {
        out.add(SeriesRowItem(series: s));
        continue;
      }
      final c = byChannelId[id];
      if (c != null) {
        out.add(ChannelRowItem(channel: c));
      }
    }
    yield out.take(_kHomeRowMax).toList(growable: false);
  }
});

/// Editor's Picks — TMDB "discover" call mixing top-rated movies and
/// series. Premium feature: we still build the request when the user is
/// free, but we emit an empty list so the home screen hides the row
/// (rather than rendering a tease the user can't tap).
@Deprecated('Replaced by category-tree home in v0.4')
final editorsPicksProvider =
    FutureProvider<List<HomeRowItem>>((Ref ref) async {
  // No TMDB key -> no editor's picks at all.
  if (!Env.hasTmdb) return const <HomeRowItem>[];

  // Free tier sees the row gated behind a PRO badge but with no items —
  // the screen rendering layer is in charge of the badge UI.
  final isPremium = ref.watch(canUseFeatureProvider(PremiumFeature.cloudSync));
  if (!isPremium) return const <HomeRowItem>[];

  final dio = ref.watch(dioProvider);
  final movies = await _tmdbDiscover(dio, kind: MediaType.movie);
  final series = await _tmdbDiscover(dio, kind: MediaType.series);
  // Interleave movies + series so the row doesn't read as "all movies
  // then all series" — keeps the surface visually varied.
  final results = <HomeRowItem>[...movies, ...series]..shuffle();
  return results.take(_kHomeRowMax).toList(growable: false);
});

Future<List<HomeRowItem>> _tmdbDiscover(
  Dio dio, {
  required MediaType kind,
}) async {
  final endpoint = kind == MediaType.movie ? '/discover/movie' : '/discover/tv';
  try {
    final resp = await dio.get<dynamic>(
      'https://api.themoviedb.org/3$endpoint',
      queryParameters: <String, dynamic>{
        'api_key': Env.tmdbApiKey,
        'language': 'en-US',
        'sort_by': 'vote_average.desc',
        'include_adult': 'false',
        'vote_count.gte': 200,
        'page': 1,
      },
    );
    final data = resp.data;
    if (data is! Map) return const <HomeRowItem>[];
    final list = data['results'];
    if (list is! List) return const <HomeRowItem>[];

    final out = <HomeRowItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final id = (m['id'] as num?)?.toInt();
      if (id == null) continue;
      final title = (m[kind == MediaType.movie ? 'title' : 'name']
              as String?)
          ?.trim();
      if (title == null || title.isEmpty) continue;
      final overview = (m['overview'] as String?)?.trim();
      final rating = (m['vote_average'] as num?)?.toDouble();
      final dateStr = (m[kind == MediaType.movie
              ? 'release_date'
              : 'first_air_date'] as String?) ??
          '';
      final date = DateTime.tryParse(dateStr);
      out.add(
        EditorsPickItem(
          tmdbId: id,
          kind: kind,
          title: title,
          posterUrl: TmdbClient.posterUrl(m['poster_path'] as String?),
          backdropUrl: TmdbClient.backdropUrl(m['backdrop_path'] as String?),
          year: date?.year,
          rating: rating,
          plot: overview,
        ),
      );
    }
    return out;
  } on Exception {
    // TMDB outages should not bring down the home screen — a swallowed
    // failure here just hides the row.
    return const <HomeRowItem>[];
  }
}

/// Whether the user has any data to show at all. Used to decide between
/// "render rows" and "show onboarding hint".
@Deprecated('Replaced by category-tree home in v0.4')
final homeHasAnyDataProvider = FutureProvider<bool>((Ref ref) async {
  final vod = await ref.watch(allVodProvider.future);
  if (vod.isNotEmpty) return true;
  final series = await ref.watch(allSeriesProvider.future);
  if (series.isNotEmpty) return true;
  final channels = await ref.watch(allChannelsProvider.future);
  return channels.isNotEmpty;
});

/// Hero carousel feed — up to 5 slots picked from continue-watching first,
/// then editor's picks, then most recent VOD/series. Always returns 0..5.
@Deprecated('Replaced by category-tree home in v0.4')
final heroSlotsProvider = FutureProvider<List<HomeRowItem>>((Ref ref) async {
  const max = 5;
  final out = <HomeRowItem>[];
  final seen = <String>{};

  void addAll(List<HomeRowItem> src) {
    for (final i in src) {
      if (out.length >= max) return;
      // Skip items without a backdrop or poster — the hero carousel needs
      // either to render properly.
      if ((i.backdropUrl == null || i.backdropUrl!.isEmpty) &&
          (i.posterUrl == null || i.posterUrl!.isEmpty)) {
        continue;
      }
      if (seen.add(i.id)) out.add(i);
    }
  }

  addAll(await ref.watch(continueWatchingProvider.future));
  addAll(await ref.watch(editorsPicksProvider.future));
  addAll(await ref.watch(newMoviesProvider.future));
  addAll(await ref.watch(newSeriesProvider.future));

  return out;
});
