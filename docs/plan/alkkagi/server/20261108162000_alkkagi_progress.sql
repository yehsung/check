-- Alkkagi durable RAW completion counts. DRAFT, not a deployed migration.
-- Apply AFTER 20261108161000_alkkagi_matches.sql in one migration transaction,
-- using the SAME trusted non-API table owner. No top-level BEGIN/COMMIT here.
-- Installation locks matches and refuses existing finished rows: an administrator
-- must review any required backfill separately, never silently start at zero.
--
-- A canonical first finish records BOTH participants atomically. Raw counts
-- include resignations, draws and ring-outs; they are NOT award eligibility.
-- Before production, the administrator must map the actual private Gomoku
-- achievement/daily-mission eligibility rules, metadata and claim chain.
-- No rewards, thresholds, achievement/claim RPCs or shared busy helpers change.
--
-- Lifetime and KST-daily rows reference ONLY profiles, never retained matches.
-- Deleting a match cannot erase counts; deleting a profile erases its own counts.
-- Daily buckets use canonical finished_at, including late rolling finalization.
-- Owner-only alk_progress(uuid) returns played/wins/losses/draws, today_played/
-- today_wins/today_losses/today_draws, and kst_day as an ISO date. Missing counters
-- read as zero. API roles cannot call it or inspect/write counters or the guard.
-- The private claim chain must call this helper itself, never accept client counts.
--
-- AFTER UPDATE OF status also fires on SET status = status. The atomic NULL guard
-- handles repeats; its own UPDATE targets only the guard and cannot recurse.
-- https://www.postgresql.org/docs/18/sql-createtrigger.html

set local lock_timeout = '3s';

do $preflight$
declare
  r record;
  v_name text;
  v_owner oid := (select oid from pg_catalog.pg_roles where rolname = current_user);
begin
  if current_setting('lock_timeout') is distinct from '3s' then
    raise exception 'Alkkagi progress: apply the complete draft in one migration transaction';
  end if;
  if current_user in ('anon', 'authenticated', 'service_role') then
    raise exception 'Alkkagi progress: a trusted non-API migration owner is required';
  end if;
  foreach v_name in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_catalog.pg_roles where rolname = v_name) then
      raise exception 'Alkkagi progress: required API role % is missing', v_name;
    end if;
  end loop;
  for r in select * from (values
    ('profiles', 'id', 'pg_catalog.uuid'::regtype),
    ('alk_matches', 'id', 'pg_catalog.uuid'::regtype),
    ('alk_matches', 'black_id', 'pg_catalog.uuid'::regtype),
    ('alk_matches', 'white_id', 'pg_catalog.uuid'::regtype),
    ('alk_matches', 'status', 'pg_catalog.text'::regtype),
    ('alk_matches', 'result', 'pg_catalog.text'::regtype),
    ('alk_matches', 'finished_at', 'pg_catalog.timestamptz'::regtype)
  ) as required(relation_name, column_name, column_type) loop
    if not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass('public.' || r.relation_name)
        and a.attname = r.column_name and a.atttypid = r.column_type and not a.attisdropped
    ) then
      raise exception 'Alkkagi progress: required public.%.% field/type is missing', r.relation_name, r.column_name;
    end if;
  end loop;
  if not exists (select 1 from pg_catalog.pg_class c
                where c.oid = 'public.alk_matches'::regclass and c.relkind = 'r'
                  and c.relowner = v_owner and c.relrowsecurity) then
    raise exception 'Alkkagi progress: use the base matches table owner with RLS intact';
  end if;
  if not has_column_privilege(current_user, 'public.profiles', 'id', 'REFERENCES') then
    raise exception 'Alkkagi progress: profiles.id REFERENCES is required';
  end if;
  foreach v_name in array array['alk_progress_totals', 'alk_progress_daily'] loop
    if to_regclass('public.' || v_name) is not null then
      raise exception 'Alkkagi progress: refusing to replace existing relation public.%', v_name;
    end if;
  end loop;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname in ('alk_record_progress', 'alk_progress')) then
    raise exception 'Alkkagi progress: function names must be unused, including overloads';
  end if;
  if exists (select 1 from pg_catalog.pg_attribute a
             where a.attrelid = 'public.alk_matches'::regclass
               and a.attname = 'progress_recorded_at' and not a.attisdropped)
     or exists (select 1 from pg_catalog.pg_trigger t
                where t.tgrelid = 'public.alk_matches'::regclass and t.tgname = 'alk_matches_record_progress') then
    raise exception 'Alkkagi progress: guard column/trigger names must be unused';
  end if;
  -- Hold the eventual ALTER TABLE lock through installation. No finish may slip
  -- between the backfill check and trigger creation.
  lock table public.alk_matches in access exclusive mode;
  if exists (select 1 from public.alk_matches where status = 'finished') then
    raise exception 'Alkkagi progress: existing finished matches require a reviewed backfill before installation';
  end if;
end
$preflight$;

alter table public.alk_matches add column progress_recorded_at timestamptz;
comment on column public.alk_matches.progress_recorded_at is
  'Private atomic first-finish guard. Never accept from or return to API clients.';

create table public.alk_progress_totals (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  played bigint not null default 0 check (played >= 0),
  wins bigint not null default 0 check (wins >= 0),
  losses bigint not null default 0 check (losses >= 0),
  draws bigint not null default 0 check (draws >= 0),
  check (played = wins + losses + draws)
);

create table public.alk_progress_daily (
  user_id uuid not null references public.profiles(id) on delete cascade,
  kst_day date not null,
  played bigint not null default 0 check (played >= 0),
  wins bigint not null default 0 check (wins >= 0),
  losses bigint not null default 0 check (losses >= 0),
  draws bigint not null default 0 check (draws >= 0),
  primary key (user_id, kst_day),
  check (played = wins + losses + draws)
);

