// 원본: Tests/CheckMobileKitTests/GamesRummyBoardGeometryTests.swift:1 @ ios-1017-cube 614d98bd
//
// 판 화면의 순수 값 — 칸 · 보기 · 받침대 · 누르기를 값으로 잰다(픽셀 비교 대신). 입력 궤적은 GamesRummyMatchInputTest, 화면 상호작용은 desktopTest GamesRummyMatchInteractionTest.
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyDropResolver
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRect
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class GamesRummyBoardGeometryTest {
    /** 세이프 영역 안 크기: SE 1세대급 · 기준 393 · 큰 폰. */
    private val screens = listOf(RummyCanvasSize(320.0, 548.0), RummyCanvasSize(393.0, 759.0), RummyCanvasSize(430.0, 830.0))
    private val tableSize = RummyCanvasSize(393.0, 469.0)

    private fun RummyCanvasRect.inside(outer: RummyCanvasRect, slack: Double = 0.001): Boolean =
        x >= outer.x - slack && y >= outer.y - slack && maxX <= outer.maxX + slack && maxY <= outer.maxY + slack

    // MARK: 칸

    @Test
    fun cellsNeverOverlapAtThreeWidths() {
        for (size in screens) {
            for (rows in listOf(2, 3, 4, 7)) {
                for (action in listOf(GamesRummyMatchLayout.actionsHeight, 84.0)) {
                    val layout = GamesRummyMatchLayout(size, rows, action)
                    val cells = listOf(layout.header, layout.opponents, layout.table, layout.status, layout.rack, layout.actions)
                    val screen = RummyCanvasRect(0.0, 0.0, size.width, size.height)
                    cells.forEachIndexed { index, cell ->
                        assertTrue(cell.inside(screen), "$size ${rows}줄: ${index}번 칸이 화면 밖 $cell")
                        for (other in cells.drop(index + 1)) {
                            assertTrue(cell.intersection(other).height <= 0.5, "$size ${rows}줄: 칸이 겹친다 $cell $other")
                        }
                    }
                    assertTrue(layout.table.height > 100, "$size ${rows}줄: 판이 너무 작다 ${layout.table.height}")
                    assertTrue(layout.actions.height >= action, "큰 글자에서 동작 줄이 잘린다")
                }
            }
        }
    }

    @Test
    fun rackGrowsAndTableShrinks() {
        val size = RummyCanvasSize(393.0, 759.0)
        val two = GamesRummyMatchLayout(size, 2)
        val three = GamesRummyMatchLayout(size, 3)
        assertEquals(118.0, two.rack.height, 0.001)
        assertEquals(165.0, three.rack.height, 0.001)
        assertEquals(469.0, two.table.height, 1.0)
        assertEquals(47.0, two.table.height - three.table.height, 0.001)
        // 3줄을 넘겨도 타일이 줄어 판을 더 안 먹는다(줄 틈만큼만).
        val five = GamesRummyMatchLayout(size, 5)
        assertTrue(five.rack.height < 180, "받침대가 판을 먹는다 ${five.rack.height}")
    }

    @Test
    fun actionWidthsFillTheRowAndSubmitIsBiggest() {
        for (total in listOf(320.0, 393.0, 430.0)) {
            val widths = GamesRummyMatchLayout.actionWidths(total)
            assertEquals(total, widths.submit + widths.draw + widths.undo + widths.sort + GamesRummyMatchLayout.actionGap * 5, 0.001)
            assertTrue(widths.submit > widths.sort && widths.submit > widths.undo && widths.submit > widths.draw, "[완료]가 가장 커야 한다 $widths")
        }
    }

    @Test
    fun bigTextSplitsTheActionRow() {
        assertEquals(1, GamesRummyMatchLayout.actionRowCount(1.0))
        assertEquals(1, GamesRummyMatchLayout.actionRowCount(1.3))
        assertEquals(2, GamesRummyMatchLayout.actionRowCount(1.31))
        assertEquals(GamesRummyMatchLayout.actionsHeight, GamesRummyMatchLayout.actionHeight(1.0), 0.001)
        val big = GamesRummyMatchLayout.actionHeight(GamesRummyMatchLayout.maxActionTextScale)
        assertEquals(GamesRummyMatchLayout.actionButtonHeight(GamesRummyMatchLayout.maxActionTextScale) * 2 + GamesRummyMatchLayout.actionGap * 3, big, 0.001)
        assertTrue(GamesRummyMatchLayout.actionButtonHeight(1.6) >= 44, "손가락 표적 아래로 내려갔다")
    }

    // MARK: 보기

    @Test
    fun defaultViewMatchesTheDesign() {
        val view = GamesRummyViewport.of(tableSize)
        assertEquals(469.0 / 640.0, view.scale, 0.001)
        assertEquals(29.3, view.tileSize.width, 0.2)
        assertEquals(41.0, view.tileSize.height, 0.3)
        assertEquals(536.0, view.visibleLogical.width, 2.0)
        assertEquals(0.393, GamesRummyViewport.fitScale(tableSize), 0.001)
        assertEquals(1.0, GamesRummyViewport.maxScale, 0.0)
        assertFalse(view.isFullView)
    }

    @Test
    fun panClampsBothEnds() {
        var view = GamesRummyViewport.of(tableSize)
        assertEquals(0.0, view.origin.x, 0.0, "처음 보기는 캔버스 왼끝이다")
        view = view.panned(100.0, 0.0)
        val home = -28 / view.scale
        assertEquals(home, view.origin.x, 0.001, "왼쪽 끝을 넘었다")
        view = view.panned(-100.0, 0.0)
        assertEquals(home + 100 / view.scale, view.origin.x, 0.001, "손을 왼쪽으로 끌면 판은 오른쪽을 보여 준다")
        view = view.panned(-100_000.0, 0.0)
        assertEquals(1000.0, view.visibleLogical.maxX, 0.001, "오른쪽 끝을 넘었다")
        // 높이가 다 보이는 기본 보기는 세로로 안 민다.
        assertEquals(0.0, view.panned(0.0, -50.0).origin.y, 0.0)
    }

    @Test
    fun logicalScreenRoundTrip() {
        val base = GamesRummyViewport.of(tableSize)
        for (view in listOf(base, base.panned(-420.0, 0.0), base.zoomed(0.95, RummyCanvasPoint(200.0, 100.0)).panned(-40.0, 30.0), base.toggledFullView())) {
            val logical = RummyCanvasPoint(321.0, 123.0)
            val back = view.transform.toLogical(view.transform.toScreen(logical))
            assertEquals(logical.x, back.x, 0.000001)
            assertEquals(logical.y, back.y, 0.000001)
        }
    }

    @Test
    fun zoomKeepsTheAnchorAndClamps() {
        var view = GamesRummyViewport.of(tableSize).panned(-200.0, 0.0)
        val anchor = RummyCanvasPoint(200.0, 200.0)
        val before = view.transform.toLogical(anchor)
        view = view.zoomed(0.95, anchor)
        assertEquals(0.95, view.scale, 0.0)
        val after = view.transform.toLogical(anchor)
        assertEquals(before.x, after.x, 0.01)
        assertEquals(before.y, after.y, 0.01)
        assertEquals(1.0, view.zoomed(5.0, anchor).scale, 0.0, "상한은 타일 폭 40")
        val floor = view.zoomed(0.01, anchor)
        assertTrue(floor.isFullView, "하한은 전체 맞춤")
        assertEquals(RummyCanvasPoint(0.0, 0.0), floor.origin, "전체 맞춤에서 오프셋이 남았다")
    }

    @Test
    fun toggleSwitchesFitAndDefault() {
        val view = GamesRummyViewport.of(tableSize)
        val full = view.toggledFullView()
        assertTrue(full.isFullView)
        // 전체 맞춤이면 캔버스가 세로 가운데에 선다.
        assertTrue(full.transform.screenOrigin.y > 0 && full.transform.screenOrigin.x == 0.0)
        assertEquals(view.scale, full.toggledFullView().scale, 0.0)
    }

    @Test
    fun resizeKeepsThePersonsChoice() {
        var view = GamesRummyViewport.of(tableSize).resized(RummyCanvasSize(393.0, 422.0))
        assertEquals(422.0 / 640.0, view.scale, 0.001)
        view = view.zoomed(0.9, RummyCanvasPoint(0.0, 0.0)).resized(tableSize)
        assertEquals(0.9, view.scale, 0.0, "사람이 고른 배율이 칸 변화로 바뀌었다")
    }

    @Test
    fun edgePanInsideTheZoneOnly() {
        var view = GamesRummyViewport.of(tableSize)
        assertEquals(view, view.edgePanned(200.0, 0.1), "가운데에서 밀렸다")
        view = view.panned(10_000.0, 0.0)
        val home = view.origin.x
        assertEquals(view, view.edgePanned(10.0, 0.1), "왼쪽 끝인데 움직였다")
        assertEquals(0, view.edgeDirection(10.0), "끝에 닿았는데 프레임을 돌린다")
        view = view.edgePanned(380.0, 0.1)
        assertEquals(home + 40, view.origin.x, 0.001)
        assertEquals(1, view.edgeDirection(380.0))
        view = view.edgePanned(5.0, 0.05)
        assertEquals(home + 20, view.origin.x, 0.001)
        assertEquals(-1, view.edgeDirection(5.0))
        // 경계값: 정확히 28 은 가장자리가 아니다.
        assertEquals(view, view.edgePanned(28.0, 0.1))
        assertEquals(view, view.edgePanned(393.0 - 28, 0.1))
        assertEquals(0, view.edgeDirection(28.0))
    }

    @Test
    fun offscreenBadgesCountAndReveal() {
        var view = GamesRummyViewport.of(tableSize)
        val frames = listOf(
            RummyRect(10, 10, 120, 56),
            RummyRect(500, 10, 120, 56), // 경계에 걸침 — 일부 보인다.
            RummyRect(620, 100, 120, 56),
            RummyRect(860, 100, 120, 56),
        )
        assertEquals(GamesRummyOffscreenCounts(0, 2), view.offscreenCounts(frames))
        view = view.revealed(GamesRummySide.right, frames)
        assertTrue(RummyCanvasRect(620.0, 100.0, 120.0, 56.0).inside(view.visibleLogical), "눌렀는데 묶음이 안 보인다")
        assertEquals(740 + GamesRummyViewport.revealMargin, view.visibleLogical.maxX, 0.001)
        val moved = view.offscreenCounts(frames)
        assertEquals(1, moved.right)
        assertEquals(1, moved.left, "밀고 나면 왼쪽 첫 묶음이 왼쪽 화면 밖이다")
        assertEquals(view, view.revealed(GamesRummySide.right, emptyList()), "밀 것이 없는데 움직였다")
        view = view.revealed(GamesRummySide.left, frames)
        assertEquals(10 - GamesRummyViewport.revealMargin, view.origin.x, 0.001, "왼끝 묶음도 여백을 두고 보여야 손잡이가 닿는다")
        // 전체 맞춤이면 화면 밖이 없다.
        assertEquals(GamesRummyOffscreenCounts(0, 0), view.toggledFullView().offscreenCounts(frames))
    }

    // MARK: 받침대

    @Test
    fun rackFrameSlotRoundTrip() {
        for (size in screens) {
            for (rows in listOf(2, 3, 5)) {
                val layout = GamesRummyMatchLayout(size, rows)
                val rack = layout.rackGeometry
                val bounds = RummyCanvasRect(0.0, 0.0, layout.rack.width, layout.rack.height)
                for (row in 0 until rows) {
                    for (half in 0..(RummyRackGeometry.phoneHalfColumns - RummyRackLayout.tileSpan)) {
                        val slot = RummyRackSlot(row, half)
                        val frame = rack.frame(slot)
                        assertTrue(frame.inside(bounds, 0.5), "$size ${rows}줄 $slot: 칸 밖 $frame")
                        assertEquals(slot, rack.slot(frame.x, frame.midY, 1), "$size ${rows}줄 왕복 실패 $slot")
                    }
                }
            }
        }
    }

    @Test
    fun rackTileSizes() {
        val base = RummyRackGeometry.phone(393.0)
        assertEquals(RummyCanvasSize(34.0, 47.0), base.tileSize)
        val narrow = RummyRackGeometry.phone(320.0)
        assertEquals(304.0 / 11, narrow.tileSize.width, 0.001)
        assertEquals(34.0 / 47, narrow.tileSize.width / narrow.tileSize.height, 0.001)
        val five = RummyRackGeometry.phone(393.0, 5)
        assertEquals(0.6, five.tileScale, 0.0001)
        assertEquals(34 * 0.6, five.tileSize.width, 0.001)
    }

    @Test
    fun rackSlotClampsToTheRow() {
        val rack = RummyRackGeometry.phone(393.0)
        assertEquals(RummyRackSlot(0, 16), rack.slot(9999.0, 10.0, 3))
        assertEquals(RummyRackSlot(1, 0), rack.slot(-50.0, 1000.0, 1))
    }

    /** 미리보기가 새 줄을 열어도 그리는 기하가 굳은 칸 안에 담긴다(되먹임 없이 타일이 줄어 담긴다). 기준선: 자연 기하는 칸을 넘는다. */
    @Test
    fun fittedRackStaysInsideAFrozenRegion() {
        for (width in listOf(320.0, 393.0, 430.0)) {
            val frozen = RummyRackGeometry.phone(width, 2).height
            val natural = RummyRackGeometry.phone(width, 3)
            assertTrue(natural.height > frozen, "기준선: 3줄은 2줄 칸을 넘는다")
            val draw = GamesRummyRackDraw.fitted(width, frozen, 3)
            assertEquals(3, draw.rowCount)
            val bounds = RummyCanvasRect(0.0, 0.0, width, frozen)
            for (row in 0 until 3) {
                for (half in listOf(0, 10, 20)) {
                    assertTrue(draw.frame(RummyRackSlot(row, half)).inside(bounds, 0.5), "$width: ${row}줄 $half 칸 밖")
                }
            }
            assertEquals(RummyRackGeometry.phone(width, 2), GamesRummyRackDraw.fitted(width, frozen, 2), "넘치지 않으면 자연 기하 그대로")
        }
    }

    // MARK: 누르기

    private val layout = GamesRummyMatchLayout(RummyCanvasSize(393.0, 759.0))
    private val view: GamesRummyViewport = GamesRummyViewport.of(RummyCanvasSize(layout.table.width, layout.table.height))
    private val table = RummyTableLayout(listOf(3, 3), listOf(RummyPoint(100, 50), RummyPoint(800, 50)))
    private val rackLayout = RummyRackLayout.packed(listOf(100, 101, 102), RummyRackGeometry.phoneHalfColumns)

    private fun classify(point: RummyCanvasPoint, editable: Boolean = true): GamesRummyHit =
        GamesRummyHitTester.classify(point, layout, layout.rackGeometry, rackLayout, view.transform, table, listOf(listOf(0, 1, 2), listOf(3, 4, 5)), editable)

    private fun screen(x: Double, y: Double): RummyCanvasPoint {
        val p = view.transform.toScreen(RummyCanvasPoint(x, y))
        return RummyCanvasPoint(p.x + layout.table.x, p.y + layout.table.y)
    }

    @Test
    fun hitClassTable() {
        val tile = layout.rackGeometry.frame(RummyRackSlot(0, 2))
        assertEquals(GamesRummyHit.RackTile(101), classify(RummyCanvasPoint(tile.midX, layout.rack.y + tile.midY)))
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(380.0, layout.rack.maxY - 2)), "받침대 빈칸은 무시")
        assertEquals(GamesRummyHit.BoardTile(1), classify(screen(100.0 + 40 + 20, 70.0)))
        // 손잡이: 묶음 왼쪽 바깥 28.
        val edge = screen(100.0, 70.0)
        assertEquals(GamesRummyHit.MeldHandle(0), classify(RummyCanvasPoint(edge.x - 10, edge.y)))
        assertEquals(GamesRummyHit.MeldHandle(0), classify(RummyCanvasPoint(edge.x - 27, edge.y)))
        assertEquals(GamesRummyHit.Felt, classify(RummyCanvasPoint(edge.x - 29, edge.y)), "28 밖은 펠트")
        assertEquals(GamesRummyHit.Felt, classify(screen(300.0, 400.0)))
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(100.0, 10.0)), "머리 줄")
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(100.0, layout.actions.midY)), "동작 줄")
    }

    /** 옆 묶음의 손잡이 터치 폭이 앞 묶음 타일 위로 겹치면 타일이 먼저다 — 타일을 못 집으면 안 된다. */
    @Test
    fun tileWinsOverANeighboursHandle() {
        val close = RummyTableLayout(listOf(3, 3), listOf(RummyPoint(100, 50), RummyPoint(236, 50)))
        val second = view.transform.toScreen(RummyCanvasPoint(236.0, 70.0))
        val point = RummyCanvasPoint(second.x - 14 + layout.table.x, second.y + layout.table.y)
        assertEquals(
            GamesRummyHit.BoardTile(2),
            GamesRummyHitTester.classify(point, layout, layout.rackGeometry, rackLayout, view.transform, close, listOf(listOf(0, 1, 2), listOf(3, 4, 5)), true),
        )
    }

    @Test
    fun handleOfALeftEdgeMeldIsReachableAfterPanning() {
        val edgeTable = RummyTableLayout(listOf(3), listOf(RummyPoint(0, 50)))
        var current = view
        fun hit(x: Double, y: Double): GamesRummyHit = GamesRummyHitTester.classify(
            RummyCanvasPoint(x + layout.table.x, y + layout.table.y), layout, layout.rackGeometry, RummyRackLayout(22), current.transform, edgeTable, listOf(listOf(0, 1, 2)), true,
        )
        val y = current.transform.toScreen(RummyCanvasPoint(0.0, 70.0)).y
        // 기준선: 처음 보기에는 묶음이 칸 왼끝에 붙어 손잡이 자리가 없다.
        assertEquals(GamesRummyHit.BoardTile(0), hit(1.0, y))
        current = current.panned(100.0, 0.0)
        assertEquals(28.0, current.transform.toScreen(RummyCanvasPoint(0.0, 70.0)).x, 0.001, "손잡이 폭만큼 안 밀린다")
        assertEquals(GamesRummyHit.MeldHandle(0), hit(14.0, y), "왼끝 묶음의 손잡이가 안 닿는다")
        assertEquals(GamesRummyHit.BoardTile(0), hit(30.0, y))
    }

    @Test
    fun notEditableMakesTheBoardFelt() {
        assertEquals(GamesRummyHit.Felt, classify(screen(160.0, 70.0), editable = false))
        val tile = layout.rackGeometry.frame(RummyRackSlot(0, 0))
        assertEquals(GamesRummyHit.RackTile(100), classify(RummyCanvasPoint(tile.midX, layout.rack.y + tile.midY), editable = false))
    }

    @Test
    fun liftRules() {
        assertEquals(RummyCanvasPoint(10.0, 52.0), GamesRummyGestureRules.liftedPoint(RummyCanvasPoint(10.0, 100.0)))
        assertEquals(1.25, GamesRummyGestureRules.liftScale, 0.0)
        assertEquals(500L, GamesRummyGestureRules.liftDelayMillis)
        assertEquals(8.0, GamesRummyGestureRules.dragThreshold, 0.0)
    }

    // MARK: 놓을 자리(코어 판정기 + 폰 칸)

    @Test
    fun dropTargetsOnThePhoneRegions() {
        fun target(point: RummyCanvasPoint, myTurn: Boolean = true): RummyDropTarget? =
            RummyDropResolver.target(point, 0, 1, layout.regions, view.transform, table, layout.rackGeometry, myTurn)
        val tile = layout.rackGeometry.frame(RummyRackSlot(1, 6))
        assertEquals(RummyDropTarget.RackSlot(RummyRackSlot(1, 6)), target(RummyCanvasPoint(tile.midX, layout.rack.y + tile.midY)))
        assertEquals(RummyDropTarget.Meld(0, 2), target(screen(165.0, 70.0)))
        assertEquals(RummyDropTarget.NewMeldAt(RummyPoint(280, 272)), target(screen(300.0, 300.0)))
        assertEquals(null, target(screen(300.0, 300.0), myTurn = false))
        assertEquals(null, target(RummyCanvasPoint(10.0, 10.0)), "머리 줄엔 못 놓는다")
    }

    // MARK: 값 표

    @Test
    fun countdownToneThresholds() {
        assertEquals(GamesRummyCountdownTone.normal, GamesRummyCountdownTone.of(10.01))
        assertEquals(GamesRummyCountdownTone.warning, GamesRummyCountdownTone.of(10.0))
        assertEquals(GamesRummyCountdownTone.warning, GamesRummyCountdownTone.of(5.01))
        assertEquals(GamesRummyCountdownTone.danger, GamesRummyCountdownTone.of(5.0))
        assertNotEquals(GamesRummyCountdownTone.of(0.0), GamesRummyCountdownTone.normal)
        assertTrue(abs(GamesRummyViewport.edgeZone - 28.0) < 0.0001 && abs(GamesRummyViewport.edgePanSpeed - 400.0) < 0.0001)
    }
}
