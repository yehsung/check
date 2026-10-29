// 원본: Tests/checkTests/CheckTodoBoardWindowTests.swift:178-240 · :684-786(앵커 시나리오) @ ef9fab11
// 맥은 y 위로(왼쪽 아래 원점), 여기는 y 아래로(DIP). 맥 숫자를 같은 장면으로 옮겨 적었다: 맥 maxY → 여기 top = 화면높이 − maxY.
package com.yehsung.aingcheck.desktop.overlay.todoboard

import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class TodoBoardAnchorTest {
    private val W = TodoBoardAnchor.BOARD_WIDTH
    private val H = TodoBoardAnchor.BOARD_HEIGHT
    private val GAP = TodoBoardAnchor.GAP

    private fun assertInside(frame: OverlayRect, work: OverlayRect) {
        assertTrue(frame.left >= work.left && frame.right <= work.right, "가로 밖: $frame / $work")
        assertTrue(frame.top >= work.top && frame.bottom <= work.bottom, "세로 밖: $frame / $work")
        assertEquals(W, frame.width)
        assertEquals(H, frame.height)
    }

    @Test
    fun anchorSitsLeftOfCharacterAndTopAligned() {
        val work = OverlayRect(0.0, 0.0, 1440.0, 900.0)
        val anchor = OverlayRect(1200.0, 130.0, 140.0, 170.0)
        val f = TodoBoardAnchor.frame(anchor, work)
        assertEquals(anchor.left - GAP, f.right) // 1190
        assertEquals(890.0, f.left)
        assertEquals(anchor.top, f.top) // 상단 정렬
        assertEquals(530.0, f.bottom)
        assertEquals(300.0 to 400.0, f.width to f.height) // 크기 고정 300×400
    }

    @Test
    fun anchorFlipsToRightWhenLeftSideIsOffScreen() {
        val work = OverlayRect(0.0, 0.0, 1440.0, 900.0)
        val anchor = OverlayRect(20.0, 130.0, 140.0, 170.0)
        val f = TodoBoardAnchor.frame(anchor, work)
        assertEquals(anchor.right + GAP, f.left) // 170
        assertEquals(470.0, f.right)
        assertEquals(anchor.top, f.top)
        assertInside(f, work)
    }

    @Test
    fun anchorClampsInsteadOfFlippingWhenNeitherSideFits() {
        val work = OverlayRect(0.0, 0.0, 400.0, 900.0)
        val anchor = OverlayRect(150.0, 130.0, 60.0, 170.0)
        val f = TodoBoardAnchor.frame(anchor, work)
        assertEquals(work.left, f.left)
        assertEquals(300.0, f.right)
        assertNotEquals(anchor.right + GAP, f.left)
        assertTrue(f.intersects(anchor), "보드가 캐릭터를 잠깐 가리는 편이 낫다(크기는 줄이지 않는다)")
    }

    @Test
    fun anchorClampsVerticallyWithoutFlippingUpward() {
        // 맥: visible(-1600,200,1440,900) · anchor(-400,250,140,170) → 여기: 화면 위=0, 아래=900, anchor top = 1100−420 = 680.
        val work = OverlayRect(-1600.0, 0.0, 1440.0, 900.0)
        val anchor = OverlayRect(-400.0, 680.0, 140.0, 170.0)
        val f = TodoBoardAnchor.frame(anchor, work)
        assertEquals(work.bottom, f.bottom) // 바닥으로 클램프
        assertEquals(500.0, f.top)
        assertNotEquals(anchor.top - GAP - H, f.top, "위로 뒤집지 않는다")
        assertEquals(anchor.left - GAP, f.right) // -410
        assertInside(f, work)
    }

    @Test
    fun flipsExactlyOnceAcrossAFullDragSweep() {
        val work = OverlayRect(0.0, 0.0, 1440.0, 900.0)
        val sides = ArrayList<Boolean>()
        var transitions = 0
        for (step in 0..1300) {
            val anchor = OverlayRect(step.toDouble(), 130.0, 140.0, 170.0)
            val f = TodoBoardAnchor.frame(anchor, work)
            assertInside(f, work)
            val isRight = f.left >= anchor.right
            if (sides.isNotEmpty() && sides.last() != isRight) transitions += 1
            sides += isRight
        }
        assertEquals(true, sides.first())
        assertEquals(false, sides.last())
        assertEquals(1, transitions, "드래그 한 번에 보드가 ${transitions}회 뒤집혔다")
    }

    @Test
    fun flipBoundaryIsExact() {
        val work = OverlayRect(0.0, 0.0, 1440.0, 900.0)
        val exact = work.left + GAP + W // 310
        val fits = TodoBoardAnchor.frame(OverlayRect(exact, 130.0, 140.0, 170.0), work)
        assertEquals(work.left, fits.left)
        assertEquals(exact - GAP, fits.right)
        val doesNotFit = TodoBoardAnchor.frame(OverlayRect(exact - 1, 130.0, 140.0, 170.0), work)
        assertEquals((exact - 1) + 140 + GAP, doesNotFit.left) // 1 모자라면 곧바로 오른쪽

        val narrow = OverlayRect(0.0, 0.0, 705.0, 900.0)
        val justFlips = OverlayRect(305.0, 130.0, 90.0, 170.0)
        val flipped = TodoBoardAnchor.frame(justFlips, narrow)
        assertEquals(justFlips.right + GAP, flipped.left) // 405 — 딱 맞으니 뒤집는다
        assertEquals(narrow.right, flipped.right)
        val cannotFlip = OverlayRect(306.0, 130.0, 90.0, 170.0)
        val clamped = TodoBoardAnchor.frame(cannotFlip, narrow)
        assertEquals(narrow.left, clamped.left) // 뒤집지 않고 왼쪽 클램프
        assertNotEquals(cannotFlip.right + GAP, clamped.left)
    }

    @Test
    fun flipsOnNegativeOriginSecondMonitor() {
        val work = OverlayRect(-1600.0, 0.0, 1440.0, 900.0) // right = -160
        val atLeft = OverlayRect(-1590.0, 130.0, 140.0, 170.0)
        val flipped = TodoBoardAnchor.frame(atLeft, work)
        assertEquals(atLeft.right + GAP, flipped.left) // -1440
        assertInside(flipped, work)
        val atRight = OverlayRect(-300.0, 130.0, 140.0, 170.0)
        val left = TodoBoardAnchor.frame(atRight, work)
        assertEquals(atRight.left - GAP, left.right) // -310
        assertInside(left, work)
    }

    @Test
    fun clampsBelowTopEdge() {
        // 맥: anchor maxY 1050 > 화면 900 → 여기 top = 900 − 1050 = −150.
        val work = OverlayRect(0.0, 0.0, 1440.0, 900.0)
        val anchor = OverlayRect(1000.0, -150.0, 140.0, 170.0)
        val f = TodoBoardAnchor.frame(anchor, work)
        assertEquals(work.top, f.top)
        assertEquals(400.0, f.bottom)
    }

    @Test
    fun facingPointsAtTheBoardCentre() {
        val character = OverlayRect(1200.0, 130.0, 140.0, 170.0)
        assertEquals(-1, TodoBoardAnchor.facing(OverlayRect(890.0, 130.0, W, H), character))
        assertEquals(1, TodoBoardAnchor.facing(OverlayRect(1350.0, 130.0, W, H), character))
        // 두 중심이 같으면(덮도록 클램프된 극단) 오른쪽.
        assertEquals(1, TodoBoardAnchor.facing(OverlayRect(1120.0, 130.0, W, H), character))
    }
}
