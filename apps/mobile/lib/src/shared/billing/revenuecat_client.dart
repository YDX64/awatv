import 'dart:io';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Stable RevenueCat product identifiers wired in the App Store + Play
/// Console. The Edge-Function webhook expects these exact strings when
/// it maps a transaction to a `PremiumPlan`.
///
/// Keep these in sync with:
///   * Apple — App Store Connect product ids
///   * Google — Play Console product ids
///   * RevenueCat — Offerings → Default offering → Packages
///   * Supabase — `revenuecat-webhook` Edge Function `mapPlan()`
class AwatvProductIds {
  const AwatvProductIds._();

  /// 1-month auto-renewing subscription.
  static const String monthly = 'awatv_premium_monthly';

  /// 1-year auto-renewing subscription.
  static const String yearly = 'awatv_premium_yearly';

  /// Non-consumable lifetime entitlement.
  static const String lifetime = 'awatv_premium_lifetime';

  /// Returns true when the given product id matches a known plan. Used
  /// for defensive validation in the purchase flow so we can surface a
  /// configuration error early instead of letting StoreKit / Billing
  /// throw an opaque "product not found".
  static bool isKnown(String id) =>
      id == monthly || id == yearly || id == lifetime;
}

/// Outcome of a [AwatvBilling.purchaseProduct] call. We don't surface
/// `CustomerInfo` here on purpose — entitlement is owned by the
/// Supabase `subscriptions` table, not RC's local view, so the UI
/// should never branch on RC's idea of premium-or-not. Instead the
/// realtime stream wired into `PremiumStatus` flips the global state
/// and the paywall re-renders accordingly.
@immutable
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

/// Purchase succeeded at the store layer. The Supabase webhook will
/// land within seconds — the UI can show a success toast immediately.
final class PurchaseOutcomeSuccess extends PurchaseOutcome {
  const PurchaseOutcomeSuccess();
}

/// User dismissed the native sheet (StoreKit / Play Billing). NOT an
/// error — show no toast, just unlock the CTA.
final class PurchaseOutcomeCancelled extends PurchaseOutcome {
  const PurchaseOutcomeCancelled();
}

/// Anything else: store unreachable, payment declined, product
/// misconfigured, billing not initialised. The UI surfaces [message]
/// in a snackbar.
final class PurchaseOutcomeFailure extends PurchaseOutcome {
  const PurchaseOutcomeFailure({
    required this.message,
    this.errorCode,
  });

  final String message;
  final PurchasesErrorCode? errorCode;
}

/// Outcome of [AwatvBilling.restorePurchases]. Like [PurchaseOutcome]
/// but slimmer because there's no cancel branch.
@immutable
sealed class RestoreOutcome {
  const RestoreOutcome();
}

/// Restore handshake completed at the store layer. The webhook will
/// reconcile within seconds; if the user actually owned an entitlement
/// the realtime stream flips premium back on automatically.
final class RestoreOutcomeSuccess extends RestoreOutcome {
  const RestoreOutcomeSuccess();
}

/// Restore failed (offline, store rejected the transaction list, etc).
final class RestoreOutcomeFailure extends RestoreOutcome {
  const RestoreOutcomeFailure({required this.message});

  final String message;
}

/// Top-level RevenueCat client. Singleton-ised so the same configured
/// instance is reachable from anywhere — Riverpod providers just hand
/// out [instance], they don't construct their own.
///
/// Boot order matters: [initialise] must run before any of the public
/// methods, otherwise `Purchases.*` calls will throw
/// [PurchasesErrorCode.configurationError]. `main.dart` fires
/// [initialise] right after Supabase init.
///
/// Web + desktop + TV are no-ops; the underlying SDK isn't shipped on
/// those platforms and the paywall there should fall back to "open in
/// the mobile app" copy. We honour the platform check at every entry
/// point so callers don't have to remember to branch.
class AwatvBilling {
  AwatvBilling._();

  static AwatvBilling? _instance;
  static bool _initialised = false;
  static bool _initInFlight = false;

