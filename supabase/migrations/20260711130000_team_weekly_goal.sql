-- 팀별 주간 목표시간: teams 에 weekly_goal_hours 컬럼 추가.
-- 목표시간은 관리자가 팀 생성/수정 시 DB 에 넣는 값이고 앱은 읽기 전용으로만 사용한다.
-- 멱등성: add column if not exists 로 재실행 안전. 기존 팀 행은 default 60 으로 채워진다.
-- team_directory() RPC 는 변경하지 않는다(가입 화면에 목표는 불필요, invite_code 비노출 유지).
alter table public.teams
  add column if not exists weekly_goal_hours integer not null default 60
  check (weekly_goal_hours >= 1 and weekly_goal_hours <= 168);
