I'll start by reading the audit report, then verify key claims against the actual code before writing the master plan.
Now let me verify the critical code claims that the whole plan hinges on.
# aing-check v0.2.14 이후 마스터 실행 설계

> 감사 리포트 `audit-v0.2.14.md` + 6개 클러스터 설계 + 적대적 리뷰를 통합한 **작업 지시서**.
> 항목 ID는 감사 리포트 기준. 리뷰에서 수정안이 나온 항목은 **수정된 최종 형태**만 적었다.
> 사실 확인: `startStatusRefreshLoop`(WorkTimerStore.swift:739-774), `applyRemoteOwnStatus`(WorkTimerStoreSync.swift:595-650), `sendHeartbeatIfWorking`(:272-291), `withSessionRetry`(WorkTimerStoreAuth.swift:388-421), `package-notarized.sh:15/36/40`, `build-local.sh:65`, 최신 마이그레이션 `20260726010000`, 테스트 476개 — 전부 실코드로 재확인했다.

---

## 설계 원칙

**1. 서버 먼저, 앱 나중 — 예외 없음.**
새 컬럼·새 RPC를 앱이 먼저 쓰면 실패가 조용하지 않다. `startWork`의 2단계가 `upsertStatus`(SupabaseWorkService.swift:226)라서, 컬럼 하나가 없으면 세션 INSERT는 성공하고 상태 upsert만 PGRST204로 죽어 **큐가 고착되고 서버에 유령 열린 세션이 남는다**(D5 경로). 그래서 마이그레이션은 전부 웨이브 0/웨이브 앞머리에서 `supabase db push` → SQL Editor 육안 확인 → 그다음 공증/배포다. 반대로 서버 변경은 앱 없이 단독으로 나갈 수 있어야 한다(순수 추가 또는 시그니처 불변).

**2. 구조 분할은 맨 마지막, 단독 커밋, 직렬.**
충돌 비용이 비대칭이다. 분할은 리베이스가 필요 없는 유일한 작업이다 — 언제든 현재 파일을 열어 다시 시작할 수 있다. 반면 기능 패치는 앵커가 사라지면 손으로 재적용해야 하고, 그 순간이 로직이 섞여 드는 지점이다. UX 웨이브가 `CheckMenuView.swift`에서 건드릴 여섯 줄(`:834 :908 :976 :2034 :2037 :2319`)이 **여섯 개 서로 다른 새 파일로 흩어지므로**, 분할이 먼저면 여섯 패치가 전부 재작성 대상이다. 또 "476개 동일 통과 + 정렬 diff 12줄"은 분할이 그 커밋의 유일한 변경일 때만 증거다. `git worktree list`에 v0.1.7 시점(`c1ba0c8`) 포크가 5개 살아 있으니 **병렬 워크트리 금지**.

**3. 하위호환 마지노선: v0.2.10 클라의 기존 요청이 바이트 하나도 달라지면 안 된다.**
`20260726010000` 헤더가 세운 원칙 그대로다. 판정 기준 셋 — (a) RETURNS TABLE 시그니처 불변이면 `create or replace`, 바뀌면 `drop function` 선행, (b) 새 컬럼은 nullable(구버전 upsert가 본문에 없는 컬럼을 건드리지 않으므로 값 보존), (c) RLS 정책은 **좁히지 말고 넓히거나 대칭으로만** 맞춘다. 혼합 함대에서 편측 수정인 항목(D2)은 그 사실을 계약에 명시한다.

**4. 거절하지 말고 클램프한다.**
오프라인 큐는 한 번 400을 받으면 영구 재시도로 고착된다(D5). 그래서 서버 제약을 새로 걸 때는 하우스 선례(`enforce_open_session_for_working` = 거절 대신 강등)를 따라 **BEFORE 트리거로 조용히 바로잡고**, `check` 제약은 그 뒤의 백스톱으로만 둔다. `check (ended_at >= started_at)` 단독 추가는 금지.

**5. 첫 웨이브는 되돌리기 한 줄짜리만.**
D1은 `store.activateStoredSessionOnLaunch()` 한 줄 삭제로 롤백된다. D2/O2처럼 상태기계·서버 계약을 바꾸는 것은 앞 웨이브가 실사용에서 하루 이상 굴러간 뒤에 간다.

---

## 릴리스 웨이브

### 웨이브 0 — 서버·릴리스 인프라 (앱 릴리스 없음)

**테마**: 앱 코드 0줄. 정문을 닫고, 다음 웨이브들이 설 바닥을 깐다.

| ID | 제목 |
|---|---|
| R9-a | 셀프 가입 차단(대시보드) + e2e 계정 발급 경로 재작성 |
| O5 | 조회 인덱스 4개 |
| O6+R9-b | 리그 주 창 필터 + 사라진 무소속 가드 복구 + 디렉터리 소속 게이트 |
| R9-c | 쓰기 정책 대칭 + 세션 무결성 클램프 트리거 |
| O7-invite | `pg_sleep(0.3)` 제거 + 약한 참여코드 회전(+회전 로그 표) |
| NF4 | `work_sessions.app_version` 컬럼 (앱 필드는 웨이브 1) |
| R5+R1 | 패키징 스크립트: 죽은 인증서 가드 부활·지문 고정·spctl 게이트화·키체인 선점검 |
| R2 → R3 → R4 | 버전 단일 원본 → 태그 소스 사슬 → 릴리스 노트 갱신 |
| R7, R8 | 롤백 절차 문서 + pg_cron 확인 쿼리 |
| R6 | CI 신설 |

**선행 조건 [사람]**
1. Supabase 대시보드 Auth → 셀프 가입 OFF (R9-a). **이게 0순위다** — 나머지 보안 항목은 전부 그 뒤에 남는 잔재를 걷는 2선 방어다. 순서를 뒤집으면 큰 SQL을 먼저 굴리고도 정문은 계속 열려 있다.
2. `supabase projects list`로 계정 확인(다중 계정 → `db push` 403 조용한 실패 전례). 그다음 `supabase db push`.
3. SQL Editor에서 `select jobname, schedule, active from cron.job order by jobname;` → `close-abandoned-work`가 `active = t`인지 확인. **웨이브 2(D2)의 선행조건**이므로 여기서 미리 확정한다.
4. O7-invite 적용 **전에** `select id, name, invite_code from public.teams where invite_code !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$';` 결과를 따로 저장. (마이그레이션이 로그 표에도 남기지만 이중 안전망.)

**왜 이것들이 함께 가는가**
전부 앱 코드를 한 줄도 안 바꾼다 → `## <버전>` 게이트에 걸리지 않고 main에 커밋만 하면 된다. 마이그레이션 6개는 앱 없이 단독으로 나갈 수 있게 설계했고(전부 순수 추가 또는 시그니처 불변), 릴리스 스크립트는 v0.2.15를 **패키징하기 전에** 들어가야 R2/R3 게이트가 처음부터 작동한다.

**검증**
- `curl -X POST $SUPABASE_URL/auth/v1/signup ...` → `422 signup_disabled`
- `swift test` 476개 그대로 + 신규 단위 2건(`signup_disabled` 문구 매핑, `TeamExitOutcome` 매핑은 웨이브 4)
- `CHECK_E2E=1 swift test` — R9-a의 헬퍼 재작성이 들어간 뒤 s01~s10 전부 통과 (**이게 이 웨이브의 핵심 실증**)
- `explain (analyze, buffers) select * from public.team_weekly_leaderboard();` → `Bitmap Index Scan on work_sessions_ended_at`
- `./scripts/release-brew.sh 0.2.4 --dry-run` → 태그 스큐 경고가 뜨는지(v0.2.3/v0.2.4가 같은 커밋 `40c1b3a1`을 가리키는 실제 과거 사고 재생)

---

### 웨이브 1 — v0.2.15 「부팅부터 살아 있는 앱」

**테마**: 재부팅 후 아이콘을 안 눌러도 앱이 동작하고, 그 대가로 늘어난 전력·egress를 같은 릴리스에서 되갚는다.

| ID | 제목 |
|---|---|
| D1 | 실행 시 저장 세션 1회 킥 + 오프라인 부팅 재확정 |
| N1-idle | 유휴 refresh 주기 300s → 600s |
| O1 | 콕찌르기 폴링을 근무 중으로 제한 |
| N2-menubar | 메뉴바에 퇴근 후에도 오늘 누적 + 티커 없는 유휴의 자정 롤오버 |
| N1-refresh | refresh grant 단일 비행 |
| N2-cancel | 취소 분기 8곳 |
| D3 | 12시간 마감 직전 시스템 유휴 확인 |
| O3, O4, O7-evict | 토큰 스캔 주기 완화 · 캐시 쓰기 스로틀 · evict 조건부 |
| D6-1 | 리프레시 토큰 만료가 "이미 가입된 이메일"로 뜨는 오분류 |
| NF4-app | 하트비트/세션에 `app_version` 실어 보내기 |
| N1-dead, N2-parser, N3-const, N5-privacy, N6-split | 구조·문서 정리 (런타임 영향 0) |

**선행 조건**: 웨이브 0 전부. 특히 R2가 들어가야 `CHANGELOG.md`의 `## 0.2.15`가 곧 앱 버전이 된다. NF4-app은 웨이브 0의 컬럼이 프로덕션에 있는지 SQL Editor로 눈으로 확인한 뒤에만.

**왜 이것들이 함께 가는가**
D1은 "앱이 언제부터 도는가"를 팝오버 오픈에서 프로세스 실행으로 바꾼다. 그러면 지금까지 **팝오버를 여는 동안만 존재하던 비용**이 24시간 상시 비용이 된다. D1 단독이면 유휴 요청이 사용자당 0 → 276회/시로 순증한다. O1이 240을 없애고 N1-idle이 나머지를 절반으로 깎아 18회/시가 된다. 반대로 O1의 유일한 부작용(무료플랜 7일 비활동 일시정지 방지 효과 상실)은 D1이 그대로 메운다 — **두 항목은 서로의 부작용을 상쇄하므로 반드시 같이 간다**.

셋 중 셋(D1의 `confirmMembershipIfNeeded`, N1의 슬라이스 개수, N2의 `rolloverIfNeeded`)이 **같은 함수 `startStatusRefreshLoop`(:739-774) 본문**을 건드린다. 따로 웨이브로 쪼개면 병합 충돌이 확정적이다.

N1-refresh + N2-cancel은 `withSessionRetry`의 같은 catch 블록이라 한 편집이다. 여기 먼저 넣어야 웨이브 2의 D2/D5 테스트가 취소 노이즈 없이 돈다.

**검증**
- `swift test` — 476 + 신규 약 25건
- **[사람] 실기기 1건 (D1의 유일한 미검증 가정)**: 재부팅 → 팝오버를 **열지 않고** 5분 방치 → 자동 근무 시작이 뜨는가. 안 뜨면 D1-R4(`CheckOverlayController.init`의 `syncNudgeScheduler()` 한 줄)가 처방이고, 그 줄은 이미 설계에 포함돼 있다.
- **[사람] 실측**: 로그인만 하고 방치 30분 → Charles/프록시 없이도 `refreshTask` 주기가 600초인지는 코드 핀 테스트로 갈음. 배터리는 `pmset -g log`의 wake 항목으로 대조(선택).
- 루프 최종 형태가 이 순서인지 확인:
```swift
await self?.confirmMembershipIfNeeded()   // D1 — teamID 없으면 큐 드레인이 throw 하므로 맨 앞
self?.rolloverIfNeeded()                  // N2 — 티커 없는 유휴의 자정 백스톱
await self?.retryPendingSync()
await self?.sendHeartbeatIfWorking()
await self?.refreshTeamStatus()
```

---

### 웨이브 2 — v0.2.16 「다기기 세션 안전」

**테마**: 맥 두 대를 켜 둬도 남의 세션이 과거 시각으로 잘리지 않는다. 이 웨이브가 이 계획에서 가장 위험하다.

| ID | 제목 |
|---|---|
| D2 | 흡수 세션 소유권 표식(+**하트비트 차단** — 리뷰가 잡은 치명 누락) |
| D5 | 23505 poison-pill 큐 처분 |
| D6-stopWork | `stopWork`에 nil-안전 세션ID 필터 |
| D4 | 로그아웃 확인 배너 + 미반영 큐 보존 |

**선행 조건**
- 웨이브 1이 실사용에서 **최소 3일** 굴러간 뒤. D1이 D2의 노출 범위를 '팝오버를 연 실행'에서 '켜져 있는 실행 전체'로 넓히므로, D1이 안정적인지 먼저 확인한다.
- **[사람] `close-abandoned-work` cron이 `active = t`** (웨이브 0에서 확인). D2가 로컬 마감 3종을 전부 막으므로 서버 스캐빈저가 백스톱이다. 미등록이면 D2를 넣지 마라.
- 마이그레이션 없음(전부 클라 변경).

**왜 이것들이 함께 가는가**
D5의 `surrenderLocalSessionToServer()`가 D2의 `adoptedRemoteSession`을 리셋하고, 회복 경로가 D2의 흡수 분기에 의존한다. D2 없이 D5를 넣으면 흡수 직후 잠자기 한 번에 그 세션이 다시 오마감된다. D6-stopWork는 D2+D5가 로컬 세션ID와 서버의 어긋남을 없앤 뒤에야 순이득이다.

D4는 독립이지만 `finishWorkBeforeQuit`의 가드를 D2와 공유하므로 같은 웨이브가 편하다.

**검증**
- `swift test` — 신규 약 18건. 특히 **대조군**이 핵심: `ownSessionStillAutoStopsOnWake`(플래그가 전부를 막지 않음), `ownSessionStillHeartbeats`, `transientFailureStillHaltsDrainInOrder`.
- **[사람] 2기기 실측 (이 웨이브의 유일한 진짜 증명)**: 맥 A에서 근무 시작 → 맥 B가 흡수(팀 패널에 '근무중') → 맥 B 덮개 닫고 10분 → 열기 → **맥 A의 근무가 계속 흐르는지**. 이어서 맥 A를 종료 → 10~15분 뒤 서버 스캐빈저가 마감하고 맥 B가 `(.offWork,.some)`로 내려가는지.
- `CHECK_E2E=1 swift test` — s09b(자리비움 자동마감)가 그대로 통과.

---

### 웨이브 3 — v0.2.17 「화면이 사실을 말한다」

**테마**: 표시 결함 일괄 정리 + 팀원 행 오늘 근무시간. 전부 클라 표시 전용, 마이그레이션 0.

| ID | 제목 |
|---|---|
| N2-clamp | `liveTodayDurationSeconds`의 KST 자정 클램프 (**NF1 선행 필수**) |
| NF1 | 팀원 행 보조줄에 '오늘 근무시간' |
| D6-2 | 토큰 공개 토글 스냅백 |
| D6-3 | 팀 목록 빈 자리의 유령 '팀원' 행 |
| D6-4 | 리그 패널 로딩/실패 3상태 + `syncMessage` 오염 제거 |
| D6-5 | 헤더 '이번 주'가 첫 왕복 동안 오늘 값으로 폴백 |
| D6-6 | 무소속 안내가 빨간 ⚠ 오류 배너로 |
| F1 | 푸터 [새로고침]이 보고 있는 패널을 갱신 |
| N1-retro | 회고 카드에 대상 주 날짜 범위(`7/21~7/27`) |
| O7-leaf | 비근무 팀원 행이 매초 `displayNow`를 읽는 문제 |

**선행 조건**: 없음(웨이브 2 머지 후). 순서만 **N2-clamp → NF1** 강제.

**왜 이것들이 함께 가는가**
전부 `CheckMenuView.swift`를 건드리는데 **구역이 전부 다르다**(`:834` 팀 목록 / `:908` 비근무 행 / `:976` 리그 / `:2034` 푸터 / `:2319` 무소속). 한 웨이브에 묶어야 분할(웨이브 4 후행)이 최신 파일 하나만 보면 된다. 하위호환 영향 0이라 위험도 낮다.

높이 예산에 영향을 줄 수 있는 항목은 **NF1 하나뿐**이다(D6-3의 자리 문구는 `minHeight: memberRowHeight`라 rowCount·높이 불변).

**검증**
- `swift test` — 신규 약 20건. **NF1 머지 전 필수**: `teamMemberRowWithSecondaryLineFitsRowBox`(자연 높이 ≤ 상자 높이, 절대 픽셀 단언 아님)가 초록인지. 빨간불이면 머지하지 말고 완화책 (a)→(b)→(c) 순으로.
- `windowHeightAdaptsToContentWithinCap`(CheckMenuRenderTests.swift:312)의 `manyMembers`/`steadyMembers` 헬퍼에 `todayDurationSeconds`를 채워 3줄 행이 실제로 그려지는 상태로 700pt 상한 재통과.
- **[사람]** `CHECK_PRESENCE_TEAM_SNAPSHOT_PATH`로 팀 패널 PNG 육안 확인(행 겹침 없음).

---

### 웨이브 4 — v0.2.18 「서버 통합 + 팀 관리」 + 후행 구조 분할

**테마**: 팀 현황 3-fanout을 1발로. 팀 탈퇴/추방. 그리고 모든 기능이 머지된 뒤 구조 분할.

| ID | 제목 |
|---|---|
| O2 | `team_status_snapshot` RPC (마이그레이션 + 앱, 폴백 래치) |
| N1-team | 팀 탈퇴/추방 RPC + owner 백필 + 자기 세션 읽기 정책 + 클라 자가감지 |
| NF2 | 별명(표시 이름) 변경 |
| NF3 | 콕찌르기 수신 거부 |
| — | **후행 커밋(릴리스 아님)**: N7 분할 → N8 `PanelListScaffold` → N9 마일스톤 키 |

**선행 조건**
- 마이그레이션 3개(`20260801010000_team_membership_exit.sql`, `..._poke_opt_out.sql`, `..._team_status_snapshot.sql`)를 **앱보다 먼저** push. `docs/release.md:63` 1-1 단계.
- N1-team은 웨이브 0의 R9-c(UPDATE 팀 게이트)가 이미 있어야 추방에 강제력이 생긴다.
- NF3는 웨이브 3의 D6-2가 고친 로더를 확장하므로 그 뒤.
- O2는 웨이브 0의 O5(`work_sessions_team_ended`)가 있어야 폴링 경로 계획이 확정적이다.

**왜 이것들이 함께 가는가**
넷 다 "서버 RPC + 앱 소비" 짝이고 `CheckMenuView`를 거의 안 건드린다(NF2/NF3의 UI는 팀 패널·찌르기 패널 헤더 국소). O2와 N1-team은 `refreshTeamStatus` 흐름을 공유하므로 한 번에 검증하는 게 낫다.

**후행 구조 분할이 여기 붙는 이유**: 사용자에게 보이는 변화가 0이라 CHANGELOG 항목이 없다 → 단독으로는 릴리스가 게이트에서 죽는다. main에 커밋만 하고 다음 기능 릴리스에 묻어간다.

**검증**
- `CHECK_E2E=1 swift test` — **s09i(`teamStatusSnapshotMatchesFanout`)가 이 웨이브의 유일한 진짜 증명**. 같은 순간에 스냅샷 RPC와 옛 3-fanout을 호출해 사람별 주간/오늘 초 차이 ≤2초.
- 분할 커밋: **정렬 멀티셋 diff가 정확히 12쌍**(`private struct X: View {` 11건 + `private static let rowSpacing` 1건). 그 외 한 줄이라도 나오면 순수 이동이 아니다 — 중단.
- 분할 커밋: `swift test` 476+α **테스트 수 불변**, 렌더 스냅샷 **치수 동일**(바이트 아님 — 여러 스토어가 `Date()` 상대 시각을 시드해 글리프가 흔들린다).

---

## 항목별 설계

---

## 웨이브 0

### R9-a 셀프 가입 차단
> 대시보드 토글 + `config.toml` 동기화 + e2e 계정 발급 경로 전면 재작성.

**변경 지점**: `supabase/config.toml:26`(`enable_signup`) · `:29`(`[auth.email] enable_signup`) / `Sources/check/SupabaseWorkHTTP.swift:137` / `Tests/checkTests/LiveE2ETests.swift:125`(E2EAdmin) · `:629 signUpCreatingE2ETeam` · `:645 signUpJoiningByCode` · `:856 s05_duplicateSignUp` / `docs/team-install.md`(신규 절)

**[사람] 대시보드 절차**
1. Authentication → Sign In/Providers → Email → "Allow new users to sign up" **OFF**
2. 실증: `curl -sS -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $ANON" -H 'content-type: application/json' -d '{"email":"probe@example.com","password":"Aa!12345678"}'` → `{"code":422,"error_code":"signup_disabled",...}`
3. 새 팀원 발급: Authentication → Users → Add user → 이메일/임시 비번 + **Auto Confirm User** + User Metadata `{"display_name":"홍길동"}`. 가입 트리거 `handle_check_auth_user`(20260711160000:189)가 그대로 `profiles.display_name`으로 넣는다.

**config.toml**
```toml
[auth]
# 프로덕션 셀프 가입은 대시보드에서 차단했다. 이 파일은 로컬 supabase start 전용이라 프로덕션에 효과가
# 없지만, true 로 남겨 두면 누군가 `supabase config push` 한 번으로 프로덕션을 다시 열어 버린다.
enable_signup = false

[auth.email]
enable_signup = false
```

**문구 하드닝** (`SupabaseWorkHTTP.swift:137`) — `error_code`가 없는 응답에서도 걸리게. `already/registered/exists` 가드(:134)보다 뒤라 기존 분류 불변.
```swift
        if (lowercased.contains("signup") && lowercased.contains("disable"))
            || lowercased.contains("signups not allowed") {
            return .signupDisabled
        }
```

**e2e 재작성 (같은 커밋 필수)** — 이걸 안 하면 `CHECK_E2E=1`이 s01부터 전멸한다.
```swift
// E2EAdmin (LiveE2ETests.swift:220 deleteUser 옆)
/// service_role 로 확인 완료 계정을 만든다. 셀프 가입을 끈 뒤 e2e 가 계정을 얻는 유일한 경로.
func createConfirmedUser(email: String, password: String, displayName: String) async throws {
    let body = try JSONSerialization.data(withJSONObject: [
        "email": email, "password": password, "email_confirm": true,
        "user_metadata": ["display_name": displayName]
    ])
    let (data, code) = try await send(path: "/auth/v1/admin/users", method: "POST", body: body)
    guard code == 200 || code == 201 else {
        throw E2EError("admin 계정 생성 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
    }
}
```
```swift
/// 계정은 admin 으로, 팀은 로그인 뒤 create_team RPC 로 만든다.
/// signUp() 을 못 쓰는 이유: 셀프 가입이 꺼졌고, 팀 생성은 signUp 안의 private createTeamAfterSignup
/// (WorkTimerStoreAuth.swift:71-75)에만 있어 signIn 으로는 절대 실행되지 않는다.
@MainActor
private func provisionOwnerWithTeam(
    store: WorkTimerStore, admin: E2EAdmin,
    email: String, displayName: String, teamName: String
) async throws {
    try await admin.createConfirmedUser(email: email, password: Emails.password, displayName: displayName)
    store.email = email; store.password = Emails.password
    await store.signIn()?.value
    let token = try #require(store.session?.accessToken)
    let created = try await store.service.createTeam(accessToken: token, name: teamName, goalHours: E2ETeam.goalHours)
    store.createdTeamCode = created.inviteCode      // s01 의 #require(:748) 가 보는 값
    await store.confirmMembership()
}

/// 무소속 계정(O6/R9-b 게이트 e2e 전용). 저장소의 두 헬퍼는 반드시 팀을 붙이므로 이게 따로 필요하다.
@MainActor
private func makeTeamlessLiveAccount(anonKey: String, admin: E2EAdmin) async throws -> WorkTimerStore {
    try await admin.deleteByEmail(Emails.teamless)
    try await admin.createConfirmedUser(email: Emails.teamless, password: Emails.password, displayName: "E2E무소속")
    let store = makeLiveStore(anonKey: anonKey, defaults: liveIsolatedDefaults())
    store.email = Emails.teamless; store.password = Emails.password
    await store.signIn()?.value
    #expect(store.isTeamless)     // confirmMembership 이 0행으로 무소속 확정(WorkTimerStoreAuth.swift:167-176)
    return store
}
```
`signUpCreatingE2ETeam`/`signUpJoiningByCode`는 본문만 위 함수로 교체(호출부 시그니처 불변). `provisionMemberJoiningByCode` 안에 `await store.performPreviewTeamCode()` 한 줄 유지 — anon 미리보기는 R9-a와 무관하게 살아 있어야 하고 그 실증이 사라지면 안 된다.

**s05 목적 전환**: 셀프 가입이 꺼지면 중복 검사 경로는 도달 불가다. `s05_duplicateSignUp` → `s05_selfSignUpIsDisabled`로 개명하고 `store.signUp()` 후 `#expect(!store.isSignedIn)`, `#expect(store.syncMessage == "가입 비활성화됨")`, `#expect(profileCount == 0)`.

**계약**: "`authenticated` 롤 = 우리 회사 사람"이 이 시점부터 성립한다. R9-b·O6·O2 게이트 설계의 전제다.
**테스트**: 자동 불가(프로덕션 Auth 설정). 실증은 위 curl 하나 + `CHECK_E2E=1` 전체 통과. 단위 1건: 스텁 호스트 `signup-disabled`에 `error_code` 없는 본문을 물려 `.signupDisabled` 확인.
**하위호환**: 기존 계정 전원 무영향(로그인·토큰 갱신·모든 RPC 그대로). 영향은 '앞으로 새 계정을 만들려는 사람'뿐이고 구버전 앱에도 "가입 비활성화됨" 매핑이 이미 있다.
**롤백**: 대시보드 토글 ON(즉시, 무배포) + config.toml 되돌림.

---

### O5 조회 인덱스 4개
> 신규 `supabase/migrations/20260801010000_query_indexes.sql`. 인덱스만, 다른 변경 없음.

```sql
-- 조회 인덱스 4개. 지금 데이터(1개월·수천 행)에서는 체감 이득 0인 선제 조치다. 넣는 이유는 아래 쿼리들이
-- 전부 '팀/사용자 + ended_at 범위' 또는 'ended_at 범위' 모양이라, 행이 늘수록 seq scan 비용이 선형으로 늘고
-- 그중 하나는 30초마다 전원이 도는 폴링 경로이기 때문이다.
-- 멱등성: create index if not exists. 읽기 계획만 바꾸고 데이터·제약은 건드리지 않는다.
-- 주의: supabase db push 는 트랜잭션 안에서 돌므로 concurrently 를 쓸 수 없다. 현재 행 수(수천)에서
--   ACCESS EXCLUSIVE 락 시간은 밀리초 단위라 무중단으로 봐도 된다.

-- 1) team_status_snapshot(O2)의 done CTE 와 옛 3-fanout 의 fetchWeeklySessions(SupabaseWorkService.swift:146)
create index if not exists work_sessions_team_ended
  on public.work_sessions(team_id, ended_at desc) where ended_at is not null;

-- 2) fetchMySessions(SupabaseWorkService.swift:483, 개인 기록 히트맵/회고)
create index if not exists work_sessions_user_ended
  on public.work_sessions(user_id, ended_at desc) where ended_at is not null;

-- 3) O6(리그 창 필터) 전용. 그 쿼리엔 team_id/user_id 필터가 없어 1)·2)의 선두 컬럼과 불일치라
--    범위 탐색을 못 한다. 'ended_at is null' 가지는 기존 work_sessions_one_open_per_user 가 받아 BitmapOr.
create index if not exists work_sessions_ended_at
  on public.work_sessions(ended_at) where ended_at is not null;

-- 4) memberships PK 는 (team_id, user_id) 라 user_id 단독 필터의 선두 컬럼이 아니다.
--    joined_at 을 2번째로 넣어 '가장 먼저 합류한 팀 1건' 정렬까지 인덱스가 준다.
create index if not exists memberships_user
  on public.memberships(user_id, joined_at, team_id);
```

**만들지 않은 것(대조 완료)**: `work_statuses`(PK `(team_id,user_id)`가 이미 커버), `is_team_member`/`stopWork` PATCH/`close_abandoned`(memberships PK + partial unique로 최적), `token_usage_*`(소형 표라 유지비 > 이득), `pokes`(20260724020000에 이미 2개).

**계약**: 쿼리 결과·제약·권한 무변경(순수 계획 최적화).
**테스트**: 자동 불가. **[사람]** SQL Editor에서 `select indexname from pg_indexes where schemaname='public' and tablename in ('work_sessions','memberships');` → 새 이름 4개. 이 두 명령을 `docs/release.md:131` 스키마 적용 절에 적어 둔다.
**하위호환**: 없음. 인덱스는 클라이언트에 안 보인다.
**롤백**: `drop index if exists public.work_sessions_team_ended, public.work_sessions_user_ended, public.work_sessions_ended_at, public.memberships_user;`

---

### O6 + R9-b 리그 창 필터 + 무소속 가드 복구 + 디렉터리 게이트
> 신규 `supabase/migrations/20260801020000_leaderboard_window_and_directory_gate.sql`. **반드시 한 파일** — 같은 함수를 두 마이그레이션이 각각 `create or replace` 하면 나중 것이 앞 것을 지운다(실제로 그래서 가드가 사라졌다).

**변경 지점**: 기준 정의 `20260712010000_leaderboard_member_count.sql:36-56`(clipped, where 절 없음) · `:73-84`(최종 select, 가드 없음) / 소실된 가드 원본 `20260711160000_invite_code_join.sql:275-277` / `20260724020000_pokes.sql:118-145`(app_user_directory)

