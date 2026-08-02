-- 세션 소유권을 추측이 아니라 **사실**로 판정하기 위한 기기별 소유 주장 표.
--
-- 왜 work_statuses 에 last_seen_device 컬럼을 더하지 않는가(이 설계의 전부다):
--   앱은 폴링마다 하트비트를 **먼저** 쓰고 **그 다음** 읽는다(WorkTimerStore.startStatusRefreshLoop).
--   그래서 내가 읽는 행은 언제나 1초 전 내가 쓴 그 행이다 — 계량 실증 seen−mine = [-0.89,-0.89,-0.90].
--   그 셀에 기기를 넣어도 결과는 같다: 읽으면 항상 '내 기기'라 "기기==나 → 소유"는 정보량이 0 이고,
--   "기기!=나 → 반납"은 상대 쓰기가 내 POST 커밋과 내 GET 사이 한 왕복(≈0.2초/30초 ≈ 0.5%)에 떨어질
--   때만 발화한다 = 이중 소유 감지에 평균 100분. 사고(뚜껑 6분 닫힘 → 남의 살아 있는 세션 마감)는 그 전에 난다.
--   즉 last_seen_at 만 못 쓰는 게 아니라 **하나의 셀을 나눠 쓰는 방식 전부**가 못 쓴다.
--   기기마다 자기 행을 주면 내 upsert 가 남의 행을 건드릴 수 없어 증거가 지워지지 않는다.
--   (token_usage_device_monthly 가 맥 2대의 토큰 합산을 가른 것과 같은 처방이다 — 기기를 PK 에 넣는다.)
--
-- 하위호환(이 프로젝트의 제1원칙): v0.2.10 은 이 표의 존재를 모른다. 쓰지도 읽지도 않는다.
--   work_statuses 는 컬럼 하나 건드리지 않고 트리거도 걸지 않으므로 **구버전의 기존 요청이 바이트 하나
--   달라지지 않는다**. 구버전 맥은 이 표에서 그냥 '보이지 않는' 상태가 되고, 앱은 그것을 '소유 불명'으로
--   읽어 기존 백스톱(7분)으로 되돌아간다 — 오탐이 아니라 정직한 판정 불가다.
--   (앱 규약: 신선하게 전진하는 **남의** 기기 행은 반납의 증거다. 그 부재는 아무것도 증명하지 않는다.
--    이 일방향 규칙이 없으면 "구버전 맥이 조용하다 = 다른 맥 없다"로 승격돼 이중 소유가 고착한다.)
--
-- 앱이 이 표를 못 읽어도(마이그레이션 미적용 서버 등) 폴링은 멀쩡해야 한다 — 그래서 앱은 이 조회를
--   팀 상태 GET 에 **임베딩하지 않고** 실패를 삼키는 별도 병렬 GET 으로 둔다. 임베딩했다면 표가 없는 서버에서
--   PostgREST 가 관계를 못 찾아 400 을 돌려주고, 팀 상태 폴링 전체(= 팀 목록·내 세션 복구·원격 종료 반영)가
--   통째로 죽는다. 앱 먼저 나가는 사고를 스키마가 아니라 코드로 막아 둔 것이다.
-- 멱등성: create table if not exists / add column if not exists / drop policy if exists → create 로 재실행 안전.

