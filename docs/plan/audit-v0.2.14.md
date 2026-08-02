# aing-check 전체 감사 (v0.2.14 기준)

8축 병렬 조사(성능·서버·동시성·신뢰성·보안·UX·구조·운영) → 축별 적대적 반증 → 종합.
확정 73 / 미확인 1 / 폐기 5. 이후 최상위 항목은 오케스트레이터가 직접 재검증.

---

## 한눈에

코드는 전반적으로 건강하다. 세대 토큰·낙관 갱신·KST 규약 같은 어려운 부분은 이미 잘 잡혀 있고,
조사에서 나온 "심각" 후보 대부분은 검증에서 등급이 내려갔다. 진짜 문제는 세 군데다.

1. **재부팅 후 아이콘을 안 누르면 앱이 통째로 무동작** — 실증 확인
2. **맥 2대 상시 로그인이면 근무가 과거 시각으로 잘린다**
3. **팀 현황 폴링이 30초마다 팀 전원의 한 주치 세션 원본을 통째로 받는다**

릴리스 쪽은 키체인 unlock 한 줄과 버전 단일 원본화가 비용 대비 가장 값지다.

---

## 1. 지금 고쳐야 할 결함

### D1. 팝오버 미오픈 실행 = 앱 전체 무동작 ★최우선
`CheckMenuView.swift:168` / `CheckApp.swift:37`

`activateStoredSession()`의 **프로덕션 호출처가 팝오버 `.task` 단 하나**다
(전수 grep: 나머지 4건은 전부 테스트).

**실증**: MenuBarExtra(.window) + 콘텐츠 `.task`/`.onAppear` 최소 재현 앱을 만들어
8초간 팝오버를 열지 않고 관찰 → `APP_didFinishLaunching`만 찍히고
`CONTENT_onAppear`/`CONTENT_task_ran`은 **한 번도 안 찍혔다**.
즉 MenuBarExtra(.window)의 콘텐츠 뷰는 첫 오픈 전까지 생성되지 않는다.

연쇄(로그인 아이템으로 자동 실행된 뒤 아이콘을 안 누른 동안):

| 기능 | 상태 | 이유 |
|---|---|---|
| 자동 근무 시작(넛지) | ❌ | `isNudgeEligible`이 `currentTeamID != nil` 요구(`CheckOverlayWindow.swift:146`). `WorkTimerStore.init`은 세션만 복원하고 팀은 복원 안 함 → 매 tick `activeMinutes` 0 리셋 |
| 하트비트 · 팀 폴링 · 큐 드레인 | ❌ | `startStatusRefreshLoop()` 호출처가 전부 `WorkTimerStoreAuth`(activateStoredSession / signIn / signUp / joinTeam) |
| 콕찌르기 수신 | ❌ | `startPokePolling()`이 위 루프 안에서만 시작 |
| 캐릭터 오버레이 | ⚠️ | 컨트롤러는 생성되나 근무가 시작 안 되니 안 뜸 |

v0.2.12가 약속한 "자동 시작 항상 켜짐"이 **재부팅 직후엔 성립하지 않는다.**
재부팅 후 아이콘을 안 누르면 그날 근무가 통째로 안 남는다.

→ `CheckApp.swift:37` `applicationDidFinishLaunching`에서 저장 세션이 있으면
`Task { await store.activateStoredSession() }` 1회 킥.
(대안: `currentTeamID`를 UserDefaults에 캐시하고 init에서 복원 — 넛지만 살리고 폴링은 못 살림)

### D2. 두 번째 맥이 남의 세션을 과거 시각으로 마감
`WorkTimerStoreSync.swift:613`

맥 B가 폴링으로 원격 세션을 흡수하면 `startedAt`/`currentSessionID`가 서버 값으로 채워지는데,
"내가 연 세션인가" 표식이 없다. B가 잠들었다 깨면 `handleWake`(`WorkTimerStore.swift:466`)가
무조건 `autoStop(endedAt: B가 잠든 시각)`을 실행하고, `stopWork` PATCH는 세션 ID가 아니라
"열린 세션"을 대상으로 한다(`SupabaseWorkService.swift:229`).
맥 A는 다음 폴링에 `(.offWork, .some)` 분기로 스스로 근무를 끝낸다. 12시간 판정도 같은 경로.

손실은 "B가 잠든 구간"으로 제한되고 그 이전 몫은 보존되지만,
**사용자가 아무것도 안 눌렀는데 근무가 끝난다.**

→ 흡수 세션에 `adoptedRemoteSession` 플래그를 세우고, `handleWake`/`evaluateLongSession`이
그 플래그가 서면 `autoStop` 대신 로컬 표시만 내린다.
(`stopWork`에 `id=eq.` 필터만 다는 걸로는 못 막는다 — 흡수 시 세션 ID까지 복사된다.)

