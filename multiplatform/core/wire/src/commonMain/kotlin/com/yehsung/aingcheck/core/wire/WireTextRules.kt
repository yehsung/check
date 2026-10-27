// 원본: Sources/CheckCore/SupabaseWorkModels.swift:2368-2502(MessageBody · MessageBodyValidation · MessageSendOutcome) · CheckCore/StatusMessage.swift:84-89(display) @ 1b8260d
package com.yehsung.aingcheck.core.wire

/**
 * 글자 규칙 이음새. NFC·보이는 글자 판정(유니코드 범위 표)은 W1-c `rules/text` 몫이고(§8-16 ② — `Character.getType` 금지),
 * wire·net 은 rules 에 기댈 수 없다(의존 방향 rules → wire). 그래서 서비스가 받는 **함수 묶음**으로 둔다 — 앱 조립(K11)이
 * W1-c 구현을 넣는다. 시험은 자기 구현을 넣는다(요청 골든은 본문만 견준다).
 */
interface WireTextRules {
    // INV-SupabaseWorkModels-8834c927 이식: (계약) 가운데 개행은 지우지 않는다 — 앞뒤만 자른다(구현은 W1-c rules/text).
    /** Swift `MessageBody.sanitized` — NFC 뒤 앞뒤 공백·줄바꿈을 자른다. */
    fun sanitized(raw: String): String

    /** Swift `MessageBody.hasVisibleContent`. */
    fun hasVisibleContent(text: String): Boolean

    /** 유니코드 스칼라 수(서버 `char_length` 와 같은 눈금 — `String.length`(UTF-16)가 아니다). */
    fun scalarCount(text: String): Int = text.codePointCountCompat()

    /** Swift `StatusMessage.display` — nil·빈 값·보이는 글자 없는 값은 null. */
    fun statusMessageDisplay(raw: String?): String? {
        if (raw == null) return null
        val normalized = statusMessageSanitized(raw)
        return if (normalized.isNotEmpty() && hasVisibleContent(normalized)) normalized else null
    }

    /** Swift `StatusMessage.sanitized`(NFC · 줄바꿈류 접기 · 명시 집합으로 자르기 — W1-c). */
    fun statusMessageSanitized(raw: String): String
}

/** UTF-16 대리쌍을 하나로 센 코드포인트 수(commonMain 에서 쓸 수 있게 손으로). */
fun String.codePointCountCompat(): Int {
    var count = 0
    var i = 0
    while (i < length) {
        val c = this[i]
        i += if (c.isHighSurrogate() && i + 1 < length && this[i + 1].isLowSurrogate()) 2 else 1
        count++
    }
    return count
}

/** Swift `MessageBodyValidation`. */
sealed interface MessageBodyValidation {
    data class Ok(val text: String) : MessageBodyValidation
    data object Empty : MessageBodyValidation
    data class TooLong(val maxLength: Long) : MessageBodyValidation
}

/** Swift `MessageBody` 의 한도·판정(글자 규칙은 [WireTextRules]). 전선은 정규화한 글자를 싣는다. */
object MessageBody {
    const val maxLength: Long = 200

    // INV-SupabaseWorkModels-688bdc37 이식: 세는 단위는 유니코드 스칼라(서버 char_length 와 같은 눈금) — 자소로 세면 화면만 통과한다.
    fun validate(raw: String, rules: WireTextRules, limit: Long = maxLength): MessageBodyValidation {
        val normalized = rules.sanitized(raw)
        if (!rules.hasVisibleContent(normalized)) return MessageBodyValidation.Empty
        if (rules.scalarCount(normalized) > limit) return MessageBodyValidation.TooLong(limit)
        return MessageBodyValidation.Ok(normalized)
    }

    fun length(raw: String, rules: WireTextRules): Int = rules.scalarCount(rules.sanitized(raw))
}

/** Swift `GomokuChatBody`(대결 채팅 — 한도 100). */
object GomokuChatBody {
    const val maxLength: Long = 100
    fun validate(raw: String, rules: WireTextRules, maxLength: Long = this.maxLength): MessageBodyValidation =
        MessageBody.validate(raw, rules, maxLength)
}

/** Swift `ContentReportDetail`(신고 상세 — 한도 200, 보이는 글자가 없으면 null 을 싣는다). */
object ContentReportDetail {
    const val maxLength: Long = 200
    fun payload(raw: String, rules: WireTextRules): String? {
        val normalized = rules.sanitized(raw)
        return if (rules.hasVisibleContent(normalized)) normalized else null
    }
    fun isWithinLimit(raw: String, rules: WireTextRules): Boolean = MessageBody.length(raw, rules) <= maxLength
}