create table if not exists public.work_status_devices (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- 이 맥의 식별자(앱이 UserDefaults 'check.deviceID' 에 1회 생성해 영속 — 토큰 원장이 쓰는 그 값).
  device_id text not null,
  -- 이 맥이 소유를 주장하는 세션. 이게 없으면 '다른 맥이 살아 있다'와 '다른 맥이 **내 세션에** 살아 있다'를
  -- 못 가른다 → 정상적인 맥 간 인수인계(A 가 끝내고 B 가 새 세션 시작)에서 B 가 방금 연 자기 세션을
  -- 남의 것으로 오인해 즉시 반납하는 오발화가 난다. 앱은 이 값을 **항상** 실어 보낸다(하트비트 경로가
  -- 세션 ID 가드를 이미 통과한 뒤라 nil 일 수 없다). null 을 허용해 두는 것은 스키마 쪽 안전판일 뿐이다.
  session_id uuid null,
  -- 이 맥이 **자기 시계로** 찍는다. 앱은 절대값(신선도)이 아니라 폴링 간 **전진 여부**로 판정하므로
  -- 두 맥의 시계 어긋남이 판정에 들어오지 않는다(updateAdoptedPresenceTracking 과 같은 규약).
  last_seen_at timestamptz not null default now(),
  -- 이 맥이 그 세션을 **직접 열었는가**(= 강한 소유). true 는 start() 또는 되돌리기 재개가 서버 왕복으로
  -- 확정한 **사실**이고, false 는 백스톱(updateAdoptedPresenceTracking)이 '아무도 안 돌보는 것 같다'고
  -- 세운 **추측**이다. 이 한 컬럼이 없으면 두 맥이 같은 세션을 주장할 때 누가 물러날지를 device_id 사전식
  -- 비교로 정할 수밖에 없고, device_id 는 랜덤 UUID 라 **정확히 절반의 확률로 진짜 소유자가 물러난다** —
  -- 그러면 살아 있는 맥의 세션이 마감되고 그 뒤 근무가 통째로 유실된다(v0.2.16 사고의 재현).
  -- 부분 유니크 인덱스(work_sessions_one_open_per_user)상 열린 세션은 사용자당 하나뿐이라 **강한 소유자는
  -- 최대 한 명**이다. 그래서 "약한 쪽이 강한 쪽에게 물러난다"는 규칙은 항상 진짜 소유자를 남긴다.
  opened_session boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (team_id, user_id, device_id),
  -- 참조 무결성 + 팀 탈퇴/계정 삭제 시 자동 정리. 그리고 훗날 팀 상태 GET 에 임베딩으로 합칠 여지를 남긴다
  -- (PostgREST 임베딩은 이 복합 FK 를 근거로 삼는다). 모든 팀 참여 경로가 work_statuses 행을 함께 만들고
  -- (20260701000000:97 / 20260711120000:48 / 20260711160000:104,150), 앱은 상태 upsert **뒤에** 이 행을
  -- 쓰므로 참조 대상은 항상 존재한다.
  foreign key (team_id, user_id) references public.work_statuses(team_id, user_id) on delete cascade
);

-- 앞선 버전의 이 마이그레이션을 이미 적용한 로컬/개발 DB 를 위한 보강(멱등).
alter table public.work_status_devices
  add column if not exists session_id uuid null;

-- 같은 이유의 보강(멱등). default false 인 이유는 앱의 판정 방향과 같다: **모르면 약하다**.
-- true 로 두면 이 컬럼을 안 보내는 쓰기(옛 앱/수동 insert)가 전부 '내가 세션을 열었다'로 승격돼
-- 진짜 소유자를 밀어낸다 — 없애려는 사고를 스키마 기본값이 다시 만들어 내는 셈이다.
alter table public.work_status_devices
  add column if not exists opened_session boolean not null default false;

alter table public.work_status_devices enable row level security;

-- 팀 범위 select 가 필요한 이유 두 가지:
--   (1) 다른 맥의 주장을 봐야 반납 규칙이 성립한다(같은 계정의 다른 기기 행도 이 정책으로 읽힌다).
--   (2) 20260723010000 에 적힌 그대로 — PostgREST merge-duplicates upsert 가 충돌 대상 행을 읽기 위해
--       select 정책을 요구한다. 없으면 자기 기기 행 업로드가 403 으로 전부 거부된다.
-- 노출되는 것은 이미 work_statuses 로 팀에 공개된 재실 정보와 같은 등급이다(기기ID + 마지막 신호).
drop policy if exists "members read team status devices" on public.work_status_devices;
create policy "members read team status devices"
  on public.work_status_devices for select
  using (public.is_team_member(work_status_devices.team_id));

drop policy if exists "members insert own status device" on public.work_status_devices;
create policy "members insert own status device"
  on public.work_status_devices for insert
  with check (
    user_id = auth.uid()
    and public.is_team_member(work_status_devices.team_id)
  );

drop policy if exists "members update own status device" on public.work_status_devices;
create policy "members update own status device"
  on public.work_status_devices for update
  using (
    user_id = auth.uid()
    and public.is_team_member(work_status_devices.team_id)
  )
  with check (user_id = auth.uid());

-- 트리거·함수·security definer 가 하나도 없다 → revoke/grant 절도, 구버전 쓰기를 깨뜨릴 표면도 존재하지 않는다.
