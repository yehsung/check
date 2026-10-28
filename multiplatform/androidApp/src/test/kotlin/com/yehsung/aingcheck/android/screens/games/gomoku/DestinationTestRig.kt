// 원본: 없음 — 오목·체스 목적지(Android 진입 함수) 시험의 스토어 한 벌. 서버는 **부르지 않는다**: 스토어 범위의 디스패처가 일을 받아 두기만 하고
// 돌리지 않는다(조회·폴링 0건 — 이 시험은 뒤로가기 배선만 잰다). 엔진도 부르면 터지는 것을 꽂는다(실서버 엔진 금지 — 구조 규칙 R3).
package com.yehsung.aingcheck.android.screens.games.gomoku

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
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
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.GomokuStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.chess.ChessGamesLink
import com.yehsung.aingcheck.ui.games.gomoku.GomokuGamesLink
import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngineBase
import io.ktor.client.engine.HttpClientEngineConfig
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.HttpResponseData
import io.ktor.utils.io.InternalAPI
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import java.io.File
import kotlin.coroutines.CoroutineContext

/** 받은 일을 쌓아 두기만 하는 디스패처 — 스토어가 띄운 조회·폴링이 한 줄도 돌지 않는다(쌓인 수는 [parked]). */
class ParkingDispatcher : CoroutineDispatcher() {
    val parked = ArrayDeque<Runnable>()
    override fun dispatch(context: CoroutineContext, block: Runnable) { parked += block }
}

/** 부르면 터지는 엔진 — 이 시험에서 서버 호출은 결함이다. */
private class RefusingEngine : HttpClientEngineBase("aingcheck-refusing") {
    override val config: HttpClientEngineConfig = HttpClientEngineConfig()

    @InternalAPI
    override suspend fun execute(data: HttpRequestData): HttpResponseData = error("목적지 시험은 서버를 부르지 않는다: ${data.url}")
}

val destinationClock: SwiftDate = SwiftDate(1_900_000_000.0)
const val DEST_ME: String = "00000000-0000-0000-0000-0000000000a1"
const val DEST_RIVAL: String = "00000000-0000-0000-0000-0000000000b2"
const val DEST_MATCH: String = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

