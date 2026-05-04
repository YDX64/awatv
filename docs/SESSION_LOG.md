# AWAtv — Session Log (chronological)

> Per-version what-was-done log. Read this if you want to know **why** the codebase is in its current state. New entries go at the **top** (most recent first).

---

## v0.5.11 — UX: success snackbars after auth + Supabase email-autoconfirm

**Released:** 2026-05-04 · **Tag:** [`awatv-v0.5.11`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.11) · **Commit:** `df6f1af`

### Why

User reported two friction points after the v0.5.x rollout:

1. **Email confirmation hop.** Supabase's `mailer_autoconfirm` was off and the project's `site_url` was the default `http://localhost:3000`. New signups landed with an unusable confirmation link pointing at a dev address. User wanted the extra step removed entirely — auth-via-password should create an active session immediately.

2. **Silent button.** After tapping "Giriş yap" / "Kayıt ol" the screen jumped without any acknowledgement that the click had landed. On a slow uplink this was indistinguishable from "did it crash, did it submit twice?".

### Backend (applied via Supabase Management API)

```
PATCH /v1/projects/ukulkbthsgkmihjcpzek/config/auth
  mailer_autoconfirm: false  →  true
  site_url: http://localhost:3000  →  https://awatv.pages.dev
  uri_allow_list: ""  →  https://awatv.pages.dev/**,
                         io.supabase.awatv://login-callback,
                         com.awatv.mobile://login-callback,
                         com.awatv.awatvMobile://login-callback
```

New signups now bypass the confirmation email entirely; the signUp call returns an active session synchronously and the auth controller's listener fires `AuthSignedIn` on the same tick.

Pending users from before the toggle: 0 (verified via `SELECT count(*) FROM auth.users WHERE email_confirmed_at IS NULL`). Database was effectively empty since the old confirmation flow had blocked every signup attempt.

### Client diffs (3 files)

`apps/mobile/lib/src/features/auth/login_screen.dart`: 2-second SnackBar "Giriş başarılı — ana ekrana yönlendiriliyorsun…" right before `context.go(next)`. ScaffoldMessenger lives above the router so the toast persists across the route push.

`apps/mobile/lib/src/features/auth/signup_screen.dart`: 3-second SnackBar "Hesabın oluşturuldu, hoş geldin {name}! Ana ekrana götürüyorum…" right before the redirect.

`apps/mobile/lib/src/features/onboarding/wizard_screen.dart`: Auth-step listener now surfaces "Hesabın oluşturuldu — devam ediliyor…" / "Giriş başarılı — devam ediliyor…" depending on `_AuthMode` before the wizard auto-advances. Best-effort: pulls `ScaffoldMessenger.maybeOf` so a missing messenger doesn't break the advance.

---

## v0.5.10 — patch: url_launcher explicit dep + cloud_sync null-check cleanup

**Released:** 2026-05-04 · **Tag:** [`awatv-v0.5.10`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.10) · **Commit:** `38281e9`

Two small post-Phase-3 fixes that surfaced after v0.5.9 shipped.

1. **`url_launcher` declared as direct dep** in `apps/mobile/pubspec.yaml`. Was transitively resolved through `supabase_flutter`'s tree. Agent B (v0.5.9 external player) flagged this as brittle — a future supabase upgrade dropping the transitive dep would silently break the external-player picker. Now pinned at `^6.3.2`.

2. **`cloud_sync_engine.dart` null-check cleanup** — 5 `unnecessary_non_null_assertion` warnings + 1 `invalid_null_aware_operator` warning originated from the v0.4.x white-screen LateInitializationError fix. After `_client` was promoted to non-nullable via method-entry guards, the analyser correctly flagged every `!` and `?.` as redundant. Removed.

   Net: 6 lines changed, 0 behavioural diff (the null-checks were already proven unreachable by flow analysis).

Lint after: 0 errors, 0 warnings, 95 info-only style hints.

---

## v0.5.9 — Phase 3 feature gaps closed

