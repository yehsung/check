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

