# Streas → AWAtv Flutter Port Specification
## Content Import + Paywall

> **Source:** React Native (Expo) IPTV app at `/tmp/Streas/artifacts/iptv-app/`
> **Target:** Flutter monorepo at `/Users/max/AWAtv/apps/mobile/`
> **Scope:** `add-source.tsx`, `paywall.tsx`, `PremiumGate.tsx` and supporting utilities only
> **Brand palette:** Cherry red Netflix-inspired (`#E11D48` primary, `#0a0a0a` background, `#141414` cards, `#f59e0b` gold accent for "BEST VALUE")

---

## 1. `add-source.tsx` — Add Playlist Screen

### 1.1 Visual Layout (Top → Bottom)

The Streas screen is a single `KeyboardAvoidingView` containing a `ScrollView`. Flow:

1. **Header bar** — fixed at top with `StyleSheet.hairlineWidth` bottom border
   - Left: close icon (`x`, 22 px) → `router.back()`
   - Center: title `"Add Playlist"` (Inter_700Bold, 17 px)
   - Right: **Save button** (cherry primary background, white bold "Save" or `ActivityIndicator` when `loading`); 60 px min width, 8 px radius. Disabled at 40 % opacity until `canSave` resolves true.

2. **Type Selector grid** — three equal-width cards in a horizontal row (`gap: 8`):
   - `xtream` — Feather `zap` icon, **"Xtream Codes"** label, sub-text *"Server + username + password"*
   - `m3u` — Feather `link` icon, **"M3U URL"** label, sub-text *"Remote playlist link"*
   - `file` — Feather `upload` icon, **"Local File"** label, sub-text *".m3u / .m3u8 from device"*
   - Active card: cherry-tinted background (`primary + "1a"`), cherry border, `LinearGradient` overlay (primary 20 → transparent diagonal), check-mark badge top-right (`primary` filled, 16×16, white check icon). Inactive: card background, border color.
   - Tap reset wipes form state via `resetState(t.id)` (clears name, error, verified, picked file, channel count).

3. **Form section** — switches based on `type`:
   - **Xtream form**:
     - InfoNote with `info` icon: *"Enter your Xtream Codes / IPTV provider credentials"*
     - **Server URL** (TextInput, keyboard `url`, no autocap) — placeholder `http://yourprovider.com:8080`
     - **Username** (plain) — placeholder `username`
     - **Password** (`secureTextEntry`) — placeholder `password`
   - **M3U URL form**:
     - InfoNote: *"Paste your M3U or M3U8 playlist URL. Works with most IPTV providers."*
     - **M3U / M3U8 URL** field — placeholder `http://provider.com/get.php?username=X&password=Y&type=m3u`
     - **EPG / XMLTV URL (optional)** field
     - "FREE SAMPLE PLAYLISTS" label (10 px Inter_700Bold, 1.5 letter-spacing)
     - 5 preset cards (IPTV-Org News 800+ / Entertainment 600+ / Sports 200+ / Free-TV 1200+ / IPTV-Org Full Index 9 000+) — each is a `TouchableOpacity` row with colored circular flag (38×38, emoji icon), name, description, count chip, and check icon when selected. Tap fills `m3uUrl` and `name`.
   - **Local File form**:
     - InfoNote: *"Pick an .m3u or .m3u8 file from your device. The playlist is read locally — no network required."*
     - **File picker tile** (large, 80 px min height, 14 px radius, dashed cherry border when empty / solid when picked):
       - Idle state: folder icon (28 px primary) in 52×52 surface box, "Browse Files" title, "Supports .m3u · .m3u8 · .txt" subtitle, chevron right.
       - Loading state: `ActivityIndicator` + "Reading file…"
       - Picked state: 44×44 cherry tile with `file-text` icon, file name truncated, format pill (e.g. `M3U8`), file size (KB/MB), `x-circle` clear button.
     - **File stats row** (only when `fileChannelCount` and `pickedFile` set): three equal columns separated by hair-line dividers — `tv` icon → channel count, `hard-drive` → file size, `file` → format. Each cell shows icon (cherry), bold value, muted label.

4. **Playlist Name field** (always visible, optional)
   - Hint text adapts: `"My IPTV"` for Xtream, `"Sports Package"` for M3U, basename without extension for file.

5. **Test Connection button** (hidden for `file` type)
   - Inactive: cherry-tinted background (`primary + "15"`), cherry border, `wifi` icon, "Test Connection".
   - Loading: spinner, "Connecting…".
   - Verified: green success tint (`#22c55e18`), green border, `check-circle`, "Connection OK".

6. **Verified info banner** — small green `#22c55e` box with check + verified message (e.g. *"✓ 800 channels found"*).

7. **Error banner** — `destructive + "18"` background, `destructive` border, `alert-circle` + message.

