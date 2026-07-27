-- 맥 2대(같은 계정) 토큰 합산 수리: 월 원장을 **기기별 표로 새로 만들고** 보드에서 서버가 합산한다.
-- 결함: 기존 원장 token_usage_monthly 의 키가 (user_id, month) 라 맥 A 가 올린 값을 맥 B 가 통째로 덮어썼다 —
-- 마지막으로 켠 기기의 로컬 집계만 남아 월 총량이 "합산"이 아니라 "마지막 기기 값"이었다.
--
-- 왜 기존 표의 기본키를 (user_id, month, device_id) 로 바꾸지 않는가(하위호환이 이 설계의 전부다):
--   프로덕션 v0.2.10 클라는 `POST /rest/v1/token_usage_monthly?on_conflict=user_id,month` 로 올린다.
--   그 표의 PK 에 device_id 를 더하면 (user_id, month) 유니크 근거가 사라져 미업데이트 사용자의 업로드가
--   42P10 으로 **100% 실패**하고(브루로 올리기 전까지 수일~수주), 이관 잔재라며 legacy 행까지 지우면 그들의
--   이번 달 수치가 배포 즉시 소실돼 순위가 통째로 어긋난다. 그래서 기존 표는 컬럼 하나도 건드리지 않고
--   그대로 둔다 — v0.2.10 은 아무 일 없었다는 듯 계속 정상 upsert 한다.
--   v0.2.11 부터는 새 표(token_usage_device_monthly)에 (user_id, month, device_id) 로 올리고,
--   보드 RPC 가 "기기별 합산과 옛 표 행 중 **큰 쪽 한 줄**"을 쓴다(더하지 않는다 → 이중 계상 없음).
--
-- 왜 '기기 행이 있으면 옛 표를 통째로 무시'가 아니라 '큰 쪽'인가(과도기 손실 금지):
--   맥 A=v0.2.10(주력, 월 200M) / 맥 B=v0.2.11(보조, 월 2M) 처럼 한 대만 올린 과도기에는,
--   A 는 옛 표에만 쓰고 B 는 새 표에만 쓴다. '무시' 규칙이면 B 가 한 번 올리는 순간 A 의 200M 이
--   순위에서 영구 누락돼(A 를 아무리 써도 2M 고정) v0.2.10 보다 **더 나빠진다**.
--   '큰 쪽' 규칙이면 과도기 동안 200M(A 값)이 그대로 남고, 두 대 다 올린 뒤에는 기기 합산이 항상 이긴다
--   — 즉 자동으로 합산 체제로 넘어간다.
--   (옛 행은 마지막으로 쓴 기기의 그 달 누적치라 항상 그 기기의 새 행 이하 ≤ 합산이다.)
--   합이 아니라 최댓값이라 업그레이드 직후 같은 누적치가 두 표에 동시에 있어도 이중 계상되지 않는다.
--   (단 '오늘 증가분'만은 행 단위 선택에서 떼어 두 출처의 큰 쪽을 쓴다 — 아래 merged 주석 참조.)
--   이 규칙이 성립하려면 v0.2.11 클라가 옛 행을 **깎지 않아야** 한다. 그래서 앱은 옛 표를 덮어쓰기 전에
--   현재 총량을 읽어 자기 값이 더 작으면 쓰지 않는다(앱: fetchLegacyTokenUsageTotal → upsertLegacyTokenUsage).
--   그 게이트가 없으면 위 예에서 B 가 옛 행을 2M 으로 덮어 legacy = device_sum 이 되고, '큰 쪽' 비교가
--   무의미해져 A 의 200M 이 사라진다(= 마지막으로 팝오버를 연 맥의 값으로 널뛰던 v0.2.10 시절 증상).
--
-- 그러면 v0.2.9 이하가 남긴 **과다계상 화석**은 누가 정정하나(옛 행을 덮어쓸 수 없게 됐으므로):
--   v0.2.9 이하는 Codex 과다계상(달을 걸친 resume 세션의 과거 누적이 이번 달 총량으로 통째 편입)을 옛 행에
--   남긴다. 그 값은 정정된 기기 합산보다 크므로, 그냥 두면 '큰 쪽' 비교에서 그 달 내내 이겨 순위판 1위에
--   고정된다(사용자가 앱에서 되돌릴 방법이 없다). 그래서 서버가 시각으로 가른다 — 아래 device_first:
--   "이 사용자가 **처음 기기별 행을 올린 시각**(= v0.2.11 로 올라온 순간) 이후로 한 번도 갱신되지 않은 옛 행"은
--   더 이상 아무도 쓰지 않는 화석이므로 무시한다. 아직 v0.2.10 인 다른 맥이 살아 쓰는 행은 그 시각 이후에도
--   계속 갱신되므로(그 맥이 켜질 때마다 upsert) 그대로 살아남는다 — 위 과도기 보증은 유지된다.
--   판정이 성립하려면 옛 행의 updated_at 이 **매 쓰기마다** 갱신돼야 한다. PostgREST upsert 는 본문에 없는
--   컬럼을 건드리지 않아 지금은 최초 insert 시각에 고정돼 있으므로, 아래에서 touch 트리거를 건다
--   (v0.2.10 클라의 쓰기에도 서버가 자동으로 적용된다 — 구버전 수정 없이 동작한다).
-- 멱등성: create table if not exists / add column if not exists / drop policy·trigger if exists → create /
--   drop function 선행 후 create 로 재실행 안전.

