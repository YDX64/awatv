import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/group_filter_chips.dart';
import 'package:awatv_mobile/src/features/channels/sort_mode_provider.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Movies grid — poster cards. Tap navigates to `/movie/:id`.
///
/// Top: chip strip filtering by genre with multi-select + persistence.
/// AppBar: sort menu (8 modes covering year + rating + alphabetical).
class VodScreen extends ConsumerWidget {
  const VodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(allVodProvider);
    final filter = ref.watch(groupFilterProvider(SortSurface.vod));
    final mode = ref.watch(sortModeProvider(SortSurface.vod));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filmler'),
        actions: const <Widget>[
          SortModeButton(surface: SortSurface.vod),
        ],
      ),
      body: vod.when(
        loading: () => const LoadingView(label: 'Filmler yukleniyor'),
        error: (Object err, StackTrace st) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(allVodProvider),
        ),
        data: (List<VodItem> items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.movie_outlined,
              title: 'Film yok',
              message: 'Senkronladigin listede film bulunamadi.',
            );
          }
          final genres = _genres(items);
          final filtered = _filter(items, filter, mode);
          // Pick a "featured" movie for the hero — first item with a
          // backdrop wins, otherwise the head of the catalogue. Gives
          // the screen a Streas-style cinematic top-of-page even when
          // metadata is sparse.
          final hero = items.firstWhere(
            (VodItem v) =>
                (v.backdropUrl?.isNotEmpty ?? false) ||
                (v.posterUrl?.isNotEmpty ?? false),
            orElse: () => items.first,
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allVodProvider);
              await ref.read(allVodProvider.future);
            },
            child: CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _VodHero(
                    item: hero,
                    badgeText: 'NEW RELEASE',
                    badgeColor: Theme.of(context).colorScheme.primary,
                    badgeForeground: Colors.white,
                    onPlay: () => context.push('/movie/${hero.id}'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: GroupFilterChips(
                    surface: SortSurface.vod,
                    groups: genres,
                    counts: _countByGroup(items, genres),
                  ),
                ),
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.movie_filter_outlined,
                      title: 'Bu filtreye uyan film yok',
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
                        final v = filtered[i];
                        return PosterCard(
                          title: v.title,
                          posterUrl: v.posterUrl,
                          year: v.year,
                          rating: v.rating,
                          onTap: () => context.push('/movie/${v.id}'),
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

  List<String> _genres(List<VodItem> items) {
    final set = <String>{};
    for (final v in items) {
      for (final g in v.genres) {
        final t = g.trim();
        if (t.isNotEmpty) set.add(t);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  Map<String, int> _countByGroup(List<VodItem> items, List<String> groups) {
    final out = <String, int>{};
    for (final g in groups) {
      out[g] = items.where((VodItem v) => v.genres.contains(g)).length;
    }
    return out;
  }

  List<VodItem> _filter(
    List<VodItem> all,
    GroupFilterState filter,
    SortMode mode,
  ) {
    final scoped = filter.selected.isEmpty
        ? all
        : all
            .where((VodItem v) =>
                v.genres.any((String g) => filter.selected.contains(g)))
            .toList();
    return mode.sortVod(scoped);
  }
}

/// Cinematic hero block at the top of the Movies / Series tabs.
///
/// 420-tall (Streas spec § 4) full-bleed image with a 3-stop bottom
/// scrim, a coloured badge ("NEW RELEASE" / "TV SHOWS"), the title, a
/// short genre line, and a "Play" CTA that hands off to the matching
/// detail screen. The badge colour is parameterised so the same widget
/// drives both the cherry-red Movies hero and the gold Series hero.
class _VodHero extends StatelessWidget {
  const _VodHero({
    required this.item,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeForeground,
    required this.onPlay,
  });

  final VodItem item;
  final String badgeText;
  final Color badgeColor;
  final Color badgeForeground;
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
          // 3-stop bottom scrim — Streas spec.
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
                    color: badgeColor,
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusXL),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeForeground,
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
                      label: const Text('Oynat'),
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