```sql
-- (a) clipped 에 이번 주 창 필터 추가(의미 동등), (b) 최종 select 에 소속 가드 복구.
-- (b)는 20260711160000:275 가 넣었던 가드가 20260712010000 재정의에서 통째로 사라진 회귀 복구다.
-- 의미 동등 증명: 제외되는 행은 ended_at is not null and ended_at < week_start 뿐이고, 그 행의 기여는
--   greatest(0, least(ended_at, now) - greatest(started_at, week_start)) 에서 감수가 week_start 미만이라 0.
--   주를 걸친 세션(일요일 시작 → 월요일 종료)은 ended_at >= week_start 라 그대로 살아남는다.
-- 반환 시그니처(6컬럼) 불변. 하우스 스타일대로 drop 선행 후 재생성하고 grant 를 다시 준다.
drop function if exists public.team_weekly_leaderboard();

create or replace function public.team_weekly_leaderboard()
returns table(
  team_id uuid, team_name text, weekly_goal_hours integer,
  total_seconds bigint, working_count integer, member_count integer
)
language sql stable security definer set search_path = public
as $$
  with bounds as (
    select (date_trunc('week', (now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul') as week_start,
           now() as now_ts
  ),
  clipped as (
    select
      s.team_id,
      greatest(0, extract(epoch from (
        least(case when s.ended_at is not null then s.ended_at
                   else coalesce(st.last_seen_at, b.now_ts) end, b.now_ts)
        - greatest(s.started_at, b.week_start)
      ))) as contribution_seconds
    from public.work_sessions s
    cross join bounds b
    left join public.work_statuses st
      on st.team_id = s.team_id and st.user_id = s.user_id
    -- 창 경계는 bounds 조인 컬럼이 아니라 stable 표현식으로 직접 쓴다 — 그래야 플래너가 실행 시 1회
    -- 평가해 work_sessions_ended_at 인덱스의 범위 경계로 바로 쓴다(조인 컬럼 비교는 nested-loop 의존).
    where s.ended_at is null
       or s.ended_at >= (date_trunc('week', (now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul')
  ),
  session_totals as (
    select clipped.team_id, sum(clipped.contribution_seconds)::bigint as total_seconds
    from clipped group by clipped.team_id
  ),
  working_counts as (
    select ws.team_id, count(*)::integer as working_count
    from public.work_statuses ws where ws.status = 'working' group by ws.team_id
  ),
  member_counts as (
    select m.team_id, count(*)::integer as member_count
    from public.memberships m group by m.team_id
  )
  select t.id, t.name, t.weekly_goal_hours,
         coalesce(sess.total_seconds, 0)::bigint,
         coalesce(wc.working_count, 0),
         coalesce(mc.member_count, 0)
  from public.teams t
  left join session_totals sess on sess.team_id = t.id
  left join working_counts wc on wc.team_id = t.id
  left join member_counts mc on mc.team_id = t.id
  where exists (select 1 from public.memberships m where m.user_id = auth.uid())
  order by coalesce(sess.total_seconds, 0) desc, t.name;
$$;

revoke all on function public.team_weekly_leaderboard() from public;
grant execute on function public.team_weekly_leaderboard() to authenticated;

-- R9-b: 콕찌르기 대상 디렉터리에 '호출자가 어떤 팀에든 소속인가' 게이트.
-- '같은 팀 공유'가 아니라 '아무 팀에나 소속'인 이유: 이 함수의 계약은 헤더 주석대로 "앱 사용자 전체"이고
-- 타팀 콕찌르기는 설계된 기능이다. 보안 수정으로 위장한 기능 축소는 하지 않는다.
-- 무소속 실사용자를 잠그지 않는다: 앱은 isTeamless 이면 콕찌르기 패널 자체를 그리지 않고
-- (CheckMenuView.swift:188-193, PokePanel 은 :257 else 가지 안), 무소속 계정은 세션을 못 열어
-- 어차피 poke_user 가 not_working 이다(20260724030000:46-51). 시그니처 4컬럼 불변.
create or replace function public.app_user_directory()
returns table(user_id uuid, display_name text, avatar_url text, is_working boolean)
language sql stable security definer set search_path = public
as $$
  select
    p.id,
    coalesce(p.display_name, '사용자'),
    p.avatar_url,
    exists (select 1 from public.work_sessions s where s.user_id = p.id and s.ended_at is null) as is_working
  from public.profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
    and exists (select 1 from public.memberships m where m.user_id = auth.uid())
  order by is_working desc, coalesce(p.display_name, '사용자');
$$;

revoke all on function public.app_user_directory() from public;
grant execute on function public.app_user_directory() to authenticated;
```

**계약**: 리그의 값 정의·컬럼·정렬 불변 + "호출자가 어떤 팀의 멤버도 아니면 0행" 규약 복구. 디렉터리는 "어떤 팀에든 소속일 때에 한해 앱 사용자 전체(본인 제외)" — 팀 경계는 여전히 넘는다.
**테스트**: 라이브 e2e 3건. `s09k_leaderboardTotalMatchesSessionRows`(주 걸친 세션 + 이번 주 세션을 admin으로 심고 클리핑 합과 ±2초), `s09l_leaderboardHiddenForTeamlessAccount`(무소속 → 빈 배열, **대조군** 소속 계정 ≥1행), `s09m_appUserDirectoryRequiresMembership`(무소속 0행 + 소속 계정에 **타팀 사용자 포함** — 팀 공유 게이트를 안 썼다는 회귀 방어). 셋 다 R9-a의 `makeTeamlessLiveAccount` 헬퍼에 의존. 단위 테스트 무영향(스텁이 고정 JSON).
**하위호환**: 시그니처 불변 → v0.2.10 디코드 그대로. 소속 가드 복구가 유일한 동작 변화인데 앱은 `isTeamless`면 리그 패널을 열 수 없어(`CheckMenuView.swift:188`) 0행을 볼 화면이 없다.
**롤백**: 두 함수를 원본 파일(`20260712010000` / `20260724020000:118-145`)에서 복붙해 `create or replace`. 무중단.

---

### R9-c 쓰기 정책 대칭 + 세션 무결성
> 신규 `supabase/migrations/20260801030000_work_write_integrity.sql`.

**변경 지점**: `20260701000000:165-171`(work_statuses UPDATE) · `:184-187`(work_sessions UPDATE) / `20260712120000:35-37`(close_abandoned set 절)

**진짜 구멍은 team_id 이동이다.** INSERT 정책은 `user_id = auth.uid() and is_team_member(team_id)`인데 UPDATE만 비대칭이라, A팀 소속자가 자기 세션 행의 `team_id`를 B팀 uuid로 PATCH해 남의 팀 리그 총합에 자기 시간을 밀어 넣을 수 있다.

```sql
-- INSERT 정책과 대칭으로 맞춘다. 정상 경로 영향 없음(전수 확인):
--   stopWork PATCH(ended_at, duration_seconds) / reopenSession PATCH(ended_at=null) /
--   upsertStatus(POST on_conflict=merge-duplicates) 는 team_id 를 바꾸지 않는다.
--   close_abandoned_work_sessions 는 security definer 라 RLS 자체를 타지 않는다.
drop policy if exists "members can close their sessions" on public.work_sessions;
create policy "members can close their sessions"
  on public.work_sessions for update
  using (user_id = auth.uid() and public.is_team_member(work_sessions.team_id))
  with check (user_id = auth.uid() and public.is_team_member(work_sessions.team_id));

drop policy if exists "members can update their status" on public.work_statuses;
create policy "members can update their status"
  on public.work_statuses for update
  using (user_id = auth.uid() and public.is_team_member(work_statuses.team_id))
  with check (user_id = auth.uid() and public.is_team_member(work_statuses.team_id));

-- 세션 행 무결성. 거절하지 않고 조용히 바로잡는다(20260717040000 의 좀비 상태 강등과 같은 방침).
--  (a) UPDATE 에서 started_at / team_id / user_id 는 항상 OLD 유지 — 값 위조와 팀 이동 차단.
--  (b) INSERT·UPDATE 모두에서 ended_at < started_at 이면 started_at 으로 클램프하고 duration 을 0 으로.
--      INSERT 에도 거는 것이 핵심이다: stopWork 는 PATCH 가 0행이면 클라 시각 두 개를 그대로 실어
--      POST 로 완료 세션을 만든다(SupabaseWorkService.swift:245-262). 시계가 뒤로 튄 기기에서 그 POST 가
--      아래 check 제약에 23514 로 걸리면 드레인이 항목을 남긴 채 멈춰(WorkTimerStoreSync.swift:544-550)
--      메뉴바가 '대기'로 영구 고착된다 — 이 항목이 피하려던 D5 가 경로만 바뀌어 재현된다.
create or replace function public.guard_work_session_write()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    new.started_at := old.started_at;
    new.team_id    := old.team_id;
    new.user_id    := old.user_id;
  end if;
  if new.ended_at is not null and new.ended_at < new.started_at then
    new.ended_at := new.started_at;
    new.duration_seconds := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists work_sessions_guard_update on public.work_sessions;   -- 옛 이름 정리(멱등)
drop trigger if exists work_sessions_guard_write  on public.work_sessions;
create trigger work_sessions_guard_write
  before insert or update on public.work_sessions
  for each row execute function public.guard_work_session_write();
```
그리고 **같은 파일에** `close_abandoned_work_sessions`를 `20260712120000` 원문 기반으로 재정의하되 set 절만:
```sql
    set ended_at = greatest(stale.last_signal, s.started_at),
        duration_seconds = greatest(0, extract(epoch from (greatest(stale.last_signal, s.started_at) - s.started_at)))::int
```
(보정 없이 제약만 넣으면 스캐빈저가 특정 엣지에서 죽는다.) 이어서 1회 수리 + 제약:
```sql
update public.work_sessions set ended_at = started_at, duration_seconds = 0
where ended_at is not null and ended_at < started_at;

-- 위 트리거가 INSERT·UPDATE 양쪽에서 클램프하므로 이 제약은 이제 위반될 수 없다. 스키마에 못 박는 백스톱.
alter table public.work_sessions drop constraint if exists work_sessions_ended_after_started;
alter table public.work_sessions add constraint work_sessions_ended_after_started
  check (ended_at is null or ended_at >= started_at);
```

**일부러 넣지 않은 것**: `new.ended_at := least(new.ended_at, now())`. 미래 시각 부풀리기까지 막히지만 시계가 앞선 사용자의 **v0.2.10 동작까지** 바뀐다. 20명 내부 도구에서 자기 시간 부풀리기는 팀 패널에 그대로 보이는 사회적 문제다.

**계약**: (1) 세션 행의 `started_at`/`team_id`/`user_id`는 **생성 후** 불변(생성 시각의 값 자체는 클라가 정한다 — INSERT 경로의 시각 위조는 이 항목의 범위가 아니며, 미래 `ended_at`은 클라·서버 양쪽 `least(…, now)` 클리핑이 이미 무력화한다). (2) `ended_at`은 null이거나 `started_at` 이상. (3) 자기 팀 밖 세션·상태 행은 만들 수도 옮길 수도 없다.
**테스트**: e2e 4건. `s09n_crossTeamSessionMoveIsIgnored`(**200 + 1행 갱신, team_id 불변** — BEFORE ROW 트리거가 RLS `with check`보다 먼저 돌므로 '0행/403'이 아니다), `s09o_startedAtIsImmutable`, `s09p_endedBeforeStartedClampsInsteadOfFailing`(PATCH), `s09p2_completedSessionInsertWithBackwardClockClamps`(**POST — 이번 리비전의 핵심 회귀 방어**). 기존 `s09b`가 그대로 통과하는 것이 `greatest()` 보정의 무해성 실증.
**하위호환**: v0.2.10 정상 경로 전부 통과(전수 확인). 동작이 바뀌는 유일한 케이스는 시계가 뒤로 튄 클라의 stop — 예전엔 음수 세션이 저장됐고 지금은 0초로 클램프된다. 그 행의 기여는 예전에도 양쪽에서 0이었으므로 **표시 숫자 변화 0**.
**롤백**: 트리거·제약 drop + 두 정책과 `close_abandoned`를 원문으로 재생성(전부 저장소에 원문 있음, 복붙 4회).

---

### O7-invite 참여코드 하드닝
> 신규 `supabase/migrations/20260801040000_invite_code_hardening.sql`. **두 변경은 반드시 한 파일** — sleep만 걷으면 대입 처리량이 300배가 되는데 `SUDOPARK` 같은 사전 단어 코드가 남아 있으면 순 보안 후퇴다.

**변경 지점**: `20260711170000_fix_invite_rpc_ambiguity.sql:98-127`(최종 정의, `:109`가 `pg_sleep(0.3)`, `:127` grant to anon) / `20260711160000:10-31`(generate_invite_code 문자셋)

```sql
-- (1) lookup_team_by_code 에서 pg_sleep 제거. 본문은 20260711170000 의 것을 그대로 옮기고 sleep 한 줄만 뺀다
--     (#variable_conflict use_column 프라그마 포함 — 빠지면 42702 재발).
--     volatile 유지: stable 로 바꾸면 PostgREST 가 GET 도 허용해 호출 표면이 는다.
create or replace function public.lookup_team_by_code(code text)
returns table(team_id uuid, name text, weekly_goal_hours integer, member_count integer)
language plpgsql volatile security definer set search_path = public
as $$
#variable_conflict use_column
declare
  normalized text;
begin
  -- pg_sleep(0.3) 제거: anon 에 열린 함수라 요청당 커넥션 점유가 정상 쿼리의 300배였다(무료 플랜 가용성 문제).
  -- 무차별 대입 방어는 지연이 아니라 코드 엔트로피(31^8 ≈ 8.5e11)가 맡는다 — 아래 (2)가 그 전제를 세운다.
  normalized := upper(regexp_replace(coalesce(code, ''), '[[:space:]-]', '', 'g'));
  if normalized = '' then return; end if;
  return query
    select t.id, t.name, t.weekly_goal_hours,
           (select count(*)::integer from public.memberships m where m.team_id = t.id)
    from public.teams t
    where upper(regexp_replace(coalesce(t.invite_code, ''), '[[:space:]-]', '', 'g')) = normalized
    limit 1;
end;
$$;
revoke all on function public.lookup_team_by_code(text) from public;
grant execute on function public.lookup_team_by_code(text) to anon, authenticated;

-- 회전 전 코드를 남긴다. 이 표가 없으면 회전이 비가역이고, 복구 수단이 '운영자가 select 결과를 미리
-- 복사해 뒀는가'라는 사람의 기억뿐이다(db push 출력의 raise notice 는 스크롤로 사라진다).
-- RLS 를 켜고 정책을 두지 않아 앱은 이 표에 접근할 수 없다(pokes 표와 같은 형태) — 구버전 요청 표면 불변.
create table if not exists public.invite_code_rotation_log (
  team_id uuid not null references public.teams(id) on delete cascade,
  old_code text not null,
  rotated_at timestamptz not null default now(),
  primary key (team_id, rotated_at)
);
alter table public.invite_code_rotation_log enable row level security;

-- (2) 생성기 규칙(8자, 헷갈리는 I/L/O/0/1 제외) 밖 코드를 전부 회전한다.
--     이미 합류한 사람은 memberships 행으로 소속 유지 — 바뀌는 것은 '앞으로 이 코드로 합류하려는 사람'뿐.
--     앱은 refreshTeamMeta → loadMyInviteCode(WorkTimerStoreAuth.swift:271)로 새 코드를 자동으로 다시 읽는다.
--     멱등: 회전 후 코드는 패턴을 만족하므로 재실행 시 루프가 0회 돈다.
do $$
declare t record; fresh text;
begin
  for t in select id, name, invite_code from public.teams
           where invite_code !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$'
  loop
    insert into public.invite_code_rotation_log (team_id, old_code) values (t.id, t.invite_code);
    fresh := public.generate_invite_code();
    update public.teams set invite_code = fresh where id = t.id;
    raise notice '참여코드 회전: team=% 옛코드=% 새코드=%', t.name, t.invite_code, fresh;
  end loop;
end
$$;
```

**계약**: `teams.invite_code`의 불변식이 "생성기 문자셋 8자"로 전 행에 성립한다. `lookup_team_by_code`의 반환·정규화·권한 규약 불변, 응답 지연만 사라진다.
**테스트**: e2e `s09q_allInviteCodesFollowGeneratorPattern` — admin `allTeams()`로 전 행 패턴 검사(실팀 회전 완료를 지키는 계약 테스트). 기존 `s09d`·`s02`가 그대로 통과하는 것이 lookup/join 무회귀 실증. **지연 단언은 넣지 않는다** — 무료 플랜 콜드스타트 때문에 왕복 시간 단언은 필연적으로 플레이키하다.
**하위호환**: 요청 형태·응답 스키마·정규화 규칙 전부 불변(구버전은 0.3초 빨라질 뿐). 저장소 어디에도 코드 문자열이 하드코딩돼 있지 않음을 grep 확인.
**롤백**: `update public.teams t set invite_code = l.old_code from public.invite_code_rotation_log l where l.team_id = t.id;` — 한 줄. pg_sleep은 `20260711170000` 원문 재적용.
**[사람] 후속**: 회전된 팀에 새 코드 재공지.

---

### NF4 `work_sessions.app_version` (컬럼만)
> 신규 `supabase/migrations/20260801050000_work_session_app_version.sql`. 앱 필드는 웨이브 1.

```sql
-- 클라이언트 버전 census: work_sessions.app_version. 세션 시작이 이미 매번 INSERT 하므로 요청 증가 0.
-- work_statuses 가 아니라 work_sessions 에 두는 이유: 맥 2대(구/신)를 쓰면 work_statuses 는 (team_id,user_id)
--   한 행이라 구버전 upsert 가 컬럼을 안 건드려 신버전 값이 남고 '전원 업데이트됨'으로 오독된다.
--   work_sessions 는 세션마다 그 세션을 연 클라가 남아 시간에 따른 분포까지 보인다.
-- 하위호환: nullable 이라 v0.2.10 의 INSERT(본문에 app_version 없음)는 그대로 성공한다.
-- **위험**: 이 컬럼이 없는 상태로 새 앱이 나가면 세션 INSERT 가 PGRST204 로 실패해 근무 시작이 막힌다.
--   db push → SQL 편집기 육안 확인 → 공증/배포 순서가 유일한 방어다.
alter table public.work_sessions add column if not exists app_version text;
```
운영 쿼리(`docs/release.md` 체크리스트):
```sql
select coalesce(app_version, '(v0.2.14 이하)') as v, count(*), max(started_at)
from public.work_sessions where started_at >= now() - interval '7 days' group by 1 order by 1;
```
**계약**: `work_sessions.app_version` = 그 세션을 연 클라이언트의 버전 문자열. null은 'v0.2.14 이하'.
**하위호환**: v0.2.10은 컬럼을 모른 채 정상 INSERT. 기존 행은 전부 null.
**롤백**: 앱 쪽에서 필드 제거(컬럼은 남겨도 무해).

---

### R5 + R1 패키징 스크립트
> `scripts/package-notarized.sh` 상단을 함께 고친다. 따로 하면 충돌.

**최종 순서 (이 순서가 설계의 절반이다)**
```
set -Eeuo pipefail + ERR trap          (R5-0)
cd ROOT / .env.local
키체인 잠금 선점검                      (R1)     ← 부수효과 0
IDENTITY 지문 확정 + 살아 있는 가드      (R5-2)   ← 부수효과 0, 최종 판정
mkdir -p dist; rm -f dist/aing-check.zip (R5-1)  ← 첫 파괴적 동작
build-local.sh → codesign → notarytool → stapler → spctl 게이트 → zip
```
부수효과 0인 가드는 전부 파괴적 동작보다 앞에 온다. 키체인이 잠겨 프롬프트를 띄웠을 때 Ctrl-C 하면, 공증·스테이플 완료된 7.9MB zip이 살아남아야 한다.

**(0) `:6`**
```bash
set -Eeuo pipefail

# 어디서 죽었는지 한 줄로 남긴다. -E 를 붙여야 함수/서브셸에서도 trap 이 산다.
trap 'echo "실패: ${BASH_SOURCE[0]}:${LINENO} — ${BASH_COMMAND}" >&2' ERR
```

**(R1) `.env.local` 블록(`:13` fi) 뒤**
```bash
# 키체인 잠금 선점검. 잠긴 채로 진행하면 :22 유니버설 릴리스 빌드(수 분)를 다 태운 뒤
# :25 codesign 에서 개인키를 못 꺼내 죽는다 — 실패를 0초 지점으로 앞당긴다.
# show-keychain-info 는 잠금 해제 상태면 프롬프트 없이 rc=0 이다(실측: "no-timeout" 출력).
# CHECK_KEYCHAIN_PW 를 .env.local 에 넣는 변형은 쓰지 마라 — login 키체인 암호 = macOS 계정 암호다.
#
# || true 가 필수다: pipefail 에서 security 가 비0이면 대입이 실패해 set -e 가
# 아래 분기에 닿기도 전에 스크립트를 죽인다(:15 의 죽은 가드와 같은 기제).
KEYCHAIN="$(security default-keychain -d user 2>/dev/null | tr -d ' \"' || true)"
if [[ -z "$KEYCHAIN" ]]; then
  echo "기본 키체인을 알아내지 못했습니다 — 잠금 선점검을 건너뜁니다(아래 인증서 가드가 최종 판정)." >&2
elif ! security show-keychain-info "$KEYCHAIN" >/dev/null 2>&1; then
  echo "키체인이 잠겨 있어 서명/공증 자격증명을 읽을 수 없습니다: $KEYCHAIN" >&2
  security unlock-keychain "$KEYCHAIN"   # tty 가 없으면 여기서 즉시 실패 — 그게 맞는 동작
fi
# 이 프로브는 '기본' 키체인만 본다. find-identity/codesign 은 검색목록 전체를 뒤지므로,
# 개인키가 다른 키체인에 있는 경우까지 판정하는 것은 아래 인증서 가드다.
```

**(R5-2) `:15-20` 교체**
```bash
# 서명 인증서를 **이름이 아니라 SHA-1 지문**으로 고정한다.
#  - 이름 서명은 인증서 갱신 시 동명 인증서가 둘이 되어 codesign 이 ambiguous 로 죽는다.
#    (실측: -p codesigning 전체 2건, -v 유효 1건 — 지금은 우연히 성공 중이다.)
#  - `|| true` 로 파이프 종료 상태를 흡수해야 아래 가드가 **실제로 도달**한다. 예전 판은
#    grep 0건일 때 pipefail 이 가드 앞에서 죽여 이 메시지가 한 번도 출력된 적 없는 죽은 코드였다.
#  - grep 이 아니라 awk 다(이 맥에서 grep 이 셸 함수로 덮여 출력이 오염된 전례).
#    head 재도입 금지 — pipefail + SIGPIPE 로 성공 경로에서도 141 이 날 수 있다.
IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Developer ID Application/ { print; exit }' || true)"
IDENTITY="$(printf '%s' "$IDENTITY_LINE" | awk '{ print $2 }')"
# -z 만으로는 부족하다. 출력 형태가 바뀌어 $2 가 지문이 아니면 codesign 이 빌드 4~5분을 태운 뒤 실패한다.
if [[ ! "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  echo "유효한 Developer ID Application 인증서를 찾지 못했습니다(키체인 잠금 또는 만료)." >&2
  echo "  find-identity 첫 매칭 줄: ${IDENTITY_LINE:-(없음)}" >&2
  echo "  Xcode > Settings > Accounts > Manage Certificates 에서 확인/발급하세요." >&2
  exit 1
fi
echo "서명 인증서:$IDENTITY_LINE" >&2
```
`codesign --sign <SHA-1>`은 표준 용법이라 `:25`는 한 글자도 안 바꾼다.

**(R5-1) `build-local.sh` 호출(`:22`) 바로 위**
```bash
# 낡은 배포 zip 을 빌드 시작 직전에 지운다. 이후 어느 지점에서 죽어도 zip 이 없어야
# release-brew.sh 의 "zip 없음" 게이트가 걸린다 — 같은 버전 재패키징 중 죽으면 버전 게이트는
# 낡은 zip 을 못 잡는다(버전이 같으니까). v0.2.3 사고의 잔여 구멍이다.
# 위쪽 가드(키체인·인증서)는 부수효과가 0이어야 하므로 삭제는 반드시 그 아래에 둔다.
mkdir -p "$ROOT/dist"
rm -f "$ROOT/dist/aing-check.zip"
```
`:40`은 `rm -rf "$STAGE"`로 축소.

**(R5-3) `:36` spctl 게이트화 — 이 그룹에서 값어치 1위**
```bash
# 유일한 게이트키퍼 검증이다. rc 만 보면 이 맥에서 Gatekeeper 평가가 꺼져 있을 때
# 무엇이든 rc=0 이라 게이트가 조용히 무의미해진다 — 판정 문구까지 요구한다.
# release-brew.sh 의 stapler validate 는 스테이플 존재만 보고 게이트키퍼 판정은 안 본다 — 여기가 유일점.
SPCTL_OUT="$(spctl --assess --type execute -v "$APP_PATH" 2>&1 || true)"
printf '%s\n' "$SPCTL_OUT" >&2
if ! printf '%s\n' "$SPCTL_OUT" | awk '/source=Notarized Developer ID/ { ok = 1 } END { exit !ok }'; then
  echo "게이트키퍼 검증 실패 — 이 앱은 팀원 맥에서 열리지 않습니다." >&2
  echo "  기대한 판정: 'accepted' + 'source=Notarized Developer ID'" >&2
  echo "  판정이 아예 안 나왔다면 이 맥의 Gatekeeper 평가가 꺼져 있을 수 있습니다(spctl --status)." >&2
  exit 1
fi
```

**계약**: 성공으로 끝났다 ⟺ `dist/aing-check.zip`이 존재하고 그 안의 앱이 게이트키퍼 통과본이다. 빌드 이후 실패로 끝나면 zip은 존재하지 않는다. 서명 인증서는 SHA-1 지문으로 결정적으로 지정된다.
**테스트**: 자동 불가. **[사람] 비파괴 실증 5종** — ① `security show-keychain-info "$KC"; echo rc=$?` → rc=0(프롬프트 없음) ② awk 패턴을 `/NoSuchCertificate/`로 임시 변경 → **안내 메시지 + exit 1**(전에는 안 나왔다) ③ `spctl --status`가 `assessments enabled`인지 ④ 현재 배포본 `spctl --assess -v` → `source=Notarized Developer ID` ⑤ 중간에 `false` 한 줄 넣고 ERR trap 줄번호 확인.
**하위호환**: 산출물 바이트 변화 0(같은 인증서, 같은 옵션). 유일한 행동 변화는 지금까지 무시되던 spctl 실패가 릴리스를 막는다는 것 — 실증 ④로 착수 전에 배제.
**롤백**: 4개 hunk 개별 되돌림. 급하면 spctl 한 줄만 `|| true`로(커밋하지 말 것).

---

### R2 앱 버전 단일 원본
> `scripts/build-local.sh`. **R3의 선행 필수** — 이걸 먼저 안 하면 R3 게이트가 곧 사라질 리터럴을 검사한다.

