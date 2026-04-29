#!/usr/bin/env bash
# AWAtv bundle-size guard.
#
# Builds the release artifacts for web + android-debug + macOS, measures
# each one, and exits non-zero when any artifact blows past the budget
# in docs/PERF-BUDGET.md.
#
# Usage:
#   ./scripts/measure-bundle-sizes.sh           # builds + measures
#   ./scripts/measure-bundle-sizes.sh --no-build # measures only
#   ./scripts/measure-bundle-sizes.sh --json    # machine-readable output
#
# Exit codes:
#   0  — every artifact under budget.
#   1  — at least one artifact over budget (or build failure).
#   2  — invalid usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOBILE_DIR="${REPO_ROOT}/apps/mobile"

# Budgets in megabytes (matches docs/PERF-BUDGET.md). Set deliberately
# generous — the script flags overshoots, not gentle drift.
BUDGET_WEB_MB=10        # build/web/ total (canvaskit included for now)
BUDGET_WEB_JS_MB=6      # main.dart.js alone
BUDGET_ANDROID_APK_MB=80 # debug build is bigger; release target is 30
BUDGET_MACOS_APP_MB=120  # release target is 80

BUILD=1
JSON=0

for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    --json)     JSON=1  ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *)
      echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# du in human form is fine for stdout but we need MB integers for budget
# arithmetic. `du -sk` is portable across BSD (macOS) + GNU (Linux).
size_mb() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "0"
    return 0
  fi
  local kb
  kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
  echo $(( (kb + 1023) / 1024 ))
}

log() {
  if [[ "$JSON" -eq 0 ]]; then
    printf '%s\n' "$*"
  fi
}

# 1. Build (unless --no-build).
if [[ "$BUILD" -eq 1 ]]; then
  log "==> Building release artifacts (web + android-debug + macOS)"
  pushd "$MOBILE_DIR" >/dev/null

  log "    flutter build web --release"
  flutter build web --release --no-tree-shake-icons || {
    log "    web build failed"; exit 1; }

  log "    flutter build apk --debug"
  flutter build apk --debug || {
    log "    android build failed"; exit 1; }

  if [[ "$(uname -s)" == "Darwin" ]]; then
    log "    flutter build macos --release"
    flutter build macos --release || {
      log "    macos build failed"; exit 1; }
  else
    log "    skipping macOS build (not on Darwin)"
  fi

  popd >/dev/null
fi

# 2. Measure each artifact.
WEB_TOTAL_MB=$(size_mb "${MOBILE_DIR}/build/web")
WEB_JS_MB=$(size_mb "${MOBILE_DIR}/build/web/main.dart.js")
APK_PATH="${MOBILE_DIR}/build/app/outputs/flutter-apk/app-debug.apk"
ANDROID_APK_MB=$(size_mb "$APK_PATH")
MACOS_APP=$(find "${MOBILE_DIR}/build/macos/Build/Products/Release" -maxdepth 2 -name "*.app" -type d 2>/dev/null | head -1 || true)
MACOS_APP_MB=$(size_mb "$MACOS_APP")

# 3. Compare against budgets, accumulate failures.
FAIL=0
check() {
  local label="$1" actual="$2" budget="$3"
  local status="OK"
  if (( actual > budget )); then
    status="OVER"
    FAIL=1
  fi
  if [[ "$JSON" -eq 1 ]]; then
    printf '{"artifact":"%s","actualMb":%s,"budgetMb":%s,"status":"%s"}\n' \
      "$label" "$actual" "$budget" "$status"
  else
    printf '  %-26s %4d MB / %4d MB  %s\n' "$label" "$actual" "$budget" "$status"
  fi
}

log ""
log "==> Bundle sizes vs budgets"
check "web (total)"       "$WEB_TOTAL_MB"   "$BUDGET_WEB_MB"
check "web/main.dart.js"  "$WEB_JS_MB"      "$BUDGET_WEB_JS_MB"
check "android apk debug" "$ANDROID_APK_MB" "$BUDGET_ANDROID_APK_MB"
check "macos .app"        "$MACOS_APP_MB"   "$BUDGET_MACOS_APP_MB"

if [[ "$FAIL" -eq 1 ]]; then
  log ""
  log "==> One or more artifacts blew the budget. See docs/PERF-BUDGET.md."
  exit 1
fi

log ""
log "==> All artifacts within budget."
exit 0
