// 원본: Sources/CheckCore/CheckWorkInsights.swift @ 1b8260d (C§5.1 E11 — 히트맵·회고·잔디. TokenDailyMerge.localTotals 는 맥 로컬 스캐너 몫이라 W2-h(Windows 보류))
package com.yehsung.aingcheck.core.rules.insights

import com.yehsung.aingcheck.core.foundation.time.IcuInternetDate
import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.SwiftDate
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.format.parseSwiftInt
import com.yehsung.aingcheck.core.rules.token.CodexEffectiveRule
import com.yehsung.aingcheck.core.rules.token.TokenRowDisplayRule
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.rules.text.codePointArray

// 개인 근무 기록 인사이트의 순수 계산 계층. 서버는 work_sessions 원본 행만 주고 분해·요약은 전부 여기서 결정적으로 계산한다.
// 모든 시간 경계는 KST. 시각은 1970 기준 초 Double(C§2.5 — Swift Date 와 1:1, 조각의 초는 Int(차) 로 자른다).

/** 서버 work_sessions 한 행 중 인사이트가 읽는 두 칸(Swift `WorkSessionRow` — 와이어 행은 W1-d, 병합 뒤 W2-c 가 넘긴다). */
data class WorkSessionTimes(val startedAt: String, val endedAt: String?)

/** 파싱을 끝낸 완료 세션(시작·종료 초). 히트맵과 회고가 같은 배열을 나눠 쓴다. */
data class WorkInsightsSession(val start: Double, val end: Double)

/** 히트맵과 회고가 **정확히 같은 주**를 보도록 주 경계를 한곳에서만 정한다. */
object WorkInsightsWeekWindow {
    data class Window(val start: Double, val end: Double, val previousStart: Double)

    /** now 가 속한 KST 주의 **직전 주**: start = 지난주 월 0시 · end = 이번 주 월 0시(배타) · previousStart = 그 전주 월 0시. */
    fun lastWeek(now: Double): Window {
        val thisWeekStart = KstCalendar.weekStart(now)
        return Window(KstCalendar.addWeeks(thisWeekStart, -1), thisWeekStart, KstCalendar.addWeeks(thisWeekStart, -2))
    }
}

/** 개인 근무 리듬 히트맵: 요일(0=월) × 시간대(0…23)에 **지난주 한 주** 동안 근무한 초(한 칸 최대 3600). */
data class WorkRhythmHeatmap(val buckets: List<List<Long>>, val totalSeconds: Long) {
    val maxBucketSeconds: Long get() = buckets.fold(0L) { partial, row -> maxOf(partial, row.maxOrNull() ?: 0L) }

    /** 가장 근무가 많았던 (요일, 시간) — 강부등호라 동률은 앞선 칸. 데이터 없으면 null. */
    val peakSlot: Pair<Int, Int>?
        get() {
            var best: Triple<Int, Int, Long>? = null
            for (day in 0 until DAY_COUNT) for (hour in 0 until HOUR_COUNT) {
                if (buckets[day][hour] > (best?.third ?: 0L)) best = Triple(day, hour, buckets[day][hour])
            }
            return best?.let { it.first to it.second }
        }

    companion object {
        const val DAY_COUNT = 7
        const val HOUR_COUNT = 24
        val empty: WorkRhythmHeatmap get() = WorkRhythmHeatmap(List(DAY_COUNT) { List(HOUR_COUNT) { 0L } }, 0)

        /** Swift `build(sessions:now:)` — JVM 서명 충돌을 피해 이름을 갈랐다(같은 계산 경로). */
        fun buildFromRows(sessions: List<WorkSessionTimes>, now: Double): WorkRhythmHeatmap = build(WorkInsightsDate.parseSessions(sessions), now)

        /** 지난주 창에 걸친 세션은 겹치는 구간만, 그 구간을 KST 정시 경계로 쪼개 각 칸에 실제로 머문 초만 더한다. */
        fun build(parsed: List<WorkInsightsSession>, now: Double): WorkRhythmHeatmap {
            val window = WorkInsightsWeekWindow.lastWeek(now)
            val buckets = Array(DAY_COUNT) { LongArray(HOUR_COUNT) }
            var total = 0L
            for (session in parsed) {
                var cursor = maxOf(session.start, window.start)
                val end = minOf(session.end, window.end)
                if (!(cursor < end)) continue
                while (cursor < end) {
                    val hourStart = KstCalendar.hourStart(cursor)
                    val nextHour = KstCalendar.addHours(hourStart, 1)
                    if (!(nextHour > cursor)) break
                    val sliceEnd = minOf(nextHour, end)
                    if (!(sliceEnd > cursor)) break
                    val seconds = (sliceEnd - cursor).toLong()
                    if (seconds > 0) {
                        buckets[KstCalendar.weekdayIndex(hourStart)][KstCalendar.localDateTime(hourStart).hour] += seconds
                        total += seconds
                    }
                    cursor = sliceEnd
                }
            }
            return WorkRhythmHeatmap(buckets.map { it.toList() }, total)
        }
    }
}

