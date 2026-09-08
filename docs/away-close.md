# 자리비움 자동 마감 — 서버 계약 (v0.2.35 / build 44)

이 문서는 **클라이언트가 서버와 주고받는 것의 정본**이다. 응답 필드 이름·타입·의미가 여기 적힌 것과
다르면 그건 서버가 아니라 이 문서가 틀린 것이니 고쳐라. 설계 근거는 `PICK.md`, 결함 이력은 `attack-1..4.md`.

마이그레이션 3개 + 스위치 2개(끄기 1 / 되켜기 1):

| 파일 | 무엇을 하나 | 마감이 일어나나 |
|---|---|---|
| `20260820010000_away_input_tracking.sql` | `last_input_at` 컬럼 2개 + 리그 라이브 클램프 + 임계 상수 + 판정 단일 출처 함수 2개 | **아니오**(오판 비용 0) |
| `20260820020000_away_restore.sql` | `auto_closed_*`/`restored_at` + 복원 RPC + `away_sync()` + 기존 마감 경로에 사유 기록 | 아니오 |
| `20260820030000_away_close_backstop.sql` | `close_away_work_sessions()` + pg_cron 5분 | **예**(임계+30분) |
| `20260820050000_away_close_disabled_until_fleet_converges.sql` | 임계를 **315360000초(10년) 센티널**로 상향 = 3층(away 마감) 꺼짐 | **아니오** |
| `20260908120000_away_close_reenable.sql` | 임계를 **9000초(2시간 30분)** 로 되세움 = 3층 켜짐 | **예**(적용 후) |

★ **실서버 현황(2026-09-08)**: 임계는 **아직** 315360000초다 — 되켜는 마이그레이션 파일은 만들어져
있지만 **적용은 사장님 승인 뒤**다. 적용되는 순간 클라·백스톱 두 판정자가 동시에 9000초로 돌아선다
(클라는 임계를 `away_sync()` 응답으로만 받으므로 코드가 갈릴 것은 없다).
껐던 이유(혼합 함대에서 구버전 흡수 맥이 서버에 행을 안 남겨 면제 조건이 그 맥을 못 보고 살아있는
근무가 소급 삭제됨)는 해소됐다: 20260820050000 의 감시 질의가 8/20 **31대** → 9/8 **8명 전원 단일
기기**로 수렴했고, 위험 조합(신버전 + 구버전 혼용)이 **0명**이다. 남은 단일 구버전 사용자는 면제
조건 (1)이 이미 걸러낸다. 근거 전문은 `20260908120000` 헤더에 있다.
1층(리그 클램프)은 내내 살아 있었고, **잠자기(sleep) 마감은 3층과 무관하게 계속 동작한다.**

★ **복원(이어붙이기)은 v0.2.46 부터 클라이언트에서 휴면이다.** 서버 쪽(2층)은 한 줄도 바뀌지 않았다 —
`restore_auto_closed_session` RPC 도, `away_sync()` 의 `restorable` 응답도 그대로 있다. **클라가 그것을
읽지도 부르지도 않을 뿐이다**(Swift `Decodable` 은 모르는 키를 무시하므로 서버는 계속 보내도 된다).
왜 껐는가는 5절에 적었다. 되살릴 때는 그 절의 조건을 먼저 읽어라.

---

## 1. 클라가 써야 하는 것 — `last_input_at`

**두 곳에 같은 값을 싣는다.** 한 곳만 쓰면 맥 2대가 서로의 값을 지운다.

| 표 | 컬럼 | 누가 쓰나 |
|---|---|---|
| `work_statuses` | `last_input_at timestamptz null` | 세션 소유 맥의 하트비트(기존 `last_seen_at` 과 같은 요청) |
| `work_status_devices` | `last_input_at timestamptz null` | **모든 맥이 자기 기기 행에.** 세션을 소유하지 않아도 이 값만은 쓴다 |

- 값의 정의: **마지막 의미 있는 입력**(키·클릭·스크롤 — 마우스 이동 제외, v0.2.17 계약). 단조 증가만.
  화면 잠금/비콘솔(`consoleSessionUsable()` 거짓)이면 전진시키지 않는다.
- **비소유 맥의 쓰기 규약**: `session_id` 는 보내지 말고(null 유지), `last_seen_at` 도 갱신하지 말고,
  `last_input_at` **만** 보낸다. 소유권 판정은 `canonicalSessionID(claim.sessionID) == sessionID` 를
  요구하므로 이 행이 소유권 로직을 오염시키지 않는다.
