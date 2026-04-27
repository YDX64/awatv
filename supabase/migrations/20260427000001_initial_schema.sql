-- ============================================================================
-- AWAtv — Initial schema
-- ----------------------------------------------------------------------------
-- Migration: 20260427000001_initial_schema
-- Author:    backend-architect agent
-- Purpose:   Create the seven core tables that back user accounts, premium
--            subscriptions, cross-device sync, and opt-in telemetry.
--
-- Conventions
--   * snake_case everywhere, matching Supabase / Postgres convention.
--   * All timestamps are timestamptz (UTC stored, locale-rendered client-side).
--   * Primary user id is uuid, sourced from auth.users via FK on delete cascade.
--   * No floats — all numeric magnitudes are integers (cents, seconds).
--   * Idempotent: every CREATE uses IF NOT EXISTS; safe to re-run.
-- ============================================================================

-- pgcrypto provides gen_random_uuid() used as a column default below.
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Generic helper: keeps an updated_at column fresh on every UPDATE.
-- Reused by triggers on profiles + subscriptions below.
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles — one row per authenticated user.
--
-- Mirrors / extends auth.users so the client can read display info without
-- hitting the auth schema (which has restrictive default permissions).
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url   text,
  -- BCP-47 tag, e.g. "en", "tr", "tr-TR". Defaults to "en" so server-side
  -- email templates have a sensible fallback.
  locale       text default 'en' not null,
  created_at   timestamptz default now() not null,
  updated_at   timestamptz default now() not null
);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

comment on table  public.profiles is 'Per-user display profile data; one row per auth.users row.';
comment on column public.profiles.locale is 'BCP-47 language tag used for emails / preferred UI language.';

-- ---------------------------------------------------------------------------
-- subscriptions — current premium entitlement state per user.
--
-- Source of truth is RevenueCat. The webhook function upserts here on every
-- INITIAL_PURCHASE / RENEWAL / CANCELLATION / EXPIRATION event.
-- Clients read this row to decide whether to show paywall vs unlocked UI.
-- ---------------------------------------------------------------------------
create table if not exists public.subscriptions (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  -- The plan key the user is on. Lifetime = one-time purchase, no renewal.
  plan           text not null check (plan in ('monthly', 'yearly', 'lifetime')),
  -- Lifecycle state from RC. in_grace = renewal failed but grace window open.
  status         text not null check (status in ('active', 'expired', 'cancelled', 'in_grace', 'trial')),
  expires_at     timestamptz,
  will_renew     boolean default false not null,
  -- The RevenueCat-side identity for this user (usually = auth.user.id, but
  -- stored explicitly so we can reconcile mismatched anon → linked transitions).
  rc_app_user_id text not null,
  -- The entitlement key configured in RC (e.g. "premium").
  rc_entitlement text not null,
  updated_at     timestamptz default now() not null
);

drop trigger if exists trg_subscriptions_updated_at on public.subscriptions;
create trigger trg_subscriptions_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

comment on table  public.subscriptions is 'Current premium subscription state, synced from RevenueCat webhooks.';
comment on column public.subscriptions.rc_app_user_id is 'RevenueCat appUserId — usually = auth.users.id but stored to handle aliases.';

-- ---------------------------------------------------------------------------
-- playlist_sources — opaque per-device sync metadata for user playlists.
--
-- IMPORTANT: This table NEVER stores M3U URLs, Xtream credentials, or any
-- secret. Those live encrypted on the device (flutter_secure_storage). The
-- server only knows: "user X has a source named Y of kind Z with stable
-- client id C". This lets us sync the *list* of playlists across a user's
-- devices without ever owning the credentials.
-- ---------------------------------------------------------------------------
create table if not exists public.playlist_sources (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text not null,
  kind          text not null check (kind in ('m3u', 'xtream')),
  -- The device-side stable id (PlaylistSource.id in awatv_core). The same
  -- source appears on multiple devices with the same client_id, which is why
  -- (user_id, client_id) is the natural sync key.
  client_id     text not null,
  added_at      timestamptz default now() not null,
  last_sync_at  timestamptz,
  unique (user_id, client_id)
);

comment on table  public.playlist_sources is 'Sync metadata for a users playlist list. NEVER contains URLs or credentials.';
comment on column public.playlist_sources.client_id is 'Device-side PlaylistSource.id; stable across devices for the same logical source.';

-- ---------------------------------------------------------------------------
-- favorites — synced favourite items.
--
-- item_id encodes both the source and the item: e.g. "<sourceId>::<channelId>".
-- This composite key lets a user have favourites across multiple playlist
-- sources without collisions.
-- ---------------------------------------------------------------------------
create table if not exists public.favorites (
  user_id    uuid not null references auth.users(id) on delete cascade,
  item_id    text not null,
  item_kind  text not null check (item_kind in ('live', 'vod', 'series')),
  added_at   timestamptz default now() not null,
  primary key (user_id, item_id)
);

comment on table  public.favorites is 'User favourites synced across devices. item_id = "<sourceId>::<channelId>".';

-- ---------------------------------------------------------------------------
-- watch_history — resume points + recently watched items.
--
-- Updated by the player every ~5s with the latest position. total_seconds is
-- redundant with the manifest length but kept here so the UI can render
-- progress bars without re-probing the source.
-- ---------------------------------------------------------------------------
create table if not exists public.watch_history (
  user_id           uuid not null references auth.users(id) on delete cascade,
  item_id           text not null,
  item_kind         text not null check (item_kind in ('live', 'vod', 'series')),
  position_seconds  integer not null default 0 check (position_seconds >= 0),
  total_seconds     integer not null default 0 check (total_seconds >= 0),
  watched_at        timestamptz default now() not null,
  primary key (user_id, item_id)
);

comment on table  public.watch_history is 'Resume positions + recently watched. Upserted every ~5s by the player.';

-- ---------------------------------------------------------------------------
-- device_sessions — track active devices for multi-screen-limit enforcement.
--
-- Free tier: 1 device, premium: 3+. The app heartbeats here on launch and
-- foreground-resume; cleanup removes rows older than 90 days.
-- ---------------------------------------------------------------------------
create table if not exists public.device_sessions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  device_id     text not null,
  device_kind   text not null check (device_kind in ('phone', 'tablet', 'tv', 'desktop', 'web')),
  -- Free-form platform identifier: "ios-17.4", "android-14", "macos-14.3", etc.
  platform      text not null,
  last_seen_at  timestamptz default now() not null,
  user_agent    text,
  unique (user_id, device_id)
);

comment on table  public.device_sessions is 'Active device registry per user; powers multi-screen limit + active-device list.';

-- ---------------------------------------------------------------------------
-- telemetry_events — opt-in analytics stream.
--
-- bigserial rather than uuid: this table is bulk-insert-heavy and the
-- numeric pkey gives a free time-ordering and tighter index footprint.
-- user_id is nullable on delete set null so "right to be forgotten" preserves
-- aggregate counts while detaching the user's identity.
-- ---------------------------------------------------------------------------
create table if not exists public.telemetry_events (
  id           bigserial primary key,
  user_id      uuid references auth.users(id) on delete set null,
  event        text not null,
  -- Free-form tags. Keep this lean (< 1 kB / row) for cheap analytics scans.
  properties   jsonb default '{}'::jsonb not null,
  occurred_at  timestamptz default now() not null
);

comment on table  public.telemetry_events is 'Opt-in product analytics. user_id nullable so deletes anonymise without losing aggregates.';