8. **Bottom info card** — explanatory bullet list keyed off `type`:
   - Xtream: "Live TV with EPG • VOD movies & series • Catch-up / time-shift • Real-time account info"
   - M3U: "Live TV channels • Channel groups (tvg-group) • Logos (tvg-logo) • XMLTV EPG via separate URL"
   - File: "No internet required • Parsed fully offline • .m3u · .m3u8 · .txt formats • Channel groups preserved"

### 1.2 Form Validation Rules

| Field | Rule |
|---|---|
| Xtream server URL | Required; validated implicitly by `new URL(server.trim()).hostname` for default name; full HTTP request must succeed; auth response must not have `auth === 0`; must contain `user_info` |
| Xtream username | Required (non-empty trimmed) |
| Xtream password | Required (non-empty trimmed) |
| M3U URL | Required (non-empty trimmed); fetch must return `resp.ok`; parsed result must have ≥ 1 channel |
| File pick | At least one parsed channel; must start with `#EXTM3U` |
| Playlist name | Optional — auto-derived if blank |

`canSave` is the boolean gate for Save button: `!loading && (xtream → server && username && password) || (m3u → m3uUrl) || (file → pickedFile)`.

### 1.3 Format Detection (18 Stream Formats)

Implemented in `utils/fileUpload.ts`. Each format includes id / name / extension / MIME type / brand color / human description / `needsVLC` flag.

| ID | Name | Ext | MIME | Color | needs VLC |
|---|---|---|---|---|---|
| `hls` | HLS | `.m3u8` | `application/x-mpegurl` | `#E11D48` | no |
| `dash` | MPEG-DASH | `.mpd` | `application/dash+xml` | `#8b5cf6` | no |
| `mpeg-ts` | MPEG-TS | `.ts` | `video/mp2t` | `#f59e0b` | no |
| `mp4` | MP4 / H.264 | `.mp4` | `video/mp4` | `#22c55e` | no |
| `mkv` | MKV / H.265 | `.mkv` | `video/x-matroska` | `#ef4444` | yes |
| `mp3` | MP3 Audio | `.mp3` | `audio/mpeg` | `#ec4899` | no |
| `aac` | AAC Audio | `.aac` | `audio/aac` | `#14b8a6` | no |
| `flac` | FLAC Audio | `.flac` | `audio/flac` | `#06b6d4` | yes |
| `rtmp` | RTMP | — | `video/x-flv` | `#f97316` | yes |
| `rtsp` | RTSP | — | `application/x-rtsp` | `#a855f7` | yes |
| `srt` | SRT Protocol | — | `application/x-srt` | `#0ea5e9` | yes |
| `udp`/`rtp` | UDP/RTP Multicast | — | `video/udp` | `#84cc16` | yes |
| `flv` | FLV | `.flv` | `video/x-flv` | `#fbbf24` | yes |
| `avi` | AVI | `.avi` | `video/avi` | `#fb923c` | yes |
| `mov` | MOV / QuickTime | `.mov` | `video/quicktime` | `#4ade80` | no |
| `wmv` | WMV | `.wmv` | `video/x-ms-wmv` | `#818cf8` | yes |
| `webm` | WebM | `.webm` | `video/webm` | `#34d399` | no |
| `mpeg` | MPEG | `.mpeg` | `video/mpeg` | `#f472b6` | yes |

Detection precedence (`detectStreamFormat(url)`): `.m3u8`/`hls` → `.mpd`/`dash` → `.ts` → `.mp4` → `.mkv` → `.mp3` → `.aac` → `.flac` → `rtmp://` → `rtsp://` → `srt://` → `udp://`/`rtp://` → `.flv` → `.avi` → `.mov` → `.wmv` → `.webm` → fallback **HLS**.

Helper builders also produce VLC / MX Player / nPlayer intent URLs for Android/iOS deep-link fallback when a format `needsVLC === true`.

### 1.4 Xtream Codes Flow

`XtreamAPI` (in `utils/xtream.ts`) wraps the standard `player_api.php` endpoint. Endpoints used:

| Method | Action |
|---|---|
| `authenticate()` | `?username=…&password=…` (no `action`) returns `{ user_info, server_info }`; throws if `user_info.auth === 0` or missing |
| `getLiveCategories()` | `action=get_live_categories` |
| `getLiveStreams(catId?)` | `action=get_live_streams[&category_id=…]` |
| `getVodCategories()` | `action=get_vod_categories` |
| `getVodStreams(catId?)` | `action=get_vod_streams[&category_id=…]` |
| `getSeriesCategories()` | `action=get_series_categories` |
| `getSeries(catId?)` | `action=get_series[&category_id=…]` |
| `getShortEPG(streamId, limit=4)` | `action=get_short_epg&stream_id=…&limit=…` |
| `getSimpleEPG(streamId)` | `action=get_simple_data_table&stream_id=…` |

