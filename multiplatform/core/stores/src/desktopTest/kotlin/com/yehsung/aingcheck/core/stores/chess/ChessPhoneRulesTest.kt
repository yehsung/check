// 원본: Tests/CheckMobileKitTests/GamesChessTextTests.swift · GamesChessBoardTests.swift · GamesChessWatchTests.swift(순수 판정 몫) @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.chess.fromFen
import com.yehsung.aingcheck.core.stores.gomoku.BoardPoint
import com.yehsung.aingcheck.core.stores.gomoku.BoardSize
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 폰 체스 문구·좌표·관전 판정(순수). 돈이 갈리는 자리(FIDE 6.9 · 신청만으로는 0원)와 뒤집기를 손으로 적은 값으로 잰다. */
class ChessPhoneRulesTest {
    @Test
    fun everyDrawReasonSaysDrawAndOnlyThoseDo() {
        for (reason in ChessEndReason.entries) {
            for (outcome in listOf(ChessMatchOutcome.won, ChessMatchOutcome.lost, ChessMatchOutcome.draw, null)) {
                val text = ChessPhoneText.endReason(reason, outcome)
                assertEquals(reason.isDraw, "무승부" in text, "$reason/$outcome → $text (무승부 ⟺ 무승부 사유)")
                assertTrue(text.isNotEmpty())
            }
            val watch = ChessPhoneText.watchEndReason(reason, if (reason.isDraw) null else ChessColor.white)
            assertEquals(reason.isDraw, "무승부" in watch, "관전 $reason → $watch")
        }
        // FIDE 6.9 — 깃발이 떨어졌어도 메이트할 기물이 없으면 무승부다. 두 문장이 섞이면 돌려받은 루비를 잃은 것으로 읽는다.
        assertEquals("시간이 다 됐어요", ChessPhoneText.endReason(ChessEndReason.timeout, ChessMatchOutcome.lost))
        assertEquals("시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요", ChessPhoneText.endReason(ChessEndReason.timeoutInsufficient, ChessMatchOutcome.draw))
        assertEquals("흑이 체크메이트를 당했어요", ChessPhoneText.watchEndReason(ChessEndReason.checkmate, ChessColor.white))
        assertEquals("무승부로 끝났어요", ChessPhoneText.unknownEndReason(ChessMatchOutcome.draw))
        assertEquals("판이 끝났어요", ChessPhoneText.endReason(null, ChessMatchOutcome.lost))
    }

    @Test
    fun stakeWordsNeverClaimTheInviteMovesRubies() {
        val line = ChessPhoneText.stakeNotHeldYet(45)
        assertTrue("빠지지 않아요" in line && "45초" in line, line)
        assertEquals("5 · 이기면 +5", ChessPhoneText.stakeLine(5), "v0.3.64 수수료 0 — 순이익은 판돈 그대로")
        assertEquals("이기면 +10", ChessPhoneText.stakeGain(10))
        assertEquals(listOf(3L, 5L, 10L), ChessPhoneText.stakes)
        assertEquals("수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요", ChessPhoneText.stakeCaption)
        assertEquals("다시 시도", ChessPhoneText.reloadUsers)
        val lines = ChessPhoneRuleLine.all(initialMs = 600_000, incrementMs = 3_000, inviteTtlSeconds = 60)
        assertEquals(8, lines.size)
        assertTrue("10분 + 한 수 3초" in lines.first { it.title == "시간" }.detail)
        assertTrue("무승부" in lines.first { it.title == "시간" }.detail, "시간 줄이 FIDE 6.9 예외를 말하지 않는다")
        assertTrue("1:1 테트리스" in lines.last().detail, "한 사람 한 판 줄이 세 게임을 다 말하지 않는다")
        assertTrue(lines.none { "수수료" in it.detail })
        assertEquals("FIDE 규칙 · 백 선공 · 5분 + 한 수 2초", ChessPhoneText.subtitle(300_000, 2_000), "서버가 말한 시계를 따르지 않는다")
    }

    @Test
    fun busyBlocksNameBothThePlayingGameAndTheBlockedEntry() {
        assertEquals("오목을 두는 중이에요", ChessPhoneText.busyTitle(ChessPhoneText.BusyGame.gomoku))
        assertEquals("1:1 테트리스 대결 중이에요", ChessPhoneText.busyTitle(ChessPhoneText.BusyGame.tetris))
        assertEquals("오목 판이 끝나면 1:1 테트리스를 신청할 수 있어요",
            ChessPhoneText.busyHint(ChessPhoneText.BusyGame.gomoku, ChessPhoneText.BusyGame.tetris))
        assertEquals("체스를 두는 중이에요\n체스 판이 끝나면 오목을 신청할 수 있어요",
            ChessPhoneText.entryBlockNotice(ChessPhoneText.BusyGame.chess, ChessPhoneText.BusyGame.gomoku))
        assertNull(ChessPhoneText.entryBlock(null))
        // 로그인은 사유가 아니다.
        assertNull(ChessPhoneText.robotEntryBlock(signedIn = false, playing = null))
        assertEquals("보낸 신청을 취소하면 로봇과 둘 수 있어요", ChessPhoneText.robotEntryBlockHint(ChessPhoneText.RobotBlock.outgoingInvite))
        assertEquals("을", ChessPhoneText.objectParticle("오목"))
        assertEquals("를", ChessPhoneText.objectParticle("체스"))
        assertEquals("과", ChessPhoneText.withParticle("민트별"))
        assertEquals("와", ChessPhoneText.withParticle("달토끼"))
        assertEquals("를", ChessPhoneText.objectParticle("Kim"))
    }

