// 원본: Tests/checkTests/V0348ChessDragPointerTests.swift @ 1a5eeca6 — 판 위 포인터 해석기. "이 입력 열을 넣으면 이 행동 열이 나온다"를 전수로 잰다.
// 수는 Swift 시험과 같다(76 칸 · 문턱 4). 폰은 문턱만 터치 슬롭으로 넘기고(문턱 값 시험을 아래에 따로 둔다) 판정은 한 벌이다. 마지막 절은 폰 전용(스크롤이 손가락을 가져감).
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.chess.ChessBoardPointer.Action
import com.yehsung.aingcheck.core.stores.gomoku.BoardPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChessBoardPointerTest {
    private fun sq(notation: String): ChessSquare = ChessSquare.parse(notation)!!

    /** 76 칸(실제 맥 판과 같은 크기)에서 그 칸 가운데. 백이 아래다. */
    private fun center(square: ChessSquare) = BoardPoint(square.file * 76.0 + 38, (7 - square.rank) * 76.0 + 38)
    private fun at(x: Double, y: Double) = BoardPoint(x, y)
    private val e2 = sq("e2")
    private val e4 = sq("e4")
    private val movable = ChessDragGrab.movable
    private val stuck = ChessDragGrab.stuck
    private val none = ChessDragGrab.none

    private fun pressed(square: ChessSquare = e2, grab: ChessDragGrab = movable, target: Boolean = false, point: BoardPoint = center(square)) =
        ChessBoardPointer().also { assertEquals(emptyList(), it.press(point, square, grab, target)) }

    // ① 문턱 경계(3.9 / 4.0 / 4.1)

    @Test
    fun thresholdBoundary() {
        val origin = center(e2)
        assertEquals(4.0, ChessBoardPointer.DEFAULT_DRAG_THRESHOLD)
        // 대각선은 **유클리드 거리**로 잰다 — 축마다 따로 재면 (3, 3)=4.24 가 탭이 된다.
        for ((dx, dy, drags) in listOf(
            Triple(3.9, 0.0, false), Triple(4.0, 0.0, true), Triple(4.1, 0.0, true),
            Triple(0.0, -3.9, false), Triple(0.0, -4.0, true), Triple(0.0, 4.1, true),
            Triple(-3.9, 0.0, false), Triple(-4.0, 0.0, true),
            Triple(2.8, 2.8, false), Triple(3.0, 3.0, true),
        )) {
            val pointer = pressed()
            val moved = at(origin.x + dx, origin.y + dy)
            val actions = pointer.move(moved)
            if (drags) {
                assertEquals(listOf(Action.BeginDrag(e2), Action.DragMoved(moved)), actions, "($dx, $dy) 움직였는데 끌기가 안 시작됐다")
                assertEquals(e2, pointer.draggingFrom)
            } else {
                assertEquals(emptyList(), actions, "($dx, $dy) 는 문턱 밑인데 행동이 나왔다")
                assertNull(pointer.draggingFrom)
                assertEquals(listOf<Action>(Action.Tap(e2)), pointer.release(moved, e2))
            }
        }
    }

    /** 폰: 문턱은 화면이 넘긴 터치 슬롭이다 — 같은 움직임이 슬롭 밑이면 탭, 이상이면 끌기(판정 몸통은 맥과 한 벌). */
    @Test
    fun touchSlopReplacesTheMouseThreshold() {
        val origin = center(e2)
        val slop = ChessBoardPointer(dragThreshold = 16.0)
        slop.press(origin, e2, movable, false)
        assertEquals(emptyList(), slop.move(at(origin.x + 15.9, origin.y)), "손가락 떨림(문턱 밑)이 끌기가 됐다 — 고른 말을 다시 눌러 해제가 죽는다")
        assertEquals(listOf<Action>(Action.Tap(e2)), slop.release(at(origin.x + 15.9, origin.y), e2))
        val crossed = ChessBoardPointer(dragThreshold = 16.0)
        crossed.press(origin, e2, movable, false)
        val moved = at(origin.x + 16.0, origin.y)
        assertEquals(listOf(Action.BeginDrag(e2), Action.DragMoved(moved)), crossed.move(moved))
    }

    @Test
    fun jitterUnderTheThresholdIsOneTap() {
        val origin = center(e2)
        val pointer = pressed()
        val all = ArrayList<Action>()
        for (step in 0 until 40) all += pointer.move(at(origin.x + (if (step % 2 == 0) 3 else -3), origin.y + 2))
        all += pointer.release(at(origin.x + 3, origin.y + 2), e2)
        assertEquals(listOf<Action>(Action.Tap(e2)), all, "문턱 밑 흔들림 40번")
        assertTrue(pointer.isIdle)
    }

    @Test
    fun onceDraggingAlwaysDragging() {
        val origin = center(e2)
        val pointer = pressed()
        pointer.move(at(origin.x + 30, origin.y))
        assertEquals(listOf<Action>(Action.DragMoved(origin)), pointer.move(origin), "되돌아온 움직임이 끄는 자리로 안 나왔다")
        assertEquals(listOf<Action>(Action.Drop(e2, e2)), pointer.release(origin, e2))
    }

    @Test
    fun flickWithoutMoveEvents() {
        val pointer = pressed()
        assertEquals(listOf(Action.BeginDrag(e2), Action.Drop(e2, e4)), pointer.release(center(e4), e4))
        assertTrue(pointer.isIdle)
    }

    // ② 끌기 한 바퀴

    @Test
    fun aFullDrag() {
        val pointer = pressed()
        val all = ArrayList<Action>()
        val path = (0..152 step 19).map { at(center(e2).x, center(e2).y - it) }
        for (point in path) all += pointer.move(point)
        all += pointer.release(center(e4), e4)
        assertEquals(listOf<Action>(Action.BeginDrag(e2)), all.filterIsInstance<Action.BeginDrag>())
        assertEquals(Action.Drop(e2, e4), all.last())
        assertEquals(1, all.filterIsInstance<Action.Drop>().size)
        assertEquals(path.drop(1), all.filterIsInstance<Action.DragMoved>().map { it.point })
        assertTrue(all.none { it is Action.Tap }, "끌기에서 탭이 나왔다")
        assertEquals(emptyList(), pointer.move(center(e4)))
        assertEquals(emptyList(), pointer.release(center(e4), e4))
    }

    @Test
    fun droppingOffTheBoard() {
        val pointer = pressed()
        pointer.move(at(-40.0, 300.0))
        assertEquals(listOf<Action>(Action.Drop(e2, null)), pointer.release(at(-40.0, 300.0), null))
    }

    // ③ 끌기가 안 되는 누름

    @Test
    fun plainPressTapsOnlyOnTheSameSquare() {
        val e5 = sq("e5")
        val origin = center(e4)
        val same = pressed(e4, none)
        val inside = at(origin.x + 30, origin.y - 20)
        assertEquals(emptyList(), same.move(inside), "끌 수 없는 누름이 움직임에 행동을 냈다")
        assertNull(same.draggingFrom)
        assertEquals(listOf<Action>(Action.Tap(e4)), same.release(inside, e4))
        val other = pressed(e4, none)
        other.move(center(e5))
        assertEquals(emptyList(), other.release(center(e5), e5), "다른 칸에서 뗐는데 행동이 나왔다")
        val outside = pressed(e4, none)
        assertEquals(emptyList(), outside.release(at(700.0, 10.0), null))
        assertTrue(outside.isIdle)
    }

    @Test
    fun pressingASelectionTargetNeverDrags() {
        val d5 = sq("d5")
        val slid = at(center(d5).x + 9, center(d5).y)
        val target = pressed(d5, movable, target = true)
        assertEquals(emptyList(), target.move(slid))
        assertEquals(listOf<Action>(Action.Tap(d5)), target.release(slid, d5), "도착 칸 누름이 탭으로 안 나왔다")
        val plain = pressed(d5, movable)
        assertEquals(listOf(Action.BeginDrag(d5), Action.DragMoved(slid)), plain.move(slid), "전제: 같은 누름이 도착 칸이 아니면 끌기다")
    }

    /** 끌기가 안 되는 누름 — 문턱 밑 손떨림은 칸 경계를 넘어 떼도 누른 칸의 탭이고, 문턱부터는 아무 일도 없다. */
    @Test
    fun aWiggleAcrossACellBorderStillTapsThePressedSquare() {
        val f4 = sq("f4")
        val e5 = sq("e5")
        val h4 = sq("h4")
        val borderX = center(e4).x + 38
        val borderY = center(e4).y - 38
        val edgeX = center(h4).x + 38
        val rowY = center(e4).y

        data class Wiggle(val label: String, val press: BoardPoint, val pressed: ChessSquare, val release: BoardPoint, val released: ChessSquare?, val taps: Boolean)
        val cases = listOf(
            Wiggle("0.8(경계 0.4 안 → 0.4 밖)", at(borderX - 0.4, rowY), e4, at(borderX + 0.4, rowY), f4, true),
            Wiggle("3.9", at(borderX - 0.5, rowY), e4, at(borderX + 3.4, rowY), f4, true),
            Wiggle("4.0", at(borderX - 0.5, rowY), e4, at(borderX + 3.5, rowY), f4, false),
            Wiggle("4.1", at(borderX - 0.5, rowY), e4, at(borderX + 3.6, rowY), f4, false),
            Wiggle("세로 3.0(위 칸으로)", at(center(e4).x, borderY + 1.5), e4, at(center(e4).x, borderY - 1.5), e5, true),
            Wiggle("세로 4.0(위 칸으로)", at(center(e4).x, borderY + 0.5), e4, at(center(e4).x, borderY - 3.5), e5, false),
            Wiggle("판 밖으로 0.8", at(edgeX - 0.4, rowY), h4, at(edgeX + 0.4, rowY), null, true),
            Wiggle("판 밖으로 4.0", at(edgeX - 0.5, rowY), h4, at(edgeX + 3.5, rowY), null, false),
        )
        val presses = listOf(Triple("빈 칸·상대 말", none, false), Triple("도착 칸", none, true), Triple("도착 칸(내 말이 선)", movable, true))
        for (item in cases) for ((name, grab, isTarget) in presses) {
            val pointer = ChessBoardPointer()
            assertEquals(emptyList(), pointer.press(item.press, item.pressed, grab, isTarget))
            assertEquals(emptyList(), pointer.move(item.release), "$name · ${item.label}: 움직임에 행동이 나왔다")
            val wanted: List<Action> = if (item.taps) listOf(Action.Tap(item.pressed)) else emptyList()
            assertEquals(wanted, pointer.release(item.release, item.released), "$name · ${item.label}")
            assertTrue(pointer.isIdle)
        }
        // 같은 칸이면 얼마를 움직였든 탭(대조).
        val same = ChessBoardPointer()
        same.press(at(borderX - 30, rowY), e4, none, true)
        assertEquals(listOf<Action>(Action.Tap(e4)), same.release(at(borderX - 0.5, rowY), e4))
    }

    @Test
    fun stuckPieceRefusesOnceOnRelease() {
        for ((point, square) in listOf(center(e4) to e4, center(e2) to e2, at(-5.0, -5.0) to null)) {
            val pointer = pressed(e2, stuck)
            val all = ArrayList<Action>()
            all += pointer.move(at(center(e2).x, center(e2).y - 60))
            all += pointer.move(point)
            assertEquals(emptyList(), all, "못 끄는 말이 움직임에 행동을 냈다")
            assertNull(pointer.draggingFrom)
            all += pointer.release(point, square)
            assertEquals(listOf<Action>(Action.Tap(e2)), all, "${square?.notation ?: "판 밖"} 에서 뗐을 때")
        }
    }

    @Test
    fun pressingOffTheBoardIsSilent() {
        val pointer = ChessBoardPointer()
        assertEquals(emptyList(), pointer.press(at(-3.0, 100.0), null, none, false))
        assertFalse(pointer.isIdle)
        assertEquals(emptyList(), pointer.move(center(e4)))
        assertEquals(emptyList(), pointer.release(center(e4), e4))
        assertTrue(pointer.isIdle)
    }

    // ④ 취소

    @Test
    fun cancelWhileDraggingSpendsThePress() {
        val pointer = pressed()
        pointer.move(center(e4))
        assertEquals(e2, pointer.draggingFrom)
        assertEquals(listOf<Action>(Action.Cancel), pointer.cancel())
        assertNull(pointer.draggingFrom)
        assertFalse(pointer.isIdle, "취소된 누름이 처음으로 돌아갔다 — 손가락은 아직 닿아 있다")
        assertTrue(pointer.isTracking(center(e2)), "취소 뒤의 움직임이 새 누름으로 읽힌다")
        assertEquals(emptyList(), pointer.cancel(), "두 번째 취소가 또 거두기를 냈다")
        assertEquals(emptyList(), pointer.move(center(e4)))
        assertEquals(emptyList(), pointer.release(center(e4), e4), "취소한 뒤 뗐는데 놓기가 나갔다")
        assertTrue(pointer.isIdle)
        // 대조: 취소가 없으면 같은 입력이 놓기다.
        val control = pressed()
        control.move(center(e4))
        assertEquals(listOf<Action>(Action.Drop(e2, e4)), control.release(center(e4), e4))
    }

    @Test
    fun cancelBeforeDraggingKeepsTheTap() {
        for (grab in listOf(movable, stuck, none)) {
            val same = pressed(e2, grab)
            assertEquals(emptyList(), same.cancel(), "끌기 전 취소가 행동을 냈다")
            assertEquals(emptyList(), same.move(at(center(e2).x + 20, center(e2).y)), "$grab: 취소한 뒤에 끌기가 시작됐다")
            assertEquals(listOf<Action>(Action.Tap(e2)), same.release(center(e2), e2), "$grab: 탭이 사라졌다")
            val other = pressed(e2, grab)
            other.cancel()
            assertEquals(emptyList(), other.release(center(e4), e4), "$grab: 다른 칸에서 뗐는데 행동이 나왔다")
        }
        val idle = ChessBoardPointer()
        assertEquals(emptyList(), idle.cancel())
        assertTrue(idle.isIdle)
    }

    @Test
    fun refusedDragIsSpent() {
        val pointer = pressed()
        assertEquals(Action.BeginDrag(e2), pointer.move(center(e4)).first())
        pointer.dragRefused()
        assertNull(pointer.draggingFrom)
        assertEquals(emptyList(), pointer.move(center(e4)))
        assertEquals(emptyList(), pointer.release(center(e4), e4))
        assertTrue(pointer.isIdle)
        pointer.dragRefused()
        assertTrue(pointer.isIdle)
    }

    @Test
    fun aNewPressAfterALostRelease() {
        val g1 = sq("g1")
        val pointer = pressed()
        pointer.move(center(e4))
        assertTrue(pointer.isTracking(center(e2)))
        assertFalse(pointer.isTracking(center(g1)), "다른 점에서 시작한 누름을 같은 누름으로 본다")
        assertEquals(listOf<Action>(Action.Cancel), pointer.press(center(g1), g1, movable, false))
        assertNull(pointer.draggingFrom)
        assertTrue(pointer.isTracking(center(g1)))
        assertFalse(pointer.isTracking(center(e2)), "거둔 누름을 아직 따라가고 있다")
        assertEquals(listOf<Action>(Action.Tap(g1)), pointer.release(center(g1), g1), "새 누름이 옛 말의 놓기로 나갔다")
        assertFalse(pointer.isTracking(center(g1)), "뗀 누름을 아직 따라가고 있다")

        val early = pressed()
        assertEquals(emptyList(), early.press(center(g1), g1, none, false))
        assertEquals(listOf<Action>(Action.Tap(g1)), early.release(center(g1), g1))
        val spent = pressed()
        spent.move(center(e4))
        spent.cancel()
        assertEquals(emptyList(), spent.press(center(g1), g1, movable, false), "이미 거둔 끌기를 또 거뒀다")
        assertEquals(listOf<Action>(Action.Tap(g1)), spent.release(center(g1), g1))
    }

    // ⑤ 폰 전용: 부모 스크롤이 손가락을 가져갔다

    @Test
    fun scrollStealingSpendsThePressWithoutATap() {
        val plain = pressed(e4, none)
        assertEquals(emptyList(), plain.stolenByScroll())
        assertFalse(plain.isIdle)
        assertEquals(emptyList(), plain.release(center(e4), e4), "스크롤하러 떠난 손가락이 뗄 때 탭을 냈다")
        assertTrue(plain.isIdle)
        // 대조: 같은 입력에서 스크롤이 안 가져가면 탭이다.
        assertEquals(listOf<Action>(Action.Tap(e4)), pressed(e4, none).release(center(e4), e4))
        // 끌던 중에 빼앗겼으면 말을 거둔다.
        val dragging = pressed()
        dragging.move(center(e4))
        assertEquals(listOf<Action>(Action.Cancel), dragging.stolenByScroll())
        assertEquals(emptyList(), dragging.release(center(e4), e4))
        // 아무것도 안 눌렀으면 아무 일도 없다.
        val idle = ChessBoardPointer()
        assertEquals(emptyList(), idle.stolenByScroll())
        assertTrue(idle.isIdle)
    }
}