/** 오목·체스 스토어 + 게임 탭 스토어 한 벌. [me] 가 null 이면 세션이 없다. */
class DestinationTestRig(me: String?) {
    val dispatcher = ParkingDispatcher()
    val scope = CoroutineScope(dispatcher + SupervisorJob())
    private val clock: () -> SwiftDate = { destinationClock }
    val appConfig = AppConfig(duelsEnabled = true)
    val service = SupabaseWorkService(
        projectURL = "https://golden.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(RefusingEngine()) { SupabaseWorkService.clientConfig(this) },
        clock = clock,
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )
    val host = object : GomokuStoreHost {
        override val service: SupabaseWorkService get() = this@DestinationTestRig.service
        override var session: SupabaseSession? = me?.let { SupabaseSession("access-token", null, it) }
        override var sessionGeneration: Int = 0
        override var realtimeState: RealtimeState = RealtimeState.Idle(IdleReason.disabled)
        override var rubyBalance: Long? = null
        override var appConfig: AppConfig = this@DestinationTestRig.appConfig
        override fun now(): SwiftDate = clock()
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
            operation(session ?: throw SupabaseWorkServiceError.SessionExpired)
    }
    val gomoku = com.yehsung.aingcheck.core.stores.gomoku.GomokuStore(scope, host).also {
        it.clock = clock
        it.spectatorFeaturesEnabled = true
    }
    val chess = ChessStore(scope, host).also {
        it.clock = clock
        it.spectatorFeaturesEnabled = true
    }
    private val prefs = object : KeyValueStore {
        private val values = LinkedHashMap<String, Any>()
        override fun getString(key: String): String? = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String): Long? = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }
    private val vault = object : TokenVault {
        private val values = HashMap<String, String>()
        override fun read(key: String): String? = values[key]
        override fun write(value: String, key: String) { values[key] = value }
        override fun delete(key: String) { values.remove(key) }
    }
    val sessionStore = SessionStore(
        service = service,
        vault = vault,
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15"),
        installationIdentity = object : InstallationIdentity { override fun installationId(): String? = "11111111-2222-4333-8444-555555555555" },
        clock = SessionClock { clock() },
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() = Unit
        },
        parentScope = scope,
    )
    private val tetrisHost = object : TetrisDuelStoreHost {
        override val session: SupabaseSession? get() = host.session
        override val sessionGeneration: Int get() = host.sessionGeneration
        override val service: SupabaseWorkService get() = this@DestinationTestRig.service
        override var rubyBalance: Int? = null
        override val appConfig: AppConfig get() = this@DestinationTestRig.appConfig
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = host.withSessionRetry(operation)
    }
    val tetris = TetrisDuelStore(host = tetrisHost, scope = scope, clock = clock)
    val presented = mutableListOf<GamesDestination>()
    val context: GamesContext = object : GamesContext {
        override val sessionStore: SessionStore get() = this@DestinationTestRig.sessionStore
        override val appConfig: AppConfig get() = this@DestinationTestRig.appConfig
        override val scope: CoroutineScope get() = this@DestinationTestRig.scope
        override val collation: Collation = StoreNaturalCollation
        override fun refreshAchievementsAfterGameResult(game: String) = Unit
        override val tetris: TetrisDuelStore get() = this@DestinationTestRig.tetris
        override val gomoku: GamesGomokuLink = GomokuGamesLink(this@DestinationTestRig.gomoku)
        override val chess: GamesBoardGameLink = ChessGamesLink(this@DestinationTestRig.chess)
        override val router: GamesRouter = object : GamesRouter {
            override fun present(destination: GamesDestination) { presented += destination }
        }
        override val hiddenBlockedPeerIDs: Set<String> get() = emptySet()
        override val sharedRubyBalance: Int? get() = 100
    }
    val games = GamesStore(context)
}

/** 사람과의 오목 판(흑 = 나, 내 차례, 4수) — gomoku_state ok 묶음을 손으로 짠다. [finished] 면 끝난 판. */
fun destinationGomokuState(finished: Boolean = false): GomokuStatePayload {
    val cells = CharArray(225) { '.' }
    for ((x, y, c) in listOf(Triple(7, 7, 'b'), Triple(8, 8, 'w'), Triple(6, 7, 'b'), Triple(9, 9, 'w'))) cells[y * 15 + x] = c
    val now = 1_900_000_000_000L
    val json = """
        {"status":"ok","match":{"id":"$DEST_MATCH","status":"${if (finished) "finished" else "active"}","stake":5,"black":"$DEST_ME","white":"$DEST_RIVAL",
        "challenger":"$DEST_RIVAL","opponent":"$DEST_ME","move_count":4,"turn":${if (finished) "null" else "\"black\""},"board":"${String(cells)}",
        "deadline_ms":${now + 25_000},"result":${if (finished) "\"black\"" else "null"},"end_reason":${if (finished) "\"resign\"" else "null"},"winner":null,
        "invite_expires_ms":null,"finished_ms":null},
        "moves":[],"my_color":"black","opponent":{"user_id":"$DEST_RIVAL","display_name":"라이벌","avatar_url":null,"character":"aing"},
        "ruby_balance":null,"server_now_ms":$now}
    """.trimIndent()
    return SwiftJson.decode(GomokuStatePayload.serializer(), json)
}

/** 저장소의 실서버 픽스처 한 장(시험 작업 디렉터리 = androidApp 모듈 → 저장소 뿌리는 두 칸 위). */
fun repoFixture(path: String): String {
    var dir: File? = File("").absoluteFile
    while (dir != null && !File(dir, "Tests/checkTests/Fixtures").isDirectory) dir = dir.parentFile
    return File(requireNotNull(dir) { "저장소 뿌리를 못 찾았다" }, path).readText()
}
