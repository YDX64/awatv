# AWAtv — Screenshot Index

All captures use the live production URL `https://awatv.pages.dev/`
(Cloudflare Pages, Wave 4-12 build). Wave 13 captures were taken with
the playwright MCP inside Claude Code — same test harness used by the
release pipeline.

> **Wave 13 status: `FAIL` (blank gray scene).** The Flutter web bundle
> hits `LateInitializationError: Field '' has not been initialized` in
> `main.dart.js` immediately after Hive opens its 10 IndexedDB stores,
> aborting `_flutter.appRunner` before any widget is mounted. Every
> Wave-13 screenshot below is therefore a near-uniform `#B6B6B6` raster
> (the bare `<body>`'s default Material gray) and serves as documentation
> of the regression rather than marketing material. See
> [`/docs/SMOKE-TEST-RESULT.md`](../../docs/SMOKE-TEST-RESULT.md).

## Wave 13 captures (2026-04-29)

Captured: **2026-04-29 07:15-07:20 UTC** (Apr 29 09:15-09:20 local).

### Default viewport (Playwright default = 1200×814)

| # | File | URL | Caption |
|---|---|---|---|
| 1 | `01-boot.png` | `/` | Boot / root route — meant to redirect to onboarding; renders blank gray (1200×814). |
| 2 | `02-onboarding.png` | `/#/onboarding` | Onboarding wizard (Wave 11) — should show the welcome carousel; blank (1200×814). |
| 3 | `03-login.png` | `/#/login` | Sign-in screen (Wave 4 auth) — blank (1200×814). |
| 4 | `04-add-playlist.png` | `/#/playlists/add` | Add-playlist form (M3U + Xtream tabs, Wave 5) — blank (1200×814). |
| 5 | `05-premium.png` | `/#/premium` | Premium upsell page (Wave 9) — blank (1200×814). |
| 6 | `06-settings.png` | `/#/settings` | Settings hub (Wave 8) — blank (1200×814). |
| 7 | `07-theme.png` | `/#/settings/theme` | Theme picker (Wave 12) — blank (1200×814). |

### Desktop viewport (1440×900)

| # | File | URL | Caption |
|---|---|---|---|
| 8 | `01-onboarding-desktop.png` | `/#/onboarding` | Onboarding @ 1440×900 — blank gray. |
| 9 | `02-add-playlist-desktop.png` | `/#/playlists/add` | Add Playlist @ 1440×900 — blank gray. |

### Mobile viewport (390×844, iPhone 14)

| # | File | URL | Caption |
|---|---|---|---|
| 10 | `01-onboarding-mobile.png` | `/#/onboarding` | Onboarding @ 390×844 — blank gray. |
| 11 | `02-add-playlist-mobile.png` | `/#/playlists/add` | Add Playlist @ 390×844 — blank gray. |

## Wave 12 archive (2026-04-28)

The previous capture run produced renderable, marketing-quality images
of the same screens. They are kept in this directory unchanged as a
visual reference until the Wave-13 production bug is fixed and the
pipeline re-runs.

| File | Viewport | Captured |
|---|---|---|
| `02-add-playlist-m3u-desktop.png` | 1440×900 | 2026-04-28 |
| `02-add-playlist-m3u-mobile.png` | 390×844 | 2026-04-28 |
| `03-add-playlist-xtream-desktop.png` | 1440×900 | 2026-04-28 |
| `03-add-playlist-xtream-mobile.png` | 390×844 | 2026-04-28 |
| `04-login-desktop.png` | 1440×900 | 2026-04-28 |
| `04-login-mobile.png` | 390×844 | 2026-04-28 |
| `05-premium-desktop.png` | 1440×900 | 2026-04-28 |
| `05-premium-mobile.png` | 390×844 | 2026-04-28 |
| `06-settings-desktop.png` | 1440×900 | 2026-04-28 |
| `06-settings-mobile.png` | 390×844 | 2026-04-28 |
| `07-remote-hub-desktop.png` | 1440×900 | 2026-04-28 |
| `07-remote-hub-mobile.png` | 390×844 | 2026-04-28 |
| `08-remote-receive-desktop.png` | 1440×900 | 2026-04-28 |
| `08-remote-receive-mobile.png` | 390×844 | 2026-04-28 |

## Regenerate

Re-run the smoke flow that produced this index:

```bash
# from repo root
scripts/capture-screenshots.sh        # uses Playwright + Cloudflare URL
```
