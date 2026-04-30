import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/watchlist/watchlist_toggle.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Series detail with seasons selector + episode list.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({required this.seriesId, super.key});

  final String seriesId;

  @override
  ConsumerState<SeriesDetailScreen> createState() =>
      _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int? _selectedSeason;

  Future<void> _onTrailer(BuildContext context, SeriesItem s) async {
    final messenger = ScaffoldMessenger.of(context);
    final tmdbId = s.tmdbId;
    if (tmdbId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fragman bulunamadi')),
      );
      return;
    }
    try {
      final youtubeId = await ref
          .read(metadataServiceProvider)
          .trailerYoutubeId(tmdbId, MediaType.series);
      if (youtubeId == null || youtubeId.isEmpty) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Fragman bulunamadi')),
        );
        return;
      }
      if (!context.mounted) return;
      unawaited(
        context.push(
          Uri(
            path: '/trailer/$youtubeId',
            queryParameters: <String, String>{'title': s.title},
          ).toString(),
        ),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fragman yüklenemedi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = ref.watch(seriesByIdProvider(widget.seriesId));

    return Scaffold(
      body: series.when(
        loading: () => const LoadingView(),
        error: (Object err, StackTrace st) =>
            ErrorView(message: err.toString()),
        data: (SeriesItem? s) {
          if (s == null) {
            return const EmptyState(
              icon: Icons.help_outline,
              title: 'Dizi bulunamadi',
            );
          }
          final season = _selectedSeason ??
              (s.seasons.isNotEmpty ? s.seasons.first : 1);

          final episodes = s.seasons.contains(season)
              ? ref.watch(seriesEpisodesProvider(s.id, season))
              : const AsyncValue<List<Episode>>.data(<Episode>[]);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (s.backdropUrl != null)
                        CachedNetworkImage(
                          imageUrl: s.backdropUrl!,
                          fit: BoxFit.cover,
                        )
                      else if (s.posterUrl != null)
                        CachedNetworkImage(
                          imageUrl: s.posterUrl!,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      const GradientScrim(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ],
                  ),
                  title: Text(
                    s.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spaceL),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.plot != null && s.plot!.isNotEmpty) ...[
                        Text(
                          s.plot!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: DesignTokens.spaceM),
                      ],
                      // Prominent play CTA — fires the first available
                      // episode of the currently-selected season. The user
                      // reported the series surface looked dead because the
                      // only play affordance lived inside each episode row;
                      // surfacing a top-level button here gives the screen a
                      // recognisable Netflix-style entry point.
                      _PlayFirstEpisodeButton(series: s, season: season),
                      const SizedBox(height: DesignTokens.spaceM),
                      Row(
                        children: <Widget>[
                          // Watchlist toggle (saat ikonu) — favoriden ayri
                          // "sonra izle" listesine ekle / cikar.
                          WatchlistToggleButton(
                            itemId: s.id,
                            kind: HistoryKind.series,
                            title: s.title,
                            posterUrl: s.posterUrl,
                            year: s.year,
                          ),
                          const SizedBox(width: DesignTokens.spaceM),
                          if (s.tmdbId != null)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.movie_filter_outlined),
                              label: const Text('Fragman'),
                              onPressed: () => _onTrailer(context, s),
                            ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spaceL),
                      if (s.seasons.length > 1) ...[
                        Row(
                          children: [
                            Text(
                              'Sezon',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(width: DesignTokens.spaceM),
                            DropdownButton<int>(
                              value: season,
                              items: [
                                for (final n in s.seasons)
                                  DropdownMenuItem<int>(
                                    value: n,
                                    child: Text('Sezon $n'),
                                  ),
                              ],
                              onChanged: (int? n) {
                                if (n != null) {
                                  setState(() => _selectedSeason = n);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spaceM),
                      ],
                    ],
                  ),
                ),
              ),
              episodes.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(DesignTokens.spaceL),
                    child: LoadingView(),
                  ),
                ),
                error: (Object err, StackTrace st) => SliverToBoxAdapter(
                  child: ErrorView(message: err.toString()),
                ),
                data: (List<Episode> eps) {
                  if (eps.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(DesignTokens.spaceL),
                        child: Text('Bu sezonda bolum yok.'),
                      ),
                    );
                  }
                  return SliverList.separated(
                    itemCount: eps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext ctx, int i) {
                      final ep = eps[i];
                      return _EpisodeTile(seriesTitle: s.title, episode: ep);
                    },
                  );
                },
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: DesignTokens.spaceXl),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Builds and pushes a /play route for one episode. Pulled out of the
/// tile / button widgets so the launch wiring lives in one place — the
/// "Ilk bolumu oynat" CTA, the per-row play button, and the row-tap all
/// share the same source-fallback shape.
void _launchEpisode(
  BuildContext context, {
  required String seriesTitle,
  required Episode episode,
}) {
  if (episode.streamUrl.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu bölüm için oynatma adresi yok.')),
    );
    return;
  }
  final epTitle = '$seriesTitle  S${episode.season}E${episode.number}';
  final urls = streamUrlVariants(episode.streamUrl).map(proxify).toList();
  final all = MediaSource.variants(urls, title: epTitle);
  final args = PlayerLaunchArgs(
    source: all.isEmpty
        ? MediaSource(url: proxify(episode.streamUrl), title: epTitle)
        : all.first,
    fallbacks:
        all.length <= 1 ? const <MediaSource>[] : all.sublist(1),
    title: epTitle,
    subtitle: episode.title,
    itemId: episode.id,
    kind: HistoryKind.series,
  );
  context.push('/play', extra: args);
}

