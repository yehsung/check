#!/usr/bin/env python3
# 20261107120000_tetris_frames.sql 생성기. 두 함수 본문을 ONE 파일에서 바이트 그대로 뽑아 치환표만 적용한다(손으로 베끼면 흘러내린다).
# 사용: gen_migration.py <ONE 파일> <출력 파일> [--old-out <구버전 복제 SQL>]
import re, sys
one_path, out_path = sys.argv[1], sys.argv[2]
one = open(one_path, encoding='utf-8').read()

def definition(name):
    head = f'create or replace function public.{name}('
    at = one.rindex(head)
    end = one.index('\n$fn$;\n', at) + len('\n$fn$;\n')
    return one[at:end]

# ── 치환표: (옛 글, 새 글). 옛 글은 정본에 정확히 한 번 있어야 한다.
REPORT = [(
"         last_seen_at    = v_now,\n",
"         last_seen_at    = v_now,\n"
"         frames_v        = case when coalesce(p_protocol, 0) >= 2 then 1 else 0 end,\n",
)]
STATE = [
("  v_bal  int;\n",
 "  v_bal  int;\n  v_dev  text;\n  v_both boolean;\n"),
("'last_seen_ms', public.tetris__ms(ql.last_seen_at), 'topped_out', ql.topped_out_at is not null)\n    into v_me, v_op\n",
 "'last_seen_ms', public.tetris__ms(ql.last_seen_at), 'topped_out', ql.topped_out_at is not null),\n"
 "         coalesce(pl.frames_v, 0) = 1 and coalesce(ql.frames_v, 0) = 1\n"
 "    into v_me, v_op, v_both\n"),
("  select p.ruby_balance into v_bal from public.profiles p where p.id = p_uid;\n",
 "  select p.ruby_balance into v_bal from public.profiles p where p.id = p_uid;\n"
 "  v_dev := public.tetris__device(p_match_id, p_uid);\n"),
("    'my_device', public.tetris__device(p_match_id, p_uid),\n",
 "    'my_device', v_dev,\n"
 "    'frames', case when m.status = 'active' and public.tetris_frames_enabled() and v_both\n"
 "                    and v_dev is distinct from 'other'\n"
 "                   then jsonb_build_object('on', true, 'topic', 'tetris:' || m.id::text)\n"
 "                   else null end,\n"),
]

def patched(src, table):
    for old, new in table:
        assert src.count(old) == 1, old
        assert src.count(new) == 0, new
        src = src.replace(old, new)
    return src

report_old, state_old = definition('tetris_report'), definition('tetris__state')
report_new, state_new = patched(report_old, REPORT), patched(state_old, STATE)

def sql_lit(s):
    return "E'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"

def inverse(var, table):
    # 새 글 → 옛 글로 되돌리는 replace 사슬(마지막 치환부터).
    expr = var
    for old, new in reversed(table):
        expr = f"replace({expr},\n      {sql_lit(new)},\n      {sql_lit(old)})"
    return expr

CANON_STATE, CANON_REPORT, DUE = '57d06d9c9436ad280d64b8801ac7f2d0', '5dd80282ca3faabad41bd3fbd789065c', 'f172dad332205d56b1dc696f3386a6e0'

