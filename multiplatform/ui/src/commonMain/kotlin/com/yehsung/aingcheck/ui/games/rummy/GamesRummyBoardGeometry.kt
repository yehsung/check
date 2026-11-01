// 원본: Sources/CheckMobileKit/Games/GamesRummyBoardGeometry.swift:1 · Sources/CheckMobileKit/Games/GamesRummyMatchInput.swift:1 @ ios-1017-cube 614d98bd · 맥 동작은 Sources/check/RummyPanelMatch.swift:490-720 @ 1a5eeca6 · 설계서 §4
//
// 폰 아잉 큐브 판 화면의 **순수 값** — Compose 를 모른다. 그리는 자리 · 누르는 자리 · 놓는 자리가 전부 이 값에서 나온다(맥과 같은 원칙 · 배치는 세로용).
// 좌표는 판 화면 왼쪽 위 원점의 dp 다(값은 Double — 코어 RummyCanvasPoint·RummyCanvasRect). 화면이 px 를 dp 로 바꿔 넘긴다.
//
//   · [GamesRummyMatchLayout] — 칸 사각형(머리 · 상대 · 판 · 상태 · 받침대 · 동작).
//   · [GamesRummyViewport] — 판 보기(배율 · 오프셋 · 클램프 · 전체 맞춤 · 자동 밀기 · 화면 밖 묶음 수). 배율은 **사람이 움직일 때만** 바뀐다(맥 교훈 — 놓을 때마다 판이 움직이면 안 된다).
//   · [GamesRummyHitTester] — 손이 처음 닿은 자리의 분류. 타일마다 제스처를 달지 않는다(판 타일 100장에서 무겁고 판 밀기와 충돌한다).
//   · [GamesRummyTouchMachine] — 손 하나의 일생(8 넘게 움직이면 한 장 · 8 안에서 0.5초면 묶음째 · 손잡이 · 빈 펠트 밀기 · 핀치 뒤 무시).
//   · [GamesRummyDropPlanner] — 놓을 자리 · 미리보기 · 놓은 결과. 맥 resolve · boardPreview · tileEnded 와 같은 갈래다. 판정은 코어 RummyDropResolver · 편집기가 한다.
//   · [GamesRummyFloatingLayout] — 집힌 타일 자리. **그린 자리와 재는 자리가 같다**: 손 위 48 점(GamesRummyDrag.pointer)이 놓기 기준이고 그림도 그 점에 선다.
//
// 받침대 frame ↔ slot 은 코어 RummyRackGeometry.phone 한 벌이다(줄 바닥 · 반 칸 · 자르기까지) — 여기는 끄는 동안의 그리기 맞춤([GamesRummyRackDraw])만 더한다.
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyBoardMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardPreview
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardTile
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasTransform
import com.yehsung.aingcheck.core.rules.rummy.RummyDropResolver
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyMatchRegions
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyRackMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyRackPlate
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRect
import com.yehsung.aingcheck.core.rules.rummy.RummyRules
import com.yehsung.aingcheck.core.rules.rummy.RummySeatArrangement
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTile
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.rules.rummy.rackMelds
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.isRackTarget
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import kotlin.math.abs
import kotlin.math.hypot

// MARK: - 칸

/** 판 화면 칸 자리 — 위에서 아래로 머리 줄 · 상대 줄 · 판(남는 높이 전부) · 상태 줄 · 받침대 · 동작 줄. [actionHeight] 는 큰 글자에서 키운다(잘리지 않게). */
data class GamesRummyMatchLayout(
    val size: RummyCanvasSize,
    val rackRows: Int = RummyRackLayout.baseRows,
    val actionHeight: Double = actionsHeight,
) {
    /** 받침대 기하(한 줄 11장 · 2줄 약 118 · 3줄 약 165 · 4줄부터 타일이 준다). 받침대 칸 왼쪽 위 원점. */
    val rackGeometry: RummyRackGeometry = RummyRackGeometry.phone(size.width, rackRows)

    val header: RummyCanvasRect = RummyCanvasRect(0.0, 0.0, size.width, headerHeight)
    val opponents: RummyCanvasRect = RummyCanvasRect(0.0, header.maxY, size.width, opponentsHeight)
    val actions: RummyCanvasRect = maxOf(actionsHeight, actionHeight).let { RummyCanvasRect(0.0, size.height - it, size.width, it) }
    val rack: RummyCanvasRect = RummyCanvasRect(0.0, actions.y - rackGeometry.height, size.width, rackGeometry.height)
    val status: RummyCanvasRect = RummyCanvasRect(0.0, rack.y - statusHeight, size.width, statusHeight)

    /** 판 — 남는 높이 전부(작은 기기에서 음수가 되지 않는다). */
    val table: RummyCanvasRect = RummyCanvasRect(0.0, opponents.maxY, size.width, maxOf(0.0, status.y - opponents.maxY))

    /** 놓기 판정기가 보는 칸 둘. */
    val regions: RummyMatchRegions get() = RummyMatchRegions(rack, table)

    companion object {
        const val headerHeight: Double = 44.0
        const val opponentsHeight: Double = 56.0
        const val statusHeight: Double = 20.0
        const val actionsHeight: Double = 52.0

        /** 글자 배율이 이 값을 넘으면 동작 줄을 두 줄로 나눈다([완료] 한 줄 · 나머지 셋 한 줄). */
        const val twoRowActionsAboveTextScale: Double = 1.3

        /** 글자 배율 상한 — 동작 줄이 잘리지 않는 끝(화면이 이 값으로 자른다). */
        const val maxActionTextScale: Double = 1.6

        /** 버튼 위아래 · 줄 사이 틈. */
        const val actionGap: Double = 6.0

        fun actionRowCount(textScale: Double): Int = if (textScale > twoRowActionsAboveTextScale) 2 else 1

        /** 버튼 한 줄 높이(44 아래로 안 내려간다 · 글자를 따라 커지되 판을 다 먹지 않게 64 에서 멈춘다). */
        fun actionButtonHeight(textScale: Double): Double =
            if (actionRowCount(textScale) != 2) actionsHeight - actionGap - 2 else minOf(64.0, maxOf(44.0, 40 * textScale))

        /** 글자 배율 → 동작 줄 높이. */
        fun actionHeight(textScale: Double): Double =
            if (actionRowCount(textScale) != 2) actionsHeight else actionButtonHeight(textScale) * 2 + actionGap * 3

        /** 한 줄 동작 줄의 버튼 폭 넷. 합 + 틈 + 양옆 여백 = 칸 폭이라 어느 폭에서도 안 겹친다. [완료]가 가장 크다. */
        fun actionWidths(total: Double): GamesRummyActionWidths {
            val room = maxOf(0.0, total - actionGap * 5)
            return GamesRummyActionWidths(room * 0.36, room * 0.19, room * 0.21, room * 0.24)
        }
    }
}

