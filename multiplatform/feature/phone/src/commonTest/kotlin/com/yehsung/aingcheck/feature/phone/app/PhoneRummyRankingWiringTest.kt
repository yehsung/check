// 원본: Sources/check/RummyPanelLobby.swift:401 (RummyRankList) · Tests/checkTests/V0369RummyWiringTests.swift(순위 주 스위치의 폰 몫) @ 1a5eeca6 · ios-1017 설계서 §5
//
// `rankingEnabled` 는 기본이 꺼짐이라 조립 한 줄이 빠지면 `rummy_ranking` 이 한 번도 안 나가고 순위 탭이 영영 빈다 — 화면이 죽는데 값 시험은 초록이다.
// 그래서 값이 아니라 **요청 건수**로 잰다. 꺼 놓은 기준선을 함께 두어 이 시험이 스위치를 실제로 재는지 확인한다(기억 comparison-baseline-must-differ).
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.refreshRanking
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneRummyRankingWiringTest {
    private companion object {
        const val PEER = "bbbbbbbb-0000-4000-8000-000000000002"
        const val NOW_MS = 1_789_621_500_000L
    }

    private fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
        "rummy_lobby" -> Reply.Json("""{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}""")
        "rummy_ranking" -> Reply.Json(
            """{"status":"ok","server_now_ms":$NOW_MS,"rows":[{"id":"$PEER","display_name":"비","games":3,"wins":2,"rank":1}],"me":{"games":1,"wins":0,"rank":2}}""",
        )
        "message_unread_summary" -> Reply.Json("""{"status":"ok","total":0,"peers":[]}""")
        "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
        "app_user_directory", "message_blocks", "my_blocked_users", "blocked_users" -> Reply.Json("[]")
        "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby" -> Reply.missingFunction
        "work_phone_touch" -> Reply.Json("""{"status":"not_working"}""")
        else -> null
    }

    private fun TestScope.rig(): PhoneHarness {
        val h = PhoneHarness(this, appConfig = AppConfig(duelsEnabled = true)) { route(it) }
        h.signIn()
        // 끝이 없는 두 고리를 재운다(주기는 코어 시험이 잰다).
        h.app.rummy.heartbeatEnabled = false
        h.app.rummy.pollStepSeconds = Double.POSITIVE_INFINITY
        h.app.sceneDidBecomeActive()
        advanceUntilIdle()
        return h
    }

    /** 조립 그대로: 큐브 화면이 뜨면 순위를 한 번 읽는다. 이 줄이 빨강이면 PhoneAppModel 의 `rummy.rankingEnabled = true` 가 빠졌다. */
    @Test
    fun openingTheScreenAsksForTheRanking() = runTest {
        val h = rig()
        h.markRequests()
        h.app.games.rummyScreenDidAppear()
        advanceUntilIdle()
        assertEquals(1, h.count("rummy_ranking"), "순위 스위치가 꺼져 있다 — 순위 탭이 영영 빈다")
        assertEquals(1, assertNotNull(h.app.rummy.ranking).rows?.size)
        h.app.games.rummyScreenDidDisappear()
    }

    /** 순위 탭이 부르는 입구도 같은 스위치를 지난다. */
    @Test
    fun theTabEntryReachesTheServer() = runTest {
        val h = rig()
        h.markRequests()
        h.app.rummy.refreshRanking()
        advanceUntilIdle()
        assertEquals(1, h.count("rummy_ranking"))
    }

    /** ★ 기준선: 스위치를 끄면 같은 길이 0건이다 — 위 두 시험이 스위치를 재고 있다는 증거. */
    @Test
    fun switchOffSendsNothing() = runTest {
        val h = rig()
        h.app.rummy.rankingEnabled = false
        h.markRequests()
        h.app.games.rummyScreenDidAppear()
        h.app.rummy.refreshRanking()
        advanceUntilIdle()
        assertEquals(0, h.count("rummy_ranking"))
        assertNull(h.app.rummy.ranking)
        h.app.games.rummyScreenDidDisappear()
    }
}
