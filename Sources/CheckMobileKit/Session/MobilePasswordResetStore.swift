import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 폰 비밀번호 재설정(w16 · SPEC 작업 B) — 코어의 3단(`sendPasswordResetCode` → `verifyPasswordResetCode`(6자리) → `updatePassword`)을
/// 맥 `WorkTimerStoreAuth` "비밀번호 재설정(메일 OTP)" 절과 **같은 규칙**으로 돈다: 형식 검증·쿨다운은 왕복 전에, 코드 화면과
/// 새 비밀번호 화면은 따로(코드가 틀렸을 때 새 비밀번호까지 같이 날아가지 않게), 세대로 늦은 응답을 버린다.
///
/// 맥과 다른 한 곳 — **성공하면 그대로 로그인 상태로 이어 붙인다**(SPEC). verify 가 준 recovery 세션은 일반 로그인과 같은 JWT 라
/// (`updatePassword` 주석) 비밀번호가 선 뒤 `adoptSignedInSession` 으로 로그인 성공과 같은 길을 탄다. 맥이 자동 로그인을 뺀 이유
/// (사용자가 새 비밀번호를 직접 쳐 보게)는 맥 화면의 결정이고, 폰은 맥이 없는 사용자가 앱 안에서 끝내야 한다.
///
/// **계정 유무를 흘리지 않는다**: recover 는 없는 주소에도 200 을 주므로(`sendPasswordResetCode` 주석) 발송 성공/실패 문구는
/// 맥 상수 그대로 "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요"다 — "가입되지 않은 이메일" 류의 문구는 없다.
@MainActor
@Observable
package final class MobilePasswordResetStore {
    package enum Phase: Equatable, Sendable {
        case enterEmail, sending, enterCode, verifying, enterNewPassword, submitting
        /// 비밀번호가 섰고 세션을 이었다(화면은 세션 단계가 바뀌며 사라진다).
        case done
    }

    /// 화면은 3개다(맥 `PasswordResetStep`) — 왕복 중은 직전 입력 화면에 머문다(진행 문구가 뜨는 동안 방금 친 값이 눈앞에 남는다).
    package enum Step: Equatable, Sendable { case email, code, newPassword }

    package var email: String
    package private(set) var phase: Phase = .enterEmail
    package private(set) var message: String?
    /// >0 이면 재발송 잠금 + 남은 초 표시.
    package private(set) var resendSeconds = 0

    @ObservationIgnored private var sendCount = 0
    /// 코드 검증이 준 recovery 세션. **여기서만** 쥐고 영속하지 않는다(맥과 같다). 성공하면 세션 스토어로 넘어가고 여기선 버린다.
    @ObservationIgnored private var verifiedSession: SupabaseSession?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    /// 쿨다운 1초 대기. 테스트가 바꿔 60초를 실제로 자지 않는다(맥 `passwordResetSleep`).
    @ObservationIgnored package var sleep: @Sendable (Int) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }

    @ObservationIgnored private let service: SupabaseWorkService
    @ObservationIgnored private let session: MobileSessionStore
    @ObservationIgnored private let clock: MobileClock

    // 맥 상수 그대로(WorkTimerStoreAuth).
    package nonisolated static let firstResendDelaySeconds = 5
    package nonisolated static let resendCooldownSeconds = 60
    package nonisolated static let minPasswordLength = 6
    package nonisolated static let codeLength = 6

    package init(session: MobileSessionStore, email: String, clock: MobileClock) {
        self.session = session
        self.service = session.service
        self.clock = clock
        self.email = Self.normalizedEmail(email)
    }

    // MARK: - 화면이 읽는 값

    package var step: Step {
        switch phase {
        case .enterCode, .verifying: return .code
        case .enterNewPassword, .submitting, .done: return .newPassword
        case .enterEmail, .sending: return .email
        }
    }

    package var isBusy: Bool { phase == .sending || phase == .verifying || phase == .submitting }

    /// 왕복 중이면 잠그고, 그 밖에는 서버에 보낼 값이 갖춰졌을 때만 연다(빈 요청으로 레이트리밋을 태우지 않는다 — 맥 폼 모델).
    package func isPrimaryEnabled(code: String, newPassword: String) -> Bool {
        guard !isBusy else { return false }
        switch step {
        case .email: return Self.isPlausibleEmail(Self.normalizedEmail(email))
        case .code: return Self.normalizedCode(code).count == Self.codeLength
        case .newPassword: return newPassword.count >= Self.minPasswordLength
        }
    }

    package var isResendEnabled: Bool { !isBusy && resendSeconds <= 0 }
    package var resendTitle: String { resendSeconds > 0 ? "다시 받기 (\(resendSeconds)초)" : "다시 받기" }

    package var primaryTitle: String {
        switch step {
        case .email: return "코드 받기"
        case .code: return "코드 확인"
        case .newPassword: return "비밀번호 바꾸기"
        }
    }

    /// 안내/오류 슬롯 문구. 스토어 문구가 우선이고, 없을 때만 진행 상태를 대신 적는다(비면 화면이 멈춘 것처럼 보인다).
    package var noticeText: String? {
        if let message, !message.isEmpty { return message }
        switch phase {
        case .sending: return "코드 보내는 중"
        case .verifying: return "코드 확인 중"
        case .submitting: return "비밀번호 바꾸는 중"
        default: return nil
        }
    }

    /// 실패가 **아닌** 문구를 열거해 그 밖을 전부 오류로 본다(낱말 추정이 아니라 — 맥 `isInformational` 의 방향).
    package var noticeIsError: Bool {
        guard !isBusy, let text = noticeText else { return false }
        switch text {
        case MobilePasswordResetText.sent, MobilePasswordResetText.alreadySent, MobilePasswordResetText.cooldown:
            return false
        default:
            return true
        }
    }

    // MARK: - 입력 정규화(맥 nonisolated static 그대로)

    package nonisolated static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 이메일 형식의 **최소** 검증 — "@ 도 없는 입력"으로 왕복(과 60초 쿨다운)을 태우지 않기 위한 사전 필터. RFC 를 흉내 내지 않는다.
    package nonisolated static func isPlausibleEmail(_ email: String) -> Bool {
        guard !email.contains(where: { $0.isWhitespace }) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// 메일에서 복사하면 공백·하이픈이 섞여 오므로 ASCII 숫자만 남긴다.
    package nonisolated static func normalizedCode(_ raw: String) -> String {
        String(raw.filter { $0.isASCII && $0.isNumber })
    }

    // MARK: - 코드 발송(1)

    /// enterEmail → sending → enterCode. 형식 검증과 쿨다운은 **왕복 전에** 건다.
    package func requestCode() async {
        let normalized = Self.normalizedEmail(email)
        guard Self.isPlausibleEmail(normalized) else {
            email = normalized
            message = MobilePasswordResetText.invalidEmail
            if phase != .enterCode { phase = .enterEmail }
            return
        }
        // 쿨다운 중이면 서버가 어차피 429 다. 헛왕복은 서버의 카운터만 더 밀어 대기를 늘린다.
        guard resendSeconds <= 0 else {
            message = MobilePasswordResetText.cooldown
            return
        }
        guard !isBusy else { return }
        email = normalized
        message = nil
        phase = .sending
        generation &+= 1
        let generation = generation
        do {
            try await service.sendPasswordResetCode(email: normalized)
            guard generation == self.generation else { return }
            phase = .enterCode
            message = MobilePasswordResetText.sent
            startCooldown(seconds: consumeResendCooldownSeconds())
        } catch {
            guard generation == self.generation else { return }
            if case .cancelled = AuthErrorRules.classify(error) { phase = .enterEmail; return }
            if let serverSeconds = Self.rateLimitSeconds(for: error) {
                // 429 = "방금 이미 보냈다". 코드는 메일함으로 가는 중이므로 입력 화면으로 넘긴다 — 남은 초는 서버가 진실이다.
                phase = .enterCode
                message = MobilePasswordResetText.alreadySent
                consumeResendCooldownSeconds()
                startCooldown(seconds: serverSeconds)
                return
            }
            phase = .enterEmail
            message = sendFailureMessage(for: error)
        }
    }

    /// 첫 발송 뒤 5초(첫 메일이 안 오는 일이 실제로 있어 1분을 붙잡아 두면 할 수 있는 일이 없다), 재전송 뒤 60초. 차수는 여기서만 올린다.
    @discardableResult
    private func consumeResendCooldownSeconds() -> Int {
        let seconds = sendCount == 0 ? Self.firstResendDelaySeconds : Self.resendCooldownSeconds
        sendCount += 1
        return seconds
    }

    /// 남은 초는 **시계 기준 데드라인에서 매번 다시 계산**한다 — 1초씩 빼기만 하면 잠자기·스케줄 지연이 누적 오차가 된다(맥과 같다).
    ///
    /// 쿨다운의 수명은 **Task 취소뿐**이다(`cancel()` · 새 쿨다운 · 비밀번호 성공). 왕복 세대(`generation`)는 보지 않는다 —
    /// 세대는 verify·PUT 도 올리는데(늦은 응답 버리기), 그 세대를 틱마다 견주면 쿨다운이 남은 채 코드를 틀린 순간(재전송 60초 안에
    /// 코드를 치는 게 보통이다) 루프가 `resendSeconds` 를 남긴 채 빠져나가 '다시 받기 (48초)' 가 영영 비활성이 된다(w16 검증 실측).
    /// 맥 `startPasswordResetCooldown` 은 세대를 견준다 — 옮기며 물려받은 결함이라 여기서 끊는다.
    package func startCooldown(seconds: Int) {
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

    // MARK: - 코드 검증(2)

    /// enterCode → verifying → (성공) enterNewPassword. 코드 6자리는 **왕복 전에** 거른다. 실패하면 enterCode 에 머문다.
    package func verifyCode(_ code: String) async {
        let normalizedCode = Self.normalizedCode(code)
        guard normalizedCode.count == Self.codeLength else {
            message = MobilePasswordResetText.invalidCode
            return
        }
        guard !email.isEmpty else {
            phase = .enterEmail
            message = MobilePasswordResetText.invalidEmail
            return
        }
        // 이미 검증을 통과해 세션을 쥐고 있으면 **왕복하지 않고** 다음 화면으로 — OTP 는 1회용이라 다시 보내면 반드시 튕긴다.
        if verifiedSession != nil {
            message = nil
            phase = .enterNewPassword
            return
        }
        guard !isBusy else { return }
        message = nil
        phase = .verifying
        generation &+= 1
        let generation = generation
        let email = email
        do {
            let verified = try await service.verifyPasswordResetCode(email: email, code: normalizedCode)
            guard generation == self.generation else { return }
            verifiedSession = verified
            phase = .enterNewPassword
            message = nil
        } catch {
            guard generation == self.generation else { return }
            phase = .enterCode
            if case .cancelled = AuthErrorRules.classify(error) { return }
            message = verifyFailureMessage(for: error)
        }
    }

    // MARK: - 새 비밀번호(3)

    /// enterNewPassword → submitting → (성공) done + 로그인 상태. 길이는 **왕복 전에** 거른다(그래핌 — 서버보다 엄격한 쪽).
    package func submitNewPassword(_ newPassword: String) async {
        guard newPassword.count >= Self.minPasswordLength else {
            message = MobilePasswordResetText.shortPassword
            return
        }
        guard let verified = verifiedSession else {
            phase = .enterCode
            message = MobilePasswordResetText.codeRejected
            return
        }
        guard !isBusy else { return }
        message = nil
        phase = .submitting
        generation &+= 1
        let generation = generation
        let email = email
        let sessionGeneration = session.generation
        do {
            try await service.updatePassword(accessToken: verified.accessToken, newPassword: newPassword)
        } catch {
            guard generation == self.generation else { return }
            if case .cancelled = AuthErrorRules.classify(error) { phase = .enterNewPassword; return }
            // 붙잡아 둔 세션까지 죽었으면 그 세션으로는 두 번 다시 못 바꾼다 — 버려서 재시도가 코드 검증부터 다시 타게 한다.
            if let serviceError = error as? SupabaseWorkServiceError,
               serviceError == .sessionExpired || serviceError == .otpInvalidOrExpired {
                verifiedSession = nil
                phase = .enterCode
                message = updateFailureMessage(for: error)
                return
            }
            // 그 밖의 거절(6자 미만·이전과 동일·일시 네트워크)은 **비밀번호만** 다시 받으면 되는 일이다 — 세션은 그대로.
            phase = .enterNewPassword
            message = updateFailureMessage(for: error)
            return
        }
        guard generation == self.generation, sessionGeneration == session.generation else { return }
        // 새 비밀번호가 섰다 — recovery 세션은 일반 세션과 같은 JWT 라 로그인 성공과 같은 길로 잇는다(머리 주석).
        verifiedSession = nil
        cooldownTask?.cancel()
        cooldownTask = nil
        resendSeconds = 0
        message = nil
        phase = .done
        if !session.isSignedIn {
            session.adoptSignedInSession(verified, email: email)
        }
    }

    /// 화면을 떠날 때. 세대를 올려 날아가 있는 응답이 상태를 못 쓰게 하고 보관 세션을 버린다(같은 폰을 여럿이 쓰는 상황).
    package func cancel() {
        generation &+= 1
        cooldownTask?.cancel()
        cooldownTask = nil
        verifiedSession = nil
        resendSeconds = 0
        sendCount = 0
        message = nil
        if phase != .done { phase = .enterEmail }
    }

    // MARK: - 오류 → 문구(맥 passwordReset*FailureMessage 그대로)

    /// 레이트리밋이면 **걸어야 할 쿨다운 초**, 아니면 nil. 서버가 초를 안 주면 60(0으로 취급하면 버튼이 바로 열려 429 를 또 맞는다).
    package nonisolated static func rateLimitSeconds(for error: Error) -> Int? {
        guard case .rateLimited(let retryAfterSeconds) = error as? SupabaseWorkServiceError else { return nil }
        return retryAfterSeconds ?? resendCooldownSeconds
    }

    /// 키 부재/스키마처럼 **사용자가 아니라 설치가 잘못된** 경우.
    private func configMessage(for error: Error) -> String? {
        guard let serviceError = error as? SupabaseWorkServiceError else { return nil }
        switch serviceError {
        case .missingAnonKey, .invalidAPIKey, .databaseSchemaMissing:
            return AuthErrorRules.message(for: serviceError, fallback: MobilePasswordResetText.sendFailed)
        default:
            return nil
        }
    }

    private func sendFailureMessage(for error: Error) -> String {
        if let config = configMessage(for: error) { return config }
        if AuthErrorRules.classify(error) == .transient { return MobilePasswordResetText.network }
        return MobilePasswordResetText.sendFailed
    }

    /// 만료와 불일치를 가르지 않는다 — GoTrue 가 둘 다 같은 403 을 주고, 어느 쪽이든 할 일은 '다시 받기'로 같다.
    private func verifyFailureMessage(for error: Error) -> String {
        if let config = configMessage(for: error) { return config }
        if Self.rateLimitSeconds(for: error) != nil { return MobilePasswordResetText.cooldown }
        if AuthErrorRules.classify(error) == .transient { return MobilePasswordResetText.network }
        return MobilePasswordResetText.codeRejected
    }

    private func updateFailureMessage(for error: Error) -> String {
        if let config = configMessage(for: error) { return config }
        if Self.rateLimitSeconds(for: error) != nil { return MobilePasswordResetText.cooldown }
        if AuthErrorRules.classify(error) == .transient { return MobilePasswordResetText.network }
        guard let serviceError = error as? SupabaseWorkServiceError else { return MobilePasswordResetText.updateFailed }
        switch serviceError {
        case .weakPassword, .samePasswordReuse:
            return MobilePasswordResetText.rejectedPassword
        case .sessionExpired, .otpInvalidOrExpired:
            return MobilePasswordResetText.codeRejected
        default:
            return MobilePasswordResetText.updateFailed
        }
    }
}

/// 재설정 화면 문구 — 맥 `WorkTimerStore.passwordReset*Message` **그대로**(문구가 곧 계약: 계정 존재 여부를 흘리지 않는다).
package enum MobilePasswordResetText {
    package static let title = "비밀번호 재설정"
    package static let verifiedTitle = "코드 확인 완료"
    package static let emailHelp = "가입할 때 쓴 이메일로 6자리 코드를 보내 드려요"
    package static let sentTo = "이 주소로 코드를 보냈어요"
    package static let codeLabel = "인증 코드 6자리"
    package static let newPasswordLabel = "새 비밀번호"
    package static let newPasswordHelp = "새 비밀번호를 정해주세요 · 영문/숫자 6자 이상"
    package static let resendPrompt = "코드가 안 왔나요?"

    package static let invalidEmail = "이메일 주소를 확인해주세요"
    package static let sent = "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요"
    package static let alreadySent = "메일을 이미 보냈어요 · 메일함을 확인해주세요"
    package static let cooldown = "조금 뒤에 다시 받을 수 있어요"
    package static let sendFailed = "메일을 보내지 못했어요 · 주소를 확인하고 다시 시도해주세요"
    /// 연결 안내만 폰 공용 문장이다(`MobileLoadText.checkConnection` — 탭마다 갈리지 않게 한 곳, IntegrationFixTests 디자인 계약).
    package static let network = MobileLoadText.checkConnection
    package static let invalidCode = "메일로 받은 6자리 숫자를 입력해주세요"
    package static let shortPassword = "비밀번호 조건 확인 · 6자 이상으로 정해주세요"
    package static let rejectedPassword = "비밀번호 조건 확인 · 6자 이상, 이전과 다른 값으로 정해주세요"
    package static let codeRejected = "코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요"
    package static let updateFailed = "비밀번호를 바꾸지 못했어요 · 다시 시도해주세요"
}
