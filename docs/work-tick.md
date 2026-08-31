# work_tick — 근무 틱 통합 RPC 계약 (v0.2.38 / 계약 `v=1`)

이 문서는 **클라이언트가 `POST /rest/v1/rpc/work_tick` 와 주고받는 것의 정본**이다. 응답 필드 이름·타입·의미가
여기 적힌 것과 다르면 서버가 아니라 이 문서가 틀린 것이니 고쳐라. 서버 정의는
`supabase/migrations/20260831120000_work_tick_rpc.sql` 하나다(함수 + 사후 단언 + 행동 프로브).

**한 줄 요약**: 근무 중 30초마다 따로 나가던 REST 7~8건(하트비트 2 + 팀 상태 GET 4 + away_sync + 60초 스로틀 팀 메타)을
**한 번의 POST 로 합친다. 전송만 합치고 의미는 바꾸지 않는다** — 각 조각은 기존 개별 요청이 돌려주던 것과
**행 단위로 동일한 JSON** 이라 지금 쓰는 디코더(`WorkStatusRow` 등)가 그대로 읽는다. 서버측 집계로 수신량을 줄이는
것은 2단계이고 이번엔 금지다.

| 원칙(사장님 결정) | 서버에서 어떻게 지켰나 |
|---|---|
| 1. 전송만 합치고 의미 불변 | 조각별 select 목록·필터·정렬을 기존 GET 과 글자 단위로 같게 옮겼다. 합산·축약 없음 |
| 2. 부작용 동일 | 하트비트는 PostgREST merge-duplicates 가 만들던 것과 같은 `INSERT … ON CONFLICT DO UPDATE`(같은 컬럼·같은 값). 좀비 강등 트리거(20260717040000)가 그대로 발화. 본문에 없던 컬럼(nil 관측)은 안 건드린다 |
| 3. 호출자 자격 | `SECURITY INVOKER` — RLS 를 그대로 탄다. DEFINER 가 필요한 조각은 기존 `away_sync()` / `my_team_invite_code()` 를 **호출**해 위임(새 우회 없음). anon·PUBLIC 실행권 회수 |
| 4. 부분 실패 금지 | 하트비트 실패 = 함수 전체 실패(한 문장 = 한 트랜잭션 → 조회까지 롤백, PostgREST 4xx). 빈 조각은 실패가 아니라 `[]` |
| 5. 혼합 함대 | 기존 표·GET·RPC 전부 그대로. 함수 하나만 **추가**(표·컬럼·FK·트리거 0 → PostgREST 임베드 축 불변) |
| 6. 협상 | 응답에 `v`(정수) + `server_now` |

---

## 1. 정찰 — 30초 틱이 **지금** 보내는 요청 전수

출처: `WorkTimerStore.startStatusRefreshLoop`(본문 순서: `confirmMembershipIfNeeded → retryPendingSync → sendHeartbeatIfWorking →
refreshTeamStatus → reconcileRealtimeWithWorkState → refreshAwayStateIfNeeded → refreshLeaderboardIfVisible → refreshTokenBoardIfVisible →
refreshPokeDirectoryIfVisible → (팝오버 열림) uploadTokenUsageIfNeeded`), `WorkTimerStoreSync.swift`, `SupabaseWorkService.swift`.
공통 헤더: `apikey`, `Authorization: Bearer <JWT ≈1.15KB>`, `Accept: application/json`. 루프 주기: fast(근무중·팝오버·미반영 큐) 30초 / idle 300초(30초 슬라이스 ×10).

