import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_mobile/src/tv/screens/tv_home_screen.dart';
import 'package:awatv_mobile/src/tv/screens/tv_live_screen.dart';
import 'package:awatv_mobile/src/tv/screens/tv_search_screen.dart';
import 'package:awatv_mobile/src/tv/screens/tv_series_screen.dart';
import 'package:awatv_mobile/src/tv/screens/tv_settings_screen.dart';
import 'package:awatv_mobile/src/tv/screens/tv_vod_screen.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 10-foot home shell — left rail + content pane.
///
/// Why we don't reuse [HomeShell]: the bottom NavigationBar is unreachable
/// with a D-pad once focus is in a content grid (the user has to scroll
/// past every item to reach the bar). A persistent left rail solves this:
/// the leftmost column always has focus when D-pad-Left is hit from the
/// content. We use a single FocusTraversalGroup per column so the rail
/// keeps Up/Down navigation, and Right pushes focus into the content.
///
/// State note: the TV shell does NOT use go_router's `StatefulShellRoute`.
/// On TV the user expects each rail click to "jump" rather than maintain
/// per-tab back stacks (which they can't see). A single index here, swapped
/// via `IndexedStack`, keeps providers warm so navigation is instant.
class TvHomeShell extends StatefulWidget {
  const TvHomeShell({super.key});

  @override
  State<TvHomeShell> createState() => _TvHomeShellState();
}

class _TvHomeShellState extends State<TvHomeShell> {
  int _index = 0;

  static const List<_TvDestination> _destinations = <_TvDestination>[
    _TvDestination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Anasayfa',
    ),
    _TvDestination(
      icon: Icons.live_tv_outlined,
      activeIcon: Icons.live_tv,
      label: 'Canli',
    ),
    _TvDestination(
      icon: Icons.movie_outlined,
      activeIcon: Icons.movie,
      label: 'Filmler',
    ),
    _TvDestination(
      icon: Icons.video_library_outlined,
      activeIcon: Icons.video_library,
      label: 'Diziler',
    ),
    _TvDestination(
      icon: Icons.search_outlined,
      activeIcon: Icons.search,
      label: 'Ara',
    ),
    _TvDestination(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Ayarlar',
    ),
  ];

  void _go(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Shortcuts(
        shortcuts: tvShortcuts(),
        child: Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent:
                CallbackAction<DirectionalFocusIntent>(
              onInvoke: (DirectionalFocusIntent intent) {
                FocusManager.instance.primaryFocus
                    ?.focusInDirection(intent.direction);
                return null;
              },
            ),
          },
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Rail(
                  destinations: _destinations,
                  selectedIndex: _index,
                  onSelected: _go,
                ),
                _RailDivider(color: scheme.outline.withValues(alpha: 0.25)),
                Expanded(
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: IndexedStack(
                      index: _index,
                      children: const <Widget>[
                        TvHomeScreen(),
                        TvLiveScreen(),
                        TvVodScreen(),
                        TvSeriesScreen(),
                        TvSearchScreen(),
                        TvSettingsScreen(),
                      ],
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

class _Rail extends StatelessWidget {
  const _Rail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_TvDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            scheme.surface,
            scheme.surface.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceL,
                DesignTokens.spaceL,
                DesignTokens.spaceL,
                DesignTokens.spaceL,
              ),
              child: ShaderMask(
                shaderCallback: (Rect r) =>
                    BrandColors.brandGradient.createShader(r),
                blendMode: BlendMode.srcIn,
                child: const Text(
                  'AWAtv',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceS),
            for (int i = 0; i < destinations.length; i++)
              FocusTraversalOrder(
                order: NumericFocusOrder(i.toDouble()),
                child: LeftRailItem(
                  icon: i == selectedIndex
                      ? destinations[i].activeIcon
                      : destinations[i].icon,
                  label: destinations[i].label,
                  selected: i == selectedIndex,
                  expanded: true,
                  autofocus: i == selectedIndex && i == 0,
                  onTap: () => onSelected(i),
                ),
              ),
            const Spacer(),
            // A subtle hint so first-time TV users know they can press
            // right to enter the grid. Not focusable.
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
                    Icons.arrow_forward,
                    size: 14,
                    color:
                        scheme.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sag tusla iceri gec',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: color);
  }
}

class _TvDestination {
  const _TvDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}
