// 원본: Sources/CheckCore/Megaphone.swift:272-578(MegaphoneStore — 배선 · 세대 · 비동기) @ 1b8260d
// 규칙(요청·응답 모양 · 결과 · 본문 판정 · 문구 · 정보 · 보내기 전 판정 · request_id 쥐기)은 W1-c core/rules/…/text/Megaphone.kt — 그 머리말이
// "MegaphoneStore 의 배선 · 세대 · 비동기는 메시지 스토어 갈래(W2-b)가 이 규칙 위에 옮긴다"고 넘겼다.
package com.yehsung.aingcheck.core.stores.messages

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.megaphoneInfoRaw
import com.yehsung.aingcheck.core.net.sendMegaphoneRaw
import com.yehsung.aingcheck.core.rules.text.BlockReportRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneBody
import com.yehsung.aingcheck.core.rules.text.MegaphoneInfo
import com.yehsung.aingcheck.core.rules.text.MegaphoneInfoResponse
import com.yehsung.aingcheck.core.rules.text.MegaphoneRequestID
import com.yehsung.aingcheck.core.rules.text.MegaphoneRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendGate
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendOutcome
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendResponse
import com.yehsung.aingcheck.core.rules.text.MegaphoneText
import com.yehsung.aingcheck.core.rules.text.MessageBodyValidation
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * 확성기가 빌리는 곳(Swift `GomokuStoreHost` 의 세션 몫 + 루비 미러 한 칸). 오목·체스·상점 호스트(W2-c·d·e)가 같은 미러를 나눠 쓴다 —
 * 조립이 그 호스트를 이 문으로 넘긴다.
 */
interface MegaphoneHost : SessionHost {
    /** 루비 잔량 미러(서버 값만 — 모르면 null). */
    var rubyBalance: Long?
}

/**
 * 확성기(📢 1.0.7) 작성 스토어 — **맥과 같은 코어 스토어**. 화면은 메시지 탭 위 📢 버튼의 시트다.
 *
 * - 2단 확인: 첫 [requestSend] 는 요청을 내지 않고 지금 시계로 막을 것을 본다. 실제 요청은 [confirmSend] 하나뿐이다.
 * - request_id 는 **서버가 답을 준 뒤에만** 버린다(C§4 #26). 결과를 모르는 실패(오프라인·5xx·응답 해석 실패)면 쥔 채 확인 단계에 남는다.
 * - 세대 가드: 세션 세대 + 이 스토어의 reset 세대. 로그아웃 뒤 도착한 응답은 다음 계정 화면에 안 들어간다.
 */
