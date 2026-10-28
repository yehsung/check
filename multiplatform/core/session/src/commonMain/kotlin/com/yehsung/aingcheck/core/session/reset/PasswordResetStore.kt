// 원본: Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.reset

import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.sendPasswordResetCode
import com.yehsung.aingcheck.core.net.updatePassword
import com.yehsung.aingcheck.core.net.verifyPasswordResetCode
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.rethrowIfOwnCancellation
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.ceil

/**
 * 비밀번호 재설정(Swift `MobilePasswordResetStore`) — 3단(`sendPasswordResetCode` → `verifyPasswordResetCode`(6자리) → `updatePassword`)을
 * 맥과 **같은 규칙**으로 돈다: 형식 검증·쿨다운은 왕복 전에, 코드 화면과 새 비밀번호 화면은 따로, 세대로 늦은 응답을 버린다.
 *
 * 맥과 다른 한 곳 — **성공하면 그대로 로그인 상태로 이어 붙인다**(recovery 세션은 일반 로그인과 같은 JWT 라 `adoptSignedInSession`).
 * **계정 유무를 흘리지 않는다**: recover 는 없는 주소에도 200 을 주므로 발송 문구는 "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요" 하나다.
 */
class PasswordResetStore(
    private val session: SessionStore,
    email: String,
    /** 새 비밀번호 길이 세기(Swift `String.count` = 확장 그래핌 — K3 GraphemeCounter, 조립 지점이 W1-c 구현을 넣는다). */
    private val graphemes: GraphemeCounter,
    private val clock: SessionClock = session.clock,
) {
    enum class Phase { enterEmail, sending, enterCode, verifying, enterNewPassword, submitting, done }

    /** 화면은 3개다(맥 `PasswordResetStep`) — 왕복 중은 직전 입력 화면에 머문다. */
    enum class Step { email, code, newPassword }

    private val service: SupabaseWorkService = session.service

    val email: MutableStateFlow<String> = MutableStateFlow(normalizedEmail(email))
    private val _phase = MutableStateFlow(Phase.enterEmail)
    private val _message = MutableStateFlow<String?>(null)
    private val _resendSeconds = MutableStateFlow(0)

    val phase: Phase get() = _phase.value
    val phaseFlow: StateFlow<Phase> = _phase.asStateFlow()
    val message: String? get() = _message.value
    val messageFlow: StateFlow<String?> = _message.asStateFlow()

    /** >0 이면 재발송 잠금 + 남은 초 표시. */
    val resendSeconds: Int get() = _resendSeconds.value
    val resendSecondsFlow: StateFlow<Int> = _resendSeconds.asStateFlow()

    private var sendCount = 0

    /** 코드 검증이 준 recovery 세션. **여기서만** 쥐고 영속하지 않는다. 성공하면 세션 스토어로 넘어가고 여기선 버린다. */
    private var verifiedSession: SupabaseSession? = null
    private var generation = 0
    private var cooldownJob: Job? = null

    /** 쿨다운 1초 대기. 시험이 바꿔 60초를 실제로 자지 않는다(가상 시간이면 기본값도 된다). */
    var sleep: suspend (Int) -> Unit = { seconds -> delay(seconds * 1_000L) }

    val step: Step
        get() = when (_phase.value) {
            Phase.enterCode, Phase.verifying -> Step.code
            Phase.enterNewPassword, Phase.submitting, Phase.done -> Step.newPassword
            Phase.enterEmail, Phase.sending -> Step.email
        }

    val isBusy: Boolean get() = _phase.value == Phase.sending || _phase.value == Phase.verifying || _phase.value == Phase.submitting

    /** 왕복 중이면 잠그고, 그 밖에는 서버에 보낼 값이 갖춰졌을 때만 연다(빈 요청으로 레이트리밋을 태우지 않는다). */
    fun isPrimaryEnabled(code: String, newPassword: String): Boolean {
        if (isBusy) return false
        return when (step) {
            Step.email -> isPlausibleEmail(normalizedEmail(email.value))
            Step.code -> normalizedCode(code).length == CODE_LENGTH
            Step.newPassword -> graphemes.count(newPassword) >= MIN_PASSWORD_LENGTH
        }
    }

    val isResendEnabled: Boolean get() = !isBusy && _resendSeconds.value <= 0
    val resendTitle: String get() = if (_resendSeconds.value > 0) "다시 받기 (${_resendSeconds.value}초)" else "다시 받기"

    val primaryTitle: String
        get() = when (step) {
            Step.email -> "코드 받기"
            Step.code -> "코드 확인"
            Step.newPassword -> "비밀번호 바꾸기"
        }

    /** 안내/오류 슬롯 문구. 스토어 문구가 우선이고, 없을 때만 진행 상태를 대신 적는다. */
    val noticeText: String?
        get() {
            val text = _message.value
            if (!text.isNullOrEmpty()) return text
            return when (_phase.value) {
                Phase.sending -> "코드 보내는 중"
                Phase.verifying -> "코드 확인 중"
                Phase.submitting -> "비밀번호 바꾸는 중"
                else -> null
            }
        }

    /** 실패가 **아닌** 문구를 열거해 그 밖을 전부 오류로 본다(낱말 추정이 아니라). */
    val noticeIsError: Boolean
        get() {
            if (isBusy) return false
            val text = noticeText ?: return false
            return when (text) {
                PasswordResetText.sent, PasswordResetText.alreadySent, PasswordResetText.cooldown -> false
                else -> true
            }
        }

    // ------------------------------------------------------------------ 코드 발송(1)

    /** enterEmail → sending → enterCode. 형식 검증과 쿨다운은 **왕복 전에** 건다. */
    suspend fun requestCode() {
        val normalized = normalizedEmail(email.value)
        if (!isPlausibleEmail(normalized)) {
            email.value = normalized
            _message.value = PasswordResetText.invalidEmail
            if (_phase.value != Phase.enterCode) _phase.value = Phase.enterEmail
            return
        }
        // 쿨다운 중이면 서버가 어차피 429 다. 헛왕복은 서버 카운터만 더 밀어 대기를 늘린다.
        if (_resendSeconds.value > 0) {
            _message.value = PasswordResetText.cooldown
            return
        }
        if (isBusy) return
        email.value = normalized
        _message.value = null
        _phase.value = Phase.sending
        generation += 1
        val myGeneration = generation
        try {
            service.sendPasswordResetCode(normalized)
            if (myGeneration != generation) return
            _phase.value = Phase.enterCode
            _message.value = PasswordResetText.sent
            startCooldown(consumeResendCooldownSeconds())
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (myGeneration != generation) return
            if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) {
                _phase.value = Phase.enterEmail
                return
            }
            val serverSeconds = rateLimitSeconds(error)
            if (serverSeconds != null) {
                // 429 = "방금 이미 보냈다". 코드는 메일함으로 가는 중이므로 입력 화면으로 넘긴다 — 남은 초는 서버가 진실이다.
                _phase.value = Phase.enterCode
                _message.value = PasswordResetText.alreadySent
                consumeResendCooldownSeconds()
                startCooldown(serverSeconds)
                return
            }
            _phase.value = Phase.enterEmail
            _message.value = sendFailureMessage(error)
        }
    }

    /** 첫 발송 뒤 5초(첫 메일이 안 오는 일이 실제로 있다), 재전송 뒤 60초. 차수는 여기서만 올린다. */
    private fun consumeResendCooldownSeconds(): Long {
        val seconds = if (sendCount == 0) FIRST_RESEND_DELAY_SECONDS else RESEND_COOLDOWN_SECONDS
        sendCount += 1
        return seconds
    }

    /**
     * 남은 초는 **시계 기준 데드라인에서 매번 다시 계산**한다(잠자기·스케줄 지연이 누적 오차가 되지 않게).
     * 쿨다운의 수명은 **작업 취소뿐**이다 — 왕복 세대는 보지 않는다. 세대를 틱마다 견주면 쿨다운이 남은 채 코드를 틀린 순간 루프가
     * 남은 초를 남긴 채 빠져나가 '다시 받기 (48초)' 가 영영 비활성이 된다(iOS w16 검증 실측 — 맥에서 물려받은 결함을 끊었다).
     */
    fun startCooldown(seconds: Long) {
        val clamped = seconds.coerceIn(1, 600)
        cooldownJob?.cancel()
        _resendSeconds.value = clamped.toInt()
        val deadline = clock.now().addingTimeInterval(clamped.toDouble())
        cooldownJob = session.scope.launch {
            while (isActive) {
                val remaining = ceil(deadline.timeIntervalSince(clock.now())).toInt()
                if (remaining <= 0) {
                    if (_resendSeconds.value != 0) _resendSeconds.value = 0
                    return@launch
                }
                if (_resendSeconds.value != remaining) _resendSeconds.value = remaining
                sleep(1)
            }
        }
    }

    // ------------------------------------------------------------------ 코드 검증(2)

    /** enterCode → verifying → (성공) enterNewPassword. 코드 6자리는 **왕복 전에** 거른다. 실패하면 enterCode 에 머문다. */
    suspend fun verifyCode(code: String) {
        val normalizedCode = normalizedCode(code)
        if (normalizedCode.length != CODE_LENGTH) {
            _message.value = PasswordResetText.invalidCode
            return
        }
        if (email.value.isEmpty()) {
            _phase.value = Phase.enterEmail
            _message.value = PasswordResetText.invalidEmail
            return
        }
        // 이미 검증을 통과해 세션을 쥐고 있으면 **왕복하지 않고** 다음 화면으로 — OTP 는 1회용이라 다시 보내면 반드시 튕긴다.
        if (verifiedSession != null) {
            _message.value = null
            _phase.value = Phase.enterNewPassword
            return
        }
        if (isBusy) return
        _message.value = null
        _phase.value = Phase.verifying
        generation += 1
        val myGeneration = generation
        val address = email.value
        try {
            val verified = service.verifyPasswordResetCode(address, normalizedCode)
            if (myGeneration != generation) return
            verifiedSession = verified
            _phase.value = Phase.enterNewPassword
            _message.value = null
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (myGeneration != generation) return
            _phase.value = Phase.enterCode
            if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
            _message.value = verifyFailureMessage(error)
        }
    }

    // ------------------------------------------------------------------ 새 비밀번호(3)

    /** enterNewPassword → submitting → (성공) done + 로그인 상태. 길이는 **왕복 전에** 거른다(그래핌 — 서버보다 엄격한 쪽). */
    suspend fun submitNewPassword(newPassword: String) {
        if (graphemes.count(newPassword) < MIN_PASSWORD_LENGTH) {
            _message.value = PasswordResetText.shortPassword
            return
        }
        val verified = verifiedSession
        if (verified == null) {
            _phase.value = Phase.enterCode
            _message.value = PasswordResetText.codeRejected
            return
        }
        if (isBusy) return
        _message.value = null
        _phase.value = Phase.submitting
        generation += 1
        val myGeneration = generation
        val address = email.value
        val sessionGeneration = session.generation
        try {
            service.updatePassword(verified.accessToken, newPassword)
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (myGeneration != generation) return
            if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) {
                _phase.value = Phase.enterNewPassword
                return
            }
            // 붙잡아 둔 세션까지 죽었으면 그 세션으로는 두 번 다시 못 바꾼다 — 버려서 재시도가 코드 검증부터 다시 타게 한다.
            if (error == SupabaseWorkServiceError.SessionExpired || error == SupabaseWorkServiceError.OtpInvalidOrExpired) {
                verifiedSession = null
                _phase.value = Phase.enterCode
                _message.value = updateFailureMessage(error)
                return
            }
            // 그 밖의 거절(6자 미만·이전과 동일·일시 네트워크)은 **비밀번호만** 다시 받으면 되는 일이다 — 세션은 그대로.
            _phase.value = Phase.enterNewPassword
            _message.value = updateFailureMessage(error)
            return
        }
        if (myGeneration != generation || sessionGeneration != session.generation) return
        // 새 비밀번호가 섰다 — recovery 세션은 일반 세션과 같은 JWT 라 로그인 성공과 같은 길로 잇는다.
        verifiedSession = null
        cooldownJob?.cancel()
        cooldownJob = null
        _resendSeconds.value = 0
        _message.value = null
        _phase.value = Phase.done
        if (!session.isSignedIn) session.adoptSignedInSession(verified, address)
    }

    /** 화면을 떠날 때. 세대를 올려 날아가 있는 응답이 상태를 못 쓰게 하고 보관 세션을 버린다(같은 폰을 여럿이 쓰는 상황). */
    fun cancel() {
        generation += 1
        cooldownJob?.cancel()
        cooldownJob = null
        verifiedSession = null
        _resendSeconds.value = 0
        sendCount = 0
        _message.value = null
        if (_phase.value != Phase.done) _phase.value = Phase.enterEmail
    }

    // ------------------------------------------------------------------ 오류 → 문구(맥 passwordReset*FailureMessage 그대로)

    /** 키 부재/스키마처럼 **사용자가 아니라 설치가 잘못된** 경우. */
    private fun configMessage(error: Throwable): String? = when (error) {
        SupabaseWorkServiceError.MissingAnonKey, SupabaseWorkServiceError.InvalidAPIKey, SupabaseWorkServiceError.DatabaseSchemaMissing ->
            AuthErrorRules.message(error, PasswordResetText.sendFailed)
        else -> null
    }

    private fun sendFailureMessage(error: Throwable): String {
        configMessage(error)?.let { return it }
        if (AuthErrorRules.classify(error) == AuthErrorDisposition.transient) return PasswordResetText.network
        return PasswordResetText.sendFailed
    }

    /** 만료와 불일치를 가르지 않는다 — GoTrue 가 둘 다 같은 403 을 주고, 어느 쪽이든 할 일은 '다시 받기'로 같다. */
    private fun verifyFailureMessage(error: Throwable): String {
        configMessage(error)?.let { return it }
        if (rateLimitSeconds(error) != null) return PasswordResetText.cooldown
        if (AuthErrorRules.classify(error) == AuthErrorDisposition.transient) return PasswordResetText.network
        return PasswordResetText.codeRejected
    }

    private fun updateFailureMessage(error: Throwable): String {
        configMessage(error)?.let { return it }
        if (rateLimitSeconds(error) != null) return PasswordResetText.cooldown
        if (AuthErrorRules.classify(error) == AuthErrorDisposition.transient) return PasswordResetText.network
        return when (error) {
            SupabaseWorkServiceError.WeakPassword, SupabaseWorkServiceError.SamePasswordReuse -> PasswordResetText.rejectedPassword
            SupabaseWorkServiceError.SessionExpired, SupabaseWorkServiceError.OtpInvalidOrExpired -> PasswordResetText.codeRejected
            else -> PasswordResetText.updateFailed
        }
    }

    companion object {
        // 맥 상수 그대로(WorkTimerStoreAuth).
        const val FIRST_RESEND_DELAY_SECONDS: Long = 5
        const val RESEND_COOLDOWN_SECONDS: Long = 60
        const val MIN_PASSWORD_LENGTH: Int = 6
        const val CODE_LENGTH: Int = 6

        fun normalizedEmail(raw: String): String = raw.trim().lowercase()

        /** 이메일 형식의 **최소** 검증 — "@ 도 없는 입력"으로 왕복(과 60초 쿨다운)을 태우지 않기 위한 사전 필터. RFC 를 흉내 내지 않는다. */
        fun isPlausibleEmail(email: String): Boolean {
            if (email.any { it.isWhitespace() }) return false
            val parts = email.split("@")
            if (parts.size != 2 || parts[0].isEmpty()) return false
            val domain = parts[1]
            return domain.contains(".") && !domain.startsWith(".") && !domain.endsWith(".")
        }

        /** 메일에서 복사하면 공백·하이픈이 섞여 오므로 ASCII 숫자만 남긴다. */
        fun normalizedCode(raw: String): String = raw.filter { it in '0'..'9' }

        /** 레이트리밋이면 **걸어야 할 쿨다운 초**, 아니면 null. 서버가 초를 안 주면 60(0으로 취급하면 버튼이 바로 열려 429 를 또 맞는다). */
        fun rateLimitSeconds(error: Throwable): Long? {
            val limited = error as? SupabaseWorkServiceError.RateLimited ?: return null
            return limited.retryAfterSeconds ?: RESEND_COOLDOWN_SECONDS
        }
    }
}

