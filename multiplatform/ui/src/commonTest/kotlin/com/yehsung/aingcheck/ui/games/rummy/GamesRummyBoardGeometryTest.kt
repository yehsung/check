// 원본: Tests/CheckMobileKitTests/GamesRummyBoardGeometryTests.swift:1 @ ios-1017-cube 61d75d8c(가로 칸 · 폭 맞춤 보기 · 16장 받침대)
//
// 판 화면의 순수 값 — 칸 · 보기 · 받침대 · 누르기를 값으로 잰다(픽셀 비교 대신). 입력 궤적은 GamesRummyMatchInputTest, 화면 상호작용은 desktopTest GamesRummyMatchInteractionTest.
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyDropResolver
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
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
    /** 시스템 막대 안 크기: 설계서 세 크기(667×375 · 852×393 · 932×430) · iOS 세이프(667×354 · 734×372). */
    private val screens = listOf(RummyCanvasSize(568.0, 320.0), RummyCanvasSize(605.0, 303.0), RummyCanvasSize(667.0, 375.0), RummyCanvasSize(852.0, 393.0), RummyCanvasSize(932.0, 430.0), RummyCanvasSize(667.0, 354.0), RummyCanvasSize(734.0, 372.0))

    /** 안드로이드 높이 낮은 폰: 폭 360dp 폰 가로에서 상태 막대 · 내비 막대를 뺀 값. */
    private val lowAndroid = RummyCanvasSize(640.0, 312.0)
    private val base = RummyCanvasSize(734.0, 372.0)

    /** 734×372 의 판 칸. */
    private val tableSize = RummyCanvasSize(544.0, 245.0)

    private fun RummyCanvasRect.inside(outer: RummyCanvasRect, slack: Double = 0.001): Boolean =
        x >= outer.x - slack && y >= outer.y - slack && maxX <= outer.maxX + slack && maxY <= outer.maxY + slack

    private fun cells(layout: GamesRummyMatchLayout): List<RummyCanvasRect> = listOf(
        layout.nav, layout.opponentCard(0), layout.opponentCard(1), layout.opponentCard(2), layout.mySeatCard,
        layout.table, layout.status, layout.rack,
        layout.info, layout.tools, layout.submit, layout.draw, layout.undo, layout.sort,
    )

    // MARK: 칸

    @Test
    fun cellsNeverOverlap() {
        for (size in screens + lowAndroid) {
            for (rows in listOf(2, 3, 7)) {
                val layout = GamesRummyMatchLayout(size, rows)
                val screen = RummyCanvasRect(0.0, 0.0, size.width, size.height)
                val all = cells(layout)
                all.forEachIndexed { index, cell ->
                    assertTrue(cell.inside(screen), "$size ${rows}줄: ${index}번 칸이 화면 밖 $cell")
                    assertTrue(cell.width > 0 && cell.height > 0, "$size: ${index}번 칸이 비었다")
                    for (other in all.drop(index + 1)) {
                        val overlap = cell.intersection(other)
                        assertTrue(overlap.height <= 0.5 || overlap.width <= 0.5, "$size ${rows}줄: 칸이 겹친다 $cell $other")
                    }
                }
                assertTrue(layout.table.height > 190, "$size ${rows}줄: 판이 너무 작다 ${layout.table.height}")
            }
        }
    }

    @Test
    fun rackHeightIsFixedAndColumnsMatchTheDesign() {
        val two = GamesRummyMatchLayout(base, 2)
        val five = GamesRummyMatchLayout(base, 5)
        assertEquals(two.rack, five.rack)
        assertEquals(two.table, five.table)
        assertEquals(90.0, two.table.x)
        assertEquals(544.0, two.table.width)
        assertEquals(634.0, two.rightColumn.x)
        assertEquals(100.0, two.rightColumn.width)
        assertEquals(two.table.width, two.rack.width)
        assertEquals(372.0, two.rack.maxY)
        assertEquals(109.1, two.rack.height, 0.2)
        assertEquals(244.9, two.table.height, 0.2)
    }

    @Test
    fun columnsFitAndSubmitIsBiggest() {
        for (size in screens) {
            val layout = GamesRummyMatchLayout(size)
            for (cell in listOf(layout.submit, layout.draw, layout.undo, layout.sort)) assertTrue(cell.height >= 44, "$size: 손가락 표적 아래 $cell")
            assertTrue(layout.submit.height > layout.draw.height && layout.draw.height > layout.undo.height && layout.undo.height > layout.sort.height)
            assertTrue(layout.sort.maxY <= size.height - GamesRummyMatchLayout.columnPadding + 0.001)
            assertTrue(layout.opponentCard(2).maxY <= layout.mySeatCard.y)
            assertTrue(layout.opponentCard(0).height >= 59, "$size: 카드 글자 세 줄이 안 든다 ${layout.opponentCard(0).height}")
            assertEquals(layout.opponentCard(0).height < GamesRummyMatchLayout.seatCardFullContentHeight, layout.isSeatCardCompact, "$size: 낮은 칸인데 얼굴이 그대로다")
            assertTrue(layout.mySeatCard.inside(layout.leftColumn) && layout.mySeatCard.maxY > size.height - 10)
        }
        // 높이 낮은 안드로이드도 칸은 안 겹친다(버튼만 조금 낮다 — 판단 기록의 숫자).
        val low = GamesRummyMatchLayout(lowAndroid)
        assertTrue(low.sort.height >= 38 && low.opponentCard(0).height >= 60, "$low")
    }

    /** 버튼 하나의 터치 자리: [나가기] · [규칙] · [777] · [789] 가 어느 크기에서도 44×44 이상이고 칸 합이 칸을 안 넘는다. */
    @Test
    fun buttonTouchTargets() {
        for (size in screens) {
            val layout = GamesRummyMatchLayout(size)
            assertTrue(layout.navButton.width >= 44 && layout.navButton.height >= 44, "$size: ${layout.navButton}")
            assertTrue(layout.sortButton.width >= 44 && layout.sortButton.height >= 44, "$size: ${layout.sortButton}")
            assertTrue(layout.navButton.width * 2 + GamesRummyMatchLayout.navGap <= layout.nav.width + 0.001)
            assertTrue(layout.sortButton.width * 2 + GamesRummyMatchLayout.sortDividerWidth <= layout.sort.width + 0.001)
            assertTrue(GamesRummyMatchLayout.navButtonDiameter <= layout.navButton.width, "그림이 터치 자리보다 크다")
        }
        // 넷 다 44 가 안 되는 높이에서는 열을 넘지 않는 쪽이 먼저다.
        val tight = GamesRummyMatchLayout(RummyCanvasSize(500.0, 260.0))
        assertTrue(tight.sort.maxY <= 260 - GamesRummyMatchLayout.columnPadding + 0.001)
    }

    @Test
    fun portraitFrameIsSafe() {
        assertFalse(GamesRummyMatchLayout.isLandscape(RummyCanvasSize(393.0, 759.0)))
        assertFalse(GamesRummyMatchLayout.isLandscape(RummyCanvasSize(400.0, 400.0)))
        assertTrue(GamesRummyMatchLayout.isLandscape(base))
        // 폰 세로 프레임은 안 세운다 · 시스템이 방향 요청을 무시하는 큰 화면은 세운다(판을 영영 못 보면 시간 초과로 기권된다).
        assertFalse(GamesRummyMatchLayout.canStand(RummyCanvasSize(393.0, 759.0)))
        assertTrue(GamesRummyMatchLayout.canStand(RummyCanvasSize(800.0, 1280.0)))
        for (size in listOf(RummyCanvasSize(393.0, 759.0), RummyCanvasSize(100.0, 100.0), RummyCanvasSize(0.0, 0.0))) {
            val layout = GamesRummyMatchLayout(size)
            for (cell in listOf(layout.table, layout.rack, layout.status, layout.submit, layout.sort, layout.mySeatCard, layout.opponentCard(2))) {
                assertTrue(cell.width >= 0 && cell.height >= 0, "$size: $cell")
            }
            layout.rackGeometry.frame(RummyRackSlot(1, 30))
            GamesRummyViewport.of(RummyCanvasSize(layout.table.width, layout.table.height)).transform
        }
    }

    // MARK: 보기

    @Test
    fun defaultViewMatchesTheDesign() {
        val view = GamesRummyViewport.of(tableSize)
        assertEquals(0.544, view.scale, 0.001)
        assertEquals(21.8, view.tileSize.width, 0.1)
        assertEquals(30.5, view.tileSize.height, 0.1)
        assertEquals(1000.0, view.visibleLogical.width, 0.01)
        assertEquals(450.0, view.visibleLogical.height, 1.0)
        assertEquals(245.0 / 640.0, GamesRummyViewport.fitScale(tableSize), 0.001)
        assertEquals(1.0, GamesRummyViewport.maxScale, 0.0)
        assertFalse(view.isFullView)
    }

    @Test
    fun panClampsBothAxes() {
        var view = GamesRummyViewport.of(tableSize)
        assertEquals(RummyCanvasPoint(0.0, 0.0), view.origin)
        view = view.panned(0.0, 100.0)
        assertEquals(0.0, view.origin.y, 0.0, "위쪽 끝을 넘었다")
        view = view.panned(0.0, -100.0)
        assertEquals(100 / view.scale, view.origin.y, 0.001, "손을 위로 끌면 판은 아래를 보여 준다")
        view = view.panned(0.0, -100_000.0)
        assertEquals(640.0, view.visibleLogical.maxY, 0.001, "아래쪽 끝을 넘었다")
        view = view.panned(-100.0, 0.0)
        assertEquals(0.0, view.origin.x, 0.01, "폭이 꼭 찬 보기가 오른쪽으로 더 갔다")
        view = view.panned(100.0, 0.0)
        assertEquals(-28 / view.scale, view.origin.x, 0.001, "왼끝 묶음 손잡이가 안 닿는다")

        var zoomed = GamesRummyViewport.of(tableSize).zoomed(1.0, RummyCanvasPoint(0.0, 0.0))
        zoomed = zoomed.panned(-100_000.0, 0.0)
        assertEquals(1000.0, zoomed.visibleLogical.maxX, 0.001, "오른쪽 끝을 넘었다")
        zoomed = zoomed.panned(100_000.0, 0.0)
        assertEquals(-28.0, zoomed.origin.x, 0.001)
    }

    @Test
    fun logicalScreenRoundTrip() {
        val start = GamesRummyViewport.of(tableSize)
        for (view in listOf(start, start.panned(0.0, -120.0), start.zoomed(0.95, RummyCanvasPoint(200.0, 100.0)).panned(-40.0, 30.0), start.toggledFullView())) {
            val logical = RummyCanvasPoint(321.0, 123.0)
            val back = view.transform.toLogical(view.transform.toScreen(logical))
            assertEquals(logical.x, back.x, 0.000001)
            assertEquals(logical.y, back.y, 0.000001)
        }
    }

    @Test
    fun zoomKeepsTheAnchorAndClamps() {
        var view = GamesRummyViewport.of(tableSize).panned(0.0, -60.0)
        val anchor = RummyCanvasPoint(200.0, 100.0)
        val before = view.transform.toLogical(anchor)
        view = view.zoomed(0.8, anchor)
        assertEquals(0.8, view.scale, 0.0)
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
        // 전체 보기는 높이까지 맞추니 캔버스가 가로 가운데에 선다.
        assertTrue(full.transform.screenOrigin.x > 0 && full.transform.screenOrigin.y == 0.0)
        assertTrue(full.scale < view.scale)
        assertEquals(view.scale, full.toggledFullView().scale, 0.0)
    }

    @Test
    fun resizeKeepsThePersonsChoice() {
        var view = GamesRummyViewport.of(tableSize).resized(RummyCanvasSize(481.0, 238.0))
        assertEquals(0.481, view.scale, 0.001)
        view = view.zoomed(0.9, RummyCanvasPoint(0.0, 0.0)).resized(tableSize)
        assertEquals(0.9, view.scale, 0.0, "사람이 고른 배율이 칸 변화로 바뀌었다")

        val turning = GamesRummyViewport.of(tableSize).resized(RummyCanvasSize(293.0, 700.0)).resized(tableSize)
        assertFalse(turning.isFullView, "세로 칸을 거치니 전체 보기가 됐다")
        assertEquals(0.544, turning.scale, 0.001)
        val full = GamesRummyViewport.of(tableSize).toggledFullView().resized(RummyCanvasSize(667.0, 300.0))
        assertTrue(full.isFullView, "사람이 고른 전체 보기가 풀렸다")
    }

    @Test
    fun edgePanInsideTheZoneOnlyOnBothAxes() {
        var view = GamesRummyViewport.of(tableSize).zoomed(1.0, RummyCanvasPoint(0.0, 0.0))
        assertEquals(view, view.edgePanned(RummyCanvasPoint(200.0, 100.0), 0.1), "가운데에서 밀렸다")
        assertFalse(view.edgeMoves(RummyCanvasPoint(200.0, 100.0)))
        view = view.panned(10_000.0, 0.0)
        val home = view.origin.x
        assertEquals(view, view.edgePanned(RummyCanvasPoint(10.0, 100.0), 0.1), "왼쪽 끝인데 움직였다")
        assertFalse(view.edgeMoves(RummyCanvasPoint(10.0, 100.0)), "끝에 닿았는데 프레임을 돌린다")
        view = view.edgePanned(RummyCanvasPoint(540.0, 100.0), 0.1)
        assertEquals(home + 40, view.origin.x, 0.001)
        assertTrue(view.edgeMoves(RummyCanvasPoint(540.0, 100.0)))
        view = view.edgePanned(RummyCanvasPoint(5.0, 100.0), 0.05)
        assertEquals(home + 20, view.origin.x, 0.001)
        // 경계값: 정확히 28 은 가장자리가 아니다.
        assertEquals(view, view.edgePanned(RummyCanvasPoint(28.0, 100.0), 0.1))
        assertEquals(view, view.edgePanned(RummyCanvasPoint(544.0 - 28, 100.0), 0.1))
        assertFalse(view.edgeMoves(RummyCanvasPoint(28.0, 100.0)))
        // 세로: 아래 가장자리에서 민다.
        val y = view.origin.y
        view = view.edgePanned(RummyCanvasPoint(200.0, 244.0 - 5), 0.1)
        assertEquals(y + 40, view.origin.y, 0.001)
        view = view.edgePanned(RummyCanvasPoint(200.0, 5.0), 0.05)
        assertEquals(y + 20, view.origin.y, 0.001)
    }

    @Test
    fun offscreenBadgesCountAndReveal() {
        var view = GamesRummyViewport.of(tableSize).zoomed(1.0, RummyCanvasPoint(0.0, 0.0))
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
        // 기본 보기 · 전체 맞춤이면 좌우 화면 밖이 없다.
        assertEquals(GamesRummyOffscreenCounts(0, 0), GamesRummyViewport.of(tableSize).offscreenCounts(frames))
        assertEquals(GamesRummyOffscreenCounts(0, 0), view.toggledFullView().offscreenCounts(frames))
    }

    @Test
    fun verticalBadgesCountWhatIsHiddenAboveAndBelow() {
        var view = GamesRummyViewport.of(tableSize)
        val frames = listOf(RummyRect(10, 10, 120, 56), RummyRect(300, 584, 120, 56), RummyRect(600, 500, 120, 56))
        assertEquals(GamesRummyOffscreenVerticalCounts(0, 2), view.offscreenVerticalCounts(frames))
        view = view.revealed(GamesRummySide.down, frames)
        assertEquals(556 + GamesRummyViewport.revealMargin, view.visibleLogical.maxY, 0.001)
        assertEquals(GamesRummyOffscreenVerticalCounts(1, 1), view.offscreenVerticalCounts(frames), "밀고 나면 윗줄 묶음이 위로 나가고 맨 아래 묶음만 아래에 남는다")
        view = view.panned(0.0, -100_000.0)
        assertEquals(1, view.offscreenVerticalCounts(frames).up, "밀고 나면 윗줄 묶음이 위쪽 화면 밖이다")
        view = view.revealed(GamesRummySide.up, frames)
        assertEquals(0.0, view.origin.y, 0.001, "여백이 위 끝을 넘으면 끝에서 멈춘다")
        // 가로로 이미 화면 밖이면 좌우 배지 몫이다 — 두 번 세지 않는다.
        val zoomed = GamesRummyViewport.of(tableSize).zoomed(1.0, RummyCanvasPoint(0.0, 0.0))
        assertEquals(GamesRummyOffscreenVerticalCounts(0, 1), zoomed.offscreenVerticalCounts(listOf(RummyRect(100, 500, 120, 56), RummyRect(900, 500, 80, 56))))
        assertEquals(1, zoomed.offscreenCounts(listOf(RummyRect(900, 500, 80, 56))).right)
        // 전체 맞춤이면 위아래도 없다.
        assertEquals(GamesRummyOffscreenVerticalCounts(0, 0), GamesRummyViewport.of(tableSize).toggledFullView().offscreenVerticalCounts(frames))
    }

    // MARK: 받침대

    @Test
    fun rackFrameSlotRoundTrip() {
        for (size in screens + lowAndroid) {
            for (rows in listOf(2, 3, 5)) {
                val rect = GamesRummyMatchLayout(size, rows).rack
                val rack = GamesRummyRackGeometry(RummyCanvasSize(rect.width, rect.height), rows)
                val bounds = RummyCanvasRect(0.0, 0.0, rect.width, rect.height)
                for (row in 0 until rows) {
                    for (half in 0..(RummyRackLayout.halfColumnsPerRow - RummyRackLayout.tileSpan)) {
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
        val rect = GamesRummyMatchLayout(base).rack
        val size = RummyCanvasSize(rect.width, rect.height)
        val two = GamesRummyRackGeometry(size)
        assertEquals(536.0 / 16, two.tileSize.width, 0.001)
        assertEquals(1.39, two.tileSize.height / two.tileSize.width, 0.001)
        val three = GamesRummyRackGeometry(size, 3)
        assertEquals(2.0 / 3, three.tileScale, 0.001)
        assertEquals(two.tileSize.width * 2 / 3, three.tileSize.width, 0.05)
        val five = GamesRummyRackGeometry(size, 5)
        assertEquals(0.4, five.tileScale, 0.0)
        assertTrue(five.tileSize.width <= two.tileSize.width * 0.4 + 0.001, "칸 안에 담으려면 산식보다 커질 수 없다")
        for (each in screens) {
            val layout = GamesRummyMatchLayout(each)
            assertTrue(layout.rack.height <= each.height * GamesRummyMatchLayout.rackMaxHeightShare + 0.001)
            // 시스템 '화면 확대'(높이 354 아래)는 칸이 그만큼 좁다 — 맥과 같은 한 줄 16장을 지키는 값이다.
            assertTrue(layout.rackGeometry.tileSize.width >= (if (each.height >= 354) 29.0 else 22.0), "$each: 받침대 타일이 너무 작다")
        }
    }

    @Test
    fun rackSlotClampsToTheRow() {
        val rack = GamesRummyMatchLayout(base).rackGeometry
        assertEquals(RummyRackSlot(0, 26), rack.slot(9999.0, 10.0, 3))
        assertEquals(RummyRackSlot(1, 0), rack.slot(-50.0, 1000.0, 1))
    }

    /** 끄는 동안 미리보기가 새 줄을 열어도 그리는 기하가 칸 안에 담긴다(되먹임 없이 타일이 2/줄로 준다). */
    @Test
    fun aNewRowFromAPreviewStaysInsideTheRegion() {
        for (size in screens + lowAndroid) {
            val rect = GamesRummyMatchLayout(size).rack
            val region = RummyCanvasSize(rect.width, rect.height)
            val bounds = RummyCanvasRect(0.0, 0.0, rect.width, rect.height)
            for (rows in listOf(3, 4)) {
                val draw = GamesRummyRackGeometry(region, rows)
                assertEquals(rows, draw.rowCount)
                for (row in 0 until rows) {
                    for (half in listOf(0, 16, 30)) assertTrue(draw.frame(RummyRackSlot(row, half)).inside(bounds, 0.5), "$size ${rows}줄 $row/$half 칸 밖")
                }
            }
        }
    }

    // MARK: 누르기

    private val layout = GamesRummyMatchLayout(base)
    private val view: GamesRummyViewport = GamesRummyViewport.of(RummyCanvasSize(layout.table.width, layout.table.height))
    private val table = RummyTableLayout(listOf(3, 3), listOf(RummyPoint(100, 50), RummyPoint(800, 50)))
    private val rackLayout = RummyRackLayout.packed(listOf(100, 101, 102))

    private fun classify(point: RummyCanvasPoint, editable: Boolean = true): GamesRummyHit =
        GamesRummyHitTester.classify(point, layout, layout.rackGeometry, rackLayout, view.transform, table, listOf(listOf(0, 1, 2), listOf(3, 4, 5)), editable)

    private fun screen(x: Double, y: Double): RummyCanvasPoint {
        val p = view.transform.toScreen(RummyCanvasPoint(x, y))
        return RummyCanvasPoint(p.x + layout.table.x, p.y + layout.table.y)
    }

    @Test
    fun hitClassTable() {
        val tile = layout.rackGeometry.frame(RummyRackSlot(0, 2))
        assertEquals(GamesRummyHit.RackTile(101), classify(RummyCanvasPoint(layout.rack.x + tile.midX, layout.rack.y + tile.midY)))
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(layout.rack.maxX - 10, layout.rack.maxY - 2)), "받침대 빈칸은 무시")
        assertEquals(GamesRummyHit.BoardTile(1), classify(screen(100.0 + 40 + 20, 70.0)))
        // 손잡이: 묶음 왼쪽 바깥 28.
        val edge = screen(100.0, 70.0)
        assertEquals(GamesRummyHit.MeldHandle(0), classify(RummyCanvasPoint(edge.x - 10, edge.y)))
        assertEquals(GamesRummyHit.MeldHandle(0), classify(RummyCanvasPoint(edge.x - 27, edge.y)))
        assertEquals(GamesRummyHit.Felt, classify(RummyCanvasPoint(edge.x - 29, edge.y)), "28 밖은 펠트")
        assertEquals(GamesRummyHit.Felt, classify(screen(300.0, 300.0)))
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(40.0, 200.0)), "왼쪽 열")
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(layout.submit.midX, layout.submit.midY)), "오른쪽 열")
        assertEquals(GamesRummyHit.None, classify(RummyCanvasPoint(layout.status.midX, layout.status.midY)), "상태 줄")
    }

    /** 옆 묶음의 나머지 터치 폭이 앞 묶음 타일 위로 겹치면 타일이 먼저다 — 타일을 못 집으면 안 된다. 막대 둘레만 타일보다 먼저다. */
    @Test
    fun tileWinsOverANeighboursHandleExceptTheDrawnBar() {
        val close = RummyTableLayout(listOf(3, 3), listOf(RummyPoint(100, 50), RummyPoint(236, 50)))
        val second = view.transform.toScreen(RummyCanvasPoint(236.0, 70.0))
        fun hit(x: Double): GamesRummyHit = GamesRummyHitTester.classify(
            RummyCanvasPoint(x + layout.table.x, second.y + layout.table.y), layout, layout.rackGeometry, rackLayout, view.transform, close, listOf(listOf(0, 1, 2), listOf(3, 4, 5)), true,
        )
        val bar = GamesRummyGestureRules.handleBar(view.transform.rect(close.frames[1]), view.scale)
        val grab = GamesRummyGestureRules.handleGrabRect(view.transform.rect(close.frames[1]), view.scale)
        assertEquals(GamesRummyHit.MeldHandle(1), hit(bar.midX), "붙은 묶음에서 막대를 눌렀는데 앞 타일이 뽑혔다")
        assertEquals(GamesRummyHit.BoardTile(2), hit(grab.x - 2), "막대 둘레 밖인데 앞 타일을 못 집는다")
        assertTrue(grab.maxX <= second.x + 0.001, "둘레가 자기 첫 타일을 먹었다")
        assertEquals(GamesRummyHit.BoardTile(3), hit(second.x + 1), "자기 첫 타일을 못 집는다")
    }

    @Test
    fun handleOfALeftEdgeMeldIsReachableAfterPanning() {
        val edgeTable = RummyTableLayout(listOf(3), listOf(RummyPoint(0, 50)))
        var current = view
        fun hit(x: Double, y: Double): GamesRummyHit = GamesRummyHitTester.classify(
            RummyCanvasPoint(x + layout.table.x, y + layout.table.y), layout, layout.rackGeometry, RummyRackLayout(), current.transform, edgeTable, listOf(listOf(0, 1, 2)), true,
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
        assertEquals(GamesRummyHit.RackTile(100), classify(RummyCanvasPoint(layout.rack.x + tile.midX, layout.rack.y + tile.midY), editable = false))
    }

    @Test
    fun liftRules() {
        assertEquals(RummyCanvasPoint(10.0, 52.0), GamesRummyGestureRules.liftedPoint(RummyCanvasPoint(10.0, 100.0)))
        assertEquals(1.25, GamesRummyGestureRules.liftScale, 0.0)
        assertEquals(500L, GamesRummyGestureRules.liftDelayMillis)
        assertEquals(8.0, GamesRummyGestureRules.dragThreshold, 0.0)
        for (size in screens + lowAndroid) {
            val each = GamesRummyMatchLayout(size)
            val rack = each.rack
            assertEquals(48.0, each.fingerLift(rack.y - 1), 0.0)
            assertEquals(48.0, each.fingerLift(rack.y), 0.0)
            assertEquals(GamesRummyGestureRules.fingerLiftAtBottom, each.fingerLift(rack.maxY), 0.001)
            var last = Double.NEGATIVE_INFINITY
            var y = 0.0
            while (y <= size.height + 30) {
                val pointer = y - each.fingerLift(y)
                assertTrue(pointer > last, "$size $y: 손을 내렸는데 기준점이 올라갔다")
                last = pointer
                assertEquals(y, each.finger(RummyCanvasPoint(5.0, pointer)).y, 0.001, "$size $y: 역산")
                y += 0.5
            }
            // 받침대 아랫줄 가운데에 놓는 손 자리가 화면 안이다(48 그대로면 화면 끝 몇 dp 뿐이다).
            val row = rack.y + each.rackGeometry.rowCenter(1)
            assertTrue(each.finger(RummyCanvasPoint(5.0, row)).y < size.height, "$size: 아랫줄 손 자리가 화면 밖")
            assertTrue(row + 48 > size.height - 8, "기준선: 48 그대로면 끝자리다 — 이 값이 없어지면 줄임이 필요 없다")
        }
    }

    // MARK: 놓을 자리(코어 판정기 + 폰 칸)

    @Test
    fun dropTargetsOnThePhoneRegions() {
        fun target(point: RummyCanvasPoint, myTurn: Boolean = true): RummyDropTarget? =
            RummyDropResolver.target(point, 0, 1, layout.regions, view.transform, table, layout.rackGeometry, myTurn)
        val tile = layout.rackGeometry.frame(RummyRackSlot(1, 6))
        assertEquals(RummyDropTarget.RackSlot(RummyRackSlot(1, 6)), target(RummyCanvasPoint(layout.rack.x + tile.midX, layout.rack.y + tile.midY)))
        assertEquals(RummyDropTarget.Meld(0, 2), target(screen(165.0, 70.0)))
        assertEquals(RummyDropTarget.NewMeldAt(RummyPoint(280, 272)), target(screen(300.0, 300.0)))
        assertEquals(null, target(screen(300.0, 300.0), myTurn = false))
        assertEquals(null, target(RummyCanvasPoint(40.0, 10.0)), "왼쪽 열엔 못 놓는다")
        assertEquals(null, target(RummyCanvasPoint(layout.submit.midX, layout.submit.midY)), "오른쪽 열엔 못 놓는다")
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
