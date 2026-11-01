// 원본: Sources/CheckMobileKit/Games/GamesRummyScreen.swift · GamesRummyRoom.swift · GamesRummyLobby.swift @ ios-1017-cube dba0c647 — 방을 떠나는 문의 화면 몫(확인 · 안내 줄 · 뒤로 경쟁). 판단은 feature/phone PhoneRummyTabExitTest.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyCard
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.minigame.UiFixtures
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val ROOM = "7e7e0000-0000-4000-8000-000000000069"
private const val PEER = "7e7e0000-0000-4000-8000-0000000000b2"
private const val NOW_MS = 1_800_000_000_000L
private val FACE = RummySeatFace("나", null, null)
private val T0 = SwiftDate(1_800_000_000.0)

@OptIn(ExperimentalTestApi::class)
class GamesRummyTabExitScreenTest {
    private class Rig(val scope: TestScope, val h: UiGamesHarness, val rummy: RummyStore, val games: GamesStore, val replies: MutableMap<String, Pair<String, Int>>) {
        fun count(rpc: String): Int = h.server.requests.count { it.rpcName == rpc }
        fun settle() = scope.testScheduler.advanceUntilIdle()
        fun tapAnotherTab(onMoved: () -> Unit = {}): Boolean {
            val guard = assertNotNull(h.departureGuard, "스토어가 문을 안 달았다")
            return guard(onMoved)
        }
    }

    private fun roomText(hostIsMe: Boolean, status: String = "forming"): String =
        """{"id":"$ROOM","status":"$status","host_id":"${if (hostIsMe) UiFixtures.USER else PEER}","stake":3,"seq":1,"server_now_ms":$NOW_MS,"my_seat_no":0,"table":[],""" +
            """"seats":[{"seat_no":0,"user_id":"${UiFixtures.USER}","display_name":"나","state":"joined"},{"seat_no":1,"user_id":"$PEER","display_name":"비","state":"joined"}]}"""

    private fun rig(hostIsMe: Boolean): Rig {
        val scope = TestScope()
        val config = AppConfig(duelsEnabled = true)
        val replies = mutableMapOf(
            "rummy_lobby" to ("""{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}""" to 200),
            "rummy_state" to ("""{"status":"ok","server_now_ms":$NOW_MS,"state":${roomText(hostIsMe)}}""" to 200),
            "rummy_leave" to ("""{"status":"ok"}""" to 200),
        )
        val h = UiGamesHarness(scope, config) { r -> r.rpcName?.let { replies[it] } }
        runBlocking { h.signIn() }
        val rummy = RummyStore(h.storeScope, UiRummyHost(h.sessionStore, config) { T0 }).also {
            it.clock = { T0 }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
        }
        h.rummy = rummy
        val games = GamesStore(h.context)
        games.rummyLeaveRetrySeconds = emptyList()
        rummy.markEngaged(SwiftUUID.parse(ROOM)!!)
        rummy.applyState(SwiftJson.decode(RummyMatchState.serializer(), roomText(hostIsMe)))
        return Rig(scope, h, rummy, games, replies)
    }

    private fun ComposeUiTest.screen(x: Rig, onLeave: () -> Unit = {}) {
        setContent {
            AingTheme(dark = false) { GamesRummyScreen(x.games, UiFixtures.USER, FACE, Modifier.fillMaxSize(), onLeave = onLeave) }
        }
        waitForIdle()
        x.settle()
        waitForIdle()
    }

    /** 방장 탭 이탈: '방이 닫혀요'가 뜨고 [계속하기]는 0건 · [방 닫고 나가기]는 나간 뒤 가려던 곳으로. */
    @Test
    fun hostTabAsksWithTheCloseRoomDialog() = runComposeUiTest {
        val x = rig(hostIsMe = true)
        screen(x)
        var moved = 0
        assertFalse(x.tapAnotherTab { moved += 1 }, "방장인데 탭을 막지 않았다")
        waitForIdle()
        val copy = assertNotNull(RummyPhoneText.exit(RummyCloseDecision.confirmCloseRoom))
        onNodeWithText(copy.detail).assertExists()
        onNodeWithTag(GamesRummyTags.EXIT_KEEP).performClick()
        waitForIdle()
        onNodeWithText(copy.detail).assertDoesNotExist()
        assertNull(x.games.rummyDeparturePrompt)
        x.settle()
        assertEquals(0, x.count("rummy_leave"))
        assertEquals(0, moved)

        assertFalse(x.tapAnotherTab { moved += 1 })
        waitForIdle()
        onNodeWithTag(GamesRummyTags.EXIT_CONFIRM).performClick()
        waitForIdle()
        x.settle()
        assertEquals(1, x.count("rummy_leave"))
        assertEquals(1, moved, "수락했는데 가려던 곳으로 안 갔다")
        assertEquals(RummyPhase.lobby, x.rummy.phase)
        x.h.close()
    }

