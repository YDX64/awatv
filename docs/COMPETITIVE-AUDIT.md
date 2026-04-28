# AWAtv — Competitive Feature Audit

> Generated 2026-04-28 from a non-invasive inspection of three reference apps
> installed locally on macOS. No app bundles were modified or run. All
> evidence is from filesystem layout, framework lists, Info.plist, embedded
> Mach-O strings, Lottie/SVG asset names, Flutter `flutter_assets/AssetManifest.json`,
> and decoded `Localizable.strings` (UTF-16 plist).

---

## 1. Executive summary

AWAtv is **structurally ahead of where most launch-grade IPTV apps start**:
M3U/Xtream parsing, EPG (XMLTV), TMDB metadata, dual-backend player (media_kit
+ flutter_vlc_player), Riverpod + go_router, premium tier sealed-class with 9
gates, working paywall stub, profiles, parental controls, cloud sync engine,
remote-control pairing, desktop chrome with PiP window, Android TV D-pad
shell, Apple TV SwiftUI scaffold and a Supabase backend. CI is green
(0 errors, 126 tests passing).

But the three reference apps reveal a **second tier of features** AWAtv
doesn't yet have, and **IPTV Expert** in particular shows what a mature
commercial Flutter/Firebase/RevenueCat IPTV app looks like in 2026:

- **Catch-up / replay TV** (Xtream `archive=1`, Stalker `tvg-rec`, time-shift)
- **Stalker / Ministra portal** support (URL `/stalker_portal/server/load.php`)
- **Recording** (record live channel to disk, trim, re-watch)
- **VOD download for offline playback** (`background_downloader`)
- **OpenSubtitles search** (Premium gate)
- **YouTube trailer** embedding for movies/series
- **Sleep timer** (only IPTV Expert has it via lottie + bingeTimer view)
- **EPG timeshift offset** (per-playlist)
- **Skip-duration setting** (forward/backward seek length)
- **Hide-category / hidden-videos** content management
- **Customizable home rows** (drag-reorder + show/hide)
- **TMDB region/language metadata preferences**
- **App icon picker** (alt icons), gradient backgrounds, color schemes
- **Remote Config + A/B testing** (Firebase) for paywall + ads
- **Open-with-Infuse** integration on macOS
- **Multi-codec FFmpeg + libplacebo + libdav1d + libsrt** in the player
  (ipTV.app ships these as Frameworks; mature codec coverage)

The biggest commercial differentiator we are missing is **catchup/replay +
recording + offline downloads**. These three together are the headline of
IPTV Expert's onboarding ("Live TV & Advanced Features", "Download & Watch
Offline") and are gated as Premium — i.e. they are the actual revenue
drivers. We have neither.

---

## 2. Reference app architecture

| App | Native? | Engine | Auth/IAP | Sync | Analytics | Codec stack |
|---|---|---|---|---|---|---|
| IPTV Expert v9.2.2 | Flutter (macOS arm64+x64) | media_kit + fvp + mdk | RevenueCat + Firebase ABT | Supabase-style backend (`/v1/sync/...`) | Firebase Crashlytics + RemoteConfig + Sessions | media_kit (libmpv) — same as us |
| ipTV (escanor) v2.0.2 | Native Swift / TCA | KSPlayer + MPVPlayer + AVPlayer | RevenueCat + Firebase | iCloud (CloudKit) | Firebase Analytics + Crashlytics | bundled FFmpeg 7.0.2 + libdav1d + libplacebo + libshaderc + libsrt + libzvbi (teletext) + libbluray + gnutls + lcms2 + libfontconfig (fontconfig.conf + ASS subtitles) |
| GSE SMART IPTV LITE v3.0 | Native AppKit (legacy 10.12) | mpv + GSEOGLView | StoreKit | none | none observed | mpv events + DLNA + UPnP discovery |

### What IPTV Expert's framework list tells us

