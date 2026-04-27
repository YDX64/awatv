-- ============================================================================
-- AWAtv — Row Level Security (RLS) policies
-- ----------------------------------------------------------------------------
-- Migration: 20260427000002_rls_policies
-- Author:    security-auditor + backend-architect agents
-- Purpose:   Enable RLS on every public table and define the minimum-privilege
--            policies that a Supabase anon/authenticated client may use.
--
-- Policy model
--   * Default deny: every table has RLS enabled with no permissive policy
--     until we add one explicitly.
--   * Each policy is keyed on auth.uid() = user_id. service_role bypasses
--     RLS at the engine level, so server-side workflows (RC webhook, edge
--     functions running with the service key) are not blocked.
--   * Telemetry: writeable by the user themselves, readable only by service
--     role (so no client can scrape another user's events).
--
-- Idempotency: drop policy if exists ... ; create policy ...
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Enable RLS on all seven public tables.
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.subscriptions     enable row level security;
alter table public.playlist_sources  enable row level security;
alter table public.favorites         enable row level security;
alter table public.watch_history     enable row level security;
alter table public.device_sessions   enable row level security;
alter table public.telemetry_events  enable row level security;

-- ---------------------------------------------------------------------------
-- profiles — user can read + update own row. Insert is via signup trigger.
-- ---------------------------------------------------------------------------
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = user_id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Insert is allowed so the signup trigger (handle_new_user) and clients
-- can create their own profile. The WITH CHECK forbids spoofing another user.
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- subscriptions — read own row only. All writes go through service_role
-- (RevenueCat webhook). Clients NEVER write here directly.
-- ---------------------------------------------------------------------------
drop policy if exists "subscriptions_select_own" on public.subscriptions;
create policy "subscriptions_select_own"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- playlist_sources — full CRUD on own rows only.
-- ---------------------------------------------------------------------------
drop policy if exists "playlist_sources_select_own" on public.playlist_sources;
create policy "playlist_sources_select_own"
  on public.playlist_sources for select
  using (auth.uid() = user_id);

drop policy if exists "playlist_sources_insert_own" on public.playlist_sources;
create policy "playlist_sources_insert_own"
  on public.playlist_sources for insert
  with check (auth.uid() = user_id);

drop policy if exists "playlist_sources_update_own" on public.playlist_sources;
create policy "playlist_sources_update_own"
  on public.playlist_sources for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "playlist_sources_delete_own" on public.playlist_sources;
create policy "playlist_sources_delete_own"
  on public.playlist_sources for delete
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- favorites — full CRUD on own rows only.
-- ---------------------------------------------------------------------------
drop policy if exists "favorites_select_own" on public.favorites;
create policy "favorites_select_own"
  on public.favorites for select
  using (auth.uid() = user_id);

drop policy if exists "favorites_insert_own" on public.favorites;
create policy "favorites_insert_own"
  on public.favorites for insert
  with check (auth.uid() = user_id);

drop policy if exists "favorites_update_own" on public.favorites;
create policy "favorites_update_own"
  on public.favorites for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "favorites_delete_own" on public.favorites;
create policy "favorites_delete_own"
  on public.favorites for delete
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- watch_history — full CRUD on own rows only.
-- ---------------------------------------------------------------------------
drop policy if exists "watch_history_select_own" on public.watch_history;
create policy "watch_history_select_own"
  on public.watch_history for select
  using (auth.uid() = user_id);

drop policy if exists "watch_history_insert_own" on public.watch_history;
create policy "watch_history_insert_own"
  on public.watch_history for insert
  with check (auth.uid() = user_id);

drop policy if exists "watch_history_update_own" on public.watch_history;
create policy "watch_history_update_own"
  on public.watch_history for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "watch_history_delete_own" on public.watch_history;
create policy "watch_history_delete_own"
  on public.watch_history for delete
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- device_sessions — full CRUD on own rows only.
-- ---------------------------------------------------------------------------
drop policy if exists "device_sessions_select_own" on public.device_sessions;
create policy "device_sessions_select_own"
  on public.device_sessions for select
  using (auth.uid() = user_id);

drop policy if exists "device_sessions_insert_own" on public.device_sessions;
create policy "device_sessions_insert_own"
  on public.device_sessions for insert
  with check (auth.uid() = user_id);

drop policy if exists "device_sessions_update_own" on public.device_sessions;
create policy "device_sessions_update_own"
  on public.device_sessions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "device_sessions_delete_own" on public.device_sessions;
create policy "device_sessions_delete_own"
  on public.device_sessions for delete
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- telemetry_events — write own only; read is service_role only.
--
-- The user can fire-and-forget events. They cannot read events back (privacy:
-- no client should be able to enumerate what another user did, and we don't
-- expose a user's own event history because the app doesn't need to display it).
-- ---------------------------------------------------------------------------
drop policy if exists "telemetry_events_insert_own" on public.telemetry_events;
create policy "telemetry_events_insert_own"
  on public.telemetry_events for insert
  with check (auth.uid() = user_id or user_id is null);

-- Explicitly: no select policy. RLS-enabled tables with no select policy
-- return zero rows for anon/authenticated. service_role bypasses RLS.

-- ---------------------------------------------------------------------------
-- handle_new_user — auto-create a profile row whenever auth.users gains a row.
--
-- Lives in public schema with security definer so it can write across schemas.
-- Trigger is attached on auth.users; that schema is owned by Supabase auth.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name, avatar_url, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data ->> 'avatar_url',
    coalesce(new.raw_user_meta_data ->> 'locale', 'en')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
