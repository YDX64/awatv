import 'dart:developer' as developer;

import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
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
                        const Text(
                          'Reklamsiz. Sinirsiz. Hizli.',
                          style: TextStyle(color: Colors.white),
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
                  for (final plan in PremiumPlan.values)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignTokens.spaceM,
                      ),
                      child: _PlanCard(
                        plan: plan,
                        selected: _selected == plan,
                        onTap: () => setState(() => _selected = plan),
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
    required this.onTap,
  });

  final PremiumPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (String title, String price, String? badge) = switch (plan) {
      PremiumPlan.monthly => ('Aylik', 'EUR 3,99 / ay', null),
      PremiumPlan.yearly => ('Yillik', 'EUR 29,99 / yil', '%37 indirim'),
      PremiumPlan.lifetime => ('Omur boyu', 'EUR 69,99', 'Tek seferlik'),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withValues(alpha: 0.4),
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
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
                  borderRadius: BorderRadius.circular(DesignTokens.radiusS),
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