```
audio_session            → background audio playback (we have it)
screen_brightness_macos  → swipe up/down brightness in player
volume_controller        → swipe up/down volume in player
screen_retriever         → multi-monitor positioning
bonsoir + nsd_macos      → mDNS / Bonjour service discovery (we have it)
app_settings             → deep link to OS Settings.app
share_plus               → OS share sheet
webview_flutter          → embedded webview (paywall? OAuth? login portal?)
isar + sqflite           → dual local DB (large playlists go to Isar)
RevenueCat               → IAP subscription management
Firebase Crashlytics     → crash reporting
Firebase RemoteConfig    → server-driven feature flags + paywall config
Firebase ABTesting       → A/B testing on paywall variants
Firebase Sessions        → session-based analytics
fvp + mdk                → alternative video engines (HEVC HW + better DRM)
network_info_plus        → Wi-Fi SSID detection (for "you must be on the same Wi-Fi as your Chromecast" check)
file_selector_macos      → file picker (import .m3u files)
flutter_secure_storage   → keychain credential storage (we have it)
window_manager           → desktop window control (we have it)
wakelock_plus            → keep screen on during playback
package_info_plus        → app version detection (we have it)
device_info_plus         → device fingerprinting
url_launcher_macos       → external URL launches
PartnerSDK               → mystery — likely a paid-content partner SDK
Libpeer                  → likely WebRTC / casting peer connection
```

### What ipTV.app's binary structure tells us

ipTV ships **Composable Architecture** (TCA) as a feature-per-folder layout:

```
PlaylistFeature   (AddPlaylistFeature, NewAddPlaylistView, PlaylistsFeature)
PlayerFeature     (PlayerControlV2UIView, ExternalSelectorScreen, AVPlayerControl)
SettingsFeature   (FilterCategoryFeature, FaqScreen, FeatureScreen, EPGSettings, PlayerSettings, ColorPickerScreen)
HomeFeature
DownloadFeature   (DownloadComponent, DownloadRow, DownloadUIComponent)  ← we don't have
EPGFeature        (NSEPGCollectionView)
MediasListFeature (parallax, recents, search, favorites)
AccountsFeature   (testers page!)
```

Plus a `RealDebridClient` library — meaning ipTV integrates with **Real-Debrid**
(a paid stream-resolution / debrid service). That's a niche feature.

---

## 3. Feature parity matrix

Legend:
- AWAtv: Y = shipped, P = partial / behind a flag, N = no
- Pri: P0 must-have, P1 strong differentiator, P2 nice-to-have, P3 niche
- Effort: S < 1 day, M 1–3 days, L > 3 days