- **소유 맥의 쓰기 규약**: 지금까지처럼 `session_id`(= 지금 세션) + `last_seen_at` + `last_input_at`.
  ★ `session_id` 를 안 보내면 그 사용자는 **영원히 away 마감 대상이 아니다**(자격 판정이 이 값을 본다).
  기능이 조용히 죽으므로 반드시 함께 보내라.
- 미래 시각을 보내지 마라. 서버는 `least(last_input_at, now())` 로 누른다(위조를 막지는 못한다 — 이미
  `ended_at` 을 클라가 보내는 기존 P0 가 더 직접적이다).
- **팀 조회 select 목록에 `last_input_at` 을 넣지 마라.** RLS 는 팀 범위라 요청하면 보인다. 남의 마지막
  키 입력 시각을 30초 해상도로 노출하는 것은 이 앱이 하기로 한 일이 아니다(규약으로만 막힌다).
- ⚠️ `docs/privacy.md` 의 "이 숫자는 로컬에서만 쓰이고 서버로 보내지 않습니다" 문장은 **이 변경과 함께
  갱신돼야 한다**(지금은 사실이 아니게 된다).

## 2. 클라가 읽어야 하는 것 — `away_sync()`

`POST /rest/v1/rpc/away_sync` (인자 없음, `authenticated` 전용). **임계값을 클라 상수로 두지 마라** —
사장님 확정 사항이다. 이 응답이 유일한 출처다. 반환은 단일 `jsonb`.

```jsonc
{
  "status": "ok",                    // "ok" | "invalid"(비로그인)
  "serverNow": "2026-08-19T13:51:15.990741+00:00",  // 시계 어긋남 감지용
  // ── 정책(서버 소유 상수. 계측 후 SQL 한 줄로 바뀐다 — 캐시해도 되지만 매 폴링 갱신이 안전) ──
  // ⚠️ 실서버는 아직 closeThresholdSeconds=315360000(10년 센티널 = 3층 꺼짐)을 돌려준다.
  //    20260908120000 이 적용되면 아래 9000/10800 이 그대로 나온다(머리말의 실서버 현황 참조).
  "closeThresholdSeconds": 9000,     // 2시간 30분. 클라 마감 임계
  "backstopSeconds": 10800,          // 3시간. 서버가 마감하는 시각(= 임계 + 유예)
  "freezeSeconds": 1800,             // 30분. 리그 라이브 클램프 유예
  "restoreWindowSeconds": 21600,     // 6시간. ended_at 기준 복원 창
  "dailyRestoreLimit": 2,
  "restorableReasons": ["away", "sleep"],
  "restoresUsedToday": 0,            // KST 하루
  "restoresLeftToday": 2,

  // ── 열린 세션이 있을 때만 존재 ──
  "openSession": {
    "id": "…uuid…",
    "teamId": "…uuid…",
    "startedAt": "…",
    "lastInputAt": "…",              // greatest(work_statuses, 내 모든 기기 행) — 클라도 같은 max 를 쓴다
    "closeEligible": false,          // ★ 아래 3절. false 면 클라는 **마감하지 않는다**
    "closeDueAt": "…"                // lastInputAt + closeThresholdSeconds (lastInputAt 이 null 이면 null)
  },

  // ── 복원 가능한 세션이 있을 때만 존재 (⚠️ v0.2.46 부터 클라 미사용 — 5절) ──
  "restorable": {
    "sessionId": "…uuid…",
    "teamId": "…uuid…",
    "startedAt": "…", "endedAt": "…",
    "durationSeconds": 10740,
    "autoClosedAt": "…", "autoClosedReason": "away",   // "away" | "sleep"
    "expiresAt": "…",                // endedAt + restoreWindowSeconds. **창 판정은 서버가 한다**
    "remainingSeconds": 10740        // 0 이면 이미 만료
  }
}
```

- `openSession`/`restorable` 은 **없을 수 있다**(키 자체가 없다). 옵셔널로 디코드하라.
- 이 RPC 가 실패하거나 404(마이그레이션 미적용 서버)면 **클라는 away 마감을 하지 않는다.**
  임계를 모르는 채 리터럴로 마감하는 것이 이 기능에서 가장 나쁜 실패 모드다.