**변경 지점**: `:12`(fi)와 `:14`(# 유니버설) 사이 / `:64-67` 히어독 리터럴 / `:74`(PLIST) 뒤·`:78`(codesign) 앞

```bash
# 앱 버전의 단일 원본은 CHANGELOG.md 맨 위의 "## <버전>" 섹션이다.
# 예전엔 Info.plist 에 버전을 손으로 박아 CHANGELOG·release-brew.sh 인자와 3중복이었고,
# 어긋나면 공증 5~10분을 태운 뒤에야 zip 버전 게이트에서 잡혔다.
# grep 이 아니라 awk 다 — 이 맥에서 grep 이 셸 함수로 덮여 출력이 오염된 전례가 있다.
#
# `|| true` 는 장식이 아니다. set -euo pipefail 아래에서 대입값이 명령치환에서 오면 대입의
# 종료상태가 그 명령의 것이 되고, CHANGELOG.md 가 없을 때 awk 는 rc=2 를 낸다 → set -e 가
# 아래 안내 문구에 닿기 전에 스크립트를 죽인다(package-notarized.sh:15 의 죽은 가드와 같은 기제).
APP_VERSION="${CHECK_APP_VERSION:-$(awk '/^## [0-9]/ { print $2; exit }' "$ROOT/CHANGELOG.md" 2>/dev/null || true)}"
if [[ -z "$APP_VERSION" ]]; then
  echo "CHANGELOG.md 에서 버전을 찾지 못했습니다 — 맨 위에 '## 0.2.15' 형태의 섹션이 있어야 합니다." >&2
  echo "  확인한 경로: $ROOT/CHANGELOG.md" >&2
  echo "  개발용으로 우회하려면: CHECK_APP_VERSION=0.0.0-dev $0" >&2
  exit 1
fi
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || true)"
```
히어독은 **인용된 `<<'PLIST'` 그대로 두고** `:65`를 `<string>0.0.0</string>`, `:67`을 `<string>23</string>`로. `PLIST`(:74) 뒤, codesign(:78) 앞:
```bash
# 히어독 인용을 절대 풀지 마라(풀면 앞으로 $ 가 들어올 때 조용히 깨진다).
# 자리표시자 0.0.0 은 -replace 가 키 존재를 요구하기 때문에 필요하다. plutil 이 실패하면
# set -e 가 여기서 죽으므로 0.0.0 번들이 밖으로 나갈 일은 없고, 나가더라도
# release-brew.sh 의 zip 버전 게이트(:171-177)가 배포 전에 잡는다 — 이중 방어.
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_DIR/Contents/Info.plist"
if [[ -n "$BUILD_NUMBER" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
# R3 선택 항목: 소스 스큐까지 닫는다(빈 값/unknown 은 게이트가 통과시키므로 구 zip 과 호환).
plutil -insert CheckSourceCommit -string "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
echo "앱 버전: $APP_VERSION (빌드 ${BUILD_NUMBER:-23})" >&2
```
주입은 반드시 **codesign 앞**이어야 한다 — 서명 후 plist를 고치면 서명이 깨진다.

**계약**: 앱 버전의 원본은 `CHANGELOG.md` 맨 위 `## <버전>` 하나. 따라서 `build-local.sh`를 부르는 **세 경로 전부**(`run-local.sh:13`, `package-local.sh:18`, `package-notarized.sh:22`)가 CHANGELOG.md에 의존한다. 개발 중 우회는 `CHECK_APP_VERSION=0.0.0-dev`. `CFBundleVersion`이 고정 23 → 커밋 수(현재 80, 단조 증가).
**테스트**: 자동 불가. **[사람]** ① `awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md` → `0.2.14`(실측 완료) ② 빌드 후 `plutil -extract CFBundleShortVersionString raw dist/aing-check.app/Contents/Info.plist` + `codesign --verify --deep --strict` ③ CHANGELOG를 임시로 옮기고 `./scripts/run-local.sh` → `swift build` 로그 없이 안내 3줄 + rc=1 ④ `awk '/<<'\''PLIST'\''/{n++} END{print n}' scripts/build-local.sh` == 1(인용 유지).
**하위호환**: 앱 버전 값이 지금과 똑같이 나온다(출처만 바뀜). `CFBundleVersion` 23→80은 증가이고 아무도 안 읽는다.
**롤백**: 두 블록 삭제 + 히어독 리터럴 복원. 커밋 1개 revert.
**문서**: `docs/release.md:55-57` 0단계 끝에 — "이 섹션의 버전 번호가 곧 앱 버전입니다. 그래서 CHANGELOG를 먼저 쓰지 않으면 **지난 버전 번호로 빌드**되고, `release-brew.sh`의 버전 게이트가 그걸 잡습니다."

---

### R3 태그 소스 사슬
> `scripts/release-brew.sh:147`(CHANGELOG 블록 닫는 `fi`)과 `:149`(`ZIP=`) 사이에 삽입. 규약상 CHANGELOG 게이트가 맨 앞이고, 새 게이트는 부수효과 0이라 그 직후·zip 게이트 앞이 맞다.

**완성된 사슬**
```
CHANGELOG 섹션 존재      (기존 :120-147)
CHANGELOG 맨 위 == 인자   (신규)   — 버전의 원본이 하나임
작업트리 청결             (신규)   — 원본 == HEAD
HEAD ⊆ origin/main       (신규)   — 태그가 가리킬 커밋이 공개돼 있음
태그 재사용 시 == HEAD    (신규)   — 재실행이 낡은 소스를 배포하지 않음
zip 내부 버전 == 인자     (기존 :169-177) — 산출물 == 원본
```

```bash
log "사전점검: 버전 단일 원본(CHANGELOG) + 태그 소스"

CHANGELOG_TOP="$(awk '/^## [0-9]/ { print $2; exit }' "$CHANGELOG" 2>/dev/null || true)"
if [[ "$CHANGELOG_TOP" != "$VERSION" ]]; then
  missing "CHANGELOG.md 맨 위 섹션이 '## ${CHANGELOG_TOP:-(없음)}' 인데 릴리스 인자는 '$VERSION' 입니다. 앱 버전은 CHANGELOG 맨 위에서 나오므로(scripts/build-local.sh), 이대로 진행하면 다른 버전이 배포됩니다."
fi

if [[ "${CHECK_RELEASE_SKIP_GIT_GATE:-0}" == "1" ]]; then
  warn "CHECK_RELEASE_SKIP_GIT_GATE=1 — 태그 소스 게이트를 건너뜁니다(비상용)."
elif ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # git 명령의 실패를 대입으로 흘려보내면 set -e 가 안내 문구 앞에서 죽인다.
  missing "git 작업트리가 아닙니다($ROOT) — 태그 소스 게이트를 판정할 수 없습니다."
else
  DIRTY="$(git status --porcelain 2>/dev/null || true)"
  if [[ -n "$DIRTY" ]]; then
    printf '%s\n' "$DIRTY" | sed 's/^/    | /' >&2
    missing "작업트리가 깨끗하지 않습니다. 태그는 커밋을 가리키므로, 커밋되지 않은(또는 추적되지 않는) 파일이 있으면 태그가 실제로 배포된 소스를 가리키지 못합니다."
  fi

  # fetch 는 네트워크 I/O + 원격추적 ref 갱신이라 부수효과다 — dry-run 에서는 돌리지 않는다.
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] git fetch --quiet origin main (생략 — 로컬 원격추적본으로 검사)" >&2
  else
    git fetch --quiet origin main 2>/dev/null || warn "origin/main fetch 실패(오프라인?) — 로컬 원격추적본으로 검사합니다."
  fi

  if git rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor HEAD refs/remotes/origin/main; then
      missing "HEAD 가 origin/main 에 아직 올라가 있지 않습니다. 'git push origin main' 을 먼저 하세요 — 태그만 올라가면 그 소스를 아무도 받을 수 없습니다."
    fi
  else
    warn "origin/main 을 찾지 못해 조상 검사를 건너뜁니다."
  fi

  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    TAG_COMMIT="$(git rev-list -n 1 "$TAG" 2>/dev/null || true)"
    HEAD_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$TAG_COMMIT" && -n "$HEAD_COMMIT" && "$TAG_COMMIT" != "$HEAD_COMMIT" ]]; then
      missing "태그 $TAG 은 이미 ${TAG_COMMIT:0:8} 을 가리키는데 HEAD 는 ${HEAD_COMMIT:0:8} 입니다 — 태그를 옮기려면 'git tag -d $TAG && git push origin :refs/tags/$TAG' 후 다시 실행하고, 아니면 버전을 올리세요."
    fi
  fi
fi
```
zip 버전 게이트(`:177`) 바로 뒤에 소스 커밋 대조(R2의 `CheckSourceCommit`과 짝):
```bash
ZIP_COMMIT="$(unzip -p "$ZIP" "aing-check/aing-check.app/Contents/Info.plist" 2>/dev/null \
  | plutil -extract CheckSourceCommit raw - 2>/dev/null || true)"
if [[ -n "$ZIP_COMMIT" && "$ZIP_COMMIT" != "unknown" && "$ZIP_COMMIT" != "$(git rev-parse --short HEAD)" ]]; then
  missing "zip 은 커밋 $ZIP_COMMIT 에서 만들어졌는데 HEAD 는 $(git rev-parse --short HEAD) 입니다 — 패키징 이후 커밋이 바뀌었습니다. package-notarized.sh 를 다시 실행하세요."
fi
```
`:197`의 `git push origin "$TAG"`는 **유지한다** — 조상 게이트가 앞에 서면 HEAD 푸시는 항상 no-op이고 detached HEAD·비main 브랜치에서는 오히려 실패한다. 푸시로 때우지 말고 게이트로 막는다.

**계약**: `v<X>` 태그는 릴리스 시점에 이미 `origin/main`에 있는 커밋을 가리키며, **그 커밋의 CHANGELOG 맨 위 버전 = 릴리스 인자 = 배포 zip 안 앱 버전 = zip을 만든 소스 커밋**이다. 새 환경변수 `CHECK_RELEASE_SKIP_GIT_GATE=1`은 git 게이트 3종만 경고로 낮춘다(CHANGELOG·zip 게이트는 못 끈다).
**테스트**: **[사람] dry-run 4종** — ① `0.2.14 --dry-run` 통과 ② `0.2.99 --dry-run` → CHANGELOG 불일치 경고 ③ `touch scratch.tmp` 후 → `?? scratch.tmp` 출력 + 경고 ④ **`0.2.4 --dry-run` → 태그 스큐 경고**(실제 과거 사고 재생, `v0.2.4` = `40c1b3a1` ≠ HEAD).
**하위호환**: 없음. 릴리스 담당자의 로컬 절차만 엄격해진다. 과거 태그는 손대지 않는다.
**롤백**: 삽입 블록 통째 삭제.
**문서**: `docs/release.md:70` 앞에 커밋 단계 추가 + `:80` 사전점검 설명에 사슬 + 탈출구 명시.

---

### R4 재실행 시 릴리스 노트도 갱신
> `scripts/release-brew.sh:206-214` 교체.

```bash
if [[ "$DRY_RUN" -eq 0 ]] && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  warn "릴리즈 $TAG 이(가) 이미 존재합니다. 자산을 덮어쓰고 제목·노트를 다시 씁니다 (멱등)."
  # 자산을 먼저 올린다. 노트를 먼저 고치면 업로드가 실패했을 때 '고쳐졌다'는 새 패치노트가
  # 낡은 바이너리 위에 붙는다 — 사용자가 읽는 문장과 받는 물건이 어긋나는 쪽이다.
  run gh release upload "$TAG" "$ZIP" --repo "$REPO" --clobber

  # --notes 가 없으면 재실행이 노트를 갱신하지 않는다. v0.2.14 부터 이 본문이 곧 앱의 업데이트 배너
  # 문구다(CheckUpdateCheck.parseNotes 가 '- ' 줄을 그대로 읽는다).
  # --prerelease=false 도 반드시 함께: docs/release.md '## 롤백' ① 로 prerelease 로 내려둔 버전을
  # 같은 번호로 다시 배포할 때, 이게 없으면 /releases/latest 가 계속 직전 버전을 가리켜
  # 스크립트는 성공했는데 아무에게도 배너가 안 뜬다(가장 조용한 실패).
  WAS_PRERELEASE="$(gh release view "$TAG" --repo "$REPO" --json isPrerelease -q .isPrerelease 2>/dev/null || true)"
  if [[ "$WAS_PRERELEASE" == "true" ]]; then
    warn "$TAG 은 prerelease 상태였습니다 — 정식 릴리스로 되돌립니다. 롤백을 되돌리는 동작이니 의도한 것인지 확인하세요."
  fi
  run gh release edit "$TAG" --repo "$REPO" \
    --title "aing-check $VERSION" \
    --notes "$RELEASE_NOTES" \
    --prerelease=false
else
  run gh release create "$TAG" "$ZIP" --repo "$REPO" \
    --title "aing-check $VERSION" --notes "$RELEASE_NOTES"
fi
```
**계약**: '멱등'이 **자산 멱등 → 릴리스 전체(제목·본문·자산·prerelease 플래그) 멱등**으로 넓어진다.
**테스트**: 파서 쪽은 `CheckUpdateCheckTests`의 `parseNotes*`가 이미 고정(수정 불필요). **[사람]** 다음 실제 릴리스에서 CHANGELOG 한 줄 고치고 같은 버전 재실행 → `gh release view v<버전> --json body -q .body`로 확인.
**하위호환**: 이미 배포된 v0.2.10~v0.2.13 본문은 건드리지 않는다(그 버전으로 재실행하지 않는 한).
**롤백**: 추가한 블록 삭제. 사고 시 `gh release edit <tag> --notes "<이전 본문>"`.

---

### R6 CI 신설
> 신규 `.github/workflows/ci.yml`(현재 `.github` 디렉터리 자체가 없다). **R5 뒤에 올려라** — `bash -n` 스텝이 최종본 스크립트를 검사한다.

**감사 리포트의 필터 제안은 버린다.** swift-testing의 `--filter`는 **테스트 이름**에 매칭되는데 리포트 목록은 **파일명**이고, 이 저장소 테스트는 전부 파일 최상위 free function이라 파일명이 ID에 안 들어간다 — 그 정규식은 거의 아무것도 안 돌린다. 게다가 `WorkTimerStoreTests`(132) `CheckNudgeTests`(8)를 빠뜨렸는데 그게 핵심 로직이다.

**실측 분류**: 그래픽 의존 148개(CheckMenuRender 65 / CheckOverlay 57 / CheckSleepEyes 12 / CheckMascotAssets 7 / CheckWindowAnchor 7) + `credentialFieldRevertsNonASCIIInput` 1개(**ASCIIInputFilterTests의 이 한 건만 `NSHostingView`+`NSWindow`를 만들고 벽시계 1초를 폴링한다** — 파일 전체가 아니라 이름 예외로 뺀다) / 순수 로직 309개 / e2e 18개. 필터 커버리지 ≈ 68%.

```yaml
# aing-check CI — 20명 사내 도구에 맞춘 최소 구성. 시크릿 0개, 외부 액션은 checkout 하나.
# 2단계 도입 중 — 1단계(지금): 렌더/오버레이가 헤드리스 러너에서 도는지 확신 못 해 continue-on-error 로 관찰.
# CHECK_E2E 는 절대 세팅하지 않는다 — 라이브 e2e 는 실제 Supabase 에 계정·팀을 만들고 지운다.
name: CI
on: { push: { branches: [main] }, pull_request: , workflow_dispatch: }
concurrency: { group: "ci-${{ github.ref }}", cancel-in-progress: true }
permissions: { contents: read }
env: { CHECK_E2E: "" }

jobs:
  macos:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - name: 툴체인 기록
        run: swift --version && xcodebuild -version
      - name: 셸 스크립트 문법 검사
        run: |
          set -euo pipefail
          for f in scripts/*.sh scripts/*.command; do
            [ -f "$f" ] || continue
            bash -n "$f"; echo "ok  $f"
          done
      - name: 빌드
        run: swift build
      - name: 그래픽 의존 테스트 목록 만들기
        run: |
          set -euo pipefail
          GFX_FILES="CheckMenuRenderTests CheckOverlayTests CheckSleepEyesTests CheckMascotAssetsTests CheckWindowAnchorTests"
          # 파일 전체가 아니라 개별 테스트만 그래픽에 의존하는 예외.
          GFX_EXTRA_NAMES="credentialFieldRevertsNonASCIIInput"
          names="$GFX_EXTRA_NAMES"
          for base in $GFX_FILES; do
            f="Tests/checkTests/${base}.swift"
            [ -f "$f" ] || { echo "제외 목록의 파일이 없습니다: $f" >&2; exit 1; }
            names="$names $(awk '
              /^[[:space:]]*@Test/ { pending = 1 }
              pending && match($0, /func [A-Za-z_][A-Za-z0-9_]*/) {
                print substr($0, RSTART + 5, RLENGTH - 5); pending = 0
              }' "$f")"
          done
          for n in $GFX_EXTRA_NAMES; do
            grep -q "func $n" Tests/checkTests/*.swift || { echo "GFX_EXTRA_NAMES 의 $n 없음" >&2; exit 1; }
          done
          GFX_COUNT="$(printf '%s\n' $names | sort -u | wc -l | tr -d ' ')"
          [ "$GFX_COUNT" -ge 100 ] || { echo "추출이 깨졌습니다(149개가 정상)" >&2; exit 1; }
          TOTAL="$(awk '/^[[:space:]]*@Test/{c++} END{print c+0}' Tests/checkTests/*.swift)"
          E2E="$(awk '/^[[:space:]]*@Test/{c++} END{print c+0}' Tests/checkTests/LiveE2ETests.swift)"
          {
            echo "GFX_REGEX=$(printf '%s\n' $names | sort -u | paste -sd '|' -)"
            echo "EXPECT_MIN=$(( TOTAL - GFX_COUNT - E2E - 2 ))"
            echo "EXPECT_MAX=$(( TOTAL - GFX_COUNT ))"
          } >> "$GITHUB_ENV"
      - name: 테스트 — 순수 로직 (필수 게이트)
        id: logic
        run: |
          set -euo pipefail
          swift test --skip "$GFX_REGEX" 2>&1 | tee /tmp/logic.log
          # --skip 이 swift-testing 으로 전달되는지, 정규식이 안전한 테스트까지 삼키지 않는지 매 실행 확인.
          N="$(awk 'match($0, /Test run with [0-9]+ test/) { s=substr($0, RSTART+14); print s+0 }' /tmp/logic.log | tail -1)"
          echo "실행된 테스트: ${N:-?} (기대 ${EXPECT_MIN}~${EXPECT_MAX})"
          if [ -z "$N" ] || [ "$N" -lt "$EXPECT_MIN" ] || [ "$N" -gt "$EXPECT_MAX" ]; then
            echo "필수 게이트 테스트 수가 기대 범위를 벗어났습니다 — --skip 전달 실패 또는 이름 충돌." >&2
            exit 1
          fi
      - name: 테스트 — 렌더/오버레이 (관측용)
        id: gfx
        continue-on-error: true
        run: swift test --filter "$GFX_REGEX"
      - name: 요약
        if: always()
        run: |
          {
            echo "### 테스트 결과"
            echo "- 순수 로직(필수): ${{ steps.logic.outcome }}"
            echo "- 렌더/오버레이(관측): ${{ steps.gfx.outcome }}"
            echo ""
            echo "필수 게이트는 전체 중 ${{ env.EXPECT_MIN }}~${{ env.EXPECT_MAX }}개만 돈다 — **초록불이 '전부 안전'을 뜻하지 않는다.**"
            echo "릴리스 전에는 로컬에서 \`swift test\` 전체를 반드시 통과시켜라."
            echo ""
            echo "#### 2단계 승격 규칙"
            echo "main 에서 렌더/오버레이가 5회 연속 success 면 두 스텝을 \`swift test\` 한 줄로 합치고 이 문단을 지운다."
            echo "계속 실패하면 러너에 쓸 만한 화면 세션이 없다는 뜻이므로 1단계를 영구 구성으로 둔다."
          } >> "$GITHUB_STEP_SUMMARY"
```
**계약**: main·PR의 모든 커밋은 `swift build`와 그래픽 비의존 테스트를 통과해야 한다. 렌더 148개는 1단계 동안 관측 대상이며 그 사실이 매 실행 요약에 명시된다. 시크릿 0개, 라이브 e2e는 절대 안 돈다.
**테스트**: **[사람] 착수 전 로컬 실증** ① 목록 생성 스텝을 그대로 붙여 `GFX_COUNT`가 149인지 ② `swift test --skip "$GFX_REGEX" 2>&1 | tail -3`의 N이 기대 범위 안인지(**이 설계의 유일한 미검증 가정**) ③ `env -u CHECK_E2E swift test --filter s00_preCleanup`이 0 실행 ④ `swift test --filter credentialFieldRevertsNonASCIIInput` 로컬 소요시간 기록.
**하위호환**: 없음. 파일 하나 추가.
**롤백**: 파일 삭제.

---

### R7 롤백 절차 문서 · R8 pg_cron 확인 쿼리
> `docs/release.md` 두 절. 코드 변경 0.

**R7** — `## 트러블슈팅`(:168) 앞에 `## 롤백` 절. 핵심은 **"릴리스를 삭제하지 마라"의 근거를 사실대로 적는 것**:
```markdown
> **릴리스를 삭제하지 마세요. `--prerelease` 로 내리세요.** 둘의 차이가 헷갈리기 쉬워 적어 둡니다.
>
> - **latest 가 내려가는 효과는 둘이 같습니다.** 앱이 치는 곳은 특정 태그가 아니라
>   `/releases/latest`(`Sources/check/CheckUpdateCheck.swift:52`)이고, 이 API 는 가장 최근의
>   정식(non-prerelease) 릴리스를 돌려줍니다. 삭제가 이 엔드포인트를 404 로 만들지는 **않습니다**
>   (남은 릴리스가 하나도 없을 때만 404).
> - **차이는 자산 URL 과 되돌리기입니다.** Cask 다운로드 주소가
>   `…/releases/download/v#{version}/aing-check.zip`(`packaging/homebrew/aing-check.rb:9`)라
>   릴리스를 지우면 그 zip 이 사라집니다. tap 이 아직 그 버전을 가리키는 동안 `brew install` 이
>   404 로 깨지고, 공증까지 마친 산출물을 다시 만들려면 빌드+공증을 처음부터 돌려야 합니다.
>   prerelease 는 플래그 한 번으로 되돌릴 수 있지만 삭제는 되돌릴 수 없습니다.
> - **어느 쪽이든 즉시 사라지지는 않습니다.** 앱은 마지막 조회 결과를 UserDefaults 에 저장했다가
>   실행 시 복원하고(`:98-101`), 조회는 24시간에 한 번이며(`checkIfStale`, `:126-128`) 조회 실패는
>   조용히 무시합니다(`:141` 의 `try?`). **반영까지 최대 하루**입니다.
```
나머지 절: ② 권장(revert 후 **버전을 올려서** 앞으로 감기 — Cask version이 내려가면 `brew upgrade`가 아무 일도 안 한다) / ③ 비상(tap revert + **`brew reinstall`**, `upgrade`는 다운그레이드를 안 잡는다) / 서버는 같이 되돌리지 않는다(전진 전용, 되돌리는 마이그레이션을 새 타임스탬프로) / 확인 명령 3종 / v0.2.4 이전 태그 스큐 주의.
**테스트**: 복원 동작은 `Tests/checkTests/CheckUpdateCheckTests.swift:91 latestNotesPersistWithVersionAndRestoreOnRelaunch`가 이미 고정한다. **추가 테스트 불필요**(476 유지).

**R8** — `:144` 뒤에 `#### pg_cron 등록 확인` 소절. 두 잡(`close-abandoned-work` `*/5 * * * *` / `cleanup-old-pokes` `0 19 * * *`)은 `exception when others then raise notice`로 감싸 등록 실패해도 `db push`가 성공으로 끝난다(**의도된 설계 — 코드를 바꾸지 마라**).
```sql
-- 1) 등록됐는가 — 아래 두 줄이 active = t 로 보여야 한다.
select jobname, schedule, active from cron.job order by jobname;

-- 2) 지금도 돌고 있는가 — 이게 판정 기준이다. status 만 보면 3주 전 성공과 5분 전 성공을
--    구분할 수 없다. close-abandoned-work 는 5분 주기이므로 last_run 이 10분 이내여야 한다.
select j.jobname, max(d.start_time) as last_run, now() - max(d.start_time) as ago,
       count(*) filter (where d.status <> 'succeeded') as failures
from cron.job j left join cron.job_run_details d on d.jobid = j.jobid
group by j.jobname order by j.jobname;

-- 3) 실패 원인 — job_run_details 에는 jobname 이 없어 조인해야 한다.
--    left join 이어야 한다: 잡이 삭제·개명된 뒤에도 이력은 남는데, inner join 이면
--    "쿼리 1에 행이 없다"는 바로 그 상황에서 원인 메시지가 통째로 가려진다.
select coalesce(j.jobname, '(등록 해제됨 jobid=' || d.jobid || ')') as jobname,
       d.status, d.start_time, d.return_message
from cron.job_run_details d left join cron.job j on j.jobid = d.jobid
order by d.start_time desc limit 10;
```
`docs/release.md:63-65` 1-1 단계에 한 줄: "`push` 가 초록이어도 pg_cron 등록은 별도 확인." 같은 절에 **셀프 가입 차단 여부(R9-a) 확인**도 1회 점검 항목으로 함께.

---

## 웨이브 1 — v0.2.15

### D1 실행 시 저장 세션 1회 킥
> 팝오버를 한 번도 열지 않아도 저장 세션을 실행당 1회 활성화한다. MenuBarExtra(.window)의 콘텐츠 뷰는 첫 오픈 전까지 생성되지 않는다(감사 실증).

**변경 지점**: `CheckApp.swift:37-45 applicationDidFinishLaunching` / `WorkTimerStoreAuth.swift:5-27 activateStoredSession` 분할 / `WorkTimerStore.swift:51` 부근(핸들) · `:755-759`(유휴 슬라이스) · `:761`(본문 첫 줄) / `WorkTimerStoreSync.swift:9-15` / `CheckOverlayWindow.swift:135`

**1) 진입점 분할** (`WorkTimerStoreAuth.swift:5`)
```swift
/// 실행 직후 저장 세션을 활성화해야 하는지. 키가 없으면(canSync==false) 킥하지 않는다 —
/// missingAnonKey 는 classifyAuthError 에서 .fatal 이라 refreshPersistedSessionIfPossible 이
/// 저장 세션을 조용히 지운다(SupabaseWorkHTTP.swift:64-66 → WorkTimerStoreAuth.swift:482-490).
/// 키 없이 `swift run` 한 개발 맥에서 실계정 세션이 화면 한 번 안 보이고 날아가는 경로.
var shouldActivateOnLaunch: Bool { isSignedIn && canSync && !hasActivatedStoredSession }

@discardableResult
func activateStoredSessionOnLaunch() -> Task<Void, Never>? {
    guard shouldActivateOnLaunch else { return nil }
    let task = Task { @MainActor [weak self] in
        await self?.performActivateStoredSession()
        self?.launchActivationTask = nil
    }
    launchActivationTask = task
    return task
}

/// 팝오버 오픈(.task) 진입점. 실행 킥이 아직 돌고 있으면 그 완료를 먼저 기다린다.
func activateStoredSession() async {
    if let launchActivationTask { await launchActivationTask.value }
    await performActivateStoredSession()
}

private func performActivateStoredSession() async { /* 기존 :5-27 본문 그대로 */ }
```
`WorkTimerStore.swift:51` 부근:
```swift
/// 실행 킥의 Task 핸들. 팝오버 `.task` 가 이 Task 를 먼저 기다리는 이유는 '활성화가 둘로 갈라져서'가 아니다
/// (hasActivatedStoredSession 이 첫 await 이전에 동기 래치되므로 두 번째 진입자는 항상 fast path 다).
/// 진짜 이유는 fast path 의 confirmMembership 이 **아직 회전 전인 낡은 access token**으로 나갔다가 401 을
/// 만나면 withSessionRetry 가 킥과 **같은 낡은 refresh token 으로** 두 번째 grant 를 치기 때문이다 —
/// GoTrue reuse-detection 창을 벗어나면 근무 중 강제 로그아웃이 된다.
@ObservationIgnored var launchActivationTask: Task<Void, Never>?
```

**2) 킥 위치** (`CheckApp.swift:37`)
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // 오버레이 컨트롤러를 **먼저** 만든다. 아래 킥이 서버의 열린 세션을 흡수해 근무중으로 복구할 수 있는데,
    // 그때 표시 전환·리액션 싱크(store.onReactionTrigger / onPokesReceived)가 이미 배선돼 있어야 한다.
    overlayController = CheckOverlayController(store: store, updateCheck: updateCheck)
    LoginItemRegistrar.registerIfNeeded(...)   // 기존 그대로
    // D1: 팝오버를 한 번도 열지 않아도 저장 세션을 실행당 1회 활성화한다.
    store.activateStoredSessionOnLaunch()
}
```

**3) 오프라인 부팅 재확정 — 슬라이스 단위** (`WorkTimerStore.swift:755-759`). 루프는 **자고 나서 본문**을 돌므로 본문에만 두면 재확정이 최대 600초 뒤다.
```swift
} else {
    let idleSlices = self?.refreshLoopIdleSliceCount ?? 20
    for _ in 0..<idleSlices {
        try? await Task.sleep(for: .seconds(slice), tolerance: tolerance)
        if Task.isCancelled { return }
        // 멤버십 미확정(= 킥이 Wi-Fi 결합 전에 실패)은 유휴 1주기를 기다리지 않는다. 그동안 팀이 nil 이라
        // 넛지(CheckOverlayWindow.swift:144 currentTeamID != nil)·하트비트·큐 드레인이 전부 죽는다.
        // 확정되면 요청 0건이라 유휴 비용 불변. 회복 상한 = 1슬라이스(30초).
        await self?.confirmMembershipIfNeeded()
        if self?.refreshLoopIsFast ?? false { break }
    }
}
```
본문 맨 앞(`:761`)에도 `await self?.confirmMembershipIfNeeded()`(fast 모드용). 헬퍼:
```swift
/// 멤버십이 한 번도 확정된 적 없으면 1회 재확정한다(확정됐으면 요청 0건).
func confirmMembershipIfNeeded() async {
    guard session != nil, !membershipConfirmed else { return }
    await confirmMembership()
}
```
맨 앞인 이유: `performPendingOperation`(WorkTimerStoreSync.swift:560)이 teamID 없으면 throw하므로, 팀 확정이 큐 드레인보다 앞서야 오프라인에서 쌓인 근무가 같은 주기에 재생된다.

**4) 무소속 문구 오염 차단** (`WorkTimerStoreSync.swift:9`) — 킥 도입으로 이 분기가 화면 없이도 매 주기 돈다.
```swift
guard let teamID = currentTeamID else {
    if !teamMembers.isEmpty { teamMembers = [] }
    // 멤버십이 확정된 적 없으면(킥이 오프라인으로 실패) '무소속'이라 단정하지 않는다.
    guard membershipConfirmed else { return }
    let teamlessMessage = WorkTimerStore.teamlessSyncMessage   // D6-6 에서 상수화(웨이브 3)
    if syncMessage != teamlessMessage { syncMessage = teamlessMessage }
    return
}
```
> 웨이브 1 시점에는 리터럴 그대로 두고, 웨이브 3의 D6-6이 상수로 승격하며 이 줄도 함께 치환한다.

**5) 넛지 기동 결정화** (`CheckOverlayWindow.swift:135`, `observeScreenChanges()` 다음)
```swift
        // 넛지 스케줄러를 여기서 한 번 가동한다. 지금까지 유일한 기동 지점이 updateWorking 의 defer(:159)뿐이라,
        // 숨김 패널의 SwiftUI 루트 뷰가 body 를 평가하는지에 자동 시작 전체가 걸려 있었다(MenuBarExtra 에서
        // 같은 종류의 가정이 이미 한 번 틀렸다). start() 는 loopTask 가드로 멱등이라 중복 무해.
        syncNudgeScheduler()
