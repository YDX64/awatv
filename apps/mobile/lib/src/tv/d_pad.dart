import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// D-pad / focus utilities for the 10-foot UI.
///
/// On TV the focus ring is the primary navigation affordance — losing it
/// causes the user to be "stuck" since they can't see what is selected.
/// Helpers here all paint a clearly visible focus state (scale + glow +
/// brand stroke) and respect Material's keyboard activation contract so
/// the regular `Enter` / `Select` keys fall through to `onTap`.

/// Wraps a TV tile (channel logo, poster, settings row) with a focus
/// highlight: scale to 1.05, brand-coloured stroke, and a soft glow.
///
/// `autofocus` is intentionally exposed because TV screens often want to
/// land focus on the first tile of a grid when they open.
class FocusableTile extends StatefulWidget {
  const FocusableTile({
    required this.child,
    this.onTap,
    this.borderRadius,
    this.scaleOnFocus = 1.05,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Defaults to [DesignTokens.radiusL] when null.
  final BorderRadius? borderRadius;

  /// Slight scale factor while focused. 1.05 reads on a 60-inch screen
  /// without making text ugly.
  final double scaleOnFocus;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<FocusableTile> createState() => _FocusableTileState();
}

class _FocusableTileState extends State<FocusableTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ??
        BorderRadius.circular(DesignTokens.radiusL);

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (bool v) => setState(() => _focused = v),
        onShowHoverHighlight: (bool v) {
          // Hover acts like focus on TV — keeps mouse-driven dev sessions
          // visually consistent with what a remote produces.
          if (v != _focused) setState(() => _focused = v);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: DesignTokens.motionFast,
            curve: Curves.easeOutCubic,
            scale: _focused ? widget.scaleOnFocus : 1.0,
            child: AnimatedContainer(
              duration: DesignTokens.motionFast,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _focused
                      ? scheme.primary
                      : scheme.outline.withValues(alpha: 0.0),
                  width: _focused ? 3 : 0,
                ),
                boxShadow: _focused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the side rail. Wraps an icon + optional label and reacts to
/// focus and "selected" state independently — the rail can show what the
/// user is hovering over with the D-pad without losing the marker for the
/// section that is currently rendered.
class LeftRailItem extends StatefulWidget {
  const LeftRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.expanded = false,
    this.autofocus = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// When true the label sits next to the icon. When false (the collapsed
  /// rail used by default) only the icon shows and the label appears in a
  /// tooltip on focus.
  final bool expanded;

  final bool autofocus;

  @override
  State<LeftRailItem> createState() => _LeftRailItemState();
}

class _LeftRailItemState extends State<LeftRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showActive = widget.selected || _focused;

    final iconColor = widget.selected
        ? scheme.primary
        : _focused
            ? scheme.onSurface
            : scheme.onSurface.withValues(alpha: 0.65);

    final tile = AnimatedContainer(
      duration: DesignTokens.motionFast,
      margin: const EdgeInsets.symmetric(
        vertical: DesignTokens.spaceXs,
        horizontal: DesignTokens.spaceS,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        gradient: widget.selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  scheme.primary.withValues(alpha: 0.30),
                  scheme.secondary.withValues(alpha: 0.15),
                ],
              )
            : null,
        color: !widget.selected && _focused
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.8)
            : null,
        border: Border.all(
          color: showActive
              ? scheme.primary.withValues(alpha: _focused ? 0.9 : 0.4)
              : Colors.transparent,
          width: _focused ? 2 : 1,
        ),
        boxShadow: _focused
            ? <BoxShadow>[
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.4),
                  blurRadius: 18,
                ),
              ]
            : const <BoxShadow>[],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.expanded ? DesignTokens.spaceM : DesignTokens.spaceS,
        vertical: DesignTokens.spaceM,
      ),
      child: Row(
        mainAxisAlignment: widget.expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(widget.icon, size: 28, color: iconColor),
          if (widget.expanded) ...<Widget>[
            const SizedBox(width: DesignTokens.spaceM),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    widget.selected ? FontWeight.w700 : FontWeight.w500,
                color: iconColor,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: widget.expanded ? '' : widget.label,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (bool v) => setState(() => _focused = v),
        onShowHoverHighlight: (bool v) {
          if (v != _focused) setState(() => _focused = v);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: tile,
        ),
      ),
    );
  }
}

/// Standard D-pad shortcuts.
///
/// Maps the four arrow keys + `select` to traversal / activation intents
/// so widgets wrapped in a [Shortcuts] can delegate to Flutter's built-in
/// [DefaultTextEditingShortcuts]-style handling.
Map<ShortcutActivator, Intent> tvShortcuts() {
  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const DirectionalFocusIntent(TraversalDirection.up),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const DirectionalFocusIntent(TraversalDirection.down),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const DirectionalFocusIntent(TraversalDirection.left),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const DirectionalFocusIntent(TraversalDirection.right),
    const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter):
        const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonA):
        const ActivateIntent(),
  };
}
