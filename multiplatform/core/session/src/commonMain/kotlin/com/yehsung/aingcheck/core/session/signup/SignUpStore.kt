// 원본: Sources/CheckMobileKit/Session/MobileSignUpStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.signup

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.resendSignUpCode
import com.yehsung.aingcheck.core.net.signUp
import com.yehsung.aingcheck.core.net.verifySignUpCode
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.reset.PasswordResetStore
import com.yehsung.aingcheck.core.session.reset.PasswordResetText
import com.yehsung.aingcheck.core.session.rethrowIfOwnCancellation
import com.yehsung.aingcheck.core.session.team.TeamJoinForm
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.ceil

/**
 * 가입(Swift `MobileSignUpStore`). **맥 가입 폼의 규칙을 그대로** — 입력 셋 필수 → 모드별 팀 칸(코드는 **미리보기 확인 필수**, 만들기는
 * 팀 이름 필수) → 소속 센터 **기본 미선택** 필수, 순서까지 같다(같은 입력에 같은 문구).
 *
 * 흐름: `/auth/v1/signup` → (코드) `join_team` / (만들기) `create_team` → 세션 스토어 `adoptSignedInSession`(로그인 성공과 같은 길).
 * **팀이 정해질 때까지 세션을 세션 스토어에 넘기지 않는다** — 합류 0행 · 합류/생성 실패면 이 스토어가 세션을 쥔 채 [Stage.Teamless] 로 남는다.
 *
 * 가입 이메일 인증코드: **두 서버 모드를 다 견딘다.** `signUp` 응답에 세션이 있으면 곧장 팀 단계로, 없으면 코드 화면으로(C§4 #8 —
 * 세션 없음 = "메일 보냄", `identities: []` = 이미 있는 계정은 net 의 `signUp` 이 [SupabaseWorkServiceError.EmailAlreadyRegistered] 로 던진다).
 * 세션이 생긴 뒤의 마무리는 어느 갈래든 같은 함수([continueAfterSession])다.
 */
class SignUpStore(private val session: SessionStore, createTeam: Boolean = false) {
    sealed interface Stage {
        /** 계정 칸 + 팀 칸(맥 가입 폼). */
        data object Account : Stage

        /** 계정은 만들어졌는데 **아직 미확인**이다. 6자리 코드만 받는다. */
        data object ConfirmCode : Stage

        /** 계정은 만들어졌는데 팀이 없다(합류 0행 = 센터 게이트 · 합류/생성 실패 · 출구로 들어와 팀 칸이 빈 경우). */
        data object Teamless : Stage

        /** 팀을 만들었다 — 참여코드 카드. [시작하기]가 세션을 잇는다. */
        data class CreatedTeam(val code: String) : Stage
    }

    private val service: SupabaseWorkService = session.service
    private val clock = session.clock

    val displayName: MutableStateFlow<String> = MutableStateFlow("")
    val email: MutableStateFlow<String> = MutableStateFlow(session.storedEmail ?: "")
    val password: MutableStateFlow<String> = MutableStateFlow("")

    /** 소속 센터의 **서버값**. **null = 미선택이 기본이다** — 기본을 서울로 두면 부산 연수생이 아무것도 안 하고 서울로 잡힌다. */
    val center: MutableStateFlow<String?> = MutableStateFlow(null)

    /** 팀 칸 한 벌('지금' 탭 무소속 카드와 같은 물건). */
    val teamForm: TeamJoinForm = TeamJoinForm(service, session.scope, createTeam)

    private val _notice = MutableStateFlow<String?>(null)
    private val _isSubmitting = MutableStateFlow(false)
    private val _isResending = MutableStateFlow(false)
    private val _stage = MutableStateFlow<Stage>(Stage.Account)
    private val _resendSeconds = MutableStateFlow(0)

    /** 화면 한 줄(거절 이유 · 실패 원인 · 코드 화면 안내). 미리보기 문구는 팀 칸의 previewLine 으로 따로 간다. */
    val notice: String? get() = _notice.value
    val noticeFlow: StateFlow<String?> = _notice.asStateFlow()
    val isSubmitting: Boolean get() = _isSubmitting.value
    val isSubmittingFlow: StateFlow<Boolean> = _isSubmitting.asStateFlow()

