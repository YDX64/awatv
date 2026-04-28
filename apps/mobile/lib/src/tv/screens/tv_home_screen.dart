import 'package:awatv_mobile/src/features/home/home_data.dart';
import 'package:awatv_mobile/src/features/home/home_hero.dart';
import 'package:awatv_mobile/src/features/home/home_row.dart';
import 'package:awatv_mobile/src/features/home/home_row_item.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 10-foot home screen.
///
/// Same row composition as the mobile screen, with a few TV-friendly
/// adjustments:
///   - Larger poster height (260dp) — readable across the room.
///   - Hero auto-rotation lengthened to 12s so passive TV viewers have
///     time to read each slot.
///   - Each card is wrapped in [FocusableTile] so D-pad navigation lights
///     up the brand glow on the focused poster.
///   - Up/Down moves between rows; Left/Right within a row; OK opens
///     the detail screen.
class TvHomeScreen extends ConsumerWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAny = ref.watch(homeHasAnyDataProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
      ),
      child: hasAny.when(
        loading: () => const _TvHomeLoading(),
        error: (Object e, StackTrace _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(homeHasAnyDataProvider),
        ),
        data: (bool any) {
          if (!any) return const _TvHomeEmpty();
          return const _TvHomeBody();
        },
      ),
    );
  }
}

class _TvHomeBody extends ConsumerWidget {
  const _TvHomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = ref.watch(heroSlotsProvider);
    final continueW = ref.watch(continueWatchingProvider);
    final trending = ref.watch(trendingNowProvider);
    final newMovies = ref.watch(newMoviesProvider);
    final newSeries = ref.watch(newSeriesProvider);
    final favs = ref.watch(homeFavoritesProvider);
    final picks = ref.watch(editorsPicksProvider);

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        children: <Widget>[
          hero.when(
            loading: () => const _TvHeroSkeleton(),
            error: (Object _, StackTrace __) => const SizedBox.shrink(),
            data: (List<HomeRowItem> slots) {
              if (slots.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 360,
                child: HomeHero(
                  slots: slots,
                  autoAdvance: const Duration(seconds: 12),
                ),
              );
            },
          ),
          _TvRowSlot(
            title: 'Izlemeye devam et',
            value: continueW,
            autofocusFirst: true,
          ),
          _TvRowSlot(title: 'Simdi trend', value: trending),
          _TvRowSlot(title: 'Yeni filmler', value: newMovies),
          _TvRowSlot(title: 'Yeni diziler', value: newSeries),
          _TvRowSlot(title: 'Favorilerin', value: favs),
          _TvRowSlot(
            title: 'Editor secimleri',
            value: picks,
            proBadge: true,
          ),
          const SizedBox(height: DesignTokens.spaceXxl),
        ],
      ),
    );
  }
}

class _TvRowSlot extends StatelessWidget {
  const _TvRowSlot({
    required this.title,
    required this.value,
    this.proBadge = false,
    this.autofocusFirst = false,
  });

  final String title;
  final AsyncValue<List<HomeRowItem>> value;
  final bool proBadge;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const HomeRowSkeleton(posterHeight: 260),
      error: (Object _, StackTrace __) => const SizedBox.shrink(),
      data: (List<HomeRowItem> items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return HomeRow(
          title: title,
          items: items,
          posterHeight: 260,
          proBadge: proBadge,
          focusable: true,
          autofocusFirst: autofocusFirst,
        );
      },
    );
  }
}

class _TvHeroSkeleton extends StatelessWidget {
  const _TvHeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: ShimmerSkeleton.box(radius: DesignTokens.radiusL),
    );
  }
}

class _TvHomeLoading extends StatelessWidget {
  const _TvHomeLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        _TvHeroSkeleton(),
        HomeRowSkeleton(posterHeight: 260),
        HomeRowSkeleton(posterHeight: 260),
      ],
    );
  }
}

class _TvHomeEmpty extends StatelessWidget {
  const _TvHomeEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Liste ekle',
        subtitle: 'Telefonundan AWAtv mobil uygulamasi ile bir M3U veya '
            'Xtream listesi ekledikten sonra burada zenginlesir.',
      ),
    );
  }
}
