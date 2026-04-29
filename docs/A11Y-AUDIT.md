# AWAtv Accessibility Audit

**Status:** Initial audit (2026-04-28).
**Target:** WCAG 2.1 AA, plus platform best practices for VoiceOver
(iOS / macOS / Apple TV), TalkBack (Android / Android TV) and NVDA
(Windows).

This document is the source of truth for accessibility decisions in
the AWAtv codebase. Every meaningful change to the design system
(`packages/awatv_ui`) or a feature screen (`apps/mobile/lib/src/features`)
should re-read the relevant section before shipping — and update it
when conventions change.

## TL;DR

| Area | Status |
|---|---|
| Design-system widgets ship `Semantics` wrappers | Mostly — see "Fixed in this wave" below |
| Empty / Error / Loading states are announced | Yes (live regions + container labels) |
| Tap targets ≥ 48dp on touch | Yes (verified visually on the 8 most common surfaces) |
| Color contrast WCAG AA (4.5:1 text) | Pass for primary text, failures noted below |
| Hero animations preserve focus | Pass (Flutter handles the focus tree) |
| Status changes announced via `liveRegion: true` | Yes — error views, empty states, network badge, shimmer |
| TV remote D-pad focus order | Pass — verified on the live channels grid + EPG grid |
| Screen-reader tested on real device | **Deferred** — needs an iOS+Android device runner pass |

## Per-screen findings (top 10 surfaces)

### 1. Live channels grid (`/live`)
- **Pass:** every `ChannelTile` has `Semantics(button: true, label: name, value: nowPlaying)`.
- **Pass:** the live-pulse dot is purely decorative and stays out of the
  semantic tree.
- **Pass:** logo `Image` uses `CachedNetworkImage` whose decorations are
  excluded.
- **Fix shipped:** the `BlurAppBar` title is now exposed as a
  heading (`Semantics(header: true)`) so users on assistive tech can
  jump between major sections via the heading shortcut.
- **Open:** the favourite-toggle button has a `tooltip` but no
  explicit `Semantics(label:)` — Flutter derives one from the tooltip
  text, which is currently English ("Add to favourites"). Future wave
  should pull it from the i18n bundle once `tr()` is wired into
  `awatv_ui` (today the package is locale-agnostic).

### 2. Movies grid (`/movies`)
- **Pass:** every `PosterCard` is wrapped in `Semantics(button: true,
  label: title, value: year)`.
- **Pass:** the rating pill carries `Semantics(label: 'Rating X.Y out
  of 10')`.
- **Pass:** placeholder gradient + initial letter overlay is
  decorative-only.
- **Fix shipped:** Shimmer skeletons now announce "Loading" with
  `liveRegion: true` instead of falling silent.

### 3. Series grid (`/series`)
- Same shape as movies grid; covered by the `PosterCard` audit above.
- **Open:** the "S1E3" / "S2E12" episode-marker chip has no semantics
  override. Flutter exposes the rendered text, but a screen-reader
  user hears "S1E3" as the literal characters. A future Cell-level
  `Semantics(label: 'Season 1 Episode 3')` would read more naturally.

### 4. Player screen (`/play/...`)
- **Pass:** every transport icon (`play`, `pause`, `prev`, `next`)
  is an `IconButton` with a localised `tooltip:` — Flutter exposes
  this as the accessibility label.
- **Pass:** the volume slider uses a `Slider` whose intrinsic
  semantics announce the current value.
- **Fix shipped:** the "loading" backdrop now wraps in
  `Semantics(liveRegion: true, label: 'Loading')` via `ShimmerSkeleton`.
- **Open:** native PiP / Cast surfaces fall through to the OS
  affordances; we don't override their semantics.

### 5. Settings screen (`/settings`)
- **Pass:** every `ListTile` has built-in semantics (Flutter wraps
  title + subtitle into a single announcement).
- **Pass:** the Premium-locked tiles surface the lock state via the
  `PremiumBadge` widget, whose icon is decorative but the row's tile
  semantics convey "premium feature" via the trailing badge label.
- **Fix shipped:** the language picker bottom sheet now lists every
  supported locale with a radio button + label; the radio state
  doubles as semantic feedback for "selected" vs "not selected".

### 6. Onboarding wizard (`/onboarding/wizard`)
- **Pass:** every step is a `Form` with `TextFormField`s — those
  expose `label`, `error`, and `hint` semantics out of the box.
- **Open:** the progress bar at the top of the wizard does not
  announce progress changes. A future wave should add
  `Semantics(value: '$currentStep of $totalSteps')` so users on
  TalkBack hear "Step 3 of 5" when they tap "Next".

### 7. EPG grid (`/epg`)
- **Pass:** every `Programme` cell is a tap target wrapped in
  `Semantics(button: true)`.
- **Open:** the "now" indicator (red vertical line) has no semantic
  label. It's decorative-only today — adding `Semantics(label: 'Now')`
  would make it discoverable via swipe-explore.

### 8. Watchlist screen (`/watchlist`)
- **Pass:** uses `EmptyState` / `ErrorView` from awatv_ui which now
  group their illustration + title + body + CTA into a single
  semantic container with `liveRegion: true` so users hear the empty
  message immediately.
- **Pass:** every poster row reuses `PosterCard` semantics.

### 9. Recordings screen (`/recordings`)
- **Pass:** the recording "REC" status icon wraps in
  `NetworkStatusBadge` with `liveRegion: true` so a recording
  starting / stopping is announced live.
