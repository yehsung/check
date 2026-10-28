// 원본: 없음 — 게임 스토어 시험 조립(W2-a core/session 시험 도우미 SessionTestKit·SessionHarness 와 같은 꼴 — 시험 소스셋은 모듈 사이에서
// 나눌 수 없어 이 갈래 패키지에 둔다). Swift 쪽 짝은 Tests/CheckMobileKitTests/GamesTestSupport.swift(스텁 서버 · 폰 세션).
package com.yehsung.aingcheck.core.stores.games

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
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.testkit.mock.PhoneForbiddenCalls
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.io.IOException
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.test.assertEquals

/** 스텁 응답 하나. */
sealed interface Reply {
    data class Json(val body: String, val status: Int = 200) : Reply

    /** 전송 실패(오프라인 · 끊김) — 서비스는 일시 오류로 접어야 한다. */
    data object Offline : Reply

    /** 응답하지 않는다(취소될 때까지). */
    data object Hang : Reply

    /** 문이 열릴 때까지 기다렸다가 [then] 을 낸다(합류 · 늦은 응답 재현). */
    class Gate(val gate: CompletableDeferred<Unit>, val then: Reply) : Reply

    companion object {
        val pgrst202: Reply = Json("""{"code":"PGRST202","message":"Could not find the function in the schema cache"}""", 404)
        val serverDown: Reply = Json("""{"message":"upstream"}""", 503)
        val notFound404: Reply = Json("", 404)
    }
}

/** 스텁 서버. 요청마다 [route] 를 불러 응답을 고른다. 모든 요청을 기록한다. MockEngine 은 **시험 디스패처**에서 돈다(가상 시간). */
@OptIn(ExperimentalCoroutinesApi::class)
class StubServer(scope: TestScope, private val route: (RecordedRequest) -> Reply?) {
    private val recorded = mutableListOf<RecordedRequest>()
    private val unroutedList = mutableListOf<RecordedRequest>()
    val requests: List<RecordedRequest> get() = recorded.toList()
    val unrouted: List<RecordedRequest> get() = unroutedList.toList()

    /** RPC 이름 열(시험 단언용). */
    fun rpcs(): List<String> = recorded.mapNotNull { it.rpcName }

    fun count(rpc: String): Int = recorded.count { it.rpcName == rpc }

    fun bodies(rpc: String): List<String> = recorded.filter { it.rpcName == rpc }.map { it.bodyText }

    val engine: MockEngine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val entry = RecordedRequest(
                    method = request.method.value,
                    path = request.url.encodedPath,
                    query = request.url.parameters.entries().flatMap { (k, vs) -> vs.map { k to it } },
                    headers = request.headers.entries().associate { it.key to it.value },
                    bodyText = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: "",
                )
                recorded += entry
                var reply: Reply = route(entry) ?: run {
                    unroutedList += entry
                    Reply.Json("""{"message":"unrouted ${entry.key}"}""", 418)
                }
                while (true) {
                    when (val r = reply) {
                        is Reply.Gate -> {
                            r.gate.await()
                            reply = r.then
                        }
                        Reply.Hang -> awaitCancellation()
                        Reply.Offline -> throw IOException("offline")
                        is Reply.Json -> return@addHandler respond(
                            r.body, HttpStatusCode.fromValue(r.status), headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                }
                @Suppress("UNREACHABLE_CODE")
                error("unreachable")
            }
        },
    )

    fun service(clock: SessionClock): SupabaseWorkService = SupabaseWorkService(
        projectURL = "https://golden.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = { clock.now() },
        text = PlainTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )
}

object PlainTextRules : WireTextRules {
    override fun sanitized(raw: String): String = raw.trim()
    override fun hasVisibleContent(text: String): Boolean = text.any { !it.isWhitespace() }
    override fun statusMessageSanitized(raw: String): String = raw.trim()
}

class MemoryPrefs : KeyValueStore {
    val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

class FixedInstallation(private val id: String?) : InstallationIdentity {
    override fun installationId(): String? = id
}

class GrantingGuard : SingleInstanceGuard {
    override fun tryAcquire(): Boolean = true
    override fun release() = Unit
}

object StoreFixtures {
    const val USER: String = "aaaaaaaa-0000-4000-8000-000000000001"
    const val PEER: String = "bbbbbbbb-0000-4000-8000-000000000002"
    const val OTHER: String = "cccccccc-0000-4000-8000-000000000003"

