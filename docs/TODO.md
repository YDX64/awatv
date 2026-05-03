# AWAtv — TODO (prioritized backlog)

> Items are ordered by **what unblocks the most other work**. Top items have ROI > effort. Update status by editing this file.

Status keys: 🔴 blocked (needs user action) · 🟡 in-progress · 🟢 ready-to-pick-up · ⚪ deferred

---

## P0 — User-action-required (unblocks everything else)

### 🔴 Apple Developer setup → iOS TestFlight

**Why:** User asked for TestFlight build. Pipeline is wired but needs 7 secrets.

**Steps:**
1. Read `docs/IOS_TESTFLIGHT_SETUP.md` start-to-finish.
2. Apple Developer Program enrollment (if not member): <https://developer.apple.com/programs/enroll/> — $99/year, 1-2 day approval.
3. Register Bundle ID `com.awatv.awatvMobile` in Apple Developer.
4. Create app in App Store Connect for that bundle ID.
5. Generate distribution certificate (.p12) via Keychain Access.
6. Generate App Store provisioning profile, name `AWAtv App Store`.
7. Generate App Store Connect API key (App Manager role) → download `.p8`.
8. base64-encode .p12, .mobileprovision, .p8 (commands in setup doc).
9. Add 7 GitHub secrets at <https://github.com/YDX64/awatv/settings/secrets/actions>:
   - `APPLE_TEAM_ID`
   - `APPLE_CERTIFICATE_P12`
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_PROVISIONING_PROFILE`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_BASE64`
10. Trigger workflow manually: <https://github.com/YDX64/awatv/actions/workflows/release-ios.yml> → Run workflow.
11. Wait ~12-15 min. Watch App Store Connect → TestFlight tab for "Ready to Test".
12. Open TestFlight app on iPhone → AWAtv build appears.

**Files involved:**
- `.github/workflows/release-ios.yml`
- `apps/mobile/ios/ExportOptions.template.plist`
- `docs/IOS_TESTFLIGHT_SETUP.md`

### 🔴 Cloudflare Pages auto-deploy

**Why:** Web build at <https://awatv.pages.dev> is currently stale (manual `wrangler pages deploy` needed). Two GitHub secrets unblock auto-deploy.

**Steps:**
1. Get Cloudflare API token at <https://dash.cloudflare.com/profile/api-tokens>:
   - "Create Token" → "Edit Cloudflare Workers" template
   - Or custom: Account → Cloudflare Pages: Edit
2. Get Account ID from Cloudflare dashboard right sidebar.
3. Add secrets:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
4. Push any change to main → `deploy-web.yml` auto-runs.

**Files involved:**
- `.github/workflows/deploy-web.yml`

---

## P1 — Streas port Phase 2 (parallel-agent ready)

The 24K-word spec at `docs/streas-port/` is ready. Phase 2 is **per-screen layout polish** — adapt each existing AWAtv Flutter screen to 1:1 match the Streas RN visual reference. Cherry palette + Inter font already shipped in v0.5.7 (Phase 1).

These can be done in parallel by 5 subagents working on non-overlapping screens.

### 🟢 Phase 2.1 — Auth + profile flow polish

Spec: `docs/streas-port/auth-profile-spec.md`
Files to edit:
- `apps/mobile/lib/src/features/onboarding/welcome_screen.dart` — Streas-aligned hero artwork + sequenced spring animation + cherry CTA
- `apps/mobile/lib/src/features/auth/login_screen.dart` — 2-step email→password flow per spec section 3
- `apps/mobile/lib/src/features/auth/signup_screen.dart` (NEW) — extract from wizard step 2 into standalone screen
- `apps/mobile/lib/src/features/profiles/profile_picker_screen.dart` — Netflix-style 24×12 avatar grid + Add Profile slot
- `apps/mobile/lib/src/features/profiles/profile_edit_screen.dart` — emoji × color grid + PIN numpad + Junior Mode
- `apps/mobile/lib/src/features/auth/account_screen.dart` — Streas account screen anatomy

Open questions from spec:
- PIN currently plain-text — port-time security upgrade to Argon2id
- Avatar `AVATAR_COLORS` index 0 and 8 are duplicates — fix on port

### 🟢 Phase 2.2 — Tab screens polish

