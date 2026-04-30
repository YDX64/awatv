# AWAtv

Cross-platform freemium IPTV / streaming application.

**Targets:** iOS, Android, Apple TV, Android TV, macOS, Windows, Web (via Flutter).

**Status:** Phase 0 + Phase 1 in progress (mobile MVP).

## Screenshots

Captured against the live deployment at <https://awatv.pages.dev>.

| Onboarding (mobile) | Add Playlist (mobile) | Onboarding (desktop) |
|---|---|---|
| ![Onboarding mobile](store/screenshots/01-onboarding-mobile.png) | ![Add Playlist mobile](store/screenshots/02-add-playlist-mobile.png) | ![Onboarding desktop](store/screenshots/01-onboarding-desktop.png) |

> **Wave 13 smoke (2026-04-29):** the live `https://awatv.pages.dev`
> deployment currently fails to render the Flutter scene — see
> [`docs/SMOKE-TEST-RESULT.md`](docs/SMOKE-TEST-RESULT.md). The Wave-13
> screenshots above are intentionally blank to document this regression.
> Earlier (Wave 12) screenshots remain in
> [`store/screenshots/INDEX.md`](store/screenshots/INDEX.md) for marketing reference.

See [`store/screenshots/INDEX.md`](store/screenshots/INDEX.md) for the
full set (Wave 13 fresh PNGs + Wave 12 archive) and the
regeneration script at [`scripts/capture-screenshots.sh`](scripts/capture-screenshots.sh).

## Quick start

```bash
# Prereqs:
#   - Flutter 3.27+ (brew install --cask flutter)
#   - Xcode (for iOS) — sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#   - Android Studio or Android SDK

cd AWAtv
flutter pub get                        # resolves all workspace packages

# Mobile app
cd apps/mobile
cp .env.example .env                   # add TMDB_API_KEY here
flutter run                            # iOS Simulator / Android Emulator / device
```

## Repository layout

See [`CLAUDE.md`](CLAUDE.md) for full architecture and decisions.
See [`AGENT.md`](AGENT.md) for module-ownership rules used by parallel agents.
See [`docs/DESIGN.md`](docs/DESIGN.md) for the design specification.
See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the phased delivery plan.

## License

Private — proprietary. All rights reserved.