HEAD = f"""-- ══════════════════════════════════════════════════════════════════════════════════════════
-- 1:1 테트리스 — 판 표시 프레임을 비공개 Broadcast 로 옮길 서버 준비(칸 · 스위치 · 상태 키 · 인가 함수 · 정책 2개)
-- ══════════════════════════════════════════════════════════════════════════════════════════
-- 사용자 결정 원문(2026-10-31): 테트리스 대결 1초 보고를 Broadcast 로 "옮기기". 2초로 늘리는 것은 원하지 않는다.
-- 명세: tetris-broadcast/SPEC.md §4 · §9 · §11 · §12 · §16 · §17.
--
-- ── 무엇을 바꾸나 ──────────────────────────────────────────────────────────────────────────
--   1. tetris_players.frames_v   그 자리의 마지막 보고가 프레임을 아는 기기였나(0/1). tetris_report 가 같은 UPDATE 로 적는다.
--   2. tetris_frames_enabled()   서버 스위치(상수 함수). false 로 재정의하면 다음 응답부터 전 클라가 1초 보고로 돌아간다.
--   3. tetris_report             UPDATE 에 칸 하나. 그 밖은 20261103124000 본문과 바이트까지 같다(§6 (3) 의 단언이 잰다).
--   4. tetris__state             키 'frames' 하나. 응답 칸이 늘 뿐 옛 클라는 모르는 키를 무시한다.
--   5. tetris_frame_allowed()    realtime.messages 정책이 부르는 인가 함수. tetris: 토픽이 아니면 표를 읽기 전에 false.
--   6. 정책 둘                   "tetris frames read"(SELECT) · "tetris frames write"(INSERT).
--
-- ── 바꾸지 않는 것 ─────────────────────────────────────────────────────────────────────────
--   tetris_protocol()(1 유지: 올리면 구버전이 진행 중 판까지 unsupported_client 로 막힌다) · tetris__due(결정 D10 은 사용자 답 대기) ·
--   tetris_silence_ms · tetris__settle · tetris_attack_cap · tetris_watch · tetris__ring · 서명 · 실행권.
--   지갑 잠금 · 판정 순서는 그대로다. 호출당 쓰기 횟수도 그대로다(UPDATE 1회, 공격 때만 초인종).
--
-- ── 명세와 다른 곳(둘 다 조회·실패 면을 줄이는 쪽) ──────────────────────────────────────────
--   ① 명세는 frames 판정에서 tetris__device 를 한 번 더 부른다. 그러면 조회가 늘어(명세 §12-4 "조회 수를 늘리지 마라") 한 번 부른
--      값을 v_dev 에 담아 my_device 와 frames 가 같이 쓴다. 응답의 my_device 값은 같다.
--   ② 명세는 auth.uid() 를 선언부에서 읽는다. 선언부 예외는 함수 밖으로 새므로(깨진 sub → 정책 오류 → 초인종 조인 실패) 토픽 접두사
--      검사 뒤, 예외 블록 안에서 읽는다. tetris: 가 아닌 토픽은 사용자 값을 읽지 않고 돌아간다.
--
-- ── 잠금 · 적용 ────────────────────────────────────────────────────────────────────────────
--   CREATE POLICY 는 realtime.messages 에 가장 강한 잠금을 잡고, 그 표는 모든 realtime.send 가 쓴다. 그래서 첫 문장이 lock_timeout 3초
--   (넘기면 55P03 으로 파일 전체가 롤백된다 — 다시 시도), 정책을 파일 맨 뒤에 만들고 그 뒤에는 카탈로그 단언과 초소형 프로브만 둔다.
--   피크를 피해 적용한다. 흐름 프로브(픽스처 · 실호출)는 잠금을 오래 쥐므로 파일에 넣지 않고 재생 하네스에 둔다.
--   정책 생성 실패를 경고로 삼키지 않는다(20260819020000 과 다르다). 실패하면 파일이 통째로 롤백되니 멈추고 보고한다(명세 D6).
--   공개 채널로 우회하지 마라: 판돈이 걸린 판의 표시를 anon 키만 가진 누구나 위조할 수 있다.
--
-- ── ★ 푸시 직전 할 일(이 파일은 로컬 재생으로만 검증했다) ─────────────────────────────────────
--   (1) 아래 §0 의 md5 세 값은 로컬 재생 결과다. 운영과 같은지는 확인하지 않았다. 운영에서 읽기로 대조하거나, 첫 push 의 §0 가드에 맡긴다.
--       tetris__state {CANON_STATE} · tetris_report {CANON_REPORT} · tetris__due {DUE}
--   (2) 결정 D10 으로 tetris__due 가 먼저 바뀌면 §0 · §6 의 그 값을 함께 고친다.
--   (3) `supabase migration list --linked` 로 대기열을 보고 번호를 정한다(메모리 migration-include-all-applies-agent-drafts).
--   (4) 적용 직후 실제 앱의 poke: 조인 + 찌르기 수신을 본다(명세 P3b). 조인 오류면 곧바로 두 정책을 지운다(rollback.sql).
--
-- ★ 달러 인용 블록 안 주석에는 그 블록의 태그 글자를 적지 않는다.

-- ── §0 잠금 · 운영 본문 가드 ─────────────────────────────────────────────────────────────────
set local lock_timeout = '3s';

do $guard$
declare
  v text;
begin
  -- 트랜잭션 밖이면 위 문장이 이미 사라졌다. 그러면 파일이 원자적이지 않다 — 아무것도 바꾸기 전에 멈춘다.
  if current_setting('lock_timeout') is distinct from '3s' then
    raise exception 'lock_timeout 이 %다(기대 3s) — 이 파일이 한 트랜잭션으로 돌지 않는다, 배포 중단', current_setting('lock_timeout');
  end if;

  select md5(prosrc) into v from pg_proc where oid = 'public.tetris__state(uuid,uuid)'::regprocedure;
  -- 정본이거나, 이 파일이 이미 바꾼 본문(두 번째 적용)일 때만 계속.
  if v is distinct from '{CANON_STATE}'
     and not exists (select 1 from pg_proc where oid = 'public.tetris__state(uuid,uuid)'::regprocedure
                       and prosrc like '%''frames'', case when m.status = ''active''%') then
    raise exception 'tetris__state 본문 md5 가 %다(정본 {CANON_STATE[:8]}…) — 그 사이 누가 고쳤다, 배포 중단', v;
  end if;

  select md5(prosrc) into v from pg_proc
   where oid = 'public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)'::regprocedure;
  if v is distinct from '{CANON_REPORT}'
     and not exists (select 1 from pg_proc
                      where oid = 'public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)'::regprocedure
                        and prosrc like '%frames_v        = case when coalesce(p_protocol, 0) >= 2 then 1 else 0 end,%') then
    raise exception 'tetris_report 본문 md5 가 %다(정본 {CANON_REPORT[:8]}…) — 그 사이 누가 고쳤다, 배포 중단', v;
  end if;

  select md5(prosrc) into v from pg_proc where oid = 'public.tetris__due(uuid,timestamp with time zone)'::regprocedure;
  if v is distinct from '{DUE}' then
    raise exception 'tetris__due 본문 md5 가 %다(기대 {DUE[:8]}…) — D10 이 먼저 들어갔으면 이 값과 §6 을 고쳐라, 배포 중단', v;
  end if;

  if public.tetris_protocol() is distinct from 1 then
    raise exception 'tetris_protocol() 이 %다(기대 1) — 전제가 다르다, 배포 중단', public.tetris_protocol();
  end if;
end
$guard$;


-- ── §1 칸 ────────────────────────────────────────────────────────────────────────────────────
alter table public.tetris_players add column if not exists frames_v smallint not null default 0;
comment on column public.tetris_players.frames_v is
  '그 자리의 마지막 쓰기 보고가 프레임을 아는 기기였나(p_protocol >= 2 → 1, 아니면 0). 두 자리 모두 1 이어야 state.frames 가 켜진다. '
  '사람 단위인 tetris_capable 로는 기기 능력을 가를 수 없어서 자리 단위로 둔다. 표시 전용.';


-- ── §2 스위치(상수 함수 — 20261021120000 의 상수들과 같은 모양 · 같은 실행권) ─────────────────────
create or replace function public.tetris_frames_enabled()
returns boolean language sql immutable as $fn$ select true $fn$;
comment on function public.tetris_frames_enabled() is
  '판 표시 프레임 서버 스위치. false 로 재정의하면 state.frames 가 null 이 되고 tetris_frame_allowed 도 false 라 새 조인·토큰 갱신이 거절된다. '
  '앱 업데이트 없이 듣는 첫 되돌림이다(명세 §17).';
grant execute on function public.tetris_frames_enabled() to public, anon, authenticated, service_role;


-- ── §3 다시 쓴 함수 둘(20261103124000 정본 + 치환 — create or replace, 서명 · 실행권 그대로) ──────
"""

