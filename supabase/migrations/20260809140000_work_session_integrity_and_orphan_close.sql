-- v0.2.18 서버 무결성 3종. 전부 서버 전용 변경이라 전 클라 버전에 즉시 적용된다(정상 경로 무영향 확인 필수).
--
-- S1) work_sessions UPDATE 위조 차단(P0). 기존 정책은 with check 가 user_id 만 봐서, PATCH 로 자기 세션의
--     team_id 를 남의 팀으로 옮겨 그 팀 리그를 오염시키거나, 자기 팀 안에서 started_at/duration 을 위조할 수 있었다.
--     정책에 is_team_member 를 더하고, BEFORE UPDATE 트리거로 started_at·team_id·user_id 를 OLD 로 고정한다
--     (마감은 ended_at·duration_seconds 만 갱신하므로 정상 경로 무영향: stopWork·reopenSession·스캐빈저 모두 통과).
--
-- S2) 주인 잃은 열린 세션 회수(P0) + 방금 시작한 세션 오마감 방지(P1). 기존 마감은 work_statuses.status='working'
--     에만 매달려, (열린 세션 O, status=off_work) 상태가 생기면 어느 경로로도 못 닫아 다음 [근무 시작]이
--     23505 로 영구 거절됐다. status 를 경유하지 않고 work_sessions 를 직접 보는 orphan CTE(30분)를 더한다.
--     또 started_at 이 마지막 신호보다 나중인 세션(= 방금 시작)은 마감 대상에서 빼고, ended_at 을
--     greatest(신호, 시작)으로 눌러 음수/0초 마감을 막는다.
--
-- S4) work_statuses UPDATE 위조 차단(P2). with check 에 is_team_member 를 더해 자기 상태 행을 남의 팀
--     명부로 옮기지 못하게 한다(S1 과 같은 비대칭이었다). 정상 경로는 team_id 를 안 바꾸므로 무영향.

-- ── S1: work_sessions 위조 차단 ──────────────────────────────────────────────
drop policy if exists "members can close their sessions" on public.work_sessions;
create policy "members can close their sessions"
  on public.work_sessions for update
  using (user_id = auth.uid() and public.is_team_member(work_sessions.team_id))
  with check (user_id = auth.uid() and public.is_team_member(work_sessions.team_id));

create or replace function public.guard_work_session_update()
returns trigger
language plpgsql
as $$
begin
  -- 시작시각·팀·소유자는 UPDATE 로 바꿀 수 없다. 마감/재개는 ended_at·duration_seconds 만 만진다.
  new.started_at := old.started_at;
  new.team_id := old.team_id;
  new.user_id := old.user_id;
  return new;
end;
$$;

drop trigger if exists guard_work_session_update on public.work_sessions;
create trigger guard_work_session_update
  before update on public.work_sessions
  for each row execute function public.guard_work_session_update();

-- ── S4: work_statuses 위조 차단 ──────────────────────────────────────────────
drop policy if exists "members can update their status" on public.work_statuses;
create policy "members can update their status"
  on public.work_statuses for update
  using (user_id = auth.uid() and public.is_team_member(work_statuses.team_id))
  with check (user_id = auth.uid() and public.is_team_member(work_statuses.team_id));

-- ── S2: orphan 회수 + 방금 시작 세션 보호 ────────────────────────────────────
create or replace function public.close_abandoned_work_sessions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  closed_count integer;
begin
  with stale as (
    -- (1) status='working' 인데 10분 무신호 — 기존 경로.
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
    set ended_at = greatest(stale.last_signal, s.started_at),
        duration_seconds = greatest(0, extract(epoch from (greatest(stale.last_signal, s.started_at) - s.started_at)))::int
    from stale
    where s.team_id = stale.team_id
      and s.user_id = stale.user_id
      and s.ended_at is null
      -- 마지막 신호보다 나중에 시작된 세션(= 방금 시작)은 방치가 아니므로 건드리지 않는다.
      and s.started_at <= stale.last_signal
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
      -- READ COMMITTED EPQ 재평가: 그 사이 하트비트가 도착해 신선해진 행은 자동으로 건너뛴다(레이스 차단).
      and st.status = 'working'
      and coalesce(st.last_seen_at, st.updated_at) < now() - interval '10 minutes'
    returning st.user_id
  ),
  orphans as (
    -- (2) status 를 경유하지 않고 work_sessions 를 직접 본다. status!='working'(또는 status 행 없음)이라
    --     위 closed_sessions 가 절대 잡지 못하는 '아무도 못 닫는 세션'이 여기서만 닫힌다. 30분 임계는
    --     '방금 열고 아직 하트비트 전'을 죽이지 않기 위한 여유다(closed_sessions 와 대상이 겹치지 않게
    --     status='working' 은 제외 — 한 문장에서 같은 행을 두 번 UPDATE 하는 것을 원천 차단).
    select
      s.id,
      s.started_at,
      coalesce(st.last_seen_at, st.updated_at, s.started_at) as last_signal
    from public.work_sessions s
    left join public.work_statuses st
      on st.team_id = s.team_id and st.user_id = s.user_id
    where s.ended_at is null
      and (st.status is distinct from 'working')
      and coalesce(st.last_seen_at, st.updated_at, s.started_at) < now() - interval '30 minutes'
  ),
  closed_orphans as (
    update public.work_sessions s
    set ended_at = greatest(o.last_signal, s.started_at),
        duration_seconds = greatest(0, extract(epoch from (greatest(o.last_signal, s.started_at) - s.started_at)))::int
    from orphans o
    where s.id = o.id
      and s.ended_at is null
    returning s.id
  )
  select (
    (select count(*) from closed_sessions) + (select count(*) from closed_orphans)
  )::int into closed_count;

  return coalesce(closed_count, 0);
end;
$$;

revoke all on function public.close_abandoned_work_sessions() from public;
grant execute on function public.close_abandoned_work_sessions() to authenticated, service_role;
-- 20260809120000 에서 anon 실행권을 회수했으므로 여기서도 anon 에 재부여하지 않는다(create or replace 는 권한 보존).

-- 사후 단언: 정상 경로가 살아 있는지 확인(어긋나면 배포 중단).
do $$
begin
  if not has_function_privilege('authenticated', 'public.close_abandoned_work_sessions()', 'execute') then
    raise exception 'authenticated 의 close_abandoned 실행권 소실 — 클라 스캐빈저 破損, 배포 중단';
  end if;
  if has_function_privilege('anon', 'public.close_abandoned_work_sessions()', 'execute') then
    raise exception 'anon 이 close_abandoned 를 실행할 수 있음 — 20260809120000 회수가 풀림, 배포 중단';
  end if;
end;
$$;
