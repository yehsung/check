// W3-c5 완료 기준: UpdatePollScheduleTest — 실행 5초 · 5분마다 · 깨어남(가짜 시계 = kotlinx-coroutines-test 가상 시간).
// 원본: CheckUpdateCheck.swift 48(5초·300초·깨어남·열기 60초) · 357-385(startServerWatch) · 393-405(handleWake) · 319-345(재진입 가드).
// 번호는 DesktopUpdateChecker 주석(①~④ 주기 · ★2 재진입 · ★3 시도 스탬프 · ★4 잠든 동안 주기 멈춤).
@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class UpdatePollScheduleTest {
    private fun TestScope.newChecker(rpc: FakeUpdateRpc): DesktopUpdateChecker {
        rpc.now = { testScheduler.currentTime }
        return DesktopUpdateChecker(rpc, 10, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
    }

    /** 지금 시각까지 걸어간다(그 시각에 잡힌 일까지 돈다). */
    private fun TestScope.walkTo(ms: Long) {
        advanceTimeBy(ms - testScheduler.currentTime)
        runCurrent()
    }

    @Test
    fun scheduleDefaultsMatchSwift() {
        val s = UpdatePollSchedule.DEFAULT
        assertEquals(listOf(5_000L, 300_000L, 10_000L, 60_000L), listOf(s.initialDelayMillis, s.intervalMillis, s.wakeSettleMillis, s.openThrottleMillis))
    }

    @Test
    fun firstAfterFiveSecondsThenEveryFiveMinutesAndNoSecondTicks() = runTest {
        val rpc = FakeUpdateRpc()
        val c = newChecker(rpc)
        c.startWatch()
        c.startWatch() // 멱등 — 루프가 둘이 되지 않는다
        walkTo(4_999)
        assertEquals(emptyList(), rpc.releaseCalls, "① 5초 전엔 치지 않는다")
        walkTo(5_000)
        assertEquals(listOf(5_000L), rpc.releaseCalls)
        walkTo(304_999)
        assertEquals(listOf(5_000L), rpc.releaseCalls, "② 1초 틱 0회 — 다음은 5분 뒤")
        walkTo(905_000)
        assertEquals(listOf(5_000L, 305_000L, 605_000L, 905_000L), rpc.releaseCalls)
        assertEquals(rpc.releaseCalls, rpc.noticeCalls, "★1 공지는 같은 조회 안에서 릴리스 뒤")
        c.stopWatch()
        walkTo(5_000_000)
        assertEquals(4, rpc.releaseCalls.size, "끈 뒤엔 치지 않는다")
    }

    @Test
    fun wakeChecksAfterSettleAndRestartsPeriod() = runTest {
        val rpc = FakeUpdateRpc()
        val c = newChecker(rpc)
        c.startWatch()
        walkTo(100_000)
        c.onPowerEvent(PowerEvent.WAKE)
        walkTo(109_999)
        assertEquals(listOf(5_000L), rpc.releaseCalls, "③ 깨어난 순간엔 치지 않는다")
        walkTo(110_000)
        assertEquals(listOf(5_000L, 110_000L), rpc.releaseCalls)
        walkTo(410_000)
        assertEquals(listOf(5_000L, 110_000L, 410_000L), rpc.releaseCalls, "★4 주기는 깨어남 조회에서 다시 센다(305초 헛조회 0)")
    }

    @Test
    fun repeatedWakesFireOnlyTheLast() = runTest {
        val rpc = FakeUpdateRpc()
        val c = newChecker(rpc)
        c.startWatch()
        walkTo(100_000)
        c.onPowerEvent(PowerEvent.WAKE)
        walkTo(105_000)
        c.onPowerEvent(PowerEvent.WAKE)
        walkTo(130_000)
        assertEquals(listOf(5_000L, 115_000L), rpc.releaseCalls, "③ 연달아 깨면 마지막 한 번만")
    }

    @Test
    fun star4SleepPausesPeriodUntilWake() = runTest {
        val rpc = FakeUpdateRpc()
        val c = newChecker(rpc)
        c.startWatch()
        walkTo(6_000)
        c.onPowerEvent(PowerEvent.SLEEP)
        walkTo(3_600_000)
        assertEquals(listOf(5_000L), rpc.releaseCalls, "★4 잠든 동안 주기가 흐르지 않는다")
        c.onPowerEvent(PowerEvent.WAKE)
        walkTo(3_610_000)
        assertEquals(listOf(5_000L, 3_610_000L), rpc.releaseCalls)
    }

    @Test
    fun powerEventsIgnoredWhileNotWatching() = runTest {
        val rpc = FakeUpdateRpc()
        val c = newChecker(rpc)
        c.onPowerEvent(PowerEvent.WAKE)
        walkTo(3_600_000)
        assertEquals(emptyList(), rpc.releaseCalls, "감시 전엔 깨어남도 치지 않는다")
        c.startWatch()
        c.stopWatch()
        c.onPowerEvent(PowerEvent.WAKE)
        walkTo(7_200_000)
        assertEquals(emptyList(), rpc.releaseCalls)
    }

    @Test
    fun openThrottleSixtySecondsFromLastAttempt() = runTest {
        val rpc = FakeUpdateRpc()
        val c = newChecker(rpc)
        c.startWatch()
        walkTo(5_000)
        walkTo(64_999)
        c.onFlyoutOpened()
        runCurrent()
        assertEquals(listOf(5_000L), rpc.releaseCalls, "④ 마지막 시도 뒤 60초 안의 열기는 조용히 돌아간다")
        walkTo(65_000)
        c.onFlyoutOpened()
        runCurrent()
        assertEquals(listOf(5_000L, 65_000L), rpc.releaseCalls)
        // 주기는 열기 스로틀을 받지 않는다(305초에 그대로).
        walkTo(305_000)
        assertEquals(listOf(5_000L, 65_000L, 305_000L), rpc.releaseCalls)
    }

    @Test
    fun star2ReentrantChecksShareOneRequest() = runTest {
        val rpc = FakeUpdateRpc()
        val gate = CompletableDeferred<Unit>()
        rpc.gate = gate
        val c = newChecker(rpc)
        val a = launch { c.checkNow() }
        val b = launch { c.checkNow() }
        c.onFlyoutOpened()
        runCurrent()
        assertEquals(1, rpc.releaseCalls.size, "★2 떠 있는 조회가 있으면 새로 치지 않는다")
        gate.complete(Unit)
        a.join()
        b.join()
        assertTrue(a.isCompleted && b.isCompleted)
        assertEquals(1, rpc.releaseCalls.size)
        rpc.gate = null
        c.checkNow()
        assertEquals(2, rpc.releaseCalls.size, "끝난 뒤엔 다시 친다")
    }
}
