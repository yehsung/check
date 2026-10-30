// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift WorkTickGate (b) 갈래(recordOverloadFailure · availability .backingOff) — 2026-10-30 안정화
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.pow
import kotlin.random.Random

/**
 * work_tick (b) 과부하·도달 불가 백오프. 공용 [com.yehsung.aingcheck.feature.desktop.work.service.WorkTickGate] 는 (a) 끔 · (c) 정지만
 * 센다 — (b) 를 그 정지 카운터에 보태면 3연속에서 1시간 동안 work_tick 이 멈춰, 서버가 닫은 세션을 1시간 뒤에야 안다
 * (반박 검증 must_fix 2). 여기서 따로 센다: k 번째 연속 실패 뒤 `min(30·2^(k−1), 120)초 × 지터(0.8~1.2)` 동안 work_tick 도
 * 기존 경로도 내지 않는다(하트비트 규칙은 호출부). 만료돼도 연속 수는 남는다(회복 확인 1건이 또 실패하면 다음 칸도 길게) —
 * 성공만 지운다. 상한 120초는 서버 스캐빈저(하트비트 10분 공백)보다 한참 안쪽이다.
 */
class WorkTickOverloadBackoff(private val jitter: () -> Double = { Random.nextDouble(JITTER_MIN, JITTER_MAX) }) {
    companion object {
        const val BASE_SECONDS: Double = 30.0
        const val MAX_SECONDS: Double = 120.0
        const val JITTER_MIN: Double = 0.8
        const val JITTER_MAX: Double = 1.2
    }

    private val lock = Any()
    private var consecutive = 0
    private var until: SwiftDate? = null
    private var lastReason: String? = null

    /** 지금 백오프 중인가(그 틱은 work_tick 도 펼침도 내지 않는다). */
    fun isBackingOff(now: SwiftDate): Boolean = synchronized(lock) {
        val u = until
        u != null && now < u
    }

    /** (b) 1회 — 다음 칸으로 늘린다(30·60·120·120…초 × 지터). */
    fun recordFailure(reason: String, now: SwiftDate) = synchronized(lock) {
        lastReason = reason
        consecutive += 1
        val doublings = minOf(consecutive - 1, 8).toDouble()
        val base = minOf(BASE_SECONDS * 2.0.pow(doublings), MAX_SECONDS)
        val factor = jitter().coerceIn(JITTER_MIN, JITTER_MAX)
        until = now.addingTimeInterval(base * factor)
    }

    /** 성공 1회 — 연속 수와 칸을 지운다. */
    fun recordSuccess() = synchronized(lock) {
        consecutive = 0
        until = null
        lastReason = null
    }

    /** 진단·시험용: 연속 실패 수, 백오프 끝, 마지막 사유. */
    val snapshot: Triple<Int, SwiftDate?, String?> get() = synchronized(lock) { Triple(consecutive, until, lastReason) }
}
