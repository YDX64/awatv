# AWAtv — Project Memory

> **Single source of truth** for picking up the project after a context break, subscription pause, or new contributor onboarding. Read this first; everything else cross-references back here.

Last updated: 2026-05-04. Current ship version: **v0.5.11** ([release page](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.11)).

---

## What is AWAtv?

A cross-platform freemium IPTV / streaming app. One Flutter codebase ships to:

| Platform | Status | Distribution |
|----------|--------|--------------|
| macOS desktop | ✅ shipping (auto-update wired) | GitHub Releases |
| Windows desktop | ✅ shipping | GitHub Releases (.exe + .zip) |
| Linux desktop | ✅ shipping | GitHub Releases (.AppImage) |
| Web | ✅ shipping | https://awatv.pages.dev (manual deploy until CF token set) |
| iOS | ⚠️ pipeline ready, awaiting Apple Developer setup | TestFlight (`docs/IOS_TESTFLIGHT_SETUP.md`) |
| Android | ⚠️ workflow exists (`release-android.yml`), not currently shipping | Play Store (TBD) |
| Apple TV | 🔮 future (uses iOS bundle) | App Store |
| Android TV | 🔮 future | Google Play (TV section) |

GitHub repo: <https://github.com/YDX64/awatv>
Production web: <https://awatv.pages.dev>
Supabase project: AWATV-USER (ref `ukulkbthsgkmihjcpzek`, region eu-central-1)

---

## Repository layout

```
/Users/max/AWAtv/
├── apps/
│   └── mobile/                              ← single Flutter app, multi-platform
│       ├── ios/                             ← iOS Xcode project
│       ├── macos/                           ← macOS Xcode project
│       ├── windows/                         ← Windows VS project
│       ├── linux/                           ← Linux CMake project
│       ├── web/                             ← Flutter web build target
│       ├── lib/
│       │   └── src/
│       │       ├── app/                     ← root widget, env, theme provider
│       │       ├── features/                ← 30+ feature directories (see below)
│       │       ├── routing/                 ← go_router config (mobile + TV)
│       │       ├── shared/                  ← cross-feature services
│       │       ├── tv/                      ← Android TV / Apple TV shell
│       │       └── desktop/                 ← desktop shell + chrome
│       ├── pubspec.yaml                     ← version: x.y.z+build (source of truth)
│       └── .env.example                     ← TMDB/Supabase/proxy env templates
├── packages/                                ← workspace packages
│   ├── awatv_core/                          ← business logic, models, M3U/Xtream parsers
│   ├── awatv_player/                        ← media_kit + flutter_vlc_player wrapper
│   └── awatv_ui/                            ← design tokens + reusable widgets
├── supabase/
│   ├── migrations/                          ← 5 SQL migrations applied to AWATV-USER
│   └── seed.sql
├── scripts/                                 ← package-macos.sh, package-linux.sh, etc.
├── .github/workflows/
│   ├── deploy-web.yml                       ← Cloudflare Pages (token-gated)
│   ├── flutter.yml                          ← lint + test on PR
│   ├── pages.yml                            ← GitHub Pages alt deploy
│   ├── release-android.yml                  ← Android .apk/.aab release
│   ├── release-desktop.yml                  ← macOS/Windows/Linux release
│   └── release-ios.yml                      ← TestFlight release ⭐ NEW
└── docs/                                    ← all human-readable docs
    ├── MEMORY.md                            ← this file
    ├── SESSION_LOG.md                       ← chronological work log per version
    ├── TODO.md                              ← prioritized backlog
    ├── SECRETS_REQUIRED.md                  ← credentials checklist
    ├── IOS_TESTFLIGHT_SETUP.md              ← Apple Developer step-by-step
    └── streas-port/                         ← Streas RN → AWAtv Flutter port spec
        ├── awatv-audit.md
        ├── auth-profile-spec.md
        ├── tabs-spec.md
        ├── player-spec.md
        ├── source-paywall-spec.md
        └── components-spec.md
```

---

## Architecture decisions

### State management

**Riverpod 2.6** with code generation. Almost every feature has a `*_controller.dart` (notifier) + `*_providers.dart` (read-only views) pattern, plus a `*.g.dart` generated file. To regenerate after editing annotated providers:

```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
# AND for the core package:
cd packages/awatv_core && dart run build_runner build --delete-conflicting-outputs
```

### Persistence