### D3. 12시간 확인 배너가 팝오버 안에만 있다
`WorkTimerStore.swift:482`

30분 뒤 anchor+12h 시점으로 자동 마감. 자동 재시작(넛지)이 받아 주지만
**응답창 30분 + 넛지 적립 5분 = 12시간 주기당 약 35분 구멍 + 세션 쪼개짐**이 남는다.

→ 마감 직전 `NudgeScheduler.systemIdleSeconds()`를 1회 읽어 최근 2분 안에 입력이 있으면
마감 대신 `longSessionAnchor = now`. 방치 세션은 예전처럼 마감된다.

### D4. 로그아웃이 확인 없이 진행 중 근무 + 미전송 큐를 버린다
`WorkTimerStoreAuth.swift:425` / `CheckMenuView.swift:2037`

`stop()` 없이 `startedAt=nil`, `pendingItems=[]`. 바로 옆 8pt에 앱 종료 버튼.
`clearPersistedSession`은 같은 큐를 명시적으로 보존하는데(`WorkTimerStore.swift:922`)
로그아웃만 규약을 어긴다.

→ 근무 중이거나 큐가 안 비었을 때만 인라인 확인 배너 + `finishWorkBeforeQuit`의 3초 배리어 재사용.

### D5. 근무 시작이 23505로 거절되면 큐가 고착된다
`WorkTimerStoreSync.swift:533`

드레인이 모든 throw를 일시 실패로 보고 항목을 남긴 채 return. 메뉴바가 '대기'로 굳고,
큐가 안 비어 `refreshLoopIsFast`가 참 고정 → 폴링 30초 고정 + 원격 상태 흡수·자동 마감이 전부 차단.
상대 맥이 퇴근할 때까지 수 시간.

→ `.sessionAlreadyOpen`은 큐에서 제거하고 로컬 상태를 버려
다음 `applyRemoteOwnStatus`가 서버 진실을 흡수하게 넘긴다.

### D6. 자잘한 표시 결함 (전부 비용 S)
- 리프레시 토큰 만료 시 로그인 화면에 **"이미 가입된 이메일"** — `SupabaseWorkHTTP.swift:134`의
  `contains("already")`가 먼저 걸린다. `:127` 뒤에 `refresh token`/`invalid_grant` → `.sessionExpired` 한 줄
- 토큰 공개 토글이 폴링 응답에 스냅백 — `WorkTimerStorePoke.swift:148`
  세대 재확인 뒤 `guard !tokenUsagePublicLoaded else { return }`
- 무소속 문구가 빨간 ⚠ 오류 배너로 — `WorkTimerStoreSync.swift:14` + `CheckMenuView.swift:2081`.
  숨김 목록에 한 줄
- 팀 목록 빈 자리에 '팀원' 유령 행(`CheckMenuView.swift:834`) / 리그 패널만 로딩·재시도 분기 없어
  본문에 "동기화됨"(`:976`) / 헤더 '이번 주'가 첫 왕복 동안 오늘값 폴백(`WorkTimerStore.swift:297`).
  노출 창이 수백 ms~1왕복이라 급하진 않음
- `stopWork`가 세션 ID 없이 PATCH(`SupabaseWorkService.swift:229`) — `id=eq.` 필터 +
  서버 `check (ended_at >= started_at)` 제약은 저비용

---

## 2. 최적화

### O1. 콕찌르기 폴링을 근무 중으로 제한 · 비용 S
`WorkTimerStorePoke.swift:102`

게이트가 `session != nil` 하나뿐이라 로그인만 되어 있으면 24시간 15초마다 `take_pokes`.
**사용자당 240회/시 = 하루 3,840~5,760회**, 유휴 구간 앱 요청의 약 95%.
서버가 `target_not_working`을 강제하므로(`20260724030000_poke_target_working.sql:33`)
비근무 시간대 응답은 **원리상 확정적으로 빈 배열**이다.

→ `guard self.startedAt != nil else { continue }`를
**`:111` `loadTokenUsagePrivacyIfNeeded()` 다음, `takePokes` 앞**에 배치
(앞에 두면 근무 이력 없는 사용자가 공개 설정을 영영 못 읽는다).
근무 종료 시 `stop()` 경로에서 `take_pokes` 1회 발사로 꼬리 회수.

실질 가치는 서버 부하(초당 1.3요청이라 무시 가능)가 아니라 **노트북 배터리** —
15초 라디오 웨이크업이 저녁·주말 내내 사라진다.

