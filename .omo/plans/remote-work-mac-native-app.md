# 소규모 팀 재택근무 macOS 네이티브 앱 구현 계획

## TL;DR
> **요약**: 소규모 Mac 팀이 RunCat처럼 상단바에서 근무 상태와 타이머를 바로 보고, 메뉴바 팝오버에서 근무 시작/종료와 팀원 상태 확인을 끝내는 macOS 네이티브 유틸리티를 만든다. 범위는 접근성 좋은 내부 도구에 맞추고, 별도 메인 앱 창과 자동 감시 기능은 제외한다.
> **산출물**:
> - SwiftUI macOS 상단바 전용 유틸리티
> - Supabase Auth/Postgres/Realtime 기반 팀 동기화
> - 이메일 로그인, 초대코드 팀 가입
> - 근무 시작/종료 타이머와 오늘 누적 시간
> - 팀원 현재 상태 목록
> - TDD 테스트, 로컬 Supabase 검증, 실제 앱 QA 증거
> **작업량**: Medium
> **병렬화**: YES - 4 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 4 -> Task 7 -> Task 10 -> Final Verification

## Context
### Confirmed Project Values
- 앱 표시 이름: `check`
- Xcode scheme / product name: `check`
- Bundle ID: `kingcheck`
- Supabase Project URL: `https://xfnhfjvubetkdnfkfljg.supabase.co`
- Supabase anon key: 사용자 제공값을 사용하되, 계획 파일과 git 추적 파일에는 원문 JWT를 저장하지 않는다. 구현 시 `Config/Supabase.local.xcconfig` 또는 개발자별 `.env.local`에 넣고 `.gitignore`로 제외한다.
- 기본 팀 이름 / seed 팀 이름: `sudo 박수`
- 테스트 이메일 1: `yehsungjohn34@gmail.com`
- 테스트 이메일 2: `ysiig78@gmail.com`
- 배포 방식: Mac 팀원들이 직접 설치할 수 있는 `.app`/`.zip` 또는 `.dmg` 산출물을 우선한다. Mac App Store, 자동 업데이트, notarization CI는 MVP 필수가 아니다.

### Original Request
- "팀원들끼리 쓰게 될 재택근무 맥 네이티브 앱을 만들려고 해"
- "우선 팀원들끼리 쓸거라서 그리고 되게 소규모 팀이어서 너무 방대한 기능들이 필요하진 않아."
- "그냥 누가 근무중인지 그리고 근무시간 체크할 수 있는 타이머 정도면 돼."
- "접근하기 쉽게 할려고 맥 네이티브 앱으로 만들려는거야. 팀원들 전부 맥을 쓰고 있어서."
- "한글로 정리해줄래? 그래야 내가 리뷰하기 편하지"
- "runcat 처럼 맥화면 상단바에서 표시하고 미니멀한 ui로 제공할 수 있으며 좋을듯"
- "애초에 상단바에 표시할 수만 있으면 돼. 별도 앱 형태를 꼭 갖추지 않아도 돼. runcat처럼"
- "앱 이름:check"
- "Bundle ID:kingcheck"
- "Supabase Project URL:https://xfnhfjvubetkdnfkfljg.supabase.co"
- "팀 이름:sudo 박수"
- "테스트 이메일 1:yehsungjohn34@gmail.com"
- "테스트 이메일 2:ysiig78@gmail.com"
- "배포 방식: 팀원들한테 그냥 설치시킬수만 있으면 됨."

### Interview Summary
- MVP는 재택근무 협업 플랫폼이 아니라 작은 팀의 현재 근무 여부와 타이머 확인 도구다.
- 모든 팀원이 Mac을 쓰므로 웹 우선이 아니라 macOS 네이티브 앱 우선이다.
- 앱의 핵심 표면은 일반적인 독립 앱 창이 아니라 상단바 표시와 작은 메뉴바 팝오버다.
- 기능을 작게 유지한다. 체크인, 캘린더, Slack, HR, 감시 기능은 제외한다.
- 계획과 설명은 한글로 작성한다.

### Research Summary
- 현재 `/Users/yesung/check`에는 앱 소스, Xcode 프로젝트, 패키지 매니페스트가 없다. 이 계획은 greenfield 기준이다.
- Apple `MenuBarExtra`는 앱이 활성화되지 않아도 자주 쓰는 기능을 메뉴바에서 제공하는 macOS 표면이다.
- Apple `SMAppService`는 필요 시 로그인 시 자동 실행을 구현하는 표준 API다.
- Supabase Swift SDK는 Swift 앱에서 Auth, Postgres 데이터 접근, Realtime 구독을 제공한다.
- Supabase CLI는 로컬 개발 스택, DB 마이그레이션, seed 데이터를 관리한다.

### Metis Review (gaps addressed)
- 백엔드 스택을 Supabase로 고정했다. 별도 커스텀 API 서버는 MVP에서 만들지 않는다.
- 인증은 이메일 magic link/OTP로 고정했다. 비밀번호, Google Workspace, SAML은 제외한다.
- 데이터 모델과 RLS 정책을 작업 범위에 포함했다.
- 동기화 의미를 `work_status` 최신 상태 + `work_sessions` 기록으로 분리했다.
- 개인정보 기준을 테스트 가능한 금지 항목으로 명시했다.
- 근무 상태는 MVP에서 `working`, `off_work` 두 가지만 사용한다. `break`는 후속 기능으로 미룬다.
- 시간 기준은 서버에 저장된 `started_at`, `ended_at`을 기준으로 한다. UI 경과 시간은 서버 기준 시작 시각을 로컬 clock으로 표시하되 저장값은 서버 기록을 신뢰한다.
- 초대코드는 팀 생성자가 확인할 수 있는 재사용 가능한 코드로 시작한다. 만료, 이메일 초대, 승인 워크플로우는 MVP 밖이다.

## Work Objectives
### Core Objective
소규모 Mac 팀원이 메뉴바 앱에서 근무 타이머를 시작/정지하고, 팀원별 현재 근무 상태와 오늘 누적 근무시간을 확인할 수 있게 한다.

### Deliverables
- `check.xcodeproj` 또는 Swift Package 기반 macOS 메뉴바 유틸리티 프로젝트
- 앱 표시 이름 `check`, Bundle ID `kingcheck`, scheme `check`
- SwiftUI `MenuBarExtra` 기반 상단바 표면
- Supabase 로컬 개발 설정과 DB 마이그레이션
- Supabase 원격 프로젝트 `https://xfnhfjvubetkdnfkfljg.supabase.co` 연결 설정
- 이메일 로그인 및 초대코드 기반 팀 가입
- 근무 타이머 시작/정지/복구 로직
- 팀원 현재 상태와 오늘 누적 시간 실시간 동기화
- 테스트 스위트와 QA 증거 파일
- 내부 배포용 빌드/실행 문서

### Definition of Done (verifiable conditions with commands)
- `xcodebuild test -scheme check -destination 'platform=macOS'`가 0으로 종료한다.
- `supabase db reset`이 로컬 마이그레이션과 seed를 적용하고 0으로 종료한다.
- SQL/RLS 검증 스크립트가 다른 팀의 상태/세션 데이터를 읽을 수 없음을 증명한다.
- 실제 macOS 앱을 실행해 `yehsungjohn34@gmail.com`, `ysiig78@gmail.com` 테스트 계정으로 로그인, `sudo 박수` 팀 가입, 타이머 시작, 팀원 상태 확인, 타이머 정지를 통과한 QA 증거가 `.omo/evidence/`에 저장된다.
- 앱은 Accessibility, Screen Recording, Camera, Microphone, Location 권한을 요청하지 않는다.
- 앱은 일반적인 메인 윈도우 없이 상단바 항목과 팝오버 중심으로 동작한다.

### Must Have
- 메뉴바에서 즉시 타이머 상태를 볼 수 있어야 한다.
- 상단바 항목은 RunCat처럼 항상 눈에 띄는 짧은 상태 표시를 제공한다. 예: `● 01:24`, `○ 종료`, `! 대기`.
- 클릭 후 열리는 UI는 메뉴바 팝오버 하나로 제한한다.
- 타이머 시작은 현재 사용자를 `근무중`으로 만든다.
- 타이머 정지는 현재 세션을 종료하고 오늘 누적 시간을 갱신한다.
- 사용자당 동시에 열린 근무 세션은 하나만 허용한다.
- 팀원 목록은 이름, 현재 상태, 오늘 누적 시간, 마지막 동기화 시각을 보여준다.
- 팀원 목록은 현재 상태가 `근무중`이면 근무 시작 시각을 보여준다.
- 앱 재실행 후 진행 중인 세션이 복구되어야 한다.
- 네트워크가 끊기면 마지막 상태를 유지하되 stale 표시를 해야 한다.
- 팀 데이터는 초대코드로 가입한 같은 팀원에게만 보인다.
- Supabase anon key 원문은 git에 커밋하지 않는다. 앱 빌드에는 개발자별 local config에서 주입한다.

### Must NOT Have
- 키보드/마우스 활동 추적 금지
- 앱/웹사이트 사용 기록 수집 금지
- 스크린샷, 카메라, 마이크, 위치 수집 금지
- 생산성 점수, 감시 대시보드, 자동 근무 판정 금지
- Slack/Calendar/HR/급여 연동 금지
- 관리자 콘솔, 감사 로그, 복잡한 권한 모델 금지
- 별도 메인 앱 창 또는 대시보드 금지
- 모바일 앱, 웹 앱, App Store 출시 금지

## Verification Strategy
> ZERO HUMAN INTERVENTION - 모든 검증은 에이전트가 실행 가능한 명령이나 실제 앱 사용 시나리오로 정의한다.
- Test decision: TDD
- macOS app tests: XCTest unit tests + XCUITest where practical
- Backend tests: Supabase local stack + SQL migration/RLS checks
- QA policy: 각 작업은 최소 happy path와 edge/failure 시나리오를 가진다.
- Evidence path: `.omo/evidence/task-{N}-{slug}.{ext}`
- 실제 앱 QA channel: desktop GUI이므로 Computer use 또는 AppleScript/osascript 보조 자동화를 사용한다. 메뉴바 상호작용 자동화가 제한될 경우 테스트 전용 accessibility identifier를 둔 동일 `MenuBarExtra` 팝오버 경로로 검증한다. 별도 메인 앱 창으로 대체하지 않는다.

## Execution Strategy
### Parallel Execution Waves
Wave 1: Task 1, Task 2, Task 3
Wave 2: Task 4, Task 5, Task 6
Wave 3: Task 7, Task 8, Task 9
Wave 4: Task 10, Task 11, Task 12