/** 지난주 회고 요약. */
data class WeeklyRetro(
    val weekStart: Double,
    val totalSeconds: Long,
    val goalSeconds: Long,
    val previousWeekSeconds: Long,
    val sessionCount: Int,
    val busiestDayIndex: Int?,
    val busiestDaySeconds: Long,
) {
    val metGoal: Boolean get() = goalSeconds > 0 && totalSeconds >= goalSeconds
    val deltaSeconds: Long get() = totalSeconds - previousWeekSeconds

    /** 주 집계는 그대로, 목표선만 갈아 끼운 사본(멤버십 응답이 늦게 와도 세션을 다시 받지 않는다). */
    fun withGoal(goalSeconds: Long): WeeklyRetro = copy(goalSeconds = goalSeconds)

    companion object {
        /** Swift `build(sessions:now:goalSeconds:)` — JVM 서명 충돌을 피해 이름을 갈랐다. */
        fun buildFromRows(sessions: List<WorkSessionTimes>, now: Double, goalSeconds: Long): WeeklyRetro? =
            build(WorkInsightsDate.parseSessions(sessions), now, goalSeconds)

        /** 지난주 근무가 없으면 null. 주 경계에 걸친 세션은 겹치는 구간만 하루 경계로 쪼개 귀속한다. */
        fun build(parsed: List<WorkInsightsSession>, now: Double, goalSeconds: Long): WeeklyRetro? {
            val window = WorkInsightsWeekWindow.lastWeek(now)
            val lastWeekStart = window.start
            val thisWeekStart = window.end
            val previousWeekStart = window.previousStart
            val dayTotals = LongArray(WorkRhythmHeatmap.DAY_COUNT)
            var total = 0L
            var sessionCount = 0
            var previousTotal = 0L
            for (session in parsed) {
                val started = session.start
                val ended = session.end
                if (!(ended > previousWeekStart && started < thisWeekStart)) continue
                var cursor = maxOf(started, lastWeekStart)
                val weekEnd = minOf(ended, thisWeekStart)
                if (cursor < weekEnd) {
                    sessionCount += 1
                    while (cursor < weekEnd) {
                        val dayStart = KstCalendar.dayStart(cursor)
                        val nextDay = KstCalendar.addDays(dayStart, 1)
                        if (!(nextDay > cursor)) break
                        val sliceEnd = minOf(nextDay, weekEnd)
                        if (!(sliceEnd > cursor)) break
                        val seconds = (sliceEnd - cursor).toLong()
                        if (seconds > 0) {
                            dayTotals[KstCalendar.weekdayIndex(dayStart)] += seconds
                            total += seconds
                        }
                        cursor = sliceEnd
                    }
                }
                val previousStart = maxOf(started, previousWeekStart)
                val previousEnd = minOf(ended, lastWeekStart)
                if (previousEnd > previousStart) previousTotal += (previousEnd - previousStart).toLong()
            }
            if (total <= 0) return null
            var busiestDayIndex: Int? = null
            var busiestDaySeconds = 0L
            for (index in 0 until WorkRhythmHeatmap.DAY_COUNT) {
                if (dayTotals[index] > busiestDaySeconds) {
                    busiestDayIndex = index
                    busiestDaySeconds = dayTotals[index]
                }
            }
            return WeeklyRetro(lastWeekStart, total, goalSeconds, previousTotal, sessionCount, busiestDayIndex, busiestDaySeconds)
        }
    }
}

/** 최근 13주 **일별** 근무 초(잔디 — 주 열 × 요일 행). 미래 칸 = 0, [isFuture] 로 가른다. */
data class WorkDailyGrid(val weekStart: Double, val weeks: Int, val seconds: List<List<Long>>, val days: Int) {
    val totalSeconds: Long get() = seconds.sumOf { it.sum() }

