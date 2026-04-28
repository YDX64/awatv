import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// What gesture-driven adjustment is currently active. The screen displays
/// a transient pill ("Volume +20", "Forward +10s") for non-`none` values.
enum PlayerGestureKind { none, brightness, volume, seek, zoom }

/// Snapshot of an in-progress gesture used to render the side / centre
/// HUD overlay.
@immutable
class PlayerGestureFeedback {
  const PlayerGestureFeedback({
    required this.kind,
    required this.value,
    this.icon,
    this.suffix = '',
    this.onLeftSide = false,
  });

  /// Type of adjustment in progress.
  final PlayerGestureKind kind;

  /// 0..1 fraction for brightness/volume bars, or arbitrary value for seek
  /// (in seconds) — the screen renders different chrome per [kind].
  final double value;

  /// Icon displayed in the pill.
  final IconData? icon;

  /// Free-form suffix appended after the numeric value (e.g. "%", "s").
  final String suffix;

  /// True for left-half drags; the screen anchors brightness/volume pills
  /// accordingly.
  final bool onLeftSide;
}

/// Wrap the player view with this widget to recognise the rich gesture
/// vocabulary of a Netflix-tier UI:
///
/// - single tap → toggle controls
/// - double-tap left half → skip back 10s
/// - double-tap right half → skip forward 10s
/// - vertical drag left half → brightness (host can ignore on web)
/// - vertical drag right half → volume
/// - horizontal drag on bottom 30% → scrub
/// - pinch → toggle BoxFit.contain ↔ BoxFit.cover
///
/// The widget is purely a *recogniser* — it never mutates player state
/// directly; instead it surfaces structured callbacks. This keeps the
/// caller in charge of immersion (e.g. ignoring brightness on web), and
/// makes the component trivial to unit-test against captured callbacks.
class PlayerGestures extends StatefulWidget {
  const PlayerGestures({
    required this.child,
    required this.onTap,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onBrightnessDelta,
    required this.onVolumeDelta,
    required this.onSeekRelative,
    required this.onPinchToggle,
    required this.onGestureFeedback,
    this.enableSeekDrag = true,
    super.key,
  });

  /// The video surface (and any persistent overlays) to gesture over.
  final Widget child;

  /// Single-tap handler — usually toggles control visibility.
  final VoidCallback onTap;

  /// Fired on a double tap landing on the left half of the surface.
  final VoidCallback onSkipBack;

  /// Fired on a double tap landing on the right half of the surface.
  final VoidCallback onSkipForward;

  /// Cumulative brightness delta between -1 and +1. Fired continuously
  /// during a left-side vertical drag. Hosts should clamp the result.
  final ValueChanged<double> onBrightnessDelta;

  /// Cumulative volume delta between -1 and +1. Fired continuously during
  /// a right-side vertical drag.
  final ValueChanged<double> onVolumeDelta;

  /// Relative seek in seconds. Fired on horizontal drag completion.
  final ValueChanged<int> onSeekRelative;

  /// Fired on pinch — toggles between contain and cover fits.
  final VoidCallback onPinchToggle;

  /// Live feedback surface. The host renders this as a transient pill.
  final ValueChanged<PlayerGestureFeedback> onGestureFeedback;

