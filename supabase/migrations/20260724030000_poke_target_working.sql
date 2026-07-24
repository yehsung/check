-- 콕찌르기 대상 게이트: 자리비움(비근무) 대상은 찌를 수 없다.
-- 기존(20260724020000_pokes)엔 "보낸이만 근무중이면 됨"이었으나, 이제 대상도 근무중(열린 세션)이어야 찌를 수 있다.
-- poke_user(p_to) 를 create or replace 로 재정의하되 로직/문구는 그대로 두고 대상 근무중 체크 하나만 추가한다.
-- 추가 위치가 중요하다: 보낸이 근무중 체크 다음, 쿨타임 체크보다 먼저. 순서 이유 —
--  (1) 찌를 수 없는(자리비움) 대상에게 "쿨타임 N초 후 다시" 를 안내하는 모순을 막는다.
--  (2) e2e 결정성: 쿨타임이 남아 있어도 대상 체크가 먼저라 target_not_working 이 확정적으로 나온다.
-- 반환 jsonb 에 status 'target_not_working' 이 추가된다:
--   {"status":"ok"} | {"status":"invalid"} | {"status":"not_working"} | {"status":"target_not_working"} | {"status":"cooldown","retry_after_seconds":N}
create or replace function public.poke_user(p_to uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  last_created timestamptz;
  elapsed numeric;
  retry_after int;
begin
  -- 비로그인/자기 자신/존재하지 않는 대상은 무효.
  if uid is null or p_to = uid or not exists (select 1 from public.profiles where id = p_to) then
    return jsonb_build_object('status', 'invalid');
  end if;

  -- 보낸이가 근무중(열린 세션)이 아니면 거부한다(클라도 선게이트하지만 서버가 최종 강제).
  if not exists (
    select 1 from public.work_sessions where user_id = uid and ended_at is null
  ) then
    return jsonb_build_object('status', 'not_working');
  end if;

  -- 대상이 근무중(열린 세션)이 아니면 거부한다(자리비움엔 찌를 수 없다). 쿨타임 체크보다 먼저 둔다:
  -- 찌를 수 없는 대상에게 "쿨타임 N초" 를 안내하는 모순을 막고, 쿨타임이 남아도 target 체크가 먼저라 결정적이다.
  if not exists (
    select 1 from public.work_sessions where user_id = p_to and ended_at is null
  ) then
    return jsonb_build_object('status', 'target_not_working');
  end if;

  -- 같은 (uid→p_to) 최근 찔림이 60초 이내면 쿨타임. 남은 초는 ceil(60 - 경과), 최소 1.
  select max(created_at) into last_created
  from public.pokes
  where from_user = uid and to_user = p_to;
  if last_created is not null then
    elapsed := extract(epoch from (now() - last_created));
    if elapsed < 60 then
      retry_after := greatest(1, ceil(60 - elapsed)::int);
      return jsonb_build_object('status', 'cooldown', 'retry_after_seconds', retry_after);
    end if;
  end if;

  insert into public.pokes (from_user, to_user) values (uid, p_to);
  return jsonb_build_object('status', 'ok');
end;
$$;

revoke all on function public.poke_user(uuid) from public;
grant execute on function public.poke_user(uuid) to authenticated;
