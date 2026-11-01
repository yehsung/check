// 원본: Tests/CheckMobileKitTests/V1017RummyResultTests.swift:96-260 @ ios-1017-cube 614d98bd — 말풍선 수명 · 정렬 시차 · 뽑기 비행 · 판 변화의 값 시험.
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyBoardMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardTile
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.stores.rummy.RummyDrawEvent
import com.yehsung.aingcheck.core.stores.rummy.RummyDrawnTile
import com.yehsung.aingcheck.core.stores.rummy.RummyReactionEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GamesRummyMotionTest {
    private val clock = SwiftDate(1_000.0)

    private fun reaction(id: Int, seat: Long, ago: Double) = RummyReactionEvent(id, seat, AingSticker.joy, false, clock.addingTimeInterval(-ago))

    private fun faces(vararg texts: String): List<RummyFace> = texts.map { RummyFace.of(it)!! }

    private fun tile(face: String, id: Int? = null) = RummyBoardTile(id, RummyFace.of(face)!!, false)

    private fun meld(id: String, x: Long, y: Long, tiles: List<RummyBoardTile>) =
        RummyBoardMeld(id, tiles, RummyTableLayout.frame(RummyPoint(x, y), tiles.size), false)

    // MARK: 말풍선

    @Test
    fun onlyTheLatestUnexpiredBubblePerSeatIsVisible() {
        val feed = listOf(reaction(1, 1, 2.0), reaction(2, 1, 0.5), reaction(3, 2, 2.5), reaction(4, 3, 2.49))
        assertEquals(listOf(2, 4), GamesRummyReactionPlan.visible(feed, clock).map { it.id }, "만료 경계 · 최신 고르기")
        assertTrue(GamesRummyReactionPlan.visible(emptyList(), clock).isEmpty())
    }

    /** ★ 맥 0.3.69 CPU 120%: 띄울 것이 없으면 시계가 돌지 않고, 도는 시계는 정해진 프레임에서 끝난다. */
    @Test
    fun theClockStopsAfterTheLastBubble() {
        assertEquals(0, GamesRummyReactionPlan.frameCount(emptyList(), clock))
        assertEquals(0, GamesRummyReactionPlan.frameCount(listOf(reaction(1, 1, 3.0)), clock), "끝난 말풍선이 시계를 돌린다")
        val live = listOf(reaction(1, 1, 1.0))
        val frames = GamesRummyReactionPlan.frameCount(live, clock)
        assertTrue(frames in 1 until 60, "1.5초 남았는데 프레임이 ${frames}개")
        val elapsed = frames * GamesRummyReactionPlan.frameMillis / 1000.0
        assertTrue(elapsed >= 1.5 && elapsed < 1.6, "마지막 프레임 $elapsed 초")
        assertTrue(GamesRummyReactionPlan.visible(live, clock.addingTimeInterval(elapsed)).isEmpty(), "마지막 프레임이 말풍선을 못 지운다")
    }

    @Test
    fun bubbleFadesLinearlyAtTheEndAndPopsAtTheStart() {
        assertEquals(1.0, GamesRummyReactionPlan.opacity(2.19))
        assertTrue(abs(GamesRummyReactionPlan.opacity(2.35) - 0.5) < 0.001, "선형이 아니다")
        assertEquals(0.0, GamesRummyReactionPlan.opacity(2.5))
        assertTrue(abs(GamesRummyReactionPlan.scale(0.0) - 0.5) < 0.0001)
        assertEquals(1.0, GamesRummyReactionPlan.scale(0.22))
        assertTrue(GamesRummyReactionPlan.scale(0.15) > 1.0, "살짝 넘쳤다 돌아와야 한다")
    }

    @Test
    fun bubbleStandsBelowTheOpponentRowAboveTheRackAndInsideTheScreen() {
        val height = GamesRummyReactionPlan.bubbleHeight
        for (width in listOf(320.0, 393.0, 430.0)) {
            val opponent = RummyCanvasRect(0.0, 48.0, 100.0, 48.0)
            assertEquals(GamesRummyReactionPlan.Side.below, GamesRummyReactionPlan.side(opponent))
            val below = GamesRummyReactionPlan.center(opponent, GamesRummyReactionPlan.Side.below, width)
            assertTrue(below.x - height / 2 >= 0 && below.y - height / 2 > opponent.maxY)
            val rack = RummyCanvasRect(0.0, 500.0, width, 118.0)
            assertEquals(GamesRummyReactionPlan.Side.above, GamesRummyReactionPlan.side(rack))
            val mine = GamesRummyReactionPlan.center(rack, GamesRummyReactionPlan.Side.above, width)
            assertTrue(mine.y + height / 2 < rack.y && abs(mine.x - width / 2) < 0.5)
            val right = GamesRummyReactionPlan.center(RummyCanvasRect(width - 40, 200.0, 40.0, 40.0), GamesRummyReactionPlan.Side.above, width)
            assertTrue(right.x + height / 2 <= width)
        }
    }

    // MARK: 받침대

    @Test
    fun sortStaggerFollowsTheSortedReadingOrder() {
        val editor = RummyTurnEditor(table = emptyList(), rack = faces("D3", "A1", "C2", "B9", "A2"), initialDone = true, rackHalfColumns = RummyRackGeometry.phoneHalfColumns)
        val before = editor.rackLayout
        val stagger = GamesRummyRackMotion.sortStagger(editor, RummyRackSort.number)
        val sorted = editor.copy()
        sorted.sortRack(RummyRackSort.number)
        assertEquals(5, stagger.size)
        sorted.rackLayout.readingOrder.forEachIndexed { position, id -> assertEquals(position * 25L, stagger[id], "타일 $id") }
        assertEquals(before, editor.rackLayout, "사본이 아니라 원본을 정렬했다")
    }

    @Test
    fun aDrawFliesUntilItsSerialIsDoneAndNeverWithReducedMotion() {
        val event = RummyDrawEvent(3, listOf(RummyDrawnTile(7, RummyFace.of("A1")!!, RummyRackSlot(0, 0))))
        assertEquals(GamesRummyRackFlight(3, setOf(7)), GamesRummyRackMotion.flight(event, 2, reduceMotion = false))
        assertNull(GamesRummyRackMotion.flight(event, 3, reduceMotion = false), "끝난 사건이 또 난다")
        assertNull(GamesRummyRackMotion.flight(event, null, reduceMotion = true), "동작 줄이기에 난다")
        assertNull(GamesRummyRackMotion.flight(null, null, reduceMotion = false))
        assertEquals(1f, GamesRummyRackMotion.flightScale(1f))
        assertEquals(0f, GamesRummyRackMotion.flightDegrees(1f), 0.0001f, "내려앉았는데 기울어 있다") // 시작 각이 음수라 -0.0 이 나온다(같은 0도).
        assertTrue(GamesRummyRackMotion.flightScale(0f) < 1f && GamesRummyRackMotion.flightDegrees(0f) != 0f)
    }

    @Test
    fun theFlightStartsInsideTheDrawButtonAtEveryWidthAndTextScale() {
        for (width in listOf(320.0, 393.0, 430.0)) {
            val size = RummyCanvasSize(width, 759.0)
            for (scale in listOf(1.0, 1.6)) {
                val layout = GamesRummyMatchLayout(size, actionHeight = GamesRummyMatchLayout.actionHeight(scale))
                val origin = layout.drawOrigin(scale)
                val screen = RummyCanvasPoint(origin.x + layout.rack.x, origin.y + layout.rack.y)
                assertTrue(layout.actions.contains(screen), "$width $scale: $screen")
                assertTrue(origin.y > layout.rack.height, "받침대 아래에서 출발해야 한다")
            }
            val widths = GamesRummyMatchLayout.actionWidths(width)
            val gap = GamesRummyMatchLayout.actionGap
            val x = GamesRummyMatchLayout(size).drawOrigin(1.0).x
            assertTrue(x > gap + widths.submit + gap && x < gap + widths.submit + gap + widths.draw, "[완료] · [되돌리기] 쪽에서 출발한다")
        }
    }

    /** SwiftUI response 와 같은 주기 — 강성이 어긋나면 맥 · iOS 와 다른 빠르기다. */
    @Test
    fun springStiffnessComesFromTheResponse() {
        assertEquals(194.96, GamesRummySpring.stiffness(GamesRummySpring.flightResponse).toDouble(), 0.05)
        assertEquals(273.4, GamesRummySpring.stiffness(GamesRummySpring.slideResponse).toDouble(), 0.05)
    }

    // MARK: 판 변화

    @Test
    fun onlyMovedMeldsFlyAndNewTilesDoNot() {
        val old = listOf(meld("a", 40, 16, listOf(tile("A1"), tile("A2"), tile("A3"))), meld("b", 400, 16, listOf(tile("B4"), tile("B5"), tile("B6"))))
        assertNull(GamesRummyBoardMotion.make(old, old))
        assertNull(GamesRummyBoardMotion.make(emptyList(), old), "처음 그릴 때 날면 안 된다")
        val moved = listOf(old[0], meld("b", 100, 200, old[1].tiles))
        val motion = assertNotNull(GamesRummyBoardMotion.make(old, moved))
        assertEquals(listOf("B4", "B5", "B6"), motion.moves.map { it.face.text })
        assertEquals((0 until 3).map { GamesRummyBoardMotion.Slot(1, it) }.toSet(), motion.hidden)
        val width = RummyTableLayout.tileWidth.toDouble()
        assertEquals(RummyCanvasPoint(400 + width, 16.0), motion.moves[1].from)
        assertEquals(RummyCanvasPoint(100 + width, 200.0), motion.moves[1].to)
        assertEquals(RummyCanvasPoint(250 + width, 108.0), motion.moves[1].at(0.5))
        val grown = listOf(meld("a", 40, 16, listOf(tile("A1"), tile("A2"), tile("A3"), tile("A4"))), old[1])
        assertNull(GamesRummyBoardMotion.make(old, grown), "뒤에 붙인 타일 때문에 나머지가 날면 안 된다")
    }

    @Test
    fun aDuplicateFaceThatStayedDoesNotCrossOver() {
        val old = listOf(meld("a", 40, 16, listOf(tile("A1"), tile("B1"), tile("C1"))), meld("b", 400, 16, listOf(tile("A1"), tile("A2"), tile("A3"))))
        val new = listOf(old[1], meld("a2", 40, 300, old[0].tiles))
        val motion = assertNotNull(GamesRummyBoardMotion.make(old, new))
        assertEquals(3, motion.moves.size)
        assertTrue(motion.moves.all { it.to.y == 300.0 && it.from.y == 16.0 && it.from.x < 200 }, "${motion.moves}")
    }

    @Test
    fun theTileJustDroppedByHandDoesNotFlyButItsNeighboursDo() {
        val old = listOf(
            meld("a", 40, 16, listOf(tile("A1", 1), tile("A3", 3), tile("A4", 4))),
            meld("b", 400, 16, listOf(tile("A2", 2), tile("B2", 5), tile("C2", 6))),
        )
        val new = listOf(
            meld("a", 40, 16, listOf(tile("A1", 1), tile("A2", 2), tile("A3", 3), tile("A4", 4))),
            meld("b", 400, 16, listOf(tile("B2", 5), tile("C2", 6))),
        )
        val motion = assertNotNull(GamesRummyBoardMotion.make(old, new, excluding = setOf(2)))
        assertFalse(motion.moves.any { it.face.text == "A2" }, "놓은 타일이 옛 자리에서 날아온다")
        assertEquals(setOf("A3", "A4", "B2", "C2"), motion.moves.map { it.face.text }.toSet())
        val without = assertNotNull(GamesRummyBoardMotion.make(old, new))
        assertTrue(without.moves.any { it.face.text == "A2" }, "기준선: 빼지 않으면 난다")
    }

    @Test
    fun reusedIDsPairByFaceAndTooManyMovesAreSkipped() {
        val old = listOf(meld("a", 40, 16, listOf(tile("A1", 1), tile("A2", 2), tile("A3", 3))))
        val new = listOf(meld("a", 40, 16, listOf(tile("B7", 1), tile("B8", 2), tile("B9", 3))))
        assertNull(GamesRummyBoardMotion.make(old, new), "다른 면이 같은 id 로 날아간다")
        val many = (0L until 14L).map { index -> meld("m$index", 40, index * 40, listOf(tile("A1"), tile("A2"), tile("A3"))) }
        val shifted = many.mapIndexed { index, item -> meld(item.id, 300, index * 40L, item.tiles) }
        assertNull(GamesRummyBoardMotion.make(many, shifted), "42장은 상한을 넘는다")
        assertEquals(15, GamesRummyBoardMotion.make(many.take(5), shifted.take(5))?.moves?.size)
    }
}