    @Test
    fun opponentRowSplitsTheWorkAxisFromTheBlockedReason() {
        val oldWorking = ChessUser("u", "솜사탕", null, null, isWorking = true, isCapable = false, inMatch = false)
        assertEquals(ChessPhoneText.OpponentRow("근무 중", "업데이트 필요"), ChessPhoneText.opponentRow(oldWorking))
        assertEquals(ChessPhoneText.OpponentRow("근무 안 함 · 대국 중", "업데이트 필요"),
            ChessPhoneText.opponentRow(oldWorking.copy(isWorking = false, inMatch = true)))
        assertEquals(ChessPhoneText.OpponentRow("근무 중", "대국 중"), ChessPhoneText.opponentRow(oldWorking.copy(isCapable = true, inMatch = true)))
        assertEquals("대국 중", ChessPhoneText.status(oldWorking.copy(inMatch = true)))
    }

    @Test
    fun clockTextRoundsLikeDarwinPrintf() {
        // 기대값은 C printf(`%.1f` — 정확한 이진 값의 최근접, 동률은 짝수)로 따로 뽑은 값이다(Python `'%.1f' % x`, 같은 규칙).
        val table = listOf(
            0.0 to "0.0", 0.04 to "0.0", 0.05 to "0.1", 0.15 to "0.1", 0.25 to "0.2", 0.35 to "0.3", 0.45 to "0.5", 0.75 to "0.8",
            1.25 to "1.2", 2.25 to "2.2", 2.35 to "2.4", 2.45 to "2.5", 3.05 to "3.0", 4.95 to "5.0", 9.95 to "9.9", 9.949 to "9.9",
            9.96 to "10.0", 0.000001 to "0.0", 5.55 to "5.5", 6.65 to "6.7", 7.75 to "7.8", 8.85 to "8.8",
        )
        for ((value, expected) in table) assertEquals(expected, ChessPhoneText.clock(value), "clock($value)")
        assertEquals("1:05", ChessPhoneText.clock(65.9))
        assertEquals("10:00", ChessPhoneText.clock(600.0))
        assertEquals("0.0", ChessPhoneText.clock(-3.0))
        assertEquals("남은 시간 1분 6초", ChessPhoneText.clockAccessibility(65.5))
        assertEquals("흑 남은 시간 3초", ChessPhoneText.clockAccessibility(2.5, ChessColor.black))
        assertEquals("43초", ChessPhoneText.remaining(42.01))
        assertEquals("−3", ChessPhoneText.signedPoints(-3))
        assertEquals("±0", ChessPhoneText.rubyDelta(0))
        assertEquals("1분 35초째", ChessPhoneText.elapsedPhrase(95.9))
    }

    @Test
    fun rankSinceUsesKstEvenOffTheDeviceZone() {
        // 2026-09-30 15:00 UTC = 10-01 00:00 KST — 기기 시간대로 조립하면 9월 30일이 된다.
        assertEquals("10월 1일부터", ChessPhoneText.rankSince(SwiftDate(1_790_780_400.0)))
        assertEquals("12위 · 승점 +4 · 6승 2패 1무", ChessPhoneText.myRankLine(ChessMyRank(12, 6, 2, 1, 4)))
        assertEquals("순위 밖 · 0승 0패 0무", ChessPhoneText.myRankLine(ChessMyRank(null, 0, 0, 0, 0)))
    }

    @Test
    fun geometryFlipsOnlyOnceForBlack() {
        val white = ChessPhoneBoardGeometry(side = 320.0, orientation = ChessColor.white)
        val black = white.copy(orientation = ChessColor.black)
        val a1 = ChessSquare.parse("a1")!!
        assertEquals(0, white.column(a1))
        assertEquals(7, white.row(a1))
        assertEquals(7, black.column(a1))
        assertEquals(0, black.row(a1))
        for (index in 0 until 64) {
            val square = ChessSquare.of(index)!!
            assertEquals(square, white.square(white.center(square)))
            assertEquals(square, black.square(black.center(square)))
        }
        assertNull(white.square(BoardPoint(320.0, 10.0)), "판 끝(side)은 칸이 아니다")
        // 보간 두 끝은 두 칸과 바이트까지 같다.
        val e2 = ChessSquare.parse("e2")!!
        val e4 = ChessSquare.parse("e4")!!
        assertEquals(black.rect(e2), black.rect(e2, e4, 0.0))
        assertEquals(black.rect(e4), black.rect(e2, e4, 1.0))
        // 판 좌표 오프셋은 흑 판에서 양축이 뒤집힌다(rank 는 화면 y 와 반대).
        assertEquals(BoardSize(40.0, -40.0), white.offset(1.0, 1.0))
        assertEquals(BoardSize(-40.0, 40.0), black.offset(1.0, 1.0))
        assertEquals(160.0, GamesChessBoardMetrics.side(BoardSize(100.0, 900.0)))
        assertEquals(360.0, GamesChessBoardMetrics.side(BoardSize(361.0, 900.0)), "8의 배수로 내리지 않았다")
        assertEquals(288.0, GamesChessWatchBudget.boardCap(554.0), "iPhone SE 검산(머리말)")
        assertNull(GamesChessWatchBudget.boardCap(0.0))
    }

