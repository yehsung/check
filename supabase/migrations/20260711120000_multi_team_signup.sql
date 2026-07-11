-- 멀티팀 가입: 트리거에서 'sudo 박수' 자동 가입 제거 + 가입 화면용 팀 목록 RPC.
-- 멱등성: create or replace / on conflict / if not exists 로 재실행 안전.
-- 기존 계정의 memberships/work_statuses 는 절대 건드리지 않는다(기존 sudo 박수 행/시드도 삭제하지 않음).

-- 1) 트리거 재작성.
--    - 항상 프로필은 생성/갱신한다.
--    - raw_user_meta_data->>'team_id' 가 있고 public.teams 에 실재하면 그 팀으로만 membership/work_status 를 만든다.
--    - team_id 가 없거나(무소속 가입) 실재하지 않으면 팀 관련 행은 만들지 않는다(프로필만).
--    - 하드코딩 팀/시드 insert 는 제거한다.
create or replace function public.handle_check_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_team_id uuid;
  resolved_team_id uuid;
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

  -- 메타데이터의 team_id 를 안전하게 uuid 로 해석한다(형식 오류/빈 문자열은 무소속 처리).
  begin
    requested_team_id := nullif(new.raw_user_meta_data ->> 'team_id', '')::uuid;
  exception when others then
    requested_team_id := null;
  end;

  if requested_team_id is not null then
    select id into resolved_team_id
    from public.teams
    where id = requested_team_id;
  end if;

  if resolved_team_id is not null then
    insert into public.memberships (team_id, user_id, role)
    values (resolved_team_id, new.id, 'member')
    on conflict (team_id, user_id) do nothing;

    insert into public.work_statuses (team_id, user_id, status, active_session_id)
    values (resolved_team_id, new.id, 'off_work', null)
    on conflict (team_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

-- 트리거 바인딩은 기존과 동일(create or replace function 이므로 재바인딩 불필요)하나 멱등하게 보장한다.
drop trigger if exists on_check_auth_user_created on auth.users;
create trigger on_check_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_check_auth_user();

-- 2) 가입 화면 팀 목록 RPC. anon/authenticated 모두 호출 가능.
--    invite_code 는 절대 반환하지 않는다(id, name 만 노출).
create or replace function public.team_directory()
returns table(id uuid, name text)
language sql
stable
security definer
set search_path = public
as $$
  select id, name from public.teams order by name
$$;

revoke all on function public.team_directory() from public;
grant execute on function public.team_directory() to anon, authenticated;

-- 3) 내 팀 조회(fetchOwnMembership: memberships?select=team_id,teams(name)&user_id=eq.{uid})는
--    기존 RLS 로 충분하다:
--      - "members can read memberships" 로 본인 소속 membership 행을 읽을 수 있고,
--      - "members can read their teams" 로 그 팀 행(name)을 임베드 조인으로 읽을 수 있다.
--    따라서 추가 정책은 필요하지 않다.
