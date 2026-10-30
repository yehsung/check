// W2-g3 완료 기준(poke.md §5) — 규약 번호는 지시서 R1~R7(★ = Swift 원본 ★ 규약).
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.session.RealtimeRefreshResult
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** ★ R3: `.drain` 인데 게이트가 닫혔으면 take_pokes 0 · 빚 true · 활동 조회 1. */
@OptIn(ExperimentalCoroutinesApi::class)
class DesktopRealtimeDrainGateTest {
    @Test
    fun closedGateDrainDoesNotTakePokesButRecordsDebtAndReadsActivity() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.subscribe()
        runCurrent()
        val activityAfterJoin = h.messages.activity
        h.runner.clearCatchUpDebt() // 조인 빚과 가르기 위해 지운다 — 아래 빚은 초인종이 적은 것이어야 한다.
        val effects = h.broadcast("poke")
        runCurrent()
        assertEquals(listOf<RealtimeEffect>(RealtimeEffect.Drain), effects)
        assertEquals(0, h.drainer.takePokes, "R3 게이트가 닫혔는데 take_pokes 가 나갔다")
        assertTrue(h.runner.catchUpDeferred, "R3 빚을 적지 않았다")
        assertEquals(activityAfterJoin + 1, h.messages.activity, "R3 활동 조회 1회")
        assertTrue(h.router.requests.isEmpty(), "러너가 HTTP 를 직접 부르면 안 된다: ${h.router.requests.map { it.key }}")
    }

    @Test
    fun openGateDrainGoesThroughSerializedRequestDrainOnly() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = true)
        h.subscribe()
        runCurrent()
        val before = h.drainer.takePokes
        val activityBefore = h.messages.activity
        h.broadcast("poke")
        runCurrent()
        assertEquals(1, h.drainer.requestDrains, "열린 게이트의 .drain 은 requestDrain(직렬화 P7) 한 번")
        assertEquals(before + 1, h.drainer.takePokes)
        assertFalse(h.runner.catchUpDeferred)
        assertEquals(activityBefore, h.messages.activity, "소비 가지는 활동 조회를 따로 쏘지 않는다")
    }

    /** poke.md §4 (6): 받는 쪽 싱크가 없어 drainer 가 조립되지 않았으면 게이트가 열려도 take_pokes 0. */
    @Test
    fun missingDrainerNeverConsumes() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = true, withDrainer = false)
        h.subscribe()
        runCurrent()
        h.broadcast("poke")
        h.runner.tick(h.now)
        runCurrent()
        assertEquals(0, h.drainer.takePokes)
        assertFalse(h.runner.mayConsumePokes(h.now))
    }
}