| # | 호출 | 메서드·경로 | 쿼리 | 본문(JSON, snake_case) | Prefer | 응답 디코더 | 근무중 | 비근무 | 팝오버 열림 |
|---|---|---|---|---|---|---|---|---|---|
| ① | `heartbeat` → `upsertStatus` | POST `/rest/v1/work_statuses` | `on_conflict=team_id,user_id` | `{team_id,user_id,status:"working",active_session_id,last_seen_at,updated_at[,last_input_at]}` (`last_input_at` 은 `awayServerSupported && 관측≠nil` 일 때만 키 존재) | `resolution=merge-duplicates,return=minimal` | (없음) | ○ 소유 맥 | × | — |
| ② | `upsertStatusDevice` | POST `/rest/v1/work_status_devices` | `on_conflict=team_id,user_id,device_id` | `{team_id,user_id,device_id,session_id,last_seen_at,updated_at[,last_input_at],opened_session}` | 〃 | (없음) | ○ 소유 맥 | × | — |
| ②′ | `reportDeviceInput` | POST `/rest/v1/work_status_devices` | 〃 | `{team_id,user_id,device_id,last_input_at}` **만** | 〃 | (없음) | ○ 흡수 맥(`adoptedRemoteSession`)이고 관측≠nil | × | — |
| ③ | `fetchTeamStatuses` | GET `/rest/v1/work_statuses` | `select=user_id,status,updated_at,last_seen_at,active_session_id,profiles(display_name,avatar_url)&team_id=eq.<T>&order=updated_at.desc` | — | — | `[WorkStatusRow]` (`profiles: ProfileRow?`) | ○ | ○ | ○(열 때 15초 스로틀 안이면 스킵) |
| ④ | `fetchActiveSessions` | GET `/rest/v1/work_sessions` | `select=id,user_id,started_at,ended_at,duration_seconds&team_id=eq.<T>&ended_at=is.null` | — | — | `[WorkSessionRow]` | ○ | ○ | ○ |
| ⑤ | `fetchWeeklySessions` | GET `/rest/v1/work_sessions` | `select=user_id,started_at,ended_at&team_id=eq.<T>&ended_at=not.is.null&ended_at=gte.<KST 월요일 00:00, "…Z">` | — | — | `[WorkSessionRow]` (id/duration 없음) | ○ | ○ | ○ |
| ⑥ | `fetchStatusDevices` | GET `/rest/v1/work_status_devices` | `select=user_id,device_id,session_id,last_seen_at,opened_session&team_id=eq.<T>` | — | — | `[WorkStatusDeviceRow]` (실패는 삼킴) | ○ | ○ | ○ |
| ⑦ | `awaySync` | POST `/rest/v1/rpc/away_sync` | — | `{}` | — | `AwaySyncResponse` | ○ 매 틱 | ○ 120초 스로틀 | — |
| ⑧a | `refreshTeamMeta` → `fetchOwnMembership` | GET `/rest/v1/memberships` | `select=team_id,role,teams(name,weekly_goal_hours)&user_id=eq.<me>&order=joined_at.asc,team_id.asc&limit=1` | — | — | `[MembershipRow]` | — | — | ○ 열 때 60초 스로틀 |
| ⑧b | `loadMyInviteCode` | POST `/rest/v1/rpc/my_team_invite_code` | — | `{}` | — | `[InviteCodeRow]` | — | — | ○ (⑧a 성공 직후) |

같은 루프에 **있지만 통합 대상이 아닌 것**(주기·의미가 다르다): `take_pokes`(별도 15/60초 폴러, 소비 부작용), `ultra_wallet_sync`(5분 스로틀, 적립 부작용),
`team_weekly_leaderboard` / `token_usage_board` / `app_user_directory`(패널 노출 중일 때만), `close_abandoned_work_sessions`(5분 스로틀 스캐빈저), 토큰 업로드(60초 스로틀).
③~⑥ 은 `async let` 으로 병렬 발사되므로 지연은 1왕복이지만 **요청 수·헤더 바이트는 4건 그대로**다 — work_tick 이 줄이는 것이 정확히 그것이다.

상태별 합계: 근무중(소유 맥) **7건**/틱(+팝오버 열 때 ⑧ 2건), 근무중(흡수 맥) 5~6건, 비근무 4건(+120초마다 ⑦), 무소속은 ③~⑥ 없이 ⑦만.

---

## 2. 계약

### 2.1 요청 — `POST /rest/v1/rpc/work_tick` (`authenticated` 전용, `Content-Type: application/json`)

PostgREST 는 **보낸 키 집합**으로 함수를 고른다. 기본값이 있는 인자는 생략 가능하지만 **`p_team_id` 는 기본값이 없으므로 항상 보낸다**(무소속이면 `null`).
여기 없는 키를 하나라도 보내면 PGRST202(404)가 나고 클라는 폴백 경로로 조용히 내려앉는다 — 이득만 사라지는 실패라 **두 대 프로브에서 200 을 반드시 확인**한다.

| 인자 | 타입 | 기본 | 값의 출처(기존 요청) | 의미 |
|---|---|---|---|---|
| `p_team_id` | uuid \| null | (필수) | ③~⑥ 의 `team_id=eq.` = `currentTeamID` | null → 팀 조각 4개 전부 `[]`, away/meta 는 정상 |
| `p_heartbeat` | bool | false | `startedAt != nil && session != nil && teamID != nil` | false 면 **쓰기 0건** |
| `p_session_id` | uuid \| null | null | ①② 의 `active_session_id`/`session_id` = `currentSessionID` | **non-null = 소유 맥 모드(①+②)**, **null = 흡수 맥 모드(②′)** |
| `p_device_id` | text \| null | null | ②/②′ 의 `device_id` = `deviceID` | null 이면 기기 행을 안 쓴다 |
| `p_opened_session` | bool | false | ② 의 `opened_session` = `ownsCurrentSessionStrongly` | 매 하트비트 **덮어쓴다**(기존 계약) |
| `p_last_input_at` | timestamptz \| null | null | ①②②′ 의 `last_input_at` = `advanceMeaningfulInput()` | null 이면 컬럼을 **건드리지 않는다**(본문 키 생략과 등가). work_tick 이 있는 서버는 away 스키마가 있으므로 `awayServerSupported` 게이트 없이 보내도 된다 |
| `p_seen_at` | timestamptz \| null | null → `now()` | ①② 의 `last_seen_at`/`updated_at` = 클라 `Date()` | 의미를 바꾸지 않으려면 지금처럼 자기 스탬프를 보낸다 |
| `p_since` | timestamptz \| null | null → 서버 KST 월요일 00:00 | ⑤ 의 `ended_at=gte.` = `koreanWeekStart(now)` | 클라 값을 보내면 ⑤ 와 글자 단위로 같다 |
| `p_include_meta` | bool | false | 팝오버 열림 && 60초 스로틀 통과(`refreshTeamMetaIfStale` 조건) | true 면 ⑧a+⑧b 를 `meta` 에 싣는다 |

