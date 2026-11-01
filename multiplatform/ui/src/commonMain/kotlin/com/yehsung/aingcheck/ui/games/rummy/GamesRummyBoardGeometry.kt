// 원본: Sources/CheckMobileKit/Games/GamesRummyBoardGeometry.swift:1 · Sources/CheckMobileKit/Games/GamesRummyMatchInput.swift:1 @ ios-1017-cube d5c9eeff · 맥 동작은 Sources/check/RummyPanelMatch.swift:490-720 @ 1a5eeca6 · 설계서 §10
//
// 폰 아잉 큐브 판 화면의 **순수 값** — Compose 를 모른다. 그리는 자리 · 누르는 자리 · 놓는 자리가 전부 이 값에서 나온다(맥과 같은 원칙 · 배치는 폰 가로 화면용).
// 좌표는 판 화면 왼쪽 위 원점의 dp 다(값은 Double — 코어 RummyCanvasPoint·RummyCanvasRect). 화면이 px 를 dp 로 바꿔 넘긴다.
//
//   · [GamesRummyMatchLayout] — 칸 사각형(왼쪽 열 | 가운데 판 · 상태 줄 · 받침대 | 오른쪽 열).
//   · [GamesRummyViewport] — 판 보기(배율 · 오프셋 · 클램프 · 전체 맞춤 · 자동 밀기 · 화면 밖 묶음 수). 배율은 **사람이 움직일 때만** 바뀐다(맥 교훈 — 놓을 때마다 판이 움직이면 안 된다).
//   · [GamesRummyRackGeometry] — 받침대 frame ↔ slot(한 줄 16장 · 맥과 같은 반 칸 32). 놓기 판정기(코어 RummyDropResolver)가 인터페이스로 받는다.
//   · [GamesRummyHitTester] — 손이 처음 닿은 자리의 분류. 타일마다 제스처를 달지 않는다(판 타일 100장에서 무겁고 판 밀기와 충돌한다).
//   · [GamesRummyTouchMachine] — 손 하나의 일생(8 넘게 움직이면 한 장 · 8 안에서 0.5초면 묶음째 · 손잡이 · 빈 펠트 밀기 · 핀치 뒤 무시).
//   · [GamesRummyDropPlanner] — 놓을 자리 · 미리보기 · 놓은 결과. 맥 resolve · boardPreview · tileEnded 와 같은 갈래다. 판정은 코어 RummyDropResolver · 편집기가 한다.
//   · [GamesRummyFloatingLayout] — 집힌 타일 자리. **그린 자리와 재는 자리가 같다**: 손 위 점(GamesRummyDrag.pointer — 판 위에서 48)이 놓기 기준이고 그림도 그 점에 선다.
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
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
import com.yehsung.aingcheck.core.rules.rummy.RummyRackDropGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyRackMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRect
import com.yehsung.aingcheck.core.rules.rummy.RummyRules
import com.yehsung.aingcheck.core.rules.rummy.RummySeatArrangement
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTile
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.rules.rummy.rackMelds
import com.yehsung.aingcheck.core.stores.rummy.RummyEditorKey
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

/**
 * 판 화면 칸 자리(가로 화면 · 시스템 막대 · 컷아웃 안 좌표, 설계서 §10.2) — 왼쪽 열(뒤로 · 규칙 · 자리 카드) | 가운데(판 · 상태 줄 · 받침대) | 오른쪽 열(판돈 · 더미 · 반응 · 전체 보기 · 동작 버튼).
 * **받침대 높이는 줄 수로 안 변한다** — 판 칸이 안 흔들린다(줄이 늘면 타일이 준다).
 */
