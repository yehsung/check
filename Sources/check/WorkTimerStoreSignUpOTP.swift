import Foundation
import CheckCore

// MARK: - 가입 이메일 인증(코드)
//
// 흐름: [가입] → (서버가 세션을 안 주면) **코드만** 입력 → verify 로 세션 → 팀 합류/만들기.
//      마지막 단계는 즉시 세션이 온 가입과 **같은 함수**(completeSignUp)다 — 두 경로가 갈리면 한쪽만 고쳐지는 날이 온다.
//
// 화면·문구·오류 재분류는 비밀번호 재설정(WorkTimerStoreAuth.swift "비밀번호 재설정(메일 OTP)")을 그대로 본떴다.
// 코드 화면은 PasswordResetPanel 을 purpose 만 바꿔 빌려 쓰고, 문구는 재설정 상수를 재사용한다(가입에서만 뜻이 다른 두 문장만 새로 둔다).
// 시계·수면 주입(clock · passwordResetSleep)과 카운트다운 루프(runResendCountdown)도 재설정 것 그대로다.
//
// **두 서버 모드**(SPEC-signup-otp): 지금 서버(가입 즉시 세션)에서는 이 파일이 **한 줄도 돌지 않는다** — signUp 의 세션 유무가
// 유일한 분기이고, 서버 설정을 따로 묻지 않는다. 설정을 켠 뒤에는 signUp 이 nil 을 돌려주고 그때만 여기로 온다.
//
// **영영 막히지 않는 출구**: 가입 도중 앱을 닫으면 계정은 만들어졌고 미확인이다. 그 사람이 다시 가입하면 "이미 가입된 이메일",
// 로그인하면 "이메일 확인 필요"가 뜬다 — 두 문구 모두 로그인 카드에 [인증 코드 다시 받기] 출구를 단다(beginSignUpConfirmation:
// 재전송 → 코드 입력). 이 출구가 없으면 그 계정은 운영자가 Admin API 로 풀어 주기 전까지 못 쓴다.
@MainActor
extension WorkTimerStore {
    /// 가입 직후(세션 없음) 코드 화면의 첫 안내. 첫 메일은 **가입 요청 자체**가 보냈다(여기서 다시 보내지 않는다).
    /// "메일이 안 와요"의 첫 답은 스팸함이다 — 커스텀 SMTP 발신(aing-check)이라 첫 메일이 거기로 가는 일이 실제로 있다.
    static let signUpConfirmSentMessage = "가입 확인 코드를 보냈어요 · 안 오면 스팸함을 확인해주세요"
    /// 재전송 성공 안내. **"이미 인증된 계정이면 오지 않는다"를 반드시 말한다** — resend 는 인증된 계정에도 빈 200 이라
    /// (계정 존재를 흘리지 않는 GoTrue), "이미 가입된 이메일" 출구로 들어온 사람이 인증된 계정이면 메일은 영영 안 온다.
    /// 그 사람이 할 일은 로그인이다. 지금 서버(가입 확인 꺼짐)에서는 모든 계정이 그 경우다.
    static let signUpConfirmResentMessage = "코드를 다시 보냈어요 · 이미 인증된 계정이면 메일이 오지 않아요, 로그인해주세요"

    /// 로그인 카드가 [인증 코드 다시 받기] 출구를 달아야 하는 상태줄 문구인가(순수 — 값으로 검증한다).
    /// "이미 가입된 이메일"(가입 재시도) · "이메일 확인 필요"(로그인 시도) · "확인 메일 필요"(코드 화면을 닫고 돌아온 사람).
    /// 앞의 둘은 코어 매퍼(AuthErrorRules)의 문장을 그대로 읽는다 — 여기 글자를 따로 적으면 매퍼가 바뀔 때 출구가 조용히 사라진다.
    nonisolated static func offersSignUpConfirmationExit(for syncMessage: String) -> Bool {
        let alreadyRegistered = AuthErrorRules.message(for: SupabaseWorkServiceError.emailAlreadyRegistered, fallback: "")
        let notConfirmed = AuthErrorRules.message(for: SupabaseWorkServiceError.emailNotConfirmed, fallback: "")
        return syncMessage == alreadyRegistered || syncMessage == notConfirmed || syncMessage == "확인 메일 필요"
    }

    // MARK: 진입/종료

