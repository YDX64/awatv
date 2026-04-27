import 'package:flutter/material.dart';


/// A subtle linear gradient overlay used to keep text legible on top of
/// imagery. Default flow is transparent at the top, dark at the bottom —
/// the classic poster legibility scrim.
///
/// Wrap any image-bearing widget with this; the child is stacked first,
/// then the scrim, then any caption you add via `Stack`.
class GradientScrim extends StatelessWidget {
  const GradientScrim({
    this.child,
    this.from = Alignment.topCenter,
    this.to = Alignment.bottomCenter,
    this.begin,
    this.end,
    this.stops,
    this.colors,
    this.intensity = 1.0,
    super.key,
  });

  /// What the scrim sits on top of (typically a network image). When null,
  /// the widget renders just the gradient — useful as a `Positioned.fill`
  /// child inside a `Stack`.
  final Widget? child;

  /// Gradient origin (use either [from] or [begin]).
  final Alignment from;

  /// Gradient terminus (use either [to] or [end]).
  final Alignment to;

  /// Alias for [from] following Flutter's `LinearGradient` naming.
  final Alignment? begin;

  /// Alias for [to] following Flutter's `LinearGradient` naming.
  final Alignment? end;

  /// Optional custom stops.
  final List<double>? stops;

  /// Optional custom colour list. When null, a transparent → near-black
  /// curve is used.
  final List<Color>? colors;

  /// Multiplier on the default scrim alpha. Useful for posters versus
  /// full-bleed backdrops where you may want a stronger or lighter veil.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final clamped = intensity.clamp(0.0, 2.0);
    final resolved = colors ??
        <Color>[
          const Color(0x00000000),
          Color.fromRGBO(0, 0, 0, (0.45 * clamped).clamp(0.0, 0.85)),
          Color.fromRGBO(0, 0, 0, (0.85 * clamped).clamp(0.0, 0.95)),
        ];

    final resolvedStops =
        stops ?? const <double>[0, 0.6, 1];

    // Resolve LinearGradient-style aliases when supplied.
    final effectiveBegin = begin ?? from;
    final effectiveEnd = end ?? to;

    final Widget gradient = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: effectiveBegin,
              end: effectiveEnd,
              colors: resolved,
              stops: resolvedStops,
            ),
          ),
        ),
      ),
    );

    final c = child;
    if (c == null) {
      // No child: render only the gradient — caller stacks us themselves.
      return gradient;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[c, gradient],
    );
  }
}
