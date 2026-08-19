# 울트라 재화 경제 · 미션 · 초인종 — 서버 계약 (v0.2.34 / build 43)

이 문서는 **클라이언트가 의존해도 되는 응답 스키마**를 정의한다. 여기 적힌 것만 계약이다 —
적히지 않은 키는 언제든 사라질 수 있고, 적힌 키는 예고 없이 사라지지 않는다.

관련 마이그레이션 (적용 순서가 곧 이 순서다):

| 파일 | 만드는 것 | 기존 RPC 변경 |
|---|---|---|
| `20260819010000_ultra_wallet.sql` | 잔량 컬럼 2개 · `ultra_ledger` · 미션/스트릭 RPC · 감사 | 없음 |
| `20260819020000_poke_realtime_ring.sql` | `poke_topic` · realtime 정책 · `poke_ring` · 킬스위치 | 없음 |
| `20260819030000_poke_economy_and_ring.sql` | `poke_user` / `send_message` / `ultra_poke_user` 재작성 1회 + `shares_team` drop | **있음** |
| `20260820040000_ultra_unlimited_flag.sql` | `ultra_wallet_sync` 에 `unlimited` 키 1개 추가(운영자 표시 전용, 본문 3줄) | 없음 |

---

## 1. 경제 규칙 (사장님 확정)

| 규칙 | 값 | 서버의 단일 출처 |
|---|---|---|
| 하루 밑바닥 (새 버전) | **1** | `ultra_daily_floor(app_build)`, `app_build >= 43` |
| 하루 밑바닥 (구버전) | **2** | `ultra_daily_floor(app_build)`, `app_build < 43` 또는 null |
| 잔량 상한 | **5** | `ultra_balance_cap()` |
| 미션 1호 목표 | 그날 누적 근무 **3시간** | `mission_work_seconds()` = 10800 |
| 미션 보상 | +1 (미션·날짜당 1회) | `ultra_ledger` 의 `unique (user_id, kst_day, reason) where delta > 0` |
| 연속 출근 스트릭 | **표시만. 보상 없음** | `ultra_wallet_sync` 는 스트릭으로 어떤 적립도 하지 않는다 |
| 울트라 발사 비용 | 1 | `ultra_poke_user` |
| 같은 대상 쿨타임 | 60초 (거절은 몫을 안 태운다) | 세 RPC 공통 |

**밑바닥은 보정이지 적립이 아니다.** `balance = max(balance, floor)` 이므로 잔량 3인 사람은 다음날에도 3이고,
열흘 잠수한 사람도 복귀 시 딱 밑바닥까지만 올라온다(도장 `profiles.ultra_floor_day` 가 하나라 산술적 보장).

**구버전 유예 — 왜 밑바닥이 갈리는가.** 구버전(build < 43)은 `ultra_wallet_sync` 를 부르는 코드가 없어
미션을 **볼 수도 쓸 수도 없다**. 게다가 v0.2.30 의 `CheckMenuView.swift:2590` 이
`if canUltra { onUltra() } else { onUltraBlocked() }` 라, 서버가 한 번 "소진"이라 답하면 그날 내내
서버에 다시 묻지 않는다. 그런 사람에게 밑바닥 1을 주면 **하루 한 발**로 조용히 열화된다.
그래서 구버전에게는 지금과 같은 2를 준다.
▸ **회수 시점**: `select count(*) from public.profiles where coalesce(app_build,0) < 43` 이 **0**이 되면
`ultra_daily_floor` 를 상수 1로 되돌린다. (2026-08-19 실측: 38명 중 25명이 구버전)

**잔량은 클라가 직접 못 읽는다.** `profiles.ultra_balance` 에는 select grant 가 없다 —
직접 읽으면 밑바닥 보정 **전** 값이 보이기 때문이다. 잔량은 반드시 아래 RPC 를 거친다.

---

## 2. `ultra_wallet_sync(p_days_back int default 1) → jsonb`

`POST /rest/v1/rpc/ultra_wallet_sync`, body `{"p_days_back": 1}`.
실행권: **authenticated 만**. anon 불가.

