// 원본: Sources/CheckCore/MilestoneTracker.swift @ 1b8260d (DrowsyWindow 의 난수 뽑기 `nextInterval` · `nextNapDuration` 은 오버레이 재생기(W5) 몫 —
//       Swift `TimeInterval.random(in:using:)` 알고리즘은 비트 동일을 요구하지 않는 연출이라 여기 옮기지 않는다)
package com.yehsung.aingcheck.core.rules.insights

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore

/** 졸기 스케줄 상수 · 밤샘 시간창(23:00~05:00 KST). */
object DrowsyWindow {
    /** 졸기 진입 간격 하한/상한(초) — 60±20분. */
    const val minInterval = 40 * 60.0
    const val maxInterval = 80 * 60.0
    /** 한 번 졸 때 자는 시간 하한/상한(초) — 5~10분. */
    const val minNapSeconds = 5 * 60.0
    const val maxNapSeconds = 10 * 60.0

    /** KST 시각이 밤샘 시간창(23,0,1,2,3,4시) 안인가. */
    fun contains(date: Double): Boolean {
        val hour = KstCalendar.localDateTime(date).hour
        return hour >= 23 || hour < 5
    }
}

/**
 * 마일스톤 1일 1회 기록기. 저장소에 "check.milestone.<키>.<yyyyMMdd(KST)>" 로 기록해 같은 날 같은 키의 축하가 두 번 터지지 않게 한다.
 * 세션 안 중복 조회를 줄이려 메모리 캐시도 둔다.
 */
class MilestoneTracker(private val defaults: KeyValueStore) {
    private val firedThisSession = HashSet<String>()
    private var cachedDay: Triple<Double, Double, String>? = null

    private fun cachedDayKey(now: Double): String {
        cachedDay?.let { (start, next, key) -> if (now >= start && now < next) return key }
        val start = KstCalendar.dayStart(now)
        val next = KstCalendar.addDays(start, 1)
        val key = dayKey(now)
        cachedDay = Triple(start, next, key)
        return key
    }

    /** 오늘(KST) 아직 안 터진 키면 기록하고 true, 이미 터졌으면 false. 하루가 지나면 다시 true. */
    fun fireIfNeeded(key: String, now: Double): Boolean {
        val dkey = defaultsKey(key, cachedDayKey(now))
        if (dkey in firedThisSession) return false
        if (defaults.getBoolean(dkey) == true) {
            firedThisSession += dkey
            return false
        }
        defaults.putBoolean(dkey, true)
        firedThisSession += dkey
        return true
    }

    companion object {
        const val hourOneKey = "hour1"
        const val hourFourKey = "hour4"
        const val teamGoalKey = "teamGoal"
        const val firstArrivalKey = "firstArrival"

        /** KST yyyyMMdd. */
        fun dayKey(date: Double): String = KstCalendar.compactDayKey(date)

        private fun defaultsKey(key: String, day: String): String = "check.milestone.$key.$day"
    }
}
