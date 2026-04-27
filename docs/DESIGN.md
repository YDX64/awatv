# AWAtv — Design Specification

**Version:** 0.1 (2026-04-27)
**Status:** approved by user (verbal, no written review yet)

## Goals

1. One Flutter codebase covering iOS, Android, Apple TV (separate Swift app), Android TV, macOS, Windows.
2. Premium-feeling UI on par with TiviMate / IPTV+ / tvMate.
3. Real-world IPTV input handling: M3U, M3U8, Xtream Codes API.
4. Smooth, buffered playback with VLC fallback for tough codecs.
5. Metadata enrichment via TMDB (TVDB/IMDB stubs for future).
6. Freemium business model: free tier with ads, premium subscription.

## Non-goals (explicitly)

- Hosting any IPTV content. The user supplies their own playlists.
- Ad-supported "free TV" channels — the app is the player, not the content provider.
- Live transcoding. We trust the source stream's codec.

## High-level architecture

```
┌─────────────────────────────────────────────────────────┐
│                     UI (Flutter)                        │
│   apps/mobile (Phase 1) → android_tv → desktop          │
│            ↓ Riverpod providers ↑                       │
├─────────────────────────────────────────────────────────┤
│              awatv_ui (design system)                   │
├─────────────────────────────────────────────────────────┤
│   awatv_core (pure Dart)        │   awatv_player        │
│   ├── PlaylistService           │   ├── BetterPlayer    │
│   ├── MetadataService (TMDB)    │   └── VLCPlayer       │
│   ├── EpgService (XMLTV)        │   (auto-selects)      │
│   ├── FavoritesService          │                        │
│   ├── HistoryService            │                        │
│   └── HiveStorage               │                        │
└─────────────────────────────────────────────────────────┘
            ↓ HTTP/HTTPS
┌──────────────────────┬──────────────────┬──────────────┐
│ User's M3U / Xtream  │   TMDB API       │  XMLTV EPG   │
└──────────────────────┴──────────────────┴──────────────┘
```

## Data flow: "User adds an Xtream playlist"

```
User input → PlaylistService.add(PlaylistSource(kind: xtream, ...))
   ↓ HiveStorage.put(source)
   ↓ XtreamClient(server, user, pass)
   ↓     → /player_api.php?action=get_live_categories
   ↓     → /player_api.php?action=get_live_streams
   ↓     → /player_api.php?action=get_vod_categories
   ↓     → /player_api.php?action=get_vod_streams
   ↓     → /player_api.php?action=get_series
   ↓ List<Channel/VodItem/SeriesItem>
   ↓ HiveStorage.putAll(channels)
   ↓ for each VOD/Series:
   ↓     MetadataService.movieByTitle(title)  ← TMDB lookup, cached
   ↓     enrich with poster/backdrop/plot/rating
   ↓ emit Stream<List<Channel>> to UI
```

Parallel: `EpgService` downloads XMLTV (gzipped), parses, indexes by `tvg_id`, stores in Hive.

## Data flow: "User taps a channel to watch"

```
ChannelTile.onTap → router.push('/player', extra: channel)
   ↓ PlayerScreen
   ↓ AwaPlayerController.create(MediaSource(channel.streamUrl))
   ↓ backend selection:
   ↓   if URL.endsWith('.m3u8') and codec is H.264 → BetterPlayer (HLS-native)
   ↓   else if codec is HEVC/AV1 → VLC (broader codec support)
   ↓   else → BetterPlayer
   ↓ buffered start, poster shown until first frame
   ↓ HistoryService.markPosition() ticks every 5s
   ↓ EPG ticker shows now/next program at top
```

## State management — Riverpod provider tree

```
RootProviderScope
├── envProvider                    (loaded from .env)
├── storageProvider                (Hive boxes)
├── playlistServiceProvider        (depends: storage, http)
├── metadataServiceProvider        (depends: storage, http, tmdbKey)
├── epgServiceProvider             (depends: storage, http)
├── favoritesServiceProvider
├── historyServiceProvider
├── premiumStatusProvider          (depends: revenuecat)
├── adsProvider                    (admob — disabled if premium)
└── theme/locale providers
```

UI screens use `ref.watch(...)` against these providers. No global singletons.

## Storage schema (Hive boxes)

| Box | Key | Value | Notes |
|-----|-----|-------|-------|
| `sources` | sourceId | `PlaylistSource` (TypeAdapter) | encrypted via flutter_secure_storage for credentials |
| `channels:{sourceId}` | channelId | `Channel` | refreshed on resync |
| `vod:{sourceId}` | vodId | `VodItem` | |
| `series:{sourceId}` | seriesId | `SeriesItem` | |
| `epg` | tvgId | `List<EpgProgramme>` | indexed time series |
| `metadata` | "tmdb:{kind}:{title}:{year}" | `TmdbResult` | TTL 30 days |
| `favorites` | channelId | `1` | set semantics |
| `history` | channelId | `HistoryEntry(position, total, watchedAt)` | |
| `prefs` | key | dynamic | user settings |

## Error handling

- All network errors → typed `NetworkException` with status, retryable flag, original cause.
- Parse errors → `PlaylistParseException` with line number when available.
- Auth errors → `XtreamAuthException` (UI shows "credentials invalid, please re-enter").
- UI: `AsyncValue.guard(...)` patterns; user-facing errors via `ErrorView` widget with retry CTA.

## UI/UX principles ("ultra creative sleek")

- **Dark-first**, with optional light theme. Brand colors: deep indigo + electric purple accent.
- **Glassmorphism** for app bars and modals (BackdropFilter blur).
- **Hero animations** on poster taps (poster → detail screen morph).
- **Shimmer skeletons** during loading; never blank screens.
- **Motion**: Material 3 expressive easings; springs on interactive cards.
- **TV-ready typography**: 14sp body for mobile, 18sp for TV (scaled by `MediaQuery.size.shortestSide`).
- **Empty states**: illustrated, with CTAs.

## Testing strategy

- **Unit**: `awatv_core` parsers and clients (mock HTTP). >80% coverage target for parsers.
- **Widget**: key UI widgets in `awatv_ui` golden-tested.
- **Integration**: `apps/mobile/integration_test/` — add playlist, browse channels, play one channel.
- **CI**: GitHub Actions runs `flutter analyze && flutter test` on every push (added in Phase 0).

## Security

- Xtream credentials stored only in flutter_secure_storage (Keychain on iOS, EncryptedSharedPreferences on Android).
- All API calls over HTTPS. M3U URLs may be HTTP — warn user, don't reject.
- TMDB API key in `.env`, never committed; bundled at build time via `--dart-define=TMDB_API_KEY=...` for CI.
- No telemetry by default. Analytics opt-in only (Phase 2).

## Premium feature gates

| Feature | Free | Premium |
|---------|------|---------|
| Number of playlists | 2 | unlimited |
| Multi-screen / PiP | ❌ | ✓ |
| EPG history (past) | 1 day | 14 days |
| Ad-free | ❌ | ✓ |
| VLC backend choice | ❌ | ✓ |
| Cloud sync of favorites | ❌ | ✓ (Phase 3) |
| Parental controls | ❌ | ✓ |
| Custom themes | ❌ | ✓ |

Pricing (TBD by user): suggested €3.99/mo, €29.99/yr, €69.99 lifetime.

## Open questions for user (track here, resolve in chat)

1. Brand identity — color preference beyond indigo/purple? Logo?
2. Pricing tiers — confirm above or override.
3. AdMob publisher account — create now or use test IDs in dev?
4. TMDB API key — provide now or .env placeholder?
5. App store names — "AWAtv" final? Or different per-platform?
