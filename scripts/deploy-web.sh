#!/usr/bin/env bash
# Deploy AWAtv web build to tv.awastats.com (or any subdomain).
#
# Usage:
#   ./scripts/deploy-web.sh                    # uses defaults / env vars
#   DEPLOY_HOST=tv.awastats.com DEPLOY_USER=root DEPLOY_PATH=/var/www/tv ./scripts/deploy-web.sh
#
# Env vars:
#   DEPLOY_HOST        SSH host (default: tv.awastats.com)
#   DEPLOY_USER        SSH user (default: $USER)
#   DEPLOY_PATH        Remote web root (default: /var/www/tv.awastats.com)
#   DEPLOY_PORT        SSH port (default: 22)
#   SKIP_BUILD=1       Skip the flutter build step (re-deploy existing build)
#   DRY_RUN=1          rsync --dry-run only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/apps/mobile"

DEPLOY_HOST="${DEPLOY_HOST:-tv.awastats.com}"
DEPLOY_USER="${DEPLOY_USER:-$USER}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/tv.awastats.com}"
DEPLOY_PORT="${DEPLOY_PORT:-22}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
red()  { printf "\033[31m%s\033[0m\n" "$*"; }

bold "==> AWAtv web deploy"
echo "    Host: $DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PORT"
echo "    Path: $DEPLOY_PATH"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  bold "==> Resolving workspace dependencies"
  (cd "$ROOT" && flutter pub get >/dev/null)

  bold "==> Running code generation"
  (cd "$ROOT/packages/awatv_core" && dart run build_runner build --delete-conflicting-outputs)
  (cd "$APP_DIR" && dart run build_runner build --delete-conflicting-outputs)

  bold "==> Building web (release, offline-first PWA)"
  (cd "$APP_DIR" && flutter build web \
    --release \
    --pwa-strategy=offline-first \
    --no-tree-shake-icons \
    --base-href=/)
fi

if [[ ! -d "$APP_DIR/build/web" ]]; then
  red "ERROR: $APP_DIR/build/web not found. Run without SKIP_BUILD=1."
  exit 1
fi

bold "==> Smoke check the build"
test -f "$APP_DIR/build/web/index.html" || { red "index.html missing"; exit 1; }
test -f "$APP_DIR/build/web/manifest.json" || { red "manifest.json missing"; exit 1; }
grep -q "AWAtv" "$APP_DIR/build/web/index.html" || { red "AWAtv title missing"; exit 1; }

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  bold "==> rsync (DRY-RUN) to $DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH"
  rsync -azhv --dry-run --delete \
    -e "ssh -p $DEPLOY_PORT" \
    "$APP_DIR/build/web/" \
    "$DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH/"
else
  bold "==> rsync to $DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH"
  rsync -azh --delete \
    -e "ssh -p $DEPLOY_PORT" \
    "$APP_DIR/build/web/" \
    "$DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH/"
fi

bold "==> Verifying https://$DEPLOY_HOST/"
if curl -fsSL --max-time 15 "https://$DEPLOY_HOST/" | grep -q "AWAtv"; then
  bold "==> ✅ Deploy succeeded — https://$DEPLOY_HOST"
else
  red "Site reachable but AWAtv title not found. Check DNS / nginx / TLS."
  exit 1
fi
