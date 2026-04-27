# Store Screenshots

Required screenshots per platform/locale (en, tr):

## App Store (iOS)
- 6.7" iPhone (1290×2796) — 5 screenshots
- 6.5" iPhone (1242×2688) — 5 screenshots
- iPad Pro 12.9" (2048×2732) — 5 screenshots

## Play Store (Android)
- Phone (1080×1920 minimum) — at least 2, up to 8
- 7" tablet (1200×1920) — at least 2, up to 8
- 10" tablet (1600×2560) — at least 2, up to 8
- Android TV banner (1280×720) — required for TV listings

## App Store (tvOS)
- 1920×1080 — at least 1, up to 5

## Mac App Store
- 1280×800 (or higher) — up to 10

## Microsoft Store
- 1920×1080 — at least 1

## Recommended screen sequence

1. **Hero shot** — VOD detail screen showing rich metadata (poster, backdrop, plot, ratings, "Play" CTA)
2. **Live channels grid** — channel tiles with EPG strip
3. **Series detail** — seasons + episodes with watched markers
4. **Player** — full-screen with custom controls, progress bar, EPG overlay
5. **Premium screen** — paywall with three pricing tiles

Generate via:

```bash
cd apps/mobile
flutter screenshot --type=device --device-id=<id>
```

Or use [Fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/) once Phase 6 store-submission is fully wired.
