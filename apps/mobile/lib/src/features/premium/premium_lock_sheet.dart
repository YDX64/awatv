import 'dart:ui';

import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Visual treatment for an inline premium gate.
///
/// Mirrors the two render modes of `components/PremiumGate.tsx` in the
/// Streas RN reference. Both routes the user to `/premium` on tap; the
/// modal `show()` helper remains the third presentation for places that
/// want a bottom sheet rather than an inline replacement.
enum PremiumLockMode {
  /// Compact pill row with a left-aligned lock icon, two-line copy and
  /// a cherry "Upgrade" button on the right. Default treatment for
  /// "in-line" gating in lists and forms.
  banner,

  /// Children are rendered at 25 % opacity behind a translucent blur
  /// overlay carrying a centred "Premium feature" + Unlock CTA. Use
  /// when you want to tease the gated UI without removing it.
  overlay,
}

/// Premium lock surface shown when a free-tier user tries to use a
/// gated capability.
///
/// `PremiumLockSheet` keeps its legacy bottom-sheet `show()` entry
/// point so the dozen-plus call sites scattered across the app keep
/// working unchanged. The new constructor adds inline `banner` and
/// `overlay` treatments to match the Streas RN `<PremiumGate>` widget.
///
/// All three presentations route the user to `/premium` (the paywall)
/// when tapped.
class PremiumLockSheet extends StatelessWidget {
  /// Inline-banner / overlay constructor used when wrapping a gated
  /// widget inline. The gating itself (free vs premium) is left to
  /// the caller — this widget is purely the presentation.
  ///
  /// In [PremiumLockMode.banner] mode [child] is ignored and the row
  /// itself is the visible treatment. In [PremiumLockMode.overlay]
  /// mode the [child] is rendered at 25 % opacity beneath a blurred
  /// translucent overlay.
  const PremiumLockSheet({
    required this.feature,
    this.mode = PremiumLockMode.banner,
    this.child,
    super.key,
  });

  final PremiumFeature feature;
  final PremiumLockMode mode;
  final Widget? child;

  /// Bottom-sheet entry point used by code that wants the legacy modal
  /// presentation. New code should prefer [PremiumLockSheet] directly
  /// for an inline banner, or wrap a widget in [PremiumLockMode.overlay].
  static Future<void> show(
    BuildContext context,
    PremiumFeature feature,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _PremiumLockBottomSheet(feature: feature),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case PremiumLockMode.banner:
        return _GateBanner(feature: feature);
      case PremiumLockMode.overlay:
        return _GateOverlay(
          feature: feature,
          child: child ?? const SizedBox.shrink(),
        );
    }
  }
}

// =============================================================================
// Inline banner — pill with lock icon + "Upgrade"
// =============================================================================

class _GateBanner extends StatelessWidget {
  const _GateBanner({required this.feature});

  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/premium'),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          decoration: BoxDecoration(
            color: BrandColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            border: Border.all(
              color: BrandColors.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BrandColors.primary.withValues(alpha: 0.18),
                  border: Border.all(
                    color: BrandColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.lock_rounded,
                  size: 20,
                  color: BrandColors.primary,
                ),
              ),
              const SizedBox(width: DesignTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      PremiumFeatureCopy.title(feature),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'premium.lock_inline_subtitle'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
              const _UpgradePill(),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpgradePill extends StatelessWidget {
  const _UpgradePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        gradient: BrandColors.brandGradient,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.primary.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        'premium.lock_inline_upgrade'.tr(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

// =============================================================================
// Overlay — children at 25% opacity, blurred lock surface on top
// =============================================================================

class _GateOverlay extends StatelessWidget {
  const _GateOverlay({
    required this.feature,
    required this.child,
  });

  final PremiumFeature feature;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Stack(
      children: <Widget>[
        IgnorePointer(
          child: Opacity(opacity: 0.25, child: child),
        ),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(
                color: cs.surface.withValues(alpha: 0.55),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/premium'),
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spaceL),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            Icons.lock_rounded,
                            size: 28,
                            color: BrandColors.primary,
                          ),
                          const SizedBox(height: DesignTokens.spaceS),
                          Text(
                            'premium.lock_overlay_title'.tr(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spaceXs),
                          Text(
                            PremiumFeatureCopy.subtitle(feature),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: DesignTokens.spaceM),
                          const _UnlockButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnlockButton extends StatelessWidget {
  const _UnlockButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/premium'),
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceS,
          ),
          decoration: BoxDecoration(
            gradient: BrandColors.brandGradient,
            borderRadius: BorderRadius.circular(DesignTokens.radiusS),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: BrandColors.primary.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            'premium.lock_overlay_unlock'.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Bottom-sheet — kept for back-compat with PremiumLockSheet.show(...)
// =============================================================================

/// Modal bottom sheet shown when a user attempts to use a gated
/// capability while on the free tier.
///
/// Drives users toward `/premium` with a hint of the unlocked perks.
/// The presentation is glassmorphism over the underlying screen so the
/// sheet feels lightweight and the user keeps context.
class _PremiumLockBottomSheet extends StatelessWidget {
  const _PremiumLockBottomSheet({required this.feature});

  final PremiumFeature feature;

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
                  children: <Widget>[
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
                      label: Text('premium.lock_sheet_see_plans'.tr()),
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
                      child: Text('premium.lock_sheet_maybe_later'.tr()),
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
      children: <Widget>[
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
            children: <Widget>[
              Text(
                'premium.lock_sheet_title'.tr(),
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

  static const List<(IconData, String)> _perks = <(IconData, String)>[
    (Icons.block_rounded, 'No ads'),
    (Icons.apps_rounded, 'Unlimited\nplaylists'),
    (Icons.picture_in_picture_alt_rounded, 'Multi-screen'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
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
        children: <Widget>[
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