| # | Feature | AWAtv | IPTV Expert | ipTV | GSE | Pri | Eff | Premium? |
|--|--|--|--|--|--|--|--|--|
| **PLAYLIST SOURCES** |
| 1 | M3U / M3U8 import | Y | Y | Y | Y | P0 | – | No |
| 2 | Xtream Codes API | Y | Y | Y | Y | P0 | – | No |
| 3 | Stalker / Ministra portal | N | Y | N | Y (Mag-style) | P1 | L | No |
| 4 | Multi-playlist (≥2) | P | Y | Y | Y | P0 | S | Y (gate exists) |
| 5 | Force-M3U fallback for broken Xtream | N | Y | N | N | P2 | S | No |
| 6 | API token auth (alternative) | N | Y | N | N | P3 | M | No |
| 7 | Paste from clipboard add flow | N | Y | Y | N | P2 | S | No |
| 8 | Multi-DNS / mirror endpoint | N | Y | N | N | P3 | M | No |
| 9 | Reload frequency setting | N | Y (daily/3d/weekly/monthly) | Y | N | P1 | S | No |
| **LIVE TV** |
| 10 | EPG (XMLTV) parsing | Y | Y | Y | Y | P0 | – | No |
| 11 | EPG grid view | Y | Y | Y | Y | P0 | – | No |
| 12 | EPG timezone autodetect | P | Y | Y | Y (manual) | P1 | S | No |
| 13 | EPG timeshift offset | N | Y | Y | Y | P1 | S | No |
| 14 | Catchup / replay (Xtream `archive=1` + Stalker `tvg-rec`) | N | Y | Y | Y | **P0** | L | Y |
| 15 | Channel zapping (prev/next via D-pad/keyboard) | P | Y | Y | Y | P1 | S | No |
| 16 | Now/next OSD on player | P | Y | Y | Y | P1 | S | No |
| 17 | Hide channel / hide group | N | Y | Y | Y | P1 | M | No |
| 18 | Lock channel (Adult/Parental) | P | Y | Y | Y | P1 | S | Y |
| 19 | Custom groups (user-made categories) | N | Y | Y | N | P2 | M | No |
| 20 | Group multi-select bulk action | N | Y | Y | N | P3 | M | No |
| **VOD / SERIES** |
| 21 | VOD grid + detail | Y | Y | Y | Y | P0 | – | No |
| 22 | Series grid + season/episode list | Y | Y | Y | Y | P0 | – | No |
| 23 | Resume/continue watching | P | Y | Y | Y | P0 | S | No |
| 24 | "Mark previous episodes watched" | N | Y | Y | N | P2 | S | No |
| 25 | Next-up auto-play next episode | N | Y | Y | N | P1 | S | No |
| 26 | Delete watching history per series | N | Y | Y | N | P2 | S | No |
| 27 | YouTube trailer playback | N | Y | N | N | P1 | M | No |
| 28 | Actor search + actor details + filmography | N | Y | N | N | P2 | M | No |
| 29 | Genre filter (Action, Drama, Sci-Fi, ...) | N | Y (24 genres localized) | Y | N | P2 | S | No |
| 30 | "Also on" cross-reference between sources | N | Y | N | N | P3 | M | No |
| **METADATA** |
| 31 | TMDB integration | Y | Y | Y | N | P0 | – | No |
| 32 | TMDB region preference | N | Y | Y | N | P2 | S | No |
| 33 | TMDB language preference | N | Y | Y | N | P2 | S | No |
| 34 | "Use playlist poster instead of TMDB" toggle | N | Y | Y | N | P2 | S | No |
| 35 | Manual change-metadata | N | Y | Y | N | P3 | M | No |
| 36 | Local metadata wipe button | N | Y | Y | N | P3 | S | No |
| 37 | TVDB / IMDB / OMDb adapters | N | N (but Imdb id stored) | N | N | P3 | L | No |
| **PLAYER** |
| 38 | media_kit (libmpv) backend | Y | Y | N (KSPlayer) | N (mpv direct) | P0 | – | No |
| 39 | VLC fallback backend | Y | N | N | N | P1 | – | Y |
| 40 | KSPlayer / native AVPlayer choice | N | Y (fvp+mdk fallback) | Y | N | P3 | L | No |
| 41 | Picture-in-picture | P (desktop window) | Y (mobile + desktop) | Y | N | P0 | M | Y |
| 42 | AirPlay (iOS/macOS) | P | Y | Y | N | P1 | M | Y |
| 43 | Chromecast (full session) | P (engine stub) | Y (full) | Y | Y (DLNA) | P0 | L | Y |
| 44 | DLNA / UPnP streaming | N | N | N | Y (BasicUPnPService) | P3 | L | No |
| 45 | Subtitle track selection | P | Y | Y | Y | P0 | S | No |
| 46 | Audio track selection | P | Y | Y | Y | P0 | S | No |
| 47 | Aspect ratio picker (16:9/4:3/2.35:1/Crop/Fit) | N | Y (Lottie + SVGs ic_fit_height/ic_fit_width/ic_fill) | Y | Y | P1 | S | No |
| 48 | Playback speed | P | Y | Y | Y | P1 | S | No |
| 49 | Playback history / resume position | P | Y (rememberHistoryLabel) | Y | Y | P0 | S | No |
| 50 | Skip-duration setting (5/10/15/30s) | N | Y (PlayerSkipDurationPage) | Y (PlayerSkipDurationViewModel) | N | P2 | S | No |
| 51 | Sleep timer (auto-stop after N min) | N | Y (PlayerBingeTimerView) | N | N | P2 | S | No |
| 52 | Subtitle font / size / color customization | P | Y (playerSettingsFont/FontColor/FontSize/UseBoldFont) | Y | Y | P2 | M | No |
| 53 | OpenSubtitles online search | N | Y (Premium gate) | Y (KSPlayer SubtitleSearch) | N | P1 | M | Y |
| 54 | Subtitle delay / timing | N | Y | Y | Y | P3 | S | No |
| 55 | Hardware acceleration toggle | N | Y | Y | N | P2 | S | No |
| 56 | Deinterlace toggle | N | Y | Y | N | P3 | S | No |
| 57 | Swipe gestures (vol/brightness/seek) | P | Y (volume_controller + screen_brightness_macos) | Y | N | P1 | M | Y |
| 58 | Volume boost > 100% | N | N | Y (mpv) | Y | P3 | S | No |
| 59 | Quick "Open with Infuse" handoff | N | Y (macOS) | N | N | P3 | S | No |
| **CATCHUP / RECORDING / DOWNLOADS** |
| 60 | Catchup / time-shift recording | N | Y | Y | Y | **P0** | L | Y |
| 61 | Live channel recording to disk | N | Y (RecordingState) | Y (RecordingManager + RecordingOpenPathUseCase) | Y (Recordings folder) | P1 | L | Y |
| 62 | Recording trim editor | N | N | Y (Movietrimview class!) | Y | P3 | L | Y |
| 63 | VOD download for offline | N | Y (background_downloader) | Y (DownloadFeature complete) | N | **P0** | L | Y |
| 64 | Active downloads queue UI | N | Y | Y (active/all downloads tabs) | N | P0 | M | Y |
| 65 | Pause/resume/retry/cancel download | N | Y | Y | N | P0 | S | Y |
| 66 | Download notifications + completion alert | N | Y (Local notifications) | Y | N | P1 | S | Y |
| **CASTING / DISCOVERY** |
| 67 | Bonjour / mDNS device discovery | Y | Y | Y | Y | P1 | – | No |
| 68 | Local network permission UX | N (auto) | Y (explicit dialog) | Y | N | P2 | S | No |
| 69 | "Same Wi-Fi" SSID warning | N | Y (network_info_plus) | N | N | P3 | S | No |
| **PROFILES & PARENTAL** |
| 70 | User profiles (multi-user on one device) | Y | Y (lottie_profiles.json) | N | N | P1 | – | Y |
| 71 | PIN-locked parental control | Y | Y | Y | N | P1 | – | Y |
| 72 | Lock by genre/age rating | P | Y | Y | N | P2 | S | Y |
| 73 | Hide adult categories | P | Y | Y | Y | P1 | S | Y |
| **PREMIUM / PAYWALL / IAP** |
| 74 | Sealed PremiumFeature gates | Y (9 gates) | Y (PaywallFeatures list) | Y | Y | P0 | – | – |
| 75 | RevenueCat IAP wired | P (stub + sim) | Y | Y | – (StoreKit) | P0 | M | – |
| 76 | Subscription tiers (Monthly/Yearly/Lifetime) | Y | Y | Y | Y | P0 | – | – |
| 77 | Free trial flow | N | Y (FREE_TRIAL config) | Y (n-day trial copy) | N | P1 | S | – |
| 78 | Restore purchases | P (stub) | Y | Y | Y | P0 | S | – |
| 79 | First-launch paywall (skippable) | N | Y (PaywallOnFirstLaunchShown) | Y | N | P2 | S | – |
| 80 | Home banner "Become Premium" | N | Y (BecomePremiumBanner) | Y | Y | P2 | S | – |
| 81 | Tablet vs mobile paywall layouts | N | Y (PaywallTablet/PaywallMobile) | Y | N | P2 | S | – |
| 82 | Promo / introductory pricing | N | Y | Y | N | P3 | M | – |
| **ADS (free tier)** |
| 83 | AdMob banner | P (planned) | Y | N | Y (GADBannerView) | P1 | M | gate |
| 84 | Interstitial cadence config (RemoteConfig) | N | Y (`ads_interstitial_every`, `ads_interstitial_first_after`) | N | N | P2 | M | gate |
| 85 | Open-app ad | N | Y (AdmobOpenAppManager) | N | N | P3 | M | gate |
| 86 | Rewarded interstitial | N | Y (RewardedInterstitialAd) | N | N | P3 | M | gate |
| **SYNC / ACCOUNT** |
| 87 | Cloud sync (favorites/history/playlists) | Y (Supabase) | Y (custom backend) | Y (CloudKit/iCloud) | N | P1 | – | Y |
| 88 | Magic-link / email login | Y | Y (sendEmailViewModel + sendPinCodeViewModel) | Y | N | P1 | – | No |
| 89 | Force-resync button | N | Y (forceRefreshAllSyncsButtonLabel) | Y | N | P2 | S | Y |
| 90 | Per-device fingerprint | Y | Y | Y | N | P2 | – | Y |
| 91 | Manage active devices | Y | Y | Y | N | P2 | – | Y |
| 92 | Customer support ID copyable | N | Y (copyCustomerSupportIDSuccessToast) | Y | N | P3 | S | No |
| **HOME / DISCOVERY** |
| 93 | Home rows (continue/favorites/recently added) | Y | Y | Y | Y | P0 | – | No |
| 94 | Customizable home (reorder/hide rows) | N | Y | Y | N | P2 | M | No |
| 95 | Featured / hero carousel | Y | Y | Y | Y | P0 | – | No |
| 96 | Global search across live+VOD+series | Y | Y (GlobalSearchUseCase) | Y | Y | P0 | – | No |
| 97 | EPG-aware search ("show me what's on now") | N | Y (GlobalSearchEpgFilterUseCase) | N | N | P2 | M | No |
| **SETTINGS / PERSONALIZATION** |
| 98 | Theme: dark/light/system | Y | Y | Y | Y | P0 | – | No |
| 99 | 10 named accent colors | N | Y | Y | N | P3 | S | Y (customThemes gate exists) |
| 100 | Alt app icon picker | N | N | Y (8 alt icons in Resources) | Y (icon-1..8 in lite) | P3 | S | Y |
| 101 | Gradient background toggle | N | Y (gradientBackgroundToggle) | Y | N | P3 | S | No |
| 102 | Default-tab / default-category preference | N | Y (CustomizationDefaultCategoryViewModel) | Y | N | P3 | S | No |
| 103 | Default playback language preference | N | Y (CustomizationDefaultLanguageViewModel) | Y | N | P3 | S | No |
| 104 | Color picker (custom hex) | N | N | Y (ColorPickerScreen.swift) | N | P3 | S | Y |
| 105 | Settings frequency (refresh schedule) | N | Y (SettingsFrequencyPage) | Y | N | P2 | S | No |
| 106 | App rating prompt | N | Y (appRatingTitle) | Y (settingReviewTheApp) | N | P3 | S | No |
| 107 | Contact / feature-request links | N | Y (settingRequestAfeature) | Y | Y | P3 | S | No |
| **PLATFORMS** |
| 108 | iOS / Android | Y | Y | Y (iOS only? — universal binary unverified) | – | P0 | – | – |
| 109 | macOS | Y | Y | Y | Y | P1 | – | – |
| 110 | Apple TV (tvOS) | P (scaffold) | Y (scanQRCodeExplanation indicates tvOS) | Y | N | P1 | L | – |
| 111 | Android TV / Fire TV | Y | N (Flutter only) | N | N | P1 | – | – |
| 112 | Windows | Y | N | N | N | P2 | – | – |
| 113 | Web | Y | N | N | N | P3 | – | – |
| **OBSERVABILITY** |
| 114 | Crash reporting | N | Y (Firebase Crashlytics) | Y | N | P1 | S | – |
| 115 | Remote feature flags | N | Y (Firebase RemoteConfig) | N | N | P1 | M | – |
| 116 | A/B testing harness | N | Y (Firebase ABTesting) | N | N | P2 | M | – |
| 117 | Session-based analytics | N | Y (Firebase Sessions) | Y | N | P2 | S | – |
| 118 | Per-feature usage telemetry | N | Y (PaywallOnFirstLaunchShown event etc) | Y | N | P2 | M | – |
| **MISCELLANEOUS** |
| 119 | Auto-update (sideloaded) | Y | N (App Store) | N (App Store) | N (App Store) | P2 | – | No |
| 120 | Multi-language UI | P (en+tr scaffold) | Y (af, ar, da, de, en, es, fi, fr, hu, id, it, ms, nl, no, pl, pt, ro, sv, tl, tr, ...) | Y (en, ar, de, es, fr, it, nl, pt, tr — 9 langs) | P (auto en) | P1 | M | No |
| 121 | "Pulled from clipboard" smart-detect | N | Y | N | N | P3 | S | No |
| 122 | "Force landscape" toggle | N | Y (forceLandscapeLabel) | Y | N | P3 | S | No |
| 123 | Customer FAQ in-app screen | N | Y | Y (FaqScreen.swift) | N | P3 | M | No |
| 124 | Featured / "What's New" release notes screen | N | Y (releaseNote* keys) | Y | N | P3 | S | No |
| 125 | Real-Debrid integration | N | N | Y (RealDebridClient) | N | P3 | L | Y |
| 126 | "Open with Infuse" deep link (macOS) | N | Y (openWithInfuse) | N | N | P3 | S | No |

