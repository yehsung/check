-- 토큰 순위판 "오늘 +N" 표시용 오늘(KST) 증가량 컬럼 추가 + 조회 RPC 확장.
-- 각 앱이 자기 로컬 로그에서 오늘(KST 자정 이후)치를 계산해 월간 행에 함께 업로드하고,
-- token_usage_board RPC 가 그 값을 함께 내려줘 순위 카드가 "이번 달 총량" 아래 "오늘 +N"을 보인다.
-- today_date 는 앱이 계산한 KST 'YYYY-MM-DD'(오늘분이 귀속된 날짜) — 표시 측이 현재 KST 날짜와 다르면 0 으로 본다.
-- 멱등성: add column if not exists / create or replace 로 재실행 안전. (db push 는 오케스트레이터가 수행 — 여기선 SQL 만.)
alter table public.token_usage_monthly
  add column if not exists today_total bigint not null default 0;
alter table public.token_usage_monthly
  add column if not exists today_date text not null default '';

-- 전체 공개 순위 RPC 를 재정의해 today_total/today_date 를 반환 컬럼에 추가한다(나머지 계약은 불변).
-- 앞선 마이그레이션(20260722130000)의 함수 시그니처를 그대로 잇되, 반환 테이블에 오늘 두 컬럼만 덧붙인다.
-- 반환 컬럼 구성이 바뀌므로 create or replace 전에 drop 한다(returns table 시그니처 변경은 replace 불가라 방어적으로).
drop function if exists public.token_usage_board(text);
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
  order by t.total desc, coalesce(p.display_name, '사용자');
$$;

-- 로그인한 앱 사용자 전용. anon 은 호출 불가(순위는 로그인 사용자만).
revoke all on function public.token_usage_board(text) from public;
grant execute on function public.token_usage_board(text) to authenticated;
