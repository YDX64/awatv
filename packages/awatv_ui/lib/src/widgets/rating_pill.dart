import 'dart:ui';

import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A frosted, gold-accented rating chip.
///
/// Designed to overlay imagery (poster top-right, hero detail header).
/// Uses a backdrop blur so it remains legible across any backdrop.
class RatingPill extends StatelessWidget {
  const RatingPill({
    required this.rating,
    this.icon = Icons.star_rounded,
    this.iconColor,
    this.compact = false,
    super.key,
  });

  /// Rating value on a 0–10 scale (TMDB convention).
  final double rating;

  /// Icon glyph — defaults to a rounded star.
  final IconData icon;

  /// Override the icon tint. Defaults to a warm gold.
  final Color? iconColor;

  /// Drops typography down a notch — useful inside list rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double fontSize = compact ? 11 : 13;
    final double iconSize = compact ? 12 : 14;
    final padding = EdgeInsets.symmetric(
      horizontal: compact ? DesignTokens.spaceS : DesignTokens.spaceS + 2,
      vertical: compact ? 2 : 4,
    );

    return Semantics(
      label: 'Rating ${rating.toStringAsFixed(1)} out of 10',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: DesignTokens.blurLow,
            sigmaY: DesignTokens.blurLow,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: iconSize,
                  color: iconColor ?? const Color(0xFFFFD24C),
                ),
                const SizedBox(width: 4),
                Text(
                  rating.toStringAsFixed(1),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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
