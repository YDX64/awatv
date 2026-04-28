import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Centered buffering indicator with a soft black halo for legibility on
/// bright video frames.
///
/// Animates in/out with a 200ms fade so quick HLS rebuffers don't flash
/// the spinner aggressively.
class PlayerBufferingOverlay extends StatelessWidget {
  const PlayerBufferingOverlay({
    required this.visible,
    this.label = 'Tamponlanıyor…',
    super.key,
  });

  /// When false, the overlay is collapsed to a 0-opacity, no-pointer state.
  final bool visible;

  /// Localised buffering string. Defaults to Turkish to match the player
  /// screen's existing copy.
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: DesignTokens.motionStandard,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceL,
              vertical: DesignTokens.spaceM,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(DesignTokens.radiusL),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      BrandColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceS),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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
}
