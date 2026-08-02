-- 긴급 수리: work_status_devices 가 팀 현황 조회를 통째로 400 으로 죽이던 것을 되돌린다.
--
-- 무슨 일이 있었나:
--   20260801010000 이 만든 work_status_devices 에 FK 가 셋이었다 —
--     team_id -> teams(id), user_id -> profiles(id), (team_id,user_id) -> work_statuses(team_id,user_id).
--   PostgREST 는 "두 표를 각각 가리키는 FK 를 가진 표"를 **다대다 연결 표(junction)** 로 자동 해석한다.
--   그래서 work_statuses 와 profiles 사이에 관계가 둘이 되었다:
--     (1) 직접: work_statuses.user_id -> profiles.id
--     (2) 경유: work_statuses <- work_status_devices -> profiles
--   앱의 팀 현황 조회는 예전부터 `work_statuses?select=...,profiles(display_name,email,avatar_url)` 인데,
--   관계가 둘이 되는 순간 PostgREST 가 PGRST201("Could not embed because more than one relationship
--   was found")로 **요청 전체를 거절**한다. 팀 목록·내 세션 복구·원격 종료 반영이 통째로 멈추고
--   화면에는 소속팀이 사라진 것처럼 보인다.
--
--   결정적으로 이건 **서버만의 변경이라 앱 버전과 무관하다** — v0.2.10~v0.2.14 를 쓰는 팀원도 같이 죽었다.
--   새 표를 더하는 것만으로 **기존 조회가 깨질 수 있다**는 것이 이 사고의 교훈이다.
--   (테스트가 못 잡은 이유: URLProtocolStub 은 보낸 select 를 해석하지 않고 준비된 JSON 을 돌려준다.
--    PostgREST 의 관계 해석은 실서버에서만 일어난다.)
--
-- 수리:
--   단일 컬럼 FK 둘을 뗀다. 그러면 work_status_devices 는 work_statuses 만 가리키는 평범한 자식 표가 되어
--   junction 해석이 성립하지 않고, 관계는 다시 하나뿐이 된다.
--
-- 왜 데이터 무결성이 유지되나:
--   (team_id,user_id) -> work_statuses 복합 FK 를 **남긴다**. work_statuses 자신이 이미
--   team_id -> teams(id) on delete cascade / user_id -> profiles(id) on delete cascade 를 들고 있으므로
--   (20260701000000:26-27), 팀이나 프로필이 지워지면 work_statuses 가 지워지고 그 연쇄로 기기 행도 지워진다.
--   즉 삭제 연쇄는 전이적으로 그대로 보존된다 — 잃는 것은 PostgREST 의 오해뿐이다.
--
--   RLS 정책은 auth.uid() 와 is_team_member() 만 쓰므로 FK 와 무관하다(정책 변경 없음).
--
-- 멱등성: drop constraint if exists 라 재실행 안전.

alter table public.work_status_devices
  drop constraint if exists work_status_devices_team_id_fkey;

alter table public.work_status_devices
  drop constraint if exists work_status_devices_user_id_fkey;
