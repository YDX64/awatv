#!/usr/bin/env bash
# Package the freshly-built macOS Flutter Release output into:
#   1. dist/awatv-macos.zip — the .app bundle ready to drag into /Applications
#   2. dist/awatv-macos.dmg — a disk image for one-double-click installation
#
# Run AFTER `flutter build macos --release` from the repo root or from CI.
# Uses macOS-only tools (`ditto`, `hdiutil`) so this script is intentionally
# skipped on Linux / Windows runners.
#
# Code-signing is intentionally OUT OF SCOPE here. The produced .app/.dmg are
# unsigned — Gatekeeper will warn the end user on first launch. To sign:
#   codesign --deep --force --options runtime --sign "Developer ID Application: ..." "$APP"
#   xcrun notarytool submit "$DMG" --keychain-profile "AC_PASSWORD" --wait
#   xcrun stapler staple "$DMG"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUILD="$ROOT/apps/mobile/build/macos/Build/Products/Release"
DIST="$ROOT/dist"

mkdir -p "$DIST"

if [ ! -d "$APP_BUILD" ]; then
  echo "ERROR: macOS build directory not found: $APP_BUILD" >&2
  echo "Run 'flutter build macos --release' first." >&2
  exit 1
fi

# Locate the .app bundle. Flutter names this after the project's `name:` in
# pubspec.yaml — currently "awatv_mobile.app" but we don't hardcode that.
APP=$(find "$APP_BUILD" -maxdepth 1 -name "*.app" -type d | head -n 1)
if [ -z "$APP" ]; then
  echo "ERROR: no .app bundle found in $APP_BUILD" >&2
  exit 1
fi

APP_NAME=$(basename "$APP")
echo "Found app bundle: $APP_NAME"
echo "Source path:      $APP"

# 1. Produce a portable zip of the .app preserving macOS extended attributes
#    (resource forks, code-signing metadata, symlinks). `ditto` is the right
#    tool here — `zip -r` would corrupt symlinks inside frameworks.
ZIP_PATH="$DIST/awatv-macos.zip"
echo "Creating ZIP: $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"

# 2. Produce a UDZO-compressed DMG. The user can mount it, drag the .app to
#    /Applications, and eject. UDZO compression keeps the file small.
DMG_PATH="$DIST/awatv-macos.dmg"
echo "Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "AWAtv" \
  -srcfolder "$APP" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo ""
echo "Packaging complete:"
ls -la "$DIST"