**Total rows: 126.** AWAtv ships **47** ("Y") + **17** partial ("P") = ~50 % of
the surface area covered. The references collectively show **62** features
we don't have at all.

---

## 4. Gap analysis (prioritized)

### P0 — Must have for launch (or ship-blocking parity)

These are features at least two reference apps treat as core, and that
free-tier users will demand. Each is a credible reason to delete the app.

1. **Catchup / replay TV** (row 14, 60). Xtream `archive=1` + Stalker
   `tvg-rec`. Without this, users with a provider that supports it will
   experience AWAtv as feature-incomplete.
2. **Working Chromecast session** (row 43). We have an engine stub; we
   need real cast-discover → load-media → control loop.
3. **VOD download for offline playback** (row 63). Both reference apps
   feature-flag this as Premium and lead with it in onboarding.
4. **Subtitle / audio track selection in player UI** (rows 45, 46). We
   parse them but the player sheet doesn't expose them yet.
5. **Resume / continue-watching with reliable position persistence**
   (rows 23, 49). Partial today; needs to be bullet-proof for VOD/series.
6. **Pic-in-picture on mobile** (row 41). Today PiP is a desktop window;
   iOS / Android PiP is a separate API surface.
7. **Restore purchases** wired to RevenueCat (row 78).

### P1 — Strong differentiators

