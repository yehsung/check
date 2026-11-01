// 원본: Tests/CheckMobileKitTests/GamesRummyMatchInputTests.swift:1 @ ios-1017-cube 614d98bd · 맥 Tests/checkTests/V0369RummyPanelRenderTests.swift · V0370RummyBoardFeelTests.swift 의 뜻
//
// 판 화면의 **끌기 판정**. "손 궤적 → 분류 → 놓을 자리 → 편집기 결과" 를 값으로 잰다. 궤적은 실제 화면과 같은 재료(GamesRummyTouchContext · GamesRummyMatchModel)로 밟고,
// 결과는 진짜 편집기(RummyTurnEditor)에 놓아 본다. 시간은 밖에서 민다(holdElapsed).
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyBoardPreview
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyDropResolver
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
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
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** 판 두 묶음(A1~A3 왼쪽 · B4~B7 오른쪽 화면 밖) + 받침대 A4 · C1 C2 C3 · D9 — 입력 시험 · 화면 시험 공용. */
internal object GamesRummyFixture {
    val screenSize = RummyCanvasSize(393.0, 759.0)

    fun faces(vararg texts: String): List<RummyFace> = texts.map { RummyFace.of(it)!! }

    fun editor(initialDone: Boolean = true, farMeldX: Long = 800): RummyTurnEditor = RummyTurnEditor(
        table = listOf(faces("A1", "A2", "A3"), faces("B4", "B5", "B6", "B7")),
        rack = faces("A4", "C1", "C2", "C3", "D9"),
        initialDone = initialDone,
        tableLayout = RummyLayout(listOf(RummyPoint(100, 50), RummyPoint(farMeldX, 50))),
        rackHalfColumns = RummyRackGeometry.phoneHalfColumns,
    )

    fun context(
        editor: RummyTurnEditor? = editor(),
        isMyTurn: Boolean = true,
        viewport: GamesRummyViewport? = null,
        size: RummyCanvasSize = screenSize,
        rows: Int? = null,
    ): GamesRummyTouchContext {
        val layout = GamesRummyMatchLayout(size, rows ?: editor?.rackLayout?.rowCount ?: 2)
        val mine = isMyTurn && editor != null
        val scene = GamesRummyBoardScene.make(null, editor, mine, null)
        val view = viewport ?: GamesRummyViewport.of(RummyCanvasSize(layout.table.width, layout.table.height))
        return GamesRummyTouchContext(layout, view, scene, editor, mine, mine)
    }

    fun id(face: String, editor: RummyTurnEditor): Int =
        editor.rack.firstOrNull { it.face.text == face }?.id ?: editor.melds.flatten().first { it.face.text == face }.id

    /** 받침대 타일 가운데(판 화면 좌표). */
    fun rackPoint(face: String, context: GamesRummyTouchContext): RummyCanvasPoint {
        val editor = context.editor!!
        val frame = context.rack.frame(editor.rackLayout.slot(id(face, editor))!!)
        return RummyCanvasPoint(frame.midX + context.layout.rack.x, frame.midY + context.layout.rack.y)
    }

    fun screen(x: Double, y: Double, context: GamesRummyTouchContext): RummyCanvasPoint {
        val local = context.viewport.transform.toScreen(RummyCanvasPoint(x, y))
        return RummyCanvasPoint(local.x + context.layout.table.x, local.y + context.layout.table.y)
    }

    /** 손 위 48 점이 [pointer] 에 오는 손 자리. */
    fun finger(pointer: RummyCanvasPoint): RummyCanvasPoint = RummyCanvasPoint(pointer.x, pointer.y + GamesRummyGestureRules.fingerLift)

    /** 궤적 한 번: 누르고 → 목적지로 가서 → 뗀다. */
    fun trace(start: RummyCanvasPoint, end: RummyCanvasPoint, context: GamesRummyTouchContext, hold: Boolean = false): GamesRummyDropAction {
        val machine = GamesRummyTouchMachine()
        machine.down(start, context)
        machine.move(start, context)
        if (hold) machine.holdElapsed(context)
        machine.move(end, context)
        return machine.up(end, context)
    }

    fun apply(action: GamesRummyDropAction, editor: RummyTurnEditor): Boolean = when (action) {
        GamesRummyDropAction.None, GamesRummyDropAction.Refused -> false
        is GamesRummyDropAction.MoveTiles -> editor.moveBlock(action.ids, action.target)
        is GamesRummyDropAction.MoveSet -> editor.moveSet(action.set, action.point)
    }
}

class GamesRummyMatchInputTest {
    private val fx = GamesRummyFixture

    private fun tableSize(context: GamesRummyTouchContext) = RummyCanvasSize(context.layout.table.width, context.layout.table.height)

    // MARK: 받침대 → 판

