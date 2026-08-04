-- 별명 변경 RPC + 쿨타임 컬럼 + profiles 컬럼 단위 UPDATE 권한 잠금.
-- 20260711090000:7-11 의 "users can update own profile" 정책은 **삭제하지 않는다**(누가=본인 판정은 계속 필요).
-- 멱등성: add column if not exists / create or replace / revoke·grant 재실행 안전.
--
-- PostgREST 임베드 안전성(결정 (o)) — 새 표 0개, 새 FK 0개. 더하는 것은 profiles 의 스칼라 컬럼
-- display_name_changed_at(timestamptz) 하나와 함수 하나뿐이다. 관계 그래프는 외래키 집합으로만 만들어지므로
-- work_statuses→profiles, memberships→teams 임베드의 경로 수는 각각 1개 그대로다.

alter table public.profiles
  add column if not exists display_name_changed_at timestamptz;
comment on column public.profiles.display_name_changed_at is
  '마지막 별명 변경 시각. null = 한 번도 안 바꿨다(첫 변경 즉시 허용). 가입 트리거는 이 값을 쓰지 않으므로 자동 생성 이름은 ''변경''이 아니다.';

-- poke_user(20260724020000) 의 jsonb 규약을 그대로 따른다.
-- {"status":"ok","display_name":"…"} | {"status":"unchanged","display_name":"…"} | {"status":"taken"}
-- | {"status":"cooldown","retry_after_seconds":N} | {"status":"invalid_empty"}
-- | {"status":"invalid_long","max_length":12} | {"status":"unauthorized"} | {"status":"no_profile"}
create or replace function public.set_display_name(p_name text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cleaned text;
  current_name text;
  changed_at timestamptz;
  elapsed numeric;
  retry_after int;
  cooldown constant numeric := 7 * 24 * 3600;   -- 1주일
  -- 별명 최대 길이. 클라의 WorkTimerStore.displayNameMaxLength 와 **같은 값이어야 한다** —
  -- 여기만 바꾸면 서버 판정은 바뀌지만 앱의 사전 검증은 옛 값으로 남아 "입력은 되는데 저장이 거부"가 된다.
  max_len  constant int := 12;
begin
  if uid is null then return jsonb_build_object('status','unauthorized'); end if;

  cleaned := public.normalize_display_name(p_name);
  if cleaned = '' then return jsonb_build_object('status','invalid_empty'); end if;
  -- '보이지 않는 문자만으로 된 이름' 차단. normalize_display_name 은 ZWJ·VS16·한글 채움 문자를
  -- **일부러 남기므로**(그래야 결합 이모지 이름이 안 깨진다) ZWJ 세 개짜리 입력도 cleaned 가 비지 않는다.
  -- 그런데 유일성 키는 그것들을 전부 지워 ''가 되고, 유니크 인덱스는 부분 인덱스(where key <> '')라
  -- 그 행을 **아예 보지 않는다**. 이 분기가 없으면 서로 다른 사용자 여럿이 연달아 ok 를 받아
  -- 전부 '화면에 아무것도 안 보이는 똑같은 이름'을 갖는다(로컬 PostgreSQL 로 실제 재현했다).
  -- 새 status 를 만들지 않고 invalid_empty 를 재사용한다 — 사용자에게 이건 실제로 빈 이름이고,
  -- 클라(SupabaseWorkModels.swift:876)가 이미 아는 값이라 모르는 status 로 떨어질 일이 없다.
  if public.display_name_key(cleaned) = '' then
    return jsonb_build_object('status','invalid_empty');
  end if;
  -- 길이는 그래핌이 아니라 **NFC 코드포인트** 수다. 클라가 같은 눈금(unicodeScalars.count)을 쓰도록
  -- normalize_display_name 이 NFC 합성을 먼저 해 둔다 — 안 그러면 NFD 로 들어온 한글이 서버에선 3배로 세진다.
  if char_length(cleaned) > max_len then
    return jsonb_build_object('status','invalid_long','max_length',max_len);
  end if;

  -- 쿨타임 판정을 **UPDATE 안으로** 넣는다. 밖에서 select 로 먼저 보면 같은 사용자의 맥 두 대가 같은 순간에
  -- 함께 통과해 한 창에서 두 번 바뀐다(행 잠금이 없어 READ COMMITTED 에서 두 번째도 그대로 성공한다).
  begin
    update public.profiles
       set display_name = cleaned, display_name_changed_at = now()
     where id = uid
       and display_name is distinct from cleaned
       and (display_name_changed_at is null
            or display_name_changed_at <= now() - make_interval(secs => cooldown));
  exception when unique_violation then
    -- 유니크 인덱스가 최종 판정자다. 사전 select 로 '비어 있음'을 확인해도 두 요청이 같은 순간에 통과한다.
    -- 서브블록이 통째로 롤백되므로 실패는 **쿨타임도 소모하지 않는다**(같은 UPDATE 문이라서).
    return jsonb_build_object('status','taken');
  end;

  if found then
    return jsonb_build_object('status','ok','display_name',cleaned);
  end if;

  -- 0행이면 사유를 판별한다(이 시점엔 경쟁 트랜잭션이 이미 커밋돼 있다).
  select p.display_name, p.display_name_changed_at into current_name, changed_at
    from public.profiles p where p.id = uid;
  if not found then return jsonb_build_object('status','no_profile'); end if;
  if cleaned = current_name then
    -- 아무것도 안 고치고 저장만 눌렀다. 이 분기가 없으면 쿨타임 1주일이 헛되이 소모돼
    -- "바꾼 게 없는데 일주일 잠김"이 된다.
    return jsonb_build_object('status','unchanged','display_name',current_name);
  end if;
  elapsed := extract(epoch from (now() - changed_at));
  retry_after := greatest(1, ceil(cooldown - elapsed)::int);
  return jsonb_build_object('status','cooldown','retry_after_seconds',retry_after);
end;
$$;

revoke all on function public.set_display_name(text) from public;
grant execute on function public.set_display_name(text) to authenticated;

-- ── 우회 경로 차단 ──────────────────────────────────────────────
-- profiles UPDATE 정책(20260711090000:7-11)은 '누가'(id = auth.uid())만 보고 '무엇을'은 안 본다.
-- 그래서 이 잠금이 없으면 클라가 위 RPC 를 통째로 건너뛰고
--   PATCH /rest/v1/profiles?id=eq.<me>  {"display_name":"아무거나"}
-- 한 방으로 길이·중복·쿨타임을 전부 우회할 수 있다(RLS 는 자기 행이니 통과한다).
--
-- **여기 없는 컬럼은 앱이 PATCH 할 수 없다.** 앞으로 클라가 직접 쓰는 컬럼을 profiles 에 더하면 반드시
-- 이 목록에 추가해야 한다(잊으면 그 PATCH 가 403 으로 죽는다 — 조용히 실패하지는 않는다).
-- 지금 앱이 PATCH 하는 컬럼은 실측상 정확히 둘이다:
--   avatar_url         → SupabaseWorkService.uploadAvatar(:379-398)
--   token_usage_public → SupabaseWorkService.updateTokenUsagePublic(:739-748)
-- token_usage_collect(20260803010000)은 목록에 **일부러 없다** — 앱은 이 컬럼을 GET 으로 읽기만 하고
-- (fetchTokenUsageSettings 의 select) PATCH 하지 않는다. 운영자는 service_role/SQL 로 끄므로 영향이 없다.
-- 컬럼 REVOKE 는 표 단위 권한을 지우지 못하므로 반드시 '표 단위 revoke → 컬럼 단위 grant' 순서다.
-- PUBLIC 까지 넣는다 — 하나라도 빠지면 선언적 잠금에 구멍이 남는다.
revoke update on public.profiles from public, anon, authenticated;
grant update (avatar_url, token_usage_public) on public.profiles to authenticated;
-- service_role 은 표 단위로 되돌려 준다. 위 revoke 의 `from public` 은 PUBLIC 을 통해 얻은 권한도 지우므로,
-- 표 권한을 PUBLIC 에서만 받고 있던 환경이라면 admin 의 profiles PATCH 가 403 이 된다
-- (e2e 의 별명 원복·쿨타임 리셋과 운영자 수동 조치가 전부 막힌다). service_role 키는 앱에 실리지 않으므로
-- 우회 경로가 열리지 않는다 — 20260804030000 의 `grant delete on public.pokes to service_role` 과 같은 이유다.
grant update on public.profiles to service_role;

-- 사후 단언. 위 revoke/grant 는 실행 역할이 public.profiles 의 소유자가 아니면 **에러가 아니라
-- WARNING 한 줄만 남기고 통과한다**(PostgreSQL 은 권한 없는 revoke 를 실패로 치지 않는다).
-- 즉 소유자가 어긋난 환경에서는 `supabase db push` 가 초록불을 띄운 채 우회 차단이 통째로 사라지고,
-- 그 뒤 PATCH /rest/v1/profiles?id=eq.<me> {"display_name":"…"} 한 방이면 길이·중복·쿨타임이 전부
-- 무력화된다 — 게다가 아무 증상이 없어 다음 사고까지 아무도 모른다. 그래서 결과를 직접 물어본다.
-- 뒤 두 줄은 **대조군**이다. 이 수리의 최악 실패는 막는 데 성공하고서 아바타 업로드와 토큰 공개 토글을
-- 같이 죽이는 것이라(둘 다 403 이 되는데 원인이 이 파일이라는 걸 아무도 못 찾는다), 막힘과 열림을
-- 한자리에서 함께 본다. 상태를 바꾸지 않는 조회뿐이라 몇 번을 다시 돌려도 안전하다.
do $$
begin
  if has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE') then
    raise exception '별명 직접 수정 차단이 걸리지 않았습니다(소유자 불일치 가능) — 배포 중단';
  end if;
  if not has_column_privilege('authenticated', 'public.profiles', 'avatar_url', 'UPDATE') then
    raise exception '아바타 변경 권한이 사라졌습니다 — 배포 중단';
  end if;
  if not has_column_privilege('authenticated', 'public.profiles', 'token_usage_public', 'UPDATE') then
    raise exception '토큰 공개 토글 권한이 사라졌습니다 — 배포 중단';
  end if;
end $$;