Stream URL builders (used to play without re-fetching):
- Live: `${base}/${user}/${pass}/${streamId}.${"ts" \| "m3u8"}`
- VOD: `${base}/movie/${user}/${pass}/${streamId}.${ext}`
- Series episode: `${base}/series/${user}/${pass}/${streamId}.${ext}`

Test-connection flow (`handleTest`):
1. Call `api.authenticate()`
2. Display success line: `"✓ {username} · {status} · Expires: {date|Never} · Max conn: {n}"`
3. If name field empty, default to `"{username} @ {hostname}"`

Save flow (`handleSave` for Xtream):
- Call `addSource({ name, type: "xtream", server, username, password })` — *does NOT load streams immediately*; only when source is later activated does `ContentContext.loadSource()` run authenticate + parallel category + stream + VOD + series fetches.

### 1.5 File Upload

- Library: `expo-document-picker` + `expo-file-system`
- Accepted MIME types: `audio/x-mpegurl`, `application/x-mpegurl`, `application/vnd.apple.mpegurl`, `video/mp2t`, `text/plain`, `application/octet-stream`, `*/*`
- Accepted extensions: **`.m3u`, `.m3u8`, `.txt`, `.ts`**
- `copyToCacheDirectory: true`, `multiple: false`
- After pick: read content via `FileSystem.readAsStringAsync(uri, "utf8")` (native) or `fetch(uri).text()` (web)
- Type detection: extension first, fallback to content sniffing (`startsWith("#EXTM3U")` → `m3u`)
- Parsing trigger: immediate `parseM3U(content)` call → throws `"No channels found in this file. Make sure it starts with #EXTM3U"` if zero
- Progress: `ActivityIndicator` swap inside the picker tile while reading
- Channel count surfaced in 3-cell stat strip below picker

### 1.6 Success / Error Feedback

- **Success after Save:** `router.back()` (no toast)
- **Connection success:** verified banner with green check + descriptive line
- **Errors:** red banner with descriptive text. Caught from:
  - `Fill in all Xtream fields`
  - `Invalid credentials`
  - `Invalid Xtream response — check server URL`
  - `HTTP {status} — check URL`
  - `No channels found — is this a valid M3U playlist?`
  - `Failed to read file`

### 1.7 Channel Count After Import

