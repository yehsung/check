// 원본: Tests/CheckMobileKitTests/V1016RankingsAllTimeTests.swift @ 1a5eeca6 ([순위] 탭 미니게임 [오늘 | 역대] — 받는 때 · 안 받는 때 · 늦은 응답 · 실패 세 갈래 · 글자)
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class RankingsAllTimeTest {
    /** 일부러 서버 정렬을 뒤집어 준다(10 이 먼저) — 클라가 다시 세우는지 잰다. */
    private fun allTimeJson(top: Int): String =
        """[{"user_id":"u-low","display_name":"작은","avatar_url":null,"best_score":10,"best_at":"2026-09-01T01:00:00Z","day":"2026-09-01","center":null},""" +
            """{"user_id":"${StoreHarness.ME}","display_name":"나","avatar_url":null,"best_score":$top,"best_at":"2026-09-02T01:00:00Z","day":"2026-09-02","center":"seoul"}]"""

    private val todayJson = """[{"user_id":"u-today","display_name":"오늘","avatar_url":null,"best_score":7,"best_at":"2026-09-17T01:00:00Z","plays":3,"center":"seoul"}]"""

    private fun answering(r: RecordedRequest): Reply? = when (r.rpcName) {
        "minigame_board" -> Reply.Json(todayJson)
        "minigame_yesterday_winner" -> Reply.Json("[]")
        "minigame_alltime_board" -> Reply.Json(allTimeJson(if (r.bodyText.contains("\"p_game\":\"flappy\"")) 300 else 500))
        else -> null
    }

    private suspend fun TestScope.make(route: (RecordedRequest) -> Reply? = ::answering): Pair<StoreHarness, RankingsStore> {
        val h = StoreHarness(this, route)
        h.signIn()
        return h to RankingsStore(h.context, h.storeScope, NaturalKoNameCollation)
    }

    private fun StoreHarness.games(rpc: String): List<String> =
        storeRequests.filter { it.rpcName == rpc }.map { Regex("\"p_game\":\"([a-z_]+)\"").find(it.bodyText)!!.groupValues[1] }

    private fun TestScope.stale() = advanceTimeBy(((RankingsStore.staleSeconds + 1) * 1000).toLong())

    /** 미니게임 판을 [역대] 로 연다. 오늘 표는 안 받는 길이다(값을 먼저 고른 뒤 판을 연다). */
    private fun TestScope.openAllTime(store: RankingsStore) {
        store.select(MiniGameBoardScope.allTime)
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
    }

    // MARK: 받는 때 · 안 받는 때

    @Test
    fun todayNeverFetchesAllTime() = runTest {
        val (h, store) = make()
        assertEquals(MiniGameBoardScope.today, store.miniGameScope, "전환의 기본은 [오늘] 이다")
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_board"))
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_board"), "신선한 표에 탭 표시는 요청을 더 내지 않는다")
        store.select(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals(listOf("timing_bar", "flappy"), h.games("minigame_board"))
        store.refresh()
        advanceUntilIdle()
        assertEquals(3, h.count("minigame_board"))
        store.tabDidDisappear()
        stale()
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(0, h.count("minigame_alltime_board"), "[오늘] 을 보는 사람에게 역대 호출이 나갔다")
        assertEquals(4, h.count("minigame_board"))
        h.assertClean()
    }

    /** 띄운 조회는 떠날 때의 보기를 지킨다: 같은 틱에 [오늘]→[역대] 를 눌러도 오늘 조회가 역대 조회로 바뀌지 않는다. */
    @Test
    fun aLaunchedFetchKeepsItsScope() = runTest {
        val (h, store) = make()
        openAllTime(store)
        assertEquals(1, h.count("minigame_alltime_board"))
        assertEquals(0, h.count("minigame_board"))
        store.select(MiniGameBoardScope.today)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_board"), "오늘 조회가 사라졌다")
        assertEquals(1, h.count("minigame_alltime_board"), "신선한 역대 표를 오늘 조회 자리에서 다시 받았다")
        assertTrue(store.miniGameState.hasLoaded)
    }

    /** 띄운 조회는 떠날 때의 판을 지킨다: 같은 틱에 AI 토큰→미니게임을 골라도 토큰 조회가 미니게임 조회로 바뀌지 않는다. */
    @Test
    fun aLaunchedFetchKeepsItsBoard() = runTest {
        val (h, store) = make { r -> if (r.rpcName == "token_usage_board") Reply.Json("[]") else if (r.path == "/rest/v1/profiles") Reply.Json("[]") else answering(r) }
        store.select(RankingsBoard.tokens)
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertEquals(1, h.count("token_usage_board"), "토큰 조회가 사라졌다")
        assertEquals(1, h.count("minigame_board"), "한 번 고른 판을 두 번 받았다")
    }

    @Test
    fun selectingFetchesOnceAndSortsOnTheClient() = runTest {
        val (h, store) = make()
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertEquals(0, h.count("minigame_alltime_board"))
        store.select(MiniGameBoardScope.allTime)
        assertTrue(store.miniGameAllTimeState.isLoading, "고른 순간 '불러오는 중'이 서야 빈 표 문구가 깜빡이지 않는다")
        advanceUntilIdle()
        assertEquals(listOf("timing_bar"), h.games("minigame_alltime_board"))
        assertEquals(listOf(500L, 10L), store.miniGameAllTime.map { it.bestScore }, "서버 정렬을 믿었다")
        assertEquals("9/2", store.miniGameAllTime.first().dayCaption)
        assertEquals(store.myUserID, store.miniGameAllTime.first().userID, "내 줄 판정 재료가 어긋났다")
        store.select(MiniGameBoardScope.allTime)
        store.select(MiniGameBoardScope.today)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"), "오가며 누를 때마다 요청이 나갔다")
        assertEquals(1, h.count("minigame_board"), "신선한 오늘 표를 다시 받았다")
        h.assertClean()
    }

    @Test
    fun allTimeTriggers() = runTest {
        val (h, store) = make()
        openAllTime(store)
        store.tabDidDisappear()
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"), "신선한 표를 재진입마다 다시 받았다")
        store.tabDidDisappear()
        stale()
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(2, h.count("minigame_alltime_board"), "낡은 표를 재진입에서 안 받았다")
        store.refresh()
        assertEquals(3, h.count("minigame_alltime_board"), "당겨서 새로고침이 역대를 안 받았다")
        store.select(MiniGameKind.flappy)
        assertEquals(emptyList(), store.miniGameAllTime, "옮기는 순간 옛 게임 줄을 비운다")
        advanceUntilIdle()
        assertEquals(300L, store.miniGameAllTime.first().bestScore)
        assertEquals("flappy", h.games("minigame_alltime_board").last())
        assertEquals(4, h.count("minigame_alltime_board"))
        assertEquals(0, h.count("minigame_board"), "[역대] 를 보는데 오늘 표를 받았다")
        assertEquals(0, h.count("minigame_yesterday_winner"))
        h.assertClean()
    }

    @Test
    fun returningToTodayLoadsTheNewGame() = runTest {
        val (h, store) = make()
        openAllTime(store)
        store.select(MiniGameKind.flappy)
        assertFalse(store.miniGameState.isLoading, "안 받는 오늘 표에 '불러오는 중'이 섰다")
        advanceUntilIdle()
        store.select(MiniGameBoardScope.today)
        advanceUntilIdle()
        assertEquals(listOf("flappy"), h.games("minigame_board"))
        assertEquals(listOf("u-today"), store.miniGameBoard.map { it.userID })
    }

    @Test
    fun changingGameOnTodayClearsAllTimeWithoutFetching() = runTest {
        val (h, store) = make()
        openAllTime(store)
        store.select(MiniGameBoardScope.today)
        advanceUntilIdle()
        store.select(MiniGameKind.flappy)
        assertTrue(store.miniGameAllTime.isEmpty() && !store.miniGameAllTimeState.hasLoaded)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"))
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(300L, store.miniGameAllTime.first().bestScore)
        assertEquals("flappy", h.games("minigame_alltime_board").last())
    }

    @Test
    fun aScopeChosenOnAnotherBoardIsOnlyRemembered() = runTest {
        val (h, store) = make()
        assertEquals(RankingsBoard.league, store.board)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(MiniGameBoardScope.allTime, store.miniGameScope)
        assertEquals(0, h.count("minigame_alltime_board"))
        assertEquals(0, h.count("team_weekly_leaderboard"), "전환이 보고 있는 다른 판을 건드렸다")
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"))
    }

    @Test
    fun sameTickTogglesDoNotDoubleFetchOrStick() = runTest {
        val (h, store) = make()
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        store.select(MiniGameBoardScope.allTime)
        store.select(MiniGameBoardScope.today)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"))
        store.select(MiniGameBoardScope.today)
        stale()
        store.select(MiniGameBoardScope.allTime)
        store.select(MiniGameBoardScope.today)
        advanceUntilIdle()
        assertFalse(store.miniGameAllTimeState.isLoading, "다른 보기로 넘어갔다고 '불러오는 중'이 안 내려왔다")
    }

    // MARK: 늦은 응답

    @Test
    fun aLateResponseAfterAGameChangeIsDropped() = runTest {
        val gate = CompletableDeferred<Unit>()
        var held = false
        val (_, store) = make { r ->
            if (r.rpcName == "minigame_alltime_board" && !held) {
                held = true
                Reply.Gate(gate, Reply.Json(allTimeJson(500)))
            } else answering(r)
        }
        store.select(MiniGameBoardScope.allTime)
        store.select(RankingsBoard.minigame)
        runCurrent()
        store.select(MiniGameKind.flappy)
        runCurrent()
        assertEquals(300L, store.miniGameAllTime.first().bestScore)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(300L, store.miniGameAllTime.first().bestScore, "늦게 온 타이밍 바 역대가 플래피 화면을 덮었다")
        assertFalse(store.miniGameAllTimeState.isLoading)
    }

    @Test
    fun aLateResponseAfterMovingToTodayAndChangingGameIsDropped() = runTest {
        val gate = CompletableDeferred<Unit>()
        val (_, store) = make { r -> if (r.rpcName == "minigame_alltime_board") Reply.Gate(gate, Reply.Json(allTimeJson(500))) else answering(r) }
        store.select(MiniGameBoardScope.allTime)
        store.select(RankingsBoard.minigame)
        runCurrent()
        store.select(MiniGameBoardScope.today)
        store.select(MiniGameKind.flappy)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(emptyList(), store.miniGameAllTime, "[오늘] 에서 게임을 바꿨는데 옛 게임 역대가 꽂혔다")
        assertFalse(store.miniGameAllTimeState.hasLoaded)
        assertFalse(store.miniGameAllTimeState.isLoading)
    }

    @Test
    fun anOlderRequestIsDropped() = runTest {
        val gate = CompletableDeferred<Unit>()
        var n = 0
        val (_, store) = make { r ->
            if (r.rpcName == "minigame_alltime_board") {
                n += 1
                if (n == 1) Reply.Gate(gate, Reply.Json(allTimeJson(100))) else Reply.Json(allTimeJson(500))
            } else answering(r)
        }
        store.select(MiniGameBoardScope.allTime)
        store.select(RankingsBoard.minigame)
        runCurrent()
        store.refresh()
        assertEquals(500L, store.miniGameAllTime.first().bestScore)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(500L, store.miniGameAllTime.first().bestScore, "먼저 떠난 응답이 새 표를 덮었다")
        assertFalse(store.miniGameAllTimeState.isLoading)
    }

    /** [오늘] 로 돌아간 사이 닿은 응답은 쓴다 — 게임도 계정도 그대로라 버릴 까닭이 없고, 다음 [역대] 가 다시 안 묻는다. */
    @Test
    fun aResponseArrivingWhileOnTodayIsKept() = runTest {
        val gate = CompletableDeferred<Unit>()
        val (h, store) = make { r -> if (r.rpcName == "minigame_alltime_board") Reply.Gate(gate, Reply.Json(allTimeJson(500))) else answering(r) }
        store.select(MiniGameBoardScope.allTime)
        store.select(RankingsBoard.minigame)
        runCurrent()
        store.select(MiniGameBoardScope.today)
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(store.miniGameAllTimeState.hasLoaded)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"))
    }

    @Test
    fun signOutDropsALateResponseAndClears() = runTest {
        val gate = CompletableDeferred<Unit>()
        var n = 0
        val (h, store) = make { r ->
            when {
                r.rpcName == "minigame_alltime_board" -> {
                    n += 1
                    if (n == 1) Reply.Json(allTimeJson(500)) else Reply.Gate(gate, Reply.Json(allTimeJson(900)))
                }
                else -> answering(r)
            }
        }
        openAllTime(store)
        assertTrue(store.miniGameAllTime.isNotEmpty())
        // 당겨서 새로고침처럼 스토어 inflight 밖에서 부른 조회 — reset 의 취소가 닿지 않으므로 세대·순번 가드만이 막는다.
        val pull = launch { store.loadMiniGameAllTime() }
        runCurrent()
        h.session.signOut()
        store.reset()
        assertEquals(emptyList(), store.miniGameAllTime, "로그아웃이 남의 역대 줄을 안 비웠다")
        assertEquals(RankingsLoadState(), store.miniGameAllTimeState)
        assertEquals(MiniGameBoardScope.allTime, store.miniGameScope, "로그아웃이 보기 선택을 되돌렸다(계정이 아니라 이 실행의 값이다)")
        gate.complete(Unit)
        pull.join()
        advanceUntilIdle()
        assertEquals(emptyList(), store.miniGameAllTime, "로그아웃 뒤 늦게 온 역대가 화면에 섰다")
        assertEquals(RankingsLoadState(), store.miniGameAllTimeState)
    }

    @Test
    fun resetClearsUnavailableAndTheNextOpenRefetches() = runTest {
        var up = false
        val (h, store) = make { r -> if (r.rpcName == "minigame_alltime_board") (if (up) Reply.Json(allTimeJson(500)) else Reply.missingFunction) else answering(r) }
        openAllTime(store)
        assertTrue(store.miniGameAllTimeUnavailable)
        store.reset()
        assertFalse(store.miniGameAllTimeUnavailable, "접힌 표식을 다음 계정에 물려줬다")
        assertEquals(RankingsBoard.league, store.board)
        assertEquals(MiniGameKind.timingBar, store.miniGameKind)
        assertEquals(MiniGameBoardScope.allTime, store.miniGameScope)
        up = true
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertEquals(500L, store.miniGameAllTime.first().bestScore)
        assertEquals(2, h.count("minigame_alltime_board"))
    }

    // MARK: 실패 세 갈래

    @Test
    fun aMissingFunctionIsComingSoon() = runTest {
        var up = false
        val (h, store) = make { r -> if (r.rpcName == "minigame_alltime_board") (if (up) Reply.Json(allTimeJson(500)) else Reply.missingFunction) else answering(r) }
        openAllTime(store)
        assertTrue(store.miniGameAllTimeUnavailable)
        assertFalse(store.miniGameAllTimeState.hasFailed)
        assertTrue(store.miniGameAllTimeState.hasLoaded)
        assertEquals(GamesMiniGameText.allTimeUnavailableCaption, store.miniGameAllTimeEmptyText)
        assertFalse(store.miniGameAllTimeShowsRetry, "'준비 중' 옆에 [다시 시도] 가 붙으면 같은 404 를 영원히 두드린다")
        store.select(MiniGameBoardScope.today)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.count("minigame_alltime_board"))
        up = true
        store.refresh()
        assertFalse(store.miniGameAllTimeUnavailable, "함수가 올라온 뒤에도 '준비 중'이 남았다")
        assertEquals(500L, store.miniGameAllTime.first().bestScore)
    }

    @Test
    fun anotherFailureOffersRetry() = runTest {
        val replies = ArrayDeque(listOf(Reply.Offline, Reply.serverDown, Reply.Json(allTimeJson(500))))
        val (h, store) = make { r -> if (r.rpcName == "minigame_alltime_board") replies.removeFirst() else answering(r) }
        openAllTime(store)
        assertTrue(store.miniGameAllTimeState.hasFailed)
        assertFalse(store.miniGameAllTimeUnavailable, "네트워크 실패를 '준비 중'으로 접었다")
        assertTrue(store.miniGameAllTimeShowsRetry)
        assertEquals(GamesMiniGameText.allTimeFailedCaption, store.miniGameAllTimeEmptyText)
        // 다시 보러 온 것이 곧 재시도 의사다(30초 안이어도).
        store.select(MiniGameBoardScope.today)
        store.select(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(2, h.count("minigame_alltime_board"))
        assertTrue(store.miniGameAllTimeState.hasFailed, "5xx 도 실패다")
        assertTrue(h.session.isSignedIn, "5xx 로 로그아웃되면 안 된다")
        store.loadMiniGameAllTime()
        assertFalse(store.miniGameAllTimeState.hasFailed)
        assertEquals(500L, store.miniGameAllTime.first().bestScore)
        assertFalse(store.miniGameAllTimeShowsRetry)
    }

    @Test
    fun cancellationChangesNothing() = runTest {
        val replies = ArrayDeque(listOf(Reply.Cancelled, Reply.Offline, Reply.Cancelled, Reply.Json(allTimeJson(500)), Reply.Cancelled))
        val (_, store) = make { r -> if (r.rpcName == "minigame_alltime_board") replies.removeFirst() else answering(r) }
        store.select(MiniGameBoardScope.allTime)
        store.loadMiniGameAllTime()
        assertFalse(store.miniGameAllTimeState.hasFailed || store.miniGameAllTimeState.hasLoaded || store.miniGameAllTimeUnavailable)
        assertFalse(store.miniGameAllTimeState.isLoading)
        store.loadMiniGameAllTime()
        assertTrue(store.miniGameAllTimeShowsRetry)
        store.loadMiniGameAllTime()
        assertTrue(store.miniGameAllTimeShowsRetry, "[다시 시도] 가 취소되자 버튼 없는 '불러오는 중' 카드로 굳었다")
        assertEquals(GamesMiniGameText.allTimeFailedCaption, store.miniGameAllTimeEmptyText)
        store.loadMiniGameAllTime()
        val loaded = store.miniGameAllTimeState
        advanceTimeBy(5_000)
        store.loadMiniGameAllTime()
        assertEquals(500L, store.miniGameAllTime.first().bestScore, "취소가 그려 둔 줄을 지웠다")
        assertEquals(loaded, store.miniGameAllTimeState, "취소가 상태를 바꿨다")
    }

    @Test
    fun rowsSurviveAFailureAndTheNextVisitAsksAgain() = runTest {
        val replies = ArrayDeque(listOf(Reply.Json(allTimeJson(500)), Reply.Offline, Reply.Json(allTimeJson(600))))
        val (_, store) = make { r -> if (r.rpcName == "minigame_alltime_board") replies.removeFirst() else answering(r) }
        openAllTime(store)
        store.refresh()
        assertTrue(store.miniGameAllTimeState.hasFailed)
        assertEquals(listOf(500L, 10L), store.miniGameAllTime.map { it.bestScore }, "실패가 그려 둔 줄을 지웠다")
        assertFalse(store.miniGameAllTimeShowsRetry, "그려 둔 표 위에 실패 카드가 섰다")
        store.tabDidDisappear()
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(600L, store.miniGameAllTime.first().bestScore, "실패한 표를 신선하다고 보고 다시 안 물었다")
    }

    // MARK: 글자

    @Test
    fun rowAccessibilityReadsTheDateOnAllTimeOnly() {
        val entry = MiniGameBoardEntry("u", "구름빵", null, 40, null, 0, "서울")
        val today = RankingsText.miniGameRowAccessibility(1, entry, true)
        assertEquals("1위, 구름빵, 서울센터, ${RankingsText.score(40)}, ${RankingsText.meChip}", today)
        val allTime = RankingsText.miniGameRowAccessibility(1, entry, true, dayCaption = "9/13")
        assertEquals("1위, 구름빵, 서울센터, ${RankingsText.score(40)}, 9/13 기록, ${RankingsText.meChip}", allTime)
    }

    @Test
    fun theSubtitleFollowsTheScope() = runTest {
        val (_, store) = make()
        assertEquals("이번 주 · 월요일 0시에 새로 시작해요", store.boardSubtitle)
        store.select(MiniGameBoardScope.allTime)
        assertEquals("이번 주 · 월요일 0시에 새로 시작해요", store.boardSubtitle, "미니게임 보기가 다른 판 부제를 바꿨다")
        store.select(RankingsBoard.minigame)
        assertEquals("역대 · 마감 없이 이어져요", store.boardSubtitle)
        store.select(MiniGameBoardScope.today)
        assertEquals("오늘 · 자정에 마감해요", store.boardSubtitle)
    }

    /** 빈 칸 문구는 [게임] 탭과 한 벌이다. 표의 순서가 곧 뜻이다(실패 → 준비 중 → 불러오는 중 → 아직 없음). */
    @Test
    fun theEmptyTextSharesTheGamesTable() = runTest {
        val (_, store) = make { r -> if (r.rpcName == "minigame_alltime_board") Reply.Json("[]") else answering(r) }
        assertEquals(GamesMiniGameText.loadingCaption, store.miniGameAllTimeEmptyText)
        store.loadMiniGameAllTime()
        assertEquals(GamesMiniGameText.emptyBoard, store.miniGameAllTimeEmptyText)
        assertFalse(store.miniGameAllTimeShowsRetry)
        assertEquals(GamesMiniGameText.allTimeFailedCaption, GamesMiniGameText.allTimeEmpty(failed = true, loaded = false, unavailable = true), "실패가 준비 중보다 먼저다")
        assertEquals(GamesMiniGameText.allTimeUnavailableCaption, GamesMiniGameText.allTimeEmpty(failed = false, loaded = true, unavailable = true))
        assertEquals(GamesMiniGameText.emptyBoard, GamesMiniGameText.allTimeEmpty(failed = true, loaded = true, unavailable = false), "받은 빈 표는 지난 실패로 덮지 않는다")
    }
}
