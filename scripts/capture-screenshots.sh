#!/usr/bin/env bash
# Capture production screenshots from https://awatv.pages.dev for the
# README, store listings, and marketing assets. Idempotent: re-running
# overwrites the existing PNGs in store/screenshots/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p store/screenshots

# Install Playwright transiently — we don't want it polluting any
# package.json that may exist elsewhere in the monorepo.
if [ ! -d node_modules/playwright ]; then
  echo "[capture] installing Playwright (transient, --no-save)..."
  npm install --no-save --silent playwright >/dev/null
fi

# Make sure Chromium is downloaded. --with-deps fails on macOS without
# sudo; fall back to the plain install which is enough for Chromium.
if ! npx playwright install chromium >/dev/null 2>&1; then
  npx playwright install --with-deps chromium
fi

echo "[capture] running scripts/capture-screenshots.js against ${AWATV_URL:-https://awatv.pages.dev}"
node scripts/capture-screenshots.js

echo "[capture] PNGs in store/screenshots/:"
ls -lh store/screenshots/*.png 2>/dev/null | awk '{print $9, $5}' | sed 's|.*store/screenshots/||'
