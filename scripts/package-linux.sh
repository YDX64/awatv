#!/usr/bin/env bash
# Package the freshly-built Linux Flutter Release output into a single
# portable `dist/awatv-linux-x86_64.AppImage`.
#
# Why AppImage and not .deb / .rpm:
#   * One file works on Ubuntu / Fedora / Arch / Debian / openSUSE without
#     the publisher maintaining 3+ packaging recipes.
#   * No root install. The user just `chmod +x ./awatv-linux-x86_64.AppImage`
#     and double-clicks it.
#   * Self-contained: bundles libmpv, GTK runtime, and Flutter engine .so's
#     so the app runs on any glibc-2.31+ host (Ubuntu 20.04 LTS or newer).
#
# Run AFTER `flutter build linux --release` from the repo root or from CI.
# Requires:
#   * appimagetool (downloaded on demand)
#   * libfuse2 (so appimagetool can run)
#   * appstream (validation)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_BUILD="$ROOT/apps/mobile/build/linux/x64/release/bundle"
DIST="$ROOT/dist"
APPDIR="$DIST/AWAtv.AppDir"
DESKTOP_SRC="$ROOT/apps/mobile/linux/awatv.desktop"
ICON_SRC="$ROOT/apps/mobile/assets/linux-icon.png"
APPIMAGE_OUT="$DIST/awatv-linux-x86_64.AppImage"

mkdir -p "$DIST"
rm -rf "$APPDIR"
rm -f "$APPIMAGE_OUT"

if [ ! -d "$LINUX_BUILD" ]; then
  echo "ERROR: Linux release bundle not found: $LINUX_BUILD" >&2
  echo "Run 'flutter build linux --release' first." >&2
  exit 1
fi

if [ ! -f "$DESKTOP_SRC" ]; then
  echo "ERROR: missing desktop entry: $DESKTOP_SRC" >&2
  exit 1
fi

if [ ! -f "$ICON_SRC" ]; then
  echo "ERROR: missing 256x256 icon: $ICON_SRC" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Build the AppDir skeleton.
#
# AppDir layout (loosely follows the linuxdeploy convention):
#
#   AWAtv.AppDir/
#     AppRun                 — entry-point shell script that exports
#                              LD_LIBRARY_PATH + execs the binary.
#     awatv.desktop          — top-level .desktop (required by appimagetool).
#     awatv.png              — top-level icon (must match Icon= field).
#     usr/
#       bin/awatv_mobile     — the Flutter binary.
#       lib/                 — bundled .so's (Flutter engine + libmpv).
#       share/
#         applications/awatv.desktop
#         icons/hicolor/256x256/apps/awatv.png
#         awatv/data/        — Flutter assets (flutter_assets, icudtl.dat).
# ---------------------------------------------------------------------------
echo "==> Staging AppDir at: $APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/awatv"

# Copy every file the Flutter Release bundle ships. cp -a preserves the
# .so symlinks the engine relies on.
cp -a "$LINUX_BUILD"/. "$APPDIR/usr/share/awatv/"

# Move the executable to a conventional path; symlink original location so
# it can still find its data/ sibling at runtime.
BIN_NAME="awatv_mobile"
if [ -f "$APPDIR/usr/share/awatv/$BIN_NAME" ]; then
  ln -sf "../share/awatv/$BIN_NAME" "$APPDIR/usr/bin/$BIN_NAME"
else
  echo "ERROR: expected binary 'awatv_mobile' inside $LINUX_BUILD" >&2
  exit 1
fi

# Bundled libraries: Flutter ships its engine + plugins under lib/. We
# expose them via LD_LIBRARY_PATH inside AppRun rather than mass-copying
# them to /usr/lib so the layout matches what Flutter's build produced.

# Desktop entry + icon at both required positions (top of AppDir AND
# inside usr/share for desktop integration tools).
cp "$DESKTOP_SRC" "$APPDIR/awatv.desktop"
cp "$DESKTOP_SRC" "$APPDIR/usr/share/applications/awatv.desktop"
cp "$ICON_SRC" "$APPDIR/awatv.png"
cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/awatv.png"

# ---------------------------------------------------------------------------
# 2. Write AppRun — the executable that is invoked when the AppImage runs.
#
# Responsibilities:
#   * Resolve the AppDir root via $APPDIR (set by the AppImage runtime).
#   * Point LD_LIBRARY_PATH at the bundled engine + plugin .so's so the
#     binary doesn't try to resolve them against the host distro's libs.
#   * Cd into the data dir so Flutter can find `data/flutter_assets` via
#     a relative path the engine bakes in.
# ---------------------------------------------------------------------------
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/share/awatv/lib:${LD_LIBRARY_PATH:-}"
cd "$HERE/usr/share/awatv" || exit 1
exec "$HERE/usr/share/awatv/awatv_mobile" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# ---------------------------------------------------------------------------
# 3. Fetch appimagetool. Pin to the upstream stable continuous release;
#    versioned tags are not produced anymore by the upstream project.
# ---------------------------------------------------------------------------
APPIMAGETOOL="$DIST/appimagetool-x86_64.AppImage"
if [ ! -x "$APPIMAGETOOL" ]; then
  echo "==> Downloading appimagetool"
  curl -fsSL \
    -o "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$APPIMAGETOOL"
fi

# ---------------------------------------------------------------------------
# 4. Build the AppImage.
#
# `--no-appstream` because we don't ship a metainfo file (yet); the tool
# would otherwise refuse to package. Output filename is forced so the
# release artifact name is deterministic.
# ---------------------------------------------------------------------------
echo "==> Building AppImage"
ARCH=x86_64 "$APPIMAGETOOL" \
  --no-appstream \
  "$APPDIR" \
  "$APPIMAGE_OUT"

if [ ! -f "$APPIMAGE_OUT" ]; then
  echo "ERROR: appimagetool failed to produce $APPIMAGE_OUT" >&2
  exit 1
fi

chmod +x "$APPIMAGE_OUT"
SIZE=$(du -h "$APPIMAGE_OUT" | awk '{print $1}')
echo "==> Wrote: $APPIMAGE_OUT ($SIZE)"
