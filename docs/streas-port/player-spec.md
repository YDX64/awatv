# Streas → AWAtv Flutter Port Spec — Player & Detail Screens

Source repo (RN/Expo): `/tmp/Streas/artifacts/iptv-app/`
Target repo (Flutter): `/Users/max/AWAtv` (existing `awatv_player` package + `apps/mobile/lib/src/features/player/player_screen.dart`)
Scope: **Player screens (live TV + VOD) + Detail page + Subtitle picker + SubtitleOverlay**. Auth, browse, settings are out of scope.

This document is the implementation contract: every visual measurement, color, animation timing, behavior branch, and data flow needed to reproduce Streas's player layer in Flutter.

---

## 0. Design system constants

From `constants/colors.ts`. All values must port verbatim into the Flutter design tokens.

| Token | Hex | Purpose |
|---|---|---|
| `primary` / `tint` / `accent` / `live` / `tag` / `focus` | `#E11D48` | Cherry crimson — primary action, LIVE badge, active state, accent borders |
| `primaryDark` | `#9F1239` | Pressed/dim variant |
| `primaryDim` (`CHERRY_DIM`) | `#BE123C` | Subtle accent |
| `background` | `#0a0a0a` | Root scaffold |
| `foreground` / `text` / `cardForeground` | `#ffffff` | All foreground text on dark |
| `card` | `#141414` | Card surfaces, secondary buttons |
| `surface` | `#111111` | Channel logo placeholders |
| `surfaceHigh` / `secondary` / `muted` | `#1c1c1c` | Genre tags, muted blocks |
| `mutedForeground` | `#808080` | Meta text, captions |
| `border` / `input` | `#282828` | Hairlines, dividers, input borders |
| `destructive` | `#ef4444` | Error toasts |
| `gold` | `#f59e0b` | Favorited state, ratings |
| `radius` | `8` | Default card radius |

Typography: Inter family — weights `400 Regular`, `500 Medium`, `600 SemiBold`, `700 Bold`. The `.tsx` files reference `Inter_400Regular`, `Inter_500Medium`, `Inter_600SemiBold`, `Inter_700Bold` — map to Flutter `FontWeight.w400/w500/w600/w700` with `GoogleFonts.inter()` or bundled Inter.

The cherry-red theme already exists in AWAtv (`apps/mobile/lib/src/theme/`); validate parity and patch as needed.

---

## 1. Live TV Player Screen — `app/tv-player.tsx`

### 1.1 Visual layout

The screen has **three responsive variants** triggered by `useWindowDimensions()`:

- **Phone portrait** (`width < height`, `width < 768`): vertical split — 16:9 video on top, info+controls panel below
- **Phone landscape** (`width > height`, `width < 768`): full-screen video with overlaid top/bottom bars
- **Tablet landscape** (`width >= 768` && landscape): video occupies `width * 0.65`, EPG side panel on right (`width * 0.35`)

#### Video container

| Mode | Width | Height |
|---|---|---|
| Phone portrait | `screenWidth` | `screenWidth * 9/16` |
| Phone landscape | `screenWidth` | `screenHeight` |
| Tablet landscape | `screenWidth * 0.65` | `screenHeight` |

Background: solid `#000`. `contentFit: "contain"` (letterbox). `nativeControls={false}` — fully custom overlay.

#### Top bar (auto-hide, in landscape and over-video portrait)

`LinearGradient` from `rgba(0,0,0,0.82)` → `transparent`, top→bottom, padding-top `safeAreaTop + 8` in landscape (zero on web). Layout `Row`:

- Back button: `chevron-down` icon, 24px, white, in 38×38 hit area.
- Title block (`flex: 1`):
  - Channel name: 15px Inter Bold, white, `numberOfLines: 1`.
  - Program (landscape only): 11px Inter Regular, `rgba(255,255,255,0.65)`, single line.
- Right cluster:
  - "Open with" icon (`monitor`, 20px white) — opens external player menu.
  - Subtitle icon (`type`, 20px) — primary if subtitles enabled, else white. When active, 8px-radius pill background `rgba(225,29,72,0.2)`.

Below the top bar: subtitle label bar (`subLabelBar`) at `top: 56`. Centered row: `type` icon (12px primary), label text 11px Inter SemiBold primary, then `x` close button → `clearSubtitles()`. Rendered only when `subtitleLabel !== "Off"`.

#### LIVE indicator (always-on, top-left corner of video)

Position: `top: 12, left: 12` (or `safeAreaTop + 8` in landscape). Background `#E11D4899` (primary @ 60% alpha), 8px-pad, 6px-radius. Inside: 6×6 white circle dot + "LIVE" text in 10px Inter Bold, 1px letter-spacing.

#### Center controls (landscape only)

Absolute centered `Row` with `gap: 40`:

- "CH–" group: `skip-back` icon 28px white, label "CH–" 10px Inter SemiBold under it.
- Play/pause button: 64×64 circle, `rgba(255,255,255,0.15)` background, 34px icon centered.
- "CH+" group: `skip-forward` icon 28px + "CH+" label.

