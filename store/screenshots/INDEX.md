# AWAtv Screenshots

Auto-generated against the live production deployment at
**https://awatv.pages.dev** by `scripts/capture-screenshots.sh`. Each
screen is captured at two form factors:

| Form factor | Logical viewport | Device pixel ratio | Output PNG |
|-------------|------------------|--------------------|------------|
| Mobile (iPhone-class) | 393 × 852 | 2× | 786 × 1704 |
| Desktop | 1280 × 800 | 2× | 2560 × 1600 |

## Files

| #  | Page                          | Mobile                                                       | Desktop                                                        | Notes |
|----|-------------------------------|--------------------------------------------------------------|----------------------------------------------------------------|-------|
| 01 | Onboarding hero               | `01-onboarding-mobile.png`                                   | `01-onboarding-desktop.png`                                    | First-run welcome screen. |
| 02 | Add Playlist — M3U / M3U8     | `02-add-playlist-m3u-mobile.png`                             | `02-add-playlist-m3u-desktop.png`                              | URL-paste tab is the default. |
| 03 | Add Playlist — Xtream Codes   | `03-add-playlist-xtream-mobile.png`                          | `03-add-playlist-xtream-desktop.png`                           | Switched to the Xtream tab post-load. |
| 04 | Sign-in                       | `04-login-mobile.png`                                        | `04-login-desktop.png`                                         | Cloud-sync sign-in (this build runs without Supabase keys, so the screen explains the local-only state honestly). |
| 05 | Premium paywall               | `05-premium-mobile.png`                                      | `05-premium-desktop.png`                                       | Production routing redirects unauthenticated first-run users back to onboarding — see "Routing honesty" below. |
| 06 | Settings                      | `06-settings-mobile.png`                                     | `06-settings-desktop.png`                                      | Same redirect-to-onboarding as #05. |
| 07 | Remote control hub            | `07-remote-hub-mobile.png`                                   | `07-remote-hub-desktop.png`                                    | Same redirect-to-onboarding as #05. |
| 08 | Remote receiver (QR pairing)  | `08-remote-receive-mobile.png`                               | `08-remote-receive-desktop.png`                                | Same redirect-to-onboarding as #05. |

## Routing honesty

Per `CLAUDE.md` the project rule is *"no mocked data, no `// TODO` stubs that
pretend to work"*, and the brief for these screenshots was explicit:

> Don't change the app code to "stage" data for screenshots; capture the
> empty / signed-out state for honesty. Don't fake a login or playlist —
> the screenshots show the genuine first-run experience.

In production, `/#/premium`, `/#/settings`, `/#/remote`, and
`/#/remote/receive` all gate behind a completed onboarding (at least one
playlist source registered in IndexedDB). A brand-new browser context
hitting those URLs is redirected to `/#/onboarding`, so screens 05–08
above show the genuine onboarding landing — that *is* what an organic
first-run user sees if they paste a deep link. Capturing the deep state
behind those routes requires a live playlist (URL with credentials),
which we deliberately do not seed.

To capture the post-onboarding deep states for the App Store / Play Store
listing, run the script on a device or browser profile where you have
already added a real playlist:

```bash
# Open https://awatv.pages.dev in a browser, finish onboarding with a
# playlist URL you control, then keep the same browser profile and run:
AWATV_URL=https://awatv.pages.dev ./scripts/capture-screenshots.sh
```

(The Playwright script uses a fresh context each run; for the post-
onboarding flow you would persist storage state via Playwright's
`storageState` API. That deeper run is intentionally out of scope here.)

## Regenerate

```bash
./scripts/capture-screenshots.sh
```

The script:

1. Installs Playwright transiently with `npm install --no-save playwright`
   (no root-level `package.json` mutation).
2. Downloads Chromium via `npx playwright install chromium`.
3. Runs `scripts/capture-screenshots.js`, which clicks the hidden
   `flt-semantics-placeholder` so Flutter Web's accessibility tree is
   reachable, waits for `flt-glass-pane` to render, and snaps each
   route at both viewports.
4. Writes 16 PNGs into this directory.

Set `AWATV_URL` to point at a different deployment (e.g. a preview
build):

```bash
AWATV_URL=https://my-preview.awatv.pages.dev ./scripts/capture-screenshots.sh
```

## Per-store sizing reference

These captures are general-purpose. Store-listing requirements:

| Store                  | Required dimensions         | Source PNG                | Action |
|------------------------|-----------------------------|---------------------------|--------|
| iOS App Store (6.7")   | 1290 × 2796                 | `*-mobile.png` (786×1704) | Upscale + safe-area pad |
| iOS App Store (6.5")   | 1242 × 2688                 | `*-mobile.png`            | Upscale + safe-area pad |
| iPad Pro 12.9"         | 2048 × 2732                 | `*-mobile.png`            | Letterbox onto white |
| Google Play (phone)    | ≥ 1080 × 1920               | `*-mobile.png`            | Already exceeds |
| Google Play (7" tab)   | 1200 × 1920                 | `*-desktop.png`           | Crop |
| Google Play (10" tab)  | 1600 × 2560                 | `*-desktop.png`           | Crop |
| Android TV banner      | 1280 × 720                  | n/a                       | Custom design required |
| tvOS                   | 1920 × 1080                 | `*-desktop.png`           | Crop |
| Mac App Store          | ≥ 1280 × 800                | `*-desktop.png`           | Already at native |
| Microsoft Store        | ≥ 1920 × 1080               | `*-desktop.png`           | Crop |
