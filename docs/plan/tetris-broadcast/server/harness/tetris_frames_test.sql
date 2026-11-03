-- 생성물(build_test.sh). 정본: tetris_frames_test.body.sql + tf_old.sql
set local role postgres;
create or replace function public.tf_old_state(p_match_id uuid, p_uid uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  m      public.tetris_matches%rowtype;
  v_peer uuid;
  v_me   jsonb;
  v_op   jsonb;
  v_bal  int;
begin
  select * into m from public.tetris_matches g where g.id = p_match_id;
  if not found then
    return null;
  end if;
  v_peer := case when p_uid = m.challenger then m.opponent else m.challenger end;
  select jsonb_build_object(
           'id', u.uid, 'display_name', coalesce(pr.display_name, '사용자'),
           'avatar_url', pr.avatar_url, 'character', pr.character,
           'ready', pl.ready_at is not null, 'seq', coalesce(pl.seq, 0), 'board', pl.board,
           'lines', coalesce(pl.lines, 0), 'garbage_sent', coalesce(pl.garbage_sent, 0),
           'garbage_applied', coalesce(pl.garbage_applied, 0), 'pending', coalesce(pl.pending, 0),
           'last_seen_ms', public.tetris__ms(pl.last_seen_at), 'topped_out', pl.topped_out_at is not null),
         jsonb_build_object(
           'id', u.peer, 'display_name', coalesce(qr.display_name, '사용자'),
           'avatar_url', qr.avatar_url, 'character', qr.character,
           'ready', ql.ready_at is not null, 'seq', coalesce(ql.seq, 0), 'board', ql.board,
           'lines', coalesce(ql.lines, 0), 'garbage_sent', coalesce(ql.garbage_sent, 0),
           'garbage_applied', coalesce(ql.garbage_applied, 0), 'pending', coalesce(ql.pending, 0),
           'last_seen_ms', public.tetris__ms(ql.last_seen_at), 'topped_out', ql.topped_out_at is not null)
    into v_me, v_op
    from (select p_uid as uid, v_peer as peer) u
    left join public.profiles pr on pr.id = u.uid
    left join public.profiles qr on qr.id = u.peer
    left join public.tetris_players pl on pl.match_id = m.id and pl.user_id = u.uid
    left join public.tetris_players ql on ql.match_id = m.id and ql.user_id = u.peer;
  select p.ruby_balance into v_bal from public.profiles p where p.id = p_uid;
  return jsonb_build_object(
    'match_id', m.id,
    'status', m.status,
    'stake', m.stake,
    'seed', m.seed,
    'server_now_ms', public.tetris__ms(clock_timestamp()),
    'accepted_at_ms', public.tetris__ms(m.accepted_at),
    'start_at_ms', public.tetris__ms(m.start_at),
    'ready_deadline_ms', public.tetris__ms(m.accepted_at + make_interval(secs => public.tetris_ready_timeout_seconds())),
    'max_end_ms', public.tetris__ms(m.start_at + make_interval(secs => public.tetris_max_duration_seconds())),
    'finished_at_ms', public.tetris__ms(m.finished_at),
    'me', v_me,
    'opponent', v_op,
    'result', m.result,
    'winner', m.winner,
    'end_reason', m.end_reason,
    'watchers', public.match__watchers('tetris', p_match_id),
    'my_device', public.tetris__device(p_match_id, p_uid),
    'ruby_balance', v_bal);
end
$fn$;

create or replace function public.tf_old_report(p_protocol int default 0, p_match_id uuid default null,
                                                p_seq int default null, p_board text default null,
                                                p_lines int default null, p_garbage_sent int default null,
                                                p_garbage_applied int default null, p_pending int default null,
                                                p_topped_out boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_now       timestamptz := clock_timestamp();
  uid         uuid := auth.uid();
  v_a         uuid;
  v_b         uuid;
  m           public.tetris_matches%rowtype;
  me          public.tetris_players%rowtype;
  v_peer      uuid;
  v_peer_sent int;
  v_cap       bigint;
  v_sent      int;
  v_rows      int;
  v_dev       text;
begin
  if uid is null then
    return jsonb_build_object('status', 'not_signed_in');
  end if;
  if coalesce(p_protocol, 0) < public.tetris_protocol() then
    return jsonb_build_object('status', 'unsupported_client', 'server_now_ms', public.tetris__ms(v_now));
  end if;
  select g.challenger, g.opponent into v_a, v_b from public.tetris_matches g where g.id = p_match_id;
  if not found or uid not in (v_a, v_b) then
    return jsonb_build_object('status', 'not_found');
  end if;
  if p_seq is null or p_seq < 1
     or (p_board is not null and (length(p_board) <> 200 or p_board ~ '[^.IJLOSTZG]'))
     or coalesce(p_lines, 0) not between 0 and 1000000
     or coalesce(p_garbage_sent, 0) not between 0 and 1000000
     or coalesce(p_garbage_applied, 0) not between 0 and 1000000
     or coalesce(p_pending, 0) not between 0 and 1000000 then
    return jsonb_build_object('status', 'invalid');
  end if;
  perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || least(v_a, v_b)::text));
  perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || greatest(v_a, v_b)::text));
  select * into m from public.tetris_matches g where g.id = p_match_id for update;
  if not found or uid not in (m.challenger, m.opponent) then
    return jsonb_build_object('status', 'not_found');
  end if;
  -- ⓪ 한 판 한 기기(20261103124000): 이 자리를 연 기기(신청·수락한 세션)가 아니면 **아무것도 쓰지 않는다** —
  --    시간 판정·준비·쓰기·탑아웃 정산보다 앞이다. 같은 계정의 다른 기기가 입력 없이 돌린 판이 진짜 판을 덮어쓰고
  --    그 판의 탑아웃으로 대결을 닫던 결함(2026-10-30 두 판)의 서버 쪽 마개다.
  v_dev := public.tetris__device(m.id, uid);
  if v_dev = 'other' then
    return jsonb_build_object('status', 'other_device', 'state', public.tf_old_state(m.id, uid));
  end if;
  -- ① 누가 불러도 닫힌다(내 침묵도 여기서 잰다 — 15초 넘게 끊겼다 돌아온 보고는 이미 진 판을 받는다)
  if public.tetris__due(m.id, v_now) then
    select * into m from public.tetris_matches g where g.id = m.id;
  end if;
  if m.status <> 'active' then
    return jsonb_build_object('status', 'stale', 'state', public.tf_old_state(m.id, uid));
  end if;
  v_peer := case when uid = m.challenger then m.opponent else m.challenger end;
  select * into me from public.tetris_players pl where pl.match_id = m.id and pl.user_id = uid for update;
  if not found then
    raise exception 'tetris_report: 판 %에 사람 %의 행이 없다 — 수락이 사람 행을 안 만들었다', m.id, uid;
  end if;
  -- ⓪' 누계가 뒤로 가면 다른 기기의 보고다(한 기기의 지운 줄·공격 누계는 줄지 않고, 재개는 서버 값에서 잇는다).
  --     늦게 온 옛 보고(seq 이하)는 아래 ④ 의 stale 이 받는다 — 여기서 다른 기기로 몰지 않는다.
  if p_seq > me.seq
     and (coalesce(p_lines, me.lines) < me.lines or coalesce(p_garbage_sent, me.garbage_sent) < me.garbage_sent) then
    return jsonb_build_object('status', 'other_device', 'state', public.tf_old_state(m.id, uid));
  end if;
  -- 세션 기록이 없던 판(이 파일 전에 수락된 판)은 거른 뒤 **실제로 쓸** 보고(seq 가 앞선 것)만 자리를 잡는다 — 늦게 온
  --     옛 보고는 ④ 에서 stale 로 끝나므로 잡으면 안 된다(다른 기기의 늦은 보고가 자리를 가로채면 진짜 기기가 막혀 침묵 패).
  --     세션 없는 토큰이면 아무것도 안 한다.
  if v_dev is null and p_seq > me.seq then
    perform public.tetris__claim(m.id, uid);
  end if;

  -- ③ 준비: 첫 보고가 준비다. 둘째 준비면 start_at = 지금 + 카운트다운.
  if me.ready_at is null then
    update public.tetris_players pl set ready_at = v_now where pl.match_id = m.id and pl.user_id = uid;
    if m.start_at is null
       and exists (select 1 from public.tetris_players pl
                    where pl.match_id = m.id and pl.user_id = v_peer and pl.ready_at is not null) then
      update public.tetris_matches g
         set start_at = v_now + interval '1 millisecond' * public.tetris_countdown_ms()
       where g.id = m.id and g.status = 'active' and g.start_at is null
      returning g.start_at into m.start_at;
      perform public.tetris__ring(m.challenger, m.id, 0);
      perform public.tetris__ring(m.opponent, m.id, 0);
    end if;
  end if;

  -- ④ 늦게 온 보고는 쓰지 않는다
  if p_seq <= me.seq then
    return jsonb_build_object('status', 'stale', 'state', public.tf_old_state(m.id, uid));
  end if;

  -- ⑤ 쓴다. 공격 누계는 단조 + 상한(경과초는 start_at 기준, 시작 전이면 0).
  select pl.garbage_sent into v_peer_sent from public.tetris_players pl
   where pl.match_id = m.id and pl.user_id = v_peer;
  v_cap := public.tetris_attack_cap(case when m.start_at is null then 0
                                         else public.tetris__ms(v_now) - public.tetris__ms(m.start_at) end);
  v_sent := greatest(me.garbage_sent, least(coalesce(p_garbage_sent, me.garbage_sent), v_cap))::int;
  update public.tetris_players pl
     set seq             = p_seq,
         board           = coalesce(p_board, pl.board),
         lines           = coalesce(p_lines, pl.lines),
         garbage_sent    = v_sent,
         garbage_applied = greatest(pl.garbage_applied,
                                    least(coalesce(p_garbage_applied, pl.garbage_applied), coalesce(v_peer_sent, 0))),
         pending         = coalesce(p_pending, pl.pending),
         last_seen_at    = v_now,
         topped_out_at   = case when coalesce(p_topped_out, false) then coalesce(pl.topped_out_at, v_now)
                                else pl.topped_out_at end
   where pl.match_id = m.id and pl.user_id = uid;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'tetris_report: 보고 쓰기가 %행이다(기대 1)', v_rows;
  end if;

  -- ⑥ 공격이 늘었을 때만 상대 초인종(매 보고마다 울리지 않는다)
  if v_sent > me.garbage_sent then
    perform public.tetris__ring(v_peer, m.id, v_sent);
  end if;

  -- ⑦ 자기 탑아웃 = 자기 패배 신고(상대 승)
  if coalesce(p_topped_out, false) then
    perform public.tetris__settle(m.id, case when uid = m.challenger then 'opponent_win' else 'challenger_win' end, 'topout');
  end if;
  return jsonb_build_object('status', 'ok', 'state', public.tf_old_state(m.id, uid));
