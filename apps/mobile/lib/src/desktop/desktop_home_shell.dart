import 'package:awatv_mobile/src/shared/home_shell.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Width threshold below which the desktop shell falls back to the mobile
/// `HomeShell` (bottom NavigationBar). 1100dp is the Material 3 expanded
/// breakpoint — wide enough that a vertical rail and a content grid both
/// have comfortable room.
const double _railBreakpoint = 1100;

/// Adaptive home shell used inside the desktop app.
///
/// At >= 1100dp it draws a left navigation rail with the same five
/// destinations as `HomeShell`, plus a header strip with the AWAtv brand
/// mark. Below 1100dp it gracefully falls back to the existing mobile
/// `HomeShell` so the same widget tree behaves correctly when the user
/// shrinks the window.
///
/// We intentionally do **not** create a new go_router shell branch — this
/// widget is plugged into the *existing* `StatefulShellRoute.indexedStack`
/// at the route layer. Keeping a single source of truth for the routing
/// graph means deep links and TV / mobile shells all share the same
/// branch indices.
class DesktopHomeShell extends StatelessWidget {
  const DesktopHomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_DesktopDestination> _destinations =
      <_DesktopDestination>[
    _DesktopDestination(
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
      label: 'Canli',
    ),
    _DesktopDestination(
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie,
      label: 'Filmler',
    ),
    _DesktopDestination(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: 'Diziler',
    ),
    _DesktopDestination(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      label: 'Ara',
    ),
    _DesktopDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Ayarlar',
    ),
  ];

  void _onSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _railBreakpoint) {
          // Narrow window — use the existing mobile shell so we don't
          // duplicate UX. The chrome bar painted by `DesktopChrome` still
          // sits above this.
          return HomeShell(navigationShell: navigationShell);
        }
        return _WideShell(
          navigationShell: navigationShell,
          destinations: _destinations,
          onSelected: _onSelected,
        );
      },
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({
    required this.navigationShell,
    required this.destinations,
    required this.onSelected,
  });

  final StatefulNavigationShell navigationShell;
  final List<_DesktopDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Custom rail rather than `NavigationRail` — we want the brand
          // mark, an explicit width, and consistent typography with the
          // TV shell.
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                right: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.18),
                ),
              ),
            ),
            child: SafeArea(
              right: false,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spaceL,
                      DesignTokens.spaceL,
                      DesignTokens.spaceL,
                      DesignTokens.spaceM,
                    ),
                    child: ShaderMask(
                      shaderCallback: (Rect r) =>
                          BrandColors.brandGradient.createShader(r),
                      blendMode: BlendMode.srcIn,
                      child: const Text(
                        'AWAtv',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  for (int i = 0; i < destinations.length; i++)
                    _RailItem(
                      destination: destinations[i],
                      selected: navigationShell.currentIndex == i,
                      onTap: () => onSelected(i),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spaceL,
                      DesignTokens.spaceM,
                      DesignTokens.spaceL,
                      DesignTokens.spaceL,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.bolt,
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Masaustu modu',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                scheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _DesktopDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final bg = selected
        ? scheme.primaryContainer.withValues(alpha: 0.6)
        : (_hover
            ? scheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent);
    final fg = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurface.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: 2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: DesignTokens.motionFast,
            height: 44,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(DesignTokens.radiusM),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? widget.destination.selectedIcon
                      : widget.destination.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Text(
                    widget.destination.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopDestination {
  const _DesktopDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
