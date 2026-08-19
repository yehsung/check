# 자리비움 자동 마감 — 서버 계약 (v0.2.35 / build 44)

이 문서는 **클라이언트가 서버와 주고받는 것의 정본**이다. 응답 필드 이름·타입·의미가 여기 적힌 것과
다르면 그건 서버가 아니라 이 문서가 틀린 것이니 고쳐라. 설계 근거는 `PICK.md`, 결함 이력은 `attack-1..4.md`.

마이그레이션 3개:

| 파일 | 무엇을 하나 | 마감이 일어나나 |
|---|---|---|
| `20260820010000_away_input_tracking.sql` | `last_input_at` 컬럼 2개 + 리그 라이브 클램프 + 임계 상수 + 판정 단일 출처 함수 2개 | **아니오**(오판 비용 0) |
| `20260820020000_away_restore.sql` | `auto_closed_*`/`restored_at` + 복원 RPC + `away_sync()` + 기존 마감 경로에 사유 기록 | 아니오 |
| `20260820030000_away_close_backstop.sql` | `close_away_work_sessions()` + pg_cron 5분 | **예**(임계+30분) |

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

  // ── 복원 가능한 세션이 있을 때만 존재 ──
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
- **`sleep` 경로 주의**: 뚜껑을 닫으면 10분 뒤 서버 스캐빈저가 먼저 `abandoned` 로 마감한다.
  깨어난 클라가 그 세션이 이미 닫혀 있는 것을 보면 `auto_closed_reason` 을 `'sleep'` 으로 **정정 PATCH** 하라
  (그래야 복원 대상이 된다). `ended_at` 은 더 이르게만 정정하라(늦추는 것은 위조다).
- 팀 조회 select 에 `auto_closed_reason` 을 넣지 마라(수동 종료와 구분 불가해야 한다).

## 5. 복원 — `restore_auto_closed_session(p_session_id uuid)`

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
`last_input_at`(max 규칙) `is not null` ∧ `last_input < now - 3시간` ∧ `started_at <= last_input`

마감 결과: `ended_at = greatest(started_at, least(last_input, now))`, `auto_closed_reason='away'`,
상태행은 `off_work` + `active_session_id=null`. 멱등(`where ended_at is null` + EPQ 재확인).

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

세 값 모두 **실측 전 잠정값**이다. 클라 배포 없이 SQL 한 줄로 바꾼다:

```sql
create or replace function public.away_close_threshold_seconds() returns int language sql immutable as $$ select 9000 $$;
create or replace function public.away_restore_window_seconds()  returns int language sql immutable as $$ select 21600 $$;
create or replace function public.away_freeze_seconds()          returns int language sql immutable as $$ select 1800 $$;
create or replace function public.away_daily_restore_limit()     returns int language sql immutable as $$ select 2 $$;
```

★ 지켜야 하는 부등식(20260820010000 의 사후 단언이 배포 때 기계로 검사한다):
**`restore_window > threshold + freeze`**. 깨지면 마감된 세션이 태어나자마자 복원 불가가 된다.

## 9. 알려진 잔여 위험 (숨기지 않는다)

1. **세션이 열린 도중 그 맥을 구버전으로 다운그레이드**하면 기기 행의 `last_input_at` 이 얼어붙은 채
   non-null 로 남아 자격 판정을 통과한다. 그 한 세션은 얼어붙은 시각으로 마감될 수 있다.
   (그 뒤 세션들은 `started_at > 얼어붙은 값` 이라 `started_at <= last_input` 가드가 영구히 막는다.)
2. **위조는 못 막는다.** `last_input_at` 을 항상 `now` 로 보내면 영구 면제다. 새 지평선은 아니다.
3. **6시간 미만 수면은 복원 버튼으로 되살릴 수 있다.** 워크숍 다녀온 사람을 살리는 문과 같은 문이라
   닫으면 둘 다 죽는다. 남는 방벽은 `restored_at` 기록과 하루 상한뿐이다.
4. **팀에 완전 무흔적은 거짓이다.** 소급 마감이면 팀원 화면의 내 today 숫자가 줄었다가 복원 시 돌아온다.
   "깎였다 되살아났다"는 패턴 자체가 자동 마감의 표지다.
