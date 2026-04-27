-- ============================================================================
-- AWAtv — Local dev seed data
-- ----------------------------------------------------------------------------
-- This file is applied by `supabase db reset` (and the initial `supabase start`)
-- to give a fresh local stack a usable demo user. NEVER run against prod.
-- ============================================================================

-- A single demo user. The id is fixed so client integration tests can reference
-- it. Email is in the reserved example.com TLD so accidental real-world use is
-- harmless.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_user_meta_data, raw_app_meta_data,
  created_at, updated_at, confirmation_token, recovery_token
) values (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'demo@awatv.app',
  -- "password" hashed with bcrypt; only valid in local dev.
  '$2a$10$abcdefghijklmnopqrstuv1234567890ABCDEFGHIJKLMNOPQRSTUV',
  now(),
  jsonb_build_object('display_name', 'AWAtv Demo', 'locale', 'en'),
  jsonb_build_object('provider', 'email', 'providers', array['email']),
  now(),
  now(),
  '',
  ''
) on conflict (id) do nothing;

-- handle_new_user trigger fires on the insert above and creates the profile
-- row automatically — so we don't need an explicit profiles insert here. We
-- still upsert in case the trigger is disabled in some test contexts.
insert into public.profiles (user_id, display_name, avatar_url, locale)
values (
  '00000000-0000-0000-0000-000000000001',
  'AWAtv Demo',
  null,
  'en'
) on conflict (user_id) do nothing;

-- A premium subscription so paywall flows are not in the way during dev.
insert into public.subscriptions (
  user_id, plan, status, expires_at, will_renew, rc_app_user_id, rc_entitlement
) values (
  '00000000-0000-0000-0000-000000000001',
  'yearly',
  'active',
  now() + interval '1 year',
  true,
  '00000000-0000-0000-0000-000000000001',
  'premium'
) on conflict (user_id) do nothing;

-- One playlist source (no URLs, just sync metadata).
insert into public.playlist_sources (id, user_id, name, kind, client_id, added_at)
values (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000001',
  'Demo Xtream',
  'xtream',
  'demo-xtream-1',
  now() - interval '7 days'
) on conflict (user_id, client_id) do nothing;

-- A few favourites and history rows so "continue watching" + "favorites"
-- screens have something to render in dev.
insert into public.favorites (user_id, item_id, item_kind, added_at)
values
  ('00000000-0000-0000-0000-000000000001', 'demo-xtream-1::live-bbc-one',  'live',   now() - interval '6 days'),
  ('00000000-0000-0000-0000-000000000001', 'demo-xtream-1::vod-inception', 'vod',    now() - interval '3 days'),
  ('00000000-0000-0000-0000-000000000001', 'demo-xtream-1::series-mr-robot','series', now() - interval '1 day')
on conflict do nothing;

insert into public.watch_history (user_id, item_id, item_kind, position_seconds, total_seconds, watched_at)
values
  ('00000000-0000-0000-0000-000000000001', 'demo-xtream-1::vod-inception',     'vod',    3600, 8880,  now() - interval '12 hours'),
  ('00000000-0000-0000-0000-000000000001', 'demo-xtream-1::series-mr-robot-s1e1','series', 1450, 2820,  now() - interval '2 days')
on conflict (user_id, item_id) do update set
  position_seconds = excluded.position_seconds,
  total_seconds    = excluded.total_seconds,
  watched_at       = excluded.watched_at;

-- A heartbeat from a fictional iPhone so the multi-screen UI has a row.
insert into public.device_sessions (id, user_id, device_id, device_kind, platform, last_seen_at, user_agent)
values (
  '22222222-2222-2222-2222-222222222222',
  '00000000-0000-0000-0000-000000000001',
  'demo-iphone-1',
  'phone',
  'ios-17.4',
  now(),
  'AWAtv/1.0 (iPhone15,3; iOS 17.4)'
) on conflict (user_id, device_id) do update set last_seen_at = excluded.last_seen_at;
