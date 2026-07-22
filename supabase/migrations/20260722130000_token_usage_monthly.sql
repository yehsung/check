-- 팀원별 이번 달 AI 토큰 사용량 순위 페이지의 서버 원장.
-- 각자 로컬에서 집계한 월간 토큰 사용량(Claude/Codex 6필드 + 총합)을 (user_id, month) 키로 upsert 하고,
-- 같은 팀 멤버끼리만 서로의 사용량을 조회한다. month 는 앱이 계산한 KST 'YYYY-MM' 문자열(월별 초기화 = 새 월 키).
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

-- 호출자(auth.uid())와 대상 유저가 같은 팀에 함께 속해 있는지 판정. 자기 자신도 참(mine=theirs 교집합)이라
-- 본인 행 조회도 이 정책으로 커버된다. security definer 로 memberships RLS 를 우회해 교집합만 본다.
create or replace function public.shares_team_with(other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships mine
    join public.memberships theirs on theirs.team_id = mine.team_id
    where mine.user_id = auth.uid()
      and theirs.user_id = other_user_id
  );
$$;

revoke all on function public.shares_team_with(uuid) from public;
grant execute on function public.shares_team_with(uuid) to authenticated;

-- select: 같은 팀 멤버만(호출자와 대상의 team_id 교집합 존재). 본인 행도 여기 포함된다.
drop policy if exists "team members can read token usage" on public.token_usage_monthly;
create policy "team members can read token usage"
  on public.token_usage_monthly for select
  using (public.shares_team_with(token_usage_monthly.user_id));

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
