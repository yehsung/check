// 원본: Sources/CheckCore/Megaphone.swift @ 1b8260d (요청·응답 모양 · 결과 · 본문 판정 · 문구 · 정보 · 보내기 전 판정 · request_id 쥐기 —
//       @MainActor 스토어 MegaphoneStore 의 배선 · 세대 · 비동기는 메시지 스토어 갈래(W2-b)가 이 규칙 위에 옮긴다. HTTP 래퍼는 W1-d)
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.format.swiftKeyed
import kotlin.math.ceil
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** `send_megaphone(p_body, p_request_id)` 본문(Swift 합성 인코딩 + convertToSnakeCase — 두 키 모두 언제나 실린다). */
data class SendMegaphoneRequest(val pBody: String, val pRequestId: String) {
    fun body(): JsonObject = JsonObject(linkedMapOf("p_body" to JsonPrimitive(pBody), "p_request_id" to JsonPrimitive(pRequestId)))
}

/** `megaphone_info()` 응답. 칸은 모두 선택(Swift `decodeIfPresent` — 모양이 틀린 칸은 **전체** 디코드 실패). */
data class MegaphoneInfoResponse(
    val status: String? = "ok",
    val enabled: Boolean? = true,
    val price: Long? = null,
    val cooldownSeconds: Long? = null,
    val cooldownRemainingSeconds: Long? = null,
    val recipients: Long? = null,
    val maxLength: Long? = null,
    val rubyBalance: Long? = null,
) {
    companion object {
        fun decode(element: JsonElement): MegaphoneInfoResponse {
            val k = swiftKeyed(element)
            return MegaphoneInfoResponse(
                status = k.stringIfPresent("status"), enabled = k.boolIfPresent("enabled"), price = k.intIfPresent("price"),
                cooldownSeconds = k.intIfPresent("cooldownSeconds"), cooldownRemainingSeconds = k.intIfPresent("cooldownRemainingSeconds"),
                recipients = k.intIfPresent("recipients"), maxLength = k.intIfPresent("maxLength"), rubyBalance = k.intIfPresent("rubyBalance"),
            )
        }
    }
}

/** `send_megaphone` 응답. status 만 필수(없으면 디코드 실패), 나머지는 선택. */
data class MegaphoneSendResponse(
    val status: String,
    val megaphoneId: String? = null,
    val recipients: Long? = null,
    val price: Long? = null,
    val rubyBalance: Long? = null,
    val duplicate: Boolean? = null,
    val need: Long? = null,
    val have: Long? = null,
    val maxLength: Long? = null,
    val retryAfterSeconds: Long? = null,
    val cooldownSeconds: Long? = null,
) {
    companion object {
        fun decode(element: JsonElement): MegaphoneSendResponse {
            val k = swiftKeyed(element)
            return MegaphoneSendResponse(
                status = k.string("status"), megaphoneId = k.stringIfPresent("megaphoneId"), recipients = k.intIfPresent("recipients"),
                price = k.intIfPresent("price"), rubyBalance = k.intIfPresent("rubyBalance"), duplicate = k.boolIfPresent("duplicate"),
                need = k.intIfPresent("need"), have = k.intIfPresent("have"), maxLength = k.intIfPresent("maxLength"),
                retryAfterSeconds = k.intIfPresent("retryAfterSeconds"), cooldownSeconds = k.intIfPresent("cooldownSeconds"),
            )
        }
    }
}

/** 보내기 결과(서버 status 의 번역). 모르는 status 는 [failed]. */
sealed interface MegaphoneSendOutcome {
    data class sent(val recipients: Long, val duplicate: Boolean) : MegaphoneSendOutcome
    data class insufficient(val need: Long?, val have: Long?) : MegaphoneSendOutcome
    data class cooldown(val retryAfterSeconds: Long?) : MegaphoneSendOutcome
    data object noRecipients : MegaphoneSendOutcome
    data object empty : MegaphoneSendOutcome
    data class tooLong(val maxLength: Long?) : MegaphoneSendOutcome
    data object notText : MegaphoneSendOutcome
    data object disabled : MegaphoneSendOutcome
    data object blackout : MegaphoneSendOutcome
    data object unavailable : MegaphoneSendOutcome
    data object failed : MegaphoneSendOutcome

