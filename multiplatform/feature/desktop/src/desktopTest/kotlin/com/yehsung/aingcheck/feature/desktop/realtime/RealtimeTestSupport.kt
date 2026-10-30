// W2-g3 실시간 시험 바탕 — 합성 픽스처만(실제 홈·계정·소켓 없음). 서버는 testkit MockRouter(경로 없음 → 어떤 요청도 기록만 남고 실패).
// PokeConsumeGate·PokeDrainer 는 핀(socialapi) 인터페이스의 시험용 가짜다 — 실물(W2-g2) 연결은 조립(AppGraph) 때.
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.RealtimeRefreshResult
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeDrainer
import com.yehsung.aingcheck.testkit.mock.MockRouter
import io.ktor.client.HttpClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import java.time.ZoneOffset
import kotlin.coroutines.cancellation.CancellationException

internal val T0: SwiftDate = SwiftDate(1_790_000_000.0)

internal class FakeHost(override val service: SupabaseWorkService) : SessionHost {
    var current: SupabaseSession? = SupabaseSession("token-1", "refresh-1", "me")
    var generation: Int = 1
    override val session: SupabaseSession? get() = current
    override val sessionGeneration: Int get() = generation
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(current ?: throw IllegalStateException("세션 없음"))
}

internal class FakeTransport : RealtimeTransport {
    data class Connect(val projectURL: String, val apiKey: String, val token: String, val channel: String, val isPrivate: Boolean)

    override var onEvent: ((RealtimeTransportEvent) -> Unit)? = null
    val connects = mutableListOf<Connect>()
    var disconnects = 0
    var heartbeats = 0
    val pushed = mutableListOf<String>()

    override fun connect(projectURL: String, apiKey: String, accessToken: String, channel: String, isPrivate: Boolean) {
        connects += Connect(projectURL, apiKey, accessToken, channel, isPrivate)
    }
    override fun pushAccessToken(token: String) { pushed += token }
    override fun sendHeartbeat() { heartbeats++ }
    override fun disconnect() { disconnects++ }

    fun emit(event: RealtimeTransportEvent) = checkNotNull(onEvent) { "onEvent 가 배선되지 않았다" }.invoke(event)
}

/** 판정 한 벌의 가짜(실물 DesktopPokeConsumeGate 는 W2-g2). */
internal class FakeGate(var open: Boolean) : PokeConsumeGate {
    var asked = 0
    override fun mayConsume(now: SwiftDate): Boolean {
        asked++
        return open
    }
}

/** take_pokes 가 나가는 두 문(requestDrain · drainOnce)을 함께 센다 — 둘 다 서버 원자 소비 한 번. */
internal class FakeDrainer : PokeDrainer {
    var requestDrains = 0
    var drainOnces = 0
    val takePokes: Int get() = requestDrains + drainOnces
    val outcomes = ArrayDeque<DrainOutcome>()

    /** 있으면 drainOnce 가 여기서 멈춘다(서버 왕복 중인 원자 소비). 멈춘 채 취소되면 [cancelledDrains] 가 오른다. */
    var hold: CompletableDeferred<Unit>? = null
    var cancelledDrains = 0
    override suspend fun drainOnce(): DrainOutcome {
        drainOnces++
        try {
            hold?.await()
        } catch (e: CancellationException) {
            cancelledDrains++
            throw e
        }
        return outcomes.removeFirstOrNull() ?: DrainOutcome.Ok(0)
    }
    override fun requestDrain() { requestDrains++ }
    override fun flushOnUserStop(isTerminating: Boolean): Job? = null
}

internal class FakeMessages : DesktopRealtimeMessages {
    var activity = 0
    var readWindows = 0
    override fun requestActivityRefresh() { activity++ }
    override fun readSignalWindowClosed() { readWindows++ }
}

internal class FakeGame(private val name: String, private val log: MutableList<String>) : DesktopRealtimeGame {
    override fun handleSignal() { log += "$name.signal" }
    override fun realtimeDidJoin() { log += "$name.join" }
    override fun systemDidWake() { log += "$name.wake" }
}

internal class RealtimeHarness(
    scope: CoroutineScope,
    val transport: FakeTransport? = FakeTransport(),
    anonKey: String? = "k",
    gateOpen: Boolean = false,
    withDrainer: Boolean = true,
    refresh: suspend () -> RealtimeRefreshResult = { RealtimeRefreshResult.Failed(fatal = false) },
    jitter: (Double) -> Double = { it * 0.75 },
) {
    var now: SwiftDate = T0
    val router = MockRouter()
    val service = SupabaseWorkService(
        "https://golden.invalid", anonKey, HttpClient(router.engine) { SupabaseWorkService.clientConfig(this) }, { now }, RulesWireTextRules,
    ) { "ABCDEF12-0000-4000-8000-000000000000" }
    val host = FakeHost(service)
    val gate = FakeGate(gateOpen)
    val drainer = FakeDrainer()
    val messages = FakeMessages()
    val gameLog = mutableListOf<String>()
    val games = DesktopRealtimeGames(FakeGame("gomoku", gameLog), FakeGame("chess", gameLog), FakeGame("tetris", gameLog))
    var drainerPresent = withDrainer
    val runner = DesktopRealtimeRunner(
        host = host,
        transport = transport,
        gate = gate,
        drainer = { if (drainerPresent) drainer else null },
        messages = messages,
        games = games,
        refreshForRealtime = refresh,
        scope = scope,
        clock = { now },
        runsTimers = false,
        jitter = jitter,
        zone = ZoneOffset.UTC,
    )

    fun advance(seconds: Double) {
        now = now.addingTimeInterval(seconds)
    }

    /** 로그인 → 조인까지(구독 상태). 조인의 `.catchUp` 이 띄운 따라잡기는 호출부가 runCurrent 로 돌린다. */
    fun subscribe() {
        runner.onSignedIn()
        checkNotNull(transport).emit(RealtimeTransportEvent.Joined)
    }

    fun broadcast(event: String) = runner.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast(event)), now)
}
