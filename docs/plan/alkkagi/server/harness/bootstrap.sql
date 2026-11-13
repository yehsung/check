-- Local test database only. Never apply this fixture to a Supabase project.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create role authenticator noinherit login password 'alkkagi-local-only';
grant anon, authenticated to authenticator;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $fn$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$fn$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url text,
  character text,
  visibility text not null default 'public',
  focus_mode integer not null default 0
);
create table public.fixture_blocks(a uuid, b uuid, primary key(a,b));
create function public.same_visibility(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $fn$
  select x.visibility = y.visibility from public.profiles x, public.profiles y
   where x.id = $1 and y.id = $2
$fn$;
create function public.blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $fn$
  select exists(select 1 from public.fixture_blocks x
                 where (x.a = $1 and x.b = $2) or (x.a = $2 and x.b = $1))
$fn$;
create function public.game__busy_users() returns table(user_id uuid)
language sql stable as $fn$ select null::uuid where false $fn$;

create schema realtime;
create table realtime.fixture_signals(payload jsonb, event text, topic text, private boolean);
create function realtime.send(payload jsonb, event text, topic text, private boolean)
returns void language sql as $fn$
  insert into realtime.fixture_signals values(payload,event,topic,private)
$fn$;

insert into auth.users values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222'),
 ('33333333-3333-4333-8333-333333333333'),
 ('44444444-4444-4444-8444-444444444444');
insert into public.profiles(id, display_name, character, visibility) values
 ('11111111-1111-4111-8111-111111111111','온라인 테스트 A','aing','public'),
 ('22222222-2222-4222-8222-222222222222','온라인 테스트 B','aing','public'),
 ('33333333-3333-4333-8333-333333333333','다른 사용자','aing','public'),
 ('44444444-4444-4444-8444-444444444444','비공개 사용자','aing','private');

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on function public.same_visibility(uuid,uuid), public.blocked_between(uuid,uuid),
 public.game__busy_users(), realtime.send(jsonb,text,text,boolean) from public, anon, authenticated;