    companion object {
        fun from(response: MegaphoneSendResponse): MegaphoneSendOutcome = when (response.status) {
            "ok" -> sent(response.recipients ?: 0, response.duplicate ?: false)
            "insufficient" -> insufficient(response.need, response.have)
            "cooldown" -> cooldown(response.retryAfterSeconds)
            "no_recipients" -> noRecipients
            "empty" -> empty
            "too_long" -> tooLong(response.maxLength)
            "not_text" -> notText
            "disabled" -> disabled
            "blackout" -> blackout
            else -> failed
        }

        /** throw 로 온 실패 중 결과를 아는 것만 — 함수 없음([BlockReportRules.isMissingFunction])이면 [unavailable], 아니면 null. */
        fun fromError(isMissingFunction: Boolean): MegaphoneSendOutcome? = if (isMissingFunction) unavailable else null
    }
}

/** 확성기 본문 — 메시지 본문 규칙(정규화 · 보이는 글자 · 코드포인트 눈금)을 그대로 쓰되 상한만 앞머리 몫을 뺀다. */
object MegaphoneBody {
    /** 서버가 받는 사람 메시지 앞에 붙이는 머리("📢 "). */
    const val prefix: String = "📢 "
    val maxLength: Int get() = MessageBody.maxLength - prefix.codePointCountCompat()

    fun length(raw: String): Int = MessageBody.length(raw)

    fun validate(raw: String, maxLength: Int? = null): MessageBodyValidation =
        com.yehsung.aingcheck.core.wire.MessageBody.validate(raw, RulesWireTextRules, (maxLength ?: this.maxLength).toLong()).toRules()

    /** 서비스 래퍼의 사전 판정(Swift `sendMegaphone` 앞머리) — 빈/긴 본문은 서버를 부르지 않고 이 응답으로 끝낸다. 보낼 수 있으면 null. */
    fun localRefusal(raw: String): MegaphoneSendResponse? = when (val v = validate(raw)) {
        is MessageBodyValidation.empty -> MegaphoneSendResponse(status = "empty", maxLength = maxLength.toLong())
        is MessageBodyValidation.tooLong -> MegaphoneSendResponse(status = "too_long", maxLength = v.maxLength.toLong())
        is MessageBodyValidation.ok -> null
    }
}

object MegaphoneText {
    const val title = "확성기"
    const val icon = "📢"
    val badgeTitle: String get() = "$icon $title"
    const val explainer = "앱을 쓰는 모두에게 메시지로 가요 · 집중 중인 사람은 빼요"
    const val placeholder = "모두에게 할 말을 적어 주세요"
    const val sendButton = "보내기"
    const val cancelButton = "취소"
    fun sent(recipients: Long): String = "보냈어요 · ${recipients}명에게"
    fun alreadySent(recipients: Long): String = "이미 보냈어요 · ${recipients}명에게"
    fun shortfall(need: Long?, have: Long?): String = SharedText.shortfallNotice(need, have)
    fun cooldown(seconds: Long): String = "${cooldownMinutes(seconds)}분 뒤에 다시 보낼 수 있어요"
    /** 남은 초 → 분(올림, 최소 1). 음수는 0 으로. */
    fun cooldownMinutes(seconds: Long): Long = maxOf(1L, (maxOf(0L, seconds) + 59) / 60)
    const val noRecipients = "받을 사람이 없어요"
    const val unavailable = "지금은 보낼 수 없어요"
    const val empty = "보낼 말을 적어 주세요"
    fun tooLong(maxLength: Long?): String = "확성기는 ${maxLength ?: MegaphoneBody.maxLength.toLong()}자까지예요. 줄여서 보내 주세요"
    val notText: String get() = MessageNoticeText.notText
    val blackout: String get() = MessageNoticeText.blackout
    const val connection = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    const val failed = "보내지 못했어요. 잠시 후 다시 시도해 주세요"
    const val loadingInfo = "받을 사람을 세는 중이에요"
    const val infoFailed = "받을 사람 수를 못 읽었어요"
    fun reach(recipients: Long): String = "지금 보내면 ${recipients}명에게 가요"
    fun confirm(price: Long, recipients: Long): String = "루비 ${price}개로 ${recipients}명에게 보낼까요?"
    fun counter(length: Int, maxLength: Int): String = "$length/$maxLength"