#### Bottom bar (landscape — overlaid; portrait — separate panel)

Landscape: `LinearGradient` from `transparent` → `rgba(0,0,0,0.92)` (top→bottom inversed at bottom), padding 14, gap 10. Children:

1. **Current EPG row** (if program exists):
   - Left (flex 1): title 13px Inter SemiBold white + time line "21:00 – 22:30 · 1h 30m" 10px Inter Regular `rgba(255,255,255,0.6)`.
   - Right: "%72" 11px Inter Regular `rgba(255,255,255,0.5)`.
2. **Progress bar**: 3px tall, 2px corner-radius. Background `rgba(255,255,255,0.2)`. Fill width = `progress * 100%`, color primary.
3. **Bottom actions row** (`space-between`):
   - Volume group (left, `flex: 1`): mute button (`volume-x | volume-1 | volume-2`, 22px white) + collapsible 100px-max volume bar (3px tall, primary fill).
   - Center play row (`gap: 4`): `skip-back` 20px @ 70% white → 44×44 circular play/pause (`rgba(255,255,255,0.18)`, 24px icon) → `skip-forward` 20px.
   - Right cluster: favorite star 22px (`gold` if favorited, else white) + list `list` 22px (toggle sidebar).

#### Portrait info panel (below video)

Background `#0d0d0d`, padded `paddingHorizontal: 16, paddingTop: 12`, `paddingBottom: insets.bottom + 8`, gap 10:

1. Channel row: channel name (16px Inter Bold) + group name (11px regular @ 45% alpha) on left; right: `monitor` + `type` icons (20px @ 70% alpha).
2. EPG box: 1px-hairline border (`colors.border`), 10px radius, 12px pad. Title (13px SemiBold) + time line (11px @ 50%) on left, percentage badge on right (13px Bold primary). Empty state shows "No program info available".
3. Same `bottomControls` row used in landscape.

#### Channel sidebar (slide-in drawer)

Position: absolute right, 260px wide, `top: 0` to `bottom: 0`, background `rgba(10,10,10,0.97)`, `borderLeftWidth: 1` color `border`. Z-index 30. Animated `translateX` from `300` to `0` with spring (tension 60, friction 10).

Header: "Channels" 15px Inter Bold + close `x` 20px. `paddingTop: safeAreaTop + 12`. 1px hairline bottom.

Items (`FlatList`):
- 60ish-pixel-tall row, `paddingVertical: 10`, `paddingHorizontal: 12`.
- 3px left border: primary if active, else transparent.
- Background: `colors.primary + "22"` (~13% alpha) if active, else transparent.
- Logo box: 44×34, 6px radius, `colors.surface`. Image inside (32×24, `contain`) or initial letter (16px Bold primary) fallback.
- Name 12px SemiBold (primary if active, else white).
- Current program 10px regular @ 45% alpha.
- 6×6 primary dot at right if active.

#### Tablet right panel (only `landscape && tablet`)

Width: `screenWidth - playerWidth` (~35%). Background `#0a0a0a`, 1px left border.

- **Header**: channel name 16px Bold + LIVE badge (10px Bold, primary background, 5px radius).
- **Current program box**: 10px-radius card, 12px pad, 1px border. Title 14px Bold white, time 11px Regular muted, optional 3-line description 12px Regular muted, line-height 17.
- **"UP NEXT"** label: 10px Bold, 1.5 letter-spacing, muted, `paddingHorizontal: 16, paddingTop: 4`.
- **Scrollable program rows**: each row `Row` with 12px gap, 16px hPad, 10px vPad, hairline bottom border. Time column 11px Bold primary, fixed width 42. Title 12px Regular white, 2 lines.
- **Tablet actions** (sticky at bottom, 12px pad, top hairline): two equal-flex buttons with row-icon-text layout, 10px vPad, 10px radius, 1px border. Star = `gold + "22"` bg if favorited else `card`. Subtitles button = `card` bg, primary icon+text.

#### Auto-hide timing

UI starts visible. After **5000 ms** of no taps → fade out via `Animated.timing(uiOpacity, 600ms)`. Tap on video `→ showUIHandler`: opacity 1 instantly (200ms), restart 5000ms timer.

#### External player menu

Absolute box, `top: 48, right: 8, width: 210`. 12px radius, 1px primary-ish border, background `rgba(10,10,10,0.97)`. Header label "OPEN WITH" 10px Bold muted, 1px tracking. Items: row with 16px play-circle icon + 13px Medium label. Active row: primary @ 13% alpha background, primary text. "internal" entry shows a "CURRENT" pill (primary bg, 8px Bold white, 0.5 letter-spacing).

#### Errors & toasts

- Stream load error overlay: full-fill `rgba(0,0,0,0.7)`, centered alert-circle 36px @ 40% alpha + 13px message + 11px sub "Playing demo stream".
- External player launch error toast: bottom 90px from bottom, `destructive` background, 10px radius, 12px pad. Auto-dismiss on tap.

