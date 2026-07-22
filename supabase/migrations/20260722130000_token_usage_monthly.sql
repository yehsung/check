-- 이번 달 AI 토큰 소모량 순위 페이지의 서버 원장 + 전체 공개 조회 RPC.
-- 각자 로컬에서 집계한 월간 토큰 사용량(Claude/Codex 6필드 + 총합)을 (user_id, month) 키로 upsert 하고,
-- 앱 사용자 누구나(팀 무관) 이번 달 순위를 조회한다 — 팀별 리그(team_weekly_leaderboard)와 같은 '전체 공개' 패턴.
-- month 는 앱이 계산한 KST 'YYYY-MM' 문자열(월별 초기화 = 새 월 키).
-- 멱등성: if not exists / create or replace / drop policy if exists 후 create 로 재실행 안전.
create table if not exists public.token_usage_monthly (
  user_id uuid not null references auth.users(id) on delete cascade,
  month text not null,  -- KST 'YYYY-MM' (앱이 Asia/Seoul 기준으로 계산해 보낸다)
  claude_input bigint not null default 0,
  claude_output bigint not null default 0,
  claude_cache_read bigint not null default 0,
  claude_cache_creation bigint not null default 0,
  codex_input bigint not null default 0,
  codex_output bigint not null default 0,
  total bigint not null default 0,  -- 6필드 합. 앱이 계산해 보내며 정렬/표시에 그대로 쓴다.
  updated_at timestamptz not null default now(),
  primary key (user_id, month)
);

alter table public.token_usage_monthly enable row level security;

-- 테이블 직접 select 는 잠근 채로 둔다(select 정책 없음) — 조회는 아래 security definer RPC(token_usage_board)로만.
-- RPC 가 profiles 에서 display_name/avatar_url 만 골라 내보내므로, 이 테이블을 직접 훑어도(정책 없어 0행) 이메일 등은 새지 않는다.
-- insert/update 는 여전히 본인 행만 허용해 남의 행을 조작하지 못하게 한다.

-- insert: 본인 행만.
drop policy if exists "users insert own token usage" on public.token_usage_monthly;
create policy "users insert own token usage"
  on public.token_usage_monthly for insert
  with check (user_id = auth.uid());

-- update: 본인 행만(merge-duplicates upsert 의 갱신 경로).
drop policy if exists "users update own token usage" on public.token_usage_monthly;
create policy "users update own token usage"
  on public.token_usage_monthly for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 전체 공개 전환 정리: 이전 초안의 '같은 팀 select' 정책과 shares_team_with 헬퍼를 제거한다(RPC 가 대체).
-- (이 마이그레이션은 미푸시라 실제로는 존재하지 않을 수 있으나, 로컬/개발 DB 에 부분 적용됐을 때를 위해 방어적으로 드롭한다.)
drop policy if exists "team members can read token usage" on public.token_usage_monthly;
drop function if exists public.shares_team_with(uuid);

-- 전체 공개 순위 RPC. 로그인 사용자 전용(anon 금지). 해당 월(p_month) **전체 사용자** 행을 profiles 와 조인해
-- (user_id, display_name, avatar_url, 6필드, total)로 반환한다. security definer 로 token_usage_monthly 의
-- 잠긴 select 를 우회하되, 골라 내보내는 컬럼은 표시에 필요한 것뿐이다(이메일 등 민감 컬럼 비노출).
-- 이메일 노출 금지: display_name 누락 시 email 이 아니라 '사용자'로 폴백한다(profiles.display_name 은 not null 이나 방어적으로).
-- 총합 내림차순 정렬은 서버도 해 주되(동률 시 이름), 클라가 신뢰하지 않고 다시 정렬한다.
-- 멱등성: create or replace + revoke/grant 로 재실행 안전.
create or replace function public.token_usage_board(p_month text)
returns table(
  user_id uuid,
  display_name text,
  avatar_url text,
  claude_input bigint,
  claude_output bigint,
  claude_cache_read bigint,
  claude_cache_creation bigint,
  codex_input bigint,
  codex_output bigint,
  total bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.user_id,
    coalesce(p.display_name, '사용자'),
    p.avatar_url,
    t.claude_input,
    t.claude_output,
    t.claude_cache_read,
    t.claude_cache_creation,
    t.codex_input,
    t.codex_output,
    t.total
  from public.token_usage_monthly t
  join public.profiles p on p.id = t.user_id
  where t.month = p_month
  order by t.total desc, coalesce(p.display_name, '사용자');
$$;

-- 로그인한 앱 사용자 전용. anon 은 호출 불가(순위는 로그인 사용자만).
revoke all on function public.token_usage_board(text) from public;
grant execute on function public.token_usage_board(text) to authenticated;
