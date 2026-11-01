// 원본: Tests/CheckMobileKitTests/V1017RummyLandscapeTests.swift:1 · Tests/CheckMobileKitTests/V1017RummyFinishTests.swift:1 @ ios-1017-cube 61d75d8c
//
// 판 화면만 가로(설계서 §10)의 손 궤적과 c9f6976f 의 손 거두기. 끌기는 합성 입력 대신 실제 화면과 같은 재료로 밟고 결과 값을 잰다. 빠져나가는 길은 core stores GamesRummyOrientationTest 가 잰다.
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyBoardMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardTile
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRect
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.stores.rummy.RummyEditorKey
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GamesRummyLandscapeTest {
    private val fx = GamesRummyFixture
    private val sizes = listOf(RummyCanvasSize(667.0, 354.0), RummyCanvasSize(734.0, 372.0), RummyCanvasSize(852.0, 393.0), RummyCanvasSize(932.0, 430.0), RummyCanvasSize(667.0, 375.0), RummyCanvasSize(640.0, 312.0))

    private fun context(editor: RummyTurnEditor, size: RummyCanvasSize, viewport: GamesRummyViewport? = null): GamesRummyTouchContext =
        fx.context(editor, viewport = viewport, size = size)

    private fun trace(start: RummyCanvasPoint, pointer: RummyCanvasPoint, context: GamesRummyTouchContext, hold: Boolean = false): GamesRummyDropAction =
        fx.trace(start, context.layout.finger(pointer), context, hold)

    private fun tableSize(context: GamesRummyTouchContext) = RummyCanvasSize(context.layout.table.width, context.layout.table.height)

    // MARK: 크기 변경

    /** 기기가 돌면 쥔 것을 거두고 손 뗄 때까지 무시한다. 처음 재는 것 · 같은 크기는 변화가 아니다. 없으면: 손 자리가 새 칸에서 다른 타일을 가리킨다. */
    @Test
    fun screenSizeChangeAbandonsTheHold() {
        val size = RummyCanvasSize(734.0, 372.0)
        val context = fx.context(size = size)
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.rackPoint("C2", context)
        val moved = RummyCanvasPoint(start.x, start.y - 100)

        model.touchDown(start, context)
        model.touchMoved(moved, context)
        model.screenSizeChanged(size)
        assertNotNull(model.drag, "처음 재는 크기에 끌기가 거둬졌다")
        model.screenSizeChanged(size)
        assertNotNull(model.drag, "같은 크기인데 거둬졌다")

        // 끌기 → 돌았다.
        model.screenSizeChanged(RummyCanvasSize(372.0, 734.0))
        assertNull(model.drag)
        assertTrue(model.draggingIDs.isEmpty())
        assertNull(model.frozenRows)
        assertFalse(model.machine.isIdle, "쉬는 상태면 다음 사건이 처음 누른 자리를 다시 집는다")
        model.touchMoved(RummyCanvasPoint(moved.x + 30, moved.y), context)
        assertNull(model.drag, "손을 안 뗐는데 다시 집혔다")
        assertEquals(GamesRummyDropAction.None, model.touchUp(moved, context), "거둔 끌기가 놓였다")
        assertTrue(model.machine.isIdle)
        model.touchDown(start, context)
        assertFalse(model.machine.isIdle)
        model.touchMoved(moved, context)
        assertNotNull(model.drag, "다음 손이 안 먹는다")
        model.touchVanished()

        // 판 밀기 → 돌았다.
        model.screenSizeChanged(size)
        val felt = fx.screen(300.0, 300.0, context)
        model.touchDown(felt, context)
        model.touchMoved(RummyCanvasPoint(felt.x, felt.y - 20), context)
        val origin = model.viewport.origin
        assertTrue(origin.y > 0)
        model.screenSizeChanged(RummyCanvasSize(800.0, 372.0))
        model.touchMoved(RummyCanvasPoint(felt.x, felt.y - 80), context)
        assertEquals(origin, model.viewport.origin, "돈 뒤에도 밀린다")
        model.touchUp(felt, context)

        // 핀치 → 돌았다: 닫혀야 다음 핀치가 낡은 기준에서 안 튄다.
        model.screenSizeChanged(size)
        assertTrue(model.beginPinch())
        model.pinch(1.3, RummyCanvasPoint(0.0, 0.0))
        assertNotEquals(model.viewport.scale, model.renderScale)
        model.screenSizeChanged(RummyCanvasSize(800.0, 372.0))
        assertEquals(model.viewport.scale, model.renderScale, "핀치가 열린 채 남았다")
        model.touchVanished()
    }

    // MARK: 끌기 궤적 — 크기마다

    @Test
    fun trajectoriesAtEverySize() {
        for (size in sizes) {
            val base = fx.editor()
            val c = context(base, size)
            fun id(face: String) = fx.id(face, base)
            assertEquals(GamesRummyDropAction.MoveTiles(listOf(id("A4")), RummyDropTarget.Meld(0, 3)), trace(fx.rackPoint("A4", c), fx.screen(100.0 + 120 - 6, 78.0, c), c), "$size 받침대 → 묶음")
            assertEquals(GamesRummyDropAction.MoveTiles(listOf(id("D9")), RummyDropTarget.NewMeldAt(RummyPoint(280, 272))), trace(fx.rackPoint("D9", c), fx.screen(300.0, 300.0, c), c), "$size 받침대 → 펠트")
            assertEquals(GamesRummyDropAction.MoveTiles(listOf(id("A3")), RummyDropTarget.Meld(1, 0)), trace(fx.screen(100.0 + 80 + 20, 78.0, c), fx.screen(810.0, 78.0, c), c), "$size 판 → 판")

            val rackMid = RummyCanvasPoint(c.layout.rack.midX, c.layout.rack.midY)
            assertEquals(GamesRummyDropAction.Refused, trace(fx.screen(100.0 + 40 + 20, 78.0, c), rackMid, c), "$size 판 → 받침대")

            val played = fx.editor()
            assertTrue(played.moveBlock(listOf(fx.id("A4", played)), RummyDropTarget.Meld(0, 3)))
            val p = context(played, size)
            val back = assertIs<GamesRummyDropAction.MoveTiles>(trace(fx.screen(100.0 + 120 + 20, 78.0, p), rackMid, p), "$size: 내가 낸 타일이 받침대로 안 돌아간다")
            assertIs<RummyDropTarget.RackSlot>(back.target)

            val edge = fx.screen(100.0, 78.0, c)
            val handle = RummyCanvasPoint(edge.x - 10, edge.y)
            assertEquals(GamesRummyHit.MeldHandle(0), c.hit(handle), "$size 손잡이")
            assertIs<GamesRummyDropAction.MoveSet>(trace(handle, fx.screen(300.0, 300.0, c), c), "$size: 손잡이가 묶음을 안 옮긴다")

            val chain = listOf("C1", "C2", "C3").map(::id)
            assertEquals(GamesRummyDropAction.MoveTiles(chain, RummyDropTarget.NewMeldAt(RummyPoint(240, 272))), trace(fx.rackPoint("C2", c), fx.screen(300.0, 300.0, c), c, hold = true), "$size 덩어리째")
        }
    }

    @Test
    fun scrolledTableAndRackRowsAtEverySize() {
        for (size in sizes) {
            val base = fx.editor(farMeldX = 650, farMeldY = 560)
            val start = GamesRummyViewport.of(RummyCanvasSize(GamesRummyMatchLayout(size).table.width, GamesRummyMatchLayout(size).table.height))
            val d9 = fx.id("D9", base)
            val plain = context(base, size, start)
            assertTrue(fx.screen(660.0, 588.0, plain).y > plain.layout.table.maxY, "$size 기준선: 아래 묶음이 처음엔 칸 밖")
            val scrolled = context(base, size, start.panned(0.0, -100_000.0))
            assertTrue(fx.screen(660.0, 588.0, scrolled).y < scrolled.layout.table.maxY, "$size: 밀어도 안 보인다")
            assertEquals(GamesRummyDropAction.MoveTiles(listOf(d9), RummyDropTarget.Meld(1, 0)), trace(fx.rackPoint("D9", scrolled), fx.screen(660.0, 588.0, scrolled), scrolled), "$size 밀린 판에 놓기")
            assertNotEquals(GamesRummyHit.Felt, scrolled.hit(fx.screen(660.0, 588.0, scrolled)), "$size 밀린 판 타일이 안 눌린다")

            // 받침대 칸 왕복 — 위 · 아랫줄 어디로든, 손은 화면 안에 있다.
            for ((row, half) in listOf(0 to 20, 1 to 0, 1 to 30)) {
                val c = context(base, size)
                val frame = c.rack.frame(RummyRackSlot(row, half))
                val pointer = RummyCanvasPoint(c.layout.rack.x + frame.midX, c.layout.rack.y + frame.midY)
                assertTrue(c.layout.finger(pointer).y <= size.height, "$size ${row}줄: 손이 화면 밖")
                assertEquals(GamesRummyDropAction.MoveTiles(listOf(d9), RummyDropTarget.RackSlot(RummyRackSlot(row, half))), trace(fx.rackPoint("D9", c), pointer, c), "$size $row/$half")
            }
        }
    }

    // MARK: 판이 바뀌었을 때의 손(c9f6976f)

    private val matchID = SwiftUUID.parse("d0000000-0000-4000-8000-0000000000aa")!!
    private val thisTurn = RummyEditorKey(matchID, 0, 1_000.0, null)
    private val nextTurn = RummyEditorKey(matchID, 1, 2_000.0, null)

    private fun held(editor: RummyTurnEditor? = fx.editor()): GamesRummyTouchContext = fx.context(editor).copy(turnKey = thisTurn)

    private fun dragging(context: GamesRummyTouchContext): Pair<GamesRummyMatchModel, RummyCanvasPoint> {
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.rackPoint("C2", context)
        model.touchDown(start, context)
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 100), context)
        return model to start
    }

    @Test
    fun turnChangeAbandonsUntilLift() {
        val context = held()
        val (model, start) = dragging(context)
        assertNotNull(model.drag)
        model.boardChanged(fx.editor(), nextTurn)
        assertNull(model.drag)
        assertTrue(model.draggingIDs.isEmpty())
        assertNull(model.frozenRows)
        assertEquals(GamesRummyTouchMachine.Phase.Ignoring, model.machine.phase)
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 140), context)
        assertNull(model.drag, "손을 안 뗐는데 새 판에서 타일이 다시 집혔다")
        assertEquals(GamesRummyDropAction.None, model.touchUp(start, context), "거둔 손이 타일을 놓았다")
        assertTrue(model.machine.isIdle)
        model.touchDown(start, context)
        assertTrue(model.machine.holdsBoard, "다음 손이 안 먹는다")
        model.touchVanished()
    }

    @Test
    fun panSurvivesBoardChange() {
        val context = held()
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.screen(300.0, 300.0, context.with(model.viewport))
        model.touchDown(start, context)
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 30), context)
        assertIs<GamesRummyTouchMachine.Phase.Panning>(model.machine.phase)
        val before = model.viewport.origin.y
        assertTrue(before > 0, "기준선: 밀기가 움직이지 않으면 이 시험은 아무것도 안 잰다")
        model.boardChanged(fx.editor(), nextTurn)
        assertIs<GamesRummyTouchMachine.Phase.Panning>(model.machine.phase, "판이 바뀌자 밀기가 거둬졌다")
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 50), context)
        assertEquals(before + 20 / model.viewport.scale, model.viewport.origin.y, 0.001, "끈 거리 전체로 튀었다")
        model.touchUp(start, context)
    }

    @Test
    fun sameTurnKeepsHoldUnlessTilesVanish() {
        val context = held()
        val (kept, _) = dragging(context)
        kept.boardChanged(fx.editor(), thisTurn)
        assertNotNull(kept.drag, "같은 판인데 끌기가 거둬졌다")
        kept.touchVanished()

        val (lost, _) = dragging(context)
        // 받침대가 준 편집기 — 쥔 C2 의 id 가 없다.
        val smaller = RummyTurnEditor(listOf(fx.faces("A1", "A2", "A3")), fx.faces("A4"), initialDone = true, tableLayout = RummyLayout(listOf(RummyPoint(100, 50))))
        val heldID = fx.id("C2", fx.editor())
        assertFalse(smaller.rack.any { it.id == heldID } || smaller.melds.flatten().any { it.id == heldID }, "기준선: 쥔 id 가 새 편집기에 남아 있다")
        lost.boardChanged(smaller, thisTurn)
        assertNull(lost.drag)
        assertEquals(GamesRummyTouchMachine.Phase.Ignoring, lost.machine.phase)
        lost.touchVanished()

        val (gone, _) = dragging(context)
        gone.boardChanged(null, thisTurn)
        assertEquals(GamesRummyTouchMachine.Phase.Ignoring, gone.machine.phase)
        gone.touchVanished()
    }

    @Test
    fun holdSurvivalComparesTheMeldNotTheNumber() {
        val editor = fx.editor()
        val context = held(editor)
        // 묶음 순서가 바뀐 편집기 — 번호는 있어도 내용이 다르다.
        val swapped = RummyTurnEditor(
            listOf(fx.faces("B4", "B5", "B6", "B7"), fx.faces("A1", "A2", "A3")),
            fx.faces("A4", "C1", "C2", "C3", "D9"),
            initialDone = true,
            tableLayout = RummyLayout(listOf(RummyPoint(800, 50), RummyPoint(100, 50))),
        )
        val pressed = GamesRummyTouchMachine()
        pressed.down(fx.rackPoint("C2", context), context)
        assertNotNull(pressed.holdElapsed(context))
        assertTrue(pressed.holdSurvives(editor, editor))
        assertFalse(pressed.holdSurvives(null, editor))

        val edge = fx.screen(100.0, 80.0, context)
        val handle = GamesRummyTouchMachine()
        handle.down(RummyCanvasPoint(edge.x - 10, edge.y), context)
        assertIs<GamesRummyTouchMachine.Phase.Handle>(handle.phase)
        assertTrue(handle.holdSurvives(editor, editor))
        assertFalse(handle.holdSurvives(swapped, editor), "번호만 같은 다른 묶음을 옮기게 된다")
        handle.move(fx.finger(fx.screen(300.0, 300.0, context)), context)
        assertNotNull(handle.drag)
        assertTrue(handle.holdSurvives(editor, editor))
        assertFalse(handle.holdSurvives(swapped, editor), "번호만 같은 다른 묶음을 옮기게 된다")
    }

    /** 차례 안에서는 받침대 줄 수가 줄지 않는다 — 타일이 통째로 커지면 다음 타일을 잡을 자리가 어긋난다. 쥔 동안은 묶인다. 차례가 바뀌면 맞춘다. */
    @Test
    fun rackRowsHoldWithinATurn() {
        val model = GamesRummyMatchModel()
        assertEquals(3, model.rackRows(3, "A"))
        assertEquals(3, model.rackRows(2, "A"), "차례 안에서 줄이 줄었다")
        assertEquals(4, model.rackRows(4, "A"))
        assertEquals(2, model.rackRows(2, "B"), "차례가 바뀌었는데 안 맞췄다")
        val context = fx.context()
        val press = GamesRummyMatchModel(tableSize(context))
        press.touchDown(fx.rackPoint("C2", context), context)
        assertEquals(2, press.frozenRows)
        assertEquals(2, press.rackRows(5, "A"), "쥔 동안 줄 수가 바뀌었다")
        press.touchVanished()
        assertEquals(5, press.rackRows(5, "A"))
    }

    // MARK: 핀치 · 동작 버튼

    @Test
    fun cancelledPinchIsCleanedUp() {
        val model = GamesRummyMatchModel()
        val base = model.viewport.scale
        assertTrue(model.beginPinch())
        model.pinch(1.2, RummyCanvasPoint(0.0, 0.0))
        val zoomed = model.viewport.scale
        assertTrue(zoomed > base)
        assertEquals(base, model.renderScale, "기준선: 핀치 중엔 그린 배율이 그대로다")
        val origin = model.viewport.origin
        model.readOnlyPan(-40.0, -40.0)
        assertEquals(origin, model.viewport.origin, "핀치 중에 밀렸다")

        model.touchVanished()
        assertEquals(zoomed, model.renderScale, "취소된 핀치가 흐린 채 남았다")
        assertTrue(model.beginPinch())
        model.pinch(1.0, RummyCanvasPoint(0.0, 0.0))
        assertEquals(zoomed, model.viewport.scale, 0.0, "다음 핀치가 낡은 기준에서 튀었다")
        model.pinchEnded()
        model.readOnlyPan(-40.0, -40.0)
        assertNotEquals(origin, model.viewport.origin, "읽기 전용 밀기가 죽었다")
    }

    @Test
    fun readOnlyPinchOpensWithoutTheMachine() {
        val model = GamesRummyMatchModel()
        val base = model.viewport.scale
        model.readOnlyPinch(1.3, RummyCanvasPoint(100.0, 100.0))
        assertEquals(base * 1.3, model.viewport.scale, 0.0001)
        model.readOnlyPinch(1.5, RummyCanvasPoint(100.0, 100.0))
        assertEquals(base * 1.5, model.viewport.scale, 0.0001, "곱한 값이 시작 기준이 아니다")
        model.pinchEnded()
        assertEquals(model.viewport.scale, model.renderScale)
    }

    @Test
    fun actionsLockWhileHolding() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        assertFalse(model.locksActions)
        val start = fx.rackPoint("C2", context)
        model.touchDown(start, context)
        assertTrue(model.locksActions, "누른 동안 [되돌리기]가 눌린다")
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 100), context)
        assertTrue(model.locksActions, "끄는 동안 [되돌리기]가 눌린다")
        model.touchUp(start, context)
        assertFalse(model.locksActions)
        val felt = fx.screen(300.0, 300.0, context.with(model.viewport))
        model.touchDown(felt, context)
        assertFalse(model.locksActions, "판을 미는데 동작 버튼이 죽었다")
        model.touchUp(felt, context)
    }

    // MARK: 상태 줄

    @Test
    fun statusLineWarnings() {
        val editor = fx.editor()
        val waiting = GamesRummyStatusLine.make(null, false, null, "구름", RummySeatState.playing, 2, engaged = true)
        assertEquals("앱을 90초 넘게 내리면 기권돼요", waiting.text)
        assertEquals("시간 초과 2/3", waiting.warning)
        val idle = GamesRummyStatusLine.make(null, false, null, "구름", RummySeatState.playing, 0, engaged = false)
        assertEquals(RummyPhoneText.turnOf("구름"), idle.text, "놀던 기기에 기권 안내가 떴다")
        assertNull(idle.warning)
        val mine = GamesRummyStatusLine.make(null, true, editor, null, RummySeatState.playing, 1, engaged = true)
        assertEquals(RummyPhoneText.myTurnStatus(editor), mine.text)
        assertEquals("시간 초과 1/3", mine.warning, "내 차례에 경고가 안 보인다")
        val notice = GamesRummyStatusLine.make("서버 말", true, editor, null, RummySeatState.playing, 2, engaged = true)
        assertEquals("서버 말", notice.text)
        assertEquals("시간 초과 2/3", notice.warning, "안내줄에 경고가 밀렸다")
        val out = GamesRummyStatusLine.make(null, false, null, "구름", RummySeatState.forfeit, 3, engaged = true)
        assertEquals(GamesRummyMatchText.spectating, out.text)
        assertNull(out.warning, "기권한 자리에 경고가 남았다")
    }

    private fun state(json: String): RummyMatchState = SwiftJson.decode(RummyMatchState.serializer(), json)

    private val waiting = state(
        """{"id":"d0000000-0000-4000-8000-0000000000aa","status":"active","my_seat_no":0,"turn_seat_no":1,"seats":[{"seat_no":0,"user_id":"d0000000-0000-4000-8000-0000000000b0","display_name":"나","state":"playing"},{"seat_no":1,"user_id":"d0000000-0000-4000-8000-0000000000b1","display_name":"비","state":"playing"}],"last_event":{"kind":"draw","seat_no":1}}""",
    )

    @Test
    fun statusTailSpeaksTheTurnOnce() {
        val quiet = GamesRummyStatusLine("", GamesRummyStatusLine.Tone.quiet)
        assertNull(GamesRummyStatusTail.make(waiting, isMyTurn = true, hasOtherDraft = false, line = quiet).turn)
        val other = GamesRummyStatusTail.make(waiting, isMyTurn = false, hasOtherDraft = false, line = quiet)
        assertEquals(RummyPhoneText.turnOf("비"), other.turn)
        assertFalse(other.isPlacing)
        assertEquals("비님이 1장 뽑았어요", other.lastEvent)
        val placing = GamesRummyStatusTail.make(waiting, isMyTurn = false, hasOtherDraft = true, line = quiet)
        assertEquals(RummyPhoneText.placing("비"), placing.turn)
        assertTrue(placing.isPlacing)
        val same = GamesRummyStatusLine(RummyPhoneText.turnOf("비"), GamesRummyStatusLine.Tone.quiet)
        assertNull(GamesRummyStatusTail.make(waiting, isMyTurn = false, hasOtherDraft = false, line = same).turn, "같은 말을 두 번 한다")
    }

    // MARK: 모션

    private fun tile(text: String, id: Int) = RummyBoardTile(id, RummyFace.of(text)!!, false)

    private fun meld(id: String, x: Long, y: Long, tiles: List<RummyBoardTile>) =
        RummyBoardMeld(id, tiles, RummyRect(x, y, tiles.size.toLong() * RummyTableLayout.tileWidth, RummyTableLayout.tileHeight), false)

    @Test
    fun droppedTileSlidesFromTheLandingPoint() {
        val old = listOf(meld("a", 40, 16, listOf(tile("A1", 1), tile("A3", 3))))
        val new = listOf(meld("a", 40, 16, listOf(tile("A1", 1), tile("A2", 9), tile("A3", 3))))
        val home = RummyCanvasPoint(40.0 + RummyTableLayout.tileWidth.toDouble(), 16.0)
        val from = RummyCanvasPoint(300.0, 200.0)
        val motion = assertNotNull(GamesRummyBoardMotion.make(old, new, setOf(9), mapOf(9 to from)))
        val landed = assertNotNull(motion.moves.firstOrNull { it.face.text == "A2" }, "놓은 타일이 순간 이동했다")
        assertEquals(from, landed.from)
        assertEquals(home, landed.to)
        val silent = GamesRummyBoardMotion.make(old, new, setOf(9), mapOf(9 to home))
        assertFalse(silent?.moves?.any { it.face.text == "A2" } == true, "제자리에 놓았는데 날았다")
        assertFalse(GamesRummyBoardMotion.make(old, new, setOf(9))?.moves?.any { it.face.text == "A2" } == true)
    }

    /** 손을 뗀 자리가 모델에 남는다 — 판 화면이 그 값으로 미끄럼을 만든다(그린 자리와 같은 기준점). */
    @Test
    fun touchUpRecordsWhereTheHandLanded() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val model = GamesRummyMatchModel(tableSize(context))
        val d9 = fx.id("D9", editor)
        val pointer = fx.screen(300.0, 300.0, context)
        val finger = fx.finger(pointer)
        model.touchDown(fx.rackPoint("D9", context), context)
        model.touchMoved(finger, context)
        model.touchUp(finger, context)
        assertEquals(setOf(d9), model.recentDropIDs)
        val landed = assertNotNull(model.recentDropOrigins[d9])
        assertEquals(280.0, landed.x, 1.0)
        assertEquals(272.0, landed.y, 1.0)
        model.touchDown(fx.screen(300.0, 300.0, context), context)
        assertTrue(model.recentDropOrigins.isEmpty(), "다음 손까지 놓은 자리가 남았다")
        model.touchVanished()
    }
}
