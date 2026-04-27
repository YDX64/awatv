import 'dart:ui';

import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A frosted-glass CTA used for prominent actions on top of imagery
/// (hero details, player overlays, onboarding hero).
///
/// Combines a `BackdropFilter` blur with a translucent gradient and a
/// hairline outline so the surface reads as glass on any backdrop.
class GlassButton extends StatefulWidget {
  const GlassButton({
    required this.child,
    required this.onPressed,
    this.tint,
    this.icon,
    this.semanticsLabel,
    this.expand = false,
    super.key,
  });

  /// Label widget — typically a `Text`. Provide an [icon] for combined
  /// icon + label layouts.
  final Widget child;

  /// Tap callback. Pass `null` to render a disabled state.
  final VoidCallback? onPressed;

  /// Optional brand tint overlaid on the glass; defaults to the theme
  /// primary at low alpha.
  final Color? tint;

  /// Optional leading icon.
  final IconData? icon;

  /// Accessibility label override; used when the [child] is purely
  /// decorative.
  final String? semanticsLabel;

  /// Stretch to fill the parent's cross-axis.
  final bool expand;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesignTokens.motionFast,
    upperBound: 0.06,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(_) {
    if (widget.onPressed == null) return;
    _controller.forward();
  }

  void _up(_) {
    if (widget.onPressed == null) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onPressed != null;

    final tint = widget.tint ?? scheme.primary;
    final labelColor = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.4);

    return Semantics(
      label: widget.semanticsLabel,
      button: true,
      enabled: enabled,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext _, Widget? __) {
          final t = _controller.value;
          return Transform.scale(
            scale: 1 - t,
            child: Opacity(
              opacity: enabled ? 1 : 0.6,
              child: GestureDetector(
                onTapDown: _down,
                onTapUp: _up,
                onTapCancel: () => _controller.reverse(),
                onTap: widget.onPressed,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusXL),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: DesignTokens.blurMid,
                      sigmaY: DesignTokens.blurMid,
                    ),
                    child: Container(
                      width: widget.expand ? double.infinity : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceL,
                        vertical: DesignTokens.spaceM,
                      ),
                      constraints: const BoxConstraints(
                        minHeight: DesignTokens.minTapTarget,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            tint.withValues(alpha: 0.32),
                            tint.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.04),
                          ],
                          stops: const <double>[0, 0.55, 1],
                        ),
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusXL),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: tint.withValues(alpha: 0.22),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: widget.expand
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (widget.icon != null) ...<Widget>[
                            Icon(
                              widget.icon,
                              size: 20,
                              color: labelColor,
                            ),
                            const SizedBox(width: DesignTokens.spaceS),
                          ],
                          DefaultTextStyle.merge(
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: labelColor,
                              letterSpacing: 0.4,
                            ),
                            child: widget.child,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