    val androidInfo: AppInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15")

    /** 데모 기준 시각(2026-09-17 14:05 KST)에서 가상 시간만큼 간 시계. */
    @OptIn(ExperimentalCoroutinesApi::class)
    fun clock(scope: TestScope): SessionClock = SessionClock {
        SwiftDate(SessionClock.demoInstant.timeIntervalSince1970 + scope.testScheduler.currentTime / 1000.0)
    }

    /** exp 가 [exp] 인 가짜 JWT(서명 검증 없음 — 세션은 exp 만 읽는다). 진짜 JWT 머리가 아니게 머리를 바꿔 둔다. */
    @OptIn(ExperimentalEncodingApi::class)
    fun jwt(exp: SwiftDate, subject: String = USER): String {
        fun b64(text: String) = Base64.Default.encode(text.encodeToByteArray()).replace('+', '-').replace('/', '_').trimEnd('=')
        return "hdr." + b64("""{"sub":"$subject","exp":${exp.timeIntervalSince1970.toLong()}}""") + ".sig"
    }

    val releaseOK: Reply = Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":3,"notes":null}""")
    val registerOK: Reply = Reply.Json("""{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":false,"feedback_reply":true}}""")
    val membershipOK: Reply = Reply.Json("""[{"team_id":"team-1","role":"member","teams":{"name":"테스트팀","weekly_goal_hours":40}}]""")
}

/** 세션 바탕 요청(실행 복원 · 기기 등록 · 소속) — 시험의 경로표 앞에 붙는다. */
fun sessionRoutes(r: RecordedRequest): Reply? = when {
    r.rpcName == "client_release" -> StoreFixtures.releaseOK
    r.rpcName == "register_device_fcm" -> StoreFixtures.registerOK
    r.path == "/rest/v1/memberships" -> StoreFixtures.membershipOK
    else -> null
}

/** 세션 바탕 RPC 이름(시험이 게임 요청만 셀 때 뺀다). */
val SESSION_RPCS: Set<String> = setOf("client_release", "register_device_fcm")

/** 테트리스 호스트(시험용 — 조립 지점이 세션 스토어 + 루비 미러 + 앱 구성으로 만드는 것과 같은 꼴). */
class TestTetrisHost(private val store: SessionStore, override val appConfig: AppConfig) : TetrisDuelStoreHost {
    override val session: SupabaseSession? get() = store.session
    override val sessionGeneration: Int get() = store.sessionGeneration
    override val service: SupabaseWorkService get() = store.service
    override var rubyBalance: Int? = null
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = store.withSessionRetry(operation)
}

/** 오목·체스 문의 가짜(W2-d 스토어 자리). 부른 문을 순서대로 적는다. */
open class FakeBoardGameLink(val name: String) : GamesBoardGameLink {
    val calls = mutableListOf<String>()
    override var activeMatchID: String? = null
    override var hasMatch: Boolean = false
    override var hasUnfinishedMatch: Boolean = false
    override var isAIMatch: Boolean = false
    override var isWindowVisible: Boolean = false
    override var presentWindow: (() -> Unit)? = null
    override fun openWindow(focusMatchID: String?) { calls += "openWindow(${focusMatchID ?: "-"})" }
    override fun windowDidShow() { calls += "windowDidShow"; isWindowVisible = true }
    override fun windowDidHide() { calls += "windowDidHide"; isWindowVisible = false }
    override fun windowDidClose() { calls += "windowDidClose" }
    override fun windowOcclusionDidChange(visible: Boolean) { calls += "occlusion($visible)" }
    override fun stopWatching() { calls += "stopWatching" }
    override suspend fun catchUp() { calls += "catchUp" }
    override fun refreshLobbyIfStale() { calls += "refreshLobbyIfStale" }

    /** 진행 중인 사람 판을 든다(끝남이면 끝난 판). */
    fun holdMatch(finished: Boolean = false, ai: Boolean = false) {
        hasMatch = true
        hasUnfinishedMatch = !finished
        isAIMatch = ai
    }
}

class FakeGomokuLink : FakeBoardGameLink("gomoku"), GamesGomokuLink {
    override var pendingIncomingInviteCount: Int = 0
    var aiAllowed: Boolean? = null
    override fun refreshInboxIfStale() { calls += "refreshInboxIfStale" }
    override fun setAIThinkerAllowed(allowed: Boolean) { aiAllowed = allowed }
}

