import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 폰 가입(w16 · SPEC 작업 B). **맥 가입 폼의 규칙을 그대로 옮겼다** — 원본은 `WorkTimerStore.signUp()` ·
/// `WorkTimerStoreAuth.signUp/joinTeamAfterSignup/createTeamAfterSignup/performPreviewTeamCode` · `CheckMenuView.LoginPanel`.
/// 새 규칙을 발명하지 않는다: 입력 셋 필수 → 모드별 팀 칸(코드는 **미리보기 확인 필수**, 만들기는 팀 이름 필수) → 소속 센터
/// **기본 미선택** 필수, 순서까지 같다(같은 입력에 같은 문구가 나와야 두 앱이 갈리지 않는다).
///
/// 흐름: `/auth/v1/signup` → (코드) `join_team` / (만들기) `create_team` → 세션 스토어 `adoptSignedInSession` — 로그인 성공과
/// **같은 길**이다(키체인 · 이메일 기억 · 기기 등록 · 소속 읽기 · 못 한 로그아웃 정리).
///
/// 맥과 다른 한 곳 — **팀이 정해질 때까지 세션을 세션 스토어에 넘기지 않는다.** 맥은 계정을 만들자마자 로그인 상태가 되고 무소속
/// 패널이 뜨는데, 폰의 '지금' 탭은 무소속이면 "팀에 속해 있지 않아요"만 보여 주고 합류 칸이 없다. 그래서 합류 0행(센터 게이트) ·
/// 합류/생성 실패면 이 스토어가 세션을 쥔 채 `.teamless` 로 남아 같은 화면에서 코드를 다시 치거나 팀을 만들게 한다(= 맥 무소속 패널).
/// 앱을 껐다 켜면 계정은 이미 있으므로 로그인으로 들어오면 된다.
///
/// 버튼 비활성(`canSubmit`)과 제출 가드(`submit()` 의 nil)는 **둘 다** 둔다 — 맥과 같은 이유로, 키보드 제출 경로가 따로 있고
/// 비활성만 두면 왜 막혔는지 말할 기회가 없다(`CheckMenuView.submitPrimary` 주석).
@MainActor
@Observable
package final class MobileSignUpStore {
    package enum Stage: Equatable, Sendable {
        /// 계정 칸 + 팀 칸(맥 가입 폼).
        case account
        /// 계정은 만들어졌는데 팀이 없다(합류 0행 = 센터 게이트 · 합류/생성 실패). 팀 칸만 남긴다(맥 무소속 패널과 같은 뜻).
        case teamless
        /// 팀을 만들었다 — 참여코드 카드(맥 `CreatedTeamCodeCard`). [시작하기]가 세션을 잇는다.
        case createdTeam(code: String)
    }

    package var displayName = ""
    package var email = ""
    package var password = ""
    /// 소속 센터의 **서버값**(`CenterLabel.seoul`/`busan`). **nil = 미선택이 기본이다** — 맥 `signupCenter` 와 같은 이유:
    /// 기본을 서울로 두면 부산 연수생이 아무것도 안 하고 서울로 잡히고, 본인은 고르지 않았다는 사실조차 모른다.
    package var center: String?
    /// 코드 입력 ↔ 팀 만들기. 가입은 항상 코드 입력으로 시작한다(맥 `switchMode` 와 같다 — 데모 스크린샷만 만들기로 시작).
    package var isCreateTeamMode: Bool
    package var teamCode = ""
    /// 미리보기 결과(nil = 미확인/불일치). 코드 모드 가입은 이것이 있어야 시작된다.
    package var joinPreview: TeamJoinPreview?
    package var joinPreviewMessage = ""
    package var createTeamName = ""
    package var createTeamGoalHours = MobileSignUpStore.defaultGoalHours
    /// 화면 한 줄(거절 이유 · 실패 원인). 미리보기 문구는 `joinPreviewMessage` 로 따로 간다(코드 칸 바로 아래).
    package private(set) var notice: String?
    package private(set) var isSubmitting = false
    package private(set) var stage: Stage = .account
    /// 계정을 만들어 받은 세션. 팀이 정해질 때까지 **여기서만** 쥔다(머리 주석). 테스트가 읽는다.
    @ObservationIgnored package private(set) var createdSession: SupabaseSession?
    @ObservationIgnored private var createdEmail = ""
    /// 코드 미리보기 재입력 경합 방지(마지막 요청 우선). 세션과 무관 — 비로그인에서 쓴다.
    @ObservationIgnored private var previewGeneration = 0

    @ObservationIgnored private let service: SupabaseWorkService
    @ObservationIgnored private let session: MobileSessionStore

    /// 맥 `createTeamGoalHours` 기본값 · `WeeklyGoalStepper` 범위와 같다.
    package nonisolated static let defaultGoalHours = 60
    package nonisolated static let goalHoursRange = 1...168

    package init(session: MobileSessionStore, createTeam: Bool = false) {
        self.session = session
        self.service = session.service
        self.isCreateTeamMode = createTeam
        // 로그인 칸에 남아 있던 주소를 미리 채운다(가입하러 온 사람이 방금 로그인에 실패한 그 주소가 거의 항상 정답이다).
        if let stored = session.storedEmail { email = stored }
    }

    // MARK: - 화면이 읽는 값

    /// 주 버튼을 **켜 둘** 수 있는가. 판정 자체는 `submit()` 의 가드에 있다(맥 `canSubmitSignUp`: 키 + 센터 선택).
    package var canSubmit: Bool {
        guard !isSubmitting else { return false }
        switch stage {
        case .account: return center != nil
        case .teamless, .createdTeam: return true
        }
    }

    package var primaryTitle: String {
        switch stage {
        case .createdTeam: return MobileSignUpText.start
        case .account: return isCreateTeamMode ? MobileSignUpText.createAndStart : MobileSignUpText.signUp
        case .teamless: return isCreateTeamMode ? MobileSignUpText.createAndStart : MobileSignUpText.join
        }
    }

    /// 머리 부제(맥 `LoginPanel.subtitle` · `TeamlessPanel` 의 BrandHeader 부제).
    package var headline: String {
        switch stage {
        case .account: return isCreateTeamMode ? MobileSignUpText.subtitleCreate : MobileSignUpText.subtitleJoin
        case .teamless: return isCreateTeamMode ? MobileSignUpText.subtitleCreate : MobileSignUpText.subtitleTeamless
        case .createdTeam: return MobileSignUpText.createdTitle
        }
    }

    /// 코드 칸 아래 한 줄: 찾은 팀 요약(초록) · 안내/실패(빨강) · 확인 중. 없으면 nil.
    package var previewLine: (text: String, isSuccess: Bool)? {
        if let joinPreview { return (MobileSignUpText.previewLine(joinPreview), true) }
        if !joinPreviewMessage.isEmpty { return (joinPreviewMessage, false) }
        return nil
    }

    // MARK: - 팀 코드 미리보기(맥 previewTeamCode/performPreviewTeamCode)

    /// 디바운스는 화면 몫이고 여기선 재입력 경합만 막는다(마지막 요청 우선). 테스트가 기다릴 수 있게 Task 를 돌려준다.
    @discardableResult
    package func previewTeamCode() -> Task<Void, Never> {
        previewGeneration &+= 1
        return Task { await performPreviewTeamCode() }
    }

    package func performPreviewTeamCode() async {
        let generation = previewGeneration
        let code = teamCode
        let normalized = SupabaseWorkService.normalizeInviteCode(code)
        guard !normalized.isEmpty else {
            joinPreview = nil
            joinPreviewMessage = ""
            return
        }
        joinPreviewMessage = MobileSignUpText.previewChecking
        do {
            let preview = try await service.lookupTeamByCode(code: code)
            guard generation == previewGeneration else { return }
            if let preview {
                joinPreview = preview
                joinPreviewMessage = ""
            } else {
                joinPreview = nil
                joinPreviewMessage = MobileSignUpText.previewMiss
            }
        } catch {
            guard generation == previewGeneration else { return }
            joinPreview = nil
            joinPreviewMessage = MobileSignUpText.previewMiss
        }
    }

    /// 코드 입력 ↔ 팀 만들기 전환. 이전 코드 미리보기 잔상을 지워 혼동을 막는다(맥 `toggleCreateTeamMode`).
    package func toggleCreateTeamMode() {
        isCreateTeamMode.toggle()
        joinPreview = nil
        joinPreviewMessage = ""
        notice = nil
    }

    // MARK: - 제출(맥 signUp() 의 가드 순서 그대로)

    /// 가드에 걸리면 **문구를 세우고 nil**(맥과 같은 계약 — 화면은 이 값을 보지 않고 부른다, 막는 일은 여기서만).
    @discardableResult
    package func submit() -> Task<Void, Never>? {
        guard !isSubmitting else { return nil }
        switch stage {
        case .createdTeam:
            guard let created = createdSession else { return nil }
            adopt(created, email: createdEmail)
            return Task {}
        case .account:
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEmail.isEmpty, !password.isEmpty, !trimmedDisplayName.isEmpty else {
                notice = MobileSignUpText.missingFields
                return nil
            }
            guard teamFieldsAreReady() else { return nil }
            // 센터 미선택은 여기서도 막는다. 버튼은 비활성이지만 **키보드 제출 경로가 따로 있고**,
            // 그 길로 새면 서버가 center 없이 계정을 만들어 영영 미지정인 사람이 생긴다(맥 signUp() 주석).
            guard let center else {
                notice = MobileSignUpText.centerRequired
                return nil
            }
            notice = nil
            isSubmitting = true
            let password = password
            return Task {
                await self.performSignUp(email: trimmedEmail, password: password, displayName: trimmedDisplayName, center: center)
            }
        case .teamless:
            guard teamFieldsAreReady() else { return nil }
            guard let created = createdSession else {
                // 있을 수 없는 상태(세션 없이 teamless) — 계정 칸으로 되돌린다.
                stage = .account
                return nil
            }
            notice = nil
            isSubmitting = true
            let email = createdEmail
            return Task {
                await self.performTeamStep(session: created, email: email)
                self.isSubmitting = false
            }
        }
    }

    /// 코드 모드: 미리보기가 확인되어야(joinPreview != nil) 가입 가능. 만들기 모드: 팀 이름 필수. (맥 signUp())
    private func teamFieldsAreReady() -> Bool {
        if isCreateTeamMode {
            guard !createTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notice = MobileSignUpText.teamNameRequired
                return false
            }
        } else {
            guard joinPreview != nil else {
                notice = MobileSignUpText.codeUnverified
                return false
            }
        }
        return true
    }

    private func performSignUp(email: String, password: String, displayName: String, center: String) async {
        defer { isSubmitting = false }
        do {
            guard let created = try await service.signUp(email: email, password: password, displayName: displayName, center: center) else {
                // 세션 없이 200 = 확인 메일이 필요한 서버 설정(맥 "확인 메일 필요"). 비밀번호는 비운다(맥과 같다).
                self.password = ""
                notice = MobileSignUpText.confirmEmail
                return
            }
            createdSession = created
            createdEmail = email
            self.password = ""
            await performTeamStep(session: created, email: email)
        } catch {
            switch AuthErrorRules.classify(error) {
            case .cancelled:
                return
            case .transient:
                notice = MobileSessionText.network
            case .fatal:
                notice = AuthErrorRules.message(for: error, fallback: MobileSignUpText.signUpFailed)
            }
        }
    }

    /// 계정이 있는 상태에서 팀을 정한다(맥 `joinTeamAfterSignup` / `createTeamAfterSignup`). 실패는 `.teamless` 로 남긴다.
    private func performTeamStep(session created: SupabaseSession, email: String) async {
        if isCreateTeamMode {
            let name = createTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            let goal = createTeamGoalHours
            do {
                let team = try await service.createTeam(accessToken: created.accessToken, name: name, goalHours: goal)
                notice = nil
                stage = .createdTeam(code: team.inviteCode)
            } catch {
                stage = .teamless
                notice = failureMessage(error, fallback: MobileSignUpText.createTeamFailed)
            }
            return
        }
        let code = teamCode
        do {
            let joined = try await service.joinTeam(accessToken: created.accessToken, code: code)
            guard joined != nil else {
                // ★ **여기까지 왔으면 코드는 맞았다** — 미리보기(`lookup_team_by_code`)가 팀을 찾아 `joinPreview` 를 세웠다.
                //   그런데도 서버가 0행을 냈다면 남은 이유는 하나다: **다른 센터 팀**이다(`join_team` 의 센터 게이트,
                //   20260912185423_join_team_center_gate.sql — 둘 다 알 때만 막고, 0행은 코드 불일치와 같은 모양이다).
                //   "코드를 확인해 주세요"라고 말하면 사용자는 멀쩡한 코드를 몇 번이고 다시 친다(맥 performJoinTeamWithCode 주석).
                stage = .teamless
                joinPreviewMessage = MobileSignUpText.teamlessJoinBlocked
                return
            }
            adopt(created, email: email)
        } catch {
            stage = .teamless
            notice = failureMessage(error, fallback: MobileSignUpText.joinFailed)
        }
    }

    private func failureMessage(_ error: Error, fallback: String) -> String? {
        switch AuthErrorRules.classify(error) {
        case .cancelled: return nil
        case .transient: return MobileSessionText.network
        case .fatal: return AuthErrorRules.message(for: error, fallback: fallback)
        }
    }

    /// 로그인 성공과 같은 길(세션 스토어 `adoptSignedInSession`). 이미 다른 세션이 들어와 있으면(있을 수 없지만) 덮지 않는다.
    private func adopt(_ created: SupabaseSession, email: String) {
        guard !session.isSignedIn else { return }
        session.adoptSignedInSession(created, email: email)
        createdSession = nil
        notice = nil
    }
}