호출 시점은 결과를 바꾸지 않는다 — 누적은 단조증가라 임계를 하루 한 번만 넘고 청구는 멱등하다.
`p_days_back` 는 0~7 로 서버가 조인다. 기본 1은 **오늘과 어제** 두 날을 평가한다
(근무만 하고 앱을 끈 사용자의 어제 몫이 영구 소실되지 않게).

### 성공 응답

```json
{
  "status": "ok",
  "balance": 3,
  "balance_cap": 5,
  "daily_floor": 1,
  "day": "2026-08-19",
  "floor_applied": true,
  "missions": [
    { "key": "work3h", "kst_day": "2026-08-19", "target_seconds": 10800,
      "progress_seconds": 14400, "claimed": true, "granted_now": true, "capped": false },
    { "key": "work3h", "kst_day": "2026-08-18", "target_seconds": 10800,
      "progress_seconds": 14400, "claimed": true, "granted_now": false, "capped": false }
  ],
  "worked_seconds_closed": 14400,
  "worked_seconds_open": 0,
  "streak_days": 3,
  "streak_includes_today": true,
  "unlimited": false,
  "measured_at": 1787098516
}
```

| 키 | 타입 | 뜻 | null 가능 |
|---|---|---|---|
| `status` | string | `"ok"` \| `"invalid"` | 아니오 |
| `balance` | int | 이 호출 **직후**의 잔량(밑바닥 보정·미션 적립이 이미 반영됨) | 아니오 |
| `balance_cap` | int | 상한(현재 5). UI 가 리터럴 5를 박지 말 것 | 아니오 |
| `daily_floor` | int | 이 사용자의 하루 밑바닥(1 또는 2). 진단용 | 아니오 |
| `day` | string | `YYYY-MM-DD` (KST) | 아니오 |
| `floor_applied` | bool | 이번 호출에서 밑바닥 보정이 **실제로 잔량을 올렸는가** | 아니오 |
| `missions` | array | 아래 표. 배열 순서는 **최신 날짜 우선** | 아니오(빈 배열은 안 나옴) |
| `worked_seconds_closed` | int | **오늘** 닫힌 세션의 합(초) | 아니오 |
| `worked_seconds_open` | int | **오늘** 열린 세션의 진행분(초) | 아니오 |
| `streak_days` | int | 연속 출근 일수. **표시 전용 — 보상 없음** | 아니오 |
| `streak_includes_today` | bool | 오늘 출근이 스트릭에 포함됐는가 | 아니오 |
| `unlimited` | bool | **잔량 제한을 받지 않는가**(운영자 `profiles.role='admin'`). 참이면 화면은 숫자 대신 무제한을 표시한다. 판정은 `ultra_poke_user` 가 발사 게이트에서 쓰는 술어와 **문자 그대로 같다** — 두 곳이 갈리면 화면과 실제가 어긋난다. **표시 전용이다**: 적립·차감 산식에 쓰지 마라 | **예**(20260820040000 이전 서버) |
| `measured_at` | int | 서버 측정 시각(epoch 초) | 아니오 |

`status == "invalid"` 이면 **`status` 외의 키는 없다**(비로그인 또는 프로필 없음).
디코딩 타입은 `status` 를 먼저 읽고 분기해야 한다.

### `missions[]` 원소

| 키 | 타입 | 뜻 |
|---|---|---|
| `key` | string | 현재 `"work3h"` 하나. 미래에 늘어날 수 있으니 **모르는 key 는 무시**할 것 |
| `kst_day` | string | `YYYY-MM-DD`. 이 행이 평가한 날 |
| `target_seconds` | int | 목표(10800) |
| `progress_seconds` | int | 그날 서버가 잰 누적 근무초(닫힌 + 열린) |
| `claimed` | bool | 그날 몫을 **이미 받았다** |
| `granted_now` | bool | **이번 호출에서** 받았다 → 연출(`.ultraCharged`)의 트리거 |
| `capped` | bool | 달성했지만 **잔량이 가득 차서 적립하지 않았다** |

