// 원본: Sources/CheckMobileKit/Games/GamesRummyMatchModel.swift:1 @ ios-1017-cube 61d75d8c · 설계서 §10
//
// 판 화면의 손 상태 한 곳. 화면 전체 입력 층 하나가 사건을 여기로 넘기고, 잎은 **자기가 쓰는 값만** 읽는다 — 그래서 손이 움직여도 판이 다시 그려지지 않는다:
//   · 손가락 자리([drag])는 떠 있는 타일 그리기만 읽는다(사건마다 바뀐다).
//   · 놓을 자리에서 나온 값([target] · [boardPreview] · [rackPreview] · [hoverRefused])은 **자리가 바뀔 때만** 쓴다(타일 하나를 끄는 동안 대부분 그대로다).
//   · 판 층의 입력([draggingIDs] · [lift] · [movingSet] · [renderScale])은 끌기가 시작 · 끝날 때만 바뀐다.
// 판 변환을 굳힌다: 누르는 동안 · 끄는 동안 칸 크기 변화를 미루고 받침대 줄 수를 묶는다([frozenRows]). 손 아래 판이 움직이면 안 된다(맥 교훈). 가장자리 자동 밀기만 예외다 — 사람이 민 것이다.
// 놓은 뒤에도 같다: 차례 안에서는 줄 수가 줄지 않는다([rackRows]) — 셋째 줄 마지막 타일을 놓는 순간 받침대 타일이 통째로 커지면 다음 타일을 잡을 자리가 어긋난다.
// 기기가 돌면(판 화면 크기가 바뀌면) 든 것을 거둔다([screenSizeChanged]) — 쥔 자리가 새 칸에서 다른 것이 된다.
// 시간은 밖에서 민다: 0.5초는 입력 층의 시간 제한, 자동 밀기는 [isEdgePanning] 이 참인 동안만 도는 프레임 잎이 [edgeTick] 을 부른다. 이 값들은 그 효과의 열쇠를 스스로 바꾸지 않는다(맥 0.3.69 재생성 고리 금지).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardPreview
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyRect
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.stores.rummy.RummyEditorKey
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.moveSet
import com.yehsung.aingcheck.core.stores.rummy.moveTiles

@Stable
class GamesRummyMatchModel(tableSize: RummyCanvasSize = RummyCanvasSize(548.0, 248.0)) {
    var viewport: GamesRummyViewport by mutableStateOf(GamesRummyViewport.of(tableSize))
        private set

    /** 판 층을 그린 배율. 핀치 중에는 그대로 두고 층을 통째로 키운다(100장을 프레임마다 다시 그리지 않게) — 손을 떼면 그 배율로 또렷하게 다시 그린다. */
    var renderScale: Double by mutableStateOf(viewport.scale)
        private set
    var drag: GamesRummyDrag? by mutableStateOf(null)
        private set
    var draggingIDs: Set<Int> by mutableStateOf(emptySet())
        private set
    var lift: GamesRummyLift? by mutableStateOf(null)
        private set
    var movingSet: Int? by mutableStateOf(null)
        private set
    var target: RummyDropTarget? by mutableStateOf(null)
        private set
    var boardPreview: RummyBoardPreview? by mutableStateOf(null)
        private set
    var rackPreview: GamesRummyRackPreview? by mutableStateOf(null)
        private set
    var hoverRefused: Boolean by mutableStateOf(false)
        private set

    /** 놓기를 거절했다 — 받침대 빨간 표시(0.6초 · 화면이 [clearRefusedFlash] 로 내린다). */
    var refusedFlash: Boolean by mutableStateOf(false)
        private set
    var frozenRows: Int? by mutableStateOf(null)
        private set

    /** 햅틱 계기(묶음째 집음 · 거절). */
    var liftSerial: Int by mutableStateOf(0)
        private set
    var refuseSerial: Int by mutableStateOf(0)
        private set

    /** 자동 밀기 중. 참인 동안만 프레임이 돈다 — 끝에 닿으면 거짓이 되어 멎는다. */
    var isEdgePanning: Boolean by mutableStateOf(false)
        private set

    val machine: GamesRummyTouchMachine = GamesRummyTouchMachine()

    /** 화면이 조립할 때마다 넣는 판단 재료(상태 아님 — 입력 층이 다시 시작하지 않게). */
    var currentContext: GamesRummyTouchContext? = null
        private set

