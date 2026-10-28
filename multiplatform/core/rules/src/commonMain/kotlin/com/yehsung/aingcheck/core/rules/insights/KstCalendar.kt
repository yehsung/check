// 원본: Sources/CheckCore/SupabaseWorkModels.swift:937-977(TeamWeeklyGoal.kstCalendar · koreanWeekStart · koreanDayStart) ·
//       CheckWorkInsights.swift(WorkInsightsCalendar) · WeeklyWorkReward.swift(WeeklyWorkCalendar) @ 1b8260d — C§2.5 · C§4 #31
package com.yehsung.aingcheck.core.rules.insights

import com.yehsung.aingcheck.core.foundation.time.FoundationGregorian
import com.yehsung.aingcheck.core.foundation.time.KST
import com.yehsung.aingcheck.core.rules.format.parseSwiftInt
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.daysUntil
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime
import kotlin.math.floor
import kotlin.time.Instant

/**
 * KST(Asia/Seoul, 월요일 주 시작) 그레고리력 — Swift `TeamWeeklyGoal.kstCalendar` 의 쓰임을 옮긴 것.
 * **시각은 Swift `Date` 처럼 1970 기준 초 Double** 로 든다(C§2.5 — `Instant` 의 정수 나노 산술로 바꾸지 않는다: 경계에서 1초 갈림).
 * 달력 연산(시작·더하기·차이)만 kotlinx-datetime(tzdb)에 맡긴다. 기기 시간대로 계산하지 않는다.
 */
object KstCalendar {
    /** Double 초 → Instant(소수부는 나노초로 내림). */
    fun instant(seconds: Double): Instant {
        val whole = floor(seconds)
        val nanos = ((seconds - whole) * 1e9).toLong().coerceIn(0L, 999_999_999L)
        return Instant.fromEpochSeconds(whole.toLong(), nanos)
    }

    /** Instant → Double 초. */
    fun seconds(instant: Instant): Double = instant.epochSeconds.toDouble() + instant.nanosecondsOfSecond / 1e9

    fun localDateTime(seconds: Double): LocalDateTime = instant(seconds).toLocalDateTime(KST)

    fun localDate(seconds: Double): LocalDate = localDateTime(seconds).date

    /** 그 날 KST 0시(`startOfDay`). */
    fun dayStart(seconds: Double): Double = seconds(localDate(seconds).atStartOfDayIn(KST))

    /** 그 주 월요일 KST 0시(`dateInterval(of: .weekOfYear)` — firstWeekday 2). */
    fun weekStart(seconds: Double): Double {
        val date = localDate(seconds)
        return seconds(date.minus(DatePeriod(days = date.dayOfWeek.ordinal)).atStartOfDayIn(KST))
    }

    /** 요일 인덱스 0=월 … 6=일. */
    fun weekdayIndex(seconds: Double): Int = localDate(seconds).dayOfWeek.ordinal

    /** 그 시각이 속한 KST 정시의 시작. */
    fun hourStart(seconds: Double): Double {
        val local = localDateTime(seconds)
        return seconds(LocalDateTime(local.year, local.month, local.day, local.hour, 0, 0).toInstant(KST))
    }

    /** `date(byAdding: .day, value:)` — 벽시계를 지키는 날 더하기. */
    fun addDays(seconds: Double, days: Int): Double = seconds(instant(seconds).plus(days, DateTimeUnit.DAY, KST))

    /** `date(byAdding: .weekOfYear, value:)`. */
    fun addWeeks(seconds: Double, weeks: Int): Double = addDays(seconds, weeks * 7)

    /** `date(byAdding: .month, value:)`. */
    fun addMonths(seconds: Double, months: Int): Double = seconds(instant(seconds).plus(months, DateTimeUnit.MONTH, KST))

    /** `date(byAdding: .hour, value:)` — 시간은 절대 길이(3600초). */
    fun addHours(seconds: Double, hours: Int): Double = seconds + hours * 3_600.0

    /** `dateComponents([.day], from:, to:).day` — 온전한 날 수(0 쪽으로 자름). */
    fun daysBetween(from: Double, to: Double): Int = instant(from).daysUntil(instant(to), KST)

    /** `dateComponents([.weekOfYear], from:, to:).weekOfYear` — 온전한 주 수. */
    fun weeksBetween(from: Double, to: Double): Int = daysBetween(from, to) / 7

    /**
     * `date(from: DateComponents(year:month:day:hour:))` — **lenient**(달 13 → 다음 해, 날 0 → 전달 말일) · Foundation 그레고리력은
     * **1582-10-15 앞을 율리우스력**으로 센다(proleptic 아님 — "0-1-1" 이 이틀 어긋난다, 골든 dates/parse 실측).
     */
    fun date(year: Int, month: Int, day: Int, hour: Int = 0): Double? = try {
        val epochDay = FoundationGregorian.epochDayLenient(year.toLong(), month.toLong(), day.toLong())   // 날짜 파서와 한 벌(c-fold)
        val local = LocalDate.fromEpochDays(epochDay)
        seconds(LocalDateTime(local.year, local.month, local.day, hour, 0, 0).toInstant(KST))
    } catch (e: RuntimeException) {
        null   // 범위 밖 해(kotlinx LocalDate 상한)
    }

    /**
     * 'YYYY-MM-DD' → 그 날 KST 0시(Swift `WeeklyWorkCalendar.kstMidnight` · `TokenDailyGrid.date(fromDay:)` · `TeamLeagueWeekNavigator.date(forKey:)`
     * — 세 자리가 같은 식이다): '-' 로 나눠(빈 조각 없음) 정수가 아닌 조각은 **버리고** 셋이면 lenient 날짜.
     */
    fun midnight(day: String?): Double? {
        if (day == null) return null
        val parts = day.split('-').filter { it.isNotEmpty() }.mapNotNull { parseSwiftInt(it) }
        if (parts.size != 3) return null
        val (y, m, d) = parts
        if (y !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() || m !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() ||
            d !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) return null
        return date(y.toInt(), m.toInt(), d.toInt())
    }

    /** "%04d-%02d-%02d" 날짜 키(KST). */
    fun dayString(seconds: Double): String {
        val d = localDate(seconds)
        return "${pad(d.year, 4)}-${pad(d.month.ordinal + 1, 2)}-${pad(d.day, 2)}"
    }

    /** "%04d%02d%02d"(MilestoneTracker.dayKey). */
    fun compactDayKey(seconds: Double): String {
        val d = localDate(seconds)
        return "${pad(d.year, 4)}${pad(d.month.ordinal + 1, 2)}${pad(d.day, 2)}"
    }

    /** "%04d-%02d"(TokenUsageMonthKey.current). */
    fun monthKey(seconds: Double): String {
        val d = localDate(seconds)
        return "${pad(d.year, 4)}-${pad(d.month.ordinal + 1, 2)}"
    }

    /** printf `%0Nd`(음수는 부호 뒤 0 채움 — C 와 같다). */
    internal fun pad(value: Int, width: Int): String {
        val digits = kotlin.math.abs(value.toLong()).toString()
        val sign = if (value < 0) "-" else ""
        val body = digits.padStart(width - sign.length, '0')
        return sign + body
    }
}
