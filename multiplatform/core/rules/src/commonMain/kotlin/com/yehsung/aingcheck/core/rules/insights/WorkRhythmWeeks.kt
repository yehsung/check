// 원본: Sources/CheckCore/CheckWorkInsights.swift(WorkRhythmWeeks · WorkRhythmHeatmap.addingLive · WorkRhythmWeekText) @ e4995a3a
//
// 주별 근무 리듬(2026-11-06 대표 결정 #d_V0mJ363LONEW — 맥 0.3.78 · 폰 1.0.18 · Android 판 8).
// 대표 원문: "근무 리듬이 매주 실시간 쌓이고 있는게 보이게끔 하는식으로 구현하고 지난 기록들 누적 주차별로 볼 수 있게 추가."
// → 기본은 **이번 주**(월요일 ~ 지금, 진행 중 근무까지 1분마다 참), ◀ 로 지난주 · 그 전주 … 첫 주까지 넘겨본다.
// 칸의 뜻(한 칸 = 그 주 그 요일 그 시간에 일한 초, 진하기 분모 3600초 고정)은 옛 '지난주 근무 리듬'과 같다.
package com.yehsung.aingcheck.core.rules.insights

import kotlin.math.floor

/** 첫 주부터 이번 주까지 주마다 하나씩의 리듬 히트맵. 마지막 원소가 이번 주다(완료 세션만). 시각은 1970 기준 초(Double). */
data class WorkRhythmWeeks(
    /** 각 주의 KST 월요일 00:00, 오래된 주 → 이번 주 순. */
    val weekStarts: List<Double>,
    /** [weekStarts] 와 같은 순서의 히트맵. */
    val heatmaps: List<WorkRhythmHeatmap>,
) {
    /** 넘겨볼 수 있는 가장 큰 오프셋(0 = 이번 주). 주가 하나뿐이면 0. */
    val maxOffset: Int get() = maxOf(0, weekStarts.size - 1)

    /** offset 0 = 이번 주, 1 = 지난주 … 범위 밖이면 null. */
    fun weekStart(offset: Int): Double? = weekStarts.getOrNull(weekStarts.size - 1 - offset)

    fun heatmap(offset: Int): WorkRhythmHeatmap? = heatmaps.getOrNull(heatmaps.size - 1 - offset)

    companion object {
        val empty = WorkRhythmWeeks(emptyList(), emptyList())

        /** 한 번에 다루는 주 수 상한(10년). 시계가 크게 틀린 행 하나가 수천 주짜리 배열을 만들지 않게 한다. */
        const val MAX_WEEKS = 520

        /**
         * 완료 세션으로 주별 히트맵을 만든다. 첫 주 = 가장 이른 세션이 시작한 주(세션이 없으면 이번 주 하나). 세션은 KST 정시 경계로 쪼개 그 시간이
         * 속한 주의 (요일, 시간) 칸에 실제로 머문 초만 넣는다 — 주 경계(일 → 월 자정)를 넘긴 세션도 두 주에 나뉘어 들어간다. now 이후 몫은 세지 않는다.
         */
        fun build(parsed: List<WorkInsightsSession>, now: Double): WorkRhythmWeeks {
            val thisWeek = KstCalendar.weekStart(now)
            var first = parsed.map { it.start }.filter { it <= now }.minOrNull()?.let { KstCalendar.weekStart(it) } ?: thisWeek
            if (first > thisWeek) first = thisWeek
            var starts = ArrayList<Double>()
            var cursorWeek = first
            while (cursorWeek <= thisWeek) {
                starts += cursorWeek
                val next = KstCalendar.addWeeks(cursorWeek, 1)
                if (!(next > cursorWeek)) break
                cursorWeek = next
                if (starts.size > MAX_WEEKS * 4) break
            }
            if (starts.size > MAX_WEEKS) starts = ArrayList(starts.takeLast(MAX_WEEKS))
            val windowStart = starts.firstOrNull() ?: return empty
            val buckets = Array(starts.size) { Array(WorkRhythmHeatmap.DAY_COUNT) { LongArray(WorkRhythmHeatmap.HOUR_COUNT) } }
            val totals = LongArray(starts.size)
            for (session in parsed) {
                var cursor = maxOf(session.start, windowStart)
                val end = minOf(session.end, now)
                while (cursor < end) {
                    val hourStart = KstCalendar.hourStart(cursor)
                    val nextHour = KstCalendar.addHours(hourStart, 1)
                    if (!(nextHour > cursor)) break
                    val sliceEnd = minOf(nextHour, end)
                    val seconds = (sliceEnd - cursor).toLong()
                    // 그 정시가 속한 주를 찾는다. KST 는 서머타임이 없어 한 주는 늘 604800초다.
                    val weekIndex = floor((hourStart - windowStart) / 604_800.0).toInt()
                    if (seconds > 0 && weekIndex in starts.indices) {
                        buckets[weekIndex][KstCalendar.weekdayIndex(hourStart)][KstCalendar.localDateTime(hourStart).hour] += seconds
                        totals[weekIndex] += seconds
                    }
                    cursor = sliceEnd
                }
            }
            val heatmaps = starts.indices.map { i -> WorkRhythmHeatmap(buckets[i].map { it.toList() }, totals[i]) }
            return WorkRhythmWeeks(starts, heatmaps)
        }
    }
}

