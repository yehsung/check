// 원본: Tests/CheckMobileKitTests/V1017RummyLandscapeTests.swift:15-155 @ ios-1017-cube 61d75d8c
//
// 판 화면만 가로(설계서 §10). 가장 나쁜 고장은 **잠금이 가로에 남아 앱 전체가 가로로 굳는 것**이다 — 빠져나가는 길마다 방향 값을 잰다.
// Activity 에 옮기는 자리는 androidApp RummyOrientationDriver · 기기 시험 RummyOrientationDeviceTest 가 잰다.
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation.landscape
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation.portrait
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyOrientationRule
import com.yehsung.aingcheck.core.stores.rummy.RummyAvailability
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.confirmBack
import com.yehsung.aingcheck.core.stores.rummy.dismissResult
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.stores.rummy.requestBack
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class GamesRummyOrientationTest {
    private companion object {
        const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
        const val OTHER = "7e7e0000-0000-4000-8000-0000000000f2"
        const val NOW_MS = 1_800_000_000_000L
        val WALL = SwiftDate(1_800_000_000.0)
    }

    private class Rig(val h: StoreHarness, val games: GamesStore, val rummy: RummyStore) {
        val value: GamesRummyInterfaceOrientation get() = games.rummyInterfaceOrientation
    }

    private fun state(status: String = "active", mine: String = if (status == "active") "playing" else "done", id: String = MATCH, seq: Long = 1): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$id","status":"$status","host_id":"${StoreFixtures.USER}","seq":$seq,"server_now_ms":$NOW_MS,""" +
            """"seats":[{"seat_no":0,"user_id":"${StoreFixtures.USER}","display_name":"나","state":"$mine"},{"seat_no":1,"user_id":"${StoreFixtures.PEER}","display_name":"비","state":"playing"}],"my_seat_no":0,""" +
            """"my_rack":${if (status == "active") """["A1","B2"]""" else "null"},"table":[],"turn_seat_no":1,"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 60_000},"grace_ms":2000}""",
    )

    private val lobbyText = """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}"""

    /** 로그인 → 화면이 뜸 → 판이 도는 판 화면까지 간 판. */
    private suspend fun TestScope.playing(): Rig {
        val config = AppConfig(duelsEnabled = true)
        val h = StoreHarness(this, config) { r ->
            when (r.rpcName) {
                "rummy_lobby" -> Reply.Json(lobbyText)
                "rummy_state" -> Reply.Offline
                "rummy_leave", "rummy_heartbeat" -> Reply.Json("""{"status":"ok"}""")
                else -> null
            }
        }
        h.signIn()
        val rummy = RummyStore(h.storeScope, TestRummyHost(h.sessionStore, config) { WALL }).also {
            it.clock = { WALL }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.deadlineWakeEnabled = false
            it.heartbeatEnabled = false
        }
        h.rummyStore = rummy
        val x = Rig(h, GamesStore(h.context), rummy)
        assertEquals(portrait, x.value, "로그인 직후가 세로가 아니다")
        x.games.rummyScreenDidAppear()
        runCurrent()
        assertEquals(portrait, x.value, "로비가 세로가 아니다")
        rummy.applyState(state())
        assertEquals(RummyPhase.playing, rummy.phase)
        assertEquals(landscape, x.value, "판 화면이 가로가 아니다")
        return x
    }

    @Test
    fun ruleTable() {
        val table = listOf(
            listOf(RummyPhase.lobby, false, false, false), listOf(RummyPhase.lobby, false, true, false), listOf(RummyPhase.lobby, true, false, false), listOf(RummyPhase.lobby, true, true, false),
            listOf(RummyPhase.room, false, false, false), listOf(RummyPhase.room, false, true, false), listOf(RummyPhase.room, true, false, false), listOf(RummyPhase.room, true, true, false),
            listOf(RummyPhase.playing, false, false, false), listOf(RummyPhase.playing, false, true, false), listOf(RummyPhase.playing, true, false, true), listOf(RummyPhase.playing, true, true, true),
            listOf(RummyPhase.finished, false, false, false), listOf(RummyPhase.finished, false, true, false), listOf(RummyPhase.finished, true, false, false), listOf(RummyPhase.finished, true, true, true),
        )
        for ((phase, visible, board, wanted) in table) {
            val label = "$phase $visible $board"
            assertEquals(wanted, GamesRummyOrientationRule.wants(phase as RummyPhase, visible as Boolean, board as Boolean), label)
            assertEquals(if (wanted == true) landscape else portrait, GamesRummyOrientationRule.orientation(phase, visible, board), label)
        }
    }

    /** 뒤로 · 탭 전환 · 딥링크 · 푸시 라우트는 모두 "화면이 사라졌다"(GamesRummyScreen 의 onDispose) 한 길이다. 돌아오면 가로 · 앱을 내렸다 올려도 가로 그대로. */
    @Test
    fun screenLifetime() = runTest {
        val x = playing()
        x.games.rummyScreenDidDisappear()
        assertEquals(portrait, x.value, "화면이 사라졌는데 가로에 남았다")
        assertEquals(RummyPhase.playing, x.rummy.phase, "기준선: 판은 아직 돈다 — 방향만 세로다")
        x.games.rummyScreenDidAppear()
        assertEquals(landscape, x.value, "돌아왔는데 가로가 아니다")
        x.games.appDidEnterBackground()
        assertEquals(landscape, x.value, "앱을 내리는 것은 화면을 떠나는 것이 아니다")
        x.games.appDidBecomeActive()
        runCurrent()
        assertEquals(landscape, x.value, "복귀했는데 판이 세로가 됐다")
        x.games.rummyScreenDidDisappear()
        assertEquals(portrait, x.value)
    }

    /** 끌려 들어옴: 다른 화면에 있던 사람에게 이 기기가 손댄 판이 시작되면 presentWindow → 화면이 뜬다. 뜨기 전에는 판이 있어도 세로다. */
    @Test
    fun pulledIntoAMatch() = runTest {
        val x = playing()
        x.games.rummyScreenDidDisappear()
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        x.rummy.applyState(state(seq = 2))
        assertEquals(portrait, x.value, "화면이 안 떴는데 먼저 돌았다")
        x.h.router.presented.clear()
        x.games.appDidBecomeActive()
        x.rummy.presentWindow!!.invoke()
        assertEquals(listOf<GamesDestination>(GamesDestination.Rummy), x.h.router.presented)
        x.games.rummyScreenDidAppear()
        assertEquals(landscape, x.value)
    }

    /** 놀던 기기: 다른 기기 판을 읽어도 화면이 안 뜨니 돌지 않는다. */
    @Test
    fun anIdleDeviceStaysPortrait() = runTest {
        val x = playing()
        x.games.rummyScreenDidDisappear()
        x.rummy.applyState(state(id = OTHER))
        x.h.router.presented.clear()
        x.games.appDidBecomeActive()
        x.rummy.presentWindow!!.invoke()
        assertEquals(emptyList(), x.h.router.presented, "놀던 기기가 판 화면으로 끌려갔다")
        assertEquals(portrait, x.value)
    }

    @Test
    fun resultAndFinalBoard() = runTest {
        val x = playing()
        x.rummy.applyState(state("finished"))
        assertEquals(RummyPhase.finished, x.rummy.phase)
        assertEquals(portrait, x.value, "결과가 가로에 남았다")
        x.games.setRummyFinalBoardShown(true)
        assertTrue(x.games.isRummyFinalBoardShown)
        assertEquals(landscape, x.value, "[최종 판]이 가로가 아니다")
        x.games.setRummyFinalBoardShown(false)
        assertEquals(portrait, x.value)
        x.games.setRummyFinalBoardShown(true)
        x.rummy.dismissResult()
        runCurrent()
        assertFalse(x.rummy.phase == RummyPhase.finished)
        assertEquals(portrait, x.value, "결과를 닫았는데 가로에 남았다")
        assertFalse(x.games.isRummyFinalBoardShown)

        // 다른 판이 끝나도 앞 판의 [최종 판] 표시가 살아나지 않는다.
        x.games.setRummyFinalBoardShown(true)
        assertFalse(x.games.isRummyFinalBoardShown, "결과가 아닌데 최종 판이다")
        x.rummy.applyState(state("finished", id = OTHER))
        assertEquals(RummyPhase.finished, x.rummy.phase)
        assertEquals(portrait, x.value, "다음 판 결과가 저절로 가로가 됐다")
    }

    @Test
    fun finalBoardClearedWithTheScreen() = runTest {
        val x = playing()
        x.rummy.applyState(state("finished"))
        x.games.setRummyFinalBoardShown(true)
        x.games.rummyScreenDidDisappear()
        assertEquals(portrait, x.value)
        assertFalse(x.games.isRummyFinalBoardShown)
    }

    /** 로그아웃 · 세션 만료(세션 사슬이 reset 을 부른다) · 코어 reset: 화면이 사라졌다는 소식 없이도 세로다. */
    @Test
    fun sessionEnd() = runTest {
        val store = playing()
        store.games.reset()
        assertEquals(portrait, store.value, "화면 깃발을 내렸는데 가로에 남았다")
        assertFalse(store.games.isRummyScreenVisible)

        val core = playing()
        core.rummy.reset()
        assertEquals(RummyPhase.lobby, core.rummy.phase)
        assertEquals(portrait, core.value, "코어가 비었는데 가로에 남았다")

        val board = playing()
        board.rummy.applyState(state("finished"))
        board.games.setRummyFinalBoardShown(true)
        board.games.reset()
        assertEquals(portrait, board.value)
        assertFalse(board.games.isRummyFinalBoardShown)
    }

    @Test
    fun unavailableIsPortrait() = runTest {
        val x = playing()
        x.rummy.availability = RummyAvailability.updateRequired
        assertEquals(portrait, x.value, "판을 안 그리는데 가로다")
        x.rummy.availability = RummyAvailability.available
        assertEquals(landscape, x.value)
    }

    /** 기권 확인: 묻는 동안은 가로 · 확인하면 판이 접혀 세로(화면 pop 전에도). 놀던 기기는 아무 요청 없이 닫힌다. */
    @Test
    fun forfeitConfirmAndIdleDevice() = runTest {
        val held = playing()
        held.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        assertEquals(RummyCloseDecision.confirmForfeit, held.rummy.requestBack())
        assertEquals(landscape, held.value, "묻는 동안 돌면 안 된다")
        assertEquals(null, held.rummy.confirmBack(RummyCloseDecision.confirmForfeit))
        runCurrent()
        assertEquals(1, held.h.server.count("rummy_leave"))
        assertEquals(portrait, held.value, "기권했는데 가로에 남았다")

        val idle = playing()
        assertEquals(RummyCloseDecision.close, idle.rummy.requestBack())
        idle.games.rummyScreenDidDisappear()
        runCurrent()
        assertEquals(portrait, idle.value)
        assertEquals(0, idle.h.server.count("rummy_leave"), "놀던 기기가 나가기를 보냈다")
    }

    /** 큐브 스토어가 없는 조립(desktopApp)은 언제나 세로다 — 방향을 건드릴 일이 없다. */
    @Test
    fun aContextWithoutRummyIsAlwaysPortrait() = runTest {
        val h = StoreHarness(this, AppConfig(duelsEnabled = true)) { null }
        h.signIn()
        val games = GamesStore(h.context)
        games.rummyScreenDidAppear()
        games.setRummyFinalBoardShown(true)
        assertEquals(portrait, games.rummyInterfaceOrientation)
        assertFalse(games.isRummyFinalBoardShown)
    }
}
