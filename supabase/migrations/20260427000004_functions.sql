-- ============================================================================
-- AWAtv — SQL helper functions
-- ----------------------------------------------------------------------------
-- Migration: 20260427000004_functions
-- Author:    backend-architect + database-admin agents
-- Purpose:   Server-side helpers that encapsulate small bits of business
--            logic the clients (and edge functions) call repeatedly.
--
-- All functions are stable / immutable where possible, and security definer
-- only when they need to read across schemas.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- get_premium_status(p_user_id) → 'free' | 'premium'
--
-- Single source of truth for premium gating. Reads subscriptions and treats
-- 'active', 'trial' and 'in_grace' as premium; everything else (including no
-- row at all) is free. Lifetime never expires.
-- ---------------------------------------------------------------------------
create or replace function public.get_premium_status(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when s.user_id is null then 'free'
    when s.plan = 'lifetime' and s.status in ('active', 'trial', 'in_grace') then 'premium'
    when s.status in ('active', 'trial', 'in_grace')
         and (s.expires_at is null or s.expires_at > now()) then 'premium'
    else 'free'
  end
  from public.subscriptions s
  where s.user_id = p_user_id;
$$;

comment on function public.get_premium_status(uuid)
  is 'Returns "premium" if the user has an active / trial / in_grace subscription, else "free".';

-- ---------------------------------------------------------------------------
-- device_count(p_user_id) → integer
--
-- Number of distinct devices that have heartbeated within the last 30 days.
-- Used to enforce the multi-screen limit at session start.
-- ---------------------------------------------------------------------------
create or replace function public.device_count(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.device_sessions
  where user_id = p_user_id
    and last_seen_at > now() - interval '30 days';
$$;

comment on function public.device_count(uuid)
  is 'Number of distinct devices active for the user in the last 30 days.';

-- ---------------------------------------------------------------------------
-- cleanup_stale_devices() → integer
--
-- Removes device_sessions rows that haven't heartbeated in 90 days.
-- Returns the number of rows deleted.
--
-- Schedule via Supabase pg_cron in production:
--   select cron.schedule('cleanup-stale-devices', '0 4 * * *',
--                        $$select public.cleanup_stale_devices();$$);
-- ---------------------------------------------------------------------------
create or replace function public.cleanup_stale_devices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  delete from public.device_sessions
   where last_seen_at < now() - interval '90 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.cleanup_stale_devices()
  is 'Removes device_sessions older than 90 days. Returns rows deleted.';

-- ---------------------------------------------------------------------------
-- touch_device_session(p_user_id, p_device_id, p_device_kind, p_platform, p_user_agent)
--
-- Idempotent upsert called on app launch / foreground-resume. Handles the
-- "first time we see this device" case and the "regular heartbeat" case.
-- ---------------------------------------------------------------------------
create or replace function public.touch_device_session(
  p_user_id     uuid,
  p_device_id   text,
  p_device_kind text,
  p_platform    text,
  p_user_agent  text default null
)
returns public.device_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.device_sessions;
begin
  insert into public.device_sessions (user_id, device_id, device_kind, platform, user_agent, last_seen_at)
  values (p_user_id, p_device_id, p_device_kind, p_platform, p_user_agent, now())
  on conflict (user_id, device_id) do update
     set last_seen_at = excluded.last_seen_at,
         device_kind  = excluded.device_kind,
         platform     = excluded.platform,
         user_agent   = excluded.user_agent
  returning * into v_row;
  return v_row;
end;
$$;

comment on function public.touch_device_session(uuid, text, text, text, text)
  is 'Upsert helper for the device heartbeat: bumps last_seen_at, refreshes platform metadata.';

-- Allow the authenticated role to call these helpers; service_role can call
-- everything by default.
grant execute on function public.get_premium_status(uuid) to authenticated;
grant execute on function public.device_count(uuid)       to authenticated;
grant execute on function public.touch_device_session(uuid, text, text, text, text) to authenticated;
-- cleanup_stale_devices intentionally service_role only — it's a job, not a client API.
revoke execute on function public.cleanup_stale_devices() from public, anon, authenticated;
