import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'feature_gate_provider.g.dart';

/// Resolves whether the active tier may use a given [PremiumFeature].
///
/// Watches [premiumStatusProvider]: any tier change cascades through
/// every consumer of `canUseFeatureProvider(feature)` automatically.
/// `keepAlive: true` because the result is dirt-cheap to compute and
/// the tier rarely changes — keeping the provider alive avoids
/// re-allocating the closure on every screen rebuild.
@Riverpod(keepAlive: true)
bool canUseFeature(Ref ref, PremiumFeature feature) {
  final tier = ref.watch(premiumStatusProvider);
  if (tier.isPremium) return true;
  return _freeTierAllowed(feature);
}

/// Whitelist for free-tier permitted features. Default is "no" — every
/// premium feature is gated unless explicitly listed here. Today the
/// list is empty, but this is the right hook for future free-tier
/// goodies (e.g. PiP could become free on Android someday).
bool _freeTierAllowed(PremiumFeature feature) {
  switch (feature) {
    // Free users get a 1-day window via FreeTier.epgPastDays — the
    // *extended* (14-day) variant is premium only.
    case PremiumFeature.extendedEpgHistory:
      return false;
    // Catchup is partially free — the airing-now programme is always
    // playable (it's the same as live), but anything older requires
    // premium. The screen / sheet enforces this finer-grained gate
    // separately by checking `programme.isPast(now)`. Returning false
    // here keeps the headline gate "premium" so the sidebar entry
    // and screen header reflect the intent.
    case PremiumFeature.catchup:
      return false;
    case PremiumFeature.unlimitedPlaylists:
    case PremiumFeature.multiScreen:
    case PremiumFeature.pictureInPicture:
    case PremiumFeature.vlcBackend:
    case PremiumFeature.cloudSync:
    case PremiumFeature.parentalControls:
    case PremiumFeature.customThemes:
    case PremiumFeature.noAds:
    // Background playback is the headline premium feature — matches
    // IPTV Expert / ipTV's "play in background" upsell.
    case PremiumFeature.backgroundPlayback:
    // Always-on-top window pinning is a desktop-only premium perk —
    // matches the player-pin toggle reference IPTV apps expose.
    case PremiumFeature.alwaysOnTop:
    // Recording requires sustained bandwidth + disk on the user's
    // device — premium only.
    case PremiumFeature.recording:
    // Offline downloads are paywalled the same way IPTV Expert /
    // ipTV.app gate them.
    case PremiumFeature.downloads:
    // Auto-subtitle fetching is gated; the picker UI itself is free.
    case PremiumFeature.autoSubtitles:
      return false;
  }
}
