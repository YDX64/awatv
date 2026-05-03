import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/group_filter_chips.dart';
import 'package:awatv_mobile/src/features/channels/sort_mode_provider.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/breakpoints/breakpoints.dart';
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

/// Series listing.
///
/// Top: chip strip filtering by genre with multi-select + persistence.
/// AppBar: sort menu (8 modes covering year + rating + alphabetical).
///
/// Adaptive layout:
///   * **phone** (<600 dp) — single-column poster grid with the genre
///     chip strip pinned at the top.
///   * **tablet** (>=600 dp) — 40 / 60 master/detail. Left pane lists
///     series with poster thumbnails, right pane shows the selected
///     series detail (header + seasons + inline episode list) so the
///     user can hop between series without losing context. Filter +
///     sort still apply to the master list.
class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(allSeriesProvider);
    final filter = ref.watch(groupFilterProvider(SortSurface.series));
    final mode = ref.watch(sortModeProvider(SortSurface.series));
    final deviceClass = deviceClassFor(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diziler'),
        actions: const <Widget>[
          SortModeButton(surface: SortSurface.series),
        ],
      ),
      body: series.when(
        loading: () => const LoadingView(label: 'Diziler yukleniyor'),
        error: (Object err, StackTrace st) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(allSeriesProvider),
        ),
        data: (List<SeriesItem> items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Dizi yok',
              message: 'Senkronladigin listede dizi bulunamadi.',
            );
          }
          final genres = _genres(items);
          final filtered = _filter(items, filter, mode);
          // Pick a "featured" series — same logic as Movies. Hero uses
          // a gold "TV SHOWS" badge per Streas spec § 5.
          final hero = items.firstWhere(
            (SeriesItem s) =>
                (s.backdropUrl?.isNotEmpty ?? false) ||
                (s.posterUrl?.isNotEmpty ?? false),
            orElse: () => items.first,
          );
          if (deviceClass.isTablet) {
            // Tablet master/detail keeps its existing 40/60 layout —
            // hero only paints on the phone form factor where the user
            // sees one column at a time.
            return Column(
              children: <Widget>[
                GroupFilterChips(
                  surface: SortSurface.series,
                  groups: genres,
                  counts: _countByGroup(items, genres),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.video_library_outlined,
                          title: 'Bu filtreye uyan dizi yok',
                          message: 'Farkli bir tur deneyin.',
                        )
                      : _SeriesTabletLayout(items: filtered),
                ),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allSeriesProvider);
              await ref.read(allSeriesProvider.future);
            },
            child: CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _SeriesHero(
                    item: hero,
                    onPlay: () => context.push('/series/${hero.id}'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: GroupFilterChips(
                    surface: SortSurface.series,
                    groups: genres,
                    counts: _countByGroup(items, genres),
                  ),
                ),
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.video_library_outlined,
                      title: 'Bu filtreye uyan dizi yok',
                      message: 'Farkli bir tur deneyin.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(DesignTokens.spaceM),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _colsFor(
                          MediaQuery.sizeOf(context).width,
                        ),
                        crossAxisSpacing: DesignTokens.spaceM,
                        mainAxisSpacing: DesignTokens.spaceM,
                        childAspectRatio: DesignTokens.posterAspect,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (BuildContext ctx, int i) {
                        final s = filtered[i];
                        return PosterCard(
                          title: s.title,
                          posterUrl: s.posterUrl,
                          year: s.year,
                          rating: s.rating,
                          onTap: () => context.push('/series/${s.id}'),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _colsFor(double width) {
    if (width > 1100) return 6;
    if (width > 800) return 5;
    if (width > 600) return 4;
    return 3;
  }

  List<String> _genres(List<SeriesItem> items) {
    final set = <String>{};
    for (final s in items) {
      for (final g in s.genres) {
        final t = g.trim();
        if (t.isNotEmpty) set.add(t);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  Map<String, int> _countByGroup(List<SeriesItem> items, List<String> groups) {
    final out = <String, int>{};
    for (final g in groups) {
      out[g] = items.where((SeriesItem s) => s.genres.contains(g)).length;
    }
    return out;
  }

  List<SeriesItem> _filter(
    List<SeriesItem> all,
    GroupFilterState filter,
    SortMode mode,
  ) {
    final scoped = filter.selected.isEmpty
        ? all
        : all
            .where((SeriesItem s) =>
                s.genres.any((String g) => filter.selected.contains(g)))
            .toList();
    return mode.sortSeries(scoped);
  }
}

// Phone single-column grid was removed — its responsibilities are now
// served by the `CustomScrollView` slivers in `SeriesScreen.build` that
// host the cinematic hero, genre chips and poster grid as one scroll
// surface.

/// Tablet 40 / 60 master + detail layout.
///
/// Left pane: scrollable list of series tiles (poster thumb + title +
/// year/season count). Tapping a row updates the right pane in place
/// — the user never leaves the screen. A "Tum sayfa" affordance in the
/// detail pane navigates to the full /series/:id detail when they want
/// the immersive backdrop.
class _SeriesTabletLayout extends ConsumerStatefulWidget {
  const _SeriesTabletLayout({required this.items});

  final List<SeriesItem> items;

  @override
  ConsumerState<_SeriesTabletLayout> createState() =>
      _SeriesTabletLayoutState();
}

class _SeriesTabletLayoutState extends ConsumerState<_SeriesTabletLayout> {
  String? _selectedId;
  int? _selectedSeason;

  @override
  Widget build(BuildContext context) {
    // Pick the active series — first time-through grabs the head of
    // the filtered list; subsequent state changes lock onto the user's
    // pick. If the filter culled the previously-selected series, fall
    // back to the head again.
    final selectedId = _selectedId != null &&
            widget.items.any((SeriesItem s) => s.id == _selectedId)
        ? _selectedId!
        : widget.items.first.id;
    final selected =
        widget.items.firstWhere((SeriesItem s) => s.id == selectedId);

    return Row(
      children: <Widget>[
        SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.4,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allSeriesProvider);
              await ref.read(allSeriesProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spaceS,
              ),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext _, int i) {
                final s = widget.items[i];
                final isActive = s.id == selectedId;
                return _SeriesListTile(
                  series: s,
                  active: isActive,
                  onTap: () => setState(() {
                    _selectedId = s.id;
                    _selectedSeason = null;
                  }),
                );
              },
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _SeriesDetailPane(
            series: selected,
            season: _selectedSeason,
            onSeasonChanged: (int n) =>
                setState(() => _selectedSeason = n),
          ),
        ),
      ],
    );
  }
}

class _SeriesListTile extends StatelessWidget {
  const _SeriesListTile({
    required this.series,
    required this.active,
    required this.onTap,
  });

  final SeriesItem series;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: active,
      selectedTileColor: scheme.primary.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceXs,
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        child: SizedBox(
          width: 48,
          height: 64,
          child: series.posterUrl == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: const Icon(Icons.video_library_outlined),
                )
              : CachedNetworkImage(
                  imageUrl: series.posterUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
        ),
      ),
      title: Text(
        series.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        <String>[
          if (series.year != null) '${series.year}',
          if (series.seasons.isNotEmpty)
            '${series.seasons.length} sezon',
        ].join(' • '),
      ),
      trailing: active
          ? Icon(Icons.chevron_right_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _SeriesDetailPane extends ConsumerWidget {
  const _SeriesDetailPane({
    required this.series,
    required this.season,
    required this.onSeasonChanged,
  });

  final SeriesItem series;

  /// `null` = "use the first season the series declares". Setting it
  /// in the parent overrides the default.
  final int? season;

  final ValueChanged<int> onSeasonChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeSeason = season ??
        (series.seasons.isNotEmpty ? series.seasons.first : 1);
    final episodes = series.seasons.contains(activeSeason)
        ? ref.watch(seriesEpisodesProvider(series.id, activeSeason))
        : const AsyncValue<List<Episode>>.data(<Episode>[]);

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _SeriesDetailHeader(series: series)),
        if (series.seasons.length > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceL,
                DesignTokens.spaceM,
                DesignTokens.spaceL,
                DesignTokens.spaceS,
              ),
              child: Row(
                children: <Widget>[
                  Text('Sezon', style: theme.textTheme.titleMedium),
                  const SizedBox(width: DesignTokens.spaceM),
                  DropdownButton<int>(
                    value: activeSeason,
                    items: <DropdownMenuItem<int>>[
                      for (final n in series.seasons)
                        DropdownMenuItem<int>(
                          value: n,
                          child: Text('Sezon $n'),
                        ),
                    ],
                    onChanged: (int? n) {
                      if (n != null) onSeasonChanged(n);
                    },
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    onPressed: () => context.push('/series/${series.id}'),
                    label: const Text('Tum sayfa'),
                  ),
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
          error: (Object err, StackTrace _) => SliverToBoxAdapter(
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
              itemBuilder: (BuildContext _, int i) =>
                  _EpisodeRow(seriesTitle: series.title, episode: eps[i]),
            );
          },
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: DesignTokens.spaceXl),
        ),
      ],
    );
  }
}