alter table public.alk_progress_totals enable row level security;
alter table public.alk_progress_daily enable row level security;
-- No API policies, including for reads. These are inputs to the PRIVATE claim chain.
revoke all on table public.alk_progress_totals, public.alk_progress_daily
  from public, anon, authenticated, service_role;

create function public.alk_record_progress()
returns trigger language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  m public.alk_matches%rowtype;
  v_user_id uuid;
  v_day date;
  v_wins bigint;
  v_losses bigint;
  v_draws bigint;
begin
  -- The outer match update already holds its row lock. Claim exactly once, in
  -- the SAME transaction as both counter upserts; any failure rolls it all back.
  update public.alk_matches g set progress_recorded_at = clock_timestamp()
    where g.id = new.id and g.status = 'finished' and g.progress_recorded_at is null
    returning g.* into m;
  if not found then return null; end if;
  if m.finished_at is null or m.result is null or m.result not in ('black', 'white', 'draw')
     or m.black_id is null or m.white_id is null or m.black_id = m.white_id then
    raise exception 'Alkkagi progress: invalid canonical finished match';
  end if;
  v_day := (m.finished_at at time zone 'Asia/Seoul')::date;
  -- Always use UUID order, independent of colors, across BOTH counter tables.
  for v_user_id in select u.user_id from unnest(array[m.black_id, m.white_id]) as u(user_id)
                  order by u.user_id loop
    v_wins := case when m.result = (case when v_user_id = m.black_id then 'black' else 'white' end) then 1 else 0 end;
    v_draws := case when m.result = 'draw' then 1 else 0 end;
    v_losses := 1 - v_wins - v_draws;
    insert into public.alk_progress_totals as t(user_id, played, wins, losses, draws)
      values (v_user_id, 1, v_wins, v_losses, v_draws)
      on conflict (user_id) do update set
        played = t.played + excluded.played, wins = t.wins + excluded.wins,
        losses = t.losses + excluded.losses, draws = t.draws + excluded.draws;
    insert into public.alk_progress_daily as d(user_id, kst_day, played, wins, losses, draws)
      values (v_user_id, v_day, 1, v_wins, v_losses, v_draws)
      on conflict (user_id, kst_day) do update set
        played = d.played + excluded.played, wins = d.wins + excluded.wins,
        losses = d.losses + excluded.losses, draws = d.draws + excluded.draws;
  end loop;
  return null;
end
$fn$;

create trigger alk_matches_record_progress
after update of status on public.alk_matches
for each row when (new.status = 'finished')
execute function public.alk_record_progress();

create function public.alk_progress(p_user_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog
as $fn$
  select jsonb_build_object(
    'played', coalesce(t.played, 0), 'wins', coalesce(t.wins, 0),
    'losses', coalesce(t.losses, 0), 'draws', coalesce(t.draws, 0),
    'today_played', coalesce(d.played, 0), 'today_wins', coalesce(d.wins, 0),
    'today_losses', coalesce(d.losses, 0), 'today_draws', coalesce(d.draws, 0),
    'kst_day', today.kst_day
  ) from (select (statement_timestamp() at time zone 'Asia/Seoul')::date as kst_day) today
  left join public.alk_progress_totals t on t.user_id = p_user_id
  left join public.alk_progress_daily d on d.user_id = p_user_id and d.kst_day = today.kst_day
$fn$;

comment on function public.alk_progress(uuid) is
  'Owner-only durable raw completion counts and current KST-day counts. Not achievement eligibility or a public RPC; integrate the actual private Gomoku award/claim rules before production.';

revoke all on function public.alk_record_progress(), public.alk_progress(uuid)
  from public, anon, authenticated, service_role;

do $assertions$
declare
  r record;
  v_role text;
begin
  for r in select c.* from pg_catalog.pg_class c
           where c.oid in ('public.alk_progress_totals'::regclass, 'public.alk_progress_daily'::regclass) loop
    if not r.relrowsecurity or exists (
      select 1 from pg_catalog.aclexplode(coalesce(r.relacl, pg_catalog.acldefault('r', r.relowner))) a
      where a.grantee <> r.relowner
    ) then raise exception 'Alkkagi progress: counter tables must be RLS-enabled and owner-only'; end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if has_table_privilege(v_role, r.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'Alkkagi progress: % has inherited/direct counter access', v_role;
      end if;
    end loop;
  end loop;
  for r in select p.* from pg_catalog.pg_proc p
           where p.oid in ('public.alk_record_progress()'::regprocedure, 'public.alk_progress(uuid)'::regprocedure) loop
    if not r.prosecdef or not ('search_path=pg_catalog' = any(r.proconfig)) or exists (
      select 1 from pg_catalog.aclexplode(coalesce(r.proacl, pg_catalog.acldefault('f', r.proowner))) a
      where a.grantee <> r.proowner
    ) then raise exception 'Alkkagi progress: functions must have a fixed search_path and owner-only grants'; end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if has_function_privilege(v_role, r.oid, 'EXECUTE') then
        raise exception 'Alkkagi progress: % has inherited/direct function access', v_role;
      end if;
    end loop;
  end loop;
  foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
    if has_column_privilege(v_role, 'public.alk_matches', 'progress_recorded_at', 'SELECT,INSERT,UPDATE,REFERENCES') then
      raise exception 'Alkkagi progress: % can inspect or forge the private completion guard', v_role;
    end if;
  end loop;
end
$assertions$;

notify pgrst, 'reload schema';
