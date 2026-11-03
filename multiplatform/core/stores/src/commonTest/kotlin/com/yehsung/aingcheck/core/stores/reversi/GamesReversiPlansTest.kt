// 원본: Tests/CheckMobileKitTests/GamesReversiMatchTests.swift · GamesReversiLobbyTests.swift(순수 표 몫) @ ios-1017-int 3e5051ed · 467aec40
//
// 폰 아잉 뒤집기 화면의 **순수 판정**(GamesReversiPlans.kt)과 문구 표(ReversiPhoneText.kt)를 값으로 잰다. 돈이 갈리는 갈래(결과 · 루비 · 무승부 환불)는 갈래마다
// 결과가 다른 짝(기준선)을 같은 시험에 둔다 — 한 값만 재면 표가 통째로 상수여도 초록이다.
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GamesReversiPlansTest {
    private val rival = ReversiUser("bbbbbbbb-0000-4000-8000-000000000001", "라이벌")

    private fun finished(result: ReversiResult?, reason: ReversiEndReason, isAI: Boolean = false, stake: Int = 5, myColor: ReversiColor = ReversiColor.black) = ReversiMatchState(
        id = if (isAI) "ai-1" else "m1", isAI = isAI, status = ReversiMatchStatus.finished, stake = stake, myColor = myColor,
        opponent = if (isAI) ReversiUser.reversiAI else rival, turn = null, result = result, endReason = reason, autoAbandonStreak = 3,
    )

    @Test
    fun resultRubyDeltaAndNotesSplitByOutcomeAndMatchKind() {
        val won = GamesReversiMatchChrome.make(finished(ReversiResult.blackWin, ReversiEndReason.resign), null, false, 30).result!!
        val lost = GamesReversiMatchChrome.make(finished(ReversiResult.whiteWin, ReversiEndReason.abandoned), null, false, 30).result!!
        val draw = GamesReversiMatchChrome.make(finished(ReversiResult.draw, ReversiEndReason.noMoves), null, false, 30).result!!
        val robot = GamesReversiMatchChrome.make(finished(ReversiResult.blackWin, ReversiEndReason.resign, isAI = true), null, false, 30).result!!
        assertEquals(listOf("이겼어요", "졌어요", "무승부예요"), listOf(won.title, lost.title, draw.title))
        assertEquals(listOf(5, -5, 0), listOf(won.rubyDelta, lost.rubyDelta, draw.rubyDelta))
        assertEquals(listOf("+5", "−5", "±0"), listOf(won.rubyDeltaText, lost.rubyDeltaText, draw.rubyDeltaText))
        assertEquals("상대가 기권했어요", won.reason)
        assertEquals("시간이 3번 이어서 지나 졌어요", lost.reason)
        assertNull(won.rubyNote, "이긴 판에는 환불 줄이 없다")
        assertEquals("판돈 5 루비를 돌려받았어요", draw.rubyNote, "무승부는 환불 한 줄")
        // 로봇 판: 루비를 안 그리고 '기록 없음' · 주어는 '로봇'.
        assertFalse(robot.showsRubyDelta)
        assertTrue(won.showsRubyDelta)
        assertEquals(0, robot.rubyDelta)
        assertEquals(ReversiPhoneText.aiNoRecord, robot.rubyNote)
        assertEquals("로봇이 기권했어요", robot.reason)
        assertEquals("상대 · 로봇", robot.opponentLine)
        assertEquals("상대 · 라이벌", won.opponentLine)
    }

    @Test
    fun scoreLineUsesServerScoreOnlyForNaturalEnds() {
        val board = requireNotNull(ReversiBoard.fromString("bbb" + ".".repeat(53) + "w......."))
        val natural = finished(ReversiResult.blackWin, ReversiEndReason.noMoves).copy(board = board, counts = board.counts)
        val resigned = natural.copy(endReason = ReversiEndReason.resign)
        // 자연 종료는 WOF 점수(빈칸은 이긴 쪽) + 판 위 돌 수, 기권은 판 위 돌 수만.
        val score = requireNotNull(ReversiRules.score(board))
        assertEquals("흑 : 백  ${score.black} : ${score.white} (판 위 3 : 1)", GamesReversiMatchChrome.scoreLine(natural))
        assertEquals("판 위 흑 3 : 백 1", GamesReversiMatchChrome.scoreLine(resigned))
    }

    @Test
    fun actionRowDetailAndWarningsFollowTheMatch() {
        val playing = ReversiMatchState(id = "m1", stake = 5, myColor = ReversiColor.black, opponent = rival, autoStones = setOf(19, 26), myAutoStreak = 2, autoAbandonStreak = 3)
        val chrome = GamesReversiMatchChrome.make(playing, notice = null, isBusy = true, serverTurnSeconds = 30)
        assertEquals(GamesReversiMatchChrome.ActionRow.playing(canResign = false), chrome.actionRow, "왕복 중엔 기권이 눌리지 않는다")
        assertEquals("시간이 지나 자동으로 놓인 돌 2개 · 회색 점", chrome.autoPlacedLine)
        assertEquals("한 번 더 시간이 지나면 져요", chrome.autoStreakWarning)
        assertEquals(" · 이기면 +5", chrome.stakeSuffix)
        assertNull(GamesReversiMatchChrome.make(playing.copy(myAutoStreak = 1), null, false, 30).autoStreakWarning, "한 번 남았을 때만 빨강 줄")
        // 안내가 먼저, 없으면 방금 일어난 패스.
        val passed = playing.copy(plies = listOf(ReversiPly(1, ReversiColor.white, ReversiPly.Kind.pass, null, emptyList(), false)), turn = ReversiColor.black)
        assertEquals(ReversiMatchLine("라이벌님이 둘 곳이 없어 내 차례가 이어져요", ReversiMatchTint.quiet), GamesReversiMatchChrome.make(passed, null, false, 30).detailLine)
        assertEquals(ReversiMatchLine("보내는 중이에요", ReversiMatchTint.warn), GamesReversiMatchChrome.make(passed, "보내는 중이에요", false, 30).detailLine)
        // 로봇 판 시계 줄은 '멈춰요', 1:1 은 '흘러요'.
        assertTrue(chrome.clockLine.startsWith("앱을 나가도 차례 시간은 흘러요"))
        assertTrue(GamesReversiMatchChrome.make(playing.copy(id = "ai-2", isAI = true, opponent = ReversiUser.reversiAI), null, false, 30).clockLine.startsWith("화면을 떠나거나"))
        assertEquals(GamesReversiMatchChrome.ActionRow.finished(showsPlayAgain = true), GamesReversiMatchChrome.make(finished(null, ReversiEndReason.resign, isAI = true), null, false, 30).actionRow)
        assertEquals(GamesReversiMatchChrome.ActionRow.finished(showsPlayAgain = false), GamesReversiMatchChrome.make(finished(null, ReversiEndReason.resign), null, false, 30).actionRow)
    }

    @Test
    fun turnLineSaysSettlingOnlyAfterDeadlinePlusGrace() {
        val now = SwiftDate(1_900_000_000.0)
        val mine = ReversiMatchState(id = "m1", stake = 5, myColor = ReversiColor.black, opponent = rival, turn = ReversiColor.black, deadline = now.addingTimeInterval(-1.0))
        assertEquals(ReversiPhoneText.myTurn, GamesReversiMatchChrome.turnLine(mine, now, graceSeconds = 2.0, isAIThinking = false).text, "유예 안에서는 아직 내 차례")
        assertEquals(ReversiPhoneText.mySettling, GamesReversiMatchChrome.turnLine(mine, now.addingTimeInterval(1.5), 2.0, false).text)
        assertEquals(ReversiPhoneText.opponentSettling, GamesReversiMatchChrome.turnLine(mine.copy(turn = ReversiColor.white), now.addingTimeInterval(1.5), 2.0, false).text)
        assertEquals(ReversiPhoneText.aiThinking, GamesReversiMatchChrome.turnLine(mine, now, 2.0, isAIThinking = true).text)
        assertEquals(ReversiMatchTint.bad, GamesReversiMatchChrome.ringTint(5.0))
        assertEquals(ReversiMatchTint.warn, GamesReversiMatchChrome.ringTint(10.0))
        assertEquals(ReversiMatchTint.good, GamesReversiMatchChrome.ringTint(10.5))
        assertEquals(0.5, GamesReversiMatchChrome.ringFraction(15.0, 30))
    }

    @Test
    fun moveLogPairsByColorNotParity() {
        fun ply(seq: Int, color: ReversiColor, pass: Boolean = false, auto: Boolean = false) =
            ReversiPly(seq, color, if (pass) ReversiPly.Kind.pass else ReversiPly.Kind.stone, if (pass) null else 19 + seq, emptyList(), auto)
        // 흑 · 백 · 흑 · 흑(백이 넘김 없이 기록 구멍) · 백(넘김) — 홀짝으로 자르면 번호가 밀린다.
        val chips = GamesReversiMoveLog.chips(listOf(ply(1, ReversiColor.black), ply(2, ReversiColor.white), ply(3, ReversiColor.black, auto = true), ply(4, ReversiColor.black), ply(5, ReversiColor.white, pass = true)))
        assertEquals(listOf(1, null, 2, 3, null), chips.map { it.number })
        assertEquals(listOf("e3", "f3", "g3 · 자동", "h3", "넘김"), chips.map { it.text })
    }

    @Test
    fun watchStatusSpeaksThirdPersonAndNeverInventsAWinner() {
        val black = ReversiUser("u1", "구름빵")
        val white = ReversiUser("u2", "")
        val seed = ReversiSpectating(id = "w1", faces = listOf(black, white))
        assertEquals(GamesReversiWatchStatus.Kind.loading, GamesReversiWatchStatus.kind(seed), "색이 서기 전엔 차례를 말하지 않는다")
        assertEquals(ReversiPhoneText.watchLoading, GamesReversiWatchStatus.headline(seed))
        val live = seed.copy(blackUser = black, whiteUser = white, turn = ReversiColor.white)
        assertEquals("관전 중 · 백 차례", GamesReversiWatchStatus.headline(live))
        assertNull(GamesReversiWatchStatus.detail(live, 3))
        val blackWon = live.copy(isFinished = true, turn = null, winner = ReversiColor.black, endReason = ReversiEndReason.resign)
        assertEquals("구름빵(흑) 승리", GamesReversiWatchStatus.headline(blackWon))
        assertEquals("백이 기권했어요", GamesReversiWatchStatus.detail(blackWon, 3))
        // 이름이 빈 쪽이 이기면 색만.
        val whiteWon = blackWon.copy(winner = ReversiColor.white, endReason = ReversiEndReason.abandoned)
        assertEquals("백 승리", GamesReversiWatchStatus.headline(whiteWon))
        assertEquals("흑 시간이 3번 이어서 지났어요", GamesReversiWatchStatus.detail(whiteWon, 3))
        assertEquals(ReversiPhoneText.watchEndedDraw, GamesReversiWatchStatus.headline(blackWon.copy(winner = null, endReason = ReversiEndReason.boardFull)))
        assertEquals("—", GamesReversiWatchStatus.displayName(white))
        assertEquals(ReversiMatchTint.warn, GamesReversiWatchStatus.clockTint(0.0), "0 은 주황 — 결과를 지어내는 빨강이 아니다")
        assertEquals(ReversiMatchTint.bad, GamesReversiWatchStatus.clockTint(3.0))
        // 관전 판은 입력이 0건.
        assertNull(GamesReversiWatchPlan.boardTapHandler)
        assertTrue(GamesReversiWatchPlan.boardLegalTargets.isEmpty())
    }

    @Test
    fun boardGeometryHasNoFlipAndNoHalfCellTolerance() {
        val g = GamesReversiBoardGeometry(320.0)
        assertEquals(40.0, g.cell)
        assertEquals(0, g.idx(0.0, 0.0), "a1 이 왼쪽 위 — 방향 뒤집기가 없다")
        assertEquals(7, g.idx(319.0, 1.0), "h1 이 오른쪽 위")
        assertEquals(19, g.idx(3 * 40 + 20.0, 2 * 40 + 20.0), "d3")
        assertNull(g.idx(320.0, 10.0), "판 밖은 아무 칸도 아니다")
        assertNull(g.idx(-0.5, 10.0))
        assertEquals(140.0 to 100.0, g.center(19))
        // 칸 화면 읽기는 칸 이름이 먼저다.
        val start = ReversiBoard.start
        assertEquals("d3, 빈칸, 둘 수 있어요", GamesReversiBoardCells.label(19, start, setOf(19), null, emptySet()))
        assertEquals("d4, 백 돌", GamesReversiBoardCells.label(27, start, emptySet(), null, emptySet()))
        assertEquals("e4, 흑 돌, 마지막 수, 자동으로 놓임", GamesReversiBoardCells.label(28, start, emptySet(), 28, setOf(28)))
        assertEquals("a1, 빈칸", GamesReversiBoardCells.label(0, start, setOf(19), null, emptySet()))
    }

    @Test
    fun boardSideFitsTheColumnAndShrinksOnlyForLargeText() {
        // 작은 폰(360dp): 열 328 → 8 의 배수.
        assertEquals(328.0, GamesReversiBoardLayout.side(360.0, 700.0, 16.0, isLargeText = false, isAccessibilitySize = false))
        assertEquals(352.0, GamesReversiBoardLayout.side(390.0, 700.0, 16.0, false, false))
        // 큰 글자: 보이는 높이의 52% · 접근성 크기 40% · 바닥 200.
        assertEquals(360.0, GamesReversiBoardLayout.side(412.0, 700.0, 16.0, true, false))
        assertEquals(280.0, GamesReversiBoardLayout.side(412.0, 700.0, 16.0, true, true))
        assertEquals(200.0, GamesReversiBoardLayout.side(412.0, 300.0, 16.0, true, true))
        assertEquals(GamesReversiBoardLayout.minimumSide, GamesReversiBoardLayout.side(0.0, 0.0, 16.0, false, false), "첫 배치 0 폭 틱은 바닥값")
        // 관전 판: 높이가 이기면 줄고, 폭이 이기면 그대로.
        assertEquals(288.0, GamesReversiWatchBudget.side(343.0, 554.0))
        assertEquals(360.0, GamesReversiWatchBudget.side(361.0, 739.0))
    }

    @Test
    fun ruleExamplesAreComputedByTheRulesAndTheLastLineNamesTheRulesOnlyAsDescription() {
        val examples = GamesReversiRuleExample.all
        assertEquals(listOf("start", "lines", "pass", "end"), examples.map { it.id })
        assertEquals(setOf(19, 26, 37, 44), examples[0].dots, "시작 판 흑의 네 칸(d3 · c4 · f5 · e6)")
        assertTrue(examples[1].flipped.size >= 3, "c3 한 수가 여러 줄을 뒤집는다")
        assertEquals(18, examples[1].lastStone)
        assertEquals(ReversiColor.black, examples[1].board[18])
        assertTrue(examples[2].dots.isNotEmpty() && ReversiRules.legalMoves(examples[2].board, ReversiColor.black).isEmpty(), "흑은 둘 곳이 없고 백은 있다")
        val score = requireNotNull(ReversiRules.score(examples[3].board))
        assertTrue(examples[3].detail.endsWith("(${score.black} : ${score.white})"))
        // 규칙 열 줄 — 숫자는 로비 응답 값 · 마지막 줄만 '리버시'를 말한다(설명으로만).
        val rules = ReversiPhoneText.rules(turnSeconds = 20, lossStreak = 4, inviteTtlSeconds = 45)
        assertEquals(10, rules.size)
        assertEquals("리버시와 같은 규칙이에요. 리버시를 알면 따로 배울 것이 없어요.", rules.last())
        assertTrue("한 수에 20초" in rules[5] && "연달아 4번" in rules[5])
        assertTrue("45초 안에" in rules[7])
        assertNotEquals(rules, ReversiPhoneText.rules(30, 3, 60), "숫자를 받지 않으면 서버가 바꾼 날 옛 숫자를 말한다")
        assertEquals(1, rules.count { "리버시" in it })
        // 상표 낱말 0건은 core/rules ReversiTrademarkTest 가 multiplatform/ 전역(이 파일 포함)을 훑어 잰다 — 여기 그 낱말을 적지 않는다.
    }

    @Test
    fun opponentRowButtonSaysTheFirstLockAndTheSubtitleKeepsTheWorkAxis() {
        val ok = ReversiUser("u1", "솜", isWorking = true, isCapable = true)
        assertEquals(ReversiPhoneText.OpponentRow("근무 중", "도전"), ReversiPhoneText.opponentRow(ok))
        val outdatedBusy = ok.copy(isWorking = false, isCapable = false, inMatch = true)
        assertEquals(ReversiPhoneText.OpponentRow("근무 안 함 · 대결 중", "업데이트 필요"), ReversiPhoneText.opponentRow(outdatedBusy))
        val legends = ReversiPhoneText.lockLegends(listOf(ok, outdatedBusy, ok.copy(focusMode = true)))
        assertEquals(3, legends.size)
        assertEquals("업데이트 필요 · 상대 앱이 아잉 뒤집기를 아직 몰라요 — 상대가 앱을 올리면 신청할 수 있어요", legends[0])
        assertTrue(ReversiPhoneText.lockLegends(listOf(ok)).isEmpty(), "까닭이 없으면 풀이 줄도 없다")
    }

    /**
     * 판 7 검토 U-F2(Android 몫): 판 한 장이 **보이는 높이에도 안 들어가면**(큰 화면 가로 · 화면 나눔) 기본 글자에서도 보이는 높이의 52% 로 줄인다 — 열 폭
     * 그대로면 내 카드의 30초 링 · '내 차례예요' · 3회 패 줄이 스크롤 아래로 밀린다. 폰 세로(360 · 390 · 411 폭)는 아이폰과 같은 값 그대로다(기준선).
     */
    @Test
    fun boardSideShrinksWhenTheBoardIsTallerThanTheVisibleHeight() {
        // 큰 화면 가로(태블릿 · 폴더블) · 화면 나눔 — 판이 보이는 높이 안에 든다.
        assertEquals(328.0, GamesReversiBoardLayout.side(1280.0, 640.0, 16.0, false, false), "1280×640 가로에서 판이 보이는 높이를 넘는다")
        assertEquals(264.0, GamesReversiBoardLayout.side(960.0, 520.0, 16.0, false, false))
        assertEquals(312.0, GamesReversiBoardLayout.side(840.0, 600.0, 16.0, false, false))
        assertEquals(GamesReversiBoardLayout.minimumSide, GamesReversiBoardLayout.side(411.0, 290.0, 16.0, false, false), "폰 위아래 나눔은 바닥값")
        for ((w, h) in listOf(1280.0 to 640.0, 960.0 to 520.0, 840.0 to 600.0)) {
            assertTrue(GamesReversiBoardLayout.side(w, h, 16.0, false, false) <= h * 0.52, "$w×$h")
        }
        // 기준선: 폰 세로 기본 글자는 열 폭 그대로(작은 폰의 짧은 높이 447 까지) — 아이폰과 픽셀이 같다.
        assertEquals(328.0, GamesReversiBoardLayout.side(360.0, 447.0, 16.0, false, false))
        assertEquals(352.0, GamesReversiBoardLayout.side(390.0, 640.0, 16.0, false, false))
        assertEquals(376.0, GamesReversiBoardLayout.side(411.0, 600.0, 16.0, false, false))
        // 기준선: 큰 화면 세로(태블릿)도 열 폭 그대로다 — 판이 보이는 높이 안에 든다.
        assertEquals(768.0, GamesReversiBoardLayout.side(800.0, 1100.0, 16.0, false, false))
        // 큰 글자는 지금 규칙 그대로(접근성 크기 40% 가 더 작으면 그쪽).
        assertEquals(256.0, GamesReversiBoardLayout.side(1280.0, 640.0, 16.0, true, true))
    }

    /** 아이폰 1.0.17 검토 수리 33727592(GamesReversiLobbyTests `rulesSheetClosesOnNewMatch`)의 규칙 값 다섯 — 판 7 검토 S-F3 · U-F1. */
    @Test
    fun rulesSheetClosesOnlyWhenANewMatchStands() {
        // 새 판: 로비(null) → 판 · 판 → 다른 판(로봇 판 중 수락).
        assertTrue(GamesReversiRulesSheetRule.closesOnMatchChange(null, "m-1"))
        assertTrue(GamesReversiRulesSheetRule.closesOnMatchChange("ai-1", "m-2"))
        // 기준선: 같은 판(판 중에 책 단추) · 로비로 돌아감은 접지 않는다.
        assertFalse(GamesReversiRulesSheetRule.closesOnMatchChange("m-1", "m-1"))
        assertFalse(GamesReversiRulesSheetRule.closesOnMatchChange("m-1", null))
        assertFalse(GamesReversiRulesSheetRule.closesOnMatchChange(null, null))
    }

    @Test
    fun aiEntryBlockSaysWhenItOpens() {
        val store = ReversiStore(kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined))
        assertEquals(GamesReversiAIEntry(true, null), GamesReversiAIEntry.of(store))
        assertEquals(ReversiPhoneText.aiButtonHelp, GamesReversiAIEntry.of(store).caption)
        assertEquals(listOf(ReversiColor.black, ReversiColor.white, null), GamesReversiAIColorChoice.entries.map { it.humanColor })
        assertEquals(listOf("흑 · 먼저 둬요", "백 · 나중에 둬요", "무작위"), GamesReversiAIColorChoice.entries.map { it.title })
        assertEquals("두고 있는 판이 끝나면 연습할 수 있어요", ReversiPhoneText.aiBlock(ReversiPhoneText.AIBlock.playing))
        assertEquals(ReversiStake.five, GamesReversiStakeSend.toggled(null, ReversiStake.five))
        assertNull(GamesReversiStakeSend.toggled(ReversiStake.five, ReversiStake.five), "같은 칸을 다시 누르면 해제")
    }
}