    /** 코드 재전송 왕복 중. 주 버튼과 나눠 둔다 — 재전송 때 주 버튼이 도는 것처럼 보이면 안 된다. */
    val isResending: Boolean get() = _isResending.value
    val isResendingFlow: StateFlow<Boolean> = _isResending.asStateFlow()
    val stage: Stage get() = _stage.value
    val stageFlow: StateFlow<Stage> = _stage.asStateFlow()

    /** >0 이면 재전송 잠금 + 남은 초. */
    val resendSeconds: Int get() = _resendSeconds.value
    val resendSecondsFlow: StateFlow<Int> = _resendSeconds.asStateFlow()

    /** 코드를 보낸 **정규화된** 주소. verify 는 이 글자를 그대로 써야 한다(서버가 아는 주소와 한 글자라도 다르면 403). */
    var confirmSentEmail: String = ""
        private set

    /** 계정을 만들어 받은 세션. 팀이 정해질 때까지 **여기서만** 쥔다. 시험이 읽는다. */
    var createdSession: SupabaseSession? = null
        private set
    private var createdEmail = ""
    private var confirmGeneration = 0
    private var confirmSendCount = 0
    private var cooldownJob: Job? = null

    /** 쿨다운 1초 대기(재설정 스토어와 같은 주입점). */
    var sleep: suspend (Int) -> Unit = { seconds -> delay(seconds * 1_000L) }

    // ------------------------------------------------------------------ 화면이 읽는 값

    /** 주 버튼을 **켜 둘** 수 있는가. 판정 자체는 [submit] 의 가드에 있다(맥 canSubmitSignUp: 키 + 센터 선택). */
    val canSubmit: Boolean
        get() {
            if (_isSubmitting.value || _isResending.value) return false
            return when (_stage.value) {
                Stage.Account -> center.value != null
                Stage.ConfirmCode -> false
                Stage.Teamless, is Stage.CreatedTeam -> true
            }
        }

    /** 코드 화면에서만 화면 상태(코드 칸)를 본다 — 빈 코드로 왕복해 레이트리밋을 태우지 않는다. */
    fun isPrimaryEnabled(code: String): Boolean {
        if (_stage.value != Stage.ConfirmCode) return canSubmit
        if (_isSubmitting.value || _isResending.value) return false
        return PasswordResetStore.normalizedCode(code).length == PasswordResetStore.CODE_LENGTH
    }

    val primaryTitle: String
        get() = when (_stage.value) {
            is Stage.CreatedTeam -> SignUpText.start
            Stage.Account -> if (teamForm.isCreateTeamMode.value) SignUpText.createAndStart else SignUpText.signUp
            Stage.ConfirmCode -> SignUpText.verifyCode
            Stage.Teamless -> if (teamForm.isCreateTeamMode.value) SignUpText.createAndStart else SignUpText.join
        }

    val headline: String
        get() = when (_stage.value) {
            Stage.Account -> if (teamForm.isCreateTeamMode.value) SignUpText.subtitleCreate else SignUpText.subtitleJoin
            Stage.ConfirmCode -> SignUpText.subtitleConfirm
            Stage.Teamless -> if (teamForm.isCreateTeamMode.value) SignUpText.subtitleCreate else SignUpText.subtitleTeamless
            is Stage.CreatedTeam -> SignUpText.createdTitle
        }

    val title: String get() = if (_stage.value == Stage.ConfirmCode) SignUpText.confirmTitle else SignUpText.title

    /** 안내 줄을 **빨갛게** 그릴까. 실패가 **아닌** 문구를 열거해 그 밖을 전부 오류로 본다. */
    val noticeIsError: Boolean
        get() {
            val text = _notice.value ?: return false
            if (text.startsWith(SignUpText.rateLimitedPrefix)) return false
            return when (text) {
                SignUpText.confirmSent, SignUpText.confirmResent, SignUpText.accountCreatedNotice,
                PasswordResetText.alreadySent, PasswordResetText.cooldown,
                -> false
                else -> true
            }
        }

