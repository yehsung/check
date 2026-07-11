-- 팀 리그: 팀별 이번 주 총 근무시간 경쟁용 RPC.
-- 로그인한 팀원 전용(anon 금지). 모든 팀의 총합/목표/근무중 인원을 돌려주되 invite_code 는 비노출한다.
-- 멱등성: create or replace + revoke/grant 로 재실행 안전.
--
-- 주 창 = Asia/Seoul 월요일 00:00 ~ now(). date_trunc('week', ...) 는 ISO 월요일 기준이라
-- 앱의 koreanWeekStart(firstWeekday=2, Asia/Seoul)와 동일 의미다.
--
-- 세션 기여(초) = 앱의 clippedContribution 과 동일 식:
--   contribution = greatest(0, extract(epoch from (effective_end - max(started_at, week_start))))
--   - 완료 세션 effective_end = least(ended_at, now())
--   - 열린 세션 effective_end = least(coalesce(last_seen_at, now()), now())
--     (하트비트 상한 — 마지막 생존신호로 클램프해 죽은 세션이 총합을 부풀리지 않게 한다. 앱 로직과 동일.)
--   신호가 없는 열린 세션은 now() 까지 인정한다(앱의 "신호 미상이면 살아있다고 본다"와 동일).
create or replace function public.team_weekly_leaderboard()
returns table(
  team_id uuid,
  team_name text,
  weekly_goal_hours integer,
  total_seconds bigint,
  working_count integer
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
    select team_id, sum(contribution_seconds)::bigint as total_seconds
    from clipped
    group by team_id
  ),
  working_counts as (
    select team_id, count(*)::integer as working_count
    from public.work_statuses
    where status = 'working'
    group by team_id
  )
  select
    t.id,
    t.name,
    t.weekly_goal_hours,
    coalesce(sess.total_seconds, 0)::bigint,
    coalesce(wc.working_count, 0)
  from public.teams t
  left join session_totals sess on sess.team_id = t.id
  left join working_counts wc on wc.team_id = t.id
  order by coalesce(sess.total_seconds, 0) desc, t.name;
$$;

-- 로그인한 팀원 전용. anon 은 호출 불가(리그는 로그인 사용자만).
revoke all on function public.team_weekly_leaderboard() from public;
grant execute on function public.team_weekly_leaderboard() to authenticated;
