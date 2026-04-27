import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cloud_sync_gate.g.dart';

/// Cloud sync requires *both* a premium tier and a signed-in account.
///
/// Premium alone is not enough — without an account we have no remote
/// to sync to. Account alone is not enough — the storage / bandwidth
/// is part of the premium plan.
///
/// Settings, paywall and any future "Sync now" button all consume this
/// instead of `canUseFeatureProvider(PremiumFeature.cloudSync)` so the
/// auth coupling stays in one place.
@Riverpod(keepAlive: true)
bool canUseCloudSync(Ref ref) {
  final tier = ref.watch(premiumStatusProvider);
  final auth = ref.watch(authControllerProvider).valueOrNull;
  return tier.isPremium && auth is AuthSignedIn;
}
