import 'dart:developer' as developer;
import 'dart:ui';

import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/remote_config/app_remote_config.dart';
import 'package:awatv_mobile/src/shared/remote_config/rc_snapshot.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;

/// Breakpoint at which the paywall pivots from a stacked phone layout
/// to the two-column tablet/desktop anatomy. Picked to land on iPad
/// landscape, foldables in book mode, and 13" laptops.
const double _kTwoColumnBreakpoint = 1100;

/// Selected pricing tile on the paywall.
///
/// Defaults to [PremiumPlan.yearly] — the tile we want to convert on —
/// and gets re-seeded by the build whenever the active Remote Config
/// variant changes the highlighted plan, unless the user already tapped
/// a tile explicitly. Lives at the top level so widget tests can drive
/// it without poking private state.
final selectedPlanProvider = StateProvider<PremiumPlan>(
  (ref) => PremiumPlan.yearly,
);

/// Sticky bit toggled to `true` the first time the user taps a tile.
/// Until then, the build is allowed to re-seed [selectedPlanProvider]
/// from the RC variant. After the user has expressed a preference we
/// stop overriding it, so a slow Firebase fetch landing mid-screen
/// can't yank the highlight off the user's chosen card.
final _userPickedPlanProvider = StateProvider<bool>((ref) => false);

/// Marketing paywall — two-column on tablets/desktops, single-column
/// stack on phones. Left side is a value-prop bullet list, right side
/// is the hero illustration + 3 pricing tiles + CTA + restore link.
///
/// Until RevenueCat lands the CTA calls
/// `PremiumStatus.simulateActivate(plan)` so the rest of the app can
/// be exercised end-to-end against a real persisted entitlement.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _activating = false;

  Future<void> _activate() async {
    if (_activating) return;
    setState(() => _activating = true);
    final messenger = ScaffoldMessenger.of(context);
    final selected = ref.read(selectedPlanProvider);
    try {
      await ref
          .read(premiumStatusProvider.notifier)
          .simulateActivate(selected);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: BrandColors.success,
          content: Text(
            'premium.paywall.snack_active'.tr(
              namedArgs: <String, String>{'plan': _planLabel(selected)},
            ),
          ),
        ),
      );
      if (context.canPop()) context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'premium.paywall.snack_failed'.tr(
              namedArgs: <String, String>{'error': '$e'},
            ),
          ),
        ),
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
      SnackBar(content: Text('premium.paywall.snack_restore'.tr())),
    );
  }

  Future<void> _signOutPremium() async {
    await ref.read(premiumStatusProvider.notifier).signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('premium.paywall.snack_signed_out'.tr())),
    );
  }

  String _planLabel(PremiumPlan p) => switch (p) {
        PremiumPlan.monthly => 'premium.plan_monthly'.tr(),
        PremiumPlan.yearly => 'premium.plan_yearly'.tr(),
        PremiumPlan.lifetime => 'premium.plan_lifetime'.tr(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = ref.watch(premiumStatusProvider);
    final rc = ref.watch(appRemoteConfigProvider);

    // Variant 'B' rearranges the card order to put Lifetime on top and
    // pre-selects it. Marketing splits the audience server-side; we
    // honour what RC tells us. Anything other than 'B' falls through
    // to the default A layout.
    final variantB = rc.paywallVariant.toUpperCase() == 'B';
    final highlighted =
        variantB ? PremiumPlan.lifetime : PremiumPlan.yearly;

    // Reseed the selected plan to the recommended one when the user
    // hasn't expressed a preference yet. Done in a post-frame callback
    // so we don't mutate provider state during build.
    final userPicked = ref.read(_userPickedPlanProvider);
    if (!userPicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(_userPickedPlanProvider)) return;
        if (ref.read(selectedPlanProvider) != highlighted) {
          ref.read(selectedPlanProvider.notifier).state = highlighted;
        }
      });
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: BrandColors.auroraGradient),
        child: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'common.close'.tr(),
                  onPressed: () =>
                      context.canPop() ? context.pop() : null,
                ),
                title: Text(
                  'AWAtv Premium',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide =
                        constraints.maxWidth >= _kTwoColumnBreakpoint;
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide
                            ? DesignTokens.spaceXl
                            : DesignTokens.spaceL,
                        vertical: DesignTokens.spaceL,
                      ),
                      child: wide
                          ? _WideLayout(
                              rc: rc,
                              variantB: variantB,
                              highlighted: highlighted,
                              activating: _activating,
                              onActivate: _activate,
                              onRestore: _restorePurchases,
                            )
                          : _NarrowLayout(
                              rc: rc,
                              variantB: variantB,
                              highlighted: highlighted,
                              activating: _activating,
                              onActivate: _activate,
                              onRestore: _restorePurchases,
                            ),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: DesignTokens.spaceL),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Layouts
