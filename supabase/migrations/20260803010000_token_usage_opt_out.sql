-- AI 토큰 사용량 '수집 안 함' 설정. profiles.token_usage_collect(기본 true)를 끄면
-- 그 사용자의 토큰 행이 **서버에 아예 쌓이지 않고**, 이미 쌓인 행도 그 순간 지워진다.
--
-- 기존 token_usage_public(20260724010000)과 무엇이 다른가:
--   public=false 는 '남의 순위판에 안 뜬다'일 뿐 데이터는 계속 수집·저장되고 본인에겐 보인다.
--   collect=false 는 '수집 자체를 안 한다' — 행이 없으므로 보드에도 아무에게도 안 뜬다(본인 포함).
--   두 설정은 독립이다. 공개는 하되 수집은 한다 / 수집은 하되 비공개다 둘 다 가능하다.
--
-- 왜 앱이 아니라 **서버**가 막는가(이 설계의 전부다):
--   브루 업데이트가 수일~수주 걸려 구버전 클라이언트가 계속 살아 있다. 앱에만 게이트를 두면
--   그 사람이 업데이트할 때까지 업로드가 계속되고, 지워 봐야 다음 폴링에 되살아난다.
--   서버가 막으면 **버전과 무관하게 즉시** 멈춘다.
--
-- 왜 거절(raise)이 아니라 조용히 버리는가:
--   업로드 실패를 던지면 클라가 영구 재시도에 고착될 수 있다(이 저장소가 이미 겪은 poison-pill 부류).
--   앱은 return=minimal 로 올리므로(SupabaseWorkService.upsertTokenUsage) 0행 응답을 성공으로 본다 —
--   조용히 버리면 앱은 아무 일 없다는 듯 지나가고 다음 주기에 난사하지도 않는다.
--   같은 이유로 하우스 선례(enforce_open_session_for_working = 거절 대신 강등)와도 규약이 일치한다.
--
-- 멱등성: add column if not exists / create or replace function / drop trigger if exists → create.

alter table public.profiles
  add column if not exists token_usage_collect boolean not null default true;

comment on column public.profiles.token_usage_collect is
  '토큰 사용량 수집 여부. false 면 서버가 이 사용자의 토큰 쓰기를 조용히 버리고 기존 행도 지운다(앱 버전 무관).';

-- 1) 쓰기 차단 — 수집 끔이면 그 행을 통째로 건너뛴다(BEFORE 트리거의 return null = 그 행 없던 일로).
--    security definer 인 이유: profiles 는 RLS 가 걸려 있어 호출자 권한으로는 남의 행은 물론
--    상황에 따라 자기 행 판정도 막힐 수 있다. 판정에 필요한 컬럼 하나만 읽는다.
create or replace function public.skip_token_usage_when_opted_out()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.profiles
    where profiles.id = new.user_id
      and profiles.token_usage_collect = false
  ) then
    return null;   -- 이 쓰기는 없던 일이 된다. 클라에는 성공(0행)으로 보인다.
  end if;
  return new;
end;
$$;

revoke all on function public.skip_token_usage_when_opted_out() from public;

drop trigger if exists skip_token_usage_device_when_opted_out on public.token_usage_device_monthly;
create trigger skip_token_usage_device_when_opted_out
  before insert or update on public.token_usage_device_monthly
  for each row execute function public.skip_token_usage_when_opted_out();

-- 옛 표도 함께 막는다 — v0.2.10 구버전 맥은 이쪽으로만 올린다.
drop trigger if exists skip_token_usage_legacy_when_opted_out on public.token_usage_monthly;
create trigger skip_token_usage_legacy_when_opted_out
  before insert or update on public.token_usage_monthly
  for each row execute function public.skip_token_usage_when_opted_out();

-- 2) 이미 쌓인 행 정리 — 설정을 끄는 순간 자동으로 지운다.
--    이걸 트리거로 두는 이유: 운영자가 플래그만 바꾸고 삭제를 잊으면 순위판에 옛 수치가 그대로 남아
--    '수집 안 함'이 지켜지지 않은 것처럼 보인다. 플래그 하나로 상태가 완결되게 한다.
--    (다시 켜면 앱이 다음 주기에 로컬 원장에서 그 달치를 복원해 올린다 — 되돌리기가 무손실이다.)
create or replace function public.purge_token_usage_on_opt_out()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.token_usage_collect = false and coalesce(old.token_usage_collect, true) = true then
    delete from public.token_usage_device_monthly where user_id = new.id;
    delete from public.token_usage_monthly where user_id = new.id;
  end if;
  return new;
end;
$$;

revoke all on function public.purge_token_usage_on_opt_out() from public;

drop trigger if exists purge_token_usage_on_opt_out on public.profiles;
create trigger purge_token_usage_on_opt_out
  after update of token_usage_collect on public.profiles
  for each row execute function public.purge_token_usage_on_opt_out();

-- 3) 이 마이그레이션 적용 시점에 이미 꺼져 있는 사용자가 있으면 함께 정리한다(재실행 안전).
--    지금은 기본값이 true 라 아무도 해당하지 않지만, 나중에 이 파일이 새 환경에 처음 적용될 때를 위해 둔다.
delete from public.token_usage_device_monthly
  where user_id in (select id from public.profiles where token_usage_collect = false);
delete from public.token_usage_monthly
  where user_id in (select id from public.profiles where token_usage_collect = false);