부작용 2가지: (a) 근무 종료 직전 15초 창의 찔림이 표시 누락될 수 있다,
(b) 이 폴링이 무료 플랜 7일 비활동 일시정지를 막아 주던 부수효과가 사라진다 — 팀 전체 장기 휴가 구간 주의.

### O2. 팀 상태 3-fanout → 스냅샷 RPC 1발 · 비용 L · 절감 최대
`SupabaseWorkService.swift:88`

필요한 값은 1인당 주간/오늘 누적 초 2개인데,
팀 전원의 **한 주치 완료 세션 원본 행 전부**를 30초마다 받아 클라에서 합산한다(`:146` limit 없음).

payload 실측 추정(행당 JSON ≈ 140B, 쿼리는 `team_id` + `ended_at >= 주시작`으로 스코프됨):

| 팀 규모 | 금요일 기준 행 수 | 1폴링 | 1인 8h/일 | 20인 22일 |
|---|---|---|---|---|
| 5인 | ~75 | ~11KB | ~11MB | ~2.3GB |
| 20인 | ~300 | ~42KB | ~40MB | ~8.8GB |

20명이 한 팀이면 무료 egress 5GB를 넘고, 작은 팀들로 쪼개져 있으면 여유가 있다.
**어느 쪽이든 요청 3발 → 1발, payload 98% 감소**는 확정 이득.

→ `team_status_snapshot(p_team uuid)` security definer RPC 신설.
본문은 `20260712010000_leaderboard_member_count.sql:36-56`의 clipped CTE를 옮기고
bounds에 KST 주시작·일시작 두 창.
**반드시 `is_team_member(p_team)` 게이트 필수**(definer라 RLS 우회).
반환에 `active_started_at` 필수(라이브 초 계산용).
덤으로 클리핑 식의 SQL/Swift 이중 구현이 하나로 합쳐진다.

### O3. 토큰 스캔 주기 완화 · 비용 S
`CheckTokenUsage.swift:842,844` — `refreshPeriod=30`, `minRefreshInterval=3`.
1회 스윕이 2,677개 파일 stat + 경로 String 생성 + 5만 엔트리 evict.
표시 값이 월 누적이라 3초 신선도는 무의미.

→ 30→300, 3→60.
**주의**: 두 값이 `nonisolated static let`이라 주입 불가이고
`Tests/checkTests/CheckTokenUsageTests.swift:922-953`이 +2초 스킵/+4초 스캔을 하드코딩 — 함께 수정.

### O4. 캐시 JSON 전량 재기록 스로틀 · 비용 M
`CheckTokenUsage.swift:292` — 새 바이트가 조금이라도 있으면 5.3MB를 통째 인코딩+원자적 재기록.
팝오버 오픈 1회당 최대 1회라 현실 상한은 하루 ~160MB 쓰기(개발자 맥 기준).

→ `startScan`에 마지막 저장 시각을 두고 `cacheChanged && now - lastSavedAt >= 300`일 때만 save.
종료 훅 flush는 `CheckApp.swift:47` `applicationShouldTerminate`의 **guard 앞**에
(비근무 시 즉시 반환하므로).

### O5. 인덱스 3개 추가 · 비용 S
전체 마이그레이션의 인덱스가 3개뿐이고, `work_sessions`엔 partial unique 하나
(`work_sessions_one_open_per_user`)만 있다. `memberships` PK는 `(team_id, user_id)`라
`user_id` 단독 필터의 선두 컬럼이 아니다.

```sql
create index if not exists work_sessions_team_ended on public.work_sessions(team_id, ended_at desc) where ended_at is not null;
create index if not exists work_sessions_user_ended on public.work_sessions(user_id, ended_at desc) where ended_at is not null;
create index if not exists memberships_user on public.memberships(user_id, joined_at, team_id);
```

현재 1개월치(수천 행)라 **지금 체감 이득 0인 순수 선제 조치**. 비용 S·위험 low라 지금 넣는 게 맞다.

### O6. 리그 RPC에 창 필터 · 비용 M
`20260712010000_leaderboard_member_count.sql:52` (최종 정의는 이 파일 — `20260711140000`은 대체됨)

"이번 주 팀별 총합"인데 `where` 절이 없어 `work_sessions` **전체 테이블**을 훑고
행마다 `work_statuses`를 조인한다. 오래된 행은 `greatest(0, …)`로 0이 되지만 스캔·계산은 다 한다.

→ `where s.ended_at is null or s.ended_at >= b.week_start` 추가(의미 동등 검증 완료 — 주 걸친 세션도 생존).
**O5 인덱스는 이 쿼리를 못 살린다**(team_id 필터가 없어 선두 컬럼 불일치) — `(ended_at)` 계열 별도 필요.
지금 아픈 문제가 아니라 증가 곡선을 끊는 조치.

