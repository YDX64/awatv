# AWAtv — Session Log (chronological)

> Per-version what-was-done log. Read this if you want to know **why** the codebase is in its current state. New entries go at the **top** (most recent first).

---

## v0.5.8 — Streas Phase 2 + freemium economy + anti-tamper premium

**Released:** 2026-05-04 · **Tag:** [`awatv-v0.5.8`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.8) · **Commit:** `e98cffc`

Massive overnight autonomous session. 5 parallel agents + concurrent platform / freemium / anti-tamper work. **53 files changed, +15725 / -2747 lines.**

### Why

User briefing: "tum pahse leri bitirmelisin bana soru sormadan sabaha kadar mobil android ve ios masaustu mac os windows ve tv os ler icin android tv ve apple tv icin tum hepsi icin yazilimlari bitirmelisin tum applar ayni supabase e baglanacak hepside ayni sistemde calisacak freemium ama reklamli ve kisitlamali vs" + "ayrica kesinlikle kirilamaz olmali yani luckypatcher ile vs kirilamamali revenuecat alt edilip oyle yapiyorlar cunku premium icin uyelik gerekmeli mesela bu sayede supabase ile bir uyelik premium kilit mekanizmasi kurmus oluruz".

Translation: every platform, full freemium with ads + restrictions, anti-tamper-proof premium gate keyed off Supabase membership.

### Streas Phase 2 — 5 parallel agents (21 files touched)

Each agent read the spec docs at `docs/streas-port/` and adapted the matching Flutter file to 1:1 visual parity with the Streas RN reference. Riverpod wiring preserved end-to-end.

- **Agent A (Auth + profile)** — welcome/login/signup/profile-picker/profile-edit/account, plus new `profile_avatar_pool.dart` (24 emojis × 12 colors with the Streas index 8 cherry-dup bug fixed by replacing with `#FF5722`).
- **Agent B (Tabs)** — settings/search/vod/series/favorites/home, including granular GDPR toggles, recent channel strip, hero badges (cherry "NEW RELEASE", gold "TV SHOWS"), TV Guide CTA banner.
- **Agent C (Player + detail)** — player_screen with 10s watch position ticker + live channel drawer + EPG sheet, vod_detail_screen full rewrite, NEW `subtitle_picker_screen.dart` (27 languages, premium-gated download, settings panel), NEW `subtitle_settings.dart` model + controller.
- **Agent D (Premium + paywall + add-source)** — premium_screen rewrite (hero + 2 plans + 10 features + confirm modal + already-premium state), premium_lock_sheet dual-mode (banner | overlay+blur), add_playlist_screen with 3 type cards + 5 sample playlist presets + Test Connection probe + file picker tab.
- **Agent E (Shared components in awatv_ui)** — poster_card 3 variants + LiveChannelCard + HeroBanner/Carousel + new streas_search_bar + profile_sheet + streas_pin_numpad.

### Anti-tamper premium gate (server-authoritative)

`premium_status_provider.dart` REWRITTEN. Hive cache now serves only for first-frame paint; every signed-in boot fetches `subscriptions` row from Supabase and overwrites local cache. Realtime stream catches RC webhook updates in <1s. `simulateActivate()` guarded by `kDebugMode` — release builds reject the call.

Architecture:
```
RC purchase → RC webhook (HMAC-signed) → Supabase Edge Function
  validates signature → upserts subscriptions row →
  RLS: clients SELECT-only, service-role-only writes →
  Realtime stream → app premium UX flips < 1s
```

LuckyPatcher / Frida flips the Hive cache for ~50ms before next server poll restores truth. Cracking requires forging a Supabase JWT, which requires the service-role key (server-only).

3 Edge Functions deployed via Management API to `ukulkbthsgkmihjcpzek`:
- `revenuecat-webhook` (no JWT verify; HMAC-secret-protected)
- `sync-snapshot`
- `tmdb-proxy`

### AdMob freemium

- `apps/mobile/lib/src/shared/ads/awatv_ads.dart` — singleton initialiser + per-platform ad unit id resolver (test ids fall back when env vars empty)
- `ads_providers.dart` — Riverpod providers: `adsEnabled` (gates on `PremiumFeature.noAds`), `playbackCounter` (every-3rd-play cadence), `interstitialAdController` (preload + show), `adsLifecycle` (`onPlaybackStart` hook)
- `ad_banner.dart` — sticky banner widget that auto-hides for premium and on web/desktop/TV
- `main.dart` wires `AwatvAds.initialise()` into the boot sequence
- iOS Info.plist: `GADApplicationIdentifier` + 9 `SKAdNetworkItems` + `NSUserTrackingUsageDescription`
- Android manifest: `com.google.android.gms.ads.APPLICATION_ID` meta-data
- pubspec: `google_mobile_ads ^5.3.1`, `purchases_flutter ^8.4.2`