**없는 인자와 이유**: `p_status`(틱 하트비트는 항상 `working` — `off_work` 전이는 `stopWork` 의 몫이지 틱이 아니다), `p_app_build`(앱 버전 보고는 profiles PATCH 실행당 1회이지 틱 요청이 아니다).

### 2.2 응답 — 단일 `jsonb`

```jsonc
{
  "v": 1,                                        // 계약 버전. 1 이 아니면 폴백(2.4)
  "server_now": "2026-08-31T12:51:03.000158+00:00",  // 트랜잭션 시각. 시계 차 진단용(판정에 쓰지 마라)
  "team_id": "…uuid…" | null,                    // p_team_id 에코
  "heartbeat": null | {                          // p_heartbeat=false → null
    "mode": "owner" | "input" | "skipped",       // owner=①+② 수행 / input=②′ 수행 / skipped=흡수 맥인데 관측 없음(쓰기 0)
    "status": "working" | "off_work",            // owner 만. 트리거가 강등했으면 off_work(열린 세션 없음)
    "active_session_id": "…" | null,             // owner 만(강등 시 null)
    "last_seen_at": "…",                         // owner 만
    "device": true | false                       // 기기 행을 썼는가
  },
  "statuses":        [ …③ 의 행 그대로 (updated_at desc) … ],   // → [WorkStatusRow]
  "sessions_active": [ …④ 의 행 그대로… ],                       // → [WorkSessionRow]
  "sessions_weekly": [ …⑤ 의 행 그대로 (id/duration 없음)… ],    // → [WorkSessionRow]
  "sessions_since":  "2026-08-30T15:00:00+00:00",                // ⑤ 에 실제로 쓴 창 시작
  "devices":         [ …⑥ 의 행 그대로… ],                       // → [WorkStatusDeviceRow]
  "away":            { …⑦ away_sync() 반환값을 한 바이트도 안 바꾼 것… },   // → AwaySyncResponse
  "meta": null | {                                              // p_include_meta=false → null
    "memberships": [ …⑧a 의 행 그대로 (0 또는 1행)… ],           // → [MembershipRow]
    "invite_code": [ {"invite_code": "…"} ]                     // ⑧b 의 행 그대로 (0 또는 1행) → [InviteCodeRow]
  }
}
```

조각별 **행 모양**(키 집합 — 사후 단언이 못 박는다):

| 조각 | 행의 키(정확히 이 집합) | null 규약 |
|---|---|---|
| `statuses[]` | `user_id,status,updated_at,last_seen_at,active_session_id,profiles` | `profiles` 는 `{display_name,avatar_url}` 객체 또는 **null**(PostgREST 다대일 임베드와 동일). `avatar_url` 없으면 키는 있고 값 null |
| `sessions_active[]` | `id,user_id,started_at,ended_at,duration_seconds` | `ended_at`/`duration_seconds` 는 null 로 온다(열린 세션) |
| `sessions_weekly[]` | `user_id,started_at,ended_at` | id/duration **없음**(v0.2.38 이 뺀 그대로) |
| `devices[]` | `user_id,device_id,session_id,last_seen_at,opened_session` | `session_id` null 가능 |
| `meta.memberships[]` | `team_id,role,teams` | `teams` 는 `{name,weekly_goal_hours}` 또는 null |

④ 와 ⑤ 를 한 배열로 합치지 않은 이유: 두 GET 의 컬럼 집합이 다르다. 합치면 행 모양이 바뀐다(원칙 1 위반).
`last_input_at` 은 **어느 팀 조각에도 싣지 않는다**(20260820010000:45-49 — 남의 마지막 입력 시각 노출 금지; 사후 단언 (3)이 소스에서 확인).

타임스탬프 표기는 Postgres `to_json(timestamptz)` = PostgREST 와 동일(`2026-08-31T12:51:03.000158+00:00`, 소수초 유무 섞임) → `SupabaseWorkService.parseDate` 가 그대로 읽는다.
uuid 는 소문자로 내려온다(Swift `UUID().uuidString` 은 대문자 — 비교는 지금처럼 `canonicalSessionID` 로).

### 2.3 부작용(하트비트) — 기존 요청과의 등가표

