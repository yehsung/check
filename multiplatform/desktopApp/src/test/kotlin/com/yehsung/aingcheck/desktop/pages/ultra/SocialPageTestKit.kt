// 원본: multiplatform/feature/desktop/src/desktopTest/…/ultra/UltraTestKit.kt @ bcd545f7 (W2-g4 가짜 서버 — 모듈 시험 경계라 갈래 안 작은 사본, 픽스처는 전부 합성)
// W3-c3 콕·울트라·집중 페이지 시험 기반. 빚: 공용 testkit 으로 옮길 때 지운다(W-6 #4 와 같은 류).
package com.yehsung.aingcheck.desktop.pages.ultra

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.LapOutcome
import com.yehsung.aingcheck.feature.desktop.work.LapWalletJudgment
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import java.io.IOException

/** 합성 사용자(실제 계정 아님). */
const val ME: String = "00000000-0000-4000-8000-0000000000aa"

sealed interface Reply {
    data class Json(val body: String, val status: Int = 200) : Reply
    data object Offline : Reply
    /** 시험이 [gate] 를 끝낼 때까지 응답을 붙잡는다(날아가는 중 상태). */
    data class Hold(val gate: CompletableDeferred<Unit>, val then: Reply) : Reply
}

data class Call(val method: String, val path: String, val query: List<Pair<String, String>>, val body: String)

/** "METHOD /path" 마다 응답 줄(차례로 쓰고 마지막을 되풀이). 모르는 요청은 500. MockEngine 이 받은 요청을 전부 녹음한다. */
class FakeServer(scope: TestScope) {
    private val routes = LinkedHashMap<String, ArrayDeque<Reply>>()
    private val recorded = mutableListOf<Call>()
    val calls: List<Call> get() = recorded.toList()

    fun on(method: String, path: String, vararg replies: Reply): FakeServer {
        routes.getOrPut("$method $path") { ArrayDeque() }.addAll(replies)
        return this
    }

    fun count(method: String, path: String): Int = recorded.count { it.method == method && it.path == path }
    fun bodies(method: String, path: String): List<String> = recorded.filter { it.method == method && it.path == path }.map { it.body }

    val engine: MockEngine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val call = Call(
                    method = request.method.value,
                    path = request.url.encodedPath,
                    query = request.url.parameters.entries().flatMap { (k, vs) -> vs.map { k to it } },
                    body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: "",
                )
                recorded += call
                val queue = routes["${call.method} ${call.path}"]
                var reply: Reply = when {
                    queue == null || queue.isEmpty() -> Reply.Json("""{"message":"not scripted"}""", 500)
                    queue.size > 1 -> queue.removeFirst()
                    else -> queue.first()
                }
                while (reply is Reply.Hold) {
                    reply.gate.await()
                    reply = reply.then
                }
                when (reply) {
                    Reply.Offline -> throw IOException("offline")
                    is Reply.Json -> respond(reply.body, HttpStatusCode.fromValue(reply.status), headersOf(HttpHeaders.ContentType, "application/json"))
                    is Reply.Hold -> error("unreachable")
                }
            }
        },
    )

    fun service(clock: () -> SwiftDate): SupabaseWorkService = SupabaseWorkService(
        projectURL = "https://golden.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = clock,
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )
}

class FakeSessionHost(override val service: SupabaseWorkService, user: String? = ME) : SessionHost {
    override var session: SupabaseSession? = user?.let { SupabaseSession("access-token", null, it) }
    override var sessionGeneration: Int = 0

    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(session ?: throw SupabaseWorkServiceError.SessionExpired)
}

class TestClock(var since1970: Double = 1_793_000_000.0) {
    fun now(): SwiftDate = SwiftDate(since1970)
    fun advance(seconds: Double) {
        since1970 += seconds
    }
}

class FakeWorkState(working: Boolean = true) : DesktopWorkState {
    val state = MutableStateFlow(DesktopWorkSnapshot(isWorking = working))
    override val snapshot: StateFlow<DesktopWorkSnapshot> = state
}

/** 랩 판정은 이 시험의 몫이 아니다(축하 0). */
val NO_LAPS: LapWalletJudgment = LapWalletJudgment { _, streak -> LapOutcome(celebrate = false, lapsToday = 0, streakDays = streak) }

const val BUY_PATH: String = "/rest/v1/rpc/buy_ultra"
const val WALLET_PATH: String = "/rest/v1/rpc/ultra_wallet_sync"
const val PROFILES_PATH: String = "/rest/v1/profiles"
const val DIRECTORY_PATH: String = "/rest/v1/rpc/app_user_directory"
const val POKE_PATH: String = "/rest/v1/rpc/poke_user"
const val ULTRA_POKE_PATH: String = "/rest/v1/rpc/ultra_poke_user"
