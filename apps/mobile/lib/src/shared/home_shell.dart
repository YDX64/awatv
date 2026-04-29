import 'package:awatv_mobile/src/shared/breakpoints/breakpoints.dart';
import 'package:awatv_mobile/src/shared/remote_config/app_remote_config.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom-tab container for the four primary content sections + a More
/// drawer.
///
/// Wraps a [StatefulNavigationShell] (from go_router) so each tab keeps
/// its own back-stack. The shell itself is responsible for the tab's
/// content; this widget only paints the chrome around it.
///
/// Tab order matches IPTV-Expert-class apps: Home (category tree),
/// Live, VOD, Series, More (drawer with Search, Settings, Favorites,
/// History, Profiles, Premium, Account).
///
/// Adaptive behaviour:
///   * **phone** (<600 dp) — bottom NavigationBar (Material 3 default).
///   * **tablet** (600–1100 dp) — left-side NavigationRail (96 dp wide)
///     with the same destinations + a "More" trigger; the body shifts
///     right by the rail width. Above 1100 dp the desktop shell takes
///     over entirely (handled outside this widget).
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Bottom-nav destinations that map 1:1 to a shell branch index.
  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Anasayfa',
      branchIndex: 0,
    ),
    _NavDestination(
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv_rounded,
      label: 'Canli',
      branchIndex: 1,
    ),
    _NavDestination(
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie_rounded,
      label: 'Filmler',
      branchIndex: 2,
    ),
    _NavDestination(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
      label: 'Diziler',
      branchIndex: 3,
    ),
  ];

  /// More-drawer entries — secondary navigation that doesn't deserve a
  /// permanent slot in a 360-wide bottom bar but is still essential.
  static const List<_MoreEntry> _moreEntries = <_MoreEntry>[
    _MoreEntry(
      icon: Icons.search_rounded,
      label: 'Ara',
      route: '/search',
      branchIndex: 4,
    ),
    _MoreEntry(
      icon: Icons.settings_outlined,
      label: 'Ayarlar',
      route: '/settings',
      branchIndex: 5,
    ),
    _MoreEntry(
      icon: Icons.queue_music_outlined,
      label: 'Listeler',
      route: '/playlists',
    ),
    _MoreEntry(
      icon: Icons.workspace_premium_rounded,
      label: 'Premium',
      route: '/premium',
    ),
    _MoreEntry(
      icon: Icons.person_outline,
      label: 'Profiller',
      route: '/profiles',
    ),
    _MoreEntry(
      icon: Icons.account_circle_outlined,
      label: 'Hesap',
      route: '/account',
    ),
    _MoreEntry(
      icon: Icons.devices_other_rounded,
      label: 'Cihazlar',
      route: '/settings/devices',
    ),
    _MoreEntry(
      icon: Icons.shield_moon_outlined,
      label: 'Ebeveyn',
      route: '/settings/parental',
    ),
    _MoreEntry(
      icon: Icons.cast_connected_rounded,
      label: 'Uzaktan kumanda',
      route: '/remote',
    ),
    _MoreEntry(
      icon: Icons.watch_later_outlined,
      label: 'Watch list',
      route: '/watchlist',
    ),
    _MoreEntry(
      icon: Icons.dashboard_customize_outlined,
      label: 'Coklu izle',
      route: '/multistream',
    ),
    _MoreEntry(
      icon: Icons.notifications_active_outlined,
      label: 'Hatirlatmalar',
      route: '/reminders',
    ),
    // Watch-time stats — additive More-sheet entry. Free tier sees
    // the headline numbers; premium unlocks 30-day / all-time totals
    // and the full Top 5 lists. Stats screen has its own empty state
    // so it doesn't need a playlist to be configured.
    _MoreEntry(
      icon: Icons.insights_outlined,
      label: 'Istatistiklerim',
      route: '/stats',
    ),
  ];

  void _onTap(BuildContext context, int index) {
    if (index == _destinations.length) {
      // "More" tab — opens the modal drawer instead of jumping to a
      // branch. Keeps the bar pattern (4 + 1) close to the IPTV Expert
      // mobile drawer affordance.
      _showMoreSheet(context);
      return;
    }
    final branch = _destinations[index].branchIndex;
    navigationShell.goBranch(
      branch,
      initialLocation: branch == navigationShell.currentIndex,
    );
  }

  Future<void> _showMoreSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _MoreSheet(
        entries: _moreEntries,
        onPick: (_MoreEntry e) {
          Navigator.of(ctx).pop();
          if (e.branchIndex != null) {
            navigationShell.goBranch(
              e.branchIndex!,
              initialLocation:
                  e.branchIndex == navigationShell.currentIndex,
            );
          } else {
            context.push(e.route);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = _activeIndexFor(navigationShell.currentIndex);
    final deviceClass = deviceClassFor(context);
    final maintenance = ref.watch(maintenanceMessageProvider);

    final body = Column(
      children: <Widget>[
        if (maintenance.isNotEmpty) _MaintenanceBanner(message: maintenance),
        Expanded(child: navigationShell),
      ],
    );

    // Tablet (600..1100 dp): use NavigationRail in the leading slot.
    // Phones still get the bottom bar; desktop is handled by the
    // dedicated desktop shell.
    if (deviceClass.isTablet) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: <Widget>[
              _TabletRail(
                activeIndex: activeIndex,
                destinations: _destinations,
                extended: deviceClass.isTabletLarge,
                onTap: (int i) => _onTap(context, i),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeIndex,
        onDestinationSelected: (int i) => _onTap(context, i),
        destinations: <NavigationDestination>[
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_horiz_rounded),
            label: 'Daha fazla',
          ),
        ],
      ),
    );
  }

  /// Map the navigation shell branch index to the bottom-nav index. The
  /// shell has 6 branches (0..5) but the bar only owns 4 + a More slot,
  /// so anything outside that range gets pinned to "More".
  int _activeIndexFor(int branch) {
    for (var i = 0; i < _destinations.length; i++) {
      if (_destinations[i].branchIndex == branch) return i;
    }
    return _destinations.length; // "More" tab
  }
}

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.branchIndex,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int branchIndex;
}