ALLOWED = """
-- ── §4 인가 함수 ─────────────────────────────────────────────────────────────────────────────
-- ★ 이 함수는 찌르기 조인의 경로에 들어간다. realtime.messages 정책은 OR 로 묶여 poke: 조인에서도 평가될 수 있다.
--   그래서 (가) tetris: 토픽이 아니면 표를 읽기 전에, 서브트랜잭션도 만들기 전에 돌아가고 (나) 안쪽 어떤 실패도 false 이며
--   (다) authenticated 에 EXECUTE 가 있어야 한다. 없으면 전원의 초인종 조인이 정책 오류로 깨진다.
create or replace function public.tetris_frame_allowed(p_write boolean default false)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_topic  text := realtime.topic();
  v_uid    uuid;
  v_id     uuid;
  v_a      uuid;
  v_b      uuid;
  v_status text;
begin
  if v_topic is null or left(v_topic, 7) <> 'tetris:' then
    return false;
  end if;
  if not public.tetris_frames_enabled() then
    return false;
  end if;
  begin
    v_uid := auth.uid();
    if v_uid is null then
      return false;
    end if;
    v_id := substr(v_topic, 8)::uuid;
    select g.challenger, g.opponent, g.status into v_a, v_b, v_status
      from public.tetris_matches g where g.id = v_id;
    if not found or v_status <> 'active' or v_uid not in (v_a, v_b) then
      return false;
    end if;
    if p_write then
      return public.tetris__device(v_id, v_uid) is distinct from 'other';
    end if;
    return true;
  exception when others then
    return false;
  end;
end
$fn$;
comment on function public.tetris_frame_allowed(boolean) is
  'realtime.messages 정책의 인가. tetris:<판> 토픽의 진행 중 판 참가자면 true, 쓰기는 다른 세션 기기를 뺀다. 그 밖과 내부 실패는 false. '
  'poke: 토픽은 표를 읽기 전에 false(가짜 초인종을 열지 않는다). 지우려면 정책을 먼저 지운다.';
revoke all on function public.tetris_frame_allowed(boolean) from public, anon;
grant execute on function public.tetris_frame_allowed(boolean) to authenticated, service_role;


-- ── §5 정책 둘(파일 맨 뒤 — 여기서 잡은 realtime.messages 잠금이 커밋까지 간다) ─────────────────────
drop policy if exists "tetris frames read" on realtime.messages;
create policy "tetris frames read" on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast' and public.tetris_frame_allowed(false));
drop policy if exists "tetris frames write" on realtime.messages;
create policy "tetris frames write" on realtime.messages for insert to authenticated
  with check (realtime.messages.extension = 'broadcast' and public.tetris_frame_allowed(true));

"""