### 1.2 Behavior

#### Player engine

`expo-video`'s `useVideoPlayer(src, init)` configured with `loop=true, muted=false`, autoplays on mount. On channel change: `player.replace({ uri: newUrl }); player.play()`.

Stream URL comes from `M3UChannel.url`. Format detection is **delegated to expo-video** (HLS .m3u8, MPEG-TS, etc.); when none provided, fallback `DEMO_STREAM = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"` is used.

#### Internal vs External

`PlayerType = "internal" | "vlc" | "mxplayer" | "nplayer" | "external"`. Default is internal. Tap "OPEN WITH" to choose:

- **vlc**: iOS → `vlc://<url>`; Android → `intent:<url>#Intent;package=org.videolan.vlc;type=video;end`.
- **mxplayer** (Android only): `intent:<url>#Intent;package=com.mxtech.videoplayer.ad;type=video;end`.
- **nplayer** (iOS only): `nplayer-<url>`.

Uses `Linking.canOpenURL` then `Linking.openURL`. On failure → red error toast `${PLAYER_TYPE_LABELS[type]} is not installed`.

#### Channel switching

`switchChannel(±1)` → bounded by `[0, channels.length-1]`. Side effects: `setActiveChannel`, `addRecentChannel`, `Haptics.impactAsync(Light)` on native, then `router.replace({ pathname: "/tv-player", params: { channelId } })`.

#### Subtitle button → picker

Pushes `/subtitle-picker` with `params: { title: currentProgram?.title || channel?.name }`. Returns to player; subtitles then render via `SubtitleOverlay` reading from `SubtitleContext`.

#### Watch position

Live TV does **not** save watch positions (no `saveWatchPosition` calls in `tv-player.tsx`). EPG progress is computed from wall-clock time (`Date.now()` vs program start/end) — purely cosmetic.

#### Background play / PiP / Cast

None present in this RN version.

#### Gestures

Only single-tap (toggle UI). No double-tap-seek, pinch-zoom, swipe brightness/volume in code, **but** `PlayerSettings` defines `doubleTapSeek=10`, `swipeVolume=true`, `swipeBrightness=true` — these are intended-but-unimplemented in RN. **Flutter port should implement them** (see §6).

### 1.3 Data flow

State (local `useState`):

- `showUI: bool` (default true) + `uiOpacity: Animated.Value(1)`
- `showSidebar: bool` + `sidebarX: Animated.Value(300)` (off-screen right)
- `showPlayerMenu: bool`
- `isPlaying: bool` (mirrors player; user-controlled toggle)
- `volume: number` (0–1, default 0.8) + `isMuted: bool`
- `showVolumeBar: bool`
- `externalError: string | null`, `videoError: string | null`

Two `useEffect` syncs:
1. `[isPlaying] → player.play() / player.pause()`
2. `[isMuted, volume] → player.muted/volume`

Channel change effect: `[channel?.id] → player.replace + play`.

Context reads: `useContent()` (channels, EPG, favorites, recents), `useSubtitle()` (settings + state).

---

## 2. VOD Player Screen — `app/player/[id].tsx`

### 2.1 Visual layout

This is the **lighter** placeholder player (RN scaffolding, no real `expo-video` wired yet — uses `<View>` placeholder with text). Flutter port should still match the layout, **but back the surface with the same `awatv_player` engine used by Live TV**.

Full-screen black scaffold. Tap to toggle controls overlay.

#### Top bar

`paddingTop: safeAreaTop + 6, paddingHorizontal: 16, paddingBottom: 10`. Row layout:
- Back: `chevron-down` 26px white.
- Title (centered, `flex: 1`, hMargin 10): 15px Inter SemiBold white, 1 line.
- More: `more-horizontal` 22px white.

#### Center controls

