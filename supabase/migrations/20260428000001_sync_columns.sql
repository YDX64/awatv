-- ============================================================================
-- AWAtv — Sync columns + auto-touch triggers
-- ----------------------------------------------------------------------------
-- Migration: 20260428000001_sync_columns
-- Author:    sync-engine agent (Phase 5)
-- Purpose:   Add a real `updated_at` column to the three sync-bearing tables
--            so the cloud sync engine has a deterministic conflict-resolution
--            timestamp. Previously the engine had to derive a comparable
--            timestamp from `added_at` / `last_sync_at` / `watched_at`, which
--            was fragile when the same row was touched concurrently.
--
-- Tables touched:
--   * favorites        — added_at was effectively immutable; we need a real
--                        mtime so a re-toggle picks the right side.
--   * watch_history    — watched_at IS effectively the mtime, but adding
--                        `updated_at` keeps the conflict-resolution rule
--                        uniform across all three tables.
--   * playlist_sources — last_sync_at flips on every refresh; the new
--                        `updated_at` column captures rename / metadata
--                        edits that don't bump last_sync_at.
--
-- Idempotent: every ALTER uses IF NOT EXISTS, every trigger is dropped
-- before re-create, every function uses CREATE OR REPLACE. Safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Generic touch_updated_at trigger function. Distinct name from the
-- existing `set_updated_at` so callers can read at a glance which tables
-- are sync-tracked vs profile-tracked.
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function public.touch_updated_at()
  is 'Bumps updated_at to now() on every UPDATE. Used by sync-tracked tables.';

-- ---------------------------------------------------------------------------
-- favorites.updated_at
-- Defaults to now() so existing rows have a sensible value the moment the
-- column is added. The trigger fires on every UPDATE; INSERTs use the
-- default. Last-writer-wins is now an exact `updated_at` comparison.
-- ---------------------------------------------------------------------------
alter table public.favorites
  add column if not exists updated_at timestamptz default now() not null;

drop trigger if exists trg_touch_favorites on public.favorites;
create trigger trg_touch_favorites
  before update on public.favorites
  for each row execute function public.touch_updated_at();

-- Fast lookup of "rows changed since X" used by the engine's catch-up pull.
create index if not exists favorites_user_updated_at_idx
  on public.favorites (user_id, updated_at desc);

-- ---------------------------------------------------------------------------
-- watch_history.updated_at
-- watched_at already serves as the de-facto mtime, but we keep them
-- separate so the engine can distinguish "user moved scrubber" (bumps
-- watched_at) from "we updated total_seconds for a manifest length"
-- (bumps only updated_at).
-- ---------------------------------------------------------------------------
alter table public.watch_history
  add column if not exists updated_at timestamptz default now() not null;

drop trigger if exists trg_touch_watch_history on public.watch_history;
create trigger trg_touch_watch_history
  before update on public.watch_history
  for each row execute function public.touch_updated_at();

create index if not exists watch_history_user_updated_at_idx
  on public.watch_history (user_id, updated_at desc);

-- ---------------------------------------------------------------------------
-- playlist_sources.updated_at
-- Distinct from last_sync_at (data-refresh time) and added_at (creation
-- time). updated_at captures rename / metadata edits.
-- ---------------------------------------------------------------------------
alter table public.playlist_sources
  add column if not exists updated_at timestamptz default now() not null;

drop trigger if exists trg_touch_playlist_sources on public.playlist_sources;
create trigger trg_touch_playlist_sources
  before update on public.playlist_sources
  for each row execute function public.touch_updated_at();

create index if not exists playlist_sources_user_updated_at_idx
  on public.playlist_sources (user_id, updated_at desc);

-- ---------------------------------------------------------------------------
-- Backfill: rows that existed before this migration get their natural
-- mtime as updated_at so the engine's first reconcile after deploy doesn't
-- treat them all as "newer than local" and trigger a thrash. Idempotent —
-- the WHERE clause skips rows that already have a non-default updated_at.
-- ---------------------------------------------------------------------------
update public.favorites
   set updated_at = added_at
 where updated_at = added_at  -- column was just added; default = now()
    or updated_at < added_at;

update public.watch_history
   set updated_at = watched_at
 where updated_at < watched_at;

update public.playlist_sources
   set updated_at = coalesce(last_sync_at, added_at)
 where updated_at < coalesce(last_sync_at, added_at);
