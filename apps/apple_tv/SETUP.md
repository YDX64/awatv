# AWAtv tvOS — Setup guide

Estimated setup time: **5 minutes** for the simulator,
~15 minutes for a real Apple TV.

This project is a SwiftUI tvOS app generated through
[xcodegen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is
**not committed** — every contributor regenerates it from `project.yml`.

---

## 1. Toolchain prerequisites

- macOS 14 (Sonoma) or later, Apple Silicon recommended.
- **Xcode 16+** with the bundled tvOS 17 SDK and Apple TV simulator
  (Xcode → Settings → Platforms → tvOS).
- Homebrew. If you don't have it:
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
- xcodegen:
  ```bash
  brew install xcodegen
  ```

If `xcode-select -p` points at `/Library/Developer/CommandLineTools` you
need to redirect it at the full IDE before any build:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

---

## 2. Generate the Xcode project

From the repo root:

```bash
cd apps/apple_tv
xcodegen generate
```

This reads `project.yml` and produces `AWAtv.xcodeproj` next to it.
You can re-run `xcodegen generate` any time the source layout or
build settings change — your `xcuserdata` and breakpoints survive
because xcodegen only touches the shared project files.

Then open it:

```bash
open AWAtv.xcodeproj
```

Wait ~30 seconds for the indexer to finish; you'll see `AWAtv` as
the runnable scheme in the toolbar.

---

## 3. Run in the simulator

1. Click the run-destination dropdown (top of the window, left of
   the play button).
2. Pick **Apple TV 4K (3rd generation)** under "tvOS Simulators".
3. Hit `⌘R` (or click the play button).

The simulator launches. Use the on-screen Apple TV remote
(`I/O → Remote` in the Simulator menu, shortcut `⌘⇧R`) to navigate.
Arrow keys also work.

CLI alternative once Xcode is configured:

```bash
xcodebuild \
  -project apps/apple_tv/AWAtv.xcodeproj \
  -scheme AWAtv \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  build
```

Sample flow inside the running app:

1. Sidebar → **Settings** → **Add**
2. Pick **Xtream Codes**, fill in server / username / password.
3. Save. The app refreshes and populates Live / Movies / Series.
4. Pick a channel — `AVPlayerViewController` takes over with full
   Siri-Remote scrubbing.

---

## 4. Deploy to a real Apple TV (optional)

You need:

- A signing-capable Apple ID (free works for personal use, paid
  Apple Developer Program membership for TestFlight / App Store).
- An Apple TV 4 / 4K on the same Wi-Fi as the Mac, with **Remote App
  and Devices → Add Device** turned on (Settings → Apps → AirPlay…).
- Xcode → Settings → Accounts → add your Apple ID.

Then:

1. In Xcode, select the `AWAtv` target → **Signing & Capabilities**.
2. Tick "Automatically manage signing" and pick your team.
   - The bundle identifier is `com.awatv.appletv`. If a personal
     team isn't authorised for that ID, change it to
     `com.<yourhandle>.awatv` before building. Edit
     `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` and re-run
     `xcodegen generate` to make the change permanent.
3. Pair the Apple TV: in Xcode → Window → Devices and Simulators →
   Apple TV in the sidebar → "Pair" → enter the on-TV code.
4. Switch the run destination to the paired Apple TV and `⌘R`.

The first install asks you to trust the developer profile on the
device: Apple TV → Settings → General → Manage Apps → trust your
Apple ID.

### TestFlight / App Store submission

Before submitting, replace the placeholder asset catalog:

1. Open `Resources/Assets.xcassets/App Icon & Top Shelf Image` in
   Xcode (it appears as a brand asset / layered tvOS icon).
2. Drop in three layered PNGs per icon size (front, middle, back —
   400×240 for app icon, 1280×768 for App Store, 1920×720 for
   the top-shelf image).
3. Archive: Product → Archive (with destination `Any tvOS Device`).
4. Window → Organizer → Distribute App → App Store Connect.

The ITSAppUsesNonExemptEncryption flag is already pre-set so the
encryption-export questionnaire is auto-answered.

---

## 5. Eventual integration with `awatv_core`

When the Phase 5 backend ships:

```
api.awatv.app/v1/sources                                  POST    add a playlist
api.awatv.app/v1/sources/{id}/snapshot                     GET     channels + vod + series
api.awatv.app/v1/sources/{id}/epg                          GET     short EPG
api.awatv.app/v1/sources/{id}/series/{seriesId}/episodes   GET
```

The Codable models in `Sources/AWAtv/Models` already match the
JSON contract used by the Flutter side, so swapping the in-app
`XtreamClient` for a `BackendClient` is a localised change in
`PlaylistStore`. The UI doesn't need to know.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `xcodegen: command not found` | `brew install xcodegen` |
| `xcodebuild` says only command-line tools available | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| "Could not build URL" on add | Ensure Xtream server starts with `http(s)://` |
| Playback fails immediately | Some streams require `User-Agent` rewriting; we send `AWAtv-tvOS/1.0` by default |
| Empty Live tab after sync | Check Settings → Playlists → last-sync timestamp; tap Refresh |
| Build fails on Xcode 15 | Upgrade to Xcode 16 — required for tvOS 17 SDK |
| Simulator remote feels off | Simulator → I/O → Remote (⌘⇧R) |
| "App icon set has no images" warning | Expected for the placeholder catalog. Drop real PNGs in before App Store submission (step 4 above). |
| Project changes don't apply | `xcodegen generate` again. The `.xcodeproj` is regenerated, never hand-edited. |