### Dependency Matrix
- Task 1: blocks Task 4, Task 5, Task 6, Task 7, Task 8, Task 9, Task 10, Task 11, Task 12
- Task 2: blocks Task 4, Task 7, Task 8, Task 10
- Task 3: blocks Task 5, Task 9, Task 12
- Task 4: blocked by Task 1, Task 2; blocks Task 7, Task 10
- Task 5: blocked by Task 1, Task 3; blocks Task 9, Task 11
- Task 6: blocked by Task 1; blocks Task 7, Task 8, Task 10
- Task 7: blocked by Task 1, Task 2, Task 4, Task 6; blocks Task 10
- Task 8: blocked by Task 1, Task 2, Task 6; blocks Task 10
- Task 9: blocked by Task 1, Task 3, Task 5; blocks Task 11
- Task 10: blocked by Task 1, Task 2, Task 4, Task 6, Task 7, Task 8
- Task 11: blocked by Task 1, Task 5, Task 9
- Task 12: blocked by Task 1, Task 3

## TODOs
- [ ] 1. `check` 상단바 전용 프로젝트 스캐폴드와 테스트 기반 만들기

  **What to do**: Xcode macOS 메뉴바 유틸리티 프로젝트를 만들고 앱 표시 이름, product name, scheme은 `check`로 고정한다. Bundle ID는 사용자 제공값 `kingcheck`로 설정한다. 최소 대상은 macOS 14 이상으로 설정한다. SwiftUI App lifecycle을 사용하고 `MenuBarExtra`를 유일한 주요 UI scene으로 둔다. Dock 아이콘/일반 메인 윈도우는 MVP에서 사용하지 않는 방향으로 구성한다. 테스트 타깃 `checkTests`, UI 테스트 타깃 `checkUITests`를 만든다. SwiftLint는 이 계획 범위에 넣지 않는다.
  **Must NOT do**: iOS, Catalyst, Electron, React Native, 웹 앱 스캐폴드, 별도 메인 앱 창을 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 4,5,6,7,8,9,10,11,12 | Blocked By: none

  **References**:
  - Pattern: 새 greenfield 프로젝트. 기존 소스 패턴 없음.
  - External: `https://developer.apple.com/documentation/swiftui/menubarextra` - 메뉴바 표면
  - External: `https://developer.apple.com/documentation/swiftui/app` - SwiftUI app lifecycle

  **Acceptance Criteria**:
  - [ ] `xcodebuild -list`에서 `check` scheme이 보인다.
  - [ ] `xcodebuild test -scheme check -destination 'platform=macOS'`가 빈 테스트 포함 0으로 종료한다.
  - [ ] `checkApp`에 `MenuBarExtra` scene이 있다.
  - [ ] Bundle ID가 `kingcheck`로 설정되어 있다.
  - [ ] 앱 실행 시 일반 메인 윈도우가 자동으로 열리지 않는다.

  **QA Scenarios**:
  ```
  Scenario: 앱 실행 happy path
    Tool: computer use + open
    Steps: `open build/Build/Products/Debug/check.app`로 앱을 실행하고 상단바 항목이 나타나는지 확인한다.
    Expected: 상단바에 앱 항목이 표시되고 일반 앱 창은 열리지 않으며 앱이 즉시 종료되지 않는다.
    Evidence: .omo/evidence/task-1-app-launch.png

  Scenario: 테스트 타깃 누락 edge
    Tool: bash
    Steps: `xcodebuild test -scheme check -destination 'platform=macOS' | tee .omo/evidence/task-1-xcodebuild.txt`
    Expected: `TEST SUCCEEDED`가 포함된다.
    Evidence: .omo/evidence/task-1-xcodebuild.txt
  ```

  **Commit**: YES | Message: `chore(app): scaffold macOS menu bar project` | Files: `check.xcodeproj`, `check/`, `checkTests/`, `checkUITests/`

- [ ] 2. Supabase 로컬 스택과 데이터 모델 만들기

  **What to do**: `supabase init` 기반 설정을 추가한다. 로컬 Supabase 스택과 원격 프로젝트 `https://xfnhfjvubetkdnfkfljg.supabase.co`를 모두 대상으로 삼는다. 마이그레이션으로 `teams`, `team_invites`, `profiles`, `memberships`, `work_statuses`, `work_sessions` 테이블을 만든다. `work_statuses`는 사용자별 최신 상태 1행만 유지한다. `work_sessions`는 시작/종료 시각과 duration seconds를 저장한다. seed 팀 이름은 `sudo 박수`로 고정한다.
  **Must NOT do**: 별도 Node/Rails/Go API 서버를 만들지 않는다. CloudKit을 병행하지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 4,7,8,10 | Blocked By: none

  **References**:
  - External: `https://supabase.com/docs/guides/local-development/overview` - 로컬 개발과 마이그레이션
  - External: `https://supabase.com/docs/guides/database/postgres/row-level-security` - RLS 정책
  - Data contract:
    - `teams(id uuid, name text, invite_code text unique, created_at timestamptz)`
    - `profiles(id uuid references auth.users, display_name text, created_at timestamptz)`
    - `memberships(team_id uuid, user_id uuid, role text, joined_at timestamptz)`
    - `work_statuses(team_id uuid, user_id uuid, status text, active_session_id uuid null, last_seen_at timestamptz, updated_at timestamptz)`
    - `work_sessions(id uuid, team_id uuid, user_id uuid, started_at timestamptz, ended_at timestamptz null, duration_seconds integer null)`
    - Constraint: `(user_id, ended_at is null)` 의미의 부분 unique index로 사용자당 열린 세션 1개만 허용

  **Acceptance Criteria**:
  - [ ] `supabase db reset`이 0으로 종료한다.
  - [ ] seed 데이터로 `sudo 박수` 팀 1개, 테스트 유저 `yehsungjohn34@gmail.com`, `ysiig78@gmail.com`, 진행 중 세션 1개, 종료 세션 1개가 만들어진다.
  - [ ] 같은 팀 멤버는 `work_statuses`와 `work_sessions`를 읽을 수 있다.
  - [ ] 다른 팀 멤버는 읽을 수 없다.

  **QA Scenarios**:
  ```
  Scenario: 로컬 DB happy path
    Tool: bash
    Steps: `supabase db reset | tee .omo/evidence/task-2-db-reset.txt`
    Expected: 마이그레이션과 seed 적용이 성공한다.
    Evidence: .omo/evidence/task-2-db-reset.txt

  Scenario: RLS 격리 failure path
    Tool: bash
    Steps: `psql "$SUPABASE_DB_URL" -f supabase/tests/rls_isolation.sql | tee .omo/evidence/task-2-rls.txt`
    Expected: 다른 팀 데이터 조회 결과가 0행이다.
    Evidence: .omo/evidence/task-2-rls.txt
  ```

  **Commit**: YES | Message: `feat(db): add team work timer schema` | Files: `supabase/`