- 폴링 경로에 얹되 실패를 삼켜라(`fetchStatusDevices` 와 같은 규약 — 실패가 팀 폴링을 죽이면 안 된다).

## 3. `closeEligible` — 클라가 마감해도 되는가

서버와 클라가 **같은 함수**(`away_input_observable`)의 결과를 본다. 클라는 서버 백스톱보다 30분 **먼저**
발화하므로, 클라가 이 값을 무시하면 서버 쪽 안전장치는 도달하지 못한 채 매일 오마감이 난다.

`true` 가 되는 조건은 둘 다 참일 때뿐이다:
1. 지금 세션을 소유한 기기 행(`session_id = 그 세션`)의 `last_input_at` 이 non-null
2. **세션이 시작된 뒤 신호를 보낸 기기 중 `last_input_at` 이 null 인 맥이 하나도 없다**(혼합 함대 제외)

→ 한 대라도 구버전인 사용자는 구버전이 사라질 때까지 **통째로 면제**된다. 의도된 동작이다.

**클라 마감 규칙(3파)**:
```
closeEligible == true
  && max(로컬 lastMeaningfulInputAt, openSession.lastInputAt) + closeThresholdSeconds <= now
  → autoStop(endedAt: 그 max 시각, reason: "away")
```
로컬 단독으로 판정하면 "아이맥 켜둔 채 노트북에서 작업"이 매일 결정론적으로 오마감된다.

## 4. 클라가 마감할 때 남겨야 하는 것

`work_sessions` PATCH 에 세 컬럼이 추가됐다(표 단위 UPDATE 권한이 이미 있어 별도 grant 불필요):

| 컬럼 | 값 |
|---|---|
| `auto_closed_at` | 마감 판정 시각(= now) |
| `auto_closed_reason` | `'away'` \| `'sleep'` \| `'abandoned'` \| `'long_session'` — **check 제약으로 고정**. 다른 값은 23514 로 거절된다 |
| `restored_at` | 클라가 쓰지 마라. 복원 RPC 가 소유한다 |

- `ended_at` 은 지금처럼 **소급 시각**(마지막 입력 / `min(sleepBeganAt, lastMeaningfulInputAt)`)이다.
- **`sleep` 경로 — 경쟁 면역 구조(v0.2.36)**: 뚜껑을 닫으면 10분 뒤 서버 스캐빈저가 먼저
  `abandoned`(복원 **불가** 사유)로 마감한다. 정정을 didWake 에만 걸면 반드시 진다 — 깨어나는 순간
  폴링 루프의 `Task.sleep` 이 즉시 재개돼 하트비트→폴링을 먼저 완주하고(부활 시도 하트비트는 서버
  트리거가 off_work 로 강등), 폴링이 `(.offWork,.some)` 을 보고 `startedAt=nil` 로 내리면 뒤늦은
  handleWake 는 startedAt 가드에서 조기 반환한다. 그래서 구조는 두 조각이다:
  1. **willSleep 영속 마커**: `handleSleep` 이 근무 중 관측(`PendingSleepClose` — sessionID/
     sessionStartedAt/sleepBeganAt/lastInputAt)을 UserDefaults(`check.sleepClose.pending`)에 심는다.
     흡수 세션엔 심지 않는다. 정상 마감 경로(수동 stop/autoStop/유예 안 wake/새 start/계정 전환)가
     지우고, handleWake 의 startedAt 가드 조기 반환과 강제 로그아웃에서는 **일부러 살린다**.
  2. **폴링 수용 지점 정정**: `applyRemoteOwnStatus` 가 서버의 닫힘을 발견하는 그 자리에서 마커를
     소비해 `reason='sleep'`, `ended_at = max(started, min(sleepBeganAt, lastInputAt))` 의 정정
     stop 을 큐에 싣는다(서버 반영은 기존 stopWork 0행 갈래의 정정 PATCH — `ended_at` 은
     `gt.` 필터로 **더 이르게만** 당긴다. 늦추는 것은 위조다). 이 지점은
     **깨어남 순서 경쟁**(폴링이 didWake 보다 먼저)·**다크웨이크**(didWake 자체가 없다)·
     **잠자는 사이 앱 사망**(다음 실행의 첫 폴링이 영속 마커+영속 소유 ID 로 정정) 전부가 지난다.
     handleWake 가 먼저 이기면 큐의 stop 항목이 수용 지점의 pendingItems 가드를 잠가 이중 정정이
     구조적으로 불가능하다. (v0.2.35~45 에서는 정정 성사가 복원 배너·넛지 복원 제안으로 이어졌다.
     v0.2.46 부터 그 두 표면은 없고, 정정의 이득은 마감 시각·사유가 사실과 같아진다는 것 자체다.)