/** 동작 줄 버튼 폭(dp). */
data class GamesRummyActionWidths(val submit: Double, val draw: Double, val undo: Double, val sort: Double)

// MARK: - 보기

/**
 * 판 보기(배율 · 오프셋). 값이고 움직이면 새 값을 돌려준다.
 *
 * 기본 보기는 **캔버스 높이를 칸에 맞춘 배율**이다(칸 높이 약 470 → 배율 약 0.73 → 타일 약 29×41, 가로 약 530 논리 단위가 보인다). 가로 1000 은 빈 펠트를 끌어 민다.
 * 위치는 모든 기기에 같다(서버 table_layout) — 폰이 재배치하지 않는다. 상한 = 타일 폭 40(배율 1) · 하한 = 전체 맞춤.
 */
data class GamesRummyViewport private constructor(
    val viewport: RummyCanvasSize,
    val scale: Double,
    /** 칸 왼쪽 위에 오는 논리 점(캔버스가 칸보다 작은 축은 0 — 가운데로 그린다). */
    val origin: RummyCanvasPoint,
) {
    val fitScale: Double get() = fitScale(viewport)
    val defaultScale: Double get() = defaultScale(viewport)
    val isFullView: Boolean get() = abs(scale - fitScale) < 0.0005
    val tileSize: RummyCanvasSize get() = RummyCanvasSize(RummyTableLayout.tileWidth.toDouble() * scale, RummyTableLayout.tileHeight.toDouble() * scale)

    /** 지금 보이는 논리 구간. */
    val visibleLogical: RummyCanvasRect
        get() = RummyCanvasRect(origin.x, origin.y, minOf(canvas.width, viewport.width / scale), minOf(canvas.height, viewport.height / scale))

    /** 그리는 자리 · 누르는 자리 · 놓는 자리가 쓰는 한 변환(칸 좌표 ↔ 논리 좌표). */
    val transform: RummyCanvasTransform
        get() = RummyCanvasTransform(scale, origin, screenOrigin(viewport, scale))

    /** 핀치 — 칸 좌표 [anchor] 아래의 논리 점을 그 자리에 두고 배율을 바꾼다. [하한, 상한]으로 자른다. */
    fun zoomed(wanted: Double, anchor: RummyCanvasPoint): GamesRummyViewport {
        val logical = transform.toLogical(anchor)
        val next = minOf(maxScale, maxOf(fitScale, wanted))
        val start = screenOrigin(viewport, next)
        return clamped(next, RummyCanvasPoint(logical.x - (anchor.x - start.x) / next, logical.y - (anchor.y - start.y) / next))
    }

    /** [전체 보기] 토글 — 맞춤 ↔ 기본. */
    fun toggledFullView(): GamesRummyViewport = clamped(if (isFullView) defaultScale else fitScale, origin)

    /** 빈 펠트 끌기 — 손가락과 같은 쪽으로 판이 움직인다(dp). */
    fun panned(dx: Double, dy: Double): GamesRummyViewport = clamped(scale, RummyCanvasPoint(origin.x - dx / scale, origin.y - dy / scale))

    /** 칸 크기가 바뀌었다(받침대 3줄 · 큰 글자). 기본 · 맞춤 보기였으면 새 칸의 기본 · 맞춤으로, 사람이 고른 배율이면 그대로(범위 안으로만). */
    fun resized(to: RummyCanvasSize): GamesRummyViewport {
        if (to == viewport) return this
        val wasFull = isFullView
        val wasDefault = abs(scale - defaultScale) < 0.0005
        val base = GamesRummyViewport(to, scale, origin)
        val next = when {
            wasFull -> base.fitScale
            wasDefault -> base.defaultScale
            else -> minOf(maxScale, maxOf(base.fitScale, scale))
        }
        return base.clamped(next, origin)
    }

    /** 칸 좌표 [pointerX] 에서 자동 밀기 방향(−1 왼쪽 · +1 오른쪽 · 0 없음). 더 못 미는 쪽이면 0 — 화면이 프레임을 돌리지 않게. 경계는 가장자리가 아니다. */
    fun edgeDirection(pointerX: Double): Int {
        val step = 1.0
        return when {
            pointerX < edgeZone -> if (clamped(scale, RummyCanvasPoint(origin.x - step, origin.y)).origin.x != origin.x) -1 else 0
            pointerX > viewport.width - edgeZone -> if (clamped(scale, RummyCanvasPoint(origin.x + step, origin.y)).origin.x != origin.x) 1 else 0
            else -> 0
        }
    }

    /** 끌기 중 가장자리 자동 밀기 한 걸음(동작 줄이기여도 켠다 — 꾸밈이 아니라 끌기 기능이다). 안 움직였으면 같은 값. */
    fun edgePanned(pointerX: Double, deltaSeconds: Double): GamesRummyViewport {
        val step = edgePanSpeed * deltaSeconds
        return when {
            pointerX < edgeZone -> clamped(scale, RummyCanvasPoint(origin.x - step, origin.y))
            pointerX > viewport.width - edgeZone -> clamped(scale, RummyCanvasPoint(origin.x + step, origin.y))
            else -> this
        }
    }

    /** 왼 · 오른쪽 화면 밖 묶음 수(남이 새로 낸 묶음을 못 보고 지나가지 않게 하는 배지의 값). 일부라도 보이면 세지 않는다. */
    fun offscreenCounts(frames: List<RummyRect>): GamesRummyOffscreenCounts {
        val visible = visibleLogical
        var left = 0
        var right = 0
        for (frame in frames) {
            if (frame.maxX.toDouble() <= visible.x) {
                left += 1
            } else if (frame.x.toDouble() >= visible.maxX) {
                right += 1
            }
        }
        return GamesRummyOffscreenCounts(left, right)
    }

    /** 배지를 눌렀다 — 그 쪽에서 가장 가까운 화면 밖 묶음이 여백을 두고 보이도록 민다. 밀 것이 없으면 그대로. */
    fun revealed(side: GamesRummySide, frames: List<RummyRect>): GamesRummyViewport {
        val visible = visibleLogical
        val x = when (side) {
            GamesRummySide.left -> {
                val nearest = frames.filter { it.maxX.toDouble() <= visible.x }.maxByOrNull { it.maxX } ?: return this
                nearest.x.toDouble() - revealMargin
            }
            GamesRummySide.right -> {
                val nearest = frames.filter { it.x.toDouble() >= visible.maxX }.minByOrNull { it.x } ?: return this
                nearest.maxX.toDouble() + revealMargin - visible.width
            }
        }
        return clamped(scale, RummyCanvasPoint(x, origin.y))
    }

    /** 밀기 모션의 한 장면 — 배율은 같고 오프셋만 [target] 쪽으로. [progress] 0…1. */
    fun interpolated(target: GamesRummyViewport, progress: Double): GamesRummyViewport =
        clamped(scale, RummyCanvasPoint(origin.x + (target.origin.x - origin.x) * progress, origin.y + (target.origin.y - origin.y) * progress))

    /** 왼쪽 끝은 손잡이 터치 폭만큼 더 민다 — 손잡이는 묶음 **왼쪽 바깥**이라 캔버스 왼끝(x 0) 묶음은 그래야 닿는다. 전체 맞춤은 밀 곳이 없다 — 그 보기에선 꾹 눌러 묶음째 옮긴다. */
    private fun clamped(nextScale: Double, wanted: RummyCanvasPoint): GamesRummyViewport {
        val visibleW = viewport.width / nextScale
        val visibleH = viewport.height / nextScale
        val leftEnd = -GamesRummyGestureRules.handleTouchWidth / nextScale
        val x = if (visibleW >= canvas.width) 0.0 else minOf(maxOf(wanted.x, leftEnd), canvas.width - visibleW)
        val y = if (visibleH >= canvas.height) 0.0 else minOf(maxOf(wanted.y, 0.0), canvas.height - visibleH)
        return GamesRummyViewport(viewport, nextScale, RummyCanvasPoint(x, y))
    }

    companion object {
        /** 끌기 중 손이 이 안에 머물면 그 쪽으로 민다. */
        const val edgeZone: Double = 28.0

        /** 가장자리 자동 밀기(논리 단위/초). */
        const val edgePanSpeed: Double = 400.0

        /** 화면 밖 묶음 배지를 눌러 밀 때 묶음 옆에 둘 여백(논리 단위). */
        const val revealMargin: Double = 24.0

        /** 타일 폭 상한(dp). */
        const val maxTileWidth: Double = 40.0

        private val canvas: RummyCanvasSize get() = RummyCanvasTransform.canvas

        /** 타일 폭 40(논리 타일 폭 40 × 배율 1). */
        val maxScale: Double get() = maxTileWidth / RummyTableLayout.tileWidth.toDouble()

        /** 전체 맞춤 배율(하한). */
        fun fitScale(viewport: RummyCanvasSize): Double =
            maxOf(0.01, minOf(minOf(viewport.width / canvas.width, viewport.height / canvas.height), maxScale))

        /** 기본 보기 배율(높이를 맞춘다). */
        fun defaultScale(viewport: RummyCanvasSize): Double = minOf(maxScale, maxOf(fitScale(viewport), viewport.height / canvas.height))

        /** 캔버스가 칸보다 작은 축은 가운데로 그린다. */
        private fun screenOrigin(viewport: RummyCanvasSize, scale: Double): RummyCanvasPoint = RummyCanvasPoint(
            maxOf(0.0, (viewport.width - canvas.width * scale) / 2),
            maxOf(0.0, (viewport.height - canvas.height * scale) / 2),
        )

        /** 기본 보기로 시작한다. */
        fun of(viewport: RummyCanvasSize): GamesRummyViewport =
            GamesRummyViewport(viewport, defaultScale(viewport), RummyCanvasPoint(0.0, 0.0)).let { it.clamped(it.scale, it.origin) }
    }
}