  /// When false, horizontal drag → scrub is suppressed (use for live).
  final bool enableSeekDrag;

  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<PlayerGestures> {
  // Vertical drag accumulators; reset on drag end.
  double _verticalAccum = 0;
  bool _verticalLeft = false;
  double _verticalBaseline = 0;

  // Horizontal drag accumulators.
  double _horizontalAccum = 0;
  double _surfaceWidth = 1;
  double _surfaceHeight = 1;
  bool _seekActive = false;

  void _emitFeedback(PlayerGestureFeedback fb) =>
      widget.onGestureFeedback(fb);

  void _clearFeedback() => _emitFeedback(
        const PlayerGestureFeedback(
          kind: PlayerGestureKind.none,
          value: 0,
        ),
      );

  void _onDoubleTapAt(Offset local) {
    if (local.dx < _surfaceWidth / 2) {
      widget.onSkipBack();
      _emitFeedback(
        const PlayerGestureFeedback(
          kind: PlayerGestureKind.seek,
          value: -10,
          icon: Icons.replay_10_rounded,
          suffix: 's',
          onLeftSide: true,
        ),
      );
    } else {
      widget.onSkipForward();
      _emitFeedback(
        const PlayerGestureFeedback(
          kind: PlayerGestureKind.seek,
          value: 10,
          icon: Icons.forward_10_rounded,
          suffix: 's',
        ),
      );
    }
    Future<void>.delayed(const Duration(milliseconds: 600), _clearFeedback);
  }

  void _onVerticalStart(DragStartDetails d) {
    _verticalLeft = d.localPosition.dx < _surfaceWidth / 2;
    _verticalAccum = 0;
    _verticalBaseline = d.localPosition.dy;
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    // Drag up == positive delta; we use surface-height as the full range
    // so a half-screen drag moves the value by 50%.
    final raw = -(d.localPosition.dy - _verticalBaseline) / _surfaceHeight;
    final clamped = raw.clamp(-1.0, 1.0);
    final delta = clamped - _verticalAccum;
    _verticalAccum = clamped;
    if (_verticalLeft) {
      widget.onBrightnessDelta(delta);
      _emitFeedback(
        PlayerGestureFeedback(
          kind: PlayerGestureKind.brightness,
          value: clamped,
          icon: Icons.light_mode_rounded,
          suffix: '%',
          onLeftSide: true,
        ),
      );
    } else {
      widget.onVolumeDelta(delta);
      _emitFeedback(
        PlayerGestureFeedback(
          kind: PlayerGestureKind.volume,
          value: clamped,
          icon: Icons.volume_up_rounded,
          suffix: '%',
        ),
      );
    }
  }

  void _onVerticalEnd(DragEndDetails d) {
    Future<void>.delayed(
      const Duration(milliseconds: 350),
      _clearFeedback,
    );
  }

  void _onHorizontalStart(DragStartDetails d) {
    if (!widget.enableSeekDrag) return;
    // Only engage scrub when the drag starts in the bottom 30% — keeps the
    // recogniser from clashing with the controls layer.
    final fromBottom = _surfaceHeight - d.localPosition.dy;
    _seekActive = fromBottom < _surfaceHeight * 0.3;
    _horizontalAccum = 0;
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    if (!_seekActive) return;
    _horizontalAccum += d.delta.dx;
    // 1 pixel == 0.25s, so a full-width swipe scrubs ~screen-width/4 sec.
    final seconds = (_horizontalAccum * 0.25).round();
    _emitFeedback(
      PlayerGestureFeedback(
        kind: PlayerGestureKind.seek,
        value: seconds.toDouble(),
        icon: seconds >= 0
            ? Icons.fast_forward_rounded
            : Icons.fast_rewind_rounded,
        suffix: 's',
      ),
    );
  }

  void _onHorizontalEnd(DragEndDetails d) {
    if (!_seekActive) return;
    final seconds = (_horizontalAccum * 0.25).round();
    if (seconds.abs() > 0) widget.onSeekRelative(seconds);
    _seekActive = false;
    _horizontalAccum = 0;
    Future<void>.delayed(
      const Duration(milliseconds: 400),
      _clearFeedback,
    );
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Pinch heuristic: any non-trivial scale change at lift-off toggles fit.
    if (d.velocity.pixelsPerSecond.distance > 200) {
      widget.onPinchToggle();
      _emitFeedback(
        const PlayerGestureFeedback(
          kind: PlayerGestureKind.zoom,
          value: 1,
          icon: Icons.aspect_ratio_rounded,
        ),
      );
      Future<void>.delayed(
        const Duration(milliseconds: 600),
        _clearFeedback,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints constraints) {
        _surfaceWidth = constraints.maxWidth;
        _surfaceHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: (TapDownDetails d) => _onDoubleTapAt(d.localPosition),
          onDoubleTap: () {},
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onVerticalDragEnd: _onVerticalEnd,
          onHorizontalDragStart: _onHorizontalStart,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          onHorizontalDragEnd: _onHorizontalEnd,
          onScaleEnd: _onScaleEnd,
          child: widget.child,
        );
      },
    );
  }
}

/// Transient HUD pill rendered while a gesture is in progress.
///
/// Sits inside the gesture overlay and listens for the latest
/// [PlayerGestureFeedback] from a parent stream. The pill is centred
/// horizontally and anchored 40% from the top.
class PlayerGestureHud extends StatelessWidget {
  const PlayerGestureHud({required this.feedback, super.key});

  final PlayerGestureFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final visible = feedback.kind != PlayerGestureKind.none;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: DesignTokens.motionFast,
        curve: DesignTokens.motionStandard,
        child: Align(
          alignment: const Alignment(0, -0.4),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceL,
              vertical: DesignTokens.spaceM,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (feedback.icon != null)
                  Icon(feedback.icon, color: Colors.white, size: 22),
                if (feedback.icon != null)
                  const SizedBox(width: DesignTokens.spaceS),
                Text(
                  _label(feedback),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _label(PlayerGestureFeedback fb) {
    switch (fb.kind) {
      case PlayerGestureKind.brightness:
      case PlayerGestureKind.volume:
        final pct = (fb.value.abs() * 100).clamp(0, 100).round();
        final sign = fb.value >= 0 ? '+' : '-';
        return '$sign$pct${fb.suffix}';
      case PlayerGestureKind.seek:
        final v = fb.value.round();
        final sign = v >= 0 ? '+' : '';
        return '$sign$v${fb.suffix}';
      case PlayerGestureKind.zoom:
        return 'Yakınlaştırma';
      case PlayerGestureKind.none:
        return '';
    }
  }
}
