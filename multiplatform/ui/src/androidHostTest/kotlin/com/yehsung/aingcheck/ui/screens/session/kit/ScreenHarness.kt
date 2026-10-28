// 원본: Sources/CheckMobileKit/Demo/MobileDemo.swift @ 3bd04bd (MobileDemoFixtures — 요청 키 · 장면 폴더 · 바늘 변형 · __status 봉투 · 없으면 404 PGRST202)
// 원본: Sources/CheckMobileKit/Demo/MobileStubURLProtocol.swift @ 3bd04bd (스텁 서버 — 요청 기록)
//
// 화면 스냅숏 시험의 스텁 조립(Android 호스트 · Robolectric). iOS 데모와 **같은 바이트**의 데모 픽스처(Sources/CheckMobileKit/Demo/Fixtures)를
// 저장소 제자리에서 읽어(복사 없음 — E§12 공유 픽스처 규칙) 진짜 SessionStore · 스토어를 몬다. 소켓 0(Ktor MockEngine) — 봉인 아래에서 돈다.
//
// 결정성: 스토어 작업과 MockEngine 은 **한 스레드**(전용 단일 실행기)에서 돈다. 데이터를 다 받은 뒤 [freeze] 하면 그 뒤 요청은 영영 답이
// 오지 않는다 — 화면이 서며 띄운 새로고침(listDidAppear · conversationDidAppear)이 그리는 도중 값을 바꾸지 못한다.
package com.yehsung.aingcheck.ui.screens.session.kit

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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.Closeable
import java.io.File
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/** iOS 데모 픽스처 색인(Swift `MobileDemoFixtures`). */
class DemoFixtures(repoRoot: File) {
    data class Entry(val key: String, val needle: String?, val scenario: String?, val relativePath: String, val text: String)

    private val root = File(repoRoot, ROOT)

    val entries: List<Entry> = root.walkTopDown().filter { it.isFile && it.name.endsWith(".json") }.map { file ->
        val relative = file.relativeTo(root).invariantSeparatorsPath
        val folders = relative.split('/').dropLast(1)
        val scenario = folders.lastOrNull { it.startsWith("_") }?.drop(1)?.lowercase()
        val name = file.name.removeSuffix(".json")
        val parts = name.split('@', limit = 2)
        Entry(parts[0], parts.getOrNull(1), scenario, relative, file.readText())
    }.sortedBy { it.relativePath }.toList()

    /** 요청 → 키(Swift `key(for:)`). */
    fun key(method: String, path: String): String {
        val m = method.lowercase()
        val segments = path.split('/').filter { it.isNotEmpty() }
        if (segments.size >= 4 && segments[0] == "rest" && segments[1] == "v1" && segments[2] == "rpc") return "rpc.${segments[3]}"
        if (segments.size >= 3 && segments[0] == "rest" && segments[1] == "v1") return "rest.${segments[2]}.$m"
        if (segments.size >= 3 && segments[0] == "auth" && segments[1] == "v1") return (listOf("auth") + segments.drop(2) + m).joinToString(".")
        if (segments.firstOrNull() == "storage") return "storage.$m"
        return "unknown.$m"
    }

    /** (상태, 본문). 키에 맞는 파일이 없으면 404 PGRST202(옛 서버처럼 조용히 접어야 한다). */
    fun response(method: String, path: String, query: String, body: String, scenario: String?): Pair<Int, String> {
        val key = key(method, path)
        val haystack = "$body&$query"
        val ranked = entries
            .filter { it.key == key && (it.scenario == null || it.scenario == scenario) && (it.needle == null || haystack.contains(it.needle)) }
            .sortedWith(compareByDescending<Entry> { if (it.scenario != null) 1 else 0 }.thenByDescending { it.needle?.length ?: -1 })
        val entry = ranked.firstOrNull()
            ?: return 404 to """{"code":"PGRST202","message":"Could not find the function public.$key in the schema cache"}"""
        val parsed = runCatching { Json.parseToJsonElement(entry.text) }.getOrNull()
        if (parsed is JsonObject && parsed["__status"] != null) {
            return (parsed["__status"]!!.jsonPrimitive.intOrNull ?: 500) to (parsed["__body"]?.toString() ?: "{}")
        }
        return 200 to entry.text
    }

