// 원본: 없음(W2-g4 시험 기반 — core/stores DuelTestKit 의 가짜 서버 모양을 갈래 안에 작게 둔다. 픽스처는 전부 합성)
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
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
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import java.io.IOException

/** 합성 사용자(실제 계정 아님). */
const val TEST_USER: String = "00000000-0000-0000-0000-0000000000AB"

/** 가짜 서버 응답 하나. */
sealed interface Reply {
    data class Json(val body: String, val status: Int = 200) : Reply
    data object Offline : Reply
    /** 시험이 [gate] 를 끝낼 때까지 응답을 붙잡는다(날아가는 중 상태를 만들 때). */
    data class Hold(val gate: CompletableDeferred<Unit>, val then: Reply) : Reply

    companion object {
        fun missingFunction(name: String): Reply =
            Json("""{"code":"PGRST202","message":"Could not find the function public.$name in the schema cache"}""", 404)
    }
}

data class Call(val method: String, val path: String, val query: List<Pair<String, String>>, val headers: Map<String, List<String>>, val body: String) {
    fun header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()
}

/**
 * 시험 스케줄러 위에서 도는 가짜 PostgREST. "METHOD /path" 마다 응답 줄을 두고 차례로 쓰며 마지막 것을 되풀이한다.
 * 모르는 요청은 500(시험이 그 수를 단언한다).
 */
class FakeServer(scope: TestScope) {
    private val routes = LinkedHashMap<String, ArrayDeque<Reply>>()
    private val recorded = mutableListOf<Call>()
    val calls: List<Call> get() = recorded.toList()

    fun on(method: String, path: String, vararg replies: Reply): FakeServer {
        routes.getOrPut("$method $path") { ArrayDeque() }.addAll(replies)
        return this
    }

    fun count(method: String, path: String): Int = recorded.count { it.method == method && it.path == path }

    val engine: MockEngine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val call = Call(
                    method = request.method.value,
                    path = request.url.encodedPath,
                    query = request.url.parameters.entries().flatMap { (k, vs) -> vs.map { k to it } },
                    headers = request.headers.entries().associate { it.key to it.value },
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

/** 세션 몫만 있는 호스트(Swift 시험의 `WorkTimerStore` 자리). [withSessionRetry] 는 갱신 없이 한 번. */
class FakeSessionHost(override val service: SupabaseWorkService, user: String? = TEST_USER) : SessionHost {
    override var session: SupabaseSession? = user?.let { SupabaseSession("access-token", null, it) }
    override var sessionGeneration: Int = 0

    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(session ?: throw SupabaseWorkServiceError.SessionExpired)
}

/** 벽시계 대신(초 단위 since1970). */
class TestClock(var since1970: Double = 1_793_000_000.0) {
    fun now(): SwiftDate = SwiftDate(since1970)
    fun advance(seconds: Double) {
        since1970 += seconds
    }
}

/**
 * 랩 판정 가짜 — W2-g6(근무 갈래)이 구현할 [LapWalletJudgment] 의 **Swift 규칙 사본**(applyUltraWallet 334-352):
 * 축하 = granted_now 행이 하나라도, 랩 수 = granted_now 행의 lapsGranted 최대(0 이면 1, ★U3). 실물이 들어오면 골든을 실물로도 돌린다.
 */
class SwiftRuleLapJudgment : LapWalletJudgment {
    var calls: Int = 0
        private set

    override fun judge(grants: List<com.yehsung.aingcheck.feature.desktop.work.LapGrant>, streakDays: Int): LapOutcome {
        calls += 1
        val granted = grants.filter { it.grantedNow }
        if (granted.isEmpty()) return LapOutcome(celebrate = false, lapsToday = 0, streakDays = streakDays)
        val laps = granted.maxOf { it.lapsGranted }.let { if (it == 0) 1 else it }
        return LapOutcome(celebrate = true, lapsToday = laps, streakDays = streakDays)
    }
}

const val WALLET_PATH: String = "/rest/v1/rpc/ultra_wallet_sync"
const val BUY_PATH: String = "/rest/v1/rpc/buy_ultra"
const val PROFILES_PATH: String = "/rest/v1/profiles"

fun walletOk(balance: Long = 2, extra: String = ""): Reply.Json =
    Reply.Json("""{"status":"ok","balance":$balance,"day":"2026-10-30"$extra}""")
