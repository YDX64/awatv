import 'dart:async';

import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/billing/revenuecat_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'billing_providers.g.dart';

/// Riverpod handle on the [AwatvBilling] singleton.
///
/// `keepAlive` because billing is global state — every paywall mount,
/// settings row, or restore-link tap reads from the same instance.
/// Re-running `build` would lose the cached `_boundUserId` and force a
/// redundant `Purchases.logIn` round-trip on every screen change.
@Riverpod(keepAlive: true)
AwatvBilling awatvBilling(Ref ref) => AwatvBilling.instance;

/// Active RC offering (the "default" set on the dashboard). Used by
/// the paywall to render localised price strings — RC formats them in
/// the user's StoreKit / Play Billing locale, which we can't replicate
/// from the Hive-cached Remote Config snapshot.
///
/// Returns `null` on web / desktop / TV, when init failed, or when the
/// dashboard has no current offering. Callers fall back to
/// `RcSnapshot` price strings in that case so the paywall still
/// renders.
@Riverpod(keepAlive: true)
Future<Offering?> currentOfferings(Ref ref) async {
  final billing = ref.watch(awatvBillingProvider);
  if (!billing.isAvailable) return null;
  return billing.getCurrentOffering();
}

/// Side-effect listener — every time auth flips to [AuthSignedIn] we
/// bind RC to the Supabase user id, and every time it flips to
/// [AuthGuest] we detach.
///
/// Keeping the binding inside a Riverpod listener (rather than an
/// imperative call from the auth controller) means:
///   * the call is automatic — every code path that signs the user in
///     funnels through `authControllerProvider` already, so we cover
///     magic-link, password sign-in, sign-up, and deep-link callback
///     in one shot.
///   * we don't have to import `AwatvBilling` inside `AuthController`,
///     keeping the auth layer free of billing dependencies.
///
/// The provider itself is intentionally `void`; it's instantiated once
/// at app start (see [billingBootstrapProvider]) and the listener does
/// all the work via [Ref.listen].
@Riverpod(keepAlive: true)
class BillingIdentitySync extends _$BillingIdentitySync {
  @override
  void build() {
    ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (previous, next) {
        final state = next.valueOrNull;
        if (state is AuthSignedIn) {
          unawaited(_bind(state.userId));
        } else if (state is AuthGuest) {
          unawaited(_unbind());
        }
        // AuthLoading / AuthError → leave the previous binding in place;
        // a transient error shouldn't drop the RC↔Supabase link.
      },
      // `fireImmediately` so a session already restored from the
      // SDK (cold-start) gets bound on first frame, not on the next
      // auth event.
      fireImmediately: true,
    );
  }

  Future<void> _bind(String userId) async {
    final billing = ref.read(awatvBillingProvider);
    // If billing is still booting, wait one tick — `initialise` is
    // fire-and-forget from `main.dart` so we may race the auth event.
    if (!billing.isInitialised) {
      await billing.initialise();
    }
    await billing.setAppUserId(userId);
  }

  Future<void> _unbind() async {
    final billing = ref.read(awatvBillingProvider);
    if (!billing.isInitialised) return;
    await billing.clearAppUserId();
  }
}

/// One-shot bootstrap that ensures [BillingIdentitySync] is mounted
/// alongside the rest of the app boot. The app shell reads this in
/// `build` so the listener attaches before any screen can offer a
/// purchase CTA.
///
/// Implemented as a `Provider<void>` rather than a `FutureProvider`
/// because we don't want consumers to await it — it just has to be
/// observed once for [BillingIdentitySync.build] to fire.
@Riverpod(keepAlive: true)
void billingBootstrap(Ref ref) {
  // Mount the identity sync listener.
  ref.watch(billingIdentitySyncProvider);
  if (kDebugMode) {
    debugPrint('[billing] identity sync mounted');
  }
}
