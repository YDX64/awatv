# AWAtv Performance Budget

Wave 12 — quality gates before v0.4.0.

These targets are enforced by:
- **Widget benchmarks** in `apps/mobile/test/perf/*.dart`
- **Bundle-size guard** in `scripts/measure-bundle-sizes.sh`
- **Manual profiling** during release-cut for cold-start and frame rate

When a budget below regresses, fix the regression or update the budget
with a written justification in this file's revision history.

---

## Cold start (time-to-first-frame after launch)

Measured from the OS app-launch event to the first paint of `AwaTvApp`'s
MaterialApp.router. Excludes splash screen.

| Surface              | Target   | Hard ceiling |
| -------------------- | -------- | ------------ |
| iPhone 12 (iOS 17)   | < 2.0s   | 2.5s         |
| Pixel 7 (Android 14) | < 2.0s   | 2.5s         |
| Web (Chrome desktop) | < 3.0s   | 4.5s         |
| macOS 14 (M2)        | < 1.5s   | 2.0s         |
| Windows 11 (x64)     | < 1.5s   | 2.0s         |
| Linux (Ubuntu 24.04) | < 1.5s   | 2.0s         |
| Android TV (cube)    | < 2.5s   | 3.5s         |
| Apple TV (tvOS 17)   | < 2.0s   | 3.0s         |

## First meaningful frame

Time from "splash dismissed" to the first frame on which the user can
interact (home shell rendered, providers seeded, redirect chain settled).

| Surface     | Target  | Hard ceiling |
| ----------- | ------- | ------------ |
| All mobile  | < 300ms | 500ms        |
| Desktop     | < 250ms | 400ms        |
| Web         | < 600ms | 1.0s         |

## Frame rate

Steady-state target during a busy scrolling channel grid.

| Surface                 | Target FPS | p99 frame budget |
| ----------------------- | ---------- | ---------------- |
| Mobile (60Hz)           | 60         | 16.6ms           |
| Mobile (120Hz ProMotion)| 120        | 8.3ms            |
| Web (canvaskit)         | 60         | 16.6ms           |
| Desktop                 | 60         | 16.6ms           |
| TV (BravelyDefault)     | 60         | 16.6ms           |

## Bundle / artifact sizes

Measured after `flutter build <target> --release` with no symbol
stripping beyond the Flutter defaults. Numbers below are baseline as
of Wave 12 (2026-04-29) — the bundle-size script flags any regression
> 10% over budget.

| Artifact                         | Target  | Current baseline |
| -------------------------------- | ------- | ---------------- |
| Web (`build/web/` total)         | < 8 MB  | 41 MB (canvaskit included) |
| Web (`main.dart.js` only)        | < 6 MB  | 5.3 MB           |
| Android APK (split per-ABI, arm64-v8a) | < 30 MB | TBD — first benchmarked release |
| Android App Bundle (.aab)        | < 40 MB | TBD              |
| iOS .ipa (archived)              | < 50 MB | TBD              |
| macOS `.app`                     | < 80 MB | TBD              |
| Windows `.exe` + dlls            | < 40 MB | TBD              |
| Linux x64 bundle                 | < 50 MB | TBD              |

> Web baseline is intentionally above target because canvaskit is
> opt-in. Setting `--web-renderer html` or trimming canvaskit for
> auto-detect drops the total under 8 MB. Tracked separately under the
> Wave 13 web-perf milestone.

## Memory ceiling

Steady-state RSS during normal navigation + 4K playback.

| State              | Soft ceiling | Hard ceiling |
| ------------------ | ------------ | ------------ |
| Idle (home shell)  | 150 MB       | 250 MB       |
| Live grid + EPG    | 200 MB       | 350 MB       |
| 4K HDR playback    | 350 MB       | 500 MB       |
| Multi-stream (4x)  | 700 MB       | 1.0 GB       |

## Network

Steady-state egress during background / foreground states.

| State                 | Budget               |
| --------------------- | -------------------- |
| Idle background       | 0 KB/min             |
| Idle foreground       | < 50 KB/min          |
| Live grid + EPG sync  | < 500 KB / sync run  |
| Active playback (HD)  | provider-driven, no client-side overhead |

## Storage

Hive footprint after a 30-day daily-use session.

| Box                  | Target ceiling |
| -------------------- | -------------- |
| `sources`            | < 100 KB       |
| `channels:<source>`  | < 5 MB / source |
| `epg`                | < 25 MB        |
| `metadata` (TMDB)    | < 50 MB        |
| `history`            | < 5 MB         |
| Total                | < 100 MB       |

---

## Revision history

- **2026-04-29** — Wave 12 initial publish. Web baseline reflects
  the canvaskit-included build; Android / iOS baselines TBD until the
  first release-cut artifacts ship through CI.