```

**계약**: 저장 세션의 전체 활성화(토큰 회전 + 멤버십 확정 + 폴링/찌르기 루프 기동)는 **실행당 정확히 1회**, 팝오버 오픈이 아니라 앱 실행 시점에 일어난다. `membershipConfirmed == false`인 동안 refresh 루프가 **매 슬라이스**(30초)마다 재확정을 1회 시도한다. `refreshTeamStatus`의 무소속 문구는 이제 멤버십이 확정된 뒤에만 뜬다.
**테스트**: `WorkTimerStoreTests.swift` 5건. ① `launchKickActivatesStoredSessionWithoutPopover`(:927 defaults 시드 재사용 → `shouldActivateOnLaunch` → `await activateStoredSessionOnLaunch()?.value` → session 회전·teamID·refreshTask·pokePollTask 확인) ② `launchKickSkipsWithoutSessionOrKey`(키 없을 때 nil 반환 + **defaults의 accessToken이 살아남음** — 이 가드의 존재 이유) ③ `launchKickSerializesRefreshGrantWithPopoverOpen`(호스트 `delayed-expired-token`, `alwaysDelayedHostPrefix` 규약. 킥 in-flight 중 `await activateStoredSession()` → grant 요청 **정확히 1건**. await를 지우면 2가 되어 실패하는 **진짜 가드 테스트**) ④ `refreshLoopReconfirmsMembershipAfterOfflineLaunch`(폴링 예산 **600회**×5ms) ⑤ `refreshLoopReconfirmsMembershipWithinOneSlice`(본문이 아니라 슬라이스에서 회복함을 고정 — 회귀 시 조용히 10분으로 되돌아간다). 스텁 수정: `URLProtocolStub`의 401 규칙을 `host?.hasSuffix("expired-token") == true`로 완화. 깨지는 기존 테스트 없음(`:190-211` 무소속 문구 테스트는 signIn 경로라 `membershipConfirmed=true` 뒤에 돈다).
**하위호환**: 서버 요청의 종류·형태·순서 무변경. 단 **부하 프로필이 바뀐다** — 로그인 사용자당 유휴 폴링이 0 → 36요청/시로 생긴다(N1-idle이 18로, O2가 6으로 줄인다). 반대 방향 부수효과로 무료플랜 7일 비활동 일시정지가 사실상 사라진다.
**롤백**: `CheckApp.swift`의 한 줄 삭제(나머지 신설 코드는 호출되지 않아 무해).
**의존**: N1-idle·O1·N2-menubar와 같은 커밋. D2(웨이브 2)의 노출 범위를 넓히므로 웨이브 2를 반드시 뒤에 둔다.

---

### N1-idle 유휴 주기 300s → 600s
**변경 지점**: `WorkTimerStore.swift:730-731`·`:736-737`·`:738`·`:755` · `:256`

```swift
/// 유휴(비근무·팝오버 닫힘·큐 없음) 모드의 슬라이스 개수. 유휴 주기 = refreshLoopSliceSeconds × 이 값.
/// D1(실행 킥) 이후 이 루프는 로그인 사용자의 **부팅부터 24시간** 돌기 때문에, 유휴 1주기가 곧 팀 전원의
/// 한 주치 세션 원본 3-fanout(5인 ≈ 11KB, 20인 ≈ 42KB)이다. 300s → 600s 로 킥이 더한 몫을 절반으로 줄인다.
/// 유휴에서 늦어지는 것은 '다른 맥이 시작한 근무의 흡수'뿐이다 — 유휴→근무 전이는 여전히 슬라이스 1회(30s)
/// 안에 감지되며(하트비트 90초 신선도 계약 보존), 방치 세션은 서버 10분 cron 이 주 경로다.
/// O2(team_status_snapshot)로 payload 가 98% 줄면 300 으로 되돌려도 된다.
@ObservationIgnored var refreshLoopIdleSliceCount = 20
```
루프에서 `let idleSlices = self?.refreshLoopIdleSliceCount ?? 20`(폴백도 새 기본값에 맞춘다).

**주석 3곳 동시 정정(같은 커밋)** — 이 저장소는 doc 주석을 계약으로 쓴다.
- `:730-731` "느린 주기(300s)" → "느린 주기(`refreshLoopSliceSeconds × refreshLoopIdleSliceCount` = 기본 600s)"
- `:736-737` "10슬라이스(기본 300s)" → "`refreshLoopIdleSliceCount` 슬라이스(기본 20 → 600s)"
- `:256` "유휴 300초로는 전달이 너무 늦다" → "유휴 600초로는…"

**계약**: 유휴 폴링 주기는 slice × count(기본 600초), fast 전이 감지 상한은 여전히 슬라이스 1회(30초).
**테스트**: 값 핀 `idleRefreshPeriodStaysCoarse` — `#expect(store.refreshLoopIdleSliceCount == 20)` + `#expect(store.refreshLoopSliceSeconds == 30)`. 전이 상한은 기존 B-F1(`idleRefreshLoopWakesWithinOneSliceWhenWorkStarts`, :2618-2655)이 이미 실증한다(`:2637`에서 fast를 참으로 만들어 첫 슬라이스에서 break하므로 개수를 안 탄다). 실시간 600초를 기다리는 테스트는 만들지 않는다.
**하위호환**: 없음. 내 상태 전파는 상대가 근무중일 때 fast 30초로 읽는다.
**롤백**: 상수 20 → 10.
**주의**: D1의 슬라이스 단위 `confirmMembershipIfNeeded`가 **반드시 같은 커밋**에 있어야 한다. 없으면 N1-idle 단독으로 오프라인 부팅의 무소속 구간을 10분으로 늘리는 순수 악화가 된다.

---

### O1 콕찌르기 폴링을 근무 중으로 제한
**변경 지점**: `WorkTimerStorePoke.swift:102-127` / `WorkTimerStore.swift:377`(finishWorkBeforeQuit) · `:454`(stop 말미) · 저장 프로퍼티 1개 / `URLProtocolStub.swift`(take_pokes 픽스처)

```swift
pokePollTask = Task { @MainActor [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Self.pokePollIntervalSeconds), tolerance: .seconds(2))
        if Task.isCancelled { return }
        guard let self else { return }
        guard self.session != nil else { continue }
        // 공개 설정 1회 로드는 게이트 **앞**이다 — 뒤에 두면 근무 이력이 없는 사용자가 서버값을 영영 못 읽는다.
        await self.loadTokenUsagePrivacyIfNeeded()
        await self.takePokesIfWorking()
    }
}

/// 근무중일 때만 수신 찔림을 소비한다. 게이트 기준은 snapshot.isWorking 이 아니라 startedAt != nil 이다
/// (sendPoke 의 선게이트·서버의 '열린 세션' 조건과 같은 눈금).
func takePokesIfWorking() async {
    guard startedAt != nil else { return }
    await drainReceivedPokes()
}

/// take_pokes 1회 소비 + 신선분 전달. 폴링과 근무 종료 꼬리 회수가 공유한다.
func drainReceivedPokes() async {
    guard session != nil else { return }
    let generation = sessionGeneration
    do {
        let rows = try await withSessionRetry { activeSession in
            try await service.takePokes(accessToken: activeSession.accessToken)
        }
        guard generation == sessionGeneration else { return }
        let batch = WorkTimerStore.freshReceivedPokes(rows: rows, now: Date())
        if !batch.isEmpty { onPokesReceived?(batch) }
    } catch { /* 취소/일시 오류는 조용히 — 다음 tick 재시도 */ }
}
```
**종료 경로에서는 꼬리 회수를 하지 않는다** (`stop()`은 사용자 버튼만이 아니라 종료 훅 `applicationShouldTerminate` → `finishWorkBeforeQuit` → `:379 stop()`도 부른다):
```swift
/// 앱 종료 시퀀스 진입 플래그. 종료 경로의 stop() 은 찔림 꼬리 회수를 건너뛴다 —
/// take_pokes 는 서버에서 원자 소비라, 응답을 못 받고 죽으면 그 찔림이 영구 소실된다
/// (다음 실행이 1시간 신선도 안에서 전달할 수 있었던 건). 종료 시점은 말풍선을 볼 사람이 없어 이득도 0이다.
@ObservationIgnored var isTerminating = false
```
`finishWorkBeforeQuit`의 `stop()` 앞에 `isTerminating = true`. `stop()`의 `syncCurrentStatus(...)` 다음 줄:
```swift
if !isTerminating {
    Task { @MainActor [weak self] in await self?.drainReceivedPokes() }
}
```
`autoStop`(잠자기·12시간·자리비움)에는 넣지 않는다 — 자리에 없다는 판정이 마감 사유이므로 그 순간의 말풍선은 볼 사람이 없다.

**계약**: 수신 찔림 폴링은 '로컬 근무중(`startedAt != nil`)'일 때만 네트워크를 낸다. 서버가 poke 생성 시점에 대상의 열린 세션을 요구하므로(`target_not_working`) 비근무 구간 응답은 **거의 항상** 빈 배열이다 — 예외는 로컬은 비근무인데 서버엔 열린 세션이 남은 구간(오프라인 종료·크래시 후 흡수 전)이며, 그 구간의 찔림은 서버 7일 cron이 정리한다. 15초 타이머는 그대로 살아 있고(공개 설정 로드가 그 위에 있다) 사용자 종료 시 1회 추가 소비가 나간다.
**테스트**: ① `pokePollingSkipsTakePokesWhenNotWorking`(startedAt nil → 요청 0건, 세팅 후 1건) ② `stopDrainsReceivedPokesOnce` ③ `quitDoesNotDrainReceivedPokes`(`finishWorkBeforeQuit(timeout: 0.05)` 후 take_pokes **0건**, 대조군 `stop()`은 1건 — 없으면 다음 리팩터가 조용히 되돌린다). 스텁: `responseData`에 `/rest/v1/rpc/take_pokes` → `[]` 추가(현재 미등록이라 `Data()`가 돌아가 디코드가 조용히 throw된다). 깨지는 기존 테스트 없음.
**하위호환**: 서버 계약 무변경. v0.2.10 상대에게 찌르기 송신 그대로.
**롤백**: `takePokesIfWorking`의 guard 한 줄 제거.

---

### N2-menubar 메뉴바가 시간을 상태 단어로 덮는다
> 감사 리포트의 "`if derived.isWorking` 가드를 걷으면 된다"는 **틀렸다** — `MenuBarStatusFormatter.title(for:)`의 `.offWork` 분기가 elapsedSeconds를 무시하고 "오프"를 반환하므로 가드만 걷으면 아무 변화가 없다. 두 곳을 함께 고친다.

**변경 지점**: `MenuBarStatusFormatter.swift:46` / `WorkTimerStore.swift:801`(refreshMenuBarTitle) · `:783-786`(tick에서 추출) · `:64`(setMenuPresented) · `:466`(handleWake 맨 앞) · `:761`(루프) · `:938`(clearPersistedSession)

```swift
// MenuBarStatusFormatter.swift:46
case .offWork:
    // 오늘 일한 시간이 남아 있으면 계속 보여 준다(6시간 일하고 퇴근했는데 '오프'만 보이던 문제).
    // 근무중과의 구분은 텍스트가 아니라 아이콘이 한다 — 캐릭터가 aing-neutral ↔ aing-negative 로 갈리고
    // SF Symbol 폴백도 figure.run ↔ pause 로 갈린다.
    return snapshot.elapsedSeconds > 0 ? duration(snapshot.elapsedSeconds) : "오프"
```
```swift
// WorkTimerStore.swift:801
func refreshMenuBarTitle() {
    var derived = snapshot
    // 근무중이 아니어도 오늘 누적을 싣는다. todayDuration(:283)이 KST 자정 클리핑과 accumulatedDayStart
    // 스탬프 판정을 이미 품고 있어, 어제 누적이 오늘 라벨로 새지 않는다.
    derived.elapsedSeconds = todayDuration
    let new = MenuBarStatusFormatter.title(for: derived)
    if menuBarTitle != new { menuBarTitle = new }
}
```
**자정 롤오버** — 라벨이 '오늘 누적'을 그리게 되면 티커 없는 유휴에서 자정을 넘겨도 어제 값이 박힌다. `tick()`의 :783-786 블록을 꺼낸다.
```swift
/// KST 자정을 넘겼으면 어제 스탬프의 누적을 0 으로 되돌리고 스탬프를 오늘로 옮긴다(+ 라벨 재계산).
func rolloverIfNeeded(now: Date = Date()) {
    let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
    guard accumulatedDayStart < dayStart else { return }
    accumulatedSeconds = 0
    accumulatedDayStart = dayStart
    // displayNow 가 어제에 멈춰 있으면 todayDuration 의 dayStart 판정도 어제라 라벨이 안 바뀐다.
    if displayNow < dayStart { displayNow = now }
    refreshMenuBarTitle()
}
```
호출 지점 5곳: `tick()`(기존 블록 치환) / refresh 루프 본문(`:761`, D1의 `confirmMembershipIfNeeded` 다음) / **`handleWake(at:)` 맨 앞**(기존 `guard let sleepBeganAt, startedAt != nil` **위**) / `setMenuPresented(true)`의 `displayNow = Date()` 다음 / `clearPersistedSession()`의 기존 `refreshMenuBarTitle()` **앞**.

> `handleWake` 맨 앞이 단순 방어가 아니라 **필수**인 이유: 밤샘 잠자기 후 rollover 없이 `autoStop(endedAt: 어제 23:00)`이 돌면 `accumulatedDayStart`가 어제로 스탬프되는데 `displayNow`도 어제라 `todayDuration`(:283-293)의 판정이 참이 되어 **어제 3시간이 오늘 라벨로 샌다**.

**계약**: 메뉴바 라벨은 '지금 상태 단어'가 아니라 **오늘(KST) 누적 시간**이다: 근무중이면 흐르고, 퇴근 후엔 멈춰 남으며, 오늘 0이면 "오프", 미반영 큐가 있으면 "대기"(우선). 근무 여부의 구분은 아이콘이 진다. 자정 롤오버는 티커가 없는 유휴에서도 일어나며 지연 상한은 유휴 refresh 1주기(최대 10분) 또는 팝오버 열기/깨어남 중 먼저 오는 쪽이다. **강제 로그아웃(clearPersistedSession)으로 refresh 루프까지 멈춘 상태에서는 깨어남/팝오버 열기만이 트리거다.**
**테스트**: ① `MenuBarStatusFormatterTests`에 `offWorkKeepsTodayTotal`(elapsed 3661 → "01:01" + 아이콘이 `pause.circle.fill`) ② `menuBarKeepsTodayTotalAfterStop` ③ `rolloverResetsMenuBarWithoutTicker`(낡은 상태 "03:00" → rollover → 0 + "오프", 시계 주입 없이 결정적) ④ `handleWakeRollsOverDayWhenNotWorking` ⑤ **`menuBarShowsServerTodayTotalWithoutPopover`** — D1의 대표 가시효과 회귀 방어:
```swift
store.teamMembers = [TeamMemberStatus(id: store.session!.userID, name: "나", status: .offWork,
    updatedAt: Date(), currentSessionStartedAt: nil, weeklyDurationSeconds: 7_200, todayDurationSeconds: 7_200)]
store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
#expect(store.accumulatedSeconds == 7_200)
#expect(store.menuBarTitle == "02:00")   // 예전 계약이면 "오프"
```
깨지는 기존 테스트 없음(`:2400`·`:2753`·`CheckMenuRenderTests:281` 전부 확인). `snapshot.elapsedSeconds`를 읽는 뷰가 0건임을 전수 grep 확인 — 표시 불일치 없음.
**하위호환**: 없음(로컬 표시 전용).
**롤백**: `.offWork` 분기 1줄. `rolloverIfNeeded`는 남겨도 무해.

---

### N1-refresh refresh grant 단일 비행
> A안(await 직후 토큰 변화 확인)과 B안(공유 Task) **둘 다 넣는다**. A가 '이미 끝난' 창을, B가 '진행 중' 창을 닫는다. 어느 하나만으로는 표적 결함이 남는다.

**변경 지점**: `WorkTimerStoreAuth.swift:388 withSessionRetry`(:396-421 교체) · `:474 refreshPersistedSessionIfPossible` · 신규 헬퍼 / `WorkTimerStore.swift`(상태 1개) · `:936`

```swift
/// refresh grant 단일 비행 핸들. 같은 refresh token 으로 동시에 여러 grant 를 치면 GoTrue 재사용 창(10초)을
/// 벗어난 낙오 요청이 400 을 받고, 그 400 은 classifyAuthError 에서 .fatal 로 분류돼 **근무 중 강제 로그아웃**이 된다.
/// 이름 충돌 주의: refreshTask 는 30초 폴링 루프다. 관찰 대상 아님.
@ObservationIgnored var sessionRefreshTask: Task<SupabaseSession, Error>?

func refreshSessionSingleFlight(using refreshToken: String) async throws -> SupabaseSession {
    if let inFlight = sessionRefreshTask { return try await inFlight.value }
    let task = Task { [service] in try await service.refreshSession(refreshToken: refreshToken) }
    sessionRefreshTask = task
    defer { sessionRefreshTask = nil }
    return try await task.value
}
```
```swift
} catch let originalError as SupabaseWorkServiceError where originalError == .sessionExpired {
    guard generation == sessionGeneration else { throw originalError }
    // (A) 내가 대기하는 동안 다른 요청이 이미 갱신을 마쳤으면 grant 를 또 치지 않는다. 이 가드가 없으면
    //     단일 비행이 **끝난 뒤** 도착한 401 이 진입 시 캡처한 낡은 refresh token 으로 새 grant 를 쳐서
    //     400 → .fatal → 강제 로그아웃이 된다(단일 비행만으로는 못 막는 창).
    if let latest = session, latest.accessToken != currentSession.accessToken {
        return try await operation(latest)
    }
    guard let refreshToken = currentSession.refreshToken else {
        clearPersistedSession(); syncMessage = "다시 로그인 필요"; throw originalError
    }
    let refreshed: SupabaseSession
    do {
        refreshed = try await refreshSessionSingleFlight(using: refreshToken)   // (B)
    } catch {
        // 취소 판정을 세대 가드보다 앞에 둔다. 단일 비행 grant 는 비구조적 Task 라 호출자 취소를 물려받지
        // 않으므로(팝오버가 닫혀도 grant 는 끝까지 돈다), 여기서 볼 것은 grant 의 오류가 아니라 **내 태스크의
        // 취소 상태**다. 이걸 .sessionExpired 로 갈아치우면 호출부 7곳의 .cancelled 가드가 전부 헛돌아
        // "다시 로그인 필요" 헛경보가 뜬다(N2 의 8번째 지점).
        if Task.isCancelled || classifyAuthError(error) == .cancelled { throw CancellationError() }
        guard generation == sessionGeneration else { throw originalError }
        switch classifyAuthError(error) {
        case .cancelled: throw error            // 도달하지 않지만 형식상
        case .transient: throw originalError
        case .fatal:
            clearPersistedSession(); syncMessage = "다시 로그인 필요"; throw originalError
        }
    }
    guard generation == sessionGeneration else { throw originalError }
    session = refreshed
    persistSession(refreshed)
    return try await operation(refreshed)
}
```
`refreshPersistedSessionIfPossible`(:474)의 `service.refreshSession(...)`도 `refreshSessionSingleFlight(using:)`로. `clearPersistedSession`(:936 `refreshTask?.cancel()` 옆)에 `sessionRefreshTask?.cancel(); sessionRefreshTask = nil`.

**계약**: refresh grant는 스토어당 동시 최대 1개. 401을 받은 요청은 ① 그 사이 토큰이 바뀌었으면 grant 없이 새 토큰으로 재시도, ② 아니면 단일 비행 결과를 공유해 재시도한다. **이 grant는 비구조적 태스크라 호출자 취소로 중단되지 않으며**(진행 중 갱신을 낭비하지 않기 위한 의도), 취소된 호출자는 `CancellationError`로 조용히 빠져나간다. grant를 실제로 중단시키는 유일한 지점은 `clearPersistedSession`이다.
**테스트**: ① `alreadyRotatedTokenRetriesWithoutNewGrant`(**네트워크 0건**의 결정적 단위 — 클로저 안에서 `store.session`을 교체하고 `.sessionExpired` throw → `seen == ["access-token","rotated"]` + 요청 0건) ② `concurrentUnauthorizedRequestsIssueSingleRefreshGrant`(`@Suite(.serialized)`, 호스트 `delayed-expired-token-race` → grant **1건** + `isSignedIn` 유지. 수정 전엔 2가 된다) ③ `cancelledCallerDoesNotSeeExpiredSessionMessage`(20ms 후 취소 → `isSignedIn` + syncMessage가 "다시 로그인 필요"/"동기화 실패" 아님). 기존 `signOutIgnoresInFlightTokenRefresh`(:1201)는 그대로 통과.
**하위호환**: 요청 개수만 줄고 형태 동일.
**롤백**: 호출 2곳을 직접 호출로 되돌리고 A안 3줄 삭제.

---

### N2-cancel 취소 분기
> **실효는 `autoCloseAbandonedOwnSessionIfNeeded`(WorkTimerStoreSync.swift:356) 하나다.** 나머지는 호출부가 비구조적 `Task {}`라 오늘은 도달하지 않는다 — 이 사실을 감추면 다음 사람이 "가드가 있으니 안전하다"고 오판한다.

**변경 지점**: `WorkTimerStoreSync.swift:356 · :439 · :465 · :544` / `WorkTimerStoreAuth.swift:53 · :86 · :330` / **`:407-416`(8번째 지점, N1-refresh에 포함)**

각 catch **첫 줄**:
```swift
// 취소(.task 취소/팝오버 빨리 닫기)는 실패가 아니다 — 헛경보 문구를 남기지 않는다.
// 주의: 이 함수의 호출부는 비구조적 Task {} 라 오늘은 도달하지 않는다(WorkTimerStore.swift:381/447/547 등).
// 앞으로 구조적 경로(await 직접 호출)로 옮길 때를 위한 계약 고정이다. 실제로 헛경보를 없애는 것은 :356 하나.
if case .cancelled = classifyAuthError(error) { return }
```
반환형에 맞춘다: `:356`은 `{ return true }`(**'이 주기는 처리됨'으로 반환해야 호출부가 낡은 스냅샷으로 흡수를 진행하지 않는다** — 오늘도 실제로 "동기화 실패" 헛경보를 띄우는 유일한 지점). `:439`는 `clearAutoCloseUndo()`를 부르지 않아 배너가 남는다.

**덤(권장, `:356`)**: `accumulatedSeconds = member.todayDurationSeconds + closedTodaySeconds` 두 대입(:321-322)이 RPC **이전**에 일어난다. 취소로 조기 반환하면 마감되지도 않은 세션 몫이 누적에 남는다(최대 30초 과다 표시). 두 대입을 `do` 블록 안쪽(성공 분기)으로 옮기면 함께 사라진다.

**계약**: 모든 사용자 대면 catch의 **첫 줄 규약** — 취소는 어떤 표시 상태도 바꾸지 않고 조용히 반환한다. 아울러 `withSessionRetry`는 취소를 `.sessionExpired`로 위장하지 않는다.
**테스트**: `@Suite(.serialized) FixBSyncRaceTests`에 5건. ①`cancelledAbandonedAutoCloseDoesNotLeaveFailureMessage`(호스트 `delayed-abandoned-session-cancel`) ②`cancelledUndoAutoCloseKeepsBannerAndMessage` ③`cancelledAvatarUploadDoesNotLeaveFailureMessage` ④ **`cancelledDrainKeepsQueueAndDoesNotMarkPendingSync` — 반드시 내부 `store.syncTask?.cancel()`로**(외곽 Task 취소는 비구조적이라 안 닿는다. 원안대로 하면 항목이 정상 제거되어 단언이 깨진다):
```swift
store.enqueueSync()
try? await Task.sleep(for: .milliseconds(40))
store.syncTask?.cancel()
await store.syncTask?.value
#expect(!store.pendingItems.isEmpty)      // 재시도 대상 유지
#expect(!store.snapshot.pendingSync)
```
⑤`cancelledTokenRefreshIsNotReportedAsExpiredSession`(N1-refresh 리비전이 함께 있어야 의미가 생긴다).
**하위호환**: 없음. **롤백**: 삽입한 한 줄들 삭제.

---

### D3 12시간 마감 직전 시스템 유휴 확인
> **되감지 말고 응답창만 다시 연다.** 12시간을 채운 세션은 정의상 12시간 내내 잠들지 않고 하트비트를 보낸 맥의 세션이라, 잠자기 마감도 서버 스캐빈저도 백스톱이 아니다 — 12시간 규칙이 유일한 마감자다. `longSessionAnchor = now`로 되감으면 다음 판정이 12시간 뒤라 **자리를 뜬 뒤 최대 12시간이 유령 근무로 쌓인다**(35분 과소를 11시간 과다로 바꾼다).

**변경 지점**: `WorkTimerStore.swift:10` 아래(상수) · `:42` 아래(주입) · `:485-494`

```swift
// 12시간 자동 마감 직전 '사람이 앉아 있는가'를 판정하는 최근 입력 창(초).
static let longSessionIdleGraceSeconds: TimeInterval = 120

/// 마지막 입력 후 경과 초(주입). 기본은 NudgeScheduler 와 같은 CGEventSource 소스다 — 권한이 필요 없고
/// 입력 '내용'은 절대 보지 않으며 숫자 하나만 읽는다. 12시간 자동 마감 직전 1회만 호출한다(상시 폴링 아님).
/// 테스트가 갈아 끼워 결정적으로 검증한다(기본값을 그대로 쓰면 개발자 맥의 실제 유휴 초를 읽어 비결정적).
@ObservationIgnored var systemIdleSeconds: () -> TimeInterval = NudgeScheduler.systemIdleSeconds
```
```swift
if isLongSessionPromptActive {
    guard let promptShownAt, now.timeIntervalSince(promptShownAt) > Self.longSessionResponseWindowSeconds else { return }
    let idle = systemIdleSeconds()
    if idle < Self.longSessionIdleGraceSeconds {
        // 사람이 앉아 있다 — 지금은 마감하지 않는다. 다만 anchor 를 now 로 되감지는 않는다:
        // 12시간을 채운 세션은 '12시간 내내 깨어 있던 맥'의 세션이라 잠자기 마감도 서버 스캐빈저도
        // 백스톱이 아니다(하트비트가 계속 나가 last_seen 이 신선하다). 되감으면 다음 판정이 12시간 뒤라
        // 자리를 뜬 뒤 최대 12시간이 유령 근무로 쌓인다. 응답창(30분)만 다시 열어 되풀이 판정한다.
        // 진짜 되감기는 사용자가 [네, 근무 중이에요]를 누를 때만 일어난다(confirmStillWorking).
        self.promptShownAt = now
        return
    }
    // 마지막 입력 시각까지는 근무로 인정한다 — 모르는 구간만 잘라낸다(서버 스캐빈저의 '마지막 신호' 규약과 동일).
    // 12시간 시점보다 이르게 잘리지 않고(max), 미래로 가지 않는다(min).
    let lastInput = now.addingTimeInterval(-idle)
    autoStop(
        endedAt: max(anchor.addingTimeInterval(Self.longSessionThresholdSeconds), min(lastInput, now)),
        message: "장시간 미확인으로 자동 근무종료됨"
    )
    return
}
```
효과: 근무 중인 사람의 세션은 끊기지 않는다(35분 구멍·세션 분할 해소). 자리를 뜨면 최대 30분 안에 판정이 성립하고 마감 시각이 '마지막 입력'이라 꼬리도 안 잃는다. **유령 근무 상한이 12시간 + 30분으로 v0.2.14보다 좁아진다.**

**계약**: 자동 마감은 '12시간 + 30분 무응답 + 최근 2분 무입력' 세 조건 AND이며, 입력이 있으면 마감이 **30분 단위로 연기**될 뿐 12시간 카운터는 사용자 확인 없이 되감기지 않는다. 마감 시각은 `max(12시간 시점, 마지막 입력 시각)`.
**테스트**: ① `longSessionDefersAutoStopWhileUserIsActive`(`systemIdleSeconds = { 5 }` → `#expect(store.isLongSessionPromptActive)`(배너 유지) + `#expect(store.longSessionAnchor == t0)`(되감기 없음) + `pendingItems.isEmpty`. 이어서 `{ 600 }`으로 바꾸고 30분 더 → 마감 성립(연기가 무한이 아님)) ② `longSessionAutoStopsWhenMachineIsIdle`(idle 600 → 마감 시각이 `max(t0+12h, now-600)`) ③ `storeIdleSourceDefaultsToNudgeScheduler`(값 단언 금지, 배선만). **깨지는 기존 테스트 1개**: `longSessionAutoStopsAfterThirtyMinutesUnconfirmed`(:2132)에 `store.systemIdleSeconds = { 10_000 }` 한 줄 추가(lastInput이 12시간 시점보다 이르므로 `max`가 `t0+12h`를 골라 기존 단언 통과).
**하위호환**: 없음. 프라이버시 증가분 0 — `CGEventSource.secondsSinceLastEventType`은 넛지가 이미 60초마다 쓰는 같은 API이고 이번 변경은 12시간 주기당 최대 1회만 더 부른다.
**롤백**: `if idle < …` 블록 삭제.
**의존**: 웨이브 2의 D2가 이 함수 **선두**에 `guard !adoptedRemoteSession else { return }`를 넣는다. 위치가 달라 충돌 없음.

---

### O3 · O4 · O7-evict 토큰 (한 커밋, `CheckTokenUsage.swift` 단일 파일)

**O3 스캔 주기** — `:842 refreshPeriod: 30 → 300`, `:844 minRefreshInterval: 3 → 60`(서버 업로드 스로틀 60초와 같은 눈금 — 더 자주 스캔해도 실어 나를 경로가 없다). 상수 주입은 **하지 않는다**: 주입하면 테스트가 프로덕션과 다른 값으로 통과해 '실제로 300/60이 걸려 있는가'를 아무도 보증하지 못한다. 통제해야 할 유일한 변수인 시각은 이미 `clock`으로 주입돼 있다.
- 테스트 `refreshIfStaleSkipsWithinMinIntervalThenScansAfter`(:922-957)의 2초/4초 리터럴을 `window = TokenUsageStore.minRefreshInterval` 상대식(`window-1` 스킵 / `window+1` 스캔)으로. + 값 핀 `tokenScanCadenceStaysCoarse`(`refreshPeriod == 300 && minRefreshInterval == 60`).
- **주석 정정 3곳**: `:924`(테스트), `:826-827`(클래스 doc), 그리고 **`CheckMenuView.swift:172`** — 이 루프의 유일한 프로덕션 진입점 바로 위에서 "즉시 1회 + **30초 주기**"라고 단언한다. 이 줄이 남으면 다음 사람이 300을 30으로 되돌린다.

