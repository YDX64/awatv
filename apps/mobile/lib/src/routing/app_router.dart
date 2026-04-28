import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/desktop/desktop_home_shell.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/features/auth/account_screen.dart';
import 'package:awatv_mobile/src/features/auth/login_screen.dart';
import 'package:awatv_mobile/src/features/auth/magic_link_callback_screen.dart';
import 'package:awatv_mobile/src/features/channels/channels_screen.dart';
import 'package:awatv_mobile/src/features/onboarding/welcome_screen.dart';
import 'package:awatv_mobile/src/features/player/player_screen.dart';
import 'package:awatv_mobile/src/features/playlists/add_playlist_screen.dart';
import 'package:awatv_mobile/src/features/playlists/playlists_screen.dart';
import 'package:awatv_mobile/src/features/premium/premium_screen.dart';
import 'package:awatv_mobile/src/features/remote/receiver_screen.dart';
import 'package:awatv_mobile/src/features/remote/remote_hub_screen.dart';
import 'package:awatv_mobile/src/features/remote/sender_screen.dart';
import 'package:awatv_mobile/src/features/search/search_screen.dart';
import 'package:awatv_mobile/src/features/series/series_detail_screen.dart';
import 'package:awatv_mobile/src/features/series/series_screen.dart';
import 'package:awatv_mobile/src/features/settings/settings_screen.dart';
import 'package:awatv_mobile/src/features/vod/vod_detail_screen.dart';
import 'package:awatv_mobile/src/features/vod/vod_screen.dart';
import 'package:awatv_mobile/src/shared/auth/auth_guard.dart';
import 'package:awatv_mobile/src/shared/home_shell.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Top-level go_router configuration.
///
/// The shell routes (`/live`, `/movies`, `/series`, `/search`, `/settings`)
/// are mounted under a [StatefulShellRoute.indexedStack] so each tab keeps
/// its own back-stack. Detail / modal routes (`/play`, `/channel/:id`, …)
/// sit at the root level and present full-screen.
///
/// The redirect ensures users with zero playlists land on `/onboarding`
/// instead of an empty Channels grid.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final playlistService = ref.watch(playlistServiceProvider);

  return GoRouter(
    initialLocation: '/live',
    redirect: (BuildContext context, GoRouterState state) async {
      final loc = state.uri.path;

      // Auth-protected routes first — redirect to /login with the
      // intended destination as `?next=` so the login flow can bounce
      // the user back after a successful magic-link confirmation.
      if (loc.startsWith('/account')) {
        final guarded = authGuard(state, ref);
        if (guarded != null) return guarded;
      }

      // Skip onboarding redirect for the onboarding / playlist / auth
      // routes themselves — otherwise we'd loop.
      if (loc.startsWith('/onboarding') ||
          loc.startsWith('/playlists') ||
          loc.startsWith('/login') ||
          loc.startsWith('/auth') ||
          loc.startsWith('/account')) {
        return null;
      }
      try {
        final sources = await playlistService.list();
        if (sources.isEmpty && loc != '/onboarding') return '/onboarding';
      } on Object {
        // If we can't read storage, prefer the welcome screen over a
        // half-broken main shell.
        return '/onboarding';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (BuildContext context, GoRouterState state) =>
            const WelcomeScreen(),
      ),
      GoRoute(
        path: '/playlists',
        name: 'playlists',
        builder: (BuildContext context, GoRouterState state) =>
            const PlaylistsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'add',
            name: 'addPlaylist',
            builder: (BuildContext context, GoRouterState state) =>
                const AddPlaylistScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/channel/:id',
        name: 'channelDetail',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id']!;
          return ChannelDetailScreen(channelId: id);
        },
      ),
      GoRoute(
        path: '/movie/:id',
        name: 'movieDetail',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id']!;
          return VodDetailScreen(vodId: id);
        },
      ),
      GoRoute(
        path: '/series/:id',
        name: 'seriesDetail',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id']!;
          return SeriesDetailScreen(seriesId: id);
        },
      ),
      GoRoute(
        path: '/play',
        name: 'play',
        builder: (BuildContext context, GoRouterState state) {
          final extra = state.extra;
          if (extra is! PlayerLaunchArgs) {
            // Defensive: someone pushed us without a media source.
            return const _PlayerArgError();
          }
          return PlayerScreen(args: extra);
        },
      ),
      GoRoute(
        path: '/premium',
        name: 'premium',
        builder: (BuildContext context, GoRouterState state) =>
            const PremiumScreen(),
      ),
      // Remote-control hub. Two big buttons: receive (this device shows
      // video) or send (this device acts as a remote). The two child
      // routes own the actual pairing flow.
      GoRoute(
        path: '/remote',
        name: 'remote',
        builder: (BuildContext context, GoRouterState state) =>
            const RemoteHubScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'receive',
            name: 'remoteReceive',
            builder: (BuildContext context, GoRouterState state) =>
                const ReceiverScreen(),
          ),
          GoRoute(
            path: 'send',
            name: 'remoteSend',
            builder: (BuildContext context, GoRouterState state) {
              final code = state.uri.queryParameters['code'];
              return SenderScreen(initialCode: code);
            },
          ),
        ],
      ),
      // Auth: magic-link sign-in. Pure additive — guests can ignore
      // this route entirely and the rest of the app continues to work.
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) {
          final next = state.uri.queryParameters['next'];
          return LoginScreen(next: next);
        },
      ),
      // Magic-link redirect target — Supabase appends `?code=…` (or
      // `?error_description=…`) once the user clicks the email link.
      GoRoute(
        path: '/auth/callback',
        name: 'authCallback',
        builder: (BuildContext context, GoRouterState state) {
          final params = state.uri.queryParameters;
          return MagicLinkCallbackScreen(
            code: params['code'],
            next: params['next'],
            error: params['error_description'] ?? params['error'],
          );
        },
      ),
      // Account dashboard — protected by the redirect above.
      GoRoute(
        path: '/account',
        name: 'account',
        builder: (BuildContext context, GoRouterState state) =>
            const AccountScreen(),
      ),
      // Bottom-nav shell. On desktop the same `StatefulNavigationShell`
      // is reused but rendered through `DesktopHomeShell` which adapts to
      // a left-rail layout above 1100dp.
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) {
          final isDesktop = ref.watch(isDesktopFormProvider);
          return isDesktop
              ? DesktopHomeShell(navigationShell: navigationShell)
              : HomeShell(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/live',
                name: 'live',
                builder: (BuildContext context, GoRouterState state) =>
                    const ChannelsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/movies',
                name: 'movies',
                builder: (BuildContext context, GoRouterState state) =>
                    const VodScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/series',
                name: 'series',
                builder: (BuildContext context, GoRouterState state) =>
                    const SeriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                name: 'search',
                builder: (BuildContext context, GoRouterState state) =>
                    const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bulunamadi')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  onPressed: () => context.go('/live'),
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

/// Arguments passed via `context.push('/play', extra: ...)`.
///
/// Carries everything PlayerScreen needs to construct an
/// [AwaPlayerController] without re-querying state from Hive.
class PlayerLaunchArgs {
  const PlayerLaunchArgs({
    required this.source,
    this.title,
    this.subtitle,
    this.itemId,
    this.kind,
    this.isLive = false,
  });

  /// MediaSource to play.
  final MediaSource source;

  /// Foreground title shown in the player overlay.
  final String? title;

  /// Optional subtitle (channel group, season+episode, etc.).
  final String? subtitle;

  /// History identifier — used to write resume positions. Pass the
  /// [Channel.id] / [VodItem.id] / [Episode.id].
  final String? itemId;

  /// What kind of item this is — used for history bucketing.
  final HistoryKind? kind;

  /// True for live streams (no seek bar, no resume). Inferred from URL by
  /// default but callers can override.
  final bool isLive;
}

class _PlayerArgError extends StatelessWidget {
  const _PlayerArgError();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player')),
      body: const Center(
        child: Text('Oynatilacak medya bulunamadi.'),
      ),
    );
  }
}
