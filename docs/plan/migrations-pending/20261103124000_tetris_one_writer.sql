-- ══════════════════════════════════════════════════════════════════════════════════════════
-- 1:1 테트리스 — 한 판 한 기기(one writer) · 맥 0.3.69 · 2026-10-30 '꼭대기 안 찼는데 졌다' 두 판
-- ══════════════════════════════════════════════════════════════════════════════════════════
--
-- ── 왜 ─────────────────────────────────────────────────────────────────────────────────────
-- 2026-10-30 15:47 · 15:49 KST 두 판(011ef7ee · 5734f1f8)에서 한 사람이 화면은 안 찼는데 '꼭대기까지 쌓였어요'로 졌다.
-- 그 계정이 맥 두 대(둘 다 0.3.68)에 로그인해 있었다. 원인 사슬:
--   ① 초인종은 사람의 **모든 기기**로 간다(tetris__ring → poke_topic(uid)).
--   ② 받은 기기마다 코어 스토어가 판을 만들고 판 루프를 돌리고, 준비가 서면 1초마다 보고한다(클라 갈래 — 같은 날 고침).
--   ③ 입력이 없는 쪽 맥의 판은 조각이 생긴 자리에 그대로 쌓였고, 그 보고가 같은 tetris_players 행을 덮어썼다
--      (board · lines 는 마지막 보고가 이긴다). 그 판이 꼭대기에 닿자 p_topped_out=true 를 냈고, 서버는 자기 탑아웃을
--      믿으므로(D9) 그 자리에서 판을 닫았다. 서버 행의 lines 0 · garbage_sent 3(공격만 단조라 진짜 맥 값이 남았다) ·
--      생성 방향 그대로 쌓인 탑이 그 흔적이다.
-- 0.3.60 부터 있던 구멍이다. 이 파일은 그 **서버 쪽 마개**이고, 옛 앱(≤ 0.3.68 · 폰 ≤ 1.0.14)에도 앱 업데이트 없이 듣는다.
--
-- ── 무엇을 바꾸나 ──────────────────────────────────────────────────────────────────────────
--   · 칸 둘: tetris_matches.challenger_session · opponent_session (uuid null) — 그 자리를 **연 기기의 로그인 세션**.
--   · 내부 도구 셋(두 밑줄 = 클라 실행권 0):
--       tetris__session()          부르는 토큰의 세션 id = nullif(auth.jwt()->>'session_id','')::uuid. 형이 안 맞으면 null.
--                                  (GoTrue v2.197 토큰은 session_id 를 싣는다. 따로 로그인한 두 기기는 세션이 다르다.)
--       tetris__device(판, 사람)   'this' | 'other' | null(가를 수 없다 — 기록 없음 · 토큰에 세션 없음 · 부르는 사람이 아님)
--       tetris__claim(판, 사람)    기록이 없는 진행 중 판이면 지금 세션으로 자리를 잡는다(이 파일 전에 수락된 판).
--   · 다시 쓴 함수 다섯(서명 · 실행권 그대로 — create or replace, drop 없음):
--       tetris_challenge   신청 행에 challenger_session 을 적는다.
--       tetris_respond     수락 전이에 opponent_session 을 적는다(거절은 그대로 — 대기 신청이다).
--       tetris_report      ⓪ 다른 기기면 other_device(쓰기 0 · 정산 0) · ⓪' 누계가 뒤로 가면 other_device · 기록 없으면 잡기.
--       tetris_resign      다른 기기면 other_device(정산 0) · 기록 없으면 잡기.
--       tetris__state      상태 묶음에 "my_device": 'this' | 'other' | null 한 칸.
--
-- ── 쓰기 규칙(보고 · 기권) ───────────────────────────────────────────────────────────────────
--   저장 세션(내 자리)   지금 세션     결과
--   있음                 있음 · 같다   그대로 진행
--   있음                 있음 · 다르다 {status:'other_device', state} — **아무것도 쓰지 않고 정산하지 않는다**
--   없음                 있음          진행 + 그 호출이 자리를 잡는다(보고는 단조 가드를 지나고 seq 가 앞선 — 실제로 쓰는 — 보고만)
--   (무엇이든)           없음          옛 동작(잠그지 않는다 — 세션을 못 싣는 토큰 · service_role)
--   단조 가드(보고만): p_seq 가 저장 seq 보다 큰데 p_lines < 저장 lines 이거나 p_garbage_sent < 저장 garbage_sent 이면
--   other_device. 한 기기의 누계는 줄지 않고(TetrisGame) 재개는 서버 값에서 잇는다(TetrisDuelSession resumingFrom).
--   ★ seq 가 저장값 이하인 늦은 보고는 가드에 걸지 않는다 — 기존 ④ stale 이 받는다(같은 기기의 순서 뒤집힘을 다른 기기로
--     몰면 클라가 판을 내려놓는다).
--
-- ── 거는 곳 / 안 거는 곳(호출자의 사람 행을 쓰거나 호출자 몫으로 판을 닫는 RPC 전수 — 2026-10-30 체인 grep) ──
--   거는 곳   tetris_report(준비 ready_at · 보고 · 탑아웃 정산) · tetris_resign(기권 정산).
--   안 건다   tetris_state — 시간 판정(tetris__due)만 돈다. '누가 불러도 닫힌다'는 설계(침묵·상한)라 기기를 안 가린다.
--             tetris_cancel — 대기 신청 취소(판돈 이동 없음). 다른 기기에서 거두는 것은 사용자의 뜻이다.
--             tetris_respond — 거절은 대기 신청이고, 수락은 바로 그 기기의 세션을 적는 자리다.
--             delete_my_account(abandoned) · tetris_settle_expired(cron) — 계정 · 서버 단위라 기기와 무관하다.
--   이 셋 말고 tetris_players 를 쓰거나 tetris__settle 을 부르는 클라 RPC 는 없다(§5 (4) 가 본문 순서를 되묻는다).
--
-- ── 옛 앱 ─────────────────────────────────────────────────────────────────────────────────
--   other_device 는 새 status 다. 옛 코어는 모르는 status 를 .unknown 으로 접고(TetrisWire.swift 머리말 ②) 보고 갈래에서
--   '보고 거절' 로그만 남긴다 — 판 루프는 돌지만 서버에 한 줄도 못 쓴다. 그래서 입력 없는 옛 맥이 진짜 판을 덮거나
--   탑아웃으로 닫는 일이 이 파일만으로 끝난다. 기권 갈래는 일반 실패 문구('잠시 후 다시 시도해 주세요')다.
--   my_device 는 새 키다 — 옛 디코더는 모르는 키를 버린다.
--
-- ── 남는 위험(알고 받는다) ───────────────────────────────────────────────────────────────────
--   · 판 중에 같은 기기에서 다시 로그인하면 세션이 바뀌어 그 판은 'other' 다 → 보고가 막혀 침묵 패. (판은 최대 8분.)
--   · 같은 맥의 두 프로세스는 같은 키체인 세션을 쓴다 → 세션으로는 못 가른다. 단조 가드가 첫 줄을 지운 뒤부터만 막는다.
--   · 이 파일 전에 수락된 진행 중 판은 기록이 없다 → 적용 뒤 가드를 지나 실제로 쓰는 첫 보고가 자리를 잡는다(최대 8분짜리 창).
--     첫 줄을 지우기 전이면 입력 없는 옛 기기의 보고도 가드를 지난다 — 그 창에서는 먼저 쓴 쪽이 잡는다.
--
-- ── 함정(이 저장소에서 데인 것) ───────────────────────────────────────────────────────────
--   · 서명을 바꾸지 않는다(바꾸면 옛 서명 drop + ACL · COMMENT 재부여 — PGRST203). 인자는 전부 DEFAULT(새 도구 둘 포함).
--   · 본문은 저장소 최신 정의에서 출발한다: tetris_challenge · tetris_respond · tetris_report · tetris_resign =
--     20261021120000 · tetris__state = 20261023120000(watchers 한 줄). §0 이 운영 본문 md5 로 되묻는다(어긋나면 멈춘다).
--   · 상수 함수의 PUBLIC 실행권을 회수하지 않는다(이 파일은 상수를 안 만든다). 새 도구 셋은 service_role 만.
--   · do 블록 · 함수 본문 안 주석에 달러 인용 태그 글자를 적지 않는다. 역할 복귀는 set local role(RESET ROLE 금지).
--   · 프로브는 합성 계정으로 실호출하고 센티널 예외로 통째 롤백한다. 초인종 realtime.send 는 표 행이라 같이 사라진다.
--
-- ── 잠금 ──────────────────────────────────────────────────────────────────────────────────
--   add column 이 tetris_matches 를 ACCESS EXCLUSIVE 로 쥔다(작은 표). 첫 문장에서 lock_timeout 3초 — 넘기면 55P03 으로
--   이 파일 전체가 롤백된다(남는 것 없음 · 한산할 때 다시 push). 쥐는 동안 대결 RPC 는 기다린다(프로브 포함 1초 안쪽).
--
-- ── 멱등성 ────────────────────────────────────────────────────────────────────────────────
--   §0 은 첫 적용(다섯 본문 = 정본 md5) 이거나 재적용(다섯 본문 = 이 파일 본문 md5)일 때만 지난다. 섞여 있거나 다른 값이면
--   누가 손댄 것이다 — create or replace 가 그 고침을 조용히 되돌리므로 멈춘다. add column if not exists · create or replace ·
--   같은 grant 재부여 · 임시 객체 drop 후 생성 · 프로브 센티널 롤백. 최상위 begin/commit 없음.
--
-- ── 되돌리기 ───────────────────────────────────────────────────────────────────────────────
--   다섯 함수를 정본 본문(위 두 파일의 마지막 정의)으로 다시 create or replace 하고 도구 셋을 drop 한다(그 순서 — 본문이
--   도구를 부른다). 칸 둘은 남겨도 무해하다. 클라(0.3.69+)는 my_device 가 없으면 '이 기기가 연 판' 기록으로 되돌아간다.
--
-- ── 뒤 파일이 이 다섯을 다시 정의할 때 ────────────────────────────────────────────────────────
--   출발점은 이 파일의 본문이다(TetrisOneWriterMigrationTests 가 "정본 + 치환표 = 이 파일 본문" 을 바이트로 되묻는다).
--   지킬 것: 보고 · 기권의 tetris__device 검사가 tetris__due · 사람 행 쓰기 · tetris__settle 보다 앞 · 단조 가드가
--   ready_at 쓰기보다 앞이고 seq 비교(p_seq > me.seq)를 품는다 · 잡기(tetris__claim)는 가드 뒤이고 보고에서는 seq 가 앞선
--   보고에만(늦은 보고 = stale 은 잡지 않는다) · 상태의 my_device.
-- ══════════════════════════════════════════════════════════════════════════════════════════