**O4 캐시 쓰기 스로틀** — `cacheSaveThrottleSeconds: TimeInterval = 300` + `lastCacheSaveAt`. `startScan`(:908-934)의 detached 클로저가 3-튜플 `(cache, usage, didSave)`를 반환하고 `saved = result.stats.cacheChanged && maySave`일 때만 `save`. **실제로 저장했을 때만 스탬프**한다(변경 없어 건너뛴 스캔이 다음 저장을 5분 뒤로 밀지 않게). 실행당 첫 저장은 `lastCacheSaveAt = .distantPast`라 스로틀 없이 나간다.
- **종료 훅 flush는 채택하지 않는다**: (1) 종료 경로(이미 3초 배리어)에 수 MB 동기 쓰기를 얹는다, (2) 필요 없다 — 저장을 놓쳐도 다음 실행이 스냅샷 전체를 롤백해 테일만 다시 읽으면 **정확히 같은 값**이 나온다(Claude는 `(message.id, requestId)` dedupe라 재삽입이 멱등, Codex는 `prevCumulative`/월·일 누산기가 같은 스냅샷에 함께 롤백), (3) '영영 저장 안 되는 실행'이 존재하지 않는다.
- 테스트 `cacheSaveIsThrottledButInMemoryStaysFresh` — mtime이 아니라 **파일 내용을 디코드**해 단언(결정적). 1) 첫 저장 나감 2) 61초 후 append+refresh → 파일은 여전히 1행이지만 `currentMonthUsage`는 최신 3) 301초 후 → 파일 3행.

**O7-evict** — `:637-649`. `filter`는 결과가 원본과 같아도 **항상 새 저장소를 할당하고 전 키를 재해싱**한다(퇴거 0건이 30일 중 29일). `contains(where:)`는 첫 히트에서 멈추고 할당이 없다.
```swift
if cache.claudeEntries.contains(where: { $0.value.ts14 < evictTs14 }) {
    cache.claudeEntries = cache.claudeEntries.filter { $0.value.ts14 >= evictTs14 }
    changed = true
}
// claudeFileStates / codexFileStates 도 동형(mtimeMicros < evictMicros)
```
의미 동등: 기존은 '개수가 줄었으면 changed', 새 코드는 '지울 대상이 하나라도 있으면 changed' — 술어가 같다. **새 테스트 없음**: 계약이 그대로라 새 단언은 중복이고 할당량은 벤치 없이 단언 불가다. 기존 `:587`(`cacheChanged == false`)과 `:641-659`(퇴거 + `cacheChanged == true`)가 술어 동등성을 양방향으로 고정한다.

**계약**: 토큰 집계 신선도는 '팝오버가 열려 있는 동안 최대 300초, 마지막 스캔으로부터 60초 이내면 재스캔 없음'. 캐시 파일 쓰기는 '변경 있음 + 300초 경과'일 때만이며 실행당 최소 1회 보장. `evict`의 관찰 가능한 계약 불변.
**하위호환**: 없음(로컬 스캔/캐시). 캐시 포맷·스키마 버전 불변.
**롤백**: 상수 되돌림 / `maySave = true` 고정 / 세 줄을 무조건 filter로.

---

### D6-1 리프레시 토큰 만료 오분류
> **삽입 위치가 핵심이다.** `lowercased`는 `[message, response.errorCode]`를 합친 문자열이라(`SupabaseWorkHTTP.swift:114-116`) `error_code` 값이 매칭 대상에 포함된다. `invalid login credentials`(:128) 앞에 넣으면 `{"error_code":"invalid_grant","msg":"Invalid login credentials"}`를 내려주는 배포본에서 **비밀번호 오류가 '다시 로그인 필요'로 뜬다**.

**변경 지점**: `SupabaseWorkHTTP.swift:133` 뒤 = `already` 분기(:134) **바로 앞**

```swift
        // refresh grant 실패(만료·재사용·폐기)는 '세션 만료'다. 바로 아래 already/registered/exists 포괄
        // 매칭보다 반드시 앞에 둔다 — GoTrue 의 "Invalid Refresh Token: Already Used" 가 그 가지에 걸려
        // 로그인 화면에 "이미 가입된 이메일"로 뜨던 오분류를 막는다. 반대로 invalid login credentials /
        // email not confirmed 보다는 **뒤**에 둔다 — lowercased 에는 error_code 도 합쳐지므로(:114-116),
        // password grant 실패가 error_code=invalid_grant 로 내려오는 배포본에서 이 분기가 먼저 걸리면
        // 비밀번호 오류가 '다시 로그인 필요'로 잘못 뜬다.
        // 두 형태를 모두 잡는다:
        //  (a) 구형 {"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}
        //      → message 는 error_description 하나만 뽑히므로(:105-112) invalid_grant 는 lowercased 에
        //        들어오지 않는다. "refresh token" 으로 잡힌다.
        //  (b) 신형 {"code":400,"error_code":"refresh_token_not_found","msg":"..."} → msg + error_code 양쪽.
        // 둘 다 400 이라 위 401 jwt 분기(:124-126)로는 못 잡는다.
        if lowercased.contains("refresh token")
            || lowercased.contains("refresh_token")
            || lowercased.contains("invalid_grant") {
            return .sessionExpired
        }
```
화면 문구는 기존 `.sessionExpired` 매핑 그대로 **"다시 로그인 필요"** — 새 문장을 만들지 않는다(JWT 만료가 이미 이 문구를 쓰고 `FooterWidthBudget` 176pt도 이 길이에 맞춰져 있으며 사용자 행동도 동일).

**계약**: 분류 우선순위에 '리프레시 토큰 실패 → `.sessionExpired`'를 `emailAlreadyRegistered`보다 앞, `invalidLoginCredentials`/`emailNotConfirmed`보다 뒤에 고정한다.
**테스트**: `serviceErrorMapsRefreshGrantFailureToSessionExpired` 4케이스 — (1) 구형 (2) 신형 (3) `{"msg":"User already registered"}` 422 → `.emailAlreadyRegistered` 유지 (4) **`{"error_code":"invalid_grant","msg":"Invalid login credentials"}` → `.invalidLoginCredentials`**(이 리비전의 존재 이유 — 원안 위치였다면 실패). 기존 `LiveE2ETests:877` 중복가입 경로는 refresh 문자열이 없어 통과.
**하위호환**: 클라 내부 분류만. **롤백**: 3줄 삭제.

---

### NF4-app · N1-dead · N2-parser · N3-const · N5-privacy · N6-split (웨이브 1 잡항목)

**NF4-app** — `SupabaseWorkModels.swift`의 `StartSessionRequest`에 `let appVersion: String`, `SupabaseWorkService`에:
```swift
/// 이 세션을 연 클라이언트 버전. 프로세스 수명 동안 불변이라 static let 로 고정한다.
/// nonisolated: actor SupabaseWorkService 가 읽으므로 UpdateCheckStore.bundleShortVersion() 도
/// nonisolated 여야 한다(CheckUpdateCheck.swift:104 에 nonisolated 를 붙일 것 — :57-66 상수들과 같은 이유).
nonisolated static let appVersion: String = UpdateCheckStore.bundleShortVersion()
```
테스트: 기존 세션 시작 본문 단언에 `#expect(body.contains("\"app_version\""))` + `#expect(!body.contains("\"appVersion\""))`. 값 자체는 번들 의존이라 단언하지 않는다.

**N1-dead 죽은 코드 4종** — 전수 grep으로 참조 0 확인. 삭제: `MyWeeklyGauge`(CheckMenuView.swift:883-897) → `TeamGoalGauge`(CheckComponents.swift:124-175, 유일 소비자가 MyWeeklyGauge라 **함께** 지워야 진짜 0) / `StatusChip`(:43-62, `// MARK: - Chips`는 PresenceChip이 쓰므로 존치) / `loadTeamDirectory()`(WorkTimerStore.swift:603-605) + `teamDirectory`/`selectedSignupTeamID`(:131-134) + `TeamDirectoryEntry`(SupabaseWorkModels.swift:100-105) + signOut의 2줄. **존치 사유 주석("렌더 테스트가 참조")이 거짓임을 실증**: `CheckMenuRenderTests` 0건, 유일 참조는 signOut 초기화 테스트 4줄. **`CheckTheme.gaugeGradient`는 지우지 마라** — `LeaderboardRow`(CheckComponents.swift:368)도 쓴다. 깨지는 테스트: `WorkTimerStoreTests:1092-1093,1129-1130` 4줄 제거. **N7 분할보다 먼저** 해야 옮길 타입이 하나 줄고 분할 diff가 깨끗해진다.

**N2-parser 파서 이중화** — 1단계로 실증 테스트만 먼저 넣어 빨간불을 확인한다.
```swift
@Test
func parseDateAcceptsMicrosecondTimestampsFromPostgREST() async throws {
    let base = try #require(ISO8601DateFormatter().date(from: "2026-07-26T04:15:35Z"))
    // 계약은 '절대 nil 이 아니다 + 같은 초에 귀속된다'까지다. 6자리를 ISO8601DateFormatter(.withFractionalSeconds)가
    // 못 읽으면 3단계 폴백이 소수부를 버리고 초 단위로 파싱한다(CheckWorkInsights.swift:340-352).
    // 소수초 '보존'까지 요구하면 그 폴백 경로에서 이 테스트가 스스로 터진다 — 요구하지 않는다.
    for value in ["2026-07-26T04:15:35.634567+00:00", "2026-07-26T04:15:35.634567Z"] {
        let parsed = try #require(await service.parseDate(value))
        let delta = parsed.timeIntervalSince(base)
        #expect(delta >= 0 && delta < 1)
    }
    #expect(await service.parseDate("2026-07-26T04:15:35+00:00") == base)
}
```
2단계: `WorkInsightsDate.parseRaw` → **`parsePreservingFraction`**(private 제거, **내림 없는** 진입점)으로 개명하고 `SupabaseWorkService.parseDate`가 위임. `parse`에 그대로 위임하면 기존 `parseDateAcceptsFractionalSecondsAndFallsBackToPlain`(:1673, 0.634 보존 단언)이 깨진다. `fractionalDateFormatter`(**`:10-17`** — `:9`의 출력용 `dateFormatter`는 존치, 지우면 8곳이 깨진다) 삭제. 계약: 수용 범위가 **넓어진다**(6자리 + 타임존 없는 소수초). 실증 커맨드는 테스트 **함수명** 기준(`--filter 'parseDate|fetchTeamStatusesParsesFractional'`).
**N3-const 명명 상수화** — `TeamMemberStatus`에(모델이 의존 방향상 아래):
```swift
/// 하트비트 신선도 상한(초). 하트비트 주기(30초)의 3배 — 한두 번 놓쳐도 stale 로 뒤집히지 않는 여유다.
/// **표시(presence)와 자동 마감(autoCloseAbandonedOwnSessionIfNeeded)이 반드시 같은 값을 써야 한다.**
/// 예전엔 두 곳이 각자 `90` 리터럴을 들고 있어, 한쪽만 손대면 화면은 '근무중'인데 스토어는
/// 세션을 마감하는(또는 그 반대) 구간이 생겼다.
static let staleAfterSeconds: TimeInterval = 90
```
치환 3곳: `SupabaseWorkModels.swift:34`(`> Self.staleAfterSeconds`), `WorkTimerStoreSync.swift:309`(`> TeamMemberStatus.staleAfterSeconds`), 그리고 **주석 2곳**(`SupabaseWorkModels.swift:3-5`, **`SupabaseWorkService.swift:19`** — 이 줄이 남으면 grep 90이 수렴하지 않는다). 나머지: `WorkTimerStore.tokenUploadThrottleSeconds = 60`(`WorkTimerStoreSync.swift:212`), `SupabaseWorkService.mySessionsRowLimit = 2000`(선언은 `:480` doc **앞**, `:479` `}` 다음 빈 줄 뒤 — `:481` 앞에 넣으면 doc이 두 동강 난다). 검증: `grep -rn '\b90\b'` 결과가 상수 선언 1줄뿐.
테스트: `staleThresholdIsOneSharedConstantForDisplayAndAutoClose`(경계 정확히 = `.activeWorking`, +1초 = `.staleWorking`) + 값 핀 2줄. 자동 마감 쪽은 런타임 테스트로 묶지 않는다 — 기존 D3 픽스처가 절대 과거 시각이라 상수를 바꿔도 안 흔들리고, 상대 시각으로 바꾸면 같은 테스트의 `accumulatedSeconds` 단언이 함께 흔들린다. **소스가 상수를 읽는다는 사실 자체(컴파일 타임 단일 원본)가 보장이다.**
**주의**: `WorkTimerStoreSync.swift:309` 근방은 웨이브 2 D2의 작업 구역이다. 웨이브가 갈려 있으므로 순서로 해소된다.

**N5-privacy `docs/privacy.md`** — 4곳. (1) `:13` 뒤 수집 항목 1줄 (2) `:22` "앱/웹사이트 사용 기록" → **"어떤 앱·웹사이트를 얼마나 썼는지(앱 사용 추적)"**로 좁힘 + `:24` 뒤 2줄 (3) `## AI 도구 토큰 사용량` 절 신설 (4) `## 다른 사람에게 보이는 정보` 절 신설.
핵심 — **경로에 대해 자기모순을 만들지 마라**. 캐시 키가 곧 파일 시스템 절대 경로이고(`CheckTokenUsage.swift:434-435`) Claude Code의 `~/.claude/projects/` 하위 디렉터리 이름은 프로젝트 경로를 인코딩한 값이라, "파일 경로를 읽지 않는다"는 거짓이다. 참인 진술만 쓴다:
```markdown
- **읽는 값**: 각 응답 줄에 도구가 기록해 둔 토큰 수(입력·출력·캐시 읽기·캐시 생성)와 그 시각, 그리고 같은
  응답을 두 번 세지 않기 위한 메시지 식별자입니다. **대화 내용·프롬프트·코드 등 로그 파일의 본문은 읽지 않습니다.**
- **서버로 보내는 값**: 이번 달 합계 여섯 숫자와 오늘 증가량, 그 숫자가 귀속된 달과 날짜, 기기 식별자뿐입니다.
  **어떤 파일·어떤 프로젝트에서 나왔는지는 보내지 않습니다.**
- **이 Mac에만 남는 값**: 다음에 이어 읽을 위치를 기억하려고, 스캔한 로그 파일의 **경로**와 크기·수정시각을
  `~/Library/Application Support/aing-check/token-usage-cache.json` 에 저장합니다. Claude Code 의 로그 경로에는
  작업 폴더 이름이 들어 있으므로 이 캐시에는 프로젝트 폴더 이름이 남습니다. **서버로 올라가지 않으며**,
  파일을 지우면 사라집니다(다음 실행에서 전체 재스캔).
```
(4)절은 **두 겹 구조**가 핵심 — 같은 팀 안(별명·아바타·근무여부·**세션 원본**·**계정 이메일**, `20260701000000:142,:173` RLS) / 앱 사용자 전체(콕찌르기·토큰 순위·팀별 현황이 팀 경계를 넘는다) / 어디에도 안 보이는 것.
검증: 각 주장을 소스 앵커로 대조(스캔 경로 `:429`·`:525`, 전송 필드 `TokenUsageMonthly:12-33`, 본문 미수집 `:458-471`, 기본 공개 `20260724010000:6`, 팀 무관 노출 `20260724020000:118-140`, 팀원이 이메일 읽음 `20260701000000:142-152`, **로컬 캐시 경로 `:434-435`**).

**N6-split `SleepEyeTexture` 분리** — 신규 `Sources/check/CheckSleepEyeTexture.swift`. 이동 범위 **`CheckCharacter3DView.swift:302-955`**(doc 302-317 + `enum` **318-955**). `:954`까지만 옮기면 enum이 안 닫히고 원본에 고아 `}`가 남는다. 원본 착지 앵커는 `:957`(`/// 근무 시간 라벨(캡슐).`). 새 파일 선두는 `import CoreGraphics` + `import SceneKit`만(302-955의 외부 타입은 `CGImage/CGContext/CGFloat` + `SCNGeometry/SCNGeometrySource/SCNGeometryElement`뿐). 최상위 `private` 선언 0건이고 역방향 참조는 `:94`·`:99` 두 곳(둘 다 non-private static)이라 **접근 수준 변경 0**.
순수성 실증:
```sh
git show HEAD:Sources/check/CheckCharacter3DView.swift | grep -vE '^import |^[[:space:]]*$' | sort > /tmp/before.txt
cat Sources/check/CheckCharacter3DView.swift Sources/check/CheckSleepEyeTexture.swift \
  | grep -vE '^import |^[[:space:]]*$' | sort > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt   # 출력이 비어야 한다
```
기능 실증은 **함수명 기준** 필터 또는 그냥 전체 `swift test`(`--filter CheckSleepEyesTests`는 파일명이라 0개를 돌린다). 충돌 위험이 사실상 0인 유일한 구조 작업이라 웨이브 1에 넣어도 안전하다(감사 §7에서 `CheckCharacter3DView` 관련 주장이 전부 폐기돼 아무도 안 건드린다).

---

## 웨이브 2 — v0.2.16

### D2 흡수 세션 소유권 표식
> `adoptedRemoteSession == true`인 동안 이 맥의 **자동** 마감 경로는 서버에 아무 쓰기도 하지 않는다. **하트비트도 보내지 않는다** — 이게 리뷰가 잡은 치명 누락이다.

**변경 지점**: `WorkTimerStore.swift:42` 아래(플래그) · `:377 finishWorkBeforeQuit` · `:412 start` · `:432 stop` · `:466 handleWake` · `:482 evaluateLongSession` · `:516 autoStop` · `:945 adoptWorkStateOwner` / `WorkTimerStoreSync.swift:273 sendHeartbeatIfWorking` · `:384 performUndoAutoClose` · `:613 switch` / `WorkTimerStoreAuth.swift:435 signOut` / `CheckApp.swift:49`

**1) 플래그**
```swift
/// 지금 진행 중인 세션(startedAt/currentSessionID)을 **이 앱 인스턴스가 열었는가**의 반대말.
/// true = 서버 스냅샷에서 흡수한 세션 — 다른 맥(또는 이 맥의 이전 실행)이 열었다.
/// 그래서 이 맥의 **자동** 마감 경로(잠자기·12시간·종료 동기화)와 **하트비트**는 이 세션을 건드리지 않는다.
/// 사용자가 직접 누른 종료(stop)는 그대로 허용한다 — 같은 사람의 명시적 의사이기 때문이다.
///
/// 수명: startedAt 을 세우는 전이가 함께 확정하고, 내리는 전이가 false 로 되돌린다. **영속하지 않는다** —
/// startedAt 자체가 영속되지 않아(init 은 세션 토큰만 복원) 재시작 후 살아나는 세션은 정의상 흡수이고
/// applyRemoteOwnStatus 가 그때 true 를 세운다. 관찰 대상 아님(뷰가 읽지 않는다).
@ObservationIgnored var adoptedRemoteSession = false
```

**2) 하트비트 차단 (필수 — 이게 없으면 D2는 '아무도 못 닫는 세션'을 만든다)** `WorkTimerStoreSync.swift:273`
```swift
func sendHeartbeatIfWorking() async {
    // 하트비트는 '내가 이 세션의 소유 맥이다'라는 선언이다. 흡수 세션에서 보내면 work_statuses.last_seen_at 이
    // 계속 신선해져 close_abandoned_work_sessions(coalesce(last_seen_at,updated_at) < now()-10min) 가 영영
    // 발화하지 못한다 — D2 가 잠자기·12시간·종료 마감을 모두 막은 상태에서 이건 '아무도 못 닫는 세션'이 된다
    // (맥A 종료 후 맥B 가 밤새 하트비트 → 타이머 40시간, 팀원 화면 '근무중' 고착).
    guard !adoptedRemoteSession else { return }
    guard startedAt != nil, session != nil, let sessionID = currentSessionID, let teamID = currentTeamID else { return }
    …
}
```
이 한 줄로 연쇄가 닫힌다: 소유 맥 사라짐 → 신호 공백 10분 → **흡수 맥 자신의 클라 스캐빈저**(Sync:86, presence 판정에 자타 구분이 없어 내 행도 대상)가 RPC 발사 → 마감 → 다음 폴링 `(.offWork,.some)` → 로컬 종료. **pg_cron 없이도 성립하므로 R8 확인이 '필수'에서 '권장'으로 내려간다.**

**3) 흡수 분기 교체** (`WorkTimerStoreSync.swift:613`)
```swift
switch (ownMember.status, startedAt) {
case (.working, nil):
    adoptRemoteSession(ownMember)
case (.offWork, .some):
    startedAt = nil
    // 흡수/자체 세션 모두 여기서 끝난다 — 표식과 잔존 세션ID를 함께 끊는다.
    // (예전엔 currentSessionID 를 남겨, 이미 닫힌 세션 id 가 다음 하트비트로 다시 올라갔다.)
    currentSessionID = nil
    adoptedRemoteSession = false
    longSessionAnchor = nil
    clearLongSessionPrompt()
    snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
    stopTimerIfIdle()
default:
    // (.working, .some): 서버가 **다른** 세션을 열고 있으면 그쪽이 진실이다. partial unique
    // (work_sessions_one_open_per_user)상 사용자당 열린 세션은 하나뿐이므로, id 가 다르다는 것은
    // 내가 든 id 가 이미 닫혔다는 뜻이다. 이 재흡수가 없으면 D2 수정 후 흡수 맥이 어제 시작시각을
    // 든 채 오늘 세션을 미러링해 타이머가 20시간이 된다. **D2 없이는 필요 없고, 이 수정 없이 D2 를
    // 넣으면 더 나쁜 버그가 된다 — 반드시 한 커밋.**
    if ownMember.status == .working, let serverSessionID = ownMember.activeSessionID,
       serverSessionID != currentSessionID {
        if currentSessionID == nil, startedAt != nil {
            currentSessionID = serverSessionID          // 강제 로그아웃 → 재로그인 (표식 불변)
        } else if ownMember.currentSessionStartedAt != nil {
            // 열린 세션 행이 실제로 온 경우에만 재흡수한다. work_statuses 와 work_sessions 는 병렬 GET 이라
            // (SupabaseWorkService.swift:88) 찢어진 읽기에서 startedAt 이 now 로 리셋될 수 있다.
            adoptRemoteSession(ownMember)
        }
    }
    snapshot.pendingSync = false
}
```
```swift
/// 서버가 들고 있는 내 열린 세션을 로컬로 흡수한다. **이 앱이 연 세션이 아니므로** 표식을 세운다.
/// == 가드로 실제 변화가 있을 때만 대입해 30초 폴링이 잎 뷰를 헛무효화하지 않게 한다.
private func adoptRemoteSession(_ ownMember: TeamMemberStatus) {
    let restoredStart = ownMember.currentSessionStartedAt ?? Date()
    displayNow = Date()
    if startedAt != restoredStart { startedAt = restoredStart }
    let resolvedID = ownMember.activeSessionID ?? currentSessionID
    if currentSessionID != resolvedID { currentSessionID = resolvedID }
    if longSessionAnchor != restoredStart { longSessionAnchor = restoredStart }
    clearLongSessionPrompt()
    sleepBeganAt = nil
    adoptedRemoteSession = true
    snapshot = WorkStatusSnapshot(status: .working,
        elapsedSeconds: max(0, Int(displayNow.timeIntervalSince(restoredStart))))
    startTimer()
}
```

**4) 자동 마감 전수 차단**
- **(a) `autoStop`(:516) 단일 초크 포인트** — `guard let sessionStart = startedAt` 뒤: `guard !adoptedRemoteSession else { return }`. 호출자마다 가드를 흩뿌리는 대신 여기 한곳에서 막아 앞으로 추가될 경로도 자동으로 안전해진다.
- **(b) `handleWake`(:466)** — `autoStop(...)` 위에:
```swift
// 흡수 세션은 이 맥의 것이 아니다 — 잠자기로 마감하지 않고 **아무 것도 하지 않는다**.
// 로컬 표시만 내리는 것은 무의미하다: 다음 폴링(≤30초)이 (.working, nil) 로 즉시 재흡수한다.
// 소유 맥이 사라지면 스캐빈저가 마지막 신호 시각으로 마감해 (.offWork,.some) 가지가 로컬을 정확히 내린다.
guard !adoptedRemoteSession else { self.sleepBeganAt = nil; return }
```
- **(c) `evaluateLongSession`(:482)** — 함수 **선두**(D3 블록 위): `guard !adoptedRemoteSession else { return }`
- **(d) `finishWorkBeforeQuit`(:377)** — 가드에 `!adoptedRemoteSession` 추가
- **(e) `applicationShouldTerminate`(CheckApp.swift:49)** — `guard store.isSignedIn, store.startedAt != nil, !store.adoptedRemoteSession else { return .terminateNow }`
- **(f) 스캐빈저 2종은 변경 없음** — `scavengeAbandonedTeamSessionsIfNeeded`(Sync:86)는 판정이 신호 공백뿐이라 살아 있는 소유 맥은 애초에 대상이 아니고, `autoCloseAbandonedOwnSessionIfNeeded`(:296)는 `startedAt == nil`을 요구해 흡수 상태에서는 진입조차 못 한다.

**5) false로 되돌리는 지점**: `start()`(:412), `stop()`(:432), `performUndoAutoClose` 성공(Sync:427 — 사용자가 소유권을 명시적으로 주장), `adoptWorkStateOwner`(:952), `signOut()`(Auth:435). **`clearPersistedSession`은 건드리지 않는다** — startedAt을 일부러 남기므로 표식도 그 세션을 계속 서술해야 한다. (`autoStop` 안의 리셋은 (a) 가드 때문에 도달 불가라 수명표 근거로 쓰지 마라.)

**계약**: `adoptedRemoteSession == true`는 "진행 중 세션을 이 앱 인스턴스가 열지 않았다"를 뜻하며, 참인 동안 이 맥의 자동 마감 경로와 하트비트가 서버에 아무 쓰기도 하지 않고 로컬 표시를 서버 미러로 유지한다. 사용자가 누른 종료/되돌리기는 영향받지 않는다. 함께 바뀌는 기존 계약 둘: `(.offWork,.some)`이 이제 `currentSessionID`도 지운다 / `(.working,.some)`에서 서버 세션ID가 다르고 **열린 세션 시작시각이 함께 왔으면** 재흡수한다.
**테스트**: 신규 9건. ①`adoptedRemoteSessionIsNotClosedByWake`(sleep/wake 6분 → `startedAt != nil`, `pendingItems.isEmpty`, 문구 불변) ②**대조군** `ownSessionStillAutoStopsOnWake`(`start()` 후 → `startedAt == nil`, 큐에 `[.start, .stop]`) ③`adoptedRemoteSessionSuppressesLongSessionPrompt` ④`adoptedRemoteSessionSkipsQuitSync` ⑤`remoteSessionCloseClearsAdoptionMarks` ⑥`replacedRemoteSessionIsReadopted`(+같은 id 재호출 시 불필요 대입 없음) ⑦`userStopIsAllowedOnAdoptedSession` ⑧**`adoptedSessionSendsNoHeartbeat`**(요청 0건) ⑨**대조군** `ownSessionStillHeartbeats`(1건).
**깨지는 기존 테스트 1개**: `reloginRestoresSessionIDSoHeartbeatResumes`(:1622~)의 **대조군 블록**(:1673-1675). 의도된 계약 변경이므로 교체:
```swift
// 계약 변경(v0.2.16): 로컬 세션ID 가 서버의 열린 세션과 다르면 서버 쪽이 진실이다(partial unique 상
// 사용자당 열린 세션은 하나뿐이라 내 id 는 이미 닫힌 세션을 가리킨다). 재흡수하고 표식을 세운다.
store.currentSessionID = "local-session"
store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
#expect(store.currentSessionID == serverSessionID)
#expect(store.adoptedRemoteSession)
```
앞부분(`currentSessionID == nil` → id만 복원)은 그대로 통과해야 한다 — 그게 이 테스트의 원래 회귀 지점이다. 렌더 테스트 영향 없음(`@ObservationIgnored`, 뷰가 안 읽음).
**하위호환**: 서버·데이터 변경 0. **혼합 함대에서는 편측 수정**이다 — 이 수정은 "새 버전 맥이 남의 세션을 마감하지 않게" 만들 뿐, 아직 v0.2.10인 두 번째 맥은 여전히 흡수 세션을 잠자기 시각으로 마감한다. 완전 해소는 전 기기 업데이트 후.
**롤백**: 커밋 revert. 급하면 플래그 초기값 옆에 `// rollback` 주석과 함께 항상 false로 두면 자동 마감이 v0.2.14로 되돌아간다.
**남는 노출(감수)**: 흡수 세션 + 5~10분 잠자기(스캐빈저 발화 전) 구간이 근무로 계상된다. 상한 ~10분, 기존 잠자기 유예 5분과 같은 자릿수.

---

### D5 23505 poison-pill 큐 처분
**변경 지점**: `WorkTimerStoreSync.swift:526 runPendingSync`(:544 catch + 꼬리) / 신규 `surrenderLocalSessionToServer()`

