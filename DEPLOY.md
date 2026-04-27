# AWAtv — Deployment Runbook

End-to-end CI/CD: from your laptop to `tv.awastats.com` and beyond.

## Map

```
┌──────────────────────┐         git push          ┌─────────────────────┐
│  Local laptop (you)  │ ────────────────────────▶ │ GitHub: YDX64/awatv │
│  Flutter / Docker    │                            │  (private repo)     │
└──────────────────────┘                            └──────────┬──────────┘
        │                                                      │
        │ scripts/deploy-web.sh (manual)                       │ workflows
        │                                                      ▼
        │                                            ┌─────────────────────┐
        │                                            │  GitHub Actions     │
        │                                            │  - flutter.yml      │  CI matrix
        │                                            │  - deploy-web.yml   │  rsync deploy
        │                                            └──────────┬──────────┘
        │                                                       │ rsync over SSH
        ▼                                                       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  awastats.com server                                                     │
│  - nginx vhost: tv.awastats.com → /var/www/tv.awastats.com               │
│  - Let's Encrypt TLS (auto-renewing via certbot.timer)                   │
│  - Optional: Supabase (cloud or self-hosted) for sync/IAP/auth           │
└──────────────────────────────────────────────────────────────────────────┘
```

## TL;DR — get tv.awastats.com live

### 1. DNS

In your DNS provider (Cloudflare, Hetzner, GoDaddy, …):

```
tv.awastats.com   A    <your server IP>      300s   proxied=DNS-only (Cloudflare orange cloud OFF for first cert issuance)
```

Wait until `dig tv.awastats.com` returns the right IP from your laptop.

### 2. Server first-time setup (run ON the server)

SSH into your server, then:

```bash
# Pulls the setup script straight from your private GitHub repo:
gh auth setup-git   # one-time, makes git pulls work
git clone https://github.com/YDX64/awatv.git /opt/awatv
sudo DOMAIN=tv.awastats.com EMAIL=yunusd64@gmail.com bash /opt/awatv/scripts/setup-server.sh
```

What `setup-server.sh` does:
- installs `nginx`, `certbot`, `rsync`
- creates `/var/www/tv.awastats.com`
- writes a PWA-tuned nginx vhost (long-cache for hashed assets, no-cache for `index.html`/service-worker, permissive CSP for IPTV streams)
- issues a Let's Encrypt cert via webroot challenge
- enables `certbot.timer` for auto-renewal

After it finishes you'll see a placeholder page at https://tv.awastats.com.

### 3. Deploy from your laptop (manual)

```bash
cd /Users/max/AWAtv
DEPLOY_HOST=tv.awastats.com \
DEPLOY_USER=root \
DEPLOY_PATH=/var/www/tv.awastats.com \
./scripts/deploy-web.sh
```

It builds release web (~45s), rsyncs to server (~5s), and curls the URL to verify the AWAtv title is in the HTML. Re-run any time.

Re-deploying without rebuilding (same build, faster):
```bash
SKIP_BUILD=1 ./scripts/deploy-web.sh
```

Dry-run first (recommended on first attempt):
```bash
DRY_RUN=1 ./scripts/deploy-web.sh
```

### 4. Deploy from CI (push to main → automatic deploy)

Set the GitHub secrets once:

```bash
cd /Users/max/AWAtv
gh secret set DEPLOY_HOST --body=tv.awastats.com
gh secret set DEPLOY_USER --body=root              # or whichever non-root user
gh secret set DEPLOY_PATH --body=/var/www/tv.awastats.com
gh secret set DEPLOY_SSH_KEY < ~/.ssh/id_ed25519   # private key contents

# Optional: TMDB API key gets baked into the build's .env
gh secret set TMDB_API_KEY --body='<your-tmdb-v3-key>'
```

Then any push to `main` that touches `apps/mobile/**` or `packages/**` will trigger `.github/workflows/deploy-web.yml`. Manual trigger:

```bash
gh workflow run deploy-web.yml
gh run list --workflow=deploy-web.yml
gh run watch
```

## What's deployed

The build at `apps/mobile/build/web/` is a **PWA**. On a phone, when the user opens `tv.awastats.com` in Safari/Chrome and taps "Add to Home Screen", they get an icon that opens AWAtv full-screen with no browser chrome — almost indistinguishable from a native app.

