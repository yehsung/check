// 원본: Tests/checkTests/V0348ChessDragStoreTests.swift 의 화면 몫 · Sources/check/ChessPanel.swift:637-815(ChessPlayBoard — 얇은 어댑터) @ 1a5eeca6
//
// 판단은 스토어 시험(ChessStoreContractTest)과 해석기 시험(ChessBoardPointerTest)이 잰다. 여기는 **화면이 그 문에 닿는가**를 잰다:
//  ① 끌기 한 바퀴를 진짜 제스처로 — 드는 동안 걸쇠 · 뗀 틱에 꼬리표 · chess_move 한 번 · 놓은 말은 미끄러지지 않는다(대조: 탭으로 둔 수는 미끄러진다).
//  ② 탭은 그대로 — 고르기 · 다시 눌러 해제 · 도착 칸. ③ 못 두는 칸 · 판 밖 · 출발 칸에 놓기. ④ 상대 말은 안 들린다. ⑤ 기본값(Windows)은 끌기가 없다 · 조립 배선.
//  ⑥ 로봇 판. ⑦ 스크롤보다 판 위 끌기가 먼저 — 끌 수 없는 누름은 화면이 스크롤되고 탭도 안 낸다. ⑧ 판이 바뀌면 거둔다. ⑨ 손에 든 말의 그림.
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPiece
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.chess.fromFen
import com.yehsung.aingcheck.core.stores.chess.ChessDragGrab
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameRig
import com.yehsung.aingcheck.ui.games.gomoku.BoardTestTheme
import com.yehsung.aingcheck.ui.games.gomoku.CHESS_FIXTURES
import com.yehsung.aingcheck.ui.games.gomoku.fixtureJSON
import com.yehsung.aingcheck.ui.games.gomoku.fixtureText
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class ChessBoardDragFlowTest {
    private val playerA: String get() = fixtureJSON(CHESS_FIXTURES, "_manifest")["users"]!!.jsonObject["A"]!!.jsonPrimitive.content
    private fun sq(notation: String): ChessSquare = ChessSquare.parse(notation)!!

    private fun DesktopComposeUiTest.settle(rig: BoardGameRig) {
        waitForIdle()
        rig.settle()
        waitForIdle()
    }

    /** 내 차례 첫 판(백) — 스토어 시험과 같은 픽스처. */
    private fun whiteRig() = BoardGameRig(me = playerA) {
        respondWith("chess_lobby") { _, _ -> fixtureText(CHESS_FIXTURES, "chess_lobby__ok_in_match") }
        queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn", "chess_state__ok_mid_since0")
        queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__ok_white_first")
    }

    private fun DesktopComposeUiTest.openMatch(rig: BoardGameRig, state: ChessScreenState = ChessScreenState(), drag: Boolean = true): ChessScreenState {
        rig.games.appDidBecomeActive()
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}, state = state, boardDragEnabled = drag) } }
        settle(rig)
        assertNotNull(rig.chess.match, "판이 안 열렸다")
        return state
    }

    /** 끌기의 앞 절반(누르고 움직이기 — 손가락은 아직 닿아 있다). */
    private fun DesktopComposeUiTest.lift(tag: String, from: ChessSquare, to: ChessSquare) {
        onNodeWithTag(tag).performTouchInput {
            val g = chessGeometry(width.toFloat(), true)
            val a = g.center(from)
            val b = g.center(to)
            down(Offset(a.x.toFloat(), a.y.toFloat()))
            moveTo(Offset(((a.x + b.x) / 2).toFloat(), ((a.y + b.y) / 2).toFloat()))
            moveTo(Offset(b.x.toFloat(), b.y.toFloat()))
        }
        waitForIdle()
    }

    private fun DesktopComposeUiTest.release(tag: String) {
        onNodeWithTag(tag).performTouchInput { up() }
        waitForIdle()
    }

    private fun DesktopComposeUiTest.tap(tag: String, square: ChessSquare) {
        onNodeWithTag(tag).performTouchInput {
            val c = chessGeometry(width.toFloat(), true).center(square)
            click(Offset(c.x.toFloat(), c.y.toFloat()))
        }
        waitForIdle()
    }

    // ① 끌기 한 바퀴

    @Test
    fun aDragPlaysTheMoveAndTheDroppedPieceDoesNotSlide() = runDesktopComposeUiTest(420, 2600) {
        val rig = whiteRig()
        val state = openMatch(rig)
        lift(ChessScreenTags.board, sq("e2"), sq("e4"))
        assertEquals(sq("e2"), rig.chess.dragOrigin, "끄는 중인데 걸쇠가 안 섰다")
        assertEquals(setOf(sq("e3"), sq("e4")), rig.chess.selection?.targets, "끄는 말의 도착 칸이 안 보인다")
        assertEquals(0, rig.server.count("chess_move"), "놓기 전에 수가 나갔다")
        release(ChessScreenTags.board)
        // 시계를 멈춘 채 수 응답을 들인다 — 날았다면 끝나기 전에 잡아야 한다(대조 시험과 같은 자리).
        mainClock.autoAdvance = false
        rig.settle()
        mainClock.advanceTimeByFrame()
        assertEquals(1, rig.server.count("chess_move"))
        assertEquals(sq("e4"), rig.chess.match!!.lastMove?.to, "전제: 답이 판에 닿았다")
        assertNull(state.matchFlight.flight, "끌어 놓은 말이 또 미끄러진다 — 손이 이미 옮겨 놓았다")
        mainClock.autoAdvance = true
        settle(rig)
        val body = rig.server.last("chess_move")
        assertEquals("e2e4", body.str("p_uci"))
        assertEquals(0L, body.long("p_expected_ply"))
        assertNull(rig.chess.selection)
        assertNull(rig.chess.dragOrigin)
        assertNull(rig.chess.pendingDrop, "답이 왔는데 놓은 말 꼬리표가 남았다(유령 말)")
        rig.close()
    }

    /** 대조: 같은 수를 탭으로 두면 미끄러진다 — 위 null 이 빈 단언이 아니다. */
    @Test
    fun aTappedMoveStillSlidesInDragMode() = runDesktopComposeUiTest(420, 2600) {
        val rig = whiteRig()
        val state = openMatch(rig)
        tap(ChessScreenTags.board, sq("e2"))
        settle(rig)
        tap(ChessScreenTags.board, sq("e4"))
        mainClock.autoAdvance = false
        rig.settle()
        mainClock.advanceTimeByFrame()
        assertEquals(1, rig.server.count("chess_move"))
        assertNotNull(state.matchFlight.flight, "탭으로 둔 수가 안 미끄러진다")
        mainClock.autoAdvance = true
        rig.close()
    }

    // ② 탭은 그대로

    @Test
    fun tapsKeepWorkingBesideTheDrag() = runDesktopComposeUiTest(420, 2600) {
        val rig = whiteRig()
        openMatch(rig)
        tap(ChessScreenTags.board, sq("e2"))
        settle(rig)
        assertEquals(sq("e2"), rig.chess.selection?.from, "탭이 말을 안 골랐다")
        assertNull(rig.chess.dragOrigin, "탭이 끌기가 됐다")
        tap(ChessScreenTags.board, sq("e2"))
        settle(rig)
        assertNull(rig.chess.selection, "고른 말을 다시 눌러도 해제가 안 된다")
        tap(ChessScreenTags.board, sq("e2"))
        settle(rig)
        tap(ChessScreenTags.board, sq("e4"))
        settle(rig)
        assertEquals("e2e4", rig.server.last("chess_move").str("p_uci"))
        rig.close()
    }

    // ③ 수가 안 되는 놓기

    @Test
    fun illegalOriginAndOffBoardDropsSendNothing() = runDesktopComposeUiTest(420, 2600) {
        val rig = whiteRig()
        openMatch(rig)
        // 못 가는 칸 — 고르기는 남고 문구가 말한다.
        lift(ChessScreenTags.board, sq("e2"), sq("e6"))
        release(ChessScreenTags.board)
        settle(rig)
        assertEquals(0, rig.server.count("chess_move"), "못 가는 칸에 놓았는데 수가 나갔다")
        assertNull(rig.chess.pendingDrop)
        assertEquals(sq("e2"), rig.chess.selection?.from)
        assertNull(rig.chess.dragOrigin)
        assertNotNull(rig.chess.notice, "못 가는 칸에 놓았는데 아무 말이 없다")
        // 출발 칸에 도로 놓기 — 고르기를 남긴다(해제가 아니다).
        lift(ChessScreenTags.board, sq("e2"), sq("e4"))
        onNodeWithTag(ChessScreenTags.board).performTouchInput {
            val c = chessGeometry(width.toFloat(), true).center(sq("e2"))
            moveTo(Offset(c.x.toFloat(), c.y.toFloat()))
            up()
        }
        settle(rig)
        assertEquals(0, rig.server.count("chess_move"))
        assertEquals(sq("e2"), rig.chess.selection?.from, "도로 놓은 끌기가 고르기를 지웠다")
        // 판 밖에 놓기.
        onNodeWithTag(ChessScreenTags.board).performTouchInput {
            val c = chessGeometry(width.toFloat(), true).center(sq("e2"))
            down(Offset(c.x.toFloat(), c.y.toFloat()))
            moveTo(Offset(c.x.toFloat(), height + 40f))
            up()
        }
        settle(rig)
        assertEquals(0, rig.server.count("chess_move"), "판 밖에 놓았는데 수가 나갔다")
        assertNull(rig.chess.dragOrigin)
        rig.close()
    }

    // ④ 상대 말

    @Test
    fun theOpponentsPieceDoesNotLift() = runDesktopComposeUiTest(420, 2600) {
        val rig = whiteRig()
        openMatch(rig)
        lift(ChessScreenTags.board, sq("e7"), sq("e5"))
        assertNull(rig.chess.dragOrigin, "상대 말이 들렸다")
        release(ChessScreenTags.board)
        settle(rig)
        assertEquals(0, rig.server.count("chess_move"))
        rig.close()
    }

    // ⑤ 기본값 · 조립 배선

    /** 기본값은 탭만이다(Windows 는 인자를 안 넘긴다 — v1 동결). 기준선: 같은 입력이 ①에서는 수를 낸다. */
    @Test
    fun theDefaultScreenHasNoDrag() = runDesktopComposeUiTest(420, 2600) {
        val rig = whiteRig()
        openMatch(rig, drag = false)
        lift(ChessScreenTags.board, sq("e2"), sq("e4"))
        assertNull(rig.chess.dragOrigin, "기본 화면에서 끌기가 시작됐다")
        release(ChessScreenTags.board)
        settle(rig)
        assertEquals(0, rig.server.count("chess_move"), "기본 화면에서 끌기로 수가 나갔다")
        rig.close()
    }

    /** 부르는 자리: 안드로이드 목적지가 켜고 Windows 창은 안 켠다(주석은 걷고 잰다). */
    @Test
    fun onlyTheAndroidDestinationTurnsItOn() {
        val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
        val android = File(mp, "androidApp/src/main/kotlin/com/yehsung/aingcheck/android/screens/games/chess/ChessDestination.kt").readText()
        val windows = File(mp, "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/windows/games/chess/ChessWindow.kt").readText()
        assertTrue("boardDragEnabled = true" in android, "안드로이드 체스 목적지가 끌기를 안 켠다 — 화면에 안 붙은 기능이다")
        assertFalse("boardDragEnabled" in windows, "Windows 창이 끌기를 건드린다")
    }

    // ⑥ 로봇 판

    @Test
    fun theRobotBoardTakesADragToo() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = null)
        val state = ChessScreenState()
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}, state = state, boardDragEnabled = true) } }
        settle(rig)
        onNodeWithTag(ChessScreenTags.robotEntry).performClick()
        waitForIdle()
        onNodeWithTag("chess-robot-white").performClick()
        settle(rig)
        assertTrue(rig.chess.isAIMatch)
        assertEquals(ChessColor.white, rig.chess.match?.myColor)
        lift("chess-robot-board", sq("e2"), sq("e4"))
        assertEquals(sq("e2"), rig.chess.dragOrigin)
        release("chess-robot-board")
        settle(rig)
        assertNull(rig.chess.pendingDrop)
        assertEquals("e4", rig.chess.match!!.moves.first().san, "로봇 판에서 끌어 둔 수가 안 나갔다")
        rig.close()
    }

    // ⑦·⑧ 스크롤 · 거두기(가짜 문 — 재는 것은 어댑터다)

    private class FakeDoor {
        val calls = mutableListOf<String>()
        var premise by mutableStateOf<Any?>(1)
        var origin by mutableStateOf<ChessSquare?>(null)
        fun port() = ChessBoardDragPort(
            grab = { if (it == ChessSquare.parse("e2")) ChessDragGrab.movable else ChessDragGrab.none },
            isSelectionTarget = { false },
            begin = { square -> calls += "begin ${square.notation}"; origin = square; true },
            drop = { from, on -> calls += "drop ${from.notation} ${on?.notation}"; origin = null },
            cancel = { calls += "cancel"; origin = null },
            origin = origin,
            pending = null,
            premise = premise,
        )
    }

    private val start = requireNotNull(ChessPosition.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))

    /** 판 + 그 아래 긴 여백을 부모 스크롤 안에 둔다 — 대국 화면(ChessMatchView)과 같은 구조. */
    private fun DesktopComposeUiTest.scrollingBoard(door: FakeDoor, tapped: MutableList<String>): androidx.compose.foundation.ScrollState {
        lateinit var scroll: androidx.compose.foundation.ScrollState
        setContent {
            BoardTestTheme {
                scroll = rememberScrollState()
                Column(Modifier.height(400.dp).verticalScroll(scroll)) {
                    ChessBoard(
                        position = start, flight = null, whiteAtBottom = true, selection = null, legalTargets = emptySet(), lastMove = null, checkSquare = null,
                        onTapSquare = { tapped += it.notation }, side = 320.dp, onFlightFinished = {}, testTag = "board", drag = door.port(),
                    )
                    Spacer(Modifier.height(1200.dp))
                }
            }
        }
        waitForIdle()
        return scroll
    }

    @Test
    fun aDragOnTheBoardBeatsTheScroll() = runDesktopComposeUiTest(420, 800) {
        val door = FakeDoor()
        val tapped = mutableListOf<String>()
        val scroll = scrollingBoard(door, tapped)
        lift("board", sq("e2"), sq("e6"))
        assertEquals(0, scroll.value, "끌 수 있는 말을 끄는데 화면이 스크롤됐다")
        assertEquals(listOf("begin e2"), door.calls)
        release("board")
        assertEquals(listOf("begin e2", "drop e2 e6"), door.calls)
        assertEquals(emptyList(), tapped, "끌기에서 탭이 나왔다")
    }

    @Test
    fun aPressThatCannotDragLetsTheScreenScrollAndDoesNotTap() = runDesktopComposeUiTest(420, 800) {
        val door = FakeDoor()
        val tapped = mutableListOf<String>()
        val scroll = scrollingBoard(door, tapped)
        // 빈 칸에서 위로 민다 — 화면이 스크롤된다.
        lift("board", sq("e4"), sq("e8"))
        release("board")
        assertNotEquals(0, scroll.value, "판 위에서 시작한 스크롤이 죽었다")
        assertEquals(emptyList(), door.calls, "끌 수 없는 누름이 끌기가 됐다")
        assertEquals(emptyList(), tapped, "스크롤하러 떠난 손가락이 탭을 냈다")
    }

    /** 대조: 같은 칸을 그냥 누르면 탭이다(위 빈 목록이 "탭이 아예 안 된다"가 아니다). */
    @Test
    fun aStillPressOnTheSameSquareIsATap() = runDesktopComposeUiTest(420, 800) {
        val door = FakeDoor()
        val tapped = mutableListOf<String>()
        scrollingBoard(door, tapped)
        tap("board", sq("e4"))
        assertEquals(listOf("e4"), tapped)
        tap("board", sq("e2"))
        assertEquals(listOf("e4", "e2"), tapped, "끌 수 있는 말을 그냥 누른 것도 탭이다")
        assertEquals(emptyList(), door.calls)
    }

    @Test
    fun aChangedBoardRevokesTheDragAndTheLaterReleaseSendsNothing() = runDesktopComposeUiTest(420, 800) {
        val door = FakeDoor()
        scrollingBoard(door, mutableListOf())
        lift("board", sq("e2"), sq("e4"))
        door.premise = 2 // 상대 수가 닿았다 · 왕복 시작 등
        waitForIdle()
        assertEquals(listOf("begin e2", "cancel"), door.calls, "판이 바뀌었는데 끌기를 안 거뒀다")
        release("board")
        assertEquals(listOf("begin e2", "cancel"), door.calls, "거둔 끌기가 뗄 때 수를 냈다")
    }

    /** 스토어가 먼저 걸쇠를 내렸다(화면 가림) — 어댑터도 거둔다. */
    @Test
    fun aDroppedStoreLatchRevokesTheDrag() = runDesktopComposeUiTest(420, 800) {
        val door = FakeDoor()
        scrollingBoard(door, mutableListOf())
        lift("board", sq("e2"), sq("e4"))
        door.origin = null
        waitForIdle()
        assertEquals(listOf("begin e2", "cancel"), door.calls)
        release("board")
        assertEquals(listOf("begin e2", "cancel"), door.calls)
    }

    // ⑨ 그림 — "칸 가운데에 극단 픽셀이 있는가"가 곧 "그 자리에 말이 있는가"다(ChessBoardInk 머리말)

    private fun DesktopComposeUiTest.piecesAt(picture: ChessBoardPicture, vararg squares: String): List<Boolean> {
        setContent { BoardTestTheme { ChessBoardCanvas(picture, side = 320.dp, modifier = Modifier.testTag("canvas")) } }
        waitForIdle()
        val map = onNodeWithTag("canvas").captureToImage().toPixelMap()
        val g = chessGeometry(map.width.toFloat(), picture.whiteAtBottom)
        return squares.map { name ->
            val c = g.center(sq(name))
            val reach = (g.cell * 0.25).toInt()
            var found = false
            for (dx in -reach..reach) for (dy in -reach..reach) {
                val p = map[c.x.toInt() + dx, c.y.toInt() + dy]
                val hi = maxOf(p.red, p.green, p.blue)
                val lo = minOf(p.red, p.green, p.blue)
                if (hi * 255 >= 235 || lo * 255 <= 55) found = true
            }
            found
        }
    }

    private val pawn = ChessPiece(ChessColor.white, ChessPieceKind.pawn)

    @Test
    fun aStillBoardKeepsThePieceOnItsSquare() = runDesktopComposeUiTest(420, 800) {
        val still = ChessBoardPicture(start, whiteAtBottom = true)
        assertEquals(listOf(true, false), piecesAt(still, "e2", "e4"), "기준선: 멈춘 판에는 말이 제자리에 있다")
    }

    @Test
    fun aDroppedPieceStandsOnItsTargetWhileWaiting() = runDesktopComposeUiTest(420, 800) {
        val waiting = ChessBoardPicture(start, whiteAtBottom = true, lifted = ChessBoardLift(pawn, sq("e2"), ChessBoardLift.Place.Square(sq("e4"))))
        assertEquals(listOf(false, true), piecesAt(waiting, "e2", "e4"), "놓은 말이 도착 칸에 안 서거나 출발 칸에 남았다")
    }

    @Test
    fun aHeldPieceFollowsTheFingerAboveIt() = runDesktopComposeUiTest(420, 800) {
        // 손가락은 e4 가운데 — 말은 그 위로 올라가 e5 쪽에 선다(손가락에 안 가린다).
        val g = chessGeometry(320f, true)
        val finger = g.center(sq("e4"))
        val held = ChessBoardPicture(start, whiteAtBottom = true, lifted = ChessBoardLift(pawn, sq("e2"), ChessBoardLift.Place.Finger(finger.x.toFloat(), finger.y.toFloat())), dropTarget = sq("e4"))
        assertEquals(listOf(false, true), piecesAt(held, "e2", "e5"), "끄는 말이 손가락 위에 안 서거나 출발 칸에 남았다")
    }

    @Test
    fun theHeldPieceStaysWhollyOnTheBoard() {
        val cell = 40f
        val side = 320f
        val half = cell * ChessPieceArt.FILL_FRACTION * ChessBoardLift.FINGER_SCALE / 2f
        // 판 안쪽: 손가락 위로 올린 자리 그대로.
        assertEquals(Offset(160f, 160f - cell * ChessBoardLift.FINGER_RAISE_CELLS), ChessBoardLift.fingerCenter(160f, 160f, cell, side))
        // 네 변 · 판 밖: 그려지는 말의 반폭만큼 안쪽으로 묶인다.
        assertEquals(Offset(half, half), ChessBoardLift.fingerCenter(-50f, -50f, cell, side))
        assertEquals(Offset(side - half, side - half), ChessBoardLift.fingerCenter(500f, 900f, cell, side))
        // 숫자가 아닌 좌표는 판을 깨지 않는다.
        assertEquals(Offset(half, half), ChessBoardLift.fingerCenter(Float.NaN, Float.NaN, cell, side))
    }
}
