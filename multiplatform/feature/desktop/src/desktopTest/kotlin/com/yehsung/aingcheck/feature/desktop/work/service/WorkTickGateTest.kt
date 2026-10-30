// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 1017-1080(WorkTickGate) · Tests/checkTests/V0238TickTests.swift (f)
//       threeServerErrorsSuspendForAnHourThenRetry @ a90d8623
// 규약 번호: xplat-w1/briefs/work.md §2 ⑨ — 404·PGRST202·403·42501·v≠1·디코드 실패는 이 실행 동안 끈다,
//            5xx 등 일시 실패 **3연속 → 1시간** 폴백 후 재시도(지속 오류 시 "실패 1 + 폴백 7" 폭주의 상한), 성공은 연속 수를 0 으로.
// 음성 대조: transientFailureLimit 3→4·3→99, suspensionSeconds 3600→0·3600→7200, recordSuccess 의 0 되돌림 제거 — 각각 아래 시험이 빨갛다.
package com.yehsung.aingcheck.feature.desktop.work.service

import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkTickGateTest {
    private val t0 = SwiftDate(1_787_000_000.0)

    @Test
    fun rule9_constantsMatchSwift() {
        assertEquals(3, WorkTickGate.transientFailureLimit)
        assertEquals(3_600.0, WorkTickGate.suspensionSeconds)
    }

    @Test
    fun rule9_threeTransientFailuresSuspendForOneHourThenRetry() {
        val gate = WorkTickGate()
        assertTrue(gate.isAvailable(t0))
        gate.recordTransientFailure("HTTP 503", t0)
        gate.recordTransientFailure("HTTP 503", t0)
        assertTrue(gate.isAvailable(t0), "2연속은 아직 정지가 아니다")
        assertNull(gate.snapshot.suspendedUntil)

        gate.recordTransientFailure("HTTP 500", t0)
        val suspended = gate.snapshot
        assertEquals(3, suspended.consecutiveTransientFailures)
        assertEquals(t0.addingTimeInterval(3_600.0), suspended.suspendedUntil, "3연속째에 1시간 정지")
        assertEquals("HTTP 500", suspended.lastTransientReason)
        assertFalse(gate.isAvailable(t0), "정지 직후 work_tick 을 두드리지 않는다")
        assertFalse(gate.isAvailable(t0.addingTimeInterval(1_800.0)), "정지 중(30분)")
        assertFalse(gate.isAvailable(t0.addingTimeInterval(3_599.0)), "정지 중(59분 59초)")

        assertTrue(gate.isAvailable(t0.addingTimeInterval(3_600.0)), "1시간이 지나면 스스로 풀린다")
        val resumed = gate.snapshot
        assertNull(resumed.suspendedUntil)
        assertEquals(0, resumed.consecutiveTransientFailures, "풀리면 연속 수를 새로 센다")
    }

    @Test
    fun rule9_afterSuspensionLiftsItTakesThreeFreshFailuresAgain() {
        val gate = WorkTickGate()
        repeat(3) { gate.recordTransientFailure("HTTP 503", t0) }
        val t1 = t0.addingTimeInterval(3_600.0)
        assertTrue(gate.isAvailable(t1))
        gate.recordTransientFailure("HTTP 503", t1)
        gate.recordTransientFailure("HTTP 503", t1)
        assertTrue(gate.isAvailable(t1), "풀린 뒤 2연속은 정지가 아니다(이전 3회를 이어 세지 않는다)")
        gate.recordTransientFailure("HTTP 503", t1.addingTimeInterval(10.0))
        assertEquals(t1.addingTimeInterval(3_610.0), gate.snapshot.suspendedUntil, "정지 끝은 셋째 실패 시각 + 1시간")
        assertFalse(gate.isAvailable(t1.addingTimeInterval(3_609.0)))
    }

    @Test
    fun rule9_successResetsTheConsecutiveCount() {
        val gate = WorkTickGate()
        gate.recordTransientFailure("HTTP 502", t0)
        gate.recordTransientFailure("HTTP 502", t0)
        gate.recordSuccess(serverNow = null, localNow = t0)
        assertEquals(0, gate.snapshot.consecutiveTransientFailures)
        assertNull(gate.snapshot.lastTransientReason)
        gate.recordTransientFailure("HTTP 502", t0)
        gate.recordTransientFailure("HTTP 502", t0)
        assertTrue(gate.isAvailable(t0), "성공 사이에 끼인 실패는 연속이 아니다(2+2 ≠ 3연속)")
        assertNull(gate.snapshot.suspendedUntil)
    }

    @Test
    fun rule9_disableIsForThisRun_firstReasonWins_successDoesNotReenable() {
        val gate = WorkTickGate()
        gate.disable("함수 없음(PGRST202)", t0)
        gate.disable("실행권 회수(42501)", t0.addingTimeInterval(5.0))
        assertEquals("함수 없음(PGRST202)", gate.snapshot.disabledReason)
        assertEquals(t0, gate.snapshot.disabledAt)
        gate.recordSuccess(serverNow = null, localNow = t0)
        assertFalse(gate.isAvailable(t0.addingTimeInterval(10.0 * 3_600.0)), "1시간 정지와 달리 시간이 지나도 풀리지 않는다")
    }

    @Test
    fun rule9_successRecordsClockSkew_fallbackCounts() {
        val gate = WorkTickGate()
        gate.recordSuccess(serverNow = t0.addingTimeInterval(2.5), localNow = t0)
        gate.recordSuccess(serverNow = null, localNow = t0)
        gate.recordFallback()
        val s = gate.snapshot
        assertEquals(2, s.successCount)
        assertEquals(2.5, s.lastClockSkewSeconds, "server_now − 로컬(양수 = 서버가 앞선다) · null 이면 앞 값 유지")
        assertEquals(1, s.fallbackCount)
    }
}