-- ── §0 잠금 · 사전 단언(운영 본문 md5) · 직전 기록 ───────────────────────────────────────────

-- (가) 잠금 — 이 파일의 첫 문장.
do $lk$
begin
  perform set_config('lock_timeout', '3s', true);
  lock table public.tetris_matches in access exclusive mode;
end
$lk$;

-- (나) 다섯 함수의 직전 모습(본문 md5 · 실행권 · 속성). §5 가 실행권·속성이 그대로인지 되묻는다.
create or replace function pg_temp.tow_attrs(p_fn regprocedure)
returns jsonb language sql stable as $tmp$
  select jsonb_build_object('oid', p.oid, 'acl', p.proacl::text, 'vol', p.provolatile, 'secdef', p.prosecdef,
                            'owner', p.proowner, 'lang', p.prolang, 'cfg', p.proconfig::text,
                            'ret', p.prorettype, 'args', pg_get_function_arguments(p.oid), 'strict', p.proisstrict)
    from pg_proc p where p.oid = p_fn
$tmp$;

drop table if exists pg_temp.tow_before;
create table pg_temp.tow_before (
  sig       text primary key,
  canon_md5 text not null,
  self_md5  text not null,
  md5       text,
  attrs     jsonb
);
-- canon = 저장소 최신 정의 본문의 md5(운영 본문과 같아야 한다) · self = 이 파일 §3 본문의 md5(재적용 핀).
-- §5 (3) 이 막 만든 본문으로 self 를 되묻는다 — 본문을 고치면 두 자리(여기 · TetrisOneWriterMigrationTests)를 같이 고친다.
insert into pg_temp.tow_before (sig, canon_md5, self_md5, md5, attrs)
select t.sig, t.canon_md5, t.self_md5, md5(p.prosrc), pg_temp.tow_attrs(p.oid)
  from (values
    ('public.tetris__state(uuid,uuid)',                                                 '640c937fb037ef55788dcaa546859d6a', '57d06d9c9436ad280d64b8801ac7f2d0'),
    ('public.tetris_challenge(integer,uuid,integer)',                                   '279093b471a03430a72f13073038c815', 'f5dc04eee9f829bcf01ec810b82d3402'),
    ('public.tetris_respond(integer,uuid,boolean)',                                     '0e64b4be06bc695b186be191a3e3ace4', '973e4bd501aae8bec4d2ab31aa966950'),
    ('public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)', '846dde8a13f5d4fa30dfc3bdbb41da62', '5dd80282ca3faabad41bd3fbd789065c'),
    ('public.tetris_resign(integer,uuid)',                                              '4643316b7cfbed99457ecf2709153974', '713bddce334a3c29cfe0387063ad3677')
  ) as t(sig, canon_md5, self_md5)
  left join pg_proc p on p.oid = to_regprocedure(t.sig);

do $pre$
declare
  v_fn    text;
  v_rel   text;
  v_n     int;
  v_first int := 0;
  v_again int := 0;
  r       record;
begin
  -- 본문이 부르는 것(plpgsql 은 만들 때 참조를 확인하지 않는다 — 없으면 첫 보고에서 터진다).
  foreach v_fn in array array[
    'auth.uid()', 'auth.jwt()', 'public.tetris_protocol()', 'public.tetris__ms(timestamptz)',
    'public.tetris__due(uuid,timestamptz)', 'public.tetris__settle(uuid,text,text)', 'public.tetris__ring(uuid,uuid,integer)',
    'public.tetris_attack_cap(bigint)', 'public.tetris_countdown_ms()', 'public.tetris_stakes()',
    'public.tetris_invite_ttl_seconds()', 'public.tetris_capable(uuid)', 'public.tetris_ready_timeout_seconds()',
    'public.tetris_max_duration_seconds()', 'public.match__watchers(text,uuid)', 'public.chess__busy(uuid)',
    'public.same_visibility(uuid,uuid)', 'public.blocked_between(uuid,uuid)', 'public.poke_blackout_active(timestamptz)']
  loop
    if to_regprocedure(v_fn) is null then
      raise exception '§0 % 가 없다 — 이 파일은 테트리스 대결(20261021120000) · 관전자 수(20261023120000) 위에 얹는다. 배포 중단', v_fn;
    end if;
  end loop;
  foreach v_rel in array array['public.tetris_matches', 'public.tetris_players', 'public.profiles']
  loop
    if to_regclass(v_rel) is null then
      raise exception '§0 % 가 없다. 배포 중단', v_rel;
    end if;
  end loop;
  -- 오버로드 1(PGRST203 상태에서 시작하지 않는다 — 이 파일은 서명을 안 바꾸므로 끝에도 1이어야 한다).
  foreach v_fn in array array['tetris__state', 'tetris_challenge', 'tetris_respond', 'tetris_report', 'tetris_resign']
  loop
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_n <> 1 then
      raise exception '§0 % 오버로드가 % 개다(기대 1) — PGRST203. 배포 중단', v_fn, v_n;
    end if;
  end loop;
  -- 첫 적용이면 다섯 다 정본 md5, 재적용이면 다섯 다 이 파일 md5. 그 밖(다른 값 · 섞임)은 누가 손댄 것 — 멈춘다.
  for r in select * from pg_temp.tow_before order by sig collate "C" loop
    if r.md5 is null then
      raise exception '§0 % 가 없다. 배포 중단', r.sig;
    elsif r.md5 = r.canon_md5 then
      v_first := v_first + 1;
    elsif r.md5 = r.self_md5 then
      v_again := v_again + 1;
    else
      raise exception '§0 % 본문 md5 가 정본(%)도 이 파일 결과(%)도 아닌 % 다 — 그 사이 누가 고쳤다. 저장소 최신 정의에서 '
                      '본문을 다시 떠 와라. 배포 중단', r.sig, r.canon_md5, r.self_md5, r.md5;
    end if;
  end loop;
  if not (v_first = 5 or v_again = 5) then
    raise exception '§0 다섯 함수 중 정본이 % 개 · 이 파일 결과가 % 개로 섞여 있다 — 누가 일부만 고쳤다. 배포 중단', v_first, v_again;
  end if;
  raise notice '§0 사전 단언 통과(%)', case when v_first = 5 then '첫 적용' else '재적용' end;