- **Hive** for local JSON-serializable state (favourites, watch history, settings, prefs flags)
- **flutter_secure_storage** for credentials (Xtream password, Supabase tokens)
- **Supabase Postgres** for cloud sync (tables: `profiles`, `playlist_sources`, `favorites`, `watch_history`, `subscriptions`, `device_sessions`, `telemetry_events`)

Cloud sync engine lives at `apps/mobile/lib/src/shared/sync/cloud_sync_engine.dart`. Activates when user is `AuthSignedIn`, uses last-writer-wins with `updated_at` triggers (defined in migration `20260428000001_sync_columns.sql`).

### Theme system

Source: `packages/awatv_ui/lib/src/theme/`
- `brand_colors.dart` — Cherry red palette (was electric purple). Legacy aurora purple/cyan preserved as `legacyAuroraXxx` for future preset.
- `typography.dart` — Inter font via `google_fonts` (was platform default).
- `app_theme.dart` — `AppTheme.dark()` / `AppTheme.light()` builds `ThemeData` from `BrandColors` constants.

User-customisable theme (premium feature) lives at `apps/mobile/lib/src/features/themes/`. Wraps `AppTheme` with a `CustomThemeBuilder` that lets premium users swap accent / variant / radius.

### Routing

`go_router 14.6.2`. Two routers in `apps/mobile/lib/src/routing/`:
- `app_router.dart` — phone/tablet/desktop bottom-nav shell
- `tv_router.dart` — Android TV / Apple TV left-rail D-pad shell

Form factor probed once at boot in `main.dart` via `isTvFormProvider`. Route lists:

**Mobile shell** (bottom nav):
- `/home`, `/channels`, `/movies`, `/series`, `/search`, `/settings`, `/favorites`

**Auth + profile flow** (modal/full):
- `/welcome`, `/login`, `/signup`, `/account`, `/profiles`, `/profiles/add`, `/profiles/edit/:id`

**Player + detail** (modal):
- `/player/:id`, `/play/:id` (live), `/detail/:id`, `/trailer/:id`, `/subtitle-picker`

**Premium / paywall**:
- `/premium`, `/premium/manage`

**Settings sub-routes**:
- `/settings/theme`, `/settings/playback`, `/settings/network`, `/settings/profiles`, `/settings/about`

### Auto-update mechanism (desktop only)

`apps/mobile/lib/src/shared/updater/`
1. Boot check kicks 5s after first frame (`update_boot_check.dart`)
2. Fetches `https://github.com/YDX64/awatv/releases/latest/download/latest.json`
3. Compares manifest version with `PackageInfo.version` (sourced from pubspec)
4. Downloads .zip → SHA-256 verifies → ditto extracts to `/Applications/AWAtv.app` (in-place overwrite)
5. exits + relaunches via `open -n`

Manifest is auto-generated by `scripts/build-update-manifest.sh` and uploaded as a release asset by `release-desktop.yml`'s `publish-manifest` job.

iOS auto-update is delegated to TestFlight / App Store — no manifest needed there.

### Premium / anti-tamper architecture

**TL;DR:** Server-side enforced. `subscriptions` Postgres row is the only authoritative source of premium state. Local Hive cache exists but is overwritten on every signed-in boot. LuckyPatcher / Frida flipping the local flag fails on the next Supabase poll.

**Flow:**

```
User taps "Subscribe" in app
  ↓
purchases_flutter SDK → App Store Connect / Play Store
  ↓
Apple/Google → RevenueCat (server-side receipt validation)
  ↓
RevenueCat → POST /functions/v1/revenuecat-webhook (signed)
  ↓
Edge Function validates HMAC → upserts public.subscriptions
  ↓
Realtime stream → Flutter app → premium_status_provider state flips
  ↓
UI re-renders with premium UX (no ads, unlimited playlists, etc.)
```

**RLS (`supabase/migrations/20260427000002_rls_policies.sql`):**

- `subscriptions_select_own` — users can SELECT their own row
- No INSERT / UPDATE / DELETE policies for clients → only service-role can write
- The webhook Edge Function uses service-role key, bypasses RLS

**Client-side cache:**

- `apps/mobile/lib/src/shared/premium/premium_status_provider.dart`
- Reads Hive cache for first-frame paint
- Fetches `subscriptions` row on every signed-in boot (auth state listener)
- Subscribes to realtime updates → cancellation/renewal reflects in <1s
- `simulateActivate()` is **kDebugMode-gated** — release builds reject the call so paywall in production can only succeed via real RC purchase
- `signOut()` clears local cache; doesn't touch server (server state remains until RC fires CANCELLATION)

**Free tier defaults:**