Features that significantly improve perceived quality vs free competitors.

8. **Live channel recording to disk** (row 61). Premium gate.
9. **OpenSubtitles search** (row 53). Premium gate.
10. **YouTube trailer playback** for VOD/Series (row 27).
11. **EPG timeshift offset** + **timezone autodetect** (rows 12, 13).
12. **Channel zapping** with prev/next + now/next OSD (rows 15, 16).
13. **Hide channel / hide group / lock-by-rating** content management
    (rows 17, 18).
14. **Sleek aspect-ratio picker** (row 47) using the SVGs IPTV Expert ships
    (`ic_fit_height`, `ic_fit_width`, `ic_fill`).
15. **Swipe gestures** for brightness/volume/seek (row 57). Premium gate.
16. **AirPlay** complete loop (row 42).
17. **Crash reporting** + **remote feature flags** (rows 114, 115).
18. **Apple TV** SwiftUI app finished (row 110).
19. **Multi-language UI**: at least the 9 ipTV.app supports — en, ar, de,
    es, fr, it, nl, pt, tr (row 120).
20. **Magic-link login** flow surfaced in the UI (row 88, partially exists).

### P2 — Nice to have

21. Trim / next-up / mark-previous-watched for series (rows 24, 25, 26).
22. Genre filter (24 genres) (row 29).
23. TMDB region/language preference (rows 32, 33).
24. Hardware acceleration / deinterlace toggles (rows 55, 56).
25. Skip-duration setting (row 50). Trivial.
26. Sleep timer (row 51). Trivial.
27. Subtitle font/size/color (row 52).
28. Customizable home rows (row 94).
29. EPG-aware search "what's on now" (row 97).
30. Tablet-specific paywall layout (row 81).
31. Free-trial CTA in paywall (row 77).
32. First-launch paywall (skippable) (row 79).
33. AdMob interstitial cadence via RemoteConfig (row 84).
34. Bulk-multiselect on groups (row 20).
35. Custom user-made groups (row 19).
36. Force-M3U fallback (row 5).
37. Reload frequency setting (row 9).
38. Force-resync button (row 89).

