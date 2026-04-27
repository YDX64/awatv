import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'premium_quotas.g.dart';

/// Sentinel for "no practical limit". Picked at 9999 (rather than
/// `int.max`) to keep UI math safe and to give us obvious telemetry
/// signal if someone accidentally rolls past it.
const int _kPremiumPlaylistCeiling = 9999;

/// Maximum number of playlist sources the current tier may register.
///
/// Free tier returns [FreeTier.playlistLimit]; premium returns the
/// effectively-unlimited sentinel. Consumers compare
/// `currentCount >= playlistQuota` to decide whether to gate the
/// "+ Add" affordance.
@Riverpod(keepAlive: true)
int playlistQuota(Ref ref) {
  final tier = ref.watch(premiumStatusProvider);
  return tier.isPremium ? _kPremiumPlaylistCeiling : FreeTier.playlistLimit;
}

/// EPG-past-days quota — gated separately because it is a numeric
/// limit rather than a yes/no capability.
///
/// Free → 1 day, Premium → 14 days. The EPG screen reads this provider
/// and clamps its scrollback range accordingly.
@Riverpod(keepAlive: true)
int epgPastDaysQuota(Ref ref) {
  final tier = ref.watch(premiumStatusProvider);
  return tier.isPremium ? 14 : FreeTier.epgPastDays;
}