- **abandoned 강하의 통보(v0.2.36)**: 마커 없이(잠자기가 아닌데 — 깨어있는 채 네트워크 단절 등)
  내 소유 세션이 신호 공백 10분+ 로 닫혀 강하하면 클라는 침묵하지 않는다 — 사용자 문구
  ("연결이 끊겨 근무가 자동 종료됐어요")를 세우고, **자동 재개 대상**으로 등록한다(6-1절).
  신선한 신호의 강하(다른 맥의 정상 종료)는 기존대로 조용히 내린다.
- 팀 조회 select 에 `auto_closed_reason` 을 넣지 마라(수동 종료와 구분 불가해야 한다).

## 5. 복원 — `restore_auto_closed_session(p_session_id uuid)` — **클라이언트 휴면 (v0.2.46~)**

> ⚠️ **이 절의 서버 계약은 전부 살아 있지만, v0.2.46 부터 클라이언트가 이 RPC 를 호출하지 않는다.**
> `away_sync()` 의 `restorable` 응답도 클라가 읽지 않는다(2절). 아래 표는 되살릴 때를 위한 정본이다.
>
> 껐던 이유 셋(실서버 21일치 실측, 사장님 승인):
> 1. **승인 직후 재마감 churn 21%** — 이어붙이기 승인 85건 중 18건이 60초 안에 사유 없는 수동종료
>    경로로 세션이 다시 닫혔고, 몇 초 뒤 새 세션이 떴다.
> 2. **수면 갭의 근무 재계상** — 21일간 14건, 42~289분. 잠자기 마감이 정확히 깎아 낸 시간을
>    복원이 도로 채워 넣었다(최대 사례는 289분 → 10시간 세션).
> 3. **원래 존재 이유가 없다** — 이 기능은 자리비움(3층) 마감의 구제책으로 만들어졌는데 3층이
>    그때 꺼져 있었다(머리말). 그래서 프로덕션에서 이 버튼이 실제로 한 일은 잠자기 마감을 되살리는 것뿐이다.
>
> **되살린다면 좁은 버전으로**: 대상 사유를 `away` **하나로만** 좁히고, 승인 직후 재마감 churn 을
> 계측할 수단을 함께 넣어라. 그 자리는 지금 **자동 재개(30분 창)** 가 대신 채우고 있다(6-1절) —
> 그쪽은 되살아나는 양이 구조적으로 30분에 묶여 위 ②(수면 갭 재계상)가 원리적으로 불가능하다.

`POST /rest/v1/rpc/restore_auto_closed_session` `{"p_session_id": "…uuid…"}` (`authenticated` 전용).
**한 트랜잭션**에서 S2 삭제 → S1 재개 → 상태행 갱신 → 하루 카운터 증가를 모두 한다.
클라에서 2회 왕복으로 흉내내지 마라 — 중간에 죽으면 열린 세션이 0개나 2개가 된다(기록된 사고).

반환은 단일 `jsonb`, 항상 `status` 를 갖는다:

| status | 의미 | 클라가 할 일 |
|---|---|---|
| `ok` | 복원됨. `sessionId`,`startedAt`,`restoredAt`,`reason`,`deletedOpenSessions`,`usedToday`,`limit` 동반 | 로컬 세션을 `startedAt` 으로 재개. `longSessionAnchor = startedAt`(복원 시각 아님 — 12시간 장치가 죽는다) |
| `already_open` | 이미 열려 있다(재시도·두 번째 맥) | 성공과 같이 다뤄라 |
| `not_found` | 내 세션이 아니거나 없다 | 배너 제거 |
| `not_restorable` | 사유가 away/sleep 이 아니다(`reason` 동반) | 배너 제거 |
| `already_restored` | 이 마감은 이미 복원했다(`restoredAt`) | 배너 제거 |
| `expired` | 창이 닫혔다(`endedAt`,`windowSeconds`,`ageSeconds`) | "복원 시간이 지났어요" |
| `limit_reached` | 하루 상한(`usedToday`,`limit`) | 사유를 사람이 읽을 수 있게 |
| `not_member` | 그 팀을 나갔다 | 배너 제거 |
| `conflict` | S1 보다 **먼저** 시작한 열린 세션이 남아 있다(정상 경로에서는 안 생긴다) | 재시도하지 말고 로그 |
| `invalid` | 비로그인 | 재로그인 |