    /** 가입 화면(계정 칸)에서 출구를 보일까 — 코드 화면에선 이미 그 안에 있으므로 달지 않는다. */
    val offersConfirmationExit: Boolean
        get() {
            val text = _notice.value ?: return false
            return _stage.value == Stage.Account && offersConfirmationExit(text)
        }

    val isResendEnabled: Boolean get() = !_isSubmitting.value && !_isResending.value && _resendSeconds.value <= 0
    val resendTitle: String
        get() = if (_resendSeconds.value > 0) "${SignUpText.resend} (${_resendSeconds.value}초)" else SignUpText.resend

    /** 코드 칸 아래 한 줄(문구가 요약보다 먼저 — 팀 칸 한 벌의 규칙). */
    val previewLine: TeamJoinForm.PreviewLine? get() = teamForm.previewLine

    // ------------------------------------------------------------------ 팀 코드 미리보기

    fun previewTeamCode(): Job = teamForm.previewTeamCode()

    suspend fun performPreviewTeamCode() = teamForm.performPreviewTeamCode()

    /** 코드 입력 ↔ 팀 만들기 전환. 이전 코드 미리보기 잔상을 지운다. */
    fun toggleCreateTeamMode() {
        teamForm.toggleCreateTeamMode()
        _notice.value = null
    }

    // ------------------------------------------------------------------ 제출(맥 signUp() 의 가드 순서 그대로)

    /** 가드에 걸리면 **문구를 세우고 null**(화면은 이 값을 보지 않고 부른다 — 막는 일은 여기서만). */
    fun submit(): Job? {
        if (_isSubmitting.value || _isResending.value) return null
        return when (_stage.value) {
            // 코드 화면의 주 버튼은 verifyCode 다(코드는 화면이 쥔다). 여기로 새는 길이 있으면 코드 없이 왕복하거나 팀 단계를 건너뛴다.
            Stage.ConfirmCode -> null
            is Stage.CreatedTeam -> {
                val created = createdSession ?: return null
                adopt(created, createdEmail)
                Job().also { it.complete() }
            }
            Stage.Account -> submitAccount()
            Stage.Teamless -> {
                if (!teamFieldsAreReady()) return null
                val created = createdSession
                if (created == null) {
                    // 있을 수 없는 상태(세션 없이 teamless) — 계정 칸으로 되돌린다.
                    _stage.value = Stage.Account
                    return null
                }
                _notice.value = null
                _isSubmitting.value = true
                val address = createdEmail
                launchNow {
                    performTeamStep(created, address)
                    _isSubmitting.value = false
                }
            }
        }
    }

    private fun submitAccount(): Job? {
        val trimmedEmail = email.value.trim()
        val trimmedDisplayName = displayName.value.trim()
        if (trimmedEmail.isEmpty() || password.value.isEmpty() || trimmedDisplayName.isEmpty()) {
            _notice.value = SignUpText.missingFields
            return null
        }
        if (!teamFieldsAreReady()) return null
        // 센터 미선택은 여기서도 막는다. 버튼은 비활성이지만 **키보드 제출 경로가 따로 있고**, 그 길로 새면 서버가 center 없이
        // 계정을 만들어 영영 미지정인 사람이 생긴다.
        val chosenCenter = center.value
        if (chosenCenter == null) {
            _notice.value = SignUpText.centerRequired
            return null
        }
        _notice.value = null
        _isSubmitting.value = true
        val pw = password.value
        return launchNow { performSignUp(trimmedEmail, pw, trimmedDisplayName, chosenCenter) }
    }

    private fun launchNow(block: suspend () -> Unit): Job {
        val job = session.scope.launch(start = CoroutineStart.LAZY) { block() }
        job.start()
        return job
    }

    /** 코드 모드: 미리보기가 확인되어야 가입 가능. 만들기 모드: 팀 이름 필수. */
    private fun teamFieldsAreReady(): Boolean {
        val message = teamForm.guardMessage() ?: return true
        _notice.value = message
        return false
    }