    fun isFuture(week: Int, weekday: Int): Boolean = week * WorkRhythmHeatmap.DAY_COUNT + weekday >= days

    fun date(week: Int, weekday: Int): Double = KstCalendar.addDays(weekStart, week * WorkRhythmHeatmap.DAY_COUNT + weekday)

    companion object {
        const val defaultWeeks = 13
        /** 잔디 농도의 분모 = 하루 8시간(고정). */
        const val fullDaySeconds = 8 * 3_600
        val empty = WorkDailyGrid(Double.NEGATIVE_INFINITY, 0, emptyList(), 0)

        /** 0 은 "근무 없음", 그 외는 헤더와 같은 "4시간 12분". */
        fun tooltipValueText(seconds: Long): String = if (seconds > 0) MenuBarStatusFormatter.hoursMinutes(seconds) else "근무 없음"

        /** 창의 시작 = 이번 주 월요일 − (weeks − 1)주. */
        fun windowStart(now: Double, weeks: Int = defaultWeeks): Double = KstCalendar.addWeeks(KstCalendar.weekStart(now), -(maxOf(1, weeks) - 1))

        /** 완료 세션 + 진행 중 세션(지금까지)으로 잔디를 만든다 — 창 앞은 버리고 끝은 now 로 자른다(미래 칸 = 0). */
        fun build(parsed: List<WorkInsightsSession>, now: Double, ongoingStart: Double? = null, weeks: Int = defaultWeeks): WorkDailyGrid {
            val weekCount = maxOf(1, weeks)
            val weekStart = windowStart(now, weekCount)
            val todayOffset = KstCalendar.daysBetween(weekStart, KstCalendar.dayStart(now))
            val dayCount = WorkRhythmHeatmap.DAY_COUNT
            val seconds = Array(weekCount) { LongArray(dayCount) }
            val sessions = ArrayList(parsed)
            if (ongoingStart != null && ongoingStart < now) sessions += WorkInsightsSession(ongoingStart, now)
            for (session in sessions) {
                var cursor = maxOf(session.start, weekStart)
                val end = minOf(session.end, now)
                if (!(cursor < end)) continue
                while (cursor < end) {
                    val dayStart = KstCalendar.dayStart(cursor)
                    val nextDay = KstCalendar.addDays(dayStart, 1)
                    if (!(nextDay > cursor)) break
                    val sliceEnd = minOf(nextDay, end)
                    if (!(sliceEnd > cursor)) break
                    val slice = (sliceEnd - cursor).toLong()
                    if (slice > 0) {
                        val offset = KstCalendar.daysBetween(weekStart, dayStart)
                        if (offset >= 0 && offset < weekCount * dayCount) seconds[offset / dayCount][offset % dayCount] += slice
                    }
                    cursor = sliceEnd
                }
            }
            return WorkDailyGrid(weekStart, weekCount, seconds.map { it.toList() }, todayOffset + 1)
        }
    }
}

/** 서버 일별 토큰 한 행 중 잔디가 읽는 칸(Swift `TokenUsageDailyRow` — 와이어 행은 W1-d). */
data class TokenDailyRowFacts(val day: String, val claudeTotal: Long, val codexTotal: Long, val codexAccount: Long?, val codexUtcTotal: Long?)

/** 최근 13주 **일별 AI 토큰** 잔디 — 근무 잔디와 같은 창 · 미래 칸 규칙. */
data class TokenDailyGrid(val weekStart: Double, val weeks: Int, val tokens: List<List<Long>>, val days: Int) {
    val totalTokens: Long get() = tokens.sumOf { it.sum() }

    fun isFuture(week: Int, weekday: Int): Boolean = week * WorkRhythmHeatmap.DAY_COUNT + weekday >= days

    /** 서버 조회 실패 때의 겹치기: 같은 창일 때만 칸별 max(미래 칸 제외). */
    fun overlaying(other: TokenDailyGrid): TokenDailyGrid {
        if (weeks <= 0 || other.weeks != weeks || other.weekStart != weekStart) return this
        val merged = tokens.map { it.toMutableList() }
        for (week in 0 until weeks) for (weekday in 0 until WorkRhythmHeatmap.DAY_COUNT) {
            if (!isFuture(week, weekday)) merged[week][weekday] = maxOf(tokens[week][weekday], other.tokens[week][weekday])
        }
        return copy(tokens = merged)
    }