    /** 방 안내 줄이 [나가기] 아래에 선다 · 놀던 기기는 없다. */
    @Test
    fun roomHintSpeaksTheTabRule() = runComposeUiTest {
        val guest = rig(hostIsMe = false)
        screen(guest)
        onNodeWithText(RummyPhoneText.tabExitHintGuest).assertExists()
        guest.h.close()
    }

    @Test
    fun hostRoomHintSpeaksTheAsking() = runComposeUiTest {
        val host = rig(hostIsMe = true)
        screen(host)
        onNodeWithText(RummyPhoneText.tabExitHintHost).assertExists()
        host.h.close()
    }

    /** 손님: 돌아오면 로비 안내 한 줄(코어 notice 가 아니다 — 방 · 판 화면으로 안 따라간다). */
    @Test
    fun lobbySpeaksTheLeftLineOnce() = runComposeUiTest {
        val x = rig(hostIsMe = false)
        screen(x)
        assertTrue(x.tapAnotherTab())
        x.settle()
        waitForIdle()
        assertEquals(RummyPhase.lobby, x.rummy.phase)
        assertNull(x.rummy.notice)
        onNodeWithText(RummyPhoneText.tabLeftNotice).assertExists()
        x.h.close()
    }

    /** 실패: 돌아온 방에 안내 줄이 서고, 게임 탭 카드도 사실을 말한다 · 판이 되면 그 말이 사라진다. */
    @Test
    fun unconfirmedLineStandsInTheRoomOnly() = runComposeUiTest {
        val x = rig(hostIsMe = false)
        x.replies["rummy_leave"] = """{"message":"down"}""" to 500
        screen(x)
        assertTrue(x.tapAnotherTab())
        x.settle()
        waitForIdle()
        assertEquals(RummyPhase.room, x.rummy.phase)
        onNodeWithText(RummyPhoneText.leaveUnconfirmedNotice).assertExists()
        assertEquals(RummyPhoneText.leaveUnconfirmedDetail, GamesRummyCard.detail(x.games))
        x.h.close()
    }

    /** 뒤로 경쟁: 탭 이탈이 나가는 중이면 [나가기] · 뒤로를 받지 않는다 — 나가기는 1건. */
    @Test
    fun backDuringDepartureIsIgnored() = runComposeUiTest {
        val x = rig(hostIsMe = false)
        var left = 0
        screen(x) { left += 1 }
        assertTrue(x.tapAnotherTab())
        assertTrue(x.games.isRummyDepartureRunning, "전제: 나가는 중")
        waitForIdle()
        onNodeWithTag(GamesRummyRoomTags.LEAVE).performClick()
        waitForIdle()
        assertEquals(0, left, "나가는 중인데 뒤로가 또 나갔다")
        x.settle()
        assertEquals(1, x.count("rummy_leave"))
        x.h.close()
    }

    /** 손님 [나가기] · 뒤로: 곧바로 화면을 내리고 1건. */
    @Test
    fun guestBackGoesAtOnceAndLeavesOnce() = runComposeUiTest {
        val x = rig(hostIsMe = false)
        var left = 0
        screen(x) { left += 1 }
        val reads = x.count("rummy_state")
        onNodeWithTag(GamesRummyRoomTags.LEAVE).performClick()
        waitForIdle()
        assertEquals(1, left)
        x.settle()
        assertTrue(x.count("rummy_state") > reads, "먼저 읽지 않았다 — 그새 시작된 판을 기권시킬 수 있다")
        assertEquals(1, x.count("rummy_leave"))
        assertEquals(RummyPhase.lobby, x.rummy.phase)
        assertNull(x.games.rummyLeftByTabNotice, "스스로 누른 나가기에 탭 얘기를 했다")
        x.h.close()
    }

    /** 방장 [방 닫고 나가기]: 못 닿으면 화면을 안 내리고 방에 남아 말한다 · 닿으면 그제야 내린다. */
    @Test
    fun hostBackStaysUntilTheRoomCloses() = runComposeUiTest {
        val x = rig(hostIsMe = true)
        x.replies["rummy_leave"] = """{"message":"down"}""" to 500
        var left = 0
        screen(x) { left += 1 }
        onNodeWithTag(GamesRummyRoomTags.LEAVE).performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyTags.EXIT_CONFIRM).performClick()
        waitForIdle()
        x.settle()
        waitForIdle()
        assertEquals(0, left, "방이 안 닫혔는데 화면을 내렸다")
        assertEquals(RummyPhase.room, x.rummy.phase)
        onNodeWithText(RummyPhoneText.leaveUnconfirmedNotice).assertExists()

        x.replies["rummy_leave"] = """{"status":"ok"}""" to 200
        onNodeWithTag(GamesRummyRoomTags.LEAVE).performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyTags.EXIT_CONFIRM).performClick()
        waitForIdle()
        x.settle()
        waitForIdle()
        assertEquals(1, left)
        assertEquals(RummyPhase.lobby, x.rummy.phase)
        x.h.close()
    }
}
