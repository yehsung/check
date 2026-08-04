-- 울트라 찌르기: 하루 두 번, 대상 화면을 5초간 뒤덮는다.
-- 원칙 3가지 —
-- (1) poke_user(uuid) 는 손대지 않는다(v0.2.10~v0.2.15 가 프로덕션에서 부른다).
-- (2) 오버로딩 금지: 두 함수 인자가 p_to 하나로 같으면 PostgREST 가 어느 쪽인지 못 가려 300/404 가 난다.
--     새 이름 ultra_poke_user 를 쓴다.
-- (3) 새 표 금지: FK 두 개짜리 새 표는 PostgREST 가 다대다 연결표로 오해해 기존 임베드를 PGRST201(400)로
--     죽인다(20260802120000 실사고). 컬럼 추가는 FK 를 만들지 않으므로 임베드 경로 유일성이 산술적으로 불변이다.
-- 멱등성: add column if not exists / drop constraint if exists 선행 / create index if not exists /
--         drop function if exists 선행.
--
-- PostgREST 임베드 안전성(결정 (o)) — 이 파일이 더하는 것은 pokes 의 스칼라 컬럼 kind(text) 1개,
-- 그 컬럼을 조건으로 하는 부분 인덱스 1개, 함수 2개다. 외래키는 하나도 늘지 않는다(pokes 의 FK 는
-- 20260701 이래 from_user/to_user → profiles 두 개 그대로). 앱이 쓰는 임베드
--   work_statuses?select=…,profiles(…)  /  memberships?select=team_id,role,teams(…)
-- 의 경로 수는 각각 1개로 불변이다. check 제약과 부분 인덱스는 관계 그래프에 참여하지 않는다.
alter table public.pokes add column if not exists kind text not null default 'normal';
alter table public.pokes drop constraint if exists pokes_kind_check;
alter table public.pokes add constraint pokes_kind_check check (kind in ('normal','ultra'));

-- 하루 한도 판정 전용 부분 인덱스(보낸이별 울트라만 좁게 스캔).
create index if not exists pokes_ultra_by_from_created
  on public.pokes(from_user, created_at desc) where kind = 'ultra';

