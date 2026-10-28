// 원본: Tests/CheckMobileKitTests/GamesGomokuBoardTests.swift · GamesGomokuWatchTests.swift · GamesAIMatchTests.swift(순수 판정 몫) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.ai.GomokuAIGame
import com.yehsung.aingcheck.core.rules.ai.GomokuAISearchLimits
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuRules
import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 폰 오목 판정(순수) — 좌표 · 미리보기 탭 · 승리선 · 규칙 예시 · 관전 상태 줄 · 차례 경고 판 몫 · 폰 AI 선택기 수명. */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuPhoneRulesTest {
    private fun match(id: String = "m", moveCount: Int = 0, turn: GomokuColor? = GomokuColor.black, myColor: GomokuColor = GomokuColor.black,
                      finished: Boolean = false, deadline: SwiftDate? = SwiftDate(100.0), board: GomokuBoard = GomokuBoard()) =
        GomokuMatchState(
            id = id, stake = 3, myColor = myColor, opponent = peerFor("o"), board = board, lastMove = null, moveCount = moveCount,
            turn = turn, deadline = deadline, isFinished = finished, outcome = null, endReason = null, rubyDelta = null, blackPassed = false,
        )

    @Test
    fun geometryRoundTripsEveryIntersectionAndRejectsTheMargin() {
        val geometry = GomokuPhoneBoardGeometry(side = 300.0)
        for (y in 0 until 15) for (x in 0 until 15) {
            val point = GomokuPoint.at(x, y)!!
            assertEquals(point, geometry.point(geometry.location(point)), "교차점 $point 왕복")
        }
        // 행은 아래가 1 — 화면 맨 위 왼쪽 교차점은 A15.
        assertEquals(GomokuPoint.at(0, 14), geometry.point(BoardPoint(geometry.inset, geometry.inset)))
        // 반 칸 넘게 바깥이면 판 밖.
        assertNull(geometry.point(BoardPoint(geometry.inset - geometry.cell * 0.6, geometry.inset)))
        assertEquals(listOf("D4", "L4", "H8", "D12", "L12"), GomokuPhoneBoardGeometry.starPoints.map { it.notation })
        // 규칙 예시 9×9 자르기.
        val crop = GomokuPhoneBoardGeometry(side = 180.0, lines = 9, originX = 3, originY = 3)
        assertTrue(crop.contains(GomokuPoint.fromNotation("H8")!!))
        assertFalse(crop.contains(GomokuPoint.fromNotation("A1")!!))
    }

    @Test
    fun roundingIsHalfAwayFromZeroLikeSwift() {
        assertEquals(3L, roundHalfAwayFromZero(2.5))
        assertEquals(-3L, roundHalfAwayFromZero(-2.5))
        assertEquals(2L, roundHalfAwayFromZero(2.4999))
    }

    @Test
    fun tapPreviewPlacesOnlyOnTheSameBoardAndCount() {
        val preview = GomokuTapPreview()
        val m = match()
        val p = GomokuPoint.at(7, 7)!!
        assertEquals(GomokuTapOutcome.preview(p), preview.tap(p, m, isBusy = false, forbidden = emptyMap()))
        assertEquals(p, preview.visiblePoint(m, isBusy = false, forbidden = emptyMap()))
        // 서버가 그 사이 한 수를 넘겼다 — 같은 칸을 다시 눌러도 곧바로 두지 않고 미리보기부터 다시 세운다.
        val advanced = m.copy(moveCount = 1)
        assertNull(preview.visiblePoint(advanced, isBusy = false, forbidden = emptyMap()))
        assertEquals(GomokuTapOutcome.preview(p), preview.tap(p, advanced, isBusy = false, forbidden = emptyMap()))
        assertEquals(GomokuTapOutcome.place(p), preview.tap(p, advanced, isBusy = false, forbidden = emptyMap()))
        assertNull(preview.point)
        // 둘 수 없는 때는 스토어로 넘겨 거절 이유를 말하게 한다(조용히 삼키지 않는다).
        assertEquals(GomokuTapOutcome.refuse(p), preview.tap(p, m.copy(turn = GomokuColor.white), isBusy = false, forbidden = emptyMap()))
        assertEquals(GomokuTapOutcome.none, preview.tap(null, m, isBusy = false, forbidden = emptyMap()))
    }

    @Test
    fun winLineFindsTheFiveThroughTheLastMove() {
        val board = GomokuBoard()
        for (x in 3..7) board[GomokuPoint.at(x, 4)!!] = GomokuColor.black
        val ends = GomokuPhoneWinLine.ends(board, GomokuPoint.at(5, 4))
        assertEquals<Pair<GomokuPoint, GomokuPoint>?>(GomokuPoint.at(3, 4)!! to GomokuPoint.at(7, 4)!!, ends)
        board[GomokuPoint.at(7, 4)!!] = null
        assertNull(GomokuPhoneWinLine.ends(board, GomokuPoint.at(5, 4)), "네 개로 승리선을 그렸다")
    }

    @Test
    fun ruleExamplesAgreeWithTheRenjuJudge() {
        assertEquals(6, GomokuPhoneRuleExample.all.size)
        for (example in GomokuPhoneRuleExample.all) {
            val verdict = GomokuRules.judge(example.board, GomokuPoint.fromNotation(example.point)!!, GomokuColor.black)
            assertEquals(example.expected, verdict, "${example.id} ${example.title}")
            // 여섯 예시 모두 H8 을 가운데로 둔 9×9 안에 들어온다.
            val crop = GomokuPhoneBoardGeometry(side = 1.0, lines = GomokuPhoneRuleExample.cropLines,
                originX = GomokuPhoneRuleExample.cropOriginX, originY = GomokuPhoneRuleExample.cropOriginY)
            for (n in example.black + example.white + listOf(example.point)) assertTrue(crop.contains(GomokuPoint.fromNotation(n)!!), "${example.id} $n")
        }
        assertEquals(GomokuPhoneRuleExample.Mark.pivot, GomokuPhoneRuleExample.all.last().marks[GomokuPoint.fromNotation("I8")])
        assertTrue(GomokuPhoneRuleExample.ruleLines.none { "수수료" in it }, "v0.3.64 에 없앤 수수료 문구가 남았다")
        assertEquals(GomokuJudgement.Win, GomokuPhoneRuleExample.all.first { it.id == "K24" }.expected)
    }

    @Test
    fun watchStatusNeverInventsALossAndNamesTheWinner() {
        val black = peerFor("b").copy(displayName = "달토끼")
        val white = peerFor("w").copy(displayName = "")
        val loading = GomokuSpectateState("x")
        assertEquals(GomokuPhoneWatchStatus.Kind.loading, GomokuPhoneWatchStatus.kind(loading, SwiftDate(0.0)))
        val live = loading.copy(black = black, white = white, turn = GomokuColor.black, deadline = SwiftDate(10.0))
        assertEquals(GomokuPhoneWatchStatus.Kind.turn(GomokuColor.black), GomokuPhoneWatchStatus.kind(live, SwiftDate(5.0)))
        // 마감이 지나도 "졌다"가 아니다 — 곧 자동으로 놓인다.
        assertEquals(GomokuPhoneWatchStatus.Kind.overdue, GomokuPhoneWatchStatus.kind(live, SwiftDate(10.0)))
        assertEquals("관전 중 · 시간이 지나 곧 자동으로 놓여요", GomokuPhoneWatchStatus.text(live, SwiftDate(11.0)))
        val ended = live.copy(isFinished = true, winner = GomokuColor.white, endReason = GomokuEndReason.abandoned)
        // 이긴 백의 이름이 비었다 — 색 이름으로 접는다. 사유는 진 쪽 것이라 "상대 자리 비움".
        assertEquals("대국이 끝났어요 · 백 승 (상대 자리 비움)", GomokuPhoneWatchStatus.text(ended, SwiftDate(0.0)))
        assertEquals("무승부 · 판이 가득 찼어요", GomokuPhoneWatchText.watchEnded(null, GomokuEndReason.boardFull))
        // 연속 경고 — 이름이 비면 줄을 세우지 않는다.
        assertEquals("달토끼님이 한 번 더 놓치면 져요", GomokuPhoneWatchStatus.streakWarning(live.copy(blackAutoStreak = 2), lossStreak = 3))
        assertNull(GomokuPhoneWatchStatus.streakWarning(live.copy(whiteAutoStreak = 2), lossStreak = 3))
        // 빈 판은 돌 개수로만 판정한다 — 돌이 있는데 마지막 수를 모르면 그렇게 말한다.
        val board = GomokuBoard().also { it[GomokuPoint.at(0, 0)!!] = GomokuColor.black }
        assertEquals("오목판, 흑 1개, 백 0개, 마지막 수는 몰라요, 관전 중 · 흑 차례",
            GomokuPhoneWatchText.watchBoardAccessibility(live.copy(board = board)))
        // W2-e 바탕 표와 같은 글자(병합 뒤 접는다 — 손으로 적은 값).
        assertEquals("흑", GomokuPhoneWatchText.stoneShort(GomokuColor.black))
        assertEquals("백", GomokuPhoneWatchText.stoneShort(GomokuColor.white))
        assertEquals("판돈 —", GomokuPhoneWatchText.watchStakeUnknown)
    }

    @Test
    fun turnWarningWatchesOnlyMyRunningClock() {
        assertFalse(GomokuTurnWarning.watchesMyClock(null), "판이 없으면 스토어가 false 로 접는다")
        assertTrue(GomokuTurnWarning.watchesMyClock(match()))
        assertFalse(GomokuTurnWarning.watchesMyClock(match(turn = GomokuColor.white)), "상대 차례 마감에 내 경고가 섰다")
        assertFalse(GomokuTurnWarning.watchesMyClock(match(deadline = null)), "멈춘 시계(AI 판 일시정지)에 경고가 섰다")
        assertFalse(GomokuTurnWarning.watchesMyClock(match(finished = true, turn = null)))
    }

    @Test
    fun stakeSelectionAndResignGuard() {
        assertNull(GomokuPhoneStakeSelection.toggled(GomokuStake.five, GomokuStake.five))
        assertEquals(GomokuStake.ten, GomokuPhoneStakeSelection.toggled(GomokuStake.five, GomokuStake.ten))
        assertTrue(GomokuPhoneStakeSelection.affordable(GomokuStake.ten, null), "잔액을 모르면 막지 않는다")
        assertFalse(GomokuPhoneStakeSelection.affordable(GomokuStake.ten, 9))
        assertFalse(GomokuPhoneResignGuard.acceptsTap(SwiftDate(10.0), SwiftDate(10.5)))
        assertTrue(GomokuPhoneResignGuard.acceptsTap(SwiftDate(10.0), SwiftDate(11.0)))
    }

    @Test
    fun phoneThinkerDropsAnInterruptedSearchAndThinksAgainOnReturn() = runTest {
        val thinker = GamesGomokuAIThinker()
        thinker.searchDispatcher = StandardTestDispatcher(testScheduler)
        var calls = 0
        thinker.engine = GamesGomokuAIThinker.Engine { _, _, _, isCancelled ->
            calls += 1
            if (calls == 1) {
                // 첫 탐색은 떠남(허락 거둠)에 끊긴다 — 끊긴 결과(덜 생각한 수)는 버려야 한다.
                thinker.setAllowed(false)
                assertTrue(isCancelled(), "허락을 거뒀는데 엔진에 취소가 안 닿았다")
                GomokuPoint.at(0, 0)
            } else {
                GomokuPoint.at(7, 7)
            }
        }
        assertEquals(GomokuAISearchLimits().timeBudget, GamesGomokuAIThinker.phoneLimits.timeBudget, "폰 한도가 맥 기본값과 갈렸다")
        thinker.setAllowed(true)
        val answer = async { thinker.choose(GomokuBoard(), GomokuColor.black) }
        runCurrent()
        assertEquals(1, thinker.searchesInterrupted)
        assertEquals(1, thinker.waitingCount, "끊긴 뒤 허락을 기다리지 않는다")
        thinker.setAllowed(true)
        assertEquals(GomokuPoint.at(7, 7), answer.await(), "끊긴 탐색의 수를 그대로 뒀다")
        assertEquals(2, thinker.searchesStarted)
        thinker.isStillNeeded = { _, _ -> false }
        assertNull(thinker.choose(GomokuBoard(), GomokuColor.black), "필요 없는 판에서 다시 생각했다")
    }

    /**
     * 판 종류별 표(Swift `GomokuPhoneMatchChrome` 의 판정 몫 — GamesAIMatchTests "사람 판 화면 표는 그대로다" · "결과 뒤 다시 두기").
     * 판 종류는 코어 서버 차단과 **같은 판정**(id 머리말 `ai-`) — 서버 판 id(uuid)는 사람 판이다. 글자 몫은 W2-e 병합 뒤.
     */
    @Test
    fun matchChromeSplitsHumanAndAIMatchesByTheIDPrefix() {
        val human = GomokuPhoneMatchChrome(isAI = false)
        assertTrue(human.showsStake && human.showsChatDrawer, "사람 판에서 판돈 줄·대화 서랍이 빠졌다")
        val server = GomokuAIGame.start(GomokuColor.black, now = 100.0, id = "3f2a8c1e-0000-4000-8000-000000000001").matchState()
        assertFalse(GomokuPhoneMatchChrome(server).isAI, "uuid 판을 AI 판으로 읽었다")
        val aiMatch = GomokuAIGame.start(GomokuColor.black, now = 100.0).matchState()
        assertTrue(aiMatch.id.startsWith("ai-"))
        val ai = GomokuPhoneMatchChrome(aiMatch)
        assertTrue(ai.isAI)
        assertFalse(ai.showsStake, "AI 판에 판돈 줄(걸린 루비가 없다)이 선다")
        assertFalse(ai.showsChatDrawer, "AI 판에 대화 서랍(신고·차단 메뉴)이 선다")
        // 서버 1:1 판(스토어가 실제로 세운 판)도 같은 판정이다.
        assertFalse(GomokuPhoneMatchChrome(match(id = HAND_MATCH)).isAI)
    }
}