| 모드 | 조건 | 수행 | 트리거 |
|---|---|---|---|
| owner | `p_heartbeat && p_session_id != null` | ① `work_statuses` upsert `(team_id,user_id,status='working',active_session_id,last_seen_at=p_seen_at,updated_at=p_seen_at,last_input_at=coalesce(p,기존))` → ② `work_status_devices` upsert `(…,session_id,last_seen_at,updated_at,last_input_at=coalesce(p,기존),opened_session)` | `work_statuses_require_open_session` 이 열린 세션 없으면 `off_work`/null 로 강등(생존신호는 보존) — 응답 `heartbeat.status` 로 보인다 |
| input | `p_heartbeat && p_session_id == null && p_device_id != null && p_last_input_at != null` | ②′ 기기 행에 `last_input_at` **만**. `session_id/last_seen_at/opened_session` 은 절대 안 건드린다(v0.2.16 세션 강탈 방지 계약) | — |
| skipped | `p_heartbeat && p_session_id == null && (device 또는 관측 없음)` | 쓰기 0 | — |
| — | `p_heartbeat == false` | 쓰기 0, `heartbeat: null` | — |

기존 경로와 **의도적으로 다른 점 하나**: 기존엔 ① 성공 후 ② 가 실패해도 ① 은 남았다(별도 요청·별도 catch). work_tick 에서는 ② 실패 = 전체 롤백(원칙 4). ② 가 실패할 수 있는 원인은 RLS(①도 같이 실패) 뿐이라 실효 차이는 없다.

### 2.4 버전 규약

- `v=1` 의 조각 모양은 **바꾸지 않는다**. 키를 **더하는** 것은 v 를 올리지 않는다(클라는 모르는 키를 무시한다 — `Decodable` 기본 동작).
- 키를 빼거나 타입을 바꾸거나 조각의 의미를 바꾸면 **v 를 올린다**(또는 새 함수명). 클라는 `v != 1` 이면 그 세션 동안 폴백 경로를 쓴다(열거값 확장엔 능력 협상 원칙).
- `heartbeat.mode` 에 새 값이 생기면 클라는 모르는 값을 "쓰기 여부 불명" 으로 접고 **아무것도 추론하지 않는다**(지금도 ack 로 상태를 바꾸지 않는다).

### 2.5 오류

| HTTP / SQLSTATE | 언제 | 클라 처리 |
|---|---|---|
| 404 `PGRST202` | 함수 없음(db push 전) 또는 **모르는 인자 키**를 보냄 | `.databaseSchemaMissing` → work_tick 을 이 실행 동안 끄고 폴백. **이 틱은 폴백 경로로 즉시 수행**(하트비트 유실 금지) |
| 401/403 `42501` | anon 호출 / EXECUTE 회수(서버측 킬스위치) / RLS 위반(남의 팀에 하트비트) | 42501 은 "서버가 껐다"로 보고 끄고 폴백. 401 은 기존 `withSessionRetry` 의 토큰 갱신 경로 |
| 400 `22023` | `p_heartbeat=true` 인데 `p_team_id=null` | 클라 버그. 폴백 + 진단 로그 |
| 400 `23514/23503` 등 | 제약 위반(정상 경로엔 없다) | 폴백(기존 경로가 같은 오류를 내면 그쪽 규약대로) |
| 5xx / 타임아웃 | 무료플랜 일시정지·네트워크 | 기존 하트비트 실패와 같다: 조용히 다음 틱. **연속 3회 실패면 1시간 폴백**(폭주 방지) |

---

## 3. 설계 결정·편차(정직하게)

1. **`p_seen_at` 를 받는다(서버 now() 로 바꾸지 않았다).** 기존 `last_seen_at` 은 클라 자기 시계다. 시계 어긋남의 약점은 알지만 "의미 불변" 이 우선이다. 클라가 null 을 보내면 서버 시각으로 떨어지므로 개선은 클라 한 줄로 가능하고, `server_now` 로 어긋남을 먼저 계측한다.
2. **PostgREST `max_rows=1000` 절단은 재현하지 않았다.** 팀당 주간 세션은 실측 최대 11행이라 도달 불가. 도달하면 기존 경로가 조용히 잘라내던 것을 work_tick 은 전부 준다(더 옳은 쪽).
3. **정렬**: ③ 은 `updated_at desc` 를 그대로. ④⑤⑥ 은 기존 GET 이 정렬을 지정하지 않았으므로(물리 순서) `started_at,id` / `user_id,device_id` 로 결정적으로 고정했다. 클라는 순서에 의존하지 않는다(딕셔너리 그룹핑).
4. **away 조각의 실패는 삼키지 않는다.** 기존 클라는 ⑦ 실패를 "모른다"로 접었다. work_tick 에서 `away_sync()` 가 예외를 내면 틱 전체가 실패하고 클라는 폴백 경로에서 같은 ⑦ 을 다시 부른다 → 같은 결과에 도달한다. 서브트랜잭션으로 삼키는 쪽이 오히려 "조용한 부분 성공" 이다.
5. **흡수 맥 관측 없음은 'skipped' 로 명시**한다(예외로 거절하지 않는다). 거절하면 그 상태의 클라가 매 틱 실패 → 팀 상태가 영영 안 갱신된다.
6. **`p_status`/`p_app_build` 를 두지 않았다**(2.1). 오케스트레이터 초안엔 있었으나 정찰 결과 틱이 보내는 값이 아니다.
7. **프로브의 역할 전환·복귀 규약(2026-08-31 1차 적용 실패의 교훈).** 호출자 자격 실증은 `set local role authenticated/anon`, 검증 조회는 **실행 역할로 복귀한 뒤**. 복귀는 `RESET ROLE` 이 아니라 `set local role <처음에 캡처한 실행 역할>` 이다 — CLI 의 링크드 연결은 세션 사용자가 표 권한 없는 별도 역할이고 `set role postgres` 로 올라와 있어서, RESET ROLE 이 그 세션 사용자로 떨어져 검증 SELECT 가 42501 로 죽었다(로컬 셰임 migrator 모드로 같은 줄에서 재현·확정; 이번 실패의 원인은 authenticated 의 ACL 이 아니다 — 같은 프로브에서 work_tick 자신은 authenticated 자격으로 work_statuses 를 읽는 데 성공했고, anon 키 REST 로 5개 표 200 `[]` 을 확인했다). 전환 가능 여부는 pg_has_role 추정이 아니라 **실제 전환 드라이런**으로 판정하고, 첫 복귀 직후 `current_user` 를 검증한다. 전환 불가 환경이면 NOTICE 로 알리고 7/7 을 돈다(INVOKER 여부는 (1)이 별도로 못 박는다). 1차 적용에서 `set local role authenticated` 가 성공한 것이 관측됐으므로 재적용은 9/9 가 기대값이다.
8. **프로브 픽스처는 `auth.users` 에 직접 insert** 한다(가입 트리거 → profiles). 권한이 없으면 행동 프로브를 통째로 건너뛰고 NOTICE 로 알린다(구조 단언 (1)~(5)는 항상 돈다). 모든 픽스처는 센티널 예외로 롤백되고 (7)이 0바이트 잔존을 되묻는다.

