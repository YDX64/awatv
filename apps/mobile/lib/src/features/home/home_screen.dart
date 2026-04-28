import 'package:awatv_mobile/src/features/home/home_data.dart';
import 'package:awatv_mobile/src/features/home/home_hero.dart';
import 'package:awatv_mobile/src/features/home/home_row.dart';
import 'package:awatv_mobile/src/features/home/home_row_item.dart';
import 'package:awatv_mobile/src/shared/network/network_chip.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Mobile home — Netflix-style stacked rows with a hero carousel up top.
///
/// Renders 7 surfaces in order:
///   1. Hero carousel (5 slots, auto-rotating)
///   2. Continue Watching       (only if non-empty)
///   3. Trending now
///   4. New movies
///   5. New series
///   6. Favorites               (only if non-empty)
///   7. Editor's Picks (PRO)    (only if available)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAny = ref.watch(homeHasAnyDataProvider);

    return Scaffold(
      body: hasAny.when(
        loading: () => const _HomeLoading(),
        error: (Object e, StackTrace _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(homeHasAnyDataProvider),
        ),
        data: (bool any) {
          if (!any) return const _HomeEmpty();
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(continueWatchingProvider)
                ..invalidate(trendingNowProvider)
                ..invalidate(newMoviesProvider)
                ..invalidate(newSeriesProvider)
                ..invalidate(homeFavoritesProvider)
                ..invalidate(editorsPicksProvider)
                ..invalidate(heroSlotsProvider)
                ..invalidate(homeHasAnyDataProvider);
              await ref.read(homeHasAnyDataProvider.future);
            },
            child: const _HomeBody(),
          );
        },
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = ref.watch(heroSlotsProvider);
    final continueW = ref.watch(continueWatchingProvider);
    final trending = ref.watch(trendingNowProvider);
    final newMovies = ref.watch(newMoviesProvider);
    final newSeries = ref.watch(newSeriesProvider);
    final favs = ref.watch(homeFavoritesProvider);
    final picks = ref.watch(editorsPicksProvider);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: <Widget>[
        SliverAppBar(
          floating: true,
          snap: true,
          backgroundColor:
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
          elevation: 0,
          title: ShaderMask(
            shaderCallback: (Rect r) =>
                BrandColors.brandGradient.createShader(r),
            blendMode: BlendMode.srcIn,
            child: const Text(
              'AWAtv',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 22,
                color: Colors.white,
              ),
            ),
          ),
          actions: <Widget>[
            // Live network chip — surfaces Wi-Fi SSID once the user has
            // granted consent in onboarding. Falls back to "Mobil veri"
            // / "Ethernet" depending on the active interface; hidden
            // outright on web and offline.
            const Padding(
              padding: EdgeInsets.only(right: DesignTokens.spaceXs),
              child: NetworkChip(),
            ),
            IconButton(
              tooltip: 'Ara',
              icon: const Icon(Icons.search),
              onPressed: () => context.push('/search'),
            ),
            IconButton(
              tooltip: 'Listeler',
              icon: const Icon(Icons.playlist_play_outlined),
              onPressed: () => context.push('/playlists'),
            ),
            const SizedBox(width: DesignTokens.spaceS),
          ],
        ),
        // One-shot SSID consent banner. Renders as a SizedBox.shrink
        // when already asked / granted so it has zero footprint after
        // the first launch.
        const SliverToBoxAdapter(child: SsidConsentBanner()),
        SliverToBoxAdapter(
          child: hero.when(
            loading: () => const _HeroSkeleton(),
            error: (Object _, StackTrace __) => const SizedBox.shrink(),
            data: (List<HomeRowItem> slots) {
              if (slots.isEmpty) return const SizedBox.shrink();
              return HomeHero(slots: slots);
            },
          ),
        ),
        SliverToBoxAdapter(
          child: _RowSlot(
            title: 'Izlemeye devam et',
            seeAll: '/movies',
            value: continueW,
          ),
        ),
        SliverToBoxAdapter(
          child: _RowSlot(
            title: 'Simdi trend',
            seeAll: '/live',
            value: trending,
          ),
        ),
        SliverToBoxAdapter(
          child: _RowSlot(
            title: 'Yeni filmler',
            seeAll: '/movies',
            value: newMovies,
          ),
        ),
        SliverToBoxAdapter(
          child: _RowSlot(
            title: 'Yeni diziler',
            seeAll: '/series',
            value: newSeries,
          ),
        ),
        SliverToBoxAdapter(
          child: _RowSlot(
            title: 'Favorilerin',
            value: favs,
          ),
        ),
        SliverToBoxAdapter(
          child: _RowSlot(
            title: 'Editor secimleri',
            value: picks,
            proBadge: true,
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.only(bottom: DesignTokens.spaceXxl),
        ),
      ],
    );
  }
}

/// Wraps an `AsyncValue<List<HomeRowItem>>` with the row UI: shimmer
/// while loading, hidden while empty, real cards when data is in.
class _RowSlot extends StatelessWidget {
  const _RowSlot({
    required this.title,
    required this.value,
    this.seeAll,
    this.proBadge = false,
  });

  final String title;
  final AsyncValue<List<HomeRowItem>> value;
  final String? seeAll;
  final bool proBadge;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const HomeRowSkeleton(),
      error: (Object _, StackTrace __) => const SizedBox.shrink(),
      data: (List<HomeRowItem> items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return HomeRow(
          title: title,
          items: items,
          seeAllRoute: seeAll,
          proBadge: proBadge,
        );
      },
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints c) {
        final h = c.maxWidth / DesignTokens.backdropAspect;
        return SizedBox(
          height: h,
          child: ShimmerSkeleton.box(radius: 0),
        );
      },
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        _HeroSkeleton(),
        HomeRowSkeleton(),
        HomeRowSkeleton(),
        HomeRowSkeleton(),
      ],
    );
  }
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Hosgeldin!',
        subtitle:
            'Bir liste ekleyince filmler, diziler ve canli kanallar burada belirir.',
        action: FilledButton.icon(
          onPressed: () => context.push('/playlists/add'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Once bir liste ekle'),
        ),
      ),
    );
  }
}