/** 화면 밖 묶음 수. */
data class GamesRummyOffscreenCounts(val left: Int, val right: Int)

/** 판 왼쪽 · 오른쪽. */
enum class GamesRummySide { left, right }

// MARK: - 받침대(그리기)

object GamesRummyRackDraw {
    /**
     * 끄는 동안 미리보기가 새 줄을 열어도 칸은 굳어 있다 — 그 줄 수를 칸 높이 [height] 에 담는 그리기 기하(타일이 줄어 담긴다 · 맥과 같은 선택).
     * 놓는 판정 기하는 그대로 둔다(끄는 동안 되먹임이 없게).
     */
    fun fitted(width: Double, height: Double, rows: Int): RummyRackGeometry {
        val natural = RummyRackGeometry.phone(width, rows)
        val plate = natural.plate ?: return natural
        if (natural.height <= height + 0.001) return natural
        val count = natural.rowCount
        val room = maxOf(1.0, height - plate.top * 2 - plate.rowGap * (count - 1))
        val factor = minOf(1.0, room / (natural.tileSize.height * count))
        val tile = RummyCanvasSize(natural.tile.width * factor, natural.tile.height * factor)
        val columns = natural.halfColumns / RummyRackLayout.tileSpan
        val side = (width - tile.width * natural.tileScale * columns) / 2
        return RummyRackGeometry(tile, height, count, natural.halfColumns, RummyRackPlate(side, plate.top, plate.rowGap, plate.fullRows))
    }