class FakeRouter : GamesRouter {
    val presented = mutableListOf<GamesDestination>()
    override fun present(destination: GamesDestination) { presented += destination }
}

/**
 * 세션 스토어 한 벌 + 스텁 서버 + 게임 탭 문맥. 세션은 금고에 심은 토큰으로 실행 복원한다([signIn]).
 * 스토어의 부모 스코프는 시험 디스패처 위의 **전경** 작업이다(`advanceUntilIdle()` 이 기다린다). 끝나면 backgroundScope 와 함께 닫는다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StoreHarness(
    val testScope: TestScope,
    appConfig: AppConfig = AppConfig(),
    val prefs: MemoryPrefs = MemoryPrefs(),
    route: (RecordedRequest) -> Reply?,
) {
    val server = StubServer(testScope) { r -> sessionRoutes(r) ?: route(r) }
    val clock: SessionClock = StoreFixtures.clock(testScope)
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(testScope.coroutineContext.minusKey(Job) + storeJob)
    val vault = InMemoryTokenVault()
    val sessionStore = SessionStore(
        service = server.service(clock),
        vault = vault,
        prefs = prefs,
        appInfo = StoreFixtures.androidInfo,
        installationIdentity = FixedInstallation("11111111-2222-4333-8444-555555555555"),
        clock = clock,
        instanceGuard = GrantingGuard(),
        parentScope = storeScope,
    )
    val tetrisHost = TestTetrisHost(sessionStore, appConfig)
    val tetris = TetrisDuelStore(host = tetrisHost, scope = storeScope, clock = { clock.now() }).also {
        // 판 루프·폴링은 재운다(시험이 tick·pollTick 을 직접 부른다) — `delay(Long.MAX_VALUE)` 는 가상 시간 예약을 안 만든다.
        it.gameLoopStepSeconds = Double.POSITIVE_INFINITY
        it.pollStepSeconds = Double.POSITIVE_INFINITY
    }
    val gomoku = FakeGomokuLink()
    val chess = FakeBoardGameLink("chess")
    val router = FakeRouter()
    val achievementRefreshes = mutableListOf<String>()
    var hiddenBlocked: Set<String> = emptySet()
    var sharedRuby: Int? = null

    val context: GamesContext = object : GamesContext {
        override val sessionStore: SessionStore get() = this@StoreHarness.sessionStore
        override val appConfig: AppConfig = appConfig
        override val scope: CoroutineScope get() = storeScope
        override val collation: Collation = StoreNaturalCollation
        override fun refreshAchievementsAfterGameResult(game: String) { achievementRefreshes += game }
        override val tetris: TetrisDuelStore get() = this@StoreHarness.tetris
        override val gomoku: GamesGomokuLink get() = this@StoreHarness.gomoku
        override val chess: GamesBoardGameLink get() = this@StoreHarness.chess
        override val router: GamesRouter get() = this@StoreHarness.router
        override val hiddenBlockedPeerIDs: Set<String> get() = hiddenBlocked
        override val sharedRubyBalance: Int? get() = sharedRuby
    }

    init {
        testScope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    /** 금고에 세션을 심고 실행 복원한다 → SignedIn. 세션 바탕 요청은 [gameRequests] 에서 빠진다. */
    suspend fun signIn() {
        vault.write(StoreFixtures.jwt(clock.now().addingTimeInterval(3600.0)), SessionVaultKeys.accessToken)
        vault.write("r0", SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, StoreFixtures.USER)
        prefs.putString(SessionPrefsKeys.email, "a@b.co")
        sessionStore.launch()
        testScope.advanceUntilIdle()
        check(sessionStore.phase == SessionPhase.SignedIn) { "로그인이 안 됐다: ${sessionStore.phase}" }
    }

    /** 세션 바탕 밖의 RPC 이름 열. */
    fun gameRpcs(): List<String> = server.rpcs().filter { it !in SESSION_RPCS }

    /** 끝 단언 둘: 모르는 요청 0 · 폰 금지 호출 0(C§4 #13). */
    fun assertClean() {
        assertEquals(emptyList(), server.unrouted.map { it.key }, "경로 없는 요청")
        assertEquals(emptyList(), PhoneForbiddenCalls.violations(server.requests), "폰 금지 호출")
    }
}