- [ ] 3. 제품 문서와 상단바 전용 범위 가드레일 작성

  **What to do**: `README.md`에 앱 목적, MVP 범위, 제외 범위, 로컬 실행 방법, 개인정보 원칙을 한글로 작성한다. `docs/privacy.md`에는 수집하는 데이터와 수집하지 않는 데이터를 명확히 쓴다. 제품 설명은 "상단바 전용 근무 타이머"로 고정한다. `README.md`에는 앱 이름 `check`, Bundle ID `kingcheck`, Supabase URL, 팀 이름 `sudo 박수`, 테스트 계정 2개를 명시하되 Supabase anon key 원문은 커밋하지 말고 로컬 설정에 넣으라고 쓴다.
  **Must NOT do**: 마케팅 랜딩 페이지나 장문의 비전 문서를 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 5,9,12 | Blocked By: none

  **References**:
  - Plan Context: 이 계획의 `Original Request`, `Interview Summary`, `Must Have`, `Must NOT Have` 섹션 - 확정된 축소 범위
  - Guardrail: 자동 감시, 생산성 점수, 스크린샷 수집 제외

  **Acceptance Criteria**:
  - [ ] `README.md`가 앱 목적과 실행 명령을 한글로 설명한다.
  - [ ] `docs/privacy.md`가 금지 데이터 항목을 명시한다.
  - [ ] `rg "스크린샷|키보드|마우스|생산성 점수" docs README.md`로 금지 항목 설명을 확인할 수 있다.

  **QA Scenarios**:
  ```
  Scenario: 문서 범위 happy path
    Tool: bash
    Steps: `rg "check|kingcheck|sudo 박수|근무중|타이머|상단바|메뉴바|소규모 팀|RunCat" README.md docs/privacy.md | tee .omo/evidence/task-3-docs.txt`
    Expected: 핵심 범위 문구가 모두 검색된다.
    Evidence: .omo/evidence/task-3-docs.txt

  Scenario: 범위 확장 회귀 edge
    Tool: bash
    Steps: `rg "메인 앱 창|대시보드|Slack|Calendar|급여|HR|스크린샷 모니터링|생산성 점수" README.md docs/privacy.md | tee .omo/evidence/task-3-guardrails.txt`
    Expected: 제외 범위로만 언급되고 기능 약속으로 쓰이지 않는다.
    Evidence: .omo/evidence/task-3-guardrails.txt
  ```

  **Commit**: YES | Message: `docs(product): define small-team timer scope` | Files: `README.md`, `docs/privacy.md`

- [ ] 4. Supabase Swift 클라이언트와 상단바 인증 세션 붙이기

  **What to do**: Supabase Swift SDK를 Swift Package dependency로 추가한다. `SupabaseClientProvider`, `AuthSessionStore`, `AuthViewModel`을 만든다. Supabase URL은 `https://xfnhfjvubetkdnfkfljg.supabase.co`로 고정한다. anon key는 사용자 제공값을 `Config/Supabase.local.xcconfig` 또는 `.env.local`에서 주입하고 git에 커밋하지 않는다. 이메일 magic link/OTP 로그인과 로그아웃을 구현한다. 로그인 입력과 오류 표시는 메뉴바 팝오버 안에서 처리한다. magic link가 시스템 브라우저를 열 수는 있지만, 인증 완료 후 앱은 상단바 유틸리티 상태로 복귀해야 한다. 세션 토큰은 Keychain에 저장한다.
  **Must NOT do**: 비밀번호 로그인, Google/Slack OAuth, SAML, 자체 JWT 서버를 구현하지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 7,10 | Blocked By: 1,2

  **References**:
  - External: `https://supabase.com/docs/reference/swift/introduction` - Supabase Swift SDK
  - External: `https://supabase.com/docs/reference/swift/auth-api` - Swift Auth
  - External: `https://developer.apple.com/documentation/security/keychain_services` - Keychain storage

  **Acceptance Criteria**:
  - [ ] `AuthViewModelTests.testEmailOtpRequestShowsPendingState`가 RED 후 GREEN으로 통과한다.
  - [ ] `AuthViewModelTests.testSignOutClearsStoredSession`이 통과한다.
  - [ ] `SupabaseConfigTests.testLoadsProvidedProjectURL`이 `https://xfnhfjvubetkdnfkfljg.supabase.co`를 읽는다.
  - [ ] `SupabaseConfigTests.testAnonKeyIsNotHardCodedInTrackedSources`가 통과한다.
  - [ ] 인증 실패 시 앱이 crash하지 않고 한글 오류 메시지를 보여준다.

  **QA Scenarios**:
  ```
  Scenario: 이메일 로그인 happy path
    Tool: computer use
    Steps: 상단바 항목 클릭 -> 팝오버에서 `yehsungjohn34@gmail.com` 입력 -> OTP/magic link 테스트 흐름 완료
    Expected: 사용자 표시명이 상단바 팝오버에 나타나고 일반 메인 창은 열리지 않는다.
    Evidence: .omo/evidence/task-4-login.png

  Scenario: 잘못된 이메일 edge
    Tool: computer use
    Steps: 상단바 팝오버 로그인 입력에 `bad-email` 입력 후 제출
    Expected: "올바른 이메일을 입력하세요" 오류가 팝오버 안에 표시되고 앱이 유지된다.
    Evidence: .omo/evidence/task-4-invalid-email.png
  ```

  **Commit**: YES | Message: `feat(auth): add Supabase email login` | Files: `check/`, `checkTests/`, `Config/`, `.gitignore`

