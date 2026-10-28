// 원본: Tests/CheckMobileKitTests/GamesTetrisLobbyTests.swift:117-410 · GamesTetrisWatchTests.swift:124-455 · GamesTetrisDuelMatchTests.swift:231-404 ·
//       GamesWatcherCountTests.swift · Tests/checkTests/V0360TetrisDuelStoreTests.swift(순수 판정) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus
import com.yehsung.aingcheck.core.wire.games.TetrisRankRow
import com.yehsung.aingcheck.core.wire.games.TetrisRankingMe
import com.yehsung.aingcheck.core.wire.games.TetrisRankingResponse
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TetrisDuelPlansTest {
    private fun user(id: String = "u1", name: String = "민트별", working: Boolean = true, capable: Boolean = true,
                     inMatch: Boolean = false, focused: Boolean = false) =
        TetrisDuelUser(id, name, null, null, working, capable, inMatch, focused)

    /** 상대 한 줄: [신청] 집합이 코어 `canBeChallenged` 와 **같고**, 부제는 늘 근무 축으로 시작한다(16 갈래 전수). */
    @Test
    fun theOpponentRowAgreesWithCanBeChallengedInAllSixteenCases() {
        var count = 0
        for (working in listOf(false, true)) for (capable in listOf(false, true)) for (inMatch in listOf(false, true)) for (focused in listOf(false, true)) {
            val u = user(working = working, capable = capable, inMatch = inMatch, focused = focused)
            val row = TetrisPhoneText.opponentRow(u)
            assertEquals(u.canBeChallenged, row.buttonTitle == TetrisPhoneText.challenge, "$u")
            assertTrue(row.subtitle.startsWith(if (working) TetrisPhoneText.working else TetrisPhoneText.notWorking), "$u")
            if (!capable) assertEquals(TetrisPhoneText.needsUpdate, row.buttonTitle, "옛 버전이 가장 먼저다")
            if (!capable && inMatch) assertTrue(TetrisPhoneText.inMatch in row.subtitle, "버튼이 못 말한 축은 부제 꼬리로")
            count += 1
        }
        assertEquals(16, count)
    }

    /** 로비 정렬: 도전 가능한 근무자 → 근무 중·가능(대결 중) → 근무 중 → 나머지, 그 안은 이름(숫자 덩어리) — 같으면 서버 순서. */
    @Test
    fun theLobbyOrderMatchesTheServerRule() {
        val users = listOf(
            user("a", "하늘", working = false),
            user("b", "별10", working = true, inMatch = true),
            user("c", "별2", working = true),
            user("d", "가람", working = true, capable = false),
            user("e", "별2", working = true),
            user("f", "나무", working = true),
        )
        val sorted = TetrisDuelStore.sortedForLobby(users, StoreNaturalCollation)
        assertEquals(listOf("f", "c", "e", "b", "d", "a"), sorted.map { it.id })
        assertTrue(NaturalKoCollation.compare("별2", "별10") < 0, "숫자 덩어리 비교(localizedStandardCompare)")
    }

    /** 순위표: 행 순서는 입력 그대로 · id·rank 없는 행은 뺀다 · 승점이 없으면 승−패 · 기록 시작이 0 이하면 없음. */
    @Test
    fun theRankingBoardKeepsServerOrderAndDropsBrokenRows() {
        val response = TetrisRankingResponse(
            status = TetrisRPCStatus.ok, recordSinceMs = 1_789_000_000_000.0,
            me = TetrisRankingMe(rank = null, wins = 0, losses = 0, draws = 0),
            rows = listOf(
                TetrisRankRow(rank = 2, id = "B", displayName = "둘", wins = 3, losses = 1),
                TetrisRankRow(rank = 1, id = "a", displayName = "하나", wins = 5, losses = 0, draws = 2, points = 9),
                TetrisRankRow(rank = null, id = "c", wins = 9),
                TetrisRankRow(rank = 3, id = null, wins = 1),
            ),
        )
        val board = TetrisDuelStore.rankingBoard(response)
        assertEquals(listOf("b", "a"), board.entries.map { it.id }, "재정렬하지 않는다 · id 는 소문자")
        assertEquals(2, board.entries[0].points, "승점이 없으면 승 − 패")
        assertEquals(9, board.entries[1].points)
        assertNull(board.me?.rank)
        assertEquals(SwiftDate(1_789_000_000.0), board.recordSince)
        assertNull(TetrisDuelStore.rankingBoard(response.copy(recordSinceMs = 0.0)).recordSince)
    }

    /** 끝난 판인지 · 상태 변화 한 줄: 같은 판의 끝난 모양을 다시 받으면 '막 끝남'이 아니다. */
    @Test
    fun matchJustFinishedFiresOncePerMatch() {
        val base = TetrisDuelMatchState("m", 5, 7, user(), null, null, null, null, false, TetrisDuelOpponentBoard.empty,
            false, null, null, null, null)
        val done = base.copy(isFinished = true, outcome = TetrisDuelOutcome.won)
        assertTrue(TetrisDuelStore.matchJustFinished(base, done))
        assertTrue(TetrisDuelStore.matchJustFinished(null, done))
        assertFalse(TetrisDuelStore.matchJustFinished(done, done))
        assertTrue(TetrisDuelStore.matchJustFinished(done, done.copy(id = "n")))
        assertFalse(TetrisDuelStore.matchJustFinished(base, base))
        assertNull(TetrisDuelStore.matchTransitionLine(base, base.copy(opponentBoard = TetrisDuelOpponentBoard.empty.copy(lines = 3))),
            "상대 판·루비는 줄을 만들지 않는다")
        assertEquals("state ready=false started=false finished=true reason=none sameMatch=true", TetrisDuelStore.matchTransitionLine(base, done))
    }

    /** 결과 카드 사유(내 기준 — 승자면 주어가 '상대')와 관전의 3인칭 사유는 다른 표다. */
    @Test
    fun endReasonsAreFirstPersonForPlayersAndThirdPersonForWatchers() {
        assertEquals("상대가 꼭대기까지 쌓였어요", TetrisDuelNoticeText.endReason(TetrisDuelEndReason.topout, TetrisDuelOutcome.won))
        assertEquals("꼭대기까지 쌓였어요", TetrisDuelNoticeText.endReason(TetrisDuelEndReason.topout, TetrisDuelOutcome.lost))
        assertEquals("둘 다 연결이 끊겼어요", TetrisDuelNoticeText.endReason(TetrisDuelEndReason.disconnect, null))
        assertEquals("", TetrisDuelNoticeText.endReason(null, TetrisDuelOutcome.won))
        assertEquals("한쪽이 기권했어요", TetrisPhoneText.watchEndReason(TetrisDuelEndReason.resign))
        assertEquals("루비 3개 더 필요해요", TetrisDuelNoticeText.challenge(TetrisRPCStatus.insufficient, need = 5, have = 2))
        assertEquals("상대의 루비가 모자라요", TetrisDuelNoticeText.respond(true, TetrisRPCStatus.insufficient, side = "challenger"))
        assertNull(TetrisDuelNoticeText.respond(true, TetrisRPCStatus.ok), "수락 성공은 말하지 않는다")
        assertTrue(TetrisDuelEndReason.timeCap.isAlwaysDraw && TetrisDuelEndReason.noShow.isAlwaysDraw && !TetrisDuelEndReason.disconnect.isAlwaysDraw)
    }

    /** 순위 탭: 0판은 빠지고 · 행을 들고 있으면 '곧 열려요'로 덮지 않고 · PGRST202 창은 '빈'이 아니라 '곧 열려요' · 전적이 어긋난 내 줄은 안 그린다. */
    @Test
    fun theRankingTabBranchesInTheRightOrder() = runTest {
        val store = TetrisDuelStore(host = null, scope = backgroundScope, clock = { SwiftDate(0.0) })
        assertEquals(GamesTetrisDuelRankingPlan.Content.loading, GamesTetrisDuelRankingPlan.content(store))
        store.rankingUnavailable = true
        store.hasLoadedRanking = true
        assertEquals(GamesTetrisDuelRankingPlan.Content.soon, GamesTetrisDuelRankingPlan.content(store), "준비 중은 빈 표보다 먼저")
        val row = TetrisDuelRankEntry("x", 1, user("x"), 1, 0, 0, 1)
        val zero = TetrisDuelRankEntry("z", 2, user("z"), 0, 0, 0, 0)
        store.ranking = TetrisDuelRankingBoard(listOf(row, zero), TetrisDuelMyRank(4, 1, 2, 0, -1), null)
        assertEquals(GamesTetrisDuelRankingPlan.Content.rows, GamesTetrisDuelRankingPlan.content(store), "행이 맨 앞이다")
        assertEquals(listOf("x"), GamesTetrisDuelRankingPlan.held(store).map { it.id }, "0판은 안 낀다")
        store.record = TetrisDuelRecord(1, 2, 0)
        assertEquals(4, GamesTetrisDuelRankingPlan.myRank(store)?.rank)
        store.record = TetrisDuelRecord(2, 2, 0)
        assertNull(GamesTetrisDuelRankingPlan.myRank(store), "로비 전적과 어긋나면 그리지 않는다")
        assertEquals(TetrisPhoneText.rankWholePeriod, GamesTetrisDuelRankingPlan.sinceCaption(store))
        store.ranking = store.ranking!!.copy(recordSince = SwiftDate(1_789_621_500.0))
        assertEquals("9월 17일부터", GamesTetrisDuelRankingPlan.sinceCaption(store) { TetrisPhoneText.rankSince(it, TimeZone.of("Asia/Seoul")) })
        store.rankingEnabled = true
        assertTrue(GamesTetrisDuelRankingPlan.shouldRefresh(store, GamesTetrisLobbyTab.ranking))
        assertFalse(GamesTetrisDuelRankingPlan.shouldRefresh(store, GamesTetrisLobbyTab.opponents), "순위 탭이 아니면 0건")
        store.phase = TetrisDuelPhase.playing
        assertFalse(GamesTetrisDuelRankingPlan.shouldRefresh(store, GamesTetrisLobbyTab.ranking), "판 중에는 0건")
    }

    /** 관전 입구: 주 스위치가 꺼지면 칩 자체가 없다 · 내 판은 캡션 · 잠금은 관전 전용 깃발 하나 · 관전자 수는 스위치와 무관하게 보인다. */
    @Test
    fun theWatchEntryAndTrailingSlot() = runTest {
        val store = TetrisDuelStore(host = null, scope = backgroundScope, clock = { SwiftDate(0.0) })
        val live = TetrisDuelLiveMatch("l", user("a"), user("b"), TetrisDuelStake.five, SwiftDate(0.0), watchers = 2)
        assertEquals(GamesTetrisWatchPlan.Entry.absent, GamesTetrisWatchPlan.entry(store, isMine = false))
        assertTrue(GamesTetrisWatchPlan.hasTrailingContent(store, live), "스위치가 꺼져도 관전자 수는 보인다")
        assertFalse(GamesTetrisWatchPlan.hasTrailingContent(store, live.copy(watchers = 0)))
        store.spectatorFeaturesEnabled = true
        assertEquals(GamesTetrisWatchPlan.Entry.myMatch, GamesTetrisWatchPlan.entry(store, isMine = true))
        store.spectatorCountUnavailable = true
        store.rankingUnavailable = true
        assertEquals(GamesTetrisWatchPlan.Entry.chip, GamesTetrisWatchPlan.entry(store, isMine = false), "다른 깃발로 잠그지 않는다")
        store.watchUnavailable = true
        assertEquals(GamesTetrisWatchPlan.Entry.soon, GamesTetrisWatchPlan.entry(store, isMine = false))
        assertNull(GamesTetrisWatchPlan.boardTapHandler)
        assertNull(GamesTetrisWatchPlan.boardDragHandler)
        assertTrue(GamesTetrisWatchPlan.controls.isEmpty())
        assertFalse(GamesTetrisWatchPlan.showsResign)
        assertFalse(GamesWatcherCount.shows(0))
        assertFalse(GamesWatcherCount.shows(-1))
        assertTrue(GamesWatcherCount.shows(1))
        assertEquals("관전자 3명", GamesWatcherCount.accessibilityLabel(3))
        assertEquals("0", GamesWatcherCount.text(-4))
    }

    /** 관전 머리 한 줄: 승자는 `match.winner` 의 자리로만 — 3인칭 이름. 무승부·모름·이름 빈칸에서는 이름을 지어내지 않는다. */
    @Test
    fun theWatchHeadlineNamesOnlyAKnownWinner() {
        val a = TetrisSpectateSide(user = user("aa", "앨리스"))
        val b = TetrisSpectateSide(user = user("bb", "밥"))
        val base = TetrisSpectateState(id = "m", a = a, b = b, hasServerState = true)
        assertEquals(TetrisPhoneText.playingNow, GamesTetrisWatchStatus.headline(base))
        assertEquals(TetrisPhoneText.watchLoading, GamesTetrisWatchStatus.headline(base.copy(hasServerState = false)))
        val ended = base.copy(isFinished = true, result = "challenger_win", winnerUserID = "bb", endReason = TetrisDuelEndReason.topout)
        assertEquals("밥 승리", GamesTetrisWatchStatus.headline(ended), "result 글자가 아니라 winner uuid 의 자리")
        assertEquals("꼭대기까지 쌓여서 끝났어요", GamesTetrisWatchStatus.detail(ended))
        assertEquals(TetrisPhoneText.watchEndedDraw, GamesTetrisWatchStatus.headline(ended.copy(winnerUserID = null, result = "draw")))
        assertEquals(TetrisPhoneText.watchEnded, GamesTetrisWatchStatus.headline(ended.copy(winnerUserID = "zz")), "그 자리 사람을 모르면 말하지 않는다")
        assertEquals(TetrisPhoneText.watchEnded, GamesTetrisWatchStatus.headline(ended.copy(b = TetrisSpectateSide(user = user("bb", "")))))
        assertNull(GamesTetrisWatchStatus.detail(base), "진행 중에는 둘째 줄이 없다")
        assertEquals("—", GamesTetrisWatchStatus.displayName(TetrisSpectateSide()))
    }

    /** 관전 칸 예산: 보통은 상한 12pt · 세로가 모자라면 줄고 · 하한 5pt 밑으로는 안 내려간다 · 세로를 모르면 폭만 본다. */
    @Test
    fun theWatchCellBudgetLooksAtWidthAndHeight() {
        assertEquals(12.0, GamesTetrisWatchBudget.cell(343.0, 554.0))
        assertEquals(12.0, GamesTetrisWatchBudget.cell(343.0, 0.0))
        assertEquals(269.0, GamesTetrisWatchBudget.blocksAroundBoards(), "54 + 85 + 60 + 38 + 8×4 (Swift 주석의 261 은 77 로 센 옛 검산)")
        assertEquals(10.0, GamesTetrisWatchBudget.cell(343.0, 269.0 + 4.0 + 200.0))
        assertEquals(5.0, GamesTetrisWatchBudget.cell(343.0, 300.0))
        assertEquals(5.0, GamesTetrisWatchBudget.cell(40.0, 0.0))
    }

    /** 대결 화면 표: 입력은 판이 흐를 때만 · 경고는 끝난 판에서만 내린다 · 결과 루비는 서버 값 우선 · 카운트다운은 1 아래로 안 내려간다. */
    @Test
    fun theMatchChromeIsDerivedFromTheMatch() {
        val m = TetrisDuelMatchState("m", 5, 7, user(name = "달토끼"), null, null, null, null, true, TetrisDuelOpponentBoard.empty,
            false, null, null, null, null)
        val stats = TetrisDuelMyStats(lines = 3, attackSent = 1, pendingGarbage = 0, levelFloor = 11, toppedOut = false)
        val playing = GamesTetrisDuelChrome(m, TetrisDuelPhase.playing, stats, null, connectionTrouble = true)
        assertEquals(GamesTetrisDuelChrome.Stage.playing, playing.stage)
        assertTrue(playing.acceptsInput && playing.showsLeaveWarning && playing.showsSpeedUp && playing.connectionTrouble && playing.canResign)
        assertFalse(GamesTetrisDuelChrome(m, TetrisDuelPhase.playing, stats.copy(toppedOut = true), null, false).acceptsInput, "탑아웃이면 입력 없음")
        assertFalse(GamesTetrisDuelChrome(m, TetrisDuelPhase.countdown, stats, null, false).acceptsInput)
        val done = m.copy(isFinished = true, outcome = TetrisDuelOutcome.lost)
        val finished = GamesTetrisDuelChrome(done, TetrisDuelPhase.playing, stats, null, true)
        assertEquals(GamesTetrisDuelChrome.Stage.finished, finished.stage)
        assertFalse(finished.showsLeaveWarning || finished.acceptsInput || finished.connectionTrouble || finished.canResign)
        assertEquals(-5, finished.result?.rubyDelta, "서버 값이 없으면 패 −판돈")
        assertEquals(7, GamesTetrisDuelChrome.result(done.copy(rubyDelta = 7)).rubyDelta, "서버 값 우선")
        assertEquals("+5", GamesTetrisDuelChrome.result(done.copy(outcome = TetrisDuelOutcome.won)).rubyDeltaText)
        assertEquals(1, GamesTetrisDuelChrome.countdownDigit(0.0))
        assertEquals(3, GamesTetrisDuelChrome.countdownDigit(2.01))
        assertEquals(30, GamesTetrisDuelChrome.readySecondsLeft(null, SwiftDate(0.0)))
        assertEquals(4, GamesTetrisDuelChrome.readySecondsLeft(SwiftDate(3.2), SwiftDate(0.0)))
        assertFalse(GamesTetrisDuelChrome.opponentIsSilent(9.0, opponentReady = false, stage = GamesTetrisDuelChrome.Stage.playing))
        assertTrue(GamesTetrisDuelChrome.opponentIsSilent(5.0, opponentReady = true, stage = GamesTetrisDuelChrome.Stage.playing))
        assertEquals(2.5, GamesTetrisDuelChrome.elapsedSeconds(GamesTetrisDuelChrome.Stage.finished, 99.0, 2.5), "끝난 판은 흘린 판 시간에서 멈춘다")
        assertEquals(TetrisPhoneText.notReady, GamesTetrisDuelChrome.opponentStatus(TetrisDuelOpponentBoard.empty, GamesTetrisDuelChrome.Stage.waiting))
    }

    /** 미니게임 문구: 테트리스 조작 줄에 '탭해서 회전' 이 꼭 있다 · 앱을 나간 테트리스는 '여기까지 기록' · 상금 20·10·5. */
    @Test
    fun miniGameCopyKeepsItsPromises() {
        assertTrue("탭해서 회전" in GamesMiniGameText.howToPlay(MiniGameKind.tetris))
        assertEquals("앱을 나가서 이번 판을 여기까지 기록했어요", GamesMiniGameText.endedInBackground(MiniGameKind.tetris))
        assertEquals("앱을 나가서 이번 판은 기록하지 않았어요", GamesMiniGameText.endedInBackground(MiniGameKind.flappy))
        assertEquals(listOf(20, 10, 5), GamesMiniGameText.rubyPrizes)
        assertEquals("자정에 1·2·3등에게 루비 20·10·5", GamesMiniGameText.prizeCaption)
        assertEquals("오늘은 아직 아무도 안 했어요 · 5명부터 지급", GamesMiniGameText.quorumCaption(0))
        assertNull(GamesMiniGameText.rankLine(null, knowsBoard = false), "모르면 머리 줄에서 뺀다")
        assertEquals("5 · 이기면 +5", TetrisPhoneText.stakeLine(5), "수수료 0 — 순이익 = 판돈")
        assertTrue(TetrisPhoneText.rules.none { "수수료" in it.second })
    }
}