---

## 4. 클라이언트 통합 지침 (S3-클라 트랙용)

### 4.1 킬스위치·가용성 상태
```swift
// WorkTimerStore (또는 SupabaseWorkService) — 컴파일 타임 킬스위치. false 면 아래 전부 죽고 지금 경로 그대로.
static let workTickEnabled = true
// 실행 단위 가용성. 404/PGRST202·403/42501·v≠1 → false 로 내리고 이 실행 동안 폴백. 연속 5xx 3회 → 1시간 뒤 재시도.
@ObservationIgnored var workTickAvailable = true
```
서버측 킬스위치는 `revoke execute on function public.work_tick(…) from authenticated` 한 줄이다(클라는 42501 → 폴백).

### 4.2 서비스 층 — 요청/응답 타입(`SupabaseWorkModels.swift`)
```swift
struct WorkTickRequest: Encodable {          // encoder 가 convertToSnakeCase → p_team_id …
    let pTeamId: String?                     // ★ nil 이어도 키가 나가야 한다 → Optional 을 명시 인코딩(encode(_:forKey:) 로 null 을 쓴다)
    let pHeartbeat: Bool
    let pSessionId: String?                  // nil 이면 키 생략(→ 기본 null = 흡수 맥 모드)
    let pDeviceId: String?
    let pOpenedSession: Bool
    let pLastInputAt: String?                // nil 이면 키 생략 = "컬럼 안 건드림"
    let pSeenAt: String                      // dateFormatter.string(from: Date()) — 기존 스탬프 그대로
    let pSince: String                       // dateFormatter.string(from: koreanWeekStart(now))
    let pIncludeMeta: Bool
}
struct WorkTickResponse: Decodable {         // decoder 가 convertFromSnakeCase
    let v: Int
    let serverNow: String
    let teamId: String?
    let heartbeat: Heartbeat?                // struct Heartbeat: Decodable { let mode: String; let status: String?; let activeSessionId: String?; let device: Bool? }
    let statuses: [WorkStatusRow]            // ← 기존 디코더 그대로
    let sessionsActive: [WorkSessionRow]
    let sessionsWeekly: [WorkSessionRow]
    let sessionsSince: String?
    let devices: [WorkStatusDeviceRow]
    let away: AwaySyncResponse               // ← 기존 디코더 그대로(camelCase 키는 convertFromSnakeCase 에 영향 없음 — 지금도 그렇게 읽는다)
    let meta: Meta?                          // struct Meta: Decodable { let memberships: [MembershipRow]; let inviteCode: [InviteCodeRow] }
}
```
`Swift 합성 Encodable` 은 nil Optional 의 키를 **생략**한다. `p_team_id` 만은 생략하면 PGRST202 라 **반드시 null 로 명시**한다(커스텀 `encode(to:)` 한 줄).

### 4.3 조립 — 디코더 재사용 지점
- `SupabaseWorkService.fetchTeamStatuses` 의 후반(행 → `TeamMemberStatus` 매핑: `activeByUser / weeklyDurations / todayDurations / devicesByUser`)을 `assembleTeamStatuses(rows:active:weekly:devices:now:) -> [TeamMemberStatus]` 로 **분리**하고, 기존 GET 경로와 work_tick 경로가 **같은 함수**를 부른다. 스냅샷 조립 로직이 두 벌이 되면 안 된다.
- `awaySync(from:)` 은 이미 순수 함수다 — `response.away` 를 그대로 넣는다.
- `fetchOwnMembership` 의 튜플 변환도 `membership(from: MembershipRow)` 로 분리해 `meta.memberships.first` 에 재사용.

