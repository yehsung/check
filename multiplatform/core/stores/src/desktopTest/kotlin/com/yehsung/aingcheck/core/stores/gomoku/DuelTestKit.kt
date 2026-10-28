// 원본: Tests/checkTests/V0327GomokuContractTests.swift:20-273(픽스처 도구 · ServerFacts · 스토어 조립 — 호스트별 스텁 · rpc 별 픽스처 큐) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.io.IOException
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

// 대결 스토어 시험 도우미(오목·체스 공용). 픽스처 `Tests/checkTests/Fixtures/{gomoku,chess}-rpc/*.json` 은 스텁 추측이 아니라 로컬 하네스에서
// RPC 를 **실제로 부른 jsonb 출력 그대로**다(Swift 계약 시험과 같은 파일을 제자리에서 읽는다 — 복사 0, A§4-2).
// 스텁 서버는 rpc 이름마다 큐를 두고 호출 순서대로 돌려준다. **큐 밖의 호출은 500**(Swift `GomokuStubProtocol` 과 같다 — 스토어의 실패 경로라
// 화면을 안 바꾼다). MockEngine 은 시험 디스패처에서 돈다(가상 시간 — 실제 시간 0).

/** 스텁 응답 하나. */
sealed interface StubReply {
    data class Json(val body: String, val status: Int = 200) : StubReply

    /** 전송 실패(오프라인). */
    data object Offline : StubReply

    companion object {
        /** PostgREST 교착(40P01) — 서버가 트랜잭션을 통째로 되돌린 실패. */
        val deadlock: StubReply = Json("""{"code":"40P01","message":"deadlock detected","details":null,"hint":null}""", 500)

        /** PostgREST 가 함수를 못 찾을 때(PGRST202) — 서버가 준비 안 된 응답(.databaseSchemaMissing). */
        fun missingFunction(name: String): StubReply =
            Json("""{"code":"PGRST202","message":"Could not find the function public.$name in the schema cache"}""", 404)
    }
}

/** 받은 요청 하나(rpc 이름 + 본문 JSON). */
data class StubCall(val rpc: String, val body: JsonObject)

/** rpc 별 큐 스텁 서버. */
@OptIn(ExperimentalCoroutinesApi::class)
class DuelStubServer(scope: TestScope) {
    private val queues = LinkedHashMap<String, ArrayDeque<StubReply>>()
    private val recorded = mutableListOf<StubCall>()
    private val counters = HashMap<String, Int>()

    val calls: List<StubCall> get() = recorded.toList()

    fun queue(rpc: String, vararg replies: StubReply): DuelStubServer {
        queues.getOrPut(rpc) { ArrayDeque() }.addAll(replies)
        return this
    }

    fun queueFixtures(rpc: String, directory: String, vararg names: String): DuelStubServer =
        queue(rpc, *names.map { StubReply.Json(fixtureText(directory, it)) }.toTypedArray())

    fun count(rpc: String): Int = recorded.count { it.rpc == rpc }

    fun lastBody(rpc: String): JsonObject = recorded.lastOrNull { it.rpc == rpc }?.body ?: JsonObject(emptyMap())

    fun bodies(rpc: String): List<JsonObject> = recorded.filter { it.rpc == rpc }.map { it.body }