**고착 연쇄(코드로 확인)**: `startWork`는 `on_conflict=id`로 **같은 id 재전송**만 멱등화한다. 서버에 다른 id의 열린 세션이 있으면 partial unique에 걸려 23505 → `.sessionAlreadyOpen`. `while`이 이 throw를 일시 실패로 보고 항목을 남긴 채 return하므로 영원히 같은 자리에서 멈춘다. 그 결과 `applyRemoteOwnStatus`(:600)와 `autoCloseAbandonedOwnSessionIfNeeded`(:297)의 `pendingItems.isEmpty` 가드가 계속 막혀 **서버 진실을 영영 흡수하지 못한다**.

```swift
private func runPendingSync() async {
    guard session != nil, !pendingItems.isEmpty else { return }
    let generation = sessionGeneration
    // 이번 드레인에서 '이미 열린 세션' 충돌을 만났는가. 꼬리의 refreshTeamStatus 가 syncMessage 를
    // "동기화됨"으로 정규화하므로(:41), 사용자에게 이유를 남기려면 그 뒤에 한 번 더 세워야 한다.
    var surrenderedToRemote = false
    while let item = pendingItems.first {
        do { … } catch {
            if case .cancelled = classifyAuthError(error) { return }   // N2(웨이브 1)
            guard generation == sessionGeneration else { return }
            // '이미 열린 세션이 있다'(23505)는 재시도해도 영원히 같은 답이다. 큐에 남기면 드레인이 그 자리에서
            // 멈춰 pendingItems.isEmpty 가드가 흡수·자동마감을 통째로 막는다. 항목을 버리고 서버에 넘긴다.
            // 같은 sessionID 를 가진 뒤따르는 항목까지 함께 버린다: start 만 버리고 남은 stop 은 세션ID 없는
            // PATCH 로 **다른 맥의 열린 세션을** 내 종료 시각으로 마감한다(D2 와 똑같은 피해).
            if (error as? SupabaseWorkServiceError) == .sessionAlreadyOpen {
                pendingItems.removeAll { $0.sessionID == item.sessionID }   // 최소한 item 자신은 제거 → 무한루프 불가
                if case .start = item.operation { surrenderLocalSessionToServer() }
                surrenderedToRemote = true
                snapshot.pendingSync = false
                refreshMenuBarTitle()
                continue
            }
            snapshot.pendingSync = true
            syncMessage = authMessage(for: error, fallback: "동기화 실패")
            refreshMenuBarTitle()
            return
        }
    }
    guard generation == sessionGeneration else { return }
    snapshot.pendingSync = false
    refreshMenuBarTitle()
    await refreshTeamStatus()
    guard generation == sessionGeneration else { return }
    if surrenderedToRemote {
        let message = authMessage(for: SupabaseWorkServiceError.sessionAlreadyOpen, fallback: "동기화 실패")
        if syncMessage != message { syncMessage = message }
    }
}
```
```swift
/// 서버가 이미 내 열린 세션을 들고 있어 이 맥의 시작이 거절됐을 때, 로컬 세션 표식을 내려놓는다.
/// 진행 표시(startedAt)까지 지워야 다음 폴링의 applyRemoteOwnStatus 가 (.working, nil) **정식 흡수** 분기로
/// 들어가 서버의 시작시각/세션ID를 그대로 받아 온다.
/// workStateWriteGeneration 은 **올리지 않는다** — 흡수를 막으면 안 되기 때문이다(다른 write 경로와 반대).
/// 누적(accumulatedSeconds)도 건드리지 않는다 — 그 세션은 아직 안 끝났고 다음 폴링이 서버 today 로 덮는다.
private func surrenderLocalSessionToServer() {
    startedAt = nil
    currentSessionID = nil
    adoptedRemoteSession = false
    longSessionAnchor = nil
    clearLongSessionPrompt()
    sleepBeganAt = nil
    snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
    stopTimerIfIdle()
    refreshTimedBanner()
}
```
표시상 근무가 잠깐(≤30초, 대개 즉시 이어지는 `refreshTeamStatus` 한 왕복) 꺼졌다가 서버 시작시각으로 되살아난다. '대기 고착 + 몇 시간 눈먼 상태'보다 압도적으로 낫다.

**계약**: `.sessionAlreadyOpen`(23505)은 **영구 거절**로 분류된다 — 해당 항목과 같은 `sessionID`의 모든 큐 항목을 버리고, `.start`였다면 로컬 소유권을 내려놓아 다음 흡수에 넘긴다. 그 외 모든 throw는 종전대로 일시 실패다. **버려지는 start+stop 쌍에 대해**: `work_sessions_one_open_per_user`는 `where ended_at is null` 부분 인덱스라 완료 세션은 걸리지 않는다 — 즉 서버가 받을 수 있었던 데이터다. 이번 릴리스에서는 **단순함을 택해 기록을 포기한다**(보존하려면 D6-stopWork의 id 필터가 먼저여야 안전하다).
**테스트**: ①`sessionAlreadyOpenDropsStartItemAndYieldsToServer`(스텁 호스트 `session-conflict`에 409 + 23505 본문. 단언 순서: 큐 비었음 → `startedAt == nil` → `currentSessionID == nil` → **PATCH 0건**(짝 stop이 남의 세션을 마감하지 않았음) → 문구) ②`sessionAlreadyOpenThenPollAdoptsServerSession` ③**대조군** `transientFailureStillHaltsDrainInOrder`(기존 `stop-fails` 호스트 → 항목 잔류 + `pendingSync`. 새 분기가 일시 실패까지 삼키지 않음을 고정). e2e `LiveE2ETests.swift:1111` 옆에 `#expect(store.startedAt != nil)` 추가 + 주석을 "409면 항목이 **버려지고 로컬이 소유권을 내려놓는다**"로 갱신(안 그러면 `:1117`의 `#require(store.currentSessionID)`가 엉뚱한 지점에서 실패한다).
**하위호환**: 서버·요청 형태 무변경. 오히려 v0.2.10 맥이 연 세션이 남은 상황에서 새 버전 맥이 자력 회복하므로 혼합 함대에 유리하다.
**롤백**: catch 안 `if ... == .sessionAlreadyOpen { … }` 블록 통째 삭제.
**의존**: D2 선행 필수.

---

### D6-stopWork nil-안전 세션ID 필터
> 감사의 두 주장 중 "`id=eq.`만으로는 D2를 못 막는다"는 맞고, "저비용이니 그래도 달자"는 **그대로 하면 새 결함이 생긴다**. `syncCurrentStatus`(:487·497)가 `currentSessionID ?? UUID().uuidString`으로 nil을 임의 UUID로 붕괴시키므로, 순진한 필터는 0행 매치 → 폴백 POST가 새 완료 세션을 만들고 서버의 열린 세션은 그대로 남아 **이중 계상**된다.

**변경 지점**: `SupabaseWorkService.swift:229 stopWork`(:233-237 queryItems) / `WorkTimerStore.swift:986 PendingWorkItem` · `:483-501 syncCurrentStatus` / `WorkTimerStoreSync.swift:576 performPendingOperation(.stop)`

```swift
/// 이 조작이 **확실히** 가리키는 서버 세션 id. sessionID 는 폴백 POST 용이라 nil 을 임의 UUID 로 붕괴시키지만,
/// 이 값은 '몰랐다'를 nil 로 보존한다 — stopWork 의 id 필터를 걸어도 되는지 판정하는 유일한 근거다.
let knownServerSessionID: String?   // init 기본값 nil — 기존 호출부(테스트 포함) 무수정
```
```swift
func stopWork(..., fallbackSessionID: String, targetSessionID: String? = nil) async throws {
    var items = [
        URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
        URLQueryItem(name: "user_id", value: "eq.\(userID)"),
        URLQueryItem(name: "ended_at", value: "is.null")
    ]
    // 서버 세션 id 를 확실히 알 때만 넘긴다. nil 이면 종전대로 '내 열린 세션'을 마감한다
    // (로컬이 id 를 잃은 복구 경로 — 여기서 필터를 걸면 서버 세션이 고아가 된다).
    if let targetSessionID { items.append(URLQueryItem(name: "id", value: "eq.\(targetSessionID)")) }
    …
}
```
필터를 다는 곳은 **`performPendingOperation`의 `.stop` 한 곳뿐**(`targetSessionID: item.knownServerSessionID`). `autoCloseAbandonedOwnSessionIfNeeded`(Sync:327)에는 **넘기지 않는다(nil)**:
```
// 이 경로는 '로컬도 상태표도 믿을 수 없어서' 도는 복구다 — work_statuses.active_session_id 는 좀비 트리거
// (20260717040000:29-30)/스캐빈저(20260712120000:47)가 독립적으로 null 로 만들고 work_sessions 와는
// 병렬 GET 이라 어긋날 수 있는데, 어긋난 id 로 필터를 걸면 PATCH 0행 → 폴백 POST 가 완료 세션을 새로
// 만들고 진짜 열린 세션은 남는다(이중 계상). 필터 없는 '내 열린 세션 마감'이 여기선 정답이다.
```
**서버 `check (ended_at >= started_at)` 제약은 여기서 하지 않는다** — R9-c(웨이브 0)가 트리거+제약 형태로 이미 처리했다. 중복 구현 금지.

**계약**: `stopWork`는 `targetSessionID`가 주어지면 그 세션 하나만 마감하고, 아니면 종전대로 '내 열린 세션'을 마감한다. 필터를 거는 것은 **큐 항목이 자기 세션을 확실히 알 때뿐**이다.
**테스트**: `SupabaseWorkServiceTests` 2건(`id=eq.S1` 포함 / 부재 + 나머지 3필터 유지). `WorkTimerStoreTests` 2건 — `stopWithoutKnownSessionIDStillClosesServerSession`은 **쿼리 문자열로만 단언**한다(`#expect(patch.url?.query?.contains("id=eq.") != true)` + `ended_at=is.null` 포함). 폴백 POST 유무는 단언하지 않는다 — 스텁은 PATCH에 빈 본문을 주므로 `updatedRows`가 항상 비어 폴백이 **언제나** 발사되고, 실서버 의미를 재현할 수 없다(그 검증은 e2e의 몫). + `stopAfterNormalStartCarriesSessionID`.
**하위호환**: PostgREST PATCH에 쿼리 파라미터 하나가 붙을 뿐. RLS 정책은 `user_id = auth.uid()`만 보므로 영향 없다. v0.2.10은 종전 요청을 그대로 보내고 서버가 두 형태를 모두 받는다.
**롤백**: 서비스의 `if let targetSessionID` 3줄 삭제.
**의존**: D2 · D5 선행 필수.

---

### D4 로그아웃 확인 배너 + 미반영 큐 보존
**변경 지점**: `WorkTimerStore.swift:213` 부근(상태) · 신규 3함수 · `:88 setMenuPresented(false)` · `:921 clearPersistedSession` / `WorkTimerStoreAuth.swift:454`(`pendingItems = []` 삭제) · `:459` / `CheckMenuView.swift:43-53 TopBanner` · `:77-84` · `:86-97` · `:187-194` · `:199-206` · `:2037-2039`

```swift
/// 로그아웃 확인 배너 노출 여부. 진행 중 근무나 미반영 큐가 있을 때만 선다 — 푸터의 로그아웃 버튼은
/// 앱 종료 버튼과 8pt 옆이라 오조작이 잦은데, 예전엔 확인 없이 startedAt/pendingItems 를 통째로 버렸다.
var signOutConfirmPending = false

/// 푸터 로그아웃 버튼의 **유일한** 진입점. 잃을 것이 없으면 즉시 로그아웃하고, 있으면 확인 배너만 세운다.
func requestSignOut() {
    guard startedAt != nil || !pendingItems.isEmpty else {
        signOutConfirmPending = false; signOut(); return
    }
    if !signOutConfirmPending { signOutConfirmPending = true }
}

/// 확인 배너의 [로그아웃]. 앱 종료와 같은 3초 배리어로 퇴근 upsert 를 밀어 넣고 로그아웃한다.
/// 배리어가 타임아웃해도(오프라인) 큐는 signOut 이 보존하므로 재로그인 시 재생된다.
@discardableResult
func confirmSignOut() -> Task<Void, Never> {
    signOutConfirmPending = false
    return Task { @MainActor [weak self] in
        await self?.finishWorkBeforeQuit()
        self?.signOut()
    }
}

func cancelSignOut() { if signOutConfirmPending { signOutConfirmPending = false } }
```
**`signOut()`의 `pendingItems = []`(Auth:454)를 삭제**하고 주석으로 대체:
```swift
// 미반영 큐는 로그아웃으로 버리지 않는다 — clearPersistedSession(WorkTimerStore.swift:922)이 강제 로그아웃
// 경로에서 이미 같은 규약을 명시한다. 큐는 UserDefaults 에 남지 않는 메모리 장부라 한 번 비우면
// 오프라인에서 쌓인 근무가 영구 소실된다. 소유 계정은 workStateOwnerUserID 로 남으므로,
// 다른 계정이 로그인하면 그때 adoptWorkStateOwner 가 정확히 걷어낸다.
```
**플래그 수명 3곳 추가** — 안 넣으면 배너를 열어 둔 채 팝오버를 닫았을 때 플래그가 남고, 이 배너가 `topBanner` 선두라 **12시간 확인·되돌리기 배너를 전부 밀어낸다**(오조작 한 번으로 유예 10분짜리 [되돌리기]가 영영 안 보일 수 있다):
- `setMenuPresented(false)` 가지(`showsRetroBanner` 옆): `if signOutConfirmPending { signOutConfirmPending = false }`
- `signOut()`(Auth:459 `isEditingWeeklyGoal = false` 옆), `clearPersistedSession()`(:921 `showsRetroBanner = false` 옆): `signOutConfirmPending = false`

**배너**(`TopBanner`에 `case signOutConfirm` 최우선 + 높이는 기존 `inlineBannerHeight` 케이스에 합류 → `worstChrome` 불변). 렌더는 **메인 가지와 무소속 가지 둘 다**(무소속 계정도 강제 로그아웃 잔재로 큐를 들고 있을 수 있는데 그 가지엔 배너 렌더가 아예 없어 버튼이 먹통으로 보인다):
```swift
InlineActionBanner(
    icon: "rectangle.portrait.and.arrow.right",
    // 게이트가 (startedAt != nil || !pendingItems.isEmpty) 이므로 문구도 갈라야 한다 —
    // 오프라인에서 start+stop 이 큐에만 쌓인 상태에서 "진행 중인 근무"는 거짓이다.
    title: store.startedAt != nil ? "진행 중인 근무가 있어요" : "아직 안 보낸 근무 기록이 있어요",
    subtitle: "저장하고 로그아웃할까요?",
    actionTitle: "로그아웃",
    tint: CheckTheme.danger,
    action: { store.confirmSignOut() },
    onDismiss: { store.cancelSignOut() }
)
```
푸터 버튼(`:2038`, 프로덕션 유일 호출처)을 `store.requestSignOut()`으로.

**계약**: 푸터 로그아웃은 2단계다. `signOut()`은 더 이상 `pendingItems`를 비우지 않는다 — 큐의 소유권은 오직 `workStateOwnerUserID` + `adoptWorkStateOwner`가 판정한다(강제 로그아웃 경로와 동일 규약).
**테스트**: 6건 — `signOutWithRunningWorkAsksForConfirmationFirst`(아무것도 파괴 안 함) / `confirmSignOutSyncsStopThenSignsOut` / `cancelSignOutKeepsSession` / `signOutWithoutWorkSignsOutImmediately` / `signOutPreservesUnsyncedQueueForSameAccount`(+ `adoptWorkStateOwner("다른-uuid")` → 비워짐, 계정 오염 방지 유지) / **`signOutConfirmClearsWhenPopoverCloses`**. 렌더 1건: `signOutConfirmBannerRendersAndOutranksOthers`(다른 배너 조건도 켠 상태로 **하나만** 그려지는지, 상대 비교).
**깨지는 기존 테스트 1개**: `signOutClearsSessionStateAndCallsLogout`의 `#expect(store.pendingItems.isEmpty)`(:1137) → `#expect(store.pendingItems.count == 1)` + `#expect(store.workStateOwnerUserID == "…0002")`(의도된 계약 변경).
**하위호환**: 없음(`pendingItems`는 UserDefaults에 없는 메모리 장부).
**롤백**: 푸터 버튼을 `signOut()`으로 되돌리고 `pendingItems = []` 복원(배너 코드는 남아도 플래그가 안 서서 무해).

---

## 웨이브 3 — v0.2.17

### N2-clamp `liveTodayDurationSeconds` KST 자정 클램프 (NF1 선행)
**변경 지점**: `SupabaseWorkModels.swift:53-75`

주간 쪽은 이미 `clippedStart`로 해결돼 있다. **창 시작만 인자로 뺀 공용 헬퍼**로 합친다.
```swift
/// 진행 세션이 [windowStart, now] 창에 기여하는 초. 창 시작 이전 구간은 귀속하지 않고, stale 세션은
/// now 가 아니라 마지막 신호 시각으로 끝을 클램프한다(서버 clippedContribution 과 동일 규약).
/// 주 경계(월요일 00:00)와 하루 경계(자정)가 같은 식을 쓰게 해, 한쪽만 고쳐 어긋나는 일을 없앤다.
private func currentContributionSeconds(windowStart: Date, now: Date) -> Int {
    guard status == .working, let started = currentSessionStartedAt else { return 0 }
    let clippedStart = max(started, windowStart)
    let end: Date
    if case .staleWorking = presence(now: now) { end = lastSeenAt ?? updatedAt ?? started } else { end = now }
    return max(0, Int(end.timeIntervalSince(clippedStart)))
}

func liveWeeklyDurationSeconds(now: Date = Date()) -> Int {
    weeklyDurationSeconds + currentContributionSeconds(windowStart: TeamWeeklyGoal.koreanWeekStart(for: now), now: now)
}

/// 팀원의 '오늘'(KST) 누적. 서버 today(완료분, 자정 클리핑 완료) + 진행 세션의 자정 이후 몫.
/// 자정 클리핑이 없던 시절엔 어제 22시에 시작한 세션이 새벽 1시에 '오늘 3시간'으로 표시됐다.
func liveTodayDurationSeconds(now: Date = Date()) -> Int {
    todayDurationSeconds + currentContributionSeconds(windowStart: TeamWeeklyGoal.koreanDayStart(for: now), now: now)
}
```
**기존 표시 영향 0**: 전수 grep 결과 `liveTodayDurationSeconds`는 정의(`:57`) 외 호출처가 소스·테스트 통틀어 **0건인 죽은 코드**다. 즉 회귀 위험 없는 선행 정지작업이고, 위험은 전부 NF1 쪽(행 높이)에 있다. `liveWeeklyDurationSeconds`는 식이 문자 그대로 동일하게 유지된다.
**테스트**: `liveTodayClipsSessionStartedBeforeKSTMidnight` — 자정−2h 시작 + now=자정+1h + today 0 → **3600**(3시간 아님). stale(lastSeenAt=자정−30분) → 0. 자정 이후 시작 → 전체 반영. 기존 주 경계 테스트를 그대로 두는 것이 리팩터링 동등성 담보.
**하위호환**: 없음(클라 순수 계산). **롤백**: 두 함수 분리 복원.

---

### NF1 팀원 행에 '오늘 근무시간'
> **단일 행 배치는 불가**: 텍스트 칼럼 가용폭 ≈202pt인데 `현재 01:02 · 오늘 3시간 12분 · 주 21시간 30분` ≈208pt로 `lineLimit(1)`에 잘린다(primaryDetail엔 `minimumScaleFactor`도 없다). **이미 존재하는 보조줄 슬롯**에 얹는다.

**변경 지점**: `CheckMenuView.swift` `TeamMemberLiveRow` 위(신규 순수 타입) · `:915` 부근(body) / `CheckComponents.swift:205` 부근(플래그) · `:243`(색)

```swift
/// 팀원 행 보조줄 판정(순수 로직, 결정적 검증 지점). PokePanel.noticeLine 과 같은 (text, isWarning) 관용구 —
/// 문구와 색을 한 곳에서 함께 정해, 두 판정이 갈라져 "오늘 …"이 경고색으로 뜨는 일을 없앤다.
/// stale(연결 끊김)이 가장 급하므로 우선하고, 그 외에는 오늘 누적을 보여 준다.
/// 오늘 0초면 nil — 비근무 팀원 행마다 "오늘 0시간 00분"이 붙어 소음이 되지 않게.
enum TeamMemberSecondaryLine {
    static func make(_ member: TeamMemberStatus, presence: MemberPresence, now: Date)
        -> (text: String, isWarning: Bool)? {
        if case .staleWorking = presence, let seen = member.lastSeenAt {
            return ("마지막 확인 \(max(1, Int(now.timeIntervalSince(seen) / 60)))분 전", true)
        }
        let today = member.liveTodayDurationSeconds(now: now)   // N2-clamp 가 선행 조건
        guard today > 0 else { return nil }
        return ("오늘 \(MenuBarStatusFormatter.hoursMinutes(today))", false)
    }
}
```
`TeamMemberRow`에 `var secondaryIsWarning: Bool = false`(기본값이 있어 기존 호출부 전부 그대로 컴파일) + `:243`을 `.foregroundStyle(secondaryIsWarning ? CheckTheme.pending : CheckTheme.secondaryText)`. `primaryDetail`(:947)은 **손대지 않는다**.

**행 높이 초과를 육안이 아니라 테스트로 막는다.** 내부 VStack(이름 16 + primary 13 + secondary 13 + 간격 4) ≈46 + 목표바 행 ≈13 = **≈62pt** vs `memberRowHeight = 58`. 지금은 stale 행에서만 일어나는 일인데 NF1 이후엔 **근무 중 팀원 전원 + today>0인 퇴근 팀원 전원**이 3줄이 된다.
```swift
@MainActor @Test
func teamMemberRowWithSecondaryLineFitsRowBox() throws {
    // 절대 픽셀값을 단언하지 않는다 — 자연 높이와 상자 높이를 **서로** 비교한다.
    let row = TeamMemberRow(name: "영식", presence: .activeWorking,
        primaryDetail: "현재 01:02:03 · 주 21시간 30분",
        secondaryDetail: "오늘 3시간 12분", secondaryIsWarning: false, goalFraction: 0.35)
    let natural = try #require(renderedPixelHeight(row))
    let boxed   = try #require(renderedPixelHeight(row.frame(height: CheckTheme.memberRowHeight)))
    #expect(natural <= boxed)
}
```
실패하면 머지하지 말고 우선순위 순으로: **(a)** 보조줄이 있을 때 `goalBar` 우측 `%` 캡션(CheckComponents.swift:273-277) 생략 → 바 행이 13→3pt로 줄어 총 ≈52pt(정보 손실은 바가 이미 표현) → **(b)** VStack spacing 2→1, 3→2 → **(c)** `memberRowHeight` 62로(**반드시** `windowHeightAdaptsToContentWithinCap` 재실행 — 6행 기준 +24pt가 700pt 예산에 들어간다).

**계약**: 팀원 행 보조줄 = stale이면 마지막 신호 경고(주황), 아니면 오늘 누적(회색, 0이면 생략). 행 높이 58pt·목표 바 위치 불변.
**테스트**: 위 높이 테스트 + 순수 판정 `teamMemberSecondaryLinePrefersStaleWarningOverToday`(3케이스) + `manyMembers`/`steadyMembers` 헬퍼(CheckMenuRenderTests.swift:941, :1074)에 `todayDurationSeconds`를 채워 **3줄 행이 실제로 그려지는 상태로 700pt 상한 재통과**(이게 이 항목의 핵심 회귀 방어).
**하위호환**: 없음 — 이미 받아 오던 필드를 그리기만 한다.
**롤백**: `secondaryDetail`을 stale 전용으로 되돌림.

---

### D6-2 ~ D6-6 · F1 · N1-retro · O7-leaf (웨이브 3 나머지)

**D6-2 토큰 공개 토글 스냅백** — `WorkTimerStorePoke.swift:148`(세대 재확인 직후)에 `guard !tokenUsagePublicLoaded else { return }`, `:174`(롤백 직후)에 `tokenUsagePublicLoaded = false`(실패한 낙관 갱신은 '내 선택'도 '서버값'도 아니므로 다음 tick이 다시 맞추게).
테스트 `tokenUsagePrivacyLoadDoesNotOverwriteToggleInFlight` — **발사와 토글 사이에 20ms 슬립이 필수다**. 테스트 본문이 `@MainActor`라 `Task {}`는 큐잉만 되고, 슬립이 없으면 토글이 먼저 돌아 로더가 **진입 가드(:142)에서 반환**해 수정 유무와 무관하게 통과하는 위양성이 된다. 스텁 추가: `/rest/v1/profiles` GET → `[{"token_usage_public": true}]`(현재 어떤 분기에도 안 걸려 빈 `Data()`가 돌아가 로더가 조용히 실패 중). 기존 `setTokenUsagePublicRevertsOnFailure`에 `#expect(!store.tokenUsagePublicLoaded)` 한 줄 보강.

**D6-3 유령 '팀원' 행** — `CheckMenuView.swift:833-835`의 가짜 `TeamMemberRow`(아바타·이름·'근무종료' 칩까지 갖췄고 name이 하필 `fetchTeamStatuses`의 폴백 이름과 같아 실제 팀원과 구분도 안 된다)를 자리 문구로 교체.
```swift
/// 팀 목록 빈 자리 문구(순수 로직). join_team/create_team RPC 가 합류 시 work_statuses 행을 만들므로
/// (20260711160000:104,150) '로드 완료 + 0명'은 사실상 나 혼자인 새 팀뿐이다.
/// 동기화 문구 자체는 **본문에 노출하지 않는다** — 판정에만 쓰고 표시는 푸터 SyncStatusView 가 맡는다.
enum TeamListEmptyMessage {
    static let loading = "불러오는 중…"
    static let noMembers = "아직 팀원이 없어요 — 참여코드를 공유해 보세요"
    static let loadFailed = "팀 목록을 불러오지 못했어요"
    static func text(hasLoaded: Bool, syncFailed: Bool) -> String {
        if hasLoaded { return noMembers }
        return syncFailed ? loadFailed : loading
    }
}
```
`Text(...).frame(maxWidth: .infinity, minHeight: CheckTheme.memberRowHeight, alignment: .leading)` — rowCount=1·`listContentHeight(1)=58` 불변이라 창 높이 예산 무영향. 스토어에 `var teamStatusLoaded = false`(clearPersistedSession에서 리셋), 세우는 위치는 **`WorkTimerStoreSync.swift:28`**(목록 반영 직후) — `:39`에 두면 자동 마감 분기(:32-35)의 조기 return 때문에 '반영했는데 로드 안 됨'이 생겨 계약이 거짓이 된다.
테스트: 순수 판정 3케이스 + `renderPNG` 성공.

**D6-4 리그 패널 로딩/실패** — 개인 기록(`InsightsEmptyMessage`, CheckMenuView.swift:1739-1747)과 **같은 2상태 규약**을 쓴다. 3상태(loading 플래그 추가)는 `(!loaded && !loading && !failed)` 구멍을 남기고 그 조합이 실제로 도달 가능하다(취소 경로 — `updateTeamGoal`이 `await refreshLeaderboardIfVisible()`을 뷰 Task 안에서 부른다). 그 구멍에서 본문에 "주간 목표 변경됨"이 뜬다 — 고치려던 그 증상이다.
```swift
/// 리그 첫 성공 로드 여부 / 마지막 조회가 (취소가 아닌) 실패로 끝났는지.
/// 개인 기록(insightsLoaded/insightsFailed)과 **같은 2상태 규약**이다 — '로드 전 && 실패 아님'을
/// 곧 진행중으로 단정해, 본문 자리에 syncMessage 가 새는 조합 자체를 없앤다.
var leaderboardLoaded = false
var leaderboardFailed = false
```
`performLoadLeaderboard`(Sync:127-143): 진입 시 `if leaderboardFailed { leaderboardFailed = false }`, 성공 시 `leaderboardLoaded = true`, catch에서 `if case .cancelled … { return }` 뒤 `leaderboardFailed = true`. **`syncMessage = "리그 불러오기 실패"` 삭제** — 패널 사유가 푸터 전역 문구를 덮으면 패널을 닫은 뒤에도 30초간 남는다. `LeaderboardEmptyMessage.text(hasLoaded:hasFailed:)`로 시그니처 축소(`fallbackStatus`/`unfilteredCount` **제거**), 패널에 `hasLoaded`/`hasFailed`/`onRetry` 추가 + 토큰 보드와 동일한 `PanelRetryButton`. `toggleLeaderboard`는 손대지 않는다(loading 플래그가 없으니 선세팅 불필요 — 첫 프레임부터 진행중).
**깨지는 기존 테스트**: `leaderboardEmptyFilterUsesNeutralMessageDistinctFromFallback`(CheckMenuRenderTests.swift:**564, 565, 566** — 2줄이 아니라 3줄). 4케이스로 교체 + **렌더 절반에 `store.leaderboardLoaded = true`를 세워야** 중립 문구 경로를 실제로 밟는다. 추가: `leaderboardFailureDoesNotOverwriteSyncMessage`, `leaderboardCancelledLoadNeverShowsSyncMessage`(3상태안이었다면 여기서 fallbackStatus가 나온다).