    /** 보내기 결과 → (문구, 오류인가). [MegaphoneRules.cooldownSecondsAfter] 로 정한 남은 초를 받는다. */
    fun notice(outcome: MegaphoneSendOutcome, cooldownLeft: Long): Pair<String, Boolean> = when (outcome) {
        is MegaphoneSendOutcome.sent -> (if (outcome.duplicate) alreadySent(outcome.recipients) else sent(outcome.recipients)) to false
        is MegaphoneSendOutcome.insufficient -> shortfall(outcome.need, outcome.have) to true
        is MegaphoneSendOutcome.cooldown -> cooldown(cooldownLeft) to true
        MegaphoneSendOutcome.noRecipients -> noRecipients to true
        MegaphoneSendOutcome.empty -> empty to true
        is MegaphoneSendOutcome.tooLong -> tooLong(outcome.maxLength) to true
        MegaphoneSendOutcome.notText -> notText to true
        MegaphoneSendOutcome.disabled -> unavailable to true
        MegaphoneSendOutcome.blackout -> blackout to true
        MegaphoneSendOutcome.unavailable -> unavailable to true
        MegaphoneSendOutcome.failed -> failed to true
    }
}

/** 확성기 정보(가격 · 받는 사람 · 상한 · 쿨다운). 시각은 1970 기준 초(Swift Date). */
data class MegaphoneInfo(
    val enabled: Boolean,
    val price: Long,
    val recipients: Long,
    val maxLength: Long,
    val cooldownSeconds: Long,
    val cooldownEndsAt: Double?,
) {
    /** 남은 쿨다운 초(올림). 끝났거나 모르면 0. */
    fun cooldownRemaining(now: Double): Long {
        val ends = cooldownEndsAt ?: return 0
        val left = ends - now
        return if (left > 0) ceil(left).toLong() else 0
    }

    companion object {
        /** `applyInfo` 의 값 부분 — status 'ok' 이고 가격·받는 사람이 있을 때만(아니면 null = 못 읽음). */
        fun from(response: MegaphoneInfoResponse, now: Double): MegaphoneInfo? {
            if (response.status != "ok") return null
            val price = response.price ?: return null
            val recipients = response.recipients ?: return null
            val left = maxOf(0L, response.cooldownRemainingSeconds ?: 0)
            return MegaphoneInfo(
                enabled = response.enabled ?: true,
                price = price,
                recipients = maxOf(0L, recipients),
                maxLength = response.maxLength ?: MegaphoneBody.maxLength.toLong(),
                cooldownSeconds = response.cooldownSeconds ?: MegaphoneRules.defaultCooldownSeconds,
                cooldownEndsAt = if (left > 0) now + left.toDouble() else null,
            )
        }
    }
}

/** 보내기 실패 뒤처리. notice 가 null 이면 문구를 남기지 않는다(오류 표시도 없음). */
data class MegaphoneFailureEffect(val notice: String?, val dropRequestID: Boolean, val serverUnavailable: Boolean, val endsConfirm: Boolean)

