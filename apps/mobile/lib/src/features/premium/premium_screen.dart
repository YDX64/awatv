import 'dart:async';

import 'package:awatv_mobile/src/shared/billing/billing_providers.dart';
import 'package:awatv_mobile/src/shared/billing/revenuecat_client.dart';
import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/remote_config/app_remote_config.dart';
import 'package:awatv_mobile/src/shared/remote_config/rc_snapshot.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;

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

/// Streas-style paywall: deep cherry hero gradient, two pricing tiles
/// (yearly default-selected with gold "EN POPULER" badge + Save 37 %),
/// 10-row "Everything included" feature card, big cherry CTA + 3-day
/// trial line + restore link, plus a confirm-purchase modal in front
/// of [PremiumStatus.simulateActivate] so the rest of the app can be
/// exercised end-to-end against a real persisted entitlement until
/// RevenueCat ships in Phase 3.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _activating = false;
  bool _restoring = false;
  String? _localError;

  /// Hidden debug gesture: 5 long-presses on any plan tile within
  /// 4 s triggers [_debugSimulateActivate] so dev / QA builds can flip
  /// to premium without a sandbox account. The counter resets on every
  /// timeout. Only ever wired in `kDebugMode` builds.
  int _debugLongPressCount = 0;
  DateTime? _debugLongPressFirst;
  static const int _debugLongPressNeeded = 5;
  static const Duration _debugLongPressWindow = Duration(seconds: 4);

  Future<void> _confirmAndPurchase() async {
    if (_activating) return;
    final selected = ref.read(selectedPlanProvider);
    final rc = ref.read(appRemoteConfigProvider);
    final price = _priceFor(rc, selected);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmPurchaseDialog(
        plan: selected,
        price: price,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _activate();
  }

  Future<void> _activate() async {
    if (_activating) return;
    setState(() {
      _activating = true;
      _localError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final selected = ref.read(selectedPlanProvider);
    try {
      final billing = ref.read(awatvBillingProvider);
      // If RC isn't available on this build (web/desktop/TV, or .env
      // missing the keys), surface a friendly error instead of letting
      // the SDK throw an opaque "configurationError".
      if (!billing.isAvailable) {
        if (!mounted) return;
        setState(
          () => _localError = 'premium.paywall.snack_failed'.tr(
            namedArgs: <String, String>{
              'error': 'Premium satin alimi bu cihazda kullanilamiyor.',
            },
          ),
        );
        return;
      }
      final productId = _productIdForPlan(selected);
      final outcome = await billing.purchaseProduct(productId);
      if (!mounted) return;
      switch (outcome) {
        case PurchaseOutcomeSuccess():
          // The store accepted the purchase; the RevenueCat → Edge
          // Function → Supabase realtime chain will flip
          // `premiumStatusProvider` to active within seconds and the
          // build will rebuild as `_AlreadyPremiumScaffold`.
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
        case PurchaseOutcomeCancelled():
          // User dismissed the StoreKit / Play sheet — not an error,
          // no toast. Just unlock the CTA.
          break;
        case PurchaseOutcomeFailure(:final message):
          setState(
            () => _localError = 'premium.paywall.snack_failed'.tr(
              namedArgs: <String, String>{'error': message},
            ),
          );
      }
    } on Object catch (e) {
      // Defensive — billing.purchaseProduct already wraps every known
      // failure into PurchaseOutcomeFailure, so reaching here means the
      // provider lookup itself blew up. Surface it inline.
      if (!mounted) return;
      setState(
        () => _localError = 'premium.paywall.snack_failed'.tr(
          namedArgs: <String, String>{'error': e.toString()},
        ),
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  /// Debug-only entrypoint reachable via the hidden long-press gesture
  /// on a plan tile (5x). Bypasses the StoreKit sheet so simulator
  /// builds can exercise the rest of the app against a "premium" tier
  /// without owning a sandbox account. NEVER reachable in release —
  /// `simulateActivate` itself refuses non-debug calls upstream.
  Future<void> _debugSimulateActivate() async {
    if (!kDebugMode) return;
    if (_activating) return;
    setState(() {
      _activating = true;
      _localError = null;
    });
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
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _localError = e.toString());
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (_restoring) return;
    setState(() {
      _restoring = true;
      _localError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final billing = ref.read(awatvBillingProvider);
      if (!billing.isAvailable) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('premium.paywall.snack_restore'.tr())),
        );
        return;
      }
      final outcome = await billing.restorePurchases();
      if (!mounted) return;
      switch (outcome) {
        case RestoreOutcomeSuccess():
          // RC posted the receipt to the backend; the webhook will
          // update Supabase and the realtime listener flips the UI
          // automatically. Show a gentle "checking" snackbar so the
          // user has feedback while the round-trip lands.
          messenger.showSnackBar(
            SnackBar(content: Text('premium.paywall.snack_restore'.tr())),
          );
        case RestoreOutcomeFailure(:final message):
          setState(
            () => _localError = 'premium.paywall.snack_failed'.tr(
              namedArgs: <String, String>{'error': message},
            ),
          );
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _localError = 'premium.paywall.snack_failed'.tr(
          namedArgs: <String, String>{'error': e.toString()},
        ),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
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

  String _priceFor(RcSnapshot rc, PremiumPlan plan) => switch (plan) {
        PremiumPlan.monthly => rc.priceMonthly,
        PremiumPlan.yearly => rc.priceYearly,
        PremiumPlan.lifetime => rc.priceLifetime,
      };

  /// Map our internal [PremiumPlan] enum to the App Store / Play /
  /// RevenueCat product identifier. Single source of truth so the
  /// purchase flow, restore flow, and analytics events all reference
  /// the same string.
  String _productIdForPlan(PremiumPlan plan) => switch (plan) {
        PremiumPlan.monthly => AwatvProductIds.monthly,
        PremiumPlan.yearly => AwatvProductIds.yearly,
        PremiumPlan.lifetime => AwatvProductIds.lifetime,
      };

  /// Handler for the hidden 5x long-press debug gesture. Counts the
  /// presses inside [_debugLongPressWindow]; when the threshold is
  /// hit it kicks off [_debugSimulateActivate]. No-op in release.
  void _onPlanTileLongPress() {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final first = _debugLongPressFirst;
    if (first == null || now.difference(first) > _debugLongPressWindow) {
      _debugLongPressFirst = now;
      _debugLongPressCount = 1;
      return;
    }
    _debugLongPressCount += 1;
    if (_debugLongPressCount >= _debugLongPressNeeded) {
      _debugLongPressCount = 0;
      _debugLongPressFirst = null;
      unawaited(_debugSimulateActivate());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(premiumStatusProvider);
    final rc = ref.watch(appRemoteConfigProvider);

    // RC variant 'B' bumps the lifetime tile to the top and pre-selects
    // it. AWAtv ships lifetime; Streas does not — so when variant !=B
    // we mirror Streas exactly: monthly + yearly only, yearly hero.
    final variantB = rc.paywallVariant.toUpperCase() == 'B';
    final highlighted =
        variantB ? PremiumPlan.lifetime : PremiumPlan.yearly;

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

    if (tier is PremiumTierActive) {
      return _AlreadyPremiumScaffold(
        tier: tier,
        onSignOut: _signOutPremium,
      );
    }

    return Scaffold(
      backgroundColor: BrandColors.background,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Hero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceM,
                  DesignTokens.spaceL,
                  DesignTokens.spaceM,
                  DesignTokens.spaceM,
                ),
                child: _PlanTilesStack(
                  rc: rc,
                  variantB: variantB,
                  highlighted: highlighted,
                  onTileLongPress:
                      kDebugMode ? _onPlanTileLongPress : null,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceM,
                ),
                child: _FeaturesCard(),
              ),
              if (_localError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceM,
                    DesignTokens.spaceM,
                    DesignTokens.spaceM,
                    0,
                  ),
                  child: _ErrorBanner(message: _localError!),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceM,
                  DesignTokens.spaceL,
                  DesignTokens.spaceM,
                  DesignTokens.spaceS,
                ),
                child: _CtaSection(
                  rc: rc,
                  activating: _activating,
                  onPurchase: _confirmAndPurchase,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceM,
                ),
                child: _TrialLine(rc: rc),
              ),
              const SizedBox(height: DesignTokens.spaceM),
              _RestoreLink(
                onRestore: _restoring ? null : _restorePurchases,
                restoring: _restoring,
              ),
              const SizedBox(height: DesignTokens.spaceM),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceL,
                ),
                child: _LegalFooter(),
              ),
              const SizedBox(height: DesignTokens.spaceL),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Hero — deep cherry gradient + crown + close button
// =============================================================================

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spaceL,
        mq.padding.top + DesignTokens.spaceS,
        DesignTokens.spaceL,
        DesignTokens.spaceL,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            BrandColors.primaryDark,
            BrandColors.background,
          ],
          stops: <double>[0, 1],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 22,
                ),
                tooltip: 'common.close'.tr(),
                onPressed: () => context.canPop() ? context.pop() : null,
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: BrandColors.brandGradient,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: BrandColors.primary.withValues(alpha: 0.55),
                    blurRadius: 32,
                    spreadRadius: 2,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                size: 56,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Text(
            'premium.paywall.hero_title'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            'premium.paywall.hero_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Plan tiles stack — yearly (hero) + monthly + (optional) lifetime
// =============================================================================

class _PlanTilesStack extends ConsumerWidget {
  const _PlanTilesStack({
    required this.rc,
    required this.variantB,
    required this.highlighted,
    this.onTileLongPress,
  });

  final RcSnapshot rc;
  final bool variantB;
  final PremiumPlan highlighted;

  /// Wired only in debug builds — fires the hidden 5x long-press
  /// gesture that activates `simulateActivate`. Null in release.
  final VoidCallback? onTileLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedPlanProvider);
    // Streas ships only monthly + yearly. AWAtv extends with lifetime
    // for variant B; we keep the full ladder here to honour RC and
    // gracefully degrade to two tiles when variant !=B.
    final orderedPlans = variantB
        ? const <PremiumPlan>[
            PremiumPlan.lifetime,
            PremiumPlan.yearly,
            PremiumPlan.monthly,
          ]
        : const <PremiumPlan>[
            PremiumPlan.yearly,
            PremiumPlan.monthly,
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
              onLongPress: onTileLongPress,
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
    this.onLongPress,
  });

  final PremiumPlan plan;
  final RcSnapshot rc;
  final bool selected;
  final bool isHero;
  final VoidCallback onTap;

  /// Hidden debug gesture handler — only non-null in debug builds.
  final VoidCallback? onLongPress;

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
        : cs.outlineVariant.withValues(alpha: 0.5);
    final borderWidth = selected ? 2.0 : 1.0;
    final fill = selected
        ? BrandColors.primary.withValues(alpha: 0.10)
        : BrandColors.surface;

    final yearlySubline = plan == PremiumPlan.yearly
        ? 'premium.paywall.tile_yearly_subline'.tr(
            namedArgs: <String, String>{'price': _yearlyPerMonth(rc)},
          )
        : null;
    final monthlySubline = plan == PremiumPlan.monthly
        ? 'premium.cancel_anytime'.tr()
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
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: DesignTokens.motionFast,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceM,
                  vertical: DesignTokens.spaceM,
                ),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusL),
                  border: Border.all(
                    color: borderColor,
                    width: borderWidth,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? BrandColors.primary
                          : cs.onSurface.withValues(alpha: 0.5),
                      size: 24,
                    ),
                    const SizedBox(width: DesignTokens.spaceM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            titleKey.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          if (yearlySubline != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              yearlySubline,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (monthlySubline != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              monthlySubline,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (lifetimeSubline != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              lifetimeSubline,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: BrandColors.goldRating,
                                fontWeight: FontWeight.w800,
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
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          price,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          periodKey.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (plan == PremiumPlan.yearly) ...<Widget>[
                          const SizedBox(height: DesignTokens.spaceXs),
                          _SaveTag(
                            label:
                                'premium.paywall.tile_yearly_save_pct'.tr(),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isHero)
                Positioned(
                  top: -10,
                  right: DesignTokens.spaceL,
                  child: _BestValueBadge(
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

class _SaveTag extends StatelessWidget {
  const _SaveTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BrandColors.success.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: BrandColors.success.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: BrandColors.success,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _BestValueBadge extends StatelessWidget {
  const _BestValueBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: BrandColors.goldRating,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.goldRating.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
      ),
    );
  }
}

// =============================================================================
// Features card — 10 rows
// =============================================================================

class _FeaturesCard extends StatelessWidget {
  const _FeaturesCard();

  static const List<_FeatureSpec> _features = <_FeatureSpec>[
    _FeatureSpec(
      icon: Icons.layers_rounded,
      titleKey: 'premium.paywall.feature_unlimited_sources_title',
      bodyKey: 'premium.paywall.feature_unlimited_sources_body',
    ),
    _FeatureSpec(
      icon: Icons.calendar_month_rounded,
      titleKey: 'premium.paywall.feature_epg_guide_title',
      bodyKey: 'premium.paywall.feature_epg_guide_body',
    ),
    _FeatureSpec(
      icon: Icons.fast_rewind_rounded,
      titleKey: 'premium.paywall.feature_catch_up_title',
      bodyKey: 'premium.paywall.feature_catch_up_body',
    ),
    _FeatureSpec(
      icon: Icons.picture_in_picture_alt_rounded,
      titleKey: 'premium.paywall.feature_pip_title',
      bodyKey: 'premium.paywall.feature_pip_body',
    ),
    _FeatureSpec(
      icon: Icons.shield_rounded,
      titleKey: 'premium.paywall.feature_no_ads_title',
      bodyKey: 'premium.paywall.feature_no_ads_body',
    ),
    _FeatureSpec(
      icon: Icons.grid_view_rounded,
      titleKey: 'premium.paywall.feature_multi_screen_title',
      bodyKey: 'premium.paywall.feature_multi_screen_body',
    ),
    _FeatureSpec(
      icon: Icons.star_rounded,
      titleKey: 'premium.paywall.feature_quality_hd_title',
      bodyKey: 'premium.paywall.feature_quality_hd_body',
    ),
    _FeatureSpec(
      icon: Icons.download_rounded,
      titleKey: 'premium.paywall.feature_download_title',
      bodyKey: 'premium.paywall.feature_download_body',
    ),
    _FeatureSpec(
      icon: Icons.cast_rounded,
      titleKey: 'premium.paywall.feature_chromecast_title',
      bodyKey: 'premium.paywall.feature_chromecast_body',
    ),
    _FeatureSpec(
      icon: Icons.lock_rounded,
      titleKey: 'premium.paywall.feature_parental_title',
      bodyKey: 'premium.paywall.feature_parental_body',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM - 2),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceXs,
              DesignTokens.spaceXs,
              DesignTokens.spaceXs,
              DesignTokens.spaceM,
            ),
            child: Text(
              'premium.paywall.section_features_title'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (var i = 0; i < _features.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == _features.length - 1
                    ? DesignTokens.spaceXs
                    : DesignTokens.spaceM - 4,
              ),
              child: _FeatureRow(spec: _features[i]),
            ),
        ],
      ),
    );
  }
}

class _FeatureSpec {
  const _FeatureSpec({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.spec});

  final _FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: BrandColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          ),
          alignment: Alignment.center,
          child: Icon(
            spec.icon,
            size: 18,
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
                spec.titleKey.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                spec.bodyKey.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Error banner
// =============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: BrandColors.error.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: BrandColors.error,
            size: 20,
          ),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: BrandColors.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CTA + trial line + restore link
// =============================================================================

class _CtaSection extends StatelessWidget {
  const _CtaSection({
    required this.rc,
    required this.activating,
    required this.onPurchase,
  });

  final RcSnapshot rc;
  final bool activating;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctaLabel = 'premium.paywall.cta_start_premium'.tr();

    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: activating ? null : onPurchase,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: Opacity(
            opacity: activating ? 0.7 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: BrandColors.brandGradient,
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusM),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: BrandColors.primary.withValues(alpha: 0.55),
                    blurRadius: 24,
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.flash_on_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: DesignTokens.spaceS),
                          Text(
                            ctaLabel,
                            style:
                                theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
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

class _TrialLine extends StatelessWidget {
  const _TrialLine({required this.rc});

  final RcSnapshot rc;

  @override
  Widget build(BuildContext context) {
    if (rc.freeTrialDays <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'premium.paywall.trial_subline'.tr(
          namedArgs: <String, String>{'days': '${rc.freeTrialDays}'},
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: BrandColors.onSurfaceMuted,
        ),
      ),
    );
  }
}

class _RestoreLink extends StatelessWidget {
  const _RestoreLink({
    required this.onRestore,
    required this.restoring,
  });

  final VoidCallback? onRestore;
  final bool restoring;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onRestore,
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        child: restoring
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(BrandColors.primary),
                ),
              )
            : Text('premium.paywall.restore'.tr()),
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
          color: BrandColors.onSurfaceMuted.withValues(alpha: 0.7),
          height: 1.4,
          fontSize: 10,
        ),
      ),
    );
  }
}