data class GamesRummyMatchLayout(
    val size: RummyCanvasSize,
    private val requestedRackRows: Int = RummyRackLayout.baseRows,
) {
    val rackRows: Int = maxOf(RummyRackLayout.baseRows, requestedRackRows)

    // 가운데

    private val centerWidth: Double = maxOf(0.0, size.width - leftColumnWidth - rightColumnWidth)
    val rackHeight: Double = GamesRummyRackGeometry.height(centerWidth, size.height * rackMaxHeightShare)
    val rack: RummyCanvasRect = RummyCanvasRect(leftColumnWidth, size.height - rackHeight, centerWidth, rackHeight)
    val status: RummyCanvasRect = RummyCanvasRect(leftColumnWidth, rack.y - statusHeight, centerWidth, statusHeight)

    /** 판 — 가운데의 남는 높이 전부. */
    val table: RummyCanvasRect = RummyCanvasRect(leftColumnWidth, 0.0, centerWidth, maxOf(0.0, status.y))

    /** 놓기 판정기가 보는 칸 둘. */
    val regions: RummyMatchRegions get() = RummyMatchRegions(rack, table)

    // 왼쪽 열

    val leftColumn: RummyCanvasRect = RummyCanvasRect(0.0, 0.0, leftColumnWidth, size.height)

    /** [나가기] · [규칙] 줄. 터치 자리가 모자라지 않게 열 안쪽 여백 없이 열 폭을 다 쓴다. */
    val nav: RummyCanvasRect = RummyCanvasRect(0.0, 0.0, leftColumnWidth, navHeight)

    /** [나가기] · [규칙] 버튼 하나의 터치 자리. */
    val navButton: RummyCanvasSize = RummyCanvasSize((nav.width - navGap) / 2, nav.height)
    private val seatCardWidth: Double = leftColumnWidth - columnPadding * 2

    private val seatCardHeight: Double = run {
        val slots = (maxOpponentCards + 1).toDouble()
        val room = size.height - nav.maxY - columnPadding - seatCardGap * slots
        maxOf(0.0, minOf(seatCardMaxHeight, room / slots))
    }

    /** 자리 카드가 글자 세 줄 + 온 얼굴을 못 담는 낮은 칸이다. */
    val isSeatCardCompact: Boolean = seatCardHeight < seatCardFullContentHeight

    /** 상대 카드 [index] 번째(내 다음 차례부터 위에서 아래로). */
    fun opponentCard(index: Int): RummyCanvasRect {
        val top = nav.maxY + seatCardGap + maxOf(0, index).toDouble() * (seatCardHeight + seatCardGap)
        return RummyCanvasRect(columnPadding, top, seatCardWidth, seatCardHeight)
    }

    /** 내 자리 카드 — 왼쪽 열 맨 아래(몇 명이 앉든 같은 자리). */
    val mySeatCard: RummyCanvasRect = RummyCanvasRect(columnPadding, size.height - columnPadding - seatCardHeight, seatCardWidth, seatCardHeight)

    // 오른쪽 열

    val rightColumn: RummyCanvasRect = RummyCanvasRect(size.width - rightColumnWidth, 0.0, rightColumnWidth, size.height)
    val info: RummyCanvasRect = RummyCanvasRect(rightColumn.x + columnPadding, columnPadding, rightColumnWidth - columnPadding * 2, infoHeight)
    val tools: RummyCanvasRect = RummyCanvasRect(info.x, info.maxY + actionGap, info.width, toolsHeight)

    private val actionsTop: Double = tools.maxY + actionGap
    private val actionRoom: Double = maxOf(0.0, size.height - columnPadding - actionsTop - actionGap * 3)

    /** 비율대로면 44 아래로 내려가는 낮은 칸(시스템 '화면 확대')은 모두 44 를 먼저 주고 남는 높이를 비율로 나눈다. 넷 다 44 가 안 되는 높이에서는 비율대로다. */
    private fun actionHeight(share: Double): Double {
        val spare = actionRoom - minActionHeight * 4
        return if (actionRoom * sortShare >= minActionHeight || spare < 0) actionRoom * share else minActionHeight + spare * share
    }

    /** 버튼 넷 칸(위에서 아래로). 어떤 높이에서도 합이 열을 안 넘는다. */
    val submit: RummyCanvasRect = RummyCanvasRect(info.x, actionsTop, info.width, actionHeight(submitShare))
    val draw: RummyCanvasRect = RummyCanvasRect(info.x, submit.maxY + actionGap, info.width, actionHeight(drawShare))
    val undo: RummyCanvasRect = RummyCanvasRect(info.x, draw.maxY + actionGap, info.width, actionHeight(undoShare))
    val sort: RummyCanvasRect = RummyCanvasRect(info.x, undo.maxY + actionGap, info.width, actionHeight(sortShare))

    /** [777] · [789] 버튼 하나의 터치 자리(안쪽 여백 없이 칸을 반씩 쓴다). */
    val sortButton: RummyCanvasSize = RummyCanvasSize((sort.width - sortDividerWidth) / 2, sort.height)

    /** 받침대 기하(받침대 칸 왼쪽 위 원점). */
    val rackGeometry: GamesRummyRackGeometry get() = GamesRummyRackGeometry(RummyCanvasSize(rack.width, rack.height), rackRows)

    // 들어 올림 — 받침대가 화면 맨 아래다

    /**
     * 손 자리 → 들어 올릴 거리. 판 위에서는 늘 48. 받침대 안에서는 아래로 갈수록 준다: 가로 화면은 받침대 아래에 아무것도 없어서, 48 그대로면 아랫줄에 놓을 손 자리가 화면 끝 몇 dp 뿐이다.
     * 손 y 가 커질수록 기준점 y 도 늘 커진다(뒤집히지 않는다).
     */
    fun fingerLift(y: Double): Double {
        val full = GamesRummyGestureRules.fingerLift
        val low = GamesRummyGestureRules.fingerLiftAtBottom
        if (y <= rack.y || rack.height <= 0) return full
        return full + (low - full) * minOf(1.0, (y - rack.y) / rack.height)
    }

    /** 기준점이 [pointer] 에 오는 손 자리([fingerLift] 의 역). 궤적을 세우는 시험이 쓴다. */
    fun finger(pointer: RummyCanvasPoint): RummyCanvasPoint {
        val full = GamesRummyGestureRules.fingerLift
        val low = GamesRummyGestureRules.fingerLiftAtBottom
        if (pointer.y + full <= rack.y || rack.height <= 0) return RummyCanvasPoint(pointer.x, pointer.y + full)
        val progress = (pointer.y + full - rack.y) / (rack.height + full - low)
        if (progress >= 1) return RummyCanvasPoint(pointer.x, pointer.y + low)
        return RummyCanvasPoint(pointer.x, rack.y + progress * rack.height)
    }

    companion object {
        /** 왼쪽 열 — [나가기] · [규칙]이 각 44 로 든다([navButton]). */
        const val leftColumnWidth: Double = 90.0
        const val rightColumnWidth: Double = 100.0
        const val statusHeight: Double = 18.0

        /** 받침대 높이 상한(화면 높이 비율) — 판 칸이 먼저 살아야 한다. */
        const val rackMaxHeightShare: Double = 0.4

        /** 열 안쪽 여백. */
        const val columnPadding: Double = 4.0

        /** 오른쪽 열 칸 사이 틈. */
        const val actionGap: Double = 6.0

        /** 왼쪽 열 [뒤로] · [규칙] 줄 높이. */
        const val navHeight: Double = 44.0

        /** 오른쪽 열 판돈 · 더미 높이. */
        const val infoHeight: Double = 40.0

        /** 오른쪽 열 [반응] · [전체 보기] 줄 높이. */
        const val toolsHeight: Double = 44.0

        /** 왼쪽 열 원형 버튼 지름(그림). 터치 자리는 [navButton] 이다. */
        const val navButtonDiameter: Double = 38.0

        /** [나가기] · [규칙] 사이 틈. */
        const val navGap: Double = 2.0

        /** [777] · [789] 사이 구분선 폭. */
        const val sortDividerWidth: Double = 0.8

        /** 상대 카드 최대 수(4인 판). 내 자리까지 네 칸을 늘 같은 높이로 나눈다 — 인원에 따라 카드가 안 늘어난다. */
        const val maxOpponentCards: Int = 3
        const val seatCardMaxHeight: Double = 76.0

        /** 카드 글자 세 줄 + 얼굴의 높이. 칸이 이보다 낮으면(시스템 '화면 확대') 얼굴을 줄여 태그 줄이 카드 밖으로 안 나가게 한다([isSeatCardCompact]). */
        const val seatCardFullContentHeight: Double = 66.0
        const val seatCardGap: Double = 4.0

        /** 동작 버튼 넷이 남는 높이를 나누는 비율. */
        const val submitShare: Double = 0.34
        const val drawShare: Double = 0.24
        const val undoShare: Double = 0.22
        const val sortShare: Double = 0.20

        /** 다른 기기 안내 카드의 판 아래 여백 · 어림 높이(배지를 그 위로 올린다). */
        const val elsewhereCardBottom: Double = 6.0
        const val elsewhereCardHeight: Double = 60.0

        /** 동작 버튼 최소 높이(터치). */
        const val minActionHeight: Double = 44.0

        /** 가로로 선 크기인가. 방향 전환 중에는 세로 크기로 한 프레임 불릴 수 있다 — 그때 칸을 세우지 않는다. */
        fun isLandscape(size: RummyCanvasSize): Boolean = size.width > size.height

        /** 세 열이 앉는 폭. 큰 화면은 시스템이 방향 요청을 무시하기도 해서(Android 16 · 멀티 윈도) 세로로 서도 칸을 세운다 — 판을 영영 못 보면 시간 초과로 기권된다. */
        const val minPortraitBoardWidth: Double = 600.0

        /** 이 크기에 판을 그려도 되는가. 아니면 안내만 그린다. */
        fun canStand(size: RummyCanvasSize): Boolean = isLandscape(size) || size.width >= minPortraitBoardWidth
    }
}

