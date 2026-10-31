// 원본: Tests/checkTests/V0369RummyV2MatchTests.swift:196 (canvasTransform · rackSlots · dropResolver) · Tests/checkTests/V0370RummyBoardFeelTests.swift(1cbaa4d1 RummyBoardVerticalCenterTests) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyLayout
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 맥 표준 판 칸(RummyMatchLayout.standard — 1200×608): 판 158,54 · 884×385, 받침대 158,447 · 689×161. */
private val regions = RummyMatchRegions(
    rack = RummyCanvasRect(158.0, 447.0, 689.0, 161.0),
    table = RummyCanvasRect(158.0, 54.0, 884.0, 385.0),
)
private val viewport = RummyCanvasSize(regions.table.width, regions.table.height)

private val mvTable = listOf("A3 A4 A5", "B7 C7 D7", "C9 C10 C11 C12", "A10 B10 C10", "D1 D2 D3", "B4 B5 B6 B7", "A11 B11 D11", "C1 C2 C3").map { ef(it) }
private val mvLayout = listOf(ep(24, 16), ep(232, 40), ep(520, 8), ep(96, 152), ep(400, 176), ep(680, 120), ep(160, 320), ep(560, 360))

private fun RummyCanvasRect.containsRect(other: RummyCanvasRect): Boolean =
    other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY

class RummyBoardCanvasTest {
    private val whole = RummyCanvasRect(0.0, 0.0, viewport.width, viewport.height)

    @Test
    fun canvasTransform() {
        // 없으면: 그린 묶음과 누르는 묶음이 어긋나거나, 판 확대가 묶음을 칸 밖으로 잘라 안 보이게 한다.
        val fit = RummyCanvasTransform.fit(viewport)
        assertTrue(whole.insetBy(-0.5, -0.5).containsRect(fit.rect(RummyRect(0, 0, 1000, 640))))
        for (p in listOf(RummyCanvasPoint(0.0, 0.0), RummyCanvasPoint(517.0, 233.0), RummyCanvasPoint(1000.0, 640.0))) {
            val back = fit.toLogical(fit.toScreen(p))
            assertTrue(abs(back.x - p.x) < 0.001 && abs(back.y - p.y) < 0.001)
        }
        val layout = RummyTableLayout(mvTable, RummyLayout(mvLayout))
        val small = layout.frames.take(3)
        val zoom = RummyCanvasTransform.zoom(viewport, small)
        assertTrue(zoom.scale > fit.scale * 1.2, "묶음 셋인데 확대가 안 된다(${fit.scale} → ${zoom.scale})")
        assertTrue(zoom.scale <= 1.0001)
        val view = whole.insetBy(-0.5, -0.5)
        for (frame in small) assertTrue(view.containsRect(zoom.rect(frame)), "확대가 묶음 $frame 을 잘랐다")
        // ★ 기준선: 묶음이 판 끝까지 퍼져 있으면 확대해도 맞춤보다 작아지지 않고, 그래도 다 보인다.
        val spread = RummyCanvasTransform.zoom(viewport, layout.frames + RummyRect(900, 580, 80, 56))
        assertTrue(spread.scale >= fit.scale - 0.0001)
        for (frame in layout.frames) assertTrue(view.containsRect(spread.rect(frame)))
    }

    private fun frames(points: List<Pair<Long, Long>>, tiles: Int = 3) = points.map { RummyTableLayout.frame(ep(it.first, it.second), tiles) }

    @Test
    fun contentIsVerticallyCentered() {
        // 1cbaa4d1. 없으면: 위 줄부터 채우는 판이 칸 위로 붙어 아래가 비는 결함(플레이 감사)이 초록이 된다.
        val rows = listOf(listOf(0L to 0L, 216L to 0L, 0L to 72L), listOf(400L to 280L, 620L to 280L), listOf(100L to 584L, 320L to 584L))
        for (row in rows) {
            val content = frames(row)
            val zoom = RummyCanvasTransform.zoom(viewport, content)
            val drawn = content.map { zoom.rect(it) }.reduce { a, b -> a.union(b) }
            assertTrue(abs(drawn.y - (viewport.height - drawn.maxY)) < 0.5, "$row: 위 ${drawn.y} · 아래 ${viewport.height - drawn.maxY}")
            assertTrue(whole.containsRect(drawn), "$row: 잘렸다 $drawn")
        }
    }

    @Test
    fun horizontalAndEmptyStay() {
        // 1cbaa4d1 기준선. 없으면: 세로만 고친다면서 가로 자리나 시작 판까지 바꾼 결함이 초록이 된다.
        val zoom = RummyCanvasTransform.zoom(viewport, frames(listOf(0L to 0L, 216L to 0L)))
        assertEquals(0.0, zoom.logicalOrigin.x)
        assertTrue(zoom.logicalOrigin.y < 0, "구간이 캔버스 위로 나가야 가운데다(${zoom.logicalOrigin.y})")
        assertEquals(RummyCanvasPoint(0.0, 0.0), RummyCanvasTransform.zoom(viewport, emptyList()).logicalOrigin)
    }