### O7. 저비용 잡항목
- `pg_sleep(0.3)` 제거 — 최종 정의는 `20260711170000_fix_invite_rpc_ambiguity.sql:109`.
  anon에 열려 있어 요청당 커넥션 점유를 정상 쿼리의 300배로. 31^8 엔트로피면 sleep 없이도 무차별 대입 비현실적.
  단 기존 실팀 코드(`SUDOPARK` 등)는 사전 공격에 약하므로 `generate_invite_code()` 산 코드로 교체 병행
- `evict` 조건부 실행 — `CheckTokenUsage.swift:637`. 퇴거 대상 0건이 30일 중 29일인데
  매번 5만 키 딕셔너리 3개 재생성(≈5.7MB 할당). 절감은 순회가 아니라 할당·재해싱·ARC
- 팀 현황 select에서 `email` 제거 — `SupabaseWorkService.swift:95`.
  소비 분기 `:117`이 도달 불가(displayName 비옵셔널)
- 참여코드 별도 왕복 제거 — `WorkTimerStoreAuth.swift:271`. 이미 임베드로 읽는 `teams` 행의 컬럼
- 팝오버 오픈 시 5초 신선도 게이트 — `WorkTimerStoreAuth.swift:15`. 이득은 O2 적용 후 커짐
- 비근무 팀원 행이 매초 `store.displayNow`를 읽음 — `CheckMenuView.swift:908`.
  삼항으로 미선택 분기를 만들면 관찰 등록 자체가 사라짐. 코드 위생 수준
- 레거시 토큰 이중 쓰기 — `WorkTimerStoreSync.swift:232`. 지금 지우지 말고
  **만료 판정 쿼리를 운영 체크리스트에**:
  `select count(*) from token_usage_monthly l join (select user_id, min(created_at) f from token_usage_device_monthly group by user_id) d on d.user_id=l.user_id where l.updated_at > d.f;` — 0이면 제거 가능

---

## 3. 개선하면 좋은 것

- **refresh 단일 비행** — `WorkTimerStoreAuth.swift:389`. 401 재시도가 진입 시점의 낡은 refresh token으로
  grant를 친다. GoTrue 재사용 창(10초) 안이면 대부분 무해하지만, 무료 플랜 콜드스타트 + 15초 타임아웃에서
  낙오한 요청은 400 → `.fatal` → **근무 중 강제 로그아웃**. await 직후 `session.accessToken`이 바뀌었으면
  refresh 없이 재시도, 아니면 공유 `Task`. 30줄. 다른 회전 리스크는 이미 차단돼 있다(`:9-18`) — 401 경로만 비었다
- **취소 분기 7곳 추가** — catch 첫 줄에 `if case .cancelled = classifyAuthError(error) { return }`.
  대상: `WorkTimerStoreSync.swift:465,439,356,544` / `WorkTimerStoreAuth.swift:53,86,330`.
  그중 `autoCloseAbandonedOwnSessionIfNeeded`(`:356`)는 **오늘도 헛경보를 띄운다**
  (팝오버 닫으면 `.task` 취소 → URLError → 세대 가드 통과 → "동기화 실패")
- **로더 중복 발사** — 실질 중첩 경로는 푸터 새로고침 연타(`CheckMenuView.swift:2035`)뿐.
  버튼에 in-flight 가드 3줄이면 충분하고, 전면적 Task 핸들 도입은 규모에 안 맞는다
- **메뉴바가 시간을 상태 단어로 덮는다** — `MenuBarStatusFormatter.swift:41`.
  근무 종료 후 오늘 6시간을 일했어도 "오프". `refreshMenuBarTitle`(`WorkTimerStore.swift:797`)의
  `if derived.isWorking` 가드를 걷으면 되는데, **비근무+팝오버 닫힘이면 티커가 멈춰 자정 롤오버 갱신이 안 온다** — 비용 S~M
- **푸터 새로고침이 보고 있는 패널을 갱신하지 않는다** — `CheckMenuView.swift:2034`. `refreshVisible()`로 분기
- **리프레시 토큰이 UserDefaults 평문** — `WorkTimerStore.swift:844`.
  `defaults read kingcheck check.session.refreshToken` 한 줄로 읽힌다(샌드박스 없음, Keychain 코드 0건).
  다만 명시적 로그아웃 시 GoTrue global logout이 실제 호출되고(`SupabaseWorkService.swift:326`)
  토큰 회전이 켜져 있어 탈취는 흔적을 남긴다. 즉시 가능한 보완:
  `packaging/homebrew/aing-check.rb:26`의 plist를 `zap`에서 `uninstall delete:`로 이동