-- 반환 jsonb:
--   {"status":"ok","ultra_remaining":N}
-- | {"status":"ultra_used_today","ultra_remaining":0,"reset_after_seconds":N}
-- | {"status":"cooldown","retry_after_seconds":N}
-- | {"status":"invalid"} | {"status":"not_working"} | {"status":"target_not_working"}
create or replace function public.ultra_poke_user(p_to uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  day_start timestamptz;
  used_today int;
  last_created timestamptz;
  elapsed numeric;
  retry_after int;
  -- 하루 한도. **한도를 바꾸려면 여기 한 줄만 바꾼다** — 판정도 ultra_remaining 계산도 전부 이 상수를 읽는다.
  -- 클라의 WorkTimerStore.ultraPokeDailyLimit 과 같은 값이어야 안내 문구("오늘 N번 남음")가 서버와 일치한다.
  ultra_poke_daily_limit constant int := 2;
begin
  if uid is null or p_to = uid or not exists (select 1 from public.profiles where id = p_to) then
    return jsonb_build_object('status','invalid');
  end if;
  if not exists (select 1 from public.work_sessions where user_id = uid and ended_at is null) then
    return jsonb_build_object('status','not_working');
  end if;
  -- 대상 근무중 게이트는 울트라에서 **더** 필수다: 수신 클라는 비근무 구간에 take_pokes 를 아예 안 부르므로
  -- (WorkTimerStorePoke.takePokesIfWorking) 자리비움 대상에게 보낸 울트라는 소비되지 않은 채 7일 cron 에
  -- 지워지고 보낸이는 하루치 몫만 태운다.
  if not exists (select 1 from public.work_sessions where user_id = p_to and ended_at is null) then
    return jsonb_build_object('status','target_not_working');
  end if;

  -- 같은 보낸이의 동시 발사가 모두 한도 검사를 통과하는 레이스를 막는다(트랜잭션 끝에 자동 해제).
  perform pg_advisory_xact_lock(hashtext('ultra_poke:' || uid::text));

  -- KST 오늘 00:00. 리그 RPC(20260711140000:29)와 문자 단위로 같은 관용구.
  day_start := (date_trunc('day', (now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul');
  -- 하루 한도는 **보낸 사람 기준(대상 무관)**. 대상별로 재면 26명 조직에서 하루 25×N 번 남의 화면을 덮을 수 있다.
  -- 한도 장부는 별도 표가 아니라 pokes 행 자체다 — 실패는 행을 안 남기므로 '실패가 몫을 태우는' 버그가
  -- 원리적으로 없다(장부와 사실이 같은 것이라 어긋날 수가 없다).
  select count(*) into used_today
    from public.pokes
   where from_user = uid and kind = 'ultra' and created_at >= day_start;

  if used_today >= ultra_poke_daily_limit then
    return jsonb_build_object(
      'status','ultra_used_today',
      -- 소진 응답에도 남은 횟수를 싣는다. 클라는 **울트라 응답에서만** 남은 횟수를 갱신하므로
      -- 여기서 빼면 "오늘 N번 남음" 표시가 실패 직후 옛 값에 굳는다.
      'ultra_remaining', greatest(0, ultra_poke_daily_limit - used_today),
      'reset_after_seconds',
      greatest(1, ceil(extract(epoch from ((day_start + interval '1 day') - now())))::int));
  end if;

  -- 쿨타임은 하루한도 **뒤**다: 오늘 몫이 없는 사람에게 '40초 뒤 다시'를 안내하는 모순을 막는다
  -- (target_not_working 을 쿨타임 앞에 둔 20260724030000 과 같은 논리).
  -- 이 쿨타임은 poke_user 와 **같은 pokes 장부를 공유한다** — 즉 일반 찌르기 직후 60초 동안은 울트라도 못 나간다.
  select max(created_at) into last_created from public.pokes where from_user = uid and to_user = p_to;
  if last_created is not null then
    elapsed := extract(epoch from (now() - last_created));
    if elapsed < 60 then
      retry_after := greatest(1, ceil(60 - elapsed)::int);
      return jsonb_build_object('status','cooldown','retry_after_seconds',retry_after);
    end if;
  end if;

  insert into public.pokes (from_user, to_user, kind) values (uid, p_to, 'ultra');
  -- 방금 쓴 한 번을 반영한 남은 횟수. 음수 클램프는 한도를 나중에 **줄였을 때** 의미가 있다
  -- (2회를 이미 쓴 사람에게 한도가 1이 되면 -1 이 나온다).
  return jsonb_build_object(
    'status','ok',
    'ultra_remaining', greatest(0, ultra_poke_daily_limit - (used_today + 1)));
end;
$$;
revoke all on function public.ultra_poke_user(uuid) from public;
grant execute on function public.ultra_poke_user(uuid) to authenticated;

-- RETURNS TABLE 시그니처가 바뀌므로(kind 추가) create or replace 로는 못 바꾼다 — drop 선행.
-- drop 은 grant 도 같이 지우므로 아래 grant 를 반드시 다시 준다.
drop function if exists public.take_pokes();
create or replace function public.take_pokes()
returns table(
  id uuid,
  from_user uuid,
  from_display_name text,
  from_avatar_url text,
  created_epoch bigint,
  kind text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  return query
  with consumed as (
    update public.pokes set consumed_at = now()
    where to_user = uid and consumed_at is null
    returning pokes.id, pokes.from_user, pokes.created_at, pokes.kind
  )
  select c.id, c.from_user, coalesce(p.display_name,'사용자'), p.avatar_url,
         extract(epoch from c.created_at)::bigint, c.kind
  from consumed c left join public.profiles p on p.id = c.from_user
  order by extract(epoch from c.created_at)::bigint asc;
end;
$$;
revoke all on function public.take_pokes() from public;
grant execute on function public.take_pokes() to authenticated;

-- e2e 픽스처가 service_role 로 pokes 를 만진다: 정리(deleteUltraPokes/deleteAllPokes)는 DELETE,
-- 한도 장부 검증(ultraPokeCount)은 SELECT, 쿨타임만 만료시키는 백데이트(backdatePokes)는 UPDATE 다.
-- RLS 는 우회되지만 표 권한은 별개이고, DELETE/UPDATE ... where from_user = … 는 그 WHERE 절 컬럼에
-- **SELECT 권한까지** 요구한다 — 하나라도 빠지면 403 이 나고 원인이 '기능 고장'처럼 보인다.
grant select, update, delete on public.pokes to service_role;