    private suspend fun performSignUp(email: String, password: String, displayName: String, center: String) {
        try {
            val created = service.signUp(email, password, displayName, center)
            // 어느 갈래든 비밀번호는 비운다 — 계정은 이미 만들어졌고, 화면에 남길 이유가 없다.
            this.password.value = ""
            if (created == null) {
                // INV-MobileSignUpStore-4900f2c6 이식: 세션 없이 200 = **가입 확인을 켠 서버**. 여기가 두 서버 모드의 유일한 갈림길이다.
                //   첫 메일은 가입 요청 자체가 보냈으므로 다시 보내지 않는다 — 코드 화면만 연다(이미 인증된 계정의 가짜 사용자 200 은
                //   net 의 signUp 이 emailAlreadyRegistered 로 던져 아래 catch 로 간다).
                enterConfirmation(email, SignUpText.confirmSent)
                return
            }
            continueAfterSession(created, email)
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            when (AuthErrorRules.classify(error)) {
                AuthErrorDisposition.cancelled -> return
                AuthErrorDisposition.transient -> {
                    // 429 는 오류가 아니라 "몇 초 뒤 다시"다(실측: 짧은 간격 재시도 = over_email_send_rate_limit).
                    val seconds = PasswordResetStore.rateLimitSeconds(error)
                    _notice.value = if (seconds != null) SignUpText.rateLimited(seconds) else SessionText.network
                }
                AuthErrorDisposition.fatal -> _notice.value = AuthErrorRules.message(error, SignUpText.signUpFailed)
            }
        } finally {
            _isSubmitting.value = false
        }
    }

    /**
     * **세션이 생긴 시점의 유일한 마무리**(즉시 세션이 온 가입 · 코드 확인 뒤). 팀 칸이 준비돼 있으면 그대로 팀을 정하고, 비어 있으면
     * 무소속 화면으로 남긴다 — 빈 코드로 join_team 을 부르면 0행이 돌아와 "다른 센터 팀이에요"라고 거짓말하게 된다.
     */
    private suspend fun continueAfterSession(created: SupabaseSession, email: String) {
        createdSession = created
        createdEmail = email
        if (!teamForm.isPrepared) {
            _stage.value = Stage.Teamless
            _notice.value = null
            return
        }
        performTeamStep(created, email)
    }

    /** 계정이 있는 상태에서 팀을 정한다. 실패는 [Stage.Teamless] 로 남긴다. 왕복·문구는 팀 칸이 쥐고 여기서는 단계만 정한다. */
    private suspend fun performTeamStep(created: SupabaseSession, email: String) {
        when (val outcome = teamForm.performTeamStep(created.accessToken)) {
            is TeamJoinForm.Outcome.Settled -> when (val settled = outcome.settled) {
                is TeamJoinForm.Settled.Created -> {
                    _notice.value = null
                    _stage.value = Stage.CreatedTeam(settled.inviteCode)
                }
                is TeamJoinForm.Settled.Joined -> adopt(created, email)
                // 코드 칸 아래 줄은 폼이 이미 '다른 센터 팀이에요' 로 바꿔 놓았다 — 무소속으로 남겨 다시 치게 한다.
                TeamJoinForm.Settled.Blocked -> _stage.value = Stage.Teamless
            }
            is TeamJoinForm.Outcome.Failed -> {
                _stage.value = Stage.Teamless
                _notice.value = outcome.message
            }
        }
    }

    // ------------------------------------------------------------------ 가입 이메일 인증코드

    /** 코드 화면으로 넘어간다. 부르는 쪽이 **직전에 메일이 나갔다**는 것을 알 때만 쓴다(가입 요청 · 재전송 성공). 첫 잠금은 5초. */
    private fun enterConfirmation(email: String, message: String) {
        confirmSentEmail = PasswordResetStore.normalizedEmail(email)
        createdEmail = confirmSentEmail
        _stage.value = Stage.ConfirmCode
        _notice.value = message
        startCooldown(consumeResendCooldownSeconds())
    }