create table if not exists public.token_usage_device_monthly (
  user_id uuid not null references auth.users(id) on delete cascade,
  month text not null,       -- KST 'YYYY-MM' (앱이 Asia/Seoul 기준으로 계산해 보낸다)
  device_id text not null,   -- 이 맥의 식별자(앱이 UserDefaults 에 1회 생성해 영속). 기기별 행 분리 키.
  claude_input bigint not null default 0,
  claude_output bigint not null default 0,
  claude_cache_read bigint not null default 0,
  claude_cache_creation bigint not null default 0,
  codex_input bigint not null default 0,
  codex_output bigint not null default 0,
  total bigint not null default 0,       -- 6필드 합(그 기기 로컬 로그의 그 달 누적치).
  today_total bigint not null default 0, -- 오늘(KST) 증가분.
  today_date text not null default '',   -- 오늘분이 귀속된 KST 'YYYY-MM-DD'.
  updated_at timestamptz not null default now(),
  -- 이 행이 처음 생긴 시각. 사용자별 최솟값이 "이 계정이 v0.2.11 로 올라온 순간"의 하한이 되어, 옛 표 행이
  -- 아직 살아 있는 v0.2.10 맥의 값인지(그 시각 이후에도 갱신됨) 화석인지(갱신 끊김)를 가르는 기준이 된다.
  -- PostgREST upsert 는 본문에 없는 컬럼을 갱신하지 않으므로 이후 upsert 에도 최초 시각이 보존된다.
  created_at timestamptz not null default now(),
  primary key (user_id, month, device_id)
);

-- 앞선 버전의 이 마이그레이션을 이미 적용한 로컬/개발 DB 를 위한 보강(멱등).
alter table public.token_usage_device_monthly
  add column if not exists created_at timestamptz not null default now();

alter table public.token_usage_device_monthly enable row level security;

-- 옛 표의 updated_at 을 매 쓰기마다 실제 쓰기 시각으로 만든다(트리거 없이는 최초 insert 시각에 고정된다 —
-- PostgREST 의 on-conflict 갱신은 요청 본문에 있는 컬럼만 SET 하기 때문이다). 보드 RPC 가 "그 옛 행이 아직
-- 살아 있는 클라(v0.2.10 맥)의 값인가"를 이 시각으로 판정하므로, 이 트리거가 판정의 전제다.
-- 서버 쪽 장치라 구버전 클라(v0.2.10)의 업로드에도 그대로 적용된다.
--
-- 예외 한 가지: **명시적으로 과거 시각을 실은 쓰기**는 그 값을 보존한다.
--   앱(v0.2.10/v0.2.11)은 이 컬럼을 요청 본문에 절대 담지 않으므로(SupabaseWorkModels 의
--   TokenUsageLegacyUpsertRequest 에 updated_at 필드 자체가 없다) 실사용 경로의 동작은 완전히 같다.
--   반대로 무조건 now() 로 덮으면 '오래전에 쓰이고 갱신이 끊긴 옛 행'(= 화석)을 service_role 로도 만들 수 없어,
--   아래 화석 무시 규칙이 라이브 E2E(s09h)에서 **영원히 검증 불가**가 된다 — 실제로 그 픽스처는 옛 행을
--   심는 순간 updated_at 이 now() 가 되어 항상 '살아 있는 구버전 맥' 취급을 받았고, 화석 단언은 구조적으로
--   통과할 수 없었다(PostgreSQL 15 실측: 보드 total 이 정정값 7,000 이 아니라 화석 5,000,000).
--   악용 여지는 없다: RLS 로 자기 행만 쓸 수 있고, 과거로 미는 것은 자기 옛 행을 화석으로 만드는 자해다.
--   갱신 시각을 **앞당기는**(미래) 쪽은 여전히 막는다 — 미래 시각은 now() 로 클램프되므로 화석 판정을
--   무한정 회피할 수 없다.
--   판별 기준:
--     * insert: PostgREST 는 본문에 없는 컬럼을 보내지 않아 컬럼 기본값 now() 가 들어온다(>= now() → 갱신).
--     * update(merge-duplicates): 본문에 없으면 new.updated_at 이 old 값 그대로다(is not distinct → 갱신).
--   즉 '기본값도 아니고 옛 값도 아닌 과거 시각'만 명시 지정으로 보고 남긴다.
create or replace function public.touch_token_usage_monthly_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.updated_at is null
    or new.updated_at >= now()
    or (tg_op = 'UPDATE' and new.updated_at is not distinct from old.updated_at)
  then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists token_usage_monthly_touch_updated_at on public.token_usage_monthly;
create trigger token_usage_monthly_touch_updated_at
  before insert or update on public.token_usage_monthly
  for each row execute function public.touch_token_usage_monthly_updated_at();

-- 정책 3종은 옛 표와 같은 규약이다: 본인 행만 insert/update/select. 타인 조회는 아래 security definer RPC 로만.
-- (select 정책이 필요한 이유는 20260723010000 에 적힌 그대로 — PostgREST merge-duplicates upsert 가
--  충돌 대상 행을 읽기 위해 select 정책을 요구한다. 없으면 업로드가 403 으로 전부 거부된다.)
drop policy if exists "users insert own device token usage" on public.token_usage_device_monthly;
create policy "users insert own device token usage"
  on public.token_usage_device_monthly for insert
  with check (user_id = auth.uid());

drop policy if exists "users update own device token usage" on public.token_usage_device_monthly;
create policy "users update own device token usage"
  on public.token_usage_device_monthly for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users read own device token usage" on public.token_usage_device_monthly;
create policy "users read own device token usage"
  on public.token_usage_device_monthly for select
  using (user_id = auth.uid());

-- 전체 공개 순위 RPC 재정의: 반환 컬럼 13개 구성은 그대로 유지하되 기기별 행을 user_id 로 묶어 합산하고,
-- 그 합산과 옛 표 한 줄 중 총량이 큰 쪽을 그 사용자의 행으로 쓴다(과도기 손실 방지 + 이중 계상 금지).
-- today 는 기기마다 today_date 가 제각각(어제 켠 맥 + 오늘 켠 맥)일 수 있으므로, 서버가 KST 오늘을 직접 계산해
-- 그 날짜인 행만 더한다 — 반환하는 today_date 도 서버가 계산한 KST 오늘 문자열로 통일해 표시 측 비교가 항상 맞는다.
-- 공개 필터(비공개 유저는 타인에게 숨고 본인에게는 보인다)는 불변. 정렬은 합산 총량 내림차순, 동률이면 이름.
-- 반환 테이블 시그니처 자체는 같지만 하우스 스타일대로 drop 선행 후 재생성한다.
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
  with device_totals as (
    select
      d.user_id as uid,
      sum(d.claude_input)::bigint as claude_input,
      sum(d.claude_output)::bigint as claude_output,
      sum(d.claude_cache_read)::bigint as claude_cache_read,
      sum(d.claude_cache_creation)::bigint as claude_cache_creation,
      sum(d.codex_input)::bigint as codex_input,
      sum(d.codex_output)::bigint as codex_output,
      sum(d.total)::bigint as total,
      sum(
        case
          when d.today_date = to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD')
          then d.today_total
          else 0
        end
      )::bigint as today_total
    from public.token_usage_device_monthly d
    where d.month = p_month
    group by d.user_id
  ),
  -- 사용자별 '첫 기기별 행 생성 시각' = 이 계정이 v0.2.11 로 올라와 새 표에 처음 쓴 순간(달 무관 최솟값).
  -- 달 무관으로 잡는 이유: 달이 바뀌면 그 달의 기기 행은 새로 생기는데, 그 시각을 기준 삼으면 매달 1일에
  -- 아직 v0.2.10 인 맥의 옛 행이 '갱신 전'으로 잠시 탈락해 순위가 널뛴다(그 맥이 그날 한 번 쓰면 복귀).
  device_first as (
    select d.user_id as uid, min(d.created_at) as first_at
    from public.token_usage_device_monthly d
    group by d.user_id
  ),
  -- 사용자·달별 기기 합산(달 필터 없음). 아래 legacy_live 판정에만 쓴다 — 보드 표시는 위 device_totals 다.
  device_month_totals as (
    select d.user_id as uid, d.month as month, sum(d.total)::bigint as total
    from public.token_usage_device_monthly d
    group by d.user_id, d.month
  ),
  -- "이 계정에 아직 v0.2.11 이 아닌 맥이 **살아서 옛 표를 쓰고 있다**"는 증거(달 무관, 사용자 단위).
  -- 증거의 요건 두 가지:
  --   (a) 첫 기기 행 이후에 쓰인 옛 행일 것(l2.updated_at > first_at) — 그 전 값은 누가 썼는지 알 수 없다.
  --   (b) 그 달의 기기 합산보다 클 것(l2.total > 기기 합산) — v0.2.11 은 옛 표에 **자기 맥의 총량**만 쓰므로
  --       언제나 기기 합산 이하다. 따라서 합산을 넘는 값은 기기 행을 남기지 않는 구버전 맥이 쓴 것이다.
  --       이 조건이 없으면 v0.2.11 자신이 다음 달 옛 행을 쓰는 순간(그 달엔 옛 행이 없어 게이트가 열린다)
  --       스스로 '살아 있는 구버전 맥' 증거를 만들어 자기 화석을 영구히 되살린다.
  --   덤으로 (b) 는 판정의 사각지대를 만들지 않는다: 옛 행이 기기 합산 이하면 어차피 아래 '큰 쪽' 규칙에서
  --   기기 합산이 이기므로, 그 행을 살리든 버리든 보드 숫자가 같다.
  legacy_live as (
    select distinct l2.user_id as uid
    from public.token_usage_monthly l2
    join device_first f2 on f2.uid = l2.user_id
    left join device_month_totals t2 on t2.uid = l2.user_id and t2.month = l2.month
    where l2.updated_at > f2.first_at
      and l2.total > coalesce(t2.total, 0)
  ),
  -- 옛 표((user_id, month) 한 줄)는 사용자 전원에 대해 읽되, **화석**만 제외한다.
  -- 제외 규칙: 기기별 행을 처음 올린 뒤로 한 번도 갱신되지 않은 옛 행(l.updated_at <= first_at) = 아무도
  -- 쓰지 않는 v0.2.9 이하의 잔재(과다계상 가능) → 무시. 그 시각 이후에도 갱신되는 행은 아직 v0.2.10 인
  -- 다른 맥이 살아 쓰는 값이므로 그대로 살린다(한 대만 업그레이드한 과도기의 주력 맥 값 보존 — 위 주석 참조).
  -- 기기별 행이 아예 없는 사용자(업그레이드 전)는 first_at 이 null 이라 조건 없이 통과한다.
  --
  -- **조회 중인 달에 그 사용자의 기기 행이 있을 때만** 이 제외를 적용한다(d.uid is not null).
  --   화석 제외는 "정정된 기기 합산이 이미 있으니 과다계상된 옛 값을 쓰지 말자"는 규칙이다. 그런데 앱은
  --   **이번 달 기기 행만** 올리므로(현재 월 usage 만 upsert) 지난달에는 기기 행이 영원히 생기지 않는다.
  --   그 상태에서 first_at(= v0.2.11 로 올라온 시각, 달 무관 최솟값)만으로 걸러 버리면 지난달 옛 행은
  --   updated_at 이 언제나 그보다 과거라 전원 탈락해, ‹ 로 지난달을 보는 순간 업그레이드한 사용자가
  --   **자기 자신을 포함해** 순위판에서 통째로 사라진다(대체할 기기 합산이 없으니 merged 에 행이 아예 없다 →
  --   245행의 `or m.uid = auth.uid()` 자기 노출 보장도 무력).
  --   달에 기기 행이 없다는 것은 '더 정확한 값이 존재하지 않는다'는 뜻이므로, 그때는 옛 값이 유일한 기록이고
  --   그대로 보여주는 것이 맞다. 달이 바뀐 직후(1일, 아직 아무 맥도 안 올림)에도 같은 이유로 옛 행이 살아남아
  --   순위가 비지 않는다 — 달 무관 first_at 을 쓴 본래 의도(월초 널뛰기 방지)와도 일치한다.
  --
  -- **살아 있는 구버전 맥이 있으면**(legacy_live) 달을 가리지 않고 옛 행을 살린다.
  --   화석 판정의 근거는 "그 뒤로 아무도 갱신하지 않았다"인데, 지난 달 옛 행은 **누구도 다시 갱신할 수 없다**
  --   (앱은 언제나 현재 월만 올린다). 즉 지난 달에는 '갱신 끊김'이 그 달만 봐서는 화석의 증거가 되지 못하고,
  --   업그레이드가 일어난 그 달에는 기기 행이 남아 있어 위의 dm.uid 예외도 통하지 않는다. 그대로 두면
  --   맥 A(v0.2.10, 6월 200M) + 맥 B(6월 15일 업그레이드, 2M) 계정이 ‹ 로 6월을 볼 때 A 의 200M 이
  --   **영구히** 사라지고 2M 만 남는다. 그래서 판정의 증거를 그 달에 가두지 않고 계정 전체에서 찾는다 —
  --   A 가 아직 살아 있다면 어느 달이든 기기 합산을 넘는 옛 행을 계속 쓰고 있다(legacy_live). 그 증거가
  --   있으면 지난 달 옛 행도 그대로 '큰 쪽' 규칙에 태우고, A 가 몇 달을 쉬어도 다음 업로드 한 번으로 되살아난다.
  --
  --   회귀 지점(이 조건이 `p_month <> 이번 달` 이던 때): 지난 달을 **무조건** 살리는 규칙과 아래 7일 유예의
  --   창이 월말에 이어 붙어, 월말에 업그레이드한 계정에서는 화석 판정식이 평가되는 순간이 **영원히 없었다**.
  --   7/27 에 v0.2.11 로 올라오면 유예가 8/3 까지 가고, 유예가 끝나는 순간 7월은 이미 '지난 달'이라 다시 통과한다.
  --   v0.2.9 의 과다계상(+수십억)이 7월 순위판 1위에 영구히 박히고 앱에서 되돌릴 방법이 없었다
  --   (v0.2.11 클라는 옛 행이 자기 값보다 크면 쓰지 않으므로 자가정정도 일어나지 않는다).
  --
  -- **첫 기기 행 이후 7일은 유예**한다(now() - first_at <= 7 days 면 화석으로 보지 않는다).
  --   판정식이 `l.updated_at > f.first_at` 이라, 업그레이드 직후에는 first_at 이 방금 시각이어서 아직 v0.2.10 인
  --   다른 맥의 옛 행이 **무조건** 그보다 과거다 — 게다가 v0.2.11 클라는 옛 행이 자기 값보다 크면 옛 표를 아예
  --   쓰지 않으므로(앱: mayWriteLegacy), 보조 맥 B 의 첫 업로드 순간 항상 이 조건이 성립한다. 그 결과 위 과도기
  --   보증(주력 맥 A 의 200M 보존)이 성립하는 바로 그 경우에만 A 의 값이 통째로 탈락해 보드가 2M 으로 폭락했다.
  --   A 의 다음 업로드는 그 맥에서 **팝오버를 열어야** 일어나므로(주말·야간이면 며칠 뒤다) 즉시 복구되지도 않는다.
  --   유예 안에서는 옛 행을 살려 두고, 유예가 지나면 first_at 이 충분히 과거가 되어 살아 있는 맥이 이번 달에
  --   한 번이라도 올렸다면 updated_at > first_at 이 자연히 성립한다 — 그때부터 판정식이 제 뜻대로 동작한다.
  --   (대가: v0.2.9 를 건너뛰어 올라온 계정의 과다계상 잔재가 최대 7일 더 보일 수 있다. 남의 실제 사용량을
  --    100배 깎는 쪽보다 훨씬 가벼운 손해다.)
  legacy_totals as (
    select
      l.user_id as uid,
      l.claude_input::bigint as claude_input,
      l.claude_output::bigint as claude_output,
      l.claude_cache_read::bigint as claude_cache_read,
      l.claude_cache_creation::bigint as claude_cache_creation,
      l.codex_input::bigint as codex_input,
      l.codex_output::bigint as codex_output,
      l.total::bigint as total,
      (case
        when l.today_date = to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD')
        then l.today_total
        else 0
      end)::bigint as today_total
    from public.token_usage_monthly l
    left join device_first f on f.uid = l.user_id
    left join device_totals dm on dm.uid = l.user_id
    left join legacy_live lv on lv.uid = l.user_id
    where l.month = p_month
      and (
        dm.uid is null
        or f.first_at is null
        or l.updated_at > f.first_at
        or lv.uid is not null
        or now() - f.first_at <= interval '7 days'
      )
  ),
  -- 두 출처를 사용자별로 짝지어 총량이 큰 쪽을 통째로 고른다(필드가 뒤섞이지 않게 행 단위 선택).
  -- 한쪽만 있으면 그쪽을 쓴다: 기기 행만 있으면 합산, 옛 행만 있으면 폴백(=업그레이드 전 사용자).
  paired as (
    select
      coalesce(d.uid, g.uid) as uid,
      (d.uid is not null and coalesce(d.total, 0) >= coalesce(g.total, 0)) as prefer_device,
      d.claude_input as d_claude_input,
      d.claude_output as d_claude_output,
      d.claude_cache_read as d_claude_cache_read,
      d.claude_cache_creation as d_claude_cache_creation,
      d.codex_input as d_codex_input,
      d.codex_output as d_codex_output,
      d.total as d_total,
      d.today_total as d_today_total,
      g.claude_input as g_claude_input,
      g.claude_output as g_claude_output,
      g.claude_cache_read as g_claude_cache_read,
      g.claude_cache_creation as g_claude_cache_creation,
      g.codex_input as g_codex_input,
      g.codex_output as g_codex_output,
      g.total as g_total,
      g.today_total as g_today_total
    from device_totals d
    full outer join legacy_totals g on g.uid = d.uid
  ),
  merged as (
    select
      uid,
      coalesce(case when prefer_device then d_claude_input else g_claude_input end, 0)::bigint as claude_input,
      coalesce(case when prefer_device then d_claude_output else g_claude_output end, 0)::bigint as claude_output,
      coalesce(case when prefer_device then d_claude_cache_read else g_claude_cache_read end, 0)::bigint as claude_cache_read,
      coalesce(case when prefer_device then d_claude_cache_creation else g_claude_cache_creation end, 0)::bigint as claude_cache_creation,
      coalesce(case when prefer_device then d_codex_input else g_codex_input end, 0)::bigint as codex_input,
      coalesce(case when prefer_device then d_codex_output else g_codex_output end, 0)::bigint as codex_output,
      coalesce(case when prefer_device then d_total else g_total end, 0)::bigint as total,
      -- today 만은 행 단위 선택을 따르지 않고 두 출처의 '큰 쪽'을 쓴다.
      -- 월 총량은 같은 누적치가 두 표에 겹칠 수 있어 합·최댓값 중 최댓값을 골랐지만, today 는 두 출처 모두
      -- 이미 '서버 KST 오늘' 필터를 통과한 값이라 각각 참 오늘 총량 이하다 → greatest 로도 과다계상이 불가능하다.
      -- 행 단위로 따라가면 과도기(옛 표 총량이 큰 맥 A + 오늘 종일 쓴 맥 B)에 today 가 0 으로 떨어져
      -- '오늘 +0 토큰'이 며칠씩 표시된다. 큰 쪽을 쓰면 실제로 오늘 쓴 기기의 값이 살아남는다.
      greatest(coalesce(d_today_total, 0), coalesce(g_today_total, 0))::bigint as today_total
    from paired
  )
  select
    m.uid,
    coalesce(p.display_name, '사용자'),
    p.avatar_url,
    m.claude_input,
    m.claude_output,
    m.claude_cache_read,
    m.claude_cache_creation,
    m.codex_input,
    m.codex_output,
    m.total,
    m.today_total,
    to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD')
  from merged m
  join public.profiles p on p.id = m.uid
  where coalesce(p.token_usage_public, true) or m.uid = auth.uid()
  order by m.total desc, coalesce(p.display_name, '사용자');
$$;

-- 로그인한 앱 사용자 전용. anon 은 호출 불가(순위는 로그인 사용자만).
revoke all on function public.token_usage_board(text) from public;
grant execute on function public.token_usage_board(text) to authenticated;