    /** 받침대에서 맞는 덩어리 밑줄 띠 자리: 덩어리 가로(양끝 4 안쪽) · 타일 아랫단 5 위부터 11(줄 사이 틈이 좁아 밖에 따로 둘 자리가 없다). */
    fun meldBar(meld: RummyRackMeld, layout: RummyRackLayout, geometry: RummyRackGeometry): RummyCanvasRect? {
        val frames = meld.tileIDs.mapNotNull { id -> layout.slot(id)?.let(geometry::frame) }
        val first = frames.firstOrNull() ?: return null
        val last = frames.last()
        return RummyCanvasRect(first.x + 4, first.maxY - 5, last.maxX - first.x - 8, 11.0)
    }
}

// MARK: - 판에 그릴 값

/** 판에 그릴 것(묶음 · 배치) — 맥 RummyMatchView.board 와 같은 세 갈래: 내 차례 = 편집기, 남의 차례 = 그 사람 작업 판, 그 밖 = 확정 판. */
data class GamesRummyBoardScene(val melds: List<RummyBoardMeld>, val layout: RummyTableLayout) {
    val meldTileIDs: List<List<Int>> get() = melds.map { meld -> meld.tiles.mapNotNull { it.id } }
    val tileCount: Int get() = melds.sumOf { it.tiles.size }

    companion object {
        val empty = GamesRummyBoardScene(emptyList(), RummyTableLayout.empty)

        fun make(match: RummyMatchState?, editor: RummyTurnEditor?, isMyTurn: Boolean, otherDraft: List<List<RummyFace>>?): GamesRummyBoardScene {
            fun fallback(count: Int): RummyRect = RummyTableLayout.frame(RummyPoint(0, 0), count)
            if (isMyTurn && editor != null) {
                val layout = editor.tableLayout
                val melds = editor.melds.mapIndexed { index, meld ->
                    RummyBoardMeld(
                        id = "e${meld.firstOrNull()?.id ?: (-index - 1)}",
                        tiles = meld.map { RummyBoardTile(it.id, it.face, !editor.isFromTable(it.id)) },
                        frame = layout.frame(index) ?: fallback(meld.size),
                        invalid = !editor.analysis(index).valid,
                    )
                }
                return GamesRummyBoardScene(melds, layout)
            }
            if (otherDraft != null) {
                // 남의 작업 판 — 확정 판에 없던 면(다중집합 차)을 이번 차례에 낸 타일로 칠한다(표시 전용, 판정 아님).
                val layout = RummyTableLayout(sets = otherDraft, layout = match?.draft?.layout)
                val confirmed = HashMap<RummyFace, Int>()
                for (face in (match?.table ?: emptyList()).flatten()) confirmed[face] = (confirmed[face] ?: 0) + 1
                val keys = RummyBoardMeld.faceKeys(otherDraft)
                val melds = otherDraft.mapIndexed { index, set ->
                    val tiles = set.map { face ->
                        val left = confirmed[face] ?: 0
                        if (left > 0) confirmed[face] = left - 1
                        RummyBoardTile(null, face, left == 0)
                    }
                    RummyBoardMeld(keys[index], tiles, layout.frame(index) ?: fallback(set.size), !RummyRules.analyze(set).valid)
                }
                return GamesRummyBoardScene(melds, layout)
            }
            val table = match?.table ?: emptyList()
            val layout = RummyTableLayout(sets = table, layout = match?.tableLayout)
            val keys = RummyBoardMeld.faceKeys(table)
            val melds = table.mapIndexed { index, set ->
                RummyBoardMeld(
                    id = keys[index],
                    tiles = RummyRules.displayOrder(set).map { RummyBoardTile(null, it, false) },
                    frame = layout.frame(index) ?: fallback(set.size),
                    invalid = false,
                )
            }
            return GamesRummyBoardScene(melds, layout)
        }
    }
}

// MARK: - 누르기

/** 손이 처음 닿은 자리의 분류. */
sealed interface GamesRummyHit {
    data class RackTile(val id: Int) : GamesRummyHit

    data class BoardTile(val id: Int) : GamesRummyHit

    /** 묶음 왼쪽 손잡이(묶음 번호). */
    data class MeldHandle(val set: Int) : GamesRummyHit

    /** 빈 펠트 — 판 밀기. */
    data object Felt : GamesRummyHit

    /** 그 밖 — 무시. */
    data object None : GamesRummyHit
}

/** 끌기 시간 · 거리 · 들어 올림 값(설계서 §4 입력). */
object GamesRummyGestureRules {
    /** 이만큼 넘게 움직이면 **한 장** 끌기. */
    const val dragThreshold: Double = 8.0

    /** 그 안에서 이만큼 버티면 **묶음째**(밀리초). */
    const val liftDelayMillis: Long = 500L

    /** 집힌 타일은 손 위로 이만큼 — 손가락에 가리지 않게. */
    const val fingerLift: Double = 48.0
    const val liftScale: Double = 1.25

    /** 묶음 손잡이 터치 폭(타일 왼쪽 바깥). */
    const val handleTouchWidth: Double = 28.0

    /** 손의 자리 → 그린 자리 · 놓을 자리 계산의 기준점. */
    fun liftedPoint(finger: RummyCanvasPoint): RummyCanvasPoint = RummyCanvasPoint(finger.x, finger.y - fingerLift)
}

object GamesRummyHitTester {
    /**
     * [point] = 판 화면 좌표. [meldTileIDs] = 묶음별 타일 id(화면 순, 편집기). [editable] = 내 차례라 판 타일을 만질 수 있다 — 아니면 판은 전부 펠트다(밀어 보기만).
     * 받침대 빈칸은 None(받침대를 밀 일이 없다).
     */
    fun classify(
        point: RummyCanvasPoint,
        layout: GamesRummyMatchLayout,
        rack: RummyRackGeometry,
        rackLayout: RummyRackLayout,
        canvas: RummyCanvasTransform,
        table: RummyTableLayout,
        meldTileIDs: List<List<Int>>,
        editable: Boolean,
    ): GamesRummyHit {
        if (layout.rack.contains(point)) {
            val local = RummyCanvasPoint(point.x - layout.rack.x, point.y - layout.rack.y)
            for ((id, slot) in rackLayout.slots) if (rack.frame(slot).contains(local)) return GamesRummyHit.RackTile(id)
            return GamesRummyHit.None
        }
        if (!layout.table.contains(point)) return GamesRummyHit.None
        if (!editable) return GamesRummyHit.Felt
        val local = RummyCanvasPoint(point.x - layout.table.x, point.y - layout.table.y)
        // 타일이 손잡이보다 먼저다(옆 묶음의 손잡이 터치 폭이 앞 묶음 타일 위로 겹칠 수 있다).
        for (set in table.counts.indices) {
            val ids = meldTileIDs.getOrNull(set) ?: continue
            for (tile in 0 until table.counts[set]) {
                val frame = table.tileFrame(set, tile) ?: continue
                val id = ids.getOrNull(tile) ?: continue
                if (canvas.rect(frame).contains(local)) return GamesRummyHit.BoardTile(id)
            }
        }
        table.frames.forEachIndexed { set, frame ->
            val shown = canvas.rect(frame)
            val handle = RummyCanvasRect(shown.x - GamesRummyGestureRules.handleTouchWidth, shown.y, GamesRummyGestureRules.handleTouchWidth, shown.height)
            if (handle.contains(local)) return GamesRummyHit.MeldHandle(set)
        }
        return GamesRummyHit.Felt
    }
}

