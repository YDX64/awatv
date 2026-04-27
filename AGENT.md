# AGENT.md — AWAtv Parallel-Agent Coordination Contract

> Shared memory + interface contracts for agents working in parallel on AWAtv.
> Every agent MUST read this before writing code, and MAY append findings (via PR-style edit, not inline overwrites).

## Why this file exists

When multiple agents (or Claude sessions) work on AWAtv concurrently, they need:
1. A **single source of truth** for module boundaries and interfaces
2. A **non-overlapping work assignment** rule
3. A **conventions document** so all output looks like one codebase

## Module ownership (strict — do not write outside your zone)

| Zone | Path | Owner role |
|------|------|-----------|
| Core domain | `packages/awatv_core/` | "Core agent" (Dart specialist) |
| Design system | `packages/awatv_ui/` | "UI agent" (Flutter+UI/UX) |
| Player abstraction | `packages/awatv_player/` | "Player agent" (Flutter+media) |
| Mobile app shell | `apps/mobile/` | "App agent" (Flutter+mobile) |
| Docs | `docs/` | "Docs agent" |
| Root configs | `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, CI | **Coordinator only** (no agents touch root configs) |

If an agent needs a change in another zone, it writes a **Cross-zone request** comment in this file (see template at bottom).

## Public APIs (interface contracts — agents code against these signatures)

### `awatv_core` exports

```dart
// Models
class PlaylistSource {
  final String id;            // uuid
  final String name;          // user-given name
  final PlaylistKind kind;    // m3u | xtream
  final String url;           // m3u: full URL; xtream: server URL
  final String? username;     // xtream only
  final String? password;     // xtream only
  final String? epgUrl;       // optional override
  final DateTime addedAt;
  final DateTime? lastSyncAt;
}

enum PlaylistKind { m3u, xtream }

class Channel {
  final String id;            // stable composite: "${sourceId}::${tvgId ?? streamId ?? name}"
  final String sourceId;
  final String name;
  final String? tvgId;        // for EPG matching
  final String? logoUrl;
  final String streamUrl;     // resolved playable URL
  final List<String> groups;  // category path
  final ChannelKind kind;     // live | vod | series
}

enum ChannelKind { live, vod, series }

class VodItem { ... }       // movie
class SeriesItem { ... }    // series with seasons
class Episode { ... }
class EpgProgramme {
  final String channelTvgId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? description;
  final String? category;
}

// Parsers
abstract class M3uParser {
  static List<Channel> parse(String body, String sourceId);
}

abstract class XtreamClient {
  XtreamClient({ required String server, required String username, required String password });
  Future<List<Channel>> liveChannels();
  Future<List<VodItem>> vodItems();
  Future<List<SeriesItem>> series();
  Future<List<EpgProgramme>> shortEpg(String streamId);
}

// Services
abstract class PlaylistService {
  Future<PlaylistSource> add(PlaylistSource src);
  Future<void> refresh(String sourceId);
  Future<List<PlaylistSource>> list();
  Future<void> remove(String sourceId);
  Stream<List<Channel>> watchChannels(String sourceId);
}

abstract class MetadataService {  // TMDB-backed
  Future<MovieMetadata?> movieByTitle(String title, {int? year});
  Future<SeriesMetadata?> seriesByTitle(String title);
  Future<String?> trailerYoutubeId(int tmdbId, MediaType kind);
}

abstract class FavoritesService {
  Future<void> toggle(String channelId);
  Stream<Set<String>> watch();
}

abstract class HistoryService {
  Future<void> markPosition(String channelId, Duration position, Duration total);
  Future<List<HistoryEntry>> recent({int limit = 50});
  Future<Duration?> resumeFor(String channelId);
}
```

### `awatv_ui` exports

```dart
class AppTheme {
  static ThemeData dark();
  static ThemeData light();
}

class DesignTokens {
  static const radiusS = 8.0;
  static const radiusM = 12.0;
  static const radiusL = 20.0;
  // spacing, durations, blurs...
}

// Widgets: PosterCard, ChannelTile, GlassButton, BlurAppBar, ShimmerSkeleton, EmptyState, ErrorView, GradientScrim
```

### `awatv_player` exports

```dart
abstract class AwaPlayerController {
  static AwaPlayerController create(MediaSource src, {PlayerBackend backend = PlayerBackend.auto});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> dispose();
  Stream<PlayerState> states();
  Stream<Duration> positions();
}

enum PlayerBackend { auto, native, vlc }
class MediaSource { final String url; final Map<String, String>? headers; final String? userAgent; }
```

## Conventions (enforced by analysis_options.yaml)

- **Lints**: `flutter_lints` + `very_good_analysis` strict
- **Null safety**: required everywhere (Dart 3.x, sound NS)
- **Imports**: package-relative (`package:awatv_core/...`), never `../../../`
- **State**: Riverpod 2.5+ providers with code-gen (`@riverpod` annotation)
- **Async**: `Future<T>` returns, never `void` for async work
- **Errors**: typed exceptions in core (`PlaylistParseException`, `XtreamAuthException`); UI catches and maps to `AsyncError`
- **Naming**: `lowerCamel` for vars/funcs, `UpperCamel` for types, `snake_case.dart` for files
- **Tests**: every public function in `awatv_core` has at least one unit test in `packages/awatv_core/test/`
- **Comments**: only when WHY is non-obvious — see CLAUDE.md house rules

## Cross-zone request template

```
### Cross-zone request — <date> — <requesting agent>

**Need from:** <zone>
**Why:** <reason>
**Specifically:** <what API/file/change>
**Status:** open | resolved
```

## Active cross-zone requests

(none yet)

## Session log

### 2026-04-27 — Coordinator (Claude Opus 4.7)
- Bootstrapped monorepo structure
- Wrote CLAUDE.md, AGENT.md, README, docs/DESIGN.md, docs/ROADMAP.md
- Started Flutter SDK install in background
- Spawning parallel agents for: awatv_core, awatv_ui, awatv_player, mobile app
