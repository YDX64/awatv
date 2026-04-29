import 'package:flutter/foundation.dart';

/// Read-only snapshot of every Remote Config value AWAtv reads.
///
/// We don't pass `FirebaseRemoteConfig` around — every consumer reads a
/// strongly-typed [RcSnapshot]. Defaults are baked in here so the rest
/// of the app behaves the same whether RC reached the network or not.
///
/// New keys go in three places:
///   1. `RcKeys` (the literal key string)
///   2. `RcSnapshot.fallback` (the default the app uses pre-fetch)
///   3. `RcSnapshot.from(rc)` (the live mapping)
@immutable
class RcSnapshot {
  const RcSnapshot({
    required this.paywallVariant,
    required this.priceMonthly,
    required this.priceYearly,
    required this.priceLifetime,
    required this.castEnabled,
    required this.remoteControlEnabled,
    required this.maintenanceMessage,
  });

  /// Default snapshot used when Firebase isn't configured or hasn't
  /// fetched yet. Matches the hard-coded copy that the app shipped with
  /// before Remote Config landed, so behaviour is invariant.
  const RcSnapshot.fallback()
      : paywallVariant = 'A',
        priceMonthly = 'EUR 3,99 / ay',
        priceYearly = 'EUR 29,99 / yil',
        priceLifetime = 'EUR 69,99',
        castEnabled = true,
        remoteControlEnabled = true,
        maintenanceMessage = '';

  /// 'A' or 'B' — drives the paywall layout. 'A' (default) highlights
  /// yearly in the middle; 'B' highlights lifetime and reorders the cards
  /// so the user lands on it first.
  final String paywallVariant;

  /// Localised price strings. Pulled live so the marketing team can move
  /// the prices in a region without shipping a build.
  final String priceMonthly;
  final String priceYearly;
  final String priceLifetime;

  /// Server-side feature flags. Off-by-default would make a missing
  /// fetch a regression for users in offline-mode, so we keep them
  /// `true` and let RC turn them off.
  final bool castEnabled;
  final bool remoteControlEnabled;

  /// When non-empty, the home shell renders a yellow banner above the
  /// content area with this string. Used for "we are migrating servers
  /// at 02:00 UTC" announcements.
  final String maintenanceMessage;

  RcSnapshot copyWith({
    String? paywallVariant,
    String? priceMonthly,
    String? priceYearly,
    String? priceLifetime,
    bool? castEnabled,
    bool? remoteControlEnabled,
    String? maintenanceMessage,
  }) {
    return RcSnapshot(
      paywallVariant: paywallVariant ?? this.paywallVariant,
      priceMonthly: priceMonthly ?? this.priceMonthly,
      priceYearly: priceYearly ?? this.priceYearly,
      priceLifetime: priceLifetime ?? this.priceLifetime,
      castEnabled: castEnabled ?? this.castEnabled,
      remoteControlEnabled:
          remoteControlEnabled ?? this.remoteControlEnabled,
      maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RcSnapshot &&
        other.paywallVariant == paywallVariant &&
        other.priceMonthly == priceMonthly &&
        other.priceYearly == priceYearly &&
        other.priceLifetime == priceLifetime &&
        other.castEnabled == castEnabled &&
        other.remoteControlEnabled == remoteControlEnabled &&
        other.maintenanceMessage == maintenanceMessage;
  }

  @override
  int get hashCode => Object.hash(
        paywallVariant,
        priceMonthly,
        priceYearly,
        priceLifetime,
        castEnabled,
        remoteControlEnabled,
        maintenanceMessage,
      );
}

/// Single source of truth for the Remote Config key strings. Used by both
/// `setDefaults` and the live mapping.
class RcKeys {
  const RcKeys._();

  static const String paywallVariant = 'paywall_variant';
  static const String priceMonthly = 'price_monthly';
  static const String priceYearly = 'price_yearly';
  static const String priceLifetime = 'price_lifetime';
  static const String featureFlagRemoteControl = 'feature_flag_remote_control';
  static const String featureFlagCast = 'feature_flag_cast';
  static const String maintenanceMessage = 'maintenance_message';

  /// All defaults in one map — handed straight to `rc.setDefaults`.
  static Map<String, dynamic> get defaults => <String, dynamic>{
        paywallVariant: 'A',
        priceMonthly: 'EUR 3,99 / ay',
        priceYearly: 'EUR 29,99 / yil',
        priceLifetime: 'EUR 69,99',
        featureFlagRemoteControl: true,
        featureFlagCast: true,
        maintenanceMessage: '',
      };
}
