import 'dart:ui';

import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Modal bottom sheet shown when a user attempts to use a gated
/// capability while on the free tier.
///
/// Drives users toward `/premium` with a hint of the unlocked perks.
/// The presentation is glassmorphism over the underlying screen so the
/// sheet feels lightweight and the user keeps context.
class PremiumLockSheet extends StatelessWidget {
  const PremiumLockSheet({
    required this.feature,
    super.key,
  });

  final PremiumFeature feature;

  /// Convenience opener — call from anywhere with a `BuildContext`.
  static Future<void> show(
    BuildContext context,
    PremiumFeature feature,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => PremiumLockSheet(feature: feature),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);

    return AnimatedPadding(
      duration: DesignTokens.motionMedium,
      curve: DesignTokens.motionEmphasized,
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXL),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: DesignTokens.blurMid,
            sigmaY: DesignTokens.blurMid,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              border: const Border(
                top: BorderSide(
                  color: BrandColors.outlineGlass,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceL,
                  DesignTokens.spaceM,
                  DesignTokens.spaceL,
                  DesignTokens.spaceL,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DragHandle(color: theme.colorScheme.onSurface),
                    const SizedBox(height: DesignTokens.spaceM),
                    _Header(feature: feature),
                    const SizedBox(height: DesignTokens.spaceL),
                    const _PerksRow(),
                    const SizedBox(height: DesignTokens.spaceL),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/premium');
                      },
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text('See plans'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spaceM,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusM),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceS),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Maybe later'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.feature});
  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: BrandColors.premiumGradient,
          ),
          child: const Icon(
            Icons.lock_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: DesignTokens.spaceM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Premium feature',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                PremiumFeatureCopy.title(feature),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXs),
              Text(
                PremiumFeatureCopy.subtitle(feature),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PerksRow extends StatelessWidget {
  const _PerksRow();

  static const _perks = <(IconData, String)>[
    (Icons.block_rounded, 'No ads'),
    (Icons.apps_rounded, 'Unlimited\nplaylists'),
    (Icons.picture_in_picture_alt_rounded, 'Multi-screen'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final p in _perks)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceXs,
              ),
              child: _PerkTile(icon: p.$1, label: p.$2),
            ),
          ),
      ],
    );
  }
}

class _PerkTile extends StatelessWidget {
  const _PerkTile({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: DesignTokens.spaceM,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