// MARK: - 손에 든 것

/** 어느 칸에서 집었나. */
enum class GamesRummySurface { rack, board }

data class GamesRummyDrag(
    val kind: Kind,
    val tiles: List<RummyTile>,
    val grabIndex: Int,
    val finger: RummyCanvasPoint,
    /** 손잡이 끌기: 잡은 자리 − 묶음 왼쪽 위(논리). */
    val grab: RummyCanvasPoint = RummyCanvasPoint(0.0, 0.0),
    val surface: GamesRummySurface,
) {
    sealed interface Kind {
        data object Tiles : Kind

        /** 손잡이로 묶음 위치 이동. */
        data class WholeMeld(val set: Int) : Kind
    }

    val ids: List<Int> get() = tiles.map { it.id }

    /** 그린 자리 = 재는 자리. 손 위 48. */
    val pointer: RummyCanvasPoint get() = GamesRummyGestureRules.liftedPoint(finger)
}

/** 꾹 눌러 들어 올린 것(아직 안 끎). */
data class GamesRummyLift(val tileID: Int, val ids: List<Int>, val surface: GamesRummySurface)

/** 받침대 위로 끄는 동안의 미리보기 — 같은 놓기를 편집기 사본에 해 본 받침대(= 실제). 이웃이 비켜 서고 점선이 놓일 자리다. */
data class GamesRummyRackPreview(
    val layout: RummyRackLayout,
    val ghosts: List<RummyRackSlot>,
    /** 놓은 뒤 받침대에서 그대로 맞는 덩어리(밑줄 띠). */
    val melds: List<RummyRackMeld>,
)

/** 놓은 결과 — 화면이 스토어로 옮긴다. */
sealed interface GamesRummyDropAction {
    data object None : GamesRummyDropAction

    data class MoveTiles(val ids: List<Int>, val target: RummyDropTarget) : GamesRummyDropAction

    data class MoveSet(val set: Int, val point: RummyPoint) : GamesRummyDropAction

    /** 판 출신을 받침대에 놓았다(R-14) — 놓지 않고 받침대를 잠깐 빨갛게. */
    data object Refused : GamesRummyDropAction
}

/** 판단 재료 한 벌. 화면이 본문에서 한 번 만들고, 보기([viewport])만 모델이 사건마다 채운다 — 본문이 보기를 읽으면 밀 때마다 화면 전체가 다시 돈다. */
data class GamesRummyTouchContext(
    val layout: GamesRummyMatchLayout,
    val viewport: GamesRummyViewport,
    val scene: GamesRummyBoardScene,
    val editor: RummyTurnEditor?,
    /** 내 차례이고 편집기가 있다(놓을 자리 판정 — 아니면 받침대 재배치만). */
    val isMyTurn: Boolean,
    /** 판 타일을 만질 수 있다(내 차례 · 요청 비행 중 아님). */
    val editable: Boolean,
) {
    val rack: RummyRackGeometry get() = layout.rackGeometry
    val rackLayout: RummyRackLayout get() = editor?.rackLayout ?: RummyRackLayout(RummyRackGeometry.phoneHalfColumns)

    fun hit(point: RummyCanvasPoint): GamesRummyHit = GamesRummyHitTester.classify(
        point, layout, rack, rackLayout, viewport.transform, scene.layout, scene.meldTileIDs, editable && editor != null,
    )

    fun with(viewport: GamesRummyViewport): GamesRummyTouchContext = copy(viewport = viewport)

    fun tile(id: Int): RummyTile? {
        val current = editor ?: return null
        return current.rack.firstOrNull { it.id == id } ?: current.melds.firstNotNullOfOrNull { meld -> meld.firstOrNull { it.id == id } }
    }

    /** 칸 좌표로 옮긴 판 안의 점. */
    fun inTable(point: RummyCanvasPoint): RummyCanvasPoint = RummyCanvasPoint(point.x - layout.table.x, point.y - layout.table.y)
}

// MARK: - 손 하나의 일생

/** 손이 닿아서 떨어질 때까지의 상태. 시간은 밖에서 민다([holdElapsed] — 시험이 0.5초를 기다리지 않게). */
class GamesRummyTouchMachine {
    sealed interface Phase {
        data object Idle : Phase

        /** 타일을 누르는 중. [picked] = 0.5초를 버텨 들어 올린 묶음. */
        data class Pressing(val tileID: Int, val surface: GamesRummySurface, val start: RummyCanvasPoint, val picked: List<Int>?) : Phase

        data class Handle(val set: Int, val start: RummyCanvasPoint) : Phase

        data class Panning(val last: RummyCanvasPoint) : Phase

        data class Dragging(val drag: GamesRummyDrag) : Phase

        /** 그 밖에서 시작했거나 핀치로 넘어갔다 — 손을 뗄 때까지 무시한다. */
        data object Ignoring : Phase
    }

    sealed interface Effect {
        data object None : Effect

        data class Pan(val dx: Double, val dy: Double) : Effect

        data object DragBegan : Effect

        data object DragMoved : Effect
    }

    var phase: Phase = Phase.Idle
        private set