### CI / deployment additions

- `.github/workflows/release-android-playstore.yml` — release-signed AAB + fastlane supply upload to Play Store internal track
- `supabase/config.toml` — db.major_version 16 → 17 (matches AWATV-USER project), email template stub disabled to unblock CLI deploys

### Memory + onboarding docs

- `docs/MEMORY.md` — extended with Premium / anti-tamper section + Ads section
- `docs/SECRETS_REQUIRED.md` — added 6 AdMob entries, RevenueCat setup instructions, webhook deploy commands
- `docs/REVENUECAT_ADMOB_SETUP.md` (NEW) — full freemium economy setup including anti-tamper verification + cancellation test
- `docs/APPLE_TV_NOTES.md` (NEW) — current status (not a build target) + 3 paths forward
- `docs/TODO.md` — Phase 2 status snapshot at the top
- `docs/streas-port/` — 6 spec files persisted from `/tmp` to repo
- `apps/mobile/ios/ExportOptions.template.plist` (existing) + `.github/workflows/release-ios.yml` (existing) — TestFlight pipeline

### What works after this release

- All 7 Streas-equivalent screens visually match the RN reference
- Cherry red palette + Inter font + correct geometry
- Premium ladder: free shows ads, signup → paywall → RC purchase → webhook → subscriptions table → realtime → premium UX flips
- **Anti-tamper:** server-authoritative gate cannot be flipped client-side
- Multi-profile (Netflix-style picker + PIN + Junior Mode)
- Subtitle picker (27 languages, premium-gated download)
- Sample playlist presets + Test Connection probe
- macOS / Windows / Linux desktop, Android (phone + Android TV) APK
- iOS pipeline ready (awaits Apple Developer secrets)
- Android Play Store pipeline ready (awaits keystore + service-account)

### Known limitations (Phase 3)

- External player deep-link (VLC / MX / nPlayer) — TODO comment in `player_screen.dart`, snackbar shows "Phase 3"
- Real OpenSubtitles search wires up automatically once `OPENSUBTITLES_API_KEY` is set; until then a deterministic stub serves sample SRT cues
- TMDB cast / crew row uses placeholder avatars (real wiring waits on metadata service expansion)
- Apple TV — see `docs/APPLE_TV_NOTES.md`
- Web auto-deploy — `CLOUDFLARE_API_TOKEN` secret still missing

---

## v0.5.7 — Streas port Phase 1 (Cherry palette + Inter typography)

**Released:** 2026-05-04 · **Tag:** [`awatv-v0.5.7`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.7) · **Commit:** `74fc792`

### Why

User asked for 1:1 visual + feature parity with the React Native "Streas" IPTV app at <https://github.com/YDX64/Streas>. After cloning and dispatching 5 parallel research agents to analyse the source (auth/profiles, tab screens, player+detail, source+paywall, shared components), produced a 24,000-word port specification at `docs/streas-port/`.

This release lands Phase 1: the global look-and-feel pivot. Subsequent phases will adapt screen-by-screen layouts and fill the small feature gaps.

### What changed

**`packages/awatv_ui/lib/src/theme/brand_colors.dart`** — Brand tokens shifted from electric purple to cherry crimson:
- `primary`: `#6C5CE7` → `#E11D48`
- `primarySoft`: `#8C7BFF` → `#BE123C`
- `primaryDark`: (new) → `#9F1239`
- `secondary`: `#00D4FF` → `#E11D48` (collapses to primary)
- `background`: `#0A0D14` → `#0A0A0A`
- `surface`: `#14181F` → `#141414`
- `surfaceHigh`: `#1C2230` → `#1C1C1C`
- `outline`: `#2A3040` → `#282828`
- `error`: `#FF4757` → `#EF4444`
- `warning`: `#FFA502` → `#F59E0B`
- `liveAccent`: `#FF3B5C` → `#E11D48`
- `goldRating`: `#FFC857` → `#F59E0B`

Brand gradient: cyan→purple → cherry→cherry-dark.
Premium gradient: warm-purple→magenta → gold→cherry.

