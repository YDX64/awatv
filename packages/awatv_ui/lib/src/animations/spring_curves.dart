import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Physics-based easing curves for AWAtv.
///
/// Most Flutter widgets accept a [Curve] (not a `Simulation`) so we wrap
/// our [SpringDescription]s in a [Curve] subclass and pre-compute the
/// simulation once at construction. The [transform] call becomes a cheap
/// `simulation.x(t)` lookup instead of allocating a fresh simulation per
/// frame — important when these curves drive list-cell hovers and scroll
/// reveals 60+ times per second.
///
/// Three presets, in increasing playfulness:
///
///   * [curveSpringSnap]    — fast snap, almost no overshoot.
///                            Good for press feedback, chip toggles.
///   * [curveSpringSoft]    — gentle settle, single subtle overshoot.
///                            Good for hero flights, modal entrances.
///   * [curveSpringFloaty]  — overshoots noticeably, takes a moment to
///                            settle. Good for celebratory micro-moments
///                            (favourite added, badge earned).
///
/// All three rest at 1.0; passing them to `CurvedAnimation` /
/// `AnimatedFoo` widgets behaves identically to any built-in Flutter
/// curve.
class SpringCurve extends Curve {
  /// Build a curve from a [SpringDescription]. The simulation is
  /// allocated once in the constructor and reused for every frame.
  ///
  /// [from] / [to] define the start and end positions for the
  /// underlying spring; the curve itself always remaps the result so
  /// that `transform(0) ≈ 0` and `transform(1) ≈ 1`, regardless of any
  /// transient overshoot.
  SpringCurve({
    required this.spring,
    this.from = 0,
    this.to = 1,
  })  : _simulation = SpringSimulation(spring, from, to, 0),
        _settleTime = _solveSettleTime(spring, from, to);

  /// Convenience: build a SpringCurve from raw mass/stiffness/damping
  /// numbers without having to import `package:flutter/physics.dart`
  /// at the call site.
  factory SpringCurve.from({
    required double mass,
    required double stiffness,
    required double damping,
  }) {
    return SpringCurve(
      spring: SpringDescription(
        mass: mass,
        stiffness: stiffness,
        damping: damping,
      ),
    );
  }

  /// Underlying spring physics description.
  final SpringDescription spring;

  /// Resting start position.
  final double from;

  /// Resting end position.
  final double to;

  final SpringSimulation _simulation;
  final double _settleTime;

  /// Approximate settle time in seconds. Useful for tuning surrounding
  /// `Duration`s (e.g. when chaining a follow-on animation).
  double get settleTime => _settleTime;

  @override
  double transformInternal(double t) {
    // Map curve [0..1] onto the simulation's settle window so the
    // animation completes in lockstep with the host AnimationController
    // duration. The user-visible animation thus blends the controller's
    // duration with the spring's character.
    final simT = t * _settleTime;
    final value = _simulation.x(simT);
    final span = to - from;
    if (span == 0) return t;
    return ((value - from) / span).clamp(-0.5, 1.5);
  }

  /// Find the time at which the spring is "done" — i.e. velocity and
  /// distance from rest both fall below the simulation's tolerance.
  /// Caps at 4s so a degenerate input never freezes the UI.
  static double _solveSettleTime(
    SpringDescription spring,
    double from,
    double to,
  ) {
    final probe = SpringSimulation(spring, from, to, 0);
    const step = 1 / 60.0;
    double t = 0;
    while (t < 4 && !probe.isDone(t)) {
      t += step;
    }
    // A small floor avoids divide-by-zero when a heavily damped spring
    // settles within a single frame.
    return t < step ? step : t;
  }
}

/// Fast snap, almost no overshoot. Default for tactile UI feedback —
/// press states, chip toggles, sidebar item selection.
///
/// (mass:1, stiffness:550, damping:18)
final SpringCurve curveSpringSnap = SpringCurve.from(
  mass: 1,
  stiffness: 550,
  damping: 18,
);

/// Gentle settle with a single subtle overshoot. Default for poster
/// hero flights, modal entrances, route transitions.
///
/// (mass:1, stiffness:280, damping:24)
final SpringCurve curveSpringSoft = SpringCurve.from(
  mass: 1,
  stiffness: 280,
  damping: 24,
);

/// Overshoots noticeably and takes a moment to settle. Reserve for
/// celebratory micro-moments — favourite tap, badge unlock, "added to
/// watchlist" toast.
///
/// (mass:1.5, stiffness:200, damping:14)
final SpringCurve curveSpringFloaty = SpringCurve.from(
  mass: 1.5,
  stiffness: 200,
  damping: 14,
);
