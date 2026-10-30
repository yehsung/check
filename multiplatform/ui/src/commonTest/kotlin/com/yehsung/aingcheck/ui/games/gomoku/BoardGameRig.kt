// 원본: 없음 — 오목·체스 화면 시험 조립(BoardGameRig)의 ui 몫. 공용 패치 13 때 이 파일의 나머지(RpcStub·FakeBoardHost·픽스처·손 상태)는
// testkit(같은 FQN)으로 옮겼고, 이 클래스만 남겼다: 게임 문맥이 ui main 의 화면 갈래 어댑터(GomokuGamesLink · ChessGamesLink)를 잇는다 —
// testkit 은 ui main 을 보지 않는다(공용 패치 7 의 galleryArt 와 같은 갈래).
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
import com.yehsung.aingcheck.ui.games.chess.ChessGamesLink
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

/**
 * 게임 탭 스토어 + 오목·체스 스토어 + 스텁 서버 한 벌. 스토어 범위는 [testScope] 의 스케줄러 위(가상 시간 — 클릭 뒤 [settle]).
 * 오목·체스 문은 **화면 갈래 어댑터**(GomokuGamesLink · ChessGamesLink)로 잇는다 — 조립이 쓸 바로 그 길이다(assembly.md).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BoardGameRig(
    me: String? = null,
    duelsEnabled: Boolean = true,
    configure: RpcStub.() -> Unit = {},
) {
    val testScope = TestScope()
    val server = RpcStub(testScope).apply(configure)
    /** 고정 시각 + 가상 시간(폴링 문턱은 스토어 시계로 잰다 — 시계가 서 있으면 폴링 한 걸음이 영영 안 찬다). */
    val clock: () -> SwiftDate = { boardClock.addingTimeInterval(testScope.testScheduler.currentTime / 1000.0) }
    val appConfig = AppConfig(duelsEnabled = duelsEnabled)
    val service = server.service(clock)
    val host = FakeBoardHost(service, me, appConfig, clock)
    val scope: CoroutineScope = CoroutineScope(testScope.coroutineContext + SupervisorJob())
    val gomoku = GomokuStore(scope, host).also { it.clock = clock }
    val chess = ChessStore(scope, host).also { it.clock = clock }
    val sessionStore = SessionStore(
        service = service,
        vault = InMemoryTokenVault(),
        prefs = MapPrefs(),
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15"),
        installationIdentity = object : InstallationIdentity { override fun installationId(): String? = "11111111-2222-4333-8444-555555555555" },
        clock = SessionClock { clock() },
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() = Unit
        },
        parentScope = scope,
    )
    val tetrisHost = object : TetrisDuelStoreHost {
        override val session: SupabaseSession? get() = host.session
        override val sessionGeneration: Int get() = host.sessionGeneration
        override val service: SupabaseWorkService get() = this@BoardGameRig.service
        override var rubyBalance: Long? = null
        override val appConfig: AppConfig get() = this@BoardGameRig.appConfig
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = host.withSessionRetry(operation)
    }
    val tetris = TetrisDuelStore(host = tetrisHost, scope = scope, clock = clock).also {
        it.gameLoopStepSeconds = Double.POSITIVE_INFINITY
        it.pollStepSeconds = Double.POSITIVE_INFINITY
    }
    val gomokuLink = GomokuGamesLink(gomoku)
    val chessLink = ChessGamesLink(chess)
    val router = RecordingRouter()
    /** 메시지 탭 차단 목록(앱에서는 메시지 스토어의 관찰 상태 — 바꾸면 화면이 다시 그린다). */
    var hiddenBlocked: Set<String> by mutableStateOf(emptySet())
    var sharedRuby: Long? = 100

    val context: GamesContext = object : GamesContext {
        override val sessionStore: SessionStore get() = this@BoardGameRig.sessionStore
        override val appConfig: AppConfig get() = this@BoardGameRig.appConfig
        override val scope: CoroutineScope get() = this@BoardGameRig.scope
        override val collation: Collation = StoreNaturalCollation
        override fun refreshAchievementsAfterGameResult(game: String) = Unit
        override val tetris: TetrisDuelStore get() = this@BoardGameRig.tetris
        override val gomoku: GamesGomokuLink get() = gomokuLink
        override val chess: GamesBoardGameLink get() = chessLink
        override val router: GamesRouter get() = this@BoardGameRig.router
        override val hiddenBlockedPeerIDs: Set<String> get() = hiddenBlocked
        override val sharedRubyBalance: Long? get() = sharedRuby
    }
    val games = GamesStore(context)

    /** 지금 시각에 걸린 스토어 일을 다 돌린다(지연 작업 — 폴링 · 만료 — 은 돌리지 않는다). */
    fun settle() = testScope.testScheduler.runCurrent()

    /** 가상 시간을 [seconds] 만큼 흘린다(폴링 한 걸음 등). */
    fun advance(seconds: Double) = testScope.testScheduler.advanceTimeBy((seconds * 1000).toLong())

    fun close() = testScope.cancel()
}

private fun TestScope.cancel() = this.coroutineContext[kotlinx.coroutines.Job]?.cancel()
