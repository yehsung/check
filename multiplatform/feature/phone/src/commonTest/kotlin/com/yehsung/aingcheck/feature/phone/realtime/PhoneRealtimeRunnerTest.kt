// 원본: Tests/CheckMobileKitTests/BaseRealtimeRunnerTests.swift(drain ≠ take_pokes · 앞쪽 즉시 + 뒤쪽 합치기 ①~⑤ @ c220021e · 체스 빈 가지 · 테트리스 신호 · 수명) ·
//       GamesTetrisDuelWiringTests.swift:296(joiningTheSocketCatchesUpTheLobby — 조인 따라잡기) ·
//       Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift @ 3bd04bd
// G §2-3 W2-f ②: drain 은 메시지 조회이고 take_pokes 는 0 — 진짜 메시지 스토어(W2-b)를 조립(PhoneAppModel)째 붙여 **스텁이 받은 요청**으로 잰다.
package com.yehsung.aingcheck.feature.phone.realtime

import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
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
        // 판 7: 아잉 뒤집기도 조인 따라잡기에서 로비를 한 번 읽는다 — 다른 게임 로비와 같은 대접.
        "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby", "rummy_lobby", "reversi_lobby", "crossy_duel_lobby" -> Reply.missingFunction
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

    /** 활성 + 로그인 → 소켓을 열고 조인까지(따라잡기 신호는 조용하던 창의 첫 신호라 곧바로 갚는다). */
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
        // 새 메시지 신호(모르는 방송 → .drain) 셋이 따라잡기의 1초 창 안에 온다 → 창 끝에 조회 한 번.
        repeat(3) { transport.emit(RealtimeTransportEvent.Broadcast("poke")) }
        runCurrent()
        assertEquals(1, summaries(h), "창이 끝나기 전에는 창 안의 신호를 부르지 않는다")
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
        transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.rummyBroadcastEvent))
        advanceUntilIdle()
        assertEquals(emptyList(), h.rpcNames(), "잠긴 빌드(기본)의 아잉 큐브 초인종은 조회를 내지 않고 메시지 조회로도 새지 않는다 — 켠 빌드는 PhoneRummyWiringTest 가 잰다")
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

    // ---------------------------------------------------------------- 메시지 활동: 앞쪽 처리 + 뒤쪽 합치기(stab-1030 §5-2)
    // 없으면: 열린 대화에서도 새 말이 늘 1초(창) 뒤에 선다 — 첫 신호도 창 끝까지 붙잡혔다.

    private inner class Counts(h: PhoneHarness) {
        var activity = 0
        var reads = 0

        init {
            h.app.realtime.onMessageActivity { activity += 1 }
            h.app.realtime.onMessageRead { reads += 1 }
        }
    }

    /**
     * 큰 창으로 붙고(조인 따라잡기가 앞쪽 한 번 — 전제) 창을 다 보내 "조용한 상태"로 만든다. 돌려주는 값은 그때까지의 활동 호출 수.
     * 벽시계만 옮긴다(`clockShift` — 가상 시간을 밀면 창 끝 타이머가 돌아 시험이 재려는 자리를 먼저 갚는다).
     */
    private fun subscribeAndGoQuiet(h: PhoneHarness, transport: FakeTransport, counts: Counts, window: Double = 10.0): Int {
        h.app.realtime.coalesceSeconds = window
        h.app.realtime.appDidBecomeActive()
        transport.emit(RealtimeTransportEvent.Joined)
        assertTrue(h.app.realtime.state is RealtimeState.Subscribed, "전제: 붙어 있다")
        assertEquals(1, counts.activity, "전제: 조인 따라잡기(catchUp)는 조용하던 창의 첫 신호라 곧바로 한 번")
        h.clockShift += window // 마지막 flush 뒤로 창이 꼭 맞게 지났다(경계 포함)
        return counts.activity
    }

    private fun ring(transport: FakeTransport) = transport.emit(RealtimeTransportEvent.Broadcast("ring"))

    private fun readSignal(transport: FakeTransport) = transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.messageReadBroadcastEvent))

    /** ① 조용한 상태의 drain 하나는 창을 기다리지 않고 곧바로 한 번 — 창 끝에 또 부르지 않는다. */
    @Test
    fun quietDrainFlushesImmediately() = runTest {
        val (h, transport) = rig()
        val counts = Counts(h)
        val base = subscribeAndGoQuiet(h, transport, counts)
        ring(transport)
        assertEquals(base + 1, counts.activity, "조용한 상태의 첫 drain 을 창 끝까지 붙잡았다")
        h.app.realtime.flushCoalescedSignals() // 창 끝
        assertEquals(base + 1, counts.activity, "곧바로 갚은 신호를 창 끝에 또 갚았다(모아 둔 것이 없다)")
        assertEquals(base + 1, h.app.realtime.activityFlushCount)
    }

    /** ② 창 안의 drain 다섯 개 → 곧바로 1회 + 창 끝 1회 = 2회(조회 폭주 없음). */
    @Test
    fun burstInWindowFlushesTwice() = runTest {
        val (h, transport) = rig()
        val counts = Counts(h)
        val base = subscribeAndGoQuiet(h, transport, counts)
        repeat(5) { ring(transport) }
        assertTrue(h.app.realtime.effectLog.takeLast(5).all { it == RealtimeEffect.Drain }, "전제: 다섯 개 모두 drain 이다")
        assertEquals(base + 1, counts.activity, "창 안 다섯 개 중 첫 하나만 곧바로여야 한다")
        h.app.realtime.flushCoalescedSignals() // 창 끝
        assertEquals(base + 2, counts.activity, "창 안의 나머지 넷이 창 끝 한 번으로 모여야 한다")
        h.app.realtime.flushCoalescedSignals()
        assertEquals(base + 2, counts.activity, "모아 둔 것이 없는데 또 불렀다")
    }

    /** ③ 창이 지난 뒤의 drain 은 다시 곧바로 한 번 — 창 끝 직전(대조군)은 모았다가 창 끝에 한 번. */
    @Test
    fun drainAfterWindowFlushesImmediatelyAgain() = runTest {
        val (h, transport) = rig()
        val counts = Counts(h)
        val base = subscribeAndGoQuiet(h, transport, counts)
        ring(transport) // 앞쪽(창 시작)
        assertEquals(base + 1, counts.activity)
        h.clockShift += 9.9 // 대조군: 아직 창 안
        ring(transport)
        assertEquals(base + 1, counts.activity, "창 안의 drain 을 곧바로 불렀다")
        h.app.realtime.flushCoalescedSignals() // 창 끝 → 이 flush 가 다음 창의 시작
        assertEquals(base + 2, counts.activity)
        h.clockShift += 10.0 // 마지막 flush 뒤로 창이 다 지났다
        ring(transport)
        assertEquals(base + 3, counts.activity, "창이 지난 뒤의 drain 을 창 끝까지 붙잡았다")
        h.app.realtime.flushCoalescedSignals()
        assertEquals(base + 3, counts.activity)
    }

    /** ④ 읽음 신호는 곧바로 부르지 않고 창 끝에 한 번(예전과 같다) — 모아 둔 읽음이 조용한 drain 을 붙잡지 않는다. */
    @Test
    fun readSignalStaysTrailingOnly() = runTest {
        val (h, transport) = rig()
        val counts = Counts(h)
        val base = subscribeAndGoQuiet(h, transport, counts)
        readSignal(transport)
        assertEquals(RealtimeEffect.MessageReadSignal, h.app.realtime.effectLog.last())
        assertEquals(0, counts.reads, "조용한 상태라도 읽음 신호는 곧바로 부르지 않는다(뒤쪽 합치기만)")
        readSignal(transport)
        assertEquals(0, counts.reads)
        assertEquals(base, counts.activity, "읽음 신호가 메시지 활동을 깨웠다")
        ring(transport) // 읽음 창이 열려 있어도 활동의 앞쪽은 따로다
        assertEquals(base + 1, counts.activity, "모아 둔 읽음 신호가 조용한 drain 을 창 끝까지 붙잡았다")
        assertEquals(0, counts.reads)
        h.app.realtime.flushCoalescedSignals() // 창 끝
        assertEquals(1, counts.reads, "읽음 두 건이 창 끝 한 번으로 모여야 한다")
        assertEquals(1, h.app.realtime.readFlushCount)
        assertEquals(base + 1, counts.activity, "창 끝에 활동을 또 불렀다(모아 둔 활동이 없다)")
    }

    /** ⑤ active 가 아니면 곧바로 부르지 않는다 — 모아 두었다가 창 끝에 한 번, background 진입은 모아 둔 것을 버린다. */
    @Test
    fun notActiveNeverFlushesImmediately() = runTest {
        val (h, _) = rig()
        val counts = Counts(h)
        val runner = h.app.realtime
        runner.coalesceSeconds = 10.0
        // 실제로는 active 일 때만 붙는다 — 여기서는 문 하나(active 여부)만 따로 재려고 링을 직접 몬다.
        runner.apply(RealtimeEvent.SignedIn(h.app.session.session!!.accessToken))
        runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Joined)) // → .catchUp
        assertTrue(runner.state is RealtimeState.Subscribed, "전제: 붙어 있다")
        assertTrue(!runner.isAppActive)
        assertTrue(RealtimeEffect.CatchUp in runner.effectLog)
        assertEquals(0, counts.activity, "active 가 아닌데 catchUp 을 곧바로 불렀다")
        runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("ring"))) // → .drain
        assertEquals(0, counts.activity, "active 가 아닌데 drain 을 곧바로 불렀다")
        runner.flushCoalescedSignals()
        assertEquals(1, counts.activity, "모아 둔 신호를 창 끝에 한 번 갚아야 한다(뒤쪽 합치기는 남는다)")

        // 폐기 규칙: active 에서 창 안에 모인 drain 은 background 로 가면 버린다.
        runner.appDidBecomeActive()
        h.clockShift += 10.0
        runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("ring"))) // 앞쪽(곧바로)
        assertEquals(2, counts.activity)
        runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("ring"))) // 창 안 → 모은다
        assertEquals(2, counts.activity)
        runner.appDidEnterBackground()
        runner.flushCoalescedSignals()
        assertEquals(2, counts.activity, "background 진입 뒤에도 모아 둔 신호를 갚았다(폐기 규칙)")
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(2, counts.activity, "background 진입 뒤에 창 끝 타이머가 돌았다")
    }

    /** 창 끝 타이머는 '마지막 flush + 창'에 돈다 — 모은 drain 의 도착 + 창이 아니다(훅 없이, 주입 시계로 남은 창을 잰다). */
    @Test
    fun activityWindowEndUsesRemainingWindow() = runTest {
        val (h, transport) = rig()
        val counts = Counts(h)
        val base = subscribeAndGoQuiet(h, transport, counts, window = 30.0)
        ring(transport) // 앞쪽
        assertEquals(base + 1, counts.activity)
        h.clockShift += 29.9 // 창 끝까지 0.1초 남았다
        ring(transport)
        assertEquals(base + 1, counts.activity, "창 안의 drain 을 곧바로 불렀다")
        // 남은 0.1초 뒤에 돌아야 한다. 도착 + 창(30초)으로 잡으면 이 시각에 아직 안 돌았다.
        advanceTimeBy(90)
        runCurrent()
        assertEquals(base + 1, counts.activity, "남은 창이 끝나기 전에 불렀다")
        advanceTimeBy(20)
        runCurrent()
        assertEquals(base + 2, counts.activity, "창 끝 타이머가 남은 창이 아니라 창 전체를 기다렸다(또는 돌지 않았다)")
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(base + 2, counts.activity, "모아 둔 것이 없는데 창 끝에 또 불렀다")
    }

    /** 읽음 창 끝 타이머도 훅 없이 돈다 — 읽음 두 건이 창 끝에 한 번. */
    @Test
    fun readWindowEndTimerFires() = runTest {
        val (h, transport) = rig()
        val counts = Counts(h)
        subscribeAndGoQuiet(h, transport, counts, window = 0.2)
        readSignal(transport)
        readSignal(transport)
        assertEquals(0, counts.reads)
        advanceTimeBy(250)
        runCurrent()
        assertEquals(1, counts.reads, "읽음 창 끝 타이머가 돌지 않았다")
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(1, counts.reads, "읽음 두 건을 창 끝에 두 번 갚았다")
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
