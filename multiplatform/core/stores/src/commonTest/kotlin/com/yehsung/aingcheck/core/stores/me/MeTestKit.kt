// 원본: Tests/CheckMobileKitTests/MeTestSupport.swift(나 탭 스토어 조립 · 스텁 서버 · 고정 시계) @ 1b8260d
// 나 탭 시험 도우미: 가상 시간 위의 스텁 서버(MockEngine 을 시험 디스패처에서 돌린다 — 문(Gate)·멈춤(Hang)이 runTest 시계를 본다).
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
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
import kotlinx.io.IOException
import kotlin.test.assertEquals

/** 스텁 응답 하나. */
sealed interface MeReply {
    data class Json(val body: String, val status: Int = 200) : MeReply

    /** 전송 실패(오프라인 · 끊김) — 결과를 모르는 실패다. */
    data object Offline : MeReply

    /** 응답하지 않는다(취소될 때까지). */
    data object Hang : MeReply

    /** 문이 열릴 때까지 기다렸다가 [then] 을 낸다(겹친 왕복 · 늦은 응답 재현). */
    class Gate(val gate: CompletableDeferred<Unit>, val then: MeReply) : MeReply

    companion object {
        fun fixture(path: String, status: Int = 200): MeReply = Json(RepoFiles.readText(path), status)
        val missingFunction: MeReply = Json("""{"code":"PGRST202","message":"Could not find the function in the schema cache"}""", 404)
        val serverDown: MeReply = Json("""{"message":"upstream"}""", 503)
    }
}