- [ ] 5. 팝오버 안에서 팀 생성/초대코드 가입 흐름 만들기

  **What to do**: 첫 로그인 후 팀이 없으면 메뉴바 팝오버 안에 `팀 만들기`와 `초대코드로 참여` 선택지를 보여준다. 팀 생성 시 8자리 초대코드를 만든다. 초대코드 가입은 `memberships`를 생성한다. 관리자 기능은 초대코드 보기까지만 만든다.
  **Must NOT do**: 멤버 제거, 역할 관리 UI, 감사 로그, 초대 이메일 발송을 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 9,11 | Blocked By: 1,3

  **References**:
  - API/Type: `teams`, `team_invites`, `memberships` from Task 2 data contract
  - UX copy: 한글 UI, 짧은 문장

  **Acceptance Criteria**:
  - [ ] `TeamOnboardingTests.testCreateTeamStoresMembership`가 통과한다.
  - [ ] `TeamOnboardingTests.testJoinWithInvalidInviteShowsError`가 통과한다.
  - [ ] 초대코드는 같은 팀 가입에만 사용되고, 없는 코드는 실패한다.

  **QA Scenarios**:
  ```
  Scenario: 팀 생성 happy path
    Tool: computer use
    Steps: `yehsungjohn34@gmail.com` 로그인 -> 상단바 팝오버에서 팀 만들기 -> 팀명 `sudo 박수` 입력
    Expected: 팀이 생성되고 초대코드가 팝오버 안에 표시된다.
    Evidence: .omo/evidence/task-5-create-team.png

  Scenario: 잘못된 초대코드 edge
    Tool: computer use
    Steps: `ysiig78@gmail.com` 로그인 -> 상단바 팝오버에서 초대코드 참여 -> `BADCODE1` 입력
    Expected: "초대코드를 찾을 수 없습니다"가 표시된다.
    Evidence: .omo/evidence/task-5-invalid-invite.png
  ```

  **Commit**: YES | Message: `feat(team): add invite-code onboarding` | Files: `check/`, `checkTests/`

- [ ] 6. 타이머 도메인 모델과 로컬 상태 복구 구현

  **What to do**: `WorkTimerState`, `WorkSessionDraft`, `TimerClock`, `TimerPersistence`를 만든다. 진행 중 세션은 앱 재실행 후 복구한다. 시간 계산은 테스트 가능한 clock injection으로 구현한다.
  **Must NOT do**: 시스템 활동, idle time, 키보드/마우스 입력으로 근무 여부를 자동 판정하지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 7,8,10 | Blocked By: 1

  **References**:
  - Domain rule: 사용자가 시작 버튼을 누르면 근무 시작, 정지 버튼을 누르면 근무 종료
  - Privacy guardrail: 자동 감시 없음

  **Acceptance Criteria**:
  - [ ] `WorkTimerTests.testStartCreatesRunningSession`가 RED 후 GREEN으로 통과한다.
  - [ ] `WorkTimerTests.testStopCalculatesDurationSeconds`가 통과한다.
  - [ ] `WorkTimerTests.testRelaunchRestoresRunningSession`가 통과한다.
  - [ ] `WorkTimerTests.testCannotStartTwoRunningSessions`가 통과한다.

  **QA Scenarios**:
  ```
  Scenario: 타이머 시작/정지 happy path
    Tool: computer use
    Steps: 앱 실행 -> 상단바 항목 클릭 -> 팝오버에서 시작 클릭 -> 3초 대기 -> 팝오버에서 정지 클릭
    Expected: 오늘 누적 시간이 3초 이상으로 표시된다.
    Evidence: .omo/evidence/task-6-timer-basic.png

  Scenario: 중복 시작 edge
    Tool: computer use
    Steps: 상단바 팝오버에서 시작 클릭 -> 다시 시작 클릭 시도
    Expected: 두 번째 진행 중 세션이 생기지 않고 UI는 정지 버튼만 보여준다.
    Evidence: .omo/evidence/task-6-no-duplicate.png
  ```

  **Commit**: YES | Message: `feat(timer): add work session state machine` | Files: `check/`, `checkTests/`

