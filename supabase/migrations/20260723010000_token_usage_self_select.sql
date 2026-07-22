-- 토큰 사용량 upsert 수리: 본인 행 select 정책 추가.
-- 실증: PostgREST 의 merge-duplicates upsert(INSERT ... ON CONFLICT DO UPDATE)는 RLS 아래에서
-- 충돌 대상 행을 읽기 위해 select 정책을 요구한다(행이 아직 없어도 요구됨 — 프로덕션 실측 403/42501,
-- 순수 INSERT 는 201 성공). select 정책이 전무하면 클라 업로드가 전부 거부되므로 "본인 행만" 열어 준다.
-- 프라이버시 불변: 타인 행 직접 select 는 여전히 불가(전체 조회는 token_usage_board RPC 가 표시 컬럼만 노출).
drop policy if exists "users read own token usage" on public.token_usage_monthly;
create policy "users read own token usage"
  on public.token_usage_monthly for select
  using (user_id = auth.uid());
