// 원본: Sources/check/WorkTimerStore.swift:4385-4420 @ a63fea2 (waitUntilSatisfied — 이미 satisfied 면 즉시, 취소되면 돌아온다,
//       상한은 스토어) — 시험은 새 코드. 묻기는 가짜 대본(합성), 시간은 가상 시계.
package com.yehsung.aingcheck.desktop.platform.windows.network

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class NetworkReadinessTest {
    private fun level(n: Int) = ConnectivityProbe.Level(n)

    @Test
    fun `판정표 — 경로가 있으면 준비됨(맥 satisfied), 없음·모름은 아직, 판독 불가·새 값은 연다`() {
        val table = (0..6).associateWith { ConnectivityLevels.classify(level(it)) }
        assertEquals(
            mapOf(
                0 to Readiness.NOT_YET, 1 to Readiness.NOT_YET, 2 to Readiness.READY, 3 to Readiness.READY,
                4 to Readiness.READY, 5 to Readiness.READY, 6 to Readiness.FAIL_OPEN,
            ),
            table,
        )
        assertEquals(Readiness.FAIL_OPEN, ConnectivityLevels.classify(ConnectivityProbe.Unavailable("UnsatisfiedLinkError")))
    }

    @Test
    fun `이미 준비됐으면 묻기 한 번에 돌아온다`() = runTest {
        var calls = 0
        val r = PolledNetworkReadiness({ calls++; level(ConnectivityLevels.INTERNET_ACCESS) }, probeContext = StandardTestDispatcher(testScheduler))
        r.awaitReady()
        assertEquals(1, calls)
        assertEquals(0L, testScheduler.currentTime)
    }

    @Test
    fun `깨어난 직후 없음 → 지역 접속이 되는 순간 돌아온다(간격마다 새로 묻는다)`() = runTest {
        val script = ArrayDeque(listOf(1, 1, 0, 2, 3))
        var calls = 0
        val r = PolledNetworkReadiness({ calls++; level(script.removeFirst()) }, pollMillis = 250, probeContext = StandardTestDispatcher(testScheduler))
        var done = false
        launch { r.awaitReady(); done = true }
        runCurrent()
        assertFalse(done)
        advanceTimeBy(500); runCurrent()
        assertFalse(done, "셋째 묻기(모름)에서 열렸다")
        advanceTimeBy(250); runCurrent()
        assertTrue(done)
        assertEquals(4, calls)
        assertEquals(level(2), r.lastProbe)
    }

    @Test
    fun `함수가 없거나 묻기가 던지면 바로 연다(fail-open — 매 깨움 10초 대기 금지)`() = runTest {
        val r = PolledNetworkReadiness({ throw UnsatisfiedLinkError("GetNetworkConnectivityHint") }, probeContext = StandardTestDispatcher(testScheduler))
        r.awaitReady()
        assertEquals(0L, testScheduler.currentTime)
        assertTrue(r.lastProbe is ConnectivityProbe.Unavailable)
    }

    @Test
    fun `끝내 없음이면 부르는 쪽 상한이 이긴다(취소에 응한다 — 영구 대기 금지)`() = runTest {
        var calls = 0
        val r = PolledNetworkReadiness({ calls++; level(ConnectivityLevels.NONE) }, pollMillis = 250, probeContext = StandardTestDispatcher(testScheduler))
        val result = withTimeoutOrNull(10_000) { r.awaitReady() }
        assertNull(result)
        assertTrue(calls in 40..41, "10초 동안 250ms 간격(0ms 포함 — 마지막 박자와 상한이 같은 순간): $calls")
    }

    @Test
    fun `맥 개발 실행은 늘 준비됨`() = runTest {
        NetworkReadiness.forHost(isWindows = false).awaitReady()
        assertEquals(NetworkReadiness.AlwaysReady, NetworkReadiness.forHost(isWindows = false))
        assertEquals(12, NL_NETWORK_CONNECTIVITY_HINT.EXPECTED_SIZE)
    }
}
