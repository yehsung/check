-- 목적: anon 키만으로 로그인 없이 실행돼 사용자 데이터를 반환/변경하던 RPC 들의 실행권을 anon·PUBLIC 에서 회수한다.
--
-- 실증(2026-08-09): 공개 brew cask 에 박힌 anon 키로 `POST /rest/v1/rpc/token_usage_board` 를 로그인 없이
--   호출하니 전 사용자의 display_name·avatar_url·codex 토큰이 그대로 반환됐다(HTTP 200, 인증 0).
--   벡터는 두 겹이다: (1) Postgres 의 `create function` 은 EXECUTE 를 PUBLIC 에 자동 부여하고, anon 은 PUBLIC
--   멤버다. (2) Supabase 는 `alter default privileges ... grant execute on functions to anon` 를 기본으로 걸어
--   함수마다 anon 직접 grant 까지 붙인다. 그래서 `revoke ... from anon` 만으로는 PUBLIC 경로가 남아 못 막는다.
--
-- 안전성(v0.2.15 임베드 사고의 교훈 — 서버 변경은 전 클라 버전에 즉시 영향):
--   · 아래 13개 함수는 앱이 **전부 accessToken(=authenticated 역할)으로만** 호출한다(SupabaseWorkService).
--     유일한 anon 호출은 lookup_team_by_code(가입 전 팀코드 미리보기)뿐이라 그 함수는 건드리지 않는다.
--   · authenticated grant 를 유지하므로 로그인 사용자·구버전(v0.2.10~v0.2.16) 전원 무영향(요청 바이트 불변).
--   · RLS 헬퍼(is_team_member 등)는 **의도적으로 손대지 않는다** — 이 함수들은 RLS 정책 안에서 호출 역할로
--     실행되므로 anon 에서 회수하면 anon 이 닿는 표의 RLS 가 통째로 깨진다. anon 이 직접 불러도 auth.uid()=null
--     이라 boolean/0행만 돌려주니 데이터 유출이 아니다(로컬 Postgres 로 실증: 회수 후에도 anon/authenticated
--     둘 다 is_team_member 정책 표 SELECT 정상).
--
-- 롤백: 이 파일을 되돌리려면 각 함수에 `grant execute ... to anon` 을 다시 주면 된다(단 그건 유출 복원이다).

do $$
declare
  -- anon·PUBLIC 에서 실행권을 회수할 앱 RPC(데이터 반환/변경). 시그니처는 각 함수의 최종 정의 기준.
  fns text[] := array[
    'public.token_usage_board(text)',
    'public.team_weekly_leaderboard()',
    'public.app_user_directory()',
    'public.close_abandoned_work_sessions()',
    'public.cleanup_old_pokes()',
    'public.take_pokes()',
    'public.poke_user(uuid)',
    'public.ultra_poke_user(uuid)',
    'public.join_team(text)',
    'public.create_team(text, integer)',
    'public.my_team_invite_code()',
    'public.set_team_weekly_goal(integer)',
    'public.set_display_name(text)'
  ];
  f text;
begin
  foreach f in array fns loop
    execute format('revoke execute on function %s from anon, public', f);
    -- authenticated 는 지금 수준 유지(앱이 이 함수들을 로그인 토큰으로 호출한다).
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- 정리 함수는 service_role/cron 전용 — authenticated 에서도 회수한다(사용자가 남의 오래된 찔림을 지울 이유가 없다).
  revoke execute on function public.cleanup_old_pokes() from authenticated;
end $$;

-- 사후 단언: 소유자 불일치 시 revoke 는 WARNING 만 남기고 통과하므로(20260804020000 의 경고와 같은 함정)
-- 실제로 걸렸는지 반드시 확인한다. 하나라도 어긋나면 배포를 중단시킨다.
do $$
declare
  fns text[] := array[
    'public.token_usage_board(text)',
    'public.team_weekly_leaderboard()',
    'public.app_user_directory()',
    'public.close_abandoned_work_sessions()',
    'public.cleanup_old_pokes()',
    'public.take_pokes()',
    'public.poke_user(uuid)',
    'public.ultra_poke_user(uuid)',
    'public.join_team(text)',
    'public.create_team(text, integer)',
    'public.my_team_invite_code()',
    'public.set_team_weekly_goal(integer)',
    'public.set_display_name(text)'
  ];
  f text;
begin
  foreach f in array fns loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'anon 이 여전히 % 를 실행할 수 있습니다 — RPC 유출 미차단, 배포 중단', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') and f <> 'public.cleanup_old_pokes()' then
      raise exception 'authenticated 의 % 실행권이 사라졌습니다 — 로그인 사용자 破損, 배포 중단', f;
    end if;
  end loop;
  -- 가입 전 팀코드 미리보기는 반대로 anon 이 반드시 실행 가능해야 한다.
  if not has_function_privilege('anon', 'public.lookup_team_by_code(text)', 'execute') then
    raise exception 'lookup_team_by_code 의 anon 실행권이 사라졌습니다 — 가입 미리보기 破損, 배포 중단';
  end if;
end $$;