**`capped` 의 정확한 의미가 중요하다.** 상한에서 미션을 달성하면 서버는
**장부를 쓰지 않고 잔량도 안 올린다**(장부만 쓰면 감사가 영구 드리프트를 내고, 잔량만 올리면 상한이 뚫린다).
그래서 `claimed` 는 **false 로 남는다**. 결과적으로 그날 중에 울트라를 한 발 쓰고 다시 sync 하면
**그때 받는다.** UI 는 이 행에 "가득 차서 오늘은 못 받아요"를 그린다.

상태 조합표:

| `claimed` | `granted_now` | `capped` | 화면 |
|---|---|---|---|
| false | false | false | 진행 중 (`progress/target`) |
| true | true | false | **방금 받았다** → 연출 + "오늘 3시간 — 울트라 +1" |
| true | false | false | 오늘 몫 이미 받음 |
| false | false | **true** | **"가득 차서 오늘은 못 받아요"** |

### 측정 규칙 (신고 대응 시 이걸 본다)

* 그날 몫만 센다: 시작점 `max(started_at, 그날 00:00 KST)`, 끝점 `min(…, 그날 24:00 KST, now())`.
* **열린 세션의 진행분을 포함한다.** 안 그러면 '누적 3시간'이 아니라 '종료 3시간'이 된다.
* 단, **10분 무신호**면 `last_seen_at` 으로 끝을 자른다 — 맥을 꺼 둔 유령 세션이 3시간을 채우지 못한다.
  (이 10분은 `close_abandoned_work_sessions` 의 마감 규약과 문자 그대로 같은 값이다.
   30초 하트비트 지연으로 상시 손실이 나지 않게 무조건 클램프하지 **않는다**.)
* 스트릭의 하루 귀속은 **`started_at` 의 KST 날짜**다. 앵커는 오늘 근무가 있으면 오늘, 없으면 어제.

### 오류

* RPC 자체가 없으면 PostgREST 가 **PGRST202** 를 낸다 → 클라는 `takePokes` 와 같은 관용구로
  전용 오류(`.ultraWalletUnavailable`)로 접어 "서버 미배포"로 진단할 것. 재던지지 말 것.

---

## 3. `ultra_poke_user(p_to uuid) → jsonb`

게이트 순서는 **불변**이다(이 순서가 계약이다):

```
invalid → not_working → target_not_working → target_focused → 관리자 → [재화] → cooldown → 발사
```

### 상태 어휘 — **정확히 이 7개. 넓히지 않는다.**

`ok` · `invalid` · `not_working` · `target_not_working` · `target_focused` · `ultra_used_today` · `cooldown`

(마이그레이션의 사후 단언이 이 집합을 정규식으로 뽑아 비교한다. 하나라도 늘어나면 배포가 멈춘다 —
구버전이 모르는 값을 받으면 조용히 접어 오배달을 만들기 때문이다.)

| status | 함께 오는 키 |
|---|---|
| `ok` (일반) | `ultra_remaining` int, `ultra_balance` int, `ring` string |
| `ok` (관리자) | `ultra_remaining` int, `ultra_balance` int, `unlimited` **true**, `ring` string |
| `ultra_used_today` | `ultra_remaining` 0, `ultra_balance` 0, `reset_after_seconds` int |
| `cooldown` | `retry_after_seconds` int, `ultra_balance` int |
| `invalid` / `not_working` / `target_not_working` / `target_focused` | 없음 |

**`ultra_remaining` 의 의미가 바뀌었다.** 예전엔 "오늘 남은 횟수", 이제는 **잔량**이다.
값의 해석이 바뀌었을 뿐 구버전 표시는 여전히 참이다(잔량 2면 실제로 2발 쏠 수 있다).
신버전은 `ultra_balance` 를 쓰고, 없으면 `ultra_remaining` 으로 폴백할 것:
`ultraBalanceForDisplay = (ultraBalance ?? ultraRemaining).map { max(0, $0) }`.