    val isIdle: Boolean get() = phase == Phase.Idle

    /** 0.5초를 기다리는 중인가(아직 안 들어 올린 누름). */
    val isAwaitingHold: Boolean get() = (phase as? Phase.Pressing)?.picked == null && phase is Phase.Pressing

    /** 판 · 받침대를 쥐고 있다(판 변환 · 받침대 줄 수를 굳힐 때). */
    val holdsBoard: Boolean
        get() = when (phase) {
            is Phase.Pressing, is Phase.Handle, is Phase.Dragging -> true
            Phase.Idle, is Phase.Panning, Phase.Ignoring -> false
        }

    val drag: GamesRummyDrag? get() = (phase as? Phase.Dragging)?.drag

    fun down(point: RummyCanvasPoint, context: GamesRummyTouchContext) {
        phase = when (val hit = context.hit(point)) {
            is GamesRummyHit.RackTile -> Phase.Pressing(hit.id, GamesRummySurface.rack, point, null)
            is GamesRummyHit.BoardTile -> Phase.Pressing(hit.id, GamesRummySurface.board, point, null)
            is GamesRummyHit.MeldHandle -> Phase.Handle(hit.set, point)
            GamesRummyHit.Felt -> Phase.Panning(point)
            GamesRummyHit.None -> Phase.Ignoring
        }
    }

    fun move(point: RummyCanvasPoint, context: GamesRummyTouchContext): Effect = when (val current = phase) {
        Phase.Idle, Phase.Ignoring -> Effect.None
        is Phase.Panning -> {
            phase = Phase.Panning(point)
            val dx = point.x - current.last.x
            val dy = point.y - current.last.y
            if (dx == 0.0 && dy == 0.0) Effect.None else Effect.Pan(dx, dy)
        }
        is Phase.Pressing -> if (distance(point, current.start) <= GamesRummyGestureRules.dragThreshold) Effect.None else beginTiles(current, point, context)
        is Phase.Handle -> if (distance(point, current.start) <= GamesRummyGestureRules.dragThreshold) Effect.None else beginMeld(current, point, context)
        is Phase.Dragging -> {
            phase = Phase.Dragging(current.drag.copy(finger = point))
            Effect.DragMoved
        }
    }

    private fun beginTiles(pressing: Phase.Pressing, point: RummyCanvasPoint, context: GamesRummyTouchContext): Effect {
        val ids = pressing.picked ?: listOf(pressing.tileID)
        val tiles = ids.mapNotNull(context::tile)
        if (tiles.isEmpty()) {
            phase = Phase.Ignoring
            return Effect.None
        }
        val grab = ids.indexOf(pressing.tileID).coerceAtLeast(0)
        phase = Phase.Dragging(GamesRummyDrag(GamesRummyDrag.Kind.Tiles, tiles, grab, point, surface = pressing.surface))
        return Effect.DragBegan
    }

    private fun beginMeld(handle: Phase.Handle, point: RummyCanvasPoint, context: GamesRummyTouchContext): Effect {
        val editor = context.editor
        val frame = context.scene.layout.frame(handle.set)
        if (editor == null || handle.set !in editor.melds.indices || frame == null) {
            phase = Phase.Ignoring
            return Effect.None
        }
        val logical = context.viewport.transform.toLogical(context.inTable(handle.start))
        phase = Phase.Dragging(
            GamesRummyDrag(
                GamesRummyDrag.Kind.WholeMeld(handle.set),
                editor.melds[handle.set],
                0,
                point,
                RummyCanvasPoint(logical.x - frame.x.toDouble(), logical.y - frame.y.toDouble()),
                GamesRummySurface.board,
            ),
        )
        return Effect.DragBegan
    }

    /** 0.5초가 지났다. 아직 8 안에서 누르고 있으면 묶음째 집는다(받침대 = 이어진 덩어리 · 판 = 가까운 끝까지). 집었으면 그 값. */
    fun holdElapsed(context: GamesRummyTouchContext): GamesRummyLift? {
        val current = phase as? Phase.Pressing ?: return null
        if (current.picked != null) return null
        val editor = context.editor ?: return null
        val ids = if (current.surface == GamesRummySurface.rack) editor.rackChain(current.tileID) else editor.meldChunk(current.tileID)
        if (ids.isEmpty()) return null
        phase = current.copy(picked = ids)
        return GamesRummyLift(current.tileID, ids, current.surface)
    }

    /** 손을 뗐다 — 놓은 결과. */
    fun up(point: RummyCanvasPoint, context: GamesRummyTouchContext): GamesRummyDropAction {
        val current = phase
        phase = Phase.Idle
        if (current !is Phase.Dragging) return GamesRummyDropAction.None
        val drag = current.drag.copy(finger = point)
        return GamesRummyDropPlanner.action(drag, GamesRummyDropPlanner.target(drag, context), context.editor)
    }

    fun cancel() {
        phase = Phase.Idle
    }

    /** 판이 바뀌었는데 손가락은 아직 닿아 있다 — 뗄 때까지 무시한다(뗀 뒤 다음 손은 새로 분류된다). */
    fun ignoreUntilUp() {
        phase = Phase.Ignoring
    }

    /** 핀치가 시작됐다. 끌던 타일이 있으면 핀치를 안 받는다(거짓). 아니면 누르기 · 밀기를 거두고 손을 뗄 때까지 무시한다 — 핀치 중 한 손가락 끌기 금지. */
    fun beginPinch(): Boolean {
        if (phase is Phase.Dragging) return false
        phase = Phase.Ignoring
        return true
    }

    private fun distance(a: RummyCanvasPoint, b: RummyCanvasPoint): Double = hypot(a.x - b.x, a.y - b.y)
}

// MARK: - 놓기

object GamesRummyDropPlanner {
    /** 묶음 하나를 통째로 집었으면 그 묶음 번호. */
    fun wholeMeld(ids: List<Int>, editor: RummyTurnEditor?): Int? {
        val current = editor ?: return null
        val set = ids.toSet()
        return current.melds.indexOfFirst { meld -> meld.map { it.id }.toSet() == set }.takeIf { it >= 0 }
    }