    @Test
    fun dropAboveCanvasLandsInside() {
        // 1cbaa4d1. 없으면: 가운데로 옮겨 새로 보이는 캔버스 밖 띠에 놓으면 서버가 못 받는 자리로 가는 결함이 초록이 된다.
        val editor = RummyTurnEditor(listOf(ef("A1 A2 A3")), ef("B9 C2 D13"), true, tableLayout = RummyLayout(listOf(ep(0, 0))))
        val tile = editor.rack.first { it.face.text == "B9" }.id
        val target = RummyDropTarget.NewMeldAt(ep(600, -120))
        val preview = editor.previewDrop(listOf(tile), target)
        assertTrue(editor.move(tile, target))
        val frame = RummyTableLayout.frame(editor.points[1], 1)
        assertTrue(frame.y >= 0 && frame.maxY <= RummyTableLayout.canvasHeight, "놓은 자리 $frame")
        assertEquals(frame, preview?.landing?.frame)
    }

    @Test
    fun rackSlots() {
        // 없으면: 받침대 위 놓기가 반 칸씩 밀리거나 다른 줄로 가고, 3번째 줄 타일이 받침대 밖에 그려진다.
        val g = RummyRackGeometry()
        assertEquals(161.0, g.height)
        assertTrue(abs(g.rowBottom(0) - 0.44 * g.height) < 0.01 && abs(g.rowBottom(1) - 0.76 * g.height) < 0.01)
        for (row in 0 until 2) {
            for (half in 0..30) {
                val slot = RummyRackSlot(row, half)
                val f = g.frame(slot)
                assertEquals(slot, g.slot(f.x + 3, f.midY, 1))
                assertTrue(f.maxX <= regions.rack.width - g.sideInset + 0.5, "타일이 받침대 구간 밖 $slot")
            }
        }
        // 묶음은 끝에서 잘린다(3장이면 반 칸 26 이 마지막).
        assertEquals(RummyRackSlot(1, 26), g.slot(9999.0, g.rowCenter(1), 3))
        val three = RummyRackGeometry(height = g.height, requestedRowCount = 3)
        assertTrue(three.tileSize.height < g.tileSize.height)
        assertTrue(three.frame(RummyRackSlot(0, 0)).y >= 0)
        assertTrue(three.frame(RummyRackSlot(2, 30)).maxY <= 0.77 * g.height)
    }

    @Test
    fun dropResolver() {
        // 없으면: 판 빈 곳에 놓은 묶음이 손 자리와 동떨어진 곳에 생기거나, 남의 차례에 판으로 요청이 나간다.
        val canvas = RummyCanvasTransform.fit(viewport)
        val table = RummyTableLayout(mvTable, RummyLayout(mvLayout))
        val rack = RummyRackGeometry()
        fun screen(x: Double, y: Double): RummyCanvasPoint {
            val p = canvas.toScreen(RummyCanvasPoint(x, y))
            return RummyCanvasPoint(p.x + regions.table.x, p.y + regions.table.y)
        }
        fun target(pointer: RummyCanvasPoint, grab: Int, count: Int, mine: Boolean, skip: Int? = null) =
            RummyDropResolver.target(pointer, grab, count, regions, canvas, table, rack, mine, skip)
        // 묶음 2(C9..C12 @ 520,8)의 셋째 타일 오른쪽 반 → 끼울 자리 3.
        assertEquals(RummyDropTarget.Meld(2, 3), target(screen(520.0 + 40 * 2 + 30, 30.0), 0, 1, true))
        // 빈 곳(논리 300,500)에 한 장 → 그 타일 가운데가 손 자리.
        val empty = screen(300.0, 500.0)
        assertEquals(RummyDropTarget.NewMeldAt(ep(280, 472)), target(empty, 0, 1, true))
        // 셋 묶음을 둘째 장으로 잡았으면 왼쪽 위는 한 장 반 왼쪽.
        assertEquals(RummyDropTarget.NewMeldAt(ep(240, 472)), target(empty, 1, 3, true))
        // 자기 묶음을 통째로 끌면 자기 위는 '빈 곳'(위치 이동).
        assertEquals(RummyDropTarget.NewMeldAt(ep(10, 2)), target(screen(30.0, 30.0), 0, 3, true, skip = 0))
        // 받침대: 앞줄 둘째 칸 자리 → 반 칸 2.
        val slotFrame = rack.frame(RummyRackSlot(1, 2))
        val onRack = RummyCanvasPoint(regions.rack.x + slotFrame.midX, regions.rack.y + slotFrame.midY)
        assertEquals(RummyDropTarget.RackSlot(RummyRackSlot(1, 2)), target(onRack, 0, 1, false))
        // 남의 차례엔 판이 닫힌다 · 판 밖(위 띠)은 없음.
        assertNull(target(empty, 0, 1, false))
        assertNull(target(RummyCanvasPoint(600.0, 10.0), 0, 1, true))
        // 손잡이: 잡은 오프셋을 뺀 왼쪽 위 · 캔버스 밖으로 안 나간다.
        assertEquals(ep(307, 472), RummyDropResolver.setTarget(empty, RummyCanvasPoint(-7.0, 28.0), 3, regions, canvas))
        assertEquals(ep(880, 584), RummyDropResolver.clampedTopLeft(RummyCanvasPoint(990.0, 700.0), 3))
        assertNull(RummyDropResolver.setTarget(RummyCanvasPoint(1.0, 1.0), RummyCanvasPoint(0.0, 0.0), 3, regions, canvas))
    }
}