    /** 방금 손으로 놓은 타일 — 판 변화 모션에서 뺀다(손이 놓은 자리가 곧 제자리다. 맥 recentDrop 과 같다). */
    var recentDropIDs: Set<Int> = emptySet()
        private set

    /** 그 타일을 손이 놓은 자리(논리 좌표) — 들어갈 자리가 다르면 여기서 미끄러진다(맥 land). */
    var recentDropOrigins: Map<Int, RummyCanvasPoint> = emptyMap()
        private set

    /** 손이 판을 쥐고 있다 — 동작 버튼을 끈다. 다른 손가락의 [되돌리기] · [777|789] 는 seq 를 안 올려서, 그대로 두면 쥔 묶음 번호가 낡은 채 다른 묶음이 옮겨진다. */
    val locksActions: Boolean get() = frozenRows != null

    private var heldRows: Pair<String?, Int>? = null
    private var screenSize: RummyCanvasSize? = null
    private var pendingTableSize: RummyCanvasSize? = null
    private var pinchBase: Double? = null

    /** 조립 단계가 재료를 만들 때 — 보기를 구독하지 않고 읽는다(구독하면 밀 때마다 화면 전체가 다시 돈다). 사건 때는 모델이 지금 보기로 채운다. */
    fun viewportUntracked(): GamesRummyViewport = Snapshot.withoutReadObservation { viewport }

    /** 화면이 조립을 마칠 때마다 — 재료를 넣고 칸 크기를 맞춘다. */
    fun sync(context: GamesRummyTouchContext) {
        currentContext = context
        tableSizeChanged(RummyCanvasSize(context.layout.table.width, context.layout.table.height))
    }

    /** 받침대 줄 수. 손이 닿은 동안은 [frozenRows], 그 밖에는 **차례 안에서 줄지 않는다** — 줄이 줄면 타일이 통째로 커져 다음 타일을 잡을 자리가 어긋난다. 판 칸은 줄 수와 무관하다. 차례가 바뀌면 그때 맞춘다. 상태가 아니라 다시 조립을 부르지 않는다. */
    fun rackRows(editorRows: Int, turnKey: String?): Int {
        frozenRows?.let { return it }
        val rows = heldRows?.let { if (it.first == turnKey) maxOf(it.second, editorRows) else editorRows } ?: editorRows
        heldRows = turnKey to rows
        return rows
    }

    /** 판 화면 크기가 바뀌었다(기기가 돌았다 · 인셋이 바뀌었다). 쥔 것 · 밀기 · 핀치를 거두고 손을 뗄 때까지 무시한다 — 손 자리가 새 칸에서 다른 것을 가리킨다. 처음 재는 것은 변화가 아니다. */
    fun screenSizeChanged(size: RummyCanvasSize) {
        val before = screenSize
        screenSize = size
        if (before == null || before == size) return
        if (!machine.isIdle) {
            machine.abandon()
            tearDown()
        }
        endPinch()
    }

    // MARK: 손

    fun touchDown(point: RummyCanvasPoint, base: GamesRummyTouchContext) {
        currentContext = base
        recentDropIDs = emptySet()
        recentDropOrigins = emptyMap()
        machine.down(point, base.with(viewport))
        if (machine.holdsBoard) frozenRows = base.layout.rackRows
    }

    fun touchMoved(point: RummyCanvasPoint, base: GamesRummyTouchContext) {
        currentContext = base
        val context = base.with(viewport)
        when (val effect = machine.move(point, context)) {
            GamesRummyTouchMachine.Effect.None -> Unit
            is GamesRummyTouchMachine.Effect.Pan -> viewport = viewport.panned(effect.dx, effect.dy)
            GamesRummyTouchMachine.Effect.DragBegan -> {
                lift = null
                val moved = machine.drag
                draggingIDs = moved?.ids?.toSet() ?: emptySet()
                val kind = moved?.kind
                if (kind is GamesRummyDrag.Kind.WholeMeld) movingSet = kind.set
                refresh(context)
            }
            GamesRummyTouchMachine.Effect.DragMoved -> refresh(context)
        }
    }

