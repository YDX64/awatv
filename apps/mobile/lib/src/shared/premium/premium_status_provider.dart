import 'dart:convert';

import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'premium_status_provider.g.dart';

/// Hive `prefs` box key used to persist the JSON-encoded tier.
const String _kPrefsKey = 'premium:tier';

/// Single-row notifier holding the user's active subscription state.
///
/// Persists every change to the shared `prefs` Hive box so the tier
/// survives app restarts. Until RevenueCat is wired (Phase 5) the
/// [simulateActivate] entry-point is what the in-app paywall calls so
/// the rest of the app can be exercised end-to-end. Once IAP lands the
/// notifier swaps `simulateActivate` for a webhook/listener — every
/// other gate keeps consuming the same state.
@Riverpod(keepAlive: true)
class PremiumStatus extends _$PremiumStatus {
  @override
  PremiumTier build() {
    final initial = _readPersisted();
    // If the stored entitlement has elapsed, demote on boot so the rest
    // of the app does not flicker through a brief premium frame.
    if (initial is PremiumTierActive &&
        initial.isExpired(DateTime.now().toUtc())) {
      // Drop expired record from disk and surface free.
      _persist(const FreeTier());
      return const FreeTier();
    }
    return initial;
  }

  /// Dev-mode entry-point used by the paywall in lieu of a real IAP
  /// flow. Maps the chosen plan to a sensible expiry window:
  ///   - monthly  → +30 days, auto-renew on
  ///   - yearly   → +365 days, auto-renew on
  ///   - lifetime → null expiry, auto-renew off
  Future<void> simulateActivate(PremiumPlan plan) async {
    final now = DateTime.now().toUtc();
    final next = switch (plan) {
      PremiumPlan.monthly => PremiumTierActive(
          plan: plan,
          expiresAt: now.add(const Duration(days: 30)),
          willRenew: true,
        ),
      PremiumPlan.yearly => PremiumTierActive(
          plan: plan,
          expiresAt: now.add(const Duration(days: 365)),
          willRenew: true,
        ),
      PremiumPlan.lifetime => PremiumTierActive(
          plan: plan,
          expiresAt: null,
          willRenew: false,
        ),
    };
    state = next;
    await _persist(next);
  }

  /// Returns the user to the free tier — used by "sign out" / cancel
  /// flows and by the dev console reset button.
  Future<void> signOut() async {
    state = const FreeTier();
    await _persist(const FreeTier());
  }

  /// Re-evaluates the expiry; called by gates when the app comes back
  /// to foreground. If we just expired we transition to free and
  /// persist.
  Future<void> reconcile() async {
    final current = state;
    if (current is PremiumTierActive &&
        current.isExpired(DateTime.now().toUtc())) {
      state = const FreeTier();
      await _persist(const FreeTier());
    }
  }

  // ---------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------

  PremiumTier _readPersisted() {
    final box = ref.read(awatvStorageProvider).prefsBox;
    final raw = box.get(_kPrefsKey);
    if (raw is! String || raw.isEmpty) return const FreeTier();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _decode(json);
    } on Object {
      // Corrupt record — fall back to free and let the next write heal.
      return const FreeTier();
    }
  }

  Future<void> _persist(PremiumTier tier) async {
    final box = ref.read(awatvStorageProvider).prefsBox;
    await box.put(_kPrefsKey, jsonEncode(_encode(tier)));
  }

  static Map<String, dynamic> _encode(PremiumTier tier) => switch (tier) {
        FreeTier() => <String, dynamic>{'tier': 'free'},
        PremiumTierActive(
          :final plan,
          :final expiresAt,
          :final willRenew,
        ) =>
          <String, dynamic>{
            'tier': 'premium',
            'plan': plan.name,
            'expiresAt': expiresAt?.toIso8601String(),
            'willRenew': willRenew,
          },
      };

  static PremiumTier _decode(Map<String, dynamic> json) {
    final kind = json['tier'] as String?;
    if (kind != 'premium') return const FreeTier();
    final planName = json['plan'] as String?;
    final plan = PremiumPlan.values.firstWhere(
      (p) => p.name == planName,
      orElse: () => PremiumPlan.monthly,
    );
    final expires = json['expiresAt'];
    final willRenew = json['willRenew'];
    return PremiumTierActive(
      plan: plan,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      willRenew: willRenew is bool && willRenew,
    );
  }
}