// =============================================================================

class _WideLayout extends ConsumerWidget {
  const _WideLayout({
    required this.rc,
    required this.variantB,
    required this.highlighted,
    required this.activating,
    required this.onActivate,
    required this.onRestore,
  });

  final RcSnapshot rc;
  final bool variantB;
  final PremiumPlan highlighted;
  final bool activating;
  final VoidCallback onActivate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 4,
          child: _ValueProps(variantB: variantB, rc: rc),
        ),
        const SizedBox(width: DesignTokens.spaceXl),
        Expanded(
          flex: 6,
          child: _PlansColumn(
            rc: rc,
            variantB: variantB,
            highlighted: highlighted,
            activating: activating,
            onActivate: onActivate,
            onRestore: onRestore,
          ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends ConsumerWidget {
  const _NarrowLayout({
    required this.rc,
    required this.variantB,
    required this.highlighted,
    required this.activating,
    required this.onActivate,
    required this.onRestore,
  });

  final RcSnapshot rc;
  final bool variantB;
  final PremiumPlan highlighted;
  final bool activating;
  final VoidCallback onActivate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _HeroIllustration(),
        const SizedBox(height: DesignTokens.spaceL),
        _ValueProps(variantB: variantB, rc: rc),
        const SizedBox(height: DesignTokens.spaceXl),
        _PlanTilesStack(
          rc: rc,
          variantB: variantB,
          highlighted: highlighted,
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _TrialAndCta(
          rc: rc,
          activating: activating,
          onActivate: onActivate,
        ),
        const SizedBox(height: DesignTokens.spaceM),
        _RestoreLink(onRestore: onRestore),
        const SizedBox(height: DesignTokens.spaceL),
        const _LegalFooter(),
      ],
    );
  }
}

// =============================================================================
// Left column — value proposition + bullet list
// =============================================================================

class _ValueProps extends StatelessWidget {
  const _ValueProps({required this.variantB, required this.rc});

