// 원본: Swift Foundation `Date`(1970 기준 초 Double) · Sources/CheckCore/SupabaseWorkService.swift:9-17·338-341(parseDate: 소수초 포매터 먼저) @ 1b8260d · C§2.5
@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.yehsung.aingcheck.core.wire

import kotlin.time.Instant

/**
 * Swift `Date` 의 Kotlin 꼴 — Swift 처럼 **2001 기준 초 Double**(`timeIntervalSinceReferenceDate`)로 들고, 1970 기준 값은 매번 더해 낸다
 * (C§2.5 "Date 산술은 Double 초로 1:1"). 1970 기준으로 들면 `addingTimeInterval` 의 반올림 자리가 달라 1ulp 갈린다(G4 걷기 실측).
 * G6 덤프는 `{"$date": timeIntervalSince1970 비트}`(contract/README §2-3).
 */
class SwiftDate private constructor(
    val timeIntervalSinceReferenceDate: Double,
    @Suppress("UNUSED_PARAMETER") reference: Byte,
) : Comparable<SwiftDate> {
    /** Swift `Date(timeIntervalSince1970:)` 과 같은 값을 만든다(1970 → 2001 기준으로 한 번 뺀다). */
    constructor(timeIntervalSince1970: Double) : this(timeIntervalSince1970 - SECONDS_1970_TO_2001, 0)

    val timeIntervalSince1970: Double get() = timeIntervalSinceReferenceDate + SECONDS_1970_TO_2001

    override fun compareTo(other: SwiftDate): Int = timeIntervalSinceReferenceDate.compareTo(other.timeIntervalSinceReferenceDate)

    /** Swift `a.timeIntervalSince(b)` = 두 2001 기준 값의 차. */
    fun timeIntervalSince(other: SwiftDate): Double = timeIntervalSinceReferenceDate - other.timeIntervalSinceReferenceDate

    fun addingTimeInterval(seconds: Double): SwiftDate = SwiftDate(timeIntervalSinceReferenceDate + seconds, 0)

    override fun equals(other: Any?): Boolean = other is SwiftDate && other.timeIntervalSinceReferenceDate == timeIntervalSinceReferenceDate
    override fun hashCode(): Int = timeIntervalSinceReferenceDate.hashCode()
    override fun toString(): String = "SwiftDate(since1970=$timeIntervalSince1970)"

    companion object {
        /** 1970-01-01 과 Swift 기준일(2001-01-01) 사이 초. */
        const val SECONDS_1970_TO_2001: Double = 978_307_200.0

        fun fromReferenceDate(seconds: Double): SwiftDate = SwiftDate(seconds, 0)

        /** ICU 처럼 ms(정수) → 초는 한 번의 나눗셈으로. */
        fun fromEpochMillis(ms: Long): SwiftDate = SwiftDate(ms.toDouble() / 1000.0)
    }
}

/**
 * Supabase timestamptz 글자 → [SwiftDate]. Swift `parseDate` 는 소수초 ISO8601 포매터를 먼저, 실패하면 기본 포매터로 읽는다
 * (`SupabaseWorkService.swift:338-341`). 두 포매터 모두 시간대(Z 또는 ±hh:mm)를 요구한다. Apple 포매터는 밀리초까지만 든다 —
 * 그래서 소수부를 밀리초로 자른다(넷째 자리부터 버림).
 */
object SwiftISO8601 {
    private val pattern = Regex(
        """^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})$""",
    )

    fun parse(text: String): SwiftDate? {
        val m = pattern.matchEntire(text) ?: return null
        val fraction = m.groupValues[7]
        val base = text.substring(0, m.groups[6]!!.range.last + 1) + normalizeZone(m.groupValues[8])
        val instant = try {
            Instant.parse(base)
        } catch (e: IllegalArgumentException) {
            return null
        }
        val millis = if (fraction.isEmpty()) 0 else fraction.drop(1).padEnd(3, '0').take(3).toInt()
        // Apple 포매터(ICU)는 1970 기준 ms(정수)를 1000 으로 한 번 나눈 뒤 2001 기준으로 옮긴다.
        return SwiftDate.fromEpochMillis(instant.epochSeconds * 1000 + millis)
    }

    private fun normalizeZone(zone: String): String = when {
        zone == "Z" -> "Z"
        zone.length == 5 -> zone.substring(0, 3) + ":" + zone.substring(3)
        else -> zone
    }

    /** Swift `ISO8601DateFormatter().string(from:)` — 초 단위 UTC `yyyy-MM-ddTHH:mm:ssZ`. */
    fun format(date: SwiftDate): String {
        val seconds = kotlin.math.floor(date.timeIntervalSince1970).toLong()
        // kotlin.time.Instant.toString 은 소수초가 0 이면 붙이지 않는다 → "…:ssZ"(Swift 기본 포매터와 같은 모양)
        return Instant.fromEpochSeconds(seconds).toString()
    }
}
