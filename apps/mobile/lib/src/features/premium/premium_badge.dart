import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Tiny "PRO" pill used to adorn premium-only affordances. The
/// gradient mirrors `BrandColors.premiumGradient` so the badge stays
/// visually anchored to the paywall it leads to.
///
/// Use the `compact` flag to render an icon-only variant for tight
/// spaces (e.g. trailing list rows). Otherwise the pill carries the
/// "PRO" label.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({
    this.compact = false,
    this.label = 'PRO',
    super.key,
  });

  final bool compact;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: BrandColors.premiumGradient,
        ),
        child: const Icon(
          Icons.lock_rounded,
          size: 12,
          color: Colors.white,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        gradient: BrandColors.premiumGradient,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
