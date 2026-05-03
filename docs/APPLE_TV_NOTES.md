# Apple TV (tvOS) — current status + path forward

## TL;DR

**Apple TV is not currently a build target.** The `apps/mobile/ios/Runner.xcodeproj` is iOS-only. Adding tvOS requires either:

1. A separate `Runner-tvOS` Xcode target inside the same xcodeproj (~3-4 hours of Xcode work)
2. A separate Flutter `ios_tv/` directory (preferred — cleaner separation)
3. Apple's "Universal Purchase" model — one App Store entry, two SKUs (iOS + tvOS), both linked

## What works today

- The `apps/mobile/lib/src/tv/` directory has a complete TV UI shell:
  - `tv_router.dart` — left-rail D-pad navigation
  - 7 TV screens (home, vod, series, live, search, player, settings)
  - `d_pad.dart` — D-pad focus management widget
- The form-factor probe in `main.dart` would auto-route to TV shell when `isTvFormProvider` flips true
- **Android TV is fully supported** — same APK, leanback feature flag, tv_banner.png. The Play Store recognises it as a TV-compatible app.

## Why Apple TV is harder

Apple TV (tvOS) needs its own Xcode target because:

1. **Different SDK**: `flutter build ios` produces an iOS-SDK binary; tvOS needs `tvOS.platform` linked frameworks
2. **No `MainStoryboard` or focus engine**: tvOS app delegate uses focus-driven UI primitives (UIFocusEnvironment); Flutter's tvOS support is experimental
3. **Different review track**: Apple TV apps go through a separate App Store Connect review, even when "Universal Purchase" is on
4. **No phone-style controls**: tvOS rejects builds that depend on touch / orientation primitives — every interaction must D-pad through

## Path forward (when prioritised)

### Option A — Universal app via additional target (hard but cleanest)

1. Open `apps/mobile/ios/Runner.xcodeproj` in Xcode
2. File → New → Target → tvOS → App
3. Name it `Runner-tvOS`
4. Configure signing: same Apple Developer Team ID, new tvOS provisioning profile for `com.awatv.awatvMobile.tvos` bundle id (or reuse base id under a tvOS distribution certificate — Universal Purchase pattern)
5. Wire Flutter to compile a tvOS engine: this is the experimental part. Flutter does not officially support tvOS as a release platform yet ([flutter/flutter#30478](https://github.com/flutter/flutter/issues/30478)). Workarounds:
   - Use [flutter-tvos](https://github.com/flutter-tvos/flutter) — community fork
   - Use a non-Flutter native Swift app that displays AWAtv via WKWebView, pointing at the existing web build
6. Tweak the form-factor probe in `main.dart` to detect tvOS at runtime
7. Add a `release-tvos.yml` workflow modelled on `release-ios.yml` with `--platform=tvos` (requires the flutter-tvos fork)

Estimated effort: 1-2 weeks for a clean implementation.

### Option B — WKWebView wrapper around web build (fastest)

Apple TV can run native Swift apps that host a WKWebView. Wrap the existing https://awatv.pages.dev build in such a wrapper:

1. New Xcode tvOS app project (not in this monorepo — separate repo)
2. ~30 lines of Swift loading https://awatv.pages.dev
3. Use `tvOSCustomActions` to map Siri Remote button events to web JS calls
4. App Store review accepts WebView-based apps that "transform a website into a native experience"

Caveat: not "native" — perceived performance and animations differ. Acceptable for an MVP TV launch.

Estimated effort: 1-3 days.

### Option C — Skip Apple TV, focus on Android TV (recommended for now)

Android TV alone covers ~30% of the global smart-TV market. Apple TV is ~15%. Until AWAtv's user base demands Apple TV specifically, the Android TV path (already working) gives 80% of the value at 0% additional cost.

When the Apple TV demand materialises, Option B (WebView wrapper) is the fast unlock; Option A is the long-term right answer.

## What NOT to do

- Do not retrofit the existing `Runner` iOS target to also build for tvOS — Xcode allows it but the resulting binary fails App Store review (tvOS apps must declare `LSApplicationCategoryType` differently, support focus engine, ship Top Shelf assets, etc.)
- Do not bundle the iOS `.app` and call it Apple TV-compatible. iOS apps don't run on tvOS.
- Do not commit experimental flutter-tvos fork to this repo's monorepo without first verifying it builds + ships releases. It's a community fork with intermittent maintenance.

## Where the existing TV UI runs

| Platform | Status |
|----------|--------|
| Android TV | ✅ shipping (same APK as phone) |
| Google TV | ✅ shipping (Google TV runs Android TV apps) |
| Fire TV | ✅ shipping (Amazon's leanback fork) |
| Roku | ❌ would need a separate Brightscript / SceneGraph app |
| Samsung Tizen / LG webOS | ❌ would need separate native apps |
| Apple TV / tvOS | ❌ not yet — see options above |

For now, "TV" practically means **Android TV / Google TV / Fire TV** (all served by the same Android APK).