  final bool variantB;
  final RcSnapshot rc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ShaderMask(
          shaderCallback: (rect) =>
              BrandColors.brandGradient.createShader(rect),
          child: Text(
            variantB
                ? 'premium.paywall.headline_b'.tr()
                : 'premium.paywall.headline'.tr(),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceM),
        Text(
          'premium.paywall.subheadline'.tr(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
            height: 1.4,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        for (final spec in _bulletSpecs)
          _BulletRow(spec: spec),
        const SizedBox(height: DesignTokens.spaceM),
        Row(
          children: <Widget>[
            Icon(
              Icons.lock_open_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.55),
            ),
            const SizedBox(width: DesignTokens.spaceXs),
            Expanded(
              child: Text(
                'premium.paywall.cancel_anytime_caption'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Nine bullets — one per top-level premium claim. Order is the
  /// same as the IPTV-app industry-standard paywall reference.
  static const List<_BulletSpec> _bulletSpecs = <_BulletSpec>[
    _BulletSpec(
      icon: Icons.block_rounded,
      titleKey: 'premium.feature.no_ads_title',
      bodyKey: 'premium.feature.no_ads_body',
    ),
    _BulletSpec(
      icon: Icons.sync_rounded,
      titleKey: 'premium.feature.always_fresh_title',
      bodyKey: 'premium.feature.always_fresh_body',
    ),
    _BulletSpec(
      icon: Icons.dark_mode_rounded,
      titleKey: 'premium.feature.themes_title',
      bodyKey: 'premium.feature.themes_body',
    ),
    _BulletSpec(
      icon: Icons.subtitles_rounded,
      titleKey: 'premium.feature.subtitles_title',
      bodyKey: 'premium.feature.subtitles_body',
    ),
    _BulletSpec(
      icon: Icons.devices_rounded,
      titleKey: 'premium.feature.multi_device_title',
      bodyKey: 'premium.feature.multi_device_body',
    ),
    _BulletSpec(
      icon: Icons.family_restroom_rounded,
      titleKey: 'premium.feature.family_title',
      bodyKey: 'premium.feature.family_body',
    ),
    _BulletSpec(
      icon: Icons.download_for_offline_rounded,
      titleKey: 'premium.feature.downloads_title',
      bodyKey: 'premium.feature.downloads_body',
    ),
    _BulletSpec(
      icon: Icons.fiber_manual_record_rounded,
      titleKey: 'premium.feature.recording_title',
      bodyKey: 'premium.feature.recording_body',
    ),
    _BulletSpec(
      icon: Icons.replay_rounded,
      titleKey: 'premium.feature.catchup_title',
      bodyKey: 'premium.feature.catchup_body',
    ),
  ];
}

class _BulletSpec {
  const _BulletSpec({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.spec});

  final _BulletSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BrandColors.primary.withValues(alpha: 0.18),
              border: Border.all(
                color: BrandColors.primary.withValues(alpha: 0.5),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: BrandColors.primarySoft,
            ),
          ),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      spec.icon,
                      size: 16,
                      color: BrandColors.secondary,
                    ),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Flexible(
                      child: Text(
                        spec.titleKey.tr(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  spec.bodyKey.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.35,
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

// =============================================================================
// Right column — hero + tiles + CTA
// =============================================================================

class _PlansColumn extends StatelessWidget {
  const _PlansColumn({
    required this.rc,
    required this.variantB,
    required this.highlighted,
    required this.activating,
    required this.onActivate,
    required this.onRestore,
  });

  final RcSnapshot rc;
  final bool variantB;
  final PremiumPlan highlighted;
  final bool activating;
  final VoidCallback onActivate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _HeroIllustration(),
        const SizedBox(height: DesignTokens.spaceL),
        _PlanTilesStack(
          rc: rc,
          variantB: variantB,
          highlighted: highlighted,
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _TrialAndCta(
          rc: rc,
          activating: activating,
          onActivate: onActivate,
        ),
        const SizedBox(height: DesignTokens.spaceM),
        _RestoreLink(onRestore: onRestore),
        const SizedBox(height: DesignTokens.spaceL),
        const _LegalFooter(),
      ],
    );
  }
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 192,
        height: 192,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: BrandColors.brandGradient,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: BrandColors.primary.withValues(alpha: 0.5),
              blurRadius: 60,
              spreadRadius: 4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: BrandColors.secondary.withValues(alpha: 0.35),
              blurRadius: 40,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(
              Icons.live_tv_rounded,
              size: 96,
              color: Colors.white,
            ),
            Positioned(
              top: 26,
              right: 32,
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTilesStack extends ConsumerWidget {
  const _PlanTilesStack({
    required this.rc,
    required this.variantB,
    required this.highlighted,
  });

  final RcSnapshot rc;
  final bool variantB;
  final PremiumPlan highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedPlanProvider);
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

    return Column(
      children: <Widget>[
        for (final plan in orderedPlans)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spaceM),
            child: _PaywallTile(
              plan: plan,
              rc: rc,
              selected: selected == plan,
              isHero: plan == highlighted,
              onTap: () {
                ref.read(_userPickedPlanProvider.notifier).state = true;
                ref.read(selectedPlanProvider.notifier).state = plan;
              },
            ),
          ),
      ],
    );
  }
}

class _PaywallTile extends StatelessWidget {
  const _PaywallTile({
    required this.plan,
    required this.rc,
    required this.selected,
    required this.isHero,
    required this.onTap,
  });

  final PremiumPlan plan;
  final RcSnapshot rc;
  final bool selected;
  final bool isHero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final price = switch (plan) {
      PremiumPlan.monthly => rc.priceMonthly,
      PremiumPlan.yearly => rc.priceYearly,
      PremiumPlan.lifetime => rc.priceLifetime,
    };
    final periodKey = switch (plan) {
      PremiumPlan.monthly => 'premium.paywall.tile_monthly_period',
      PremiumPlan.yearly => 'premium.paywall.tile_yearly_period',
      PremiumPlan.lifetime => 'premium.paywall.tile_lifetime_period',
    };
    final titleKey = switch (plan) {
      PremiumPlan.monthly => 'premium.plan_monthly',
      PremiumPlan.yearly => 'premium.plan_yearly',
      PremiumPlan.lifetime => 'premium.plan_lifetime',
    };

    final borderColor = selected
        ? BrandColors.primary
        : isHero
            ? BrandColors.primary.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.14);
    final borderWidth = selected ? 2.0 : (isHero ? 1.4 : 1.0);

    final glassFill = isHero
        ? BrandColors.primary.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.05);

    final yearlySubline = plan == PremiumPlan.yearly
        ? 'premium.paywall.tile_yearly_subline'.tr(
            namedArgs: <String, String>{'price': _yearlyPerMonth(rc)},
          )
        : null;
    final lifetimeSubline = plan == PremiumPlan.lifetime
        ? 'premium.paywall.tile_lifetime_subline'.tr()
        : null;

    return Semantics(
      label: '${titleKey.tr()} $price',
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusL),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: DesignTokens.glassBlurMedium,
                    sigmaY: DesignTokens.glassBlurMedium,
                  ),
                  child: AnimatedContainer(
                    duration: DesignTokens.motionFast,
                    padding: EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceM,
                      vertical: isHero
                          ? DesignTokens.spaceL
                          : DesignTokens.spaceM,
                    ),
                    decoration: BoxDecoration(
                      color: glassFill,
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusL),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: selected
                          ? <BoxShadow>[
                              BoxShadow(
                                color: BrandColors.primary
                                    .withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? BrandColors.primary
                              : Colors.white.withValues(alpha: 0.55),
                          size: 22,
                        ),
                        const SizedBox(width: DesignTokens.spaceM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                titleKey.tr(),
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: isHero
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: isHero ? 20 : 16,
                                ),
                              ),
                              if (yearlySubline != null) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  yearlySubline,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                    color: Colors.white
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                              if (lifetimeSubline != null) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  lifetimeSubline,
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                    color: BrandColors.secondary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spaceM),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              price,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: isHero ? 22 : 16,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              periodKey.tr(),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                color: Colors.white
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: DesignTokens.spaceXs),
                        if (cs.brightness == Brightness.light)
                          // No-op spacer so analyzer keeps cs reference.
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ),
              if (isHero)
                Positioned(
                  top: -10,
                  right: DesignTokens.spaceL,
                  child: _BrandBadge(
                    label: plan == PremiumPlan.lifetime
                        ? 'premium.paywall.badge_lifetime'.tr()
                        : 'premium.paywall.badge_most_popular'.tr(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Best-effort "per month" derivation for the yearly tile sub-line.
  /// Picks the first numeric token in the priced string and divides
  /// by 12. Falls back to a copy of the source string if parsing fails.
  String _yearlyPerMonth(RcSnapshot rc) {
    final raw = rc.priceYearly;
    final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(raw);
    if (match == null) return raw;
    final n = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (n == null) return raw;
    final perMonth = n / 12.0;
    final formatted = perMonth.toStringAsFixed(2).replaceAll('.', ',');
    final prefix = raw.replaceFirst(match.group(0)!, '').trim();
    final currency =
        prefix.split(' ').firstWhere((s) => s.isNotEmpty, orElse: () => '');
    return currency.isEmpty ? formatted : '$currency $formatted';
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.label});

  final String label;

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
            color: BrandColors.primary.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
      ),
    );
  }
}

