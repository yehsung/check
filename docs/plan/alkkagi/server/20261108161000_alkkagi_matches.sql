-- Alkkagi authoritative matches, protocol 1. DRAFT, not a deployed migration.
-- Apply AFTER 20261108160000_alkkagi_physics.sql, in one migration transaction.
-- There is deliberately no top-level BEGIN/COMMIT and no replacement of private
-- production helpers, global Realtime policies, cron jobs, or other games' SQL.
-- PostgreSQL SECURITY DEFINER guidance:
-- https://www.postgresql.org/docs/18/sql-createfunction.html
--
-- Dependencies are mandatory, including real visibility/blocking decisions.
-- A local-only harness must supply its own synthetic dependencies BEFORE this
-- file; this draft never installs permissive fallback helpers.
-- The applying role must be a trusted, non-API owner with access to profiles and
-- EXECUTE on the dependencies. API roles must not inherit that owner role.
-- New object names must be unused. A rerun fails rather than replacing unknown SQL.
--
-- Exclusivity is local to Alkkagi. Integrate owner-only public.alk_busy(uuid)
-- into the existing shared game-busy mechanism before cross-game rollout; its
-- unknown existing definition is intentionally not altered here.
-- Feature presence is separate from private client_devices: authenticated
-- protocol-1 lobby calls refresh only their own alk_clients row. Peers/targets
-- must have announced protocol 1 within 24 hours; old clients receive no invites.
--
-- Bounded history / retention contract:
-- * Store one current board and one latest shot, not a trajectory/event history.
-- * Keep the latest 200 chat messages, with a monotonic, never-reset chat_seq.
--   A cursor older than the retained window receives the remaining recent tail.
--   Muting is a member display preference: messages/cursors still synchronize.
-- * Keep successful action IDs until their match is deleted. Never time-prune
--   action IDs from an active match: an old retry must not become a new action.
--   At 16,384 recorded actions reject new nonterminal writes as rate_limited;
--   cancel/respond/resign/leave remain available. This caps an abandoned active
--   match without inventing a time limit or automatically resigning a player.
-- * Before deployment, arrange operator-owned retention: delete terminal invites
--   after one day and finished matches after 30 days (always after the 120-second
--   chat grace). Cascades remove members/actions/chat. No scheduler is added.
--   Active matches are never silently deleted or auto-resigned. Account deletion
--   cascades from EITHER profiles.id through the match and all of its records.
-- * Lobby peers and incoming invites are each capped at 200; invites expire at
--   their absolute timestamp even if lazy status persistence has not run yet.
--
-- All normal responses use {status,protocol:1,server_now_ms,me,state}; pending
-- invitations additionally include outgoing or incoming. Lobby includes both
-- invite fields, and users only when p_users is true. Nonmembers get not_found.
-- Delivery failures never undo state; private poke hints contain no chat/board.
-- Polling repairs missed hints. Expected-revision failures include current state.
-- During rolling, deadline_ms retains the shooter's original aiming deadline;
-- the client freezes remaining time at max(0, (deadline_ms-started_at_ms)/1000).
-- rolling_result stays private: wire result is null until phase = finished.

set local lock_timeout = '3s';

do $preflight$
declare
  v_signature text;
  v_name text;
  v_oid oid;
begin
  if current_setting('lock_timeout') is distinct from '3s' then
    raise exception 'Alkkagi: apply the complete draft in one migration transaction';
  end if;
  if current_user in ('anon', 'authenticated', 'service_role') then
    raise exception 'Alkkagi: a trusted non-API migration owner is required';
  end if;
  if current_setting('server_encoding') <> 'UTF8' then
    raise exception 'Alkkagi: UTF8 is required for the Unicode codepoint chat limit';
  end if;
  foreach v_name in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_catalog.pg_roles r where r.rolname = v_name) then
      raise exception 'Alkkagi: required API role % is missing', v_name;
    end if;
  end loop;
  if to_regclass('public.profiles') is null or not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass('public.profiles') and a.attname = 'id'
      and a.atttypid = 'pg_catalog.uuid'::regtype and not a.attisdropped
  ) then
    raise exception 'Alkkagi: public.profiles with UUID id is required';
  end if;
  if not has_table_privilege(current_user, 'public.profiles', 'SELECT')
     or not has_column_privilege(current_user, 'public.profiles', 'id', 'REFERENCES') then
    raise exception 'Alkkagi: migration owner needs SELECT and id REFERENCES on profiles';
  end if;
  foreach v_signature in array array[
    'auth.uid()', 'public.same_visibility(uuid,uuid)',
    'public.blocked_between(uuid,uuid)', 'realtime.send(jsonb,text,text,boolean)',
    'public.alkkagi_simulate(jsonb,integer,double precision,double precision)'
  ] loop
    v_oid := to_regprocedure(v_signature);
    if v_oid is null or not has_function_privilege(current_user, v_oid, 'EXECUTE') then
      raise exception 'Alkkagi: required executable dependency % is missing/inaccessible', v_signature;
    end if;
  end loop;
  if (select p.prorettype from pg_catalog.pg_proc p where p.oid = 'auth.uid()'::regprocedure)
       <> 'pg_catalog.uuid'::regtype
     or (select p.prorettype from pg_catalog.pg_proc p
         where p.oid = 'public.same_visibility(uuid,uuid)'::regprocedure) <> 'pg_catalog.bool'::regtype
     or (select p.prorettype from pg_catalog.pg_proc p
         where p.oid = 'public.blocked_between(uuid,uuid)'::regprocedure) <> 'pg_catalog.bool'::regtype
     or (select p.prorettype from pg_catalog.pg_proc p
         where p.oid = 'public.alkkagi_simulate(jsonb,integer,double precision,double precision)'::regprocedure)
          <> 'pg_catalog.jsonb'::regtype then
    raise exception 'Alkkagi: dependency return types do not match the required contract';
  end if;
  foreach v_name in array array[
    'alk_clients', 'alk_matches', 'alk_match_members', 'alk_match_actions', 'alk_chat_messages'
  ] loop
    if to_regclass('public.' || v_name) is not null then
      raise exception 'Alkkagi: refusing to replace existing relation public.%', v_name;
    end if;
  end loop;
  if exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (
      left(p.proname, 4) = 'alk_' or p.proname = any(array[
        'alkkagi_lobby', 'alkkagi_challenge', 'alkkagi_cancel', 'alkkagi_respond',
        'alkkagi_state', 'alkkagi_place', 'alkkagi_ready', 'alkkagi_shoot',
        'alkkagi_resign', 'alkkagi_leave', 'alkkagi_chat_send', 'alkkagi_chat_mute'
      ])
    )
  ) then
    raise exception 'Alkkagi: new helper/RPC names must be unused; inspect existing definitions first';
  end if;