### 4.4 스토어 루프 — 호출 지점과 상태별 인자
`startStatusRefreshLoop` 본문의 `sendHeartbeatIfWorking → refreshTeamStatus → refreshAwayStateIfNeeded` 세 호출을 **`workTickIfPossible()` 하나로 대체**하되, 가드·세대(generation) 규약은 그대로 옮긴다:

| 상태 | `p_heartbeat` | `p_session_id` | `p_device_id` | `p_opened_session` | `p_last_input_at` | `p_include_meta` |
|---|---|---|---|---|---|---|
| 근무중·소유 맥 | true | `currentSessionID` | `deviceID` | `ownsCurrentSessionStrongly` | `advanceMeaningfulInput(now)` | 아래 규칙 |
| 근무중·흡수 맥 | true | **nil** | `deviceID` | false | 관측(있으면) | 〃 |
| 비근무 | false | nil | nil | false | nil | 〃 |
| 무소속(`currentTeamID == nil`) | false | — | — | — | — | false (`p_team_id: null`) |

- `p_include_meta`: `isMenuPresented && now - lastTeamMetaRefreshAt >= 60` 일 때 true 로 보내고 `lastTeamMetaRefreshAt` 을 갱신. `setMenuPresented(true)` 의 `refreshTeamMetaIfStale()` 은 그대로 두되, 같은 스탬프를 보므로 이중 발사가 없다.
- 비근무 away 120초 스로틀(`awaySyncIdleThrottleSeconds`): work_tick 은 어차피 틱마다 away 를 실어 오므로 **비근무에서도 매 틱 반영**해도 된다(요청 수 증가 0). 기존 스로틀 변수는 폴백 경로용으로 남긴다.
- 응답 처리 순서는 기존과 같다: (1) `heartbeat` 는 **무시**(진단 로그만 — 지금도 ack 로 상태를 바꾸지 않는다) → (2) `assembleTeamStatuses` → `teamMembers` 반영 → `detectTeamReactions` → `autoCloseAbandonedOwnSessionIfNeeded` → `applyRemoteOwnStatus` → `scavengeAbandonedTeamSessionsIfNeeded` → (3) `applyAwaySync(awaySync(from: response.away))` → (4) meta 있으면 `currentTeamID/teamName/teamGoalSeconds/teamRole/myTeamInviteCode` 갱신(기존 `refreshTeamMeta` 의 != 가드·`teamGoalWriteGeneration` 스냅백 방지 그대로).
- **세대 가드**: 발사 전 `sessionGeneration`/`workStateWriteGeneration` 캡처 → 응답 반영 전 비교(기존 `refreshTeamStatus` 와 동일). 하트비트 결과는 세대와 무관하게 서버에 이미 반영된 것이므로 되돌리지 않는다.
- 팝오버 즉시 새로고침(`.task` 의 `refreshTeamStatus()`, 15초 스로틀)은 **`p_heartbeat=false` 의 work_tick** 으로 보낸다(하트비트를 틱 밖에서 추가로 쓰지 않는다 — 지금도 `refreshTeamStatus` 는 하트비트를 안 보낸다).

### 4.5 폴백 규칙(2.5 의 표와 같다)
```
workTickEnabled && workTickAvailable ? work_tick 1회
  성공(v==1)      → 반영
  404/PGRST202    → workTickAvailable=false; **이 틱을 기존 3함수로 즉시 수행**
  403/42501       → 〃(서버가 껐다)
  v != 1          → 〃(계약 협상 실패)
  기타/5xx        → 기존 3함수로 즉시 수행; 연속 3회면 1시간 동안 기존 경로
그 외             → 기존 3함수(sendHeartbeatIfWorking / refreshTeamStatus / refreshAwayStateIfNeeded)
```
기존 3함수는 **삭제하지 않는다**(폴백 + 구서버 대응). 하트비트 유실 창을 만들지 않는 것이 이 규칙의 전부다.

### 4.6 테스트에서 못 잡는 것(스텁 한계 — 반드시 두 대 프로브)
`URLProtocolStub` 은 보낸 키 집합을 해석하지 않는다. **키 이름 오타(예 `p_session`)는 단위 테스트에선 초록이고 실서버에선 매 틱 404 → 조용한 폴백**이다. 단위 테스트엔 최소한 "보낸 JSON 의 키 집합 == 2.1 의 집합" 소스 계약 테스트를 두고, 실증은 6절로 한다.

---

## 5. 배포 순서와 명령 (오케스트레이터)

**순서: 서버 먼저 → 앱.** 구클라는 새 함수를 모르고, 신클라는 함수가 없으면 폴백하므로 어느 순서든 죽지는 않지만, 서버가 먼저여야 신클라 첫 실행부터 이득이 난다. 이 파일은 함수 추가만이라 **적용 즉시 구클라(빌드 38~46)에 영향 0** 이다(사후 단언 (4)가 임베드 축 불변을 확인).