    /// 가입 응답에 세션이 없을 때(가입 확인을 켠 서버) signUp 이 부른다. 첫 메일은 가입 요청이 이미 보냈으므로 여기서는 보내지
    /// 않고 코드 화면만 연다. 첫 잠금은 재설정과 같은 5초다 — 첫 메일이 실제로 안 오는 일이 있어 바로 다시 눌러 볼 수 있어야 하고,
    /// 서버 간격(60초)에 걸리면 429 가 주는 남은 초로 덮인다(performResendSignUpCode).
    func enterSignUpConfirmation(email: String, displayName: String?, center: String?) {
        clearSignUpConfirmState()
        signUpConfirmEmail = Self.normalizedResetEmail(email)
        signUpConfirmDisplayName = displayName
        signUpConfirmCenter = center
        signUpConfirmPhase = .enterCode
        signUpConfirmMessage = Self.signUpConfirmSentMessage
        startSignUpConfirmCooldown(seconds: consumeSignUpConfirmResendCooldownSeconds())
    }

    /// 로그인 카드의 출구([인증 코드 다시 받기]). 계정은 이미 있고(미확인) 이 흐름의 첫 발송은 **재전송**이다 — 보낸 뒤 코드 화면으로.
    /// 별명·센터는 폼에 남은 값이 있으면 쓰고 없으면 모른다(nil) — 가입 때 실어 보낸 값이 서버 정본이라 잃는 것이 없다.
    /// 이메일이 형식에 안 맞으면 코드 화면을 열지 않고 로그인 카드의 상태줄로 말한다(코드 화면엔 주소 칸이 없다).
    func beginSignUpConfirmation(email: String) async {
        let normalized = Self.normalizedResetEmail(email)
        guard Self.isPlausibleResetEmail(normalized) else {
            syncMessage = Self.passwordResetInvalidEmailMessage
            return
        }
        clearSignUpConfirmState()
        signUpConfirmEmail = normalized
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        signUpConfirmDisplayName = name.isEmpty ? nil : name
        signUpConfirmCenter = signupCenter
        await resendSignUpCode()
    }

    /// 어느 단계에서든 idle 로 되돌린다(왕복 중 취소 포함). **서버의 계정은 그대로 미확인으로 남는다** — 다음에 로그인/가입을
    /// 시도하면 로그인 카드의 출구가 다시 코드 화면으로 데려온다.
    func cancelSignUpConfirmation() {
        clearSignUpConfirmState()
    }

    /// 상태 전부를 내리는 **유일한 지점**(재설정의 clearPasswordResetState 와 같은 순서 — 세대를 먼저 올리고, 그다음 Task 를
    /// 취소한다. 뒤집히면 취소와 세대 증가 사이의 틈으로 응답이 들어와 상태를 되살린다).
    private func clearSignUpConfirmState() {
        signUpConfirmGeneration &+= 1
        signUpConfirmTask?.cancel()
        signUpConfirmTask = nil
        signUpConfirmCooldownTask?.cancel()
        signUpConfirmCooldownTask = nil
        signUpConfirmPhase = .idle
        signUpConfirmMessage = nil
        signUpConfirmEmail = ""
        signUpConfirmResendSeconds = 0
        // 발송 차수도 되돌린다(남기면 다음 흐름의 첫 발송이 60초로 잠긴다 — 재설정과 같은 함정).
        signUpConfirmSendCount = 0
        signUpConfirmDisplayName = nil
        signUpConfirmCenter = nil
    }

    // MARK: 재전송