Spec: `docs/streas-port/tabs-spec.md`
Files:
- `apps/mobile/lib/src/features/home/home_screen.dart` — 52% screen hero + 6-row layout (Live Now / Continue Watching / Trending / Movies / Series / TV Guide CTA)
- `apps/mobile/lib/src/features/channels/*` — 120-wide live cards + LIVE badge + viewer count
- `apps/mobile/lib/src/features/vod/*` — Movies tab geometry
- `apps/mobile/lib/src/features/series/*` — TV Shows tab geometry
- `apps/mobile/lib/src/features/search/*` — Streas search bar + result rows
- `apps/mobile/lib/src/features/favorites/*` — list-style favourites
- `apps/mobile/lib/src/features/settings/*` — Settings tile geometry
- `apps/mobile/lib/src/shared/home_shell.dart` — bottom-nav 5 visible tabs + 3 hidden routes (guide, favorites, settings)
- `packages/awatv_ui/lib/src/widgets/epg_grid.dart` — 90-wide channel column + 18 half-hour slots × 120px

### 🟢 Phase 2.3 — Player + detail polish

Spec: `docs/streas-port/player-spec.md`
Files:
- `apps/mobile/lib/src/features/player/player_screen.dart` — EPG overlay + channel side drawer (live mode)
- VOD detail screen (in `features/vod/`) — backdrop hero + cast/crew + similar row
- New `subtitle_picker_screen.dart` — OpenSubtitles search UI

### 🟢 Phase 2.4 — Premium + paywall polish

Spec: `docs/streas-port/source-paywall-spec.md`
Files:
- `apps/mobile/lib/src/features/premium/premium_screen.dart` — Streas paywall geometry (hero + 2 plan tiles + 10 feature rows + cherry confirm modal)
- `apps/mobile/lib/src/features/premium/premium_lock_sheet.dart` — banner + overlay variants
- `apps/mobile/lib/src/features/playlists/*` — add-source 3-tab segmented (M3U URL / Xtream / File) + 5 sample playlist presets

### 🟢 Phase 2.5 — Shared components polish

Spec: `docs/streas-port/components-spec.md`
Files:
- `packages/awatv_ui/lib/src/widgets/poster_card.dart` — Streas ContentCard 2:3 + 16:9 + channel logo variants
- `packages/awatv_ui/lib/src/widgets/channel_tile.dart` — LiveChannelCard with persistent LIVE badge + viewers
- `packages/awatv_ui/lib/src/widgets/backdrop_header.dart` + `gradient_scrim.dart` — HeroBanner anatomy
- New `streas_search_bar.dart` — debounced 300ms + clear button + voice button
- New `profile_sheet.dart` — bottom sheet with current profile + stats + 6 menu items + premium banner

---

## P2 — Streas port Phase 3 (feature gaps)

Each is independently scopable. Order by user value.

### ⚪ OpenSubtitles search UI

**Spec:** `docs/streas-port/player-spec.md` § subtitle pipeline
**Why:** Free vs subscribed gating; Streas has 27 languages.
**Where:** subtitle picker screen (new) + `apps/mobile/lib/src/shared/player/subtitle_*.dart`
**Effort:** ~1-2 days

### ⚪ File upload tab in add-source

**Spec:** `docs/streas-port/source-paywall-spec.md` § add-source.tsx
**Why:** Users want to drop M3U/M3U8/TXT directly without URL.
**Where:** Add a tab to existing `apps/mobile/lib/src/features/playlists/add_playlist_screen.dart`
**Note:** Persist as document-directory paths, NOT as `localFileContent` blobs in storage.
**Effort:** ~1 day

### ⚪ Watch position 10s ticker (VOD)

**Spec:** `docs/streas-port/player-spec.md` § watch positions
**Why:** Streas has the table + service but never wired the ticker — port must fix this.
**Where:** `apps/mobile/lib/src/features/player/player_screen.dart` (VOD branch) + new ticker provider
**Effort:** half a day

### ⚪ External player deep-link (VLC / MX / nPlayer)

**Spec:** `docs/streas-port/player-spec.md` § hybrid player
**Why:** RTMP / RTSP / SRT / UDP / RTP / FLV not supported by media_kit reliably; deep-link to native players.
**Where:** New `apps/mobile/lib/src/features/player/external_player_picker.dart`
**Effort:** ~1 day per platform (iOS / Android / desktop)

