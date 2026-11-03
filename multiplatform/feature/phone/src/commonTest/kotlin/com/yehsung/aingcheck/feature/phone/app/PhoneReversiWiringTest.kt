// 원본: Sources/CheckMobileKit/App/MobileAppModel.swift(아잉 뒤집기 조립 — 91ea495d) · Tests/CheckMobileKitTests/GamesReversiWiringTests.swift(조립 몫) @ ios-1017-int
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.signOut
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.phone.FakeTransport
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * 폰 조립의 아잉 뒤집기 배선(판 7 — 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)") + **떼어 내기 깃발**(`AppConfig.reversiEnabled`).
 * 깃발을 끄면 리버시 입구·배너(받은 신청 · 탭 배지)·실시간 가지·미션 꼬리 숨김이 모두 사라지고, 다른 게임이 내는 요청이 판 7 이전과 같아야 한다 —
 * 같은 장면을 깃발 켬/끔으로 두 번 돌려 요청 열을 견준다(켬에서 `reversi_*` 만 뺀 열 == 끔의 열).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PhoneReversiWiringTest {
    private companion object {
        const val PEER = "bbbbbbbb-0000-4000-8000-000000000002"
        const val MATCH = "5e5e0000-0000-4000-8000-000000000071"
        const val NOW_MS = 1_789_621_500_000L
    }

    private fun lobbyText(incoming: Int = 0, active: String? = null): String =
        """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"turn_seconds":30,"invite_ttl_seconds":60,""" +
            """"me":{"ruby_balance":10,"wins":0,"losses":0,"draws":0,"active_match_id":${active?.let { "\"$it\"" } ?: "null"},""" +
            """"incoming":[${(0 until incoming).joinToString(",") { """{"match_id":"5e5e0000-0000-4000-8000-00000000009$it","from":{"id":"$PEER","display_name":"비"},"stake":5,"expires_at_ms":${NOW_MS + 600_000}}""" }}],""" +
            """"outgoing":null},"users":[{"id":"$PEER","display_name":"비","capable":true,"is_working":true}],"matches":[]}"""

    private var lobbyIncoming = 0

    private fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
        "reversi_lobby" -> Reply.Json(lobbyText(lobbyIncoming))
        "reversi_ranking" -> Reply.Json("""{"status":"ok","server_now_ms":$NOW_MS,"rows":[],"me":null}""")
        "reversi_state" -> Reply.Offline
        "message_unread_summary" -> Reply.Json("""{"status":"ok","total":0,"peers":[]}""")
        "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
        "app_user_directory", "message_blocks", "my_blocked_users", "blocked_users" -> Reply.Json("[]")
        "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby", "rummy_lobby" -> Reply.missingFunction
        "work_phone_touch" -> Reply.Json("""{"status":"not_working"}""")
        "block_user" -> Reply.Json("""{"status":"ok"}""")
        else -> null
    }

    private fun TestScope.rig(reversiEnabled: Boolean = true, duels: Boolean = true, transport: FakeTransport? = null): PhoneHarness {
        val h = PhoneHarness(this, transport = transport, appConfig = AppConfig(duelsEnabled = duels, reversiEnabled = reversiEnabled)) { route(it) }
        h.signIn()
        // 하트비트 고리는 끝이 없다 — 재운다(큐브 시험과 같은 꼴). 이 시험은 가상 시간을 **정한 만큼만** 민다(advanceUntilIdle 은 받은 신청의 만료까지
        // 시간을 밀어 신청을 걷어 버리고, 앱 활성 장면의 주기 일과 함께 끝나지 않을 수 있다).
        h.app.rummy.heartbeatEnabled = false
        return h
    }

    /** 배선 값: 주 스위치 둘 · 실시간 칸 · 게임 탭 문맥 · 같은 호스트(루비 칸 하나) · 미션 꼬리 · 나 탭 미션 줄. 빠지면 순위·관전이 한 번도 안 나가거나 초인종이 nil 에 말을 건다. */
    @Test
    fun assemblyWiresTheStoreEverywhere() = runTest {
        val h = PhoneHarness(this) { route(it) }
        val app = h.app
        assertTrue(AppConfig().reversiEnabled, "떼어 내기 깃발의 기본은 켜짐이다")
        val reversi = assertNotNull(app.reversi)
        assertTrue(reversi.rankingEnabled, "순위 주 스위치")
        assertTrue(reversi.spectatorFeaturesEnabled, "관전 주 스위치")
        assertNotNull(app.realtime.reversi)
        assertSame(reversi, app.context.reversi)
        assertSame(reversi, app.gamesContext.reversi)
        assertSame(reversi, app.games.reversi)
        assertSame(app.gomokuHost, reversi.host, "호스트는 오목과 같은 하나(같은 루비 칸)")
        assertNotNull(reversi.onMatchFinished, "판 끝 일일 미션 고리")
        assertNotNull(reversi.presentWindow, "판 시작 문(게임 탭이 단다)")
        assertTrue(app.me.context.meLinks.reversiPlayable)
        assertEquals("", MeText.dailyMissionCaption("reversi", "맥에서 할 수 있어요", app.me.context.meLinks.reversiPlayable))
    }

    /** 깃발 끔: 스토어를 만들지 않는다 — 실시간 칸 · 게임 탭 문맥 · 나 탭 미션 꼬리가 모두 '리버시 없음'이다. */
    @Test
    fun removalFlagOffBuildsNoReversi() = runTest {
        val h = rig(reversiEnabled = false)
        val app = h.app
        assertNull(app.reversi)
        assertNull(app.realtime.reversi)
        assertNull(app.context.reversi)
        assertNull(app.gamesContext.reversi)
        assertNull(app.games.reversi)
        assertFalse(app.me.context.meLinks.reversiPlayable)
        assertEquals("맥에서 할 수 있어요", MeText.dailyMissionCaption("reversi", "맥에서 할 수 있어요", app.me.context.meLinks.reversiPlayable), "리버시가 없는 폰에서 '맥에서'는 참이다")
        assertFalse(app.games.hasLiveReversiMatch)
        assertNull(app.games.reversiEntryBlock)
    }

    /** 같은 장면(게임 탭 활성 · 허브 · 소켓 조인 · 'reversi' 초인종)을 깃발 켬/끔으로 돌린다. 끔은 리버시 요청 0 이고 나머지 요청은 켬과 같다(판 7 이전과 같다). */
    @Test
    fun removalFlagOffKeepsOtherGamesRequestsAsBefore() = runTest {
        fun scenario(enabled: Boolean): Pair<List<String>, Int> {
            val transport = FakeTransport()
            val h = rig(reversiEnabled = enabled, transport = transport)
            // 게임 탭의 활성 · 허브 계기. 앱 장면 전체 활성(`sceneDidBecomeActive`)은 쓰지 않는다 — 할 일 주기 동기화가 가상 시간을 끝없이 잡아, 같은 시험
            // 스케줄러를 쓰는 둘째 조립의 로그인(`signIn` 의 advanceUntilIdle)이 돌아오지 않는다(측정: 둘째 조립에서 멈춤 — 깃발과 무관).
            h.app.games.appDidBecomeActive()
            h.app.games.hubDidAppear()
            h.app.realtime.appDidBecomeActive()
            transport.emit(RealtimeTransportEvent.Opened)
            transport.emit(RealtimeTransportEvent.Joined)
            advanceTimeBy(3_000)
            runCurrent()
            val flushes = h.app.realtime.activityFlushCount
            transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.reversiBroadcastEvent))
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(flushes, h.app.realtime.activityFlushCount, "'reversi' 초인종이 메시지 조회로 샜다 enabled=$enabled")
            return h.rpcNames() to h.app.badges.games
        }
        val (on, badgeOn) = scenario(enabled = true)
        val (off, badgeOff) = scenario(enabled = false)
        assertTrue(on.count { it == "reversi_lobby" } >= 3, "켬: 게임 탭 활성 · 조인 따라잡기 · 초인종이 로비를 읽는다 — $on")
        assertTrue(off.none { it.startsWith("reversi_") }, "끔인데 리버시 요청이 나갔다: $off")
        assertEquals(on.filterNot { it.startsWith("reversi_") }.sorted(), off.sorted(), "깃발을 끈 조립의 다른 게임 요청이 켠 조립과 다르다")
        assertEquals(badgeOn, badgeOff, "받은 신청이 없으면 배지는 같다")
    }

    /** 받은 신청이 탭 배지에 선다(켬) · 끔은 같은 서버 응답이 와도 배지가 판 7 이전 값이다(리버시 스토어가 없다). */
    @Test
    fun incomingReversiInviteRaisesBadgeOnlyWhenEnabled() = runTest {
        lobbyIncoming = 2
        val on = rig()
        on.app.games.hubDidAppear()
        advanceTimeBy(3_000)
        runCurrent()
        assertEquals(2, on.app.reversi!!.visibleIncomingInvites.size)
        assertEquals(2, on.app.badges.games)
        val off = rig(reversiEnabled = false)
        off.app.games.hubDidAppear()
        advanceTimeBy(3_000)
        runCurrent()
        assertEquals(0, off.app.badges.games)
        // 판돈 깃발이 꺼진 빌드(§8-17 #1)는 리버시가 있어도 수락할 수 없는 신청을 안 센다.
        val locked = rig(duels = false)
        locked.app.games.hubDidAppear()
        advanceTimeBy(3_000)
        runCurrent()
        assertEquals(2, locked.app.reversi!!.incoming.size, "서버 사실은 든다")
        assertEquals(0, locked.app.badges.games)
    }

    /** 차단: 메시지 탭이 차단한 사람의 신청은 로비·배지에서 걷힌다(조립이 차단 변화를 리버시 거울에 넣는다). */
    @Test
    fun blockingHidesReversiInvites() = runTest {
        lobbyIncoming = 1
        val h = rig()
        h.app.games.hubDidAppear()
        advanceTimeBy(3_000)
        runCurrent()
        assertEquals(1, h.app.badges.games)
        h.app.messages.blockPeer(PEER)
        advanceTimeBy(3_000)
        runCurrent()
        assertEquals(setOf(PEER), h.app.reversi!!.hiddenPeerIDs)
        assertEquals(0, h.app.badges.games)
        assertTrue(h.app.games.reversiLobbyUsers.none { it.id == PEER })
    }

    /** 로그아웃: 리버시 스토어를 비운다 — 안 비우면 다음 사람이 앞 계정의 판·신청·루비를 본다. 배선 값(주 스위치)은 남는다. */
    @Test
    fun signOutResetsReversi() = runTest {
        val h = rig()
        val app = h.app
        val reversi = app.reversi!!
        reversi.applyLobby(SwiftJson.decode(ReversiLobbyResponse.serializer(), lobbyText(incoming = 1)))
        reversi.applyState(
            SwiftJson.decode(
                ReversiStatePayload.serializer(),
                """{"match":{"id":"$MATCH","status":"active","stake":5,"black":"${PhoneHarness.ME}","white":"$PEER","move_count":0,"turn":"black",""" +
                    """"board":"...........................wb......bw...........................","deadline_ms":${NOW_MS + 30_000}},""" +
                    """"moves":[],"my_color":"black","legal_moves":[19],"opponent":{"user_id":"$PEER","display_name":"비"},"server_now_ms":$NOW_MS}""",
            ),
        )
        assertNotNull(reversi.match)
        val job = launch { app.me.signOut() }
        advanceTimeBy(3_000)
        runCurrent()
        job.join()
        assertFalse(app.session.isSignedIn)
        assertNull(reversi.match, "다음 사람이 앞 계정의 판을 본다")
        assertTrue(reversi.incoming.isEmpty())
        assertNull(reversi.rubyBalance)
        assertEquals(1, reversi.resetGeneration, "로그아웃 사슬이 리버시를 안 비웠다")
        assertTrue(reversi.rankingEnabled && reversi.spectatorFeaturesEnabled, "배선 값까지 지웠다")
    }
}
