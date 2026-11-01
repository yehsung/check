// 원본: Tests/checkTests/V0369RummyPanelRenderTests.swift 의 뜻(결과 줄 · 최종 판) — 픽셀 대신 값으로 잰다. 폰 칸 폭 값은 ios-1017 설계서 §4·§6.
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun id(n: Int): SwiftUUID = SwiftUUID.parse("7e7e0000-0000-4000-8000-00000000000$n")!!

private fun faces(vararg texts: String): List<RummyFace> = texts.map { RummyFace.of(it)!! }

private fun seat(n: Int, no: Long?, state: RummySeatState?, rank: Long? = null, payout: Long? = null, winner: Boolean? = null, name: String = "자리$n") =
    RummyMatchSeat(seatNo = no, userId = id(n), displayName = name, state = state, finalRank = rank, payout = payout, isWinner = winner)

class RummyResultSummaryTest {
    private val match = RummyMatchState(
        id = id(9),
        stake = 5,
        mySeatNo = 0,
        seats = listOf(
            seat(1, 0, RummySeatState.done, rank = 2, payout = 5),
            seat(2, 3, RummySeatState.forfeit, rank = 3, payout = 0),
            seat(3, 1, RummySeatState.done, rank = 1, payout = 10, winner = true, name = "비"),
            seat(4, null, RummySeatState.invited),
            seat(5, 2, RummySeatState.forfeit),
        ),
    )

    @Test
    fun rowsFollowServerRankAndDropInvitedSeats() {
        // 없으면: 초대만 받고 안 온 사람이 등수 줄에 서거나, 자리 순으로 그려져 1등이 가운데 온다.
        val rows = RummyResultSummary.rows(match)
        assertEquals(listOf<Long?>(1, 0, 3, 2), rows.map { it.seatNo })
        assertEquals("비", RummyResultSummary.winnerName(rows))
        assertNull(RummyResultSummary.winnerName(rows.filter { it.isWinner != true }))
        assertTrue(RummyResultSummary.rows(match.copy(seats = null)).isEmpty())
    }

    @Test
    fun rankTiesBreakBySeat() {
        // 공동 등수(막힘 끝 최소 집단)는 자리 순 — 폴링마다 줄이 뒤바뀌면 안 된다.
        val tied = match.copy(seats = listOf(seat(1, 2, RummySeatState.done, rank = 1), seat(2, 0, RummySeatState.done, rank = 1)))
        assertEquals(listOf<Long?>(0, 2), RummyResultSummary.rows(tied).map { it.seatNo })
    }

    @Test
    fun netIsPayoutMinusStake() {
        // 3인 판돈 5: 받는 몫 10·5·0 → 순수익 +5·0·−5(사용자 결정 +N/0/−N). 받은 몫을 그대로 보이면 꼴찌도 '0'이라 잃은 줄 모른다.
        val rows = RummyResultSummary.rows(match)
        assertEquals(5L, RummyResultSummary.net(rows[0], match.stake))
        assertEquals(0L, RummyResultSummary.net(rows[1], match.stake))
        assertEquals(-5L, RummyResultSummary.net(rows[2], match.stake))
        assertEquals(-5L, RummyResultSummary.net(rows[3], match.stake), "payout 이 비면 판돈만큼 잃은 것")
        assertEquals(10L, RummyResultSummary.net(rows[0], null))
    }

    @Test
    fun isMeNeedsASeat() {
        assertTrue(RummyResultSummary.isMe(match.seats!![0], match))
        assertFalse(RummyResultSummary.isMe(match.seats!![2], match))
        // 내 자리도 그 자리도 null 인 판 — null == null 로 모두가 '나'가 되면 안 된다.
        assertFalse(RummyResultSummary.isMe(seat(4, null, RummySeatState.invited), match.copy(mySeatNo = null)))
    }

