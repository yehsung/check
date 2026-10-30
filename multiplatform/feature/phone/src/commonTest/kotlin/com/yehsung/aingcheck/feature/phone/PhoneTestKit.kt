// 원본: 없음 — 폰 로직 시험 조립(core/stores 시험의 StoreHarness·StubServer 를 본떴다 — 그 파일은 다른 모듈의 시험 소스라 볼 수 없다).
// Swift 짝: Tests/CheckMobileKitTests/BaseTestSupport.swift(BaseTestClock · BaseFakeTransport) · PushTestSupport.swift(PushFakeSystem · PushHarness) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.phone.app.PhoneAppModel
import com.yehsung.aingcheck.feature.phone.app.PhoneEnvironment
import com.yehsung.aingcheck.feature.phone.push.PhonePushAuthorization
import com.yehsung.aingcheck.feature.phone.push.PhonePushSystem
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotFile
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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.test.assertEquals

/** 스텁 응답 하나. */
sealed interface Reply {
    data class Json(val body: String, val status: Int = 200) : Reply

    /** 전송 실패(오프라인 · 끊김). */
    data object Offline : Reply

    /** 문이 열릴 때까지 기다렸다가 [then] 을 낸다(늦은 응답 재현). */
    class Gate(val gate: CompletableDeferred<Unit>, val then: Reply) : Reply

    companion object {
        /** PostgREST 가 함수를 못 찾을 때(PGRST202 · 404) — 서버가 준비 안 된 응답. */
        val missingFunction: Reply = Json("""{"code":"PGRST202","message":"Could not find the function in the schema cache"}""", 404)
    }
}

/** 스텁 서버. 요청마다 [route] 를 불러 응답을 고르고 모든 요청을 기록한다(MockEngine 은 시험 디스패처에서 돈다). */
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

/** 메모리 할 일 파일 시스템. */
class MemoryTodoFiles : TodoFileSystem {
    val contents: MutableMap<String, ByteArray> = LinkedHashMap()
    override fun read(path: String): ByteArray? = contents[path]?.copyOf()
    override fun writeAtomically(path: String, bytes: ByteArray) { contents[path] = bytes.copyOf() }
    override fun move(from: String, to: String) {
        val bytes = contents.remove(from) ?: return
        contents[to] = bytes
    }
}

/** 메모리 위젯 스냅숏 파일. 쓰기 실패를 흉내 내려면 [failWrites]. */
class MemoryWidgetFile(initial: ByteArray? = null) : WidgetSnapshotFile {
    var bytes: ByteArray? = initial
    var failWrites: Boolean = false
    var writes: Int = 0
        private set
    var removes: Int = 0
        private set

    override fun read(): ByteArray? = bytes?.copyOf()
    override fun writeAtomically(bytes: ByteArray) {
        if (failWrites) throw IllegalStateException("쓰기 실패(흉내)")
        writes += 1
        this.bytes = bytes.copyOf()
    }
    override fun remove() {
        removes += 1
        bytes = null
    }

    val text: String? get() = bytes?.decodeToString()
    val json: JsonObject? get() = text?.let { Json.parseToJsonElement(it).jsonObject }
}

/** 기록하는 가짜 시스템(Swift `RecordingPushSystem`). */
class RecordingPushSystem(var status: PhonePushAuthorization = PhonePushAuthorization.authorized) : PhonePushSystem {
    val calls = mutableListOf<String>()
    var badges = mutableListOf<Int>()
    var grantOnRequest: Boolean = true
    var overlay: Boolean = false
    var overlayObserver: ((Boolean) -> Unit)? = null

    override suspend fun authorizationStatus(): PhonePushAuthorization = status
    override suspend fun requestAuthorization(): Boolean {
        calls += "requestAuthorization"
        if (status == PhonePushAuthorization.notDetermined) {
            status = if (grantOnRequest) PhonePushAuthorization.authorized else PhonePushAuthorization.denied
        }
        return status == PhonePushAuthorization.authorized
    }
    override fun registerForRemoteNotifications() { calls += "register" }
    override fun unregisterForRemoteNotifications() { calls += "unregister" }
    override fun removeAllDeliveredNotifications() { calls += "removeAll" }
    override fun setBadgeCount(count: Int) { badges += count }
    override fun openSystemSettings() { calls += "openSettings" }
    override fun presentPermissionPrimer() { calls += "presentPrimer" }
    override fun dismissPermissionPrimer() { calls += "dismissPrimer" }
    override val isSystemOverlayPresented: Boolean get() = overlay
    override fun startObservingSystemOverlay(onChange: (Boolean) -> Unit) {
        calls += "observeOverlay"
        overlayObserver = onChange
    }
    override fun stopObservingSystemOverlay() {
        calls += "stopObserveOverlay"
        overlayObserver = null
    }

    fun count(call: String) = calls.count { it == call }
}

/** 기록하는 가짜 실시간 전송자(사건은 [emit] 으로 넣는다). */
class FakeTransport : RealtimeTransport {
    override var onEvent: ((RealtimeTransportEvent) -> Unit)? = null
    val calls = mutableListOf<String>()
    var lastConnect: List<Any?>? = null

    override fun connect(projectURL: String, apiKey: String, accessToken: String, channel: String, isPrivate: Boolean) {
        calls += "connect"
        lastConnect = listOf(projectURL, apiKey, accessToken, channel, isPrivate)
    }
    override fun pushAccessToken(token: String) { calls += "pushAccessToken" }
    override fun sendHeartbeat() { calls += "heartbeat" }
    override fun disconnect() { calls += "disconnect" }

    fun emit(event: RealtimeTransportEvent) = onEvent?.invoke(event)
}

/**
 * 로그인한 폰 앱 한 벌(스텁 서버 + [PhoneAppModel]). [signIn] 이 세션을 복원(launch)하고, 그 뒤 요청만 [appRequests] 로 센다.
 * 스토어의 부모 스코프는 시험 디스패처 위의 전경 작업이다(`advanceUntilIdle` 이 스토어 작업을 기다린다).
 */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalEncodingApi::class)
