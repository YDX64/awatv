import 'dart:async';
import 'dart:io';

import 'package:awatv_mobile/src/shared/ads/awatv_ads.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ads_providers.g.dart';

/// True when the current user / tier should see ads. Inverse of the
/// `PremiumFeature.noAds` gate — every screen that shows ads watches
/// this provider and renders an empty `SizedBox.shrink()` when it
/// reads `false`.
///
/// Returns `false` on web / desktop / TV regardless of tier (the
/// AdMob SDK isn't available there, no point showing ad slots).
@Riverpod(keepAlive: true)
bool adsEnabled(Ref ref) {
  if (kIsWeb) return false;
  try {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
  } on Object {
    return false;
  }
  // Premium users have the noAds feature unlocked.
  final hasNoAds = ref.watch(canUseFeatureProvider(PremiumFeature.noAds));
  return !hasNoAds;
}

/// Counter that drives the interstitial cadence. Every time a VOD or
/// channel starts playing the player calls `bumpPlaybackCounter()`;
/// when the counter mod [_interstitialEveryN] hits 0 we flag an
/// interstitial show.
@Riverpod(keepAlive: true)
class PlaybackCounter extends _$PlaybackCounter {
  @override
  int build() => 0;

  /// Show an interstitial after every Nth playback start. Starts at 1
  /// because the user typically taps once after onboarding — letting
  /// them play the first stream ad-free is good vibes.
  static const int _interstitialEveryN = 3;

  /// Bump the counter. Returns true when the caller should trigger
  /// an interstitial. No-op for premium users.
  bool bump() {
    final adsOn = ref.read(adsEnabledProvider);
    if (!adsOn) return false;
    final next = state + 1;
    state = next;
    return next % _interstitialEveryN == 0;
  }
}

/// Loads + caches a single [InterstitialAd]. The first `show()` call
/// after init hits a preloaded ad; subsequent calls re-load.
@Riverpod(keepAlive: true)
class InterstitialAdController extends _$InterstitialAdController {
  InterstitialAd? _loaded;
  bool _loading = false;

  @override
  void build() {
    ref.onDispose(() {
      _loaded?.dispose();
      _loaded = null;
    });
    // Preload on first observer mount so the first show() is instant.
    _preload();
  }

  void _preload() {
    if (_loading || _loaded != null) return;
    final adsOn = ref.read(adsEnabledProvider);
    if (!adsOn) return;
    final ads = AwatvAds.instance;
    if (!ads.isAvailable) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: ads.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _loaded = ad;
          _loading = false;
          if (kDebugMode) debugPrint('[ads] interstitial preloaded');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _loading = false;
          if (kDebugMode) debugPrint('[ads] interstitial load failed: $error');
        },
      ),
    );
  }

  /// Show the preloaded interstitial, if any. After dismiss, kick off
  /// the next preload so the chain stays warm.
  Future<void> show() async {
    final ad = _loaded;
    if (ad == null) {
      // Nothing to show — kick off a load for next time.
      _preload();
      return;
    }
    _loaded = null;
    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete();
        _preload();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError err) {
        ad.dispose();
        if (kDebugMode) debugPrint('[ads] interstitial failed to show: $err');
        if (!completer.isCompleted) completer.complete();
        _preload();
      },
    );
    await ad.show();
    return completer.future;
  }
}

/// Convenience that bumps the playback counter and, if cadence hits,
/// shows an interstitial. Returns true if an ad was shown so the
/// caller can wait before starting playback (better UX — let the ad
/// finish before audio starts).
@riverpod
class AdsLifecycle extends _$AdsLifecycle {
  @override
  void build() {}

  /// Call from the player on every playback start.
  Future<bool> onPlaybackStart() async {
    final due = ref.read(playbackCounterProvider.notifier).bump();
    if (!due) return false;
    await ref.read(interstitialAdControllerProvider.notifier).show();
    return true;
  }
}
