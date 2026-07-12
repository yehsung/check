-- 방치 세션 서버 자동 마감: 근무종료를 안 누르고 컴퓨터를 꺼버려 하트비트가 10분 넘게 끊긴 세션을,
-- 마지막 생존신호 시각 기준으로 서버가 자동 근무종료 처리한다. 서버 cron(주 경로) + 클라 스캐빈저(폴백)
-- 이중 안전망으로 돌린다. 멱등 — 대상이 없으면 0을 돌려주며 반복 호출해도 무해하다.
--
-- 임계 10분 근거: 잠자기 5분 유예 + 하트비트 30초 주기 → 정상 복귀 시 최대 신호 공백 ~6분 < 10분.
-- 따라서 10분 넘게 끊긴 세션은 정상 근무가 아니라 방치로 본다.
--
-- 마감 규약(앱의 자리비움 자동마감·clippedContribution 과 동일 의미):
--   - ended_at = 마지막 신호 시각 coalesce(last_seen_at, updated_at) — 무신호 구간은 근무로 인정하지 않는다.
--   - duration_seconds = greatest(0, extract(epoch from (마지막신호 - started_at)))::int (음수는 0 클램프).
-- 대상: work_statuses 에서 status='working' 이고 마지막 신호가 now() - 10분 보다 이전인 행.
-- 반환: 마감한(열린→닫힌) 세션 수. status 만 있고 열린 세션이 없던 행도 off_work 로 정리한다.
-- 멱등성: create or replace + revoke/grant 로 재실행 안전.
create or replace function public.close_abandoned_work_sessions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  closed_count integer;
begin
  -- stale·세션 마감·상태 정리를 한 문장의 데이터변경 CTE 로 묶어 같은 스냅샷 위에서 원자적으로 처리한다.
  -- (closed_statuses 는 최종 select 가 참조하지 않아도 데이터변경 CTE 라 항상 끝까지 실행된다.)
  with stale as (
    select
      st.team_id,
      st.user_id,
      coalesce(st.last_seen_at, st.updated_at) as last_signal
    from public.work_statuses st
    where st.status = 'working'
      and coalesce(st.last_seen_at, st.updated_at) < now() - interval '10 minutes'
  ),
  closed_sessions as (
    update public.work_sessions s
    set ended_at = stale.last_signal,
        duration_seconds = greatest(0, extract(epoch from (stale.last_signal - s.started_at)))::int
    from stale
    where s.team_id = stale.team_id
      and s.user_id = stale.user_id
      and s.ended_at is null
    returning s.id
  ),
  closed_statuses as (
    update public.work_statuses st
    set status = 'off_work',
        active_session_id = null,
        updated_at = now()
    from stale
    where st.team_id = stale.team_id
      and st.user_id = stale.user_id
    returning st.user_id
  )
  select count(*)::int into closed_count from closed_sessions;

  return coalesce(closed_count, 0);
end;
$$;

-- 클라 스캐빈저 폴백을 위해 authenticated 도 호출 가능하게 둔다. 이미 10분 무신호인 세션만 건드리므로
-- (security definer 로 전역 정리) 남용 여지가 없다. cron/정리용 service_role 도 함께 허용한다.
revoke all on function public.close_abandoned_work_sessions() from public;
grant execute on function public.close_abandoned_work_sessions() to authenticated, service_role;

-- pg_cron 5분 주기 스케줄. 이게 주 경로다(클라 스캐빈저는 "누군가 보고 있는 동안 더 빨리" 보정하는 폴백).
-- pg_cron 을 못 쓰는 환경이어도 함수는 남고 클라 폴백이 동작하도록, extension/schedule 실패가
-- 마이그레이션 전체를 죽이지 않게 do 블록으로 감싼다. cron.schedule 은 같은 잡 이름 재호출 시 교체하므로 멱등하다.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule(
    'close-abandoned-work',
    '*/5 * * * *',
    $cron$select public.close_abandoned_work_sessions();$cron$
  );
exception when others then
  raise notice 'pg_cron 스케줄 등록 건너뜀(환경 미지원 가능): %', sqlerrm;
end
$$;