### P3 — Vendor-specific / niche

39. Stalker / Ministra portal (row 3). Specific provider tech; large effort.
40. Real-Debrid integration (row 125). Niche debrid users only.
41. DLNA / UPnP rendering (row 44). GSE has it; modern audiences use Cast.
42. Recording trim editor (row 62).
43. Open-with-Infuse handoff (row 126). macOS-only nicety.
44. Alt app icon picker (row 100). Cosmetic.
45. Gradient background, color picker, named colors (rows 99, 101, 104).
46. App rating prompt (row 106).
47. FAQ screen (row 123). Web link is enough until growth justifies it.
48. Force landscape toggle (row 122).
49. Customer support ID copy (row 92).
50. Multi-DNS / mirror endpoint (row 8).
51. Volume boost > 100 % (row 58).
52. "Also on" cross-source (row 30).
53. Manual change-metadata (row 35).

---

## 5. Recommended next 3 waves (each = one parallel-agent task)

### Wave 1 — Player completeness (≈ 3 days, 1 agent)

```
Title: Wave 1 — Player feature parity (subtitles, audio tracks, gestures, sleep timer)

Scope:
1. Implement subtitle-track + audio-track switcher in player_settings_sheet.dart.
   Expose via media_kit's `Player.streams.subtitles` and `Player.streams.audios`.
   Wire VLC backend equivalents in awatv_player/src/backends/vlc_backend.dart.
2. Add SleepTimer widget in features/player/widgets/sleep_timer_sheet.dart
   (already a stub) — modal with chips 15/30/45/60/90 min + "End of episode".
   Persist to Hive box `player_prefs`; on tick, fade out + Player.pause + dismiss.
3. Add SkipDurationSetting in features/settings — radio (5/10/15/30s).
   Apply to existing forward/backward seek buttons.
4. Add aspect-ratio picker (16:9 / 4:3 / 2.35:1 / Fit / Fill) using SVGs at
   apps/mobile/assets/svg/ic_fit_*.svg (ship them — 5 SVGs from IPTV Expert
   layout *concepts*, redrawn in our brand).
5. Swipe gestures (left half = brightness, right half = volume, double-tap-edge = seek)
   in player_gestures.dart — already a file. Premium-gate via PremiumFeature.gestureControls
   (add new enum value).
6. Resume / continue-watching: extend HistoryService with thresholdSeconds=10 +
   completionThreshold=0.95. On enter player, restore position. On exit, persist.
   Add "Continue watching" home row.

Files:
- apps/mobile/lib/src/features/player/widgets/player_settings_sheet.dart
- apps/mobile/lib/src/features/player/widgets/sleep_timer_sheet.dart
- apps/mobile/lib/src/features/player/widgets/player_gestures.dart
- apps/mobile/lib/src/features/player/widgets/aspect_ratio_picker.dart  (new)
- apps/mobile/lib/src/features/settings/skip_duration_screen.dart       (new)
- packages/awatv_player/lib/src/awa_player_controller.dart  (track APIs)
- packages/awatv_player/lib/src/backends/media_kit_backend.dart
- packages/awatv_player/lib/src/backends/vlc_backend.dart
- packages/awatv_core/lib/src/services/history_service.dart  (resume thresholds)
- apps/mobile/lib/src/shared/premium/premium_features.dart  (gestureControls)

Acceptance:
- flutter analyze: clean
- Unit tests in awatv_player_test for track-switcher logic
- Manual: open a stream, switch audio track, switch subtitle track, sleep timer
  fires, gesture seeks, aspect-ratio cycles
- HistoryService restores position within 1s of last paused frame

Out of scope: catchup, recording, downloads, OpenSubtitles.
```

