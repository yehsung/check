// 원본: 없음 — 게임 화면 시험 조립(core/stores commonTest StoresTestKit 의 같은 꼴 — 시험 소스셋은 모듈 사이에서 나눌 수 없어 이 갈래 패키지에 둔다).
// 스텁 서버(가상 시간 MockEngine) · 로그인한 세션 스토어 · 게임 탭 문맥. 망은 쓰지 않는다(봉인 게이트 아래 — golden.invalid 는 MockEngine 이 받는다).
package com.yehsung.aingcheck.ui.games.minigame

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.games.GamesBoardGameLink
import com.yehsung.aingcheck.core.stores.games.GamesContext
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesGomokuLink
import com.yehsung.aingcheck.core.stores.games.GamesRouter
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/** 스텁 서버. 요청마다 [route] 가 응답(JSON 글자 · 상태)을 고른다. 모든 요청을 기록한다. */
@OptIn(ExperimentalCoroutinesApi::class)
class UiStubServer(scope: TestScope, private val route: (RecordedRequest) -> Pair<String, Int>?) {
    private val recorded = mutableListOf<RecordedRequest>()
    val requests: List<RecordedRequest> get() = recorded.toList()
    val unrouted = mutableListOf<RecordedRequest>()

    fun bodies(rpc: String): List<String> = recorded.filter { it.rpcName == rpc }.map { it.bodyText }

    fun count(rpc: String): Int = recorded.count { it.rpcName == rpc }

    val engine: MockEngine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val entry = RecordedRequest(
                    method = request.method.value,
                    path = request.url.encodedPath,
                    query = request.url.parameters.entries().flatMap { (k, vs) -> vs.map { k to it } },
                    // 본문 형식은 MockEngine 에서 머리가 아니라 본문 쪽에 실린다 — 요청 골든의 content-type 과 맞추려 머리로 옮겨 적는다.
                    headers = request.headers.entries().associate { it.key to it.value } +
                        (request.body.contentType?.let { mapOf("Content-Type" to listOf(it.toString())) } ?: emptyMap()),
                    bodyText = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: "",
                )
                recorded += entry
                val (body, status) = route(entry) ?: run {
                    unrouted += entry
                    """{"message":"unrouted ${entry.key}"}""" to 418
                }
                respond(body, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
            }
        },
    )

    fun service(clock: SessionClock): SupabaseWorkService = SupabaseWorkService(
        projectURL = "https://golden.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = { clock.now() },
        text = UiPlainTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )
}

object UiPlainTextRules : WireTextRules {
    override fun sanitized(raw: String): String = raw.trim()
    override fun hasVisibleContent(text: String): Boolean = text.any { !it.isWhitespace() }
    override fun statusMessageSanitized(raw: String): String = raw.trim()
}

class UiMemoryPrefs : KeyValueStore {
    val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

object UiFixtures {
    const val USER: String = "aaaaaaaa-0000-4000-8000-000000000001"
    val androidInfo: AppInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15")

    @OptIn(ExperimentalCoroutinesApi::class)
    fun clock(scope: TestScope): SessionClock = SessionClock {
        SwiftDate(SessionClock.demoInstant.timeIntervalSince1970 + scope.testScheduler.currentTime / 1000.0)
    }

    @OptIn(ExperimentalEncodingApi::class)
    fun jwt(exp: SwiftDate, subject: String = USER): String {
        fun b64(text: String) = Base64.Default.encode(text.encodeToByteArray()).replace('+', '-').replace('/', '_').trimEnd('=')
        return "hdr." + b64("""{"sub":"$subject","exp":${exp.timeIntervalSince1970.toLong()}}""") + ".sig"
    }

    /** 세션 바탕 요청(실행 복원 · 기기 등록 · 소속). */
    fun sessionRoute(r: RecordedRequest): Pair<String, Int>? = when {
        r.rpcName == "client_release" -> """{"status":"ok","platform":"android","min_build":1,"latest_build":3,"notes":null}""" to 200
        r.rpcName == "register_device_fcm" -> """{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":false,"feedback_reply":true}}""" to 200
        r.path == "/rest/v1/memberships" -> """[{"team_id":"team-1","role":"member","teams":{"name":"테스트팀","weekly_goal_hours":40}}]""" to 200
        else -> null
    }