    /**
     * 미확인 계정의 **출구**(로그인 화면의 "이메일 확인 필요" · 가입 화면). 계정은 이미 있으므로 이 흐름의 첫 발송은 **재전송**이다.
     * 주소가 형식에 안 맞으면 코드 화면을 열지 않는다(코드 화면엔 주소 칸이 없어 고칠 방법이 없다).
     */
    suspend fun beginConfirmation(raw: String) {
        val normalized = PasswordResetStore.normalizedEmail(raw)
        if (!PasswordResetStore.isPlausibleEmail(normalized)) {
            _notice.value = PasswordResetText.invalidEmail
            return
        }
        cancelPendingWork()
        confirmSendCount = 0
        _resendSeconds.value = 0
        confirmSentEmail = normalized
        createdEmail = normalized
        email.value = normalized
        _stage.value = Stage.ConfirmCode
        _notice.value = null
        performResend()
    }

    /** [다시 받기]. 쿨다운은 **왕복 전에** 건다(헛왕복은 서버 카운터만 밀어 대기를 늘린다). */
    suspend fun resendCode() {
        if (_stage.value != Stage.ConfirmCode || confirmSentEmail.isEmpty()) return
        if (_isSubmitting.value || _isResending.value) return
        if (_resendSeconds.value > 0) {
            _notice.value = PasswordResetText.cooldown
            return
        }
        performResend()
    }

    private suspend fun performResend() {
        val address = confirmSentEmail
        if (address.isEmpty()) return
        // 이번 발송이 첫 발송인가(= 출구로 들어와 계정 존재를 모르는 상태인가). 재전송 안내가 갈린다.
        val isFirstSend = confirmSendCount == 0
        _notice.value = null
        _isResending.value = true
        confirmGeneration += 1
        val generation = confirmGeneration
        try {
            service.resendSignUpCode(address)
            if (generation != confirmGeneration) return
            // INV-MobileSignUpStore-9dd2a9a0 이식: **재전송은 앞 코드를 무효화한다**(실측) — 그걸 말하지 않으면 사용자는 첫 메일의 코드를
            //   계속 넣고 403 만 본다. 첫 발송(출구)에는 앞 코드가 없으므로 같은 말을 하면 안 된다.
            _notice.value = if (isFirstSend) SignUpText.confirmSent else SignUpText.confirmResent
            startCooldown(consumeResendCooldownSeconds())
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (generation != confirmGeneration) return
            if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
            // 어느 실패든 코드 화면에 머문다 — 물러날 주소 칸이 없고, 코드가 이미 메일함에 있을 수 있다.
            val serverSeconds = PasswordResetStore.rateLimitSeconds(error)
            if (serverSeconds != null) {
                // 429 = 방금 이미 보냈다(가입 요청의 첫 메일이 간격 안이다). 남은 초는 **서버가 진실**이다.
                _notice.value = PasswordResetText.alreadySent
                consumeResendCooldownSeconds()
                startCooldown(serverSeconds)
                return
            }
            _notice.value = TeamJoinForm.failureMessage(error, SignUpText.resendFailed)
        } finally {
            _isResending.value = false
        }
    }

    /** 방금 끝난 발송 뒤에 걸 쿨다운(초)을 정하고 차수를 한 칸 올린다(재설정과 같은 규칙). */
    private fun consumeResendCooldownSeconds(): Long {
        val seconds = if (confirmSendCount == 0) PasswordResetStore.FIRST_RESEND_DELAY_SECONDS else PasswordResetStore.RESEND_COOLDOWN_SECONDS
        confirmSendCount += 1
        return seconds
    }