- [ ] 7. 근무 시작/종료를 Supabase에 동기화하기

  **What to do**: 타이머 시작 시 DB 서버 시간 기준으로 `work_sessions`에 열린 세션을 만들고 `work_statuses.status = working`으로 upsert한다. 정지 시 서버 시간 기준 `ended_at`, `duration_seconds`를 저장하고 `work_statuses.status = off_work`로 갱신한다. 요청 실패 시 로컬 pending operation으로 재시도한다.
  **Must NOT do**: 실패한 동기화를 조용히 버리지 않는다. 사용자를 자동으로 근무중/근무종료로 바꾸지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 10 | Blocked By: 1,2,4,6

  **References**:
  - External: `https://supabase.com/docs/reference/swift/select` - Swift 데이터 조회/변경
  - API/Type: `work_sessions`, `work_statuses` from Task 2
  - Test pattern: mock Supabase repository protocol

  **Acceptance Criteria**:
  - [ ] `WorkSyncTests.testStartUpsertsWorkingStatus`가 통과한다.
  - [ ] `WorkSyncTests.testStopClosesSessionAndMarksOffWork`가 통과한다.
  - [ ] `WorkSyncTests.testNetworkFailureQueuesRetry`가 통과한다.
  - [ ] 로컬 Supabase에 실제 행이 생성/갱신된다.

  **QA Scenarios**:
  ```
  Scenario: 동기화 happy path
    Tool: bash + computer use
    Steps: 앱에서 시작/정지 실행 후 `psql "$SUPABASE_DB_URL" -f supabase/tests/work_session_created.sql`
    Expected: 세션 1개와 최신 상태 off_work 1개가 확인된다.
    Evidence: .omo/evidence/task-7-sync.txt

  Scenario: 네트워크 실패 edge
    Tool: computer use
    Steps: Supabase 로컬 스택 정지 -> 앱에서 시작 -> Supabase 재시작
    Expected: 앱이 "동기화 대기중"을 표시하고 재연결 후 서버에 반영한다.
    Evidence: .omo/evidence/task-7-offline-retry.png
  ```

  **Commit**: YES | Message: `feat(sync): persist timer state to Supabase` | Files: `check/`, `checkTests/`, `supabase/tests/`

- [ ] 8. 팀원 현재 상태와 오늘 누적 시간 구독 구현

  **What to do**: 팀별 `work_statuses`와 오늘의 `work_sessions`를 조회하고 Supabase Realtime으로 최신 상태 변경을 구독한다. 팀원 행에는 이름, 상태 배지, 오늘 누적 시간, 마지막 동기화 시각을 표시한다.
  **Must NOT do**: 과거 상세 타임라인, 통계 대시보드, 생산성 랭킹을 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 10 | Blocked By: 1,2,6

  **References**:
  - External: `https://supabase.com/docs/reference/swift/subscribe` - Realtime 구독
  - UI contract: 팀원 목록은 compact list, 한글 상태 `근무중`, `근무종료`, `동기화 지연`

  **Acceptance Criteria**:
  - [ ] `TeamStatusTests.testLoadsCurrentTeamStatuses`가 통과한다.
  - [ ] `TeamStatusTests.testRealtimeUpdateChangesVisibleStatus`가 통과한다.
  - [ ] `TeamStatusTests.testStaleStatusShowsLastSeen`가 통과한다.

  **QA Scenarios**:
  ```
  Scenario: 팀원 상태 happy path
    Tool: computer use + bash
    Steps: seed로 `yehsungjohn34@gmail.com` 근무중, `ysiig78@gmail.com` 근무종료 생성 -> 상단바 팝오버에서 팀원 목록 열기
    Expected: 두 팀원의 상태와 오늘 누적 시간이 표시된다.
    Evidence: .omo/evidence/task-8-team-status.png

  Scenario: stale 상태 edge
    Tool: bash + computer use
    Steps: `ysiig78@gmail.com`의 `last_seen_at`을 15분 전으로 변경 -> 상단바 팝오버 목록 갱신
    Expected: `ysiig78@gmail.com`에 "동기화 지연" 또는 마지막 동기화 시각이 표시된다.
    Evidence: .omo/evidence/task-8-stale-status.png
  ```

  **Commit**: YES | Message: `feat(team): show realtime work status list` | Files: `check/`, `checkTests/`

- [ ] 9. RunCat-like 상단바 중심 UI 완성

  **What to do**: 상단바 항목에 현재 상태와 경과 시간을 짧게 표시한다. RunCat처럼 계속 눈에 들어오는 미니 상태 표시가 핵심이다. 표시 형식은 `● 01:24`(근무중), `○ 종료`(근무종료), `! 대기`(동기화 대기)로 고정한다. 클릭 시 메뉴바 팝오버에서 시작/정지 버튼, 오늘 누적 시간, 팀원 미니 리스트, 설정 진입점만 보여준다. 텍스트는 전부 한글로 작성한다.
  **Must NOT do**: 랜딩 페이지형 UI, 카드 과잉 디자인, 복잡한 네비게이션, 별도 메인 앱 창, 대시보드를 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 11 | Blocked By: 1,3,5

  **References**:
  - External: `https://developer.apple.com/documentation/swiftui/menubarextra`
  - UX reference: RunCat처럼 상단바에 계속 보이는 미니멀 상태 표시
  - Frontend guardrail: 조용하고 실용적인 내부 도구 UI

  **Acceptance Criteria**:
  - [ ] `checkUITests.testMenuShowsStartAndStopFlow`가 통과한다.
  - [ ] `checkUITests.testKoreanLabelsFitMenuPopover`가 통과한다.
  - [ ] `MenuBarStatusFormatterTests.testWorkingShowsDotAndElapsedTime`가 통과한다.
  - [ ] `MenuBarStatusFormatterTests.testOffWorkShowsEndedLabel`가 통과한다.
  - [ ] 상단바에 running 상태에서 경과 시간이 표시된다.
  - [ ] 상단바 항목 클릭 전에도 내 근무 상태를 알 수 있다.

  **QA Scenarios**:
  ```
  Scenario: 상단바 사용 happy path
    Tool: computer use
    Steps: 상단바 항목 클릭 -> 팝오버에서 시작 -> 상단바 경과 시간 확인 -> 팝오버에서 정지
    Expected: 상단바 텍스트가 `● 00:03` 같은 형식으로 변하고 정지 후 `○ 종료`로 바뀐다.
    Evidence: .omo/evidence/task-9-menubar-flow.png

  Scenario: 미니 팝오버 edge
    Tool: computer use
    Steps: 메뉴바 팝오버를 열고 팀원 10명 seed 데이터를 표시한다.
    Expected: 한글 버튼/라벨이 잘리지 않고 겹치지 않으며 별도 메인 창이 열리지 않는다.
    Evidence: .omo/evidence/task-9-compact-ui.png
  ```

  **Commit**: YES | Message: `feat(ui): build minimal menu bar timer UI` | Files: `check/`, `checkTests/`, `checkUITests/`