/** ★ R4: 빚 상환 조건 넷 · 근무 시작 drain 이 빚을 지운다(take_pokes 두 번 금지). */
@OptIn(ExperimentalCoroutinesApi::class)
class CatchUpDebtTest {
    /** 근무 시작 한 번 = take_pokes 1회. 음성 대조: onWorkStarted 에서 clearCatchUpDebt 를 빼면 2회. */
    @Test
    fun workStartOnceTakesPokesOnce() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.subscribe() // 비근무 로그인 → 조인 → 따라잡기는 게이트에 막혀 빚.
        runCurrent()
        h.broadcast("poke") // 비근무 초인종 → 빚.
        runCurrent()
        assertTrue(h.runner.catchUpDeferred)
        assertEquals(0, h.drainer.takePokes)
        // 근무 시작(AppGraph 가 펼치는 순서 — 찌르기 갈래의 requestDrain, 그리고 실시간의 onWorkStarted).
        h.gate.open = true
        h.drainer.requestDrain()
        h.runner.onWorkStarted()
        // 다음 5초 티커 · 30초 되맞춤이 같은 빚을 또 갚으면 안 된다.
        h.advance(5.0)
        h.runner.tick(h.now)
        h.runner.onTeamStatusApplied()
        runCurrent()
        assertEquals(1, h.drainer.takePokes, "근무 시작 한 번에 take_pokes 는 한 번(R4)")
        assertFalse(h.runner.catchUpDeferred)
        assertEquals(1, h.transport!!.connects.size, "근무 시작이 붙은 소켓을 다시 붙이면 안 된다(R2)")
    }

    /** 근무 시작 drain 없이 게이트만 열린 경로(재시작 복구·흡수 해제): 빚은 tick·되맞춤 중 **한 번만** 갚는다. */
    @Test
    fun debtIsRepaidExactlyOnceWhenGateOpens() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.subscribe()
        runCurrent()
        assertTrue(h.runner.catchUpDeferred)
        h.runner.tick(h.now)
        runCurrent()
        assertEquals(0, h.drainer.takePokes, "게이트가 닫혀 있으면 갚지 않는다")
        h.gate.open = true
        h.runner.onTeamStatusApplied()
        h.runner.tick(h.now) // 따라잡기가 도는 중(catchUpJob != null) — 두 번째로 띄우지 않는다.
        runCurrent()
        h.runner.tick(h.now)
        h.runner.onTeamStatusApplied()
        runCurrent()
        assertEquals(1, h.drainer.drainOnces, "빚은 한 번만")
        assertFalse(h.runner.catchUpDeferred)
        assertNotNull(h.runner.diagnostics.lastCatchUpAt)
    }

    /**
     * 조건 넷 중 '도는 따라잡기 없음': 왕복 중인 따라잡기(take_pokes 원자 소비)를 갚기가 취소·재시작하면 응답 유실 = 찌르기 영구 소실.
     * 그 사이 닫힌 게이트의 초인종이 적은 빚은 따라잡기가 끝난 **뒤** 한 번 갚는다.
     */
    @Test
    fun inFlightCatchUpIsNotRestartedByRepayment() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = true)
        val hold = CompletableDeferred<Unit>()
        h.drainer.hold = hold
        h.subscribe()
        runCurrent()
        assertEquals(1, h.drainer.drainOnces)
        h.gate.open = false
        h.broadcast("poke")
        assertTrue(h.runner.catchUpDeferred)
        h.gate.open = true
        h.runner.tick(h.now)
        h.runner.onTeamStatusApplied()
        runCurrent()
        assertEquals(0, h.drainer.cancelledDrains, "왕복 중인 따라잡기를 취소했다")
        assertEquals(1, h.drainer.drainOnces)
        hold.complete(Unit)
        runCurrent()
        h.runner.tick(h.now)
        runCurrent()
        assertEquals(2, h.drainer.drainOnces, "끝난 뒤 남은 빚을 한 번 갚는다")
        assertFalse(h.runner.catchUpDeferred)
    }

    /** 조건 넷 중 '구독 중': 빚이 있어도 구독이 아니면 갚지 않는다. */
    @Test
    fun debtWaitsForSubscription() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.subscribe()
        runCurrent()
        h.transport!!.emit(RealtimeTransportEvent.Closed(null))
        assertTrue(h.runner.state.value is RealtimeState.Reconnecting)
        h.gate.open = true
        h.runner.onTeamStatusApplied()
        runCurrent()
        assertEquals(0, h.drainer.takePokes)
        assertTrue(h.runner.catchUpDeferred)
    }

    /** 따라잡기 시도 3회 · 사이 1·2초 · 실패하면 경고 시각을 세운다. 성공하면 경고를 nil 로 되돌린다. */
    @Test
    fun catchUpRetriesThreeTimesThenFlagsFailure() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = true)
        repeat(3) { h.drainer.outcomes.addLast(DrainOutcome.Failed("boom$it")) }
        h.subscribe()
        runCurrent()
        assertEquals(1, h.drainer.drainOnces)
        advanceTimeBy(999)
        runCurrent()
        assertEquals(1, h.drainer.drainOnces, "1초 전에는 다시 시도하지 않는다")
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, h.drainer.drainOnces)
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(3, h.drainer.drainOnces)
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(3, h.drainer.drainOnces, "시도는 3회")
        assertEquals(3, h.runner.diagnostics.lastCatchUpAttempts)
        assertEquals("boom2", h.runner.diagnostics.lastCatchUpFailure)
        assertNotNull(h.runner.catchUpFailedAt.value)
        assertTrue(h.runner.diagnosticsLine.endsWith("따라잡기 실패"), h.runner.diagnosticsLine)
        // 재조인 성공 → 경고 해제.
        h.transport!!.emit(RealtimeTransportEvent.Closed(null))
        h.runner.apply(RealtimeEvent.BackoffElapsed, h.now)
        h.transport.emit(RealtimeTransportEvent.Joined)
        runCurrent()
        assertNull(h.runner.catchUpFailedAt.value)
        assertEquals(4, h.drainer.drainOnces)
    }
}

