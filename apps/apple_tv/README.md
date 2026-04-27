# AWAtv — Apple TV (tvOS) app

Native SwiftUI client for AWAtv on Apple TV. Flutter has no official tvOS
support, so this lives outside the Flutter monorepo as a standalone Swift
Package Manager project.

## What's here

A self-contained tvOS 17+ SwiftUI app with:

- Five top-level sections (Live, Movies, Series, Search, Settings) wired
  into a sidebar `TabView` and the native tvOS focus engine.
- Codable models that mirror the Dart freezed models in `awatv_core`
  (`Channel`, `VodItem`, `SeriesItem`, `Episode`, `EpgProgramme`,
  `PlaylistSource`).
- Real `URLSession` + async/await networking: `XtreamClient`,
  `M3UDownloader` (with `M3UParser`), and a `TmdbClient` for metadata.
- An `@Observable` `PlaylistStore` that mirrors Riverpod's
  `PlaylistService` lifecycle (add / refresh / persist).
- `PlayerView` wrapping `AVPlayerViewController` for HLS / TS / MP4
  playback with first-class Siri Remote support.
- A signature focus + scale + brand-purple glow on every focusable
  surface (`PosterCard`, `ChannelTile`, episode cards).

## Prerequisites

- macOS Sonoma or later
- **Xcode 16+** (older versions cannot open SwiftPM apps as a project)
- Apple TV simulator (bundled with Xcode)
- Optional: an Apple Developer membership to deploy to a real Apple TV

No Cocoapods, no Carthage, no Flutter. Just SwiftPM.

## Quick start

1. Open `apps/apple_tv/Package.swift` in Xcode 16+.
2. Pick the **Apple TV 4K (3rd generation)** simulator from the run
   destination dropdown.
3. Hit `⌘R`.
4. In Settings → Playlists, add an Xtream account or M3U URL.
5. Watch live channels, movies, and series.

See `SETUP.md` for the longer walkthrough and signing tips for physical
hardware.

## Project layout

```
Sources/AWAtv/
├── AWAtvApp.swift          @main entry, environment stores
├── ContentView.swift       Sidebar TabView with the 5 sections
├── HomeView.swift          Thin alias kept for spec parity
├── Theme/                  BrandColors, Typography, focusGlow modifier
├── Models/                 Codable mirrors of the Dart models
├── Networking/             XtreamClient, M3UParser, TmdbClient
├── Stores/                 PlaylistStore, PlayerStore (@Observable)
├── Screens/                Live, Movies, Series, Search, Settings, Player
└── Components/             Reusable focusable cards and tiles
```

## Eventual integration with `awatv_core`

In Phase 5 of the AWAtv roadmap, a small REST backend will expose the
same JSON contract these Codable models already decode. At that point:

1. Replace each `XtreamClient` instantiation in `PlaylistStore` with a
   single `BackendClient` that fetches
   `https://api.awatv.app/v1/sources/{id}/snapshot`.
2. Drop credentials from the device — the backend signs Xtream URLs.
3. Adopt CloudKit (or the same backend's `/sync` endpoints) for shared
   favourites and watch history with the iOS / Android apps.

Until then this app is fully self-contained: real HTTP, real parsing,
real playback.
