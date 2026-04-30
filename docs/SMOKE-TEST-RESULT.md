# Wave 13 Smoke Test — Live Production

**Status: `FAIL`** — blocking JS error prevents the Flutter scene from
mounting. Every route renders a blank gray viewport. The deployment is
serving real assets (HTML + `flutter_bootstrap.js` + `main.dart.js`
are all delivered, Hive opens its 10 IndexedDB stores) but the Dart
runtime aborts before `runApp` is invoked.

| Field | Value |
|---|---|
| Target | `https://awatv.pages.dev/` (Cloudflare Pages) |
| Run start | 2026-04-29 07:15:14 UTC |
| Run end   | 2026-04-29 07:20:43 UTC |
| Browser   | Playwright Chromium (default device-pixel-ratio = 2) |
| Routes hit | `/`, `/#/onboarding`, `/#/login`, `/#/playlists/add`, `/#/premium`, `/#/settings`, `/#/settings/theme` |
| Viewports | 1200×814 (default), 1440×900, 390×844 |
| Screenshots | 11 fresh PNGs in `store/screenshots/` (all blank gray) |
| Console errors (`error` level) | 0 |
| Console warnings (`warning` level) | 0 |
| Console `[LOG]` lines reporting a thrown error | **38 lines = 1 unhandled exception + ~37 stack frames** |
| Verdict | **FAIL — blocks rendering on every route.** |

## Why the playwright `error` channel is empty but the page is broken

Flutter's web engine logs uncaught Dart exceptions through
`console.log` (not `console.error`), so the playwright
`browser_console_messages(level='error')` filter returned `0`. The same
exception is plainly visible at `level='debug'` and is the cause of
the blank scene.

```text
[LOG] LateInitializationError: Field '' has not been initialized.
[LOG] #1   al8.c0n           main.dart.js:46795:23
[LOG] #2   kK.a6Z            main.dart.js:173907:19
[LOG] #3   kK.Ey             main.dart.js:173908:21
[LOG] #4   rY.gcW            main.dart.js:173328:10
[LOG] #5   zS.kd             main.dart.js:173609:10
[LOG] #6   a9z.V             main.dart.js:161687:48
[LOG] #7   a8i.bS            main.dart.js:72014:3
[LOG] #8   aqF.q             main.dart.js:161657:10
[LOG] #9   al8.c0n           main.dart.js:46795:23
[LOG] #10  kK.a6Z            main.dart.js:173907:19
[LOG] #11  kK.Ey             main.dart.js:173908:21
[LOG] #12  rY.gcW            main.dart.js:173328:10
[LOG] #13  rY.V              main.dart.js:173404:10
[LOG] #14  al8.czr           main.dart.js:15252:18
[LOG] #15  rY.tO             main.dart.js:173884:36
[LOG] #16  rY.alL            main.dart.js:173363:3
[LOG] #17  Object.a          main.dart.js:4934:25
[LOG] #18  al8.czq           main.dart.js:15242:10
[LOG] #19  rY.tO             main.dart.js:173884:36
[LOG] #20  rY.alL            main.dart.js:173363:3
[LOG] #21  rY.beS            main.dart.js:173331:3
[LOG] #22  wN.aHm            main.dart.js:173235:3
[LOG] #23  JU.zX             main.dart.js:173287:20
[LOG] #24  rY.V              main.dart.js:173401:5
[LOG] #25  al8.czr           main.dart.js:15252:18
[LOG] #26  rY.tO             main.dart.js:173884:36
... (frames 27-37 truncated by playwright debug stream)
```

### Preceding signal (these all succeeded)

```text
[DEBUG] Injecting <script> tag. Using callback.   flutter_bootstrap.js
[LOG]   Got object store box in database sources.
[LOG]   Got object store box in database epg.
[LOG]   Got object store box in database metadata.
[LOG]   Got object store box in database favorites.
[LOG]   Got object store box in database history.
[LOG]   Got object store box in database prefs.
[LOG]   Got object store box in database recordings.
[LOG]   Got object store box in database downloads.
[LOG]   Got object store box in database reminders.
[LOG]   Got object store box in database watchlist.
```

So Hive's 10 IndexedDB boxes open successfully. The crash happens
**after** Hive init and **before** the first `runApp` paint:
`window._flutter.appRunner` is still undefined when the page is idle.

### Likely cause

`LateInitializationError: Field '' has not been initialized.` is the
runtime tell-tale of a `late final` field with no name (anonymous in
release-mode minified output) being read before assignment. The fact
that the exception is thrown twice in the same trace (frames 1 and 9)
indicates a service-locator / GetIt singleton that is read inside its
own `init()` chain — most plausibly a Riverpod / GetIt registration
that depends on a Wave 12-13 newly-added service (theme service,
voice-search service, smart-channel switcher, watchlist EPG enricher,
etc.).

## DOM probe

```js
// at https://awatv.pages.dev/#/playlists/add (mobile viewport)
{
  flutterLoader: true,            // _flutter loader did inject
  appLoaded:    false,            // _flutter.appRunner never set → runApp never reached
  documentReady:'complete',
  sceneCanvas:  0,                // Flutter scene canvas absent
  glassPaneShadow: true,          // glass-pane shadow root mounted (skeleton only)
  semanticsHostExists: true       // a11y host mounted
}
```

## Per-route observations

| URL | Viewport | Screenshot | Visible content |
|---|---|---|---|
| `/`                       | 1200×814 | `01-boot.png`               | blank gray |
| `/#/onboarding`           | 1200×814 | `02-onboarding.png`         | blank gray |
| `/#/login`                | 1200×814 | `03-login.png`              | blank gray |
| `/#/playlists/add`        | 1200×814 | `04-add-playlist.png`       | blank gray |
| `/#/premium`              | 1200×814 | `05-premium.png`            | blank gray |
| `/#/settings`             | 1200×814 | `06-settings.png`           | blank gray |
| `/#/settings/theme`       | 1200×814 | `07-theme.png`              | blank gray |
| `/#/onboarding`           | 1440×900 | `01-onboarding-desktop.png` | blank gray |
| `/#/playlists/add`        | 1440×900 | `02-add-playlist-desktop.png` | blank gray |
| `/#/onboarding`           | 390×844  | `01-onboarding-mobile.png`  | blank gray |
| `/#/playlists/add`        | 390×844  | `02-add-playlist-mobile.png` | blank gray |

## Recommended next steps

1. Re-build the web bundle locally with
   `flutter run -d chrome --web-renderer canvaskit` and reproduce the
   `LateInitializationError`; the un-minified stack will name the
   `late final` field.
2. Audit Wave 12-13 service additions (`themeService`, `voiceSearch`,
   `smartChannelSwitcher`, `watchStats`, `multiStreamView`,
   `persistentPlayerBar`) for `late` fields read inside another
   service's constructor body.
3. Re-deploy and re-run this smoke pipeline. The 14 Wave-12 archive
   screenshots in `store/screenshots/` confirm the previous deploy
   rendered correctly, so this is a new regression.
