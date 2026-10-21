// 원본: Sources/check/CheckWorkNudge.swift:63-65 @ a63fea2 (lastTickAt — 벽시계 간격으로 잠자기 공백) — 시험은 새 코드: 설계 D§5-2
package com.yehsung.aingcheck.desktop.platform.windows.power

import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import java.awt.desktop.UserSessionEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

/** D§5-2 2차 신호: 1초 티커의 벽시계 간격이 기대보다 30초 넘게 크면 그 구간을 잔 것으로 본다. */
class WallClockGapDetectorTest {
    private val t0 = Instant.fromEpochSeconds(1_800_000_000)

    @Test
    fun steadyTicksAreNoGap() {
        val d = WallClockGapDetector()
        assertNull(d.tick(t0))
        for (i in 1..120) assertNull(d.tick(t0 + i.seconds), "tick $i")
    }

    @Test
    fun boundaryIsExpectedPlusThreshold() {
        val d = WallClockGapDetector(expectedInterval = 1.seconds, threshold = 30.seconds)
        d.tick(t0)
        assertNull(d.tick(t0 + 31.seconds), "정확히 31초는 공백이 아니다")
        val gap = d.tick(t0 + 31.seconds + 32.seconds)
        assertEquals(WallClockGapDetector.Gap(t0 + 31.seconds, t0 + 63.seconds), gap)
        assertEquals(32.seconds, gap!!.length)
    }

    @Test
    fun sleepOfTenMinutesIsReportedOnce() {
        val d = WallClockGapDetector()
        d.tick(t0)
        val wake = t0 + 10.minutes
        assertEquals(10.minutes, d.tick(wake)!!.length)
        assertNull(d.tick(wake + 1.seconds))
    }

    @Test
    fun clockGoingBackwardsIsNotAGapAndRebases() {
        val d = WallClockGapDetector()
        d.tick(t0)
        assertNull(d.tick(t0 - 5.minutes))
        assertNull(d.tick(t0 - 5.minutes + 1.seconds))
    }

    @Test
    fun resetForgetsThePreviousTick() {
        val d = WallClockGapDetector()
        d.tick(t0)
        d.reset()
        assertNull(d.tick(t0 + 2.minutes), "루프가 꺼져 있던 구간은 공백의 증거가 아니다")
    }

    @Test
    fun userSessionReasonsMapToK3Events() {
        val r = UserSessionEvent.Reason.LOCK
        assertEquals(SessionEvent.LOCK, DesktopPowerEvents.mapReason(r, active = false))
        assertEquals(SessionEvent.UNLOCK, DesktopPowerEvents.mapReason(r, active = true))
        assertEquals(SessionEvent.CONSOLE_DISCONNECT, DesktopPowerEvents.mapReason(UserSessionEvent.Reason.CONSOLE, active = false))
        assertEquals(SessionEvent.REMOTE_CONNECT, DesktopPowerEvents.mapReason(UserSessionEvent.Reason.REMOTE, active = true))
    }

    @Test
    fun headlessInstallDoesNotThrowAndReportsNotInstalled() {
        // 시험은 java.awt.headless=true — JDK 데스크톱 통지는 붙지 않는다(isDesktopSupported=false). 조용히 false.
        val events = DesktopPowerEvents()
        assertEquals(false, events.install())
        var got: SessionEvent? = null
        events.sessionEvents.addListener { got = it }
        events.onShutdown()
        assertEquals(SessionEvent.LOGOFF, got)
    }
}
