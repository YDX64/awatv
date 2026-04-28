import 'package:awatv_ui/src/animations/spring_curves.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A page route that fades in while gently lifting the new screen up by
/// 4 logical pixels.
///
/// Quieter than the default platform transitions — meant for content
/// drilldowns where we want the user's eye to stay on the hero.
class FadeRoute<T> extends PageRoute<T> {
  FadeRoute({
    required this.builder,
    this.duration = DesignTokens.motionMedium,
    this.reverseDuration,
    Curve? curve,
    Curve? reverseCurve,
    this.maintainStateOverride = true,
    this.opaqueOverride = true,
    this.barrierLabelOverride,
    this.fullscreenDialogOverride = false,
    super.settings,
  })  : curve = curve ?? curveSpringSnap,
        reverseCurve = reverseCurve ?? curveSpringSoft;

  /// Builds the destination's body.
  final WidgetBuilder builder;

  /// Forward animation duration.
  final Duration duration;

  /// Reverse animation duration (defaults to [duration]).
  final Duration? reverseDuration;

  /// Forward easing curve. Defaults to [curveSpringSnap] — quick into
  /// the destination, almost no overshoot, feels decisive.
  final Curve curve;

  /// Reverse easing curve. Defaults to [curveSpringSoft] — gentler on
  /// the way back so the user's eye can follow the receding screen.
  final Curve reverseCurve;

  final bool maintainStateOverride;
  final bool opaqueOverride;
  final String? barrierLabelOverride;
  final bool fullscreenDialogOverride;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => barrierLabelOverride;

  @override
  bool get maintainState => maintainStateOverride;

  @override
  bool get opaque => opaqueOverride;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => reverseDuration ?? duration;

  @override
  bool get fullscreenDialog => fullscreenDialogOverride;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: reverseCurve,
    );

    final slide = Tween<Offset>(
      begin: const Offset(0, 0.012), // ~4px on a typical viewport
      end: Offset.zero,
    ).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: slide,
        child: child,
      ),
    );
  }
}