**관리자는 재화를 쓰지 않는다.** 응답의 숫자는 `greatest(실제잔량, 1)` 이다 —
0을 실어 보내면 구버전이 버튼을 잠그기 때문이다(20260817130000 이 세운 예외를 승계).

**거절은 몫을 태우지 않는다.** `cooldown` 은 잔량 차감 **전**에 반환된다.

---

## 4. `poke_user(p_to uuid)` / `send_message(p_to uuid, p_body text)`

**본문 로직은 한 글자도 안 바뀌었다.** 더해진 것은 응답의 `ring` 키 하나뿐이다.

```json
{"status":"ok","ring":"sent"}                     // poke_user
{"status":"ok","body":"하","ring":"sent"}          // send_message
```

`ring` 은 `ok` 일 때만 온다. `poke_user` 의 상태 어휘(`ok`/`invalid`/`not_working`/
`target_not_working`/`target_focused`/`cooldown`)와 `send_message` 의 어휘
(+ `not_text`/`too_long`, 둘 다 `max_length` 동반)는 **불변**이다.

---

## 5. 초인종 (Realtime Broadcast)

### 채널

* 채널명 = `poke:<수신자 uuid>` — 서버의 `public.poke_topic(uuid)` 와 **문자 그대로 같은 문자열**.
* Phoenix wire 의 `topic` 필드는 `realtime:poke:<uuid>` 이고, RLS 가 보는 `realtime.topic()` 은
  접두사를 뗀 `poke:<uuid>` 다. **둘은 같은 것의 두 표현이다.**
* 채널은 반드시 **private** 이다(`config.private = true`). 빠뜨리면 조인이 그냥 성공하고
  RLS 가 아예 상담되지 않는다 = 인가 실패 분기가 죽은 코드가 된다.
* 구독은 **SELECT 만** 허용된다. INSERT 정책은 만들지 않았다 — 클라가 초인종을 울릴 수 없다.

### 이벤트

이벤트 이름은 **언제나 `ring` 하나**다. 종류별로 나누지 않는다.

```json
{ "v": 1, "at": 1787099321, "pending": 2,
  "rid": "5b54c77b-…", "id": "4bdbb4c8-…" }
```

| 키 | 뜻 |
|---|---|
| `v` | 페이로드 버전. 지금 `1`. 모르는 버전이면 그냥 `take_pokes` 를 부를 것 |
| `at` | 발신 시각(epoch 초). 클라가 링 지연을 실측한다 |
| `pending` | 그 순간 **미소비 개수**. `take_pokes` 와 **같은 술어**로 센다(5분 창 밖 메시지 제외) |
| `rid` | 서버 자기검증용. 클라는 무시해도 된다 |
| `id` | `realtime.send` 가 스스로 넣는 메시지 id. 계약이 아니다 — **의존하지 말 것** |

**페이로드에 내용이 없는 것이 설계다.** `kind`/`body`/보낸이/poke id 는 **절대 실리지 않는다**.
담는 순간 `take_pokes` 의 두 규칙(5분 배달 창 · 원자적 소비)을 통째로 우회한다.
초인종은 "너에게 뭔가 있다"만 말하고, **무엇인지는 반드시 `take_pokes` 가 정한다.**

`pending` 이 이어지는 `take_pokes` 결과 수와 다르면 소비 경로 문제,
`at` 과 수신 시각의 차가 크면 전송 지연이다.

### `ring` 값의 의미 (진단의 핵심)

| 관측 | 뜻 |
|---|---|
| `"sent"` | `realtime.messages` 에 실제로 썼다(같은 트랜잭션에서 rid 로 되읽어 확인) |
| `"failed"` | `realtime.send` 가 삼켰다. **킬스위치가 내려가 있어 찌르기는 정상 진행**됐다 |
| HTTP 400 + `poke_ring_failed:` (P0001) | 킬스위치가 올라간 상태에서 삼켰다 → **찌르기 자체가 롤백**(코인 안 탐) |

