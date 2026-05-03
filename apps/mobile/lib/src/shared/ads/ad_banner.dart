import 'dart:io';

import 'package:awatv_mobile/src/shared/ads/ads_providers.dart';
import 'package:awatv_mobile/src/shared/ads/awatv_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Sticky banner ad slot. Renders nothing for premium users (gate
/// `PremiumFeature.noAds`) and on platforms where AdMob isn't shipped
/// (web / desktop / TV).
///
/// Drop into a Scaffold's `bottomNavigationBar` slot or as the last
/// child in a Column; the widget self-sizes to the AdSize.banner
/// dimensions (320×50 standard, larger on tablets if `adaptiveBanner`
/// is true).
class AdBannerWidget extends ConsumerStatefulWidget {
  const AdBannerWidget({
    super.key,
    this.adaptiveBanner = false,
    this.padding = EdgeInsets.zero,
  });

  /// When true, request an anchored adaptive banner sized to the screen
  /// width. Smarter for tablets but loads slightly slower because the
  /// SDK queries the device for the optimal height. False keeps the
  /// classic 320×50 slot.
  final bool adaptiveBanner;

  /// Padding around the rendered banner — handy when stacking on top
  /// of a card to leave a visual gap.
  final EdgeInsets padding;

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadAd(BoxConstraints constraints) async {
    if (_loaded || _loading) return;
    final adsOn = ref.read(adsEnabledProvider);
    if (!adsOn) return;
    final ads = AwatvAds.instance;
    if (!ads.isAvailable) return;
    _loading = true;

    final size = widget.adaptiveBanner
        ? await _resolveAdaptiveSize(constraints) ?? AdSize.banner
        : AdSize.banner;

    _ad = BannerAd(
      adUnitId: ads.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) return;
          setState(() {
            _loaded = true;
            _loading = false;
          });
          if (kDebugMode) debugPrint('[ads] banner loaded');
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
          _loading = false;
          if (kDebugMode) debugPrint('[ads] banner failed: $error');
        },
      ),
    );
    await _ad!.load();
  }

  Future<AdSize?> _resolveAdaptiveSize(BoxConstraints constraints) async {
    try {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth.truncate()
          : MediaQuery.of(context).size.width.truncate();
      // Adaptive banner only available for Android + iOS — defensive call.
      if (Platform.isAndroid) {
        return AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      }
      if (Platform.isIOS) {
        return AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      }
      return null;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final adsOn = ref.watch(adsEnabledProvider);
    if (!adsOn) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Kick off load on first build with concrete constraints.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeLoadAd(constraints);
        });

        if (!_loaded || _ad == null) {
          // Reserve the slot's height so the layout doesn't jump when
          // the ad lands. 50 is the standard banner height; adaptive
          // banners may grow once loaded.
          return const SizedBox(height: 50, child: SizedBox.expand());
        }

        return Padding(
          padding: widget.padding,
          child: SizedBox(
            width: _ad!.size.width.toDouble(),
            height: _ad!.size.height.toDouble(),
            child: AdWidget(ad: _ad!),
          ),
        );
      },
    );
  }
}
