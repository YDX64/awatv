import 'dart:ui';

import 'package:awatv_mobile/src/desktop/widgets/sidebar_prefs.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Section in the sidebar. Each one renders as a single rail row.
///
/// `route` may be null when the section is "coming soon" — those rows
/// stay clickable but only show a non-blocking SnackBar.
@immutable
class SidebarSection {
  const SidebarSection({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    this.comingSoon = false,
    this.shortcut,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String? route;
  final bool comingSoon;

  /// Optional keyboard shortcut hint shown on the right of the row when
  /// the sidebar is expanded. Decorative only — the shortcut is wired up
  /// elsewhere.
  final String? shortcut;
}

/// IPTV-Expert-class collapsible sidebar.
///
/// Two states:
///   * **Collapsed** ([DesignTokens.sidebarWidthCollapsed], 72dp): icon
///     column, labels become tooltips, the toggle becomes a chevron-right
///     glyph at the top.
///   * **Expanded** ([DesignTokens.sidebarWidthExpanded], 240dp): brand
///     mark + search hint at the top, full labels next to icons, profile
///     pill at the bottom with the active profile name.
///
/// State lives in [sidebarCollapsedProvider] and is persisted to Hive
/// under `prefs:desktop.sidebar.collapsed` so the choice carries across
/// app restarts (matching IPTV Expert's behaviour).
class IpxSidebar extends ConsumerWidget {
  const IpxSidebar({
    required this.sections,
    required this.activeRoute,
    this.onNavigate,
    super.key,
  });

  /// Ordered list of rail items.
  final List<SidebarSection> sections;

  /// Currently-active route — used to highlight the matching item.
  final String activeRoute;

  /// Callback when the user taps a navigable section. Defaults to
  /// `context.go(route)` when null.
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final width = collapsed
        ? DesignTokens.sidebarWidthCollapsed
        : DesignTokens.sidebarWidthExpanded;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Glass surface + subtle gradient overlay. Inspired by what we
    // observed in the IPTV Expert / ipTV references — but tuned to the
    // AWAtv brand palette so we never copy their exact colour values.
    final bgAlpha = isDark
        ? DesignTokens.glassBgAlphaDark + 0.30 // 0.85 — sidebar is dense
        : DesignTokens.glassBgAlphaLight;

    return AnimatedContainer(
      duration: DesignTokens.motionPanelSlide,
      curve: DesignTokens.motionStandard,
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: bgAlpha),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.10),
            Colors.transparent,
            scheme.secondary.withValues(alpha: 0.05),
          ],
          stops: const <double>[0, 0.5, 1],
        ),
        border: Border(
          right: BorderSide(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: DesignTokens.glassBlurMedium,
            sigmaY: DesignTokens.glassBlurMedium,
          ),
          child: SafeArea(
            right: false,
            child: Column(
              children: <Widget>[
                _Header(collapsed: collapsed),
                _SearchPill(collapsed: collapsed),
                const SizedBox(height: DesignTokens.spaceXs),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: DesignTokens.spaceXs,
                    ),
                    physics: const ClampingScrollPhysics(),
                    itemCount: sections.length,
                    itemBuilder: (BuildContext ctx, int i) {
                      final s = sections[i];
                      return _SidebarRow(
                        section: s,
                        collapsed: collapsed,
                        active: _routeMatches(activeRoute, s.route),
                        onTap: () => _handleTap(context, s),
                      );
                    },
                  ),
                ),
                _Footer(collapsed: collapsed),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _routeMatches(String active, String? route) {
    if (route == null) return false;
    if (active == route) return true;
    // Sub-routes still light up the parent (e.g. /live/epg lights /live).
    return active.startsWith('$route/');
  }

  void _handleTap(BuildContext context, SidebarSection s) {
    if (s.comingSoon) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${s.label} — yakinda'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final route = s.route;
    if (route == null) return;
    if (onNavigate != null) {
      onNavigate!(route);
    } else {
      context.go(route);
    }
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 0 : DesignTokens.spaceL,
        DesignTokens.spaceM,
        collapsed ? 0 : DesignTokens.spaceM,
        DesignTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          if (!collapsed)
            Expanded(
              child: ShaderMask(
                shaderCallback: (Rect r) =>
                    BrandColors.brandGradient.createShader(r),
                blendMode: BlendMode.srcIn,
                child: const Text(
                  'AWAtv',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: ShaderMask(
                  shaderCallback: (Rect r) =>
                      BrandColors.brandGradient.createShader(r),
                  blendMode: BlendMode.srcIn,
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          Tooltip(
            message: collapsed ? 'Genislet' : 'Daralt',
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              splashRadius: 20,
              iconSize: 18,
              icon: AnimatedRotation(
                turns: collapsed ? 0 : 0.5,
                duration: DesignTokens.motionMicroBounce,
                child: const Icon(Icons.chevron_right_rounded),
              ),
              color: scheme.onSurface.withValues(alpha: 0.65),
              onPressed: () =>
                  ref.read(sidebarCollapsedProvider.notifier).toggle(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceXs,
          vertical: DesignTokens.spaceXs,
        ),
        child: Tooltip(
          message: 'Ara (Ctrl+F)',
          child: SizedBox(
            height: 36,
            child: Material(
              color: scheme.surface.withValues(alpha: 0.6),
              borderRadius:
                  BorderRadius.circular(DesignTokens.radiusM),
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusM),
                onTap: () => context.push('/search'),
                child: Center(
                  child: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceXs,
      ),
      child: SizedBox(
        height: 36,
        child: Material(
          color: scheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            onTap: () => context.push('/search'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceM,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  Expanded(
                    child: Text(
                      'Ara...',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusS),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Ctrl F',
                      style: TextStyle(
                        fontSize: 10,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        color:
                            scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.section,
    required this.collapsed,
    required this.active,
    required this.onTap,
  });

  final SidebarSection section;
  final bool collapsed;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.active;
    final disabled = widget.section.comingSoon;

    final fg = disabled
        ? scheme.onSurface.withValues(alpha: 0.32)
        : selected
            ? scheme.primary
            : _hover
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.78);

    final bgColor = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : (_hover && !disabled
            ? scheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent);

    final row = AnimatedContainer(
      duration: DesignTokens.motionFast,
      curve: Curves.easeOut,
      height: 42,
      margin: EdgeInsets.symmetric(
        horizontal: widget.collapsed ? 6 : DesignTokens.spaceXs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        boxShadow: _hover && !disabled && !selected
            ? <BoxShadow>[
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.18),
                  blurRadius: 12,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Stack(
        children: <Widget>[
          if (selected)
            Positioned(
              left: 4,
              top: 8,
              bottom: 8,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: BrandColors.brandGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal:
                  widget.collapsed ? 0 : DesignTokens.spaceM,
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: <Widget>[
                Icon(
                  selected
                      ? widget.section.activeIcon
                      : widget.section.icon,
                  size: 20,
                  color: fg,
                ),
                if (!widget.collapsed) ...<Widget>[
                  const SizedBox(width: DesignTokens.spaceM),
                  Expanded(
                    child: Text(
                      widget.section.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (disabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiary
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusS,
                        ),
                      ),
                      child: Text(
                        'YAKINDA',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: scheme.tertiary,
                        ),
                      ),
                    )
                  else if (widget.section.shortcut != null)
                    Text(
                      widget.section.shortcut!,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurface
                            .withValues(alpha: 0.45),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: widget.collapsed ? widget.section.label : '',
      child: MouseRegion(
        cursor: disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: DesignTokens.motionFast,
            curve: Curves.easeOut,
            scale: _hover && !disabled ? 1.02 : 1.0,
            child: row,
          ),
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final activeProfile = ref.watch(activeProfileProvider);

    final initials = (activeProfile?.name.isNotEmpty ?? false)
        ? activeProfile!.name.trim()[0].toUpperCase()
        : 'A';
    final displayName = activeProfile?.name ?? 'Misafir';

    final avatar = Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        gradient: BrandColors.brandGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          DesignTokens.spaceXs,
          0,
          DesignTokens.spaceM,
        ),
        child: Tooltip(
          message: '$displayName • Profil degistir',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/profiles'),
            child: Center(child: avatar),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceS,
        DesignTokens.spaceS,
        DesignTokens.spaceM,
      ),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          onTap: () => context.push('/profiles'),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceS),
            child: Row(
              children: <Widget>[
                avatar,
                const SizedBox(width: DesignTokens.spaceS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Profil degistir',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
