// 원본: 없음(6차 c-fold — foundation 날짜 파서의 Nd 표가 rules 번들 표(Swift 범위 표)와 한 칸도 다르지 않은지)
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.foundation.text.DecimalDigits
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 날짜 파서는 foundation 에 있고 foundation 은 rules 번들 표([TextScalars])에 기댈 수 없어서, Nd 묶음 시작만 따로 싣는다([DecimalDigits]).
 * 두 표가 갈리면(골든 scalar-classes 를 새 유니코드로 다시 내보냈는데 foundation 표를 안 고쳤다 등) 날짜 칸이 받는 숫자가 Swift 와 달라진다.
 * 그래서 U+0000…U+10FFFF 전부를 rules 표의 답(일반 범주 Nd · 구간 시작에서의 거리 % 10 — 옮기기 전 rules 파서의 식 그대로)과 대조한다.
 */
class DecimalDigitsBundleTest {
    @Test
    fun foundationDecimalDigitsEqualRulesBundleForEveryScalar() {
        var nd = 0
        val mismatches = ArrayList<String>()
        for (cp in 0..0x10FFFF) {
            val want = if (TextScalars.generalCategory(cp) == "Nd") (cp - TextScalars.rangeStartOf(cp)) % 10 else -1
            if (want >= 0) nd++
            val got = DecimalDigits.value(cp)
            if (got != want && mismatches.size < 20) mismatches += "U+${cp.toString(16)}: rules=$want foundation=$got"
            else if (got != want) mismatches += ""
        }
        println("AINGCHECK-CFOLD decimal-digits nd=$nd runs=${DecimalDigits.runCount} mismatches=${mismatches.size}")
        assertTrue(mismatches.isEmpty(), "foundation DecimalDigits 가 rules 번들 표와 ${mismatches.size}칸 다르다:\n" + mismatches.filter { it.isNotEmpty() }.joinToString("\n"))
        // 표의 모양: Nd 는 열 칸 묶음으로만 온다(유니코드 안정성) — 칸 수 = 묶음 × 10.
        assertEquals(nd, DecimalDigits.runCount * 10, "Nd 칸 수가 묶음 수 × 10 이 아니다")
        assertTrue(nd >= 700, "Nd 가 너무 적다($nd) — 표를 못 읽었다")
    }
}
