import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// What flavour of network / quality state a [NetworkStatusBadge] represents.
///
/// `live`     — currently airing live content. Pulses red.
/// `buffering` — stalled / rebuffering. Pulses warning-amber.
/// `lowBandwidth` — degraded but playing. Static warning-amber.
/// `offline`  — connection lost. Static error-red.
/// `hd`       — 1080p / HD playback. Static brand-cyan.
/// `fourK`    — 4K / UHD. Brand gradient with the "4K" label.
enum NetworkStatusKind { live, buffering, lowBandwidth, offline, hd, fourK }

/// A compact inline badge surfacing the current stream state.
///
/// Drop into a player overlay, channel tile corner, or VOD detail header
/// to communicate quality at a glance. Each variant has its own colour,
/// icon and label; `live` and `buffering` pulse to read as alive.
///
/// Use [compact] to render the icon-only pill (with an a11y semantics
/// label still present), useful inside dense tiles.
class NetworkStatusBadge extends StatefulWidget {
  const NetworkStatusBadge({
    required this.kind,
    this.compact = false,
    super.key,
  });

  /// Variant to render.
  final NetworkStatusKind kind;

  /// When true, only the icon (and dot, if any) is shown — the text
  /// label is collapsed but remains in the accessibility tree.
  final bool compact;

  @override
  State<NetworkStatusBadge> createState() => _NetworkStatusBadgeState();
}

class _NetworkStatusBadgeState extends State<NetworkStatusBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  bool get _isPulsing =>
      widget.kind == NetworkStatusKind.live ||
      widget.kind == NetworkStatusKind.buffering;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant NetworkStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_isPulsing) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: widget.kind == NetworkStatusKind.buffering
            ? const Duration(milliseconds: 900)
            : const Duration(milliseconds: 1300),
      );
      if (!_pulse!.isAnimating) {
        _pulse!.repeat(reverse: true);
      }
    } else {
      _pulse?.stop();
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final spec = _specFor(widget.kind, scheme);

    final icon = Icon(spec.icon, size: 13, color: spec.foreground);
    final label = Text(
      spec.label,
      style: theme.labelSmall?.copyWith(
        color: spec.foreground,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_isPulsing)
          _PulseDot(
            color: spec.dotColor,
            controller: _pulse!,
          )
        else
          icon,
        if (!widget.compact) ...<Widget>[
          const SizedBox(width: 4),
          label,
        ],
      ],
    );

    Widget badge = Container(
      constraints: const BoxConstraints(
        minHeight: 24,
        minWidth: 24,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 6 : DesignTokens.spaceS,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        gradient: spec.gradient,
        color: spec.gradient == null ? spec.background : null,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: spec.border,
          width: 0.6,
        ),
        boxShadow: spec.glow == null
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: spec.glow!,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: content,
    );

    if (widget.compact) {
      // Keep it square-ish for icon-only mode.
      badge = Center(child: badge);
    }

    return Semantics(
      label: spec.semanticLabel,
      liveRegion: _isPulsing,
      child: badge,
    );
  }

  static _BadgeSpec _specFor(NetworkStatusKind kind, ColorScheme scheme) {
    switch (kind) {
      case NetworkStatusKind.live:
        return _BadgeSpec(
          label: 'LIVE',
          semanticLabel: 'Currently broadcasting live',
          icon: Icons.fiber_manual_record_rounded,
          foreground: Colors.white,
          background: scheme.error.withValues(alpha: 0.92),
          border: Colors.white.withValues(alpha: 0.18),
          dotColor: Colors.white,
          glow: scheme.error.withValues(alpha: 0.35),
        );
      case NetworkStatusKind.buffering:
        return _BadgeSpec(
          label: 'BUFFERING',
          semanticLabel: 'Buffering, network may be unstable',
          icon: Icons.hourglass_top_rounded,
          foreground: Colors.white,
          background: BrandColors.warning.withValues(alpha: 0.92),
          border: Colors.white.withValues(alpha: 0.16),
          dotColor: Colors.white,
          glow: BrandColors.warning.withValues(alpha: 0.32),
        );
      case NetworkStatusKind.lowBandwidth:
        return _BadgeSpec(
          label: 'LOW BW',
          semanticLabel: 'Low bandwidth — quality reduced',
          icon: Icons.signal_cellular_alt_rounded,
          foreground: BrandColors.warning,
          background: BrandColors.warning.withValues(alpha: 0.16),
          border: BrandColors.warning.withValues(alpha: 0.45),
        );
      case NetworkStatusKind.offline:
        return _BadgeSpec(
          label: 'OFFLINE',
          semanticLabel: 'Connection lost',
          icon: Icons.cloud_off_rounded,
          foreground: scheme.error,
          background: scheme.error.withValues(alpha: 0.16),
          border: scheme.error.withValues(alpha: 0.45),
        );
      case NetworkStatusKind.hd:
        return _BadgeSpec(
          label: 'HD',
          semanticLabel: 'High definition stream',
          icon: Icons.high_quality_rounded,
          foreground: scheme.secondary,
          background: scheme.secondary.withValues(alpha: 0.16),
          border: scheme.secondary.withValues(alpha: 0.45),
        );
      case NetworkStatusKind.fourK:
        return _BadgeSpec(
          label: '4K',
          semanticLabel: 'Ultra HD 4K stream',
          icon: Icons.auto_awesome_rounded,
          foreground: Colors.white,
          background: Colors.transparent,
          gradient: BrandColors.brandGradient,
          border: Colors.white.withValues(alpha: 0.22),
          glow: scheme.primary.withValues(alpha: 0.28),
        );
    }
  }
}

class _BadgeSpec {
  const _BadgeSpec({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
    this.gradient,
    this.dotColor,
    this.glow,
  });

  final String label;
  final String semanticLabel;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;
  final Gradient? gradient;
  final Color? dotColor;
  final Color? glow;
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color, required this.controller});

  final Color color;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext _, Widget? __) {
        final t = controller.value;
        return SizedBox(
          width: 9,
          height: 9,
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7 + 0.3 * t),
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.35 + 0.35 * t),
                    blurRadius: 4 + 4 * t,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