end
$preflight$;

create table public.alk_clients (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  protocol integer not null check (protocol = 1),
  last_seen_at timestamptz not null
);
create index alk_clients_recent on public.alk_clients(last_seen_at, user_id);

create table public.alk_matches (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  black_id uuid not null references public.profiles(id) on delete cascade,
  white_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'finished', 'cancelled', 'declined', 'expired')),
  revision integer not null default 1 check (revision > 0),
  phase text check (phase in ('placing_black', 'placing_white', 'aiming', 'rolling', 'finished')),
  current_player text not null default 'black' check (current_player in ('black', 'white')),
  stones jsonb not null check (jsonb_typeof(stones) = 'array' and jsonb_array_length(stones) = 10),
  invite_expires_at timestamptz not null,
  deadline_at timestamptz,
  roll_until timestamptz,
  shot jsonb,
  shot_count integer not null default 0 check (shot_count >= 0),
  rolling_result text check (rolling_result in ('black', 'white', 'draw')),
  result text check (result in ('black', 'white', 'draw')),
  finish_reason text,
  finished_at timestamptz,
  chat_seq integer not null default 0 check (chat_seq >= 0),
  action_count integer not null default 0 check (action_count >= 0),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  check (black_id <> white_id),
  check (
    (status in ('pending', 'cancelled', 'declined', 'expired') and phase is null and result is null)
    or (status = 'active' and phase is not null and phase in ('placing_black', 'placing_white', 'aiming', 'rolling')
        and result is null and finished_at is null)
    or (status = 'finished' and phase is not null and phase = 'finished' and result is not null and finished_at is not null)
  ),
  check (
    case
      when phase is null or phase = 'finished' then deadline_at is null and roll_until is null
      when phase = 'rolling' then deadline_at is not null and roll_until is not null and shot is not null
      else deadline_at is not null and roll_until is null
    end
  )
);

create unique index alk_matches_one_pending_outgoing on public.alk_matches(black_id)
  where status = 'pending';
create index alk_matches_incoming on public.alk_matches(white_id, invite_expires_at, id)
  where status = 'pending';
create index alk_matches_terminal_retention on public.alk_matches(status, updated_at)
  where status <> 'active';

create table public.alk_match_members (
  match_id uuid not null references public.alk_matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  color text not null check (color in ('black', 'white')),
  is_active boolean not null default true,
  muted boolean not null default false,
  left_at timestamptz,
  last_chat_at timestamptz,
  joined_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (match_id, user_id),
  unique (match_id, color)
);
-- Unlike two separate color indexes, this enforces one active match across BOTH colors.
create unique index alk_match_members_one_active on public.alk_match_members(user_id)
  where is_active;
create index alk_match_members_unleft on public.alk_match_members(user_id, joined_at desc)
  where left_at is null;

create table public.alk_match_actions (
  match_id uuid not null references public.alk_matches(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  action_id uuid not null,
  kind text not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (actor_id, match_id, action_id)
);
-- challenge has no match ID until creation; its retry lookup is actor-scoped too.
create unique index alk_match_actions_challenge_retry on public.alk_match_actions(actor_id, action_id)
  where kind = 'challenge';

create table public.alk_chat_messages (
  match_id uuid not null references public.alk_matches(id) on delete cascade,
  seq integer not null check (seq > 0),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 100 and body ~ '[^[:space:]]'),
  sent_at timestamptz not null,
  primary key (match_id, seq),
  foreign key (match_id, sender_id) references public.alk_match_members(match_id, user_id) on delete cascade
);

alter table public.alk_clients enable row level security;
alter table public.alk_matches enable row level security;
alter table public.alk_match_members enable row level security;
alter table public.alk_match_actions enable row level security;
alter table public.alk_chat_messages enable row level security;
-- No direct-table policies. The trusted table owner enters only through guarded RPCs.
revoke all on table public.alk_clients, public.alk_matches, public.alk_match_members,
  public.alk_match_actions, public.alk_chat_messages from public, anon, authenticated, service_role;

create function public.alk_ms(p_at timestamptz)
returns double precision language sql immutable strict security invoker
set search_path = pg_catalog
as $fn$ select (extract(epoch from p_at) * 1000)::double precision $fn$;

create function public.alk_lock_users(p_first uuid, p_second uuid)
returns void language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
begin
  -- Same namespace and UUID ordering for challenge/respond. No global mutex.
  perform pg_advisory_xact_lock(hashtextextended('alkkagi/user/' || least(p_first, p_second)::text, 0));
  if p_first <> p_second then
    perform pg_advisory_xact_lock(hashtextextended('alkkagi/user/' || greatest(p_first, p_second)::text, 0));
  end if;
end
$fn$;

create function public.alk_initial_stones()
returns jsonb language sql immutable security invoker
set search_path = pg_catalog
as $fn$
  select jsonb_agg(jsonb_build_object(
    'id', s.id, 'owner', case when s.id < 5 then 'black' else 'white' end,
    'position', jsonb_build_object('x', (array[80,190,300,410,520])[s.id % 5 + 1],
                                  'y', case when s.id < 5 then 460 else 140 end),
    'velocity', jsonb_build_object('x', 0, 'y', 0), 'isOut', false, 'isPlaced', false
  ) order by s.id) from generate_series(0, 9) as s(id)
$fn$;