/// Top-level "Ilk bolumu oynat" / "Devam et" CTA. Resolves the first
/// episode of [season] from [seriesEpisodesProvider], hands it to
/// [_launchEpisode]. Disabled while the episode list is loading or empty
/// so the button never lies — it only ever shows up clickable when
/// there's a real source to push.
class _PlayFirstEpisodeButton extends ConsumerWidget {
  const _PlayFirstEpisodeButton({
    required this.series,
    required this.season,
  });

  final SeriesItem series;
  final int season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(seriesEpisodesProvider(series.id, season));
    final eps = episodes.value ?? const <Episode>[];
    final loading = episodes.isLoading;
    final ready = !loading && eps.isNotEmpty;
    final first = ready ? eps.first : null;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(
          loading
              ? 'Yükleniyor…'
              : (first == null
                  ? 'Bölüm yok'
                  : 'Oynat: S${first.season}E${first.number}'),
        ),
        onPressed: first == null
            ? null
            : () => _launchEpisode(
                  context,
                  seriesTitle: series.title,
                  episode: first,
                ),
      ),
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({required this.seriesTitle, required this.episode});

  final String seriesTitle;
  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyServiceProvider);
    return FutureBuilder<Duration?>(
      future: history.resumeFor(episode.id),
      builder: (BuildContext ctx, AsyncSnapshot<Duration?> snap) {
        final resume = snap.data;
        final hasResume = resume != null && resume > Duration.zero;
        return ListTile(
          leading: CircleAvatar(
            child: Text('${episode.number}'),
          ),
          title: Text(
            episode.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: hasResume
              ? Text('Devam: ${_format(resume)}')
              : (episode.plot != null && episode.plot!.isNotEmpty
                  ? Text(
                      episode.plot!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null),
          // Explicit play affordance — was previously just a single
          // unlabelled icon, easy to miss. The IconButton has its own
          // tap target so the whole row still launches playback for
          // forgiving touch UX.
          trailing: IconButton(
            tooltip: hasResume ? 'Devam et' : 'Oynat',
            icon: Icon(
              hasResume ? Icons.replay_rounded : Icons.play_arrow_rounded,
            ),
            onPressed: () => _launchEpisode(
              context,
              seriesTitle: seriesTitle,
              episode: episode,
            ),
          ),
          onTap: () => _launchEpisode(
            context,
            seriesTitle: seriesTitle,
            episode: episode,
          ),
        );
      },
    );
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h}s ${m.toString().padLeft(2, '0')}d';
    }
    return '${m}d ${s.toString().padLeft(2, '0')}s';
  }
}