    @Test
    fun rackToMeldUsesThePointAboveTheFinger() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val a4 = fx.id("A4", editor)
        val pointer = fx.screen(100.0 + 120 - 6, 78.0, context)
        val action = fx.trace(fx.rackPoint("A4", context), fx.finger(pointer), context)
        assertEquals(GamesRummyDropAction.MoveTiles(listOf(a4), RummyDropTarget.Meld(0, 3)), action)
        assertTrue(fx.apply(action, editor))
        assertEquals(listOf("A1", "A2", "A3", "A4"), editor.melds[0].map { it.face.text })
        assertTrue(editor.rack.none { it.id == a4 })
        assertTrue(editor.canSubmit)
        // 기준선: 손 자리(48 아래)로 쟀다면 묶음 위가 아니다 — 들어 올림이 판정에 실제로 들어간다.
        val wrong = fx.trace(fx.rackPoint("D9", context), pointer, context)
        assertNotEquals(GamesRummyDropAction.MoveTiles(listOf(fx.id("D9", editor)), RummyDropTarget.Meld(0, 3)), wrong, "손 위 48 을 안 쓰고 잰다")
    }

    @Test
    fun rackToFeltMakesANewMeld() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val d9 = fx.id("D9", editor)
        val pointer = fx.screen(300.0, 300.0, context)
        val action = fx.trace(fx.rackPoint("D9", context), fx.finger(pointer), context)
        assertEquals(GamesRummyDropAction.MoveTiles(listOf(d9), RummyDropTarget.NewMeldAt(RummyPoint(280, 272))), action)
        assertTrue(fx.apply(action, editor))
        assertEquals(listOf(d9), editor.melds[2].map { it.id })
    }

    @Test
    fun dragThresholdIsEight() {
        val context = fx.context()
        val start = fx.rackPoint("C2", context)
        val machine = GamesRummyTouchMachine()
        machine.down(start, context)
        assertEquals(GamesRummyTouchMachine.Effect.None, machine.move(RummyCanvasPoint(start.x + 8, start.y), context))
        assertNull(machine.drag)
        assertEquals(GamesRummyTouchMachine.Effect.DragBegan, machine.move(RummyCanvasPoint(start.x + 8.5, start.y), context))
        assertEquals(listOf(fx.id("C2", context.editor!!)), machine.drag?.ids, "꾹 안 눌렀는데 묶음째 집혔다")
        val tap = GamesRummyTouchMachine()
        tap.down(start, context)
        assertEquals(GamesRummyDropAction.None, tap.up(start, context))
        assertTrue(tap.isIdle)
    }

    @Test
    fun holdPicksTheRackChain() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val start = fx.rackPoint("C2", context)
        val machine = GamesRummyTouchMachine()
        machine.down(start, context)
        assertTrue(machine.isAwaitingHold)
        val chain = listOf("C1", "C2", "C3").map { fx.id(it, editor) }
        assertEquals(chain, machine.holdElapsed(context)?.ids)
        assertFalse(machine.isAwaitingHold)
        assertNull(machine.holdElapsed(context), "두 번 집는다")
        val pointer = fx.screen(300.0, 300.0, context)
        assertEquals(GamesRummyTouchMachine.Effect.DragBegan, machine.move(fx.finger(pointer), context))
        assertEquals(chain, machine.drag?.ids)
        assertEquals(1, machine.drag?.grabIndex)
        val action = machine.up(fx.finger(pointer), context)
        // 가운데 타일을 잡았으니 묶음 왼쪽은 기준점에서 1.5칸 왼쪽.
        assertEquals(GamesRummyDropAction.MoveTiles(chain, RummyDropTarget.NewMeldAt(RummyPoint(240, 272))), action)
        assertTrue(fx.apply(action, editor))
        assertEquals(listOf("C1", "C2", "C3"), editor.melds.last().map { it.face.text })

        // 위에서 C1~C3 을 판에 냈다 — 받침대가 그대로인 새 판에서 잰다(옛 자리엔 이제 타일이 없어 손이 무시되고, 그러면 아래 단언은 늘 참이다).
        val freshContext = fx.context(fx.editor())
        val freshStart = fx.rackPoint("C2", freshContext)
        val moved = GamesRummyTouchMachine()
        moved.down(freshStart, freshContext)
        moved.move(RummyCanvasPoint(freshStart.x + 20, freshStart.y), freshContext)
        assertNull(moved.holdElapsed(freshContext), "이미 한 장을 끌기 시작했는데 묶음이 된다")
        assertEquals(1, moved.drag?.ids?.size)
    }

    // MARK: 판 → 판 · 판 → 받침대

    @Test
    fun boardToBoardOnAScrolledTable() {
        val editor = fx.editor(farMeldX = 650)
        val base = fx.context(editor)
        val context = fx.context(editor, viewport = base.viewport.panned(-130.0, 0.0))
        // 밀어 두지 않았다면 오른쪽 묶음(x 650)은 화면 밖이다.
        assertTrue(fx.screen(660.0, 78.0, base).x > 393)
        val a3 = fx.id("A3", editor)
        val start = fx.screen(100.0 + 80 + 20, 78.0, context)
        assertEquals(GamesRummyHit.BoardTile(a3), context.hit(start))
        val pointer = fx.screen(660.0, 78.0, context)
        assertTrue(pointer.x > 0 && pointer.x < 393, "기준선: 목적지가 화면 안이어야 시험이 뜻이 있다")
        val action = fx.trace(start, fx.finger(pointer), context)
        assertEquals(GamesRummyDropAction.MoveTiles(listOf(a3), RummyDropTarget.Meld(1, 0)), action)
        assertTrue(fx.apply(action, editor))
        assertEquals(2, editor.melds[0].size)
        assertTrue(editor.melds[1].any { it.id == a3 })
    }

    @Test
    fun autoPanReachesTheFarMeld() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val model = GamesRummyMatchModel(tableSize(context))
        val a3 = fx.id("A3", editor)
        val start = fx.screen(100.0 + 80 + 20, 78.0, context)
        val y = fx.screen(0.0, 78.0, context).y
        model.touchDown(start, context)
        model.touchMoved(fx.finger(RummyCanvasPoint(385.0, y)), context)
        assertEquals(1, model.edgeDirection, "가장자리인데 프레임이 안 돈다")
        repeat(200) { model.edgeTick(0.016) }
        assertEquals(1000.0, model.viewport.visibleLogical.maxX, 0.01, "자동 밀기가 끝까지 안 갔다")
        assertEquals(0, model.edgeDirection, "끝에 닿았는데 프레임이 돈다")
        val view = context.with(model.viewport)
        val over = fx.finger(fx.screen(800.0 + 160 - 6, 78.0, view))
        model.touchMoved(over, context)
        val action = model.touchUp(over, context)
        assertEquals(GamesRummyDropAction.MoveTiles(listOf(a3), RummyDropTarget.Meld(1, 4)), action)
        assertTrue(fx.apply(action, editor))
        assertTrue(editor.melds[1].any { it.id == a3 })
    }

    @Test
    fun boardToRackIsRefusedButMyPlayedTileReturns() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val a2 = fx.id("A2", editor)
        val start = fx.screen(100.0 + 40 + 20, 78.0, context)
        val over = RummyCanvasPoint(context.layout.rack.midX, context.layout.rack.midY)
        assertEquals(GamesRummyDropAction.Refused, fx.trace(start, fx.finger(over), context))

        val model = GamesRummyMatchModel(tableSize(context))
        model.touchDown(start, context)
        model.touchMoved(fx.finger(over), context)
        assertTrue(model.hoverRefused)
        assertNull(model.rackPreview, "거절인데 받침대가 비켜 선다")
        assertEquals(setOf(a2), model.draggingIDs)
        val action = model.touchUp(fx.finger(over), context)
        assertEquals(GamesRummyDropAction.Refused, action)
        assertTrue(model.refusedFlash)
        assertEquals(1, model.refuseSerial)
        assertFalse(model.hoverRefused)
        assertTrue(model.draggingIDs.isEmpty())
        assertNull(model.drag, "제자리로 안 돌아간다")
        val before = editor.copy()
        assertFalse(fx.apply(action, editor))
        assertEquals(before, editor)
        model.clearRefusedFlash()
        assertFalse(model.refusedFlash)

        // 이번 차례에 받침대에서 낸 타일은 받침대로 돌아간다(판 출신이 아니다).
        val a4 = fx.id("A4", editor)
        assertTrue(editor.moveBlock(listOf(a4), RummyDropTarget.Meld(0, 3)))
        val played = fx.context(editor)
        val back = fx.screen(100.0 + 120 + 20, 78.0, played)
        assertEquals(GamesRummyHit.BoardTile(a4), played.hit(back))
        val returned = assertIs<GamesRummyDropAction.MoveTiles>(fx.trace(back, fx.finger(over), played), "내가 낸 타일이 받침대로 안 돌아간다")
        assertEquals(listOf(a4), returned.ids)
        assertIs<RummyDropTarget.RackSlot>(returned.target)
    }

    // MARK: 묶음 이동

    @Test
    fun handleMovesTheWholeMeld() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val scale = context.viewport.scale
        val edge = fx.screen(100.0, 50.0 + 28, context)
        val start = RummyCanvasPoint(edge.x - 10, edge.y)
        assertEquals(GamesRummyHit.MeldHandle(0), context.hit(start))
        val finger = RummyCanvasPoint(edge.x + 100, edge.y + 200)
        val machine = GamesRummyTouchMachine()
        machine.down(start, context)
        assertEquals(GamesRummyTouchMachine.Effect.DragBegan, machine.move(finger, context))
        val drag = assertNotNull(machine.drag)
        assertEquals(GamesRummyDrag.Kind.WholeMeld(0), drag.kind)
        assertEquals(-10 / scale, drag.grab.x, 0.01)
        assertEquals(28.0, drag.grab.y, 0.01)
        val logical = context.viewport.transform.toLogical(context.inTable(GamesRummyGestureRules.liftedPoint(finger)))
        val want = RummyDropResolver.clampedTopLeft(RummyCanvasPoint(logical.x - drag.grab.x, logical.y - drag.grab.y), 3)
        val action = machine.up(finger, context)
        assertEquals(GamesRummyDropAction.MoveSet(0, want), action)
        assertTrue(fx.apply(action, editor))
        assertNotEquals(RummyPoint(100, 50), editor.points[0])
        assertEquals(3, editor.melds[0].size, "옮기기가 묶음을 바꿨다")

        val outside = GamesRummyTouchMachine()
        outside.down(start, context)
        val overRack = RummyCanvasPoint(200.0, context.layout.rack.midY + 48)
        outside.move(overRack, context)
        assertEquals(GamesRummyDropAction.None, outside.up(overRack, context))
    }

    @Test
    fun holdOnBoardPicksChunkAndWholeMeldGoesToMoveSet() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val middle = fx.screen(100.0 + 40 + 20, 78.0, context)
        val pointer = fx.screen(300.0, 300.0, context)
        val action = fx.trace(middle, fx.finger(pointer), context, hold = true)
        assertIs<GamesRummyDropAction.MoveSet>(action, "묶음 통째가 moveSet 으로 안 갔다")
        assertTrue(fx.apply(action, editor))
        assertEquals(3, editor.melds[0].size)

        val split = fx.context(fx.editor())
        val machine = GamesRummyTouchMachine()
        machine.down(fx.screen(100.0 + 80 + 20, 78.0, split), split)
        // A3(오른쪽 끝) = 그 타일부터 끝까지 = 한 장.
        assertEquals(listOf(fx.id("A3", split.editor!!)), machine.holdElapsed(split)?.ids)
    }

    // MARK: 좌표 왕복

    @Test
    fun drawnFramesAreWhereTheHitLands() {
        val editor = fx.editor()
        val base = fx.context(editor).viewport
        val panned = base.panned(-420.0, 0.0)
        val zoomed = base.zoomed(0.95, RummyCanvasPoint(200.0, 100.0)).panned(-40.0, 30.0)
        val full = base.toggledFullView()
        for (view in listOf(base, panned, zoomed, full)) {
            val context = fx.context(editor, viewport = view)
            val table = context.layout.table
            for (set in context.scene.melds.indices) {
                for (slot in context.scene.melds[set].tiles.indices) {
                    val frame = context.scene.layout.tileFrame(set, slot)!!
                    val drawn = view.transform.rect(frame)
                    val point = RummyCanvasPoint(drawn.midX + table.x, drawn.midY + table.y)
                    if (!table.insetBy(1.0, 1.0).contains(point)) continue
                    assertEquals(GamesRummyHit.BoardTile(context.scene.melds[set].tiles[slot].id!!), context.hit(point), "${view.scale} $set/$slot")
                    val logical = view.transform.toLogical(context.inTable(point))
                    assertEquals((frame.x + 20).toDouble(), logical.x, 0.01)
                    assertEquals((frame.y + 28).toDouble(), logical.y, 0.01)
                }
            }
        }
        // 기준선: 밀린 보기는 처음 보기와 다른 자리에 그린다.
        assertNotEquals(base.transform.toScreen(RummyCanvasPoint(800.0, 50.0)), panned.transform.toScreen(RummyCanvasPoint(800.0, 50.0)))
    }

    @Test
    fun floatingFramesAreTheDropPoint() {
        val context = fx.context()
        val start = fx.rackPoint("C2", context)
        val machine = GamesRummyTouchMachine()
        machine.down(start, context)
        machine.holdElapsed(context)
        val finger = fx.finger(fx.screen(301.0, 305.0, context))
        machine.move(finger, context)
        val drag = assertNotNull(machine.drag)
        val plain = GamesRummyFloatingLayout.frames(drag, context.viewport.tileSize, context.viewport.scale, liftScale = 1.0)
        val logical = context.viewport.transform.toLogical(context.inTable(RummyCanvasPoint(plain[0].x, plain[0].y)))
        val target = assertIs<RummyDropTarget.NewMeldAt>(GamesRummyDropPlanner.target(drag, context), "빈 펠트가 아니다")
        assertEquals(target.point.x.toDouble(), logical.x, 1.0)
        assertEquals(target.point.y.toDouble(), logical.y, 1.0)
        assertEquals(3, plain.size)
        assertEquals(plain[0].maxX, plain[1].x, 0.001)
        // 1.25 배: 잡은 타일 가운데가 기준점에 그대로 있고 들어 올림이 손 위 48 이다.
        val lifted = GamesRummyFloatingLayout.frames(drag, context.viewport.tileSize, context.viewport.scale)
        assertEquals(finger.x, lifted[1].midX, 0.001)
        assertEquals(finger.y - 48, lifted[1].midY, 0.001)
        assertEquals(context.viewport.tileSize.width * 1.25, lifted[1].width, 0.001)

        // 손잡이.
        val edge = fx.screen(100.0, 78.0, context)
        val handle = GamesRummyTouchMachine()
        handle.down(RummyCanvasPoint(edge.x - 10, edge.y), context)
        handle.move(fx.finger(fx.screen(300.0, 300.0, context)), context)
        val set = assertNotNull(handle.drag)
        val frames = GamesRummyFloatingLayout.frames(set, context.viewport.tileSize, context.viewport.scale, liftScale = 1.0)
        val origin = context.viewport.transform.toLogical(context.inTable(RummyCanvasPoint(frames[0].x, frames[0].y)))
        val setTarget = assertIs<RummyDropTarget.NewMeldAt>(GamesRummyDropPlanner.target(set, context), "손잡이 놓을 자리 없음")
        assertEquals(setTarget.point.x.toDouble(), origin.x, 1.0)
        assertEquals(setTarget.point.y.toDouble(), origin.y, 1.0)
    }

    // MARK: 내 차례 아님

    @Test
    fun notMyTurnOnlyRearrangesTheRack() {
        val editor = fx.editor()
        val context = fx.context(editor, isMyTurn = false)
        assertTrue(context.scene.meldTileIDs.all { it.isEmpty() }, "남의 차례 판 타일에 id 가 있다")
        val board = fx.screen(160.0, 78.0, context)
        assertEquals(GamesRummyHit.Felt, context.hit(board))
        val felt = fx.screen(300.0, 300.0, context)
        assertEquals(GamesRummyDropAction.None, fx.trace(fx.rackPoint("D9", context), fx.finger(felt), context))
        val frame = context.rack.frame(RummyRackSlot(1, 12))
        val target = RummyCanvasPoint(context.layout.rack.x + frame.midX, context.layout.rack.y + frame.midY)
        val action = fx.trace(fx.rackPoint("D9", context), fx.finger(target), context)
        val d9 = fx.id("D9", editor)
        assertEquals(GamesRummyDropAction.MoveTiles(listOf(d9), RummyDropTarget.RackSlot(RummyRackSlot(1, 12))), action)
        assertTrue(fx.apply(action, editor))
        assertEquals(RummyRackSlot(1, 12), editor.rackLayout.slot(d9))
        // 편집기가 없는 자리(기권)는 받침대도 없다.
        assertEquals(GamesRummyHit.Felt, fx.context(null, isMyTurn = false).hit(board))
    }

    // MARK: 핀치 · 자동 밀기 · 굳히기

    @Test
    fun pinchRules() {
        val context = fx.context()
        val start = fx.rackPoint("C2", context)
        val machine = GamesRummyTouchMachine()
        machine.down(start, context)
        assertTrue(machine.beginPinch())
        val after = RummyCanvasPoint(start.x + 50, start.y - 200)
        assertEquals(GamesRummyTouchMachine.Effect.None, machine.move(after, context))
        assertNull(machine.drag)
        assertEquals(GamesRummyDropAction.None, machine.up(after, context))
        assertTrue(machine.isIdle)

        val dragging = GamesRummyTouchMachine()
        dragging.down(start, context)
        dragging.move(RummyCanvasPoint(start.x, start.y - 100), context)
        assertFalse(dragging.beginPinch())
        assertNotNull(dragging.drag)

        val model = GamesRummyMatchModel(tableSize(context))
        val before = model.viewport.scale
        assertTrue(model.beginPinch())
        model.pinch(1.2, RummyCanvasPoint(200.0, 200.0))
        assertTrue(model.viewport.scale > before)
        assertEquals(before, model.renderScale, "핀치 중에 판 층을 다시 그린다")
        model.pinchEnded()
        assertEquals(model.viewport.scale, model.renderScale, "손을 뗐는데 또렷하게 안 그린다")
        assertEquals(GamesRummyDropAction.None, model.touchUp(start, context))
        assertTrue(model.machine.isIdle, "핀치 뒤 다음 손이 막힌다")
    }

    @Test
    fun edgeAutoPanOnlyInTheZone() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.rackPoint("D9", context)
        model.touchDown(start, context)
        val pointer = RummyCanvasPoint(380.0, context.layout.table.midY)
        model.touchMoved(fx.finger(pointer), context)
        val first = model.target
        val x = model.viewport.origin.x
        model.edgeTick(0.1)
        assertEquals(x + 40, model.viewport.origin.x, 0.001)
        assertNotEquals(first, model.target, "밀렸는데 놓을 자리가 그대로다")
        model.touchMoved(fx.finger(RummyCanvasPoint(200.0, context.layout.table.midY)), context)
        assertEquals(0, model.edgeDirection)
        val still = model.viewport.origin.x
        model.edgeTick(0.1)
        assertEquals(still, model.viewport.origin.x, 0.0, "가운데인데 밀렸다")
        model.touchMoved(fx.finger(RummyCanvasPoint(380.0, context.layout.rack.midY)), context)
        assertEquals(0, model.edgeDirection, "받침대 위인데 자동 밀기가 돈다")
        model.edgeTick(0.1)
        assertEquals(still, model.viewport.origin.x, 0.0, "받침대 위인데 판이 밀렸다")
        model.cancelTouch()
    }

    @Test
    fun boardIsFrozenWhileHolding() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        val scale = model.viewport.scale
        val start = fx.rackPoint("C2", context)
        model.touchDown(start, context)
        assertEquals(2, model.frozenRows)
        model.tableSizeChanged(RummyCanvasSize(393.0, 422.0))
        assertEquals(scale, model.viewport.scale, "누르는 동안 판이 움직였다")
        val up = RummyCanvasPoint(start.x, start.y - 100)
        model.touchMoved(up, context)
        model.tableSizeChanged(RummyCanvasSize(393.0, 400.0))
        assertEquals(scale, model.viewport.scale, "끄는 동안 판이 움직였다")
        model.touchUp(up, context)
        assertNull(model.frozenRows)
        assertEquals(400.0 / 640.0, model.viewport.scale, 0.001, "뗀 뒤에 안 맞췄다")
        assertEquals(model.viewport.scale, model.renderScale)
        // 빈 펠트 밀기는 굳히지 않는다.
        val felt = fx.screen(300.0, 300.0, context.with(model.viewport))
        model.touchDown(felt, context)
        assertNull(model.frozenRows)
        model.touchUp(felt, context)
    }

    @Test
    fun cancelledTouchDropsNothingAndNextTouchIsNew() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.rackPoint("C2", context)
        val up = RummyCanvasPoint(start.x, start.y - 100)
        model.touchDown(start, context)
        model.touchMoved(up, context)
        assertNotNull(model.drag)
        // 판이 바뀌었다 — 손가락은 아직 닿아 있다. 뗄 때까지 무시한다.
        model.cancelTouch()
        assertNull(model.drag)
        assertTrue(model.draggingIDs.isEmpty())
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 200), context)
        assertNull(model.drag, "거둔 손이 다시 집었다")
        assertEquals(GamesRummyDropAction.None, model.touchUp(up, context))
        assertTrue(model.machine.isIdle)
        // 시스템이 거뒀다 — 다음 손은 새로 분류된다.
        model.touchDown(start, context)
        model.touchMoved(up, context)
        model.touchVanished()
        assertTrue(model.machine.isIdle)
        assertNull(model.drag)
        model.touchDown(start, context)
        assertFalse(model.machine.isIdle, "낡은 거둠이 새 손을 죽였다")
        model.cancelTouch()
    }

    // MARK: 성능의 값

    /** 손을 1,000번 움직여도 판 층 입력은 같은 값이다(판을 다시 그리는 계기가 없다). 떠 있는 타일 값만 바뀐다. */
    @Test
    fun fingerDoesNotTouchTheBoardInputs() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.rackPoint("C2", context)
        model.touchDown(start, context)
        model.touchMoved(RummyCanvasPoint(start.x, start.y - 200), context)
        val dragging = model.draggingIDs
        val viewport = model.viewport
        val render = model.renderScale
        val rows = model.frozenRows
        repeat(1_000) { step ->
            model.touchMoved(RummyCanvasPoint(100.0 + step % 100, start.y - 200), context)
        }
        assertSame(dragging, model.draggingIDs)
        assertSame(viewport, model.viewport)
        assertEquals(render, model.renderScale)
        assertEquals(rows, model.frozenRows)
        val before = model.drag
        model.touchMoved(RummyCanvasPoint(150.0, start.y - 190), context)
        assertNotEquals(before, model.drag, "기준선: 떠 있는 타일은 움직인다")
        model.cancelTouch()
    }

    @Test
    fun previewOnlyChangesWithTheTarget() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        val start = fx.rackPoint("A4", context)
        val over = fx.finger(fx.screen(100.0 + 120 - 6, 78.0, context))
        model.touchDown(start, context)
        model.touchMoved(over, context)
        val preview = assertNotNull(model.boardPreview)
        repeat(20) { step -> model.touchMoved(RummyCanvasPoint(over.x + step % 2, over.y), context) }
        assertSame(preview, model.boardPreview, "손이 떨릴 때마다 미리보기를 다시 묻는다")
        model.cancelTouch()
    }

    @Test
    fun panTouchesOnlyTheViewport() {
        val context = fx.context()
        val model = GamesRummyMatchModel(tableSize(context))
        val felt = fx.screen(300.0, 300.0, context)
        model.touchDown(felt, context)
        val dragging = model.draggingIDs
        val render = model.renderScale
        model.touchMoved(RummyCanvasPoint(felt.x - 40, felt.y), context)
        assertSame(dragging, model.draggingIDs)
        assertEquals(render, model.renderScale)
        assertNull(model.drag)
        assertTrue(model.viewport.origin.x > 0, "밀리지 않았다")
        model.touchUp(felt, context)
    }

    // MARK: 미리보기

    private fun dragTo(context: GamesRummyTouchContext, face: String, pointer: RummyCanvasPoint): GamesRummyDrag {
        val machine = GamesRummyTouchMachine()
        machine.down(fx.rackPoint(face, context), context)
        machine.move(fx.finger(pointer), context)
        return machine.drag!!
    }

    @Test
    fun boardPreviewKinds() {
        val context = fx.context()
        val onMeld = dragTo(context, "A4", fx.screen(214.0, 78.0, context))
        val preview = assertNotNull(GamesRummyDropPlanner.boardPreview(onMeld, GamesRummyDropPlanner.target(onMeld, context), context))
        assertEquals(0, preview.targetSet)
        assertTrue(preview.completes, "맞는 세트가 되면 초록")

        val felt = dragTo(context, "D9", fx.screen(300.0, 300.0, context))
        assertIs<RummyBoardPreview.Ghost>(GamesRummyDropPlanner.boardPreview(felt, GamesRummyDropPlanner.target(felt, context), context), "빈 곳 점선이 없다")

        // 첫 등록 전 판 묶음에 꽂기는 초록을 거둔다(R-12 — 놓고 [완료]를 눌러야 막히면 안 된다).
        val before = fx.context(fx.editor(initialDone = false))
        val beforeDrag = dragTo(before, "A4", fx.screen(214.0, 78.0, before))
        val veiled = assertNotNull(GamesRummyDropPlanner.boardPreview(beforeDrag, GamesRummyDropPlanner.target(beforeDrag, before), before))
        assertFalse(veiled.completes, "첫 등록 전인데 초록이다")

        // 남의 차례는 미리보기가 없다.
        val other = fx.context(isMyTurn = false)
        val otherDrag = dragTo(other, "D9", fx.screen(300.0, 300.0, other))
        assertNull(GamesRummyDropPlanner.boardPreview(otherDrag, GamesRummyDropPlanner.target(otherDrag, other), other))
    }

    @Test
    fun rackPreviewIsTheRealLayout() {
        val editor = fx.editor()
        val context = fx.context(editor)
        val d9 = fx.id("D9", editor)
        val frame = context.rack.frame(RummyRackSlot(0, 2))
        val over = RummyCanvasPoint(context.layout.rack.x + frame.midX, context.layout.rack.y + frame.midY)
        val drag = dragTo(context, "D9", over)
        val target = GamesRummyDropPlanner.target(drag, context)
        val preview = assertNotNull(GamesRummyDropPlanner.rackPreview(drag, target, editor))
        assertEquals(listOf(preview.layout.slot(d9)), preview.ghosts)
        // 놓은 결과와 같다(미리보기 = 실제). 편집기는 안 바뀌었다.
        val copy = editor.copy()
        assertTrue(copy.moveBlock(listOf(d9), target!!))
        assertEquals(copy.rackLayout, preview.layout)
        assertNotEquals(copy.rackLayout, editor.rackLayout)
    }

    // MARK: 판 장면

    private fun state(json: String): RummyMatchState = SwiftJson.decode(RummyMatchState.serializer(), json)

    private val base = """"id":"7e7e0000-0000-4000-8000-000000000068","status":"active","seq":1,"my_seat_no":0,"turn_seat_no":1,""" +
        """"seats":[{"seat_no":0,"user_id":"7e7e0000-0000-4000-8000-0000000000a1","state":"playing"},{"seat_no":2,"user_id":"7e7e0000-0000-4000-8000-0000000000c3","state":"forfeit"},{"seat_no":1,"user_id":"7e7e0000-0000-4000-8000-0000000000b2","state":"playing","rack_count":9,"initial_done":false,"timeout_streak":2},{"user_id":"7e7e0000-0000-4000-8000-0000000000d4","state":"invited"}]"""

    /** 위치는 서버 table_layout 그대로 — 폰이 재배치하지 않는다. */
    @Test
    fun confirmedBoardKeepsTheServerLayout() {
        val match = state("""{$base,"table":[["A1","A2","A3"],["B1","B2","B3"]],"table_layout":[[612,304],[8,16]]}""")
        val scene = GamesRummyBoardScene.make(match, null, false, null)
        assertEquals(RummyPoint(612, 304), scene.melds[0].frame.origin)
        assertEquals(RummyPoint(8, 16), scene.melds[1].frame.origin)
        assertTrue(scene.meldTileIDs.all { it.isEmpty() })
    }

    /** 남의 작업 판: 확정 판에 없던 면을 이번 차례에 낸 타일로 칠한다 · 무효 묶음은 무효로 그린다. */
    @Test
    fun otherDraftHighlightsNewFaces() {
        val match = state(
            """{$base,"table":[["A1","A2","A3"]],"table_layout":[[100,50]],"draft":{"table":[["A1","A2","A3","A4"],["D9"]],"layout":[[100,50],[300,300]],"draft_seq":3}}""",
        )
        val draft = match.draft?.table
        val scene = GamesRummyBoardScene.make(match, null, false, draft)
        assertEquals(listOf(false, false, false, true), scene.melds[0].tiles.map { it.highlighted })
        assertFalse(scene.melds[0].invalid)
        assertTrue(scene.melds[1].invalid)
        assertEquals(RummyPoint(300, 300), scene.melds[1].frame.origin)
    }

    @Test
    fun opponentsStartFromMyNextSeatAndHideNothingButTheRack() {
        val match = state("""{$base,"table":[]}""")
        assertEquals(listOf(1L, 2L), GamesRummySeats.opponents(match).map { it.seatNo }, "내 다음 차례부터 · 자리 번호 없는 사람은 판에 없다")
        val peer = GamesRummySeats.opponents(match)[0]
        assertTrue(GamesRummySeats.isTurn(peer, match))
        assertEquals(listOf<GamesRummySeatTag>(GamesRummySeatTag.Timeouts(2), GamesRummySeatTag.BeforeInitial), GamesRummySeats.tags(peer))
        val gone = GamesRummySeats.opponents(match)[1]
        assertEquals(RummySeatState.forfeit, gone.state)
        assertEquals(listOf<GamesRummySeatTag>(GamesRummySeatTag.Forfeit), GamesRummySeats.tags(gone), "기권이면 다른 표시는 안 붙인다")
        assertTrue(GamesRummySeats.isGone(gone))
        assertFalse(GamesRummySeats.isTurn(gone, match))
        assertEquals(60.0, GamesRummySeats.turnTotal(match), 0.0, "마감을 모르면 60초")
    }

    @Test
    fun statusLineOrder() {
        val editor = fx.editor()
        assertEquals(GamesRummyStatusLine.Tone.notice, GamesRummyStatusLine.make("판이 바뀌었어요", true, editor, "비", RummySeatState.playing).tone, "서버 문구가 먼저")
        val mine = GamesRummyStatusLine.make(null, true, editor, "비", RummySeatState.playing)
        assertEquals(RummyPhoneText.myTurnStatus(editor), mine.text)
        assertEquals(GamesRummyStatusLine.Tone.plain, mine.tone)
        assertTrue(editor.moveBlock(listOf(fx.id("A4", editor)), RummyDropTarget.Meld(0, 3)))
        assertEquals(GamesRummyStatusLine.Tone.ready, GamesRummyStatusLine.make(null, true, editor, "비", RummySeatState.playing).tone, "[완료]가 켜지면 초록")
        assertEquals(GamesRummyMatchText.spectating, GamesRummyStatusLine.make(null, false, null, "비", RummySeatState.forfeit).text)
        assertEquals(RummyPhoneText.turnOf("비"), GamesRummyStatusLine.make(null, false, editor, "비", RummySeatState.playing).text)
        assertEquals("", GamesRummyStatusLine.make(null, false, null, null, RummySeatState.playing).text)
    }

    /** 첫 등록 합: 첫 등록 뒤엔 없고, 남의 차례엔 판 쪽을 세지 않는다. */
    @Test
    fun planLineCountsTheRackAndMyBoard() {
        assertNull(gamesRummyPlanLine(fx.editor(initialDone = true), true))
        assertNull(gamesRummyPlanLine(fx.editor(initialDone = false), true), "랙 묶음이 없으면 안 보인다")
        val editor = RummyTurnEditor(
            table = emptyList(),
            rack = fx.faces("D10", "D11", "D12", "C1", "C2", "C3"),
            initialDone = false,
            rackHalfColumns = RummyRackGeometry.phoneHalfColumns,
        )
        // 빈칸 없이 놓였으니 딱 붙은 여섯 장 한 덩어리는 맞는 묶음이 아니다 — 뒤 셋을 다음 줄로 떼어 놓는다.
        assertTrue(editor.moveBlock(editor.rack.takeLast(3).map { it.id }, RummyDropTarget.RackSlot(RummyRackSlot(1, 0))))
        val plan = assertNotNull(gamesRummyPlanLine(editor, true))
        assertEquals(RummyPhoneText.plan(0, 39), plan.first)
        assertTrue(plan.second, "39 는 30 을 넘는다")
    }
}
