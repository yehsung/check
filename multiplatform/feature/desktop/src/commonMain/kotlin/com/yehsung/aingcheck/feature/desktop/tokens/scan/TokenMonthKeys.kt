// W2-h1 소유 규칙(공용 자리) — 스캐너(desktopMain tokens/scan)와 업로드 본문(commonMain tokens/upload, W2-h3)이 같은 함수를 부른다.
// 원본: Sources/CheckCore/CheckTokenUsage.swift:1975 (TokenUsageIncrementalScanner.utcRetainFromKey). W-6 #4: h3 사본을 걷고 여기로 모았다.
package com.yehsung.aingcheck.feature.desktop.tokens.scan

object TokenMonthKeys {
    /** UTC 일별 보존 하한 = 그 KST 월 1일의 전날("2026-10" → "2026-09-30"). 형식이 아니면 "". */
    fun utcRetainFromKey(monthString: String): String {
        val parts = monthString.split('-')
        if (parts.size != 2) return ""
        val y = parts[0].toIntOrNull() ?: return ""
        val m = parts[1].toIntOrNull() ?: return ""
        if (m !in 1..12) return ""
        val (py, pm) = if (m == 1) (y - 1) to 12 else y to (m - 1)
        return "${py.toString().padStart(4, '0')}-${pm.toString().padStart(2, '0')}-${daysInMonth(py, pm).toString().padStart(2, '0')}"
    }

    private fun daysInMonth(year: Int, month: Int): Int = when (month) {
        1, 3, 5, 7, 8, 10, 12 -> 31
        4, 6, 9, 11 -> 30
        else -> if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) 29 else 28
    }
}