`realtime.send` 는 내부에서 **모든 예외를 `RAISE WARNING` 으로 삼킨다**(프로덕션 정의 실측).
그래서 "예외가 안 났으니 갔겠지"는 성립하지 않고, rid 되읽기만이 삼킴을 검출한다.

### ★ 출시 시점의 상태 — **초인종은 꺼진 채로 나간다**

`poke_ring_strict()` 의 출시 기본값은 **false(삼킴)** 다. 이유 두 가지 모두 실측이다:

1. **`realtime.messages` 에 파티션이 0개다.** 이 프로젝트는 Realtime 을 한 번도 쓴 적이 없어
   파티션을 만드는 Realtime 서비스 작업이 아직 돈 적이 없다. 지금 `realtime.send` 를 부르면
   INSERT 가 실패하고 warning 으로 삼켜진다 → `ring` 은 `"failed"` 가 된다.
2. **정책 생성이 실패할 수 있다.** `realtime.messages` 의 소유자는 `supabase_realtime_admin` 이고
   `postgres` 는 그 롤의 멤버가 아니다(`pg_has_role(...)= false`). `CREATE POLICY` 는 소유자만 할 수 있다.
   실패하면 마이그레이션은 **경고만 남기고 계속 진행한다** — 나머지 6개 기능을 살리기 위해서다.

그래서 **v0.2.34 는 폴링을 유지한 채 나간다.** 리얼타임 코드는 킬스위치가 꺼진 채로도
나머지가 온전히 동작해야 한다.

### 켜는 절차 (v0.2.35)

```sql
-- ① 준비도 점검 (service_role)
select public.poke_ring_readiness();
--    {"policy_present":true,"partitions":3,"write_and_readback":true,
--     "strict":false,"ready_for_strict":true,"hint":"…"}

-- ② policy_present 가 false 라면 대시보드 SQL 에디터(더 높은 권한)에서:
create policy "users listen to their own poke channel"
  on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast'
         and realtime.topic() = public.poke_topic((select auth.uid())));

-- ③ 두 프로세스 e2e 프로브(맥 두 대)로 **실제 배달**을 확인한 뒤에만:
create or replace function public.poke_ring_strict()
returns boolean language sql immutable as $$ select true $$;
```

②③ 없이 ③만 올리면 **찌르기·메시지·울트라가 전부 400 으로 죽는다.**
(마이그레이션을 다시 돌리면 사후 단언이 그 상태를 잡아 배포를 멈춘다.)

---

## 6. 운영자 진단 (service_role 전용)

| 함수 | 언제 |
|---|---|
| `ultra_wallet_audit()` | "잔량 숫자를 믿어도 되나". **빈 결과 = 잔량과 장부가 한 글자도 안 갈렸다** |
| `unconsumed_poke_age()` | "울렸다는데 아무도 안 가져갔다". `fresh`/`stale`/`dead` 버킷별 미소비 개수 |
| `poke_ring_readiness()` | strict 로 올리기 전 필수. 정책·파티션·실제 쓰기/되읽기를 한 번에 |

`ultra_ledger` 는 append-only 장부다. 미션 적립 행의 `detail.seconds` 에 **그 순간의 측정값**이
박혀 있어 "3시간 일했는데 코인이 안 늘었다"를 사후에 판정할 수 있다.

```sql
select kst_day, reason, delta, balance_after, detail
  from public.ultra_ledger where user_id = '<uid>'
 order by created_at desc limit 20;
```

### 신고가 들어오면 이 순서로 가른다

1. **제보자 빌드부터**: `select id, app_build from public.profiles where email = '<제보자>'`.
   `app_build < 43` 이면 구버전이고 미션도 리얼타임도 없다 — 여기서 끝난다
   (팀 무제한 상실로 두 번째 발사가 거절된 것이 원인일 가능성이 가장 높다).
2. **서버가 배포됐는가**: `select to_regprocedure('public.ultra_wallet_sync(int)'),
   to_regprocedure('public.poke_ring(uuid)'), to_regprocedure('public.shares_team(uuid,uuid)')`.
   앞 둘이 null = 마이그레이션 미적용. `shares_team` 이 **살아 있으면** 파일 3이 안 돌았다.