    /// enterCode → resending → enterCode. 쿨다운은 **왕복 전에** 건다(헛왕복은 서버 카운터만 밀어 대기를 늘린다).
    func resendSignUpCode() async {
        let email = signUpConfirmEmail
        guard !email.isEmpty else { return }
        guard signUpConfirmResendSeconds <= 0 else {
            signUpConfirmMessage = Self.passwordResetCooldownMessage
            return
        }
        signUpConfirmMessage = nil
        signUpConfirmPhase = .resending
        signUpConfirmGeneration &+= 1
        let generation = signUpConfirmGeneration
        signUpConfirmTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performResendSignUpCode(email: email, generation: generation)
        }
        signUpConfirmTask = task
        await task.value
        if signUpConfirmTask == task { signUpConfirmTask = nil }
    }

    private func performResendSignUpCode(email: String, generation: Int) async {
        do {
            try await service.resendSignUpCode(email: email)
            guard generation == signUpConfirmGeneration else { return }
            signUpConfirmPhase = .enterCode
            signUpConfirmMessage = Self.signUpConfirmResentMessage
            startSignUpConfirmCooldown(seconds: consumeSignUpConfirmResendCooldownSeconds())
        } catch {
            guard generation == signUpConfirmGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            // 어느 실패든 코드 화면에 머문다 — 재설정과 달리 물러날 이메일 화면이 없고, 코드가 이미 메일함에 있을 수 있다.
            signUpConfirmPhase = .enterCode
            if let serverSeconds = passwordResetRateLimitSeconds(for: error) {
                // 429 = 방금 이미 보냈다(가입 요청의 첫 메일이 60초 안이다). 남은 초는 **서버가 진실**이다(재설정과 같은 근거).
                signUpConfirmMessage = Self.passwordResetAlreadySentMessage
                consumeSignUpConfirmResendCooldownSeconds()
                startSignUpConfirmCooldown(seconds: serverSeconds)
                return
            }
            signUpConfirmMessage = passwordResetSendFailureMessage(for: error)
        }
    }

    /// 방금 끝난 발송 뒤에 걸 쿨다운(초)을 정하고 차수를 한 칸 올린다(재설정의 consumeResendCooldownSeconds 와 같은 규칙).
    @discardableResult
    private func consumeSignUpConfirmResendCooldownSeconds() -> Int {
        let seconds = signUpConfirmSendCount == 0
            ? Self.passwordResetFirstResendDelaySeconds
            : Self.passwordResetResendCooldownSeconds
        signUpConfirmSendCount += 1
        return seconds
    }

    /// 재발송 카운트다운. 루프 본체는 재설정과 공용(runResendCountdown) — 값이 갈 자리와 세대만 여기 것이다.
    func startSignUpConfirmCooldown(seconds: Int) {
        let seconds = min(max(seconds, 1), 600)
        signUpConfirmCooldownTask?.cancel()
        signUpConfirmResendSeconds = seconds
        let deadline = clock().addingTimeInterval(TimeInterval(seconds))
        let generation = signUpConfirmGeneration
        signUpConfirmCooldownTask = runResendCountdown(
            deadline: deadline,
            isCurrent: { [weak self] in self?.signUpConfirmGeneration == generation },
            apply: { [weak self] remaining in
                guard let self, self.signUpConfirmResendSeconds != remaining else { return }
                self.signUpConfirmResendSeconds = remaining
            }
        )
    }

    // MARK: 코드 검증

    /// enterCode → verifying → (성공) idle + completeSignUp. 코드 6자리는 **왕복 전에** 거른다.
    /// 실패하면 enterCode 에 그대로 머문다([다시 받기]가 그 화면에 있다).
    func verifySignUpCode(code: String) async {
        let normalizedCode = Self.normalizedResetCode(code)
        guard normalizedCode.count == Self.passwordResetCodeLength else {
            signUpConfirmMessage = Self.passwordResetInvalidCodeMessage
            return
        }
        let email = signUpConfirmEmail
        guard !email.isEmpty else {
            // 어느 주소로 보냈는지 모르면 검증할 수 없다. 코드 화면엔 주소 칸이 없으므로 로그인 카드로 돌려보낸다 —
            // 거기엔 "확인 메일 필요" 출구가 있어 주소를 다시 적고 코드 화면으로 돌아올 수 있다.
            cancelSignUpConfirmation()
            syncMessage = "확인 메일 필요"
            return
        }
        signUpConfirmMessage = nil
        signUpConfirmPhase = .verifying
        signUpConfirmGeneration &+= 1
        let generation = signUpConfirmGeneration
        signUpConfirmTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performVerifySignUpCode(email: email, code: normalizedCode, generation: generation)
        }
        signUpConfirmTask = task
        await task.value
        if signUpConfirmTask == task { signUpConfirmTask = nil }
    }

    private func performVerifySignUpCode(email: String, code: String, generation: Int) async {
        let sessionGen = sessionGeneration
        let verified: SupabaseSession
        do {
            verified = try await service.verifySignUpCode(email: email, code: code)
        } catch {
            guard generation == signUpConfirmGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            signUpConfirmPhase = .enterCode
            signUpConfirmMessage = passwordResetVerifyFailureMessage(for: error)
            return
        }
        // 두 세대를 다 본다: 흐름이 취소됐거나(사용자가 닫은 화면이 **그 사람을 로그인시키면 안 된다**) 그 사이 다른
        // 로그인/로그아웃이 있었으면 이 세션은 버린다 — 재설정의 늦은 응답 방어와 같은 자리다.
        guard generation == signUpConfirmGeneration, sessionGen == sessionGeneration else { return }
        let displayName = signUpConfirmDisplayName
        let center = signUpConfirmCenter
        // 청소 전에 핸들을 **먼저 뗀다**: 지금 실행 중인 이 Task 가 곧 '날아가 있는 왕복'이라, 떼지 않으면 clear 가 스스로를
        // 취소한다(재설정 성공 경로와 같은 순서).
        signUpConfirmTask = nil
        clearSignUpConfirmState()
        // 여기부터는 즉시 세션이 온 가입과 한 글자도 다르지 않다 — 팀 합류/만들기·폴링 시작 전부 그 함수 안이다.
        await completeSignUp(verified, email: email, displayName: displayName, center: center)
    }
}