/** 보내기 전 판정(Swift `MegaphoneStore.requestSend` 의 순서 그대로) — 화면 상태가 아니라 값만. */
sealed interface MegaphoneSendGate {
    /** 아무 일도 하지 않는다(보내는 중 · 세션 없음). */
    data object ignore : MegaphoneSendGate
    /** 안내만 남긴다. [reloadInfo] 면 정보를 다시 읽는다. */
    data class notice(val text: String, val isError: Boolean, val reloadInfo: Boolean = false) : MegaphoneSendGate
    /** 확인 질문으로 넘어간다. */
    data object confirm : MegaphoneSendGate
}

object MegaphoneRules {
    const val defaultCooldownSeconds: Long = 600

    /**
     * 확인 단계로 갈 수 있는가. 검사 순서가 문구를 정한다: 함수 없음 → 본문(빈 → 긺) → 정보 모름(못 읽었으면 오류, 읽는 중이면 안내 + 다시 읽기)
     * → 꺼짐 → 쿨다운 → 받는 사람 0 → 루비 부족(잔액을 알 때만).
     */
    fun requestSend(
        isSending: Boolean,
        hasSession: Boolean,
        serverUnavailable: Boolean,
        draft: String,
        info: MegaphoneInfo?,
        infoFailed: Boolean,
        rubyBalance: Long?,
        now: Double,
    ): MegaphoneSendGate {
        if (isSending || !hasSession) return MegaphoneSendGate.ignore
        if (serverUnavailable) return MegaphoneSendGate.notice(MegaphoneText.unavailable, true)
        val maxLength = (info?.maxLength ?: MegaphoneBody.maxLength.toLong()).toInt()
        when (val v = MegaphoneBody.validate(draft, maxLength)) {
            MessageBodyValidation.empty -> return MegaphoneSendGate.notice(MegaphoneText.empty, true)
            is MessageBodyValidation.tooLong -> return MegaphoneSendGate.notice(MegaphoneText.tooLong(v.maxLength.toLong()), true)
            is MessageBodyValidation.ok -> Unit
        }
        if (info == null) {
            return MegaphoneSendGate.notice(if (infoFailed) MegaphoneText.infoFailed else MegaphoneText.loadingInfo, infoFailed, reloadInfo = true)
        }
        if (!info.enabled) return MegaphoneSendGate.notice(MegaphoneText.unavailable, true)
        val left = info.cooldownRemaining(now)
        if (left > 0) return MegaphoneSendGate.notice(MegaphoneText.cooldown(left), true)
        if (info.recipients <= 0) return MegaphoneSendGate.notice(MegaphoneText.noRecipients, true)
        if (rubyBalance != null && rubyBalance < info.price) {
            return MegaphoneSendGate.notice(MegaphoneText.shortfall(info.price, rubyBalance), true)
        }
        return MegaphoneSendGate.confirm
    }

    /** 정보 줄(작성 창 위 한 줄) — 함수 없음 → 정보 모름 → 꺼짐 → 쿨다운 → 받는 사람 0 → 도달 수. */
    fun infoLine(serverUnavailable: Boolean, info: MegaphoneInfo?, infoFailed: Boolean, now: Double): String {
        if (serverUnavailable) return MegaphoneText.unavailable
        if (info == null) return if (infoFailed) MegaphoneText.infoFailed else MegaphoneText.loadingInfo
        if (!info.enabled) return MegaphoneText.unavailable
        val left = info.cooldownRemaining(now)
        if (left > 0) return MegaphoneText.cooldown(left)
        if (info.recipients <= 0) return MegaphoneText.noRecipients
        return MegaphoneText.reach(info.recipients)
    }

    /** 정보 응답 뒤 루비 미러 — 정보를 받아들였고(ok · 가격 · 받는 사람) 응답에 잔액이 있을 때만 바꾼다. */
    fun rubyAfterInfo(response: MegaphoneInfoResponse, accepted: MegaphoneInfo?, current: Long?): Long? =
        if (accepted != null && response.rubyBalance != null) response.rubyBalance else current