성공 시 서버가 하는 일(클라가 중복으로 하지 마라):
- S1 `ended_at=null, duration_seconds=null, restored_at=now()`
- 복귀 후 자동 시작이 연 **열린 세션(S1 보다 나중에 시작한 것)을 삭제** — 그 구간은 S1 이 덮는다
- `work_statuses`: `status='working'`, `active_session_id=S1`, **`last_seen_at=now()`, `last_input_at=now()`**
  (이걸 빼면 되살린 세션이 10분 스캐빈저에 즉시 다시 닫힌다 — 공격이 잡은 결함)
- `profiles.away_restore_day/away_restore_count` 증가(클라는 읽지도 쓰지도 못한다)

## 6. 서버 백스톱 — `close_away_work_sessions()`

**클라는 이 함수를 호출할 수 없다**(`service_role` 전용, cron `*/5 * * * *`). 의도적이다:
`close_abandoned_work_sessions()` 는 클라 스캐빈저가 부르는데, 거기에 away 를 섞으면 팀원이 팝오버를
여는 것만으로 남의 자리비움 마감이 앞당겨 발화한다.

마감 조건(전부 참일 때만):
`ended_at is null` ∧ `status='working'` ∧ `active_session_id = 그 세션` ∧ `closeEligible` ∧
`last_input_at`(max 규칙) `is not null` ∧ `last_input < now - (임계+유예)` ∧ `started_at <= last_input`
(임계+유예 = 3시간. 임계가 10년 센티널인 동안은 이 백스톱이 후보를 잡지 못한다 — cron 은 재개 절차를
한 단계로 줄이기 위해 등록된 채 두었고, `20260908120000` 이 적용되면 그날부터 다시 발화한다.)

마감 결과: `ended_at = greatest(started_at, least(last_input, now))`, `auto_closed_reason='away'`,
상태행은 `off_work` + `active_session_id=null`. 멱등(`where ended_at is null` + EPQ 재확인).

## 6-1. 자동 재개 — 최근 30분 안에 자동 마감된 내 세션 (v0.2.47, **클라 전용**)

서버 계약이 **아니다.** 이 절의 판정과 발화는 전부 클라 안에서 일어나고, 서버로 나가는 것은 기존
`reopenSession` PATCH(= `ended_at`/`duration_seconds` 를 null 로 되돌리고 상태행을 working 으로) 하나뿐이다.

규칙(사장님 확정): **자동 마감된 내 소유 세션의 `ended_at` 이 지금으로부터 30분 이내이고 사유가
`long_session` 이 아니면, 복귀가 감지되는 순간 배너 없이 그 세션을 되살린다**(새 세션을 만들지 않는다).

- **앵커는 `ended_at`이다**(마감이 발화한 시각이 아니다). 되살아나는 시간이 정확히 `지금 − ended_at`
  이므로, 그 값을 30분으로 묶으면 **재계상 상한이 구조적으로 30분**이 된다. 5절이 제거한 이어붙이기에는
  이 상한이 없어 289분짜리 수면을 근무로 되살렸다 — **이 상한이 이 기능과 그 버그를 가르는 유일한 선이다.**
- **실질 대상은 `sleep`·`abandoned`** 다. `away` 는 사유 필터 없이 산술로 빠진다(갭 = 임계 = 2시간 30분
  > 30분). `long_session` 은 갭이 정확히 응답 창(30분)이라 경계에 걸리므로 **사유로 명시 제외**한다.
- **발화 지점은 하나**다: `CheckOverlayController.nudgeAutoStart()`(최근 10분 안에 실제 사용 5분).
  잠에서 깬 복귀도 여기로 들어온다(NudgeScheduler 가 didWake 에 누적을 0 으로 되돌린다).
  **새 세션을 만들기 전에** 재개 대상을 본다 — 순서가 뒤바뀌면 세션이 두 개가 되거나 재개가 조용히 죽는다.
