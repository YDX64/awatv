# AWAtv — Supabase backend

Infrastructure-as-code for the AWAtv backend: schema, RLS, indexes, helper
functions, and three Edge Functions (RevenueCat webhook, TMDB proxy, sync
snapshot). No Supabase project is created yet; everything here is committed
to the repo and applied with `supabase db push` once the project exists.

## Layout

```
supabase/
├── README.md                                  ← this file
├── config.toml                                ← project config (ports, auth, edge fns)
├── seed.sql                                   ← local dev seed data
├── migrations/
│   ├── 20260427000001_initial_schema.sql      ← seven tables + updated_at trigger
│   ├── 20260427000002_rls_policies.sql        ← RLS + handle_new_user trigger
│   ├── 20260427000003_indexes.sql             ← per-user composite indexes
│   └── 20260427000004_functions.sql           ← get_premium_status, device_count, ...
├── functions/
│   ├── _shared/cors.ts                        ← CORS preflight helper
│   ├── revenuecat-webhook/                    ← upserts subscriptions
│   ├── tmdb-proxy/                            ← keeps TMDB key server-side, 24h cache
│   └── sync-snapshot/                         ← single-call hydration payload
└── tests/
    └── policies_test.sql                      ← RLS regression tests
```

## Setup (one-time, on a fresh machine)

```bash
# 1. Install the Supabase CLI
brew install supabase/tap/supabase

# 2. From the repo root, initialise the local stack metadata
cd /Users/max/AWAtv
supabase init      # writes .gitignore + supabase/.gitignore; safe to re-run

# 3. Boot the local Postgres + GoTrue + PostgREST + Inbucket stack
supabase start

# 4. Apply the migrations + seed.sql
supabase db reset  # drops local DB, re-runs migrations, runs seed.sql

# 5. Sanity-check policies
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
     -f supabase/tests/policies_test.sql
```

## Linking to a hosted project

```bash
# Create the project in the Supabase dashboard, then:
supabase link --project-ref <your-project-ref>
supabase db push                                # applies migrations to prod
supabase functions deploy revenuecat-webhook
supabase functions deploy tmdb-proxy
supabase functions deploy sync-snapshot

# Set the secrets the functions read
supabase secrets set REVENUECAT_WEBHOOK_SECRET=...
supabase secrets set TMDB_API_KEY=...
# SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are auto-set
# by Supabase for deployed functions.
```

## Wiring into the Flutter app

`apps/mobile/.env` (do not commit) should contain:

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_ANON_KEY=<anon-key-from-dashboard>
```

The Dart side reads these via `--dart-define` at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

## What's stored, and what isn't

| Stored server-side                          | Stored only on device                     |
|---------------------------------------------|-------------------------------------------|
| Profile (display name, avatar, locale)      | M3U URLs                                  |
| Subscription state (from RevenueCat)        | Xtream usernames + passwords              |
| Playlist *metadata* (name, kind, client_id) | Decoded channel lists (parsed locally)    |
| Favourites + watch history                  | EPG cache                                 |
| Device sessions                             | TMDB metadata cache                       |
| Opt-in telemetry events                     |                                           |

Credentials live in `flutter_secure_storage` (Keychain on iOS,
EncryptedSharedPreferences on Android). The server never receives them.

## Edge functions at a glance

| Function              | Auth                     | Purpose                                        |
|-----------------------|--------------------------|------------------------------------------------|
| `revenuecat-webhook`  | Shared secret header     | Maps RC events → `public.subscriptions`        |
| `tmdb-proxy`          | Supabase JWT             | Forwards TMDB calls; caches GETs for 24 h      |
| `sync-snapshot`       | Supabase JWT             | One-call hydration of all per-user state       |

## Migration policy

* Migrations are append-only. Never edit a published migration.
* File naming: `YYYYMMDDHHMMSS_<short-description>.sql`.
* Every migration is idempotent (`if not exists`, `drop policy if exists`).
* Schema changes that are not backwards-compatible must ship paired
  client-side feature flags.