    /** 보내기 응답 뒤 루비 미러 — 어떤 결과든 응답에 잔액이 있으면 그 값(서버 값만 믿는다). */
    fun rubyAfterSend(response: MegaphoneSendResponse, current: Long?): Long? = response.rubyBalance ?: current

    /** throw 로 끝난 보내기의 뒤처리(C§4 #26). 취소는 말없이 id 를 쥐고, 함수 없음은 id 를 버리고 막고, 그 밖(결과 모름)은 id 를 쥔 채 확인 단계에 남는다. */
    fun afterSendFailure(error: ServiceErrorFacts): MegaphoneFailureEffect = when {
        error == ServiceErrorFacts.cancelled -> MegaphoneFailureEffect(notice = null, dropRequestID = false, serverUnavailable = false, endsConfirm = false)
        BlockReportRules.isMissingFunction(error) ->
            MegaphoneFailureEffect(notice = MegaphoneText.unavailable, dropRequestID = true, serverUnavailable = true, endsConfirm = true)
        else -> MegaphoneFailureEffect(notice = MegaphoneText.connection, dropRequestID = false, serverUnavailable = false, endsConfirm = false)
    }

    /** cooldown 응답 뒤 남은 초: 서버가 준 값 → 아는 정보의 쿨다운 → 기본 600, 최소 1. */
    fun cooldownSecondsAfter(outcome: MegaphoneSendOutcome.cooldown, info: MegaphoneInfo?): Long =
        maxOf(1L, outcome.retryAfterSeconds ?: info?.cooldownSeconds ?: defaultCooldownSeconds)

    /** 보낸 뒤의 정보 갱신(Swift `apply`): 새로 보냈으면 지금부터 쿨다운, cooldown 이면 남은 초, 받는 사람 0 · 꺼짐 반영. */
    fun infoAfter(outcome: MegaphoneSendOutcome, info: MegaphoneInfo?, now: Double): MegaphoneInfo? {
        val known = info ?: return null
        return when (outcome) {
            is MegaphoneSendOutcome.sent -> if (outcome.duplicate) known else known.copy(cooldownEndsAt = now + known.cooldownSeconds.toDouble())
            is MegaphoneSendOutcome.cooldown -> known.copy(cooldownEndsAt = now + cooldownSecondsAfter(outcome, known).toDouble())
            MegaphoneSendOutcome.noRecipients -> known.copy(recipients = 0)
            MegaphoneSendOutcome.disabled -> known.copy(enabled = false)
            else -> known
        }
    }
}

/**
 * 확성기 request_id 쥐기(C§4 #26) — 결과를 모르는 실패(오프라인 · 5xx · 응답 해석 실패 · 취소)면 **쥔 채** 확인 단계에 남아 다시 누르면
 * 같은 id 로 묻는다(서버가 이미 처리했을 수 있다 — 두 번 깎이지 않게). 함수 없음이면 서버에서 아무것도 안 돌았으니 버린다.
 */
class MegaphoneRequestID {
    var pending: String? = null
        private set

    /** 보낼 id — 쥔 것이 있으면 그것, 없으면 새로 만들어 쥔다(접지 않는다 — 소문자 uuid 는 생성기 몫, Swift 와 같다). */
    fun begin(make: () -> String): String {
        pending?.let { return it }
        val made = make()
        pending = made
        return made
    }

    /** 서버가 답을 줬다(어떤 status 든) — 그 id 를 버린다. 그 사이 다른 id 를 쥐었으면 건드리지 않는다. */
    fun settle(requestID: String) {
        if (pending == requestID) pending = null
    }

    /** throw 로 끝났다. 함수 없음이면 버리고, 그 밖(결과 모름 · 취소)은 쥔다. */
    fun failed(isMissingFunction: Boolean) {
        if (isMissingFunction) pending = null
    }

    /** 로그아웃 · 계정 전환. */
    fun reset() {
        pending = null
    }
}
