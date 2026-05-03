import 'dart:io';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Top-level ad service. Initialises the AdMob SDK on mobile (iOS /
/// Android), no-ops everywhere else.
///
/// AWAtv is freemium: free users see a sticky banner on the home screen
/// and an interstitial every Nth VOD play; premium users (gate
/// `PremiumFeature.noAds`) never see either.
///
/// The AdMob test app IDs are baked in as defaults so the build works
/// without credentials. Real ad unit IDs come from `Env`:
///
///   * AD_UNIT_BANNER_ANDROID
///   * AD_UNIT_BANNER_IOS
///   * AD_UNIT_INTERSTITIAL_ANDROID
///   * AD_UNIT_INTERSTITIAL_IOS
///
/// Override these in `.env` for production. Test IDs serve real ads
/// in test mode (visible "Test Ad" watermark) and never accumulate
/// revenue so they're safe to ship in dev / staging builds.
class AwatvAds {
  AwatvAds._();

  static AwatvAds? _instance;
  static bool _initialised = false;

  /// Singleton — call [initialise] from `main.dart` then read this
  /// from anywhere.
  static AwatvAds get instance {
    return _instance ??= AwatvAds._();
  }

  /// Initialise the AdMob SDK. Safe to call multiple times — second+
  /// calls are no-ops. Wrapped in a try/catch so a missing native
  /// SDK on web / desktop / TV doesn't crash boot.
  static Future<void> initialise() async {
    if (_initialised) return;
    if (!_isMobile) {
      _initialised = true;
      return;
    }
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      if (kDebugMode) {
        debugPrint('[ads] MobileAds initialised');
      }
    } on Object catch (e) {
      // SDK not available on this platform (web/desktop/TV). Silently
      // disable ads — the rest of the app keeps working.
      if (kDebugMode) {
        debugPrint('[ads] MobileAds init skipped: $e');
      }
      _initialised = true;
    }
  }

  /// Whether the host platform supports AdMob at all.
  static bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } on Object {
      return false;
    }
  }

  /// True once [initialise] has run AND the platform is mobile.
  bool get isAvailable => _initialised && _isMobile;

  /// Banner ad unit id for the current platform. Falls back to AdMob's
  /// universally-recognised test id if the env var isn't set.
  String get bannerAdUnitId {
    if (!_isMobile) return _testBannerId;
    if (Platform.isAndroid) {
      final fromEnv = Env.admobBannerAndroid;
      return fromEnv.isNotEmpty ? fromEnv : _testBannerAndroid;
    }
    if (Platform.isIOS) {
      final fromEnv = Env.admobBannerIos;
      return fromEnv.isNotEmpty ? fromEnv : _testBannerIos;
    }
    return _testBannerId;
  }

  /// Interstitial ad unit id for the current platform.
  String get interstitialAdUnitId {
    if (!_isMobile) return _testInterstitialId;
    if (Platform.isAndroid) {
      final fromEnv = Env.admobInterstitialAndroid;
      return fromEnv.isNotEmpty ? fromEnv : _testInterstitialAndroid;
    }
    if (Platform.isIOS) {
      final fromEnv = Env.admobInterstitialIos;
      return fromEnv.isNotEmpty ? fromEnv : _testInterstitialIos;
    }
    return _testInterstitialId;
  }

  // --- AdMob test ad unit ids — see https://developers.google.com/admob/android/test-ads
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  // Generic fallbacks (Android test ids work cross-platform in dev mode).
  static const String _testBannerId = _testBannerAndroid;
  static const String _testInterstitialId = _testInterstitialAndroid;
}
