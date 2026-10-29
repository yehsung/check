// 원본: 없음 — 체스 화면 순수 표(ChessMatchChrome · ChessRankingPlan · ChessRobotChrome)의 이식 시험. Swift GamesChessMatchTests·GamesChessRankingTests·GamesChessAITests 와
// 같은 판정을 실서버 픽스처로 잰다(기대값은 손으로 적는다 — 구현을 거울처럼 다시 쓰지 않는다).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.stores.chess.ChessMatchOutcome
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessRankEntry
import com.yehsung.aingcheck.core.stores.chess.ChessRankingBoard
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.startAIMatch
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameRig
import com.yehsung.aingcheck.ui.games.gomoku.CHESS_FIXTURES
import com.yehsung.aingcheck.ui.games.gomoku.fixtureJSON
import com.yehsung.aingcheck.ui.games.gomoku.fixtureText
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChessPlansTest {
    private fun payload(name: String): ChessStatePayload = SwiftJson.decode(ChessStatePayload.serializer(), fixtureText(CHESS_FIXTURES, name))

    private fun rigWith(me: String, fixture: String): BoardGameRig {
        val rig = BoardGameRig(me = null)
        rig.host.session = com.yehsung.aingcheck.core.wire.SupabaseSession("t", null, me)
        rig.chess.applyState(payload(fixture))
        return rig
    }

    private val users get() = fixtureJSON(CHESS_FIXTURES, "_manifest")["users"]!!.jsonObject
    private fun user(key: String) = users[key]!!.jsonPrimitive.content

    @Test
    fun timeoutLossAndFideInsufficientDrawAreDifferentSentences() {
        // 흑이 시간패(백 승) — 흑 시점.
        val lost = rigWith(user("B"), "chess_state__end_timeout")
        val lostMatch = assertNotNull(lost.chess.match)
        val lostChrome = ChessMatchChrome.make(lostMatch, null, null, isBusy = false, isRobotMatch = false, initialMs = 600_000)
        val lostResult = assertNotNull(lostChrome.result)
        assertEquals(ChessMatchOutcome.lost, lostMatch.outcome)
        assertEquals(ChessMatchTint.bad, lostResult.tint)
        assertEquals(-lostMatch.stake, lostResult.rubyDelta)
        assertNull(lostResult.rubyNote)
        // FIDE 6.9 — 깃발은 떨어졌지만 메이트 재료가 없어 무승부(백 시점).
        val draw = rigWith(user("A"), "chess_state__end_timeout_insufficient")
        val drawMatch = assertNotNull(draw.chess.match)
        val drawResult = assertNotNull(ChessMatchChrome.make(drawMatch, null, null, false, false, 600_000).result)
        assertEquals(ChessMatchOutcome.draw, drawMatch.outcome)
        assertTrue(drawResult.isDraw)
        assertEquals(0L, drawResult.rubyDelta)
        assertEquals(ChessPhoneText.drawRefund(drawMatch.stake), drawResult.rubyNote, "무승부 환불 한 줄")
        assertNotEquals(lostResult.reason, drawResult.reason, "timeout 과 timeout_insufficient 가 같은 문장")
        assertEquals(ChessMatchChrome.ActionRow.finished(showsPlayAgain = false), lostChrome.actionRow)
        lost.close(); draw.close()
    }

    @Test
    fun robotResultShowsNoRubyAndOffersPlayAgain() {
        val rig = BoardGameRig(me = null)
        rig.chess.startAIMatch(ChessColor.white)
        val match = assertNotNull(rig.chess.match)
        val chrome = ChessMatchChrome.make(match, null, null, isBusy = false, isRobotMatch = true, initialMs = 600_000)
        assertEquals(false, chrome.showsStake)
        assertNull(chrome.stakeSuffix)
        assertEquals(ChessMatchChrome.ActionRow.playing(canOfferDraw = false, canResign = true), chrome.actionRow, "로봇 판에는 무승부 제안이 없다")
        rig.close()
    }

    @Test
    fun boardNeverWidensTheColumnAtAnyPhoneWidth() {
        // 기본 글자 전용 결함: 판 한 변이 화면 폭으로 정해지면 8의 배수 내림 때문에 모든 폭에서 10~16pt 넘쳤다. 열 폭(화면 − 여백 2×16)을 넘지 않아야 한다.
        for (width in listOf(320, 360, 375, 390, 393, 402, 412, 430)) {
            val side = ChessMatchChrome.side(width.dp, 800.dp, 16.dp, isLargeText = false, isAccessibilitySize = false)
            assertTrue(side <= (width - 32).dp, "폭 $width 에서 판 $side 가 열을 넘는다")
            assertEquals(0f, side.value % 8f, "폭 $width 에서 판 $side 가 8의 배수가 아니다(격자 이음선)")
        }
        // 화면 폭을 그대로 넘기던 옛 식은 넘친다 — 위 단언이 늘 참이 아니다.
        val naive = com.yehsung.aingcheck.core.stores.chess.GamesChessBoardMetrics.side(com.yehsung.aingcheck.core.stores.gomoku.BoardSize(402.0, 800.0))
        assertTrue(naive > 402 - 32, "옛 식(화면 폭 예산)도 열 안에 든다 — 이 시험이 아무것도 못 잡는다")
        // 큰 글자에서만 높이 예산으로 줄인다.
        assertEquals(312.dp, ChessMatchChrome.boardSide(368.dp, 600.dp, isLargeText = true, isAccessibilitySize = false))
        assertEquals(368.dp, ChessMatchChrome.boardSide(368.dp, 600.dp, isLargeText = false, isAccessibilitySize = false))
    }

    @Test
    fun resignTapIsIgnoredForOneSecondAfterTheScreenAppears() {
        val shown = com.yehsung.aingcheck.ui.games.gomoku.boardClock
        assertEquals(false, ChessMatchChrome.acceptsResignTap(shown, shown.addingTimeInterval(0.4)))
        assertEquals(true, ChessMatchChrome.acceptsResignTap(shown, shown.addingTimeInterval(1.0)))
        assertEquals(true, ChessMatchChrome.acceptsResignTap(null, shown))
    }

    @Test
    fun rankingDropsZeroGameRowsAndKeepsTheBranchOrder() {
        val u = { id: String -> ChessUser(id, id, null, null, false, false, false) }
        val rows = listOf(
            ChessRankEntry("a", 1, u("a"), 3, 0, 0, 3),
            ChessRankEntry("z", 2, u("z"), 0, 0, 0, 0),
            ChessRankEntry("b", 3, u("b"), 0, 1, 0, -1),
        )
        assertEquals(listOf("a", "b"), ChessRankingPlan.playable(rows).map { it.id }, "0판인 사람이 끼었다")
        // 행 → 준비 중 → 빈·실패·로딩.
        assertEquals(ChessRankingPlan.Content.rows, ChessRankingPlan.content(hasRows = true, rankingUnavailable = true, hasLoaded = true, lastFailed = true))
        assertEquals(ChessRankingPlan.Content.soon, ChessRankingPlan.content(hasRows = false, rankingUnavailable = true, hasLoaded = true, lastFailed = false))
        assertEquals(ChessRankingPlan.Content.empty, ChessRankingPlan.content(hasRows = false, rankingUnavailable = false, hasLoaded = true, lastFailed = false))
        assertEquals(ChessRankingPlan.Content.failed, ChessRankingPlan.content(hasRows = false, rankingUnavailable = false, hasLoaded = false, lastFailed = true))
        assertEquals(ChessRankingPlan.Content.loading, ChessRankingPlan.content(hasRows = false, rankingUnavailable = false, hasLoaded = false, lastFailed = false))
        // 스토어 위에서도: 0판 행만 든 순위는 "행 없음"이다.
        val rig = BoardGameRig(me = null)
        rig.chess.ranking = ChessRankingBoard(listOf(rows[1]), null, null)
        rig.chess.hasLoadedRanking = true
        assertEquals(ChessRankingPlan.Content.empty, ChessRankingPlan.content(rig.chess))
        assertNull(ChessRankingPlan.sinceCaption(BoardGameRig(me = null).chess), "한 번도 못 받았는데 기간을 말한다")
        rig.close()
    }

    @Test
    fun robotEntryNeedsNoSignInAndTellsWhyItIsClosed() {
        assertEquals(false, ChessRobotChrome.REQUIRES_SIGN_IN)
        assertEquals(0L, ChessRobotChrome.STAKE)
        assertEquals(false, ChessRobotChrome.ENTERS_RANKING)
        // 세션 없는 스토어에서 입구가 열리고 판이 선다.
        val rig = BoardGameRig(me = null)
        assertTrue(ChessRobotChrome.of(rig.chess).canStart)
        assertNull(ChessRobotChrome.blockReason(rig.chess))
        rig.chess.startAIMatch(ChessColor.black)
        val chrome = ChessRobotChrome.of(rig.chess)
        assertEquals(ChessRobotChrome.Stage.playing, chrome.stage)
        assertEquals(false, assertNotNull(chrome.board).whiteAtBottom, "흑을 고르면 흑이 아래")
        assertEquals(0L, chrome.matchStake)
        rig.close()
        // 보낸 신청만 있다 — "두는 중"이 아니라 "답을 기다리는 중".
        val out = BoardGameRig(me = null)
        out.chess.outgoing = com.yehsung.aingcheck.core.stores.chess.ChessInvite("x", ChessUser("p", "p", null, null, true, true, false), 3, com.yehsung.aingcheck.ui.games.gomoku.boardClock)
        assertEquals(ChessPhoneText.RobotBlock.outgoingInvite, ChessRobotChrome.blockReason(out.chess))
        out.close()
    }
}
