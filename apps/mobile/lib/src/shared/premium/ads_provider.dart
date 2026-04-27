import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ads_provider.g.dart';

/// Whether AdMob banners and interstitials should be displayed.
///
/// Phase 1 just exposes the boolean — the actual ad widgets land in
/// Phase 4 once the AdMob publisher account is set up. Wiring the
/// provider now means future ad components only need to
/// `ref.watch(adsEnabledProvider)` and the premium opt-out happens
/// automatically.
@Riverpod(keepAlive: true)
bool adsEnabled(Ref ref) {
  // "Ads enabled" is the inverse of "user has the no-ads gate". Going
  // through `canUseFeatureProvider` keeps the contract consistent —
  // every other gated capability uses the same provider.
  return !ref.watch(canUseFeatureProvider(PremiumFeature.noAds));
}
