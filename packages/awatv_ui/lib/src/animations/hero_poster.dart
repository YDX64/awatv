import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// Helpers for poster → detail Hero transitions.
///
/// Use [HeroPoster.tagFor] to keep tag generation consistent across
/// the list / detail screens, and [HeroPoster.posterShuttle] as the
/// `flightShuttleBuilder` on either Hero. The shuttle interpolates
/// border-radius and elevation so the poster glides into a full-bleed
/// detail backdrop without a "pop" at the seams.
class HeroPoster {
  const HeroPoster._();

  /// Build a deterministic Hero tag for a piece of content. Keeping the
  /// helper centralised avoids tag mismatches between rails and detail
  /// screens.
  static String tagFor({required String kind, required String id}) {
    return 'awatv-$kind-$id';
  }

  /// Standard shuttle builder for poster Hero transitions.
  ///
  /// Animates the rounded-corner radius from the source card to a flat
  /// (full-bleed) detail header, and adds a subtle drop shadow at mid
  /// flight to reinforce the lift-off feeling.
  static HeroFlightShuttleBuilder posterShuttle({
    double fromRadius = DesignTokens.radiusL,
    double toRadius = 0,
    double maxElevation = 24,
  }) {
    return (
      BuildContext flightContext,
      Animation<double> animation,
      HeroFlightDirection flightDirection,
      BuildContext fromHeroContext,
      BuildContext toHeroContext,
    ) {
      final toHero = toHeroContext.widget;
      // Always render the destination's child so the shuttle matches
      // what the user is about to see.
      final child = toHero is Hero ? toHero.child : toHero;

      final curved = CurvedAnimation(
        parent: animation,
        curve: DesignTokens.motionEmphasized,
        reverseCurve: DesignTokens.motionStandard.flipped,
      );

      return AnimatedBuilder(
        animation: curved,
        builder: (BuildContext _, Widget? built) {
          // 0 = from, 1 = to.
          final t = curved.value;
          final radius =
              fromRadius + (toRadius - fromRadius) * t;
          // Bell-curve elevation: peaks mid-flight, lands flush.
          final bell = (4 * t * (1 - t)).clamp(0.0, 1.0);
          final elevation = bell * maxElevation;
          return Material(
            color: Colors.transparent,
            elevation: elevation,
            shadowColor: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(radius),
            clipBehavior: Clip.antiAlias,
            child: built,
          );
        },
        child: child,
      );
    };
  }

  /// A `Hero` widget pre-wired with the standard shuttle for posters.
  ///
  /// Drop into either the list cell or the detail header — pass the
  /// same [tag] on both ends.
  static Widget hero({
    required String tag,
    required Widget child,
    Key? key,
  }) {
    return Hero(
      key: key,
      tag: tag,
      flightShuttleBuilder: posterShuttle(),
      child: child,
    );
  }
}
