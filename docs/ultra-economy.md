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
| `20260901120000_admin_ultra_ledger.sql` | 없음(표·컬럼 0개) | **있음** — `ultra_poke_user` 관리자 분기가 장부에 `delta 0` 을 적는다 |
| `20260901130000_ultra_lap_economy.sql` | 없음(표·컬럼 0개) | **있음** — 상한 5→3 · `ultra_wallet_sync` 가 3시간 **마다** 지급하고 가득 참은 영구 소멸 |
| `20260901140000_ultra_capped_persistent.sql` | 없음 | **있음** — `capped` 를 순간 신호에서 **상태**(잔량 ≥ 상한)로 |
| `20260903190000_ultra_pending_lap.sql` | `profiles` 퀘스트 상태 3컬럼(grant 없음) | **있음** — 가득 찼을 때의 달성이 **소멸에서 대기**로. `missions[].pending` 키 추가 |

---

## 1. 경제 규칙 (사장님 확정)

| 규칙 | 값 | 서버의 단일 출처 |
|---|---|---|
| 하루 밑바닥 (새 버전) | **1** | `ultra_daily_floor(app_build)`, `app_build >= 43` |
| 하루 밑바닥 (구버전) | **2** | `ultra_daily_floor(app_build)`, `app_build < 43` 또는 null |
| 잔량 상한 | **3** | `ultra_balance_cap()` (2026-09-01 에 5→3) |
| 미션 1호 목표 | 그날 누적 근무 **3시간마다**(3·6·9…) | `mission_work_seconds()` = 10800 |
| 미션 보상 | 랩당 +1 (**랩·날짜당 1회**) | `ultra_ledger` 의 `unique (user_id, kst_day, reason) where delta > 0` |
| 가득 찼을 때 달성 | **대기**(2026-09-04 확정. 최대 1개 · 카운터 정지 · 지급 시점부터 재시작) | `profiles.ultra_quest_pending` |
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
  "balance_cap": 3,
  "daily_floor": 1,
  "day": "2026-09-01",
  "floor_applied": true,
  "missions": [
    { "key": "work3h", "kst_day": "2026-09-01", "target_seconds": 10800,
      "progress_seconds": 3600, "claimed": false, "granted_now": true, "capped": true,
      "pending": false, "laps_settled": 2, "laps_granted": 2, "worked_seconds": 25200 },
    { "key": "work3h", "kst_day": "2026-08-31", "target_seconds": 10800,
      "progress_seconds": 0, "claimed": false, "granted_now": false, "capped": true,
      "pending": false, "laps_settled": 1, "laps_granted": 1, "worked_seconds": 10900 }
  ],
  "worked_seconds_closed": 25200,
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
| `balance_cap` | int | 상한(현재 **3**. 2026-09-01 에 5→3). UI 가 리터럴을 박지 말 것 | 아니오 |
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
| `progress_seconds` | int | **현재 랩의 진행**(0…`target_seconds`). 랩마다 0 으로 되감긴다 — 그날 총합은 `worked_seconds` |
| `claimed` | bool | **언제나 false**(랩이 반복되므로 완료 상태가 없다). 옛 의미: 그날 몫을 이미 받았다 |
| `granted_now` | bool | **이번 호출에서** 한 랩 이상 받았다 → 연출(`.ultraCharged`)의 트리거 |
| `capped` | bool | **지금 잔량이 상한 이상이다**(상태. 아직 아무것도 못 채운 사람에게도 참) |
| `pending` | bool | **3시간을 채워 두고 기다리는 중**(오늘 행에서만 참). 하나 쓰면 다음 sync 가 지급한다 |
| `laps_settled` | int | 그날 **지급된** 랩 수(= `laps_granted`). 소멸 폐지 후 두 값은 언제나 같고, 구서버 응답에서만 갈린다 |
| `laps_granted` | int | 그날 실제로 받은 랩 수. **더해진 진단 키** |
| `worked_seconds` | int | 그날 총 근무초(= 옛 `progress_seconds`). **더해진 진단 키** |

**★ 2026-09-01 에 랩(lap) 방식으로 바뀌었다.** 미션은 하루 1회가 아니라 **그날 누적 3시간마다** 성립한다.
랩 N 의 장부 `reason` 은 랩 1이 `mission:work3h`, 랩 2 이상이 `mission:work3h#N` 이다.