    /** 손을 뗐다. 결과는 화면이 [apply] 로 스토어에 옮긴다. */
    fun touchUp(point: RummyCanvasPoint, base: GamesRummyTouchContext): GamesRummyDropAction {
        val context = base.with(viewport)
        val released = machine.drag?.moved(point, base.layout)
        val action = machine.up(point, context)
        when (action) {
            is GamesRummyDropAction.MoveTiles -> {
                recentDropIDs = action.ids.toSet()
                recentDropOrigins = released?.let { dropOrigins(it, context) } ?: emptyMap()
            }
            is GamesRummyDropAction.MoveSet -> {
                recentDropIDs = base.scene.meldTileIDs.getOrNull(action.set)?.toSet() ?: emptySet()
                recentDropOrigins = released?.let { dropOrigins(it, context) } ?: emptyMap()
            }
            GamesRummyDropAction.None, GamesRummyDropAction.Refused -> Unit
        }
        tearDown()
        if (action == GamesRummyDropAction.Refused) {
            refuseSerial += 1
            refusedFlash = true
        }
        return action
    }

    /**
     * 판이 바뀌었다(seq 상승). **손은 아직 닿아 있을 수 있다.**
     * · 판 밀기는 그대로 둔다(타일을 쥔 게 아니다).
     * · 같은 차례이고 쥔 타일이 편집기에 그대로면 둔다 — 남이 기권해 seq 만 오른 경우다. 꾹 눌러 집은 묶음이 풀리면 안 된다.
     * · 차례가 바뀌었거나 쥔 id · 묶음이 사라졌으면 낡았다(새 차례는 id 를 다시 매긴다) — 거두고 손을 뗄 때까지 무시한다.
     */
    fun boardChanged(editor: RummyTurnEditor?, turnKey: RummyEditorKey?) {
        if (!machine.holdsBoard) return
        val held = currentContext
        if (turnKey == held?.turnKey && machine.holdSurvives(editor, held?.editor)) return
        machine.abandon()
        tearDown()
    }

    /** 시스템이 손을 거뒀다 · 입력 층이 죽었다 — 끌던 타일을 공중에 남기지 않는다. 함께 사라진 핀치도 푼다. */
    fun touchVanished() {
        machine.cancel()
        tearDown()
        endPinch()
    }

    /** 손을 놓은 자리(타일 왼쪽 위, 논리 좌표). 떠 있는 타일과 같은 기준점에서 나온다. 받침대 위에서 놓았으면 값은 있어도 판에 그 타일이 없어 쓰이지 않는다. */
    private fun dropOrigins(drag: GamesRummyDrag, context: GamesRummyTouchContext): Map<Int, RummyCanvasPoint> {
        val frames = GamesRummyFloatingLayout.frames(drag, context.viewport.tileSize, context.viewport.scale, liftScale = 1.0)
        return drag.ids.zip(frames).associate { (id, frame) -> id to context.viewport.transform.toLogical(context.inTable(RummyCanvasPoint(frame.x, frame.y))) }
    }

    private fun tearDown() {
        drag = null
        draggingIDs = emptySet()
        lift = null
        movingSet = null
        target = null
        boardPreview = null
        rackPreview = null
        hoverRefused = false
        frozenRows = null
        isEdgePanning = false
        pendingTableSize?.let {
            pendingTableSize = null
            tableSizeChanged(it)
        }
    }

    /** 손가락이나 보기가 움직인 뒤 파생 값을 맞춘다. 놓을 자리가 그대로면 미리보기를 다시 묻지 않는다. */
    private fun refresh(context: GamesRummyTouchContext) {
        val moved = machine.drag ?: return
        drag = moved
        isEdgePanning = context.layout.table.contains(moved.pointer) && viewport.edgeMoves(context.inTable(moved.pointer))
        val next = GamesRummyDropPlanner.target(moved, context)
        if (next == target) return
        target = next
        boardPreview = GamesRummyDropPlanner.boardPreview(moved, next, context)
        rackPreview = GamesRummyDropPlanner.rackPreview(moved, next, context.editor)
        hoverRefused = GamesRummyDropPlanner.refused(moved, next, context.editor)
    }

    // MARK: 0.5초 · 가장자리

    /** 0.5초가 지났다(입력 층의 시간 제한 · 시험이 직접 밟는다). */
    fun holdElapsed(base: GamesRummyTouchContext) {
        val picked = machine.holdElapsed(base.with(viewport)) ?: return
        lift = picked
        liftSerial += 1
    }

