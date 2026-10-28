// 원본: Tests/CheckMobileKitTests/RankingsStoreTests.swift @ 1b8260d (+ G §2-3 W2-b ③ 공유 Codex 비율은 서버값만 — 원본 없음)
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class RankingsStoreTest {
    private val league = """
        [
          {"team_id":"t-low","team_name":"낮은팀","weekly_goal_hours":40,"total_seconds":36000,"working_count":0,"member_count":2,"center":null},
          {"team_id":"team-1","team_name":"테스트팀","weekly_goal_hours":40,"total_seconds":0,"working_count":0,"member_count":3,"center":"seoul"},
          {"team_id":"t-high","team_name":"높은팀","weekly_goal_hours":40,"total_seconds":288000,"working_count":2,"member_count":4,"center":"busan"},
          {"team_id":"t-zero","team_name":"쉬는팀","weekly_goal_hours":40,"total_seconds":0,"working_count":0,"member_count":3,"center":null}
        ]
    """.trimIndent()

    private fun tokenRow(user: String, name: String, total: Long, today: Long = 0, todayDate: String = "2026-09-17"): String =
        """{"user_id":"$user","display_name":"$name","avatar_url":null,"claude_input":$total,"claude_output":0,"claude_cache_read":0,""" +
            """"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":$total,"today_total":$today,"today_date":"$todayDate",""" +
            """"codex_effective":0,"center":null}"""

    private fun boardRow(user: String, name: String, score: Long, at: String): String =
        """{"user_id":"$user","display_name":"$name","avatar_url":null,"best_score":$score,"best_at":"$at","plays":3,"center":"seoul"}"""

    private suspend fun TestScope.make(route: (RecordedRequest) -> Reply?): Pair<StoreHarness, RankingsStore> {
        val h = StoreHarness(this, route)
        h.signIn()
        return h to RankingsStore(h.context, h.storeScope, NaturalKoNameCollation)
    }

    private fun body(r: RecordedRequest, key: String): String? = (SwiftJson.parse(r.bodyText) as? JsonObject)?.get(key)?.jsonPrimitive?.content

    @Test
    fun scenarioLeagueTokensMiniGameReadOnly() = runTest {
        val me = StoreHarness.ME
        val (h, store) = make { r ->
            when (r.rpcName) {
                "team_weekly_leaderboard" -> Reply.Json(league)
                "token_usage_board" -> if (r.bodyText.contains("2026-08")) Reply.Json("[${tokenRow("u-aug", "팔월", 900)}]") else Reply.Json(
                    "[${tokenRow("u-small", "작은", 10)},${tokenRow(me, "나", 5000, today = 70)},${tokenRow("u-old", "옛날", 300, 99, "2026-09-10")}]",
                )
                "minigame_board" -> if (r.bodyText.contains("flappy")) Reply.Json("[${boardRow("u-f", "플래피", 12, "2026-09-17T01:00:00Z")}]") else Reply.Json(
                    "[${boardRow("u-b", "늦게", 900, "2026-09-17T03:00:00Z")},${boardRow(me, "나", 950, "2026-09-17T02:00:00Z")}," +
                        "${boardRow("u-a", "먼저", 900, "2026-09-17T01:00:00Z")}]",
                )
                "minigame_yesterday_winner" -> if (r.bodyText.contains("flappy")) Reply.Json("[]") else Reply.Json(
                    """[{"day":"2026-09-16","user_id":"u-a","display_name":"먼저","avatar_url":null,"score":990,"awarded":true,"center":"busan"}]""",
                )
                else -> if (r.path == "/rest/v1/profiles" && r.method == "GET") Reply.Json("""[{"token_usage_public":false,"token_usage_collect":true,"focus_mode":true}]""") else null
            }
        }
        // 보이지 않는 탭은 서버를 두드리지 않는다.
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(emptyList(), h.paths())

        store.tabDidAppear()
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded)
        assertEquals(listOf("t-high", "t-low", "team-1"), store.leagueDisplay.map { it.id }, "평균 내림차순 + 0시간 팀 숨김 + 내 팀 유지")
        assertEquals("각자 목표 40시간 · 총 80시간 00분 · 4명 · 2명 근무중", RankingsText.leagueCaption(store.leagueDisplay[0], h.now()))
        assertEquals("평균 20시간 00분", RankingsText.leagueAverage(store.leagueDisplay[0]))
        assertEquals(50, RankingsText.leaguePercent(store.leagueDisplay[0]))
        // 신선한 판은 다시 부르지 않는다 · 30초가 지나면 active 에서 다시.
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(1, h.count("team_weekly_leaderboard"))
        advanceTimeBy(31_000)
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(2, h.count("team_weekly_leaderboard"))

        store.select(RankingsBoard.tokens)
        advanceUntilIdle()
        assertEquals("2026-09", store.tokenMonth)
        assertEquals(listOf(me, "u-old", "u-small"), store.tokenBoard.map { it.userID })
        assertEquals(false, store.myTokenUsagePublic, "내 행 비공개 칩")
        assertEquals("9월 AI 토큰 소모량", store.tokenTitle)
        assertEquals("오늘 +70 토큰", RankingsText.tokenToday(store.tokenBoard[0], store.todayKey))
        assertEquals("오늘 +0 토큰", RankingsText.tokenToday(store.tokenBoard[1], store.todayKey), "어제 이후 스테일 행은 0")
        store.stepTokenMonth(1)
        advanceUntilIdle()
        assertEquals(1, h.count("token_usage_board"), "미래 달로는 못 간다 — 값이 그대로면 요청도 없다")
        store.stepTokenMonth(-1)
        assertEquals(emptyList(), store.tokenBoard, "옮기는 순간 이전 달 행을 비운다")
        advanceUntilIdle()
        assertEquals(listOf("u-aug"), store.tokenBoard.map { it.userID })
        assertFalse(store.isCurrentTokenMonth)

        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertEquals(listOf(me, "u-a", "u-b"), store.miniGameBoard.map { it.userID }, "점수 → 먼저 낸 사람")
        assertEquals(1, store.myMiniGameRank)
        assertEquals(true, store.miniGameWinner?.awarded)
        assertEquals("timing_bar", body(h.storeRequests.first { it.rpcName == "minigame_board" }, "p_game"))
        store.select(MiniGameKind.flappy)
        assertEquals(emptyList(), store.miniGameBoard)
        advanceUntilIdle()
        assertEquals(listOf("u-f"), store.miniGameBoard.map { it.userID })
        assertNull(store.miniGameWinner)

        // 읽기만 한다: RPC 는 전부 조회, 표는 GET 만.
        val writes = h.storeRequests.filter { it.rpcName == null && it.method != "GET" }
        assertEquals(emptyList(), writes.map { "${it.method} ${it.path}" }, "순위 탭이 쓰기를 냈다")
        h.assertClean()
    }

    /**
     * G §2-3 W2-b ③ — **공유 Codex 비율은 서버값만**. 서버가 나눈 몫(`codex_effective` · `codex_account_month`)과 `total` 을 그대로 그리고,
     * 로컬 Codex(입력·출력)나 계정 월합으로 다시 재지 않는다. 기준선: 같은 행에서 로컬 값이 서버 몫과 크게 다르다(다시 재면 숫자가 바뀐다).
     */
    @Test
    fun sharedCodexShareUsesServerValuesOnly() = runTest {
        val me = StoreHarness.ME
        // 나: 로컬 Codex 9억(입력+출력)인데 서버가 공유 계정에서 나눈 내 몫은 3천만 · total 은 그 몫으로 센 값.
        val mine = """{"user_id":"$me","display_name":"나","avatar_url":null,"claude_input":1000,"claude_output":0,"claude_cache_read":0,""" +
            """"claude_cache_creation":0,"codex_input":800000000,"codex_output":100000000,"total":30001000,"today_total":0,"today_date":"2026-09-17",""" +
            """"codex_cache_read":0,"codex_account_month":30000000,"codex_effective":30000000,"center":null}"""
        // 동료: 로컬 0 이지만 공유 계정 몫 5억 — total 이 내 행보다 크다(정렬은 서버 total).
        val peer = """{"user_id":"u-peer","display_name":"동료","avatar_url":null,"claude_input":0,"claude_output":0,"claude_cache_read":0,""" +
            """"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":500000000,"today_total":0,"today_date":"2026-09-17",""" +
            """"codex_cache_read":0,"codex_account_month":500000000,"codex_effective":500000000,"center":null}"""
        val (h, store) = make { r ->
            when (r.rpcName) {
                "team_weekly_leaderboard" -> Reply.Json("[]")
                "token_usage_board" -> Reply.Json("[$mine,$peer]")
                else -> if (r.path == "/rest/v1/profiles" && r.method == "GET") Reply.Json("[]") else null
            }
        }
        store.tabDidAppear()
        store.select(RankingsBoard.tokens)
        advanceUntilIdle()
        assertEquals(listOf("u-peer", me), store.tokenBoard.map { it.userID }, "정렬은 서버 total — 로컬 9억으로 다시 재면 내가 위로 간다")
        val row = store.tokenBoard.single { it.userID == me }
        assertEquals(30_000_000L, row.codexEffective, "서버 몫 대신 로컬·계정으로 다시 쟀다")
        assertEquals(30_001_000L, row.total)
        assertEquals(0L, row.antigravityEffective)
        assertEquals("Claude 1,000 · Codex 3,000만", TokenBoardText.toolUsageLabel(row))
        assertEquals("Claude 1,000 · Codex 30,000,000", TokenBoardText.detailTooltip(row))
        h.assertClean()
    }

    @Test
    fun lateTokenResponseForPreviousMonthIsDropped() = runTest {
        val gate = CompletableDeferred<Unit>()
        val (h, store) = make { r ->
            when (r.rpcName) {
                "team_weekly_leaderboard" -> Reply.Json("[]")
                "token_usage_board" -> if (r.bodyText.contains("2026-09")) Reply.Gate(gate, Reply.Json("[${tokenRow("u-sep", "구월", 10)}]")) else Reply.Json(
                    "[${tokenRow("u-aug", "팔월", 9)}]",
                )
                else -> if (r.path == "/rest/v1/profiles" && r.method == "GET") Reply.Json("[]") else null
            }
        }
        store.tabDidAppear()
        store.select(RankingsBoard.tokens)
        runCurrent()
        // 9월 조회가 떠 있는 채로 8월로 옮긴다(가상 시간을 밀지 않는다 — 밀면 멈춘 조회가 HTTP 시한에 걸려 '늦은 응답'이 아니라 '실패'가 된다).
        store.stepTokenMonth(-1)
        runCurrent()
        assertEquals(listOf("u-aug"), store.tokenBoard.map { it.userID })
        gate.complete(Unit)
        runCurrent()
        assertTrue(h.storeRequests.any { it.rpcName == "token_usage_board" && it.bodyText.contains("2026-09") }, "9월 조회가 떠나지 않았다")
        assertEquals("2026-08", store.tokenMonth)
        assertEquals(listOf("u-aug"), store.tokenBoard.map { it.userID }, "옮긴 뒤 도착한 이전 달 응답이 꽂혔다")
        advanceUntilIdle()
        h.assertClean()
    }

    @Test
    fun resetAfterSignOutDropsInFlightLeague() = runTest {
        val gate = CompletableDeferred<Unit>()
        val (h, store) = make { r -> if (r.rpcName == "team_weekly_leaderboard") Reply.Gate(gate, Reply.Json(league)) else null }
        store.tabDidAppear()
        runCurrent()
        h.session.signOut()
        store.reset()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(emptyList(), store.league, "로그아웃 뒤 도착한 리그가 들어왔다")
        assertFalse(store.leagueState.hasLoaded)
        h.assertClean()
    }

    /** 작업 취소가 닿지 않는 조회(직접 부른 loadLeague)도 세대·순번 가드가 버린다 — 위 시험은 reset 의 취소가 먼저 막는다(결함 심기 M22). */
    @Test
    fun lateLeagueOutsideInflightIsDroppedByGenerationAndSerial() = runTest {
        val gate = CompletableDeferred<Unit>()
        val (h, store) = make { r -> if (r.rpcName == "team_weekly_leaderboard") Reply.Gate(gate, Reply.Json(league)) else null }
        val late = launch { store.loadLeague() }
        runCurrent()
        val startedAt = testScheduler.currentTime
        h.session.signOut()
        store.reset()
        gate.complete(Unit)
        late.join()
        assertEquals(startedAt, testScheduler.currentTime, "멈춘 조회가 시한에 걸렸다(늦은 응답을 재지 못했다)")
        assertEquals(emptyList(), store.league, "로그아웃 뒤 도착한 리그가 다음 계정 화면에 들어왔다")
        assertFalse(store.leagueState.hasLoaded)
        assertFalse(store.leagueState.isLoading)
        h.assertClean()
    }

    @Test
    fun missingMiniGameFunctionIsNotAFailure() = runTest {
        val (h, store) = make { r ->
            when (r.rpcName) {
                "team_weekly_leaderboard" -> Reply.serverDown
                "minigame_board", "minigame_yesterday_winner" -> Reply.missingFunction
                else -> null
            }
        }
        store.tabDidAppear()
        advanceUntilIdle()
        assertTrue(store.leagueState.hasFailed, "리그 503 은 실패 + 다시 시도")
        assertEquals(RankingsText.leagueFailed, RankingsText.leagueEmpty(store.leagueState.hasLoaded, store.leagueState.isLoading, store.leagueState.hasFailed, 0))
        store.select(RankingsBoard.minigame)
        advanceUntilIdle()
        assertTrue(store.miniGameState.hasLoaded)
        assertFalse(store.miniGameState.hasFailed, "함수 없음(PGRST202)은 실패가 아니라 '아직 없음'")
        assertEquals(RankingsText.miniGameEmpty, RankingsText.miniGameEmptyText(store.miniGameState.hasLoaded, store.miniGameState.hasFailed))
        h.assertClean()
    }
}
