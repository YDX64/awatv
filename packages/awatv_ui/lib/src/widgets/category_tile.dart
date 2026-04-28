import 'package:awatv_ui/src/animations/spring_curves.dart';
import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A single-line tile for the IPTV-Expert-style category-tree sidebar.
///
/// Visual anatomy (left to right):
///   * 4dp brand bar that fades/slides in when the tile is selected.
///   * Optional 24dp leading icon.
///   * Indent — `depth * 16dp` — for nested categories.
///   * Label — 14sp, weight steps up when selected.
///   * Either a count badge ("HD 234") OR an animated chevron when the
///     tile is expandable.
///
/// Behaviour:
///   * `onTap` fires on a single tap — the host decides whether to
///     navigate, expand, or both.
///   * Hover scales the tile to 1.01 and adds a faint brand glow.
///   * Selected gets a soft glass background fill.
///
/// Pure visual primitive — no state. The category-tree feature widget
/// owns expansion, selection, and lifecycle.
class CategoryTile extends StatefulWidget {
  const CategoryTile({
    required this.label,
    this.icon,
    this.count,
    this.selected = false,
    this.expandable = false,
    this.expanded = false,
    this.depth = 0,
    this.onTap,
    super.key,
  });

  /// Category label (e.g. "Movies", "Sports HD").
  final String label;

  /// Optional leading icon. Sized to 24dp.
  final IconData? icon;

  /// Optional trailing count. When provided and the tile is not
  /// [expandable], shown as a badge ("234"). When the value is small
  /// the badge stays compact; when it's wide ("HD 1024") it grows
  /// to fit.
  final String? count;

  /// Selection state — drives the brand bar and background fill.
  final bool selected;

  /// Whether the tile shows a chevron and toggles a child group.
  final bool expandable;

  /// Whether [expandable] tiles are currently open. Drives chevron
  /// rotation (0 → 90deg).
  final bool expanded;

  /// Nesting depth (0 = root). Each step adds 16dp of leading indent.
  final int depth;

  /// Tap callback. The host decides between selection / expansion.
  final VoidCallback? onTap;

  @override
  State<CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<CategoryTile>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _hoverController = AnimationController(
    vsync: this,
    duration: DesignTokens.motionMicroBounce,
    upperBound: 0.01,
  );

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _setHover(bool value) {
    if (_hovering == value) return;
    setState(() => _hovering = value);
    if (value) {
      _hoverController.forward();
    } else {
      _hoverController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    final indent = widget.depth * 16.0;

    final bgFill = widget.selected
        ? scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10)
        : (_hovering
            ? scheme.onSurface.withValues(alpha: 0.04)
            : Colors.transparent);

    final labelStyle = (text.titleSmall ?? const TextStyle()).copyWith(
      color: widget.selected
          ? scheme.onSurface
          : scheme.onSurface.withValues(alpha: 0.78),
      fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0.1,
    );

    final iconColor = widget.selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.72);

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedBuilder(
        animation: _hoverController,
        builder: (BuildContext _, Widget? child) {
          return Transform.scale(
            scale: 1 + _hoverController.value,
            alignment: Alignment.centerLeft,
            child: child,
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: DesignTokens.motionMicroBounce,
            curve: curveSpringSnap,
            constraints: const BoxConstraints(minHeight: 40),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: bgFill,
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              boxShadow: _hovering && widget.onTap != null
                  ? <BoxShadow>[
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: <Widget>[
                _SelectedBar(visible: widget.selected, color: scheme.primary),
                SizedBox(width: 8 + indent),
                if (widget.icon != null) ...<Widget>[
                  Icon(widget.icon, size: 20, color: iconColor),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                ),
                if (widget.expandable)
                  _Chevron(open: widget.expanded, color: iconColor)
                else if (widget.count != null)
                  _CountBadge(
                    label: widget.count!,
                    selected: widget.selected,
                    scheme: scheme,
                  ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBar extends StatelessWidget {
  const _SelectedBar({required this.visible, required this.color});

  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: DesignTokens.motionMicroBounce,
      curve: curveSpringSoft,
      width: 4,
      height: visible ? 16 : 0,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: visible
            ? <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.open, required this.color});

  final bool open;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: DesignTokens.motionMicroBounce,
      curve: curveSpringSnap,
      tween: Tween<double>(begin: 0, end: open ? 1 : 0),
      builder: (BuildContext _, double t, Widget? __) {
        return Transform.rotate(
          // 0 → -90deg so chevron points right when closed, down when open.
          angle: t * 1.5707963, // pi/2
          child: Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: color,
          ),
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.selected,
    required this.scheme,
  });

  final String label;
  final bool selected;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.onSurface.withValues(alpha: 0.08);
    final fg = selected
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.65);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: BrandColors.outlineGlass.withValues(
            alpha: selected ? 0.4 : 0.2,
          ),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: fg,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
