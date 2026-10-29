// 원본: Tests/CheckMobileKitTests/BaseWidgetSnapshotTests.swift:161-186(같은 값 건너뛰기 · 30초 스로틀 · 뒤늦은 새로고침 · clear) ·
//       Sources/CheckMobileKit/App/WidgetSnapshotWriter.swift @ 3bd04bd
// G §2-3 W2-f ③: 위젯 스냅숏은 30초 스로틀 — 새로고침 횟수를 가상 시간으로 센다.
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.phone.MemoryWidgetFile
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class WidgetSnapshotWriterTest {
    private class Rig(scope: TestScope, val file: MemoryWidgetFile = MemoryWidgetFile()) {
        var reloads = 0
        val clock = SessionClock { SwiftDate(BASE + scope.testScheduler.currentTime / 1000.0) }
        val writer = WidgetSnapshotWriter(file, clock, scope.backgroundScope) { reloads += 1 }
    }

    private fun me(today: Int) = WidgetSnapshot.Me(true, SwiftDate(BASE - 600.0), today, today, 40, WidgetSnapshot.WorkState.working)

    @Test
    fun firstWriteReloadsNowAndLaterWritesCoalesceIntoOneTrailingReloadPer30Seconds() = runTest {
        val rig = Rig(this)
        rig.writer.update { it.copy(me = me(1)) }
        assertEquals(1, rig.reloads, "첫 쓰기는 바로 새로고침")
        advanceTimeBy(10_000)
        rig.writer.update { it.copy(me = me(2)) }
        advanceTimeBy(10_000)
        rig.writer.update { it.copy(me = me(3)) }
        runCurrent()
        assertEquals(3, rig.writer.writeCount, "값이 바뀌면 파일은 매번 쓴다")
        assertEquals(1, rig.reloads, "30초 창 안의 새로고침은 미룬다")
        assertTrue(rig.writer.hasTrailingReload, "창 끝의 뒤늦은 새로고침 하나만 걸린다")
        advanceTimeBy(9_999)
        runCurrent()
        assertEquals(1, rig.reloads)
        advanceTimeBy(2)
        runCurrent()
        assertEquals(2, rig.reloads, "창(30초)이 끝나는 순간 한 번 더 민다 — 마지막 값이 홈 화면에 남지 않게")
        assertFalse(rig.writer.hasTrailingReload)
        assertEquals(me(3), WidgetSnapshotCodec.decode(rig.file.bytes!!)!!.me)
    }

    @Test
    fun everySecondChangesForTwoMinutesNeverReloadMoreThanOncePer30Seconds() = runTest {
        val rig = Rig(this)
        for (second in 0 until 120) {
            rig.writer.update { it.copy(me = me(second)) }
            advanceTimeBy(1_000)
            runCurrent()
        }
        advanceUntilIdle()
        assertEquals(120, rig.writer.writeCount)
        assertTrue(rig.reloads <= 1 + 120 / 30 + 1, "1초마다 바뀌어도 새로고침은 30초에 한 번(실측 ${rig.reloads})")
        assertTrue(rig.reloads >= 4, "그래도 30초마다는 민다(실측 ${rig.reloads})")
    }

    @Test
    fun sameValueSkipsFileAndReloadEvenThoughTimeMoved() = runTest {
        // INV-WidgetSnapshot-af897ec6(소비 쪽): 리밋 칸은 절대 시각만 담는다 — 같은 패널을 다시 넘기면 쓰기 창구의 중복 제거가 파일도 위젯도
        //   건드리지 않는다("남은 초"를 실었다면 매번 값이 달라 60초마다 다시 쓰고 위젯 예산을 태웠다).
        val rig = Rig(this)
        val panel = MeAILimitWidgetPanel(
            providers = listOf(MeAILimitWidgetRow("claude", 30.0, SwiftDate(BASE + 3_600), 10.0, SwiftDate(BASE + 86_400), SwiftDate(BASE - 60))),
            deviceName = "Mac mini (A1B2)",
            deviceNameTail = "A1B2",
        )
        rig.writer.update { it.copy(aiLimits = panel) }
        advanceTimeBy(60_000)
        rig.writer.update { it.copy(aiLimits = panel) }
        rig.writer.update { it }
        advanceUntilIdle()
        assertEquals(1, rig.writer.writeCount, "generatedAt 만 다른 쓰기는 하지 않는다")
        assertEquals(1, rig.reloads)
        assertEquals(1, rig.file.writes)
    }

    @Test
    fun clearRemovesFileReloadsImmediatelyAndCancelsTrailing() = runTest {
        val rig = Rig(this)
        rig.writer.update { it.copy(me = me(1)) }
        advanceTimeBy(5_000)
        rig.writer.update { it.copy(me = me(2)) }
        assertTrue(rig.writer.hasTrailingReload)
        rig.writer.clear()
        assertNull(rig.file.bytes)
        assertNull(rig.writer.current)
        assertEquals(2, rig.reloads, "로그아웃 화면은 스로틀 없이 바로")
        advanceUntilIdle()
        assertEquals(2, rig.reloads, "걸려 있던 뒤늦은 새로고침은 거둔다")
    }

    @Test
    fun writeFailureKeepsPreviousFileAndDoesNotReload() = runTest {
        val rig = Rig(this)
        rig.writer.update { it.copy(me = me(1)) }
        rig.file.failWrites = true
        advanceTimeBy(40_000)
        rig.writer.update { it.copy(me = me(2)) }
        assertEquals(me(1), rig.writer.current?.me, "쓰기 실패는 조용히 — 직전 값을 지킨다")
        assertEquals(1, rig.reloads)
    }

    @Test
    fun startsFromTheFileOnDiskAndTouchMovesOnlyStaleNonCountingSnapshots() = runTest {
        val existing = WidgetSnapshot(generatedAt = SwiftDate(BASE - 120), me = WidgetSnapshot.Me(false, null, 3_600, 7_200, 40, WidgetSnapshot.WorkState.off))
        val rig = Rig(this, MemoryWidgetFile(WidgetSnapshotCodec.encode(existing)))
        assertEquals(existing, rig.writer.current, "시작할 때 파일을 읽는다")
        // 60초 넘게 낡았고 세는 me 가 아니다 → generatedAt 만 옮기고 새로고침.
        assertTrue(rig.writer.touchGeneratedAt(rig.clock.now(), 60.0))
        assertEquals(rig.clock.now(), WidgetSnapshotCodec.decode(rig.file.bytes!!)!!.generatedAt)
        assertEquals(1, rig.reloads)
        // 방금 옮겼으니 60초 안에는 다시 옮기지 않는다.
        assertFalse(rig.writer.touchGeneratedAt(rig.clock.now(), 60.0))
        // 세는 me(근무 중 · 시작 시각 있음)는 옮기지 않는다 — 누적이 generatedAt 기준이다.
        val counting = WidgetSnapshot(generatedAt = SwiftDate(BASE - 300), me = me(100))
        val rig2 = Rig(this, MemoryWidgetFile(WidgetSnapshotCodec.encode(counting)))
        assertFalse(rig2.writer.touchGeneratedAt(rig2.clock.now(), 60.0))
        assertEquals(0, rig2.reloads)
    }

    private companion object {
        const val BASE = 1_789_621_500.0
    }
}
