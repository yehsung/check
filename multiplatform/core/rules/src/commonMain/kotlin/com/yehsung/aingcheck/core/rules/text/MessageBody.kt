// 원본: Sources/CheckCore/SupabaseWorkModels.swift:2379-2450(MessageBodyValidation · MessageBody) @ 1b8260d
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.MessageBody as WireMessageBody
import com.yehsung.aingcheck.core.wire.MessageBodyValidation as WireMessageBodyValidation

/**
 * W1-d 와이어의 글자 규칙 이음새([WireTextRules])에 꽂는 **실제 구현**(병합 접기 — 검증 지적: 같은 규칙의 사본이 둘이었다).
 * 한도 · 검사 순서는 와이어(`core.wire.MessageBody` · `ContentReportDetail` · `statusMessageDisplay`)가 한 벌로 갖고, 글자 기초
 * (NFC · 보이는 글자 번들 표 · 상태메시지 다듬기)는 여기(rules/text)가 댄다. 앱 조립(K11)은 서비스에 이 객체를 넘긴다.
 * rules 쪽 `MessageBody` · `ContentReportDetail` · `StatusMessage.display` 는 와이어 판정을 부르는 얇은 겉이라 골든
 * text/sanitize · text/block-report · text/megaphone · text/status-message 가 와이어 판정까지 잰다.
 */
object RulesWireTextRules : WireTextRules {
    override fun sanitized(raw: String): String = MessageBody.sanitized(raw)
    override fun hasVisibleContent(text: String): Boolean = MessageBody.hasVisibleContent(text)
    override fun statusMessageSanitized(raw: String): String = StatusMessage.sanitized(raw)
}

internal fun WireMessageBodyValidation.toRules(): MessageBodyValidation = when (this) {
    is WireMessageBodyValidation.Ok -> MessageBodyValidation.ok(text)
    WireMessageBodyValidation.Empty -> MessageBodyValidation.empty
    is WireMessageBodyValidation.TooLong -> MessageBodyValidation.tooLong(maxLength.toInt())
}

/** 메시지 본문 사전 판정 결과(Swift `MessageBodyValidation`) — 와이어 판정([WireMessageBodyValidation])을 rules 모양으로. */
sealed interface MessageBodyValidation {
    /** 실제로 보낼 문자열(정규화 완료). 원문이 아니라 **이 값**을 서버로 보내야 한다. */
    data class ok(val value: String) : MessageBodyValidation
    /** 비었거나, 눈에 보이는 글자가 하나도 없다(공백·제어문자·폭 0 채움문자만 있는 입력). */
    data object empty : MessageBodyValidation
    data class tooLong(val maxLength: Int) : MessageBodyValidation
}

/**
 * 메시지 본문의 정규화·길이 판정(Swift `MessageBody`). 입력 카운터·전송 게이트·네트워크 계층이 같은 답을 내야 한다 —
 * 판정의 최종 권위는 서버이고 여기 있는 것은 헛왕복을 줄이는 사전 게이트다.
 */
object MessageBody {
    /** 상한. **단위는 유니코드 스칼라(코드포인트)** 이고 서버 `char_length` 와 같은 눈금이다(String.length·그래핌으로 세지 않는다). */
    val maxLength: Int = WireMessageBody.maxLength.toInt()

    /**
     * 사용자 입력 → 실제로 보낼 문자열: ① NFC(맥 입력기·파인더 붙여넣기의 자모 분해를 합친다) ② 앞뒤 공백·개행 trim.
     *
     * ★ 가운데 개행은 지우지 않는다(Swift 주석 그대로) — trim 은 앞뒤만. 200자 창에서 Enter 는 줄바꿈이다.
     * trim 집합은 Foundation `.whitespacesAndNewlines`(번들 표 비트 ②)다. Kotlin `trim()`·`isWhitespace` 를 쓰지 않는다(집합이 다르다).
     */
    fun sanitized(raw: String): String = TextScalars.trimmingWhitespacesAndNewlines(TextNormalization.nfc(raw))

    /** 서버와 **같은 눈금**의 길이(정규화 후 코드포인트 수). 화면 카운터("N/200")도 이 값을 쓴다. */
    fun length(raw: String): Int = WireMessageBody.length(raw, RulesWireTextRules)

    /**
     * 눈에 보이는 글자가 하나라도 있는가. 한글 채움(U+3164)처럼 폭 0 인 '글자'는 보이지 않는다(별명 사칭에 뚫린 전례).
     * 판정은 스칼라마다 번들 표의 보이는 글자 비트다(= Swift 의 White_Space · 채움 다섯 · 범주 Cc Cf Cs Cn Zs Zl Zp 제외 규칙의 결과).
     */
    fun hasVisibleContent(text: String): Boolean {
        val cps = text.codePointArray()
        for (cp in cps) if (TextScalars.isVisible(cp)) return true
        return false
    }

    /** **검사 순서가 문구를 정한다.** 빈 판정이 먼저다 — 공백만 200자 친 입력에 "200자까지예요"라고 하지 않는다(와이어 판정 한 벌). */
    fun validate(raw: String): MessageBodyValidation = WireMessageBody.validate(raw, RulesWireTextRules).toRules()
}