end
$fn$;

-- ── 도구 ───────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.tf_as(p_uid uuid, p_session text, p_role text default 'authenticated', p_sub text default null)
returns void language plpgsql as $tmp$
begin
  perform set_config('request.jwt.claims',
                     (jsonb_build_object('sub', coalesce(p_sub, p_uid::text), 'role', p_role, 'aud', p_role)
                      || case when p_session is null then '{}'::jsonb
                              else jsonb_build_object('session_id', p_session) end)::text, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub, p_uid::text, ''), true);
  perform set_config('request.jwt.claim.role', p_role, true);
  execute format('set local role %I', p_role);
end $tmp$;

create or replace function pg_temp.tf_rpc(p_uid uuid, p_session text, p_sql text)
returns jsonb language plpgsql as $tmp$
declare v_back text := current_user; v jsonb;
begin
  perform pg_temp.tf_as(p_uid, p_session);
  execute p_sql into v;
  execute format('set local role %I', v_back);
  return v;
end $tmp$;

-- 보고 한 번. p_fn 으로 구버전 복제를 부를 수 있다.
create or replace function pg_temp.tf_report(p_uid uuid, p_session text, p_match uuid, p_seq int, p_lines int, p_sent int,
                                             p_proto int, p_topped boolean default false, p_fn text default 'public.tetris_report',
                                             p_board text default null)
returns jsonb language plpgsql as $tmp$
begin
  return pg_temp.tf_rpc(p_uid, p_session, format(
    'select %s(p_protocol => %s, p_match_id => %L::uuid, p_seq => %s, p_board => %L, p_lines => %s, '
    'p_garbage_sent => %s, p_garbage_applied => 0, p_pending => 0, p_topped_out => %L::boolean)',
    p_fn, p_proto, p_match, p_seq, coalesce(p_board, repeat('.', 200)), p_lines, p_sent, p_topped));
end $tmp$;

create or replace function pg_temp.tf_state(p_uid uuid, p_session text, p_match uuid, p_proto int default 1)
returns jsonb language plpgsql as $tmp$
begin
  return pg_temp.tf_rpc(p_uid, p_session, format('select public.tetris_state(%s, %L::uuid)', p_proto, p_match));
end $tmp$;