create function public.alk_can_place(
  p_stones jsonb, p_color text, p_stone_id integer, p_x double precision, p_y double precision
)
returns boolean language sql immutable security invoker
set search_path = pg_catalog
as $fn$
  select coalesce(
    p_stone_id between 0 and 9 and p_color in ('black', 'white')
    and (p_stones -> p_stone_id ->> 'id')::integer = p_stone_id
    and (p_stones -> p_stone_id ->> 'owner') = p_color
    and not (p_stones -> p_stone_id ->> 'isOut')::boolean
    and p_x between 20 and 580 and p_y between 20 and 580
    and case when p_color = 'black' then p_y >= 320 else p_y <= 280 end
    and not exists (
      select 1 from jsonb_array_elements(p_stones) as s(stone)
      where (s.stone ->> 'id')::integer <> p_stone_id
        and (s.stone ->> 'isPlaced')::boolean and not (s.stone ->> 'isOut')::boolean
        and point(p_x, p_y) <-> point((s.stone #>> '{position,x}')::double precision,
                                      (s.stone #>> '{position,y}')::double precision) < 42
    ), false)
$fn$;

create function public.alk_autofill(p_stones jsonb, p_color text)
returns jsonb language plpgsql immutable security invoker
set search_path = pg_catalog
as $fn$
declare
  v_stones jsonb := p_stones;
  v_id integer;
  v_x double precision;
  v_y double precision;
  v_row integer;
  v_column integer;
  v_found boolean;
begin
  -- At most 5 * (1 + 7 * 14) candidates; placed stones never move.
  for v_id in (case when p_color = 'black' then 0 else 5 end)..
              (case when p_color = 'black' then 4 else 9 end) loop
    if (v_stones -> v_id ->> 'isPlaced')::boolean then continue; end if;
    v_x := (array[80,190,300,410,520])[v_id % 5 + 1];
    v_y := case when p_color = 'black' then 460 else 140 end;
    v_found := public.alk_can_place(v_stones, p_color, v_id, v_x, v_y);
    if not v_found then
      <<grid>>
      for v_row in 0..6 loop
        v_y := (case when p_color = 'black' then 320 else 20 end) + v_row * 42;
        for v_column in 0..13 loop
          v_x := 20 + v_column * 42;
          if public.alk_can_place(v_stones, p_color, v_id, v_x, v_y) then
            v_found := true;
            exit grid;
          end if;
        end loop;
      end loop;
    end if;
    if not v_found then raise exception 'Alkkagi: bounded placement grid exhausted'; end if;
    v_stones := jsonb_set(v_stones, array[v_id::text],
      (v_stones -> v_id) || jsonb_build_object(
        'position', jsonb_build_object('x', v_x, 'y', v_y),
        'velocity', jsonb_build_object('x', 0, 'y', 0), 'isPlaced', true));
  end loop;
  return v_stones;
end
$fn$;

create function public.alk_busy(p_user_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog
as $fn$
  select exists (select 1 from public.alk_match_members m where m.user_id = p_user_id and m.is_active)
$fn$;

comment on function public.alk_busy(uuid) is
  'Owner-only Alkkagi active membership check. Shared cross-game busy integration is required separately; no existing helper is replaced.';

create function public.alk_peer(p_user_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog
as $fn$
  select jsonb_build_object(
    'id', p.id,
    'display_name', coalesce(nullif(to_jsonb(p) ->> 'display_name', ''),
                             nullif(to_jsonb(p) ->> 'nickname', ''), '사용자'),
    'avatar_url', to_jsonb(p) ->> 'avatar_url',
    'character_id', to_jsonb(p) ->> 'character',
    'busy', public.alk_busy(p.id)
  ) from public.profiles p where p.id = p_user_id
$fn$;

create function public.alk_notify(p_match_id uuid, p_revision integer)
returns void language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select m.black_id from public.alk_matches m where m.id = p_match_id
    union all
    select m.white_id from public.alk_matches m where m.id = p_match_id
  loop
    begin
      perform realtime.send(jsonb_build_object('v', 1, 'm', p_match_id, 'revision', p_revision),
                            'alkkagi', 'poke:' || v_user_id::text, true);
    exception when others then
      -- Persist the action even if one delivery fails; still try the other member.
      null;
    end;
  end loop;
end
$fn$;

create function public.alk_advance(p_match_id uuid, p_now timestamptz)
returns public.alk_matches language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  m public.alk_matches%rowtype;
  v_before integer;
  v_passes bigint;
begin
  select g.* into m from public.alk_matches g where g.id = p_match_id for update;
  if not found then return null; end if;
  -- Callers without a pre-held row lock pass NULL, so lock waits cannot leave
  -- their snapshot based on a timestamp taken before the wait.
  p_now := coalesce(p_now, clock_timestamp());
  v_before := m.revision;
  if m.status = 'pending' and m.invite_expires_at <= p_now then
    m.status := 'expired';
    m.revision := m.revision + 1;
  end if;
  if m.status = 'active' then
    -- Each stage runs at most once. Advance from OLD deadlines, not poll time.
    if m.phase = 'placing_black' and m.deadline_at <= p_now then
      m.stones := public.alk_autofill(m.stones, 'black');
      m.phase := 'placing_white'; m.current_player := 'white';
      m.deadline_at := m.deadline_at + interval '30 seconds';
      m.revision := m.revision + 1;
    end if;
    if m.phase = 'placing_white' and m.deadline_at <= p_now then
      m.stones := public.alk_autofill(m.stones, 'white');
      m.phase := 'aiming'; m.current_player := 'black';
      m.deadline_at := m.deadline_at + interval '30 seconds';
      m.revision := m.revision + 1;
    end if;
    if m.phase = 'rolling' and m.roll_until <= p_now then
      if m.rolling_result is not null then
        m.status := 'finished'; m.phase := 'finished';
        m.result := m.rolling_result; m.finish_reason := 'ring_out';
        m.finished_at := m.roll_until; m.deadline_at := null;
      else
        m.phase := 'aiming';
        m.current_player := case when m.current_player = 'black' then 'white' else 'black' end;
        m.deadline_at := m.roll_until + interval '30 seconds';
      end if;
      m.roll_until := null; m.rolling_result := null;
      m.revision := m.revision + 1;
    end if;
    if m.phase = 'aiming' and m.deadline_at <= p_now then
      v_passes := floor(extract(epoch from (p_now - m.deadline_at)) / 30)::bigint + 1;
      if v_passes % 2 = 1 then
        m.current_player := case when m.current_player = 'black' then 'white' else 'black' end;
      end if;
      m.deadline_at := m.deadline_at + interval '30 seconds' * v_passes::double precision;
      m.revision := (m.revision::bigint + v_passes)::integer;
    end if;
  end if;
  if m.revision <> v_before then
    m.updated_at := p_now;
    update public.alk_matches g set
      status = m.status, phase = m.phase, current_player = m.current_player,
      stones = m.stones, deadline_at = m.deadline_at, roll_until = m.roll_until,
      rolling_result = m.rolling_result, result = m.result, finish_reason = m.finish_reason,
      finished_at = m.finished_at, revision = m.revision, updated_at = m.updated_at
    where g.id = m.id;
    if m.status = 'finished' then
      update public.alk_match_members a set is_active = false where a.match_id = m.id and a.is_active;
    end if;
    perform public.alk_notify(m.id, m.revision);
  end if;
  return m;
end
$fn$;

create function public.alk_snapshot(p_match_id uuid, p_user_id uuid, p_since_chat_seq integer)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  m public.alk_matches%rowtype;
  a public.alk_match_members%rowtype;
  v_chat jsonb := '[]'::jsonb;
begin
  select g.* into m from public.alk_matches g
    where g.id = p_match_id and p_user_id in (g.black_id, g.white_id) and g.phase is not null;
  if not found then return null; end if;
  select g.* into a from public.alk_match_members g where g.match_id = m.id and g.user_id = p_user_id;
  if not found then return null; end if;
  if a.left_at is null and (m.status = 'active' or
      (m.status = 'finished' and clock_timestamp() < m.finished_at + interval '120 seconds')) then
    select coalesce(jsonb_agg(jsonb_build_object(
      'seq', c.seq, 'sender_id', c.sender_id, 'body', c.body, 'sent_at_ms', public.alk_ms(c.sent_at)
    ) order by c.seq), '[]'::jsonb) into v_chat
    from public.alk_chat_messages c
    where c.match_id = m.id and c.seq > greatest(coalesce(p_since_chat_seq, 0), 0);
  end if;
  return jsonb_build_object(
    'id', m.id, 'revision', m.revision, 'phase', m.phase,
    'current_player', m.current_player, 'my_color', a.color,
    'black', public.alk_peer(m.black_id), 'white', public.alk_peer(m.white_id),
    'stones', m.stones, 'deadline_ms', public.alk_ms(m.deadline_at),
    'shot_count', m.shot_count, 'result', m.result, 'finish_reason', m.finish_reason,
    'shot', m.shot, 'chat_seq', m.chat_seq, 'chat', v_chat, 'muted', a.muted
  );
end
$fn$;

create function public.alk_response(p_status text, p_user_id uuid, p_match_id uuid, p_since_chat_seq integer)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  v_response jsonb;
  m public.alk_matches%rowtype;
  v_invite jsonb;
begin
  v_response := jsonb_build_object(
    'status', p_status, 'protocol', 1, 'server_now_ms', public.alk_ms(clock_timestamp()),
    'me', public.alk_peer(p_user_id),
    'state', public.alk_snapshot(p_match_id, p_user_id, p_since_chat_seq)
  );
  select g.* into m from public.alk_matches g
    where g.id = p_match_id and p_user_id in (g.black_id, g.white_id);
  if found and m.status = 'pending' and m.invite_expires_at > clock_timestamp()
     and public.same_visibility(m.black_id, m.white_id) is true
     and public.blocked_between(m.black_id, m.white_id) is false then
    v_invite := jsonb_build_object('id', m.id,
      'opponent', public.alk_peer(case when p_user_id = m.black_id then m.white_id else m.black_id end),
      'expires_at_ms', public.alk_ms(m.invite_expires_at));
    if p_user_id = m.black_id then
      v_response := v_response || jsonb_build_object('outgoing', v_invite);
    else
      v_response := v_response || jsonb_build_object('incoming', jsonb_build_array(v_invite));
    end if;
  end if;
  return v_response;
end
$fn$;

-- One guarded dispatcher keeps membership, clocks, revisions and retries identical
-- across thin wire wrappers. It is owner-only, never itself an API entry point.
create function public.alk_match_call(
  p_operation text, p_match_id uuid, p_action_id uuid, p_expected_revision integer,
  p_payload jsonb, p_protocol integer
)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  v_uid uuid := auth.uid();
  m public.alk_matches%rowtype;
  a public.alk_match_members%rowtype;
  v_now timestamptz;
  v_duplicate boolean;
  v_board_changed boolean := true;
  v_notify boolean := true;
  v_color text;
  v_accept boolean;
  v_stone_id integer;
  v_x double precision;
  v_y double precision;
  v_stone jsonb;
  v_simulation jsonb;
  v_steps integer;
  v_body text;
  v_muted boolean;
  v_since integer := greatest(coalesce((p_payload ->> 'since_chat_seq')::integer, 0), 0);
begin
  if p_protocol is distinct from 1 then
    return public.alk_response('unsupported_client', v_uid, null, 0);
  end if;
  if v_uid is null or not exists (select 1 from public.profiles p where p.id = v_uid) then
    return public.alk_response('not_signed_in', null, null, 0);
  end if;
  if p_operation not in ('state', 'cancel', 'respond', 'place', 'ready', 'shoot',
                         'resign', 'leave', 'chat_send', 'chat_mute')
     or p_match_id is null or (p_operation <> 'state' and p_action_id is null) then
    return public.alk_response('invalid', v_uid, null, 0);
  end if;
  -- First discover the actual pair without exposing anything to a nonparticipant.
  select g.* into m from public.alk_matches g
    where g.id = p_match_id and v_uid in (g.black_id, g.white_id);
  if not found then return public.alk_response('not_found', v_uid, null, 0); end if;
  if p_operation = 'respond' then
    perform public.alk_lock_users(m.black_id, m.white_id);
  end if;
  -- All writes, including chat and retries, serialize ONLY on this match row.
  select g.* into m from public.alk_matches g
    where g.id = p_match_id and v_uid in (g.black_id, g.white_id) for update;
  if not found then return public.alk_response('not_found', v_uid, null, 0); end if;
  v_now := clock_timestamp();
  v_duplicate := p_operation <> 'state' and exists (
    select 1 from public.alk_match_actions r
    where r.actor_id = v_uid and r.match_id = m.id and r.action_id = p_action_id
  );
  m := public.alk_advance(m.id, v_now);
  -- A retry may observe normal elapsed-clock advancement, never repeat its action.
  -- In particular this is BEFORE expected-revision, role, payload and phase checks.
  if v_duplicate then return public.alk_response('ok', v_uid, m.id, v_since); end if;
  if p_operation = 'state' then return public.alk_response('ok', v_uid, m.id, v_since); end if;
  if p_operation in ('place', 'shoot') and p_expected_revision is null then
    return public.alk_response('invalid', v_uid, m.id, 0);
  end if;
  if p_expected_revision is not null and p_expected_revision <> m.revision then
    return public.alk_response('stale', v_uid, m.id, 0);
  end if;
  if m.action_count >= 16384 and p_operation not in ('cancel', 'respond', 'resign', 'leave') then
    return public.alk_response('rate_limited', v_uid, m.id, 0);
  end if;

  if p_operation in ('cancel', 'respond') then
    if (p_operation = 'cancel' and v_uid <> m.black_id)
       or (p_operation = 'respond' and v_uid <> m.white_id) then
      return public.alk_response('forbidden', v_uid, m.id, 0);
    end if;
    if m.status = 'expired' then return public.alk_response('expired', v_uid, m.id, 0); end if;
    if m.status <> 'pending' then return public.alk_response('not_pending', v_uid, m.id, 0); end if;
    if p_operation = 'cancel' then
      m.status := 'cancelled';
    else
      v_accept := (p_payload ->> 'accept')::boolean;
      if v_accept is null then return public.alk_response('invalid', v_uid, m.id, 0); end if;
      if not v_accept then
        m.status := 'declined';
      else
        -- Fail CLOSED for unknown/null helper results; acceptance rechecks privacy.
        if public.same_visibility(m.black_id, m.white_id) is distinct from true
           or public.blocked_between(m.black_id, m.white_id) is distinct from false then
          return public.alk_response('forbidden', v_uid, m.id, 0);
        end if;
        if public.alk_busy(v_uid) then return public.alk_response('busy', v_uid, m.id, 0); end if;
        if public.alk_busy(m.black_id) then return public.alk_response('target_busy', v_uid, m.id, 0); end if;
        m.status := 'active'; m.phase := 'placing_black'; m.current_player := 'black';
        m.deadline_at := v_now + interval '30 seconds';
        insert into public.alk_match_members(match_id, user_id, color, joined_at) values
          (m.id, m.black_id, 'black', v_now), (m.id, m.white_id, 'white', v_now);
      end if;
    end if;
  else
    select g.* into a from public.alk_match_members g where g.match_id = m.id and g.user_id = v_uid;
    if not found then return public.alk_response('not_active', v_uid, m.id, 0); end if;
    v_color := a.color;
    if p_operation = 'leave' then
      if m.status <> 'finished' then return public.alk_response('not_active', v_uid, m.id, 0); end if;
      -- Finished leave is idempotent even with a fresh action ID; no new record or hint.
      if a.left_at is not null then return public.alk_response('ok', v_uid, m.id, 0); end if;
      update public.alk_match_members g set left_at = v_now where g.match_id = m.id and g.user_id = v_uid;
      if not exists (select 1 from public.alk_match_members g where g.match_id = m.id and g.left_at is null) then
        delete from public.alk_chat_messages c where c.match_id = m.id;
      end if;
    elsif p_operation in ('chat_send', 'chat_mute') then
      if a.left_at is not null or not (m.status = 'active' or
          (m.status = 'finished' and v_now < m.finished_at + interval '120 seconds')) then
        return public.alk_response('not_active', v_uid, m.id, 0);
      end if;
      v_board_changed := false;
      if p_operation = 'chat_mute' then
        v_muted := (p_payload ->> 'muted')::boolean;
        if v_muted is null then return public.alk_response('invalid', v_uid, m.id, 0); end if;
        v_notify := a.muted is distinct from v_muted;
        if v_notify then
          update public.alk_match_members g set muted = v_muted where g.match_id = m.id and g.user_id = v_uid;
        end if;
      else
        -- This is private match chat, never a way around later visibility/block changes.
        if public.same_visibility(m.black_id, m.white_id) is distinct from true
           or public.blocked_between(m.black_id, m.white_id) is distinct from false then
          return public.alk_response('forbidden', v_uid, m.id, 0);
        end if;
        v_body := regexp_replace(p_payload ->> 'body', '^[[:space:]]+|[[:space:]]+$', '', 'g');
        if v_body is null or char_length(v_body) not between 1 and 100 or v_body !~ '[^[:space:]]' then
          return public.alk_response('invalid', v_uid, m.id, 0);
        end if;
        if a.last_chat_at is not null and v_now < a.last_chat_at + interval '0.5 seconds' then
          return public.alk_response('rate_limited', v_uid, m.id, 0);
        end if;
        m.chat_seq := m.chat_seq + 1;
        insert into public.alk_chat_messages(match_id, seq, sender_id, body, sent_at)
          values (m.id, m.chat_seq, v_uid, v_body, v_now);
        update public.alk_match_members g set last_chat_at = v_now where g.match_id = m.id and g.user_id = v_uid;
        delete from public.alk_chat_messages c where c.match_id = m.id and c.seq <= m.chat_seq - 200;
      end if;
    else
      if m.status <> 'active' then return public.alk_response('not_active', v_uid, m.id, 0); end if;
      if p_operation = 'resign' then
        m.status := 'finished'; m.phase := 'finished';
        m.result := case when v_color = 'black' then 'white' else 'black' end;
        m.finish_reason := 'resign'; m.finished_at := v_now;
        m.deadline_at := null; m.roll_until := null; m.rolling_result := null;
      else
        if v_color <> m.current_player then return public.alk_response('forbidden', v_uid, m.id, 0); end if;
        if p_operation in ('place', 'ready') then
          if m.phase <> (case when v_color = 'black' then 'placing_black' else 'placing_white' end) then
            return public.alk_response('not_active', v_uid, m.id, 0);
          end if;
          if p_operation = 'ready' then
            if (select count(*) from jsonb_array_elements(m.stones) as s(stone)
                where s.stone ->> 'owner' = v_color and (s.stone ->> 'isPlaced')::boolean
                  and not (s.stone ->> 'isOut')::boolean) <> 5 then
              return public.alk_response('invalid', v_uid, m.id, 0);
            end if;
            m.phase := case when v_color = 'black' then 'placing_white' else 'aiming' end;
            m.current_player := case when v_color = 'black' then 'white' else 'black' end;
            m.deadline_at := v_now + interval '30 seconds';
          else
            v_stone_id := (p_payload ->> 'stone_id')::integer;
            v_x := (p_payload ->> 'x')::double precision; v_y := (p_payload ->> 'y')::double precision;
            if not public.alk_can_place(m.stones, v_color, v_stone_id, v_x, v_y) then
              return public.alk_response('invalid', v_uid, m.id, 0);
            end if;
            m.stones := jsonb_set(m.stones, array[v_stone_id::text], (m.stones -> v_stone_id) || jsonb_build_object(
              'position', jsonb_build_object('x', v_x, 'y', v_y),
              'velocity', jsonb_build_object('x', 0, 'y', 0), 'isPlaced', true));
          end if;
        elsif p_operation = 'shoot' then
          if m.phase <> 'aiming' or m.deadline_at <= v_now then
            return public.alk_response('not_active', v_uid, m.id, 0);
          end if;
          v_stone_id := (p_payload ->> 'stone_id')::integer;
          v_x := (p_payload ->> 'pull_x')::double precision; v_y := (p_payload ->> 'pull_y')::double precision;
          if v_stone_id is null or v_stone_id not between 0 and 9 or v_x is null or v_y is null
             or not (v_x > '-Infinity'::double precision and v_x < 'Infinity'::double precision)
             or not (v_y > '-Infinity'::double precision and v_y < 'Infinity'::double precision) then
            return public.alk_response('invalid', v_uid, m.id, 0);
          end if;
          v_stone := m.stones -> v_stone_id;
          if v_stone ->> 'owner' <> v_color or not (v_stone ->> 'isPlaced')::boolean
             or (v_stone ->> 'isOut')::boolean then
            return public.alk_response('invalid', v_uid, m.id, 0);
          end if;
          -- Authorization and the current, server-owned board precede the physics call.
          begin
            v_simulation := public.alkkagi_simulate(m.stones, v_stone_id, v_x, v_y);
          exception when invalid_parameter_value or numeric_value_out_of_range then
            return public.alk_response('invalid', v_uid, m.id, 0);
          end;
          v_steps := (v_simulation ->> 'steps')::integer;
          if v_steps is null or v_steps not between 1 and 2400 then
            raise exception 'Alkkagi: simulation returned an invalid step count';
          end if;
          m.shot := jsonb_build_object('id', p_action_id, 'stone_id', v_stone_id,
            'pull', jsonb_build_object('x', v_x, 'y', v_y), 'started_at_ms', public.alk_ms(v_now),
            'steps', v_steps, 'initial_stones', m.stones);
          m.stones := v_simulation -> 'stones';
          m.rolling_result := v_simulation ->> 'result';
          -- Keep the original aiming deadline for the frozen client clock.
          -- Never expose the helper's winner until the absolute roll completion.
          m.result := null; m.phase := 'rolling'; m.shot_count := m.shot_count + 1;
          m.roll_until := v_now + interval '1 second' * (v_steps::double precision / 240.0);
        end if;
      end if;
    end if;
  end if;

  if v_board_changed then m.revision := m.revision + 1; end if;
  m.action_count := m.action_count + 1; m.updated_at := v_now;
  insert into public.alk_match_actions(match_id, actor_id, action_id, kind, created_at)
    values (m.id, v_uid, p_action_id, p_operation, v_now);
  update public.alk_matches g set
    status = m.status, phase = m.phase, revision = m.revision, current_player = m.current_player,
    stones = m.stones, deadline_at = m.deadline_at, roll_until = m.roll_until,
    shot = m.shot, shot_count = m.shot_count, rolling_result = m.rolling_result,
    result = m.result, finish_reason = m.finish_reason, finished_at = m.finished_at,
    chat_seq = m.chat_seq, action_count = m.action_count, updated_at = m.updated_at
  where g.id = m.id;
  if m.status = 'finished' then
    update public.alk_match_members g set is_active = false where g.match_id = m.id and g.is_active;
  end if;
  if v_notify then perform public.alk_notify(m.id, m.revision); end if;
  return public.alk_response('ok', v_uid, m.id, 0);
end
$fn$;

create function public.alkkagi_lobby(p_users boolean default true, p_protocol integer default 1)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_now timestamptz;
  v_result jsonb;
  v_incoming jsonb;
  v_outgoing jsonb;
  v_users jsonb;
begin
  if p_protocol is distinct from 1 then return public.alk_response('unsupported_client', v_uid, null, 0); end if;
  if v_uid is null or not exists (select 1 from public.profiles p where p.id = v_uid) then
    return public.alk_response('not_signed_in', null, null, 0);
  end if;
  -- Only the caller's single outgoing row is lazily expired here. Expired incoming
  -- rows are filtered by timestamp and expired on addressed RPCs. This avoids a
  -- multi-match lock sweep or an unbounded polling workload.
  insert into public.alk_clients(user_id, protocol, last_seen_at) values (v_uid, 1, clock_timestamp())
    on conflict (user_id) do update set protocol = excluded.protocol, last_seen_at = excluded.last_seen_at;
  select g.id into v_id from public.alk_matches g where g.black_id = v_uid and g.status = 'pending';
  if v_id is not null then perform public.alk_advance(v_id, null); end if;
  select g.id into v_id from public.alk_match_members a join public.alk_matches g on g.id = a.match_id
    where a.user_id = v_uid and a.left_at is null and (a.is_active or g.status = 'finished')
    order by a.is_active desc, a.joined_at desc, g.id limit 1;
  if v_id is not null then perform public.alk_advance(v_id, null); end if;
  v_result := public.alk_response('ok', v_uid, v_id, 0);
  v_now := clock_timestamp();
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id, 'opponent', public.alk_peer(g.black_id), 'expires_at_ms', public.alk_ms(g.invite_expires_at)
  ) order by g.invite_expires_at, g.id), '[]'::jsonb) into v_incoming
  from (
    select m.id, m.black_id, m.invite_expires_at from public.alk_matches m
    where m.white_id = v_uid and m.status = 'pending' and m.invite_expires_at > v_now
      and public.same_visibility(v_uid, m.black_id) is true
      and public.blocked_between(v_uid, m.black_id) is false
    order by m.invite_expires_at, m.id limit 200
  ) g;
  select jsonb_build_object('id', m.id, 'opponent', public.alk_peer(m.white_id),
    'expires_at_ms', public.alk_ms(m.invite_expires_at)) into v_outgoing
  from public.alk_matches m where m.black_id = v_uid and m.status = 'pending' and m.invite_expires_at > v_now
    and public.same_visibility(v_uid, m.white_id) is true and public.blocked_between(v_uid, m.white_id) is false;
  v_result := v_result || jsonb_build_object('incoming', v_incoming, 'outgoing', v_outgoing);
  if p_users is true then
    select coalesce(jsonb_agg(public.alk_peer(g.id) order by g.id), '[]'::jsonb) into v_users
    from (
      select p.id from public.profiles p join public.alk_clients c on c.user_id = p.id
      where p.id <> v_uid and c.protocol = 1 and c.last_seen_at > v_now - interval '24 hours'
        and public.same_visibility(v_uid, p.id) is true and public.blocked_between(v_uid, p.id) is false
      order by p.id limit 200
    ) g;
    v_result := v_result || jsonb_build_object('users', v_users);
  end if;
  return v_result;
end
$fn$;

create function public.alkkagi_challenge(p_opponent uuid, p_action_id uuid, p_protocol integer default 1)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog
as $fn$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_now timestamptz;
begin
  if p_protocol is distinct from 1 then return public.alk_response('unsupported_client', v_uid, null, 0); end if;
  if v_uid is null or not exists (select 1 from public.profiles p where p.id = v_uid) then
    return public.alk_response('not_signed_in', null, null, 0);
  end if;
  if p_opponent is null or p_opponent = v_uid or p_action_id is null then
    return public.alk_response('invalid', v_uid, null, 0);
  end if;
  perform public.alk_lock_users(v_uid, p_opponent);
  select a.match_id into v_id from public.alk_match_actions a
    where a.actor_id = v_uid and a.action_id = p_action_id and a.kind = 'challenge';
  if v_id is not null then
    perform public.alk_advance(v_id, null);
    return public.alk_response('ok', v_uid, v_id, 0);
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_opponent)
     or public.same_visibility(v_uid, p_opponent) is distinct from true
     or public.blocked_between(v_uid, p_opponent) is distinct from false then
    return public.alk_response('not_found', v_uid, null, 0);
  end if;
  if not exists (select 1 from public.alk_clients c where c.user_id = p_opponent
                 and c.protocol = 1 and c.last_seen_at > clock_timestamp() - interval '24 hours') then
    return public.alk_response('not_found', v_uid, null, 0);
  end if;
  select g.id into v_id from public.alk_matches g where g.black_id = v_uid and g.status = 'pending';
  if v_id is not null then perform public.alk_advance(v_id, null); end if;
  if public.alk_busy(v_uid) then return public.alk_response('busy', v_uid, null, 0); end if;
  if public.alk_busy(p_opponent) then return public.alk_response('target_busy', v_uid, null, 0); end if;
  select g.id into v_id from public.alk_matches g where g.black_id = v_uid and g.status = 'pending';
  if v_id is not null then return public.alk_response('already_pending', v_uid, v_id, 0); end if;
  v_now := clock_timestamp();
  insert into public.alk_matches(black_id, white_id, stones, invite_expires_at, action_count, created_at, updated_at)
    values (v_uid, p_opponent, public.alk_initial_stones(), v_now + interval '60 seconds', 1, v_now, v_now)
    returning id into v_id;
  insert into public.alk_match_actions(match_id, actor_id, action_id, kind, created_at)
    values (v_id, v_uid, p_action_id, 'challenge', v_now);
  perform public.alk_notify(v_id, 1);
  return public.alk_response('ok', v_uid, v_id, 0);
end
$fn$;

-- Exact wire signatures: defaults occur only at the end; no overloads are created.
create function public.alkkagi_cancel(
  p_match_id uuid, p_action_id uuid, p_expected_revision integer default null, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('cancel', p_match_id, p_action_id, p_expected_revision, '{}'::jsonb, p_protocol) $fn$;

create function public.alkkagi_respond(
  p_match_id uuid, p_accept boolean, p_action_id uuid, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('respond', p_match_id, p_action_id, null, jsonb_build_object('accept', p_accept), p_protocol) $fn$;

create function public.alkkagi_state(
  p_match_id uuid, p_since_chat_seq integer default 0, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('state', p_match_id, null, null, jsonb_build_object('since_chat_seq', p_since_chat_seq), p_protocol) $fn$;

create function public.alkkagi_place(
  p_match_id uuid, p_expected_revision integer, p_stone_id integer,
  p_x double precision, p_y double precision, p_action_id uuid, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$
  select public.alk_match_call('place', p_match_id, p_action_id, p_expected_revision,
    jsonb_build_object('stone_id', p_stone_id, 'x', p_x, 'y', p_y), p_protocol)
$fn$;

create function public.alkkagi_ready(
  p_match_id uuid, p_action_id uuid, p_expected_revision integer default null, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('ready', p_match_id, p_action_id, p_expected_revision, '{}'::jsonb, p_protocol) $fn$;

create function public.alkkagi_shoot(
  p_match_id uuid, p_expected_revision integer, p_stone_id integer,
  p_pull_x double precision, p_pull_y double precision, p_action_id uuid, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$
  select public.alk_match_call('shoot', p_match_id, p_action_id, p_expected_revision,
    jsonb_build_object('stone_id', p_stone_id, 'pull_x', p_pull_x, 'pull_y', p_pull_y), p_protocol)
$fn$;

create function public.alkkagi_resign(
  p_match_id uuid, p_action_id uuid, p_expected_revision integer default null, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('resign', p_match_id, p_action_id, p_expected_revision, '{}'::jsonb, p_protocol) $fn$;

create function public.alkkagi_leave(
  p_match_id uuid, p_action_id uuid, p_expected_revision integer default null, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('leave', p_match_id, p_action_id, p_expected_revision, '{}'::jsonb, p_protocol) $fn$;

create function public.alkkagi_chat_send(
  p_match_id uuid, p_body text, p_action_id uuid, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('chat_send', p_match_id, p_action_id, null, jsonb_build_object('body', p_body), p_protocol) $fn$;

create function public.alkkagi_chat_mute(
  p_match_id uuid, p_muted boolean, p_action_id uuid, p_protocol integer default 1
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $fn$ select public.alk_match_call('chat_mute', p_match_id, p_action_id, null, jsonb_build_object('muted', p_muted), p_protocol) $fn$;

-- Revoke explicit Supabase default grants as well as PUBLIC's implicit EXECUTE.
-- The migration transaction prevents an intermediate publicly executable helper.
do $grants$
declare
  r record;
begin
  for r in
    select p.oid, p.proname from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(array[
      'alk_ms', 'alk_lock_users', 'alk_initial_stones', 'alk_can_place', 'alk_autofill',
      'alk_busy', 'alk_peer', 'alk_notify', 'alk_advance', 'alk_snapshot', 'alk_response', 'alk_match_call',
      'alkkagi_lobby', 'alkkagi_challenge', 'alkkagi_cancel', 'alkkagi_respond',
      'alkkagi_state', 'alkkagi_place', 'alkkagi_ready', 'alkkagi_shoot',
      'alkkagi_resign', 'alkkagi_leave', 'alkkagi_chat_send', 'alkkagi_chat_mute'
    ])
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', r.oid::regprocedure);
    if left(r.proname, 8) = 'alkkagi_' then
      execute format('grant execute on function %s to authenticated', r.oid::regprocedure);
    end if;
  end loop;
end
$grants$;

-- Deployment assertions inspect effective grants too (including role inheritance),
-- so an unsafe owner or inherited API privilege cannot quietly pass this draft.
do $assertions$
declare
  r record;
  v_role text;
  v_table text;
  v_oid oid;
  v_rpc_names constant text[] := array[
    'alkkagi_lobby', 'alkkagi_challenge', 'alkkagi_cancel', 'alkkagi_respond',
    'alkkagi_state', 'alkkagi_place', 'alkkagi_ready', 'alkkagi_shoot',
    'alkkagi_resign', 'alkkagi_leave', 'alkkagi_chat_send', 'alkkagi_chat_mute'
  ];
begin
  foreach v_table in array array['alk_clients', 'alk_matches', 'alk_match_members', 'alk_match_actions', 'alk_chat_messages'] loop
    v_oid := to_regclass('public.' || v_table);
    if not exists (select 1 from pg_catalog.pg_class c where c.oid = v_oid and c.relrowsecurity) then
      raise exception 'Alkkagi: RLS missing on %', v_table;
    end if;
    if exists (
      select 1 from pg_catalog.pg_class c,
        lateral pg_catalog.aclexplode(coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))) a
      where c.oid = v_oid and a.grantee = 0
    ) then raise exception 'Alkkagi: PUBLIC has direct access to %', v_table; end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if has_table_privilege(v_role, v_oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'Alkkagi: % has inherited/direct table access to %', v_role, v_table;
      end if;
    end loop;
  end loop;
  for r in
    select p.* from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (
      p.proname = any(v_rpc_names) or p.proname = any(array[
        'alk_ms', 'alk_lock_users', 'alk_initial_stones', 'alk_can_place', 'alk_autofill',
        'alk_busy', 'alk_peer', 'alk_notify', 'alk_advance', 'alk_snapshot', 'alk_response', 'alk_match_call',
        'alkkagi_simulate'
      ])
    )
  loop
    if not ('search_path=pg_catalog' = any(r.proconfig)) then
      raise exception 'Alkkagi: unsafe function search_path on %', r.oid::regprocedure;
    end if;
    if exists (
      select 1 from pg_catalog.aclexplode(coalesce(r.proacl, pg_catalog.acldefault('f', r.proowner))) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then raise exception 'Alkkagi: PUBLIC can execute %', r.oid::regprocedure; end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if has_function_privilege(v_role, r.oid, 'EXECUTE') is distinct from
          (v_role = 'authenticated' and r.proname = any(v_rpc_names)) then
        raise exception 'Alkkagi: unexpected effective % EXECUTE on %', v_role, r.oid::regprocedure;
      end if;
    end loop;
  end loop;
  for r in select * from (values
    ('alkkagi_lobby', 'public.alkkagi_lobby(boolean,integer)', array['p_users','p_protocol'], 2),
    ('alkkagi_challenge', 'public.alkkagi_challenge(uuid,uuid,integer)', array['p_opponent','p_action_id','p_protocol'], 1),
    ('alkkagi_cancel', 'public.alkkagi_cancel(uuid,uuid,integer,integer)', array['p_match_id','p_action_id','p_expected_revision','p_protocol'], 2),
    ('alkkagi_respond', 'public.alkkagi_respond(uuid,boolean,uuid,integer)', array['p_match_id','p_accept','p_action_id','p_protocol'], 1),
    ('alkkagi_state', 'public.alkkagi_state(uuid,integer,integer)', array['p_match_id','p_since_chat_seq','p_protocol'], 2),
    ('alkkagi_place', 'public.alkkagi_place(uuid,integer,integer,double precision,double precision,uuid,integer)', array['p_match_id','p_expected_revision','p_stone_id','p_x','p_y','p_action_id','p_protocol'], 1),
    ('alkkagi_ready', 'public.alkkagi_ready(uuid,uuid,integer,integer)', array['p_match_id','p_action_id','p_expected_revision','p_protocol'], 2),
    ('alkkagi_shoot', 'public.alkkagi_shoot(uuid,integer,integer,double precision,double precision,uuid,integer)', array['p_match_id','p_expected_revision','p_stone_id','p_pull_x','p_pull_y','p_action_id','p_protocol'], 1),
    ('alkkagi_resign', 'public.alkkagi_resign(uuid,uuid,integer,integer)', array['p_match_id','p_action_id','p_expected_revision','p_protocol'], 2),
    ('alkkagi_leave', 'public.alkkagi_leave(uuid,uuid,integer,integer)', array['p_match_id','p_action_id','p_expected_revision','p_protocol'], 2),
    ('alkkagi_chat_send', 'public.alkkagi_chat_send(uuid,text,uuid,integer)', array['p_match_id','p_body','p_action_id','p_protocol'], 1),
    ('alkkagi_chat_mute', 'public.alkkagi_chat_mute(uuid,boolean,uuid,integer)', array['p_match_id','p_muted','p_action_id','p_protocol'], 1)
  ) as expected(name, signature, argnames, defaults) loop
    v_oid := to_regprocedure(r.signature);
    if v_oid is null or not exists (
      select 1 from pg_catalog.pg_proc p where p.oid = v_oid and p.proargnames = r.argnames
        and p.pronargs = cardinality(r.argnames) and p.pronargdefaults = r.defaults
        and p.prorettype = 'pg_catalog.jsonb'::regtype and not p.proretset and p.prosecdef
    ) or (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = r.name) <> 1 then
      raise exception 'Alkkagi: wire signature/defaults/overload mismatch for %', r.name;
    end if;
  end loop;
end
$assertions$;

notify pgrst, 'reload schema';