end
$pre$;


-- ── §1 칸 둘 ──────────────────────────────────────────────────────────────────────────────
alter table public.tetris_matches add column if not exists challenger_session uuid null;
alter table public.tetris_matches add column if not exists opponent_session uuid null;
comment on column public.tetris_matches.challenger_session is
  '신청을 낸 기기의 로그인 세션(auth.jwt()->>''session_id''). 이 자리의 보고·기권은 이 세션만 쓴다(20261103124000 — '
  '한 판 한 기기). null = 기록 없음(이 파일 전 판 · 세션 없는 토큰) → 가드를 지나 실제로 쓰는 첫 보고가 잡는다.';
comment on column public.tetris_matches.opponent_session is
  '수락한 기기의 로그인 세션. challenger_session 과 같은 규칙(20261103124000 — 한 판 한 기기).';


-- ── §2 내부 도구 셋(두 밑줄 = 클라 실행권 0) ─────────────────────────────────────────────────

-- 부르는 토큰의 세션 id. 클레임이 없거나 uuid 가 아니면 null(→ 옛 동작). 어떤 오류도 밖으로 내지 않는다.
create or replace function public.tetris__session()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  return nullif(auth.jwt() ->> 'session_id', '')::uuid;
exception when others then
  return null;
end
$fn$;

-- 이 판에서 부르는 사람 자리의 기기 판정. 'this' = 그 자리를 연 세션이다 · 'other' = 다른 세션이다 ·
-- null = 가를 수 없다(저장 세션 없음 · 토큰에 세션 없음 · 부르는 사람이 그 자리 주인이 아님 · 판 없음).
create or replace function public.tetris__device(p_match_id uuid default null, p_uid uuid default null)
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_cur  uuid := public.tetris__session();
  v_have uuid;
begin
  if v_cur is null or p_match_id is null or p_uid is null or p_uid is distinct from auth.uid() then
    return null;
  end if;
  select case when p_uid = g.challenger then g.challenger_session
              when p_uid = g.opponent then g.opponent_session end
    into v_have
    from public.tetris_matches g where g.id = p_match_id;
  if v_have is null then
    return null;
  end if;
  return case when v_have = v_cur then 'this' else 'other' end;
end
$fn$;

-- 기록이 없는 **진행 중** 판의 내 자리를 지금 세션으로 잡는다(true = 이번에 잡았다). 이미 기록이 있거나 세션이 없으면
-- 아무것도 안 한다. 호출자가 매치 행을 for update 로 쥔 뒤에 부른다(같은 판의 두 기기 경합은 그 잠금이 줄 세운다).
create or replace function public.tetris__claim(p_match_id uuid default null, p_uid uuid default null)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_cur  uuid := public.tetris__session();
  v_rows int;
begin
  if v_cur is null or p_match_id is null or p_uid is null or p_uid is distinct from auth.uid() then
    return false;
  end if;
  update public.tetris_matches g
     set challenger_session = case when p_uid = g.challenger then v_cur else g.challenger_session end,
         opponent_session   = case when p_uid = g.opponent then v_cur else g.opponent_session end
   where g.id = p_match_id and g.status = 'active'
     and ((p_uid = g.challenger and g.challenger_session is null)
          or (p_uid = g.opponent and g.opponent_session is null));
  get diagnostics v_rows = row_count;
  return v_rows = 1;
end
$fn$;

comment on function public.tetris__session() is
  '부르는 토큰의 로그인 세션 id(auth.jwt()->>''session_id''). 없거나 uuid 가 아니면 null — 그때 대결은 옛 동작(잠그지 '
  '않는다). 20261103124000 한 판 한 기기. 내부 전용.';
comment on function public.tetris__device(uuid, uuid) is
  '판에서 부르는 사람 자리의 기기 판정: this(그 자리를 연 세션) · other(다른 세션) · null(저장 세션 없음 · 토큰에 세션 '
  '없음 · 부르는 사람이 아님). tetris_report · tetris_resign 의 쓰기 규칙과 상태의 my_device 가 부른다. 내부 전용.';
comment on function public.tetris__claim(uuid, uuid) is
  '기록이 없는 진행 중 판의 내 자리를 지금 세션으로 잡는다(true = 잡았다). 이 파일 전에 수락된 판을 위한 것이다. '
  '호출자가 매치 행을 쥔 뒤에 부른다. 내부 전용.';


-- ── §3 다시 쓴 함수 다섯(정본 + 치환 — 머리말 '뒤 파일이…') ──────────────────────────────────

create or replace function public.tetris__state(p_match_id uuid, p_uid uuid)
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

create or replace function public.tetris_challenge(p_protocol int default 0, p_opponent uuid default null,
                                                   p_stake int default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_now   timestamptz := clock_timestamp();
  uid     uuid := auth.uid();
  v_focus boolean;
  v_bal   int;
  v_id    uuid;
  v_exp   timestamptz;
  v_pair  uuid[];
  v_keys  uuid[];
  v_k     uuid;
  v_stale uuid;
begin
  if uid is null then
    return jsonb_build_object('status', 'not_signed_in');
  end if;
  if coalesce(p_protocol, 0) < public.tetris_protocol() then
    return jsonb_build_object('status', 'unsupported_client', 'server_now_ms', public.tetris__ms(v_now));
  end if;
  -- 없는 상대 · 숨김 다른 쪽 · 차단 · 판돈 밖은 **같은 응답**이다.
  if p_stake is null or not (p_stake = any (public.tetris_stakes()))
     or p_opponent is null or p_opponent = uid
     or not exists (select 1 from public.profiles where id = p_opponent)
     or not exists (select 1 from public.profiles where id = uid)
     or not public.same_visibility(uid, p_opponent)
     or public.blocked_between(uid, p_opponent) then
    return jsonb_build_object('status', 'invalid', 'stakes', to_jsonb(public.tetris_stakes()));
  end if;
  if public.poke_blackout_active() then
    return jsonb_build_object('status', 'blackout');
  end if;
  select p.focus_mode into v_focus from public.profiles p where p.id = p_opponent;
  if v_focus then
    return jsonb_build_object('status', 'target_focused');
  end if;
  if not public.tetris_capable(p_opponent) then
    return jsonb_build_object('status', 'target_outdated');
  end if;

  -- 지갑 키: 나·상대 + 둘이 낀 테트리스 active 판의 두 사람(그 판이 지금 닫혀야 할 수 있다). uuid 순으로 한 번에.
  v_pair := array[uid, p_opponent];
  select array_agg(distinct k.uid order by k.uid) into v_keys
    from (select unnest(v_pair) as uid
          union
          select unnest(array[g.challenger, g.opponent]) from public.tetris_matches g
           where g.status = 'active' and (g.challenger = any (v_pair) or g.opponent = any (v_pair))) k;
  foreach v_k in array v_keys loop
    perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || v_k::text));
  end loop;
  -- 두 참가자 키를 다 쥔 판만 시간 판정을 돌린다(그 사이 새로 생긴 판은 busy 가 되고 다음 호출·cron 이 닫는다).
  for v_stale in
    select g.id from public.tetris_matches g
     where g.status = 'active' and (g.challenger = any (v_pair) or g.opponent = any (v_pair))
       and g.challenger = any (v_keys) and g.opponent = any (v_keys)
     order by g.id
  loop
    perform 1 from public.tetris_matches g where g.id = v_stale for update;
    perform public.tetris__due(v_stale, v_now);
  end loop;

  if public.chess__busy(uid) then
    return jsonb_build_object('status', 'busy');
  end if;
  if public.chess__busy(p_opponent) then
    return jsonb_build_object('status', 'target_busy');
  end if;
  perform 1 from public.tetris_matches g where g.challenger = uid and g.status = 'pending' for update;
  update public.tetris_matches g set status = 'expired'
   where g.challenger = uid and g.status = 'pending' and g.invite_expires_at < v_now;
  select g.id into v_id from public.tetris_matches g where g.challenger = uid and g.status = 'pending';
  if v_id is not null then
    return jsonb_build_object('status', 'already_pending', 'match_id', v_id);
  end if;
  select p.ruby_balance into v_bal from public.profiles p where p.id = uid;
  if coalesce(v_bal, 0) < p_stake then
    return jsonb_build_object('status', 'insufficient', 'need', p_stake, 'have', coalesce(v_bal, 0),
                              'ruby_balance', v_bal);
  end if;

  v_exp := v_now + make_interval(secs => public.tetris_invite_ttl_seconds());
  -- 한 판 한 기기(20261103124000): 신청을 낸 기기의 세션을 적는다 — 이 자리의 보고·기권은 이 세션만 쓴다.
  insert into public.tetris_matches(challenger, opponent, stake, status, invite_expires_at, challenger_session)
  values (uid, p_opponent, p_stake, 'pending', v_exp, public.tetris__session())
  returning id into v_id;
  perform public.tetris__ring(p_opponent, v_id, 0);
  return jsonb_build_object('status', 'ok', 'match_id', v_id, 'expires_at_ms', public.tetris__ms(v_exp),
                            'ruby_balance', v_bal, 'server_now_ms', public.tetris__ms(v_now));