> ⚠️ **랩 1의 reason 을 바꾸지 마라.** 바꾸는 순간 어제 이미 받은 사람의 행이 "없는 것"으로 보여
> `p_days_back=1` 이 어제 몫을 **한 번 더 지급한다**(전원에게 1회씩). 마이그레이션의 소스 단언이
> 이 리터럴을 되묻어 배포를 멈춘다.

**`capped` 는 "지금 가득 차 있다"는 상태다**(20260901140000). 처음엔 "이번 호출에서 랩이 소멸했다"는
순간 신호였는데, 그러면 가득 찬 사람이 3시간을 채우는 그 한 번의 sync 에서만 참이고 5분 뒤엔 사라져
**정작 계속 잃는 사람이 왜 잃는지 모른다**. 지금은 잔량 기준(`v_bal >= v_cap`)이라 가득 찬 동안
계속 참이고, 잔량이 상한 밑으로 내려가면 사라진다.
클라 문구(v0.2.41): `"가득 찼어요 — 3시간을 채워도 대기해요"`.

### ★ 가득 찼을 때의 달성은 **대기**한다 (2026-09-04, 20260903190000)

사장님 지시: *"다 차 있는 상태인데 달성하면 달성한 상태 그대로 유지하다가, 소모하면 퀘스트를 달성한
걸로 하고 지급하고 다시 3시간을 돌게끔."* 정정: **대기는 최대 1개**다 —
*"꽉 찬 상태를 계속 대기해주면서 시간을 계속 카운트하면 최대 보유 횟수를 3회로 제한한 이유가 없잖아"*.

규칙 셋:

1. 3시간을 채웠는데 잔량이 상한이면 퀘스트가 **얼어붙는다**. 진행도는 100%(`progress_seconds == target`)로
   멈추고 **그 뒤의 근무 시간은 다음 랩으로 쌓이지 않는다.**
2. 울트라를 하나 써서 잔량이 상한 밑으로 내려가면 **다음 sync 가 그 한 개를 지급**하고, 진행도는
   **지급 시점부터 0** 이다(대기 중 흘려보낸 시간은 이월되지 않는다 — 그것이 상한의 존재 이유다).
   장부 행의 `detail.pending_paid = true` 가 이 경로를 감사에서 구분한다.
3. 대기는 **동시에 1개**를 넘지 않는다(그래서 상태가 boolean 이다).

이걸 위해 `public.profiles` 에 상태 3개가 생겼다. **grant 가 하나도 없다** — 클라는 읽지도 쓰지도 못하고
security definer RPC 만 만진다(그게 위조 방어이고, 컬럼 단위로 잠긴 이 표의 규약이다).

| 컬럼 | 뜻 |
|---|---|
| `ultra_quest_day` | 아래 baseline 이 속한 KST 날짜. **sync 가 끝나면 언제나 오늘** |
| `ultra_quest_base_sec` | 그날 누적 근무초 중 **현재 퀘스트가 시작한 지점** |
| `ultra_quest_pending` | 3시간을 채웠지만 가득 차서 대기 중 |

불변식: ① 대기 중이면 진행도는 언제나 `target` 이고 baseline 은 전진하지 않는다.
② baseline 은 **지급이 일어난 sync 에서만** 움직인다(정상 지급 `+= target` — 남은 시간은 이월된다,
대기 지급 `:= 그 시점의 오늘 누적초` — 이월하지 않는다). ③ sync 후 `ultra_quest_day` 는 오늘이다.

**날짜 롤오버**: 앱이 꺼진 채 자정을 넘겨 어제 퀘스트를 채우고도 평가받지 못한 사람에게는
**어제 날짜 키로 딱 1개**를 따라잡아 준다. 단 **대기가 서 있었다면 따라잡지 않는다** — 대기 플래그와
따라잡기는 같은 하나의 랩을 가리키므로, 둘 다 주면 하나를 두 번 지급하게 된다.
그때 잔량이 이미 상한이면 **버리지 않고 대기로 넘긴다**. 여기서만 버리면 같은 근무·같은 잔량인데
"앱을 켜 두었으면 대기, 꺼 두었으면 소멸"로 갈린다.