class _MoreEntry {
  const _MoreEntry({
    required this.icon,
    required this.label,
    required this.route,
    this.branchIndex,
  });

  final IconData icon;
  final String label;
  final String route;

  /// When set, picking this entry calls `goBranch` instead of `context.push`
  /// so the user lands on the same shell-managed tab they would reach via
  /// the bottom bar / sidebar elsewhere.
  final int? branchIndex;
}

/// Tablet-form NavigationRail.
///
/// Shows the same five destinations as the phone bottom-nav (4 main + a
/// "More" trigger) but laid out vertically. Width is 96 dp at the
/// "tablet" breakpoint and expands with labels on the wider tablet
/// breakpoint to feel less cramped on landscape iPads / Android
/// foldables in book mode.
class _TabletRail extends StatelessWidget {
  const _TabletRail({
    required this.activeIndex,
    required this.destinations,
    required this.extended,
    required this.onTap,
  });

  final int activeIndex;
  final List<_NavDestination> destinations;
  final bool extended;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // NavigationRail's `selectedIndex` only accepts indices into the
    // exact list of `destinations` passed to it. We have N + 1 slots
    // (the trailing "More" item) so we pin selection to null when the
    // current branch is one of the More-only routes.
    final inMain = activeIndex < destinations.length;
    return NavigationRail(
      selectedIndex: inMain ? activeIndex : null,
      groupAlignment: -0.85,
      labelType: extended
          ? NavigationRailLabelType.all
          : NavigationRailLabelType.selected,
      onDestinationSelected: onTap,
      destinations: <NavigationRailDestination>[
        for (final d in destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
        const NavigationRailDestination(
          icon: Icon(Icons.more_horiz_rounded),
          selectedIcon: Icon(Icons.more_horiz_rounded),
          label: Text('Daha fazla'),
        ),
      ],
    );
  }
}

/// Yellow banner pinned above the navigation shell when Remote Config
/// publishes a `maintenance_message`. Hidden whenever the string is empty.
class _MaintenanceBanner extends StatelessWidget {
  const _MaintenanceBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                color: scheme.onTertiaryContainer,
                size: 18,
              ),
              const SizedBox(width: DesignTokens.spaceS),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.entries, required this.onPick});

  final List<_MoreEntry> entries;
  final ValueChanged<_MoreEntry> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceL,
              DesignTokens.spaceS,
              DesignTokens.spaceL,
              DesignTokens.spaceS,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'Daha fazla',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text(
                  '${entries.length} secenek',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              physics: const ClampingScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: DesignTokens.spaceS,
                crossAxisSpacing: DesignTokens.spaceS,
              ),
              itemCount: entries.length,
              itemBuilder: (BuildContext _, int i) {
                final e = entries[i];
                return Material(
                  color: scheme.surface,
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusM),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusM),
                    onTap: () => onPick(e),
                    child: Padding(
                      padding: const EdgeInsets.all(
                        DesignTokens.spaceS,
                      ),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            e.icon,
                            size: 22,
                            color: scheme.primary,
                          ),
                          const SizedBox(height: DesignTokens.spaceXs),
                          Text(
                            e.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
