import 'package:awatv_mobile/src/features/onboarding/welcome_screen.dart';
import 'package:awatv_mobile/src/features/playlists/add_playlist_screen.dart';
import 'package:awatv_mobile/src/features/playlists/playlists_screen.dart';
import 'package:awatv_mobile/src/features/premium/premium_screen.dart';
import 'package:awatv_mobile/src/features/series/series_detail_screen.dart';
import 'package:awatv_mobile/src/features/vod/vod_detail_screen.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/tv/screens/tv_player_screen.dart';
import 'package:awatv_mobile/src/tv/tv_home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tv_router.g.dart';

/// Dedicated router for the 10-foot UI.
///
/// We picked a separate router (rather than branching inside
/// [appRouterProvider]'s shell builder) because:
///   - The TV shell is NOT a `StatefulShellRoute` — it doesn't keep five
///     parallel back-stacks, it swaps an `IndexedStack`. Trying to graft
///     that into `StatefulNavigationShell.builder` requires faking branches
///     we never use.
///   - Keeping the routers separate makes the form-factor switch a single
///     line in `AwaTvApp.build` and isolates TV-specific concerns inside
///     `lib/src/tv/`.
///
/// Detail / player routes that don't depend on the shell layout are
/// *intentionally* mirrored here (welcome, playlists, premium, vod detail,
/// series detail) — they are reused widgets so the duplication is just a
/// route table, not real UI code.
@Riverpod(keepAlive: true)
GoRouter appTvRouter(Ref ref) {
  final playlistService = ref.watch(playlistServiceProvider);

  return GoRouter(
    initialLocation: '/tv',
    redirect: (BuildContext _, GoRouterState state) async {
      final loc = state.uri.path;
      if (loc.startsWith('/onboarding') || loc.startsWith('/playlists')) {
        return null;
      }
      try {
        final sources = await playlistService.list();
        if (sources.isEmpty && loc != '/onboarding') return '/onboarding';
      } on Object {
        return '/onboarding';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (BuildContext _, GoRouterState __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/playlists',
        name: 'playlists',
        builder: (BuildContext _, GoRouterState __) =>
            const PlaylistsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'add',
            name: 'addPlaylist',
            builder: (BuildContext _, GoRouterState __) =>
                const AddPlaylistScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/movie/:id',
        name: 'movieDetail',
        builder: (BuildContext _, GoRouterState state) {
          final id = state.pathParameters['id']!;
          return VodDetailScreen(vodId: id);
        },
      ),
      GoRoute(
        path: '/series/:id',
        name: 'seriesDetail',
        builder: (BuildContext _, GoRouterState state) {
          final id = state.pathParameters['id']!;
          return SeriesDetailScreen(seriesId: id);
        },
      ),
      GoRoute(
        path: '/play',
        name: 'play',
        builder: (BuildContext _, GoRouterState state) {
          final extra = state.extra;
          if (extra is! PlayerLaunchArgs) {
            return const _TvPlayerArgError();
          }
          return TvPlayerScreen(args: extra);
        },
      ),
      GoRoute(
        path: '/premium',
        name: 'premium',
        builder: (BuildContext _, GoRouterState __) => const PremiumScreen(),
      ),
      GoRoute(
        path: '/tv',
        name: 'tvHome',
        builder: (BuildContext _, GoRouterState __) => const TvHomeShell(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Sayfa bulunamadi',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  state.uri.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/tv'),
                  child: const Text('Ana ekrana don'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TvPlayerArgError extends StatelessWidget {
  const _TvPlayerArgError();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Oynatilacak medya bulunamadi.',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
    );
  }
}