### 5.1 적용 전(읽기 전용)
```sh
cd /Users/yesung/check
set -a; source .env.local; set +a
supabase projects list                      # ★ 계정 함정: xfnhfjvubetkdnfkfljg 가 보이는 계정인지(아니면 supabase login)
supabase link --project-ref xfnhfjvubetkdnfkfljg
supabase migration list                     # 20260831120000 이 Local 에만 있고 Remote 에 없어야 한다
python3 <scratchpad>/s3/verify_prod_work_tick.py   # 적용 전엔 "OpenAPI 존재" 와 "anon 404" 두 항목이 FAIL 로 나오는 것이 정상(=미적용)
```

### 5.2 적용
```sh
supabase db push                            # (또는 supabase migration up --linked) 20260831120000_work_tick_rpc.sql 하나만 올라간다
# 1차 적용(2026-08-31)은 프로브의 RESET ROLE 이 세션 사용자로 떨어져 42501 로 실패했고 깨끗이 롤백됐다(rpc 404·이력 미기록).
# 수정본은 실행 역할을 캡처해 명시 복귀한다 — 로컬에서 "세션 사용자 migrator → set role postgres" 모양으로 9/9 재현·통과.
# 출력에서 NOTICE 를 확인한다(문구 끝에 "실행 역할 postgres, 세션 사용자 <…>" 가 붙는다 — 세션 사용자 이름을 보고에 남겨라):
#   "work_tick 행동 검증 통과(9/9 묶음)"  → RLS 포함 전부 실증
#   "… 통과(7/7 묶음, RLS·anon 단언은 실행 롤 제약으로 건너뜀)" → INVOKER 는 (1)로 보장, RLS 실증은 6절 실기기로
#   "행동 프로브 건너뜀: … auth.users 에 픽스처를 만들 수 없습니다" → 구조 단언만 통과, 6절 실기기 필수
# ERROR 로 멈추면 그 메시지가 곧 원인이다(전부 "…, 배포 중단" 문구). 롤백은 자동(단일 트랜잭션).
```
NOTICE 가 출력에 안 보이면 Supabase 대시보드 SQL 에디터에서 파일의 `do $assert$ … $assert$;` 블록만 다시 실행해도 된다(읽기·롤백 전용, 프로덕션 행 변화 0).

### 5.3 적용 후 검증(읽기 전용 — service_role 은 RLS 를 못 타므로 모양·값 등가만 본다)
```sh
python3 <scratchpad>/s3/verify_prod_work_tick.py   # 전부 PASS 여야 한다: 존재 / anon 401|403 / service_role 200·v=1·빈 배열·away invalid / 21개 팀 조각 == 개별 GET
# 수동 한 줄씩:
URL=https://xfnhfjvubetkdnfkfljg.supabase.co; ANON=$CHECK_SUPABASE_ANON_KEY; SR=$CHECK_SUPABASE_SERVICE_ROLE_KEY
curl -s -o /dev/null -w '%{http_code}\n' -X POST $URL/rest/v1/rpc/work_tick -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' -d '{"p_team_id":null}'   # 401|403 (404=미적용, 200=유출)
curl -s -X POST $URL/rest/v1/rpc/work_tick -H "apikey: $SR" -H "Authorization: Bearer $SR" -H 'Content-Type: application/json' -d '{"p_team_id":null}' | head -c 400; echo   # {"v":1,…,"away":{"status":"invalid",…}}
curl -s "$URL/rest/v1/work_statuses?select=user_id,profiles(display_name)&limit=1" -H "apikey: $SR" -H "Authorization: Bearer $SR" -o /dev/null -w '%{http_code}\n'   # 200 — 기존 임베드 생존(release.md 1-2)
```
서비스 롤 `work_tick` 호출은 `p_heartbeat` 를 생략하므로 **쓰기 0건**이다(`heartbeat: null`). 프로덕션에 `p_heartbeat:true` 를 service_role 로 보내지 마라(uid 없음 → 42501 로 거절되긴 한다).

### 5.4 롤백
```sql
-- 함수만 제거하면 신클라는 다음 틱부터 404 → 폴백. 표·데이터 변화 없음.
drop function public.work_tick(uuid, boolean, uuid, text, boolean, timestamptz, timestamptz, timestamptz, boolean);
-- 또는 잠깐 끄기: revoke execute on function public.work_tick(uuid, boolean, uuid, text, boolean, timestamptz, timestamptz, timestamptz, boolean) from authenticated;
```

---

## 6. 두 대 프로브 체크리스트(앱 배포 전, 실기기)

맥 A = work_tick 빌드, 맥 B = 구빌드(예 46), 같은 계정 또는 같은 팀 계정. Proxyman/Charles 로 A 의 요청을 본다.

