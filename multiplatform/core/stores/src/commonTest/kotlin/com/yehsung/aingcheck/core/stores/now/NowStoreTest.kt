// 원본: Tests/CheckMobileKitTests/NowStoreTests.swift · NowTeamJoinTests.swift:148(합류 전에 떠난 소속 조회의 늦은 [] — W2-a 이월) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
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
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class NowStoreTest {
    private val me = StoreHarness.ME

    /** 데모 시각(2026-09-17 14:05 KST = 05:05Z): 나는 13:00 KST 부터 근무 중(신호 30초 전), 팀원 한 명은 끊김(신호 5분 전). */
    private fun teamRoutes(r: RecordedRequest): Reply? = when {
        r.path == "/rest/v1/work_statuses" -> Reply.Json(
            """[{"user_id":"$me","status":"working","updated_at":"2026-09-17T05:04:30Z","last_seen_at":"2026-09-17T05:04:30Z","active_session_id":"S-1",""" +
                """"profiles":{"display_name":"나","avatar_url":null}},""" +
                """{"user_id":"mate-1","status":"working","updated_at":"2026-09-17T05:00:00Z","last_seen_at":"2026-09-17T05:00:00Z","active_session_id":null,""" +
                """"profiles":{"display_name":"민트","avatar_url":null}}]""",
        )
        r.path == "/rest/v1/work_sessions" && r.query.any { it.second == "is.null" } -> Reply.Json(
            """[{"id":"S-1","user_id":"$me","started_at":"2026-09-17T04:00:00Z","ended_at":null,"duration_seconds":null},""" +
                """{"id":"S-2","user_id":"mate-1","started_at":"2026-09-17T03:00:00Z","ended_at":null,"duration_seconds":null}]""",
        )
        r.path == "/rest/v1/work_sessions" -> Reply.Json(
            """[{"user_id":"$me","started_at":"2026-09-16T23:00:00Z","ended_at":"2026-09-17T01:00:00Z"}]""",
        )
        r.path == "/rest/v1/work_status_devices" -> Reply.Json("[]")
        // active 진입이 할 일을 한 번 맞춘다(빈 목록 · 받기만).
        r.rpcName == "todo_sync" -> Reply.Json("""{"status":"ok","items":[],"watermark_ms":1789621500000,"rejected":[],"full":true}""")
        r.rpcName == "app_user_directory" -> Reply.Json(
            """[{"user_id":"other-1","display_name":"다른팀","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan","status_message":"집중"},""" +
                """{"user_id":"mate-1","display_name":"민트","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"}]""",
        )
        else -> null
    }

    private suspend fun TestScope.make(route: (RecordedRequest) -> Reply? = ::teamRoutes): Pair<StoreHarness, NowStore> {
        val h = StoreHarness(this, route)
        h.signIn()
        return h to NowStore(h.context, h.storeScope, NowTodoStorage("/mem/now", InMemoryTodoFileSystem()), timers = ManualScheduler())
    }

    @Test
    fun refreshReadsTeamValuesOnlyAndComputesCards() = runTest {
        val (h, store) = make()
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(NowLoadState.loaded, store.teamLoadState)
        assertEquals(NowMembership("team-1", "아잉 데모팀", 40, "member"), store.membership)
        val card = store.myCard(h.now())!!
        assertTrue(card.isWorking)
        assertFalse(card.isStale)
        // 오늘: 끝난 세션 08:00~10:00 KST(2시간 — 전부 오늘) + 진행 13:00~14:05(65분).
        assertEquals(2 * 3600 + 65 * 60, card.todaySeconds)
        assertEquals("근무 중", card.stateText, "출처를 모르면(폰 RPC 응답 전) '근무 중'으로만")
        val people = store.workingPeople(h.now())
        assertEquals(listOf("mate-1", "other-1"), people.map { it.id }, "우리 팀 먼저(나 제외), 그다음 다른 팀")
        assertTrue(people[0].isStale, "신호 5분 전 팀원은 끊김")
        assertEquals("집중", people[1].statusMessage)
        // 읽기만: 표는 GET, RPC 는 조회.
        val writes = h.storeRequests.filter { it.rpcName == null && it.method != "GET" }
        assertEquals(emptyList(), writes.map { "${it.method} ${it.path}" })
        assertEquals(1, store.refreshCount)
        h.assertClean()
    }

    /** W2-a 이월(NowTeamJoinTests.swift:148): 합류 전에 떠난 소속 조회의 늦은 `[]` 가 무소속 카드를 되살리지 않는다. */
    @Test
    fun lateNoTeamFromBeforeSettlingDoesNotRestoreNoTeamCard() = runTest {
        val gate = CompletableDeferred<Unit>()
        val after = CompletableDeferred<Unit>()
        var memberships = 0
        val (h, store) = make { r ->
            if (r.path == "/rest/v1/memberships") {
                memberships += 1
                // 로그인 복원의 소속 조회(1)는 무소속. 지금 탭의 첫 조회(2)는 늦게 무소속, 합류 뒤 조회(3~ — 프로필 · 다시 돌기)는 팀이되 멈춰 둔다.
                when (memberships) {
                    1 -> Reply.Json("[]")
                    2 -> Reply.Gate(gate, Reply.Json("[]"))
                    else -> Reply.Gate(after, Reply.Json(StoreHarness.MEMBERSHIP))
                }
            } else {
                teamRoutes(r)
            }
        }
        store.appDidBecomeActive()
        runCurrent()
        // 합류가 끝났다(TeamJoinStore.onTeamSettled — 가입 화면과 같은 문).
        store.teamJoin.onTeamSettled!!.invoke()
        assertTrue(store.isSettlingTeam)
        gate.complete(Unit)
        // advanceUntilIdle 이 아니다 — 가상 시간을 밀면 멈춰 둔 조회가 HTTP 시한(가상 시계)에 걸려 '늦은 응답'이 아니라 '실패'가 된다.
        runCurrent()
        // 늦은 '소속 없음'은 도착했고, 진짜 소속은 아직 오는 중 — 그 사이에 무소속 카드가 서면 안 된다(스피너).
        assertFalse(store.hasNoTeam, "합류 전에 떠난 조회의 '소속 없음'이 무소속 카드를 되살렸다")
        assertTrue(store.isSettlingTeam)
        assertEquals(NowLoadState.loading, store.teamLoadState)
        after.complete(Unit)
        advanceUntilIdle()
        assertFalse(store.hasNoTeam)
        assertEquals("team-1", store.membership?.teamID)
        assertFalse(store.isSettlingTeam)
        h.assertClean()
    }

    @Test
    fun goalSaveWinsOverMembershipFetchedBeforeIt() = runTest {
        val gate = CompletableDeferred<Unit>()
        var memberships = 0
        val (h, store) = make { r ->
            when {
                r.path == "/rest/v1/memberships" -> {
                    memberships += 1
                    if (memberships == 3) Reply.Gate(gate, Reply.Json(StoreHarness.MEMBERSHIP)) else Reply.Json(StoreHarness.MEMBERSHIP)
                }
                r.rpcName == "set_team_weekly_goal" -> Reply.Json("""[{"weekly_goal_hours":30}]""")
                else -> teamRoutes(r)
            }
        }
        store.appDidBecomeActive()
        advanceUntilIdle()
        store.refresh()
        runCurrent()
        assertTrue(store.saveGoal(30))
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(30, store.membership?.goalHours, "저장 전에 떠난 소속 조회가 옛 목표(40)로 되돌렸다")
        assertFalse(store.saveGoal(0), "범위 밖은 보내지 않는다")
        assertEquals(1, h.count("set_team_weekly_goal"))
        h.assertClean()
    }

    @Test
    fun offlineRefreshShowsFailureInsteadOfEndlessSpinner() = runTest {
        val (h, store) = make { r -> if (r.path == "/rest/v1/memberships" && r.query.isNotEmpty()) Reply.Offline else teamRoutes(r) }
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(NowLoadState.failed, store.teamLoadState)
        assertEquals("연결을 확인하고 다시 시도해 주세요", store.notice)
        assertNull(store.myCard(h.now()))
        h.assertClean()
    }
}