// MARK: - 보기

/**
 * 판 보기(배율 · 오프셋). 값이고 움직이면 새 값을 돌려준다.
 *
 * 기본 보기는 **폭 맞춤**이다(캔버스 1000 이 칸 폭에 꼭 찬다). 나머지 세로는 민다. [전체 보기] = 높이까지 맞춘 배율.
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

    /**
     * 칸 크기가 바뀌었다(기기 방향 · 인셋). 기본 · 맞춤 보기였으면 새 칸의 기본 · 맞춤으로, 사람이 고른 배율이면 그대로(범위 안으로만).
     * 기본을 먼저 묻는다: 전환 중 세로 칸에서는 기본 = 맞춤이라, 맞춤을 먼저 물으면 기본 보기가 돌아온 뒤 전체 보기가 된다.
     */
    fun resized(to: RummyCanvasSize): GamesRummyViewport {
        if (to == viewport) return this
        val wasDefault = abs(scale - defaultScale) < 0.0005
        val wasFull = isFullView
        val base = GamesRummyViewport(to, scale, origin)
        val next = when {
            wasDefault -> base.defaultScale
            wasFull -> base.fitScale
            else -> minOf(maxScale, maxOf(base.fitScale, scale))
        }
        return base.clamped(next, origin)
    }

    /** 칸 좌표 [pointer] 에서 자동 밀기가 정말 움직이는가. 더 못 미는 쪽이면 거짓 — 화면이 프레임을 돌리지 않게. 경계는 가장자리가 아니다. */
    fun edgeMoves(pointer: RummyCanvasPoint): Boolean = edgePanned(pointer, 1.0 / 60.0) != this

    /** 끌기 중 가장자리 자동 밀기 한 걸음. 가로 · 세로를 따로 민다(기본 보기는 세로로 · 키우면 가로로도 움직인다 · 동작 줄이기여도 켠다 — 꾸밈이 아니라 끌기 기능이다). 안 움직였으면 같은 값. */
    fun edgePanned(pointer: RummyCanvasPoint, deltaSeconds: Double): GamesRummyViewport {
        val step = edgePanSpeed * deltaSeconds
        var x = origin.x
        var y = origin.y
        if (pointer.x < edgeZone) x -= step else if (pointer.x > viewport.width - edgeZone) x += step
        if (pointer.y < edgeZone) y -= step else if (pointer.y > viewport.height - edgeZone) y += step
        if (x == origin.x && y == origin.y) return this
        return clamped(scale, RummyCanvasPoint(x, y))
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

    /** 위 · 아래로 가려진 묶음 수(기본 보기는 칸이 캔버스보다 낮아 늘 쓰인다). 가로로 이미 화면 밖인 묶음은 좌우 배지가 센다 — 두 번 세지 않는다. */
    fun offscreenVerticalCounts(frames: List<RummyRect>): GamesRummyOffscreenVerticalCounts {
        val visible = visibleLogical
        var up = 0
        var down = 0
        for (frame in frames) {
            if (frame.maxX.toDouble() <= visible.x || frame.x.toDouble() >= visible.maxX) continue
            if (frame.maxY.toDouble() <= visible.y) {
                up += 1
            } else if (frame.y.toDouble() >= visible.maxY) {
                down += 1
            }
        }
        return GamesRummyOffscreenVerticalCounts(up, down)
    }

    /** 배지를 눌렀다 — 그 쪽에서 가장 가까운 화면 밖 묶음이 여백을 두고 보이도록 민다. 밀 것이 없으면 그대로. */
    fun revealed(side: GamesRummySide, frames: List<RummyRect>): GamesRummyViewport {
        val visible = visibleLogical
        return when (side) {
            GamesRummySide.left -> {
                val nearest = frames.filter { it.maxX.toDouble() <= visible.x }.maxByOrNull { it.maxX } ?: return this
                clamped(scale, RummyCanvasPoint(nearest.x.toDouble() - revealMargin, origin.y))
            }
            GamesRummySide.right -> {
                val nearest = frames.filter { it.x.toDouble() >= visible.maxX }.minByOrNull { it.x } ?: return this
                clamped(scale, RummyCanvasPoint(nearest.maxX.toDouble() + revealMargin - visible.width, origin.y))
            }
            GamesRummySide.up -> {
                val nearest = frames.filter { it.maxY.toDouble() <= visible.y }.maxByOrNull { it.maxY } ?: return this
                clamped(scale, RummyCanvasPoint(origin.x, nearest.y.toDouble() - revealMargin))
            }
            GamesRummySide.down -> {
                val nearest = frames.filter { it.y.toDouble() >= visible.maxY }.minByOrNull { it.y } ?: return this
                clamped(scale, RummyCanvasPoint(origin.x, nearest.maxY.toDouble() + revealMargin - visible.height))
            }
        }
    }

    /** 밀기 모션의 한 장면 — 배율은 같고 오프셋만 [target] 쪽으로. [progress] 0…1. */
    fun interpolated(target: GamesRummyViewport, progress: Double): GamesRummyViewport =
        clamped(scale, RummyCanvasPoint(origin.x + (target.origin.x - origin.x) * progress, origin.y + (target.origin.y - origin.y) * progress))

    /**
     * 왼쪽 끝은 손잡이 터치 폭만큼 더 민다 — 손잡이는 묶음 **왼쪽 바깥**이라 캔버스 왼끝(x 0) 묶음은 그래야 닿는다. 기본 보기(폭 맞춤)도 이만큼은 민다.
     * 전체 맞춤은 칸 폭이 남아 캔버스 양옆에 이미 그 자리가 있다. 폭 맞춤은 부동소수 오차로 양쪽을 오간다 — 0.5 단위 넘게 남을 때만 '칸이 더 넓다'로 친다.
     */
    private fun clamped(nextScale: Double, wanted: RummyCanvasPoint): GamesRummyViewport {
        val visibleW = viewport.width / nextScale
        val visibleH = viewport.height / nextScale
        val leftEnd = -GamesRummyGestureRules.handleTouchWidth / nextScale
        val x = if (visibleW > canvas.width + 0.5) 0.0 else minOf(maxOf(wanted.x, leftEnd), maxOf(0.0, canvas.width - visibleW))
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

        /** 기본 보기 배율(폭 맞춤). */
        fun defaultScale(viewport: RummyCanvasSize): Double = minOf(maxScale, maxOf(fitScale(viewport), viewport.width / canvas.width))

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

/** 좌우 화면 밖 묶음 수. */
data class GamesRummyOffscreenCounts(val left: Int, val right: Int)

/** 위아래 화면 밖 묶음 수. */
data class GamesRummyOffscreenVerticalCounts(val up: Int, val down: Int)

/** 판 왼쪽 · 오른쪽 · 위 · 아래. */
enum class GamesRummySide { left, right, up, down }

// MARK: - 받침대

/**
 * 받침대 기하(받침대 칸 왼쪽 위 원점) — **한 줄 16장**(맥과 같은 반 칸 32) · 반 칸 격자. 그리는 자리([frame])와 놓는 자리([slot])가 한 산식이다.
 * 칸 높이는 줄 수로 안 변한다. 3줄부터는 맥 tileScale 산식(2/줄)으로 타일이 줄어 담긴다. 그림 기준선을 쓰는 코어 RummyRackGeometry 와 달리 폭이 다른 기기에 맞춰 값으로 잰다.
 */
data class GamesRummyRackGeometry(val size: RummyCanvasSize, private val requestedRowCount: Int = RummyRackLayout.baseRows) : RummyRackDropGeometry {
    val rowCount: Int = maxOf(RummyRackLayout.baseRows, requestedRowCount)

    /** 줄이 넘치면 타일을 줄인다(받침대 안 스크롤은 쓰지 않는다 — 맥 tileScale 과 같은 산식). */
    val tileScale: Double get() = if (rowCount <= RummyRackLayout.baseRows) 1.0 else RummyRackLayout.baseRows.toDouble() / rowCount.toDouble()

    /** 칸 안에 담긴다: 폭으로 한 번 · 높이로 한 번 자른다. */
    val tileSize: RummyCanvasSize
        get() {
            val rows = rowCount.toDouble()
            val heightRoom = maxOf(1.0, (size.height - verticalPadding * 2 - minRowGap * (rows - 1)) / rows)
            val width = minOf(baseTileWidth(size.width) * tileScale, heightRoom / tileAspect)
            return RummyCanvasSize(width, width * tileAspect)
        }

    override val dropTileWidth: Double get() = tileSize.width
    val sideInset: Double get() = maxOf(minSideInset, (size.width - tileSize.width * perRow) / 2)
    val halfPitch: Double get() = tileSize.width / RummyRackLayout.tileSpan.toDouble()

    /** 줄 위쪽. 줄 사이 틈은 남는 높이에서 나오되 [rowGap] 을 안 넘고, 묶음째 칸 세로 가운데에 선다(줄이 넘쳐 타일이 줄어도 틈만 벌어지지 않게). */
    fun rowTop(row: Int): Double {
        val rows = rowCount.toDouble()
        val tile = tileSize.height
        val gap = if (rowCount <= 1) 0.0 else minOf(rowGap, maxOf(0.0, (size.height - verticalPadding * 2 - tile * rows) / (rows - 1)))
        val top = maxOf(verticalPadding, (size.height - tile * rows - gap * (rows - 1)) / 2)
        return top + row.toDouble() * (tile + gap)
    }

    fun rowCenter(row: Int): Double = rowTop(row) + tileSize.height / 2

    fun frame(slot: RummyRackSlot): RummyCanvasRect =
        RummyCanvasRect(sideInset + slot.halfCol.toDouble() * halfPitch, rowTop(slot.row), tileSize.width, tileSize.height)

    override fun slot(tileLeft: Double, centerY: Double, tiles: Int): RummyRackSlot {
        val maxHalf = maxOf(0, RummyRackLayout.halfColumnsPerRow - RummyRackLayout.tileSpan * maxOf(1, tiles))
        val half = roundedHalfAwayFromZero((tileLeft - sideInset) / halfPitch).toInt()
        val row = (0 until rowCount).minByOrNull { abs(rowCenter(it) - centerY) } ?: 0
        return RummyRackSlot(row, minOf(maxOf(half, 0), maxHalf))
    }

    companion object {
        /** 타일 높이 / 폭. */
        const val tileAspect: Double = 1.39

        /** 받침대 좌우 최소 여백. */
        const val minSideInset: Double = 4.0

        /** 위아래 여백 — 아랫줄 선반이 테두리 빛에 묻히지 않을 만큼. */
        const val verticalPadding: Double = 6.0
        const val rowGap: Double = 4.0

        /** 줄 사이 틈의 하한(타일이 위아래로 닿지 않게). */
        const val minRowGap: Double = 2.0

        private val perRow: Double get() = (RummyRackLayout.halfColumnsPerRow / RummyRackLayout.tileSpan).toDouble()

        private fun baseTileWidth(width: Double): Double = maxOf(1.0, width - minSideInset * 2) / perRow

        /** 칸 높이 — 2줄이 꼭 들어가는 값. 넓은 기기라도 [maxHeight] 를 안 넘는다(그때는 타일이 그만큼 작다). */
        fun height(width: Double, maxHeight: Double): Double {
            val rows = RummyRackLayout.baseRows.toDouble()
            return minOf(maxHeight, baseTileWidth(width) * tileAspect * rows + rowGap * (rows - 1) + verticalPadding * 2)
        }
    }
}

object GamesRummyRackDraw {
    /** 받침대에서 맞는 덩어리 밑줄 띠 자리: 덩어리 가로(양끝 4 안쪽) · 타일 아랫단 5 위부터 11(줄 사이 틈이 좁아 밖에 따로 둘 자리가 없다). */
    fun meldBar(meld: RummyRackMeld, layout: RummyRackLayout, geometry: GamesRummyRackGeometry): RummyCanvasRect? {
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

    /** 손이 받침대 아래 끝에 닿았을 때의 들어 올림([GamesRummyMatchLayout.fingerLift] — 받침대가 화면 맨 아래라 아랫줄에 놓을 손 자리를 벌어 준다). */
    const val fingerLiftAtBottom: Double = 18.0
    const val liftScale: Double = 1.25

    /** 묶음 손잡이 터치 폭(타일 왼쪽 바깥). */
    const val handleTouchWidth: Double = 28.0

    /** 손의 자리 → 그린 자리 · 놓을 자리 계산의 기준점. */
    fun liftedPoint(finger: RummyCanvasPoint, lift: Double = fingerLift): RummyCanvasPoint = RummyCanvasPoint(finger.x, finger.y - lift)

    /** 그려진 손잡이 막대(묶음 사각형 [shown] 왼쪽 바깥). 그리는 자리(판 층)와 재는 자리([handleGrabRect])가 이 값 하나를 쓴다. */
    fun handleBar(shown: RummyCanvasRect, scale: Double): RummyCanvasRect = RummyCanvasRect(
        shown.x - maxOf(9.0, 13 * scale),
        shown.midY - shown.height * 0.43,
        maxOf(8.0, 10 * scale),
        shown.height * 0.86,
    )

    /**
     * 타일보다 **먼저** 잡히는 손잡이 자리: 그려진 막대 둘레. 붙은 묶음은 틈이 좁아(스냅이면 0) 타일을 먼저 재면 막대를 눌러도 앞 묶음 끝 타일이 뽑힌다.
     * 앞 타일을 다 먹지 않게 둘레는 타일 폭의 ¼(최대 8)이고, 자기 첫 타일 쪽으로는 안 넘어간다.
     */
    fun handleGrabRect(shown: RummyCanvasRect, scale: Double): RummyCanvasRect {
        val bar = handleBar(shown, scale)
        val margin = minOf(8.0, RummyTableLayout.tileWidth.toDouble() * scale * 0.25)
        val left = bar.x - margin
        return RummyCanvasRect(left, shown.y, maxOf(0.0, minOf(bar.maxX + margin, shown.x) - left), shown.height)
    }
}

object GamesRummyHitTester {
    /**
     * [point] = 판 화면 좌표. [meldTileIDs] = 묶음별 타일 id(화면 순, 편집기). [editable] = 내 차례라 판 타일을 만질 수 있다 — 아니면 판은 전부 펠트다(밀어 보기만).
     * 받침대 빈칸은 None(받침대를 밀 일이 없다).
     */
    fun classify(
        point: RummyCanvasPoint,
        layout: GamesRummyMatchLayout,
        rack: GamesRummyRackGeometry,
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
        // ① 그려진 손잡이 막대 둘레 — 타일보다 먼저(붙은 묶음에서도 막대를 누르면 막대가 잡힌다).
        table.frames.forEachIndexed { set, frame ->
            if (GamesRummyGestureRules.handleGrabRect(canvas.rect(frame), canvas.scale).contains(local)) return GamesRummyHit.MeldHandle(set)
        }
        // ② 타일 — 나머지 터치 폭(③)보다 먼저다(옆 묶음의 손잡이 터치 폭이 앞 묶음 타일 위로 겹칠 수 있다).
        for (set in table.counts.indices) {
            val ids = meldTileIDs.getOrNull(set) ?: continue
            for (tile in 0 until table.counts[set]) {
                val frame = table.tileFrame(set, tile) ?: continue
                val id = ids.getOrNull(tile) ?: continue
                if (canvas.rect(frame).contains(local)) return GamesRummyHit.BoardTile(id)
            }
        }
        // ③ 막대 왼쪽 나머지 터치 폭(묶음과 세로로 겹칠 때만) — 왼쪽이 빈 펠트인 묶음은 여기로 잡기 쉽다.
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
    /** 손 자리에서 나온 들어 올림([GamesRummyMatchLayout.fingerLift]). */
    val lift: Double = GamesRummyGestureRules.fingerLift,
) {
    sealed interface Kind {
        data object Tiles : Kind

        /** 손잡이로 묶음 위치 이동. */
        data class WholeMeld(val set: Int) : Kind
    }

    val ids: List<Int> get() = tiles.map { it.id }

    /** 그린 자리 = 재는 자리. 판 위에서 손 위 48. */
    val pointer: RummyCanvasPoint get() = GamesRummyGestureRules.liftedPoint(finger, lift)

    /** 손이 옮겨 갔다. */
    fun moved(to: RummyCanvasPoint, layout: GamesRummyMatchLayout): GamesRummyDrag = copy(finger = to, lift = layout.fingerLift(to.y))
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
    /** 이 값을 만든 차례. 손을 쥔 사이 차례가 바뀌었는지 가른다([GamesRummyMatchModel.boardChanged]). */
    val turnKey: RummyEditorKey? = null,
) {
    val rack: GamesRummyRackGeometry get() = layout.rackGeometry
    val rackLayout: RummyRackLayout get() = editor?.rackLayout ?: RummyRackLayout()

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
            phase = Phase.Dragging(current.drag.moved(point, context.layout))
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
        phase = Phase.Dragging(GamesRummyDrag(GamesRummyDrag.Kind.Tiles, tiles, grab, point, surface = pressing.surface, lift = context.layout.fingerLift(point.y)))
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
                context.layout.fingerLift(point.y),
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
        val drag = current.drag.moved(point, context.layout)
        return GamesRummyDropPlanner.action(drag, GamesRummyDropPlanner.target(drag, context), context.editor)
    }

    fun cancel() {
        phase = Phase.Idle
    }

    /** 쥔 것이 이 편집기에 그대로 있는가(같은 차례 안에서 판이 바뀌었을 때 묻는다). [was] = 쥘 때의 편집기 — 손잡이는 묶음 번호만 들고 있어 그 번호의 내용을 견준다. */
    fun holdSurvives(editor: RummyTurnEditor?, was: RummyTurnEditor?): Boolean {
        val current = editor ?: return false
        fun alive(id: Int): Boolean = current.rack.any { it.id == id } || current.melds.any { meld -> meld.any { it.id == id } }
        fun sameMeld(index: Int, ids: List<Int>?): Boolean = ids != null && index in current.melds.indices && current.melds[index].map { it.id } == ids
        return when (val held = phase) {
            Phase.Idle, is Phase.Panning, Phase.Ignoring -> true
            is Phase.Pressing -> (held.picked ?: listOf(held.tileID)).all(::alive)
            is Phase.Handle -> sameMeld(held.set, was?.melds?.getOrNull(held.set)?.map { it.id })
            is Phase.Dragging -> {
                val kind = held.drag.kind
                if (kind is GamesRummyDrag.Kind.WholeMeld) sameMeld(kind.set, held.drag.ids) else held.drag.ids.all(::alive)
            }
        }
    }

    /** 손에 든 것을 거둔다 — **손은 아직 닿아 있다**. 뗄 때까지 무시한다(뗀 뒤 다음 손은 새로 분류된다). */
    fun abandon() {
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
    /** 상대 카드 — 내 다음 차례부터. 자리 번호 없는 사람(초대만 받은 사람)은 판에 없다. */
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

/**
 * 상태 줄 한 줄 — 서버 · 판정 문구는 스토어 notice, 내 차례 글자는 myTurnStatus(첫 등록 진행 · [완료]가 꺼진 이유). 맥 statusText 와 같은 서열.
 * [warning] = 내 시간 초과 연속 횟수(내 자리가 playing 일 때만). 상태 글자와 따로 위험 색으로 늘 보인다 — 다음 초과면 기권인데 글자 서열에 밀려 안 보이면 안 된다.
 */
data class GamesRummyStatusLine(val text: String, val tone: Tone, val warning: String? = null) {
    enum class Tone { notice, ready, plain, quiet }

    companion object {
        /** [engaged] = 이 기기가 손댄 판(앱을 내리면 기권될 수 있는 기기). 남의 차례 줄은 꼬리가 이미 '누구 차례'를 말하므로, 이 기기엔 90초 규칙을 말한다. */
        fun make(
            notice: String?,
            isMyTurn: Boolean,
            editor: RummyTurnEditor?,
            turnName: String?,
            mySeatState: RummySeatState?,
            myTimeoutStreak: Long? = null,
            engaged: Boolean = false,
        ): GamesRummyStatusLine {
            val line = base(notice, isMyTurn, editor, turnName, mySeatState, engaged)
            if (mySeatState == RummySeatState.playing && myTimeoutStreak != null && myTimeoutStreak > 0) return line.copy(warning = RummyPhoneText.timeouts(myTimeoutStreak))
            return line
        }

        private fun base(notice: String?, isMyTurn: Boolean, editor: RummyTurnEditor?, turnName: String?, mySeatState: RummySeatState?, engaged: Boolean): GamesRummyStatusLine {
            if (notice != null) return GamesRummyStatusLine(notice, Tone.notice)
            if (isMyTurn && editor != null) {
                return GamesRummyStatusLine(RummyPhoneText.myTurnStatus(editor), if (editor.canSubmit) Tone.ready else Tone.plain)
            }
            if (mySeatState == RummySeatState.forfeit) return GamesRummyStatusLine(GamesRummyMatchText.spectating, Tone.quiet)
            if (engaged && mySeatState == RummySeatState.playing) return GamesRummyStatusLine(RummyPhoneText.backgroundWarning, Tone.quiet)
            if (turnName != null) return GamesRummyStatusLine(RummyPhoneText.turnOf(turnName), Tone.quiet)
            return GamesRummyStatusLine("", Tone.quiet)
        }
    }
}

/** 상태 줄 오른쪽 작은 글자 — 직전 사건 · 남의 차례(작업 중이면 '놓는 중'). 판 위에 띄우면 낮은 칸에서 타일을 가린다. [turn] = 상태 글자가 이미 같은 말이면 비운다. */
data class GamesRummyStatusTail(val lastEvent: String?, val turn: String?, val isPlacing: Boolean) {
    companion object {
        fun make(match: RummyMatchState, isMyTurn: Boolean, hasOtherDraft: Boolean, line: GamesRummyStatusLine): GamesRummyStatusTail {
            val event = match.lastEvent
            val last = RummyPhoneText.lastEvent(event, match.seats?.firstOrNull { it.seatNo == event?.seatNo }?.displayName)
            var turn: String? = null
            val name = GamesRummySeats.turnSeat(match)?.displayName
            if (!isMyTurn && name != null) {
                val text = if (hasOtherDraft) RummyPhoneText.placing(name) else RummyPhoneText.turnOf(name)
                if (text != line.text) turn = text
            }
            return GamesRummyStatusTail(last, turn, hasOtherDraft)
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
