import 'package:awatv_mobile/src/desktop/widgets/persistent_player_bar.dart';
import 'package:awatv_mobile/src/desktop/widgets/sidebar.dart';
import 'package:awatv_mobile/src/shared/home_shell.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// IPTV-Expert-class desktop home shell.
///
/// Layout (>= [DesignTokens.desktopShellBreakpoint]):
/// ┌──────────┬───────────────────────────────────────────────┐
/// │          │                                                 │
/// │          │                                                 │
/// │ Sidebar  │  Branch content (home / live / movies / etc.)   │
/// │ (72/240) │                                                 │
/// │          │                                                 │
/// │          ├───────────────────────────────────────────────┤
/// │          │  Persistent mini player (when playing, 64dp)   │
/// └──────────┴───────────────────────────────────────────────┘
///
/// Below the breakpoint, the shell falls back to the mobile [HomeShell]
/// (bottom NavigationBar) so a user shrinking their window keeps a
/// usable layout. The desktop chrome bar still sits above whatever this
/// widget paints — same as before.
///
/// We intentionally do **not** create a new go_router shell branch — this
/// widget is plugged into the *existing* `StatefulShellRoute.indexedStack`
/// at the route layer. Keeping a single source of truth for the routing
/// graph means deep links and TV / mobile shells all share the same
/// branch indices.
class DesktopHomeShell extends StatelessWidget {
  const DesktopHomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints constraints) {
        if (constraints.maxWidth < DesignTokens.desktopShellBreakpoint) {
          // Narrow window — fall back to the mobile shell so the same
          // widget tree behaves correctly when the user shrinks the
          // window. The persistent player bar still pins to the bottom
          // of the mobile body.
          return Stack(
            children: <Widget>[
              HomeShell(navigationShell: navigationShell),
              const Align(
                alignment: Alignment.bottomCenter,
                child: PersistentPlayerBar(),
              ),
            ],
          );
        }
        return _WideShell(navigationShell: navigationShell);
      },
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<SidebarSection> _sections = <SidebarSection>[
    SidebarSection(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Anasayfa',
      route: '/home',
    ),
    SidebarSection(
      icon: Icons.live_tv_outlined,
      activeIcon: Icons.live_tv_rounded,
      label: 'Canli TV',
      route: '/live',
    ),
    SidebarSection(
      icon: Icons.movie_outlined,
      activeIcon: Icons.movie_rounded,
      label: 'Filmler',
      route: '/movies',
    ),
    SidebarSection(
      icon: Icons.video_library_outlined,
      activeIcon: Icons.video_library_rounded,
      label: 'Diziler',
      route: '/series',
    ),
    SidebarSection(
      icon: Icons.replay_circle_filled_outlined,
      activeIcon: Icons.replay_circle_filled_rounded,
      label: 'Catchup',
      route: '/catchup',
    ),
    SidebarSection(
      icon: Icons.fiber_manual_record_outlined,
      activeIcon: Icons.fiber_manual_record_rounded,
      label: 'Kayitlar',
      route: '/recordings',
    ),
    SidebarSection(
      icon: Icons.download_outlined,
      activeIcon: Icons.download_rounded,
      label: 'Indirilenler',
      route: '/downloads',
    ),
    SidebarSection(
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
      label: 'Ara',
      route: '/search',
      shortcut: 'F',
    ),
    SidebarSection(
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
      label: 'Favoriler',
      route: '/favorites',
      comingSoon: true,
    ),
    SidebarSection(
      icon: Icons.history_rounded,
      activeIcon: Icons.history_rounded,
      label: 'Gecmis',
      route: '/history',
      comingSoon: true,
    ),
    SidebarSection(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Ayarlar',
      route: '/settings',
    ),
  ];

  // Each shell branch index — must match `routing/app_router.dart`. We
  // keep the list literal here so the wide shell can swap between
  // shell-aware sidebar items (which call `goBranch`) and standalone
  // `context.go` items without losing the back-stack semantics.
  static const Map<String, int> _branchIndex = <String, int>{
    '/home': 0,
    '/live': 1,
    '/movies': 2,
    '/series': 3,
    '/search': 4,
    '/settings': 5,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeBranchIndex = navigationShell.currentIndex;
    final activeRoute = _branchIndex.entries
        .firstWhere(
          (MapEntry<String, int> e) => e.value == activeBranchIndex,
          orElse: () => const MapEntry<String, int>('/home', 0),
        )
        .key;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          IpxSidebar(
            sections: _sections,
            activeRoute: activeRoute,
            onNavigate: (String route) => _navigate(context, route),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: navigationShell),
                const PersistentPlayerBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Route a sidebar tap. Branch routes use `goBranch` so each tab keeps
  /// its own back-stack; everything else falls through to a plain
  /// `context.go` so deep-linkable routes (favorites/history once they
  /// ship) work without rebuilding the shell.
  void _navigate(BuildContext context, String route) {
    final branch = _branchIndex[route];
    if (branch != null) {
      navigationShell.goBranch(
        branch,
        initialLocation: branch == navigationShell.currentIndex,
      );
      return;
    }
    context.go(route);
  }
}
