// W-6 #4: h3 사본을 걷고 모은 utcRetainFromKey — 다른 구현(java.time)과 대조한다(기억 comparison-baseline-must-differ).
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class TokenMonthKeysTest {
    @Test
    fun utcRetainFromKeyIsDayBeforeMonthStartAgainstJavaTime() {
        for (year in listOf(1900, 1999, 2000, 2024, 2025, 2026, 2100, 2400)) {
            for (month in 1..12) {
                val key = "$year-${month.toString().padStart(2, '0')}"
                val expected = LocalDate.of(year, month, 1).minusDays(1).toString()
                assertEquals(expected, TokenMonthKeys.utcRetainFromKey(key), key)
                assertEquals(expected, TokenUsageIncrementalScanner.utcRetainFromKey(key), "스캐너도 같은 함수: $key")
            }
        }
    }

    @Test
    fun malformedKeysAreEmpty() {
        for (bad in listOf("", "2026", "2026-13", "2026-00", "2026-1-1", "x-01", "2026-xx")) {
            assertEquals("", TokenMonthKeys.utcRetainFromKey(bad), bad)
        }
    }
}