  /// Currently bound RevenueCat appUserId (Supabase user id when signed
  /// in, anonymous RC id when guest). Tracked so [setAppUserId] can
  /// short-circuit redundant `logIn` calls — RC's network round-trip
  /// is real (≈300 ms on cellular).
  String? _boundUserId;

  /// Singleton accessor.
  static AwatvBilling get instance {
    return _instance ??= AwatvBilling._();
  }

  /// Whether [initialise] has run AND we're on a platform with a
  /// native SDK (iOS / Android). Read by Riverpod gates so screens
  /// can hide the "Subscribe" CTA on unsupported platforms.
  bool get isAvailable => _initialised && _isMobile;

  /// True after [initialise] finishes (either successfully or after
  /// having decided the platform is unsupported). Lets the UI tell
  /// "still booting" apart from "available".
  bool get isInitialised => _initialised;

  /// Initialise the SDK with the platform-specific public API key from
  /// `.env`. Idempotent — second+ calls are no-ops. Safe to fire from
  /// `main.dart` without awaiting; the first paywall mount will read
  /// [isInitialised] and show a spinner if init is still in flight.
  ///
  /// On web / desktop / TV we mark as initialised-but-unavailable so
  /// the rest of the codebase doesn't have to special-case those
  /// platforms.
  Future<void> initialise() async {
    if (_initialised || _initInFlight) return;
    _initInFlight = true;
    try {
      if (!_isMobile) {
        if (kDebugMode) {
          debugPrint(
            '[billing] RevenueCat init skipped: unsupported platform',
          );
        }
        _initialised = true;
        return;
      }
      final apiKey = _apiKeyForPlatform();
      if (apiKey.isEmpty) {
        // No key configured → init is a no-op. We still flip
        // `_initialised` so isAvailable returns false consistently
        // and the UI hides the CTA instead of showing an enabled
        // button that would crash on tap.
        if (kDebugMode) {
          debugPrint('[billing] RevenueCat key missing for this platform');
        }
        _initialised = true;
        return;
      }
      // Verbose logs only in debug — keeps the production console clean
      // and avoids leaking customer ids into Crashlytics breadcrumbs.
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      } else {
        await Purchases.setLogLevel(LogLevel.warn);
      }
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _initialised = true;
      if (kDebugMode) {
        debugPrint('[billing] RevenueCat configured');
      }
    } on Object catch (e) {
      // SDK refused to initialise (malformed key, missing native module,
      // sandbox quirk). Mark as initialised so [isAvailable] returns
      // false and the UI shows a polite "Premium unavailable on this
      // device" rather than a spinner that never resolves.
      if (kDebugMode) {
        debugPrint('[billing] RevenueCat init failed: $e');
      }
      _initialised = true;
    } finally {
      _initInFlight = false;
    }
  }

  /// Bind the RevenueCat appUserId to the Supabase user id. Called when
  /// auth flips to `AuthSignedIn` — guarantees RC's webhook payload
  /// carries the same id the `subscriptions` table is keyed on, so the
  /// Edge Function can find the right row.
  ///
  /// Idempotent: a second call with the same id is a cheap local
  /// branch, no network round-trip.
  Future<void> setAppUserId(String supabaseUserId) async {
    if (!isAvailable) return;
    if (supabaseUserId.isEmpty) return;
    if (_boundUserId == supabaseUserId) return;
    try {
      await Purchases.logIn(supabaseUserId);
      _boundUserId = supabaseUserId;
      if (kDebugMode) {
        debugPrint('[billing] RC bound to user $supabaseUserId');
      }
    } on Object catch (e) {
      // Failing to bind doesn't break purchase — RC will use its
      // anonymous id and the webhook will fall back to the receipt
      // email. Surface in debug so a misconfigured staging build is
      // caught early.
      if (kDebugMode) {
        debugPrint('[billing] RC logIn failed: $e');
      }
    }
  }

  /// Detach the current appUserId (sign-out). RC's anonymous flow
  /// kicks in until the next [setAppUserId]. Safe to call when no user
  /// is bound; it's a no-op.
  Future<void> clearAppUserId() async {
    if (!isAvailable) return;
    if (_boundUserId == null) return;
    try {
      await Purchases.logOut();
    } on Object catch (e) {
      // logOut throws when the current user is already anonymous —
      // we treat that as success since the desired state is reached.
      if (kDebugMode) {
        debugPrint('[billing] RC logOut: $e');
      }
    } finally {
      _boundUserId = null;
    }
  }

  /// Fetch the active offering. Returns null when unavailable
  /// (unsupported platform, init failed, RC dashboard misconfigured).
  /// Callers should fall back to RC-prefilled price strings from
  /// `RcSnapshot` in that case.
  Future<Offering?> getCurrentOffering() async {
    if (!isAvailable) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[billing] getOfferings failed: $e');
      }
      return null;
    }
  }

  /// Fetch all configured offerings. Used by debug screens; the paywall
  /// only ever needs [getCurrentOffering].
  Future<Offerings?> getOfferings() async {
    if (!isAvailable) return null;
    try {
      return await Purchases.getOfferings();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[billing] getOfferings failed: $e');
      }
      return null;
    }
  }

  /// Look up the [Package] in the current offering for the given
  /// product id. Returns null when no package matches — e.g. RC
  /// dashboard hasn't been wired yet, or the offering's package list
  /// drifted from the constants in [AwatvProductIds].
  ///
  /// Resolution order:
  ///   1. Match by `package.storeProduct.identifier` exactly. Catches
  ///      the common case where the dashboard package id is e.g.
  ///      `$rc_monthly` but the underlying StoreKit product id is
  ///      `awatv_premium_monthly` (RC's recommended setup).
  ///   2. Match by `package.identifier` — if the dashboard editor
  ///      named the package directly with our product id.
  Future<Package?> findPackageForProduct(String productId) async {
    final offering = await getCurrentOffering();
    if (offering == null) return null;
    for (final package in offering.availablePackages) {
      if (package.storeProduct.identifier == productId) return package;
    }
    for (final package in offering.availablePackages) {
      if (package.identifier == productId) return package;
    }
    return null;
  }

  /// Run the StoreKit / Play Billing purchase sheet for [productId].
  ///
  /// We deliberately resolve through the [Package] flow even when the
  /// caller hands us a raw product id — `Purchases.purchasePackage` is
  /// the recommended path because it forwards the offering context
  /// that the RC backend correlates against the webhook payload.
  ///
  /// Errors map cleanly:
  ///   * user-cancellation → [PurchaseOutcomeCancelled]
  ///   * everything else → [PurchaseOutcomeFailure] with a
  ///     copy-ready message. The UI never sees a raw stack trace.
  ///
  /// Entitlement state is *not* mutated locally. The Supabase
  /// realtime listener inside `PremiumStatus` picks up the row write
  /// from the RC → webhook chain and flips the global premium UX.
  Future<PurchaseOutcome> purchaseProduct(String productId) async {
    if (!isAvailable) {
      return const PurchaseOutcomeFailure(
        message: 'Premium satin alimi bu cihazda kullanilamiyor.',
      );
    }
    if (!AwatvProductIds.isKnown(productId)) {
      // Programming error — the paywall asked for an unknown sku.
      // Refuse loudly rather than letting the store throw.
      return PurchaseOutcomeFailure(
        message: 'Bilinmeyen urun: $productId',
      );
    }
    try {
      final package = await findPackageForProduct(productId);
      if (package != null) {
        await Purchases.purchasePackage(package);
        return const PurchaseOutcomeSuccess();
      }
      // Fallback path when the offering wasn't configured properly:
      // attempt a direct product fetch + purchase. Keeps the user
      // unblocked while a misconfigured RC dashboard is sorted out.
      final products = await Purchases.getProducts(<String>[productId]);
      if (products.isEmpty) {
        return PurchaseOutcomeFailure(
          message: 'Satin alma urunu bulunamadi: $productId',
        );
      }
      await Purchases.purchaseStoreProduct(products.first);
      return const PurchaseOutcomeSuccess();
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return const PurchaseOutcomeCancelled();
      }
      return PurchaseOutcomeFailure(
        message: _humaniseError(code, e.message),
        errorCode: code,
      );
    } on Object catch (e) {
      return PurchaseOutcomeFailure(message: e.toString());
    }
  }

  /// Trigger RC's `restorePurchases`. The store hands back the receipt,
  /// RC posts it to the backend, and the webhook updates Supabase.
  /// We don't read the returned `CustomerInfo` — the realtime stream
  /// is the source of truth.
  Future<RestoreOutcome> restorePurchases() async {
    if (!isAvailable) {
      return const RestoreOutcomeFailure(
        message: 'Geri yukleme bu cihazda kullanilamiyor.',
      );
    }
    try {
      await Purchases.restorePurchases();
      return const RestoreOutcomeSuccess();
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      return RestoreOutcomeFailure(
        message: _humaniseError(code, e.message),
      );
    } on Object catch (e) {
      return RestoreOutcomeFailure(message: e.toString());
    }
  }

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  /// Whether the current platform has a native RevenueCat SDK.
  static bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } on Object {
      return false;
    }
  }

  /// Public RC API key for the current platform. Empty when the
  /// developer hasn't filled in `.env` — the rest of the boot path
  /// treats that as "billing unavailable".
  static String _apiKeyForPlatform() {
    if (kIsWeb) return '';
    try {
      if (Platform.isIOS) return Env.revenueCatKeyIos;
      if (Platform.isAndroid) return Env.revenueCatKeyAndroid;
    } on Object {
      return '';
    }
    return '';
  }

  /// Defensively decode the `e.code` integer string. RC ships the
  /// error code as the `PlatformException.code` field; some store
  /// errors arrive without one, in which case we fall back to
  /// `unknownError` rather than crashing the UI.
  static PurchasesErrorCode? _safeErrorCode(PlatformException e) {
    try {
      return PurchasesErrorHelper.getErrorCode(e);
    } on Object {
      return null;
    }
  }

  /// Map an RC error code to user-facing Turkish copy. The strings are
  /// duplicated here (rather than living in i18n JSON) on purpose — the
  /// localiser is a snackbar surface and we don't want a build-time
  /// failure if a translation key is missing for a brand-new RC error
  /// variant. Falls back to the platform-provided message which is
  /// already localised by the OS.
  static String _humaniseError(
    PurchasesErrorCode? code,
    String? fallback,
  ) {
    final mapped = switch (code) {
      PurchasesErrorCode.purchaseCancelledError => 'Satin alim iptal edildi.',
      PurchasesErrorCode.purchaseNotAllowedError =>
        'Bu cihazda satin alima izin yok.',
      PurchasesErrorCode.purchaseInvalidError ||
      PurchasesErrorCode.productNotAvailableForPurchaseError =>
        'Urun mevcut degil. Lutfen daha sonra tekrar deneyin.',
      PurchasesErrorCode.productAlreadyPurchasedError =>
        'Bu urun zaten satin alinmis.',
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError =>
        'Internet baglantisi kurulamadi.',
      PurchasesErrorCode.paymentPendingError =>
        'Odeme onaylaniyor. Onaylandiginda Premium etkinlesir.',
      PurchasesErrorCode.storeProblemError =>
        'Magaza yanit vermiyor. Tekrar deneyin.',
      PurchasesErrorCode.invalidReceiptError ||
      PurchasesErrorCode.missingReceiptFileError =>
        'Magaza fisi dogrulanamadi.',
      PurchasesErrorCode.configurationError =>
        'Premium yapilandirmasi eksik.',
      PurchasesErrorCode.receiptAlreadyInUseError ||
      PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
        'Bu fis baska bir hesapta aktif.',
      PurchasesErrorCode.ineligibleError => 'Bu plan icin uygunluk yok.',
      _ => null,
    };
    if (mapped != null) return mapped;
    if (fallback != null && fallback.trim().isNotEmpty) return fallback;
    return 'Beklenmeyen bir hata olustu.';
  }
}
