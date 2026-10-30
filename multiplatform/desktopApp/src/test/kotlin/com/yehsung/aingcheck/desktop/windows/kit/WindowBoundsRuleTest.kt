// 원본: Sources/check/CheckMiniGameWindow.swift:160-176(setFrameUsingName — 없으면 화면 중앙) (W4-d)
//       모니터 배치는 합성값만(실제 화면 정보 안 읽음).
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class WindowBoundsRuleTest {
    // 100%: 1920×1080 주 모니터(작업 표시줄 40) + 오른쪽 1920×1080 보조.
    private val primary100 = PxRect(0, 0, 1920, 1040)
    private val secondary100 = PxRect(1920, 0, 3840, 1040)
    // 150%: 2880×1620 주 모니터(작업 표시줄 60).
    private val primary150 = PxRect(0, 0, 2880, 1560)

    private val game100 = WindowBoundsRule.sizePx(440, 720, 1.0)
    private val game150 = WindowBoundsRule.sizePx(440, 720, 1.5)

    @Test
    fun dpToPxAtScale100And150() {
        assertEquals(440 to 720, game100)
        assertEquals(660 to 1080, game150)
        assertEquals(630 to 828, WindowBoundsRule.sizePx(420, 552, 1.5))
    }

    @Test
    fun noSavedValueCentersOnPrimaryAtBothScales() {
        assertEquals(PxRect(740, 160, 1180, 880), WindowBoundsRule.restore(null, listOf(primary100, secondary100), game100))
        assertEquals(PxRect(1110, 240, 1770, 1320), WindowBoundsRule.restore(null, listOf(primary150), game150))
    }

    @Test
    fun defaultLargerThanWorkAreaIsClamped() {
        // 150% 기본(660×1080)이 100% 작업 영역(1040 높이)보다 크다 — 높이를 줄인다.
        assertEquals(PxRect(630, 0, 1290, 1040), WindowBoundsRule.restore(null, listOf(primary100), game150))
    }

    @Test
    fun savedOnLiveSecondaryMonitorIsKept() {
        val saved = PxRect(2500, 100, 2940, 820)
        assertEquals(saved, WindowBoundsRule.restore(saved, listOf(primary100, secondary100), game100))
    }

    @Test
    fun monitorRemovedMovesToPrimaryKeepingSize() {
        val saved = PxRect(2500, 100, 2940, 820)   // 보조 모니터가 빠졌다.
        assertEquals(PxRect(740, 160, 1180, 880), WindowBoundsRule.restore(saved, listOf(primary100), game100))
    }

    @Test
    fun offScreenSavedValueIsRecentered() {
        val farLeft = PxRect(-5000, 100, -4560, 820)
        assertEquals(PxRect(740, 160, 1180, 880), WindowBoundsRule.restore(farLeft, listOf(primary100), game100))
        val titleAbove = PxRect(100, -30, 540, 690)   // 제목줄이 작업 영역 위로 나갔다.
        assertEquals(PxRect(740, 160, 1180, 880), WindowBoundsRule.restore(titleAbove, listOf(primary100), game100))
        val titleBelow = PxRect(100, 1000, 540, 1720)   // 제목줄 아래로 48px 이 안 남는다.
        assertEquals(PxRect(740, 160, 1180, 880), WindowBoundsRule.restore(titleBelow, listOf(primary100), game100))
    }

    @Test
    fun barelyVisibleNeedsMinVisiblePixels() {
        val sliver = PxRect(1900, 100, 2340, 820)   // 겹침 20px < 48
        assertEquals(PxRect(740, 160, 1180, 880), WindowBoundsRule.restore(sliver, listOf(primary100), game100))
        val enough = PxRect(1800, 100, 2240, 820)   // 겹침 120px
        assertEquals(enough, WindowBoundsRule.restore(enough, listOf(primary100), game100))
    }

    @Test
    fun savedAt150OnSmallerMonitorShrinksInside() {
        val saved = PxRect(200, 100, 860, 1180)   // 150% 에서 저장한 660×1080 → 1040 높이 영역
        assertEquals(PxRect(200, 0, 860, 1040), WindowBoundsRule.restore(saved, listOf(primary100), game100))
    }

    @Test
    fun noWorkAreasFallsBackToOrigin() {
        assertEquals(PxRect(0, 0, 440, 720), WindowBoundsRule.restore(PxRect(10, 10, 50, 50), emptyList(), game100))
    }

    @Test
    fun keyValueStoreRoundTripAndRejectsBroken() {
        val kv = InMemoryDesktopKeyValueStore()
        val store = KeyValueWindowBoundsStore(kv)
        val r = PxRect(-1200, 40, -760, 760)
        store.save(GameWindowKind.Gomoku.boundsKey, r)
        assertEquals(r, store.load(GameWindowKind.Gomoku.boundsKey))
        assertEquals("-1200,40,-760,760", kv.getString("windowBounds.check.gomoku.window"))
        assertNull(store.load(GameWindowKind.Chess.boundsKey))
        store.save(GameWindowKind.Chess.boundsKey, PxRect(10, 10, 10, 50))   // 빈 사각형은 저장 안 함
        assertNull(kv.getString("windowBounds.check.chess.window"))
        for (bad in listOf("1,2,3", "a,b,c,d", "0,0,0,0", "5,5,1,1", "")) {
            kv.putString("windowBounds.x", bad)
            assertNull(store.load("x"), "'$bad'")
        }
    }
}
