-- 팀원 목표 수정 + 참여코드 전 팀원 공개.
-- (B2) my_team_invite_code(): owner 제한을 없애 소속 팀원이면 누구나 참여코드를 조회한다 — 코드가 곧 열쇠이므로
--      팀원도 새 동료를 초대할 수 있어야 한다.
-- (B3) set_team_weekly_goal(): 팀원(역할 무관)이 주간 목표시간을 바꾼다.
-- 멱등성: create or replace / revoke·grant 재실행 안전. 기존 마이그레이션 스타일(joined_at 순 limit 1,
--   security definer, set search_path=public, 1~168 검증, revoke all→grant authenticated)을 그대로 따른다.

-- 1) 내 팀 참여코드(소속 팀원 전체 공개).
--    기존엔 role='owner' 제한이 있었으나, 팀원 누구나 코드를 공유해 새 동료를 초대할 수 있게 role 조건을 없앤다.
--    본인이 속한 팀(joined_at 순 첫 팀)의 invite_code 를 반환한다. 무소속이면 0행.
create or replace function public.my_team_invite_code()
returns table(invite_code text)
language sql
stable
security definer
set search_path = public
as $$
  select t.invite_code
  from public.teams t
  join public.memberships m on m.team_id = t.id
  where m.user_id = auth.uid()
  order by m.joined_at
  limit 1;
$$;

revoke all on function public.my_team_invite_code() from public;
grant execute on function public.my_team_invite_code() to authenticated;

-- 2) 팀 주간 목표시간 수정(팀원 누구나).
--    로그인 필수(auth.uid()). 호출자가 속한 팀(joined_at 순 첫 팀)의 weekly_goal_hours 를 바꾼다.
--    목표는 1~168 범위 검증(위반 시 예외 — teams 의 check 제약과 동일 범위라 제약 위반 이전에 막는다).
--    변경 후 서버에 반영된 값을 반환한다. 역할(owner/member) 제한은 없다.
create or replace function public.set_team_weekly_goal(goal_hours integer)
returns table(weekly_goal_hours integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  goal integer := goal_hours;
  target_team uuid;
begin
  if uid is null then
    raise exception 'authentication required';
  end if;
  if goal is null or goal < 1 or goal > 168 then
    raise exception 'goal hours out of range';
  end if;

  select m.team_id into target_team
  from public.memberships m
  where m.user_id = uid
  order by m.joined_at
  limit 1;
  if not found then
    raise exception 'no team membership';
  end if;

  update public.teams t
  set weekly_goal_hours = goal
  where t.id = target_team;

  return query
    select t.weekly_goal_hours
    from public.teams t
    where t.id = target_team;
end;
$$;

revoke all on function public.set_team_weekly_goal(integer) from public;
grant execute on function public.set_team_weekly_goal(integer) to authenticated;