ASSERT = f"""
-- ── §6 사후 단언(카탈로그만) ─────────────────────────────────────────────────────────────────
do $assert$
declare
  v_src   text;
  v_n     int;
  v_names text[];
  v_cat   record;
begin
  -- (1) 칸
  select a.atttypid::regtype::text as typ, a.attnotnull as nn, pg_get_expr(d.adbin, d.adrelid) as def into v_cat
    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'public.tetris_players'::regclass and a.attname = 'frames_v' and not a.attisdropped;
  if v_cat.typ is distinct from 'smallint' or v_cat.nn is distinct from true or v_cat.def is distinct from '0' then
    raise exception '(1) frames_v 칸이 %다(기대 smallint not null default 0). 배포 중단', v_cat;
  end if;

  -- (2) 프로토콜 · 침묵 판정은 그대로
  if public.tetris_protocol() is distinct from 1 then
    raise exception '(2) tetris_protocol() 이 %다 — 구버전이 진행 중 판까지 막힌다. 배포 중단', public.tetris_protocol();
  end if;
  select md5(prosrc) into v_src from pg_proc where oid = 'public.tetris__due(uuid,timestamp with time zone)'::regprocedure;
  if v_src is distinct from '{DUE}' then
    raise exception '(2) tetris__due 본문이 바뀌었다(%). D10 은 사용자 답 대기다. 배포 중단', v_src;
  end if;

  -- (3) 두 본문 = 정본 + 치환표(새 글을 옛 글로 되돌리면 정본 md5). 베낀 본문의 어느 한 줄도 흘러내리지 않았다.
  select prosrc into v_src from pg_proc
   where oid = 'public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)'::regprocedure;
  if md5({inverse('v_src', REPORT)}) is distinct from '{CANON_REPORT}' then
    raise exception '(3) tetris_report 본문이 정본 + 칸 하나가 아니다. 배포 중단';
  end if;
  select prosrc into v_src from pg_proc where oid = 'public.tetris__state(uuid,uuid)'::regprocedure;
  if md5({inverse('v_src', STATE)}) is distinct from '{CANON_STATE}' then
    raise exception '(3) tetris__state 본문이 정본 + 프레임 키가 아니다. 배포 중단';
  end if;

  -- (4) 정책은 정확히 셋 · INSERT 는 우리 것 하나 · 찌르기 구독 정책은 그대로
  select count(*)::int, array_agg(policyname::text order by policyname collate "C") into v_n, v_names
    from pg_policies where schemaname = 'realtime' and tablename = 'messages';
  if v_n is distinct from 3
     or v_names is distinct from array['tetris frames read', 'tetris frames write', 'users listen to their own poke channel'] then
    raise exception '(4) realtime.messages 정책이 %개 %다(기대 3개). 배포 중단', v_n, v_names;
  end if;
  if exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
              and cmd = 'INSERT' and policyname <> 'tetris frames write') then
    raise exception '(4) 다른 INSERT 정책이 있다 — 가짜 초인종. 배포 중단';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
                  and policyname = 'tetris frames write' and cmd = 'INSERT' and roles = array['authenticated']::name[]
                  and qual is null and strpos(with_check, 'tetris_frame_allowed(true)') > 0
                  and strpos(with_check, 'broadcast') > 0) then
    raise exception '(4) 쓰기 정책의 모양이 다르다. 배포 중단';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
                  and policyname = 'tetris frames read' and cmd = 'SELECT' and roles = array['authenticated']::name[]
                  and with_check is null and strpos(qual, 'tetris_frame_allowed(false)') > 0
                  and strpos(qual, 'broadcast') > 0) then
    raise exception '(4) 읽기 정책의 모양이 다르다. 배포 중단';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
                  and policyname = 'users listen to their own poke channel' and cmd = 'SELECT'
                  and strpos(qual, 'poke_topic') > 0 and strpos(qual, 'uid') > 0) then
    raise exception '(4) 찌르기 구독 정책이 달라졌다. 배포 중단';
  end if;

  -- (5) 인가 함수: 실행권 · 속성 · 접두사 검사가 표 읽기와 예외 블록보다 앞
  if not has_function_privilege('authenticated', 'public.tetris_frame_allowed(boolean)', 'EXECUTE') then
    raise exception '(5) authenticated 에 tetris_frame_allowed 실행권이 없다 — 전원의 초인종 조인이 깨진다. 배포 중단';
  end if;
  if has_function_privilege('anon', 'public.tetris_frame_allowed(boolean)', 'EXECUTE') then
    raise exception '(5) anon 에 tetris_frame_allowed 실행권이 있다. 배포 중단';
  end if;
  select p.prosrc into v_src from pg_proc p
   where p.oid = 'public.tetris_frame_allowed(boolean)'::regprocedure and p.prosecdef and p.provolatile = 's'
     and p.proconfig = array['search_path=public'];
  if v_src is null then
    raise exception '(5) tetris_frame_allowed 의 속성이 다르다(security definer · stable · search_path). 배포 중단';
  end if;
  if strpos(v_src, 'left(v_topic, 7) <> ''tetris:''') = 0
     or strpos(v_src, 'left(v_topic, 7) <> ''tetris:''') > strpos(v_src, 'public.tetris_matches')
     or strpos(v_src, 'left(v_topic, 7) <> ''tetris:''') > strpos(v_src, 'auth.uid()')
     or strpos(v_src, 'exception when others then') = 0 then
    raise exception '(5) tetris_frame_allowed 가 poke: 토픽에서 표를 읽기 전에 돌아가지 않는다. 배포 중단';
  end if;

  raise notice 'tetris_frames 사후 단언 전부 통과: 칸 · 프로토콜 1 · tetris__due 불변 · 본문 정본 · 정책 3개 · 인가 함수';
end
$assert$;


-- ── §7 초소형 프로브(앱 역할 · 센티널 롤백 · 표 행 없음) ─────────────────────────────────────────
-- 실행 역할 복귀는 RESET ROLE 을 쓰지 않는다. CLI 연결에선 세션 사용자로 떨어진다.
do $probe$
declare
  v_exec  text := current_user;
  v_uid   uuid := gen_random_uuid();
  v_peer  uuid := gen_random_uuid();
  v_topic text;
  v_ok    boolean;
begin
  begin
    perform set_config('request.jwt.claims',
                       jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    execute 'set local role authenticated';

    foreach v_topic in array array[public.poke_topic(v_uid), public.poke_topic(v_peer), 'tetris:not-a-uuid',
                                   'tetris:' || gen_random_uuid()::text, ''] loop
      perform set_config('realtime.topic', v_topic, true);
      -- 실행권이 없으면 여기서 42501 로 파일 전체가 멈춘다. 그게 이 프로브의 첫째 일이다.
      if public.tetris_frame_allowed(false) is distinct from false
         or public.tetris_frame_allowed(true) is distinct from false then
        raise exception '토픽 "%" 에서 tetris_frame_allowed 가 false 가 아니다. 배포 중단', v_topic;
      end if;
    end loop;

    -- 앱이 할 수 없어야 하는 일: poke: 토픽 쓰기. RLS 거절(42501)만 통과로 친다.
    foreach v_topic in array array[public.poke_topic(v_uid), public.poke_topic(v_peer)] loop
      perform set_config('realtime.topic', v_topic, true);
      v_ok := false;
      begin
        insert into realtime.messages (topic, extension, event, payload, private)
        values (v_topic, 'broadcast', 'frame', '{{}}'::jsonb, true);
      exception when insufficient_privilege then
        v_ok := true;
      end;
      if not v_ok then
        raise exception '토픽 "%" 쓰기가 42501 로 거절되지 않았다 — 가짜 초인종이 열렸다. 배포 중단', v_topic;
      end if;
    end loop;

    raise exception 'tetris-frames-probe-rollback' using errcode = 'TFPRB';
  exception when sqlstate 'TFPRB' then
    null;
  end;
  if current_user is distinct from v_exec then
    raise exception '프로브가 역할을 %로 남겼다(기대 %). 배포 중단', current_user, v_exec;
  end if;
  if current_setting('realtime.topic', true) is not null and current_setting('realtime.topic', true) <> '' then
    raise exception '프로브가 realtime.topic 을 남겼다. 배포 중단';
  end if;
  raise notice 'tetris_frames 프로브 통과: poke: 쓰기 거절 · 인가 함수 실행권 · 깨진 토픽 false';
end
$probe$;
"""

sql = HEAD + state_new + '\n' + report_new + '\n' + ALLOWED + ASSERT
assert '$probe$' not in ASSERT.split('do $probe$',1)[1].rsplit('$probe$;',1)[0]
open(out_path, 'w', encoding='utf-8').write(sql)

# 구버전 복제(하네스 차등 시험용 — 이름만 바꾼 정본 두 함수)
if '--old-out' in sys.argv:
    o = sys.argv[sys.argv.index('--old-out') + 1]
    s = state_old.replace('public.tetris__state(', 'public.tf_old_state(')
    r = report_old.replace('public.tetris_report(', 'public.tf_old_report(').replace('public.tetris__state(', 'public.tf_old_state(')
    open(o, 'w', encoding='utf-8').write(s + '\n' + r + '\n')