// =============================================================================
// Confirm purchase modal
// =============================================================================

class _ConfirmPurchaseDialog extends StatelessWidget {
  const _ConfirmPurchaseDialog({
    required this.plan,
    required this.price,
  });

  final PremiumPlan plan;
  final String price;

  String _planLabel() => switch (plan) {
        PremiumPlan.monthly => 'premium.plan_monthly'.tr(),
        PremiumPlan.yearly => 'premium.plan_yearly'.tr(),
        PremiumPlan.lifetime => 'premium.plan_lifetime'.tr(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceL,
      ),
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        decoration: BoxDecoration(
          color: BrandColors.surfaceHigh,
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BrandColors.primary.withValues(alpha: 0.18),
                  border: Border.all(
                    color: BrandColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shopping_bag_rounded,
                  color: BrandColors.primary,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              'premium.paywall.confirm_title'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              'premium.paywall.confirm_body'.tr(
                namedArgs: <String, String>{
                  'plan': _planLabel(),
                  'price': price,
                },
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceL),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spaceM,
                      ),
                    ),
                    child:
                        Text('premium.paywall.confirm_cancel'.tr()),
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.primary,
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spaceM,
                      ),
                    ),
                    child:
                        Text('premium.paywall.confirm_buy'.tr()),
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

// =============================================================================
// "Already premium" success state
// =============================================================================

class _AlreadyPremiumScaffold extends StatelessWidget {
  const _AlreadyPremiumScaffold({
    required this.tier,
    required this.onSignOut,
  });

  final PremiumTierActive tier;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
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

    return Scaffold(
      backgroundColor: BrandColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              BrandColors.primary,
              BrandColors.background,
            ],
            stops: <double>[0, 0.55],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              DesignTokens.spaceL,
              mq.padding.top,
              DesignTokens.spaceL,
              DesignTokens.spaceL,
            ),
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      onPressed: () =>
                          context.canPop() ? context.pop() : null,
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BrandColors.success.withValues(alpha: 0.18),
                    border: Border.all(
                      color: BrandColors.success,
                      width: 3,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    color: BrandColors.success,
                    size: 44,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceL),
                Text(
                  'premium.paywall.already_premium_title'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceS),
                Text(
                  'premium.paywall.already_premium_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusM),
                      ),
                    ),
                    child: Text(
                      'premium.paywall.already_premium_continue'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceS),
                TextButton(
                  onPressed: onSignOut,
                  child: Text(
                    'premium.paywall.active_close'.tr(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
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