따라잡기는 `ultra_quest_day` 가 **어제이거나, null 이거나, 어제보다 오래된** 모든 경우에 돈다
(구정의는 어제를 매 호출 재평가했다 — 그 그물을 좁히면 배포 당일 전원의 어제 몫이 사라진다).
그때 어제의 기준선은 상태가 정확히 어제면 그 baseline, 아니면 **어제 이미 지급된 랩 수 × target** 이다.

**장부 `reason` 슬롯은 그날 이미 쓰인 최대 랩 번호 + 1 이다**(그날 지급 **개수** + 1 이 아니다).
소멸 행을 지우면 장부 가운데에 구멍이 남는데(예: `[work3h(삭제), #2(지급)]`), 개수 + 1 은 `#2` 를
내놓아 이미 쓰인 자리와 부딪힌다. 그러면 `on conflict do nothing` 이 삽입을 삼켜 지급이 없던 일이 되고
`ultra_quest_pending` 이 참인 채 굳는다 — 화면은 계속 "하나 쓰면 받아요"라고 말하는데 이미 썼고
들어오지 않는다. 두 숫자(개수·최대 번호)는 `public.ultra_work3h_laps(uuid, date)` 한 곳에서만 만든다.

**배포 당일**: `ultra_quest_day` 가 null 인 사람의 첫 sync 는 baseline 을
**오늘 이미 지급된 랩 수 × target** 으로 잡는다(0 이 아니다). 0 으로 잡으면 오늘 이미 받고 소비까지
끝낸 랩을 같은 근무로 다시 준다. 이 값이 장부에서 오므로, **소멸로 파괴됐던 랩만** 복구되고
이미 받은 랩은 재평가되지 않는다(그 복구가 아래 "소멸은 폐지됐다"의 일회성 삭제가 노린 것이다).
잔량 상한이 그 위를 한 번 더 잠근다.

**소멸은 폐지됐다.** 직전 판(2026-09-01)은 가득 찬 상태의 랩을 `delta 0 · detail.capped=true` 행으로
못 박아 영구 소멸시켰다. 새 규칙에서 그 행은 대기해야 할 랩을 '정산됨'으로 붙잡으므로, 함수에서 그
insert 를 없애고 **오늘·어제 KST 의 그 행만** 일회성으로 지웠다(그보다 과거는 그 시점의 규칙대로 벌어진
역사라 보존한다). `delta` 가 0 이라 `ultra_wallet_audit()` 합계에는 영향이 없다.

**`claimed` 는 이제 언제나 `false` 다.** 랩이 반복되므로 "오늘 몫 끝"이라는 상태가 존재하지 않는다.
구버전(build 43~47)은 `claimed=false` 일 때 보상 칩(⚡︎ +1)과 진행 바를 그리는데, 그것이 정확히
우리가 원하는 화면이다. `claimed` 와 `capped` 는 여전히 **동시에 참일 수 없다**(클라 계약).

**`progress_seconds` 는 그날 총합이 아니라 `현재 랩의 진행`(0…target)이다.** 랩을 하나 정산할 때마다
0 으로 되감긴다 — 구버전이 이 값 하나로 진행 바를 그리므로, 되감아야 "다음 하나까지"가 보인다.
그날 총합이 필요하면 응답 최상위의 `worked_seconds_closed + worked_seconds_open` 을 쓸 것.

상태 조합표:

| `claimed` | `granted_now` | `capped` | `pending` | 화면 |
|---|---|---|---|---|
| false | false | false | false | 진행 중 (`progress/target` — **다음 하나까지**) |
| false | **true** | false | false | **방금 받았다** → 연출 + "3시간 채웠어요 — 울트라 +1" |
| false | false | **true** | false | **"가득 찼어요 — 3시간을 채워도 대기해요"**(잔량 ≥ 상한, 아직 못 채움) |
| false | false | **true** | **true** | **"대기 중" 칩 + "3시간 채웠어요 — 하나 쓰면 받아요"**. 진행 바 100% |
| false | **true** | **true** | false | 받자마자 가득 찼다 — 연출과 경고가 함께 뜬다(정상) |
| — | — | false | **true** | **나오지 않는다**(대기하려면 잔량이 가득 차 있어야 한다) |
| true | — | — | — | **이제 나오지 않는다** |

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

