-- 테트리스 판 표시 프레임 되돌리기(명세 §17). 20261108133700_tetris_frames.sql 의 짝. 마이그레이션 폴더에 두지 마라.
-- 번호는 자리표시다(11-03 에 20261107120000 → 20261108120000 → 20261108133700 으로 옮겼다 — 둘 다 다른 파일과 겹쳤다).
-- 푸시 직전 그 파일의 번호를 다시 정하면 이 줄도 같이 고친다.
--
-- 순서가 곧 안전이다: ① 스위치 끔 → ② 정책 먼저 삭제 → ③ 인가 함수 나중.
--   ② 전에 ③ 을 하면 찌르기 조인의 정책 평가가 없는 함수를 만나 전원의 초인종이 깨진다. 서버도 의존성으로 거절한다.
--   그러니 CASCADE 를 절대 붙이지 마라. 지금 어떤 정책이 그 함수를 물고 있는지를 지우는 말이 된다.
--
-- 단계마다 따로 커밋한다. ② 가 실패해도 ① 은 남아야 하기 때문이다. psql 은 -v ON_ERROR_STOP=1 로 돌려라.
--   · 기능만 멈추면 되면 ① 만 실행한다. 다음 응답부터 state.frames 가 null, 체크포인트 3초 안에 전 클라가 1초 보고로 돌아가고 소켓을 닫는다.
--     구버전 영향 0, 앱 업데이트 불필요. 새 조인·토큰 갱신도 거절된다.
--   · 조인 오류(명세 P3b 실패)면 ① · ② · ③ 을 곧바로 다 돌린다.
--   · 이미 쓰기가 캐시된 소켓은 그 소켓이 닫힐 때까지 보낼 수 있다(토큰 갱신 전까지 캐시). 그래서 ② 를 ① 없이 쓰지 마라.
--
-- 남기는 것: tetris_players.frames_v(무해. drop 은 구버전이 안 쓰는 것을 확인한 뒤로), tetris_frames_enabled()(tetris__state 가 부른다),
--            tetris_report · tetris__state 의 새 본문(스위치가 꺼지면 frames 는 언제나 null 이고 나머지는 옛 본문과 같다).
-- 다시 켤 때: 번호를 새로 받은 파일로 스위치 true, 함수, 정책을 다시 만든다. 지금 파일의 §0 가드는 새 본문을 통과시키므로 내용을 그대로 다시 쓸 수 있다.
-- ★ ① 을 운영에 손으로 돌렸으면 같은 내용(스위치 false)을 **번호 붙은 마이그레이션으로도** 남겨라. 안 남기면 운영(false)과 체인 재생
--    (true)이 갈라져, 다음에 이 함수에 기대는 마이그레이션 · 재생 하네스가 운영과 다른 전제로 돈다(11-03 검토 7).
--
-- ★ 확인하지 못한 것: 운영에서 DROP POLICY 가 되는지. 운영 supautils.policy_grants 가 CREATE POLICY 를 열어 주는 것은 명세가 확인했지만
--    DROP 은 첫 실행으로만 안다. 막히면 ① 은 이미 커밋돼 있으니 기능은 멈춘 상태다. 대시보드 SQL 에디터에서 ② 를 돌려라.

-- ── ① 스위치 끔 ──────────────────────────────────────────────────────────────────────────────
begin;
create or replace function public.tetris_frames_enabled()
returns boolean language sql immutable as $fn$ select false $fn$;
commit;

-- ── ② 정책 삭제(realtime.messages 에 가장 강한 잠금 — 3초 안에 못 잡으면 실패, 다시 시도) ──────────────
begin;
set local lock_timeout = '3s';
drop policy if exists "tetris frames write" on realtime.messages;
drop policy if exists "tetris frames read" on realtime.messages;
do $check$
declare v_names text[];
begin
  select array_agg(policyname::text order by policyname collate "C") into v_names
    from pg_policies where schemaname = 'realtime' and tablename = 'messages';
  if v_names is distinct from array['users listen to their own poke channel'] then
    raise exception '되돌린 뒤 realtime.messages 정책이 %다(기대: 찌르기 구독 정책 하나)', v_names;
  end if;
end
$check$;
commit;

-- ── ③ 인가 함수 삭제(정책이 아직 물고 있으면 서버가 거절한다) ──────────────────────────────────
begin;
drop function if exists public.tetris_frame_allowed(boolean);
do $check$
begin
  if to_regprocedure('public.tetris_frame_allowed(boolean)') is not null then
    raise exception 'tetris_frame_allowed 가 남았다';
  end if;
  if public.tetris_frames_enabled() is distinct from false then
    raise exception '스위치가 꺼져 있지 않다';
  end if;
  if public.tetris_protocol() is distinct from 1 then
    raise exception 'tetris_protocol() 이 %다', public.tetris_protocol();
  end if;
end
$check$;
commit;