@OptIn(ExperimentalUuidApi::class)
class MegaphoneStore(
    host: MegaphoneHost?,
    private val scope: CoroutineScope,
    /** 시각(주입 시계). */
    var clock: () -> SwiftDate,
    /** 요청 id 를 만드는 곳(시험이 바꾼다). */
    var makeRequestID: () -> String = { Uuid.random().toString().lowercase() },
) {
    /** 네트워크·세션·루비 미러를 빌리는 곳. 소유자가 이 스토어를 쥔다. */
    var host: MegaphoneHost? = host
        private set

    /** 작성 칸(화면이 바인딩한다 — 고칠 때는 [setDraft] 를 지난다). */
    val draft: String get() = draftState
    private var draftState: String by mutableStateOf("")
    var isComposerOpen: Boolean by mutableStateOf(false)
        private set

    /** 2단 확인의 둘째 단계("루비 50개로 N명에게 보낼까요?"). */
    var isConfirming: Boolean by mutableStateOf(false)
        private set

    /** 전송 왕복 중(한 번에 하나). */
    var isSending: Boolean by mutableStateOf(false)
        private set
    var notice: String? by mutableStateOf(null)
        private set
    var noticeIsError: Boolean by mutableStateOf(false)
        private set
    var info: MegaphoneInfo? by mutableStateOf(null)
        private set
    var infoLoading: Boolean by mutableStateOf(false)
        private set
    var infoFailed: Boolean by mutableStateOf(false)
        private set

    /** 서버에 확성기 함수가 아직 없다(PGRST202). */
    var serverUnavailable: Boolean by mutableStateOf(false)
        private set

    private val requestID = MegaphoneRequestID()

    /** 이 작성의 요청 id. **서버가 답을 준 뒤에만** 버린다. 시험이 읽는다. */
    val pendingRequestID: String? get() = requestID.pending

    private var resetGeneration = 0

    /**
     * 전송이 `sent`(중복 포함)로 끝났을 때 — 보낸 본문(정규화된 것)과 서버가 준 확성기 id(원본 Megaphone.swift `onSent` @ a6791165).
     * 소유자(폰 조립)가 자기 배너를 한 번 띄운다([MegaphoneBannerStore.presentOwn] — 서버 fan-out 에는 본인이 없다).
     */
    var onSent: ((body: String, megaphoneID: String?) -> Unit)? = null

    fun attach(host: MegaphoneHost) {
        this.host = host
    }

    private fun now(): Double = clock().timeIntervalSince1970

    // ---------------------------------------------------------------- 파생값

    val maxLength: Int get() = info?.maxLength?.toInt() ?: MegaphoneBody.maxLength
    val draftLength: Int get() = MegaphoneBody.length(draft)
    val isOverLength: Boolean get() = draftLength > maxLength
    val counterText: String get() = MegaphoneText.counter(draftLength, maxLength)

    /** 가격(서버 값만 — 모르면 null, 숫자를 지어내지 않는다). */
    val price: Long? get() = info?.price

    /** [보내기](첫 단계)를 누를 수 있는가. 판정의 나머지는 누르는 순간 [requestSend] 가 **그때의 시계로** 본다. */
    val canRequestSend: Boolean
        get() {
            if (isSending || host?.session == null || serverUnavailable) return false
            return MegaphoneBody.validate(draft, maxLength) is MessageBodyValidation.ok
        }

    fun infoLine(now: SwiftDate): String = MegaphoneRules.infoLine(serverUnavailable, info, infoFailed, now.timeIntervalSince1970)

    val confirmQuestion: String? get() = info?.let { MegaphoneText.confirm(it.price, it.recipients) }

    // ---------------------------------------------------------------- 화면 사건

    /** 작성 화면을 연다. 글은 남겨 둔다 · 확인 단계는 내린다 · 정보를 다시 읽는다. 결과 한 줄은 여기서 지우지 않는다. */
    fun open() {
        isComposerOpen = true
        isConfirming = false
        loadInfo()
    }

    /** 작성 화면을 닫는다. 왕복 중이면 결과 한 줄을 남겨 둔다(곧 도착할 결과가 들어갈 자리다). */
    fun close() {
        isComposerOpen = false
        isConfirming = false
        if (!isSending) setNotice(null)
    }

    /** 글을 고친다. 고치면 확인 단계는 풀린다(확인한 글과 보낼 글이 달라지면 안 된다) · 지난 결과 한 줄도 내린다. */
    fun setDraft(text: String) {
        if (draftState == text) return
        draftState = text
        if (isConfirming) isConfirming = false
        if (notice != null) setNotice(null)
    }

    /** 첫 단계 [보내기]. **요청을 내지 않는다** — 막을 것을 지금 시계로 보고, 통과하면 확인 단계로 간다. */
    fun requestSend() {
        when (
            val gate = MegaphoneRules.requestSend(
                isSending, host?.session != null, serverUnavailable, draft, info, infoFailed, host?.rubyBalance, now(),
            )
        ) {
            MegaphoneSendGate.ignore -> return
            is MegaphoneSendGate.notice -> {
                setNotice(gate.text, gate.isError)
                if (gate.reloadInfo) loadInfo()
            }
            MegaphoneSendGate.confirm -> {
                setNotice(null)
                isConfirming = true
            }
        }
    }

    fun cancelConfirm() {
        isConfirming = false
    }

    /** 확인 단계 [보내기] — **실제 요청은 여기 하나뿐이다.** 반환: 요청을 띄웠는가. */
    fun confirmSend(): Boolean {
        val host = host ?: return false
        if (!isConfirming || isSending || host.session == null) return false
        val validation = MegaphoneBody.validate(draft, maxLength) as? MessageBodyValidation.ok
        if (validation == null) {
            isConfirming = false
            return false
        }
        val id = requestID.begin(makeRequestID)
        isSending = true
        setNotice(null)
        val sessionGeneration = host.sessionGeneration
        val generation = resetGeneration
        val service = host.service
        scope.launch {
            try {
                val raw = host.withSessionRetry { session -> service.sendMegaphoneRaw(session.accessToken, validation.value, id) }
                val response = MegaphoneSendResponse.decode(raw)
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                isSending = false
                apply(response, id)
                if (MegaphoneSendOutcome.from(response) is MegaphoneSendOutcome.sent) onSent?.invoke(validation.value, response.megaphoneId)
            } catch (error: Throwable) {
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                isSending = false
                // 취소(창 닫기·세대 교체)는 실패가 아니다 — 문구를 남기지 않는다. id 는 쥔다(서버가 처리했을 수 있다).
                if (host.classifyAuthError(error) == AuthErrorDisposition.cancelled) return@launch
                val effect = MegaphoneRules.afterSendFailure(serviceErrorFacts(error))
                requestID.failed(effect.dropRequestID)
                if (effect.serverUnavailable) serverUnavailable = true
                if (effect.endsConfirm) isConfirming = false
                // 결과를 모른다(오프라인·5xx·응답 해석 실패) — **id 를 쥔 채** 확인 단계에 남는다.
                effect.notice?.let { setNotice(it, error = true) }
            }
        }
        return true
    }

    /** 서버 답(어떤 status 든)을 화면에 옮긴다. 서버가 답을 줬으니 id 는 여기서 버린다. */
    fun apply(response: MegaphoneSendResponse, requestID: String) {
        this.requestID.settle(requestID)
        isConfirming = false
        host?.let { it.rubyBalance = MegaphoneRules.rubyAfterSend(response, it.rubyBalance) }
        val now = now()
        val outcome = MegaphoneSendOutcome.from(response)
        val left = if (outcome is MegaphoneSendOutcome.cooldown) MegaphoneRules.cooldownSecondsAfter(outcome, info) else 0
        info = MegaphoneRules.infoAfter(outcome, info, now)
        when (outcome) {
            is MegaphoneSendOutcome.sent -> {
                draftState = ""
                setNotice(MegaphoneText.notice(outcome, left).first)
                loadInfo()
            }
            MegaphoneSendOutcome.unavailable -> {
                serverUnavailable = true
                setNotice(MegaphoneText.unavailable, error = true)
            }
            else -> {
                val (text, isError) = MegaphoneText.notice(outcome, left)
                setNotice(text, isError)
            }
        }
    }

    /**
     * `megaphone_info` 를 읽는다(작성 화면이 열릴 때 · 보낸 뒤). 겹치지 않는다.
     * `mirrorsRubyBalance = false` 는 **가격만 미리 읽는** 호출이다(그 순간 잔량은 같이 나간 상점 조회가 말한다 — 늦은 이 응답이 덮지 않게).
     */
    fun loadInfo(mirrorsRubyBalance: Boolean = true) {
        val host = host ?: return
        if (host.session == null || infoLoading) return
        infoLoading = true
        val sessionGeneration = host.sessionGeneration
        val generation = resetGeneration
        val service = host.service
        scope.launch {
            try {
                val raw = host.withSessionRetry { session -> service.megaphoneInfoRaw(session.accessToken) }
                val response = MegaphoneInfoResponse.decode(raw)
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                infoLoading = false
                applyInfo(response, mirrorsRubyBalance)
            } catch (error: Throwable) {
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                infoLoading = false
                if (host.classifyAuthError(error) == AuthErrorDisposition.cancelled) return@launch
                if (BlockReportRules.isMissingFunction(serviceErrorFacts(error))) {
                    serverUnavailable = true
                    return@launch
                }
                infoFailed = true
            }
        }
    }

    /** 정보 응답을 화면 값으로. ok 가 아니면 실패로 센다(숫자를 지어내지 않는다). */
    fun applyInfo(response: MegaphoneInfoResponse, mirrorsRubyBalance: Boolean = true) {
        val accepted = MegaphoneInfo.from(response, now())
        if (accepted == null) {
            infoFailed = true
            return
        }
        info = accepted
        infoFailed = false
        serverUnavailable = false
        if (mirrorsRubyBalance) host?.let { it.rubyBalance = MegaphoneRules.rubyAfterInfo(response, accepted, it.rubyBalance) }
    }

    /** 로그아웃·계정 전환. 계정에 묶인 값(글·id·정보)을 전부 비우고, 나가 있던 응답은 세대로 버린다. */
    fun reset() {
        resetGeneration += 1
        draftState = ""
        isComposerOpen = false
        isConfirming = false
        isSending = false
        notice = null
        noticeIsError = false
        info = null
        infoLoading = false
        infoFailed = false
        serverUnavailable = false
        requestID.reset()
    }

    private fun setNotice(text: String?, error: Boolean = false) {
        if (notice != text) notice = text
        val isError = text != null && error
        if (noticeIsError != isError) noticeIsError = isError
    }
}
