-- 콕찌르기: 로그인 사용자끼리 서로를 "콕" 찔러 상대 캐릭터를 움찔+말풍선으로 자극한다.
-- 규약: 보낸이가 근무중(열린 세션)일 때만 보낼 수 있고, 같은 대상에게는 60초 쿨타임을 서버가 강제한다.
-- 찔린 쪽은 15초 폴링으로 take_pokes() 를 호출해 원자적으로 수신+소비한다(1시간 지난 찔림은 클라가 미표시).
-- 멱등성: create table if not exists / create or replace + revoke/grant / do 블록 cron 으로 재실행 안전.
create table if not exists public.pokes (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  consumed_at timestamptz null
);

-- RLS 를 켜되 정책은 두지 않는다 — 직접 접근(select/insert/update/delete)을 전면 차단한다.
-- 모든 접근은 아래 security definer RPC(poke_user/take_pokes)로만 이뤄진다(찌르기 규칙·소비 원자성을 서버가 독점).
alter table public.pokes enable row level security;

-- 수신 폴링(미소비 찔림 조회+소비)용 부분 인덱스: 대상별 열린 찔림만 좁게 스캔한다.
create index if not exists pokes_unconsumed_by_to
  on public.pokes(to_user)
  where consumed_at is null;

-- 쿨타임 판정용: (보낸이→받는이) 쌍의 최신 찔림을 빠르게 찾는다.
create index if not exists pokes_from_to_created
  on public.pokes(from_user, to_user, created_at desc);

-- 콕 찌르기. 보낸이 근무중 게이트 + 같은 대상 60초 쿨타임을 서버가 강제한다.
-- 반환 jsonb: {"status":"ok"} | {"status":"invalid"} | {"status":"not_working"} | {"status":"cooldown","retry_after_seconds":N}
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

-- 내게 온 미소비 찔림을 원자적으로 수신+소비한다(폴링 1콜). 소비 표시(consumed_at)를 찍으며 보낸이 표시명/아바타를 함께 돌려준다.
-- created_epoch 은 extract(epoch)::bigint — ISO 소수초 파싱 함정 없이 클라가 Date 로 복원한다.
create or replace function public.take_pokes()
returns table(
  id uuid,
  from_user uuid,
  from_display_name text,
  from_avatar_url text,
  created_epoch bigint
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return;
  end if;
  return query
  with consumed as (
    update public.pokes
    set consumed_at = now()
    where to_user = uid and consumed_at is null
    returning pokes.id, pokes.from_user, pokes.created_at
  )
  select
    c.id,
    c.from_user,
    coalesce(p.display_name, '사용자'),
    p.avatar_url,
    extract(epoch from c.created_at)::bigint
  from consumed c
  left join public.profiles p on p.id = c.from_user
  order by extract(epoch from c.created_at)::bigint asc;
end;
$$;

revoke all on function public.take_pokes() from public;
grant execute on function public.take_pokes() to authenticated;

-- 콕찌르기 대상 디렉토리: 앱 사용자 전체(본인 제외) + 근무중 여부. 근무중 먼저·이름순으로 정렬한다.
-- 이메일 등 민감 컬럼은 노출하지 않는다(표시명/아바타/근무여부만).
create or replace function public.app_user_directory()
returns table(
  user_id uuid,
  display_name text,
  avatar_url text,
  is_working boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    coalesce(p.display_name, '사용자'),
    p.avatar_url,
    exists (
      select 1 from public.work_sessions s
      where s.user_id = p.id and s.ended_at is null
    ) as is_working
  from public.profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
  order by is_working desc, coalesce(p.display_name, '사용자');
$$;

revoke all on function public.app_user_directory() from public;
grant execute on function public.app_user_directory() to authenticated;

-- 오래된 찔림 청소(7일 경과분 삭제). 소비 여부와 무관하게 잔존 로그를 비운다 — 표시는 이미 1시간 신선도로 제한되므로
-- 7일 넘은 행은 보관 가치가 없다. 클라는 호출하지 않으므로 service_role 만 실행 가능하게 둔다.
create or replace function public.cleanup_old_pokes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  with removed as (
    delete from public.pokes
    where created_at < now() - interval '7 days'
    returning id
  )
  select count(*)::int into deleted_count from removed;
  return coalesce(deleted_count, 0);
end;
$$;

revoke all on function public.cleanup_old_pokes() from public;
grant execute on function public.cleanup_old_pokes() to service_role;

-- pg_cron 일 1회 스케줄('0 19 * * *' UTC = KST 새벽 4시). 20260712120000 하우스 패턴을 따른다:
-- pg_cron 미지원 환경이어도 함수는 남고 마이그레이션이 죽지 않도록 do 블록으로 감싼다. cron.schedule 은
-- 같은 잡 이름 재호출 시 교체하므로 멱등하다.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule(
    'cleanup-old-pokes',
    '0 19 * * *',
    $cron$select public.cleanup_old_pokes();$cron$
  );
exception when others then
  raise notice 'pg_cron 스케줄 등록 건너뜀(환경 미지원 가능): %', sqlerrm;
end
$$;
