// 원본: Tests/CheckMobileKitTests/BaseTestSupport.swift(BaseStub · 가짜 JWT · 응답 견본) @ 1b8260d
// 세션 시험 도우미: 가상 시간 위의 스텁 서버(MockEngine 을 시험 디스패처에서 돌린다 — 지연·상한이 runTest 시계로 잰다).
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.io.IOException
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/** 스텁 응답 하나. */
sealed interface Reply {
    data class Json(val body: String, val status: Int = 200) : Reply

    /** 전송 실패(오프라인 · 끊김) — 서비스는 일시 오류로 접어야 한다. */
    data object Offline : Reply

    /** 응답하지 않는다(취소될 때까지). client_release 상한·HttpTimeout 을 잰다. */
    data object Hang : Reply

    /** 문이 열릴 때까지 기다렸다가 [then] 을 낸다(합류 · 늦은 응답 재현). */
    class Gate(val gate: CompletableDeferred<Unit>, val then: Reply) : Reply
}

/** 받은 요청 하나(testkit RecordedRequest — 폰 금지 호출 판정기를 그대로 쓴다). */
val RecordedRequest.authorization: String get() = headers["Authorization"]?.firstOrNull() ?: ""

/**
 * 스텁 서버. 요청마다 [route] 를 불러 응답을 고른다. 모든 요청을 기록한다. MockEngine 은 **시험 디스패처**에서 돈다 —
 * 그래서 [Reply.Gate]·[Reply.Hang] 과 `withTimeoutOrNull(3_000)` 이 같은 가상 시계를 본다(실제 시간 0).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StubServer(scope: TestScope, private val route: (RecordedRequest) -> Reply?) {
    private val recorded = mutableListOf<RecordedRequest>()
    private val unroutedList = mutableListOf<RecordedRequest>()
    val requests: List<RecordedRequest> get() = recorded.toList()

    /** 경로가 없는 요청(시험 끝에 비어 있어야 한다 — 모르는 요청은 실패). */
    val unrouted: List<RecordedRequest> get() = unroutedList.toList()

    fun paths(): List<String> = recorded.map { r -> r.rpcName?.let { "rpc/$it" } ?: r.path }

    fun count(path: String): Int = recorded.count { it.path == path }

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
        anonKey = STUB_ANON,
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = { clock.now() },
        text = PlainTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )

    companion object {
        const val STUB_ANON: String = "stub-anon-key"
    }
}

/** 세션 시험에는 메시지 글자 규칙이 필요 없다(서비스 생성자만 채운다). */
object PlainTextRules : WireTextRules {
    override fun sanitized(raw: String): String = raw.trim()
    override fun hasVisibleContent(text: String): Boolean = text.any { !it.isWhitespace() }
    override fun statusMessageSanitized(raw: String): String = raw.trim()
}

/** 메모리 설정 저장소. */
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

/** 읽기를 세는 금고(단일 실행 가드 시험 — 거부된 실행이 금고를 열지 않았음을 잰다). */
class CountingVault(private val inner: InMemoryTokenVault = InMemoryTokenVault()) : TokenVault {
    /** 읽은 칸 이름(차례대로). */
    val readKeys: MutableList<String> = mutableListOf()
    var writes: Int = 0
    val reads: Int get() = readKeys.size
    var failsWrites: Boolean
        get() = inner.failsWrites
        set(value) { inner.failsWrites = value }
    override fun read(key: String): String? { readKeys += key; return inner.read(key) }
    override fun write(value: String, key: String) { writes += 1; inner.write(value, key) }
    override fun delete(key: String) = inner.delete(key)

    /** 세지 않고 읽기(시험 단언용). */
    fun peek(key: String): String? = inner.read(key)

    fun resetCounts() {
        readKeys.clear()
        writes = 0
    }
}

class FixedInstallation(var id: String?) : InstallationIdentity {
    var calls: Int = 0
    override fun installationId(): String? { calls += 1; return id }
}

class TestGuard(var grants: Boolean = true) : SingleInstanceGuard {
    var acquires: Int = 0
    var releases: Int = 0
    override fun tryAcquire(): Boolean { acquires += 1; return grants }
    override fun release() { releases += 1 }
}

object SessionFixtures {
    const val INSTALLATION: String = "11111111-2222-4333-8444-555555555555"

    /** Android versionCode 1 · 0.1.0. */
    val androidInfo: AppInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15")

    /** 데모 기준 시각(2026-09-17 14:05 KST)에서 가상 시간만큼 간 시계. */
    @OptIn(ExperimentalCoroutinesApi::class)
    fun clock(scope: TestScope): SessionClock = SessionClock {
        SwiftDate(SessionClock.demoInstant.timeIntervalSince1970 + scope.testScheduler.currentTime / 1000.0)
    }

    /** exp 가 [exp] 인 가짜 JWT(서명 검증 없음 — 세션은 exp 만 읽는다). 진짜 JWT 머리(eyJ…)가 아니게 머리를 바꿔 둔다. */
    @OptIn(ExperimentalEncodingApi::class)
    fun jwt(exp: SwiftDate, subject: String = "user-1", salt: String = ""): String {
        fun b64(text: String) = Base64.Default.encode(text.encodeToByteArray()).replace('+', '-').replace('/', '_').trimEnd('=')
        val payload = """{"sub":"$subject","exp":${exp.timeIntervalSince1970.toLong()},"n":"$salt"}"""
        return "hdr." + b64(payload) + ".sig"
    }

    fun auth(access: String, refresh: String, userID: String = "user-1"): Reply =
        Reply.Json("""{"access_token":"$access","refresh_token":"$refresh","user":{"id":"$userID"}}""")

    val releaseOK: Reply = Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":3,"notes":null}""")
    val registerOK: Reply = Reply.Json("""{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":false,"feedback_reply":true}}""")
    val membershipOK: Reply = Reply.Json("""[{"team_id":"team-1","role":"member","teams":{"name":"테스트팀","weekly_goal_hours":40}}]""")
    val jwtExpired: Reply = Reply.Json("""{"code":"PGRST301","message":"JWT expired"}""", 401)
    val invalidGrant: Reply = Reply.Json("""{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}""", 400)
    val pgrst202: Reply = Reply.Json("""{"code":"PGRST202","message":"Could not find the function in the schema cache"}""", 404)
    val serverDown: Reply = Reply.Json("""{"message":"upstream"}""", 503)
    val rateLimited: Reply = Reply.Json("""{"message":"rate limited"}""", 429)
    val unregistered: Reply = Reply.Json("""{"status":"ok","removed":true}""")
    val emptyObject: Reply = Reply.Json("{}")
}