- Per `apps/mobile/lib/src/shared/premium/premium_features.dart`
- Each `PremiumFeature` enum value gates a capability
- `feature_gate_provider.dart` decides whether free tier still gets it (default: premium-only)
- Quotas (playlist count, EPG history days, downloads) live in `premium_quotas.dart`

### Ads / freemium

- Banner: `apps/mobile/lib/src/shared/ads/ad_banner.dart` — sticky, auto-hides for `noAds` premium feature
- Interstitial: `apps/mobile/lib/src/shared/ads/ads_providers.dart` — every Nth playback start (currently N=3)
- Boot init: `AwatvAds.initialise()` called from `main.dart` (no-op on web/desktop/TV)
- Premium tier read via `adsEnabledProvider`; flips false the moment `premium_status_provider` flips premium

### Auth

`auth_controller.dart` wraps Supabase GoTrue:
- `sendMagicLink(email)` — passwordless, `shouldCreateUser: true`
- `signInWithPassword({email, password})`
- `signUpWithPassword({email, password})` — explicit signup with 6-char min
- `signOut()`, `updateDisplayName(name)`, `exchangeCodeForSession(code)`

States: `AuthGuest`, `AuthSignedIn(userId, email, displayName)`, `AuthError(message)`.

When `Env.hasSupabase == false` (no `SUPABASE_URL` baked into `.env`), the controller short-circuits to permanent `AuthGuest` and mutating calls throw `AuthBackendNotConfiguredException`.

---

## Operational runbook

### Releasing a new desktop version

1. `cd /Users/max/AWAtv && vim apps/mobile/pubspec.yaml`
2. Bump `version: 0.5.7+10` → `0.5.8+11`
3. `git add apps/mobile/pubspec.yaml && git commit -m "<release notes summary>" && git push origin main`
4. CI auto-triggers `release-desktop.yml` (push event matches `apps/mobile/pubspec.yaml` paths filter)
5. Wait ~17 min for build (3 platforms in parallel)
6. Download artifacts:
   ```bash
   gh run download <run-id> -R YDX64/awatv -n awatv-macos-dmg -D /tmp/awatv-vX.Y.Z/awatv-macos-dmg
   # ... repeat for awatv-macos-zip, awatv-linux-appimage, awatv-windows-zip, awatv-windows-setup
   ```
7. Stage in `dist/`, generate manifest:
   ```bash
   cd /Users/max/AWAtv && rm -rf dist && mkdir -p dist
   cp /tmp/awatv-vX.Y.Z/*/awatv-* dist/
   RELEASE_TAG=awatv-vX.Y.Z RELEASE_NOTES="$(cat /tmp/awatv-vX.Y.Z/RELEASE_NOTES.md)" GH_OWNER=YDX64 GH_REPO=awatv bash scripts/build-update-manifest.sh
   ```
8. Create GitHub Release with all 5 binaries + latest.json:
   ```bash
   gh release create awatv-vX.Y.Z \
     --title "..." \
     --notes-file /tmp/awatv-vX.Y.Z/RELEASE_NOTES.md \
     --target main \
     dist/awatv-macos.dmg dist/awatv-macos.zip dist/awatv-linux-x86_64.AppImage \
     dist/awatv-windows.zip dist/awatv-setup.exe dist/latest.json
   ```
9. Verify public propagation:
   ```bash
   curl -sLo /tmp/lj.json -w "HTTP %{http_code}\n" "https://github.com/YDX64/awatv/releases/latest/download/latest.json"
   python3 -c "import json; m=json.load(open('/tmp/lj.json')); print('version:', m['version'])"
   ```
10. User opens AWAtv → auto-updates → relaunches as new version.

### Releasing iOS to TestFlight

See `docs/IOS_TESTFLIGHT_SETUP.md`. Once Apple Developer secrets are set:

1. <https://github.com/YDX64/awatv/actions/workflows/release-ios.yml> → Run workflow → main branch
2. ~12-15 min build, then auto-upload to TestFlight
3. App Store Connect → app → TestFlight → Ready to Test (~5-10 min export-compliance pass)
4. iPhone TestFlight app → AWAtv build appears

### Local dev loop

```bash
cd /Users/max/AWAtv && flutter pub get
cd apps/mobile && flutter run -d macos    # or chrome / iPhone / Pixel
```

Hot reload works for Dart changes. Native (Swift / ObjC / C++) changes need full rebuild.

### Test suite

```bash
cd /Users/max/AWAtv
flutter test                              # all packages
flutter test apps/mobile/test/            # mobile only
flutter test apps/mobile/integration_test/ # E2E smoke
```

