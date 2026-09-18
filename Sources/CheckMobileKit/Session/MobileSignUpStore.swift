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
///
/// ## 가입 이메일 인증코드(w16 · SPEC-signup-otp 작업 P — 맥 `WorkTimerStoreSignUpOTP` 와 같은 규칙)
///
/// **두 서버 모드를 다 견딘다.** 클라이언트는 서버 설정(`enable_confirmations`)을 켜기 전에 먼저 배포되므로 분기는 하나뿐이다:
/// `signUp` 응답에 세션이 **있으면**(지금 서버) 예전과 한 글자도 다르지 않게 곧장 팀 합류/만들기로 가고, **없으면**(설정을 켠 뒤)
/// 코드 화면으로 간다. 서버 상태를 따로 묻지 않는다 — `signUp` 이 주는 nil 이 유일한 신호다.
///
/// 세션이 생긴 뒤의 마무리는 **어느 갈래든 같은 함수**(`continueAfterSession`)다. 두 벌로 갈라지면 한쪽만 고쳐지는 날이 온다.
///
/// 실측한 서버 응답(2026-09-18 프로덕션에서 설정을 잠깐 켜고 직접 찍은 것)이 이 스토어의 갈래를 정한다:
/// - 이미 인증된 이메일로 가입하면 422 가 아니라 `identities: []` 인 **가짜 사용자**가 200 으로 온다 → 코어가
///   `.emailAlreadyRegistered` 로 던진다(세션 없음을 코드 화면으로 오해하면 영영 오지 않을 메일을 기다린다).
/// - 짧은 간격 재시도는 429 `over_email_send_rate_limit` — **오류가 아니라 "몇 초 뒤 다시"**다.
/// - 틀린 코드와 만료가 똑같이 403 `otp_expired` → 문구는 하나(재설정과 같은 상수).
/// - **재전송은 앞 코드를 무효화한다** → 재전송 안내가 그 사실을 말한다(`confirmResent`).
/// - `profiles` 행은 인증 전에 이미 있다(가입 트리거) → 인증 뒤에 프로필을 새로 만들지 않는다.
@MainActor
@Observable
package final class MobileSignUpStore {
    package enum Stage: Equatable, Sendable {
        /// 계정 칸 + 팀 칸(맥 가입 폼).
        case account
        /// 계정은 만들어졌는데 **아직 미확인**이다(가입 확인을 켠 서버 · 미확인 계정의 출구). 6자리 코드만 받는다.
        case confirmCode
        /// 계정은 만들어졌는데 팀이 없다(합류 0행 = 센터 게이트 · 합류/생성 실패 · 출구로 들어와 팀 칸이 빈 경우).
        /// 팀 칸만 남긴다(맥 무소속 패널과 같은 뜻).
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
    /// 팀 칸 한 벌(코드 ↔ 만들기 · 미리보기 · 왕복). **'지금' 탭 무소속 카드와 같은 물건**이다(`MobileTeamJoinForm`) —
    /// 아래 프로퍼티들은 그 값을 그대로 지나 보낸다(화면·테스트가 보는 이름은 한 글자도 바뀌지 않는다).
    @ObservationIgnored package let teamForm: MobileTeamJoinForm

    package var isCreateTeamMode: Bool {
        get { teamForm.isCreateTeamMode }
        set { teamForm.isCreateTeamMode = newValue }
    }
    package var teamCode: String {
        get { teamForm.teamCode }
        set { teamForm.teamCode = newValue }
    }
    /// 미리보기 결과(nil = 미확인/불일치). 코드 모드 가입은 이것이 있어야 시작된다.
    package var joinPreview: TeamJoinPreview? {
        get { teamForm.joinPreview }
        set { teamForm.joinPreview = newValue }
    }
    package var joinPreviewMessage: String {
        get { teamForm.joinPreviewMessage }
        set { teamForm.joinPreviewMessage = newValue }
    }
    package var createTeamName: String {
        get { teamForm.createTeamName }
        set { teamForm.createTeamName = newValue }
    }
    package var createTeamGoalHours: Int {
        get { teamForm.createTeamGoalHours }
        set { teamForm.createTeamGoalHours = newValue }
    }
    /// 화면 한 줄(거절 이유 · 실패 원인 · 코드 화면의 안내). 미리보기 문구는 `joinPreviewMessage` 로 따로 간다(코드 칸 바로 아래).
    package private(set) var notice: String?
    package private(set) var isSubmitting = false
    /// 코드 재전송 왕복 중. 주 버튼(`isSubmitting`)과 나눠 둔다 — 재전송 때 주 버튼이 도는 것처럼 보이면 안 된다.
    package private(set) var isResending = false
    package private(set) var stage: Stage = .account
    /// 코드를 보낸 **정규화된** 주소. verify 는 이 문자열을 그대로 써야 한다(서버가 아는 주소와 한 글자라도 다르면 403 이다).
    package private(set) var confirmSentEmail = ""
    /// >0 이면 재전송 잠금 + 남은 초 표시(재설정 화면과 같은 규칙).
    package private(set) var resendSeconds = 0
    /// 계정을 만들어 받은 세션. 팀이 정해질 때까지 **여기서만** 쥔다(머리 주석). 테스트가 읽는다.
    @ObservationIgnored package private(set) var createdSession: SupabaseSession?
    @ObservationIgnored private var createdEmail = ""
    /// 코드 화면의 왕복 세대(늦은 응답 버리기). 미리보기와 따로 센다.
    @ObservationIgnored private var confirmGeneration = 0
    /// 발송 차수 — 0 이면 다음 잠금은 5초, 그 뒤는 60초(재설정 `consumeResendCooldownSeconds` 와 같은 규칙).
    @ObservationIgnored private var confirmSendCount = 0
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    /// 쿨다운 1초 대기. 테스트가 바꿔 60초를 실제로 자지 않는다(재설정 스토어와 같은 주입점).
    @ObservationIgnored package var sleep: @Sendable (Int) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }

    @ObservationIgnored private let service: SupabaseWorkService
    @ObservationIgnored private let session: MobileSessionStore
    @ObservationIgnored private let clock: MobileClock

    /// 맥 `createTeamGoalHours` 기본값 · `WeeklyGoalStepper` 범위와 같다(값의 주인은 팀 칸 한 벌).
    package nonisolated static let defaultGoalHours = MobileTeamJoinForm.defaultGoalHours
    package nonisolated static let goalHoursRange = MobileTeamJoinForm.goalHoursRange

    package init(session: MobileSessionStore, createTeam: Bool = false) {
        self.session = session
        self.service = session.service
        self.clock = session.clock
        self.teamForm = MobileTeamJoinForm(service: session.service, createTeam: createTeam)
        // 로그인 칸에 남아 있던 주소를 미리 채운다(가입하러 온 사람이 방금 로그인에 실패한 그 주소가 거의 항상 정답이다).
        if let stored = session.storedEmail { email = stored }
    }

    // MARK: - 화면이 읽는 값

    /// 주 버튼을 **켜 둘** 수 있는가. 판정 자체는 `submit()` 의 가드에 있다(맥 `canSubmitSignUp`: 키 + 센터 선택).
    /// 코드 화면은 화면이 쥔 코드 6자리가 조건이라 여기서 못 판정한다 — `isPrimaryEnabled(code:)` 가 그 갈래를 덮는다.
    package var canSubmit: Bool {
        guard !isSubmitting, !isResending else { return false }
        switch stage {
        case .account: return center != nil
        case .confirmCode: return false
        case .teamless, .createdTeam: return true
        }
    }

    /// 화면이 부르는 주 버튼 활성 조건. 코드 화면에서만 화면 상태(코드 칸)를 본다 — 나머지는 `canSubmit` 그대로.
    /// 빈 코드로 왕복해 레이트리밋을 태우지 않는다(재설정 `isPrimaryEnabled` 와 같은 이유).
    package func isPrimaryEnabled(code: String) -> Bool {
        guard stage == .confirmCode else { return canSubmit }
        guard !isSubmitting, !isResending else { return false }
        return MobilePasswordResetStore.normalizedCode(code).count == MobilePasswordResetStore.codeLength
    }

    package var primaryTitle: String {
        switch stage {
        case .createdTeam: return MobileSignUpText.start
        case .account: return isCreateTeamMode ? MobileSignUpText.createAndStart : MobileSignUpText.signUp
        case .confirmCode: return MobileSignUpText.verifyCode
        case .teamless: return isCreateTeamMode ? MobileSignUpText.createAndStart : MobileSignUpText.join
        }
    }

    /// 머리 부제(맥 `LoginPanel.subtitle` · `TeamlessPanel` 의 BrandHeader 부제).
    package var headline: String {
        switch stage {
        case .account: return isCreateTeamMode ? MobileSignUpText.subtitleCreate : MobileSignUpText.subtitleJoin
        case .confirmCode: return MobileSignUpText.subtitleConfirm
        case .teamless: return isCreateTeamMode ? MobileSignUpText.subtitleCreate : MobileSignUpText.subtitleTeamless
        case .createdTeam: return MobileSignUpText.createdTitle
        }
    }

    /// 머리 제목. 코드 화면만 다르다(가입 폼과 같은 제목을 달면 왜 코드 칸만 남았는지 알 수 없다).
    package var title: String {
        stage == .confirmCode ? MobileSignUpText.confirmTitle : MobileSignUpText.title
    }

    /// 안내 줄을 **빨갛게** 그릴 것인가. 실패가 **아닌** 문구를 열거해 그 밖을 전부 오류로 본다
    /// (낱말 추정이 아니라 — 재설정 스토어 `noticeIsError` 와 같은 방향).
    package var noticeIsError: Bool {
        guard let notice else { return false }
        if notice.hasPrefix(MobileSignUpText.rateLimitedPrefix) { return false }
        switch notice {
        case MobileSignUpText.confirmSent, MobileSignUpText.confirmResent,
             MobileSignUpText.accountCreatedNotice,
             MobilePasswordResetText.alreadySent, MobilePasswordResetText.cooldown:
            return false
        default:
            return true
        }
    }

    // MARK: - 미확인 계정의 출구(화면이 읽는다)

    /// 지금 안내가 "계정은 이미 있다"는 신호라 [인증 코드 받기] 출구를 달아야 하는가.
    /// **코어 매퍼(`AuthErrorRules`)의 문장을 그대로 읽는다** — 여기 글자를 따로 적으면 매퍼가 바뀌는 날 출구가 조용히 사라진다
    /// (맥 `offersSignUpConfirmationExit` 와 같은 근거).
    /// ★ **"이미 가입된 이메일"에는 달지 않는다**(2026-09-18 배포 전 검토). 그 문구가 뜨는 계정은 인증을 마친 계정이라
    ///   재전송해도 메일이 나가지 않는다 — 화면만 "새 코드를 보냈어요"라고 말하고 사람은 오지 않을 메일을 기다린다.
    ///   미확인 계정은 (가입 확인을 켠 서버에서) 재가입하면 메일이 다시 가고 코드 화면으로 이어지며, 로그인하면
    ///   "이메일 확인 필요"가 떠서 그 문구가 출구를 단다. 맥도 같은 규칙이다(WorkTimerStore.offersSignUpConfirmationExit).
    package nonisolated static func offersConfirmationExit(for message: String) -> Bool {
        message == AuthErrorRules.message(for: SupabaseWorkServiceError.emailNotConfirmed, fallback: "")
    }

    /// 가입 화면(계정 칸)에서 출구를 보일 것인가 — 코드 화면에선 이미 그 안에 있으므로 달지 않는다.
    package var offersConfirmationExit: Bool {
        guard stage == .account, let notice else { return false }
        return Self.offersConfirmationExit(for: notice)
    }

    package var isResendEnabled: Bool { !isSubmitting && !isResending && resendSeconds <= 0 }
    package var resendTitle: String {
        resendSeconds > 0 ? "\(MobileSignUpText.resend) (\(resendSeconds)초)" : MobileSignUpText.resend
    }

    /// 코드 칸 아래 한 줄: 안내/실패·확인 중(문구) · 찾은 팀 요약. 없으면 nil.
    /// **문구가 요약보다 먼저다** — 그 까닭은 `MobileTeamJoinForm.previewLine` 에 있다(w16 검증 결함).
    package var previewLine: (text: String, isSuccess: Bool)? { teamForm.previewLine }

    // MARK: - 팀 코드 미리보기(맥 previewTeamCode/performPreviewTeamCode — 규칙은 `MobileTeamJoinForm`)

    /// 디바운스는 화면 몫이고 여기선 재입력 경합만 막는다(마지막 요청 우선). 테스트가 기다릴 수 있게 Task 를 돌려준다.
    @discardableResult
    package func previewTeamCode() -> Task<Void, Never> { teamForm.previewTeamCode() }

    package func performPreviewTeamCode() async { await teamForm.performPreviewTeamCode() }

    /// 코드 입력 ↔ 팀 만들기 전환. 이전 코드 미리보기 잔상을 지워 혼동을 막는다(맥 `toggleCreateTeamMode`).
    package func toggleCreateTeamMode() {
        teamForm.toggleCreateTeamMode()
        notice = nil
    }

    // MARK: - 제출(맥 signUp() 의 가드 순서 그대로)

    /// 가드에 걸리면 **문구를 세우고 nil**(맥과 같은 계약 — 화면은 이 값을 보지 않고 부른다, 막는 일은 여기서만).
    @discardableResult
    package func submit() -> Task<Void, Never>? {
        guard !isSubmitting, !isResending else { return nil }
        switch stage {
        case .confirmCode:
            // 코드 화면의 주 버튼은 `verifyCode(_:)` 다(코드는 화면이 쥔다 — 스토어에 남기지 않는다, 재설정과 같다).
            // 여기로 새는 길이 있으면 코드 없이 왕복하거나 팀 단계를 건너뛴다.
            return nil
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
        guard let message = teamForm.guardMessage() else { return true }
        notice = message
        return false
    }

    private func performSignUp(email: String, password: String, displayName: String, center: String) async {
        defer { isSubmitting = false }
        do {
            let created = try await service.signUp(email: email, password: password, displayName: displayName, center: center)
            // 어느 갈래든 비밀번호는 비운다(맥과 같다) — 계정은 이미 만들어졌고, 화면에 남길 이유가 없다.
            self.password = ""
            guard let created else {
                // ★ 세션 없이 200 = **가입 확인을 켠 서버**. 여기가 두 서버 모드의 유일한 갈림길이다(머리 주석).
                //   첫 메일은 가입 요청 자체가 보냈으므로 여기서 다시 보내지 않는다 — 코드 화면만 연다.
                //   (이미 인증된 계정의 가짜 사용자 200 은 코어가 `.emailAlreadyRegistered` 로 던져 아래 catch 로 간다.)
                enterConfirmation(email: email, message: MobileSignUpText.confirmSent)
                return
            }
            await continueAfterSession(created, email: email)
        } catch {
            switch AuthErrorRules.classify(error) {
            case .cancelled:
                return
            case .transient:
                // 429 는 오류가 아니라 "몇 초 뒤 다시"다(실측: 짧은 간격 재시도 = over_email_send_rate_limit).
                // 연결 안내로 뭉개면 사용자는 인터넷을 의심하며 같은 버튼을 더 빨리 눌러 대기를 늘린다.
                if let seconds = MobilePasswordResetStore.rateLimitSeconds(for: error) {
                    notice = MobileSignUpText.rateLimited(seconds: seconds)
                    return
                }
                notice = MobileSessionText.network
            case .fatal:
                notice = AuthErrorRules.message(for: error, fallback: MobileSignUpText.signUpFailed)
            }
        }
    }

    /// **세션이 생긴 시점의 유일한 마무리**(즉시 세션이 온 가입 · 코드 확인 뒤 — 두 갈래가 여기서 합류한다).
    ///
    /// 팀 칸이 준비돼 있으면 그대로 팀을 정하고, 비어 있으면(미확인 계정 출구로 들어와 가입 폼을 채운 적이 없는 사람)
    /// 무소속 화면으로 남겨 같은 화면에서 코드를 치거나 팀을 만들게 한다 — 빈 코드로 join_team 을 부르면 0행이 돌아와
    /// "다른 센터 팀이에요"라고 거짓말하게 된다.
    private func continueAfterSession(_ created: SupabaseSession, email: String) async {
        createdSession = created
        createdEmail = email
        guard teamFieldsArePrepared else {
            stage = .teamless
            notice = nil
            return
        }
        await performTeamStep(session: created, email: email)
    }

    /// 팀 단계를 **왕복 없이** 시작할 수 있는가(문구를 세우지 않는 순수 판정 — 가드 문구는 `teamFieldsAreReady()` 몫).
    private var teamFieldsArePrepared: Bool { teamForm.isPrepared }

    /// 계정이 있는 상태에서 팀을 정한다(맥 `joinTeamAfterSignup` / `createTeamAfterSignup`). 실패는 `.teamless` 로 남긴다.
    /// 왕복·문구는 팀 칸 한 벌(`MobileTeamJoinForm`)이 쥐고, 여기서는 **이 화면의 단계**만 정한다.
    private func performTeamStep(session created: SupabaseSession, email: String) async {
        switch await teamForm.performTeamStep(accessToken: created.accessToken) {
        case .settled(.created(_, _, let inviteCode, _)):
            notice = nil
            stage = .createdTeam(code: inviteCode)
        case .settled(.joined):
            adopt(created, email: email)
        case .settled(.blocked):
            // 코드 칸 아래 줄은 폼이 이미 '다른 센터 팀이에요' 로 바꿔 놓았다 — 여기선 무소속으로 남겨 다시 치게 한다.
            stage = .teamless
        case .failed(let message):
            stage = .teamless
            notice = message
        }
    }

    // MARK: - 가입 이메일 인증코드(맥 WorkTimerStoreSignUpOTP 와 같은 규칙 · 재설정 화면의 코드 단계와 같은 문구)

    /// 코드 화면으로 넘어간다. 부르는 쪽이 **직전에 메일이 나갔다**는 것을 알고 있을 때만 쓴다(가입 요청 · 재전송 성공).
    /// 첫 잠금은 재설정과 같은 5초다 — 첫 메일이 실제로 안 오는 일이 있어 1분을 붙잡아 두면 할 수 있는 일이 없고,
    /// 서버 간격(60초)에 걸리면 429 가 주는 남은 초로 덮인다(`performResend`).
    private func enterConfirmation(email: String, message: String) {
        confirmSentEmail = MobilePasswordResetStore.normalizedEmail(email)
        createdEmail = confirmSentEmail
        stage = .confirmCode
        notice = message
        startCooldown(seconds: consumeResendCooldownSeconds())
    }

    /// 미확인 계정의 **출구**. 로그인 화면의 "이메일 확인 필요" · 가입 화면의 "이미 가입된 이메일"에서 온다.
    /// 계정은 이미 있으므로 이 흐름의 첫 발송은 **재전송**이다 — 보내고 나서 코드 화면에 선다.
    ///
    /// 주소가 형식에 안 맞으면 코드 화면을 열지 않는다(코드 화면엔 주소 칸이 없어 고칠 방법이 없다 — 맥과 같은 이유).
    package func beginConfirmation(email raw: String) async {
        let normalized = MobilePasswordResetStore.normalizedEmail(raw)
        guard MobilePasswordResetStore.isPlausibleEmail(normalized) else {
            notice = MobilePasswordResetText.invalidEmail
            return
        }
        cancelPendingWork()
        confirmSendCount = 0
        resendSeconds = 0
        confirmSentEmail = normalized
        createdEmail = normalized
        email = normalized
        stage = .confirmCode
        notice = nil
        await performResend()
    }

    /// [다시 받기]. 쿨다운은 **왕복 전에** 건다(헛왕복은 서버 카운터만 밀어 대기를 늘린다).
    package func resendCode() async {
        guard stage == .confirmCode, !confirmSentEmail.isEmpty else { return }
        guard !isSubmitting, !isResending else { return }
        guard resendSeconds <= 0 else {
            notice = MobilePasswordResetText.cooldown
            return
        }
        await performResend()
    }

    private func performResend() async {
        let email = confirmSentEmail
        guard !email.isEmpty else { return }
        // 이번 발송이 첫 발송인가(= 출구로 들어와 계정 존재를 모르는 상태인가). 재전송 안내가 갈린다.
        let isFirstSend = confirmSendCount == 0
        notice = nil
        isResending = true
        confirmGeneration &+= 1
        let generation = confirmGeneration
        defer { isResending = false }
        do {
            try await service.resendSignUpCode(email: email)
            guard generation == confirmGeneration else { return }
            // ★ **재전송은 앞 코드를 무효화한다**(실측) — 그걸 말하지 않으면 사용자는 첫 메일의 코드를 계속 넣고
            //   403 만 본다. 첫 발송(출구)에는 앞 코드가 없으므로 같은 말을 하면 안 된다.
            notice = isFirstSend ? MobileSignUpText.confirmSent : MobileSignUpText.confirmResent
            startCooldown(seconds: consumeResendCooldownSeconds())
        } catch {
            guard generation == confirmGeneration else { return }
            if case .cancelled = AuthErrorRules.classify(error) { return }
            // 어느 실패든 코드 화면에 머문다 — 물러날 주소 칸이 없고, 코드가 이미 메일함에 있을 수 있다.
            if let serverSeconds = MobilePasswordResetStore.rateLimitSeconds(for: error) {
                // 429 = 방금 이미 보냈다(가입 요청의 첫 메일이 간격 안이다). 남은 초는 **서버가 진실**이다.
                notice = MobilePasswordResetText.alreadySent
                consumeResendCooldownSeconds()
                startCooldown(seconds: serverSeconds)
                return
            }
            notice = failureMessage(error, fallback: MobileSignUpText.resendFailed)
        }
    }

    /// 방금 끝난 발송 뒤에 걸 쿨다운(초)을 정하고 차수를 한 칸 올린다(재설정 `consumeResendCooldownSeconds` 와 같은 규칙).
    @discardableResult
    private func consumeResendCooldownSeconds() -> Int {
        let seconds = confirmSendCount == 0
            ? MobilePasswordResetStore.firstResendDelaySeconds
            : MobilePasswordResetStore.resendCooldownSeconds
        confirmSendCount += 1
        return seconds
    }

    /// 남은 초는 **시계 기준 데드라인에서 매번 다시 계산**한다(잠자기·스케줄 지연이 누적 오차가 되지 않게 — 재설정과 같다).
    /// 쿨다운의 수명은 **Task 취소뿐**이다: 왕복 세대를 틱마다 견주면 코드를 틀린 순간(재전송 60초 안에 코드를 치는 게 보통이다)
    /// 루프가 남은 초를 남긴 채 빠져나가 [다시 받기 (48초)]가 영영 비활성이 된다(재설정에서 실측한 결함).
    private func startCooldown(seconds: Int) {
        let seconds = min(max(seconds, 1), 600)
        cooldownTask?.cancel()
        resendSeconds = seconds
        let deadline = clock.now().addingTimeInterval(TimeInterval(seconds))
        cooldownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = Int(ceil(deadline.timeIntervalSince(self.clock.now())))
                guard remaining > 0 else {
                    if self.resendSeconds != 0 { self.resendSeconds = 0 }
                    return
                }
                if self.resendSeconds != remaining { self.resendSeconds = remaining }
                let sleep = self.sleep
                await sleep(1)
            }
        }
    }

    /// 6자리 코드 검증 → 세션 → **즉시 세션이 온 가입과 같은 마무리**(`continueAfterSession`).
    /// 6자리 미만은 왕복 전에 거른다. 실패하면 코드 화면에 그대로 머문다([다시 받기]가 거기 있다).
    package func verifyCode(_ code: String) async {
        guard stage == .confirmCode else { return }
        let normalizedCode = MobilePasswordResetStore.normalizedCode(code)
        guard normalizedCode.count == MobilePasswordResetStore.codeLength else {
            notice = MobilePasswordResetText.invalidCode
            return
        }
        let email = confirmSentEmail
        guard !email.isEmpty else {
            // 어느 주소로 보냈는지 모르면 검증할 수 없다(있을 수 없는 상태) — 가입 폼으로 되돌린다.
            stage = .account
            notice = MobilePasswordResetText.invalidEmail
            return
        }
        guard !isSubmitting, !isResending else { return }
        notice = nil
        isSubmitting = true
        confirmGeneration &+= 1
        let generation = confirmGeneration
        defer { isSubmitting = false }
        let verified: SupabaseSession
        do {
            verified = try await service.verifySignUpCode(email: email, code: normalizedCode)
        } catch {
            guard generation == confirmGeneration else { return }
            if case .cancelled = AuthErrorRules.classify(error) { return }
            // 틀린 코드와 만료가 똑같이 403 otp_expired 라 문구는 하나다(실측) — 둘을 가르는 척하면 거짓말이 된다.
            if MobilePasswordResetStore.rateLimitSeconds(for: error) != nil {
                notice = MobilePasswordResetText.cooldown
                return
            }
            notice = AuthErrorRules.classify(error) == .transient
                ? MobileSessionText.network
                : MobilePasswordResetText.codeRejected
            return
        }
        // 화면을 떠났거나(그 사람을 로그인시키면 안 된다) 그 사이 다른 로그인이 있었으면 이 세션은 버린다.
        guard generation == confirmGeneration, !session.isSignedIn else { return }
        cooldownTask?.cancel()
        cooldownTask = nil
        resendSeconds = 0
        confirmSentEmail = ""
        confirmSendCount = 0
        notice = nil
        // 여기부터는 즉시 세션이 온 가입과 한 줄도 다르지 않다 — 팀 합류/만들기가 그 함수 안이다.
        await continueAfterSession(verified, email: email)
    }

    /// 화면을 떠날 때. **상태(만들어진 계정 · 단계)는 그대로 두고** 날아가 있는 왕복과 카운트다운만 끊는다 —
    /// 서버의 계정은 미확인으로 남고, 다음에 로그인/가입을 시도하면 그 문구의 출구가 다시 코드 화면으로 데려온다.
    package func cancelPendingWork() {
        confirmGeneration &+= 1
        teamForm.cancelPendingPreview()
        cooldownTask?.cancel()
        cooldownTask = nil
    }

    private func failureMessage(_ error: Error, fallback: String) -> String? {
        MobileTeamJoinForm.failureMessage(error, fallback: fallback)
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
    package static let confirmTitle = "이메일 인증"
    package static let subtitleConfirm = "메일로 받은 6자리 코드를 넣어 주세요"
    package static let createdTitle = "팀이 만들어졌어요"
    package static let createdBody = "팀원에게 이 코드를 전달하세요"
    package static let accountCreatedNotice = "계정은 만들어졌어요 · 합류할 팀을 정해 주세요"

    // 약관 동의 한 줄(앱스토어 심사 지침 1.2 — 사용자 생성 콘텐츠 앱은 약관에 동의를 받고, 그 약관에 무관용 규칙이 있어야 한다).
    // 체크박스가 아니라 **버튼 아래 한 줄**인 이유: 가입 버튼을 누르는 것이 곧 동의라고 적는 방식(애플이 널리 받아들이는 형태)이고,
    // 체크박스 하나가 더 늘면 가입 이탈만 는다. 두 링크는 실제로 열리는 페이지여야 한다(GitHub Pages — docs/terms.md · docs/privacy.md).
    package static let termsAgreement = "가입하면 이용약관과 개인정보 처리방침에 동의하는 것으로 봅니다"
    package static let termsLink = "이용약관"
    package static let privacyLink = "개인정보 처리방침"
    package static let termsURL = URL(string: "https://yehsung.github.io/check/terms")!
    /// 나 → 설정의 처리방침 링크와 **같은 주소**여야 한다(`MeText.privacyPolicyURL`).
    package static let privacyURL = URL(string: "https://yehsung.github.io/check/privacy")!

    /// 위 한 줄에 두 링크를 심은 것(화면이 그대로 그린다). 링크는 **글자 안**에 있다 — 줄 밑에 버튼 두 개를 따로 두면
    /// 가입 버튼 아래에 누를 것이 셋이 되어 주 동작이 흐려진다. 순수 값이라 macOS 테스트가 링크 둘을 값으로 잰다.
    package static var termsAgreementAttributed: AttributedString {
        var text = AttributedString(termsAgreement)
        if let range = text.range(of: termsLink) {
            text[range].link = termsURL
            text[range].underlineStyle = .single
        }
        if let range = text.range(of: privacyLink) {
            text[range].link = privacyURL
            text[range].underlineStyle = .single
        }
        return text
    }

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
    // 가입 이메일 인증코드(맥 `WorkTimerStore.signUpConfirm*Message` 와 같은 뜻).
    //
    // 예전엔 세션 없는 200 을 "확인 메일을 보냈어요 · 메일의 링크를 누른 뒤 로그인해 주세요"로 말했다. 그 링크는
    // `check://auth` 로 리다이렉트되는데 그 스킴을 등록한 앱이 없어 **죽은 링크**였다(비밀번호 재설정이 OTP 로 간 이유와 같다).
    /// 코드 화면의 첫 안내. "메일이 안 와요"의 첫 답은 스팸함이다 — 커스텀 SMTP 발신(aing-check)이라 실제로 그리로 간다.
    package static let confirmSent = "인증 코드를 보냈어요 · 안 오면 스팸함을 확인해 주세요"
    /// 재전송 성공. ★ **재전송은 앞 코드를 무효화한다**(실측) — 그 사실을 말하지 않으면 사용자는 첫 메일의 코드를 계속 넣는다.
    package static let confirmResent = "새 코드를 보냈어요 · 앞 코드는 이제 쓸 수 없어요, 마지막 메일의 코드를 넣어 주세요"
    /// 코드 화면에 늘 붙는 도움말. `resend` 는 **이미 인증된 계정에도 빈 200** 이라(GoTrue 가 계정 존재를 흘리지 않는다)
    /// 출구로 들어온 사람이 인증된 계정이면 메일은 영영 오지 않는다 — 그 사람이 할 일은 로그인이다.
    /// 안내 줄(사라지는 문구)이 아니라 **고정 도움말**로 두는 이유: 그 사실은 재전송 결과와 상관없이 늘 참이다.
    package static let confirmHelp = "이미 인증을 마친 계정이면 메일이 오지 않아요 · 그때는 로그인해 주세요"
    /// 미확인 계정의 출구 버튼("이미 가입된 이메일" · "이메일 확인 필요" 아래).
    package static let confirmExit = "인증 코드 받기"
    package static let verifyCode = "코드 확인"
    package static let resend = "다시 받기"
    package static let resendFailed = "코드를 보내지 못했어요 · 잠시 뒤 다시 시도해 주세요"
    /// 429(over_email_send_rate_limit). 오류가 아니라 "몇 초 뒤 다시"다 — 서버가 초를 주면 그 초를 그대로 보여 준다.
    /// 앞머리를 상수로 둔 이유: 안내/오류 색 판정(`noticeIsError`)이 초가 붙은 문장도 안내로 알아봐야 한다.
    package static let rateLimitedPrefix = "조금 뒤에 다시 시도해 주세요"
    package static func rateLimited(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return rateLimitedPrefix }
        return "\(rateLimitedPrefix) (\(seconds)초)"
    }
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