    @Test
    fun rackLineFitsItsWidth() {
        val tile = RummyResultSummary.rackTile.size.width
        val spacing = RummyResultSummary.rackTileSpacing
        val badge = RummyResultSummary.rackBadgeWidth
        val fourteen = List(14) { RummyFace.joker }
        for (width in listOf(240.0, 288.0, 337.0, 374.0)) {
            val line = RummyResultSummary.rackLine(fourteen, width)
            assertEquals(14, line.shown.size + line.overflow, "장수 보존 w=$width")
            val drawn = line.shown.size * (tile + spacing) + (if (line.overflow > 0) badge else -spacing)
            assertTrue(drawn <= width, "넘침 w=$width drawn=$drawn")
        }
        // 다 들어가면 +N 칸 때문에 한 장을 숨기지 않는다.
        val exact = 3 * tile + 2 * spacing
        assertEquals(RummyResultRackLine(faces("A1", "B2", "C3"), 0), RummyResultSummary.rackLine(faces("A1", "B2", "C3"), exact))
        assertEquals(RummyResultRackLine(emptyList(), 0), RummyResultSummary.rackLine(emptyList(), 100.0))
        // 칸이 없으면 장수만.
        assertEquals(RummyResultRackLine(emptyList(), 2), RummyResultSummary.rackLine(faces("A1", "B2"), 10.0))
    }

    @Test
    fun boardTilesStayWhereTheServerPutThem() {
        // 없으면: 폰이 판을 재배치한다. 위치는 모든 기기에 같아야 한다(사용자 결정 — 설계서 §4).
        val sets = listOf(faces("A1", "A2", "A3"), faces("B7", "C7", "D7"))
        val tiles = RummyResultSummary.boardTiles(sets, RummyLayout(listOf(RummyPoint(80, 40), RummyPoint(400, 320))))
        assertEquals(
            listOf(
                RummyFinalBoardTile(sets[0][0], 80, 40), RummyFinalBoardTile(sets[0][1], 120, 40), RummyFinalBoardTile(sets[0][2], 160, 40),
                RummyFinalBoardTile(sets[1][0], 400, 320), RummyFinalBoardTile(sets[1][1], 440, 320), RummyFinalBoardTile(sets[1][2], 480, 320),
            ),
            tiles,
        )
        assertTrue(RummyResultSummary.boardTiles(emptyList(), null).isEmpty())
        // 옛 판(배치 없음)도 한 장도 잃지 않고 캔버스 안에 선다.
        val placed = RummyResultSummary.boardTiles(sets, null)
        assertEquals(6, placed.size)
        assertTrue(placed.all { it.x in 0..RummyTableLayout.canvasWidth && it.y in 0..RummyTableLayout.canvasHeight })
    }

    @Test
    fun finalBoardWholeViewFitsEveryPhoneWidth() {
        for (width in listOf(320.0, 393.0, 430.0)) {
            val whole = RummyFinalBoardLayout.make(width, 500.0, whole = true)
            assertFalse(whole.scrolls, "w=$width")
            assertTrue(whole.width <= width - RummyFinalBoardLayout.inset * 2 + 0.001, "w=$width")
            assertTrue(whole.height <= 500.0 - RummyFinalBoardLayout.inset * 2 + 0.001, "w=$width")
            assertTrue(abs(whole.height / whole.width - 0.64) < 0.001, "비율 유지 w=$width")
        }
    }

    @Test
    fun finalBoardDefaultViewFollowsTheHeight() {
        // 기준 폰: 설계서 §4 '타일 ≈ 29×41' — 판 화면 기본 보기와 같은 크기로 읽힌다.
        val view = RummyFinalBoardLayout.make(393.0, 500.0, whole = false)
        assertTrue(view.scrolls)
        assertTrue(abs(view.tile.size.width - 29.25) < 0.01, "${view.tile.size}")
        assertTrue(abs(view.tile.size.height - 40.95) < 0.01, "${view.tile.size}")
        assertTrue(RummyFinalBoardLayout.canZoom(393.0, 500.0))
        // 타일 폭 40 상한 — 큰 칸에서 끝없이 커지지 않는다.
        assertEquals(RummyFinalBoardLayout.maxScale, RummyFinalBoardLayout.make(393.0, 2000.0, whole = false).scale)
        // 넓은 칸은 두 보기가 같다(단추를 세우지 않는다) · 기본 보기가 전체 보기보다 작아지지 않는다.
        assertFalse(RummyFinalBoardLayout.canZoom(2000.0, 1500.0))
        assertEquals(RummyFinalBoardLayout.make(2000.0, 1500.0, whole = true).scale, RummyFinalBoardLayout.make(2000.0, 1500.0, whole = false).scale)
    }

    @Test
    fun finalBoardSurvivesAnEmptyView() {
        // 첫 측정 전 0×0 — 음수 배율로 죽으면 결과 화면 전체가 죽는다.
        val zero = RummyFinalBoardLayout.make(0.0, 0.0, whole = false)
        assertTrue(zero.scale > 0)
        assertTrue(zero.width > 0 && zero.height > 0)
    }
}
