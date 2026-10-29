// 원본: Tests/CheckMobileKitTests/BaseRealtimeRunnerTests.swift(drain ≠ take_pokes · 합치기 · 체스 빈 가지 · 테트리스 신호 · 수명) ·
//       GamesTetrisDuelWiringTests.swift:296(joiningTheSocketCatchesUpTheLobby — 조인 따라잡기) ·
//       Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift @ 3bd04bd
// G §2-3 W2-f ②: drain 은 메시지 조회이고 take_pokes 는 0 — 진짜 메시지 스토어(W2-b)를 조립(PhoneAppModel)째 붙여 **스텁이 받은 요청**으로 잰다.
package com.yehsung.aingcheck.feature.phone.realtime

import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.feature.phone.FakeTransport
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.testkit.mock.PhoneForbiddenCalls
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneRealtimeRunnerTest {
    /** 메시지 · 게임 조회 응답. 이력 함수 셋은 없는 서버로(조용히 빈 이력) — 이 시험이 재는 것은 **무엇을 불렀는가**다. */
    private fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
        "message_unread_summary" -> Reply.Json("""{"status":"ok","total":0,"peers":[]}""")
        "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
        "app_user_directory" -> Reply.Json("[]")
        "message_blocks", "my_blocked_users", "blocked_users" -> Reply.Json("[]")
        "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby" -> Reply.missingFunction
        else -> null
    }

    private fun TestScope.rig(): Pair<PhoneHarness, FakeTransport> {
        val transport = FakeTransport()
        val h = PhoneHarness(this, transport = transport) { route(it) }
        h.signIn()
        h.app.messages.appDidBecomeActive()
        h.app.realtime.coalesceSeconds = 1.0
        advanceUntilIdle()
        h.markRequests()
        return h to transport
    }

    /** 활성 + 로그인 → 소켓을 열고 조인까지(따라잡기 신호 한 번을 합치기 창 뒤에 갚는다). */
    private fun TestScope.connectAndJoin(h: PhoneHarness, transport: FakeTransport) {
        h.app.realtime.appDidBecomeActive()
        transport.emit(RealtimeTransportEvent.Opened)
        transport.emit(RealtimeTransportEvent.Joined)
        advanceUntilIdle()
    }

    private fun summaries(h: PhoneHarness) = h.count("message_unread_summary")

    @Test
    fun connectsPrivatePokeChannelWithCurrentTokenOnlyWhenActiveAndSignedIn() = runTest {
        val (h, transport) = rig()
        assertTrue(transport.calls.none { it == "connect" }, "앱이 앞에 오기 전에는 소켓을 열지 않는다")
        h.app.realtime.appDidBecomeActive()
        val args = transport.lastConnect!!
        assertEquals("https://golden.invalid", args[0])
        assertEquals("stub-anon-key", args[1])
        assertEquals(h.app.session.session!!.accessToken, args[2], "링이 실어 온 토큰이 아니라 지금 세션 토큰")
        assertEquals(RealtimeLinkConstants.pokeChannel(PhoneHarness.ME), args[3])
        assertEquals(true, args[4], "private=true 필수(빠뜨리면 RLS 없는 공개 채널)")
        transport.emit(RealtimeTransportEvent.Joined)
        assertTrue(h.app.realtime.state is RealtimeState.Subscribed)
        // background → 내려놓는다.
        h.app.realtime.appDidEnterBackground()
        assertEquals(RealtimeState.Idle(IdleReason.suspended), h.app.realtime.state)
        assertTrue(transport.calls.contains("disconnect"))
    }

    @Test
    fun catchUpAndDrainQueryMessagesAndNeverTakePokes() = runTest {
        val (h, transport) = rig()
        connectAndJoin(h, transport)
        assertEquals(1, summaries(h), "조인 따라잡기(.catchUp)는 메시지 요약 조회로 갚는다")
        // 새 메시지 신호(모르는 방송 → .drain) 셋이 1초 창 안에 온다 → 조회 한 번.
        repeat(3) { transport.emit(RealtimeTransportEvent.Broadcast("poke")) }
        assertEquals(1, summaries(h), "창이 끝나기 전에는 부르지 않는다")
        advanceTimeBy(1_001)
        runCurrent()
        advanceUntilIdle()
        assertEquals(2, summaries(h), ".drain 셋이 한 번으로 합쳐 조회된다")
        assertEquals(2, h.app.realtime.activityFlushCount)
        assertTrue(h.app.realtime.effectLog.count { it == RealtimeEffect.Drain } == 3)
        assertEquals(0, h.server.requests.count { it.rpcName == "take_pokes" }, ".drain 은 take_pokes 가 아니다(R3 · C§4 #15)")
        assertEquals(emptyList(), PhoneForbiddenCalls.violations(h.server.requests), "폰 금지 호출 0")
        h.assertClean()
    }

    @Test
    fun readSignalRefreshesThroughReadHandlers() = runTest {
        val (h, transport) = rig()
        connectAndJoin(h, transport)
        val before = summaries(h)
        transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.messageReadBroadcastEvent))
        advanceUntilIdle()
        assertEquals(1, h.app.realtime.readFlushCount)
        assertEquals(before + 1, summaries(h), "읽음 신호는 읽음 재조회(요약)로 갚는다")
    }

    @Test
    fun chessSignalIsDeliberatelyEmptyAndTetrisGomokuDoNotFallIntoDrain() = runTest {
        val (h, transport) = rig()
        connectAndJoin(h, transport)
        h.markRequests()
        val flushes = h.app.realtime.activityFlushCount
        transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.chessBroadcastEvent))
        advanceUntilIdle()
        assertEquals(emptyList(), h.rpcNames(), "체스 초인종은 일부러 빈 가지다 — 아무 조회도 내지 않는다")
        transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.tetrisBroadcastEvent))
        transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.gomokuBroadcastEvent))
        advanceUntilIdle()
        assertEquals(0, summaries(h), "테트리스·오목 초인종이 메시지 조회로 새지 않는다")
        assertEquals(flushes, h.app.realtime.activityFlushCount)
        assertTrue(h.rpcNames().any { it.startsWith("tetris_") }, "테트리스 초인종은 테트리스 스토어의 재조회로 간다")
        assertTrue(h.rpcNames().any { it.startsWith("gomoku_") }, "오목 초인종은 오목 스토어의 재조회로 간다")
    }

    @Test
    fun backgroundDropsCoalescedSignalsAndSignOutDisconnects() = runTest {
        val (h, transport) = rig()
        connectAndJoin(h, transport)
        val before = summaries(h)
        transport.emit(RealtimeTransportEvent.Broadcast("poke"))
        h.app.realtime.appDidEnterBackground()
        advanceTimeBy(5_000)
        advanceUntilIdle()
        assertEquals(before, summaries(h), "뒤로 가면 모아 둔 신호는 버린다(돌아올 때 따라잡기가 다시 읽는다)")
        h.app.realtime.appDidBecomeActive()
        transport.emit(RealtimeTransportEvent.Joined)
        advanceUntilIdle()
        assertEquals(before + 1, summaries(h), "다시 붙으면 따라잡기 한 번")
        h.app.session.signOut()
        advanceUntilIdle()
        assertEquals(RealtimeState.Idle(IdleReason.signedOut), h.app.realtime.state)
        val connects = transport.calls.count { it == "connect" }
        h.app.realtime.appDidBecomeActive()
        assertEquals(connects, transport.calls.count { it == "connect" }, "로그아웃이면 다시 열지 않는다")
    }

    /**
     * INV-MobileRealtimeRunner-b94b3ac4 · Swift GamesTetrisDuelWiringTests:296(joiningTheSocketCatchesUpTheLobby): 조인 따라잡기(`.catchUp`)는
     * 테트리스 로비와 오목 받은함을 **한 번씩** 긁는다 — 소켓이 내려가 있던 사이의 신청·수락·방해 줄은 재생되지 않는다. 기준선(다른 입력):
     * 러너의 두 칸을 뗀 조립은 같은 조인에 0건 — 위 1건이 러너 배선 때문임을 가른다.
     */
    @Test
    fun joiningCatchesUpTheTetrisLobbyAndGomokuInboxOnceEach() = runTest {
        fun TestScope.joinAndCount(detach: Boolean): Pair<Int, Int> {
            val (h, transport) = rig()
            if (detach) {
                h.app.realtime.tetris = null
                h.app.realtime.gomoku = null
            }
            h.app.realtime.appDidBecomeActive()
            transport.emit(RealtimeTransportEvent.Opened)
            advanceUntilIdle()
            h.markRequests()
            transport.emit(RealtimeTransportEvent.Joined)
            advanceUntilIdle()
            assertTrue(RealtimeEffect.CatchUp in h.app.realtime.effectLog, "조인이 따라잡기 effect 를 안 냈다")
            assertEquals(1, summaries(h), "메시지 따라잡기는 러너 칸과 무관하게 한 번")
            return h.count("tetris_lobby") to h.count("gomoku_inbox")
        }
        assertEquals(1 to 1, joinAndCount(detach = false), "조인 한 번에 (테트리스 로비, 오목 받은함)")
        assertEquals(0 to 0, joinAndCount(detach = true), "기준선이 안 갈린다 — 러너 칸과 무관하게 조회가 나가면 위 1건은 배선을 재지 않는다")
    }

    @Test
    fun tokenRefreshedElsewhereIsPushedToTheJoinedChannel() = runTest {
        val (h, transport) = rig()
        connectAndJoin(h, transport)
        h.app.realtime.accessTokenDidChange(h.jwt(PhoneHarness.ME, "rotated"))
        assertTrue(transport.calls.contains("pushAccessToken"), "붙어 있으면 재연결 없이 새 토큰을 민다")
        assertEquals(1, transport.calls.count { it == "connect" })
    }
}