### ⚪ RevenueCat real billing

**Spec:** `docs/streas-port/source-paywall-spec.md` § RevenueCat
**Why:** Currently `is_subscribed` flag is manually toggled via Remote Config. Production needs in-app purchase + receipt validation.
**Where:** New `apps/mobile/lib/src/shared/billing/` with `purchases_flutter` SDK
**Effort:** 2-3 days (cert + product registration in App Store Connect / Google Play)

### ⚪ 18-stream-format registry

**Spec:** `docs/streas-port/source-paywall-spec.md` § fileUpload.ts
**Why:** Per-format MIME / hex color / `needsVLC` flag for graceful degradation.
**Where:** `packages/awatv_core/lib/src/streaming/stream_formats.dart` (new)
**Effort:** half a day

---

## P3 — Streas port Phase 4 (verification)

### ⚪ Side-by-side screenshot comparison

**Why:** "1:1 görünüm" claim verification.
**How:** Run Streas web export at one URL, AWAtv web build at another, capture every route, diff. Use Playwright + pixelmatch.
**Effort:** 1-2 days for setup + 1 day per screen.

---

## P4 — Cleanup + polish

### ⚪ Settings → "Onboarding'i tekrar göster" tile

**Why:** v0.5.6 introduced a manual `rm -rf ~/Library/Application Support/com.awatv.mobile/awatv-storage` workaround. UI button > shell command.
**Where:** `apps/mobile/lib/src/features/settings/settings_screen.dart`
**Effort:** 1 hour

### ⚪ Settings privacy section → granular 2-toggle UI

**Why:** v0.5.6 split into `crashlyticsOptInKey` + `analyticsOptInKey` but Settings still uses single union flag. Backward-compat works but UI doesn't expose granularity.
**Where:** `apps/mobile/lib/src/features/settings/settings_screen.dart`
**Effort:** 2 hours

### ⚪ Replace placeholder `privacy@awatv.app` with real inbox

**Why:** GDPR Art. 13 lists controller contact — placeholder is currently in `apps/mobile/web/privacy.html`.
**Where:** `apps/mobile/web/privacy.html` (search for `privacy@awatv.app`)
**Effort:** 5 min

### ⚪ Settings privacy policy link → /privacy

Pull `apps/mobile/lib/src/features/settings/settings_screen.dart` and add a tile linking to <https://awatv.pages.dev/privacy>. Currently only the onboarding step links there.

### ⚪ Bump dependencies

77 packages have newer versions per `flutter pub outdated`. Should batch-update on a quiet branch + run integration tests.

### ⚪ Web build verify

Web auto-deploy is gated on `CLOUDFLARE_API_TOKEN`; until then production at <https://awatv.pages.dev> may be stale. Manually deploy after v0.5.7 changes:

```bash
cd apps/mobile && flutter build web --release --pwa-strategy=offline-first --no-tree-shake-icons --base-href=/
npx wrangler pages deploy build/web --project-name=awatv --branch=main --commit-dirty=true
```

---

## P5 — Future feature ideas (not in Streas, not yet planned)

- Apple TV (`tvos`) — iOS bundle works, just need build target
- Android TV — `tv_router.dart` exists, build target wiring + leanback launcher metadata
- ChromeOS / iPad — already work via responsive layout, just need store listings
- Stalker / Mac / portal IPTV format support deeper integration
- DVR cloud recording (premium)
- Family sharing via Apple Family / Google Play Family
- Live ARM-based Linux build (currently x86_64 only)

---

## Triage notes

- "Streas port Phase 2" entries are **safe to dispatch via parallel agents** — non-overlapping files. See "Operational runbook" in MEMORY.md for the dispatch pattern.
- "Phase 3" feature gaps are smaller and can land independently.
- "Phase 4" verification is the last phase — only meaningful after Phase 2 + 3 are done.

---

## Daily startup checklist (when session resumes)

1. `git pull origin main` to refresh local repo.
2. `git log --oneline -10` to see recent commits.
3. Read `docs/MEMORY.md` for project state overview.
4. Read `docs/SESSION_LOG.md` top entry — what was last done?
5. Read this file (`docs/TODO.md`) — what's next?
6. Pick a P0 / P1 / P2 item, mark 🟡 in-progress, commit when done.
