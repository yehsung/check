// 원본: Tests/checkTests/V0369RummyWiringTests.swift(맥 배선 계약의 폰 몫 — 소스 글자가 아니라 요청과 값으로 잰다) · Sources/check/RummyExitFlow.swift(signOutLeavingRummy) @ 1a5eeca6
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.me.deleteAccount
import com.yehsung.aingcheck.core.stores.me.signOut
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyLobby
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.phone.FakeTransport
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
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
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneRummyWiringTest {
    private companion object {
        const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
        const val ROOM = "7e7e0000-0000-4000-8000-000000000069"
        const val PEER = "bbbbbbbb-0000-4000-8000-000000000002"
        const val NOW_MS = 1_789_621_500_000L
    }

    private fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
        "rummy_lobby" -> Reply.Json(lobbyText())
        "rummy_leave", "rummy_heartbeat" -> Reply.Json("""{"status":"ok"}""")
        "rummy_state" -> Reply.Offline
        "block_user" -> Reply.Json("""{"status":"ok"}""")
        "message_unread_summary" -> Reply.Json("""{"status":"ok","total":0,"peers":[]}""")
        "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
        "app_user_directory", "message_blocks", "my_blocked_users", "blocked_users" -> Reply.Json("[]")
        // 판 7: 아잉 뒤집기도 조인 따라잡기에서 로비를 한 번 읽는다(떼어 내기 깃발 기본 켜짐) — 다른 게임 로비와 같은 대접.
        "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby", "reversi_lobby", "crossy_duel_lobby" -> Reply.missingFunction
        "work_phone_touch" -> Reply.Json("""{"status":"not_working"}""")
        "delete_my_account" -> Reply.Json("null")
        else -> null
    }

    private fun lobbyText(invites: Int = 0): String =
        """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[${if (invites > 0) inviteText() else ""}],"public_rooms":[],""" +
            """"users":[{"id":"$PEER","display_name":"비","capable":true}]}"""

    private fun inviteText(): String =
        """{"id":"$ROOM","host":{"id":"$PEER","display_name":"비"},"stake":5,"expires_at_ms":${NOW_MS + 600_000},"seats":[{"user_id":"$PEER","state":"joined","seat_no":0}]}"""

    private fun active(status: String = "active", mine: String = "playing"): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"$status","host_id":"${PhoneHarness.ME}","seq":1,"server_now_ms":$NOW_MS,""" +
            """"seats":[{"seat_no":0,"user_id":"${PhoneHarness.ME}","state":"$mine"},{"seat_no":1,"user_id":"$PEER","state":"playing"}],"my_seat_no":0,""" +
            """"my_rack":["A1","B2"],"table":[],"turn_seat_no":1,"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 60_000},"grace_ms":2000}""",
    )

    private fun TestScope.rig(enabled: Boolean = true, transport: FakeTransport? = null): PhoneHarness {
        val h = PhoneHarness(this, transport = transport, appConfig = AppConfig(duelsEnabled = enabled)) { route(it) }
        h.signIn()
        // 하트비트 고리는 끝이 없다 — advanceUntilIdle 이 돌아오게 재운다(주기는 코어 시험이 잰다).
        h.app.rummy.heartbeatEnabled = false
        return h
    }

    private fun RummyStore.holdEngagedMatch() {
        markEngaged(SwiftUUID.parse(MATCH)!!)
        applyState(active())
    }

    /** 배선 값: 저장소 둘 · 순위 스위치 · 실시간 칸 · 게임 탭 문맥이 조립의 그 스토어다. 빠지면 재실행한 폰이 쥐던 판의 하트비트를 잃는다(90초 끊김 기권). */
    @Test
    fun assemblyWiresTheStoreEverywhere() = runTest {
        val h = PhoneHarness(this) { route(it) }
        val app = h.app
        assertSame(h.prefs, app.rummy.rackDefaults, "받침대 자리를 앱 저장소에 안 둔다")
        assertSame(h.prefs, app.rummy.engagedDefaults, "손댄 판 장부를 앱 저장소에 안 둔다")
        assertTrue(app.rummy.rankingEnabled)
        assertNotNull(app.realtime.rummy)
        assertSame(app.rummy, app.context.rummy)
        assertSame(app.rummy, app.gamesContext.rummy)
        assertNotNull(app.rummy.onMatchFinished, "판 끝 일일 미션 고리")
        // 호스트는 오목과 같은 하나 — 같은 루비 칸.
        assertSame(app.gomokuHost, app.rummy.host)
    }

    /** 초인종: 켠 빌드는 큐브 재조회로 가고 메시지 조회로 새지 않는다. 잠긴 빌드는 아무것도 안 낸다. 조인 따라잡기도 같다. */
    @Test
    fun realtimeSignalReachesTheStoreOnlyInEnabledBuilds() = runTest {
        for (enabled in listOf(false, true)) {
            val transport = FakeTransport()
            val h = rig(enabled, transport)
            h.app.realtime.appDidBecomeActive()
            transport.emit(RealtimeTransportEvent.Opened)
            transport.emit(RealtimeTransportEvent.Joined)
            advanceUntilIdle()
            assertEquals(if (enabled) 1 else 0, h.count("rummy_lobby"), "조인 따라잡기 enabled=$enabled")
            h.markRequests()
            val flushes = h.app.realtime.activityFlushCount
            transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.rummyBroadcastEvent))
            advanceUntilIdle()
            assertEquals(if (enabled) listOf("rummy_lobby") else emptyList(), h.rpcNames(), "초인종 enabled=$enabled")
            assertEquals(flushes, h.app.realtime.activityFlushCount, "큐브 초인종이 메시지 조회로 샜다 — 끌기마다 조회가 나간다")
            h.assertClean()
        }
    }

    /** 확성기 미룸: 손댄 판에서 내 자리 playing 이면 미룬다(화면이 안 떠 있어도). 놀던 기기 · 기권 뒤 구경은 안 미룬다 · 큐브 화면은 판 없이도 미룬다. */
    @Test
    fun megaphoneDefersDuringAnEngagedMatch() = runTest {
        val h = rig()
        val app = h.app
        assertFalse(app.isMegaphoneBannerDeferred)
        app.rummy.applyState(active())
        assertFalse(app.isMegaphoneBannerDeferred, "놀던 기기가 배너를 미뤘다")
        app.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        assertTrue(app.isMegaphoneBannerDeferred)
    }

    /** 게임 탭 배지 = 받은 오목 신청 + 받은 큐브 초대(앱 아이콘에도 더한다). 잠긴 빌드는 안 센다. */
    @Test
    fun rummyInvitesFeedTheGamesBadge() = runTest {
        val lobby = SwiftJson.decode(RummyLobby.serializer(), lobbyText(invites = 1))
        val open = rig()
        open.app.rummy.applyLobby(lobby)
        assertEquals(1, open.app.badges.games)
        assertEquals(1, open.app.badges.appBadgeTotal)
        val locked = rig(enabled = false)
        locked.app.rummy.applyLobby(lobby)
        assertEquals(1, locked.app.rummy.lobby?.invites?.size, "전제: 초대는 살아 있다")
        assertEquals(0, locked.app.badges.games, "깃발이 꺼진 빌드의 게임 탭 배지가 받은 초대를 셌다")
    }

    /** 차단 거울: 메시지 탭에서 차단하면 큐브 로비·받은 초대에서 그 사람이 사라진다(맥 `rummy.setHiddenPeers`). */
    @Test
    fun blockingInMessagesHidesThePeerInRummy() = runTest {
        val h = rig()
        val app = h.app
        app.rummy.applyLobby(SwiftJson.decode(RummyLobby.serializer(), lobbyText(invites = 1)))
        assertEquals(1, app.rummy.lobby?.users?.size)
        app.messages.blockPeer(PEER)
        advanceUntilIdle()
        assertEquals(setOf(SwiftUUID.parse(PEER)!!), app.rummy.hiddenPeerIDs)
        assertEquals(0, app.rummy.lobby?.users?.size)
        assertEquals(0, app.rummy.lobby?.invites?.size)
        assertEquals(0, app.badges.games, "차단한 사람의 초대를 세었다")
    }

    /** 로그아웃: 쥔 판에서 **먼저** 나가고(`rummy_leave`) 그 뒤 세션을 내린다 — 거꾸로면 이탈 요청이 토큰 없이 떠나 판이 '플레이 중'으로 남는다. 그리고 스토어를 비운다. */
    @Test
    fun signOutLeavesTheHeldMatchFirstThenResets() = runTest {
        val h = rig()
        val app = h.app
        app.rummy.holdEngagedMatch()
        val job = launch { app.me.signOut() }
        advanceUntilIdle()
        job.join()
        val names = h.appRequests.map { it.rpcName ?: it.path }
        val leave = names.indexOf("rummy_leave")
        val logout = names.indexOf("/auth/v1/logout")
        assertTrue(leave >= 0, "이탈을 안 보냈다: $names")
        assertTrue(logout < 0 || leave < logout, "세션을 먼저 내렸다: $names")
        assertFalse(app.session.isSignedIn)
        assertNull(app.rummy.match, "다음 사람이 앞 계정의 판을 본다")
        assertNull(app.rummy.editor)
        assertEquals(1, app.rummy.resetGeneration, "로그아웃 사슬이 큐브를 안 비웠다")
    }

    /**
     * 계정 삭제 앞에는 나가지 않는다 — 서버 `delete_my_account` 가 같은 트랜잭션에서 기권 · 방 정리를 한다. `rummy_leave` 를 먼저 보내면 삭제가 실패해도 기권이 안 되돌아간다.
     * 기준선: 같은 판의 로그아웃은 위 시험에서 나간다.
     */
    @Test
    fun accountDeletionSendsNoLeave() = runTest {
        val h = rig()
        val app = h.app
        h.tokenReply = Reply.Json("""{"access_token":"${h.jwt(PhoneHarness.ME, "reauth")}","refresh_token":"r1","user":{"id":"${PhoneHarness.ME}"}}""")
        app.rummy.holdEngagedMatch()
        app.me.accountDeletionPassword = "pw"
        val job = launch { app.me.deleteAccount() }
        advanceUntilIdle()
        job.join()
        assertTrue(h.appRequests.any { it.rpcName == "delete_my_account" }, "기준선: 삭제까지 안 갔다: ${h.appRequests.map { it.rpcName ?: it.path }}")
        assertEquals(0, h.count("rummy_leave"), "계정 삭제 앞에 판을 나갔다")
    }

    /** 일일 미션 큐브 줄의 '맥에서' 글자를 지우는 깃발이 폰 조립에서 켜진다 — 없으면: 큐브가 있는 폰에 '맥에서 할 수 있어요'가 뜬다. */
    @Test
    fun rummyIsPlayableOnThePhone() = runTest {
        assertTrue(rig().app.me.context.meLinks.rummyPlayable)
    }

    /** 놀던 기기의 로그아웃은 아무것도 안 보낸다 — 다른 기기의 판이 기권되지 않게. */
    @Test
    fun signOutOnIdleDeviceSendsNoLeave() = runTest {
        val h = rig()
        val app = h.app
        app.rummy.applyState(active())
        val job = launch { app.me.signOut() }
        advanceUntilIdle()
        job.join()
        assertEquals(0, h.count("rummy_leave"), "놀던 기기의 로그아웃이 다른 기기의 판을 기권시켰다")
        assertFalse(app.session.isSignedIn)
    }

    /** 잠긴 빌드(기본)는 앱 활성화·허브에서 큐브 조회를 한 건도 내지 않는다 — 기존 요청 열이 그대로다. */
    @Test
    fun lockedBuildAddsNoRequestsOnActivation() = runTest {
        val h = rig(enabled = false)
        h.markRequests()
        h.app.sceneDidBecomeActive()
        h.app.games.hubDidAppear()
        // active 동안은 할 일 주기 동기화가 돌아 가상 시간이 끝나지 않는다 — 조금만 민다.
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(0, h.rpcNames().count { it.startsWith("rummy_") })
    }
}