-- 인가 함수를 앱 역할로. 예외가 새면 호출부로 그대로 간다(내부 실패는 false 여야 한다).
create or replace function pg_temp.tf_allowed(p_uid uuid, p_session text, p_topic text, p_write boolean, p_sub text default null)
returns boolean language plpgsql as $tmp$
declare v_back text := current_user; v boolean;
begin
  perform pg_temp.tf_as(p_uid, p_session, 'authenticated', p_sub);
  perform set_config('realtime.topic', coalesce(p_topic, ''), true);
  execute format('select public.tetris_frame_allowed(%L::boolean)', p_write) into v;
  perform set_config('realtime.topic', '', true);
  execute format('set local role %I', v_back);
  return v;
end $tmp$;

-- 앱 역할 INSERT(웹소켓 첫 전송 때 Realtime 이 하는 인가와 같은 모양) → SQLSTATE 또는 ok. 넣은 행은 센티널로 되돌리지 않는다.
create or replace function pg_temp.tf_ins(p_uid uuid, p_session text, p_topic text, p_ext text default 'broadcast')
returns text language plpgsql as $tmp$
declare v_back text := current_user; v_state text := 'ok';
begin
  begin
    perform pg_temp.tf_as(p_uid, p_session);
    perform set_config('realtime.topic', p_topic, true);
    insert into realtime.messages (topic, extension, event, payload, private)
    values (p_topic, p_ext, 'frame', '{"probe":true}'::jsonb, true);
    perform set_config('realtime.topic', '', true);
  exception when others then
    v_state := sqlstate;
  end;
  execute format('set local role %I', v_back);
  return v_state;
end $tmp$;

-- 앱 역할 SELECT: 그 토픽 설정으로 보이는 행 수.
create or replace function pg_temp.tf_sel(p_uid uuid, p_session text, p_topic text)
returns int language plpgsql as $tmp$
declare v_back text := current_user; v int;
begin
  perform pg_temp.tf_as(p_uid, p_session);
  perform set_config('realtime.topic', p_topic, true);
  execute format('select count(*)::int from realtime.messages m where m.topic = %L', p_topic) into v;
  perform set_config('realtime.topic', '', true);
  execute format('set local role %I', v_back);
  return v;
end $tmp$;

-- 시각 칸을 걷는다(응답 비교용). frames 는 p_drop_frames 일 때만 걷는다.
create or replace function pg_temp.tf_strip(p jsonb, p_drop_frames boolean default true)
returns jsonb language plpgsql as $tmp$
declare v jsonb := p; s jsonb;
begin
  if v is null then return null; end if;
  if v ? 'state' and jsonb_typeof(v -> 'state') = 'object' then
    s := v -> 'state';
    s := s - 'server_now_ms' - 'start_at_ms' - 'max_end_ms' - 'finished_at_ms';
    s := jsonb_set(s, '{me}', (s -> 'me') - 'last_seen_ms');
    s := jsonb_set(s, '{opponent}', (s -> 'opponent') - 'last_seen_ms');
    if p_drop_frames then s := s - 'frames'; end if;
    v := jsonb_set(v, '{state}', s);
  end if;
  return v - 'server_now_ms';
end $tmp$;

create or replace function pg_temp.tf_rows(p_match uuid)
returns jsonb language sql as $tmp$
  select jsonb_build_object(
    'players', (select jsonb_agg((to_jsonb(pl) - 'last_seen_at' - 'ready_at' - 'topped_out_at' - 'frames_v'
                                  || jsonb_build_object('ready', pl.ready_at is not null, 'topped', pl.topped_out_at is not null))
                                 order by pl.user_id)
                  from public.tetris_players pl where pl.match_id = p_match),
    'match', (select to_jsonb(g) - 'start_at' - 'finished_at' - 'updated_at' || jsonb_build_object('started', g.start_at is not null)
                from public.tetris_matches g where g.id = p_match),
    'rings', (select count(*) from realtime.messages rm where rm.event = 'tetris'),
    'ledger', (select count(*) from public.ruby_ledger));
$tmp$;

-- 쓰기 계수기(이 트랜잭션은 롤백된다).
set local role postgres;
create table public.tf_writes(id bigserial primary key, op text);
create or replace function public.tf_count_w() returns trigger language plpgsql security definer set search_path = public as $tmp$
begin insert into public.tf_writes(op) values (tg_op); return new; end $tmp$;
create trigger tf_count_w after update on public.tetris_players for each row execute function public.tf_count_w();

select set_config('tf.a', :'sub', true), set_config('tf.b', :'sub2', true), set_config('tf.c', :'sub3', true) \g /dev/null

do $t$
declare
  a uuid := current_setting('tf.a')::uuid; b uuid := current_setting('tf.b')::uuid; c uuid := current_setting('tf.c')::uuid;
  sa1 text := gen_random_uuid()::text; sa2 text := gen_random_uuid()::text;
  sb1 text := gen_random_uuid()::text; sb2 text := gen_random_uuid()::text;
  sc  text := gen_random_uuid()::text;
  P   constant int := public.tetris_protocol();
  mid uuid; mid2 uuid;
  v jsonb; w jsonb; x jsonb; v_on jsonb; v_exp jsonb;
  checks int := 0;
  w0 bigint; r0 bigint; s0 bigint;
  fa int; fb int; sw boolean; st text; dev text; sess text;
  v_old jsonb; v_new jsonb; v_old_r jsonb; v_new_r jsonb; sc_name text; sc_row record;
  v_exec text := current_user;
  n int;
  tp text;
  wo bigint; wn bigint; ro bigint; rn bigint; wmax bigint := 0; rmax bigint := 0;
