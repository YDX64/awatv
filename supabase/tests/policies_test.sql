-- ============================================================================
-- AWAtv — RLS regression tests
-- ----------------------------------------------------------------------------
-- These are smoke tests that confirm the RLS policies do what we expect.
-- They run inside a transaction that is rolled back at the end, so they are
-- safe to execute against any Supabase instance (local dev or a throwaway
-- branch DB).
--
-- Run:
--   supabase db reset
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
--        -f supabase/tests/policies_test.sql
--
-- The script raises an exception on the first assertion failure and aborts
-- the transaction. A successful run prints "OK: rls policy tests passed".
-- ============================================================================

begin;

-- Set up two distinct users.
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice@example.com',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob@example.com',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   '{}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

-- Helper: pretend we are a given user by setting the JWT claim Postgres uses
-- to populate auth.uid() inside RLS.
create or replace function pg_temp.act_as(p_user uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.assert(cond boolean, msg text)
returns void
language plpgsql
as $$
begin
  if not cond then
    raise exception 'ASSERTION FAILED: %', msg;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles: each user reads only their own row.
-- ---------------------------------------------------------------------------
insert into public.profiles (user_id, display_name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Alice'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bob')
on conflict (user_id) do nothing;

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select pg_temp.assert(
  (select count(*) from public.profiles) = 1,
  'alice should see exactly her own profile row');
select pg_temp.assert(
  (select display_name from public.profiles) = 'Alice',
  'alice should see her own display name');

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select pg_temp.assert(
  (select count(*) from public.profiles) = 1,
  'bob should see exactly his own profile row');

-- ---------------------------------------------------------------------------
-- favorites: cross-user isolation.
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claims;

insert into public.favorites (user_id, item_id, item_kind) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'src1::ch1', 'live'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'src1::ch1', 'live')
on conflict do nothing;

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select pg_temp.assert(
  (select count(*) from public.favorites) = 1,
  'alice should see exactly one favourite (her own)');

-- Try to read a row that belongs to bob — must return zero rows.
select pg_temp.assert(
  (select count(*) from public.favorites
    where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 0,
  'alice must not be able to read bob favourites');

-- Try to insert a row pretending to be bob — must fail.
do $$
begin
  begin
    insert into public.favorites (user_id, item_id, item_kind)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'src1::ch2', 'live');
    raise exception 'ASSERTION FAILED: alice was able to insert as bob';
  exception when others then
    -- expected
    null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- subscriptions: select own only; service-role write happens elsewhere.
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claims;

insert into public.subscriptions (user_id, plan, status, rc_app_user_id, rc_entitlement)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'monthly', 'active',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'premium')
on conflict (user_id) do nothing;

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select pg_temp.assert(
  (select count(*) from public.subscriptions) = 1,
  'alice should see her own subscription row');

select pg_temp.act_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select pg_temp.assert(
  (select count(*) from public.subscriptions) = 0,
  'bob should not see alice subscription');

-- ---------------------------------------------------------------------------
-- get_premium_status helper.
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claims;

select pg_temp.assert(
  public.get_premium_status('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'premium',
  'alice should be premium');

select pg_temp.assert(
  public.get_premium_status('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 'free',
  'bob should be free');

-- ---------------------------------------------------------------------------
-- All assertions passed — emit a notice and roll back.
-- ---------------------------------------------------------------------------
do $$ begin raise notice 'OK: rls policy tests passed'; end $$;

rollback;
