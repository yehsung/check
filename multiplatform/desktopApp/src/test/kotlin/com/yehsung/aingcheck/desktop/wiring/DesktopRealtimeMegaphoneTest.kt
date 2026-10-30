// 원본: Sources/CheckCore/RealtimeLink.swift `megaphoneBroadcastEvent`(@ a6791165 — 확성기는 테트리스 가지 앞) ·
//       Sources/check/WorkTimerStoreRealtime.swift 의 `.megaphoneSignal` 가지(맥은 배너 큐로 간다).
// 데스크톱은 확성기 배너 화면이 아직 없다 — DesktopRealtimeRunner.kt 의 `RealtimeEffect.MegaphoneSignal -> Unit`.
// 이 시험이 지키는 것: 확성기 프레임은 **아무 일도 하지 않는다**(찌르기 소비 0 · 메시지 조회 0 · 게임 신호 0).
//   - core RealtimeLink 의 `megaphone → MegaphoneSignal` 매핑이 빠지면 확성기 프레임이 기본값(.drain)으로 떨어져 take_pokes 가
//     한 번 더 나간다 → drain 2 로 빨강.
//   - 러너가 MegaphoneSignal 을 메시지 조회·게임 신호로 바꾸면 각각 빨강.
// 망 없음(소켓은 가짜 · REST 는 MockEngine `.invalid` · 픽스처 합성).
@file:OptIn(ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.RealtimeRefreshResult
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeGame
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeGames
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeMessages
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeRunner
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeDrainer
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesktopRealtimeMegaphoneTest {
    private class Transport : RealtimeTransport {
        override var onEvent: ((RealtimeTransportEvent) -> Unit)? = null
        override fun connect(projectURL: String, apiKey: String, accessToken: String, channel: String, isPrivate: Boolean) = Unit
        override fun pushAccessToken(token: String) = Unit
        override fun sendHeartbeat() = Unit
        override fun disconnect() = Unit
        fun emit(event: RealtimeTransportEvent) = checkNotNull(onEvent) { "onEvent 가 배선되지 않았다" }.invoke(event)
    }

    private class Drainer : PokeDrainer {
        var requestDrains = 0
        var drainOnces = 0
        override suspend fun drainOnce(): DrainOutcome { drainOnces++; return DrainOutcome.Ok(0) }
        override fun requestDrain() { requestDrains++ }
        override fun flushOnUserStop(isTerminating: Boolean): Job? = null
    }

    private class Messages : DesktopRealtimeMessages {
        var activity = 0
        var readWindows = 0
        override fun requestActivityRefresh() { activity++ }
        override fun readSignalWindowClosed() { readWindows++ }
    }

    private class Game(private val name: String, private val log: MutableList<String>) : DesktopRealtimeGame {
        override fun handleSignal() { log += "$name.signal" }
        override fun realtimeDidJoin() { log += "$name.join" }
        override fun systemDidWake() { log += "$name.wake" }
    }

    @Test
    fun 확성기_프레임은_찌르기_소비도_메시지_조회도_게임_신호도_내지_않는다() = runTest {
        val now = SwiftDate(1_790_000_000.0)
        val paths = mutableListOf<String>()
        val engine = MockEngine { request ->
            paths += request.url.encodedPath
            respond("[]", HttpStatusCode.NotFound)
        }
        val service = SupabaseWorkService(
            "https://probe.invalid", "k", HttpClient(engine) { SupabaseWorkService.clientConfig(this) }, { now }, RulesWireTextRules,
        ) { "ABCDEF12-0000-4000-8000-000000000000" }
        val host = object : SessionHost {
            override val service: SupabaseWorkService = service
            override val session: SupabaseSession? = SupabaseSession("token-1", "refresh-1", "me")
            override val sessionGeneration: Int = 1
            override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = operation(checkNotNull(session))
        }
        val transport = Transport()
        val drainer = Drainer()
        val messages = Messages()
        val gameLog = mutableListOf<String>()
        // 게이트는 열림 — 찌르기 프레임이 take_pokes(requestDrain) 한 번으로 가야 한다(닫힘이면 메시지 조회로 빚을 적는다).
        val gate = object : PokeConsumeGate { override fun mayConsume(now: SwiftDate): Boolean = true }
        val runner = DesktopRealtimeRunner(
            host = host,
            transport = transport,
            gate = gate,
            drainer = { drainer },
            messages = messages,
            games = DesktopRealtimeGames(Game("gomoku", gameLog), Game("chess", gameLog), Game("tetris", gameLog)),
            refreshForRealtime = { RealtimeRefreshResult.Failed(fatal = false) },
            scope = backgroundScope,
            clock = { now },
            runsTimers = false,
            jitter = { it * 0.75 },
            zone = ZoneOffset.UTC,
        )
        runner.onSignedIn()
        transport.emit(RealtimeTransportEvent.Joined)
        runCurrent()
        // 조인의 따라잡기(게임 join · 메시지 조회 등)는 이 시험의 대상이 아니다 — 여기서 영점.
        val drainsAtJoin = drainer.requestDrains + drainer.drainOnces
        val activityAtJoin = messages.activity
        gameLog.clear()

        // 같은 소켓에 찌르기 프레임(서버 send_poke 의 `ring` — 기본 가지) 하나 + 확성기 프레임 하나.
        runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("ring")), now)
        runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("megaphone")), now)
        runCurrent()

        val drains = drainer.requestDrains + drainer.drainOnces - drainsAtJoin
        assertEquals(1, drains, "take_pokes 는 찌르기 프레임 한 번만이다 — 확성기가 .drain 으로 떨어졌다(RealtimeLink 매핑 빠짐)")
        assertEquals(0, messages.activity - activityAtJoin, "확성기 프레임이 메시지 조회를 냈다")
        assertEquals(0, messages.readWindows, "확성기 프레임이 읽음 창을 건드렸다")
        assertTrue(gameLog.isEmpty(), "확성기 프레임이 게임 신호를 냈다: $gameLog")
        assertTrue(paths.none { it.contains("take_pokes") || it.contains("message") }, "망으로 소비·조회가 나갔다: $paths")
    }
}
