// 원본: Tests/checkTests/V0367MiniGameAllTimeTests.swift(맥 [오늘|역대]) · Sources/check/WorkTimerStoreMiniGame.swift:920-1000 @ 1b8260d
// 6차 지시: "역대 순위 `minigame_alltime_board`·[오늘|역대] 상태도 스토어에" — 폰 허브에 맥 규약 그대로(지금 연 게임 한 판).
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MiniGameAllTimeTest {
    private class Stub {
        val allTime = ArrayDeque<Reply>()
        fun route(r: RecordedRequest): Reply? = when {
            r.rpcName == "minigame_alltime_board" -> allTime.removeFirstOrNull() ?: rows(500)
            r.rpcName == "minigame_start_round" -> Reply.Json("""{"status":"ok","token":"t"}""")
            r.rpcName == "minigame_submit_score" -> Reply.Json("""{"status":"ok","best_score":10}""")
            r.rpcName == "minigame_board" || r.rpcName == "minigame_yesterday_winner" -> Reply.Json("[]")
            r.path == "/rest/v1/profiles" -> Reply.Json("""[{"minigame_public":true}]""")
            else -> null
        }

        companion object {
            fun rows(mine: Int) = Reply.Json(
                """[{"user_id":"${StoreFixtures.PEER}","display_name":"구름빵","best_score":900,"best_at":"2026-09-01T01:00:00Z","day":"2026-09-01"},""" +
                    """{"user_id":"${StoreFixtures.USER}","display_name":"나","best_score":$mine,"best_at":"2026-09-02T01:00:00Z","day":"2026-09-02"},""" +
                    """{"display_name":"깨진 행"}]""",
            )
        }
    }

    private suspend fun TestScope.open(stub: Stub = Stub()): Pair<StoreHarness, GamesMiniGameHub> {
        val h = StoreHarness(this, route = stub::route)
        h.signIn()
        return h to GamesMiniGameHub(h.context)
    }

    private fun StoreHarness.allTimeCalls(): List<String> =
        server.requests.filter { it.rpcName == "minigame_alltime_board" }.map { Regex("\"p_game\":\"([a-z_]+)\"").find(it.bodyText)!!.groupValues[1] }

    /**
     * [역대] 로 넘어갈 때 한 번 받고, 오가며 눌러도 최신이면 다시 받지 않는다 · 판이 기록되면 낡음 표시가 서서 다음에 [역대] 를 볼 때(지금 보고 있으면
     * 곧바로) 다시 받는다 · 행 하나가 깨져도 그 행만 버리고 내 역대 행은 로컬 최고를 올린다. 보기 선택은 로그아웃이 되돌리지 않는다.
     */
    @Test
    fun allTimeLoadsOnDemandAndRefreshesAfterARecordedRound() = runTest {
        val (h, hub) = open()
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals(emptyList(), h.allTimeCalls(), "[오늘] 이면 역대를 받지 않는다")
        hub.selectBoardScope(MiniGameBoardScope.allTime)
        assertTrue(hub.allTimeLoading, "첫 프레임부터 불러오는 중")
        advanceUntilIdle()
        assertEquals(listOf("flappy"), h.allTimeCalls())
        assertEquals(listOf(StoreFixtures.PEER, StoreFixtures.USER), hub.allTimeBoard.map { it.userID }, "점수 내림 · 깨진 행은 버린다")
        assertTrue(hub.allTimeLoaded)
        assertFalse(hub.allTimeLoading)
        assertEquals(500L, hub.best(MiniGameKind.flappy), "내 역대 행이 로컬 최고를 올린다")
        hub.selectBoardScope(MiniGameBoardScope.today)
        hub.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.allTimeCalls().size, "최신 표를 들고 있으면 다시 받지 않는다")
        hub.selectBoardScope(MiniGameBoardScope.today)
        hub.recordScore(MiniGameKind.flappy, 10)
        advanceUntilIdle()
        assertEquals(1, h.allTimeCalls().size, "[오늘] 을 보는 동안 기록된 판은 역대를 당기지 않는다")
        hub.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(2, h.allTimeCalls().size, "판이 기록돼 낡았으니 [역대] 로 넘어갈 때 다시 받는다")
        hub.recordScore(MiniGameKind.flappy, 11)
        advanceUntilIdle()
        assertEquals(3, h.allTimeCalls().size, "[역대] 를 보는 중에 기록되면 오늘 순위 뒤에 곧바로 다시 받는다")
        hub.reset()
        assertEquals(MiniGameBoardScope.allTime, hub.boardScope, "보기 선택은 앱 실행의 것 — 로그아웃이 되돌리지 않는다")
        assertTrue(hub.allTimeBoard.isEmpty(), "남의 행은 계정에 묶인다")
    }

    /** 게임을 바꾸면 앞 게임의 역대 표를 비운다(앞 게임 1등이 이 게임 1등인 척 보이면 안 된다) — [역대] 를 보는 중이면 바뀐 게임 표를 곧바로 받는다. */
    @Test
    fun switchingGamesClearsTheTable() = runTest {
        val (h, hub) = open()
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertTrue(hub.allTimeBoard.isNotEmpty())
        hub.openScreen(MiniGameKind.tetris)
        assertTrue(hub.allTimeBoard.isEmpty(), "바꾸는 순간 비운다")
        assertTrue(hub.allTimeLoading)
        advanceUntilIdle()
        assertEquals(listOf("flappy", "tetris"), h.allTimeCalls())
        assertEquals(null, hub.myAllTimeBest(MiniGameKind.flappy), "남은 표는 지금 게임(테트리스)의 것이다")
        assertEquals(500L, hub.myAllTimeBest(MiniGameKind.tetris))
    }

    /** 실패는 셋: 함수가 없는 서버(PGRST202 · 404) → '준비 중'(실패 아님, 오가며 눌러도 다시 안 두드림) · 5xx → 실패(다시 보러 오면 한 번 더) · 늦은 옛 응답은 새 표를 덮지 않는다. */
    @Test
    fun failuresAreSortedIntoUnavailableFailedAndStale() = runTest {
        val stub = Stub()
        stub.allTime += Reply.pgrst202
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.timingBar)
        advanceUntilIdle()
        hub.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertTrue(hub.allTimeUnavailable)
        assertFalse(hub.allTimeFailed, "준비 중은 실패가 아니다")
        assertTrue(hub.allTimeLoaded)
        hub.selectBoardScope(MiniGameBoardScope.today)
        hub.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(1, h.allTimeCalls().size, "같은 게임으로 오가며 404 를 다시 두드리지 않는다")

        val stub2 = Stub()
        stub2.allTime += Reply.serverDown
        val (h2, hub2) = open(stub2)
        hub2.openScreen(MiniGameKind.timingBar)
        advanceUntilIdle()
        hub2.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertTrue(hub2.allTimeFailed)
        assertFalse(hub2.allTimeUnavailable)
        hub2.selectBoardScope(MiniGameBoardScope.today)
        hub2.selectBoardScope(MiniGameBoardScope.allTime)
        advanceUntilIdle()
        assertEquals(2, h2.allTimeCalls().size, "실패한 채였으면 다시 보러 올 때 한 번 더 받는다")
        assertFalse(hub2.allTimeFailed)

        val stub3 = Stub()
        val slow = CompletableDeferred<Unit>()
        stub3.allTime += Reply.Gate(slow, Stub.rows(1))
        stub3.allTime += Stub.rows(777)
        val (_, hub3) = open(stub3)
        hub3.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub3.selectBoardScope(MiniGameBoardScope.allTime)
        runCurrent()
        hub3.loadAllTimeBoard()     // [다시 시도] — 뒤에 떠난 받기
        advanceUntilIdle()
        assertEquals(777L, hub3.myAllTimeBest(MiniGameKind.flappy))
        slow.complete(Unit)
        advanceUntilIdle()
        assertEquals(777L, hub3.myAllTimeBest(MiniGameKind.flappy), "늦게 닿은 옛 받기는 새 표를 덮지 않는다")
    }
}
