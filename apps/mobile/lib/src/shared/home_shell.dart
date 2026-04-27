import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-tab container for the five primary sections.
///
/// Wraps a [StatefulNavigationShell] (from go_router) so each tab keeps its
/// own back-stack. The shell itself is responsible for the tab's content;
/// this widget only paints the chrome around it.
class HomeShell extends StatelessWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
      label: 'Canli',
    ),
    _NavDestination(
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie,
      label: 'Filmler',
    ),
    _NavDestination(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: 'Diziler',
    ),
    _NavDestination(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      label: 'Ara',
    ),
    _NavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Ayarlar',
    ),
  ];

  void _onTap(int index) {
    // `goBranch` keeps the existing branch state if already selected, but
    // pops to its root when re-tapping the active tab — matches platform
    // expectations on iOS / Android.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: <NavigationDestination>[
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
