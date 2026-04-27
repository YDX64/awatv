# AWAtv — Project Memory (auto-loaded into Claude Code sessions)

> **READ THIS FIRST** in any session that touches the AWAtv codebase.
> This is the source of truth for *what we are building, why, and how*.

## What is AWAtv

A cross-platform freemium IPTV/streaming application. One app that runs on:
**iOS, Android, Apple TV, Android TV, macOS, Windows, Web**.

### Core capabilities (target product)

- Add playlists: **M3U / M3U8 / Xtream Codes API**
- Live channels with **EPG** (electronic program guide)
- VOD (movies) and Series with **smart episode tracking** (next-up, watched markers)
- **Metadata enrichment**: TMDB primary, TVDB/IMDB stubs (channel logos, posters, backdrops, plots, cast, ratings, trailers)
- **Player**: in-app (better_player / video_player) + **VLC fallback** (flutter_vlc_player) for codecs the native player can't handle
- **Smart buffering** for smooth YouTube-like playback
- **Freemium model**: AdMob banners/interstitials in free tier, premium unlocks (multi-screen, unlimited playlists, EPG extended, no ads, premium player)
- **Sleek modern UI**: dark-first, glassmorphism accents, motion design

## Architecture

**Monorepo** (Dart path-based local dependencies, no melos required):

```
AWAtv/
├── CLAUDE.md             ← you are here
├── AGENT.md              ← parallel-agent coordination contract
├── README.md
├── docs/
│   ├── DESIGN.md         ← architecture & data flows (long form)
│   └── ROADMAP.md        ← phased delivery plan
├── packages/
│   ├── awatv_core/       ← pure Dart: parsers, models, services, storage
│   │   └── lib/src/
│   │       ├── models/         (PlaylistSource, Channel, VodItem, Series, Episode, EpgProgramme, ...)
│   │       ├── parsers/        (M3uParser, XtreamParser)
│   │       ├── clients/        (XtreamClient, TmdbClient, EpgClient)
│   │       ├── services/       (PlaylistService, MetadataService, EpgService, FavoritesService, HistoryService)
│   │       ├── storage/        (HiveStorage, KeyStore)
│   │       └── utils/          (logger, time, url)
│   ├── awatv_ui/         ← Flutter: theme, tokens, design-system widgets
│   │   └── lib/src/
│   │       ├── theme/          (AppTheme, Brand colors, typography)
│   │       ├── tokens/         (DesignTokens — spacing, radii, durations)
│   │       ├── widgets/        (PosterCard, ChannelTile, ShimmerSkeleton, GlassButton, BlurAppBar, ...)
│   │       └── animations/     (HeroPoster, FadeRoute)
│   └── awatv_player/     ← Flutter: video player abstraction (better_player + VLC)
└── apps/
    └── mobile/           ← Flutter app for iOS + Android (Phase 1)
        └── lib/src/
            ├── app/                (root app, providers, env)
            ├── routing/            (GoRouter config)
            └── features/
                ├── onboarding/     (welcome + add-first-playlist flow)
                ├── playlists/      (manage playlists, refresh, delete)
                ├── channels/       (live channels grid, search, EPG)
                ├── vod/            (movies grid, detail, trailer)
                ├── series/         (series grid, detail, season/episode list)
                ├── player/         (player screen, controls, casting)
                ├── search/         (global search)
                ├── settings/       (preferences, account, parental control)
                └── premium/        (subscription gates, paywall)
```

Future phases add `apps/android_tv`, `apps/desktop`, `apps/apple_tv` (the last is a separate SwiftUI Xcode project sharing logic via FFI/REST).

## Key technical decisions

| Decision | Choice | Why |
|---------|--------|-----|
| Framework | Flutter | Single codebase covers 5/6 platforms officially; pixel-perfect UI control |
| State management | **Riverpod 2.5+** | Type-safe, no BuildContext leaks, easy code-gen |
| Routing | **go_router 14+** | Declarative, deep-link-friendly, TV-D-pad-friendly |
| Storage | **Hive** + `flutter_secure_storage` | Hive for fast key-value/box of objects; secure for credentials |
| HTTP | **dio** | Interceptors, retry, multipart, mature |
| Player | **better_player** (primary) + **flutter_vlc_player** (fallback) | better_player gives controls/UX; VLC handles tough codecs |
| Metadata | **TMDB v3** | Free, deep, well-documented; key required (env var) |
| EPG | XMLTV format from playlist provider OR `epg_url` from Xtream | Standard format, parser in awatv_core |
| Ads | **google_mobile_ads** | AdMob — needs publisher account; placeholder IDs in dev |
| IAP | **in_app_purchase** + **revenue_cat** wrapper | Cross-store subscriptions, server validation |
| i18n | **easy_localization** | JSON-based translations, runtime locale switch |

## What "real working" means in this project

User explicitly said: *"test demo basit mock icerikleri asla istemiyorum gercek calisan programlar yazmalisin"*.

Translation: **No mocked data, no `// TODO` stubs that pretend to work**. Every feature shipped must:

1. Compile (`flutter analyze` clean — no errors, warnings tolerated only with `// ignore: ` and a reason)
2. Run on a real device/emulator with a real M3U or Xtream URL
3. Handle real-world edge cases (offline, expired URL, malformed M3U, slow network)

If something cannot ship in a session, **state it explicitly as deferred** — don't fake it.

## What's deferred (NOT in current session scope)

- Apple TV (tvOS) native app — requires separate Xcode project
- Production store submission (App Store, Play Store) — requires accounts, certs, screenshots
- Backend (Supabase) — placeholders only; IAP/sync/analytics wired with real keys later
- TVDB and IMDB metadata clients — TMDB is primary; others are stubs returning `null`
- Trailer playback — TMDB returns YouTube IDs but native YT player not embedded yet
- Casting (Chromecast/AirPlay) — deferred to Phase 2
- Multi-screen / picture-in-picture — deferred to Phase 2

## Dev environment notes

- macOS 26.5 (Tahoe), Apple Silicon
- Brew at `/opt/homebrew/bin/brew`
- Xcode.app present but `xcode-select` points at CommandLineTools — fix with: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` for iOS builds
- Android SDK at `/Users/max/Library/Android/sdk` — add to PATH: `export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"`
- Flutter installed via `brew install --cask flutter` (binary in `/opt/homebrew/bin/flutter` after install)

## How to resume work in a new session

1. Read this file (auto-loaded).
2. Read `AGENT.md` for current parallel-agent state.
3. Run `flutter --version && flutter doctor` to verify toolchain.
4. `cd /Users/max/AWAtv && flutter pub get` (recursive — resolves all packages).
5. Check `docs/ROADMAP.md` for what phase we're in.

## House rules

- Turkish for user-facing chat, English for code/comments/commits.
- No emojis in code or commits unless explicitly requested.
- Real working code only — no demos.
- Use parallel agents for independent work streams.
- Verify before claiming done (`flutter analyze`, `flutter test`, `flutter run`).