- [ ] 10. 앱 재실행, sleep/wake, 오프라인 복구 품질 보강

  **What to do**: 앱 시작 시 진행 중 세션을 서버와 로컬 캐시에서 복구한다. 네트워크 실패는 `동기화 대기중`으로 표시한다. Mac sleep/wake 또는 앱 재실행 후에도 타이머 경과 시간이 실제 시작 시각 기준으로 계산되게 한다.
  **Must NOT do**: 백그라운드에서 사용자를 자동 감시하거나 idle time으로 시간을 깎지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 4 | Blocks: final | Blocked By: 1,2,4,6,7,8

  **References**:
  - API/Type: `TimerClock`, `TimerPersistence`, Supabase repositories from Tasks 6-8
  - macOS behavior: app lifecycle foreground/background transitions

  **Acceptance Criteria**:
  - [ ] `RecoveryTests.testRunningTimerUsesStartedAtAfterRelaunch`가 통과한다.
  - [ ] `RecoveryTests.testPendingSyncFlushesAfterReconnect`가 통과한다.
  - [ ] `RecoveryTests.testServerSessionWinsWhenLocalCacheIsOlder`가 통과한다.

  **QA Scenarios**:
  ```
  Scenario: 재실행 복구 happy path
    Tool: computer use
    Steps: 상단바 팝오버에서 시작 클릭 -> 앱 종료 -> 앱 재실행
    Expected: 상단바에 타이머가 계속 진행 중으로 보이고 경과 시간이 초기화되지 않는다.
    Evidence: .omo/evidence/task-10-relaunch-recovery.png

  Scenario: 오프라인 복구 edge
    Tool: computer use + bash
    Steps: Supabase 정지 -> 정지 클릭 -> Supabase 재시작
    Expected: 동기화 대기중 표시 후 서버에 종료 시간이 반영된다.
    Evidence: .omo/evidence/task-10-offline-recovery.png
  ```

  **Commit**: YES | Message: `fix(sync): recover timer state across relaunch` | Files: `check/`, `checkTests/`

- [ ] 11. 팝오버 설정과 로그인 시 자동 실행 옵션 추가

  **What to do**: 메뉴바 팝오버 안의 설정 섹션에 표시명, 팀명/초대코드 보기, 로그아웃, 로그인 시 자동 실행 토글을 둔다. 자동 실행은 `SMAppService.mainApp` 또는 적절한 ServiceManagement API로 구현한다.
  **Must NOT do**: 다중 팀 전환, 멤버 관리, 관리자 권한 UI를 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 4 | Blocks: final | Blocked By: 1,5,9

  **References**:
  - External: `https://developer.apple.com/documentation/servicemanagement/smappservice`
  - UX contract: 설정은 MVP 보조 기능이며 한 화면 안에 유지

  **Acceptance Criteria**:
  - [ ] `SettingsTests.testDisplayNameUpdatePersists`가 통과한다.
  - [ ] `SettingsTests.testLogoutClearsSessionAndReturnsToLogin`가 통과한다.
  - [ ] `SettingsTests.testLaunchAtLoginToggleCallsService`가 통과한다.

  **QA Scenarios**:
  ```
  Scenario: 설정 happy path
    Tool: computer use
    Steps: 상단바 팝오버 열기 -> 설정 섹션 열기 -> 표시명 변경 -> 팝오버 닫기 -> 다시 열기
    Expected: 변경한 표시명이 유지된다.
    Evidence: .omo/evidence/task-11-settings.png

  Scenario: 로그아웃 edge
    Tool: computer use
    Steps: 상단바 팝오버 설정 섹션 열기 -> 로그아웃 클릭
    Expected: 세션이 사라지고 팝오버가 로그인 상태로 돌아간다.
    Evidence: .omo/evidence/task-11-logout.png
  ```

  **Commit**: YES | Message: `feat(settings): add small-team app settings` | Files: `check/`, `checkTests/`