- For M3U file picker: `parseM3U()` runs synchronously after read; count rendered in a stats strip immediately
- For M3U URL & Xtream: count surfaced via verified banner during *test*; full count flows into `ContentContext.sources[].channelCount` on activation
- `parseM3U` enforces a hard cap **`MAX_CHANNELS = 1500`** to keep the JS bridge responsive
- YouTube and Twitch URLs (`https://www.youtube.com`, `https://www.twitch.tv`, `https://youtu.be`) are silently skipped (native player can't handle them)

---

## 2. `paywall.tsx` — Subscription Screen

### 2.1 Visual Layout

The screen is a `View` containing a `ScrollView` (no SafeAreaView wrapper for the hero — gradient bleeds into the status bar).

1. **Hero section** — `LinearGradient` from `#1a3a6b` (deep blue) to background black (top-down):
   - Top-right close button (`x` icon, 22 px, semi-transparent white)
   - 64×64 cherry primary square logo with rounded corners (radius 18), white "AW" text (Inter_700Bold 24 px, 1 letter-spacing)
   - Title: **"AwaTV Premium"** (28 px, white, Inter_700Bold, centered)
   - Subtitle: *"The ultimate IPTV experience — unlimited channels, live EPG, and more"* (14 px, white 65 %)

2. **Plan selector** (16 px horizontal padding, 10 px gap):
   - **Yearly tile** — radio + name "Yearly Plan" + sub-text "{$X}/month · billed annually" + price right + "Save 37%" green tag. **"BEST VALUE"** badge floats `top: -10` and uses gold (`#f59e0b`). Selected: 2 px cherry border + cherry-tinted background. Unselected: 1 px outline + card.
   - **Monthly tile** — radio + "Monthly Plan" + "Flexible, cancel anytime" + price `/mo`.

3. **Features card** — `card` background, border, 14 px padding, 16 px radius, 12 px gap.
   - Title: **"Everything included"**
   - 10 feature rows. Each row: 28×28 cherry-tinted square (icon center) + descriptive text.

4. **Error banner** (when `localError || purchaseError`).

5. **CTA section**:
   - Primary CTA — full-width 16 px vertical padding, 14 px radius, cherry, `zap` icon + label `"Start Yearly — $59.99"` (or Monthly variant). 70 % opacity while purchasing.
   - **"Restore purchases"** text-button below.
   - Legal copy fine print at bottom (10 px, border color).

6. **Confirmation modal** (transparent overlay, fade animation):
   - Card with cherry-tinted `shopping-bag` icon (60×60 round)
   - Title: "Confirm Purchase"
   - Body explains the plan + price; ends with *"This is a test purchase and no real money will be charged."*
   - Cancel + Confirm buttons in a row.

7. **Already-subscribed success state** (early return when `isSubscribed`):
   - Hero gradient (cherry 55 % → bg)
   - 80×80 green ring with `check` icon
   - **"You're Premium!"** title, "All features are unlocked. Enjoy AwaTV Premium." subtitle
   - "Continue" cherry button (14 px vertical padding)

### 2.2 Plan Options

Mock-mode prices from `lib/revenuecat.tsx`:

| Plan | Identifier | Product ID | Display | Annual equivalent |
|---|---|---|---|---|
| Monthly | `$rc_monthly` | `awatv_premium_monthly` | **$7.99** | — |
| Yearly | `$rc_annual` | `awatv_premium_yearly` | **$59.99** | $5.00/mo (Save 37 %) |
| Lifetime | *(not in Streas — added later in AWAtv RC variant B)* | — | — | — |

**Streas only ships monthly + yearly.** Lifetime is an AWAtv-side enhancement keyed off Remote Config (`paywallVariant === "B"` shifts Lifetime to top and pre-selects it).

### 2.3 Trial Period

**Streas does not ship a free-trial offer.** All purchase prompts go straight to the paid plan.

The AWAtv Flutter side has Remote-Config-driven `freeTrialDays` and shows *"premium.paywall.trial_line"* only when `selected != PremiumPlan.lifetime && rc.freeTrialDays > 0`. Recommended port behaviour: keep this hook and default `freeTrialDays = 3` to align with industry-standard 3-day trials.

### 2.4 Feature Highlights (Streas: 10 items)

From `PREMIUM_FEATURES` map in `lib/revenuecat.tsx`:

| Key | Feather icon | Description |
|---|---|---|
| `unlimited_sources` | `layers` | "Add unlimited M3U & Xtream playlists" |
| `epg_guide` | `calendar` | "Full 7-day EPG TV Guide" |
| `catch_up` | `rewind` | "Catch-up & Time-shift recording" |
| `pip` | `minimize` | "Picture-in-Picture mode" |
| `no_ads` | `shield` | "Ad-free experience" |
| `multi_screen` | `grid` | "Multi-screen view" |
| `quality_hd` | `star` | "4K / HDR stream support" |
| `download` | `download` | "Download for offline" |
| `chromecast` | `cast` | "Chromecast & AirPlay" |
| `parental` | `lock` | "Parental controls & PIN lock" |

### 2.5 Background / Imagery

- **Hero gradient:** `#1a3a6b` deep blue → background black (linear, top-bottom)
- **Already-subscribed success gradient:** cherry 55 % → background black
- No image assets — all glyphs are Feather icons
- "BEST VALUE" badge uses gold `#f59e0b`

### 2.6 Animations

- **Modal**: `animationType="fade"` for the confirm modal
- **Selection**: instant (no spring)
- **Loading buttons**: `ActivityIndicator`
- **Active LinearGradient overlay** on type cards uses `position: absoluteFillObject`
- No Reanimated / Lottie usage

### 2.7 Restore Purchases Flow

`handleRestore`:
1. Clear `localError`
2. Call `restore()` (mock: 600 ms delay → `_mockSubscribed` unchanged in demo, real RC will read `customerInfo`)
3. Catch & display error message via `localError`

The button shows `ActivityIndicator` while `isRestoring`.

### 2.8 Error Handling

- **Purchase failed**: caught from mock 800 ms `setTimeout` (real RC throws `PurchaseError`); only displayed if `!e.userCancelled` (the user-cancellation path is silent)
- **Network error during restore**: caught, displayed in same `errorBox`
- **Display layer**: single `errorBox` with `destructive` tint + `alert-circle` icon, prefers `localError ?? purchaseError.message ?? "Something went wrong"`

---

## 3. `PremiumGate` Component

### 3.1 When It Renders

Wraps any UI that is gated behind a `PremiumFeatureKey`. The check is `useSubscription().isSubscribed`. When `isLoading || isSubscribed`, the children are rendered untouched. Used at the call sites of any feature beyond the free tier:

- "Add additional source" button (after first/limit) → `feature: "unlimited_sources"`
- TV Guide tab opening → `feature: "epg_guide"`
- Catch-up rewind controls → `feature: "catch_up"`
- PiP toggle → `feature: "pip"`
- 4K / HDR badge in player settings → `feature: "quality_hd"`
- Download button on VOD detail → `feature: "download"`
- Chromecast button in player → `feature: "chromecast"`
- Parental PIN settings panel → `feature: "parental"`
- Multi-screen launcher → `feature: "multi_screen"`

### 3.2 Visual Treatment

Two render modes selected by the `overlay` prop:

**Mode A — Banner (default `overlay = false`)**: a 14 px padded card row with:
- 36×36 cherry-tinted square containing `lock` icon (20 px)
- Two-line text: bold "Premium Feature" (13 px) + muted feature description (11 px)
- Cherry "Upgrade" pill on the right (12 px horizontal × 6 px vertical, white bold "Upgrade" 11 px)
- Whole card is a `TouchableOpacity` → `router.push("/paywall")`
- 16 px outer margin

**Mode B — Overlay (`overlay = true`)**: wraps `children` in a relative-positioned view:
- Children rendered at 25 % opacity, `pointerEvents: "none"`
- Absolute-fill overlay (background + `cc` alpha = 80 %) with center-aligned column:
  - 22 px cherry `lock` icon
  - "Premium feature" title (13 px)
  - Cherry "Unlock" button (20 px horizontal × 8 px vertical)
- Tap "Unlock" → `router.push("/paywall")`

### 3.3 Tap Behavior

Both modes route to the paywall via Expo Router (`/paywall`). No toast, no haptic. The paywall, on success, navigates back via `router.back()` to the gated screen.

### 3.4 `usePremium()` Helper Hook

```ts
const { isPremium, isLoading } = usePremium();
```
Exposes a one-line helper around `useSubscription()` for non-render checks.

---

## 4. Data Flow

### 4.1 M3U Parsing → Channel List

`parseM3U(content, limit = 1500)` in `utils/m3u.ts`:

1. Split on `\n`, trim, drop blanks
2. Validate `lines[0]?.startsWith("#EXTM3U")` (else return `[]`)
3. Iterate; for each `#EXTINF:…,…` line:
   - Walk forward through subsequent `#`-prefixed `#EXT*` directives
   - Find first non-`#` line → that's the URL
   - Skip if URL starts with YouTube/Twitch prefixes
   - Extract attrs via regex `tvg-id="…"`, `tvg-name="…"`, `tvg-logo="…"`, `group-title="…"`
   - Channel name = comma-split tail of `#EXTINF` line (`split(",").slice(1).join(",").trim()`)
   - Push `{ id, name, logo, group, tvgId, tvgName, url }`
4. Stop at `MAX_CHANNELS = 1500`

`generateMockEPG(channels)` synthesises 10 fake EPG entries per channel covering past 2 hours + future, randomly choosing duration `[30, 60, 90, 120]` minutes and rotating through genre-specific program names (`News`, `Sports`, `Entertainment`, `Kids`, `Music`, `Movies`).

### 4.2 Xtream Codes API Endpoints

See section 1.4. Live URL pattern: `${base}/${user}/${pass}/${streamId}.ts` (or `.m3u8`). Token caching is **not** implemented in Streas — each `XtreamAPI` instantiation re-authenticates on demand.

### 4.3 Source Storage

Persistence: `AsyncStorage` keys defined in `ContentContext.tsx`:

| Key | Stores |
|---|---|
| `awatv_my_list` | VOD "my list" |
| `awatv_sources` | All `PlaylistSource[]` (full M3U content for local files included) |
| `awatv_favorites` | Channel ID array |
| `awatv_recent_channels` | Last 20 channels played |
| `awatv_settings` | `AppSettings` object |
| `awatv_channels` | (declared but unused in current code) |

**Supabase sync:** `lib/supabase.ts` exists in the repo but is **not currently wired** through `ContentContext`. The full `PlaylistSource` interface includes `url`/`serverUrl` aliases marked "sync compat" — these are placeholders for future sync. No row-level operations occur here.

`addSource` flow:
1. Generate `id = src_${Date.now()}`
2. `isActive = false` initially
3. Append to `sources` state
4. Persist via `saveSources(next)` → `AsyncStorage.setItem(KEYS.SOURCES, JSON.stringify(next))`

`activateSource(id)`:
1. Set `isActive = true` on target, false on all others
2. Persist
3. Call `loadSource(target)` which:
   - For M3U: fetch URL → parse → set `channels` + `epgPrograms` (mock EPG), update `channelCount` + `lastUpdated`
   - For Xtream: parallel `authenticate()` + `getLiveCategories()` → `getLiveStreams()` → `streamsToChannels()`. Then in background, parallel VOD + Series fetches. Sets `xtreamUserInfo`, `xtreamVods`, `xtreamSeries`.
4. On error, fall back to `DEMO_CHANNELS` (25 hard-coded news/sports/entertainment fixtures)

`addSourceFromFile(file)`:
1. Parse content
2. Build `PlaylistSource` with `type: "local_file"`, raw content stored in `localFileContent`
3. Deactivate other sources, activate this one
4. Persist + set channels + EPG

### 4.4 RevenueCat Purchase Flow

Currently a **pure mock** (`lib/revenuecat.tsx`). Architecture:

- Wrapped by `<SubscriptionProvider>` at app root (uses TanStack Query under the hood)
- `useQuery(["revenuecat","customer-info"])` returns synthetic entitlements (`_mockSubscribed` module-level boolean)
- `useQuery(["revenuecat","offerings"])` returns frozen `MOCK_OFFERINGS` with monthly + annual packages
- `useMutation` for purchase: 800 ms delay → set `_mockSubscribed = true` → invalidate queries
- `useMutation` for restore: 600 ms delay, no-op (mock)

**Production switch (per code comment):**
- Connect RevenueCat connector in Replit integrations
- Run `scripts/src/seedRevenueCat.ts`
- Set env vars: `EXPO_PUBLIC_REVENUECAT_TEST_API_KEY`, `EXPO_PUBLIC_REVENUECAT_IOS_API_KEY`, `EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY`
- Replace mock hooks with real `react-native-purchases` calls; entitlement identifier is `premium`

### 4.5 `isSubscribed` Flag Propagation

- `useSubscription().isSubscribed` is computed from `customerInfo.entitlements.active.premium`
- Read directly in:
  - `<PremiumGate>` (gates wrapping UI)
  - `usePremium()` (free-form checks)
  - `paywall.tsx` (early-returns to success state)
- After `purchase()` resolves, query invalidation → all consumers re-render and unlock simultaneously

---

## 5. Flutter Port Mapping

### 5.1 Current Flutter Surface

Existing in `/Users/max/AWAtv/apps/mobile/lib/src/features/`:

```
playlists/
├── add_playlist_screen.dart   ← MAPS TO add-source.tsx
├── playlists_screen.dart
├── playlist_providers.dart
└── playlist_providers.g.dart  (Riverpod codegen)

premium/
├── premium_screen.dart        ← MAPS TO paywall.tsx
├── premium_lock_sheet.dart    ← MAPS TO PremiumGate.tsx
└── premium_badge.dart         ← AWAtv-only PRO pill
```

Foundation pieces already implemented in AWAtv:
- `PlaylistSource` model with `PlaylistKind { m3u, xtream, stalker }` (Streas lacks Stalker; AWAtv has 3)
- `playlistServiceProvider` with `add()` that persists + triggers initial sync
- `XtreamAuthException`, `StalkerAuthException`, `PlaylistParseException`, `NetworkException` (typed errors)
- `premiumStatusProvider` with `simulateActivate(plan)` until RC ships
- Remote-Config plumbing (`appRemoteConfigProvider`) with paywall variant A/B
- `BrandColors.brandGradient`, `BrandColors.auroraGradient`, `DesignTokens.*` (radii, spacing, motion durations, blur sigmas)
- `PremiumLockSheet.show(context, feature)` glassmorphism modal

### 5.2 Streas → Flutter Screen Mapping

| Streas | AWAtv Flutter | Status |
|---|---|---|
| `app/add-source.tsx` | `features/playlists/add_playlist_screen.dart` | **Exists** — needs File-Upload tab + sample-playlist preset list + 18-format detection |
| `app/paywall.tsx` | `features/premium/premium_screen.dart` | **Exists** — already richer (3 plans, A/B variants, two-column desktop layout) |
| `components/PremiumGate.tsx` | `features/premium/premium_lock_sheet.dart` | **Exists as bottom-sheet** — Streas overlay+banner modes need adding |
| `lib/revenuecat.tsx` | `shared/premium/premium_status_provider.dart` | **Stub exists** — RevenueCat SDK not yet integrated |
| `utils/m3u.ts` | `awatv_core` package M3U parser | **Exists** (used by `playlistServiceProvider`) |
| `utils/xtream.ts` | `awatv_core/StalkerClient` + `XtreamClient` (in core) | **Exists** |
| `utils/fileUpload.ts` | *(not yet implemented)* | **MISSING** |
| `constants/colors.ts` | `awatv_ui/BrandColors` | **Exists** — different palette (brand gradient vs. cherry red) |

### 5.3 What's Missing in Flutter

1. **File upload tab** — Streas's third source type (`Local File`) is not in `add_playlist_screen.dart`. Needs:
   - `file_picker` package (cross-platform) with extensions `["m3u","m3u8","txt","ts"]`
   - Read-as-string with `dart:io File.readAsString()` (encoding `utf8`)
   - Local content persistence (mobile: write to `path_provider.getApplicationDocumentsDirectory()`; the in-memory `localFileContent` field can stay on `PlaylistSource`)
   - Format detection helper mirroring `detectStreamFormat`

2. **Sample playlist presets** — The 5 hard-coded IPTV-Org / Free-TV cards in Streas's M3U tab. AWAtv has none. Add as `SAMPLE_PLAYLISTS` const list and render cards under the M3U URL field.

3. **Test connection button** — Streas runs a probe before save. AWAtv only has `_probeStalker` for the Stalker variant. Add equivalents:
   - M3U URL → fetch + parse + report channel count
   - Xtream → call `XtreamClient.authenticate()` + show username/expiry/max-connections

4. **18-format `StreamFormatRegistry`** — port `ALL_STREAM_FORMATS` to `awatv_core/lib/src/streaming/stream_format.dart` with VLC / MX Player / nPlayer intent builders. Use `url_launcher` package for deep-link fallback when `needsVlc == true`.

5. **`react-native-purchases` → `purchases_flutter`** — replace `simulateActivate` with the real `Purchases.configure()`, `getOfferings()`, `purchasePackage()`, `restorePurchases()`. Entitlement key remains `premium`.

6. **`PremiumGate` overlay/banner widget variants** — `premium_lock_sheet.dart` is bottom-sheet only. Add inline equivalents matching Streas's two visual modes.

### 5.4 Recommended Widget Tree Skeleton

#### `add_playlist_screen.dart` (extended)

```
Scaffold
├── AppBar
│   ├── leading: IconButton(close)
│   ├── title: "Add Playlist"
│   └── actions: [ FilledButton("Save", onPressed: canSave ? submit : null) ]
└── body: SafeArea > AbsorbPointer(absorbing: busy)
    └── SingleChildScrollView
        └── Form(key: _formKey)
            ├── _SourceTypeGrid(selected: kind, onChanged: setKind)
            │   └── 3× _TypeCard(icon, label, desc, isActive)
            │       (tab variants: m3u | xtream | file)   ← NEW: file
            ├── _NameField                                ← always visible
            ├── if (kind == m3u) _M3uForm
            │     ├── InfoNote
            │     ├── TextFormField(m3uUrl)
            │     ├── TextFormField(epgUrl, optional)
            │     └── _SamplePlaylistsList                ← NEW
            ├── if (kind == xtream) _XtreamForm
            │     ├── InfoNote
            │     ├── TextFormField(server)
            │     ├── _LocalDiscoveryPanel                ← already exists
            │     ├── TextFormField(username)
            │     └── TextFormField(password, obscureText)
            ├── if (kind == file) _FileForm               ← NEW
            │     ├── InfoNote
            │     ├── _FilePickerTile(onTap: pickFile)
            │     └── if (parsed) _FileStatsRow(channels, size, format)
            ├── if (kind != file) _TestConnectionButton   ← NEW
            ├── if (verifiedInfo != null) _SuccessBanner
            ├── if (error != null) _ErrorBanner
            └── _BottomInfoCard(kind: kind)
```

State (Riverpod):
- Reuse `PlaylistKind` enum, extend with `file` value
- New `selectedFileProvider` (StateProvider<PickedPlaylistFile?>)
- New `verifiedSourceProvider` (StateProvider<String?>)

Submit handler (`_submit`):
- For `file` kind: call `playlistServiceProvider.addLocalFile(name, content)`
- Otherwise existing M3U / Xtream paths

#### `premium_screen.dart` (already implemented)

Existing tree is more sophisticated than Streas (two-column adaptive layout, 9 bullet rows, 3 plans, hero illustration, RC variant B reordering). Streas-specific items to merge:
- Add `Confirm Purchase` modal (`showDialog`) before calling `simulateActivate` to mirror Streas's confirmation step
- Surface "Save 37 %" badge on yearly tile (already partially via `_BrandBadge`)
- Add the **already-subscribed success state** when `tier is PremiumTierActive` immediately after CTA tap (currently only shows the inline `_ActiveBanner`)

#### `PremiumGate` Flutter widget (new + bottom-sheet existing)

```dart
class PremiumGate extends ConsumerWidget {
  final PremiumFeature feature;
  final Widget child;
  final bool overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(premiumStatusProvider);
    if (tier.isLoading || tier.isActive) return child;

    if (overlay) {
      return Stack(
        children: [
          IgnorePointer(
              ignoring: true,
              child: Opacity(opacity: 0.25, child: child)),
          Positioned.fill(child: _OverlayContent(feature: feature)),
        ],
      );
    }
    return _GateBanner(feature: feature);
  }
}
```

`_GateBanner`: row with cherry-tinted lock square + title + subtitle + cherry "Upgrade" pill. `onTap` calls `context.push('/premium')`.
`_OverlayContent`: centered column over translucent surface (background `withValues(alpha: 0.8)`); large lock icon + "Premium feature" + cherry "Unlock" button.

`PremiumLockSheet.show(context, feature)` remains the modal variant; gate widget can call it on tap instead of routing for less context loss when wrapping UI in a list.

### 5.5 Provider / Service Wiring

```
Riverpod providers (mostly exist already):
  playlistServiceProvider     ← extended: addLocalFile(name, content)
  playlistsProvider           ← rebuilds on add
  allChannelsProvider         ← rebuilds on add/activate
  premiumStatusProvider       ← swap from simulateActivate to purchases_flutter
  selectedPlanProvider        ← already exists
  appRemoteConfigProvider     ← already exists, drives variant + trial days
  localIptvDiscoveryProvider  ← already exists for Xtream auto-fill
```

New helpers:

```
fileFormatRegistryProvider  → static list of 18 StreamFormat objects
streamLauncherProvider      → wraps url_launcher for VLC/MX/nPlayer fallbacks
samplePlaylistsProvider     → static list of 5 IPTV-Org / Free-TV presets
```

### 5.6 Persistence Strategy

Streas uses raw JSON in AsyncStorage. AWAtv should keep its existing pattern (presumed Drift/Isar/SharedPreferences via `playlistServiceProvider`). The `localFileContent` field is the only memory hog — for AWAtv recommend writing the picked file to documents-directory and storing the **path**, not the contents, in `PlaylistSource`. This avoids a 2-5 MB string sitting in the database for big playlists.

### 5.7 Testing Surface

Flutter port tests to add:

| Test | Target |
|---|---|
| Widget — add screen renders 3 (or 4 with file) source-type cards | `add_playlist_screen_test.dart` |
| Widget — switching tabs clears form errors | same |
| Widget — Test Connection success/failure banners | same |
| Unit — M3U parser respects `MAX_CHANNELS`, skips YouTube/Twitch | `m3u_parser_test.dart` |
| Unit — `detectStreamFormat` covers all 18 formats + falls back to HLS | `stream_format_test.dart` |
| Unit — XtreamClient encodes URL exactly: `…/player_api.php?username=…&password=…&action=…` | `xtream_client_test.dart` |
| Widget — Paywall renders 3 plan tiles, selects yearly by default | `premium_screen_test.dart` |
| Widget — Confirm purchase modal flow → activate → success banner | same |
| Widget — `PremiumGate` overlay mode dims children + shows Unlock | `premium_gate_test.dart` |
| Integration — `pickFile()` reads sample.m3u → 25 channels parsed | platform_test |

---

## 6. Migration Effort Summary

| Area | Effort | Notes |
|---|---|---|
| Add-source UI restructure (3 → 3 or 4 tabs) | **M** | File-upload tab is the new piece; existing m3u + xtream forms map cleanly |
| File-picker integration | **S** | `file_picker` package + path_provider; ~100 lines |
| Sample playlist presets | **XS** | Static list + scrollable cards |
| Test-connection button | **S** | Existing clients already support `authenticate()` and `fetch()` |
| 18-format registry | **S** | Static list + 1 detection function; copy verbatim from `fileUpload.ts` |
| Paywall confirm modal | **XS** | `showDialog` wrapper |
| `PremiumGate` widget | **S** | Two simple variants; existing bottom sheet stays |
| RevenueCat real integration | **L** | `purchases_flutter` config + entitlement plumbing + iOS/Android product setup + receipt validation; *do not stub-out indefinitely* |
| Supabase sync of `PlaylistSource` | **L** | Cross-cutting; out-of-scope for this spec but worth flagging — Streas already has fields aliased for it (`serverUrl`, `url`) |

Total estimated work for everything in this spec, excluding RevenueCat production wiring and Supabase sync: **~4-6 days for one Flutter dev**.

---

## 7. Reference Snippets

### 7.1 PlaylistSource shape (Streas)

```ts
interface PlaylistSource {
  id: string;
  name: string;
  type: "m3u" | "xtream" | "local_file";
  isActive: boolean;
  channelCount?: number;
  lastUpdated?: number;
  m3uUrl?: string;
  url?: string;        // sync alias
  epgUrl?: string;
  localFileName?: string;
  localFileContent?: string;
  server?: string;
  serverUrl?: string;  // sync alias
  username?: string;
  password?: string;
  userInfo?: XtreamUserInfo;
}
```

### 7.2 PlaylistKind (existing in AWAtv)

```dart
enum PlaylistKind { m3u, xtream, stalker }
// → recommend extending: enum PlaylistKind { m3u, xtream, stalker, localFile }
```

### 7.3 Cherry palette → AWAtv brand mapping

| Streas (`constants/colors.ts`) | AWAtv (`BrandColors`) | Notes |
|---|---|---|
| `primary: #E11D48` (cherry crimson) | `BrandColors.primary` | AWAtv brand differs — keep AWAtv's, but Streas hex is canonical for the IPTV-app reference design |
| `gold: #f59e0b` | `BrandColors.secondary` | Used for "BEST VALUE" badge |
| `destructive: #ef4444` | `BrandColors.error` | Error banners |
| `card: #141414` | `theme.colorScheme.surfaceContainer` | Tile backgrounds |
| `border: #282828` | `theme.colorScheme.outlineVariant` | Hairline strokes |
| `mutedForeground: #808080` | `theme.colorScheme.onSurfaceVariant` | Secondary text |

---

**End of spec.**