/** 스텁 서버 — 요청마다 [route] 를 불러 응답을 고르고 모두 기록한다. 경로 없는 요청은 418(시험 끝에 비어 있어야 한다). */
@OptIn(ExperimentalCoroutinesApi::class)
class MeStubServer(scope: TestScope, private val route: (RecordedRequest) -> MeReply?) {
    private val recorded = mutableListOf<RecordedRequest>()
    private val unroutedList = mutableListOf<RecordedRequest>()
    val requests: List<RecordedRequest> get() = recorded.toList()
    val unrouted: List<RecordedRequest> get() = unroutedList.toList()

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
                var reply: MeReply = route(entry) ?: run {
                    unroutedList += entry
                    MeReply.Json("""{"message":"unrouted ${entry.key}"}""", 418)
                }
                while (true) {
                    when (val r = reply) {
                        is MeReply.Gate -> {
                            r.gate.await()
                            reply = r.then
                        }
                        MeReply.Hang -> awaitCancellation()
                        MeReply.Offline -> throw IOException("offline")
                        is MeReply.Json -> return@addHandler respond(
                            r.body,
                            HttpStatusCode.fromValue(r.status),
                            headersOf(HttpHeaders.ContentType, "application/json"),
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
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )
}

class MeMemoryPrefs : KeyValueStore {
    val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

/** 바깥 고리 기록기(라우터 · 캐릭터 표 · 위젯 패널 · 순위 · 게임 화면). */
class RecordingMeLinks : MeLinks {
    val equipped = mutableListOf<String?>()
    val panels = mutableListOf<MeAILimitWidgetPanel>()
    val pushed = mutableListOf<MeDestination>()
    var poppedToRoot = 0
    val tokenPublic = mutableListOf<Boolean>()
    var matchScreenVisible = false

    override fun noteMyEquipped(serverID: String?) { equipped += serverID }
    override val isAnyMatchScreenVisible: Boolean get() = matchScreenVisible
    override fun noteAILimitPanel(panel: MeAILimitWidgetPanel) { panels += panel }
    override fun noteTokenUsagePublic(isPublic: Boolean) { tokenPublic += isPublic }
    override fun popMeToRoot() { poppedToRoot += 1 }
    override fun pushMe(destination: MeDestination) { pushed += destination }
}

object MeFixtures {
    /** 데모 기준 시각 2026-09-17 14:05:00 KST — 픽스처 server_now_ms(1789621500000)와 같은 순간. */
    const val DEMO_EPOCH: Double = 1_789_621_500.0
    const val ME = "Sources/CheckMobileKit/Demo/Fixtures/me"

    val androidInfo: AppInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15")

    /** 번들 초상이 다 있는 집합(상점 번호 4) — ui CharacterArt 가 싣는 열한 캐릭터. */
    val allPortraits: Set<String> = setOf(
        "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
        "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
    )

    fun fixture(name: String): String = RepoFiles.readText("$ME/$name")

    const val registerOK = """{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}"""
}

/**
 * 나 탭 스토어 한 벌 + 세션 스토어 + 스텁 서버. 스토어의 부모 스코프는 시험 디스패처 위의 **전경** 작업이다(`backgroundScope` 면
 * `advanceUntilIdle()` 이 띄운 일을 기다리지 않아 "요청 0" 이 거짓 초록이 된다).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MeHarness(
    val scope: TestScope,
    drawable: Set<String> = MeFixtures.allPortraits,
    /** 소속 응답(팀 목표가 기록에 쓰인다). */
    var membership: String = "[]",
    route: (RecordedRequest) -> MeReply?,
) {
    val server = MeStubServer(scope) { r -> sessionRoute(r) ?: route(r) }
    val clock: SessionClock = SessionClock { SwiftDate(MeFixtures.DEMO_EPOCH + scope.testScheduler.currentTime / 1000.0) }
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + storeJob)
    val prefs = MeMemoryPrefs()
    val links = RecordingMeLinks()
    val ruby = RubyBalanceCell()
    private var requestIDs = 0
    val sessionStore = SessionStore(
        service = server.service(clock),
        vault = InMemoryTokenVault(),
        prefs = prefs,
        appInfo = MeFixtures.androidInfo,
        installationIdentity = object : InstallationIdentity {
            override fun installationId(): String = "11111111-2222-4333-8444-555555555555"
        },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() {}
        },
        parentScope = storeScope,
        newCleanupID = { "cleanup-1" },
    )
    val context: MeContext = MeContext(sessionStore, AppConfig(), ruby, links)
    val store = MeStore(
        context = context,
        parentScope = storeScope,
        drawableCharacters = DrawableCharacterSource.of(drawable),
        computeContext = StandardTestDispatcher(scope.testScheduler),
        newRequestID = { "AAAAAAAA-0000-4000-8000-${(++requestIDs).toString().padStart(12, '0')}" },
    )

    init {
        scope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    private fun sessionRoute(r: RecordedRequest): MeReply? = when {
        r.rpcName == "register_device_fcm" -> MeReply.Json(MeFixtures.registerOK)
        r.method == "GET" && r.path == "/rest/v1/memberships" -> MeReply.Json(membership)
        r.rpcName == "unregister_device" -> MeReply.Json("""{"status":"ok","removed":true}""")
        r.path == "/auth/v1/logout" -> MeReply.Json("{}", 204)
        else -> null
    }

    /** 로그인(세션 스토어의 공통 마무리 — 기기 등록 · 소속 읽기가 함께 뜬다). */
    fun signIn(userID: String = "user-1") {
        sessionStore.adoptSignedInSession(SupabaseSession("tok-$userID", "ref-$userID", userID), "a@b.co")
    }

    /** 나 탭 요청만(세션 층 요청 — 기기 등록 · 소속 · 로그아웃 — 은 뺀다). */
    val meRequests: List<RecordedRequest>
        get() = server.requests.filter { sessionRoute(it) == null }

    /** 끝 단언 둘: 모르는 요청 0 · 폰 금지 호출 0. */
    fun assertClean() {
        assertEquals(emptyList(), server.unrouted.map { it.key }, "경로 없는 요청")
        assertEquals(emptyList(), PhoneForbiddenCalls.violations(server.requests), "폰 금지 호출")
    }
}