- **`docs/privacy.md`가 AI 토큰 수집을 고지하지 않는다** — 코드는 약속을 지킨다
  (본문 미수집, `CheckTokenUsage.swift:456-470`). 문서만 v0.2.9에 멈춤.
  사용량 수집 + 기본 전체공개 + 근무여부 전사 노출 3줄 추가.
  `:22` "앱/웹사이트 사용 기록"은 정면 충돌로 읽히니 "어떤 앱·웹사이트를 얼마나 썼는지"로 좁힐 것
- **구조 정리**(런타임 영향 0): 죽은 코드 ~150줄 삭제
  (`MyWeeklyGauge` `CheckMenuView.swift:884`, `TeamGoalGauge`/`StatusChip` `CheckComponents.swift:126,43`,
  `loadTeamDirectory` 계열 — 존치 사유 주석이 이미 거짓) → `CheckMenuView.swift` 2,422줄 9분할 →
  리스트 스캐폴딩 4벌 복제(`:853,1077,1308,1584`)를 `PanelListScaffold`로.
  `SleepEyeTexture`(639줄)를 `CheckCharacter3DView.swift`에서 분리
- **테스트 갭**(전부 S): `TeamPanel.sortedMembers`를 모델 확장으로 옮겨 정렬 규약 고정 /
  `pokeCooldownRemaining` 경계 3케이스 / `AuthMessageKind` 분류 /
  `#expect(TeamPanel.maxVisibleRows == 6)` + `CheckMenuRenderTests.swift:316,337` 주석 정정
  (실제 유효 상한은 토큰 행 때문에 5).
  **픽셀 높이 절대값 단언은 넣지 마라** — macOS/폰트 버전에 흔들려서 저장소가 의도적으로 상대 비교만 써 왔다
- **파서 이중화** — `SupabaseWorkService.parseDate`(`:206`, 2단)와
  `WorkInsightsDate`(`CheckWorkInsights.swift:337`, 3단). 개인 기록엔 6자리 마이크로초 회귀 테스트가 있는데
  서비스 쪽은 3자리만 고정. **1단계로 `SupabaseWorkServiceTests`에 6자리 픽스처를 추가해
  현행 `parseDate`가 nil인지부터 실증**하고 그다음 위임(위임 시 세션당 최대 1초 내림 발생 — 무해하나 명시)
- **명명 상수화** — `90`(`SupabaseWorkModels.swift:34` / `WorkTimerStoreSync.swift:309` —
  반드시 같아야 하는데 독립 리터럴), `60`(`:212`), `"2000"`(`SupabaseWorkService.swift:493`)
- **마일스톤 defaults 무한 증식** — `CheckOverlayReactions.swift:132`. 연 ~520개, 3년 ~1,600개.
  실피해 0. 고칠 거면 날짜 접미를 없애고 값에 dayKey를 저장해 키 3개로 고정

---

## 4. 새 기능 후보

| 기능 | 지금 데이터로 되나 | 비고 |
|---|---|---|
| **팀 탈퇴/추방 RPC** | ✅ 마이그레이션 1개 | `memberships` DELETE 정책도 탈퇴 경로도 0건. 퇴사자가 자기 계정으로 팀 근무현황을 계속 본다. 관리자 우회는 콘솔뿐. **코드 회전보다 실효 큼** — 회전은 이미 합류한 사람을 못 내보냄 |
| **팀원 행에 '오늘 근무시간'** | ✅ 이미 폴링에 실려 옴 | 단 `liveTodayDurationSeconds`(`SupabaseWorkModels.swift:57`)에 **KST 자정 클램프 없음** — 어제 22시 시작 세션이 새벽 1시에 '오늘 3시간'. 클램프 먼저 |
| **별명 변경** | ✅ 마이그레이션 0 | `profiles` UPDATE 정책이 이미 본인 행 허용, 트리거는 insert에만. UI는 팀 목록 내 행 인라인 편집 |
| **콕찌르기 수신 거부** | ✅ 정책 추가 불필요 | `token_usage_public`과 같은 패턴(컬럼 + `app_user_directory` 필터 + 종 아이콘). 캐릭터 끈 사용자에게도 peek이 뜨는 건 v0.2.7 의도된 계약이니 유지 |
| **`work_statuses.app_version`** | ✅ 컬럼 1 + 필드 1 | 하트비트가 이미 매번 upsert. "아직 누가 v0.2.10인가"에 답할 수 없어 호환 코드를 지울 근거가 없는 상태. 프라이버시 증가분 0 |
| **개인 기록 [지난주\|이번 주] 탭** | ✅ 조회 상한 없어 이미 메모리에 | "같은 주" 불변식을 깨지 말고 **쌍째로** 전환. 우선순위 최하위 |
| **os_log 카테고리 확장** | ✅ | `Logger`가 앱 전체에 1개(`CheckWindowAnchor.swift:33`), `print()`조차 0건. `try?` 46곳에서 실패가 사라진다. 전송 없어 프라이버시 비용 0. 크래시는 macOS가 이미 `~/Library/Logs/DiagnosticReports/`에 남기므로 그 경로를 `docs/team-install.md`에 적는 것만으로 절반 회수. **진단 복사 버튼(M)은 20명 규모에 과하다** |