The only platform-specific gap on web vs native: no background playback, no Picture-in-Picture by default (browser-permission gated), no native player codec support beyond what the browser provides (libmpv → web is built on HTML5 video; HEVC depends on the user's browser/OS).

For full native experience: open `https://github.com/YDX64/awatv` and follow the iOS/Android build instructions in `CLAUDE.md`.

---

## Local Postgres / Supabase development

The repo ships a complete Supabase backend at `supabase/` (migrations, RLS, edge functions). To run it locally:

### Prerequisites
- **Docker Desktop** running (`open -a Docker` on macOS)
- **Supabase CLI** installed (`brew install supabase/tap/supabase`) ✅ already installed

### Start the local stack

```bash
cd /Users/max/AWAtv
supabase start
```

First run pulls ~5 GB of Docker images (Postgres, Studio, Auth, Storage, Realtime, Inbucket). Subsequent runs are seconds.

Output gives you:
- API URL: `http://127.0.0.1:54321`
- DB URL: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`
- Studio: `http://127.0.0.1:54323`
- Inbucket (email testing): `http://127.0.0.1:54324`
- anon key + service_role key

Apply migrations:
```bash
supabase db reset   # drops + re-applies migrations + runs seed.sql
```

Wire up the mobile app to local Supabase:
```bash
cd apps/mobile
cat >> .env <<EOF
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<anon key from supabase start output>
EOF
flutter run
```

### Stop the local stack
```bash
supabase stop          # keeps data
supabase stop --no-backup   # wipes data
```

## Production Postgres / Supabase

Two paths:

### A. Supabase Cloud (recommended — easiest)
```bash
# 1. Create a project at https://supabase.com/dashboard
# 2. Link this repo to it:
supabase link --project-ref <your-project-ref>
# 3. Push migrations:
supabase db push
# 4. Deploy edge functions:
supabase functions deploy revenuecat-webhook --no-verify-jwt
supabase functions deploy tmdb-proxy
supabase functions deploy sync-snapshot
# 5. Set secrets:
supabase secrets set TMDB_API_KEY=<your-key>
supabase secrets set REVENUECAT_WEBHOOK_SECRET=<your-secret>
```

### B. Self-host on the same `awastats.com` server
See `supabase/README.md` for the long form. Short version:
```bash
# On the server:
cd /opt/awatv/supabase
docker compose up -d   # uses the official supabase/docker-compose.yml
```
Then expose `api.awastats.com → :8000` (Kong) via nginx and `db.awastats.com → :5432` only for migrations/admin (firewalled).

## GitHub Actions secrets reference

| Secret | Where used | Example |
|--------|-----------|---------|
| `DEPLOY_HOST` | deploy-web.yml | `tv.awastats.com` |
| `DEPLOY_USER` | deploy-web.yml | `root` or `deploy` |
| `DEPLOY_PATH` | deploy-web.yml | `/var/www/tv.awastats.com` |
| `DEPLOY_SSH_KEY` | deploy-web.yml | `-----BEGIN OPENSSH PRIVATE KEY-----…` |
| `TMDB_API_KEY` | flutter.yml + deploy-web.yml | TMDB v3 API key |
| `REVENUECAT_WEBHOOK_SECRET` | (future) | per RevenueCat dashboard |
| `SUPABASE_URL` | (future) | `https://xxx.supabase.co` |
| `SUPABASE_ANON_KEY` | (future) | from Supabase dashboard |
| `SUPABASE_SERVICE_ROLE_KEY` | (future, server-only) | from Supabase dashboard |

Set them all once with `gh secret set <name>` (see step 4 above).

## Roll back a bad deploy

```bash
# Find the previous successful Actions run:
gh run list --workflow=deploy-web.yml --status=success

# Re-run that exact commit's deploy:
gh run rerun <run-id>
```

Or manually:
```bash
git revert HEAD
git push origin main      # re-triggers deploy-web.yml from the previous good state
```

## Updating the app

The whole monorepo is designed for "merge to `main` → world updates":

| Change | Triggers |
|--------|----------|
| Anything in `apps/mobile/**` or `packages/**` | `flutter.yml` (build matrix) + `deploy-web.yml` (web only) |
| Anything in `supabase/migrations/**` | currently manual: `supabase db push` (CI step is a future PR) |
| Anything in `apps/apple_tv/**` | manual: open `Package.swift` in Xcode 15+ |
| `.github/workflows/**` | the changed workflow itself |

Mobile/native iOS+Android builds: tagged release flow (planned Phase 6 follow-up). For now, build locally and submit to TestFlight / Play Internal Testing manually.

## Troubleshooting

### "Cannot connect to the Docker daemon"
`open -a Docker` — wait 30s, retry `supabase start`.

### "Failed to issue cert: ACME challenge failed"
Check DNS propagation: `dig +short tv.awastats.com` from a public DNS (e.g. `dig +short tv.awastats.com @1.1.1.1`). If the A-record is wrong, fix it before re-running setup-server.sh.

### "rsync: connection unexpectedly closed"
- Verify SSH access: `ssh root@tv.awastats.com 'echo ok'`.
- Verify the `DEPLOY_SSH_KEY` secret has the **private** key (`id_ed25519`), not the public one.
- Verify the user has write access to `DEPLOY_PATH`.

### "PWA installs but doesn't update"
Service workers cache aggressively. Hit `chrome://serviceworker-internals` and Unregister the old SW, or clear site data in dev tools.

### "Site reachable but blank screen"
Check the browser console — missing CSP entries or wrong base href. The setup script assumes `--base-href=/`; if you deployed under a sub-path (e.g. `/awatv/`), rebuild with `--base-href=/awatv/` and adjust the nginx `root` accordingly.

## Status

| Component | Status |
|-----------|--------|
| GitHub repo | ✅ https://github.com/YDX64/awatv (private) |
| CI workflow (analyze + build matrix) | ✅ `.github/workflows/flutter.yml` |
| Deploy workflow (web → tv.awastats.com) | ✅ `.github/workflows/deploy-web.yml` (needs secrets) |
| Manual deploy script | ✅ `scripts/deploy-web.sh` |
| Server setup script | ✅ `scripts/setup-server.sh` |
| Local web build | ✅ `apps/mobile/build/web/` (PWA, offline-first) |
| Local Supabase | 🟡 ready, needs Docker Desktop running |
| DNS for tv.awastats.com | ⏳ user action |
| Production server provisioned | ⏳ user action |
| GitHub secrets configured | ⏳ user action |