- 되돌리기 배너(v0.2.35~46, 유예 10분)는 **없앴다**. 사용자가 누를 것이 없다.
- 유지되는 가드(전부 실제 사고에서 나왔다): 소유 강도 상속, 누적에서 그 세션 몫 빼기(이중 계상 금지),
  왕복 중 사용자 조작 스냅백 방지(`workStateWriteGeneration`), 근무 중이면 거절, 흡수 세션 제외.

## 7. 리그 라이브 클램프 (구버전 포함 전원에게 즉시 적용)

`team_weekly_leaderboard()` 의 **열린 세션 상한만** 바뀌었다:

```
effective_end = least(coalesce(li + 30분, last_seen_at), last_seen_at, now)
li = greatest(work_statuses.last_input_at, max(work_status_devices.last_input_at))
```

- **닫힌 세션은 한 글자도 안 바뀐다** → 돌아온 사람은 1초도 잃지 않는다(오판 비용 0).
- `li` 가 null(구버전)이면 **기존 동작과 완전히 동일**하다(배포 시점 등가성을 마이그레이션이 기계로 확인한다).
- 부작용(정직하게): 30분 넘는 회의 중에는 라이브 순위 기여가 멈췄다가 복귀 시 점프한다. 원장은 안 줄어든다.

## 8. 상수를 바꾸는 법 (계측 후)

세 값 모두 **실측 전 잠정값**이다. 클라 배포 없이 SQL 한 줄로 바뀌지만, **반드시 새 마이그레이션
파일로 바꿔라** — 이 프로젝트는 전체 재적용을 실제로 겪었고(무료플랜 일시정지 복원), ad-hoc SQL 은
재적용 때 조용히 되돌아간다. 임계는 `20260820050000` 이 315360000(10년 센티널 = 3층 꺼짐)으로
이미 한 번 덮었다 — 아래 9000 은 다시 켤 때의 값이다:

```sql
create or replace function public.away_close_threshold_seconds() returns int language sql immutable as $$ select 9000 $$;
create or replace function public.away_restore_window_seconds()  returns int language sql immutable as $$ select 21600 $$;
create or replace function public.away_freeze_seconds()          returns int language sql immutable as $$ select 1800 $$;
create or replace function public.away_daily_restore_limit()     returns int language sql immutable as $$ select 2 $$;
```

★ 지켜야 하는 부등식(20260820010000 의 사후 단언이 배포 때 기계로 검사한다):
**`restore_window > threshold + freeze`**. 깨지면 마감된 세션이 태어나자마자 복원 불가가 된다.
(임계가 10년 센티널인 동안은 이 부등식이 **일부러** 깨져 있다 — away 마감 자체가 없어 무해하다.
`20260908120000` 이 9000 으로 되세우며 이 부등식을 복원하고, 자기 사후 단언으로 다시 검사한다.)

★ **임계를 30분 밑으로 내리지 마라.** 클라의 자동 재개(6-1절)가 away 마감을 되살리지 않는 근거는
사유 필터가 아니라 산술이다: away 의 갭 = 임계이고 재개 창은 30분이다. 임계가 30분 밑으로 내려가면
away 마감이 조용히 자동 재개된다. 서버 함수 코멘트에도 같은 경고가 있다.

## 9. 알려진 잔여 위험 (숨기지 않는다)

1. **세션이 열린 도중 그 맥을 구버전으로 다운그레이드**하면 기기 행의 `last_input_at` 이 얼어붙은 채
   non-null 로 남아 자격 판정을 통과한다. 그 한 세션은 얼어붙은 시각으로 마감될 수 있다.
   (그 뒤 세션들은 `started_at > 얼어붙은 값` 이라 `started_at <= last_input` 가드가 영구히 막는다.)
2. **위조는 못 막는다.** `last_input_at` 을 항상 `now` 로 보내면 영구 면제다. 새 지평선은 아니다.
3. **~~6시간 미만 수면은 복원 버튼으로 되살릴 수 있다.~~** (v0.2.46 해소 — 클라가 복원 버튼을 없앴다.
   이 위험이 21일간 14건으로 실현된 것이 5절의 제거 사유 ②다. 되살릴 때 반드시 다시 읽어라.)
4. **팀에 완전 무흔적은 거짓이다.** 소급 마감이면 팀원 화면의 내 today 숫자가 줄어든다.
   "갑자기 깎였다"는 패턴 자체가 자동 마감의 표지다.