class _TrialAndCta extends ConsumerWidget {
  const _TrialAndCta({
    required this.rc,
    required this.activating,
    required this.onActivate,
  });

  final RcSnapshot rc;
  final bool activating;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedPlanProvider);
    final showTrial =
        selected != PremiumPlan.lifetime && rc.freeTrialDays > 0;

    final ctaLabel = selected == PremiumPlan.lifetime
        ? 'premium.paywall.cta_buy_lifetime'.tr()
        : showTrial
            ? 'premium.paywall.cta_with_trial'.tr()
            : 'premium.paywall.cta_subscribe'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showTrial)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spaceS),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: BrandColors.secondary,
                ),
                const SizedBox(width: DesignTokens.spaceXs),
                Flexible(
                  child: Text(
                    'premium.paywall.trial_line'.tr(
                      namedArgs: <String, String>{
                        'days': '${rc.freeTrialDays}',
                      },
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 56,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: activating ? null : onActivate,
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              child: Opacity(
                opacity: activating ? 0.6 : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: BrandColors.brandGradient,
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusM),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: BrandColors.primary.withValues(alpha: 0.55),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: activating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            ctaLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
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

class _RestoreLink extends StatelessWidget {
  const _RestoreLink({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onRestore,
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.primarySoft,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        child: Text('premium.paywall.restore'.tr()),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'premium.paywall.footer_terms'.tr(),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.5),
          height: 1.4,
        ),
      ),
    );
  }
}

// =============================================================================
// "Already premium" banner
// =============================================================================

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
    final fmt = intl.DateFormat.yMMMd();
    final expires = tier.expiresAt;
    final subtitle = switch (tier.plan) {
      PremiumPlan.lifetime => 'premium.paywall.active_lifetime'.tr(),
      PremiumPlan.monthly when expires != null =>
        'premium.paywall.active_monthly'.tr(
          namedArgs: <String, String>{'date': fmt.format(expires)},
        ),
      PremiumPlan.yearly when expires != null =>
        'premium.paywall.active_yearly'.tr(
          namedArgs: <String, String>{'date': fmt.format(expires)},
        ),
      _ => 'premium.paywall.active_generic'.tr(),
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
        color: BrandColors.success.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        border: Border.all(
          color: BrandColors.success.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle, color: BrandColors.success),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'premium.paywall.active_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onSignOut,
            child: Text('premium.paywall.active_close'.tr()),
          ),
        ],
      ),
    );
  }
}