**D6-5 헤더 '이번 주' 폴백** — `WorkTimerStore.swift:296-304`. 현재 `else { return todayDuration }`이라 첫 왕복 동안 오늘치가 '이번 주'로 표시되고 %/게이지까지 함께 틀린다.
```swift
/// 내 이번 주 누적(초). 출처는 팀 목록의 내 행뿐이라 아직 못 받았으면 nil 이다.
/// 예전엔 nil 대신 todayDuration 을 돌려줬는데, 헤더가 그 값을 "이번 주"라고 적어 오독시켰다.
var myWeeklySecondsIfKnown: Int? { … }
/// 게이지/퍼센트용. 모를 때는 0(빈 게이지)으로 그린다 — 오늘치로 채우지 않는다.
var myLiveWeeklySeconds: Int { myWeeklySecondsIfKnown ?? 0 }
```
뷰(`CheckMenuView.swift:532/551/556`): 미확정이면 `이번 주 -- / 60시간` + `--%`.
테스트: `myWeeklyGaugeUsesMyRowNotTeamTotal`(:520-557)의 마지막 2줄이 **의미상 무효**가 되므로(값이 우연히 0==0이라 통과는 하지만 계약이 반대) 교체 — `teamMembers=[]` + `startedAt = now-3600`에서 `#expect(store.myWeeklySecondsIfKnown == nil)`, `#expect(store.myLiveWeeklySeconds == 0)`(오늘치가 주간으로 새지 않음을 실증).

**D6-6 무소속 안내가 빨간 ⚠로** — 리터럴이 `WorkTimerStoreSync.swift:13`과 `:562` **두 곳에 이미 독립 복제**돼 있으니 뷰에 세 번째 사본을 심지 말고 상수로 올린다.
```swift
// WorkTimerStore.swift
/// 무소속(팀 미확정) 안내 문구. 스토어 두 곳과 뷰의 배너 억제 판정이 같은 문자열을 봐야 한다.
/// nonisolated 인 이유: AuthMessageKind.isSuppressedBanner(nonisolated static func)가 읽는다 —
/// pokeDisplayFreshnessSeconds(WorkTimerStorePoke.swift:15)·UpdateCheckStore 상수들과 같은 규약.
/// (Swift 6 언어 모드에서 @MainActor 타입의 평범한 static let 을 nonisolated 컨텍스트가 읽으면 에러다.)
nonisolated static let teamlessSyncMessage = "소속 팀이 없어요 — 팀 코드로 참여해 주세요"
```
```swift
// CheckMenuView.swift, AuthMessageKind 뒤
/// 배너로 띄우지 않는 문구. 정상 상태라 오류 스타일(빨간 ⚠)로 보이면 안 되는 것들이다.
/// 무소속 안내는 화면 자체가 이미 '합류할 팀을 찾아요' + 코드 입력 폼이라 배너가 중복이다.
/// 푸터 SyncStatusView 에는 그대로 남아 상태를 잃지 않는다.
/// (.info 로 격하하는 대안은 아이콘이 envelope.badge.fill(메일 확인 전용)이라 의미가 안 맞아 버렸다.)
extension AuthMessageKind {
    static func isSuppressedBanner(_ message: String) -> Bool {
        message == "동기화됨" || message == "로그인 필요" || message == WorkTimerStore.teamlessSyncMessage
    }
}
```
`TeamlessPanel`(:2318-2320)·`LoginPanel`(:2125)이 `.opacity(...)` + `.accessibilityHidden(...)`로 사용(높이는 불변). 리터럴 치환 2곳(Sync `:13` `:562`). D1(웨이브 1)이 `:13`에 넣은 리터럴도 여기서 상수로 바뀐다.
테스트: 순수 판정 2건 + 높이 불변 상대 비교.

**F1 푸터 새로고침** — `WorkTimerStore.swift:601` 뒤:
```swift
/// 진행 중인 수동 새로고침이 있는지(연타 가드). 관찰 대상이 아니다 — 버튼을 비활성화하지 않기 때문이다.
/// 비활성화하지 않는 이유: refreshVisible 은 다섯 로더를 직렬 await 하고 각 요청 타임아웃이 15초라
/// 무료 플랜 콜드스타트에서 1분 넘게 버튼이 죽을 수 있다. 30초 폴링 루프도 같은 시퀀스를 돌지만
/// 아무 것도 비활성화하지 않는다(WorkTimerStore.swift:761-767).
@ObservationIgnored var isManualRefreshInFlight = false

/// 푸터 [새로고침] 전용 진입점. 미반영 큐 → 팀 현황 → **지금 보고 있는 하위 패널** 순으로 갱신한다.
func refreshVisible() {
    guard !isManualRefreshInFlight else { return }
    isManualRefreshInFlight = true
    Task { @MainActor in
        defer { isManualRefreshInFlight = false }
        // 사용자가 이 버튼을 누르는 가장 흔한 이유가 '대기'/'동기화 실패' 표시다 → 큐부터 민다.
        // retryPendingSync 는 성공 시 끝에서 스스로 refreshTeamStatus 를 부르므로(Sync:556)
        // 큐가 비어 있을 때만 여기서 따로 부른다(팀 조회 이중 발사 방지).
        if pendingItems.isEmpty { await refreshTeamStatus() } else { await retryPendingSync() }
        await refreshLeaderboardIfVisible()
        await refreshTokenBoardIfVisible()
        await refreshPokeDirectoryIfVisible()
        if isInsightsPanelVisible { await performLoadInsights() }
    }
}
```
뷰(`:2034`)는 `enabled:` **없이** 액션만 교체. 테스트 2건 모두 **완료 대기를 명시**한다(fire-and-forget이라 손잡이가 없다 — `for _ in 0..<200 where store.isManualRefreshInFlight { sleep 5ms }`). `refreshVisibleAlsoReloadsOpenPanel`(리그 RPC 경로 포함) / `refreshVisibleIgnoresReentrantTaps`(3연타 → 리그 요청 1건).

**N1-retro 회고 카드 주 범위** — `CheckWorkInsights.swift:125-161 WeeklyRetro`에:
```swift
/// 회고 대상 주의 표시 라벨("7/21~7/27"). weekStart 는 KST 월요일 00:00 이라 +6일이 일요일이다.
/// 카드가 '지난주'라는 상대 표현만 쓰면 어느 주인지 확인할 길이 없다(주 경계 재계산 실패 시 특히).
var rangeLabel: String { … }   // TeamWeeklyGoal.kstCalendar 로 month/day 추출
```
뷰(`:1845` `Text("지난주 회고")` 다음)에 `.font(.caption2)` 회색 `.fixedSize()`. 폭 여유 확인됨(제목 55 + 라벨 45 + 칩 70 ≈ 190 < 270). 연도 없음 — 회고는 항상 직전 주라 해 넘김 혼동이 없다.
테스트: `weeklyRetroRangeLabelSpansMondayToSunday` + 연말 걸침(12/29~1/4).

**O7-leaf 비근무 행의 `displayNow`** — `CheckMenuView.swift:908`. 삼항으로 미선택 분기를 만들면 관찰 등록 자체가 사라진다. NF1이 같은 구역을 건드리므로 함께 적용. 코드 위생 수준(회귀 테스트 불필요).

---

## 웨이브 4 — v0.2.18

### O2 `team_status_snapshot` RPC
> 신규 `supabase/migrations/20260801060000_team_status_snapshot.sql` + 앱. **앱과 함께 나가는 유일한 서버 항목.**

**변경 지점**: `SupabaseWorkService.swift:88 fetchTeamStatuses`(분기 진입점으로 재작성, 기존 본문은 `fetchTeamStatusesFanout`으로 **internal 존치** — 폴백이자 e2e 기준선) · `:130/:146/:165/:176/:190` 존치 / `SupabaseWorkModels.swift:283`·`:448`(신규 타입 2개) / `URLProtocolStub.swift:136`·`:191` / 호출처 `WorkTimerStoreSync.swift:24`는 **무변경**(시그니처 동일)

**SQL 핵심** — 리그의 clipped CTE를 1인당으로 옮기되 세 가지가 다르다: (a) `group by s.user_id`, (b) **열린 세션을 합산에 넣지 않는다**(클라가 `liveWeeklyDurationSeconds`로 stale 동결까지 포함해 라이브 계산하므로 서버가 더하면 이중 계상 — 대신 `active_started_epoch`를 따로 준다), (c) 주 창 + 오늘 창 둘을 같은 행에서.
```sql
create or replace function public.team_status_snapshot(p_team uuid)
returns table(
  user_id uuid, display_name text, avatar_url text, status text, active_session_id uuid,
  updated_epoch bigint, last_seen_epoch bigint, active_started_epoch bigint,
  weekly_seconds bigint, today_seconds bigint
)
language plpgsql stable security definer set search_path = public
as $$
begin
  -- security definer 라 RLS 를 우회한다. 이 게이트가 없으면 아무 팀 uuid 나 넣어 남의 팀 현황을 통째로 읽는다.
  -- 예외가 아니라 0행으로 돌려준다 — RLS 로 0행을 받던 옛 3-fanout 과 같은 결과라 앱 분기가 변하지 않는다.
  if not public.is_team_member(p_team) then return; end if;

  return query
  with bounds as (
    select (date_trunc('week', (now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul') as week_start,
           ((now() at time zone 'Asia/Seoul')::date at time zone 'Asia/Seoul') as day_start,
           now() as now_ts
  ),
  done as (
    select s.user_id as uid,
      -- 사람별 trunc() 후 합산: 클라 clippedContribution(:196)이 세션마다 Int() 로 절사한 뒤 더하므로
      -- SQL 도 행마다 절사해야 값이 같다(리그의 sum(...)::bigint 는 반올림이라 이 자리엔 부적합).
      sum(trunc(greatest(0, extract(epoch from
        (least(s.ended_at, b.now_ts) - greatest(s.started_at, b.week_start))))))::bigint as weekly_seconds,
      sum(trunc(greatest(0, extract(epoch from
        (least(s.ended_at, b.now_ts) - greatest(s.started_at, b.day_start))))))::bigint as today_seconds
    from public.work_sessions s cross join bounds b
    where s.team_id = p_team and s.ended_at is not null
      -- 창 경계는 bounds 조인 컬럼이 아니라 stable 표현식으로 직접 쓴다(30초 폴링 경로라 계획이 확정적이어야 한다).
      and s.ended_at >= (date_trunc('week', (now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul')
    group by s.user_id
  ),
  live as (
    select s.user_id as uid, min(s.started_at) as started_at
    from public.work_sessions s where s.team_id = p_team and s.ended_at is null group by s.user_id
  )
  select st.user_id,
         coalesce(p.display_name, '팀원'),     -- 옛 경로(SupabaseWorkService.swift:117)와 값이 같도록 다듬지 않는다
         p.avatar_url, st.status, st.active_session_id,
         floor(extract(epoch from st.updated_at))::bigint,
         floor(extract(epoch from st.last_seen_at))::bigint,
         floor(extract(epoch from l.started_at))::bigint,
         coalesce(d.weekly_seconds, 0), coalesce(d.today_seconds, 0)
  from public.work_statuses st
  join public.profiles p on p.id = st.user_id
  left join done d on d.uid = st.user_id
  left join live l on l.uid = st.user_id
  where st.team_id = p_team
  order by st.updated_at desc, st.user_id;   -- user_id 타이브레이커: 동률 비결정이면 != 가드가 뚫려 헛무효화
end;
$$;
revoke all on function public.team_status_snapshot(uuid) from public;
grant execute on function public.team_status_snapshot(uuid) to authenticated;
```
**반환 컬럼을 빼면 깨지는 것**: `active_started_epoch` 없으면 근무중 팀원의 '현재 N시간'이 전부 0으로 굳고 주간 라이브가 멈춘다. `active_session_id` 없으면 세션ID 복구와 자동마감 fallback이 UUID 난수로 떨어져 **닫힌 세션이 중복 생성**된다. `last_seen_epoch` 없으면 stale 판정이 사라져 죽은 세션이 무한 카운트한다. `email`은 미반환(소비 분기가 `displayName` 비옵셔널이라 도달 불가).

**타임스탬프는 epoch bigint** — `take_pokes`의 `created_epoch` 선례(20260724020000:74)를 따라 ISO 소수초 파싱 함정을 이 경로에는 애초에 만들지 않는다.

**클라 폴백 래치** — 실패 시 팀 패널(메인 화면)이 전면 무동작이고 사용자가 자력으로 못 고친다. 이 저장소는 다중 계정 때문에 `db push`가 403으로 조용히 실패한 전례가 실재한다.
```swift
private var snapshotRPCUnavailable = false

func fetchTeamStatuses(accessToken: String, teamID: String, now: Date = Date()) async throws -> [TeamMemberStatus] {
    if !snapshotRPCUnavailable {
        do {
            return try await fetchTeamStatusSnapshot(accessToken: accessToken, teamID: teamID)
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            snapshotRPCUnavailable = true          // PGRST202: 함수 자체가 없다(마이그레이션 미적용)
        } catch SupabaseWorkServiceError.authMessage(let message) where Self.snapshotRPCUnusable(message) {
            // 함수는 있는데 grant 가 빠졌거나(revoke all → grant 규약상 가장 잦은 운영 실수) 시그니처가 다르다.
            // 이 가지가 없으면 팀 패널이 영어 원문(permission denied for function …)과 함께 죽고
            // 사용자가 자력으로 고칠 방법이 없다 — 폴백을 넣은 이유가 통째로 무효가 된다.
            snapshotRPCUnavailable = true
        }
    }
    return try await fetchTeamStatusesFanout(accessToken: accessToken, teamID: teamID, now: now)
}

/// 서버가 '이 RPC 를 호출할 수 없다'고 말한 것인지. 401/5xx/네트워크/취소는 절대 여기 걸리면 안 된다.
private static func snapshotRPCUnusable(_ message: String) -> Bool {
    let m = message.lowercased()
    guard m.contains("team_status_snapshot") else { return false }
    return m.contains("permission denied") || m.contains("does not exist") || m.contains("not find")
}
```
`fetchTeamStatuses`의 doc에 못 박는다:
```swift
/// `now` 는 **폴백(3-fanout) 경로 전용**이다. 스냅샷 RPC 경로는 서버 now() 로 창을 잡으므로 주입이 무시된다.
/// 따라서 주/일 창 정확성의 실증은 s09i_teamStatusSnapshotMatchesFanout(CHECK_E2E)에만 있다.
```

**계약**: `team_status_snapshot(p_team)` = "호출자가 그 팀 멤버일 때에 한해, 그 팀 work_statuses 행마다 표시에 필요한 값 전부 + 이번 주/오늘 **완료 세션만**의 클리핑 누적 + 열린 세션 시작시각을 한 행으로". 열린 세션의 진행 몫은 서버가 절대 더하지 않는다(클라 라이브 계산의 단일 책임). `snapshotRPCUnavailable`: 참이면 이 프로세스는 다시는 스냅샷 RPC를 호출하지 않는다. `fetchTeamStatuses`의 시그니처·반환 타입·호출처 불변.
**테스트**: 단위 6건 — `teamStatusSnapshotMapsRowsWithSingleRequest`(10필드 매핑 + work_statuses/work_sessions **0건**) / `teamStatusSnapshotSendsTeamIDAsPTeam`(`"p_team"` snake_case 회귀) / `teamStatusSnapshotFallsBackToFanoutWhenFunctionMissing` / `teamStatusSnapshotLatchesFallbackAfterFirstMiss`(RPC 1건, work_statuses 2건) / **`teamStatusSnapshotIgnoresInjectedNow`**(6개월 전 now를 넣어도 픽스처 그대로 — 나중에 누가 `now:` 주입으로 클리핑을 검증하려다 조용히 폴백만 테스트하는 사고 방지) / **`teamStatusSnapshotFixtureEncodesKSTWindows`**(주/오늘 두 값 자리 뒤바뀜이라는 가장 값싼 회귀).
스텁: `device-table-missing`(:178,:213) 선례대로 — host에 "snapshot"이 없으면 `/rest/v1/rpc/team_status_snapshot`에 404 + PGRST202 본문. 이러면 **기존 팀 픽스처 호스트가 전부 옛 3-fanout 폴백을 타므로 기존 12건이 무수정 통과하고 폴백 경로도 매 테스트에서 덤으로 실증된다.**
e2e 2건 — **`s09i_teamStatusSnapshotMatchesFanout`**(완료 세션 2건 + 열린 세션 1건을 admin으로 심고 같은 순간에 두 경로 호출 → 사람별 주/오늘 차이 ≤2초, `activeSessionID`/`status`/`name`/`currentSessionStartedAt`(±1초) 일치) / `s09j_teamStatusSnapshotDeniesNonMember`(0행).
**하위호환**: **서버는 순수 추가** — 표·컬럼·정책·기존 함수를 하나도 안 건드린다. v0.2.10/v0.2.14는 GET 3발을 그대로 쓴다. 앱 쪽은 폴백 래치가 담당(마이그레이션 미적용 서버에 붙어도 첫 폴링에서 한 번 맞고 옛 경로로 정상 동작, 사용자 증상 0). 새 경로 타임스탬프는 초 단위 절사라 최대 1초 차이(표시 단위가 분이라 육안 무영향).
**롤백**: `drop function if exists public.team_status_snapshot(uuid);` 한 줄 — **앱은 그 순간부터 폴백 래치로 자동 복귀한다**(재배포 불필요). 이 성질이 폴백을 넣는 두 번째 이유다.
**절감**: 20인 금요일 기준 ~300행 ≈42KB + 2발 → 20행 ≈3.6KB **1발**. 요청 3→1, payload 약 91%↓.

---

### N1-team 팀 탈퇴/추방
> 신규 `supabase/migrations/20260801070000_team_membership_exit.sql` + 앱. `memberships`에 DELETE 정책이 **아예 없어**(전 마이그레이션 grep) RLS 아래에서는 누구도 소속을 끊을 수 없다 — 퇴사자가 자기 계정으로 팀 근무현황을 계속 본다.

**SQL 4덩어리 (전부 한 파일)**
1. `detach_team_member(p_team, p_user)` — 내부 전용(grant 없음). **(열린 세션 마감 → 상태행 삭제 → 멤버십 삭제)를 한 트랜잭션에서**. 앱이 셋을 따로 지우면 중간에 끊겼을 때 좀비 상태가 남는다. `work_sessions`(근무 기록)는 **보존**(지우면 그 주 팀 총합과 본인 개인기록이 소급 변조된다), `work_statuses`는 **삭제**(남기면 나간 사람이 팀 패널에 계속 보인다).
2. `leave_team(p_team)` → jsonb `{"status":"ok"|"not_member"|"last_owner"|"invalid"}`. `poke_user`(20260724020000:27) 규약. **남은 사람이 있는데 마지막 owner가 나가면 그 팀은 영영 아무도 추방할 수 없다** → `last_owner`로 막는다(혼자 남은 owner는 나갈 수 있다).
3. `remove_team_member(p_team, p_user)` → `{"status":"ok"|"forbidden"|"forbidden_owner"|"not_member"|"use_leave"|"invalid"}`. owner 전용. owner끼리는 서로 못 내보낸다(계정 하나 뚫리면 팀을 통째로 장악하는 경로 차단).
4. **owner 백필 (이게 없으면 실팀에서 무용지물)** — 옛 트리거 시절(`20260711120000:44`) 만들어진 팀은 전원 `role='member'`라 owner가 없고, 그 팀에서는 추방이 영원히 불가능하다. 팀마다 가장 먼저 합류한 사람을 승격(이미 owner가 있으면 무변경, 멱등).
5. **자기 세션 읽기 정책 (리뷰가 잡은 누락)**
```sql
-- 탈퇴/추방 뒤에도 본인은 자기 근무 기록을 읽을 수 있어야 한다. 이 정책이 없으면 memberships 행이
-- 사라지는 순간 fetchMySessions(SupabaseWorkService.swift:483)가 0행이 되어 개인 기록이 영구히 빈다
-- (그 함수 주석 :481 이 '같은 팀 읽기 허용'을 전제로 쓰여 있다). 본인이 못 읽는 보존은 보존이 아니다.
-- 기존 팀 읽기 정책은 그대로 둔다 — RLS 정책은 OR 로 합쳐지므로 순수 확대다.
drop policy if exists "users can read their own sessions" on public.work_sessions;
create policy "users can read their own sessions"
  on public.work_sessions for select using (user_id = auth.uid());
```

**클라 — 탈퇴와 추방을 반드시 분리한다.** 공통 핸들러를 쓰면 **추방한 owner 자신이 초기화된다**(진행 중 근무가 끊기고 미전송 큐가 버려진다 — `clearPersistedSession`조차 일부러 보존하는 장부다).
```swift
/// 내가 나갔다 — 이 기기의 팀 상태가 통째로 무효다.
func handleLeftTeam() {
    // 세대를 올려 왕복 중이던 폴링 응답이 옛 팀 값을 되살리지 못하게 한다.
    workStateWriteGeneration &+= 1
    startedAt = nil; currentSessionID = nil; longSessionAnchor = nil
    // 소속이 없어 INSERT/UPDATE 정책(R9-c 의 팀 게이트)에 영구히 막힐 큐는 버린다.
    pendingItems = []
    snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
    teamMembers = []; currentTeamID = nil; teamName = "팀"; teamRole = nil; myTeamInviteCode = nil
    refreshMenuBarTitle()
}

/// 남을 내보냈다 — **내 팀 상태는 그대로 유효하다.**
func handleRemovedMember() async { await refreshTeamStatus() }
```
**추방당한 쪽 자가 감지 (필수)** — 30초 루프는 `confirmMembership`을 부르지 않는다(호출처가 `activateStoredSession`/`signIn`/`signUp`뿐). 없으면 `currentTeamID`가 옛 팀을 계속 가리키고 → 0행 → `applyRemoteOwnStatus`가 `guard let ownMember`에서 즉시 반환 → **자동 마감도 스냅백도 없이 로컬 타이머가 영원히 돈다**(하트비트 403은 조용히 삼켜지고 `syncMessage`는 "동기화됨"). `refreshTeamStatus`의 세대 재확인 뒤(표준 로딩 6단계 준수):
```swift
guard generation == sessionGeneration else { return }
if teamMembers != members { teamMembers = members }
// 소속 팀을 조회했는데 0행이면 내 work_statuses 행조차 없다는 뜻 — 팀원이면 자기 행은 언제나 보이므로
// (20260701000000:154-156) 추방/탈퇴가 확정적이다. join_team/create_team 이 work_statuses 행을 반드시
// 만들므로(20260711170000:41-43, :85-87) 나 혼자인 팀에서도 헛발동하지 않는다.
if members.isEmpty {
    await confirmMembership()
    guard generation == sessionGeneration else { return }
    if currentTeamID == nil { handleLeftTeam() }
    return
}
```

**계약**: `leave_team` = "호출자가 그 팀 멤버이고 (남은 사람이 있는 팀의 마지막 owner가 아니면), 열린 세션을 지금 마감하고 상태행·멤버십을 삭제한다. 닫힌 근무 기록은 남기고 본인은 계속 읽을 수 있다." 새 불변식: **모든 팀에 owner가 최소 1명 존재한다**.
**테스트**: 단위 3건 — `teamExitOutcomeMapsServerStatus`(6분기) / **`removedMemberDropsQueueAndStopsLocalWork`**(빈 팀 응답 호스트로 `refreshTeamStatus()` → `startedAt == nil`, `pendingItems.isEmpty`, `isTeamless`) / **`removingMemberKeepsOwnerWorkState`**(`handleRemovedMember()` 뒤 `startedAt`/`pendingItems`/`currentTeamID` **불변**). e2e 5건 — `s09r_memberLeavesTeam`(닫힌 세션 잔존 확인) / `s09s_removedMemberCannotReadTeamStatus`(O2 게이트 실증 겸함) / `s09t_ownerRemovesMember` / `s09u_lastOwnerCannotLeaveWithMembersLeft` / `s09v_leftMemberStillReadsOwnSessions`(5번 정책 실증). `s10_cleanup`에 새 이메일 추가.
**하위호환**: **순수 추가**. 구버전 클라를 쓰는 사람이 추방당하면 `confirmMembership`의 0행으로 `isTeamless`에 떨어진다(v0.2.10에도 있는 경로). 다만 그 순간 미전송 큐는 구버전에선 안 비워져 재시도가 계속 실패한다 — 서버가 이미 세션을 닫았으므로 데이터 손실은 없고 그 앱의 메뉴바만 '대기'로 남는다(재로그인하면 정리된다). 기존 데이터 변경 1건: owner 백필.
**롤백**: 세 함수 drop. **owner 백필은 되돌리지 않는다**(되돌리면 다시 추방 불가 상태가 된다).
**의존**: R9-c 선행 **필수**(UPDATE 팀 게이트가 추방의 강제력이다). 자가 감지는 R9-c와 반드시 함께 — 게이트가 붙는데 자가 감지가 없으면 추방당한 기기가 무한 재시도로 고착된다.
**UI**: 팀 카드 헤더는 `TeamHeaderWidthBudget`(CheckMenuView.swift:676-700) 회귀 테스트가 버튼 개수를 고정하고 팀원 행은 `memberRowHeight` 고정이라, **참여코드 인라인 행(`:773`) 자리에 '팀 관리' 드로어**를 붙이는 것이 두 제약을 모두 피한다.

---

### NF2 별명 변경
**변경 지점**: `SupabaseWorkService.swift:671` 뒤(`updateDisplayName`) / `SupabaseWorkModels.swift:571` 부근 / `WorkTimerStore.swift:283` 옆(`@ObservationIgnored var isUpdatingDisplayName = false`) / `WorkTimerStoreAuth.swift:232` 뒤 / `CheckComponents.swift:199-257`(onEditName) / `CheckMenuView.swift:830-846`(편집 행 분기)

**마이그레이션 0** — `profiles` UPDATE 정책이 이미 본인 행 허용(`20260711090000:7-11`, 컬럼 제한 없음), `display_name`은 `text not null`, 트리거는 `after insert on auth.users`라 기존 사용자에겐 안 돈다. 표시명은 팀 목록·`app_user_directory`·`token_usage_board`가 전부 `profiles.display_name`을 읽으므로 한 번 바꾸면 모든 화면에 전파된다.

**핵심: 문구는 반드시 `refreshTeamStatus` 뒤에 세운다.**
```swift
/// **문구는 반드시 refreshTeamStatus 뒤에** — 그 함수가 성공 경로 끝에서 syncMessage 를 "동기화됨"으로
/// 덮으므로(WorkTimerStoreSync.swift:39) 앞에 두면 안내가 즉시 사라진다.
/// updateAvatar(WorkTimerStoreSync.swift:462-464)가 같은 이유로 같은 순서를 쓴다.
/// (updateTeamGoal 골격을 그대로 베끼면 안 된다 — 그건 뒤에 refreshLeaderboardIfVisible 을 불러 syncMessage 를 안 건드린다.)
@discardableResult
func updateDisplayName(_ raw: String) async -> Bool {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= Self.displayNameMaxLength, !isUpdatingDisplayName else { return false }
    isUpdatingDisplayName = true
    defer { isUpdatingDisplayName = false }
    let generation = sessionGeneration
    do {
        try await withSessionRetry { activeSession in
            try await service.updateDisplayName(accessToken: activeSession.accessToken,
                                                userID: activeSession.userID, displayName: name)
        }
        guard generation == sessionGeneration else { return false }
        if displayName != name { displayName = name }
        defaults.set(name, forKey: Self.displayNameKey)
        await refreshTeamStatus()
        guard generation == sessionGeneration else { return false }
        syncMessage = "별명 변경됨"      // ← 반드시 refresh 뒤
        return true
    } catch {
        guard generation == sessionGeneration else { return false }
        if case .cancelled = classifyAuthError(error) { return false }
        syncMessage = authMessage(for: error, fallback: "별명 변경 실패")
        return false
    }
}
```
UI는 팀 목록의 **내 행**을 같은 58pt 편집 행으로 **대체**한다(rowCount·행 높이·스크롤 상한 전부 불변 → 창 높이 예산 무영향). 아바타가 이미 내 행에서만 `EditableAvatarView`로 바뀌므로 같은 자리·같은 관용구다. 헤더 목표 편집기처럼 **성공했을 때만 닫는다**.
**테스트**: `updateDisplayNamePatchesProfileRow`(`"display_name"` 포함 + `"displayName"` 미포함) / `updateDisplayNameRejectsBlankAndTooLong`(요청 0건) / `updateDisplayNameKeepsEditorOpenOnFailure` / **순서 회귀 `#expect(store.syncMessage == "별명 변경됨")`** / 렌더 `nameEditorRowKeepsListHeight`(편집·비편집 두 렌더 높이 동일, 상대 비교).
**하위호환**: 서버 스키마·정책·RPC 무변경. v0.2.10은 임베드된 `display_name`을 그대로 읽어 다음 폴링에 바뀐 이름이 보인다(오히려 즉시 혜택).
**롤백**: 편집 진입점(`onEditName`) 제거로 기능만 숨김(서버는 원래 허용 상태라 되돌릴 것이 없다).
**문서**: `docs/release.md` 운영 주의 한 줄 — "`supabase db reset`은 `20260701000000:114-122` 백필을 재실행해 사용자가 바꾼 별명을 가입 메타데이터로 되돌린다. 프로덕션에선 `db push`(미적용분만)만 쓴다."

---

### NF3 콕찌르기 수신 거부
> 신규 `supabase/migrations/20260801080000_poke_opt_out.sql` + 앱. `token_usage_public`과 같은 패턴.