/** ★ R2: 소켓은 근무가 아니라 로그인 기준. */
@OptIn(ExperimentalCoroutinesApi::class)
class SocketIsLoginTest {
    @Test
    fun signedInNotWorkingConnectsOnce() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.runner.onSignedIn()
        val t = h.transport!!
        assertEquals(1, t.connects.size, "비근무 로그인 → connect 1")
        assertEquals(FakeTransport.Connect("https://golden.invalid", "k", "token-1", "poke:me", true), t.connects.single())
        assertTrue(h.runner.state.value is RealtimeState.Connecting)
        // 두 번째 로그인 지점·근무 시작은 로그아웃 상태의 링만 출발시킨다.
        h.runner.onSignedIn()
        h.runner.onWorkStarted()
        t.emit(RealtimeTransportEvent.Joined)
        h.runner.onWorkStarted()
        runCurrent()
        assertEquals(1, t.connects.size)
        assertTrue(h.runner.isSubscribed)
    }

    @Test
    fun signOutDropsSocketAndSleepWakeRejoins() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.subscribe()
        runCurrent()
        val t = h.transport!!
        h.runner.onWillSleep(h.now)
        assertEquals(RealtimeState.Idle(IdleReason.suspended), h.runner.state.value, "비근무여도 뚜껑에 내려간다")
        h.advance(600.0)
        h.runner.onDidWake(h.now)
        assertEquals(2, t.connects.size, "깨어남 → 재조인 1")
        assertTrue(h.gameLog.none { it.endsWith(".wake") }, "R5 전송자가 있으면 didWake 의 게임 조회는 하지 않는다(조인이 맡는다)")
        h.runner.onSignedOut()
        assertEquals(RealtimeState.Idle(IdleReason.signedOut), h.runner.state.value)
        assertFalse(h.runner.catchUpDeferred, "로그아웃은 빚도 지운다")
        assertTrue(t.disconnects >= 2)
    }

    /** ★ R6 경합 2: 링이 실어 온 토큰이 아니라 연결 시점의 세션 토큰으로 붙는다. */
    @Test
    fun connectReadsTokenAtConnectTime() = runTest {
        val h = RealtimeHarness(backgroundScope)
        h.subscribe()
        h.transport!!.emit(RealtimeTransportEvent.Closed(1006))
        h.host.current = h.host.current!!.copy(accessToken = "token-2")
        h.runner.apply(RealtimeEvent.BackoffElapsed, h.now)
        assertEquals("token-2", h.transport.connects.last().token)
        assertTrue(h.runner.diagnostics.recent.any { it.cause == "token-superseded" })
    }
}