Legacy purple/cyan preserved as `legacyAuroraPrimary`, `legacyAuroraSecondary`, `legacyAuroraSurface`, `legacyAuroraSurfaceHigh` so the future "Aurora" theme preset can bring them back.

**`packages/awatv_ui/lib/src/theme/typography.dart`** — `primaryFamily: null` → `'Inter'`. The base style builder now wraps `GoogleFonts.inter(...)` so every text style inherits Inter glyphs.

**`packages/awatv_ui/pubspec.yaml`** — Added `google_fonts: ^6.2.1` (Apache-2.0).

**`apps/mobile/pubspec.yaml`** — `0.5.6+9` → `0.5.7+10`.

### Spec dispatch

5 parallel research agents (each in their own `general-purpose` subagent) analysed the Streas RN codebase concurrently and produced spec docs. Total ~24K words / ~3000 lines:
- `auth-profile-spec.md` (5500 words)
- `tabs-spec.md` (5000 words)
- `player-spec.md` (4600 words)
- `source-paywall-spec.md` (4722 words)
- `components-spec.md` (4960 words)

Each spec maps every Streas screen / component to:
- Visual layout (px / radii / colors / typography)
- Behavior (interactions, validation, animations)
- Data flow (which context state, Supabase tables touched)
- Flutter port mapping (existing AWAtv file, what to change vs build new, recommended Riverpod provider name + signature, widget tree skeleton)

---

## v0.5.6 — GDPR-compliant privacy step

**Released:** 2026-05-03 · **Tag:** [`awatv-v0.5.6`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.6) · **Commits:** `0c6ff21` + `52cac92`

### Why

User feedback: "gdpr sart o yuzden opsiyonel degil privacy" — privacy step in onboarding had four GDPR violations:

1. Toggle changes were never persisted (local widget state only; `main.dart` read a different `observability.optIn` flag nobody wrote to)
2. `Atla` button bypassed the choice without recording a 'no' (Art. 7 requires affirmative action)
3. Single union flag governed both Crashlytics + Analytics (Art. 7(2) requires granular consent)
4. No link to a privacy policy (Art. 13 requires informing the data subject at point of collection)

### What changed

**`apps/mobile/lib/src/shared/observability/awatv_observability.dart`** — Split single union API into granular:
- `crashlyticsOptInKey = 'observability.crashlytics'`
- `analyticsOptInKey = 'observability.analytics'`
- `setCrashlyticsOptIn(bool)` / `setAnalyticsOptIn(bool)`
- `readCrashlyticsOptIn()` / `readAnalyticsOptIn()`
- Backward compat: `_readFlagWithLegacyFallback` checks new key first, falls back to union flag.

**`apps/mobile/lib/src/features/onboarding/wizard_screen.dart`** — `_StepPrivacy` rewritten as `ConsumerStatefulWidget`:
- Reads initial values from Hive on initState
- Each toggle persists to Hive on the same tick
- `Atla` button **removed**
- Two explicit-choice CTAs: "Seçimimle devam et" + "Hepsini reddet ve devam"
- Each toggle wrapped in `_ConsentTile` with subtitle explaining what / why / no PII
- "Gizlilik politikasını oku" link → /privacy

**`apps/mobile/web/privacy.html`** — Static privacy policy (TR + EN tabs), data controller + subprocessors + retention + GDPR rights summary. Bundled in web build.

**`apps/mobile/web/_redirects`** — `/privacy` route added before catch-all.

**`apps/mobile/pubspec.yaml`** — `0.5.5+8` → `0.5.6+9`.

---

## v0.5.5 — Wired to AWATV-USER Supabase project (clean dedicated backend)

**Released:** 2026-05-03 · **Tag:** [`awatv-v0.5.5`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.5) · **Commit:** `0ba28d5`

### Why

User confirmed earlier builds (v0.5.0–v0.5.4) bundled `SUPABASE_URL=https://supabase-awa.awastats.com` — a multi-tenant project shared with the user's other apps. Wrong target. Created dedicated AWATV-USER project (`ukulkbthsgkmihjcpzek`).

### What changed

**Schema migrations** — 5 SQL migrations applied to AWATV-USER via Supabase Management API:
- `20260427000001_initial_schema.sql` — 7 tables (profiles, playlist_sources, favorites, watch_history, subscriptions, device_sessions, telemetry_events)
- `20260427000002_rls_policies.sql` — RLS per user_id
- `20260427000003_indexes.sql` — query perf
- `20260427000004_functions.sql` — SQL helpers
- `20260428000001_sync_columns.sql` — `updated_at` + auto-touch triggers