end
$fn$;

create or replace function public.tetris_respond(p_protocol int default 0, p_match_id uuid default null,
                                                 p_accept boolean default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_now   timestamptz := clock_timestamp();
  v_start timestamptz;
  uid     uuid := auth.uid();
  v_a     uuid;
  v_b     uuid;
  m       public.tetris_matches%rowtype;
  v_mine  int;
  v_their int;
  v_after int;
  v_rows  int;
  v_seed  int;
  v_u     uuid;
  v_kst   date := (now() at time zone 'Asia/Seoul')::date;
  v_state jsonb;
  v_pair  uuid[];
  v_keys  uuid[];
  v_k     uuid;
  v_stale uuid;
  v_other record;
begin
  if uid is null then
    return jsonb_build_object('status', 'not_signed_in');
  end if;
  if coalesce(p_protocol, 0) < public.tetris_protocol() then
    return jsonb_build_object('status', 'unsupported_client', 'server_now_ms', public.tetris__ms(v_now));
  end if;
  select g.challenger, g.opponent into v_a, v_b from public.tetris_matches g where g.id = p_match_id;
  if not found or v_b <> uid then
    return jsonb_build_object('status', 'not_found');
  end if;
  if p_accept is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if p_accept and (not public.same_visibility(uid, v_a) or public.blocked_between(uid, v_a)) then
    return jsonb_build_object('status', 'invalid');
  end if;
  v_pair := array[v_a, v_b];
  select array_agg(distinct k.uid order by k.uid) into v_keys
    from (select unnest(v_pair) as uid
          union
          select unnest(array[g.challenger, g.opponent]) from public.tetris_matches g
           where g.status = 'active' and (g.challenger = any (v_pair) or g.opponent = any (v_pair))) k;
  foreach v_k in array v_keys loop
    perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || v_k::text));
  end loop;
  for v_stale in
    select g.id from public.tetris_matches g
     where g.status = 'active' and (g.challenger = any (v_pair) or g.opponent = any (v_pair))
       and g.challenger = any (v_keys) and g.opponent = any (v_keys)
     order by g.id
  loop
    perform 1 from public.tetris_matches g where g.id = v_stale for update;
    perform public.tetris__due(v_stale, v_now);
  end loop;
  select * into m from public.tetris_matches g where g.id = p_match_id for update;
  if not found or m.opponent <> uid then
    return jsonb_build_object('status', 'not_found');
  end if;
  select p.ruby_balance into v_mine from public.profiles p where p.id = uid;
  if m.status <> 'pending' then
    return jsonb_build_object('status', 'not_pending', 'match_status', m.status, 'ruby_balance', v_mine);
  end if;

  if not p_accept then
    update public.tetris_matches g set status = 'declined' where g.id = m.id and g.status = 'pending';
    perform public.tetris__ring(m.challenger, m.id, 0);
    return jsonb_build_object('status', 'ok', 'accepted', false, 'ruby_balance', v_mine,
                              'server_now_ms', public.tetris__ms(v_now));
  end if;

  if v_now > m.invite_expires_at then
    update public.tetris_matches g set status = 'expired' where g.id = m.id and g.status = 'pending';
    perform public.tetris__ring(m.challenger, m.id, 0);
    return jsonb_build_object('status', 'expired', 'ruby_balance', v_mine);
  end if;
  if public.chess__busy(uid) then
    return jsonb_build_object('status', 'busy', 'ruby_balance', v_mine);
  end if;
  if public.chess__busy(m.challenger) then
    return jsonb_build_object('status', 'target_busy', 'ruby_balance', v_mine);
  end if;

  perform 1 from public.profiles p where p.id in (m.challenger, m.opponent) order by p.id for update;
  select p.ruby_balance into v_mine  from public.profiles p where p.id = uid;
  select p.ruby_balance into v_their from public.profiles p where p.id = m.challenger;
  if coalesce(v_mine, 0) < m.stake then
    return jsonb_build_object('status', 'insufficient', 'side', 'me', 'need', m.stake,
                              'have', coalesce(v_mine, 0), 'ruby_balance', v_mine);
  end if;
  if coalesce(v_their, 0) < m.stake then
    -- 남의 잔액은 숫자로 알려 주지 않는다(have null).
    return jsonb_build_object('status', 'insufficient', 'side', 'challenger', 'need', m.stake,
                              'have', null, 'ruby_balance', v_mine);
  end if;

  v_seed  := floor(random() * 2147483648)::int;
  v_start := clock_timestamp();
  update public.tetris_matches g
     set status      = 'active',
         accepted_at = v_start,
         seed        = v_seed,
         start_at    = null,
         -- 한 판 한 기기(20261103124000): 수락한 기기의 세션 — 이 자리의 보고·기권은 이 세션만 쓴다.
         opponent_session = public.tetris__session()
   where g.id = m.id and g.status = 'pending';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'tetris_respond: 수락 전이가 %행이다(기대 1)', v_rows;
  end if;
  foreach v_u in array array[least(m.challenger, m.opponent), greatest(m.challenger, m.opponent)] loop
    update public.profiles set ruby_balance = ruby_balance - m.stake
     where id = v_u returning ruby_balance into v_after;
    if not found then
      raise exception 'tetris_respond: 지갑 행이 없다(%)', v_u;
    end if;
    insert into public.ruby_ledger(user_id, kst_day, reason, delta, balance_after, detail)
    values (v_u, v_kst, 'spend:tetris:stake:' || m.id::text, -m.stake, v_after,
            jsonb_build_object('match_id', m.id, 'stake', m.stake));
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
      raise exception 'tetris_respond: 판돈 원장이 %행이다(기대 1)', v_rows;
    end if;
  end loop;
  insert into public.tetris_players(match_id, user_id)
  values (m.id, m.challenger), (m.id, m.opponent);
  get diagnostics v_rows = row_count;
  if v_rows <> 2 then
    raise exception 'tetris_respond: 사람 행이 %개다(기대 2)', v_rows;
  end if;
  -- 두 사람이 낀 다른 **테트리스** 대기 신청은 전부 닫는다(보낸 것·받은 것). 다른 게임의 신청은 그대로 둔다 —
  -- 나중 수락 때 busy 게이트가 막는다.
  for v_other in
    update public.tetris_matches g set status = 'cancelled'
     where g.status = 'pending' and g.id <> m.id
       and (g.challenger in (m.challenger, m.opponent) or g.opponent in (m.challenger, m.opponent))
    returning g.id, g.challenger, g.opponent
  loop
    if v_other.challenger not in (m.challenger, m.opponent) then
      perform public.tetris__ring(v_other.challenger, v_other.id, 0);
    elsif v_other.opponent not in (m.challenger, m.opponent) then
      perform public.tetris__ring(v_other.opponent, v_other.id, 0);
    end if;
  end loop;
  perform public.tetris__ring(m.challenger, m.id, 0);
  v_state := public.tetris__state(m.id, uid);
  return jsonb_build_object('status', 'ok', 'accepted', true, 'state', v_state);
end
$fn$;