---

## 5. 운영·릴리스

### R1. 키체인 unlock — 권장: 대화형 프롬프트만
저장소 전체에 `security unlock-keychain`이 **0건**이다.
잠긴 상태로 돌리면 `package-notarized.sh:22` 유니버설 릴리스 빌드(수 분)를 다 태운 뒤 `:25` codesign에서 죽는다.

→ 스크립트 선두(`:14` IDENTITY 조회 직전)에 대화형 unlock을 넣어 **실패를 0초 지점으로 앞당긴다.**
`CHECK_KEYCHAIN_PW`를 `.env.local`에 넣는 변형은 쓰지 마라 — login 키체인 암호 = macOS 계정 암호다.

※ 정정: login 키체인은 화면 잠금으로는 안 잠긴다(로그아웃·명시적 잠금·설정한 절전 시).
대화형 Terminal이면 GUI 다이얼로그가 뜨므로 "조용히 죽는" 경로는 ssh/비대화 셸 한정.
실측 사고는 23회 릴리스 중 1건. **서명 전용 비잠금 키체인 도입은 현시점에 과하다.**

### R2. 버전 3중복 → CHANGELOG 단일 원본
`scripts/build-local.sh:64` + `CHANGELOG.md:12` + `release-brew.sh` 인자.
어긋나면 공증 5~10분을 태운 뒤 zip 버전 게이트에서야 잡힌다.
`CFBundleVersion`(23)은 **어떤 게이트도 검사하지 않고 Swift 코드가 읽지도 않는다.**

→ (a) `release-brew.sh` 사전점검에 `CHANGELOG 맨 위 == 인자` 게이트 한 줄 — 5~10분 낭비를 실제로 없앤다
→ (b) plist 주입은 **히어독 인용을 풀지 말고**(`<<'PLIST'` → `<<PLIST`는 앞으로 `$`가 들어오면 조용히 깨진다)
작성 직후 `plutil -replace CFBundleShortVersionString -string "$VERSION"` 두 줄로

### R3. 태그가 릴리스된 소스를 안 가리킨다
`scripts/release-brew.sh:191`

실증: **v0.2.3과 v0.2.4가 같은 커밋 40c1b3a1을 가리키고, 그 커밋의 `build-local.sh`는 `0.2.3`이다**
(태그 14:34:28, 버전업 커밋 6386261은 17초 뒤). 롤백·이슈 재현·bisect가 한 칸씩 어긋난다.

→ 사전점검(`:178` zip 게이트 뒤)에 ① 작업트리 청결 ② `HEAD의 앱 버전 == 릴리스 버전`
③ `merge-base --is-ancestor HEAD origin/main`. `:197`을 `git push origin HEAD "$TAG"`로.

※ 게이트 코드 주의: 이 맥의 `grep`은 셸 함수라 `-A` 출력에 `-` 접두가 붙고,
zsh에서 `"$c:scripts/..."`는 `:s`를 히스토리 수식자로 먹는다.
`awk '/CFBundleShortVersionString/{getline; gsub(/[^0-9.]/,""); print; exit}'` + `"${VAR}:path"` 형태로.

### R4. 재실행 시 릴리스 노트가 안 바뀐다
`scripts/release-brew.sh:206` — 기존 릴리스 분기가 `upload --clobber` 하나뿐이고 `--notes`가 없다.
v0.2.14부터 이 노트가 곧 사용자 배너 문구다.

→ `run gh release edit "$TAG" --repo "$REPO" --title "aing-check $VERSION" --notes "$RELEASE_NOTES"` 한 줄.
`docs/release.md:81`의 '멱등' 설명에 단서 한 구절.

### R5. 패키징 스크립트 3줄 (전부 `package-notarized.sh`)
- `:15` 인증서 가드가 **도달 불가 죽은 코드**(`set -euo pipefail` + 파이프라인이 한 줄 위에서 죽인다 — 재현 확인).
  `awk '... {print $2; exit}' || true`로 파이프 상태를 흡수하면 가드가 살아나고,
  덤으로 **이름 대신 SHA-1 지문**을 쓰게 되어 인증서 갱신 시 `ambiguous` 실패도 예방
  (이 맥에 이미 동명 인증서가 두 쌍 있다)