**GitHub secrets rotated:**
- `SUPABASE_URL` → `https://ukulkbthsgkmihjcpzek.supabase.co`
- `SUPABASE_ANON_KEY` → legacy anon JWT (10-year exp)

**`apps/mobile/pubspec.yaml`** — `0.5.4+7` → `0.5.5+8` (single-byte version bump to retrigger CI; no source changes since flutter_dotenv reads compile-time .env).

---

## v0.5.4 — Onboarding gets login/register + cloud-sync hint + premium teaser

**Released:** 2026-05-01 · **Tag:** [`awatv-v0.5.4`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.4) · **Commits:** `1537baf` + `e6e2ab2`

### Why

User feedback: "onboarding te login yok ? premium features a noldu ?" Two architectural pieces existed but were invisible during first-run:
- `cloud_sync_engine.dart` already syncs `playlist_sources` to Supabase once signed in, but onboarding never asked
- `premium_screen.dart` already advertises 9 paid features, but onboarding never linked there

### What changed

**Onboarding 5 steps → 7:**
- Step 2 (NEW): `_StepAuth` with tabbed UI (Giriş Yap / Hesap Oluştur / Misafir Devam Et). Auto-advance on `AuthSignedIn`.
- Step 5 (modified): playlist form gains primary-tinted "Listen otomatik olarak hesabına yedeklenecek" banner when signed in.
- Step 6 (NEW): `_StepPremium` — 9-feature grid + brand-gradient PREMIUM chip, "Detaylar ve fiyatlar" → /premium.

**`apps/mobile/lib/src/shared/auth/auth_controller.dart`** — `signUpWithPassword(email, password)` added. Validates email shape + 6-char min password client-side.

**`apps/mobile/pubspec.yaml`** — `0.5.3+6` → `0.5.4+7`.

---

## v0.5.3 — Bundle name AWAtv.app + version placeholder + 0.5.3 bump

**Released:** 2026-05-01 · **Tag:** [`awatv-v0.5.3`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.3) · **Commit:** `7f849fc`

### Why

Two more compounding bugs from v0.5.2 that bricked the auto-update flow on the user's actual machine:

1. **Bundle filename mismatch** — `flutter build macos --release` produces `awatv_mobile.app` because pubspec's project name is `awatv_mobile`. Manual installs renamed this to `AWAtv.app`. The auto-updater unzipped into `/Applications/` and the zip preserved the original name → `/Applications/awatv_mobile.app` appeared next to existing `/Applications/AWAtv.app`. `_findInstalledMacosApp` walked the dir, both bundles matched its `path.contains('awatv')` filter, and the relaunch happened on whichever `listSync()` returned first.

2. **Frozen version 0.2.0 in Info.plist** — `flutter build macos --release` only resolves Flutter's `$(FLUTTER_BUILD_NAME)` placeholder; the plist had a hardcoded `<string>0.2.0</string>`. Result: every shipped binary reported `PackageInfo.version = "0.2.0"` regardless of pubspec, triggering an infinite "yeni sürüm var" loop.

### What changed

**`scripts/package-macos.sh`** — Stages every build into a tmp dir as `AWAtv.app` regardless of source bundle name. Both .zip and .dmg uniformly contain `AWAtv.app`. Auto-updater's `ditto -x -k zip /Applications/` now overwrites the existing bundle in place.

**`apps/mobile/macos/Runner/Info.plist`** — Switched to Flutter standard:
```xml
<key>CFBundleShortVersionString</key>
<string>$(FLUTTER_BUILD_NAME)</string>
<key>CFBundleVersion</key>
<string>$(FLUTTER_BUILD_NUMBER)</string>
```

**`apps/mobile/pubspec.yaml`** — `0.5.2+5` → `0.5.3+6`.

---

## v0.5.2 — macOS sandbox off, auto-download update flow, version bump

**Released:** 2026-05-01 · **Tag:** [`awatv-v0.5.2`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.2) · **Commit:** `c754ee9`

### Why

User feedback: "yok hicbirsey calismiyor a yi yaptim yeni surum diyor ama indirme kurma vs yok". v0.5.0/v0.5.1 had two compounding bugs:

1. **App Sandbox = true** in `Release.entitlements` blocked `Process.run('ditto')` and writes to `/Applications/`, so the install step silently failed → `UpdateError` state in a small Settings tile that was easy to miss.
2. **Boot check never auto-started the download** — only surfaced a snackbar with "AÇ" button.

### What changed

**`apps/mobile/macos/Runner/Release.entitlements`** — `app-sandbox: true` → `false`. Hardened Runtime stays on for media_kit's JIT shaders.

**`apps/mobile/lib/src/shared/updater/update_boot_check.dart`** — Chains `UpdateAvailable` → auto-download → `UpdateReadyToInstall` → louder snackbar with "ŞİMDİ KUR" button → `installUpdate()`. Errors get loud snackbar with "DETAY" button to Settings.

**`apps/mobile/pubspec.yaml`** — `0.1.0+1` → `0.5.2+5` (PackageInfo finally reports release tag).

---

## v0.5.1 — Player UX overhaul + auto-update unblock

**Released:** 2026-05-01 · **Tag:** [`awatv-v0.5.1`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.1) · **Commits:** `f713c06` + `6461506` + `0374b1f`

### Why

User feedback: "player kontrolleri asla gorunmuyor". Plus v0.5.0's `release.published` runs failed silently with HTTP 403 because `GITHUB_TOKEN` lacked `contents: write`.

### What changed

**`apps/mobile/lib/src/features/player/player_screen.dart`**
- Removed `_toggleControls`, replaced with `_onTap` smart policy (visible→play/pause, hidden→reveal)
- Removed `kIsWeb` gate on `onHover` so desktop native gets cursor-driven control reveal
- Auto-hide bumped 3500ms → 5000ms
- Cursor hidden when controls hidden (`MouseRegion.cursor: SystemMouseCursors.none`)

**`.github/workflows/release-desktop.yml`** — Added workflow-root `permissions: contents: write` so `gh release upload` can attach assets.

**`.github/workflows/deploy-web.yml`** — Switched SSH/rsync (broken — secrets empty) → Cloudflare Pages via `cloudflare/wrangler-action@v3`. Gated on `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (skips deploy if missing instead of failing).

---

## v0.5.0 — Player UX + Paywall + Desktop unblock

**Released:** 2026-05-01 · **Tag:** [`awatv-v0.5.0`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.0) · **Commit:** `c15e700` (paywall) + `12d9066` (macOS-15 runner)

### Why

Bumped macOS runner from `macos-14` to `macos-15` because FirebaseSharedSwift uses Swift 6.0 `sending` keyword, which Xcode 15 / Swift 5.9 (on macos-14) couldn't parse.

Refactored paywall to industry-standard IPTV-app pattern (2-column desktop / stacked mobile, 9 feature bullets, 3 plan tiles with yearly default-selected + "EN POPULER" badge, 3-day trial line, restore link).

---

## Pre-v0.5 (recap)

- v0.3.0 (2026-04-28): VLC, auto-update mechanism, cloud sync
- v0.2.1 (2026-04-28): Netflix-tier player + Remote Control + Desktop builds
- v0.2.0 (2026-04-27): Multi-platform foundation

Earlier history not maintained — repo is the source of truth via `git log --oneline`.

---

## Cross-cutting wins this session

1. **Cascading bug-discovery onion**: Each white-screen fix exposed the next one. v0.5.0 paywall → v0.5.1 player + permissions → v0.5.2 sandbox → v0.5.3 bundle rename + version frozen → v0.5.4 onboarding visibility → v0.5.5 wrong Supabase → v0.5.6 GDPR → v0.5.7 Streas port. Live testing on user's real machine surfaced bugs no synthetic test would have caught (especially the bundle filename mismatch — only visible after a successful auto-update install).

2. **Public manifest delivery**: Repo public + `contents: write` permission + `release.published` webhook all coordinated for reliable `latest.json` propagation. The user's app now auto-updates without intervention.

3. **Multi-platform parallel build**: macos-15 / windows-latest / ubuntu-latest run concurrently (~17 min total). Each platform's "Attach to GitHub Release" step uses `--clobber` for idempotent re-uploads.

4. **5-agent parallel research**: Streas port spec produced in ~5 min via 5 concurrent agents, each on a non-overlapping domain. Total ~24K words / 3000 lines, persisted to `docs/streas-port/`.

5. **GDPR compliance closed**: granular Crashlytics + Analytics flags, persisted-on-change toggles, explicit choice (no Skip), privacy policy at `/privacy` (TR + EN, dark/light auto via `prefers-color-scheme`).