create or replace function public.tetris_report(p_protocol int default 0, p_match_id uuid default null,
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
    return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid));
  end if;
  -- ① 누가 불러도 닫힌다(내 침묵도 여기서 잰다 — 15초 넘게 끊겼다 돌아온 보고는 이미 진 판을 받는다)
  if public.tetris__due(m.id, v_now) then
    select * into m from public.tetris_matches g where g.id = m.id;
  end if;
  if m.status <> 'active' then
    return jsonb_build_object('status', 'stale', 'state', public.tetris__state(m.id, uid));
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
    return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid));
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
    return jsonb_build_object('status', 'stale', 'state', public.tetris__state(m.id, uid));
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
  return jsonb_build_object('status', 'ok', 'state', public.tetris__state(m.id, uid));
end
$fn$;

create or replace function public.tetris_resign(p_protocol int default 0, p_match_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_now timestamptz := clock_timestamp();
  uid   uuid := auth.uid();
  v_a   uuid;
  v_b   uuid;
  m     public.tetris_matches%rowtype;
  v_dev text;
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
  perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || least(v_a, v_b)::text));
  perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || greatest(v_a, v_b)::text));
  select * into m from public.tetris_matches g where g.id = p_match_id for update;
  if not found or uid not in (m.challenger, m.opponent) then
    return jsonb_build_object('status', 'not_found');
  end if;
  -- 한 판 한 기기(20261103124000): 이 자리를 연 기기가 아니면 기권도 받지 않는다(쓰기 없음 · 정산 없음).
  v_dev := public.tetris__device(m.id, uid);
  if v_dev = 'other' then
    return jsonb_build_object('status', 'other_device', 'state', public.tetris__state(m.id, uid));
  end if;
  if public.tetris__due(m.id, v_now) then
    select * into m from public.tetris_matches g where g.id = m.id;
  end if;
  if m.status <> 'active' then
    return jsonb_build_object('status', 'not_active', 'state', public.tetris__state(m.id, uid));
  end if;
  if v_dev is null then
    perform public.tetris__claim(m.id, uid);
  end if;
  perform public.tetris__settle(m.id, case when uid = m.challenger then 'opponent_win' else 'challenger_win' end, 'resign');
  return jsonb_build_object('status', 'ok', 'state', public.tetris__state(m.id, uid));
end
$fn$;

comment on function public.tetris__state(uuid, uuid) is
  '부르는 사람 시점의 대결 상태: {match_id, status, stake, seed, server_now_ms, accepted_at_ms, start_at_ms|null, '
  'ready_deadline_ms, max_end_ms|null, finished_at_ms|null, me{id, display_name, avatar_url, character, ready, seq, '
  'board|null, lines, garbage_sent, garbage_applied, pending, last_seen_ms|null, topped_out}, opponent{같은 모양}, '
  'result|null, winner|null, end_reason|null, watchers, my_device(this|other|null — 20261103124000), ruby_balance}. '
  '응답 조립 전용(권한 검사는 호출자). 내부 전용.';
comment on function public.tetris_challenge(integer, uuid, integer) is
  '테트리스 신청(루비는 안 움직인다). not_signed_in · unsupported_client · invalid{stakes}(없는 상대·숨김 다른 쪽·'
  '차단·판돈 밖) · blackout · target_focused · target_outdated · busy · target_busy(오목·체스·테트리스 active 를 '
  '함께 본다) · already_pending{match_id} · insufficient{need, have, ruby_balance} · '
  'ok{match_id, expires_at_ms, ruby_balance, server_now_ms}. 신청한 기기의 세션을 challenger_session 에 적는다.';
comment on function public.tetris_respond(integer, uuid, boolean) is
  '테트리스 신청 응답. 수락 순간 양쪽에서 stake 차감(spend:tetris:stake:<id>) · seed 추첨 · 사람 행 2개 · 두 사람의 '
  '다른 테트리스 대기 신청을 닫는다 · 수락한 기기의 세션을 opponent_session 에 적는다. not_signed_in · '
  'unsupported_client · not_found · invalid · not_pending{match_status} · ok{accepted:false} · expired · busy · '
  'target_busy · insufficient{side(me|challenger), need, have} · ok{accepted:true, state}.';
comment on function public.tetris_report(integer, uuid, integer, text, integer, integer, integer, integer, boolean) is
  '테트리스 판 보고(1초 하트비트 겸). ok{state} · stale{state}(seq 가 저장값 이하이거나 판이 active 가 아니다 — 쓰지 않았다) · '
  'other_device{state}(그 자리를 연 기기 세션이 아니거나 누계가 뒤로 갔다 — 쓰지도 정산하지도 않았다, 20261103124000) · '
  'not_found · invalid(seq<1 · board 200글자 .IJLOSTZG 아님 · 음수) · not_signed_in · unsupported_client. '
  '첫 보고 = 준비, 둘째 준비면 start_at = 그 시각 + 3초. garbage_sent 는 단조·상한(8 + 3×경과초)으로 자른다. '
  'p_topped_out=true 면 상대 승 topout 정산. null 칸은 그대로 둔다.';
comment on function public.tetris_resign(integer, uuid) is
  '테트리스 기권(상대 승 · resign). 카운트다운 중에도 된다. 시간 판정이 먼저라 이미 끝났어야 할 판은 그 사유로 닫히고 '
  'not_active{state} 가 온다. ok{state} · not_active{state} · other_device{state}(그 자리를 연 기기 세션이 아니다 — '
  '정산하지 않았다, 20261103124000) · not_found · not_signed_in · unsupported_client.';


-- ── §4 실행권 ── 다시 쓴 다섯은 create or replace 라 ACL 이 그대로다(같은 grant 를 다시 준다 — §5 (3) 이 직전과 대조).
revoke all on function public.tetris__session()            from public, anon, authenticated;
revoke all on function public.tetris__device(uuid, uuid)   from public, anon, authenticated;
revoke all on function public.tetris__claim(uuid, uuid)    from public, anon, authenticated;
grant execute on function public.tetris__session()          to service_role;
grant execute on function public.tetris__device(uuid, uuid) to service_role;
grant execute on function public.tetris__claim(uuid, uuid)  to service_role;

grant execute on function public.tetris__state(uuid, uuid)                       to service_role;
grant execute on function public.tetris_challenge(integer, uuid, integer)       to authenticated, service_role;
grant execute on function public.tetris_respond(integer, uuid, boolean)         to authenticated, service_role;
grant execute on function public.tetris_report(integer, uuid, integer, text, integer, integer, integer, integer, boolean)
                                                                                to authenticated, service_role;
grant execute on function public.tetris_resign(integer, uuid)                   to authenticated, service_role;


-- ── §5 사후 단언 ───────────────────────────────────────────────────────────────────────────
do $assert$
declare
  r        record;
  v_oid    oid;
  v_src    text;
  v_n      int;
  v_dev    int;
  v_tok    text;
  v_w      text;
  v_pos    int;
  v_probes int := 0;