**단, 발사 사실은 장부에 남는다**(20260901120000). 재화를 안 썼으니 `delta` 는 **0** 이고,
`detail` 에 `{"unlimited": true}` 가 박혀 유료 차감(-1)과 한눈에 갈린다. `delta 0` 인 것이 계약이다:
`ultra_wallet_audit()` 은 delta 를 합산하므로 0 은 드리프트를 만들지 않고,
`ultra_ledger_grant_once` 는 `where delta > 0` 부분 인덱스라 0 은 색인되지 않아
**같은 날 여러 발**이 유니크 충돌 없이 남는다(관리자는 하루 한도가 없으므로 필수 조건이다).
`balance_after` 는 응답용 `greatest(_,1)` 이 아니라 실제 잔량이고, 관리자 분기는
`ultra_wallet_touch` 보다 앞이므로 그 값은 **밑바닥 보정 전** 값이다.

> 왜 뒤늦게 넣었나 — 2026-09-01 실측에서 7일간 울트라 79발 중 **38발이 관리자 발사였고 장부에는 0줄**이었다.
> `pokes` 는 7일 보존(`cleanup_old_pokes`)이라 그 뒤엔 흔적이 사라진다. 감사 도구에 구멍이 하나 있으면
> 그 도구 전체를 못 믿는다. **이 파일 이전의 관리자 발사는 소급 복원하지 않는다** — 원천이 없고,
> 없는 것을 지어내면 장부가 감사 증거이기를 그만둔다.

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

**울트라 발사 전건**(관리자 포함, 20260901120000 이후). 누가 누구에게 몇 발 쐈는지는 이 한 줄이 원천이다 —
`pokes` 와 달리 장부는 지워지지 않는다:

```sql
select l.created_at, p.display_name as 보낸이, l.delta,
       coalesce(l.detail->>'unlimited', 'false') as 무제한,
       (select display_name from public.profiles where id = (l.detail->>'to')::uuid) as 받은이
  from public.ultra_ledger l join public.profiles p on p.id = l.user_id
 where l.reason = 'spend:ultra'
 order by l.created_at desc limit 50;
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
   `pending=true` → 3시간을 채워 두고 **대기 중**이다. 하나 쓰면 다음 sync 에 들어온다. 정상.
   `capped=true` + `pending=false` → 가득 찼고 아직 이번 랩을 못 채운 것이다. 정상.
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
* **대기는 날짜를 넘어 유지되지만 개수는 언제나 1개다**(2026-09-04 확정). 어제 대기한 채 자정을 넘겨도
  약속은 살아 있고, 그동안 카운터는 멈춰 있다 — 이틀을 가득 찬 채로 일해도 받을 수 있는 것은 하나다.
  이것은 버그가 아니라 규칙이다(상한 3을 둔 이유가 사라지지 않게 하는 것이 설계 의도다).
  또한 **대기·지급 판정은 "달성한 순간"이 아니라 "달성 후 첫 평가 시점"의 잔량으로 내려진다** —
  서버는 과거 시점의 잔량을 알 수 없기 때문이다. 근무 중에는 5분마다, 그리고 **울트라를 쏜 직후**
  sync 가 돌아 그 차이는 실질적으로 5분 이내다.
* **배포 직후 하루는 한 번 헐거워진다 — 단 "이미 받은 것"까지 다시 주지는 않는다.** 기존 사용자는
  `ultra_quest_day` 가 null 이라 첫 sync 가 baseline 을 **오늘 이미 지급된 랩 수 × 3시간** 으로 잡는다.
  그래서 소멸로 파괴됐던 랩(이 파일이 지운 `delta 0` 행)만 되살아나고, 이미 받아서 쓴 랩은 재평가되지
  않는다. 어제 몫도 같은 규칙으로 딱 1개까지 소급된다. 상한 3이 그 위를 한 번 더 잠근다.
* **상한을 5→3 으로 내렸을 때 이미 4~5개를 들고 있던 사람은 깎지 않았다**(실측 14명).
  `ultra_wallet_touch` 는 잔량을 **절대 내리지 않는다** — 내리면 장부 합계와 갈려
  `ultra_wallet_audit()` 이 영구 드리프트를 낸다. 쓰면서 3 이하로 내려가면 그때부터 상한 3 이 걸린다.