    /** 지금 놓으면 어디로 가는가. 받침대 위 = 자리 · 묶음 위 = 끼울 번호 · 빈 펠트 = 새 묶음 · 그 밖 = null. */
    fun target(drag: GamesRummyDrag, context: GamesRummyTouchContext): RummyDropTarget? = when (val kind = drag.kind) {
        is GamesRummyDrag.Kind.WholeMeld -> {
            val count = context.scene.layout.counts.getOrNull(kind.set) ?: drag.tiles.size
            RummyDropResolver.setTarget(drag.pointer, drag.grab, count, context.layout.regions, context.viewport.transform)
                ?.let { RummyDropTarget.NewMeldAt(it) }
        }
        GamesRummyDrag.Kind.Tiles -> RummyDropResolver.target(
            pointer = drag.pointer,
            grabIndex = drag.grabIndex,
            count = drag.tiles.size,
            layout = context.layout.regions,
            canvas = context.viewport.transform,
            table = context.scene.layout,
            rack = context.rack,
            isMyTurn = context.isMyTurn,
            skipMeld = wholeMeld(drag.ids, context.editor),
        )
    }

    /** 판 타일을 받침대 위로 끄는 중 — 놓기 거절 표시(R-14). */
    fun refused(drag: GamesRummyDrag, target: RummyDropTarget?, editor: RummyTurnEditor?): Boolean {
        if (target == null || editor == null || !RummyStore.isRackTarget(target)) return false
        return drag.ids.any(editor::isFromTable)
    }

    /** 놓은 결과(맥 tileEnded 와 같은 갈래). */
    fun action(drag: GamesRummyDrag, target: RummyDropTarget?, editor: RummyTurnEditor?): GamesRummyDropAction {
        if (target == null || editor == null) return GamesRummyDropAction.None
        val kind = drag.kind
        if (kind is GamesRummyDrag.Kind.WholeMeld) {
            return if (target is RummyDropTarget.NewMeldAt) GamesRummyDropAction.MoveSet(kind.set, target.point) else GamesRummyDropAction.None
        }
        if (refused(drag, target, editor)) return GamesRummyDropAction.Refused
        if (target is RummyDropTarget.NewMeldAt) {
            wholeMeld(drag.ids, editor)?.let { return GamesRummyDropAction.MoveSet(it, target.point) }
        }
        return GamesRummyDropAction.MoveTiles(drag.ids, target)
    }

    /**
     * 놓기 미리보기 — 편집기에 "놓으면 어떻게 되는가"를 묻는다(바꾸지 않는다). 놓을 때 부르는 길과 **같은 갈래**:
     * 손잡이 끌기 · 묶음 통째를 빈 곳에 = previewMoveSet, 나머지 = previewDrop. 받침대행 · 거절 · 남의 차례는 null.
     */
    fun boardPreview(drag: GamesRummyDrag, target: RummyDropTarget?, context: GamesRummyTouchContext): RummyBoardPreview? {
        val editor = context.editor
        if (!context.isMyTurn || editor == null || target == null || RummyStore.isRackTarget(target)) return null
        val ids = editor.melds.map { meld -> meld.map { it.id } }
        val frames = context.scene.layout.frames
        val dragged = drag.ids.toSet()
        fun moveSet(index: Int, point: RummyPoint): RummyBoardPreview? {
            if (index !in editor.melds.indices) return null
            return RummyBoardPreview.make(editor.previewMoveSet(index, point), editor.melds[index].size, ids, frames, dragged)
        }
        val kind = drag.kind
        if (kind is GamesRummyDrag.Kind.WholeMeld) {
            return if (target is RummyDropTarget.NewMeldAt) moveSet(kind.set, target.point) else null
        }
        if (target is RummyDropTarget.NewMeldAt) {
            wholeMeld(drag.ids, editor)?.let { return moveSet(it, target.point) }
        }
        val preview = RummyBoardPreview.make(editor.previewDrop(drag.ids, target), drag.ids.size, ids, frames, dragged) ?: return null
        val set = preview.targetSet
        if (editor.initialDone || set == null || set !in editor.melds.indices) return preview
        return preview.beforeInitial(editor.melds[set].any { editor.isFromTable(it.id) })
    }

    /** 받침대 미리보기(거절이면 null). 같은 놓기를 사본에 해 본다. */
    fun rackPreview(drag: GamesRummyDrag, target: RummyDropTarget?, editor: RummyTurnEditor?): GamesRummyRackPreview? {
        if (target !is RummyDropTarget.RackSlot || editor == null || refused(drag, target, editor)) return null
        val copy = editor.copy()
        if (!copy.moveBlock(drag.ids, target)) return null
        val after = copy.rackLayout
        return GamesRummyRackPreview(after, drag.ids.mapNotNull(after::slot), copy.rackMelds)
    }
}

// MARK: - 집힌 타일 자리

object GamesRummyFloatingLayout {
    /** 그릴 타일 크기(들어 올림 배율 전): 손잡이 끌기는 판 크기, 나머지는 판 위면 판 크기 · 그 밖이면 받침대 크기. */
    fun tileSize(drag: GamesRummyDrag, context: GamesRummyTouchContext): RummyCanvasSize {
        if (drag.kind is GamesRummyDrag.Kind.WholeMeld) return context.viewport.tileSize
        return if (context.layout.table.contains(drag.pointer)) context.viewport.tileSize else context.rack.tileSize
    }

    /** 손에 든 타일들의 화면 자리(판 화면 좌표). **기준점 drag.pointer 를 중심으로 키운다** — [liftScale] 을 1 로 두면 그 왼쪽 위가 곧 놓을 자리다. */
    fun frames(
        drag: GamesRummyDrag,
        tile: RummyCanvasSize,
        tableScale: Double,
        liftScale: Double = GamesRummyGestureRules.liftScale,
    ): List<RummyCanvasRect> {
        val width = tile.width * liftScale
        val height = tile.height * liftScale
        val origin = when (drag.kind) {
            GamesRummyDrag.Kind.Tiles -> RummyCanvasPoint(drag.pointer.x - (drag.grabIndex + 0.5) * width, drag.pointer.y - height / 2)
            is GamesRummyDrag.Kind.WholeMeld -> RummyCanvasPoint(drag.pointer.x - drag.grab.x * tableScale * liftScale, drag.pointer.y - drag.grab.y * tableScale * liftScale)
        }
        return drag.tiles.indices.map { index -> RummyCanvasRect(origin.x + index * width, origin.y, width, height) }
    }
}