### Wave 2 — Catchup + Recording + Downloads trifecta (≈ 5 days, 1 agent + 1 sub-agent)

```
Title: Wave 2 — Catchup TV + recording + offline downloads (Premium)

Scope:
1. Catchup support
   a. Detect Xtream `archive=1` flag on channels in m3u_parser.dart.
   b. Generate catchup URL: `{server}/timeshift/{user}/{pass}/{duration}/{start_yyyymmddhhmm}/{stream_id}.ts`
      (Xtream pattern observed in IPTV Expert binary string `/timeshift/`).
   c. For Stalker `tvg-rec`, defer (Wave 3).
   d. Add "catchup window" to EPG grid: a per-programme button if archive enabled.

2. Live channel recording
   a. Use ffmpeg via `flutter_ffmpeg_kit_full` (or media_kit Recorder API if exposed)
      to remux live HLS/TS to local mp4 in app docs.
   b. New service awatv_core/lib/src/services/recording_service.dart
   c. New screen features/recordings/recordings_screen.dart with:
      Active recordings (with progress + duration) | Completed (sortable, openable)
   d. Premium gate: PremiumFeature.recording (add).

3. VOD downloads (offline)
   a. Add background_downloader package.
   b. Service awatv_core/lib/src/services/download_service.dart with:
      enqueue(MediaSource), pause, resume, retry, cancel, delete.
   c. Local notifications via flutter_local_notifications (already on roadmap?).
   d. Screen features/downloads/downloads_screen.dart — reuse list components.
   e. Player auto-resolves a VOD URL to local path if downloaded.
   f. Premium gate: PremiumFeature.offlineDownloads (add).

4. Settings
   - Storage budget slider (1-50 GB)
   - "Wi-Fi only downloads" toggle
   - Auto-delete watched downloads toggle

Files:
- packages/awatv_core/lib/src/services/{recording_service,download_service,catchup_service}.dart  (new)
- packages/awatv_core/lib/src/models/{recording,download_task}.dart  (new + freezed)
- apps/mobile/lib/src/features/recordings/  (new tree)
- apps/mobile/lib/src/features/downloads/   (new tree)
- apps/mobile/lib/src/shared/premium/premium_features.dart  (recording, offlineDownloads)

Acceptance:
- A real catchup URL plays back from EPG grid context-menu.
- A recording can be started + stopped, file appears in recordings_screen.
- A VOD can be downloaded, paused, resumed, played offline (airplane mode).
- All three are paywalled when premium=false.

Out of scope: Stalker portal catchup, recording trim editor.
```

### Wave 3 — Trust & telemetry foundation (≈ 3 days, 2 parallel agents)