    companion object {
        /** 잔디 농도의 분모(토큰/일) = 5천만 고정. */
        const val fullDayTokens = 50_000_000L
        val empty = TokenDailyGrid(Double.NEGATIVE_INFINITY, 0, emptyList(), 0)

        fun tooltipValueText(tokens: Long): String = if (tokens > 0) "${TokenNumberFormatter.grouped(tokens)} 토큰" else "사용 없음"

        fun dayString(date: Double): String = KstCalendar.dayString(date)

        fun date(fromDay: String): Double? = KstCalendar.midnight(fromDay)

        /** 날짜별 토큰 맵 → 잔디. 창 밖 · 미래 · 못 읽는 날 · 0 이하는 버린다. */
        fun build(daily: Map<String, Long>, now: Double, weeks: Int = WorkDailyGrid.defaultWeeks): TokenDailyGrid {
            val weekCount = maxOf(1, weeks)
            val weekStart = WorkDailyGrid.windowStart(now, weekCount)
            val todayOffset = KstCalendar.daysBetween(weekStart, KstCalendar.dayStart(now))
            val dayCount = WorkRhythmHeatmap.DAY_COUNT
            val days = todayOffset + 1
            val tokens = Array(weekCount) { LongArray(dayCount) }
            for ((day, value) in daily) {
                if (value <= 0) continue
                val date = date(day) ?: continue
                val offset = KstCalendar.daysBetween(weekStart, date)
                if (offset < 0 || offset >= weekCount * dayCount || offset >= days) continue
                tokens[offset / dayCount][offset % dayCount] += value
            }
            return TokenDailyGrid(weekStart, weekCount, tokens.map { it.toList() }, days)
        }
    }
}

/** 토큰 잔디의 원천을 날짜별 유효 토큰 한 맵으로 합치는 규칙(서버 몫 · 합치기). 로컬 몫(`localTotals`)은 맥 스캐너 → W2-h. */
object TokenDailyMerge {
    /** 서버 일별 행 → 날짜별 유효 토큰(claude 합 + Codex 유효 — 계정 버킷에만 비율). 마지막 버킷 날은 **축소 전** 키로. */
    fun serverTotals(rows: List<TokenDailyRowFacts>, accountShareRatio: Double = 1.0): Map<String, Long> {
        val (claude, codexLocal, codexAccount) = fold(rows)
        val lastDay = codexAccount.keys.maxOrNull()
        val result = LinkedHashMap<String, Long>()
        for (day in claude.keys + codexLocal.keys + codexAccount.keys) {
            if (day in result) continue
            val bucket = codexAccount[day]?.let { TokenRowDisplayRule.scaledAccountBucket(it, accountShareRatio) }
            result[day] = (claude[day] ?: 0L) + CodexEffectiveRule.day(day, codexLocal[day] ?: 0L, bucket, lastDay)
        }
        return result
    }

    /** 행을 세 맵으로 접는 **단 하나의 자리**: claude/codexLocal 은 기기 sum, codexAccount 는 날짜별 기기 간 max(null 은 빠진다). */
    private fun fold(rows: List<TokenDailyRowFacts>): Triple<Map<String, Long>, Map<String, Long>, Map<String, Long>> {
        val claude = LinkedHashMap<String, Long>()
        val codexLocal = LinkedHashMap<String, Long>()
        val codexAccount = LinkedHashMap<String, Long>()
        for (row in rows) {
            claude[row.day] = (claude[row.day] ?: 0L) + maxOf(0L, row.claudeTotal)
            codexLocal[row.day] = (codexLocal[row.day] ?: 0L) + maxOf(0L, row.codexUtcTotal ?: row.codexTotal)
            val account = row.codexAccount
            if (account != null) codexAccount[row.day] = maxOf(codexAccount[row.day] ?: 0L, account)
        }
        return Triple(claude, codexLocal, codexAccount)
    }

    /** 'YYYY-MM' 달의 계정 버킷 합(폰의 공유 비율 분모) — 날짜 키 문자열 접두어로 가른다(서버 `like p_month || '-%'` 와 같다). */
    fun accountBucketSum(rows: List<TokenDailyRowFacts>, month: String): Long {
        val prefix = "$month-"
        return fold(rows).third.entries.sumOf { if (it.key.startsWith(prefix)) it.value else 0L }
    }