    /** 끄는 중 기준점이 판 가장자리 28 안이면 민다. 보기가 바뀌었으니 놓을 자리를 다시 묻는다. */
    fun edgeTick(deltaSeconds: Double) {
        val base = currentContext ?: return
        val moved = machine.drag ?: return
        if (!base.layout.table.contains(moved.pointer)) return
        val next = viewport.edgePanned(base.inTable(moved.pointer), deltaSeconds)
        if (next == viewport) {
            isEdgePanning = false
            return
        }
        viewport = next
        refresh(base.with(next))
    }

    // MARK: 보기

    fun tableSizeChanged(size: RummyCanvasSize) {
        if (machine.holdsBoard) {
            pendingTableSize = size
            return
        }
        if (size == viewport.viewport || size.width <= 0 || size.height <= 0) return
        viewport = viewport.resized(size)
        renderScale = viewport.scale
    }

    fun toggleFullView() {
        if (machine.holdsBoard) return
        viewport = viewport.toggledFullView()
        renderScale = viewport.scale
    }

    fun reveal(side: GamesRummySide, frames: List<RummyRect>) {
        viewport = viewport.revealed(side, frames)
    }

    /** 배지 밀기 모션의 한 장면. 그 사이 손이 닿았으면 손이 먼저다. */
    fun showRevealStep(from: GamesRummyViewport, to: GamesRummyViewport, progress: Double) {
        if (!machine.isIdle || pinchBase != null) return
        viewport = from.interpolated(to, progress)
    }

    /** 두 번째 손가락이 닿았다. 끌던 타일이 있으면 핀치를 안 받는다(거짓). 아니면 누르기 · 밀기를 거두고 손을 뗄 때까지 무시한다. */
    fun beginPinch(): Boolean {
        if (pinchBase != null) return true
        if (!machine.beginPinch()) return false
        tearDown()
        pinchBase = viewport.scale
        return true
    }

    /** 핀치 — [magnification] 은 시작부터 곱한 값, 기준점은 판 칸 좌표다. 그린 배율은 그대로 둔다. */
    fun pinch(magnification: Double, tableAnchor: RummyCanvasPoint) {
        val base = pinchBase ?: return
        viewport = viewport.zoomed(base * magnification, tableAnchor)
    }

    /** 핀치 끝 — 그 배율로 또렷하게 다시 그린다. 손을 뗄 때까지 기계는 무시를 잇는다. */
    fun pinchEnded() {
        if (pinchBase == null) return
        endPinch()
    }

    /** 열린 핀치를 닫고 흐린 배율을 또렷하게 맞춘다. 안 닫으면 다음 핀치가 낡은 기준에서 튀고 읽기 전용 밀기가 죽는다. */
    private fun endPinch() {
        pinchBase = null
        if (renderScale != viewport.scale) renderScale = viewport.scale
    }

    /** 읽기 전용 판(결과의 [최종 판]) 밀기 — 타일을 집지 않으니 손 기계를 안 거친다. 핀치 중에는 안 민다. */
    fun readOnlyPan(dx: Double, dy: Double) {
        if (pinchBase != null || (dx == 0.0 && dy == 0.0)) return
        viewport = viewport.panned(dx, dy)
    }

    /** 읽기 전용 판의 핀치 — 손 기계 없이 연다(거기는 쥔 타일이 없다). 기준점은 판 칸 좌표다. */
    fun readOnlyPinch(magnification: Double, tableAnchor: RummyCanvasPoint) {
        if (pinchBase == null) pinchBase = viewport.scale
        viewport = viewport.zoomed((pinchBase ?: viewport.scale) * magnification, tableAnchor)
    }

    fun clearRefusedFlash() {
        refusedFlash = false
    }

    companion object {
        /** 놓은 결과를 스토어로. */
        fun apply(action: GamesRummyDropAction, store: RummyStore) {
            when (action) {
                GamesRummyDropAction.None, GamesRummyDropAction.Refused -> Unit
                is GamesRummyDropAction.MoveTiles -> store.moveTiles(action.ids, action.target)
                is GamesRummyDropAction.MoveSet -> store.moveSet(action.set, action.point)
            }
        }
    }
}
