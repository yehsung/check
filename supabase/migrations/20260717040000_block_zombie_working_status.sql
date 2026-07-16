-- 좀비 '근무중' 상태 차단: 열린 세션이 없는 유저는 work_statuses 가 'working' 이 될 수 없다.
--
-- 배경(실제 발생한 버그): 자동마감(close_abandoned_work_sessions)이 10분 무신호 세션을 닫은 뒤,
-- 그 사람의 맥이 다시 깨어나면 앱은 자신이 근무중인 줄 알고 하트비트(upsert status='working')를
-- 계속 보낸다. 세션은 닫혀 있는데 상태만 '근무중'으로 부활하고, last_seen 이 계속 갱신되므로
-- 자동마감에 다시는 걸리지 않는다 — 팀원들에게 "근무중인데 현재 00:00 동결"로 보이는 영구 좀비.
--
-- 해결: before insert/update 트리거로 'working' 기록 시 열린 세션 실존을 강제한다.
-- 열린 세션이 없으면 status 를 'off_work' 로 강등하고 active_session_id 를 비운다
-- (last_seen_at/updated_at 갱신은 그대로 두어 생존신호 기록은 보존).
--
-- 정상 흐름은 전부 통과한다: startWork/reopenSession 은 세션을 먼저 열고 상태를 upsert 하므로
-- (세션 insert → status upsert 순서) 트리거 시점에 열린 세션이 항상 존재한다.
-- 근무종료(off_work upsert)는 검사 대상이 아니다.
create or replace function public.enforce_open_session_for_working()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'working' and not exists (
    select 1
    from public.work_sessions s
    where s.team_id = new.team_id
      and s.user_id = new.user_id
      and s.ended_at is null
  ) then
    new.status := 'off_work';
    new.active_session_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists work_statuses_require_open_session on public.work_statuses;
create trigger work_statuses_require_open_session
  before insert or update on public.work_statuses
  for each row execute function public.enforce_open_session_for_working();

-- 이미 존재하는 좀비 행 즉시 정리(멱등): 열린 세션 없는 'working' 상태를 강등한다.
update public.work_statuses st
set status = 'off_work', active_session_id = null, updated_at = now()
where st.status = 'working'
  and not exists (
    select 1 from public.work_sessions s
    where s.team_id = st.team_id and s.user_id = st.user_id and s.ended_at is null
  );
