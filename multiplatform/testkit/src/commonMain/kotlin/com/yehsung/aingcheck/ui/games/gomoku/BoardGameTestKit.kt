// 원본: 없음 — 오목·체스 화면 시험 조립(시험 소스셋은 모듈 사이에서 나눌 수 없어 core/stores 의 DuelTestKit·StoresTestKit 과 같은 꼴을 이 갈래 패키지에 둔다).
//
// 스텁 서버는 rpc 이름마다 큐(또는 처리기)를 두고 호출 순서대로 돌려준다. 큐 밖의 호출은 500(스토어의 실패 경로 — 화면이 안 바뀐다). 픽스처
// `Tests/checkTests/Fixtures/{gomoku,chess}-rpc/*.json` 은 로컬 하네스에서 RPC 를 실제로 부른 jsonb 출력 그대로다(제자리에서 읽는다 — 복사 0).
// MockEngine 은 시험 스케줄러 위에서 돈다(가상 시간) — 화면 시험은 클릭 뒤 [BoardGameRig.settle] 로 스토어 일을 돌린다.
// 공용 패치 13: ui commonTest 에서 testkit 으로 옮겼다(FQN 그대로). 조립 클래스 BoardGameRig 는 ui main 어댑터를 잇는 몫이라 ui 시험(BoardGameRig.kt)에 남았다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesBoardGameLink
import com.yehsung.aingcheck.core.stores.games.GamesContext
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesGomokuLink
import com.yehsung.aingcheck.core.stores.games.GamesRouter
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull

/** 받은 요청 하나. */
data class RpcCall(val rpc: String, val body: JsonObject) {
    fun long(key: String): Long? = (body[key] as? JsonPrimitive)?.longOrNull
    fun str(key: String): String? = (body[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
}

/** rpc 별 큐 · 처리기 스텁 서버(DuelStubServer 의 화면 시험판). */
@OptIn(ExperimentalCoroutinesApi::class)
class RpcStub(scope: TestScope) {
    private val queues = LinkedHashMap<String, ArrayDeque<String>>()
    private val handlers = LinkedHashMap<String, (JsonObject, Int) -> String?>()
    private val counters = HashMap<String, Int>()
    private val recorded = mutableListOf<RpcCall>()
    val calls: List<RpcCall> get() = recorded.toList()

    fun queueFixtures(rpc: String, directory: String, vararg names: String): RpcStub {
        queues.getOrPut(rpc) { ArrayDeque() }.addAll(names.map { fixtureText(directory, it) })
        return this
    }

    fun queueJson(rpc: String, vararg bodies: String): RpcStub {
        queues.getOrPut(rpc) { ArrayDeque() }.addAll(bodies)
        return this
    }

    /** 본문과 호출 순번(0부터)으로 답한다 — 큐보다 먼저. null 이면 큐. */
    fun respondWith(rpc: String, handler: (JsonObject, Int) -> String?): RpcStub {
        handlers[rpc] = handler
        return this
    }

    fun count(rpc: String): Int = recorded.count { it.rpc == rpc }
    fun last(rpc: String): RpcCall = recorded.last { it.rpc == rpc }

    val engine: MockEngine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val rpc = request.url.encodedPath.removePrefix("/rest/v1/rpc/")
                val text = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
                val body = if (text.isBlank()) JsonObject(emptyMap()) else Json.parseToJsonElement(text).jsonObject
                recorded += RpcCall(rpc, body)
                val index = counters[rpc] ?: 0
                counters[rpc] = index + 1
                val reply = handlers[rpc]?.invoke(body, index) ?: queues[rpc]?.removeFirstOrNull()
                if (reply == null) {
                    respond("""{"message":"not scripted"}""", HttpStatusCode.InternalServerError, headersOf(HttpHeaders.ContentType, "application/json"))
                } else {
                    respond(reply, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
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

/** 대결 스토어 호스트(시험 — 세션 몫 + 루비 미러 + 앱 구성). [me] 가 null 이면 세션이 없다(서버 호출 0 — 스냅숏이 쓴다). */
class FakeBoardHost(
    override val service: SupabaseWorkService,
    me: String?,
    override var appConfig: AppConfig,
    private val clockNow: () -> SwiftDate,
) : GomokuStoreHost {
    override var session: SupabaseSession? = me?.let { SupabaseSession("access-token", null, it) }
    override var sessionGeneration: Int = 0
    override var realtimeState: RealtimeState = RealtimeState.Idle(IdleReason.disabled)
    override var rubyBalance: Long? = null
    override fun now(): SwiftDate = clockNow()
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(session ?: throw SupabaseWorkServiceError.SessionExpired)
}

class MapPrefs : KeyValueStore {
    private val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

class RecordingRouter : GamesRouter {
    val presented = mutableListOf<GamesDestination>()
    override fun present(destination: GamesDestination) { presented += destination }
}

/** Swift 계약 시험의 고정 시계(1_900_000_000 = 2030-03-17). 픽스처는 과거에 떴다 — 마감은 server_now_ms 차이로 보정된다. */
val boardClock: SwiftDate = SwiftDate(1_900_000_000.0)

const val GOMOKU_FIXTURES: String = "Tests/checkTests/Fixtures/gomoku-rpc"
const val CHESS_FIXTURES: String = "Tests/checkTests/Fixtures/chess-rpc"

fun fixtureText(directory: String, name: String): String = RepoFiles.readText("$directory/$name.json")

fun fixtureJSON(directory: String, name: String): JsonObject = Json.parseToJsonElement(fixtureText(directory, name)).jsonObject



const val HAND_ME: String = "00000000-0000-0000-0000-0000000000a1"
const val HAND_RIVAL: String = "00000000-0000-0000-0000-0000000000b2"
const val HAND_MATCH: String = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

/**
 * gomoku_state 의 ok 묶음(손으로 짠 것 — core/stores DuelTestKit.handState 와 같은 꼴). 나는 [HAND_ME], 상대는 [HAND_RIVAL]. [board] 는 225칸 글자
 * (없으면 빈 판), 돌은 [stones] 로 얹는다(x, y, 'b'|'w').
 */
fun handGomokuState(
    myColor: String = "black",
    turn: String? = "black",
    moveCount: Int = 0,
    finished: Boolean = false,
    result: String? = null,
    endReason: String? = null,
    stones: List<Triple<Int, Int, Char>> = emptyList(),
    stake: Int = 5,
    deadlineMs: Long? = null,
    serverNowMs: Long? = null,
    opponentName: String = "라이벌",
    watchers: Int? = null,
): com.yehsung.aingcheck.core.wire.games.GomokuStatePayload {
    val cells = CharArray(225) { '.' }
    for ((x, y, c) in stones) cells[y * 15 + x] = c
    fun q(v: String?) = if (v == null) "null" else "\"$v\""
    val black = if (myColor == "black") HAND_ME else HAND_RIVAL
    val white = if (myColor == "black") HAND_RIVAL else HAND_ME
    val json = """
        {"status":"ok","match":{"id":"$HAND_MATCH","status":"${if (finished) "finished" else "active"}","stake":$stake,"black":"$black","white":"$white",
        "challenger":"$HAND_RIVAL","opponent":"$HAND_ME","move_count":$moveCount,"turn":${q(if (finished) null else turn)},"board":"${String(cells)}",
        "deadline_ms":${deadlineMs ?: "null"},"result":${q(result)},"end_reason":${q(endReason)},"winner":null,"invite_expires_ms":null,"finished_ms":null},
        "moves":[],"my_color":"$myColor","opponent":{"user_id":"$HAND_RIVAL","display_name":"$opponentName","avatar_url":null,"character":"aing"},
        "ruby_balance":null,"server_now_ms":${serverNowMs ?: "null"}${if (watchers != null) ",\"watchers\":$watchers" else ""}}
    """.trimIndent()
    return com.yehsung.aingcheck.core.wire.json.SwiftJson.decode(com.yehsung.aingcheck.core.wire.games.GomokuStatePayload.serializer(), json)
}