/** 재설정 화면 문구 — 맥 `WorkTimerStore.passwordReset*Message` **그대로**(문구가 곧 계약: 계정 존재 여부를 흘리지 않는다). */
object PasswordResetText {
    const val title: String = "비밀번호 재설정"
    const val verifiedTitle: String = "코드 확인 완료"
    const val emailHelp: String = "가입할 때 쓴 이메일로 6자리 코드를 보내 드려요"
    const val sentTo: String = "이 주소로 코드를 보냈어요"
    const val codeLabel: String = "인증 코드 6자리"
    const val newPasswordLabel: String = "새 비밀번호"
    const val newPasswordHelp: String = "새 비밀번호를 정해주세요 · 영문/숫자 6자 이상"
    const val resendPrompt: String = "코드가 안 왔나요?"

    const val invalidEmail: String = "이메일 주소를 확인해주세요"
    const val sent: String = "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요"
    const val alreadySent: String = "메일을 이미 보냈어요 · 메일함을 확인해주세요"
    const val cooldown: String = "조금 뒤에 다시 받을 수 있어요"
    const val sendFailed: String = "메일을 보내지 못했어요 · 주소를 확인하고 다시 시도해주세요"

    /** 연결 안내만 공용 문장이다(탭마다 갈리지 않게 한 곳). */
    const val network: String = SessionText.network
    const val invalidCode: String = "메일로 받은 6자리 숫자를 입력해주세요"
    const val shortPassword: String = "비밀번호 조건 확인 · 6자 이상으로 정해주세요"
    const val rejectedPassword: String = "비밀번호 조건 확인 · 6자 이상, 이전과 다른 값으로 정해주세요"
    const val codeRejected: String = "코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요"
    const val updateFailed: String = "비밀번호를 바꾸지 못했어요 · 다시 시도해주세요"
}
