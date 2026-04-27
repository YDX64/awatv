import 'package:flutter/foundation.dart';

/// Subscription state for the current user.
///
/// Sealed so the rest of the codebase can pattern-match on the two
/// variants without remembering nullable contracts. The active variant
/// carries the plan, optional expiry (lifetime is `null`), and a
/// `willRenew` bit copied from the store receipt — when `false` we
/// surface a "renews on …" cue and after expiry we drop back to free.
@immutable
sealed class PremiumTier {
  const PremiumTier();
}

/// Default tier — the user has not (or no longer has) an active premium
/// entitlement. Hardcoded quotas live as static constants so they can be
/// referenced by the comparison table without instantiating the class.
final class FreeTier extends PremiumTier {
  const FreeTier();

  /// Maximum number of playlist sources a free user can register.
  static const int playlistLimit = 2;

  /// How far back the EPG screen is allowed to render in the free tier.
  static const int epgPastDays = 1;
}

/// Active premium entitlement.
///
/// `expiresAt` is `null` for the lifetime plan; for monthly/yearly it
/// reflects the store-provided "next renewal" date. `willRenew` mirrors
/// the auto-renew flag — when the user cancels we keep premium until
/// the period ends, then revert to [FreeTier].
final class PremiumTierActive extends PremiumTier {
  const PremiumTierActive({
    required this.plan,
    required this.expiresAt,
    required this.willRenew,
  });

  final PremiumPlan plan;
  final DateTime? expiresAt;
  final bool willRenew;

  PremiumTierActive copyWith({
    PremiumPlan? plan,
    DateTime? expiresAt,
    bool? willRenew,
  }) {
    return PremiumTierActive(
      plan: plan ?? this.plan,
      expiresAt: expiresAt ?? this.expiresAt,
      willRenew: willRenew ?? this.willRenew,
    );
  }

  /// True once `expiresAt` is in the past. Lifetime never expires.
  bool isExpired(DateTime now) {
    final expires = expiresAt;
    if (expires == null) return false;
    return now.isAfter(expires);
  }
}

/// Pricing plans surfaced on the paywall. New plans require updating
/// the JSON serialisation in `premium_status_provider.dart`.
enum PremiumPlan { monthly, yearly, lifetime }

extension PremiumTierExt on PremiumTier {
  /// Convenience: any [PremiumTierActive] state — even one that is
  /// about to be expired by the next tick — counts as premium.
  bool get isPremium => this is PremiumTierActive;

  /// Inverse of [isPremium].
  bool get isFree => this is FreeTier;

  /// The active plan when premium, otherwise `null`.
  PremiumPlan? get plan => switch (this) {
        PremiumTierActive(:final plan) => plan,
        FreeTier() => null,
      };

  /// Renewal/expiry date when premium, otherwise `null`.
  DateTime? get expiresAt => switch (this) {
        PremiumTierActive(:final expiresAt) => expiresAt,
        FreeTier() => null,
      };
}
