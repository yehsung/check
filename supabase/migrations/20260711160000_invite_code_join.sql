-- 초대코드 기반 팀 참여/생성.
-- 코드가 곧 열쇠다: 팀 목록 공개(team_directory)를 폐기하고, 코드 미리보기 → 가입/합류 흐름으로 바꾼다.
-- 멱등성: create or replace / drop function if exists / on conflict 로 재실행 안전.
-- 하위호환: 기존 실팀(sudo 박수=SUDOPARK, 낭만러너 김유정=RUNNER01)과 그 코드는 8자 규칙과 형식이
--   달라도 정규화(대문자·공백/하이픈 제거) 일치 기준으로 그대로 조회·합류된다.

-- 1) 참여코드 생성기(내부 전용).
--    문자셋에서 헷갈리는 문자(I, L, O, 0, 1)를 제외한 8자 난수. teams.invite_code 유니크 충돌 시 재생성해
--    기존 팀과 절대 불충돌한다. security definer 로 만들어 create_team(정의자 권한) 내부에서만 쓴다(grant 없음).
create or replace function public.generate_invite_code()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  candidate text;
  i integer;
begin
  loop
    candidate := '';
    for i in 1..8 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from public.teams where invite_code = candidate);
  end loop;
  return candidate;
end;
$$;

revoke all on function public.generate_invite_code() from public;

-- 2) 코드 미리보기(가입 전에도 호출).
--    입력을 정규화(대문자, 공백/하이픈 제거)해 teams.invite_code 도 같은 정규화 기준으로 비교한다.
--    못 찾으면 0행. 무차별 대입 완화를 위해 pg_sleep(0.3) 을 상시 건다(그래서 volatile).
--    가입 전 미리보기가 필요하므로 anon, authenticated 모두 실행 가능.
create or replace function public.lookup_team_by_code(code text)
returns table(team_id uuid, name text, weekly_goal_hours integer, member_count integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
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

-- 3) 코드로 팀 합류.
--    로그인 필수(auth.uid()). 정규화 조회로 팀을 찾으면 membership('member')+work_statuses 를 upsert 하고
--    (이미 멤버면 no-op) 팀 정보를 반환한다. 로그인 안 됨/코드 불일치는 예외 대신 0행으로 알린다.
create or replace function public.join_team(code text)
returns table(team_id uuid, name text, weekly_goal_hours integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
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

-- 4) 새 팀 만들기.
--    로그인 필수. 이름 trim 비어있지 않음 + goal 1~168 검증 후 generate_invite_code() 로 팀을 만들고
--    생성자를 owner 로 등록한다(work_statuses 도 함께). 참여코드를 포함해 팀 정보를 반환한다.
create or replace function public.create_team(team_name text, goal_hours integer)
returns table(team_id uuid, name text, invite_code text, weekly_goal_hours integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
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

-- 5) 내 팀 참여코드(owner 전용).
--    본인이 owner 인 팀의 invite_code 를 반환한다. owner 가 아니면 0행.
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
    and m.role = 'owner'
  order by m.joined_at
  limit 1;
$$;

revoke all on function public.my_team_invite_code() from public;
grant execute on function public.my_team_invite_code() to authenticated;

-- 6) 팀 목록 공개 RPC 폐기. 코드가 곧 열쇠이므로 팀 목록은 더 이상 노출하지 않는다.
drop function if exists public.team_directory();

-- 7) 가입 트리거 단순화: 프로필 upsert 만 한다.
--    팀 합류/생성은 이제 앱이 명시적으로 join_team/create_team 을 호출해 처리하므로, 트리거에서 팀 메타데이터
--    로직(membership/work_status 생성)은 제거한다. 하드코딩 팀 insert 도 없다.
create or replace function public.handle_check_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, '팀원'), '@', 1))
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = excluded.display_name;
  return new;
end;
$$;

drop trigger if exists on_check_auth_user_created on auth.users;
create trigger on_check_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_check_auth_user();

-- 8) 리그 가드: 호출자가 어떤 팀의 멤버도 아니면 0행을 반환한다(무소속 계정은 리그를 보지 못한다).
--    본문은 기존과 동일한 clippedContribution 식이고, 최종 select 에 멤버십 존재 가드만 더한다.
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
  where exists (
    select 1 from public.memberships m where m.user_id = auth.uid()
  )
  order by coalesce(sess.total_seconds, 0) desc, t.name;
$$;

revoke all on function public.team_weekly_leaderboard() from public;
grant execute on function public.team_weekly_leaderboard() to authenticated;