class PhoneHarness(
    val scope: TestScope,
    clockStart: SwiftDate = SessionClock.demoInstant,
    val transport: FakeTransport? = null,
    val widgetFile: MemoryWidgetFile = MemoryWidgetFile(),
    appConfig: AppConfig = AppConfig(),
    /** 번들에 초상이 실린 캐릭터(상점 번호 — 케이크 선물은 번호 4 이상에서만 묻는다). */
    drawableCharacters: List<String> = listOf("aing"),
    route: (RecordedRequest) -> Reply? = { null },
) {
    /** 시험이 고르는 응답(없으면 로그인 기본 응답). */
    var route: (RecordedRequest) -> Reply? = route
    val server = StubServer(scope) { r -> this.route(r) ?: defaults(r) }

    /** 가상 시간을 밀지 않고 벽시계만 옮긴다. */
    var clockShift: Double = 0.0
    val clock = SessionClock { SwiftDate(clockStart.timeIntervalSince1970 + clockShift + scope.testScheduler.currentTime / 1000.0) }
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + storeJob)
    val vault = InMemoryTokenVault()
    val prefs = MemoryPrefs()
    val todoFiles = MemoryTodoFiles()
    var widgetReloads: Int = 0
        private set
    val pushSystem = RecordingPushSystem()

    val env = PhoneEnvironment(
        service = server.service(clock),
        vault = vault,
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 7, "0.1.0"), "Android 15"),
        installationIdentity = object : InstallationIdentity {
            override fun installationId(): String = INSTALLATION
        },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() {}
        },
        appConfig = appConfig,
        scope = storeScope,
        realtimeTransport = transport,
        runsTimers = false,
        widgetFile = widgetFile,
        reloadWidgetTimelines = { widgetReloads += 1 },
        todoStorage = NowTodoStorage("/mem/aing", todoFiles),
        collation = NaturalKoNameCollation,
        drawableCharacters = DrawableCharacterSource.of(drawableCharacters),
        knownCharacterIDs = drawableCharacters,
    )
    val app = PhoneAppModel(env)
    private var mark = 0

    init {
        scope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    /** 복원 뒤 앱이 보낸 요청. */
    val appRequests: List<RecordedRequest> get() = server.requests.drop(mark)

    fun count(rpc: String): Int = appRequests.count { it.rpcName == rpc }

    fun rpcNames(): List<String> = appRequests.mapNotNull { it.rpcName }

    fun now(): SwiftDate = clock.now()

    fun markRequests() {
        mark = server.requests.size
    }

    fun settle() = scope.advanceUntilIdle()

    private fun b64(text: String) = Base64.Default.encode(text.encodeToByteArray()).replace('+', '-').replace('/', '_').trimEnd('=')

    fun jwt(userID: String, salt: String = ""): String {
        val exp = (now().timeIntervalSince1970 + 3_600).toLong()
        return "hdr." + b64("""{"sub":"$userID","exp":$exp,"salt":"$salt"}""") + ".sig"
    }

    var tokenReply: Reply? = null

    /** 지난 실행의 세션을 금고에 심고 앱을 시작한다(실행 복원). */
    fun signIn(userID: String = ME) {
        vault.write(jwt(userID), SessionVaultKeys.accessToken)
        vault.write("r0", SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, userID)
        prefs.putString(SessionPrefsKeys.email, "me@example.invalid")
        app.start()
        scope.advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, app.session.phase, "시험 조립: 로그인 복원이 끝나야 한다")
        mark = server.requests.size
    }

    /** 끝 단언 둘: 경로 없는 요청 0 · 폰 금지 호출 0(C§4 #13). */
    fun assertClean() {
        assertEquals(emptyList(), server.unrouted.map { it.key }, "경로 없는 요청")
        assertEquals(emptyList(), PhoneForbiddenCalls.violations(server.requests), "폰 금지 호출")
    }

    /** 로그인·기본 탭 조회에 쓰는 기본 응답(시험이 [route] 로 덮는다). */
    fun defaults(r: RecordedRequest): Reply? = when {
        r.rpcName == "client_release" -> Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":1}""")
        r.rpcName == "register_device_fcm" -> Reply.Json("""{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}""")
        r.rpcName == "unregister_device" -> Reply.Json("""{"status":"ok","removed":true}""")
        r.path == "/auth/v1/logout" -> Reply.Json("{}")
        r.path == "/auth/v1/token" -> tokenReply
        r.path == "/rest/v1/profiles" && r.method == "GET" -> Reply.Json("""[{"display_name":"나","character":null}]""")
        r.path == "/rest/v1/memberships" -> Reply.Json(MEMBERSHIP)
        // 로그인 직후 캐릭터 한 표(AppUserCharacterStore.refresh) · 근무 종료 뒤 주간 보상 재조회(MeStore.weeklyWorkDidChange).
        r.rpcName == "app_user_characters" -> Reply.Json("[]")
        r.rpcName == "weekly_work_status" -> Reply.Json("""{"status":"ok"}""")
        // 확성기 배너(a6791165): 메시지 스토어가 앞으로 올 때 `megaphone_inbox` 를 한 번 묻는다. 기본은 옛 서버(함수 없음 = 필터 끔 · 지금처럼 메시지)다 —
        // 배너를 재는 시험(MegaphoneBannerPhoneTest)은 자기 응답을 준다.
        r.rpcName == "megaphone_inbox" -> Reply.missingFunction
        else -> null
    }

    companion object {
        const val ME = "00000000-0000-4000-8000-0000000000ee"
        const val INSTALLATION = "11111111-2222-4333-8444-555555555555"
        const val MEMBERSHIP = """[{"team_id":"team-1","role":"member","teams":{"name":"아잉 데모팀","weekly_goal_hours":40}}]"""

        /** 요청 본문(JSON) — 빈 본문이면 null. */
        fun body(r: RecordedRequest): JsonElement? = r.bodyText.takeIf { it.isNotEmpty() }?.let { Json.parseToJsonElement(it) }
    }
}