3. **재화인가 미션인가**: `ultra_wallet_sync()` 한 번.
   `balance=0` + `claimed=true` → 정상(오늘 몫 다 씀).
   `claimed=false` + `progress < target` → 측정 문제(4번).
   `claimed=true` 인데 잔량이 안 늘었다 → 적립 경로 버그(`ultra_ledger` + `ultra_wallet_audit()`).
   `capped=true` → 가득 찬 것이다. 정상.
4. **측정이 왜 모자란가**: 같은 응답의 `worked_seconds_open` 이 0인데 근무 중이면
   하트비트/`last_seen_at` 문제다(10분을 넘겼으면 서버가 안 세는 것이 맞다 — 맥 시계 어긋남 포함).
5. **초인종**: 발사 응답의 `ring` 값 → `sent`/`failed`/HTTP 400. 그리고
   `select topic, inserted_at, payload from realtime.messages where topic = 'poke:<수신 uid>'`.
6. **그래도 못 가르면**: `poke_ring_strict()` 를 false 로 내리고 `ring` 값 분포를 하루 모은다.
   `failed` 로 치우치면 realtime 인프라 문제, `sent` 인데 신고가 계속되면 배달/클라 문제다.

---

## 7. 구버전(v0.2.33 이하) 영향 — 브루 배포라 수 주 생존한다

| 항목 | 벌어지는 일 | 판정 |
|---|---|---|
| RPC 시그니처 | `ultra_poke_user(p_to)` / `take_pokes()` / `take_pokes(bool)` 전부 그대로. 새 오버로드 0개 | 무해 |
| 응답 키 추가 | `ultra_balance` · `ring` · `unlimited`. Swift Decodable 은 모르는 키를 무시 | 무해 |
| 상태 어휘 | 넓히지 않는다(사후 단언이 강제) | 무해 |
| `ultra_remaining` 해석 | "오늘 남은 횟수" → "잔량". 구버전 표시는 여전히 참 | 허용 |
| 하루 몫 | 밑바닥 2라 지금과 같다 | **열화 없음** |
| "하루에 2번까지예요" 문구 | 구버전에겐 여전히 사실상 참(밑바닥 2) | 허용 |
| 팀 무제한 | 사라진다. 팀원에게도 잔량을 쓴다 | **의도된 변경** |
| 폴링 | 서버는 폴링 경로를 하나도 없애지 않았다. 15초 폴링 그대로 동작 | 무해 |
| 초인종 | 구버전은 채널을 구독하지 않는다 → 링은 그냥 버려진다(발신은 안 막힌다) | 무해 |

---

## 8. 알려진 한계 (정직하게 적어 둔다)

* **미션 3시간은 위조 가능하다.** `work_sessions.started_at/ended_at` 을 클라가 보내는 기존 P0 가
  그대로다. 노출 수준은 기존과 동일하고(클라 판정보다는 엄격하다), 위조해도 얻는 것은 하루 +1 이다.
  `ultra_ledger.detail.seconds` 에 판정 근거가 남으므로 이상 패턴은 사후에 잡을 수 있다.
* **겹치는 세션은 이중 계산된다.** 리그 RPC(20260712010000)와 같은 성질이다 — 새 산식을 만들지 않고
  이미 검증된 산식을 재사용한 결과다.
* **`ultra_ledger` 는 무한히 자란다**(38명 × 하루 ~3행 = 연 4만 행). 청소 크론이 없다.
  필요해지면 `cleanup_old_pokes`(20260724020000) 패턴으로 180일 이전 `spend` 행만 지운다
  (`floor`/`mission` 행은 감사 증거라 남긴다).
* **상한에서 놓친 어제 몫은 이틀 뒤 사라진다.** `p_days_back` 기본이 1이라 오늘과 어제만 본다.
  잔량이 가득 찬 사람에게만 해당하므로 손해는 실질적으로 0이다.
