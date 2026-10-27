// 원본: Sources/CheckCore/SupabaseWorkModels.swift:2379-2450(MessageBodyValidation · MessageBody) @ 1b8260d
package com.yehsung.aingcheck.core.rules.text

/**
 * 메시지 본문 사전 판정 결과(Swift `MessageBodyValidation`).
 *
 * 와이어 파일(SupabaseWorkModels)에 있던 **글자 규칙**이다(C§3.2 C-1 "와이어 파일에 있지만 규칙이다"). 보이는 글자 판정이
 * G §8-16 ② 의 번들 표에 기대므로 글자 규칙 자리(rules/text)에 둔다 — 와이어(W1-d)는 rules 를 부를 수 없으니(의존 rules → wire)
 * W1-d 는 글자 기초를 `WireTextRules` 이음새로 받는다. 병합 때 조정자 접기 패치(W1-c 5차 04)가 이 구현을 그 이음새에 꽂고, 한도 · 검사
 * 순서는 와이어 판정 한 벌로 모은다(같은 규칙의 사본이 둘이 되지 않게).
 */
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
    const val maxLength: Int = 200

    /**
     * 사용자 입력 → 실제로 보낼 문자열: ① NFC(맥 입력기·파인더 붙여넣기의 자모 분해를 합친다) ② 앞뒤 공백·개행 trim.
     *
     * ★ 가운데 개행은 지우지 않는다(Swift 주석 그대로) — trim 은 앞뒤만. 200자 창에서 Enter 는 줄바꿈이다.
     * trim 집합은 Foundation `.whitespacesAndNewlines`(번들 표 비트 ②)다. Kotlin `trim()`·`isWhitespace` 를 쓰지 않는다(집합이 다르다).
     */
    fun sanitized(raw: String): String = TextScalars.trimmingWhitespacesAndNewlines(TextNormalization.nfc(raw))

    /** 서버와 **같은 눈금**의 길이(정규화 후 코드포인트 수). 화면 카운터("N/200")도 이 값을 쓴다. */
    fun length(raw: String): Int = sanitized(raw).codePointCountCompat()

    /**
     * 눈에 보이는 글자가 하나라도 있는가. 한글 채움(U+3164)처럼 폭 0 인 '글자'는 보이지 않는다(별명 사칭에 뚫린 전례).
     * 판정은 스칼라마다 번들 표의 보이는 글자 비트다(= Swift 의 White_Space · 채움 다섯 · 범주 Cc Cf Cs Cn Zs Zl Zp 제외 규칙의 결과).
     */
    fun hasVisibleContent(text: String): Boolean {
        val cps = text.codePointArray()
        for (cp in cps) if (TextScalars.isVisible(cp)) return true
        return false
    }

    /** **검사 순서가 문구를 정한다.** 빈 판정이 먼저다 — 공백만 200자 친 입력에 "200자까지예요"라고 하지 않는다. */
    fun validate(raw: String): MessageBodyValidation {
        val normalized = sanitized(raw)
        if (!hasVisibleContent(normalized)) return MessageBodyValidation.empty
        if (normalized.codePointCountCompat() > maxLength) return MessageBodyValidation.tooLong(maxLength)
        return MessageBodyValidation.ok(normalized)
    }
}
