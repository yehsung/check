// 원본: Sources/CheckCore/CheckTokenUsage.swift:243-300(TokenNumberFormatter) @ 1b8260d (C§4 #32 숫자 표시)
package com.yehsung.aingcheck.core.rules.format

/** 토큰 수 표기 — 로캘 비의존 수동 조립 · 정수 연산만(Double 경계 오차 없음). */
object TokenNumberFormatter {
    /** 콤마 천 단위 **전체 숫자**(축약 없음). 음수는 0. */
    fun grouped(value: Long): String {
        val digits = maxOf(0L, value).toString()
        val out = StringBuilder()
        var count = 0
        for (ch in digits.reversed()) {
            if (count > 0 && count % 3 == 0) out.append(',')
            out.append(ch)
            count++
        }
        return out.reverse().toString()
    }

    /**
     * 좁은 보조 캡션 전용 축약("Claude 196.6억 · Codex 254만"). 1억 이상 억(1000억 미만 소수 첫째 반올림 · .0 떼기, 이상은 정수 반올림),
     * 1만 이상 만(반올림이 1억에 닿으면 "1억"), 그 미만 grouped, 0 이하 "0".
     */
    fun compactKorean(value: Long): String {
        if (value <= 0) return "0"
        val eok = 100_000_000L
        val man = 10_000L
        if (value >= eok) {
            if (value >= 1_000 * eok) return grouped((value + eok / 2) / eok) + "억"
            val tenths = (value * 10 + eok / 2) / eok
            val whole = tenths / 10
            val frac = tenths % 10
            return if (frac == 0L) grouped(whole) + "억" else grouped(whole) + ".${frac}억"
        }
        if (value >= man) {
            val rounded = (value + man / 2) / man
            return if (rounded >= man) "1억" else grouped(rounded) + "만"
        }
        return grouped(value)
    }
}
