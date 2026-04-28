import 'dart:ui';

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

    // Premium top-tinted glow: kicks in only when the caller dialled
    // the intensity past 1.0 (i.e. they explicitly want extra depth).
    // A soft brand-tinted blur over the top 20% mimics the way light
    // bleeds across a glass panel above an image, lending the surface
    // the kind of layered feel premium IPTV apps lean on for hero
    // panels and player chrome — without breaking the API.
    final boost = (clamped - 1.0).clamp(0.0, 1.0);
    final overlay = boost > 0
        ? Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const <double>[0, 0.22, 1],
                        colors: <Color>[
                          // Cool brand tint at the very top — blends
                          // into the hero image rather than masking it.
                          Color.fromRGBO(
                            108,
                            92,
                            231,
                            (0.10 * boost).clamp(0.0, 0.18),
                          ),
                          Color.fromRGBO(
                            108,
                            92,
                            231,
                            (0.04 * boost).clamp(0.0, 0.08),
                          ),
                          const Color(0x00000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : null;

    final c = child;
    if (c == null) {
      // No child: render only the gradient — caller stacks us themselves.
      return overlay == null
          ? gradient
          : Stack(
              fit: StackFit.passthrough,
              children: <Widget>[gradient, overlay],
            );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        c,
        gradient,
        if (overlay != null) overlay,
      ],
    );
  }
}
