-- 초대코드 RPC 모호성 수정.
-- plpgsql 에서 RETURNS TABLE 의 출력 컬럼명(team_id 등)은 함수 스코프 변수가 되는데,
-- ON CONFLICT (team_id, user_id) 의 충돌 대상이 표현식으로 파싱되며 "변수 vs 컬럼" 모호성
-- 에러(42702, column reference "team_id" is ambiguous)가 난다 — 라이브 E2E 에서 발견.
-- 수정: #variable_conflict use_column 프라그마로 모호한 이름을 컬럼 우선으로 해석.
-- (본문에서 변수 읽기는 전부 uid/normalized/target.*/created.* 로 명시적이라 부작용 없음)

create or replace function public.join_team(code text)
returns table(team_id uuid, name text, weekly_goal_hours integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  normalized text;
  target public.teams;
begin
  if uid is null then
    return;
  end if;
  normalized := upper(regexp_replace(coalesce(code, ''), '[[:space:]-]', '', 'g'));
  if normalized = '' then
    return;
  end if;

  select * into target
  from public.teams t
  where upper(regexp_replace(coalesce(t.invite_code, ''), '[[:space:]-]', '', 'g')) = normalized
  limit 1;
  if not found then
    return;
  end if;

  insert into public.memberships (team_id, user_id, role)
  values (target.id, uid, 'member')
  on conflict (team_id, user_id) do nothing;

  insert into public.work_statuses (team_id, user_id, status, active_session_id)
  values (target.id, uid, 'off_work', null)
  on conflict (team_id, user_id) do nothing;

  return query
    select target.id, target.name, target.weekly_goal_hours;
end;
$$;

revoke all on function public.join_team(text) from public;
grant execute on function public.join_team(text) to authenticated;

create or replace function public.create_team(team_name text, goal_hours integer)
returns table(team_id uuid, name text, invite_code text, weekly_goal_hours integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  trimmed text := btrim(coalesce(team_name, ''));
  goal integer := coalesce(goal_hours, 60);
  created public.teams;
begin
  if uid is null then
    raise exception 'authentication required';
  end if;
  if trimmed = '' then
    raise exception 'team name required';
  end if;
  if goal < 1 or goal > 168 then
    raise exception 'goal hours out of range';
  end if;

  insert into public.teams (name, invite_code, weekly_goal_hours)
  values (trimmed, public.generate_invite_code(), goal)
  returning * into created;

  insert into public.memberships (team_id, user_id, role)
  values (created.id, uid, 'owner')
  on conflict (team_id, user_id) do nothing;

  insert into public.work_statuses (team_id, user_id, status, active_session_id)
  values (created.id, uid, 'off_work', null)
  on conflict (team_id, user_id) do nothing;

  return query
    select created.id, created.name, created.invite_code, created.weekly_goal_hours;
end;
$$;

revoke all on function public.create_team(text, integer) from public;
grant execute on function public.create_team(text, integer) to authenticated;

-- 같은 패턴 예방 차원(현재는 정상 동작): lookup_team_by_code 에도 동일 프라그마 적용.
create or replace function public.lookup_team_by_code(code text)
returns table(team_id uuid, name text, weekly_goal_hours integer, member_count integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  normalized text;
begin
  perform pg_sleep(0.3);
  normalized := upper(regexp_replace(coalesce(code, ''), '[[:space:]-]', '', 'g'));
  if normalized = '' then
    return;
  end if;
  return query
    select
      t.id,
      t.name,
      t.weekly_goal_hours,
      (select count(*)::integer from public.memberships m where m.team_id = t.id)
    from public.teams t
    where upper(regexp_replace(coalesce(t.invite_code, ''), '[[:space:]-]', '', 'g')) = normalized
    limit 1;
end;
$$;

revoke all on function public.lookup_team_by_code(text) from public;
grant execute on function public.lookup_team_by_code(text) to anon, authenticated;
