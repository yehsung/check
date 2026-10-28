// 원본: 없음 — 스토어 시험 조립(W2-a core/session 시험의 SessionHarness·StubServer 를 본떴다 — 그 파일은 다른 모듈의 시험 소스라 볼 수 없다).
// Swift 짝: Tests/CheckMobileKitTests/MessagesTestSupport.swift · NowTestSupport.swift(스텁 서버 + 로그인한 앱 문맥) @ 1b8260d
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.wire.SwiftDate
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

    /** 전송 실패(오프라인 · 끊김) — 서비스는 일시 오류(전송)로 접는다. */
    data object Offline : Reply

    /** 문이 열릴 때까지 기다렸다가 [then] 을 낸다(늦은 응답 · 겹침 재현). */
    class Gate(val gate: CompletableDeferred<Unit>, val then: Reply) : Reply

    companion object {
        /** PostgREST 가 함수를 못 찾을 때(PGRST202 · 404) — 서버가 준비 안 된 응답. */
        val missingFunction: Reply = Json("""{"code":"PGRST202","message":"Could not find the function in the schema cache"}""", 404)
        val serverDown: Reply = Json("""{"message":"upstream"}""", 503)
    }
}

/**
 * 스텁 서버. 요청마다 [route] 를 불러 응답을 고른다. 모든 요청을 기록한다. MockEngine 은 **시험 디스패처**에서 돈다 — 병렬 요청(요약 + 이력)이
 * 한 스레드에서 차례로 기록되고(기록 목록 경합 없음 — W2-a 지적의 WireRequestsGoldenTest 간헐 빨강 자리), [Reply.Gate] 가 가상 시계를 본다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StubServer(scope: TestScope, var route: (RecordedRequest) -> Reply?) {
    private val recorded = mutableListOf<RecordedRequest>()
    private val unroutedList = mutableListOf<RecordedRequest>()
    val requests: List<RecordedRequest> get() = recorded.toList()
    val unrouted: List<RecordedRequest> get() = unroutedList.toList()

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
                        Reply.Offline -> throw IOException("offline")
                        is Reply.Json -> return@addHandler respond(
                            r.body,
                            HttpStatusCode.fromValue(r.status),
                            headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                }
                @Suppress("UNREACHABLE_CODE")
                awaitCancellation()
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

/**
 * 로그인한 앱 문맥 한 벌 + 스텁 서버. [signIn] 이 세션을 복원(launch)하고, 그 뒤 요청만 [storeRequests] 로 센다.
 * 스토어의 부모 스코프는 [storeScope] — 시험 디스패처 위의 전경 작업이다(`advanceUntilIdle` 이 스토어 작업을 기다린다).
 */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalEncodingApi::class)
class StoreHarness(val scope: TestScope, route: (RecordedRequest) -> Reply? = { null }) {
    /** 시험이 고르는 응답(없으면 로그인 기본 응답 — client_release · 기기 등록 · 소속). */
    var route: (RecordedRequest) -> Reply? = route
    val server = StubServer(scope) { r -> this.route(r) ?: launchDefaults(r) }
    val clock = SessionClock { SwiftDate(SessionClock.demoInstant.timeIntervalSince1970 + scope.testScheduler.currentTime / 1000.0) }
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + storeJob)
    val vault = InMemoryTokenVault()
    val prefs = MemoryPrefs()
    val session = SessionStore(
        service = server.service(clock),
        vault = vault,
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15"),
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
    val context: SessionContext = SessionContext(session)
    private var mark = 0

    init {
        scope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    /** 로그인 직후 받은 요청(복원 · 등록 · 소속)을 빼고 스토어가 보낸 요청만. */
    val storeRequests: List<RecordedRequest> get() = server.requests.drop(mark)

    fun paths(): List<String> = storeRequests.map { r -> r.rpcName?.let { "rpc/$it" } ?: "${r.method} ${r.path}" }

    fun count(rpc: String): Int = storeRequests.count { it.rpcName == rpc }

    fun now(): SwiftDate = clock.now()

    /** 지난 실행의 세션을 금고에 심고 복원한다(Swift 시험의 `signedInContext`). */
    suspend fun signIn(userID: String = ME) {
        val exp = (now().timeIntervalSince1970 + 3_600).toLong()
        fun b64(text: String) = Base64.Default.encode(text.encodeToByteArray()).replace('+', '-').replace('/', '_').trimEnd('=')
        vault.write("hdr." + b64("""{"sub":"$userID","exp":$exp}""") + ".sig", SessionVaultKeys.accessToken)
        vault.write("r0", SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, userID)
        prefs.putString(SessionPrefsKeys.email, "me@example.invalid")
        session.launch()
        scope.advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, session.phase, "시험 조립: 로그인 복원이 끝나야 한다")
        mark = server.requests.size
    }

    /** 끝 단언 둘: 모르는 요청 0 · 폰 금지 호출 0(C§4 #13 — Android 스토어 시험 끝마다 violations == [] · G §2-3 W2-b ①). */
    fun assertClean() {
        assertEquals(emptyList(), server.unrouted.map { it.key }, "경로 없는 요청")
        assertEquals(emptyList(), PhoneForbiddenCalls.violations(server.requests), "폰 금지 호출")
    }

    private fun launchDefaults(r: RecordedRequest): Reply? = when {
        r.rpcName == "client_release" -> Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":1}""")
        r.rpcName == "register_device_fcm" -> Reply.Json("""{"status":"ok","device_id":"dev-1"}""")
        r.path == "/rest/v1/memberships" -> Reply.Json(MEMBERSHIP)
        // 로그아웃(시험이 세대를 바꿀 때): 기기 등록 해제 · local 범위 로그아웃.
        r.rpcName == "unregister_device" -> Reply.Json("""{"status":"ok","removed":true}""")
        r.path == "/auth/v1/logout" -> Reply.Json("{}")
        else -> null
    }

    companion object {
        const val ME = "00000000-0000-4000-8000-0000000000ee"
        const val MEMBERSHIP = """[{"team_id":"team-1","role":"member","teams":{"name":"아잉 데모팀","weekly_goal_hours":40}}]"""
    }
}