class _SeriesDetailHeader extends StatelessWidget {
  const _SeriesDetailHeader({required this.series});

  final SeriesItem series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (series.backdropUrl != null)
            CachedNetworkImage(
              imageUrl: series.backdropUrl!,
              fit: BoxFit.cover,
            )
          else if (series.posterUrl != null)
            CachedNetworkImage(
              imageUrl: series.posterUrl!,
              fit: BoxFit.cover,
            )
          else
            Container(color: theme.colorScheme.surfaceContainerHighest),
          const GradientScrim(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  series.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (series.plot != null && series.plot!.isNotEmpty) ...[
                  const SizedBox(height: DesignTokens.spaceS),
                  Text(
                    series.plot!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({required this.seriesTitle, required this.episode});

  final String seriesTitle;
  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyServiceProvider);
    return FutureBuilder<Duration?>(
      future: history.resumeFor(episode.id),
      builder: (BuildContext _, AsyncSnapshot<Duration?> snap) {
        final resume = snap.data;
        final hasResume = resume != null && resume > Duration.zero;
        return ListTile(
          leading: CircleAvatar(child: Text('${episode.number}')),
          title: Text(
            episode.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: hasResume
              ? Text('Devam: ${_formatDuration(resume)}')
              : (episode.plot != null && episode.plot!.isNotEmpty
                  ? Text(
                      episode.plot!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null),
          trailing: Icon(hasResume ? Icons.replay : Icons.play_arrow_rounded),
          onTap: () {
            final epTitle =
                '$seriesTitle  S${episode.season}E${episode.number}';
            final urls = streamUrlVariants(episode.streamUrl)
                .map(proxify)
                .toList();
            final all = MediaSource.variants(urls, title: epTitle);
            final args = PlayerLaunchArgs(
              source: all.isEmpty
                  ? MediaSource(
                      url: proxify(episode.streamUrl),
                      title: epTitle,
                    )
                  : all.first,
              fallbacks: all.length <= 1
                  ? const <MediaSource>[]
                  : all.sublist(1),
              title: epTitle,
              subtitle: episode.title,
              itemId: episode.id,
              kind: HistoryKind.series,
            );
            context.push('/play', extra: args);
          },
        );
      },
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}s ${m.toString().padLeft(2, '0')}d';
  return '${m}d ${s.toString().padLeft(2, '0')}s';
}

/// Cinematic Series hero — gold "TV SHOWS" badge per Streas spec § 5.
/// Same geometry as `_VodHero` in vod_screen.dart, kept local because
/// the data type differs (`SeriesItem` vs `VodItem`).
class _SeriesHero extends StatelessWidget {
  const _SeriesHero({
    required this.item,
    required this.onPlay,
  });

  final SeriesItem item;
  final VoidCallback onPlay;

  String? get _imageUrl {
    final b = item.backdropUrl;
    if (b != null && b.isNotEmpty) return b;
    return item.posterUrl;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = _imageUrl;
    final genres = item.genres
        .where((String g) => g.trim().isNotEmpty)
        .take(3)
        .join(' · ');

    return SizedBox(
      height: 420,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              fadeInDuration: DesignTokens.motionMedium,
              errorWidget: (BuildContext _, String __, Object ___) =>
                  ColoredBox(color: scheme.surfaceContainerHighest),
              placeholder: (BuildContext _, String __) =>
                  ColoredBox(color: scheme.surfaceContainerHighest),
            )
          else
            ColoredBox(color: scheme.surfaceContainerHighest),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0, 0.55, 1],
                  colors: <Color>[
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                    scheme.surface,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: DesignTokens.spaceL,
            right: DesignTokens.spaceL,
            bottom: DesignTokens.spaceL,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceM,
                    vertical: DesignTokens.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.goldRating,
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusXL),
                  ),
                  child: const Text(
                    'TV SHOWS',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (genres.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DesignTokens.spaceXs),
                  Text(
                    genres,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                const SizedBox(height: DesignTokens.spaceM),
                Row(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Izle'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spaceL,
                          vertical: DesignTokens.spaceM,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spaceS),
                    if (item.rating != null) RatingPill(rating: item.rating!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