    /** 미니게임 서버(토큰 t1, t2 … · 제출 ok · 순위 빈 표 · 공개). */
    fun miniGameRoute(r: RecordedRequest, tokens: () -> Int): Pair<String, Int>? = when {
        r.rpcName == "minigame_start_round" -> """{"status":"ok","token":"t${tokens()}"}""" to 200
        r.rpcName == "minigame_submit_score" -> """{"status":"ok","best_score":1,"plays":1,"improved":true}""" to 200
        r.rpcName == "minigame_board" -> "[]" to 200
        r.rpcName == "minigame_yesterday_winner" -> "[]" to 200
        r.path == "/rest/v1/profiles" && r.method == "GET" -> """[{"minigame_public":true}]""" to 200
        else -> null
    }
}

class UiFakeBoardGameLink : GamesBoardGameLink {
    override var activeMatchID: String? = null
    override var hasMatch: Boolean = false
    override var hasUnfinishedMatch: Boolean = false
    override var isAIMatch: Boolean = false
    override var isWindowVisible: Boolean = false
    override var presentWindow: (() -> Unit)? = null
    override fun openWindow(focusMatchID: String?) = Unit
    override fun windowDidShow() { isWindowVisible = true }
    override fun windowDidHide() { isWindowVisible = false }
    override fun windowDidClose() = Unit
    override fun windowOcclusionDidChange(visible: Boolean) = Unit
    override fun stopWatching() = Unit
    override suspend fun catchUp() = Unit
    override fun refreshLobbyIfStale() = Unit
}

class UiFakeGomokuLink(private val link: UiFakeBoardGameLink = UiFakeBoardGameLink()) : GamesGomokuLink, GamesBoardGameLink by link {
    override var pendingIncomingInviteCount: Int = 0
    override fun refreshInboxIfStale() = Unit
    override fun setAIThinkerAllowed(allowed: Boolean) = Unit
}

/**
 * 세션 스토어 한 벌 + 스텁 서버 + 게임 탭 문맥. 스토어의 부모 범위는 시험 디스패처 위의 **전경** 작업이다(advanceUntilIdle 이 기다린다).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class UiGamesHarness(val testScope: TestScope, appConfig: AppConfig = AppConfig(), route: (RecordedRequest) -> Pair<String, Int>?) {
    val server = UiStubServer(testScope) { r -> UiFixtures.sessionRoute(r) ?: route(r) }
    val clock: SessionClock = UiFixtures.clock(testScope)
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(testScope.coroutineContext.minusKey(Job) + storeJob)
    val vault = InMemoryTokenVault()
    val prefs = UiMemoryPrefs()
    val sessionStore = SessionStore(
        service = server.service(clock),
        vault = vault,
        prefs = prefs,
        appInfo = UiFixtures.androidInfo,
        installationIdentity = object : InstallationIdentity { override fun installationId(): String? = "11111111-2222-4333-8444-555555555555" },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() = Unit
        },
        parentScope = storeScope,
    )
    val tetrisHost = object : TetrisDuelStoreHost {
        override val session: SupabaseSession? get() = sessionStore.session
        override val sessionGeneration: Int get() = sessionStore.sessionGeneration
        override val service: SupabaseWorkService get() = sessionStore.service
        override var rubyBalance: Int? = null
        override val appConfig: AppConfig = appConfig
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = sessionStore.withSessionRetry(operation)
    }
    val tetris = TetrisDuelStore(host = tetrisHost, scope = storeScope, clock = { clock.now() }).also {
        it.gameLoopStepSeconds = Double.POSITIVE_INFINITY
        it.pollStepSeconds = Double.POSITIVE_INFINITY
    }
    val gomoku = UiFakeGomokuLink()
    val chess = UiFakeBoardGameLink()
    val presented = mutableListOf<GamesDestination>()

    val context: GamesContext = object : GamesContext {
        override val sessionStore: SessionStore get() = this@UiGamesHarness.sessionStore
        override val appConfig: AppConfig = appConfig
        override val scope: CoroutineScope get() = storeScope
        override val collation: Collation = StoreNaturalCollation
        override fun refreshAchievementsAfterGameResult(game: String) = Unit
        override val tetris: TetrisDuelStore get() = this@UiGamesHarness.tetris
        override val gomoku: GamesGomokuLink get() = this@UiGamesHarness.gomoku
        override val chess: GamesBoardGameLink get() = this@UiGamesHarness.chess
        override val router: GamesRouter = object : GamesRouter {
            override fun present(destination: GamesDestination) { presented += destination }
        }
        override val hiddenBlockedPeerIDs: Set<String> = emptySet()
        override val sharedRubyBalance: Int? = null
    }

    init {
        testScope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    /** 금고에 세션을 심고 실행 복원한다 → SignedIn. */
    suspend fun signIn() {
        vault.write(UiFixtures.jwt(clock.now().addingTimeInterval(3600.0)), SessionVaultKeys.accessToken)
        vault.write("r0", SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, UiFixtures.USER)
        prefs.putString(SessionPrefsKeys.email, "a@b.co")
        sessionStore.launch()
        testScope.advanceUntilIdle()
        check(sessionStore.phase == SessionPhase.SignedIn) { "로그인이 안 됐다: ${sessionStore.phase}" }
    }

    /** 스토어 일이 남지 않게 끝낸다(전경 작업이라 runTest 가 끝을 기다리지 않도록). */
    fun close() {
        storeJob.cancel()
    }
}

/** 골든 대본 연산 줄("n:연산 연산,…") → 프레임별 연산 목록(GoldenReplaySupport.decode 와 같은 꼴). */
object ScriptOps {
    fun decode(text: String): List<List<String>> {
        val frames = mutableListOf<List<String>>()
        if (text.isEmpty()) return frames
        for (chunk in text.split(',')) {
            val colon = chunk.indexOf(':')
            val count = chunk.substring(0, colon).toInt()
            val body = chunk.substring(colon + 1)
            val ops = if (body.isEmpty()) emptyList() else body.split(' ').filter { it.isNotEmpty() }
            repeat(count) { frames.add(ops) }
        }
        return frames
    }
}
