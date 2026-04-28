# Desktop auto-update

The desktop builds (macOS + Windows) ship with an in-app updater so users
do not have to revisit the GitHub Releases page every time we cut a new
version.

## High-level flow

1. CI builds `awatv-macos.{dmg,zip}` and `awatv-windows.{setup.exe,zip}`,
   uploads them to a `awatv-vX.Y.Z` GitHub Release, then computes their
   SHA-256 digests and writes `latest.json` alongside.
2. The app fires a silent `checkForUpdates` 5 seconds after first frame.
   It fetches `https://github.com/YDX64/awatv/releases/latest/download/latest.json`
   (a stable URL — GitHub redirects it to the most recent release).
3. If the manifest's `version` is newer than the running build, the
   updater stages an `UpdateAvailable` state and surfaces a snackbar.
4. The user opens **Ayarlar > Sürüm**, taps **İndir ve kur**. The app
   stream-downloads the platform-correct asset, verifies its SHA-256
   against the manifest, and stages `UpdateReadyToInstall`.
5. The user taps **Yeniden başlat ve yükle**. The app:
   - **macOS**: `ditto -x -k <zip> /Applications/`, strips
     `com.apple.quarantine`, `open -n` the new bundle, `exit(0)`.
   - **Windows**: detached-start the Inno installer with
     `/SILENT /SUPPRESSMSGBOXES /NORESTART`, `exit(0)`. The installer's
     `[Run]` section relaunches the freshly-installed binary.

The manifest schema is documented at the top of `scripts/build-update-manifest.sh`
and in `apps/mobile/lib/src/shared/updater/update_manifest.dart`.

## Force-update

Set `MIN_VERSION` when invoking `build-update-manifest.sh` to mark the
release as a hard floor. When the running build is older than that, the
in-app card hides the **Sonra** button and shows a **ZORUNLU** badge.

## Code-signing & notarisation

The current pipeline produces **unsigned** binaries. Consequences:

- **macOS**: Gatekeeper quarantines a freshly-extracted `.app`. The
  updater calls `xattr -dr com.apple.quarantine` after extraction so the
  user is not prompted on first launch. To produce notarised binaries,
  add an `Apple Developer ID` certificate to the macOS runner, sign the
  `.app` with `codesign --deep --options runtime`, then submit the `.zip`
  / `.dmg` to `xcrun notarytool submit … --wait` and `stapler staple`
  the result. The updater code does not need any changes.
- **Windows**: SmartScreen will warn on first run of an unsigned `.exe`.
  Add a code-signing certificate (Sectigo / DigiCert / SSL.com), wire
  `signtool sign` after the `iscc` step in `scripts/package-windows.ps1`,
  and the warning disappears.

The SHA-256 in the manifest is the only integrity guarantee until
signing is wired — the in-app updater rejects any payload whose digest
does not match, so a man-in-the-middle that swaps the asset bytes is
caught even on an unsigned channel.

## Updater file layout

```
apps/mobile/lib/src/shared/updater/
├── update_state.dart           ← sealed state machine
├── update_manifest.dart        ← latest.json parser + semver compare
├── updater_service.dart        ← Riverpod notifier (check/download/install)
├── updater_service.g.dart      ← Riverpod codegen (hand-maintained)
├── update_boot_check.dart      ← post-frame silent check + snackbar
└── update_settings_card.dart   ← Sürüm tile + Hakkında inline UI
```

## Cache locations

- macOS: `~/Library/Caches/<bundle-id>/updates/`
- Windows: `%LOCALAPPDATA%\<bundle-id>\updates\`

The updater only ever writes one file per release tag and overwrites any
prior partial download before the SHA check.
