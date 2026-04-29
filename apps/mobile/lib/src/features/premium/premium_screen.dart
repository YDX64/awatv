import 'dart:developer' as developer;

import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/remote_config/app_remote_config.dart';
import 'package:awatv_mobile/src/shared/remote_config/rc_snapshot.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Paywall — three plan tiles + a "Restore purchases" footer.
///
/// Until RevenueCat lands (Phase 5) the CTA calls
/// `PremiumStatus.simulateActivate(plan)` so the rest of the app can
/// be exercised end-to-end against a real persisted entitlement.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  PremiumPlan _selected = PremiumPlan.yearly;
  bool _activating = false;

  /// True once the user explicitly taps a plan card. Until then, the
  /// build reseeds `_selected` to the variant-recommended plan so that
  /// a slow Remote Config fetch landing mid-screen still steers the
  /// user to the highlighted card.
  bool _userPicked = false;

  Future<void> _activate() async {
    if (_activating) return;
    setState(() => _activating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(premiumStatusProvider.notifier)
          .simulateActivate(_selected);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: BrandColors.success,
          content: Text(
            'Premium ${_planLabel(_selected)} aktif. Iyi seyirler!',
          ),
        ),
      );
      // Pop back to where the user came from so gates re-evaluate.
      if (context.canPop()) context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Aktivasyon basarisiz: $e')),
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _restorePurchases() async {
    // No-op stub — real restore wires through RevenueCat in Phase 5.
    developer.log(
      'Premium restore requested (no-op until RevenueCat ships).',
      name: 'awatv.premium',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Satin alimlari geri yukleme magaza entegrasyonu ile aktiflesir.',
        ),
      ),
    );
  }

  Future<void> _signOutPremium() async {
    await ref.read(premiumStatusProvider.notifier).signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Premium kapatildi.')),
    );
  }

  String _planLabel(PremiumPlan p) => switch (p) {
        PremiumPlan.monthly => 'aylik',
        PremiumPlan.yearly => 'yillik',
        PremiumPlan.lifetime => 'omur boyu',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = ref.watch(premiumStatusProvider);
    final rc = ref.watch(appRemoteConfigProvider);

    // Variant 'B' rearranges the card order to put Lifetime first and
    // pre-selects it. Marketing splits the audience server-side; we just
    // honour what RC tells us. Anything other than 'B' falls through to
    // the default A layout.
    final variantB = rc.paywallVariant.toUpperCase() == 'B';
    final orderedPlans = variantB
        ? const <PremiumPlan>[
            PremiumPlan.lifetime,
            PremiumPlan.yearly,
            PremiumPlan.monthly,
          ]
        : const <PremiumPlan>[
            PremiumPlan.monthly,
            PremiumPlan.yearly,
            PremiumPlan.lifetime,
          ];
    final highlighted =
        variantB ? PremiumPlan.lifetime : PremiumPlan.yearly;

    // First build seeds `_selected`; if the variant landed late we
    // re-target the user to the highlighted plan unless they've already
    // tapped one explicitly (the `_userPicked` flag remembers that).
    if (!_userPicked) {
      _selected = highlighted;
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: BrandColors.premiumGradient,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.spaceL),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.workspace_premium,
                          color: Colors.white,
                          size: 56,
                        ),
                        const SizedBox(height: DesignTokens.spaceS),
                        Text(
                          'AWAtv Premium',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spaceXs),
                        Text(
                          variantB
                              ? 'Bir kez ode, sonsuza kadar premium.'
                              : 'Reklamsiz. Sinirsiz. Hizli.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (tier is PremiumTierActive)
            SliverToBoxAdapter(
              child: _ActiveBanner(
                tier: tier,
                onSignOut: _signOutPremium,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spaceL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Plan sec',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  for (final plan in orderedPlans)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignTokens.spaceM,
                      ),
                      child: _PlanCard(
                        plan: plan,
                        selected: _selected == plan,
                        highlighted: plan == highlighted,
                        rc: rc,
                        onTap: () => setState(() {
                          _selected = plan;
                          _userPicked = true;
                        }),
                      ),
                    ),
                  const SizedBox(height: DesignTokens.spaceM),
                  FilledButton(
                    onPressed: _activating ? null : _activate,
                    child: _activating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _selected == PremiumPlan.lifetime
                                ? 'Tek seferlik satin al'
                                : 'Aboneligi baslat',
                          ),
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  Text(
                    'Premium ile gelen avantajlar',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  const _Comparison(),
                  const SizedBox(height: DesignTokens.spaceL),
                  TextButton.icon(
                    onPressed: _restorePurchases,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Satin alimlarimi geri yukle'),
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  Text(
                    'Aboneligini istediginde iptal edebilirsin. Apple App '
                    'Store / Google Play kurallari gecerlidir.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner shown above the plan list when the user is already premium.
/// Surfaces the renewal date and exposes a "sign out" link so the dev
/// console can reset back to free without losing the rest of the app
/// state.
class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({
    required this.tier,
    required this.onSignOut,
  });

  final PremiumTierActive tier;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd();
    final expires = tier.expiresAt;
    final subtitle = switch (tier.plan) {
      PremiumPlan.lifetime => 'Omur boyu — sonsuza kadar.',
      PremiumPlan.monthly when expires != null =>
        'Aylik abonelik — yenileme: ${fmt.format(expires)}',
      PremiumPlan.yearly when expires != null =>
        'Yillik abonelik — yenileme: ${fmt.format(expires)}',
      _ => 'Premium aktif.',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        DesignTokens.spaceL,
        DesignTokens.spaceL,
        DesignTokens.spaceL,
        0,
      ),
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: BrandColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        border: Border.all(
          color: BrandColors.success.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: BrandColors.success),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Premium aktif',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: onSignOut,
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.highlighted,
    required this.rc,
    required this.onTap,
  });

  final PremiumPlan plan;
  final bool selected;

  /// True for the plan flagged as "best value" by the active RC variant.
  /// Highlighted cards get a tinted background, a subtle glow border,
  /// and a "ONERILEN" badge above the price row.
  final bool highlighted;

  final RcSnapshot rc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Title + badge labels are still local; only the price string is
    // server-driven so the marketing team can move pricing without a
    // store release.
    final (String title, String price, String? badge) = switch (plan) {
      PremiumPlan.monthly => ('Aylik', rc.priceMonthly, null),
      PremiumPlan.yearly => ('Yillik', rc.priceYearly, '%37 indirim'),
      PremiumPlan.lifetime =>
        ('Omur boyu', rc.priceLifetime, 'Tek seferlik'),
    };

    final borderColor = selected
        ? cs.primary
        : (highlighted
            ? cs.primary.withValues(alpha: 0.6)
            : cs.outline.withValues(alpha: 0.4));
    final bgColor = highlighted
        ? cs.primary.withValues(alpha: 0.06)
        : cs.surface;

    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (highlighted)
              Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spaceS),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceS,
                    vertical: DesignTokens.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusS,
                    ),
                  ),
                  child: Text(
                    'ONERILEN',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(price, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceS,
                      vertical: DesignTokens.spaceXs,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusS,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison();

  static const _rows = <(String, String, String)>[
    ('Liste sayisi', '2', 'Sinirsiz'),
    ('Reklam', 'Var', 'Yok'),
    ('PiP / cok ekran', 'Yok', 'Var'),
    ('Gecmis EPG', '1 gun', '14 gun'),
    ('VLC arka uc', 'Yok', 'Var'),
    ('Aile koruma', 'Yok', 'Var'),
    ('Ozel temalar', 'Yok', 'Var'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'Ozellik',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Ucretsiz',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Premium',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final r in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceM,
                vertical: DesignTokens.spaceS,
              ),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text(r.$1)),
                  Expanded(
                    flex: 3,
                    child: Text(
                      r.$2,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      r.$3,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
