// 원본: Tests/CheckMobileKitTests/GamesTetrisWiringTests.swift:59-420 · 864-915 · GamesTetrisGestureTests.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class GamesPlayControllerTest {
    private val t0 = SwiftDate(1_789_621_500.0)

    private fun at(seconds: Double) = t0.addingTimeInterval(seconds)

    /** 테트리스 판을 켜고 첫 조각이 나올 때까지 민다. */
    private fun startedTetris(seed: ULong = 7u): GamesPlayController {
        val c = GamesPlayController(MiniGameKind.tetris, seed)
        c.tap()                                     // 시작 전 탭 = 새 판
        c.tick(at(0.0))                             // 첫 프레임은 기준만
        var s = 0.0
        while (c.tetris.active == null && s < 2) {
            s += 1.0 / 60
            c.tick(at(s))
        }
        check(c.tetris.phase == TetrisGame.Phase.Running && c.tetris.active != null) { "판이 안 섰다: ${c.tetris.phase}" }
        return c
    }

    /** 가로 끌기: 문턱(셀 폭)을 넘은 배수만큼 **정확히 그만큼** 옆으로 간다 — 되돌리면 되돌아온다(환불). */
    @Test
    fun aHorizontalDragMovesExactlyThatManyCells() {
        val c = startedTetris()
        c.updateCellWidth(20.0)
        val column = c.tetris.active!!.column
        val start = MiniGamePoint(100.0, 100.0)
        c.canvasDragChanged(start, MiniGameSize(-41.0, 0.0), at(1.0))
        assertEquals(column - 2, c.tetris.active!!.column, "41pt / 20pt = 두 칸")
        c.canvasDragChanged(start, MiniGameSize(-1.0, 0.0), at(1.1))
        assertEquals(column - 1, c.tetris.active!!.column, "되돌린 거리(39pt)만큼 — 한 칸(20pt) 단위로만 되돌아온다")
        c.canvasDragChanged(start, MiniGameSize(0.0, 0.0), at(1.15))
        assertEquals(column, c.tetris.active!!.column, "제자리로 되돌리면 조각도 제자리다(환불)")
        assertFalse(c.canvasDragEnded(MiniGameSize(0.0, 0.0), at(1.2)), "걸음을 낸 끌기는 탭이 아니다")
    }

    /** 세로 끌기는 칸마다 한 칸 · 칸당 1점이고 **래칫**이다(아래위로 문질러 점수를 위조할 수 없다). */
    @Test
    fun aVerticalDragIsARatchetWorthOnePointPerCell() {
        val c = startedTetris()
        c.updateCellWidth(20.0)
        val score = c.tetris.score
        val row = c.tetris.active!!.row
        val start = MiniGamePoint(50.0, 50.0)
        c.canvasDragChanged(start, MiniGameSize(0.0, 60.0), at(1.0))
        assertEquals(score + 3, c.tetris.score)
        assertNotEquals(row, c.tetris.active!!.row)
        c.canvasDragChanged(start, MiniGameSize(0.0, 10.0), at(1.1))
        c.canvasDragChanged(start, MiniGameSize(0.0, 60.0), at(1.2))
        assertEquals(score + 3, c.tetris.score, "문지르기는 새 걸음을 내지 않는다")
    }

    /** 캔버스 탭 = **시계 회전**(하드드롭이 아니다) — 8pt 미만 · 0.25초 안. 천천히 뗀 탭과 8pt 넘게 움직인 탭은 아무 일도 안 한다. */
    @Test
    fun aTapRotatesClockwiseAndNeverHardDrops() {
        val c = startedTetris()
        val rotation = c.tetris.active!!.rotation
        val start = MiniGamePoint(10.0, 10.0)
        c.canvasDragChanged(start, MiniGameSize(2.0, 1.0), at(1.0))
        assertTrue(c.canvasDragEnded(MiniGameSize(2.0, 1.0), at(1.1)))
        assertEquals(rotation.clockwise, c.tetris.active!!.rotation)
        assertEquals(0, c.hardDropSerial, "탭은 하드드롭이 아니다")
        c.canvasDragChanged(start.copy(x = 11.0), MiniGameSize(1.0, 0.0), at(2.0))
        assertFalse(c.canvasDragEnded(MiniGameSize(1.0, 0.0), at(2.4)), "0.25초를 넘겨 뗀 것은 탭이 아니다")
        c.canvasDragChanged(start.copy(x = 12.0), MiniGameSize(9.0, 0.0), at(3.0))
        assertFalse(c.canvasDragEnded(MiniGameSize(9.0, 0.0), at(3.05)), "8pt 넘게 움직였으면 탭이 아니다(죽은 구간)")
    }

    /** 취소된 끌기(끝이 안 옴)의 잠금·소비량이 다음 접촉으로 새지 않는다 — 시작점이 바뀌면 새 접촉이다(없는 입력을 만들지 않는다). */
    @Test
    fun aCancelledDragDoesNotLeakIntoTheNextTouch() {
        val c = startedTetris()
        c.updateCellWidth(20.0)
        c.canvasDragChanged(MiniGamePoint(0.0, 0.0), MiniGameSize(-60.0, 0.0), at(1.0))
        val column = c.tetris.active!!.column
        c.canvasDragChanged(MiniGamePoint(200.0, 0.0), MiniGameSize(0.0, 0.0), at(1.5))
        assertEquals(column, c.tetris.active!!.column, "새 접촉의 0 이동은 걸음이 아니다")
    }

    /** 가로 한 걸음은 **양쪽 대칭**이고, 쌍이 끝나면 자동 반복이 안 남는다 — 0.5초가 흘러도 조각이 더 가지 않는다. */
    @Test
    fun oneCellStepsAreSymmetricAndLeaveNoRepeat() {
        val c = startedTetris()
        val column = c.tetris.active!!.column
        c.moveRightOneCell()
        assertEquals(column + 1, c.tetris.active!!.column)
        c.moveLeftOneCell()
        c.moveLeftOneCell()
        assertEquals(column - 1, c.tetris.active!!.column)
        var s = 1.0
        repeat(30) { s += 1.0 / 60; c.tick(at(s)) }
        assertEquals(column - 1, c.tetris.active!!.column, "눌린 채 남지 않는다")
    }

    /** endRound: 테트리스는 그 점수로 **확정해 알린다**(판마다 한 번) — 기존 두 게임은 **버린다**(알리지 않는다). abandon 은 셋 다 버린다. */
    @Test
    fun endRoundConfirmsTetrisButAbandonsTheOthers() {
        val c = startedTetris()
        val scores = mutableListOf<Int>()
        c.onFinished = { scores += it }
        c.softDropOneCell()
        val outcome = c.endRound()
        assertIs<GamesPlayController.EndOutcome.Confirmed>(outcome)
        assertEquals(listOf(c.tetris.score), scores)
        assertEquals(GamesPlayController.EndOutcome.None, c.endRound(), "두 번째 끝내기는 없다")
        c.tick(at(10.0))
        assertEquals(1, scores.size, "확정 뒤 틱이 또 알리지 않는다")

        for (kind in listOf(MiniGameKind.timingBar, MiniGameKind.flappy)) {
            val other = GamesPlayController(kind, 3u)
            val got = mutableListOf<Int>()
            other.onFinished = { got += it }
            other.tap()
            assertTrue(other.isPlaying, kind.rawValue)
            assertEquals(GamesPlayController.EndOutcome.Abandoned, other.endRound(), kind.rawValue)
            assertEquals(emptyList(), got, "${kind.rawValue} 는 알리지 않는다(제출 없음)")
        }
        val abandoned = startedTetris()
        val none = mutableListOf<Int>()
        abandoned.onFinished = { none += it }
        assertTrue(abandoned.abandon())
        assertEquals(emptyList(), none, "로그아웃·경합 정리는 테트리스도 버린다")
        assertFalse(abandoned.isPlaying)
    }

    /** 판 벽시계 상한(테트리스 15분) — 기준점은 **첫 틱**이 자기 축에서 잡는다(주입 시계와 섞이지 않는다). 기존 두 게임에는 상한이 없다. */
    @Test
    fun theRoundLimitIsALengthMeasuredOnTheTickAxis() {
        val c = startedTetris()
        val scores = mutableListOf<Int>()
        c.onFinished = { scores += it }
        c.roundLimitSeconds = 15.0 * 60
        val base = at(5_000.0)                      // 아무 축이든 — 기준점은 첫 틱이 잡는다
        c.tick(base)
        assertTrue(c.isPlaying, "첫 틱에 죽지 않는다(길이라서)")
        c.tick(base.addingTimeInterval(15.0 * 60 - 0.1))
        assertTrue(c.isPlaying || scores.isNotEmpty())
        if (c.isPlaying) {
            c.tick(base.addingTimeInterval(15.0 * 60))
            assertFalse(c.isPlaying, "15분에 끝난다")
        }
        assertEquals(1, scores.size, "그 점수로 확정된다")
        val flappy = GamesPlayController(MiniGameKind.flappy, 5u)
        flappy.roundLimitSeconds = 1.0
        flappy.tap()
        flappy.tick(at(0.0))
        flappy.tick(at(0.5))
        assertTrue(flappy.isPlaying, "플래피에는 상한이 걸리지 않는다(테트리스만)")
    }

    /** 버튼: 반시계는 캔버스 탭과 **반대 방향** · 하드드롭은 굳히고 햅틱 serial 을 올린다 · 소진된 홀드는 조용하다. */
    @Test
    fun buttonsRotateCounterClockwiseHardDropAndHoldOnce() {
        val c = startedTetris()
        val rotation = c.tetris.active!!.rotation
        c.rotate(clockwise = false)
        assertEquals(rotation.counterClockwise, c.tetris.active!!.rotation)
        c.hold()
        val afterFirst = c.tapSerial
        c.hold()
        assertEquals(afterFirst, c.tapSerial, "소진된 홀드는 조용하다")
        c.hardDrop()
        assertEquals(1, c.hardDropSerial)
    }

    /** 길건너는 폰에 아직 없다(phoneCases) — 구동기는 '판 없음'으로 답하고 탭·틱·출구가 아무 일도 안 한다. */
    @Test
    fun crossyIsInertOnThePhone() {
        val c = GamesPlayController(MiniGameKind.crossy, 1u)
        c.tap()
        c.tick(at(1.0))
        assertFalse(c.isPlaying)
        assertEquals(0, c.score)
        assertEquals(GamesPlayController.EndOutcome.None, c.endRound())
    }

    /** 제스처 판정 표: 위로 끄는 것은 축을 잠그지 않고 · 비스듬한 가로 끌기는 소프트드롭을 같이 만들지 않는다(먼저 넘은 축이 이긴다). */
    @Test
    fun theGestureTrackerLocksTheFirstAxis() {
        val t = TetrisGestureTracker(TetrisGestureThresholds(15.0))
        val p = MiniGamePoint(0.0, 0.0)
        assertEquals(emptyList(), t.drag(p, MiniGameSize(0.0, -40.0)), "위로는 아무 동작도 없다")
        assertEquals(listOf(TetrisGestureStep.moveRight), t.drag(p, MiniGameSize(16.0, -40.0)), "위로 끈 뒤 옆으로 가면 가로가 잠긴다")
        assertEquals(TetrisGestureTracker.Axis.horizontal, t.axis)
        assertEquals(listOf(TetrisGestureStep.moveRight), t.drag(p, MiniGameSize(31.0, 40.0)), "가로가 잠긴 동안 세로는 안 먹는다")
        assertFalse(t.end(MiniGameSize(31.0, 40.0), 0.1))
        assertEquals(1.0, TetrisGestureThresholds(0.0).cellWidth, "셀 폭은 1 밑으로 안 내려간다")
        assertEquals(8.0, TetrisGestureThresholds(13.0).tapMaxDistance)
        assertEquals(0.25, TetrisGestureThresholds(13.0).tapMaxDuration)
    }
}
