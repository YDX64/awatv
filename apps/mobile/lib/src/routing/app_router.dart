import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/desktop/desktop_home_shell.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/features/auth/account_screen.dart';
import 'package:awatv_mobile/src/features/auth/login_screen.dart';
import 'package:awatv_mobile/src/features/auth/magic_link_callback_screen.dart';
import 'package:awatv_mobile/src/features/catchup/catchup_screen.dart';
import 'package:awatv_mobile/src/features/channels/channels_screen.dart';
import 'package:awatv_mobile/src/features/channels/epg_grid_screen.dart';
import 'package:awatv_mobile/src/features/downloads/downloads_screen.dart';
import 'package:awatv_mobile/src/features/favorites/favorites_screen.dart';
import 'package:awatv_mobile/src/features/home/home_screen.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_screen.dart';
import 'package:awatv_mobile/src/features/groups/groups_screen.dart';
import 'package:awatv_mobile/src/features/onboarding/welcome_screen.dart';
import 'package:awatv_mobile/src/features/onboarding/wizard_screen.dart';
import 'package:awatv_mobile/src/features/smart_alerts/smart_alerts_screen.dart';
import 'package:awatv_mobile/src/features/parental/parental_screen.dart';
import 'package:awatv_mobile/src/features/player/player_screen.dart';
import 'package:awatv_mobile/src/features/player/trailer_screen.dart';
import 'package:awatv_mobile/src/features/profiles/profile_edit_screen.dart';
import 'package:awatv_mobile/src/features/profiles/profile_picker_screen.dart';
import 'package:awatv_mobile/src/features/playlists/add_playlist_screen.dart';
import 'package:awatv_mobile/src/features/playlists/playlists_screen.dart';
import 'package:awatv_mobile/src/features/premium/premium_screen.dart';
import 'package:awatv_mobile/src/features/recordings/recordings_screen.dart';
import 'package:awatv_mobile/src/features/reminders/reminders_screen.dart';
import 'package:awatv_mobile/src/features/remote/receiver_screen.dart';
import 'package:awatv_mobile/src/features/remote/remote_hub_screen.dart';
import 'package:awatv_mobile/src/features/remote/sender_screen.dart';
import 'package:awatv_mobile/src/features/search/search_screen.dart';
import 'package:awatv_mobile/src/features/series/series_detail_screen.dart';
import 'package:awatv_mobile/src/features/series/series_screen.dart';
import 'package:awatv_mobile/src/features/settings/manage_devices_screen.dart';
import 'package:awatv_mobile/src/features/settings/settings_screen.dart';
import 'package:awatv_mobile/src/features/stats/stats_screen.dart';
import 'package:awatv_mobile/src/features/themes/theme_settings_screen.dart';
import 'package:awatv_mobile/src/features/vod/vod_detail_screen.dart';
import 'package:awatv_mobile/src/features/vod/vod_screen.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_landing_screen.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_screen.dart';
import 'package:awatv_mobile/src/features/watchlist/watchlist_screen.dart';
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
    initialLocation: '/home',
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
          loc.startsWith('/account') ||
          loc.startsWith('/profiles') ||
          loc.startsWith('/settings/parental') ||
          loc.startsWith('/settings/devices') ||
          // The catchup / recordings / downloads hubs are reachable
          // from the sidebar even without a playlist (they each own
          // their own empty state that nudges the user to add a
          // source / explains the Premium gate), so don't bounce them
          // through /onboarding.
          loc.startsWith('/catchup') ||
          loc.startsWith('/recordings') ||
          loc.startsWith('/downloads') ||
          // Reminders + Watchlist are accessible without a playlist —
          // both have their own empty states that point the user back
          // at the relevant flow (TV Rehberi, Filmler / Diziler).
          loc.startsWith('/reminders') ||
          loc.startsWith('/watchlist') ||
          // Smart alerts + groups customisation each render their
          // own empty states ("Akilli uyari yok" / "Grup yok") and
          // never depend on a configured playlist.
          loc.startsWith('/alerts') ||
          loc.startsWith('/settings/groups') ||
          // Favourites + watch-party + remote each have their own
          // empty states / cloud-account guards, so don't bounce them
          // through /onboarding when no playlist is configured yet.
          loc.startsWith('/favorites') ||
          loc.startsWith('/party') ||
          loc.startsWith('/remote') ||
          // Stats + theme picker each render their own empty state
          // ("henuz izleme verisi yok" / "varsayilan tema") and never
          // depend on a configured playlist.
          loc.startsWith('/stats') ||
          loc.startsWith('/settings/theme') ||
          // Multi-stream view — premium-gated, but the screen has its
          // own empty state ("Coklu izlemeye basla — kanal sec") and
          // its own paywall trigger so it doesn't need a playlist gate.
          loc.startsWith('/multistream')) {
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
        routes: <RouteBase>[
          // Multi-step wizard (welcome → privacy → notifications →
          // first playlist → all-set). The wrapper above redirects
          // here when the user has not yet completed the wizard.
          GoRoute(
            path: 'wizard',
            name: 'onboardingWizard',
            builder: (BuildContext context, GoRouterState state) =>
                const OnboardingWizardScreen(),
          ),
        ],
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
      // YouTube trailer playback. The path parameter is the YouTube
      // video id (11 chars); the optional `title` query string is
      // shown in the top bar.
      GoRoute(
        path: '/trailer/:id',
        name: 'trailer',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          final title = state.uri.queryParameters['title'];
          return TrailerScreen(youtubeId: id, title: title);
        },
      ),
      GoRoute(
        path: '/premium',
        name: 'premium',
        builder: (BuildContext context, GoRouterState state) =>
            const PremiumScreen(),
      ),
      // Catchup TV hub — Xtream `archive=1` / timeshift playback.
      GoRoute(
        path: '/catchup',
        name: 'catchup',
        builder: (BuildContext context, GoRouterState state) =>
            const CatchupScreen(),
      ),
      // Live channel recording hub (active / completed / scheduled).
      GoRoute(
        path: '/recordings',
        name: 'recordings',
        builder: (BuildContext context, GoRouterState state) =>
            const RecordingsScreen(),
      ),
      // Offline VOD downloads hub.
      GoRoute(
        path: '/downloads',
        name: 'downloads',
        builder: (BuildContext context, GoRouterState state) =>
            const DownloadsScreen(),
      ),
      // EPG reminders ("Hatirlat") — list of upcoming scheduled
      // notifications the user has set from the TV Rehberi screen.
      GoRoute(
        path: '/reminders',
        name: 'reminders',
        builder: (BuildContext context, GoRouterState state) =>
            const RemindersScreen(),
      ),
      // Smart alerts — keyword-driven EPG alerts. Scans favourite
      // channels for upcoming programmes matching the user's keywords
      // and schedules a reminder 5 minutes before air.
      GoRoute(
        path: '/alerts',
        name: 'alerts',
        builder: (BuildContext context, GoRouterState state) =>
            const SmartAlertsScreen(),
      ),
      // Watch later list — distinct from favourites; both VOD + series
      // get a "saat" toggle on their detail screens that drops the item
      // into this queue.
      GoRoute(
        path: '/watchlist',
        name: 'watchlist',
        builder: (BuildContext context, GoRouterState state) =>
            const WatchlistScreen(),
      ),
      // Favourites + folders. Replaces the legacy "coming soon" stub
      // that the desktop sidebar used to surface.
      GoRoute(
        path: '/favorites',
        name: 'favorites',
        builder: (BuildContext context, GoRouterState state) =>
            const FavoritesScreen(),
      ),
      // Watch-party hub + party room. Hub generates an 8-char id and
      // pushes the room; the room subscribes to the matching Supabase
      // Realtime broadcast channel and mirrors the host's playback.
      GoRoute(
        path: '/party',
        name: 'party',
        builder: (BuildContext context, GoRouterState state) =>
            const WatchPartyLandingScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':partyId',
            name: 'partyRoom',
            builder: (BuildContext context, GoRouterState state) {
              final id = state.pathParameters['partyId'] ?? '';
              final isHost = state.uri.queryParameters['host'] == '1';
              final name = state.uri.queryParameters['name']?.trim();
              return WatchPartyScreen(
                partyId: id,
                userName: (name == null || name.isEmpty)
                    ? (isHost ? 'Host' : 'Misafir')
                    : name,
                isHost: isHost,
              );
            },
          ),
        ],
      ),
      // Multi-stream view — up to 4 channels at once, sport-watching
      // premium feature. The screen owns its own paywall + onboarding
      // so it doesn't need a redirect through /onboarding.
      GoRoute(
        path: '/multistream',
        name: 'multistream',
        builder: (BuildContext context, GoRouterState state) =>
            const MultiStreamScreen(),
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
      // Manage devices screen — surfaces the user's `device_sessions`
      // rows and lets them sign out a remote device. Premium + signed-in
      // gate is enforced inside the screen via the engine.
      GoRoute(
        path: '/settings/devices',
        name: 'settingsDevices',
        builder: (BuildContext context, GoRouterState state) =>
            const ManageDevicesScreen(),
      ),
      // Parental controls — premium-gated central hub for the device
      // PIN, max age rating, blocked categories, daily watch limit
      // and bedtime hour. Read-only when the active tier doesn't cover
      // [PremiumFeature.parentalControls] but always reachable so the
      // settings entry point keeps a stable destination.
      GoRoute(
        path: '/settings/parental',
        name: 'settingsParental',
        builder: (BuildContext context, GoRouterState state) =>
            const ParentalScreen(),
      ),
      // Theme customisation — premium-gated picker for accent / variant /
      // corner radius. The screen owns the paywall sheet so a stale deep
      // link cannot bypass the gate.
      GoRoute(
        path: '/settings/theme',
        name: 'settingsTheme',
        builder: (BuildContext context, GoRouterState state) =>
            const ThemeSettingsScreen(),
      ),
      // Channel groups customisation — drag-to-reorder, hide and
      // rename groups inside Live / Movies / Series buckets. Wires
      // through to [customisedCategoryTreeProvider] so the sidebar
      // tree, home chip row and group-filter strip all reflect the
      // user's preferences.
      GoRoute(
        path: '/settings/groups',
        name: 'settingsGroups',
        builder: (BuildContext context, GoRouterState state) =>
            const GroupsScreen(),
      ),
      // Watch-time stats — Spotify-Wrapped-style aggregate over the
      // local HistoryService. Free tier sees the last 7 days + Top 3;
      // premium unlocks 30-day / all-time totals + Top 5 lists.
      GoRoute(
        path: '/stats',
        name: 'stats',
        builder: (BuildContext context, GoRouterState state) =>
            const StatsScreen(),
      ),
      // Profile picker — Netflix-style "who's watching" tile grid.
      // Bouncing through this route after login is handled by the
      // post-login gate in `awa_tv_app.dart` so the picker only takes
      // over when there are 2+ profiles.
      GoRoute(
        path: '/profiles',
        name: 'profiles',
        builder: (BuildContext context, GoRouterState state) =>
            const ProfilePickerScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'edit',
            name: 'profileCreate',
            builder: (BuildContext context, GoRouterState state) =>
                const ProfileEditScreen(),
          ),
          GoRoute(
            path: 'edit/:id',
            name: 'profileEdit',
            builder: (BuildContext context, GoRouterState state) {
              final id = state.pathParameters['id'];
              return ProfileEditScreen(profileId: id);
            },
          ),
        ],
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
                path: '/home',
                name: 'home',
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/live',
                name: 'live',
                builder: (BuildContext context, GoRouterState state) =>
                    const ChannelsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'epg',
                    name: 'liveEpg',
                    builder: (
                      BuildContext context,
                      GoRouterState state,
                    ) =>
                        const EpgGridScreen(),
                  ),
                ],
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
                  onPressed: () => context.go('/home'),
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
    this.fallbacks = const <MediaSource>[],
    this.title,
    this.subtitle,
    this.itemId,
    this.kind,
    this.isLive = false,
  });

  /// MediaSource to play first. Always consumed verbatim; the fallback
  /// chain only kicks in if it fails.
  final MediaSource source;

  /// Optional ordered list of alternate sources to try when [source]
  /// fails to start playback. Identical headers/UA/referer/title across
  /// entries, only the URL varies. See `streamUrlVariants` for the
  /// canonical way to build this list.
  final List<MediaSource> fallbacks;

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

  /// All sources to try in order: [source] first, then [fallbacks].
  List<MediaSource> get allSources =>
      <MediaSource>[source, ...fallbacks];
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
