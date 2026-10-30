// 배선 시험 조립(work·social): MockEngine 녹음 라우터 + 진짜 SessionStore(가짜 금고·가짜 신원) + InMemoryDesktopKeyValueStore + 가짜 OS 사건.
// 픽스처는 합성뿐이다. 실서버·소켓 0(RunningTests=참 → KtorRealtimeTransport.create 는 null).
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.socialapi.DesktopSocialLifecycle
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

class WiringTestRig(
    val test: TestScope,
    /** 경로(…/rpc/<이름> · …/rest/v1/<표>) → 본문. null 이면 404(PGRST202). */
    var answer: (path: String) -> String? = { path -> if (path.endsWith("/rpc/take_pokes")) "[]" else null },
) {
    /** 받은 요청 "METHOD path?query" 녹음. */
    val requests = mutableListOf<String>()
    val uncaught = mutableListOf<Throwable>()

    private val job = SupervisorJob()
    val scope: CoroutineScope = CoroutineScope(
        test.coroutineContext.minusKey(Job) + job + CoroutineExceptionHandler { _, e -> uncaught += e },
    )

    val clock: Clock = object : Clock {
        override fun now(): Instant = Instant.fromEpochMilliseconds(BASE_MS + test.testScheduler.currentTime)
    }
    val sessionClock = SessionClock { SwiftDate.fromEpochMillis(BASE_MS + test.testScheduler.currentTime) }

    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(test.testScheduler)
            addHandler { request ->
                val path = request.url.encodedPath
                requests += "${request.method.value} ${request.url.encodedPathAndQuery}"
                val body = answer(path)
                if (body == null) {
                    respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json"))
                } else {
                    respond(body, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }
        },
    )
    val httpClient = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }

    val service = SupabaseWorkService(
        projectURL = "https://wiring.invalid",
        anonKey = "stub-anon-key",
        client = httpClient,
        clock = { sessionClock.now() },
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )

    val sessionStore = SessionStore(
        service = service,
        vault = InMemoryTokenVault(),
        prefs = MemoryPrefs(),
        appInfo = AppInfo(ClientIdentity(ClientPlatform.WINDOWS, 7L, "0.1.0"), "Windows 11"),
        installationIdentity = object : InstallationIdentity {
            override fun installationId(): String = INSTALLATION
        },
        clock = sessionClock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() {}
        },
        parentScope = scope,
        newCleanupID = { "cleanup-1" },
    )

    val kv = InMemoryDesktopKeyValueStore()
    val idle = FakeIdle()
    val power = FakePower()
    val sessionEvents = FakeSessionEvents()
    val runningTests = object : RunningTests {
        override val isRunningTests: Boolean = true
    }

    fun signIn(userID: String = USER) {
        sessionStore.adoptSignedInSession(SupabaseSession("tok-$userID", "ref-$userID", userID), "dawn@aing.example")
    }

    fun count(suffix: String): Int = requests.count { it.substringAfter(' ').substringBefore('?').endsWith(suffix) }

    fun countContaining(fragment: String): Int = requests.count { fragment in it }

    fun close() {
        job.cancel()
    }

    companion object {
        const val BASE_MS = 1_789_623_900_000L
        const val USER = "d0000000-0000-4000-8000-000000000001"
        const val TEAM = "d0000000-0000-4000-8000-000000007ea1"
        const val INSTALLATION = "11111111-2222-4333-8444-555555555555"
        const val DEVICE = "win:$INSTALLATION"
    }
}

class MemoryPrefs : KeyValueStore {
    private val values = mutableMapOf<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

class FakeIdle : IdleSource {
    var last: Instant? = null
    override fun lastInput(kinds: Set<InputKind>): Instant? = last
    override fun addListener(listener: (kind: InputKind, at: Instant) -> Unit): Registration = Registration { }
}

class FakePower : PowerEvents {
    val listeners = mutableListOf<(PowerEvent) -> Unit>()
    override fun addListener(listener: (PowerEvent) -> Unit): Registration {
        listeners += listener
        return Registration { listeners.remove(listener) }
    }
    fun emit(event: PowerEvent) = listeners.toList().forEach { it(event) }
}

class FakeSessionEvents : SessionEvents {
    val listeners = mutableListOf<(SessionEvent) -> Unit>()
    override fun addListener(listener: (SessionEvent) -> Unit): Registration {
        listeners += listener
        return Registration { listeners.remove(listener) }
    }
}

/** 근무→소셜 생명주기 녹음. 부를 때의 근무 상태도 함께 적는다(순서 시험). */
class RecordingLifecycle(private val snapshot: () -> DesktopWorkSnapshot?) : DesktopSocialLifecycle {
    val calls = mutableListOf<String>()
    /** onWillSleep 순간에 읽을 값(잠자기 마커 — 가드보다 앞인지). */
    var willSleepProbe: () -> Any? = { null }
    override fun onSignedIn() { calls += "signedIn" }
    override fun onSignedOut() { calls += "signedOut" }
    override fun onWorkStarted() { calls += "workStarted(working=${snapshot()?.isWorking})" }
    override fun onUserStoppedWork(isTerminating: Boolean) { calls += "userStopped(terminating=$isTerminating)" }
    override fun onLapCrossed(lap: Int) { calls += "lap($lap)" }
    override fun onTeamStatusApplied() { calls += "teamStatus" }
    override fun onWillSleep(at: SwiftDate) { calls += "willSleep(marker=${willSleepProbe()})" }
    override fun onDidWake(at: SwiftDate) { calls += "didWake" }
}