/// 가입 화면 문구. 맥과 뜻이 같은 가드 문구는 **맥 문장 그대로**(`WorkTimerStore.signUp()` · `WorkTimerStoreAuth`) —
/// 같은 입력에 두 앱이 다른 말을 하면 팀 안내 문서(docs/team-install.md)가 한쪽에서 틀린다.
package enum MobileSignUpText {
    package static let title = "가입하기"
    package static let subtitleJoin = "팀 코드로 합류해요"
    package static let subtitleCreate = "새 팀을 만들어요"
    package static let subtitleTeamless = "합류할 팀을 찾아요"
    package static let createdTitle = "팀이 만들어졌어요"
    package static let createdBody = "팀원에게 이 코드를 전달하세요"
    package static let accountCreatedNotice = "계정은 만들어졌어요 · 합류할 팀을 정해 주세요"

    package static let signUp = "가입"
    package static let createAndStart = "팀 만들고 시작하기"
    package static let join = "참여하기"
    package static let start = "시작하기"
    package static let copy = "복사"
    package static let copied = "복사됨"
    package static let noCodePrompt = "팀 코드가 없나요?"
    package static let switchToCreate = "새 팀 만들기"
    package static let switchToCode = "코드로 참여하기"

    package static let displayName = "별명"
    package static let email = "이메일"
    package static let password = "비밀번호"
    package static let centerLabel = "소속 센터"
    package static let teamCode = "팀 코드"
    package static let teamName = "팀 이름"
    package static let weeklyGoal = "주간 목표"

    // 가드 문구(맥 `signUp()` 순서: 입력 셋 → 팀 칸 → 센터).
    package static let missingFields = "별명, 이메일, 비밀번호를 모두 입력해 주세요"
    package static let teamNameRequired = "팀 이름을 입력해 주세요"
    package static let codeUnverified = "팀 코드를 확인해 주세요"
    package static let centerRequired = "소속 센터를 골라 주세요"
    // 미리보기(맥 performPreviewTeamCode).
    package static let previewChecking = "확인 중"
    package static let previewMiss = "코드를 확인해 주세요"
    /// 코드는 맞았는데 합류가 0행일 때 — 맥 `teamlessJoinBlockedMessage` 와 같은 문장(서버 근거는 `join_team` 의 센터 게이트).
    package static let teamlessJoinBlocked = "다른 센터 팀이에요 — 같은 센터 코드인지 확인해 주세요"
    /// 세션 없이 200(확인 메일이 필요한 서버 설정 — 맥 "확인 메일 필요").
    package static let confirmEmail = "확인 메일을 보냈어요 · 메일의 링크를 누른 뒤 로그인해 주세요"
    // 실패 폴백(맥 authMessage(for:fallback:) 의 fallback 그대로).
    package static let signUpFailed = "계정 생성 실패"
    package static let createTeamFailed = "팀 생성 실패"
    package static let joinFailed = "합류 실패"

    /// 맥 `TeamCodePreviewSlot` 과 같은 요약.
    package static func previewLine(_ preview: TeamJoinPreview) -> String {
        "팀 \(preview.name) · \(preview.memberCount)명 · 주 \(preview.weeklyGoalHours)시간"
    }

    package static func goalHours(_ hours: Int) -> String { "\(hours)시간" }
}