- [ ] 12. 팀원 직접 설치용 빌드 패키징과 개인정보 권한 점검 자동화

  **What to do**: `scripts/build-local.sh`, `scripts/package-local.sh`, `scripts/qa-permissions.sh`를 추가한다. 빌드 스크립트는 Release `check.app`을 만들고 결과 경로를 출력한다. 패키징 스크립트는 팀원에게 전달 가능한 `dist/check.zip`을 만들고, 선택적으로 로컬 환경에 `create-dmg`가 있으면 `dist/check.dmg`도 만든다. 권한 점검은 entitlements와 `Info.plist`를 검사해 금지 권한 문구가 없는지 확인한다. Developer ID signing/notarization은 문서화만 하고 MVP 필수 자동화로 만들지 않는다.
  **Must NOT do**: Mac App Store 배포, 자동 업데이트 프레임워크, notarization CI를 MVP 필수로 만들지 않는다.

  **Parallelization**: Can Parallel: YES | Wave 4 | Blocks: final | Blocked By: 1,3

  **References**:
  - External: `https://developer.apple.com/documentation/xcode/notarizing-macos-software-before-distribution`
  - Guardrail: MVP에서 Screen Recording, Camera, Microphone, Location, Accessibility 권한 없음

  **Acceptance Criteria**:
  - [ ] `./scripts/build-local.sh`가 0으로 종료하고 `check.app` 경로를 출력한다.
  - [ ] `./scripts/package-local.sh`가 0으로 종료하고 `dist/check.zip` 경로를 출력한다.
  - [ ] `./scripts/qa-permissions.sh`가 0으로 종료한다.
  - [ ] entitlements에 App Sandbox 외 불필요한 민감 권한이 없다.
  - [ ] `README.md`에 팀원이 zip/dmg를 받아 설치하는 방법이 한글로 적혀 있다.

  **QA Scenarios**:
  ```
  Scenario: 로컬 빌드 happy path
    Tool: bash
    Steps: `./scripts/build-local.sh | tee .omo/evidence/task-12-build.txt`
    Expected: `check.app` 경로가 출력되고 파일이 존재한다.
    Evidence: .omo/evidence/task-12-build.txt

  Scenario: 팀원 설치 패키지 happy path
    Tool: bash
    Steps: `./scripts/package-local.sh | tee .omo/evidence/task-12-package.txt`
    Expected: `dist/check.zip`이 생성되고 압축을 풀면 `check.app`이 있다.
    Evidence: .omo/evidence/task-12-package.txt

  Scenario: 권한 회귀 edge
    Tool: bash
    Steps: `./scripts/qa-permissions.sh | tee .omo/evidence/task-12-permissions.txt`
    Expected: Accessibility, Screen Recording, Camera, Microphone, Location 권한 요청이 없다고 출력된다.
    Evidence: .omo/evidence/task-12-permissions.txt
  ```

  **Commit**: YES | Message: `build(app): add local packaging and permission checks` | Files: `scripts/`, `README.md`, app entitlements

## Final Verification Wave (MANDATORY - after ALL implementation tasks)
> ALL must APPROVE. 결과를 사용자에게 한글로 요약하고 명시적 확인을 받기 전에는 완료 처리하지 않는다.
- [ ] F1. Plan Compliance Audit
  - `rg -n "Slack|Calendar|스크린샷 모니터링|생산성 점수|HR|급여|메인 앱 창|대시보드" check README.md docs supabase scripts`로 제외 범위가 구현되지 않았음을 확인한다.
  - 모든 TODO의 Acceptance Criteria와 QA evidence 파일이 존재하는지 확인한다.
- [ ] F2. Code Quality Review
  - `xcodebuild test -scheme check -destination 'platform=macOS'` 실행
  - `supabase db reset` 실행
  - SQL/RLS 테스트 실행
  - Swift 파일별 LSP/diagnostics 확인
- [ ] F3. Real Manual QA
  - 컴퓨터 사용 채널로 앱을 실제 실행한다.
  - 테스트 사용자 2명으로 상단바 팝오버에서 로그인/팀 가입/타이머 시작/팀원 상태 확인/타이머 정지 시나리오를 수행한다.
  - 시작 전후 상단바 텍스트가 `○ 종료`, `● HH:MM`, `! 대기` 규칙을 따르는지 확인한다.
  - 스크린샷과 실행 로그를 `.omo/evidence/final-manual-qa.*`에 저장한다.
- [ ] F4. Scope Fidelity Check
  - 앱이 접근성/화면녹화/카메라/마이크/위치 권한을 요청하지 않는지 확인한다.
  - 앱 실행 시 별도 메인 앱 창이 열리지 않는지 확인한다.
  - 오늘 누적 근무시간과 현재 상태가 DB와 UI에서 일치하는지 확인한다.

## Commit Strategy
- 각 TODO는 계획에 적힌 Conventional Commit 메시지로 독립 커밋한다.
- 자동 커밋은 하지 않는다. 구현 에이전트는 커밋 전 변경 파일과 테스트 결과를 사용자에게 보고한다.
- 커밋마다 해당 작업의 테스트와 QA evidence가 있어야 한다.

## Success Criteria
- 소규모 팀원이 상단바 유틸리티를 실행하고 팝오버에서 이메일로 로그인할 수 있다.
- 첫 사용자가 팝오버에서 팀을 만들고 초대코드를 볼 수 있다.
- 다른 사용자가 팝오버에서 초대코드로 같은 팀에 가입할 수 있다.
- 사용자가 상단바 팝오버에서 근무 타이머를 시작하면 상단바에 `● HH:MM` 형식이 보이고 팀원 목록에 `근무중`으로 보인다.
- 사용자가 타이머를 정지하면 오늘 누적 근무시간이 증가하고 상태가 `근무종료`로 보인다.
- 앱은 별도 메인 앱 창 없이 상단바 항목과 팝오버로 핵심 흐름을 제공한다.
- `dist/check.zip` 또는 `dist/check.dmg`를 팀원에게 전달해 직접 설치할 수 있다.
- 앱 재실행 후 진행 중 타이머가 복구된다.
- 네트워크 장애 후 동기화 대기 상태와 재시도 동작이 검증된다.
- 앱은 자동 감시성 권한을 요청하지 않는다.
- 계획, 문서, UI 문구는 한글 리뷰가 가능하게 작성된다.
