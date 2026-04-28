#!/usr/bin/env bash
# build-update-manifest.sh
#
# Generates `dist/latest.json` — the manifest the in-app updater fetches
# from `https://github.com/<owner>/<repo>/releases/latest/download/latest.json`
# to discover newer desktop builds.
#
# Inputs (env):
#   RELEASE_TAG       e.g. "awatv-v0.3.0" (required when called from a release event)
#   RELEASE_VERSION   e.g. "0.3.0" — defaults to RELEASE_TAG with the leading
#                     "awatv-v" / "v" stripped.
#   RELEASE_NOTES     free-form markdown to embed in the manifest. Strips
#                     markdown headings to keep things simple. Optional.
#   MIN_VERSION       optional — when set, the in-app updater treats anything
#                     older than this as a forced update.
#   GH_OWNER          repo owner — defaults to "YDX64"
#   GH_REPO           repo name  — defaults to "awatv"
#
# Inputs (filesystem):
#   dist/awatv-macos.dmg       — required if present
#   dist/awatv-macos.zip       — required if present
#   dist/awatv-setup.exe       — required if present
#   dist/awatv-windows.zip     — required if present
#
# Output:
#   dist/latest.json
#
# The script SKIPS missing files instead of failing — a macOS-only run from
# a manual workflow_dispatch should still produce a manifest with just the
# macOS keys populated. CI invokes it once per platform and the final
# release-attach step uploads whichever subset it finds.
#
# SHA-256 is computed with shasum (BSD) on macOS, sha256sum (GNU) on Linux.
# The manifest stores the digest as lowercase hex — the in-app updater
# compares byte-by-byte against `crypto.sha256` output.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
MANIFEST="$DIST/latest.json"

mkdir -p "$DIST"

GH_OWNER="${GH_OWNER:-YDX64}"
GH_REPO="${GH_REPO:-awatv}"
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
MIN_VERSION="${MIN_VERSION:-}"

# Derive a clean version number from the release tag if RELEASE_VERSION
# wasn't passed in. We accept "awatv-v0.3.0", "v0.3.0", or "0.3.0".
if [ -z "${RELEASE_VERSION:-}" ]; then
  if [ -n "$RELEASE_TAG" ]; then
    RELEASE_VERSION="${RELEASE_TAG#awatv-v}"
    RELEASE_VERSION="${RELEASE_VERSION#v}"
  else
    # Fall back to pubspec.yaml's `version:` line so a manual run produces
    # something useful even without a release tag.
    RELEASE_VERSION="$(grep -E '^version: ' "$ROOT/apps/mobile/pubspec.yaml" \
      | head -n 1 \
      | awk '{print $2}' \
      | cut -d'+' -f1)"
  fi
fi

# Default minimum version = current version (no force update). Callers can
# override when shipping a critical bug fix.
if [ -z "$MIN_VERSION" ]; then
  MIN_VERSION="$RELEASE_VERSION"
fi

# Pick the right hashing tool. macOS ships `shasum`; Linux ships
# `sha256sum`. We never see Windows here because release-desktop.yml
# composes the manifest on the macOS runner (one OS does the merge).
if command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  HASH_CMD="shasum -a 256"
else
  echo "ERROR: neither sha256sum nor shasum is available on PATH" >&2
  exit 1
fi

hash_of() {
  local file="$1"
  $HASH_CMD "$file" | awk '{print $1}' | tr '[:upper:]' '[:lower:]'
}

size_of() {
  local file="$1"
  if stat -f%z "$file" >/dev/null 2>&1; then
    stat -f%z "$file"
  else
    stat -c%s "$file"
  fi
}

asset_url() {
  local file_name="$1"
  printf 'https://github.com/%s/%s/releases/download/%s/%s' \
    "$GH_OWNER" "$GH_REPO" "$RELEASE_TAG" "$file_name"
}

# Build a single channel entry "<key>": { ... } for each present asset.
channel_entries=()

emit_entry() {
  local key="$1"
  local file="$2"
  if [ ! -f "$file" ]; then
    echo "skip: $file (not present)"
    return 0
  fi
  local size
  local hash
  local url
  size="$(size_of "$file")"
  hash="$(hash_of "$file")"
  url="$(asset_url "$(basename "$file")")"
  channel_entries+=("\"$key\": {\"url\": \"$url\", \"sha256\": \"$hash\", \"size\": $size}")
  echo "added: $key -> $(basename "$file") ($size bytes, $hash)"
}

emit_entry "macos"             "$DIST/awatv-macos.dmg"
emit_entry "macos-zip"         "$DIST/awatv-macos.zip"
emit_entry "windows-installer" "$DIST/awatv-setup.exe"
emit_entry "windows-zip"       "$DIST/awatv-windows.zip"

if [ ${#channel_entries[@]} -eq 0 ]; then
  echo "ERROR: no recognised assets found in $DIST. Build at least one platform first." >&2
  exit 1
fi

# json-escape the release notes — handed to python3 so we pick up the
# canonical JSON string-encoding rules (backslash, quote, control-chars,
# unicode) without trying to roll our own with sed. python3 is shipped
# with every macOS-14 / ubuntu-latest runner and predates this workflow.
escape_json() {
  python3 - "$1" <<'PY'
import json, sys
sys.stdout.write(json.dumps(sys.argv[1])[1:-1])
PY
}

# Strip leading markdown headings so the manifest doesn't carry "## " etc.
notes_clean="$(printf '%s' "$RELEASE_NOTES" \
  | tr -d '\r' \
  | sed -E 's/^#+ //g')"
escaped_notes="$(escape_json "$notes_clean")"
released_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Serialize the channels.stable map. join_lines pads each entry with two
# leading spaces so the resulting JSON is human-readable.
joined=""
for ((i = 0; i < ${#channel_entries[@]}; i++)); do
  if [ $i -gt 0 ]; then
    joined+=$',\n      '
  else
    joined+="      "
  fi
  joined+="${channel_entries[$i]}"
done

cat > "$MANIFEST" <<EOF
{
  "version": "$RELEASE_VERSION",
  "releasedAt": "$released_at",
  "minimumVersion": "$MIN_VERSION",
  "notes": "$escaped_notes",
  "channels": {
    "stable": {
$joined
    }
  }
}
EOF

echo ""
echo "Manifest written: $MANIFEST"
cat "$MANIFEST"