Centered Row, gap 40:
- Skip-back-10 group: `rotate-ccw` 28px white + "10" 10px SemiBold under it (positioned at `bottom: -4`).
- Play/pause button: **72×72** circle (larger than live TV's 64), bg `rgba(255,255,255,0.15)`, 36px icon.
- Skip-forward-10 group: `rotate-cw` 28px + "10" label.

Skip granularity: `progress ± 0.05` (5% of total). VOD playback total is hardcoded to 3600s (60 minutes) in `formatTime` — Flutter port should drive this from real `duration`.

#### Bottom bar

`paddingHorizontal: 16, paddingBottom: insets.bottom + 20, gap: 14`:

1. Progress row: `[currentTime] [trackBar] [duration]`. Time text 11px Medium @ 70% alpha, fixed-width 35. Track: 20px tall hit area, with a 3px-tall background bar `rgba(255,255,255,0.3)`. Fill bar primary, position-by-percent. Thumb: 12×12 primary circle, top -4.5, marginLeft -6 (so it center-aligns to the percent point). Tap-on-track seeks to that proportion.
2. Bottom icons row: `flex-end`, gap 22:
   - Volume `volume-2` 20px (no bar shown here, unlike live TV).
   - Subtitles `message-square` 20px.
   - Settings `settings` 20px.
   - Maximize `maximize` 20px.

### 2.2 Behavior

- Auto-hide: 3000ms after starts playing (vs 5000 in live TV). Hide animation 400ms. Show animation 200ms.
- Pause → keep controls visible.
- Haptics on play/pause: `Haptics.impactAsync(Light)`.
- Stream loading: not wired in RN (placeholder shows "▶ {title}" when paused).

### 2.3 Data flow

- `isPlaying`, `progress: 0.25` (defaults to mid-position fake), `showControls`, `volume: 0.8`.
- Reads `ALL_CONTENT` synchronously to pull title.
- **Watch positions**: NOT wired here either, despite `syncService.ts` existing. Flutter port should call `syncService.saveWatchPosition` every 10 seconds during playback (see §5).

---

## 3. Detail Screen — `app/detail/[id].tsx`

### 3.1 Visual layout

Vertical scroll. No safe-area top — banner extends under status bar.

#### Banner

Height **280px**. `Image` with `resizeMode: cover`, source `item.banner ?? item.thumbnail`. Overlaid 35%-black gradient (`rgba(0,0,0,0.35)` flat, not gradient).

Floating back button: absolute `top: insets.top + 10, left: 16`. 40×40 circle, `rgba(0,0,0,0.6)` bg, `chevron-left` 26px white.

#### Content section (padding 20, gap 12)

1. **NEW badge** (if `item.isNew`): 8px hPad, 3px vPad, 4px radius, primary bg, 10px Bold "NEW" text 1px letter-spacing.
2. **Title**: 26px Inter Bold, foreground.
3. **Meta row** (Row, gap 10, marginTop -4):
   - Year: 13px Regular muted.
   - Rating badge ("TV-14"): 1px border, 6×2 pad, 3px radius, 11px Medium muted.
   - Duration: 13px Regular muted.
4. **Genres row** (Row wrap, gap 6):
   - Tags: 10×4 pad, 12px radius, `secondary` bg, 12px Medium muted.
5. **Primary Play button**: full-width Row, 14px vPad, 8px radius, primary bg, marginTop 4. Children: `play` 20px white + "Play" 16px Bold.
6. **Secondary actions row** (Row, gap 10, three flex-1 buttons): each is column-laid 18px icon + 11px Medium label, 10px vPad, 8px radius, 1px border, `card` bg.
   - "My List" / "In My List" — toggles `addToList`/`removeFromList`. Icon swaps `plus` ↔ `check`.
   - "Download" (no behavior wired).
   - "Share" (no behavior wired).
7. **Description**: 14px Regular muted, lineHeight 22.
8. **"More Like This"** section: 16px SemiBold heading, then horizontal `ScrollView` with negative -20 hMargin. Each card 110px wide, 10px right margin: 110×165 thumbnail (8px radius, `card` bg), then 11px Medium title 1 line.

No cast/crew, no trailer button — these are absent in Streas RN. Flutter port should treat them as future enhancements (see §7 gap analysis).

### 3.2 Behavior

- Play: `router.push('/player/[id]', { id, title })`.
- My List: `Haptics.impactAsync(Light)` then toggle.
- More-Like-This card tap: `router.replace('/detail/[id]', { id })` (replaces in stack).

### 3.3 Loading / buffering / error states

- No skeletons in current RN (page renders synchronously from `ALL_CONTENT`). Flutter port should add 280-tall shimmering banner placeholder + skeleton bars for title, meta, genres, action buttons while data loads.
- No buffering UI — instant render.
- Fallback when `id` not found: hardcoded "Unknown Title" item with picsum thumbnail. Flutter port should show a proper error empty state instead.

---

## 4. Subtitle Picker Screen — `app/subtitle-picker.tsx`

### 4.1 Visual layout

Modal-style screen pushed over player.

**Header**: 1px hairline bottom, `paddingTop: insets.top + 12, paddingBottom: 14`. Row: `x` close 22px (left, 36×36 hit) — "Subtitles" 17px Inter Bold (center) — empty 36×36 spacer (right).

**Premium banner** (only if `!isSubscribed`): 16px margin, 12px radius, 1px primary @ 33% alpha border, primary @ 9% alpha bg. Row: `lock` 16px primary + (title "Premium Feature" 13px Bold + sub "Upgrade to download subtitles from OpenSubtitles.com" 11px Regular muted) + "Upgrade →" 12px Bold primary. Tap → `/paywall`.

**Search bar** (16px hMargin, 16px topMargin, 12px radius, 1px border, 14×12 inner pad, `card` bg): `search` 16px muted icon + `TextInput` (14px Regular foreground, placeholder muted) + `x` clear when query non-empty.

**Language selector row** (16px hMargin, 10px topMargin, 12px radius, 1px border, `card` bg, 14×12 pad): `globe` 16px primary + selected language native name (e.g. "Türkçe") 14px Medium + chevron-up/down 14px border-color.

When opened, **language picker dropdown**: 12px radius, 1px border, `card` bg, max-height 280, hairline rows. Each row 14×10 pad: nativeName 13px SemiBold + en name 11px Regular muted + check icon (14px primary) if selected. Selected row bg = `primary + "22"`.

**Disable button**: 16px hMargin, 10px top, 12px radius, 1px border, `card` bg, 14×12 pad. Row: `slash` 16px muted + "Disable subtitles" 13px Medium muted. Triggers `clearSubtitles()` and `router.back()`.

**Search button**: 16px hMargin, 14px top, 12px radius, 14px vPad, primary bg. Center row: `search` 16px white + "Search OpenSubtitles" 15px Bold white. Replaced with `ActivityIndicator color="#fff"` while loading. Disabled if query empty.

**"Powered by opensubtitles.com"** caption: 10px Regular muted, centered, 8px topMargin.

**Error box** (when `searchError`): 16px hMargin, 12px top, 1px border, `card` bg, 10px radius, 12px pad. Row: alert-circle 14px muted + 12px Regular muted text.

**Results section** (when `results.length > 0`):
- Header label "{n} subtitles found" 11px Regular muted, 16px top.
- Each result: 16px hMargin, 12px pad, 10px radius, 1px border, `card` bg, 8px bottomMargin. Row: text column (flex 1) + trailing icon. Icon = `lock` if guest, `ActivityIndicator` if downloading, else `download` 16px primary.
- Text column: title 13px SemiBold (with optional `S{n}E{m}` suffix for series), then meta row with language pill (primary @ 13% alpha bg, primary text), optional CC pill (border bg), optional HD pill (`#22c55e22` bg, green text), download count + ratings star, then file name 10px Regular muted (1 line).

### 4.2 Behavior

- **Search**: `searchSubtitles({ query, languages })` → OpenSubtitles REST API. No-results → "No subtitles found." in error box.
- **Select**: 
  - Guest → `router.push('/paywall')`.
  - Subscribed → `getDownloadLink(file_id)` → `downloadSubtitleContent(link)` → `loadSRT(content, label)` (parses + sets cues in context) → `router.back()`.
- **Disable**: `clearSubtitles()` + back.

API: `https://api.opensubtitles.com/api/v1/subtitles?query=...&languages=...`. Free quota: 20/day search, 5/day download (no key); 40/10 with free key. App identifies as `User-Agent: AwaTV v1.0`. Optional `Api-Key` and `Authorization: Bearer <token>` headers.

### 4.3 Languages supported

27 languages: en, tr, ar, de, es, fr, it, pt, ru, nl, pl, ja, ko, zh-CN, zh-TW, hi, fa, sv, da, no, fi, ro, uk, el, he, cs, hu. Flutter port must enumerate these as a constant list with `code`, `name`, `nativeName`.

---

## 5. SubtitleContext + SubtitleOverlay + Sync Service

### 5.1 SubtitleContext

Two settings models persisted in AsyncStorage:

**`SubtitleSettings`**:
- `enabled: bool` (default true)
- `preferredLanguage: string` (default "en")
- `size: "small" | "medium" | "large" | "xlarge"` → `13 | 16 | 20 | 26` px
- `color: "white" | "yellow" | "green" | "cyan"` → `#fff | #fde047 | #4ade80 | #22d3ee`
- `background: "none" | "semi" | "solid"` → `transparent | rgba(0,0,0,0.6) | rgba(0,0,0,0.92)`
- `position: "bottom" | "top"`
- `bold: bool`
- `apiKey: string` (user OpenSubtitles key)

**`PlayerSettings`**:
- `defaultPlayer: PlayerType` (default "internal")
- `hardwareDecoding: bool` (true)
- `bufferMs: number` (3000)
- `preferredFormat: "hls" | "ts" | "dash" | "auto"` (auto)
- `autoPlay: bool` (true)
- `rememberPosition: bool` (true)
- `doubleTapSeek: number` (10s)
- `swipeVolume: bool` (true)
- `swipeBrightness: bool` (true)

Persisted under AsyncStorage keys `awatv_subtitle_settings` and `awatv_player_settings`. **Flutter port: use `SharedPreferences` or `Hive` with same JSON shapes.**

Runtime state: `cues: SubtitleCue[]`, `activeCue: SubtitleCue | null`, `subtitleLabel: string` ("Off" or "Title [LANG]"), `isLoadingSubtitles`, `subtitleError`.

`updatePosition(ms)` — called every video frame/tick — calls `getActiveCue(cues, ms)` (linear search through cue array). Flutter port should optimize with binary search if cue count is large.

### 5.2 SubtitleOverlay

`Positioned.fill` style absolute container, `bottom: bottomOffset` (60 default; player passes 60 in landscape, 8 in portrait) or `top: 80` if position="top". Centered text alignment, 20 hPad, gap 2 between lines.

Each line: `Text` styled with `fontSize`, `color`, fontWeight `700|600` (bold setting), `textShadowColor: rgba(0,0,0,0.9), offset (1,1), radius 3`, `paddingHorizontal: 8, paddingVertical: 2, borderRadius: 4`, `lineHeight: 24, letterSpacing: 0.2`. Background applied per-line as `bgColor`.

Multi-line support: splits on `\n`, renders each on its own row.

`pointerEvents: none` — does not intercept taps.

### 5.3 SRT parser (utils/subtitles.ts)

Splits on double-newline blocks, parses index, time-line via regex `(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(...)`, joins remaining lines as text, **strips HTML** (`<[^>]+>`). Time conversion: `hh*3600000 + mm*60000 + ss*1000 + ms`. Handles both `,` and `.` decimal separators.

`getActiveCue` is a linear search: `cues.find(c => positionMs >= c.startMs && positionMs <= c.endMs)`.

### 5.4 syncService.ts — Watch positions

Storage strategy: **local-first**, mirrored to Supabase `watch_positions` table.

Local AsyncStorage key: `sync_positions_${userId}_${profileId}` → JSON `Record<contentId, WatchPosition>`.

`WatchPosition`:
```
{
  contentId: string,
  contentType: "channel" | "vod" | "series",
  positionMs: number,
  durationMs: number,
  updatedAt: number  // ms timestamp
}
```

Supabase upsert on `(user_id, profile_id, content_id)`.

**Save cadence**: NOT enforced anywhere in current RN. Player screens never call `saveWatchPosition`. Flutter port must add a periodic save: every **10 seconds** while playing AND on pause/exit/seek, with `contentType: "vod" | "series"` (skip for live channels — they get position 0/duration 0 if needed).

Cloud restore: `syncWatchPositionsFromCloud(userId, profileId)` pulls all rows and overwrites local. Called by `performFullSync` on login.

Other sync entities (out of scope for this spec): playlists, settings.

---

## 6. Flutter port mapping

### 6.1 Existing AWAtv assets

- `awatv_player` package — top-level player abstraction (assumed wraps `video_player` or `media_kit`).
- `apps/mobile/lib/src/features/player/player_screen.dart` — single existing player screen.

### 6.2 Required new screens / widgets

| Streas | Flutter target | Notes |
|---|---|---|
| `app/tv-player.tsx` | `apps/mobile/lib/src/features/player/live_tv_player_screen.dart` | NEW. Live TV-specific player with EPG + channel sidebar + tablet panel |
| `app/player/[id].tsx` | `apps/mobile/lib/src/features/player/player_screen.dart` (extend) | EXTEND existing. Add real position tracking, subtitle overlay, watch-position save loop |
| `app/detail/[id].tsx` | `apps/mobile/lib/src/features/detail/detail_screen.dart` | NEW (likely missing) |
| `app/subtitle-picker.tsx` | `apps/mobile/lib/src/features/subtitles/subtitle_picker_screen.dart` | NEW. Full OpenSubtitles flow |
| `components/SubtitleOverlay.tsx` | `awatv_player/lib/src/widgets/subtitle_overlay.dart` | NEW |
| `context/SubtitleContext.tsx` | `apps/mobile/lib/src/features/subtitles/subtitle_controller.dart` (Riverpod/Bloc) | NEW. Settings + cue state |
| `services/syncService.ts` (positions only) | `apps/mobile/lib/src/data/sync/watch_position_repository.dart` | Likely exists — verify save cadence |
| `utils/subtitles.ts` (SRT parser + API) | `awatv_player/lib/src/subtitles/srt_parser.dart` + `apps/mobile/lib/src/data/opensubtitles_api.dart` | NEW. Use `dio` or `http` |

### 6.3 What's MISSING in current Flutter player (gap analysis)

Likely gaps based on the existing single `player_screen.dart`:

1. **Subtitle picker UI** — no equivalent screen exists. Needs full build.
2. **OpenSubtitles API client** — NEW. 27-language list, search/download endpoints, hourly rate-limit handling.
3. **SubtitleOverlay widget** — Flutter `video_player` has caption support but Streas's overlay has custom font/size/color/background presets that need a custom widget.
4. **SRT parser** — Flutter has `subtitle` package or roll own; port logic verbatim including HTML strip.
5. **EPG overlay (current program + percentage)** — landscape gradient + portrait box.
6. **Channel side-drawer** — slide-in `Drawer` with spring animation, channel logos, current program preview, active highlight.
7. **Tablet right panel** — `MediaQuery` width >= 768 + landscape branch with EPG list.
8. **External player launcher** — VLC/MX/nPlayer deep-link builders. Flutter equivalent: `url_launcher` with platform-specific URI schemes. iOS schemes: `vlc://`, `nplayer-`. Android intents: `intent:URL#Intent;package=...;type=video;end`.
9. **External player picker menu** (top-right dropdown).
10. **LIVE indicator badge** + auto-hide animations.
11. **Custom volume bar overlay** with mute toggle.
12. **EPG progress percentage** (`Date.now() - start) / (end - start)`).
13. **Cherry-red (`#E11D48`) theming validation** — verify AWAtv tokens match.
14. **Watch position save loop** — must be added (10s periodic + lifecycle hooks).
15. **Subtitle settings persistence** (`SharedPreferences` JSON).
16. **Player settings persistence** (same).
17. **Unimplemented-in-RN-but-needed**: double-tap-seek (±10s), swipe-volume, swipe-brightness, PiP, casting (Chromecast/AirPlay), background audio. Flutter has packages: `flutter_volume_controller`, `screen_brightness`, `flutter_cast`, audio session APIs via `just_audio_background` if you swap engines.

### 6.4 Stream format detection

Streas relies on expo-video to auto-detect. Flutter equivalents:

- `video_player` plugin: handles HLS (.m3u8), MP4. Limited DASH/RTMP.
- **`media_kit`** (recommended for IPTV): wraps libmpv → handles HLS, DASH, MPEG-TS, RTMP, RTSP, virtually all containers. Already likely the basis of `awatv_player`.

Format hint logic (Streas implicitly delegates): Flutter port can add `_inferFormat(url)` that checks extension `.m3u8` → HLS, `.mpd` → DASH, `.ts` → MPEG-TS, `rtmp://` → RTMP, else → "auto".

### 6.5 Recommended widget tree skeleton

#### `LiveTvPlayerScreen`

```
Scaffold(backgroundColor: Color(0xFF000000))
  body: OrientationBuilder + LayoutBuilder
    landscape && tablet:
      Row
        Stack [video area]                 // 65% width
          AwatvPlayerView(controller)
          LiveBadge()
          SubtitleOverlay()
          AnimatedOpacity (5s auto-hide) [
            TopGradientBar(back, title, monitor, subtitles)
            CenterControls(skipBack, playPause64, skipFwd)
            BottomGradientBar(epgRow, progressBar, controlsRow)
          ]
          ExternalPlayerMenu (overlay)
          ErrorToast (overlay)
        TabletEpgPanel()                    // 35% width
    landscape && phone:
      Stack [full-screen video same as above]
    portrait:
      Column
        Stack [16:9 video area]
        PortraitInfoPanel(channelRow, epgBox, controlsRow)
  floatingDrawer: ChannelSidebar (animated translateX, 260 wide)
```

State management: `Riverpod` (`liveTvPlayerProvider`) with sub-providers for `channelsProvider`, `epgProvider`, `subtitleProvider`, `playerSettingsProvider`. `AwatvPlayerController` is the engine handle (play/pause/replace/volume/muted).

Animations: `AnimationController(duration: 600ms)` for UI fade; `AnimationController(duration: 200ms)` for re-show; spring `SimulationBuilder` for sidebar.

Auto-hide: `Timer(Duration(seconds: 5))` rescheduled on every tap.

#### `VodPlayerScreen` (extend existing `player_screen.dart`)

```
Scaffold(backgroundColor: Colors.black)
  body: GestureDetector(onTap: showControls, onDoubleTapDown: seekDelta)
    Stack
      AwatvPlayerView(controller)
      SubtitleOverlay(bottomOffset: 60)
      AnimatedOpacity (3s auto-hide) [
        TopBar(back, title, more)
        CenterControls(skipBack10_72px_skipFwd10)
        BottomBar(progressRow + bottomIcons)
      ]
  WatchPositionSaver(controller, contentId, contentType)  // ticker every 10s
```

Add `Subtitle Settings Sheet` triggered by the `message-square` icon → either pushes `/subtitle-picker` or opens an in-place bottom sheet for size/color/position/bold toggles.

#### `DetailScreen`

```
Scaffold(backgroundColor: Color(0xFF0A0A0A))
  body: CustomScrollView
    SliverAppBar(
      expandedHeight: 280,
      flexibleSpace: Stack[
        Image.network(banner, fit: cover),
        Container(color: rgba(0,0,0,0.35)),  // overlay
      ],
      leading: CircleBackButton(40)
    )
    SliverPadding(20, 20, 20, 40)
      SliverList[
        if (isNew) NewBadge,
        TitleText(26, w700),
        MetaRow(year, ratingBadge, duration),
        GenreWrap(),
        PrimaryPlayButton(),
        SecondaryActionsRow([myList, download, share]),
        DescriptionText(),
        SectionHeading("More Like This"),
        HorizontalCardScroll(items=trending, w=110, h=165),
      ]
```

#### `SubtitlePickerScreen`

```
Scaffold(bg: 0a0a0a)
  appBar: SimpleAppBar(close, "Subtitles")
  body: SingleChildScrollView
    Column[
      if (!subscribed) PremiumBanner(),
      SearchField(query, onSearch),
      LanguageSelector(language, onChange),
      if (showLangPicker) LanguagePicker(27 langs),
      DisableButton(),
      SearchButton() (loading state),
      "Powered by opensubtitles.com",
      if (error) ErrorBox(),
      if (results.isNotEmpty) ResultsList(
        for each: SubtitleResultCard(title, langPill, ccPill, hdPill, count, rating, fileName, trailingIcon)
      ),
    ]
```

#### `SubtitleOverlay`

```
class SubtitleOverlay extends ConsumerWidget {
  final double bottomOffset;
  Widget build(context, ref) {
    final cue = ref.watch(activeCueProvider);
    final s = ref.watch(subtitleSettingsProvider);
    if (!s.enabled || cue == null) return SizedBox.shrink();
    return Positioned(
      left: 0, right: 0,
      top: s.position == top ? 80 : null,
      bottom: s.position == bottom ? bottomOffset : null,
      child: IgnorePointer(child: Column(
        children: cue.text.split("\n").map((line) => Container(
          padding: EdgeInsets.symmetric(h: 8, v: 2),
          decoration: BoxDecoration(
            color: backgroundFor(s.background),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(line, style: TextStyle(
            fontSize: sizeFor(s.size),
            color: colorFor(s.color),
            fontWeight: s.bold ? w700 : w600,
            shadows: [Shadow(color: rgba(0,0,0,0.9), offset: (1,1), blurRadius: 3)],
            letterSpacing: 0.2,
            height: 24 / fontSize,
          )),
        )).toList(),
      )),
    );
  }
}
```

### 6.6 OpenSubtitles client (Flutter)

```
class OpenSubtitlesClient {
  static const baseUrl = 'https://api.opensubtitles.com/api/v1';
  String? apiKey;
  String? token;

  Map<String, String> _headers() => {
    'Content-Type': 'application/json',
    'User-Agent': 'AwaTV v1.0',
    'Accept': 'application/json',
    if (apiKey != null) 'Api-Key': apiKey!,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<SubtitleSearchResult> search({...}) async { ... }
  Future<DownloadLink> getDownloadLink(int fileId) async { ... }
  Future<String> downloadContent(String url) async { ... }
}
```

Mirror the 27-language list as a `const List<SubtitleLanguage>`.

### 6.7 Watch position save ticker

```
class WatchPositionTicker {
  Timer? _timer;
  void start(AwatvPlayerController c, String contentId, String contentType) {
    _timer = Timer.periodic(Duration(seconds: 10), (_) async {
      if (!c.isPlaying) return;
      await repo.saveWatchPosition(WatchPosition(
        contentId: contentId,
        contentType: contentType,
        positionMs: c.position.inMilliseconds,
        durationMs: c.duration.inMilliseconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
  }
  void stopAndFlush() {
    _timer?.cancel();
    // final save
  }
}
```

Hooked into player screen's `dispose()` and on pause-events.

---

## 7. Out-of-scope but worth flagging

- Cast/crew, trailer button on Detail page — not in Streas; future enhancement.
- Skeleton loading shimmers for Detail page — needs to be added in Flutter port.
- PiP, Chromecast, AirPlay, background audio — not in Streas; flag for AWAtv roadmap.
- Episode list for series content — not in Streas detail page; needs design extension.
- Player gestures (double-tap-seek, swipe brightness/volume) — declared in `PlayerSettings` but unimplemented in RN; **must be implemented** in Flutter port.
- Picture-in-picture — Flutter `floating` package or platform channels.
- Watch-position UI on Home/Continue Watching row — orthogonal to player but consumes saved positions.

---

## 8. Verification checklist for Flutter parity

- [ ] Cherry red `#E11D48` exactly across LIVE badge, primary buttons, active sidebar item, progress fill, subtitle pill.
- [ ] Auto-hide timing: 5000ms (live), 3000ms (VOD); fade durations 600/400ms; show 200ms.
- [ ] Live TV play button = 64×64; VOD play button = 72×72.
- [ ] LIVE badge bg = `#E11D4899`, dot 6×6 white, text 10px Inter Bold 1px tracking.
- [ ] Sidebar = 260 wide, slide-in spring (tension 60, friction 10).
- [ ] Tablet right panel triggered at width >= 768 in landscape only.
- [ ] EPG progress % = wall-clock based (not stream position).
- [ ] External player URI schemes match exactly (vlc://, intent:..., nplayer-).
- [ ] 27 subtitle languages in identical order.
- [ ] OpenSubtitles `User-Agent: AwaTV v1.0`.
- [ ] SRT parser: handles `,` and `.` decimal, strips HTML, splits on double-newline.
- [ ] Subtitle sizes: 13/16/20/26.
- [ ] Subtitle colors: white/yellow/green/cyan with hex match.
- [ ] Subtitle backgrounds: none/semi (rgba(0,0,0,0.6))/solid (rgba(0,0,0,0.92)).
- [ ] Watch position saved every 10s + on pause/exit; upserted to Supabase `watch_positions` keyed on (user_id, profile_id, content_id).
- [ ] Detail banner = 280 height, image cover, 35%-black overlay, floating circular back button.
- [ ] Detail title 26px Bold, primary Play button full-width 14px vPad, three secondary action cards with column-icon-text layout.
- [ ] More-Like-This horizontal scroll: 110×165 thumbnails, 10px gap.

---

End of spec.
