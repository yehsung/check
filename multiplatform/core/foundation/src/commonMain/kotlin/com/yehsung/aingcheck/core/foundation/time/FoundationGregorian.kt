// 원본: Sources/CheckCore/SupabaseWorkModels.swift:937-977(kstCalendar — lenient date(from:)) · Sources/CheckCore/CheckWorkInsights.swift:616-672(ISO8601DateFormatter) @ 1b8260d
//       — 둘 다 Foundation 그레고리력(속은 ICU GregorianCalendar, 율리우스 전환 1582-10-15). 옛 자리: rules insights KstCalendar.epochDayLenient
package com.yehsung.aingcheck.core.foundation.time

/**
 * Foundation 그레고리력의 날짜 산술 한 벌(날짜 파서 [IcuInternetDate] 와 rules `KstCalendar.date` 가 같이 쓴다 — 두 벌을 두지 않는다).
 * **proleptic 이 아니다**: 1582-10-15 앞은 율리우스력으로 센다(ICU GregorianCalendar 기본 전환 — "0-1-1" 이 이틀 어긋난다, 골든 dates/parse 실측).
 */
object FoundationGregorian {
    /** lenient 날짜 → 1970-01-01 기준 날 수(달 13 → 다음 해, 날 0 → 전달 말일, 날 32 → 다음 달). */
    fun epochDayLenient(year: Long, month: Long, day: Long): Long {
        val m0 = month - 1
        val y = year + m0.floorDiv(12L)
        val m = m0.mod(12L) + 1
        return epochDayOfFirst(y, m) + (day - 1)
    }

    /** 그 달 1일의 날 수. 1582-10 이후는 그레고리력, 그 앞은 율리우스력(JDN 경유). */
    private fun epochDayOfFirst(year: Long, month: Long): Long {
        val gregorian = year > 1582 || (year == 1582L && month >= 10)
        val a = (14 - month) / 12
        val y = year + 4800 - a
        val m = month + 12 * a - 3
        val jdn = if (gregorian) {
            1 + (153 * m + 2) / 5 + 365 * y + y.floorDiv(4L) - y.floorDiv(100L) + y.floorDiv(400L) - 32045
        } else {
            1 + (153 * m + 2) / 5 + 365 * y + y.floorDiv(4L) - 32083
        }
        return jdn - 2_440_588L
    }
}