### Linting

```bash
flutter analyze                           # very_good_analysis ruleset
flutter analyze packages/awatv_ui/        # single package
```

### Web deploy (manual, until Cloudflare token set)

```bash
cd /Users/max/AWAtv/apps/mobile
flutter build web --release --pwa-strategy=offline-first --no-tree-shake-icons --base-href=/
npx wrangler pages deploy build/web --project-name=awatv --branch=main --commit-dirty=true
```

Setting `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` GitHub secrets makes `deploy-web.yml` auto-run on every push (already wired).

---

## Current state snapshot (as of v0.5.7)

### Working

- Desktop auto-update chain ✅
- Cherry-red palette + Inter typography ✅
- Multi-profile system ✅ (avatars, PIN, junior mode, profile picker)
- Sandbox-off macOS install ✅
- Bundle name uniformly `AWAtv.app` ✅
- pubspec → Info.plist version flow ✅
- AWATV-USER Supabase backend wired ✅
- 5 DB migrations applied ✅
- GDPR-compliant privacy step ✅ (granular Crashlytics + Analytics, persisted toggles, privacy policy at /privacy)
- Onboarding 7 steps (Welcome / Auth / Privacy / Notifications / First playlist / Premium teaser / All set) ✅
- iOS pipeline written (awaits Apple Developer secrets) ✅

### Known gaps

- Web auto-deploy needs `CLOUDFLARE_API_TOKEN` GitHub secret
- iOS TestFlight needs 7 Apple Developer secrets (see `docs/SECRETS_REQUIRED.md`)
- Android Play Store: workflow exists but not currently a focus
- Streas port phases 2/3/4 not yet implemented (see `docs/TODO.md` and `docs/streas-port/`)
- No real RevenueCat billing — premium tier flag manually toggled via Remote Config
- OpenSubtitles search UI missing (only SRT file load works)
- External player deep-link (VLC/MX/nPlayer) not wired

---

## Key files for newcomers (read these first)

1. `apps/mobile/lib/main.dart` — boot path: env load + Hive init + Supabase init + EasyLocalization + ProviderScope wrap
2. `apps/mobile/lib/src/app/awa_tv_app.dart` — root widget, ThemeMode, router selection
3. `apps/mobile/lib/src/routing/app_router.dart` — go_router config for phone/tablet
4. `apps/mobile/lib/src/shared/auth/auth_controller.dart` — Supabase auth machine
5. `apps/mobile/lib/src/shared/sync/cloud_sync_engine.dart` — cloud sync state machine
6. `apps/mobile/lib/src/shared/updater/updater_service.dart` — desktop auto-update
7. `apps/mobile/lib/src/features/onboarding/wizard_screen.dart` — 7-step onboarding
8. `packages/awatv_ui/lib/src/theme/brand_colors.dart` — design palette
9. `.github/workflows/release-desktop.yml` — desktop CI/CD
10. `.github/workflows/release-ios.yml` — iOS CI/CD

---

## Where data + secrets live

| What | Where |
|------|-------|
| GitHub repo secrets | <https://github.com/YDX64/awatv/settings/secrets/actions> |
| Supabase project dashboard | <https://supabase.com/dashboard/project/ukulkbthsgkmihjcpzek> |
| App Store Connect | <https://appstoreconnect.apple.com/apps> (after iOS setup) |
| Apple Developer | <https://developer.apple.com/account> |
| GitHub Releases | <https://github.com/YDX64/awatv/releases> |
| Cloudflare Pages | <https://dash.cloudflare.com> → Pages → awatv |
| Production web | <https://awatv.pages.dev> |

User identity:
- GitHub: YDX64 (owner)
- Apple ID: TBD (when Apple Developer set up)
- Supabase email: TBD (will be set when first signup happens against AWATV-USER)
- Email: yunusd64@gmail.com / iklim.se@gmail.com (per memory at `~/.claude/projects/-Users-max-bankocu/memory/`)

---

## Reading order for next session

1. **This file** (`MEMORY.md`) — overview
2. **`SESSION_LOG.md`** — what was done version-by-version (so you don't redo)
3. **`TODO.md`** — what's next, in priority order
4. **`SECRETS_REQUIRED.md`** — credentials still needed before iOS / web auto-deploy
5. **`docs/streas-port/awatv-audit.md`** — Streas port roadmap (Phase 2 starts here)
6. Specific feature work? → `docs/streas-port/{auth-profile,tabs,player,source-paywall,components}-spec.md`