- [ ] **요청 수**: A 근무중 30초 창에 `POST /rpc/work_tick` **1건**이고 `work_statuses`/`work_status_devices`/`work_sessions` GET·POST, `rpc/away_sync` 가 **0건**(200 응답, `v:1`). 하나라도 남아 있으면 폴백 중이다 → 응답 코드 확인(404 면 키 이름 오타).
- [ ] **하트비트 등가**: B 의 팀 목록에서 A 가 `근무중`이고 90초 안에 신선(stale 아님). service_role 로 `work_statuses` 행의 `last_seen_at/updated_at` 이 A 의 스탬프로 30초마다 전진, `last_input_at` 이 A 의 입력 관측을 따라간다.
- [ ] **기기 행**: `work_status_devices` 에 A 의 `device_id` 행이 `session_id = A 세션`, `opened_session=true` 로 전진. B 가 A 의 세션을 흡수하지 않는다(소유권 규칙 불변).
- [ ] **흡수 맥 모드**: 같은 계정 B(구빌드)로 근무 시작 → A 는 흡수 상태. A 의 틱은 `p_session_id` 없이 나가고 `heartbeat.mode == "input"`; A 의 기기 행은 `last_input_at` 만 바뀌고 `session_id/last_seen_at` 은 그대로.
- [ ] **좀비 강등**: A 근무중 상태에서 service_role 로 A 의 열린 세션을 닫으면(기존 스캐빈저와 같은 방식) 다음 틱의 `heartbeat.status == "off_work"` 이고 A 의 화면이 폴링으로 비근무로 내려간다(기존과 같은 시점).
- [ ] **away/복원**: A 에서 잠자기 → 깨움 → 복원 배너가 기존과 같은 조건에 뜬다(`away` 조각이 `restorable` 을 싣는다).
- [ ] **팀 메타**: B 에서 팀 목표를 바꾸면 A 팝오버 재오픈 60초 안에 반영(`meta` 조각). 팝오버 닫힌 상태에선 `p_include_meta=false` 로 나간다(요청 바디에서 확인).
- [ ] **무소속 계정**: 팀 없는 계정으로 A 로그인 → `p_team_id:null`, 응답 팀 조각 `[]`, 화면 문구 "소속 팀이 없어요 — 팀 코드로 참여해 주세요" 그대로.
- [ ] **RLS 실증**: A 의 토큰으로 curl `{"p_team_id":"<남의 팀 uuid>"}` → 200 이되 `statuses:[]`(RLS). `{"p_team_id":"<남의 팀>","p_heartbeat":true,"p_session_id":"<아무 uuid>","p_device_id":"x"}` → 403(42501).
- [ ] **폴백**: 서버에서 `revoke execute … from authenticated` → A 다음 틱 403 → 즉시 기존 7건 경로로 돌아가고 하트비트 공백이 30초를 넘지 않는다(B 화면에서 A 가 stale 로 안 떨어진다). `grant` 되돌리면 앱 재시작 후 work_tick 복귀.
- [ ] **바이트 계측**: 30초 창의 송신 바이트(헤더 포함)가 이전 대비 ~1/7 (수신은 거의 동일 — 원칙 1).

---

## 7. 남은 위험(숨기지 않는다)

1. **역할 전환은 1차 적용에서 성공이 관측됐다**(세션 사용자 ∈ authenticated) → 재적용은 9/9 기대. 다만 세션 사용자가 `postgres` 의 멤버가 아닌 연결(예: 다른 도구)에서는 `set local role postgres` 복귀가 실패해 배포가 명시적 오류로 멈춘다(조용한 오판은 없다). 그 경우 `supabase db push`/`migration up` 으로 다시 적용하면 된다.
2. **키 이름 오타 = 조용한 폴백.** 스텁 테스트가 못 잡는다(4.6). 6절 첫 항목이 유일한 그물이다.
3. **연속 실패 폭주**: 지속 오류(예 22023 클라 버그)면 매 틱 work_tick 실패 + 폴백 7건 = 지금보다 1건 더 나간다. 4.5 의 "3회 → 1시간" 이 상한을 만든다.
4. **`p_seen_at` 클라 시계 유지**: 시계가 어긋난 맥은 지금처럼 자기 상태가 남에게 stale 로 보일 수 있다(불변). `server_now` 로 계측 후 2단계에서 서버 시각으로 바꿀 수 있다(클라 한 줄).
5. **응답 크기 불변**: 수신량은 그대로다(원칙 1). 팀 3명 기준 ~3~5KB/틱. 2단계(서버 집계) 전까지는 송신 헤더 절감(≈7×1.15KB)만 이득이다.
6. **한 트랜잭션 안의 순서**: 하트비트 → 조회 → away 순으로 같은 트랜잭션에서 돈다. 각 문장은 새 스냅샷(READ COMMITTED)이라 자기 쓰기를 읽는다(프로브 ⓑ가 확인). 기존 경로(요청 4~5개가 수십 ms 간격)와 실효 차이 없음.
7. **`max_rows` 절단 미재현**(3절 2번) — 이득이지 손해가 아니지만 "행 단위 동일" 의 문자적 예외다.