// MARK: - 자리 · 상태 줄

/** 자리 하나에 붙는 표시. **서버가 말한 것만** — 남의 패는 장수뿐이다(추측 표시 금지). */
sealed interface GamesRummySeatTag {
    val text: String

    data object Forfeit : GamesRummySeatTag {
        override val text: String get() = RummyPhoneText.forfeit
    }

    /** 판이 시작될 때 90초 넘게 안 보여 빠진 자리(dropped) · 나간 자리(left). 판 중 끊김 기권은 서버 state 에 사유가 안 실려 Forfeit 으로 보인다. */
    data object Disconnected : GamesRummySeatTag {
        override val text: String get() = GamesRummyMatchText.disconnectedTag
    }

    data object BeforeInitial : GamesRummySeatTag {
        override val text: String get() = RummyPhoneText.beforeInitial
    }

    data class Timeouts(val streak: Long) : GamesRummySeatTag {
        override val text: String get() = RummyPhoneText.timeouts(streak)
    }
}

object GamesRummySeats {
    /** 상대 줄 — 내 다음 차례부터. 자리 번호 없는 사람(초대만 받은 사람)은 판에 없다. */
    fun opponents(match: RummyMatchState): List<RummyMatchSeat> {
        val seats = (match.seats ?: emptyList()).filter { it.seatNo != null }
        val order = RummySeatArrangement.arrange(seats.mapNotNull { it.seatNo }, match.mySeatNo).ordered
        return order.mapNotNull { number -> seats.firstOrNull { it.seatNo == number } }
    }

    fun mine(match: RummyMatchState): RummyMatchSeat? {
        val mine = match.mySeatNo ?: return null
        return match.seats?.firstOrNull { it.seatNo == mine }
    }

    fun turnSeat(match: RummyMatchState): RummyMatchSeat? {
        val turn = match.turnSeatNo ?: return null
        return match.seats?.firstOrNull { it.seatNo == turn }
    }

    fun isTurn(seat: RummyMatchSeat, match: RummyMatchState): Boolean =
        seat.seatNo == match.turnSeatNo && seat.state == RummySeatState.playing && match.status == RummyMatchStatus.active

    fun isGone(seat: RummyMatchSeat): Boolean =
        seat.state == RummySeatState.forfeit || seat.state == RummySeatState.dropped || seat.state == RummySeatState.left

    fun tags(seat: RummyMatchSeat): List<GamesRummySeatTag> {
        when (seat.state) {
            RummySeatState.forfeit -> return listOf(GamesRummySeatTag.Forfeit)
            RummySeatState.dropped, RummySeatState.left -> return listOf(GamesRummySeatTag.Disconnected)
            else -> Unit
        }
        val tags = ArrayList<GamesRummySeatTag>()
        val streak = seat.timeoutStreak
        if (streak != null && streak > 0) tags.add(GamesRummySeatTag.Timeouts(streak))
        if (seat.initialDone == false) tags.add(GamesRummySeatTag.BeforeInitial)
        return tags
    }

    /** 이번 차례 전체 시간(초). */
    fun turnTotal(match: RummyMatchState): Double {
        val start = match.turnStartedMs
        val end = match.turnDeadlineMs
        return if (start == null || end == null || end <= start) 60.0 else (end - start) / 1000
    }
}

/** 남은 시간 색 문턱(링 · 초 · [완료] 안 초가 같은 값을 쓴다): 10초 이하 주황 · 5초 이하 빨강. */
enum class GamesRummyCountdownTone {
    normal, warning, danger;

    companion object {
        fun of(remaining: Double): GamesRummyCountdownTone = when {
            remaining <= 5 -> danger
            remaining <= 10 -> warning
            else -> normal
        }
    }
}

/** 상태 줄 한 줄 — 서버 · 판정 문구는 스토어 notice, 내 차례 글자는 myTurnStatus(첫 등록 진행 · [완료]가 꺼진 이유). 맥 statusText 와 같은 서열. */
data class GamesRummyStatusLine(val text: String, val tone: Tone) {
    enum class Tone { notice, ready, plain, quiet }

    companion object {
        fun make(notice: String?, isMyTurn: Boolean, editor: RummyTurnEditor?, turnName: String?, mySeatState: RummySeatState?): GamesRummyStatusLine {
            if (notice != null) return GamesRummyStatusLine(notice, Tone.notice)
            if (isMyTurn && editor != null) {
                return GamesRummyStatusLine(RummyPhoneText.myTurnStatus(editor), if (editor.canSubmit) Tone.ready else Tone.plain)
            }
            if (mySeatState == RummySeatState.forfeit) return GamesRummyStatusLine(GamesRummyMatchText.spectating, Tone.quiet)
            if (turnName != null) return GamesRummyStatusLine(RummyPhoneText.turnOf(turnName), Tone.quiet)
            return GamesRummyStatusLine("", Tone.quiet)
        }
    }
}

/** 판 화면이 더 쓰는 글자(문구 표 RummyPhoneText 의 짝 — 이 갈래 몫). */
object GamesRummyMatchText {
    const val disconnectedTag: String = "끊김"
    const val spectating: String = "기권한 판을 보고 있어요"
    const val leaveDescription: String = "나가기. 판 중이면 기권돼요."
    const val sortNumberName: String = "같은 숫자끼리 정렬"
    const val sortColorName: String = "색별로 이어지게 정렬"
    const val turnWord: String = "차례"

    fun boardSummary(melds: Int, tiles: Int): String = "판 묶음 ${melds}개, 타일 ${tiles}장"

    fun rackSummary(count: Int): String = "내 받침대 ${count}장"

    fun seatSummary(name: String, count: Long?, isTurn: Boolean, tags: List<String>): String =
        (listOf(name, RummyPhoneText.rackCount(count)) + (if (isTurn) listOf(turnWord) else emptyList()) + tags).joinToString(", ")

    fun remaining(seconds: Int): String = "남은 시간 ${seconds}초"
}