    /** 날짜별 max(서버, 로컬) — 더하면 이중 계상. */
    fun merged(server: Map<String, Long>, local: Map<String, Long>): Map<String, Long> {
        val result = LinkedHashMap(server)
        for ((day, value) in local) result[day] = maxOf(result[day] ?: 0L, value)
        return result
    }
}

/** 개인 기록 계산 결과 묶음(히트맵 + 회고 + 잔디) — 같은 파싱 결과를 나눠 쓴다. 순수 계산이라 어느 스레드에서 불러도 같다. */
data class WorkInsightsComputation(val heatmap: WorkRhythmHeatmap, val retro: WeeklyRetro?, val dailyGrid: WorkDailyGrid) {
    companion object {
        /** ongoingStart: 진행 중인 내 세션의 시작 — 지금까지만 기여한다. 잔디는 진행 세션을 스스로 얹는다(이중 계상 없음). */
        fun build(rows: List<WorkSessionTimes>, now: Double, goalSeconds: Long, ongoingStart: Double? = null): WorkInsightsComputation {
            val completed = WorkInsightsDate.parseSessions(rows)
            val parsed = ArrayList(completed)
            if (ongoingStart != null && ongoingStart < now) parsed += WorkInsightsSession(ongoingStart, now)
            return WorkInsightsComputation(
                WorkRhythmHeatmap.build(parsed, now),
                WeeklyRetro.build(parsed, now, goalSeconds),
                WorkDailyGrid.build(completed, now, ongoingStart),
            )
        }
    }
}

/** 요일 인덱스(0=월) · 정시 시작(Swift `WorkInsightsCalendar`). */
object WorkInsightsCalendar {
    fun weekdayIndex(date: Double): Int = KstCalendar.weekdayIndex(date)
    fun hourStart(date: Double): Double = KstCalendar.hourStart(date)
}

/**
 * 서버 타임스탬프 파서(C§4 #30 — 골든 `dates/parse`). Apple `ISO8601DateFormatter`(.withInternetDateTime) → 소수초 판 → 소수부를
 * 도려내고(타임존이 없으면 Z) 다시. 결과는 언제나 **초 내림**(히트맵 조각마다 1초가 사라지지 않게).
 * 포매터가 받는 꼴(ICU 파서 — Nd 숫자 · 부분 일치 시간대 · GMT/UTC 꼴)은 foundation [IcuInternetDate] 가 옮긴다(앱의 날짜 파서 한 벌 —
 * wire `SwiftISO8601` 도 같은 것을 부른다, c-fold). 정규식은 쓰지 않는다(ART 의 java.util.regex 는 ICU 라 `\d` 가 Nd 전부를 받아 JDK 와
 * 답이 갈린다 — 에뮬레이터 API 36 실측).
 */
object WorkInsightsDate {
    fun parse(value: String): Double? {
        val raw = parseRaw(value) ?: return null
        return kotlin.math.floor(raw)
    }

    fun parseSessions(rows: List<WorkSessionTimes>): List<WorkInsightsSession> {
        val parsed = ArrayList<WorkInsightsSession>(rows.size)
        for (row in rows) {
            val endedText = row.endedAt ?: continue
            val started = parse(row.startedAt) ?: continue
            val ended = parse(endedText) ?: continue
            if (!(ended > started)) continue
            parsed += WorkInsightsSession(started, ended)
        }
        return parsed
    }

    private fun parseRaw(value: String): Double? {
        icu(value, fractional = false)?.let { return it }
        icu(value, fractional = true)?.let { return it }
        val dot = value.indexOf('.')
        if (dot < 0) return null
        val rest = value.substring(dot + 1)
        // Swift `rest.firstIndex(where: { !$0.isNumber })` — **글자(그래핌) 단위**, 그 글자의 첫 스칼라가 숫자인가.
        var consumed = 0
        for (cluster in Graphemes.clusters(rest)) {
            if (!isNumberScalar(cluster.codePointArray()[0])) break
            consumed += cluster.length
        }
        val trimmed = value.substring(0, dot) + if (consumed < rest.length) rest.substring(consumed) else "Z"
        return icu(trimmed, fractional = false)
    }

    /** foundation 파서(1970 기준 초 — 2001 기준 왕복 전) → Swift `Date.timeIntervalSince1970`(2001 기준 왕복 그대로). */
    private fun icu(text: String, fractional: Boolean): Double? = IcuInternetDate.parse(text, fractional)?.let(SwiftDate::since1970)