    /** 남은 초는 시계 기준 데드라인에서 매번 다시 계산한다. 쿨다운의 수명은 **작업 취소뿐**이다(재설정과 같은 이유). */
    private fun startCooldown(seconds: Long) {
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

    /**
     * 6자리 코드 검증 → 세션 → **즉시 세션이 온 가입과 같은 마무리**([continueAfterSession]). 6자리 미만은 왕복 전에 거른다.
     * 실패하면 코드 화면에 그대로 머문다([다시 받기]가 거기 있다).
     */
    suspend fun verifyCode(code: String) {
        if (_stage.value != Stage.ConfirmCode) return
        val normalizedCode = PasswordResetStore.normalizedCode(code)
        if (normalizedCode.length != PasswordResetStore.CODE_LENGTH) {
            _notice.value = PasswordResetText.invalidCode
            return
        }
        val address = confirmSentEmail
        if (address.isEmpty()) {
            // 어느 주소로 보냈는지 모르면 검증할 수 없다(있을 수 없는 상태) — 가입 폼으로 되돌린다.
            _stage.value = Stage.Account
            _notice.value = PasswordResetText.invalidEmail
            return
        }
        if (_isSubmitting.value || _isResending.value) return
        _notice.value = null
        _isSubmitting.value = true
        confirmGeneration += 1
        val generation = confirmGeneration
        try {
            val verified: SupabaseSession = try {
                service.verifySignUpCode(address, normalizedCode)
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (generation != confirmGeneration) return
                if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
                // 틀린 코드와 만료가 똑같이 403 otp_expired 라 문구는 하나다(실측) — 둘을 가르는 척하면 거짓말이 된다.
                _notice.value = when {
                    PasswordResetStore.rateLimitSeconds(error) != null -> PasswordResetText.cooldown
                    AuthErrorRules.classify(error) == AuthErrorDisposition.transient -> SessionText.network
                    else -> PasswordResetText.codeRejected
                }
                return
            }
            // 화면을 떠났거나(그 사람을 로그인시키면 안 된다) 그 사이 다른 로그인이 있었으면 이 세션은 버린다.
            if (generation != confirmGeneration || session.isSignedIn) return
            cooldownJob?.cancel()
            cooldownJob = null
            _resendSeconds.value = 0
            confirmSentEmail = ""
            confirmSendCount = 0
            _notice.value = null
            // 여기부터는 즉시 세션이 온 가입과 한 줄도 다르지 않다 — 팀 합류/만들기가 그 함수 안이다.
            continueAfterSession(verified, address)
        } finally {
            _isSubmitting.value = false
        }
    }

    /** 화면을 떠날 때. **상태(만들어진 계정 · 단계)는 그대로 두고** 날아가 있는 왕복과 카운트다운만 끊는다. */
    fun cancelPendingWork() {
        confirmGeneration += 1
        teamForm.cancelPendingPreview()
        cooldownJob?.cancel()
        cooldownJob = null
    }

    /** 로그인 성공과 같은 길(세션 스토어 adoptSignedInSession). 이미 다른 세션이 들어와 있으면 덮지 않는다. */
    private fun adopt(created: SupabaseSession, email: String) {
        if (session.isSignedIn) return
        session.adoptSignedInSession(created, email)
        createdSession = null
        _notice.value = null
    }

    companion object {
        /** 맥 `createTeamGoalHours` 기본값 · 범위와 같다(값의 주인은 팀 칸 한 벌). */
        const val DEFAULT_GOAL_HOURS: Long = TeamJoinForm.DEFAULT_GOAL_HOURS
        val GOAL_HOURS_RANGE: LongRange = TeamJoinForm.GOAL_HOURS_RANGE

        /**
         * 지금 안내가 "계정은 이미 있다"는 신호라 [인증 코드 받기] 출구를 달아야 하는가. **코어 매퍼(AuthErrorRules)의 문장을 그대로
         * 읽는다** — 여기 글자를 따로 적으면 매퍼가 바뀌는 날 출구가 조용히 사라진다.
         *
         * INV-MobileSignUpStore-8b6a03d1 이식: **"이미 가입된 이메일"에는 달지 않는다.** 그 문구가 뜨는 계정은 인증을 마친 계정이라 재전송해도
         *   메일이 나가지 않는다 — 화면만 "새 코드를 보냈어요"라고 말하고 사람은 오지 않을 메일을 기다린다. 미확인 계정은 로그인하면
         *   "이메일 확인 필요"가 떠서 그 문구가 출구를 단다.
         */
        fun offersConfirmationExit(message: String): Boolean =
            message == AuthErrorRules.message(SupabaseWorkServiceError.EmailNotConfirmed, "")
    }
}