    companion object {
        const val ROOT = "Sources/CheckMobileKit/Demo/Fixtures"
        /** 데모 사용자(Swift `MobileDemo.userID`). */
        const val DEMO_USER = "d0000000-0000-4000-8000-000000000001"
        const val DEMO_EMAIL = "demo@aing-check.invalid"
    }
}

/** 비밀 아닌 설정(메모리). */
class MemoryKeyValueStore : KeyValueStore {
    private val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

/**
 * 스텁 조립 한 벌. [scenario] 는 데모 장면 폴더 이름(`messages` · `now` …). 시계는 데모 시각(2026-09-17 14:05 KST)에 멈춰 있다.
 */
class ScreenHarness(
    val scenario: String?,
    repoRoot: File,
    val clock: SessionClock = SessionClock.fixed(SessionClock.demoInstant),
) : Closeable {
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "screen-harness").apply { isDaemon = true } }
    val dispatcher = executor.asCoroutineDispatcher()
    val scope = CoroutineScope(SupervisorJob() + dispatcher)
    val fixtures = DemoFixtures(repoRoot)
    val requests = CopyOnWriteArrayList<String>()

    @Volatile
    var frozen = false
        private set

    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = this@ScreenHarness.dispatcher
            addHandler { request ->
                val body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
                val path = request.url.encodedPath
                requests += "${request.method.value} $path"
                if (frozen) awaitCancellation()
                val (status, text) = fixtures.response(request.method.value, path, request.url.encodedQuery, body, scenario)
                respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
            }
        },
    )

    val service = SupabaseWorkService(
        projectURL = "https://demo.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = { clock.now() },
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )
    val vault = InMemoryTokenVault()
    val prefs = MemoryKeyValueStore()
    val session = SessionStore(
        service = service,
        vault = vault,
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
        installationIdentity = object : InstallationIdentity {
            override fun installationId(): String = "d0000000-0000-4000-8000-0000000000aa"
        },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() {}
        },
        parentScope = scope,
        newCleanupID = { "cleanup-1" },
    )
    val context: SessionContext = SessionContext(session)

    /** 스토어 스레드에서 돈다(스토어 공개 함수는 한 디스패처에서 부른다 — 스토어 규약). */
    fun <T> onStore(block: suspend CoroutineScope.() -> T): T = runBlocking(dispatcher) { block() }

    /** 지난 실행의 세션을 금고에 심고 복원한다(데모 사용자). */
    fun signIn(userID: String = DemoFixtures.DEMO_USER) = onStore {
        val exp = (clock.now().timeIntervalSince1970 + 3_600).toLong()
        vault.write(jwt(userID, exp), SessionVaultKeys.accessToken)
        vault.write("r0", SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, userID)
        prefs.putString(SessionPrefsKeys.email, DemoFixtures.DEMO_EMAIL)
        session.launch()
        check(session.phase == SessionPhase.SignedIn) { "데모 복원이 로그인으로 끝나야 한다: ${session.phase}" }
    }

    /** 로그아웃 상태로 연다(로그인 화면 — 지난 이메일만 남아 있다). */
    fun signedOut(storedEmail: String? = DemoFixtures.DEMO_EMAIL) = onStore {
        storedEmail?.let { prefs.putString(SessionPrefsKeys.email, it) }
        session.launch()
        check(session.phase == SessionPhase.SignedOut) { "로그아웃 단계여야 한다: ${session.phase}" }
    }

    /** [done] 이 참이 될 때까지 스토어 스레드에서 기다린다(시한 10초). */
    fun awaitStore(label: String, done: () -> Boolean) = onStore {
        withTimeout(10_000) { while (!done()) delay(10) }
        check(done()) { label }
    }

    /** 이 뒤 요청은 답하지 않는다(그리는 도중 값이 바뀌지 않게). */
    fun freeze() {
        frozen = true
    }

    override fun close() {
        scope.cancel()
        executor.shutdownNow()
    }

    private fun jwt(userID: String, exp: Long): String {
        val b64 = Base64.getUrlEncoder().withoutPadding()
        return "hdr." + b64.encodeToString("""{"sub":"$userID","exp":$exp}""".toByteArray()) + ".sig"
    }

    companion object {
        val demoNow: SwiftDate get() = SessionClock.demoInstant
    }
}