    /** Swift `Character.isNumber`(첫 스칼라의 numericType != nil)을 번들 표의 범주 Nd · Nl · No 로(한자 수사 같은 Lo 숫자는 모형 밖). */
    private fun isNumberScalar(cp: Int): Boolean =
        TextScalars.generalCategory(cp).let { it == "Nd" || it == "Nl" || it == "No" }
}

/** 회고 배너를 이번 주에 보였는지 기록하는 키(KST 월요일 'YYYY-MM-DD'). */
object RetroWeekKey {
    fun current(now: Double): String = KstCalendar.dayString(KstCalendar.weekStart(now))
}

/** 토큰 순위판 월 이동(KST 'YYYY-MM'). 현재 월보다 미래로는 갈 수 없다. */
object TokenBoardMonthNavigator {
    fun step(monthKey: String, delta: Int, now: Double): String {
        val parts = monthKey.split('-').filter { it.isNotEmpty() }.mapNotNull { parseSwiftInt(it) }
        if (parts.size != 2) return KstCalendar.monthKey(now)
        val base = KstCalendar.date(parts[0].toInt(), parts[1].toInt(), 1) ?: return KstCalendar.monthKey(now)
        val moved = KstCalendar.addMonths(base, delta)
        val movedKey = KstCalendar.monthKey(moved)
        val currentKey = KstCalendar.monthKey(now)
        return if (movedKey > currentKey) currentKey else movedKey
    }

    fun canStepForward(monthKey: String, now: Double): Boolean = monthKey < KstCalendar.monthKey(now)

    /** 'YYYY-MM' → "N월"(올해가 아니면 "YYYY년 N월"). */
    fun displayTitle(monthKey: String, now: Double): String {
        val parts = monthKey.split('-').filter { it.isNotEmpty() }.mapNotNull { parseSwiftInt(it) }
        if (parts.size != 2) return monthKey
        val currentYear = KstCalendar.localDate(now).year.toLong()
        return if (parts[0] == currentYear) "${parts[1]}월" else "${parts[0]}년 ${parts[1]}월"
    }
}

/**
 * 팀 리그 주 이동(KST 월요일 'YYYY-MM-DD').
 * INV-CheckWorkInsights-4ab18beb 이식: 들고 다니는 상태는 **주 키(절대 날짜)** 다 — 오프셋은 '지금'에 매달려 월요일 0시에 한 칸 밀린다.
 * INV-CheckWorkInsights-dafae198 이식: 부호 규약이 둘이다 — 서버 오프셋은 양수가 과거, step 의 delta 는 화살표 방향(-1 ◂ 과거로).
 */
object TeamLeagueWeekNavigator {
    const val maxWeeksBack = 6

    fun currentKey(now: Double): String = key(KstCalendar.weekStart(now))

    fun key(weekStart: Double): String = KstCalendar.dayString(weekStart)

    fun key(offset: Int, now: Double): String = key(KstCalendar.addWeeks(KstCalendar.weekStart(now), -clamp(offset)))

    fun offset(weekKey: String, now: Double): Int {
        val start = date(weekKey) ?: return 0
        val thisWeek = KstCalendar.weekStart(now)
        return clamp(KstCalendar.weeksBetween(start, thisWeek))
    }

    fun clamp(offset: Int): Int = minOf(maxOf(offset, 0), maxWeeksBack)

    fun step(weekKey: String, delta: Int, now: Double): String = key(clamp(offset(weekKey, now) - delta), now)

    fun canStepForward(weekKey: String, now: Double): Boolean = offset(weekKey, now) > 0

    fun canStepBack(weekKey: String, now: Double): Boolean = offset(weekKey, now) < maxWeeksBack

    fun isCurrentWeek(weekKey: String, now: Double): Boolean = !canStepForward(weekKey, now)

    /** 이번 주는 "이번 주", 과거는 "9월 15일 주"(해가 다르면 "2025년 12월 29일 주"). */
    fun displayTitle(weekKey: String, now: Double): String {
        val start = date(weekKey)
        if (isCurrentWeek(weekKey, now) || start == null) return "이번 주"
        val d = KstCalendar.localDate(start)
        val month = d.month.ordinal + 1
        val currentYear = KstCalendar.localDate(now).year
        return if (d.year == currentYear) "${month}월 ${d.day}일 주" else "${d.year}년 ${month}월 ${d.day}일 주"
    }

    fun date(weekKey: String): Double? = KstCalendar.midnight(weekKey)
}
