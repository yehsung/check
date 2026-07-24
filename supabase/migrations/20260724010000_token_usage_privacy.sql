-- 토큰 사용량 공개/비공개 설정. profiles.token_usage_public(기본 true)을 추가하고,
-- token_usage_board RPC 가 비공개 사용자를 타인 보드에서 숨기되 본인에게는 보이게 필터를 덧댄다.
-- 비공개로 두면 남의 순위판엔 안 뜨지만(익명도 아니고 통째로 제외) 자기 순위판엔 자기 행이 그대로 보인다.
-- 멱등성: add column if not exists / create or replace + revoke/grant 로 재실행 안전. (db push 는 오케스트레이터가 수행.)
alter table public.profiles
  add column if not exists token_usage_public boolean not null default true;

-- 전체 공개 순위 RPC 재정의: 반환 컬럼 구성(13컬럼)은 20260723060000 그대로 유지하고, where 절에만
-- 공개 필터를 추가한다 — 시그니처가 불변이라 create or replace 로 충분하나, 하우스 스타일대로 revoke/grant 를 재명시한다.
-- 필터: 사용자가 공개(coalesce true)이거나 본인(auth.uid())이면 포함. 비공개 유저는 타인에게 숨고 자기 자신에게는 보인다.
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
  total bigint,
  today_total bigint,
  today_date text
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
    t.total,
    t.today_total,
    t.today_date
  from public.token_usage_monthly t
  join public.profiles p on p.id = t.user_id
  where t.month = p_month
    and (coalesce(p.token_usage_public, true) or t.user_id = auth.uid())
  order by t.total desc, coalesce(p.display_name, '사용자');
$$;

-- 로그인한 앱 사용자 전용. anon 은 호출 불가(순위는 로그인 사용자만).
revoke all on function public.token_usage_board(text) from public;
grant execute on function public.token_usage_board(text) to authenticated;