/** ★ R6: 전송자 nil → `idle(disabled)`, 요청 0. anon 키가 없으면 출발하지 않는다. */
@OptIn(ExperimentalCoroutinesApi::class)
class RealtimeNoTransportTest {
    @Test
    fun nilTransportIsDisabledAndSilent() = runTest {
        val h = RealtimeHarness(backgroundScope, transport = null, gateOpen = true)
        assertEquals(RealtimeState.Idle(IdleReason.disabled), h.runner.state.value)
        h.runner.onSignedIn()
        h.runner.onWorkStarted()
        h.runner.tick(h.now)
        h.runner.onTeamStatusApplied()
        runCurrent()
        assertEquals(RealtimeState.Idle(IdleReason.disabled), h.runner.state.value)
        assertFalse(h.runner.isSubscribed)
        assertEquals(0, h.drainer.takePokes)
        assertEquals(0, h.messages.activity)
        assertTrue(h.router.requests.isEmpty())
        assertTrue(h.runner.diagnosticsLine.startsWith("idle(disabled) · 전송자 없음 · 재연결 0회 · 따라잡기 없음"), h.runner.diagnosticsLine)
        // R5: 전송자가 없으면 깨어남이 게임 조회를 직접 한 번(오목 → 체스 → 테트리스).
        h.runner.onDidWake(h.now)
        assertEquals(listOf("gomoku.wake", "chess.wake", "tetris.wake"), h.gameLog)
    }

    @Test
    fun missingAnonKeyDoesNotStartTheLink() = runTest {
        val h = RealtimeHarness(backgroundScope, anonKey = null)
        h.runner.onSignedIn()
        h.runner.onWorkStarted()
        assertEquals(RealtimeState.Idle(IdleReason.signedOut), h.runner.state.value)
        assertEquals(0, h.transport!!.connects.size)
        assertNull(h.transport.onEvent, "출발하지 않으면 배선도 하지 않는다")
    }
}

/** ★ R5 · R7 신호 가지: 게임 따라잡기는 게이트 없이 · 읽음 신호는 1초 창 하나. */
@OptIn(ExperimentalCoroutinesApi::class)
class DesktopRealtimeSignalTest {
    @Test
    fun catchUpCallsGameJoinWithoutGate() = runTest {
        val h = RealtimeHarness(backgroundScope, gateOpen = false)
        h.subscribe()
        runCurrent()
        assertEquals(listOf("gomoku.join", "chess.join", "tetris.join"), h.gameLog)
        h.broadcast("gomoku")
        h.broadcast("chess")
        h.broadcast("tetris")
        assertEquals(listOf("gomoku.signal", "chess.signal", "tetris.signal"), h.gameLog.drop(3))
        assertEquals(0, h.drainer.takePokes)
    }

    @Test
    fun readSignalsCoalesceInOneSecondWindow() = runTest {
        val h = RealtimeHarness(backgroundScope)
        h.subscribe()
        runCurrent()
        repeat(3) { h.broadcast("message_read") }
        advanceTimeBy(999)
        runCurrent()
        assertEquals(0, h.messages.readWindows)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, h.messages.readWindows, "창 하나에 한 번")
        h.broadcast("message_read")
        h.host.generation += 1 // 창이 열린 사이 계정 전환 — 옛 창은 새 계정에 쏘지 않는다.
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(1, h.messages.readWindows)
    }

    /** 토큰 갱신: 강제 갱신 결과가 링에 들어가 재조인 · stale 결과는 버린다. */
    @Test
    fun expiredJoinForcesRefreshThroughCoordinator() = runTest {
        var calls = 0
        val results = ArrayDeque(listOf<RealtimeRefreshResult>(RealtimeRefreshResult.Refreshed("token-9"), RealtimeRefreshResult.Failed.Stale))
        val h = RealtimeHarness(backgroundScope, refresh = { calls++; results.removeFirst() })
        h.runner.onSignedIn()
        h.runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.ExpiredToken)), h.now)
        h.host.current = h.host.current!!.copy(accessToken = "token-9")
        runCurrent()
        assertEquals(1, calls)
        assertEquals("token-9", h.transport!!.connects.last().token)
        assertEquals(2, h.transport.connects.size)
        // 갱신된 토큰으로 다시 붙은 시도가 또 만료로 거절 → 다시 강제 갱신. 그 결과가 stale(세대가 끝남)이면 링에 넣지 않는다.
        h.runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.ExpiredToken)), h.now)
        runCurrent()
        assertEquals(2, calls)
        assertTrue(h.runner.state.value is RealtimeState.Connecting, "stale 결과가 막 붙는 소켓을 내리면 안 된다: ${h.runner.state.value}")
        assertEquals(2, h.transport.connects.size)
    }
}
