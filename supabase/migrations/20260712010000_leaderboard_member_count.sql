-- 팀 리그에 팀별 인원수(member_count)를 더한다. 앱은 이 값으로 "팀원 각자 평균 근무시간"
-- (총합 ÷ 인원)을 계산해 1인당 주간 목표와 비교한다. weekly_goal_hours 는 팀 총합 목표가 아니라
-- "각자 이번 주 X시간 이상 하자"는 1인당 약속이므로, 게이지/정렬의 기준을 총합이 아닌 평균으로 옮긴다.
--
-- 20260711140000_team_leaderboard.sql 의 함수를 create or replace 로 확장한다. 클리핑(KST 주 창 +
-- 하트비트 상한)·정렬·grant(authenticated 전용)는 그대로 두고, 반환 컬럼에 member_count 만 추가한다.
-- member_count = 그 팀의 memberships 행 수(소속 인원). 세션이 없는 팀도 0 이 아니라 실제 인원을 돌려준다.
-- 멱등성: create or replace + revoke/grant 로 재실행 안전. 모든 컬럼은 별칭으로 한정한다.
--
-- 주 창 = Asia/Seoul 월요일 00:00 ~ now(). 세션 기여(초) 식은 앱의 clippedContribution 과 동일하다:
--   contribution = greatest(0, extract(epoch from (effective_end - max(started_at, week_start))))
--   - 완료 세션 effective_end = least(ended_at, now())
--   - 열린 세션 effective_end = least(coalesce(last_seen_at, now()), now())  (하트비트 상한)
-- 반환 컬럼 추가는 create or replace 로 불가(42P13) — 기존 함수를 먼저 제거한다.
drop function if exists public.team_weekly_leaderboard();

create or replace function public.team_weekly_leaderboard()
returns table(
  team_id uuid,
  team_name text,
  weekly_goal_hours integer,
  total_seconds bigint,
  working_count integer,
  member_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (
    select
      (date_trunc('week', (now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul') as week_start,
      now() as now_ts
  ),
  clipped as (
    select
      s.team_id,
      greatest(
        0,
        extract(epoch from (
          least(
            case
              when s.ended_at is not null then s.ended_at
              else coalesce(st.last_seen_at, b.now_ts)
            end,
            b.now_ts
          )
          - greatest(s.started_at, b.week_start)
        ))
      ) as contribution_seconds
    from public.work_sessions s
    cross join bounds b
    left join public.work_statuses st
      on st.team_id = s.team_id and st.user_id = s.user_id
  ),
  session_totals as (
    select clipped.team_id, sum(clipped.contribution_seconds)::bigint as total_seconds
    from clipped
    group by clipped.team_id
  ),
  working_counts as (
    select ws.team_id, count(*)::integer as working_count
    from public.work_statuses ws
    where ws.status = 'working'
    group by ws.team_id
  ),
  member_counts as (
    select m.team_id, count(*)::integer as member_count
    from public.memberships m
    group by m.team_id
  )
  select
    t.id,
    t.name,
    t.weekly_goal_hours,
    coalesce(sess.total_seconds, 0)::bigint,
    coalesce(wc.working_count, 0),
    coalesce(mc.member_count, 0)
  from public.teams t
  left join session_totals sess on sess.team_id = t.id
  left join working_counts wc on wc.team_id = t.id
  left join member_counts mc on mc.team_id = t.id
  order by coalesce(sess.total_seconds, 0) desc, t.name;
$$;

-- 로그인한 팀원 전용. anon 은 호출 불가(리그는 로그인 사용자만).
revoke all on function public.team_weekly_leaderboard() from public;
grant execute on function public.team_weekly_leaderboard() to authenticated;
