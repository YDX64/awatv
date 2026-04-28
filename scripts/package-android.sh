#!/usr/bin/env bash
# Package the freshly-built Android Flutter Release APKs into a stable set of
# user-facing filenames under dist/, ready for upload as CI artifacts or as
# release assets via `gh release upload`.
#
# Inputs (produced by `flutter build apk --release [--split-per-abi]`):
#   apps/mobile/build/app/outputs/flutter-apk/app-release.apk
#   apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#   apps/mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#   apps/mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk      (optional)
#
# Outputs:
#   dist/awatv-android-universal.apk      (multi-arch fat APK; mobile + TV)
#   dist/awatv-android-arm64.apk          (most modern phones + Android TV boxes)
#   dist/awatv-android-armeabi-v7a.apk    (older 32-bit devices)
#   dist/awatv-android-x86_64.apk         (only if produced; emulator / x86 TV)
#
# This script is intentionally idempotent and tolerant: any APK that does not
# exist is silently skipped so a build that omits split-per-abi still passes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_DIR="$ROOT/apps/mobile/build/app/outputs/flutter-apk"
DIST="$ROOT/dist"

mkdir -p "$DIST"

if [ ! -d "$APK_DIR" ]; then
  echo "ERROR: APK output directory not found: $APK_DIR" >&2
  echo "Run 'flutter build apk --release' first." >&2
  exit 1
fi

copy_if_present() {
  local src="$1"
  local dest="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dest"
    echo "  packaged $(basename "$dest") ($(du -h "$dest" | cut -f1))"
  else
    echo "  skipped  $(basename "$dest") (source missing: $(basename "$src"))"
  fi
}

echo "Packaging APKs into $DIST"
copy_if_present "$APK_DIR/app-release.apk"             "$DIST/awatv-android-universal.apk"
copy_if_present "$APK_DIR/app-arm64-v8a-release.apk"   "$DIST/awatv-android-arm64.apk"
copy_if_present "$APK_DIR/app-armeabi-v7a-release.apk" "$DIST/awatv-android-armeabi-v7a.apk"
copy_if_present "$APK_DIR/app-x86_64-release.apk"      "$DIST/awatv-android-x86_64.apk"

echo ""
echo "Packaging complete:"
ls -la "$DIST"