    val engine: MockEngine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val path = request.url.encodedPath
                val rpc = path.removePrefix("/rest/v1/rpc/")
                val text = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
                val body = if (text.isBlank()) JsonObject(emptyMap()) else Json.parseToJsonElement(text).jsonObject
                recorded += StubCall(rpc, body)
                val index = counters[rpc] ?: 0
                counters[rpc] = index + 1
                val reply = queues[rpc]?.removeFirstOrNull() ?: StubReply.Json("""{"message":"not scripted"}""", 500)
                when (reply) {
                    StubReply.Offline -> throw IOException("offline")
                    is StubReply.Json -> respond(
                        reply.body, HttpStatusCode.fromValue(reply.status), headersOf(HttpHeaders.ContentType, "application/json"),
                    )
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

/** 시험용 호스트(Swift 시험의 `WorkTimerStore` 자리 — 세션 몫만). [withSessionRetry] 는 갱신 없이 한 번 부른다. */
class FakeDuelHost(
    override val service: SupabaseWorkService,
    me: String?,
    override var appConfig: AppConfig = AppConfig(duelsEnabled = true),
    private val clockNow: () -> SwiftDate,
) : GomokuStoreHost {
    override var session: SupabaseSession? = me?.let { SupabaseSession("access-token", null, it) }
    override var sessionGeneration: Int = 0
    override var realtimeState: RealtimeState = RealtimeState.Idle(IdleReason.disabled)
    var rubyWrites: Int = 0
        private set
    override var rubyBalance: Long? = null
        set(value) {
            field = value
            rubyWrites += 1
        }
    val logs: MutableList<String> = mutableListOf()
    override val logger: Logger = object : Logger {
        override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {
            logs += "$tag $message"
        }
    }

    override fun now(): SwiftDate = clockNow()

    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(session ?: throw SupabaseWorkServiceError.SessionExpired)
}

/** Swift `contractClock`(1_900_000_000 = 2030-03-17). 픽스처는 과거에 떴다 — 마감은 server_now_ms 차이로 보정된다. */
val contractClock: SwiftDate = SwiftDate(1_900_000_000.0)

/** 시험 디스패처 위의 스토어 범위(SessionHarness 와 같은 꼴 — `backgroundScope` 는 advanceUntilIdle 이 안 기다린다). */
fun TestScope.storeScope(): CoroutineScope {
    val job = SupervisorJob()
    backgroundScope.coroutineContext.job.invokeOnCompletion { job.cancel() }
    return CoroutineScope(coroutineContext.minusKey(Job) + job)
}

/** 지금 시각에 걸린 작업을 다 돌린다(지연 작업 — 만료 타이머·폴링 — 은 돌리지 않는다). */
@OptIn(ExperimentalCoroutinesApi::class)
fun TestScope.settle() {
    runCurrent()
}

const val GOMOKU_FIXTURES: String = "Tests/checkTests/Fixtures/gomoku-rpc"
const val CHESS_FIXTURES: String = "Tests/checkTests/Fixtures/chess-rpc"

fun fixtureText(directory: String, name: String): String = RepoFiles.readText("$directory/$name.json")

fun fixtureJSON(directory: String, name: String): JsonObject = Json.parseToJsonElement(fixtureText(directory, name)).jsonObject

/** 픽스처 하나를 앱의 실제 응답 모델로 읽는다(Swift `contractDecoder` — convertFromSnakeCase 와 같은 디코드 규칙). */
fun <T> decodeFixture(directory: String, name: String, deserializer: DeserializationStrategy<T>): T =
    SwiftJson.decode(deserializer, fixtureText(directory, name))

fun <T> decodeJson(json: JsonObject, deserializer: DeserializationStrategy<T>): T = SwiftJson.decode(deserializer, json.toString())

fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content

fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.longOrNull

fun JsonObject.double(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.doubleOrNull

fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull

fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

fun JsonElement.objects(): List<JsonObject> = jsonArray.map { it.jsonObject }

/** 상태를 싣는 오목 응답 하나에서 읽은 서버의 사실(Swift `ServerFacts`). */
class GomokuServerFacts(val json: JsonObject) {
    private val match = json.obj("match") ?: error("상태 응답 모양이 아니다: ${json.keys.sorted()}")
    val status: String = json.str("status") ?: error("status 없음")
    val matchID: String = match.str("id")!!
    val matchStatus: String = match.str("status")!!
    val board: String = match.str("board")!!
    val moveCount: Int = match.long("move_count")!!.toInt()
    val turn: String? = match.str("turn")
    val myColor: String = json.str("my_color")!!
    val myID: String = (if (myColor == "black") match.str("black") else match.str("white"))!!
    val result: String? = match.str("result")
    val endReason: String? = match.str("end_reason")
    val stake: Long = match.long("stake")!!
    val ruby: Long? = json.long("ruby_balance")
    val serverNowMs: Double? = json.double("server_now_ms")
    val deadlineMs: Double? = match.double("deadline_ms")

    constructor(name: String) : this(fixtureJSON(GOMOKU_FIXTURES, name))
}

/** 매니페스트(호출자 · 사람 id · M1 흐름 순서 — 흑백은 서버 random() 이라 흐름은 매니페스트가 말한다). */
fun gomokuManifest(): JsonObject = fixtureJSON(GOMOKU_FIXTURES, "_manifest")

fun gomokuUser(key: String): String = gomokuManifest().obj("users")!!.str(key)!!

fun peerFor(id: String): GomokuUser =
    GomokuUser(id = id, displayName = "", avatarURL = null, characterID = null, isWorking = true, isCapable = true, inMatch = false)

/** 본문의 정수 칸(없으면 null). */
fun JsonObject.intField(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull
