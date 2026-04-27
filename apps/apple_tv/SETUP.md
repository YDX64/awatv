# AWAtv tvOS — Setup guide

Estimated setup time: **5 minutes** for the simulator, ~15 for a real
Apple TV.

## 1. Toolchain

- macOS 14 (Sonoma) or later, Apple Silicon strongly preferred.
- **Xcode 16+** (App Store). Earlier versions can't open
  `Package.swift` as a runnable app project.
- The bundled tvOS 17+ SDK and Apple TV simulator (Xcode → Settings →
  Platforms → tvOS).

If `xcode-select -p` points at `/Library/Developer/CommandLineTools` you
need to redirect it at the full IDE:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 2. Open the project

```bash
open /Users/max/AWAtv/apps/apple_tv/Package.swift
```

Xcode opens a SwiftPM workspace. Wait ~30 seconds for the indexer to
finish; you'll see `AWAtv` as the runnable scheme in the toolbar.

## 3. Run in the simulator

1. Click the run-destination dropdown (top of the window, left of the
   play button).
2. Pick **Apple TV 4K (3rd generation)** under "tvOS Simulators".
3. Hit `⌘R` (or click the play button).

The simulator launches. Use the on-screen Apple TV remote (`⌘⇧R` in
Simulator → Devices) to navigate. Arrow keys also work.

Sample flow:

1. Sidebar → **Settings** → **Add**
2. Pick **Xtream Codes**, fill in server / username / password.
3. Save. The app refreshes and populates Live / Movies / Series.
4. Pick a channel — `AVPlayerViewController` takes over with full
   Siri-Remote scrubbing.

## 4. Deploy to a real Apple TV (optional)

You need:

- A signing-capable Apple ID (free works for personal use, paid Apple
  Developer Program membership for TestFlight / App Store).
- An Apple TV 4 / 4K on the same Wi-Fi as the Mac, with **Remote App
  and Devices → Add Device** turned on (Settings → Apps → AirPlay…).
- Xcode → Settings → Accounts → add your Apple ID.

Then:

1. Project navigator → click `AWAtv` target → **Signing & Capabilities**.
2. Tick "Automatically manage signing" and pick your team.
3. Pair the Apple TV: in Xcode → Window → Devices and Simulators →
   Apple TV in the sidebar → "Pair" → enter the on-TV code.
4. Switch the run destination to the paired Apple TV and `⌘R`.

The first install asks you to trust the developer profile on the device:
Apple TV → Settings → General → Manage Apps → trust your Apple ID.

## 5. Eventual integration with `awatv_core`

When the Phase 5 backend ships:

```
api.awatv.app/v1/sources                POST    add a playlist
api.awatv.app/v1/sources/{id}/snapshot   GET     channels + vod + series
api.awatv.app/v1/sources/{id}/epg        GET     short EPG
api.awatv.app/v1/sources/{id}/series/{seriesId}/episodes  GET
```

The Codable models in `Sources/AWAtv/Models` already match the JSON
contract used by the Flutter side, so swapping the in-app `XtreamClient`
for a `BackendClient` is a localised change in `PlaylistStore`. The UI
doesn't need to know.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| "Could not build URL" on add | Ensure Xtream server starts with `http(s)://` |
| Playback fails immediately | Some streams require `User-Agent` rewriting; we send `AWAtv-tvOS/1.0` by default |
| Empty Live tab after sync | Check Settings → Playlists → last-sync timestamp; tap Refresh |
| Build fails on Xcode 15 | Upgrade to Xcode 16 — SwiftPM-app support landed there |
| Simulator remote feels off | Simulator → Devices → Apple TV Remote (⌘⇧R) |