begin
  -- (1) 칸 둘: uuid · null 허용 · 기본값 없음
  for r in select c.column_name, c.data_type, c.is_nullable, c.column_default
             from information_schema.columns c
            where c.table_schema = 'public' and c.table_name = 'tetris_matches'
              and c.column_name in ('challenger_session', 'opponent_session') loop
    if r.data_type <> 'uuid' or r.is_nullable <> 'YES' or r.column_default is not null then
      raise exception '(1) tetris_matches.% 가 uuid · null 허용 · 기본값 없음이 아니다(% · % · %). 배포 중단',
        r.column_name, r.data_type, r.is_nullable, r.column_default;
    end if;
    v_n := coalesce(v_n, 0) + 1;
  end loop;
  if coalesce(v_n, 0) <> 2 then
    raise exception '(1) 세션 칸이 % 개다(기대 2). 배포 중단', coalesce(v_n, 0);
  end if;
  v_probes := v_probes + 1;

  -- (2) 도구 셋: definer · search_path=public · 인자 전부 DEFAULT · 클라 실행권 0 · service_role 은 된다
  for r in select * from (values ('public.tetris__session()'), ('public.tetris__device(uuid,uuid)'),
                                 ('public.tetris__claim(uuid,uuid)')) t(sig) loop
    v_oid := to_regprocedure(r.sig);
    if v_oid is null then
      raise exception '(2) % 가 없다. 배포 중단', r.sig;
    end if;
    if not (select p.prosecdef and p.proconfig::text = '{search_path=public}' and p.pronargdefaults = p.pronargs
              from pg_proc p where p.oid = v_oid) then
      raise exception '(2) % 가 definer · search_path=public · 인자 전부 DEFAULT 가 아니다. 배포 중단', r.sig;
    end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') or has_function_privilege('anon', v_oid, 'EXECUTE')
       or has_function_privilege('authenticated', v_oid, 'EXECUTE') then
      raise exception '(2) % 를 클라가 부를 수 있다 — 남의 판 자리를 잡는 문이 열린다. 배포 중단', r.sig;
    end if;
    if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
      raise exception '(2) service_role 이 % 를 못 부른다. 배포 중단', r.sig;
    end if;
  end loop;
  v_probes := v_probes + 1;

  -- (3) 다섯: 오버로드 1 · 본문 = 이 파일 결과(재적용 핀) · oid · 실행권 · 속성이 직전과 같다
  for r in select * from pg_temp.tow_before order by sig collate "C" loop
    v_oid := to_regprocedure(r.sig);
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = (select p2.proname from pg_proc p2 where p2.oid = v_oid);
    if v_n <> 1 then
      raise exception '(3) % 오버로드가 % 개다 — PGRST203. 배포 중단', r.sig, v_n;
    end if;
    if (select md5(p.prosrc) from pg_proc p where p.oid = v_oid) is distinct from r.self_md5 then
      raise exception '(3) % 의 본문 md5 가 이 파일 결과(%)가 아니다 — §0 핀과 §3 본문이 어긋났다. 배포 중단', r.sig, r.self_md5;
    end if;
    if pg_temp.tow_attrs(v_oid) is distinct from r.attrs then
      raise exception '(3) % 의 oid · 실행권 · 속성이 바뀌었다(전 % · 후 %) — 이 파일은 본문만 바꾼다. 배포 중단',
        r.sig, r.attrs, pg_temp.tow_attrs(v_oid);
    end if;
  end loop;
  v_probes := v_probes + 1;

  -- (4) 순서 계약: 보고 · 기권의 기기 검사가 시간 판정 · 사람 행 쓰기 · 정산보다 앞, 단조 가드는 준비 쓰기보다 앞, 잡기는 가드 뒤
  --     (보고의 잡기는 seq 가 앞선 보고에만)
  foreach v_tok in array array['public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)',
                               'public.tetris_resign(integer,uuid)'] loop
    select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure(v_tok);
    v_dev := strpos(v_src, 'v_dev := public.tetris__device(m.id, uid);');
    if v_dev = 0 or strpos(v_src, 'if v_dev = ''other'' then') < v_dev then
      raise exception '(4) % 에 기기 검사가 없다. 배포 중단', v_tok;
    end if;
    foreach v_w in array array['public.tetris__due(', 'update public.tetris_players', 'public.tetris__settle(',
                               'public.tetris__claim('] loop
      v_pos := strpos(v_src, v_w);
      if v_pos > 0 and v_pos < v_dev then
        raise exception '(4) % 에서 "%" 가 기기 검사보다 앞이다 — 다른 기기가 쓰거나 정산한다. 배포 중단', v_tok, v_w;
      end if;
    end loop;
  end loop;
  select p.prosrc into v_src from pg_proc p
   where p.oid = to_regprocedure('public.tetris_report(integer,uuid,integer,text,integer,integer,integer,integer,boolean)');
  v_pos := strpos(v_src, 'if p_seq > me.seq');
  if v_pos = 0 or strpos(v_src, 'coalesce(p_lines, me.lines) < me.lines') < v_pos
     or strpos(v_src, 'coalesce(p_garbage_sent, me.garbage_sent) < me.garbage_sent') < v_pos then
    raise exception '(4) tetris_report 에 단조 가드(seq 비교 · 줄 · 공격)가 없다. 배포 중단';
  end if;
  if strpos(v_src, 'update public.tetris_players pl set ready_at') < v_pos
     or strpos(v_src, 'perform public.tetris__claim(m.id, uid);') < v_pos then
    raise exception '(4) tetris_report 의 준비 쓰기 · 자리 잡기가 단조 가드보다 앞이다. 배포 중단';
  end if;
  if strpos(v_src, 'if v_dev is null and p_seq > me.seq then') = 0 then
    raise exception '(4) tetris_report 의 자리 잡기가 seq 비교 없이 걸려 있다 — 다른 기기의 늦은(stale) 보고가 자리를 가로챈다. 배포 중단';
  end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.tetris__state(uuid,uuid)');
  if strpos(v_src, '''my_device'', public.tetris__device(p_match_id, p_uid)') = 0 then
    raise exception '(4) tetris__state 에 my_device 가 없다. 배포 중단';
  end if;
  v_probes := v_probes + 1;

  raise notice '§5 사후 단언 전부 통과(검사 %건)', v_probes;
end
$assert$;


-- ── §6 흐름 프로브(실호출 — 센티널 예외로 통째 롤백) ────────────────────────────────────────
-- 사용자 흉내 도구(임시 스키마). 세션 id 를 클레임에 싣는다(null 이면 싣지 않는다 — 세션 없는 토큰).
create or replace function pg_temp.tow_as(p_uid uuid, p_session uuid)
returns void language plpgsql as $tmp$
begin
  perform set_config('request.jwt.claims',
                     (jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aud', 'authenticated')
                      || case when p_session is null then '{}'::jsonb
                              else jsonb_build_object('session_id', p_session) end)::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
end $tmp$;

-- 그 사람(그 세션)으로 RPC 한 번 → 원래 역할로 복귀.
create or replace function pg_temp.tow_rpc(p_uid uuid, p_session uuid, p_sql text)
returns jsonb language plpgsql as $tmp$
declare v_back text := current_user; v jsonb;
begin
  perform pg_temp.tow_as(p_uid, p_session);
  execute p_sql into v;
  execute format('set local role %I', v_back);
  return v;
end $tmp$;

-- 그 사람으로 문장 하나 → SQLSTATE(성공이면 'ok'). 원래 역할로 복귀.
create or replace function pg_temp.tow_err(p_uid uuid, p_session uuid, p_sql text)
returns text language plpgsql as $tmp$
declare v_back text := current_user; v_state text := 'ok';
begin
  begin
    perform pg_temp.tow_as(p_uid, p_session);
    execute p_sql;
  exception when others then
    v_state := sqlstate;
  end;
  execute format('set local role %I', v_back);
  return v_state;
end $tmp$;

-- 보고 한 번(빈 판 200글자 · 받은 공격 0 · 대기 0).
create or replace function pg_temp.tow_report(p_uid uuid, p_session uuid, p_match uuid, p_seq int, p_lines int,
                                              p_sent int, p_topped boolean default false)
returns jsonb language plpgsql as $tmp$
begin
  return pg_temp.tow_rpc(p_uid, p_session, format(
    'select public.tetris_report(p_protocol => %s, p_match_id => %L::uuid, p_seq => %s, p_board => %L, p_lines => %s, '
    'p_garbage_sent => %s, p_garbage_applied => 0, p_pending => 0, p_topped_out => %L::boolean)',
    public.tetris_protocol(), p_match, p_seq, repeat('.', 200), p_lines, p_sent, p_topped));
end $tmp$;

-- ★ 이 블록 안 주석에 달러 태그 글자를 적지 마라. 뽑은 값 비교는 is distinct from. 기대 숫자는 전후 델타.
do $probe$
declare
  v_exec_role text := current_user;
  v_expected  constant int := 12;
  probes      int := 0;
  v_synth     boolean := false;
  P           constant int := public.tetris_protocol();
  a uuid; b uuid;
  sa1 uuid := gen_random_uuid(); sa2 uuid := gen_random_uuid();
  sb1 uuid := gen_random_uuid(); sb2 uuid := gen_random_uuid();
  mid  uuid;
  mid2 uuid;
  v    jsonb;
  pl   public.tetris_players%rowtype;
  m    public.tetris_matches%rowtype;
  v_blk text;
begin
  begin
    --------------------------------------------------------------------------------------------
    -- 픽스처: a(신청자) · b(받는 사람). 합성 계정이 가능하면 합성, 아니면 대국 중이 아닌 일반 프로필을 빌린다
    -- (빌린 값은 센티널 롤백으로 전부 되돌아간다). 기기 넷 = 세션 넷(sa1 · sa2 · sb1 · sb2).
    --------------------------------------------------------------------------------------------
    if has_table_privilege('auth.users', 'INSERT') then
      v_synth := true;
      a := gen_random_uuid(); b := gen_random_uuid();
      insert into auth.users (id, email, raw_user_meta_data)
        select u.id, 'tetris-one-writer-probe-' || u.tag || '-' || u.id || '@example.invalid',
               jsonb_build_object('display_name', 'TOW-' || u.tag || '-' || left(u.id::text, 8))
          from unnest(array[a, b], array['a', 'b']) as u(id, tag);
      insert into public.profiles (id, email, display_name)
        select u.id, 'tetris-one-writer-probe-' || u.tag || '-' || u.id || '@example.invalid',
               'TOW-' || u.tag || '-' || left(u.id::text, 8)
          from unnest(array[a, b], array['a', 'b']) as u(id, tag)
      on conflict (id) do nothing;
    else
      select s.ids[1], s.ids[2] into a, b
        from (select array_agg(q.id order by q.created_at, q.id) as ids
                from (select p.id, p.created_at from public.profiles p
                       where not public.is_hidden_user(p.id) and not public.chess__busy(p.id)
                       order by p.created_at, p.id limit 2) q) s;
      if a is null or b is null then
        raise exception '§6 픽스처를 만들 수도 빌릴 수도 없다 — 프로브가 no-op 인 채로 배포되면 안 된다, 배포 중단';
      end if;
    end if;
    update public.profiles set app_build = public.tetris_min_build(), ruby_balance = 100, focus_mode = false,
                               is_hidden = false
     where id in (a, b);
    delete from public.user_blocks where blocker in (a, b) or blocked in (a, b);
    update public.tetris_matches set status = 'cancelled'
     where status = 'pending' and (challenger in (a, b) or opponent in (a, b));
    if public.chess__busy(a) or public.chess__busy(b) then
      raise exception '§6 픽스처 사용자가 이미 대국 중이다';
    end if;
    -- 조용한 기간이면 신청이 blackout 으로 막힌다 — 이 블록 안에서만 끈다(센티널 롤백이 되돌리고, 끝에서도 원문으로 되돌린다).
    if public.poke_blackout_active() then
      select pg_get_functiondef('public.poke_blackout_active(timestamp with time zone)'::regprocedure) into v_blk;
      execute 'create or replace function public.poke_blackout_active(p_at timestamptz default now()) '
              'returns boolean language sql stable as ''select false''';
    end if;

    --------------------------------------------------------------------------------------------
    -- ① a(기기 sa1)가 신청 → challenger_session = sa1 · 상대 자리는 비어 있다 · 신청자의 상태는 기기마다 this/other
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_rpc(a, sa1, format('select public.tetris_challenge(%s, %L::uuid, 3)', P, b));
    if v ->> 'status' is distinct from 'ok' then
      raise exception '① a→b 신청이 %', v;
    end if;
    mid := (v ->> 'match_id')::uuid;
    select * into m from public.tetris_matches where id = mid;
    if m.challenger_session is distinct from sa1 or m.opponent_session is not null then
      raise exception '① 신청이 세션을 안 적었다(challenger % · opponent %)', m.challenger_session, m.opponent_session;
    end if;
    v := pg_temp.tow_rpc(a, sa1, format('select public.tetris_state(%s, %L::uuid)', P, mid));
    if v -> 'state' ->> 'my_device' is distinct from 'this' then
      raise exception '① 신청한 기기의 상태가 my_device=% 다(기대 this)', v -> 'state' -> 'my_device';
    end if;
    v := pg_temp.tow_rpc(a, sa2, format('select public.tetris_state(%s, %L::uuid)', P, mid));
    if v -> 'state' ->> 'my_device' is distinct from 'other' then
      raise exception '① 신청자의 다른 기기 상태가 my_device=% 다(기대 other)', v -> 'state' -> 'my_device';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ② b(기기 sb1)가 수락 → opponent_session = sb1 · 응답 상태 my_device = this
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_rpc(b, sb1, format('select public.tetris_respond(%s, %L::uuid, true)', P, mid));
    if v ->> 'status' is distinct from 'ok' or v -> 'state' ->> 'my_device' is distinct from 'this' then
      raise exception '② 수락이 % (기대 ok · my_device this)', v;
    end if;
    select * into m from public.tetris_matches where id = mid;
    if m.status <> 'active' or m.opponent_session is distinct from sb1 or m.challenger_session is distinct from sa1 then
      raise exception '② 수락 뒤 판이 % · challenger % · opponent %', m.status, m.challenger_session, m.opponent_session;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ③ my_device 갈래: 다른 기기 other · 세션 없는 토큰 null(키는 있다) · JWT 없는 내부 호출 null
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_rpc(b, sb2, format('select public.tetris_state(%s, %L::uuid)', P, mid));
    if v -> 'state' ->> 'my_device' is distinct from 'other' then
      raise exception '③ 받는 사람의 다른 기기 상태가 my_device=% 다(기대 other)', v -> 'state' -> 'my_device';
    end if;
    v := pg_temp.tow_rpc(b, null, format('select public.tetris_state(%s, %L::uuid)', P, mid));
    if not (v -> 'state' ? 'my_device') or v -> 'state' -> 'my_device' <> 'null'::jsonb then
      raise exception '③ 세션 없는 토큰의 my_device 가 % 다(기대 키 있음 · null)', v -> 'state' -> 'my_device';
    end if;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    if public.tetris__state(mid, b) -> 'my_device' <> 'null'::jsonb then
      raise exception '③ 부르는 사람이 없는 내부 조립의 my_device 가 null 이 아니다';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ④ b 의 다른 기기(sb2)가 첫 보고(=준비)를 낸다 → other_device{state} · 사람 행에 아무것도 안 적힌다
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_report(b, sb2, mid, 1, 0, 0);
    if v ->> 'status' is distinct from 'other_device'
       or (select array_agg(k order by k collate "C") from jsonb_object_keys(v) k) is distinct from array['state', 'status']
       or v -> 'state' ->> 'match_id' is distinct from mid::text or v -> 'state' ->> 'my_device' is distinct from 'other' then
      raise exception '④ 다른 기기의 준비 보고가 % (기대 {status:other_device, state(my_device other)})', v;
    end if;
    select * into pl from public.tetris_players where match_id = mid and user_id = b;
    if pl.ready_at is not null or pl.seq <> 0 or pl.last_seen_at is not null or pl.board is not null then
      raise exception '④ 다른 기기의 보고가 사람 행에 적혔다(ready % · seq % · last_seen %)', pl.ready_at, pl.seq, pl.last_seen_at;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑤ 진짜 기기 둘의 준비 → 시작 시각 · 그 사이 신청자의 다른 기기(sa2) 준비는 막힌다
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_report(b, sb1, mid, 1, 0, 0);
    if v ->> 'status' is distinct from 'ok' then
      raise exception '⑤ b(sb1) 준비가 %', v;
    end if;
    v := pg_temp.tow_report(a, sa2, mid, 1, 0, 0);
    if v ->> 'status' is distinct from 'other_device' then
      raise exception '⑤ a 의 다른 기기 준비가 % (기대 other_device)', v;
    end if;
    if (select ready_at from public.tetris_players where match_id = mid and user_id = a) is not null
       or (select start_at from public.tetris_matches where id = mid) is not null then
      raise exception '⑤ 다른 기기의 준비가 준비·시작 시각을 세웠다';
    end if;
    v := pg_temp.tow_report(a, sa1, mid, 1, 0, 0);
    if v ->> 'status' is distinct from 'ok' or (select start_at from public.tetris_matches where id = mid) is null then
      raise exception '⑤ 두 사람이 준비했는데 시작 시각이 없다: %', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑥ 2026-10-30 재현: 진짜 기기(sb1)가 3줄을 지운 뒤 다른 기기(sb2)가 더 큰 seq 로 빈 판 · 0줄 · 탑아웃을 낸다
    --    → other_device · 판은 active · 사람 행은 진짜 기기 값 그대로 · 탑아웃 시각 없음
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_report(b, sb1, mid, 2, 3, 2);
    if v ->> 'status' is distinct from 'ok' then
      raise exception '⑥ b(sb1) 보고가 %', v;
    end if;
    v := pg_temp.tow_report(b, sb2, mid, 99, 0, 0, true);
    if v ->> 'status' is distinct from 'other_device' then
      raise exception '⑥ 다른 기기의 탑아웃이 % (기대 other_device)', v;
    end if;
    select * into m from public.tetris_matches where id = mid;
    select * into pl from public.tetris_players where match_id = mid and user_id = b;
    if m.status <> 'active' or m.result is not null or pl.topped_out_at is not null
       or pl.seq <> 2 or pl.lines <> 3 or pl.garbage_sent <> 2 then
      raise exception '⑥ 다른 기기의 탑아웃이 판을 건드렸다(판 % · 결과 % · seq % · lines % · sent % · topped %)',
        m.status, m.result, pl.seq, pl.lines, pl.garbage_sent, pl.topped_out_at;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑦ 단조 가드(같은 세션이어도): 줄이 뒤로 → other_device · 공격이 뒤로 → other_device · 둘 다 앞으로 → ok
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_report(b, sb1, mid, 3, 1, 2);
    if v ->> 'status' is distinct from 'other_device' then
      raise exception '⑦ 지운 줄이 3 → 1 로 줄었는데 %', v;
    end if;
    v := pg_temp.tow_report(b, sb1, mid, 3, 3, 1);
    if v ->> 'status' is distinct from 'other_device' then
      raise exception '⑦ 공격 누계가 2 → 1 로 줄었는데 %', v;
    end if;
    select * into pl from public.tetris_players where match_id = mid and user_id = b;
    if pl.seq <> 2 or pl.lines <> 3 or pl.garbage_sent <> 2 then
      raise exception '⑦ 막힌 보고가 행을 바꿨다(seq % · lines % · sent %)', pl.seq, pl.lines, pl.garbage_sent;
    end if;
    v := pg_temp.tow_report(b, sb1, mid, 3, 4, 2);
    if v ->> 'status' is distinct from 'ok' or (select lines from public.tetris_players where match_id = mid and user_id = b) <> 4 then
      raise exception '⑦ 앞으로 간 보고가 %', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑧ 늦게 온 옛 보고(seq 이하 · 줄 적음)는 가드가 아니라 stale 이다 — 같은 기기의 순서 뒤집힘을 다른 기기로 몰지 않는다
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_report(b, sb1, mid, 2, 0, 0);
    if v ->> 'status' is distinct from 'stale' then
      raise exception '⑧ 늦게 온 옛 보고가 % (기대 stale)', v ->> 'status';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑨ 세션 없는 토큰은 옛 동작(잠그지 않는다) · 저장 세션은 그대로
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_report(b, null, mid, 4, 4, 2);
    if v ->> 'status' is distinct from 'ok'
       or (select seq from public.tetris_players where match_id = mid and user_id = b) <> 4
       or (select opponent_session from public.tetris_matches where id = mid) is distinct from sb1 then
      raise exception '⑨ 세션 없는 보고가 % (기대 ok · seq 4 · 저장 세션 sb1 그대로)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑩ 기권: 다른 기기(sb2)는 other_device · 판 active · 진짜 기기(sb1)는 ok · 신청자 승 resign
    --------------------------------------------------------------------------------------------
    v := pg_temp.tow_rpc(b, sb2, format('select public.tetris_resign(%s, %L::uuid)', P, mid));
    if v ->> 'status' is distinct from 'other_device' or (select status from public.tetris_matches where id = mid) <> 'active' then
      raise exception '⑩ 다른 기기의 기권이 % (기대 other_device · 판 active)', v;
    end if;
    v := pg_temp.tow_rpc(b, sb1, format('select public.tetris_resign(%s, %L::uuid)', P, mid));
    select * into m from public.tetris_matches where id = mid;
    if v ->> 'status' is distinct from 'ok' or m.status <> 'finished' or m.result <> 'challenger_win'
       or m.end_reason <> 'resign' then
      raise exception '⑩ 진짜 기기의 기권이 % (판 % · 결과 % · 사유 %)', v ->> 'status', m.status, m.result, m.end_reason;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑪ 기록 없는 판(이 파일 전에 수락된 판): 늦게 온 보고 · 가드에 걸린 보고는 자리를 못 잡고, 지난 보고가 잡는다
    --    → 그 뒤 다른 기기는 막힌다
    --------------------------------------------------------------------------------------------
    mid2 := gen_random_uuid();
    insert into public.tetris_matches (id, challenger, opponent, stake, status, seed, created_at, invite_expires_at,
                                       accepted_at, start_at)
    values (mid2, a, b, 3, 'active', 4242, clock_timestamp() - interval '20 seconds',
            clock_timestamp() + interval '40 seconds', clock_timestamp() - interval '10 seconds',
            clock_timestamp() - interval '5 seconds');
    insert into public.tetris_players (match_id, user_id, ready_at, seq, lines, last_seen_at)
    values (mid2, a, clock_timestamp() - interval '10 seconds', 4, 3, clock_timestamp()),
           (mid2, b, clock_timestamp() - interval '10 seconds', 4, 0, clock_timestamp());
    -- 다른 기기(sa2)의 늦은 보고: seq 가 저장값과 같고 줄이 뒤로 — 가드는 seq 비교로 넘기고 ④ 가 stale 로 받는다.
    -- 이 보고가 자리를 잡으면 진짜 기기(sa1)의 다음 보고가 other_device 로 막혀 침묵 패가 된다(리뷰 지적 그대로).
    v := pg_temp.tow_report(a, sa2, mid2, 4, 0, 0, true);
    if v ->> 'status' is distinct from 'stale'
       or (select challenger_session from public.tetris_matches where id = mid2) is not null
       or (select lines from public.tetris_players where match_id = mid2 and user_id = a) is distinct from 3
       or (select status from public.tetris_matches where id = mid2) <> 'active' then
      raise exception '⑪ 늦게 온 다른 기기 보고가 % (기대 stale · 자리 안 잡음 · 줄 3 그대로 · 판 active)', v;
    end if;
    v := pg_temp.tow_report(a, sa2, mid2, 5, 0, 0, true);
    if v ->> 'status' is distinct from 'other_device'
       or (select challenger_session from public.tetris_matches where id = mid2) is not null
       or (select status from public.tetris_matches where id = mid2) <> 'active' then
      raise exception '⑪ 줄이 뒤로 간 보고가 % (기대 other_device · 자리 안 잡음 · 판 active)', v;
    end if;
    v := pg_temp.tow_report(a, sa1, mid2, 5, 3, 0);
    if v ->> 'status' is distinct from 'ok' or v -> 'state' ->> 'my_device' is distinct from 'this'
       or (select challenger_session from public.tetris_matches where id = mid2) is distinct from sa1 then
      raise exception '⑪ 가드를 지난 보고가 자리를 못 잡았다: %', v;
    end if;
    v := pg_temp.tow_report(a, sa2, mid2, 6, 9, 0);
    if v ->> 'status' is distinct from 'other_device'
       or (select seq from public.tetris_players where match_id = mid2 and user_id = a) <> 5 then
      raise exception '⑪ 자리를 잡은 뒤 다른 기기 보고가 % (기대 other_device · seq 5 그대로)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑫ 도구 셋은 클라가 직접 못 부른다(남의 판 자리를 잡거나 판정을 엿보는 문 — 42501)
    --------------------------------------------------------------------------------------------
    if pg_temp.tow_err(a, sa1, 'select public.tetris__session()') <> '42501'
       or pg_temp.tow_err(a, sa1, format('select public.tetris__device(%L::uuid, %L::uuid)', mid2, a)) <> '42501'
       or pg_temp.tow_err(a, sa1, format('select public.tetris__claim(%L::uuid, %L::uuid)', mid2, a)) <> '42501' then
      raise exception '⑫ 클라가 도구를 부를 수 있다';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    if v_blk is not null then
      execute v_blk;
    end if;
    if probes <> v_expected then
      raise exception '§6 프로브 %건만 돌았다(기대 %건) — 검사가 조용히 빠졌다', probes, v_expected;
    end if;
    raise notice '§6 흐름 프로브 %건 통과(합성 계정 % · 롤백)', probes, v_synth;
    raise exception 'TETRIS_ONE_WRITER_PROBE_ROLLBACK';
  exception
    when others then
      execute format('set local role %I', v_exec_role);
      if sqlerrm = 'TETRIS_ONE_WRITER_PROBE_ROLLBACK' then
        raise notice '§6 롤백 완료 — 대결 표·장부·초인종에 흔적이 남지 않았다';
      else
        raise;
      end if;
  end;
end $probe$;

drop function if exists pg_temp.tow_report(uuid, uuid, uuid, integer, integer, integer, boolean);
drop function if exists pg_temp.tow_rpc(uuid, uuid, text);
drop function if exists pg_temp.tow_err(uuid, uuid, text);
drop function if exists pg_temp.tow_as(uuid, uuid);

notify pgrst, 'reload schema';