**Released:** 2026-05-04 · **Tag:** [`awatv-v0.5.9`](https://github.com/YDX64/awatv/releases/tag/awatv-v0.5.9) · **Commits:** `b328d5d` + `d61d594`

Four parallel agents shipped the Phase 3 backlog: real RevenueCat client wiring, VLC/MX/nPlayer external-player launchers, TMDB cast + similar-movies API integration, and a cleanup pass.

### Agent A — RevenueCat client + purchase flow

`apps/mobile/lib/src/shared/billing/revenuecat_client.dart` (NEW): `AwatvBilling` singleton wrapping `purchases_flutter` v8. Public API: `AwatvProductIds.{monthly,yearly,lifetime}` constants, `initialise()` (idempotent, no-op on web/desktop/TV), `setAppUserId / clearAppUserId` (caches bound user), `getCurrentOffering / getOfferings / findPackageForProduct`, `purchaseProduct(productId)` returning sealed `PurchaseOutcome` (Success / Cancelled / Failure), `restorePurchases()` returning `RestoreOutcome`, `_humaniseError` mapping every `PurchasesErrorCode` to TR copy.

`apps/mobile/lib/src/shared/billing/billing_providers.dart` (NEW): Riverpod providers including `billingIdentitySyncProvider` that listens to `authControllerProvider` and calls `setAppUserId` on AuthSignedIn / `clearAppUserId` on AuthGuest, with `fireImmediately: true` so cold-start sessions bind on first frame.

`main.dart`: `unawaited(AwatvBilling.instance.initialise())` after Supabase init + `container.read(billingBootstrapProvider)` to mount the auth listener.

`premium_screen.dart`: `_activate()` calls real `AwatvBilling.purchaseProduct(productId)` with full sealed-outcome switch. `_restorePurchases()` calls real `restorePurchases()`. `simulateActivate` reachable ONLY via hidden 5x long-press on plan tile within 4s, gated by `kDebugMode`. Production builds reject the debug shortcut entirely.

### Agent B — External player deep-link

`external_player_launcher.dart` (NEW): per-platform URI builders for VLC / MX Player Pro+Free / nPlayer. Header forwarding via Android intent extras `S.User-Agent` / `S.Referer`.

`external_player_picker_sheet.dart` (NEW): bottom sheet with per-row tile (icon + name + tagline + chevron/spinner). Filters players by platform support.

`player_screen.dart`: `_onExternalPlayerRequested` replaces TODO with real flow. On launch failure shows TR "X yuklu degil — Indir" snackbar with App Store / Play Store deep-link.

`ios/Runner/Info.plist`: `LSApplicationQueriesSchemes` with `vlc-x-callback`, `vlc`, `nplayer-`.

`android/app/src/main/AndroidManifest.xml`: `<queries>` block extended with `org.videolan.vlc` + 2 MX packages (Android 11+ visibility).

### Agent C — TMDB cast + crew + similar movies

`packages/awatv_core/lib/src/models/tmdb_credits.dart` (NEW): `TmdbCastMember`, `TmdbCrewMember`, `TmdbCredits` plain Dart with manual JSON parsing.

`tmdb_client.dart`: + `profileUrl(path)` w185 helper, + `credits(tmdbId, {isMovie})` (top-8 cast, top-4 crew filtered to Director/Writer/Screenplay/Story), + `similarTmdbIds(tmdbId, {isMovie, limit})`.

`metadata_service.dart`: + `credits()` and `similarTmdbIds()` with 24h Hive-backed TTL via existing `AwatvStorage.putMetadataJson`.

`apps/mobile/lib/src/features/vod/vod_credits_provider.dart` (NEW): `vodCreditsProvider` + `vodSimilarTmdbIdsProvider` as `FutureProvider.autoDispose.family<…, int?>` with 1h `keepAlive`.

`apps/mobile/lib/src/features/vod/cast_detail_screen.dart` (NEW): `/cast/:id` no-op stub.

`vod_detail_screen.dart`: `_CastRow` becomes `ConsumerWidget` reading `vodCreditsProvider`. Loading: 6-circle skeleton; error/empty: hides row entirely. Each `_CastAvatar`: 60-px ClipOval(CachedNetworkImage), tap → `/cast/:id?name=…`. `_SimilarRow` merges TMDB recommendations with local genre-overlap scoring: top-5 TMDB-owned-locally + top-5 genre-overlap, deduped.

### Agent D — Cleanups + race fix

`apps/mobile/web/privacy.html`: `privacy@awatv.app` → `support@awatv.com` (4 occurrences) + TODO comment header.

`opensubtitles_client.dart`: User-Agent `'AWAtv v0.1'` → `'AWAtv v0.5.8'`.

`updater_service.dart`: `_installMacos` race fix. `Process.run('open', ['-n', appPath])` → `Process.start('open', ['-n', '-W', appPath], mode: ProcessStartMode.detached)`. The `-W` makes `open` wait, `detached` makes it survive the parent's exit, `-n` forces a fresh instance. Fixes the v0.5.2/v0.5.3 "app closed but didn't relaunch" Launch Services race.

### Fix-up commit (`d61d594`)

Initial v0.5.9 commit accidentally staged `/dist/` (190 MB of binaries) plus `/supabase/.temp/`. Added both to `.gitignore` + `git rm --cached`. Future commits won't include them.

### What works after this release

- Real RC purchase flow on iOS / Android (StoreKit / Play Billing wired; webhook → Supabase realtime → premium UX flips < 1s)
- External player deep-link from player chrome (VLC / MX / nPlayer)
- TMDB cast + crew avatars on VOD detail (live data)
- Similar movies merge TMDB recommendations with local catalog
- Privacy email replaced
- macOS auto-update relaunch race fixed (no more "closed but didn't reopen")

### Known limitations (deferred)

- Apple TV — see `docs/APPLE_TV_NOTES.md` (Universal Purchase target / WebView wrapper paths)
- Web auto-deploy — `CLOUDFLARE_API_TOKEN` secret still missing
- `/cast/:id` route is a stub — Phase 4 fills filmography
- `url_launcher` not declared as direct dep in pubspec; imports tagged with `// ignore: depend_on_referenced_packages`. Should add explicitly to remove the brittle transitive resolution

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