- `:36` `spctl --assess ... || true` — 유일한 게이트키퍼 검증 결과를 버린다.
  `|| { echo ...; exit 1; }`로 게이트화. **이 그룹에서 값어치 가장 큼**
- `:40`의 `rm -f dist/aing-check.zip`을 선두로 이동 + 선두에
  `trap 'echo "실패: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR`

### R6. CI 없음
`.github` 디렉터리 자체가 없다. public 저장소라 macOS 러너 무료.

→ `ci.yml` 한 파일, `swift build` + `swift test`. **2단계 도입**:
1단계는 순수 로직만(`--filter 'CheckUpdateCheck|MenuBarStatusFormatter|CheckWorkInsights|CheckTokenUsage|SupabaseWorkService|ASCIIInputFilter|SupabaseConfig'`)
— 렌더/오버레이 테스트가 러너의 AppKit/Metal에서 도는지 확인 전엔 확신 못 한다.
`CHECK_E2E`는 절대 세팅 금지. 1단계 커버리지가 절반 이하임을 문서에 명기해 "초록불 = 안전" 오해 방지.

### R7. 롤백 절차 부재
`docs/release.md:168` 앞에 `## 롤백` 절.
① 즉시 차단: `gh release edit vX --prerelease`
(**삭제 금지** — 자산 URL이 살아 있어야 재설치가 되고, `/releases/latest`가 낮은 버전으로 바뀌어야 배너가 스스로 내려간다.
삭제해도 404는 안 나며, 404가 나도 `CheckUpdateCheck.swift:98-101`이 이전 값을 복원해 **낡은 배너가 계속 뜬다**)
② 권장: revert 후 앞으로 감기
③ 비상: tap cask revert + `brew reinstall --cask`(`upgrade`는 다운그레이드를 안 잡는다)

### R8. pg_cron 확인 쿼리
등록 실패가 `raise notice`로 삼켜진다(`20260712120000:68`, `20260724020000:171`).
코드 변경 없이 `docs/release.md:131`·`:146-150`에
`select jobname, schedule, active from cron.job order by jobname;` 두 줄.

### R9. 가입이 인터넷 전체에 열려 있다 ★
`supabase/config.toml:26-32` — `enable_signup=true` + `enable_confirmations=false`.

공개 cask의 `CheckConfig.plist`에서 anon key를 꺼낸 사람이면 누구나 curl 한 번으로 `authenticated`가 되고,
그 상태로 `app_user_directory()`(전 사용자 실명·근무여부)·`token_usage_board()`·`team_weekly_leaderboard()`를
전부 읽는다 — 세 RPC 모두 팀 소속을 요구하지 않는다.

→ **반드시 Supabase 대시보드 Auth 설정에서** 셀프 가입을 끄거나 email confirmation + 사내 도메인 제한.
`config.toml`은 로컬 `supabase start` 설정이라 고쳐도 프로덕션에 효과가 없다.
출구 쪽(RPC에 팀 공유 게이트)은 그다음.

※ 콕찌르기는 curl 2번으론 안 된다 — 무소속 계정은 세션을 못 열어 `target_not_working`.
`create_team`을 한 번 거치면 가능(총 4단계).

※ 함께: `work_sessions`/`work_statuses` UPDATE 정책의 `with check`에 `is_team_member(team_id)`가 빠져 있다
(`20260701000000:184`, `:165`). INSERT와 대칭으로 맞추는 마이그레이션 1개.
**닫힌 세션의 `started_at`/`ended_at`을 임의로 PATCH해 근무시간 위조가 가능한 게 실질 위험.**

---

## 6. 우선순위

영향 대비 비용 순.