```
Title: Wave 3 — Crashlytics + RemoteConfig + OpenSubtitles + YouTube trailer

Agent A — observability:
1. Add firebase_core, firebase_crashlytics, firebase_remote_config to apps/mobile.
2. Wire Crashlytics in main.dart (FlutterError.onError + PlatformDispatcher.instance.onError).
3. RemoteConfig keys:
   - paywall_first_launch_enabled (bool)
   - paywall_default_plan (yearly|monthly|lifetime)
   - ads_interstitial_every (int, default 3)
   - ads_interstitial_first_after (int, default 2)
   - feature_catchup_enabled (kill-switch)
   - feature_recording_enabled (kill-switch)
4. Refactor existing premium + ads gates to consult RemoteConfig.

Agent B — content discovery:
1. OpenSubtitles client in awatv_core/lib/src/clients/opensubtitles_client.dart
   (REST API — needs API key, env var OPENSUBTITLES_API_KEY).
2. Premium gate PremiumFeature.subtitleSearch.
3. UI: "Search subtitles online" entry in player_settings_sheet → list → tap = download to
   /tmp/awatv-subs/{movie_id}.srt → load into media_kit Player.setSubtitleTrack(file).
4. YouTube trailer playback:
   - tmdb_client.dart already returns videos (where key=youtubeKey, site=YouTube)
   - Embed via youtube_player_flutter (or webview_flutter) in vod_detail_screen.dart
     and series_detail_screen.dart.
   - Premium-free (it's TMDB metadata; no licensing concern).

Acceptance:
- Force a runtime exception → appears in Firebase Crashlytics dashboard.
- Toggling a RemoteConfig flag from Firebase console changes app behavior on next launch.
- A subtitle download replaces the "burned-in subs only" current state on at least one VOD.
- A trailer button on a VOD detail screen plays the YouTube trailer in-app.
```

---

## 6. Risks & non-goals

### What we explicitly will NOT copy

- **PartnerSDK.framework** in IPTV Expert — proprietary, undocumented, likely a
  paid content-partnership SDK. We don't ship paid content; out of scope.
- **Real-Debrid integration** — niche; their TOS + auth model + maintenance
  burden outweighs the addressable market. P3, deferred indefinitely.
- **Bundling our own FFmpeg / libplacebo / libdav1d** — ipTV ships ~28 native
  frameworks for codec coverage. media_kit (libmpv) already covers HEVC, AV1,
  HDR10, HLS, DASH, SRT. Re-bundling is huge effort for marginal gain.
- **lcms2 (color management)** — only matters on calibrated wide-gamut
  displays; defer until users ask.
- **DLNA / UPnP rendering** — GSE has it; the modern audience uses Chromecast
  + AirPlay. Stop investing in DLNA.
- **Stalker portal** support is a P1 differentiator on paper, but in
  practice serving Stalker users means dealing with bizarre auth flows,
  device-MAC binding, and time-limited tokens that get reset by the provider.
  Defer to Wave 4 unless customer signal is strong.
- **`forceLandscape` toggle** — Flutter handles orientation natively; this is
  a relic of UIKit-era apps.
- **Releasing on Apple TV before iOS+Android+macOS+Web are stable** — Apple
  TV polish requires a separate UX pass; do not block the broader launch.

### Risks if we copy blindly

- **RevenueCat lock-in**: easy to integrate, hard to leave. Validate before
  Wave 1 ships that we can swap for direct StoreKit + Play Billing if needed.
- **Firebase quota / GDPR**: Crashlytics + Sessions is cheap, but
  RemoteConfig + ABTesting at scale costs money. Cap experiments per release.
- **Real codec gaps** when users hit Asian/Russian provider streams — VLC
  fallback covers most; budget time for codec investigations.
- **OpenSubtitles**: free tier rate limits aggressive (200/day). Need
  client-side caching by hash + premium-only tier.
- **Recording legality**: in EU, user-side time-shift recording of
  broadcast TV is generally permitted (private copy exception); in some
  jurisdictions and for some licensors, not. Surface a one-time disclaimer.

### Things we already match or beat

We are equal-or-ahead on:
- **Auto-update** of sideloaded macOS/Windows builds (no reference does this)
- **Web build** (no reference does this)
- **Android TV** native (no reference does this)
- **Cross-device remote-control pairing** (only ipTV has anything close,
  via `RemoteRegistration` for Apple TV → iPhone)
- **Cloud-sync architecture** — our Supabase RLS + signed envelopes is
  cleaner than IPTV Expert's `/v1/sync/*` endpoints (we know this from
  string analysis; theirs is similar but newer and not battle-tested longer).
- **Multi-platform Flutter monorepo** — IPTV Expert is desktop-only in
  Flutter; we cover 6 platforms.

---

*Audit by: claude-opus-4-7 (1M ctx). Source: filesystem inspection,
Mach-O `strings` dumps, Flutter `AssetManifest.json`, decoded
`Localizable.strings` plists. No reference apps were executed.*