/**
 * 진행 중인 근무(liveStart ~ now)를 weekStart 로 시작하는 주의 칸에 얹은 사본. 화면이 1분마다 불러 이번 주가 실시간으로 찬다.
 * liveStart 가 null 이거나 그 주와 겹치지 않으면 그대로 돌려준다. 같은 칸이 3600초를 넘지 않게 자른다(완료분과 겹친 기록 방어).
 */
fun WorkRhythmHeatmap.addingLive(liveStart: Double?, now: Double, weekStart: Double): WorkRhythmHeatmap {
    if (liveStart == null) return this
    val weekEnd = weekStart + 604_800.0
    var cursor = maxOf(liveStart, weekStart)
    val end = minOf(now, weekEnd)
    if (!(cursor < end)) return this
    val base = if (buckets.size != WorkRhythmHeatmap.DAY_COUNT || buckets.any { it.size != WorkRhythmHeatmap.HOUR_COUNT }) WorkRhythmHeatmap.empty else this
    val grid = Array(WorkRhythmHeatmap.DAY_COUNT) { d -> LongArray(WorkRhythmHeatmap.HOUR_COUNT) { h -> base.buckets[d][h] } }
    var total = base.totalSeconds
    while (cursor < end) {
        val hourStart = KstCalendar.hourStart(cursor)
        val nextHour = KstCalendar.addHours(hourStart, 1)
        if (!(nextHour > cursor)) break
        val sliceEnd = minOf(nextHour, end)
        val seconds = (sliceEnd - cursor).toLong()
        if (seconds > 0) {
            val day = KstCalendar.weekdayIndex(hourStart)
            val hour = KstCalendar.localDateTime(hourStart).hour
            val room = maxOf(0L, 3_600L - grid[day][hour])
            val add = minOf(seconds, room)
            grid[day][hour] += add
            total += add
        }
        cursor = sliceEnd
    }
    return WorkRhythmHeatmap(grid.map { it.toList() }, total)
}

/** 주별 리듬 칸의 머리 · 위치 문구(순수 — 값으로 시험한다). 맥 · 폰과 같은 글자. */
object WorkRhythmWeekText {
    /** 칸 제목. 기간이 **제목 안에** 들어간다(옛 '지난주 근무 리듬'과 같은 규약). */
    fun title(offset: Int, weekStart: Double?): String = when (offset) {
        0 -> "이번 주 근무 리듬"
        1 -> "지난주 근무 리듬"
        else -> {
            if (weekStart == null) "근무 리듬"
            else {
                val d = KstCalendar.localDate(weekStart)
                "${d.monthNumber}월 ${d.dayOfMonth}일 주 근무 리듬"
            }
        }
    }

    /** 이번 주 칸 중 '아직 오지 않은' 첫 칸(요일, 시간). 이번 주가 아니면 null(모든 칸이 지난 시간). */
    fun futureFrom(offset: Int, now: Double): Pair<Int, Int>? {
        if (offset != 0) return null
        return KstCalendar.weekdayIndex(now) to (KstCalendar.localDateTime(now).hour + 1)
    }

    /** 칸 아래 한 줄: "12시간 30분 · 가장 활발한 시간: 화요일 15시". 기록이 없으면 그 주에 맞는 빈 문구. */
    fun caption(heatmap: WorkRhythmHeatmap, offset: Int): String {
        val names = listOf("월", "화", "수", "목", "금", "토", "일")
        if (heatmap.totalSeconds <= 0) return if (offset == 0) "이번 주 기록이 아직 없어요" else "이 주는 기록이 없어요"
        val h = heatmap.totalSeconds / 3_600
        val m = (heatmap.totalSeconds % 3_600) / 60
        val total = if (h > 0) "${h}시간 ${m}분" else "${m}분"
        val peak = heatmap.peakSlot ?: return total
        if (peak.first !in names.indices) return total
        return "$total · 가장 활발한 시간: ${names[peak.first]}요일 ${peak.second}시"
    }
}