| # | 항목 | 축 | 영향 | 비용 | 위험 |
|---|---|---|---|---|---|
| 1 | launch 시 `activateStoredSession` 1회 킥 | 신뢰성 | 팝오버 미오픈 실행의 전면 무동작 해소 | S | low |
| 2 | 콕찌르기 폴링 근무중 게이트 | 전력 | 하루 3,840회 라디오 웨이크업 제거 | S | low |
| 3 | 키체인 unlock + `spctl` 게이트화 + 인증서 지문 | 릴리스 | 5분 태우고 죽는 패턴 제거 | S | low |
| 4 | CHANGELOG 단일 원본 + 태그 소스 게이트 | 릴리스 | v0.2.4류 스큐 재발 차단 | S | low |
| 5 | `gh release edit --notes` 한 줄 | 릴리스 | 배너에 낡은 패치노트 노출 차단 | S | low |
| 6 | 인덱스 3개 마이그레이션 | DB | 선제(지금 이득 0, 곡선 차단) | S | low |
| 7 | 토큰 스캔 30s/3s → 300s/60s (+테스트) | 전력 | 스윕 약 10배 감소 | S | low |
| 8 | 12시간 마감 직전 idle 확인 | UX | 12h 주기당 35분 구멍 제거 | S | low |
| 9 | 취소 분기 7곳 + 세션만료 문구 분류 | 신뢰성 | 헛경보 1건 실제 제거 | S | low |
| 10 | 대시보드 Auth 가입 차단 + UPDATE 정책 대칭 | 보안 | 외부인 전사 열람·근무시간 위조 차단 | S~M | low |
| 11 | 흡수 세션 플래그(다기기 오마감) | 신뢰성 | 실제 근무 시간 소실 방지 | M | med |
| 12 | refresh 단일 비행 | 신뢰성 | 근무 중 강제 로그아웃 근절 | M | med |
| 13 | poison-pill 큐 처분 + 로그아웃 확인 배너 | 신뢰성 | '대기' 고착 / 오프라인 근무 소실 | M | low |
| 14 | `team_status_snapshot` RPC 통합 | 서버 | egress 98%↓, 요청 3→1 | L | med |

---

## 7. 검증에서 폐기된 주장

조사에서 나왔지만 반증된 것들 — "왜 이건 안 나왔는지" 참고용.

- **"감은 눈 텍스처가 2048² 파이프라인을 메인에서 돌려 16.8MB 상주 + 1초 UI 정지"** — 틀렸다.
  `CheckCharacter3DView.swift:168`이 씬 로드 직후 모든 디퓨즈를 **512로 리샘플**하고
  테스트가 그걸 고정한다(`CheckOverlayTests.swift:1513`). 실제 규모는 1/16(1MB, 수십 ms)
- **"마우스 이동 콜백에 패널 프레임 선판정이 없어 하루 65만 회 낭비"** — 서술은 맞지만 제안이 비용을 안 줄인다.
  지배항은 콜백 진입 + `NSEvent.mouseLocation`(윈도서버 질의)인데 제안은 그 뒤 좌표 변환(수백 ns)만 없앤다.
  절감 총량 하루 CPU 0.2초
- **"willSleep 기록을 놓치면 밤새 잠자기가 통째로 근무로 계상된다"** — 다음 방어선은 12시간 배너가 아니라
  **10분 스캐빈저**다(`20260712120000`). 노출 상한은 12.5시간이 아니라 10~15분
- **"아이콘 버튼 15개에 접근성 라벨이 없다"** — SwiftUI `.help()`는 macOS에서 툴팁과
  **접근성 hint를 동시에** 설정한다. VoiceOver는 이미 읽는다
- **"RLS security definer 함수가 스캔 행마다 호출돼 시간당 168~840 CPU-초"** — PostgreSQL은 leakproof 필터를
  비용순으로 먼저 배치하므로 함수는 **통과한 행에만** 걸린다. 연 7만 행에서도 호출은 수백 회
- **"테스트가 전역 `TokenUsageStore.shared`를 타 개발자 실기기 스냅샷이 새어 든다"** — 인과 불성립.
  `init`은 스캔을 킥하지 않고, 렌더 테스트는 격리 인스턴스를 주입하며,
  swift test 프로세스의 UserDefaults 도메인은 앱 번들과 다르다
- **"리그 무소속 가드 회귀가 타 팀 UUID 유출을 연다"** — 가드는 '아무 팀에나 소속인가'만 본다.
  `create_team`이 authenticated 전원에게 열려 있어 팀 하나 만들면 즉시 통과.
  보안 수정이 아니라 **리팩터링 회귀 복구 + 계약 테스트**로 분류
- **"'스냅샷' 렌더 테스트 20여 개가 아무것도 검증 안 한다"** — 과장. `#expect` 207건 중 187건이 순수/상대 단언이고
  배너 상호배타·패치노트 줄 수·토큰 행 높이 분기 등 픽셀 기반 회귀 테스트도 여럿 실재.
  유효한 지적은 `maxVisibleRows` 상한값 고정과 낡은 주석 정정뿐

### SceneKit 렌더 루프도 문제 없음
`CheckCharacter3DView.swift:1002-1003` — `isPlaying`/`rendersContinuously`가 `isActive`로 게이팅돼
패널 숨김 시 렌더 루프가 멈춘다. 이미 잘 되어 있다.

---

**베이스라인**: `swift test` 476개 전부 통과(64.7초). 이 감사는 읽기 전용이며 코드를 변경하지 않았다.