    @Test
    fun checkMarkReadsTheFlagButNeverOnAFinishedBoard() {
        val position = ChessPosition.fromFen("4k3/8/8/8/8/8/4q3/4K3 w - - 0 1")!!
        assertEquals(ChessSquare.parse("e1"), GamesChessCheckMark.square(true, false, ChessColor.white, position))
        assertNull(GamesChessCheckMark.square(true, true, ChessColor.white, position), "결과 화면에 빨간 칸이 남았다")
        assertNull(GamesChessCheckMark.square(false, false, ChessColor.white, position))
        val watch = ChessSpectateState("x", position = position, turn = ChessColor.white, isInCheck = true)
        assertEquals(ChessSquare.parse("e1"), GamesChessWatchPlan.boardCheckSquare(watch))
        assertNull(GamesChessWatchPlan.boardTapHandler, "관전 판에 탭 처리기가 붙었다")
        assertTrue(GamesChessWatchPlan.boardWhiteAtBottom)
    }

    @Test
    fun watchStatusNeverInventsAResultFromTheClock() {
        val loading = ChessSpectateState("x")
        assertEquals("판을 불러오고 있어요", GamesChessWatchStatus.headline(loading))
        val u = ChessUser("a", "a", null, null, true, true, true)
        val live = loading.copy(black = u, white = u.copy(id = "b"), turn = ChessColor.black)
        assertEquals("관전 중 · 흑 차례", GamesChessWatchStatus.headline(live))
        assertNull(GamesChessWatchStatus.detail(live))
        val ended = live.copy(isFinished = true, winner = ChessColor.white, endReason = ChessEndReason.resign, turn = null)
        assertEquals("백 승리", GamesChessWatchStatus.headline(ended))
        assertEquals("흑이 기권했어요", GamesChessWatchStatus.detail(ended), "3인칭이 아니다(관전자 자기모순)")
        assertEquals("무승부로 끝났어요", GamesChessWatchStatus.headline(ended.copy(winner = null, endReason = ChessEndReason.agreement)))
        assertFalse(ChessPhoneText.watchCaption.isEmpty())
    }

    @Test
    fun serverClockInterpolatesButNeverBelowZeroAndFlagUsesTheRowBudget() {
        val clock = ChessServerClock(whiteMsLeft = 5_000, blackMsLeft = 9_000, incrementMs = 3_000, turnStartedAt = SwiftDate(100.0), running = ChessColor.white)
        assertEquals(2.0, clock.remainingSeconds(ChessColor.white, SwiftDate(103.0)))
        assertEquals(0.0, clock.remainingSeconds(ChessColor.white, SwiftDate(200.0)))
        assertEquals(9.0, clock.remainingSeconds(ChessColor.black, SwiftDate(200.0)), "흐르지 않는 쪽 시계가 흘렀다")
        assertEquals(SwiftDate(105.0), clock.deadline)
        val state = ChessMatchState(
            id = "m", stake = 3, myColor = ChessColor.black, opponent = ChessUser.chessAI, fen = "", position = null, plyCount = 0,
            turn = ChessColor.white, lastMove = null, moves = emptyList(), clock = clock, isInCheck = false, legalMoves = emptyList(),
            isFinished = false, outcome = null, endReason = null, rubyDelta = null, drawOfferBy = null, drawOfferedByMe = false,
            whiteGraceMs = 0,
        )
        // 유예 예산을 다 쓴 판(행의 white_grace_ms 0) — 로비의 전역 2초를 쓰면 서버에서 이미 끝난 판을 2초 더 기다린다.
        assertTrue(state.isFlagOverdue(SwiftDate(105.5), graceSeconds = 2.0))
        assertFalse(state.copy(whiteGraceMs = null).isFlagOverdue(SwiftDate(105.5), graceSeconds = 2.0))
        assertFalse(state.isFlagOverdue(SwiftDate(105.0), graceSeconds = 2.0), "부등호가 서버(`>`)와 다르다")
        assertEquals(1.5, ChessStore.statePollSeconds(subscribed = true))
        assertEquals(1.0, ChessStore.statePollSeconds(subscribed = false))
    }
}
