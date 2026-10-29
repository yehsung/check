// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift:85-89 @ a90d8623 (★1 초를 보이지 않아야 티커를 60초로 늦출 수 있다)
//       · CheckMenuView.swift:1186-1190 (매초 재계산 없음 — == 가드)
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TrayTickPlannerTest {
    private class FakeHost(private val now: () -> Long) : TrayHost {
        val uploads = mutableListOf<Pair<Long, String>>()
        override fun show(icon: RasterImage, tooltip: String) { uploads += now() to tooltip }
        override fun update(icon: RasterImage, tooltip: String) { uploads += now() to tooltip }
        override fun remove() {}
        override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit) = Registration {}
    }

    private fun work(sec: Long, pending: Boolean = false) = WorkStatusSnapshot(WorkStatus.working, sec, pending)

    @Test
    fun plannerWakesOnlyAtMinuteBoundaries() {
        assertEquals(55_000L, TrayTickPlanner.nextDelayMillis(work(125), 125_000))
        assertEquals(60_000L, TrayTickPlanner.nextDelayMillis(work(180), 180_000))
        assertEquals(1L, TrayTickPlanner.nextDelayMillis(work(179), 179_999))
        assertNull(TrayTickPlanner.nextDelayMillis(WorkStatusSnapshot(WorkStatus.offWork, 0), 0))
        assertNull(TrayTickPlanner.nextDelayMillis(work(125, pending = true), 125_000), "대기는 시계를 그리지 않는다")
    }

    private fun TestScope.presenter(work: MutableStateFlow<WorkStatusSnapshot>): Pair<TrayPresenter, FakeHost> {
        val host = FakeHost { testScheduler.currentTime }
        val p = TrayPresenter(host, sizePx = { 16 }, monotonicMillis = { testScheduler.currentTime })
        p.start(backgroundScope, work, MutableStateFlow(TrayDotReasons()), MutableStateFlow(TaskbarTheme.DARK))
        return p to host
    }

    @Test
    fun workingTenMinutesIsElevenUploadsZeroOneSecondTicks() = runTest {
        val work = MutableStateFlow(work(125))
        val (p, host) = presenter(work)
        runCurrent()
        advanceTimeBy(600_000)
        runCurrent()
        // 첫 장 + 분 경계 열 번(180·240·…·720 초)
        assertEquals(11, host.uploads.size, host.uploads.toString())
        assertEquals(11, p.wakeups, "깨어남도 분 경계만")
        for ((t, _) in host.uploads.drop(1)) assertEquals(0L, (125_000 + t) % 60_000, "분 경계가 아닌 ${t}ms 에 올렸다")
        assertTrue(host.uploads.last().second.endsWith("00:12"), host.uploads.last().second)
    }

    @Test
    fun perSecondUpstreamValuesDoNotRedrawWithinAMinute() = runTest {
        val work = MutableStateFlow(work(125))
        val (_, host) = presenter(work)
        runCurrent()
        repeat(120) { i ->
            advanceTimeBy(1_000)
            work.value = work(126L + i)
            runCurrent()
        }
        // 125 → 245 초: 분이 바뀐 것은 180·240 두 번뿐
        assertEquals(3, host.uploads.size, host.uploads.toString())
    }

    @Test
    fun offAndPendingNeverTick() = runTest {
        val work = MutableStateFlow(WorkStatusSnapshot(WorkStatus.offWork, 0))
        val (p, host) = presenter(work)
        runCurrent()
        advanceTimeBy(600_000)
        assertEquals(1, host.uploads.size)
        assertEquals(1, p.wakeups)
        work.value = work(30, pending = true)
        runCurrent()
        advanceTimeBy(600_000)
        assertEquals(2, host.uploads.size)
        assertEquals(2, p.wakeups)
    }
}