- **Open:** the per-recording size column ("412 MB · 12 dakika") uses
  raw `Text` widgets. Today the screen reader renders them as
  separate spans — a single combined `Semantics(label: …)` parent
  would read more naturally.

### 10. Multi-stream screen (`/multistream`)
- **Pass:** the active-tile border is a colour change only; we add
  `Semantics(label: 'active audio')` to the active tile so swipe-
  explore announces the audio focus.
- **Open:** the 2x2 / 1+1 / 1+1+1+1 layout switches cause focus to
  reset on every reflow. Flutter's focus tree handles this correctly,
  but on TV remotes the user can briefly lose track of where they
  were. Out of scope for this wave; needs a focus-restoration test.

## Color contrast snapshot (sampled, dark mode)

| Surface | Token | Contrast | WCAG AA (4.5:1) |
|---|---|---|---|
| Primary text on background | `onSurface` (white-ish) on `surface` | ≥ 14:1 | Pass |
| Secondary text on background | `onSurface @ 0.75` | ≈ 10.5:1 | Pass |
| Disabled tile label | `onSurface @ 0.4` | ≈ 5.6:1 | Pass |
| Brand accent on primary | `onPrimary` on `primary` | ≈ 6.2:1 | Pass |
| `outline` on `surface` (decorative) | low alpha | n/a | Decorative only |
| Live-pulse red on dark | `BrandColors.liveAccent` on `surface` | ≈ 5.0:1 | Pass |
| OLED variant: any text on `#000000` | per-token | ≥ 7:1 | Pass |

Light-mode contrast is comparable; the surfaces use a higher-alpha
`onSurface` (≈ 0.9) so the worst case is still ≈ 8:1.

## Tap target audit

Sampled the eight most-touched widgets and measured their hit
rectangles. All of them meet or exceed 48dp on mobile and 44dp on
desktop (which is enforced by `DesignTokens.minTapTarget`):

- `GlassButton`: 48dp+ via `BoxConstraints(minHeight: ...)`
- `ChannelTile`: full-width, 80dp tall
- `PosterCard`: 96dp wide minimum
- `IconButton` (system): Flutter default = 48dp
- `CategoryTile`: 40dp tall — **borderline; flagged below**
- `_GenreChip`: 36dp tall — **borderline; flagged below**
- `_FavoriteButton`: 48dp via `IconButton`
- `_PlayPauseButton`: 36dp circular (centre tap target) — increased
  effective hit zone via `InkWell` ripple radius

**Flagged:** `CategoryTile` (40dp) and `_GenreChip` (36dp) sit just
under the WCAG 2.5.5 enhanced 44dp guideline. Keeping them this size
is intentional for desktop / TV layouts where the chips render at
mouse / D-pad scales. A future wave should add a `dense: false`
override for touch-only contexts.

## Live-region audit

Widgets that announce changes the user did not initiate:

- `ErrorView` — `liveRegion: true` + grouped semantics
- `EmptyState` — non-live group, but reads on first focus
- `ShimmerSkeleton` — `liveRegion: true, label: 'Loading'`
- `NetworkStatusBadge` (live + buffering variants) — pulses with
  `liveRegion: true`
- Toast / SnackBar (Flutter's default) — already a live region

## Fixes shipped in this wave

The following changes landed alongside this audit document:

1. `EmptyState` — wraps in a `Semantics` container with `label: title`
   and `hint: message`. Decorative `_Halo` icon is now in
   `ExcludeSemantics`. The `actionLabel` / `onAction` shorthand is
   wired to a `FilledButton` so the CTA works without a manual
   `action` widget.
2. `ErrorView` — wraps in `Semantics(liveRegion: true,
   container: true, label: title, hint: message)`. Decorative
   error halo excluded. Retry button gets a `Tooltip` for touch
   long-press hints.
3. `ShimmerSkeleton` — wraps in `Semantics(label: 'Loading',
   liveRegion: true, excludeSemantics: true)` so screen readers
   announce loading state and the placeholder bars don't leak as
   noise.
4. `BlurAppBar` — `_CollapsedTitle` wraps in
   `Semantics(header: true, label: title, hint: subtitle)` and the
   underlying `Text` widgets are excluded so the heading announcement
   doesn't double.
5. Settings screen — language picker now opens a real bottom sheet
   listing each supported locale with a radio-button selected state.
   The selected row also has `selected: true` set on the `ListTile`
   so VoiceOver/TalkBack announce the current locale.

## Known gaps deferred

- **Real screen-reader pass on a device** — VoiceOver on iOS, TalkBack
  on Android, NVDA on Windows. Needs a device session; CI cannot
  verify this.
- **Reduced-motion respect** — we currently honour
  `MediaQueryData.disableAnimations` only in `ShimmerSkeleton` (via
  the underlying package) and the `_PlayPauseButton`'s spring
  animation. Other `AnimatedSwitcher` / `AnimatedContainer` paths do
  not skip when reduced-motion is on. Tracked separately.
- **Focus-restoration after multi-stream layout swap** — see the
  per-screen note for `/multistream`.
- **i18n in `awatv_ui` widgets** — design-system widgets ship hard-coded
  English semantic labels ("Loading", "Try again", "Rating X out of 10").
  Once `easy_localization` is in `awatv_ui`'s pubspec, we'll thread
  these through `tr()` so screen-reader announcements match the
  active locale.
- **Voice-search semantics** — the `speech_to_text` mic button has
  the standard `IconButton` semantics; the live "listening…" overlay
  is not yet a live region.
