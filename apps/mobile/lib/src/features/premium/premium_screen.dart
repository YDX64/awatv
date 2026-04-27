import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Paywall mockup. Real IAP wires in Phase 5 (RevenueCat). For now the
/// CTAs surface a "Coming soon" SnackBar.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  _Plan _selected = _Plan.yearly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  for (final plan in _Plan.values)
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Yakinda — abonelik magaza entegrasyonu Phase 5.',
                          ),
                        ),
                      );
                    },
                    child: Text(
                      _selected == _Plan.lifetime
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
                  const SizedBox(height: DesignTokens.spaceXl),
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

enum _Plan { monthly, yearly, lifetime }

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (String title, String price, String? badge) = switch (plan) {
      _Plan.monthly => ('Aylik', 'EUR 3,99 / ay', null),
      _Plan.yearly => ('Yillik', 'EUR 29,99 / yil', '%37 indirim'),
      _Plan.lifetime => ('Omur boyu', 'EUR 69,99', 'Tek seferlik'),
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
