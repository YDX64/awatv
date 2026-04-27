# AWAtv — Roadmap

## Phase 0 — Foundation (this session)

**Status:** in progress

- [x] Decide tech stack (Flutter monorepo)
- [x] Memory files & coordination contract (CLAUDE.md, AGENT.md)
- [x] Design spec (docs/DESIGN.md)
- [ ] Flutter SDK installed
- [ ] Monorepo `pubspec.yaml` workspace
- [ ] `analysis_options.yaml` (very_good_analysis)
- [ ] Empty packages with valid `pubspec.yaml` and `lib/<name>.dart` exports
- [ ] CI skeleton (.github/workflows/flutter.yml)

## Phase 1 — Mobile MVP (this session, after Phase 0)

**Status:** queued

`awatv_core`:
- [ ] Models with Hive TypeAdapters and `freezed` generated equality/copyWith
- [ ] M3UParser (handles `#EXTINF`, `#EXTGRP`, `#EXTVLCOPT`, `tvg-*` attributes)
- [ ] XtreamClient (live/vod/series/EPG endpoints; typed errors)
- [ ] EpgService (XMLTV gzip download + indexed parsing)
- [ ] TmdbClient + MetadataService (search by title; trailer extraction)
- [ ] HiveStorage adapters
- [ ] FavoritesService, HistoryService
- [ ] Unit tests for parsers

`awatv_ui`:
- [ ] AppTheme (dark + light)
- [ ] DesignTokens
- [ ] Widgets: PosterCard, ChannelTile, GlassButton, BlurAppBar, ShimmerSkeleton, EmptyState, ErrorView, GradientScrim, RatingPill
- [ ] Material 3 expressive motion

`awatv_player`:
- [ ] AwaPlayerController abstraction
- [ ] BetterPlayer backend
- [ ] VLC backend (flutter_vlc_player)
- [ ] Auto-select logic (URL/codec sniffing)

`apps/mobile`:
- [ ] App bootstrap (`main.dart`, ProviderScope, env loading)
- [ ] go_router config
- [ ] Onboarding flow (welcome + add-first-playlist)
- [ ] Playlist management screen
- [ ] Channels grid with EPG strip
- [ ] VOD grid with detail screen + trailer button
- [ ] Series grid with seasons/episodes
- [ ] Player screen with custom controls
- [ ] Search screen (global)
- [ ] Settings (theme, language, parental, premium)
- [ ] Premium paywall screen
- [ ] AdMob banner integration (dev IDs)

## Phase 2 — Android TV (next session)

- [ ] D-pad focus management (`FocusableActionDetector`)
- [ ] Leanback-style 10-foot UI
- [ ] AndroidManifest.xml with `android.software.leanback` and `LEANBACK_LAUNCHER` intent filter
- [ ] TV grid layouts (larger tiles, focus scaling)
- [ ] Recently watched + recommendations row

## Phase 3 — Desktop (next session)

- [ ] macOS + Windows builds
- [ ] Window chrome (custom titlebar)
- [ ] Keyboard shortcuts (space=pause, ←→=seek, M=mute, F=fullscreen)
- [ ] Multi-window support (PiP)
- [ ] System tray integration

## Phase 4 — Apple TV (later session)

- [ ] Separate SwiftUI Xcode project at `apps/apple_tv/`
- [ ] Reuse Dart core via `flutter build aar` → wrap in framework, OR call REST backend
- [ ] Top Shelf extension
- [ ] Siri remote gestures
- [ ] App Store Connect submission

## Phase 5 — Backend & monetisation

- [ ] Supabase project (auth, profiles, sync)
- [ ] RevenueCat for cross-store IAP
- [ ] AdMob production IDs
- [ ] Analytics (PostHog or Plausible — user choice)
- [ ] Cloud sync of favorites/history
- [ ] Parental control PIN sync

## Phase 6 — Polish & launch

- [ ] App store screenshots & metadata (en, tr)
- [ ] Privacy policy, ToS, EULA
- [ ] Crash reporting (Sentry)
- [ ] Beta program (TestFlight + Play Internal Testing)
- [ ] Public launch