begin
  if P is distinct from 1 then raise exception 'tetris_protocol() 이 %', P; end if;
  checks := checks + 1;

  -- 픽스처
  update public.profiles set app_build = public.tetris_min_build(), ruby_balance = 100, focus_mode = false, is_hidden = false
   where id in (a, b, c);
  delete from public.user_blocks where blocker in (a, b, c) or blocked in (a, b, c);
  if public.poke_blackout_active() then
    execute 'create or replace function public.poke_blackout_active(p_at timestamptz default now()) '
            'returns boolean language sql stable as ''select false''';
  end if;

  ----------------------------------------------------------------------------------------------
  -- A. 대기 판: 키는 있고 값은 null · 인가 false
  ----------------------------------------------------------------------------------------------
  v := pg_temp.tf_rpc(a, sa1, format('select public.tetris_challenge(%s, %L::uuid, 3)', P, b));
  if v ->> 'status' is distinct from 'ok' then raise exception 'A 신청 %', v; end if;
  mid := (v ->> 'match_id')::uuid;
  v_on := jsonb_build_object('on', true, 'topic', 'tetris:' || mid::text);
  if mid::text is distinct from lower(mid::text) then raise exception 'A uuid 대문자'; end if;
  v := pg_temp.tf_state(a, sa1, mid);
  if not (v -> 'state' ? 'frames') or v -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'A 대기 판 frames %', v -> 'state'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, false) is distinct from false then raise exception 'A 대기 판 읽기 인가'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, true) is distinct from false then raise exception 'A 대기 판 쓰기 인가'; end if;
  checks := checks + 3;

  v := pg_temp.tf_rpc(b, sb1, format('select public.tetris_respond(%s, %L::uuid, true)', P, mid));
  if v ->> 'status' is distinct from 'ok' or v -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'A 수락 %', v; end if;
  checks := checks + 1;

  ----------------------------------------------------------------------------------------------
  -- B. frames_v 기록(p_protocol 1 · 2) + 호출당 쓰기 불변(UPDATE 횟수 · 초인종 횟수)
  ----------------------------------------------------------------------------------------------
  select count(*) into w0 from public.tf_writes;
  select count(*) into r0 from realtime.messages rm where rm.event = 'tetris';

  -- B1 a 프로토콜 1 준비: 쓰기 2(준비 + 보고) · 초인종 0
  v := pg_temp.tf_report(a, sa1, mid, 1, 0, 0, 1);
  if v ->> 'status' is distinct from 'ok' or v -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'B1 %', v; end if;
  if (select frames_v from public.tetris_players where match_id = mid and user_id = a) is distinct from 0::smallint then raise exception 'B1 frames_v'; end if;
  if (select count(*) from public.tf_writes) - w0 <> 2 then raise exception 'B1 쓰기 %', (select count(*) from public.tf_writes) - w0; end if;
  if (select count(*) from realtime.messages rm where rm.event = 'tetris') - r0 <> 0 then raise exception 'B1 초인종'; end if;
  w0 := w0 + 2;
  checks := checks + 4;

  -- B2 b 프로토콜 2 준비(둘째 준비): 쓰기 2 · 시작 초인종 2 · 상대가 0 이니 frames null
  v := pg_temp.tf_report(b, sb1, mid, 1, 0, 0, 2);
  if v ->> 'status' is distinct from 'ok' or v -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'B2 %', v; end if;
  if (select frames_v from public.tetris_players where match_id = mid and user_id = b) is distinct from 1::smallint then raise exception 'B2 frames_v'; end if;
  if (select count(*) from public.tf_writes) - w0 <> 2 then raise exception 'B2 쓰기'; end if;
  if (select count(*) from realtime.messages rm where rm.event = 'tetris') - r0 <> 2 then raise exception 'B2 초인종'; end if;
  w0 := w0 + 2; r0 := r0 + 2;
  checks := checks + 4;

  -- B3 a 프로토콜 2: 쓰기 1 · 초인종 0 · 두 자리 1 → 같은 호출의 응답이 곧바로 켜진다, 상대 응답도
  v := pg_temp.tf_report(a, sa1, mid, 2, 0, 0, 2);
  if v -> 'state' -> 'frames' is distinct from v_on then raise exception 'B3 frames %', v -> 'state' -> 'frames'; end if;
  if pg_temp.tf_state(b, sb1, mid) -> 'state' -> 'frames' is distinct from v_on then raise exception 'B3 상대 상태'; end if;
  if (select count(*) from public.tf_writes) - w0 <> 1 then raise exception 'B3 쓰기'; end if;
  if (select count(*) from realtime.messages rm where rm.event = 'tetris') - r0 <> 0 then raise exception 'B3 초인종'; end if;
  w0 := w0 + 1;
  checks := checks + 4;

  -- B4 b 가 프로토콜 1 로 내려감: 쓰기 1 · 초인종 0 · 양쪽 null(그쪽 첫 보고가 0 을 적는다)
  v := pg_temp.tf_report(b, sb1, mid, 2, 0, 0, 1);
  if v -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'B4 %', v; end if;
  if pg_temp.tf_state(a, sa1, mid) -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'B4 상대 상태'; end if;
  if (select frames_v from public.tetris_players where match_id = mid and user_id = b) is distinct from 0::smallint then raise exception 'B4 frames_v'; end if;
  if (select count(*) from public.tf_writes) - w0 <> 1 then raise exception 'B4 쓰기'; end if;
  w0 := w0 + 1;
  checks := checks + 4;

  -- B5 공격 보고: 프로토콜 1 · 2 모두 쓰기 1 · 초인종 1
  v := pg_temp.tf_report(b, sb1, mid, 3, 0, 1, 2);
  if v ->> 'status' is distinct from 'ok' or v -> 'state' -> 'frames' is distinct from v_on then raise exception 'B5 %', v; end if;
  if (select count(*) from public.tf_writes) - w0 <> 1 then raise exception 'B5 쓰기(2)'; end if;
  if (select count(*) from realtime.messages rm where rm.event = 'tetris') - r0 <> 1 then raise exception 'B5 초인종(2)'; end if;
  w0 := w0 + 1; r0 := r0 + 1;
  v := pg_temp.tf_report(b, sb1, mid, 4, 0, 2, 1);
  if v ->> 'status' is distinct from 'ok' then raise exception 'B5 %', v; end if;
  if (select count(*) from public.tf_writes) - w0 <> 1 then raise exception 'B5 쓰기(1)'; end if;
  if (select count(*) from realtime.messages rm where rm.event = 'tetris') - r0 <> 1 then raise exception 'B5 초인종(1)'; end if;
  w0 := w0 + 1; r0 := r0 + 1;
  checks := checks + 5;

  -- B6 늦은 보고(프로토콜 2, seq 이하): stale · 쓰기 0 · 칸 그대로(0)
  v := pg_temp.tf_report(b, sb1, mid, 4, 0, 2, 2);
  if v ->> 'status' is distinct from 'stale' then raise exception 'B6 %', v; end if;
  if (select frames_v from public.tetris_players where match_id = mid and user_id = b) is distinct from 0::smallint then raise exception 'B6 stale 이 칸을 적었다'; end if;
  if (select count(*) from public.tf_writes) - w0 <> 0 then raise exception 'B6 쓰기'; end if;
  checks := checks + 3;

  -- B7 p_protocol 0: unsupported_client · 쓰기 0
  v := pg_temp.tf_report(b, sb1, mid, 9, 0, 2, 0);
  if v ->> 'status' is distinct from 'unsupported_client' then raise exception 'B7 %', v; end if;
  if (select count(*) from public.tf_writes) - w0 <> 0 then raise exception 'B7 쓰기'; end if;
  checks := checks + 2;

  -- 다시 켠다
  v := pg_temp.tf_report(b, sb1, mid, 5, 0, 2, 2);
  if v -> 'state' -> 'frames' is distinct from v_on then raise exception 'B8 %', v; end if;
  w0 := w0 + 1;
  checks := checks + 1;

  -- B9 다른 기기(프로토콜 2, 큰 seq): other_device · 쓰기 0 · 칸 그대로 · 그 응답의 frames 는 null
  v := pg_temp.tf_report(a, sa2, mid, 99, 0, 0, 2);
  if v ->> 'status' is distinct from 'other_device' or v -> 'state' -> 'frames' <> 'null'::jsonb or v -> 'state' ->> 'my_device' is distinct from 'other' then raise exception 'B9 %', v; end if;
  if (select count(*) from public.tf_writes) - w0 <> 0 then raise exception 'B9 쓰기'; end if;
  if (select seq from public.tetris_players where match_id = mid and user_id = a) is distinct from 2 then raise exception 'B9 seq'; end if;
  checks := checks + 3;

  -- B10 읽기는 칸을 안 바꾼다(프로토콜 1 로 읽어도 켜진 채) · 프로토콜 2 로 읽어도 된다
  if pg_temp.tf_state(a, sa1, mid, 1) -> 'state' -> 'frames' is distinct from v_on then raise exception 'B10 p1'; end if;
  v := pg_temp.tf_state(a, sa1, mid, 2);
  if v ->> 'status' is distinct from 'ok' or v -> 'state' -> 'frames' is distinct from v_on then raise exception 'B10 p2 %', v; end if;
  if (select count(*) from public.tf_writes) - w0 <> 0 then raise exception 'B10 쓰기'; end if;
  -- 세션 없는 토큰: 기기를 가를 수 없으니 켜진다(옛 동작과 같은 fail-open)
  v := pg_temp.tf_state(a, null, mid, 1);
  if v -> 'state' -> 'frames' is distinct from v_on or v -> 'state' -> 'my_device' <> 'null'::jsonb then raise exception 'B10 세션 없음 %', v; end if;
  checks := checks + 4;

  -- B11 뒤에 올 프로토콜(3)도 프레임을 아는 기기다(>= 2): 쓰기 1 · 초인종 0 · 칸 1 · 켜진 채
  v := pg_temp.tf_report(b, sb1, mid, 6, 0, 2, 3);
  if v ->> 'status' is distinct from 'ok' or v -> 'state' -> 'frames' is distinct from v_on then raise exception 'B11 %', v; end if;
  if (select frames_v from public.tetris_players where match_id = mid and user_id = b) is distinct from 1::smallint then raise exception 'B11 frames_v'; end if;
  if (select count(*) from public.tf_writes) - w0 <> 1 then raise exception 'B11 쓰기'; end if;
  if (select count(*) from realtime.messages rm where rm.event = 'tetris') - r0 <> 0 then raise exception 'B11 초인종'; end if;
  w0 := w0 + 1;
  -- B12 p_protocol null(옛 본문이 칸을 빠뜨린 모양): unsupported_client · 쓰기 0 · 칸 그대로
  v := pg_temp.tf_rpc(b, sb1, format(
    'select public.tetris_report(p_protocol => null, p_match_id => %L::uuid, p_seq => 7, p_board => %L, p_lines => 0, '
    'p_garbage_sent => 2, p_garbage_applied => 0, p_pending => 0)', mid, repeat('.', 200)));
  if v ->> 'status' is distinct from 'unsupported_client' then raise exception 'B12 %', v; end if;
  if (select count(*) from public.tf_writes) - w0 <> 0 then raise exception 'B12 쓰기'; end if;
  if (select frames_v from public.tetris_players where match_id = mid and user_id = b) is distinct from 1::smallint then raise exception 'B12 칸'; end if;
  checks := checks + 8;

  ----------------------------------------------------------------------------------------------
  -- C. state.frames 진리표: frames_v(a) × frames_v(b) × 스위치 × 판 상태 × 기기 = 2·2·2·2·3 = 48칸
  ----------------------------------------------------------------------------------------------
  n := 0;
  foreach fa in array array[0, 1] loop
   foreach fb in array array[0, 1] loop
    foreach sw in array array[true, false] loop
     foreach st in array array['active', 'finished'] loop
      foreach dev in array array['this', 'other', 'null'] loop
        update public.tetris_players set frames_v = fa where match_id = mid and user_id = a;
        update public.tetris_players set frames_v = fb where match_id = mid and user_id = b;
        update public.tetris_matches
           set status = st,
               result = case when st = 'finished' then 'draw' end,
               end_reason = case when st = 'finished' then 'time_cap' end,
               finished_at = case when st = 'finished' then clock_timestamp() end
         where id = mid;
        execute format('create or replace function public.tetris_frames_enabled() returns boolean language sql immutable as %L', 'select ' || sw);
        sess := case dev when 'this' then sa1 when 'other' then sa2 else null end;
        v := pg_temp.tf_state(a, sess, mid);
        if v ->> 'status' is distinct from 'ok' then raise exception 'C 응답 % (%/%/%/%/%)', v, fa, fb, sw, st, dev; end if;
        v_exp := case when fa = 1 and fb = 1 and sw and st = 'active' and dev <> 'other' then v_on else 'null'::jsonb end;
        if not (v -> 'state' ? 'frames') or v -> 'state' -> 'frames' is distinct from v_exp then
          raise exception 'C 진리표 틀림: a=% b=% sw=% st=% dev=% → % (기대 %)', fa, fb, sw, st, dev, v -> 'state' -> 'frames', v_exp;
        end if;
        if (v -> 'state' ->> 'my_device') is distinct from (case dev when 'null' then null else dev end) then
          raise exception 'C my_device %', v -> 'state' -> 'my_device';
        end if;
        n := n + 1;
      end loop;
     end loop;
    end loop;
   end loop;
  end loop;
  if n <> 48 then raise exception 'C 칸 수 %', n; end if;
  checks := checks + n;
  update public.tetris_players set frames_v = 1 where match_id = mid;
  update public.tetris_matches set status = 'active', result = null, end_reason = null, finished_at = null where id = mid;
  execute 'create or replace function public.tetris_frames_enabled() returns boolean language sql immutable as ''select true''';

  -- C2. active 가 아닌 나머지 상태(거절 · 취소 · 만료. 대기는 A, 끝남은 C · G)도 꺼진다 — 두 자리 1 · 스위치 켬 · 이 기기여도
  foreach st in array array['declined', 'cancelled', 'expired'] loop
    update public.tetris_matches set status = st where id = mid;
    v := pg_temp.tf_state(a, sa1, mid);
    if v ->> 'status' is distinct from 'ok' or v -> 'state' ->> 'status' is distinct from st
       or not (v -> 'state' ? 'frames') or v -> 'state' -> 'frames' <> 'null'::jsonb then
      raise exception 'C2 [%] frames %', st, v -> 'state';
    end if;
    if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, false) is distinct from false then raise exception 'C2 [%] 읽기 인가', st; end if;
    if pg_temp.tf_allowed(b, sb1, 'tetris:' || mid, true)  is distinct from false then raise exception 'C2 [%] 쓰기 인가', st; end if;
    checks := checks + 3;
  end loop;
  update public.tetris_matches set status = 'active' where id = mid;
  -- 되돌리면 다시 켜진다(앞 단언이 언제나 null 인 응답에 헛돌지 않았다)
  if pg_temp.tf_state(a, sa1, mid) -> 'state' -> 'frames' is distinct from v_on then raise exception 'C2 복귀'; end if;
  checks := checks + 1;

  ----------------------------------------------------------------------------------------------
  -- D. tetris_frame_allowed 경우별
  ----------------------------------------------------------------------------------------------
  -- 참가자(이 세션): 읽기·쓰기 true, 양쪽 자리
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, false) is distinct from true then raise exception 'D a 읽기'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, true)  is distinct from true then raise exception 'D a 쓰기'; end if;
  if pg_temp.tf_allowed(b, sb1, 'tetris:' || mid, false) is distinct from true then raise exception 'D b 읽기'; end if;
  if pg_temp.tf_allowed(b, sb1, 'tetris:' || mid, true)  is distinct from true then raise exception 'D b 쓰기'; end if;
  -- 제3자
  if pg_temp.tf_allowed(c, sc, 'tetris:' || mid, false) is distinct from false then raise exception 'D 제3자 읽기'; end if;
  if pg_temp.tf_allowed(c, sc, 'tetris:' || mid, true)  is distinct from false then raise exception 'D 제3자 쓰기'; end if;
  -- other 세션: 읽기는 되고 쓰기는 안 된다
  if pg_temp.tf_allowed(a, sa2, 'tetris:' || mid, false) is distinct from true then raise exception 'D other 읽기'; end if;
  if pg_temp.tf_allowed(a, sa2, 'tetris:' || mid, true)  is distinct from false then raise exception 'D other 쓰기'; end if;
  -- 세션 없는 토큰 · 세션이 uuid 가 아닌 토큰: 가를 수 없어 통과(표시 전용 fail-open, 명세 §9)
  if pg_temp.tf_allowed(a, null, 'tetris:' || mid, true)  is distinct from true then raise exception 'D 세션 없음 쓰기'; end if;
  if pg_temp.tf_allowed(a, null, 'tetris:' || mid, false) is distinct from true then raise exception 'D 세션 없음 읽기'; end if;
  if pg_temp.tf_allowed(a, 'not-a-uuid', 'tetris:' || mid, true) is distinct from true then raise exception 'D 깨진 세션'; end if;
  -- poke 토픽: 내 것 · 남의 것
  if pg_temp.tf_allowed(a, sa1, public.poke_topic(a), false) is distinct from false then raise exception 'D poke 내 읽기'; end if;
  if pg_temp.tf_allowed(a, sa1, public.poke_topic(a), true)  is distinct from false then raise exception 'D poke 내 쓰기'; end if;
  if pg_temp.tf_allowed(a, sa1, public.poke_topic(b), false) is distinct from false then raise exception 'D poke 남 읽기'; end if;
  if pg_temp.tf_allowed(a, sa1, public.poke_topic(b), true)  is distinct from false then raise exception 'D poke 남 쓰기'; end if;
  -- 깨진 토픽 · 없는 판 · 토픽 없음(Realtime 밖)
  if pg_temp.tf_allowed(a, sa1, 'tetris:not-a-uuid', false) is distinct from false then raise exception 'D 깨진 uuid 읽기'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:not-a-uuid', true)  is distinct from false then raise exception 'D 깨진 uuid 쓰기'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:', true)            is distinct from false then raise exception 'D 빈 uuid'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || gen_random_uuid(), true) is distinct from false then raise exception 'D 없는 판'; end if;
  if pg_temp.tf_allowed(a, sa1, 'TETRIS:' || mid, true)     is distinct from false then raise exception 'D 접두사 대문자'; end if;
  if pg_temp.tf_allowed(a, sa1, 'xtetris:' || mid, true)    is distinct from false then raise exception 'D 접두사 앞 글자'; end if;
  if pg_temp.tf_allowed(a, sa1, null, true)                 is distinct from false then raise exception 'D 토픽 없음'; end if;
  -- 깨진 sub(토큰이 이상해도 예외가 새면 안 된다): tetris 토픽 · poke 토픽
  if pg_temp.tf_allowed(null, sa1, 'tetris:' || mid, true, 'garbage') is distinct from false then raise exception 'D 깨진 sub tetris'; end if;
  if pg_temp.tf_allowed(null, sa1, 'poke:' || a, true, 'garbage')     is distinct from false then raise exception 'D 깨진 sub poke'; end if;
  if pg_temp.tf_allowed(null, null, 'tetris:' || mid, true, '')       is distinct from false then raise exception 'D 빈 sub'; end if;
  checks := checks + 26;

  -- 서버가 내린 토픽 글자를 그대로 쓴다(클라는 조립하지 않는다): 'tetris:' + 소문자 하이픈 uuid = 43자, 인가가 바로 그 글자를 받는다
  tp := pg_temp.tf_state(b, sb1, mid) -> 'state' -> 'frames' ->> 'topic';
  if tp is distinct from 'tetris:' || lower(mid::text) or length(tp) <> 43 then raise exception 'D 서버 토픽 글자 %', tp; end if;
  if pg_temp.tf_allowed(b, sb1, tp, true) is distinct from true or pg_temp.tf_allowed(a, sa1, tp, false) is distinct from true then
    raise exception 'D 서버 토픽 인가';
  end if;
  -- 같은 판의 다른 철자(대문자 · 중괄호 · 하이픈 없음)는 uuid 로는 같은 판이라 참가자는 통과한다(서버가 내리지 않는 다른 채널일 뿐 표시 전용).
  -- 제3자는 어떤 철자로도 거절이다.
  foreach tp in array array['tetris:' || upper(mid::text), 'tetris:{' || mid::text || '}', 'tetris:' || replace(mid::text, '-', '')] loop
    if pg_temp.tf_allowed(c, sc, tp, false) is distinct from false or pg_temp.tf_allowed(c, sc, tp, true) is distinct from false then
      raise exception 'D 제3자 다른 철자 % 통과', tp;
    end if;
  end loop;
  checks := checks + 5;

  -- poke 토픽은 표를 안 읽는다: tetris_matches 스캔 수가 그대로다(양성 대조: tetris 토픽은 는다)
  select coalesce(seq_scan, 0) + coalesce(idx_scan, 0) into s0 from pg_stat_xact_user_tables where relid = 'public.tetris_matches'::regclass;
  perform pg_temp.tf_allowed(a, sa1, public.poke_topic(a), false);
  perform pg_temp.tf_allowed(a, sa1, public.poke_topic(b), true);
  if (select coalesce(seq_scan, 0) + coalesce(idx_scan, 0) from pg_stat_xact_user_tables where relid = 'public.tetris_matches'::regclass) <> s0 then
    raise exception 'D poke 토픽이 표를 읽었다';
  end if;
  perform pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, false);
  if (select coalesce(seq_scan, 0) + coalesce(idx_scan, 0) from pg_stat_xact_user_tables where relid = 'public.tetris_matches'::regclass) <= s0 then
    raise exception 'D 양성 대조 실패: tetris 토픽의 스캔이 안 잡힌다(앞 단언이 헛돈다)';
  end if;
  checks := checks + 2;

  -- 실행권: authenticated · service_role 있음, anon 없음(앱 역할로 실제 호출)
  if not has_function_privilege('authenticated', 'public.tetris_frame_allowed(boolean)', 'EXECUTE') then raise exception 'D authenticated 실행권'; end if;
  if not has_function_privilege('service_role', 'public.tetris_frame_allowed(boolean)', 'EXECUTE') then raise exception 'D service_role 실행권'; end if;
  if has_function_privilege('anon', 'public.tetris_frame_allowed(boolean)', 'EXECUTE') then raise exception 'D anon 실행권'; end if;
  begin
    perform pg_temp.tf_as(null, null, 'anon');
    perform public.tetris_frame_allowed(false);
    raise exception 'D anon 호출이 통과' using errcode = 'TFBAD';
  exception when insufficient_privilege then
    null;
  end;
  if current_user is distinct from v_exec then raise exception 'D 역할이 %', current_user; end if;
  checks := checks + 4;

  -- 스위치 끔: 참가자도 false
  execute 'create or replace function public.tetris_frames_enabled() returns boolean language sql immutable as ''select false''';
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, false) is distinct from false then raise exception 'D 스위치 끔 읽기'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, true)  is distinct from false then raise exception 'D 스위치 끔 쓰기'; end if;
  execute 'create or replace function public.tetris_frames_enabled() returns boolean language sql immutable as ''select true''';
  checks := checks + 2;

  ----------------------------------------------------------------------------------------------
  -- E. 정책 실평가(하네스 사본은 authenticated 표 권한 · 정책을 운영처럼 갖췄다). Realtime 의 인가 쿼리와 같은 모양.
  ----------------------------------------------------------------------------------------------
  if pg_temp.tf_ins(a, sa1, 'tetris:' || mid) is distinct from 'ok' then raise exception 'E a 쓰기 %', pg_temp.tf_ins(a, sa1, 'tetris:' || mid); end if;
  if pg_temp.tf_ins(b, sb1, 'tetris:' || mid) is distinct from 'ok' then raise exception 'E b 쓰기'; end if;
  if pg_temp.tf_ins(c, sc,  'tetris:' || mid) is distinct from '42501' then raise exception 'E 제3자 쓰기'; end if;
  if pg_temp.tf_ins(a, sa2, 'tetris:' || mid) is distinct from '42501' then raise exception 'E other 쓰기'; end if;
  if pg_temp.tf_ins(a, sa1, 'tetris:' || mid, 'presence') is distinct from '42501' then raise exception 'E presence 쓰기'; end if;
  -- ★ 가짜 초인종: 내 것 · 상대 것 · 제3자 것 모두 거절
  if pg_temp.tf_ins(a, sa1, public.poke_topic(a)) is distinct from '42501' then raise exception 'E poke 내 쓰기가 열렸다'; end if;
  if pg_temp.tf_ins(a, sa1, public.poke_topic(b)) is distinct from '42501' then raise exception 'E poke 상대 쓰기가 열렸다'; end if;
  if pg_temp.tf_ins(c, sc,  public.poke_topic(a)) is distinct from '42501' then raise exception 'E poke 제3자 쓰기가 열렸다'; end if;
  checks := checks + 8;

  n := pg_temp.tf_sel(a, sa1, 'tetris:' || mid);
  if n < 2 then raise exception 'E a 읽기 %행', n; end if;
  if pg_temp.tf_sel(b, sb1, 'tetris:' || mid) <> n then raise exception 'E b 읽기'; end if;
  if pg_temp.tf_sel(c, sc,  'tetris:' || mid) <> 0 then raise exception 'E 제3자가 읽었다'; end if;
  -- ★ 초인종 조인(P3b 의 로컬 대응): 내 poke 토픽은 이 판의 초인종이 보이고, 오류가 안 난다 · 남의 것은 0행
  if pg_temp.tf_sel(a, sa1, public.poke_topic(a)) < 1 then raise exception 'E 내 초인종이 안 보인다'; end if;
  if pg_temp.tf_sel(b, sb1, public.poke_topic(b)) < 1 then raise exception 'E 상대 초인종이 안 보인다'; end if;
  if pg_temp.tf_sel(a, sa1, public.poke_topic(b)) <> 0 then raise exception 'E 남의 초인종이 보인다'; end if;
  if pg_temp.tf_sel(c, sc,  public.poke_topic(a)) <> 0 then raise exception 'E 제3자에게 초인종이 보인다'; end if;
  checks := checks + 7;

  -- 정책 없는 anon: 어떤 토픽도 못 쓴다(함수에 닿기 전에 막힌다)
  begin
    perform pg_temp.tf_as(null, null, 'anon');
    perform set_config('realtime.topic', 'tetris:' || mid, true);
    insert into realtime.messages (topic, extension, event, payload, private) values ('tetris:' || mid, 'broadcast', 'frame', '{}', true);
    raise exception 'E anon 쓰기가 통과' using errcode = 'TFBAD';
  exception when insufficient_privilege then
    null;
  end;
  checks := checks + 1;

  ----------------------------------------------------------------------------------------------
  -- F. 구버전 본문(p_protocol=1) 차등: 정본 복제(tf_old_*)와 새 함수에 같은 상태 · 같은 입력을 넣고 응답 · 행을 비교한다.
  --    다른 곳은 frames 키 · frames_v 칸뿐이어야 한다. 각 경우는 센티널로 되돌려 같은 출발점에서 돈다.
  ----------------------------------------------------------------------------------------------
  for sc_row in
    select * from (values
      ('평범한 보고',     a, sa1, 3,  1, 0, false, null::text, 1, 'ok'),
      ('공격 보고',       a, sa1, 3,  1, 3, false, null, 1, 'ok'),
      ('탑아웃 정산',     a, sa1, 3,  1, 0, true,  null, 1, 'ok'),
      ('늦은 보고',       a, sa1, 2,  0, 0, false, null, 1, 'stale'),
      ('다른 기기',       a, sa2, 50, 1, 0, false, null, 1, 'other_device'),
      ('세션 없는 토큰',  a, null, 3, 1, 0, false, null, 1, 'ok'),
      ('공격이 뒤로',     b, sb1, 9, 0, 0, false, null, 1, 'other_device'),
      ('판 글자 깨짐',    a, sa1, 3,  1, 0, false, 'xx', 1, 'invalid'),
      ('제3자',           c, sc,  3,  1, 0, false, null, 1, 'not_found'),
      ('프로토콜 0',      a, sa1, 3,  1, 0, false, null, 0, 'unsupported_client'),
      ('프로토콜 2 평범', a, sa1, 3,  1, 0, false, null, 2, 'ok')
    ) t(name, uid, sess, seq, lines, sent, topped, board, proto, want)
  loop
    sc_name := sc_row.name;
    -- 쓰기 수(사람 행 UPDATE · 초인종)는 센티널 안에서 재 둔다. 변수는 롤백되지 않는다.
    begin
      wo := (select count(*) from public.tf_writes);
      ro := (select count(*) from realtime.messages rm where rm.event = 'tetris');
      v_old := pg_temp.tf_report(sc_row.uid, sc_row.sess, mid, sc_row.seq, greatest(sc_row.lines, 0), sc_row.sent, sc_row.proto, sc_row.topped, 'public.tf_old_report', sc_row.board);
      v_old_r := pg_temp.tf_rows(mid);
      wo := (select count(*) from public.tf_writes) - wo;
      ro := (select count(*) from realtime.messages rm where rm.event = 'tetris') - ro;
      raise exception 'sentinel' using errcode = 'TFSNT';
    exception when sqlstate 'TFSNT' then null;
    end;
    begin
      wn := (select count(*) from public.tf_writes);
      rn := (select count(*) from realtime.messages rm where rm.event = 'tetris');
      v_new := pg_temp.tf_report(sc_row.uid, sc_row.sess, mid, sc_row.seq, greatest(sc_row.lines, 0), sc_row.sent, sc_row.proto, sc_row.topped, 'public.tetris_report', sc_row.board);
      v_new_r := pg_temp.tf_rows(mid);
      wn := (select count(*) from public.tf_writes) - wn;
      rn := (select count(*) from realtime.messages rm where rm.event = 'tetris') - rn;
      raise exception 'sentinel' using errcode = 'TFSNT';
    exception when sqlstate 'TFSNT' then null;
    end;
    if wn is distinct from wo or rn is distinct from ro then
      raise exception 'F [%] 호출당 쓰기가 다르다: 옛 UPDATE % · 초인종 % / 새 UPDATE % · 초인종 %', sc_name, wo, ro, wn, rn;
    end if;
    wmax := greatest(wmax, wn); rmax := greatest(rmax, rn);
    checks := checks + 1;
    if v_new ->> 'status' is distinct from sc_row.want or v_old ->> 'status' is distinct from sc_row.want then
      raise exception 'F [%] 상태 옛 % 새 % (기대 %)', sc_name, v_old ->> 'status', v_new ->> 'status', sc_row.want;
    end if;
    if v_new ? 'state' and not (v_new -> 'state' ? 'frames') then raise exception 'F [%] 새 응답에 frames 키가 없다', sc_name; end if;
    if v_old ? 'state' and v_old -> 'state' ? 'frames' then raise exception 'F [%] 복제가 정본이 아니다', sc_name; end if;
    if pg_temp.tf_strip(v_new) is distinct from pg_temp.tf_strip(v_old) then
      raise exception 'F [%] 응답이 다르다: 옛 % / 새 %', sc_name, pg_temp.tf_strip(v_old), pg_temp.tf_strip(v_new);
    end if;
    if v_new_r is distinct from v_old_r then
      raise exception 'F [%] 행이 다르다: 옛 % / 새 %', sc_name, v_old_r, v_new_r;
    end if;
    checks := checks + 3;
  end loop;
  -- 차등이 헛돌지 않았다: 위 경우들이 정말 서로 다른 상태를 냈다(탑아웃은 끝난 판, 프로토콜 0 은 거절)
  if v_new ->> 'status' is distinct from 'ok' then raise exception 'F 마지막 경우가 %', v_new; end if;
  if (select status from public.tetris_matches where id = mid) is distinct from 'active' then raise exception 'F 센티널이 판을 못 되돌렸다'; end if;
  -- 쓰기 수 비교가 헛돌지 않았다: 어떤 경우는 실제로 사람 행을 쓰고 초인종을 울렸다(0 = 0 만 견준 게 아니다)
  if wmax < 1 or rmax < 1 then raise exception 'F 쓰기 계수가 헛돈다(UPDATE 최대 % · 초인종 최대 %)', wmax, rmax; end if;
  checks := checks + 3;

  ----------------------------------------------------------------------------------------------
  -- G. 끝난 판: 진짜 탑아웃으로 끝낸다 → 양쪽 frames null · 인가 false(정책 평가도 거절)
  ----------------------------------------------------------------------------------------------
  v := pg_temp.tf_report(a, sa1, mid, 3, 1, 0, 2, true);
  if v ->> 'status' is distinct from 'ok' or v -> 'state' ->> 'status' is distinct from 'finished' or v -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'G %', v; end if;
  if pg_temp.tf_state(b, sb1, mid) -> 'state' -> 'frames' <> 'null'::jsonb then raise exception 'G 상대 상태'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, false) is distinct from false then raise exception 'G 끝난 판 읽기'; end if;
  if pg_temp.tf_allowed(a, sa1, 'tetris:' || mid, true)  is distinct from false then raise exception 'G 끝난 판 쓰기'; end if;
  if pg_temp.tf_allowed(b, sb1, 'tetris:' || mid, false) is distinct from false then raise exception 'G 끝난 판 읽기 b'; end if;
  if pg_temp.tf_ins(a, sa1, 'tetris:' || mid) is distinct from '42501' then raise exception 'G 끝난 판 쓰기 정책'; end if;
  if pg_temp.tf_sel(a, sa1, 'tetris:' || mid) <> 0 then raise exception 'G 끝난 판 읽기 정책'; end if;
  checks := checks + 7;

  ----------------------------------------------------------------------------------------------
  -- H. 불변: 프로토콜 1 · tetris__due 본문 · 정책 3개
  ----------------------------------------------------------------------------------------------
  if public.tetris_protocol() is distinct from 1 then raise exception 'H 프로토콜'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.tetris__due(uuid,timestamp with time zone)'::regprocedure) is distinct from 'f172dad332205d56b1dc696f3386a6e0' then raise exception 'H tetris__due'; end if;
  if (select count(*) from pg_policies where schemaname = 'realtime' and tablename = 'messages') <> 3 then raise exception 'H 정책 수'; end if;
  checks := checks + 3;

  raise notice 'tetris_frames_test: 전부 통과 — 단언 %건', checks;
end
$t$;