**SQL 3덩어리**
```sql
alter table public.profiles add column if not exists pokes_enabled boolean not null default true;
```
`app_user_directory` 재정의 — **웨이브 0의 R9-b 정의를 기반으로** where 절에 `and coalesce(p.pokes_enabled, true)` 한 항 추가 + `revoke all`/`grant execute` 재명시.
`poke_user` 재정의 — **본문 전체를 `20260724030000`에서 그대로 복사**하고 첫 `if`에만 접어 넣는다(plpgsql `create or replace`는 본문 전체를 다시 써야 한다). **`revoke all` / `grant execute` 두 줄을 반드시 재명시**(원본 `:60-61`).
```sql
  -- 비로그인/자기 자신/존재하지 않는 대상/**수신 거부한 대상**은 무효.
  -- 존재하지 않는 대상과 수신 거부한 대상이 같은 응답이 되어 발신자가 둘을 구분할 수 없다.
  if uid is null or p_to = uid or not exists (
       select 1 from public.profiles where id = p_to and coalesce(pokes_enabled, true)
     ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- ↓ 아래는 20260724030000:26-56 을 그대로 복사(보낸이 근무중 / 대상 근무중 / 쿨타임 / insert).
```
**발신자에게 거부 사실을 알리지 않는다(`invalid` 확정, 새 status 신설 반대)**: 목록에서 통째로 숨기므로 정상 경로엔 버튼조차 없고, 낡은 목록(≤30초)으로 찌른 예외에서만 응답이 온다. 여기서 `target_opted_out`을 주면 **20명 사내에서 누가 거부를 켰는지가 그대로 드러난다** — `token_usage_public`이 익명화가 아니라 통째 제외를 택한 것과 같은 이유다. 구버전 클라는 미지 status를 `invalid`로 폴백하므로(`SupabaseWorkModels.swift:666`, `WorkTimerStoreTests:3480`이 고정) 어느 쪽으로도 안전하다. `.invalid` 분기(`WorkTimerStorePoke.swift:81`)에 `loadPokeDirectory()` 한 줄 추가해 사라진 대상이 즉시 목록에서 빠지게.

**클라 — 로드 플래그를 필드별로 나눈다.** 하나로 합치면 D6-2가 만든 계약 위에 새 경쟁 조건이 생긴다(눈 버튼 in-flight 중 종 버튼 PATCH가 실패해 롤백이 플래그를 내리면, 다음 GET이 아직 in-flight인 공개 토글까지 서버 낡은 값으로 되돌린다).
```swift
var tokenUsagePublic = true
var pokesEnabled = true
/// 필드별 로드/확정 마커. **하나로 합치지 않는다** — 두 토글은 독립이라, 한쪽 PATCH 실패의 롤백이
/// 플래그를 내리면 다음 GET 이 다른 쪽의 in-flight 선택까지 서버 낡은 값으로 되돌린다(D6-2 가 막은 스냅백).
@ObservationIgnored var tokenUsagePublicLoaded = false
@ObservationIgnored var pokesEnabledLoaded = false
```
`loadProfilePrivacyIfNeeded()`는 **한 번의 GET**(select에 컬럼만 추가 — 요청 증가 0)으로 두 값을 받고 **필드별로 독립 판정**한다. `setPokesEnabled`는 `setTokenUsagePublic`과 동형.
UI: PokePanel 헤더에 토큰 보드와 같은 자리·같은 관용구(`bell` / `bell.slash` IconButton) + 거부 중이면 안내줄 회색 한 줄 `지금은 콕 찌르기를 받지 않아요`.

**계약**: `pokes_enabled=false`인 사용자는 다른 사람의 대상 목록에 존재하지 않으며, 서버는 그를 향한 찌르기를 '없는 대상'과 동일하게 거절한다. 발신자에게 거부 사실은 노출되지 않는다.
**테스트**: `fetchProfilePrivacyReadsBothColumns` / `fetchProfilePrivacyDefaultsWhenRowAbsent`(`[]` → `(true,true)`) / **`profilePrivacyLoadFailureLeavesOptimisticDefaults`**(400 스텁 → 두 플래그 false 유지 + 값은 낙관 기본 — 마이그레이션 순서를 어겼을 때의 실제 동작 고정. "컬럼 누락 시 기본 true 폴백"은 도달 불가한 상황이라 테스트하지 않는다: 컬럼이 없으면 PostgREST가 select 전체를 400으로 거절한다) / `setPokesEnabledRevertsOnFailure` / **`setPokesEnabledFailureDoesNotResetTokenPrivacyLoaded`**(통합안이었다면 실패) / 렌더 `pokePanelShowsBellSlashWhenOptedOut` / e2e `s09w_pokeOptOutHidesFromDirectory`.
**하위호환**: (a) profiles GET은 구버전이 `select=token_usage_public`만 요구하므로 새 컬럼이 있어도 그만, (b) 두 RPC의 RETURNS 시그니처 불변, (c) 구버전 사용자도 '거부한 사람이 목록에서 사라지는' 새 동작을 자동으로 따른다(의도된 방향). 기존 데이터는 default true라 전원 현행 유지.
**위험**: 마이그레이션 미적용 상태에서 새 앱이 나가면 `select=…,pokes_enabled`가 400이 되어 **공개 설정 로드 전체가 실패**한다(토글이 낙관 기본값으로 남고 매 tick 재시도 — 경미하지만 순서를 지켜라).
**롤백**: 마이그레이션은 되돌리지 말고(컬럼은 무해) 두 함수를 `20260724030000`/R9-b 정의로 `create or replace`.

---

### 후행 커밋 (릴리스 아님): N7 → N8 → N9

**N7 `CheckMenuView.swift`(2,422줄) 11파일 분할**
- **순수 이동은 불가능하다.** Swift 최상위 `private == fileprivate`이라, 파일 경계를 넘는 참조 때문에 **정확히 11개 타입**의 `private struct X: View {` → `struct X: View {`가 강제된다(`UpdateBanner` `HeaderCard` `TeamPanel` `LeaderboardPanel` `TokenBoardPanel` `PokePanel` `InsightsPanel` `FooterBar` `LoginPanel` `TeamlessPanel` `PanelRetryButton`) + `TeamPanel.rowSpacing`의 `private` 1개. 나머지 8개 private 타입은 유일 소비자와 같은 파일에 남으므로 그대로. 이름 충돌 0건 확인. 선례: `TokenBoardRowView`가 "렌더 테스트가 직접 검증할 수 있도록 internal"로 이미 그렇게 돼 있다.
- 파일: **존치** `CheckMenuView.swift`(CheckMenuView + MenuBarStatusLabel) / 신규 10개 — `CheckMenuPanelKit`(ListRowBudget, PanelRetryButton) `UpdateBanner` `HeaderCard` `TeamPanel` `LeaderboardPanel` `TokenBoardPanel` `PokePanel` `InsightsPanel` `FooterBar` `AuthPanel`.
- **이동 단위는 선언이 아니라 블록(선행 MARK·doc 포함)이다.** 주의: `// MARK: - Team card`(`:648-649`)는 `ListRowBudget`(`:650-674`)이 아니라 **`CheckMenuTeamPanel.swift` 맨 위로** 간다.
- 새 파일에 **파일 헤더 주석을 달지 않는다** — 이 커밋의 diff가 12줄만 남게.
- **1차 증거는 테스트 통과가 아니라 정렬 멀티셋 diff다**(476 통과는 필요조건일 뿐 — 주석 한 줄을 지워도 통과한다):
```sh
git show HEAD:Sources/check/CheckMenuView.swift | grep -vE '^import |^[[:space:]]*$' | sort > /tmp/split-before.txt
cat Sources/check/CheckMenuView.swift \
    Sources/check/CheckMenu{PanelKit,UpdateBanner,HeaderCard,TeamPanel,LeaderboardPanel,TokenBoardPanel,PokePanel,InsightsPanel,FooterBar,AuthPanel}.swift \
  | grep -vE '^import |^[[:space:]]*$' | sort > /tmp/split-after.txt
diff /tmp/split-before.txt /tmp/split-after.txt
# 기대: 정확히 12쌍. 한 줄이라도 더 나오면 순수 이동이 아니다 — 중단.
# glob CheckMenu*.swift 는 CheckMenuView.swift 를 중복 계수하므로 반드시 명시 나열.
```
(`import` 는 grep에서 제외되므로 `import AppKit`을 남기든 지우든 무관 — 이번 커밋에서는 손대지 않는다.)
- 스냅샷은 **바이트가 아니라 치수 동일**로 비교(`CHECK_SNAPSHOT_DIR` + `--filter dumpTrackFSnapshots` + `sips`). 여러 스토어가 `Date()` 상대 시각을 시드해 실행마다 글리프가 흔들린다.
- **분할 다음 커밋**으로 `teamPanelVisibleRowCapAccountsForTheTokenUsageRow` 추가(`TeamPanel.maxVisibleRows == 6` + 메인 실효 상한 5 + 하위 패널 6). 분할 커밋 자체는 테스트 수 불변.
- **계약**: `CheckMenuView.swift`만이 조립(어떤 상태에서 어떤 패널을 그릴지)을 안다. 패널 파일은 서로를 참조하지 않고, 둘 이상이 공유하는 것은 `CheckMenuPanelKit.swift`로.
- **롤백**: 단독 커밋이므로 `git revert <sha>` 한 번. **다른 변경을 절대 섞지 마라** — 이 성질이 사라진다.

**N8 `PanelListScaffold`** — 실제 복제는 리포트가 지목한 4벌이 아니라 **12벌**(높이 4 + 스캐폴드 본체 4 + `visibleRows` 파생 4). 높이 계산은 `ListRowBudget.contentHeight(rowCount:rowHeight:rowSpacing:)`로 분리한다(제네릭 타입의 static은 호출부에서 타입 인자를 요구한다 — `PanelListScaffold<AnyView>.contentHeight(...)`는 못 봐 준다. `ListRowBudget` 쪽엔 이미 `visibleRows` 순수 테스트가 있어 테스트 자리도 자연스럽다). 순삭감 ≈41줄이지만 진짜 이득은 "창 높이 상한 규약을 한 곳에서만 고친다"는 것.
검증 3겹: ① 함수명 기준 필터로 상한 테스트 3종 + `swift test` 전체 ② `dumpTrackFSnapshots` 치수 대조(팀·리그) ③ 토큰 보드는 `RendersTokenBoard` 계열이 항상 스크래치패드에 PNG를 쓰므로 그걸로 대조. **콕찌르기 스냅샷이 없으면 스캐폴드 교체 **전에** `dumpTrackFSnapshots`에 `poke-eight-scroll.png` 한 줄을 추가하는 선행 커밋**으로 베이스라인을 만든다. 신규 테스트 `listContentHeightMatchesFixedRowGeometry`(0/1/6행 + 토큰보드 412 + 콕찌르기 384 + 음수 방어 — 소스 주석의 실측값과 코드를 같은 테스트로 묶는다).

**N9 마일스톤 defaults 키** — `CheckOverlayReactions.swift:95-96`(**doc 주석도 함께 갈아야 한다** — 계약 문장이 옛 저장 형식을 부정하게 된다) · `:114-116` · `:131-133` · `:150-162`. 키를 3개로 고정하고 값에 dayKey를 담는다 + **옛 날짜접미 키 1회 정리**(`split(".").count == 4`인 것만 — 새 키는 3토막이라 안전. 정리가 없으면 이미 쌓인 수백~수천 키가 영영 안 지워져 문제의 절반만 해결된다) + **세션 memo 키를 `(키, 날짜)` 쌍으로**(키에서 날짜가 빠졌으므로 그대로 두면 **자정 롤오버 후 재발화가 안 되는 회귀**가 생긴다).
```swift
let memo = "\(dkey)\u{0}\(day)"
if firedThisSession.contains(memo) { return false }
if defaults.string(forKey: dkey) == day { firedThisSession.insert(memo); return false }
defaults.set(day, forKey: dkey); firedThisSession.insert(memo); return true
```
계약: 정리는 **`MilestoneTracker` 생성 시 1회**(프로덕션에선 `WorkTimerStore.init`이 유일 호출처라 앱 실행당 1회, 테스트에선 스토어 생성마다 1회 — `dictionaryRepresentation()`이 도메인 전체를 1벌 복사하지만 테스트는 전부 격리 suite라 오염 없음). 부작용: 업데이트 당일 이미 터뜨린 사용자가 하루 한 번 더 축하를 본다(감수). 기존 `milestoneTrackerFiresOncePerKoreanDay`(CheckOverlayTests.swift:524-544)가 **단언 수정 없이 통과하는 것이 곧 관찰 동작 불변 증거**. 신규 1건으로 키 3개 고정 + purge + 자정 재발화를 함께 고정.

---

## 교차 충돌

| 파일 · 함수 | 충돌 항목 | 해소 |
|---|---|---|
| `WorkTimerStore.startStatusRefreshLoop`(:739-774) | D1(슬라이스 재확정 + 본문 첫 줄) · N1-idle(20슬라이스) · N2-menubar(rollover) | **웨이브 1 한 커밋** 필수. 본문 순서: confirmMembershipIfNeeded → rolloverIfNeeded → retryPendingSync → … |
| `WorkTimerStoreAuth.withSessionRetry`(:396-421) | N1-refresh(단일비행 + A안) · N2-cancel(8번째 지점) | **한 편집**. N2의 취소 처분이 N1의 catch 블록 안에 들어간다 |
| `WorkTimerStore.evaluateLongSession`(:482) | D3(웨이브 1, 마감 직전 idle) · D2(웨이브 2, 선두 guard) | **순서 강제**. D3가 먼저, D2가 함수 **선두**에 한 줄 추가(위치가 달라 자동 병합) |
| `WorkTimerStoreSync.runPendingSync` catch(:544) | N2-cancel(웨이브 1) · D5(웨이브 2) | 순서 강제. 취소 가드가 첫 줄, `.sessionAlreadyOpen` 분기가 그 뒤(취소와 23505는 배타) |
| `WorkTimerStoreSync.refreshTeamStatus`(:24-45) | D6-3 `teamStatusLoaded`(웨이브 3, :28) · N1-team 0행 자가감지(웨이브 4, :28 직후) | 순서 강제. 둘 다 `:28` 근방이므로 웨이브 4에서 D6-3의 한 줄 아래에 얹는다 |
| `WorkTimerStoreSync.swift:309` | N3-const 상수화(웨이브 1) · D2(웨이브 2, 근방 편집) | 순서로 해소. 충돌 시 "양쪽 다 적용" |
| `WorkTimerStore.finishWorkBeforeQuit`(:377) | O1 `isTerminating`(웨이브 1) · D2 `!adoptedRemoteSession`(웨이브 2) · D4 `confirmSignOut`(웨이브 2) | 웨이브 1 → 2 순서. 가드가 누적될 뿐 서로 배타적이지 않다 |
| `WorkTimerStorePoke.loadTokenUsagePrivacyIfNeeded`(:141-154) | D6-2(웨이브 3, in-flight 가드) · NF3(웨이브 4, 두 필드로 확장) | **순서 강제**. NF3가 D6-2의 계약(플래그 = '서버 진실 또는 확정 선택') 위에 **필드별 플래그 2개**로 확장 |
| `CheckMenuView.swift` 여러 구역 | D6-3(:834) · O7-leaf/NF1(:908) · D6-4(:976) · F1(:2034) · D4 배너(:2037·:199) · D6-6(:2081·:2319) · N1-retro(:1845) | **웨이브 3 한 웨이브**(D4만 웨이브 2 — 배너 렌더 자리 `:199`/`:187`로 구역 상이). 전부 다른 줄 |
| `CheckMenuView.swift` 전체 | 위 전부 · **N7 분할** | **분할이 맨 마지막**. 여섯 지점이 여섯 개 새 파일로 흩어지므로 역순은 여섯 패치 전부 재작성 |
| `CheckMenuView.swift:858-867 sortedMembers` | N4(모델 확장으로 이동) · UX 클러스터(`:834`/`:908`) | 같은 `TeamPanel` 안, 줄은 다름. 충돌 시 "양쪽 다 적용"이 정답 |
| `CheckTokenUsage.swift` | O3(:842·:844) · O4(:908-934) · O7-evict(:637-649) | **웨이브 1 한 커밋**. 접점 없음 |
| `SupabaseWorkService.fetchTeamStatuses`(:88) | O2 · O7-email 제거 | O2가 흡수(스냅샷 경로는 email을 애초에 안 받는다) |
| `app_user_directory` | R9-b 소속 게이트(웨이브 0) · NF3 `pokes_enabled`(웨이브 4) | 같은 함수 `create or replace`. **웨이브 4가 웨이브 0 정의를 기반으로** where 절에 한 항 추가 |
| `close_abandoned_work_sessions` | R9-c `greatest()` 보정(웨이브 0) · D2 백스톱 의존(웨이브 2) | 웨이브 0에서 재정의 완료 → 웨이브 2는 읽기만 |
| `stopWork` 무결성 | D6-stopWork `id=eq.`(웨이브 2, 클라) · R9-c 트리거/제약(웨이브 0, 서버) | **중복 구현 금지**. 서버 제약은 R9-c가 전담, 클라는 필터만 |
| `package-notarized.sh` 상단(:6-40) | R1 프로브 · R5 4개 hunk | **한 커밋**. R5의 zip 삭제를 R1 프로브 **뒤**(빌드 직전)로 |
| `release-brew.sh` | R2 → R3 → R4 | 순서 강제. R2가 없으면 R3 게이트가 곧 사라질 리터럴을 검사 |
| `docs/release.md` | R2(0단계) · R3(:80) · R4(:81) · R7(:168 앞) · R8(:144) · O5/O7 확인 쿼리 | 웨이브 0 한 커밋 권장(절이 인접) |
| `LiveE2ETests.swift` 헬퍼 | R9-a(계정 발급 재작성) · O6/R9-b(무소속 계정) · N1-team(탈퇴 픽스처) | R9-a가 **헬퍼 한 벌**을 만들고 나머지가 공유 |

---

## 하지 않기로 한 것

| 항목 | 이유 |
|---|---|
| **D1 대안: `currentTeamID` UserDefaults 캐시** | 넛지만 살고 폴링·하트비트·찌르기·큐 드레인은 그대로 죽는다. 게다가 팀을 옮긴 사용자가 낡은 team_id로 근무를 기록하는 오염 경로가 새로 생긴다. |
| **O3 상수 주입(인스턴스 let + init 파라미터)** | `nonisolated static let` 제약은 실재하지만, 주입하면 테스트가 프로덕션과 다른 값으로 통과해 '실제로 300/60이 걸려 있는가'를 아무도 보증하지 못한다. 통제할 유일한 변수인 시각은 이미 `clock`으로 주입돼 있다. → 테스트를 상수 상대식으로 + 값 핀 테스트. |
| **O4 종료 훅 flush** | (1) 이미 3초 배리어가 붙은 종료 경로에 수 MB 동기 쓰기를 얹는다 (2) **필요가 없다** — 저장을 놓쳐도 다음 실행이 스냅샷 전체를 롤백해 테일만 다시 읽으면 정확히 같은 값이 나온다(Claude는 키 dedupe가 멱등, Codex는 누산기가 같은 스냅샷에 함께 롤백) (3) 실행당 첫 저장은 스로틀이 열려 있어 '영영 저장 안 되는 실행'이 없다. |
| **O7-evict 신규 테스트** | 관찰 가능한 계약이 그대로라 새 단언은 중복이고, 할당량은 벤치 하네스 없이 단언할 수 없다. 기존 `:587`·`:641-659`가 술어 동등성을 양방향으로 이미 고정한다. |
| **`check (ended_at >= started_at)` 제약 단독** | 클라 시계가 뒤로 튄 순간 PATCH/POST가 400으로 영구 거절되어 **D5와 똑같은 poison-pill을 새로 만든다**. R9-c의 BEFORE INSERT OR UPDATE 클램프 트리거로 대체. |
| **D5의 '닫힌 쌍 보존' 변형** | `stop` 단독 재생은 id 필터 없이는 남의 열린 세션을 마감한다(D2와 같은 피해). D6-stopWork가 먼저 들어가야 안전한데 D5가 그보다 앞이다. 계약 문장을 "기록을 포기한다(부분 인덱스상 넣을 수는 있으나 이번 릴리스는 단순함을 택한다)"로 정직하게 적는 쪽을 택했다. |
| **NF5 개인 기록 [지난주\|이번 주] 탭** | 데이터는 이미 메모리에 있지만(조회 상한 없음), 회고 카드 정보 4개 중 3개(전주 대비·부족분·가장 많이 일한 날)가 **진행 중인 주에서는 의미가 무너져** 문구 세트를 새로 써야 한다 — 비용이 M을 넘는다. '이번 주 얼마나 일했나'는 헤더가 이미 상시 답한다. 실제 혼란 지점은 "이 회고가 정말 지난주가 맞나"이고 그건 N1-retro(S)로 해결된다. |
| **`token_usage_board`에 소속 게이트** | 게이트 자체는 2줄이지만 시그니처 무변경이어도 하우스 스타일상 drop 후 재생성이라 **저장소에서 가장 정교한 200줄 SQL(기기/레거시 병합, 문서화된 회귀 함정 5개)을 통째로 옮겨 적어야** 한다. R9-a가 이미 같은 경계를 막는 마당에 옮겨 적다 한 글자 틀릴 위험이 이득보다 크다. **R9-a 적용 후에도 무소속 계정이 남은 것이 확인되면** 그때 `where m.uid = auth.uid() or (coalesce(p.token_usage_public,true) and exists(...))` 2줄만 넣어 재발행. |
| **R1 옵션 (c) notarytool API 키** | 공증조차 제대로 해결하지 못한다 — `--key/--key-id/--issuer`는 `:33` notarytool의 키체인 접근만 없애는데, 실제로 5분을 태우고 죽는 지점은 그보다 **앞선 `:25` codesign**이고 여기는 Developer ID 개인키가 필요해 키체인 의존이 그대로 남는다. 늦고 싼 실패 하나를 없애고 이르고 비싼 실패는 그대로 두면서, 비용은 `.p8` 개인키 파일이라는 **새 비밀을 디스크에 추가**하는 것. 순수 손해. |
| **R1 옵션 (b) 서명 전용 비잠금 키체인** | 개인키를 `.p12`로 뽑아 스크립트가 아는 암호의 별도 키체인에 넣는다 = 실질 보안 하락. 실측 사고가 23회 중 1건인데 과하다. |
| **`CHECK_KEYCHAIN_PW`를 `.env.local`에** | login 키체인 암호 = macOS 계정 암호다. |
| **shellcheck를 CI에** | 기존 스크립트에 경고가 잔뜩 나와 초기 정리 부담이 생긴다. `bash -n`이 비용 0으로 문법 회귀만 잡는다. |
| **브랜치 보호 설정** | 1인 메인테이너가 main에 직접 푸시하는 흐름이라 CI는 게이트가 아니라 신호로 쓴다. |
| **refresh token을 Keychain으로 이전** | M~L 비용이고 클러스터 설계·검증이 없다. 완화 근거는 실재한다 — 명시적 로그아웃 시 GoTrue global logout이 실제 호출되고(`SupabaseWorkService.swift:326`) 토큰 회전이 켜져 있어 탈취가 흔적을 남긴다. 감사가 제안한 cask plist `zap`→`uninstall delete:` 이동도 설계·검증되지 않아 함께 보류. |
| **os_log 카테고리 확장 · 진단 복사 버튼** | 20명 도구에 관측 스택은 과잉이다(설계 원칙). 크래시는 macOS가 이미 `~/Library/Logs/DiagnosticReports/`에 남기므로 **그 경로를 `docs/team-install.md`에 적는 것만으로 절반 회수**된다 — 그 한 줄만 R7 문서 작업에 끼워 넣는다. |
| **참여코드 별도 왕복 제거 · 팝오버 5초 신선도 게이트** | 클러스터 설계가 없어 검증되지 않았고, 후자는 O2 적용 후에나 이득이 커진다. O2가 안정된 뒤 재평가. |
| **레거시 토큰 이중 쓰기 제거** | 지금 지우면 v0.2.10 사용자의 이번 달 수치가 소실된다. 만료 판정 쿼리를 운영 체크리스트에만 넣는다: `select count(*) from token_usage_monthly l join (select user_id, min(created_at) f from token_usage_device_monthly group by user_id) d on d.user_id=l.user_id where l.updated_at > d.f;` — 0이면 제거 가능. |
| **`NF4`를 `work_statuses`에** | 맥 2대(구/신)면 구버전 upsert가 컬럼을 안 건드려 신버전 값이 남고 **'전원 업데이트됨'으로 오독된다**. 마이그레이션 순서 위험이 `work_sessions`와 **동일 등급**(둘 다 미적용 시 근무 시작이 막힌다)이므로, 위험이 같다면 census가 정확한 쪽을 택한다. |
| **감사 §7의 폐기된 주장 8종** | 감은 눈 텍스처 2048²(실제로는 512 리샘플, `CheckOverlayTests:1513`이 고정) / 마우스 이동 콜백(지배항은 `NSEvent.mouseLocation`이고 제안은 그 뒤 좌표 변환만 없앤다) / willSleep 12.5시간(다음 방어선은 12시간 배너가 아니라 10분 스캐빈저) / 접근성 라벨(`.help()`가 macOS에서 툴팁 + 접근성 hint를 동시에 설정) / definer 함수 CPU(leakproof 필터가 비용순으로 먼저 배치돼 통과한 행에만 호출) / `TokenUsageStore.shared` 오염(인과 불성립) / 리그 무소속 가드가 UUID 유출(가드는 '아무 팀에나 소속'만 본다 — 리팩터링 회귀 복구로 재분류해 O6에 포함) / 스냅샷 테스트 무용(`#expect` 207건 중 187건이 순수·상대 단언). |

---

## 실행 체크리스트 — 웨이브 0을 지금 시작한다면

**A. 정문 닫기 (먼저, 되돌리기 쉬움)**
1. **[사람]** Supabase 대시보드 → Authentication → Sign In/Providers → Email → "Allow new users to sign up" **OFF**
2. **[사람]** `curl -sS -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $ANON" -H 'content-type: application/json' -d '{"email":"probe-'$RANDOM'@example.com","password":"Aa!12345678"}'` → `422 signup_disabled` 확인. 200이 나오면 토글이 안 걸린 것. (만든 계정이 있으면 Auth → Users에서 삭제.)
3. `supabase/config.toml:26,29`를 `enable_signup = false`로(누군가 `supabase config push` 한 번으로 다시 여는 것 방지)
4. `SupabaseWorkHTTP.swift:137` 문구 하드닝 1줄 + 단위 테스트 1건

**B. e2e 계정 발급 경로 재작성 (A와 같은 커밋 — 안 하면 e2e가 조용히 죽은 채 방치된다)**
5. `E2EAdmin.createConfirmedUser` 추가
6. `provisionOwnerWithTeam` / `provisionMemberJoiningByCode` / `makeTeamlessLiveAccount` 추가, 기존 두 헬퍼 본문 교체
7. `s05_duplicateSignUp` → `s05_selfSignUpIsDisabled` 목적 전환, `Emails.teamless` + `s10_cleanup` 갱신
8. **[사람]** `CHECK_E2E=1 swift test` → s01~s10 전부 통과 확인 (**여기까지가 A/B의 완료 조건**)

**C. 스키마 (순서대로, 한 번의 `db push`)**
9. **[사람]** `supabase projects list`로 계정 확인 (다중 계정 403 조용한 실패 전례)
10. **[사람]** O7-invite 적용 **전에** `select id, name, invite_code from public.teams where invite_code !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$';` 결과 저장
11. 마이그레이션 파일 5개 작성 — `20260801010000_query_indexes` / `..._020000_leaderboard_window_and_directory_gate` / `..._030000_work_write_integrity` / `..._040000_invite_code_hardening` / `..._050000_work_session_app_version`
12. **[사람]** `supabase db push`
13. **[사람]** SQL Editor 검증 4종 — ① `select indexname from pg_indexes where tablename in ('work_sessions','memberships');` 새 이름 4개 ② `select jobname, schedule, active from cron.job order by jobname;` **`close-abandoned-work` active = t**(웨이브 2 선행조건) ③ `select * from public.invite_code_rotation_log;`(회전된 팀 확인) ④ `\d public.work_sessions`에 `app_version` 컬럼
14. **[사람]** 회전된 팀에 새 참여코드 재공지
15. **[사람]** `CHECK_E2E=1 swift test` — 신규 e2e(s09k·s09l·s09m·s09n·s09o·s09p·s09p2·s09q) 포함 전부 통과

**D. 릴리스 스크립트 (커밋 순서 강제)**
16. **커밋 1**: R5 + R1 — `package-notarized.sh` 상단. 순서는 `set -Eeuo pipefail`+trap → 키체인 프로브 → IDENTITY 지문 가드 → **zip 삭제(빌드 직전)** → … → spctl 게이트
17. **[사람]** 비파괴 실증 5종(위 R5 항목). 특히 `spctl --status`가 `assessments enabled`인지 먼저
18. **커밋 2**: R2 — `build-local.sh` APP_VERSION/BUILD_NUMBER/plutil. **[사람]** CHANGELOG를 임시로 옮기고 `./scripts/run-local.sh` → 안내 3줄 + rc=1 확인 후 원복
19. **커밋 3**: R3 — `release-brew.sh` 사전점검 사슬. **[사람]** dry-run 4종, 특히 `0.2.4 --dry-run`이 태그 스큐를 잡는지
20. **커밋 4**: R4 — `gh release upload` → `edit --prerelease=false`
21. **커밋 5**: R7 + R8 + O5/O7 확인 쿼리 + 크래시 로그 경로 — `docs/release.md` / `docs/team-install.md`
22. **커밋 6**: R6 — `.github/workflows/ci.yml`. **[사람]** 착수 전 로컬 실증 4종(특히 `swift test --skip "$GFX_REGEX" | tail -3`의 N이 기대 범위 안인지 — 이 설계의 유일한 미검증 가정)

**E. 웨이브 0 종료 판정**
23. `swift build` + `swift test` 476 + 신규(테스트 수만 늘고 기존 단언 변경 0)
24. `git push origin main` → CI 첫 실행이 초록인지
25. **[사람]** 하루 굴려 보고 팀 패널·리그·콕찌르기가 평소대로 동작하는지 확인. 그다음 웨이브 1의 `## 0.2.15` CHANGELOG를 먼저 쓰고 착수한다(R2 이후 CHANGELOG가 물리적 강제다 — 안 쓰면 지난 버전 번호로 빌드되고 R3 게이트가 그걸 잡는다).