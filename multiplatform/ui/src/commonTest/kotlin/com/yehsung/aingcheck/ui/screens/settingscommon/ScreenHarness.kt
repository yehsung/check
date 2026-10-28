// 원본: Sources/CheckMobileKit/Demo/MobileDemo.swift:160-290 @ 3bd04bd (데모 픽스처 색인 — 키 · 장면 · 바늘 고르기) · Tests/CheckMobileKitTests/MeTestSupport.swift(스텁 서버 + 로그인 문맥)
//
// W3-b 화면 시험 조립: 스텁 서버(MockEngine, 시험 디스패처) + 로그인한 세션 + 진짜 스토어. 응답은 iOS 데모 픽스처(Sources/CheckMobileKit/Demo/Fixtures)를
// **제자리에서** 읽는다(복사 없음 — A§4-2). 픽스처 고르기는 Swift MobileDemoFixtures 규칙 그대로: 키(rpc.<이름> · rest.<표>.<방법>) → 장면 폴더(_<장면>)가
// 바깥보다 앞 → 바늘(@뒤 글자 — 본문·쿼리에 들어 있어야 한다)이 긴 것이 앞. 시계는 데모 시각(2026-09-17 14:05 KST)에 고정이라 렌더가 결정적이다.
package com.yehsung.aingcheck.ui.screens.settingscommon

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
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeLinks
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
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

/** 데모 픽스처 한 장. */
data class DemoFixture(val relativePath: String) {
    val key: String
    val needle: String?
    val scenario: String?

    init {
        val parts = relativePath.split('/')
        scenario = parts.dropLast(1).lastOrNull { it.startsWith("_") }?.drop(1)?.lowercase()
        val name = parts.last().removeSuffix(".json")
        val at = name.indexOf('@')
        key = if (at < 0) name else name.substring(0, at)
        needle = if (at < 0) null else name.substring(at + 1)
    }

    fun read(): String = RepoFiles.readText(DemoFixtures.ROOT + "/" + relativePath)
}

/** Swift `MobileDemoFixtures` 의 고르기 규칙(목록은 시험이 쓰는 장면만 — 저장소 목록을 걷지 않는다). */
class DemoFixtures(paths: List<String>) {
    private val entries = paths.map(::DemoFixture)

    fun key(r: RecordedRequest): String {
        r.rpcName?.let { return "rpc.$it" }
        val segments = r.path.split('/').filter { it.isNotEmpty() }
        val method = r.method.lowercase()
        if (segments.size >= 3 && segments[0] == "rest" && segments[1] == "v1") return "rest.${segments[2]}.$method"
        if (segments.size >= 3 && segments[0] == "auth" && segments[1] == "v1") return (listOf("auth") + segments.drop(2) + method).joinToString(".")
        if (segments.firstOrNull() == "storage") return "storage.$method"
        return "unknown.$method"
    }

    fun entry(r: RecordedRequest, scenario: String?): DemoFixture? {
        val key = key(r)
        val haystack = r.bodyText + "&" + r.query.joinToString("&") { "${it.first}=${it.second}" }
        return entries
            .filter { it.key == key && (it.scenario == null || it.scenario == scenario) }
            .filter { e -> e.needle?.let { haystack.contains(it) } ?: true }
            .sortedWith(compareByDescending<DemoFixture> { if (it.scenario != null) 1 else 0 }.thenByDescending { it.needle?.length ?: -1 })
            .firstOrNull()
    }

    companion object {
        const val ROOT = "Sources/CheckMobileKit/Demo/Fixtures"
        const val DEMO_USER = "d0000000-0000-4000-8000-000000000001"

        val base = listOf(
            "base/rest.memberships.get.json",
            "base/rpc.app_user_characters.json",
            "base/rpc.register_device.json",
            "base/rpc.set_push_prefs.json",
        )

        val rankings = base + listOf(
            "rankings/rpc.team_weekly_leaderboard.json",
            "rankings/rpc.token_usage_board.json",
            "rankings/_rankings-tokens/rest.profiles.get@token_usage_collect.json",
            "rankings/_rankings-minigame/rpc.minigame_board.json",
            "rankings/_rankings-minigame/rpc.minigame_board@flappy.json",
            "rankings/_rankings-minigame/rpc.minigame_yesterday_winner.json",
            "rankings/_rankings-minigame/rpc.minigame_yesterday_winner@flappy.json",
        )

        val me = base + listOf(
            "me/rest.ai_limits.get.json",
            "me/rest.profiles.get@display_name,avatar_url.json",
            "me/rest.profiles.get@select=center.json",
            "me/rest.profiles.get@select=character.json",
            "me/rest.profiles.get@select=status_message.json",
            "me/rest.profiles.get@token_usage_collect.json",
            "me/rest.token_usage_device_daily.get.json",
            "me/rest.work_sessions.get@limit=5000.json",
            "me/rpc.character_gift_pending.json",
            "me/rpc.feedback_reply_latest.json",
            "me/rpc.my_team_invite_code.json",
            "me/_me/rest.work_statuses.get.json",
            "me/_me/rpc.achievements_status.json",
            "me/_me/rpc.shop_state.json",
            "me/_me/rpc.weekly_work_status.json",
            "me/_me-settings/rest.profiles.get@select=minigame_public.json",
        )
    }
}

/** 비밀 아닌 설정(메모리판). */
class ScreenMemoryPrefs : KeyValueStore {
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
 * 로그인한 앱 문맥 한 벌 + 스텁 서버 + 데모 픽스처. [override] 가 먼저 답하고(장면별 바꿈), 없으면 픽스처, 그것도 없으면 404(PGRST202 — 서버 준비 전과 같은 접힘).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ScreenHarness(
    val scope: TestScope,
    private val fixtures: DemoFixtures,
    private val scenario: String? = null,
    var override: (RecordedRequest) -> String? = { null },
) {
    private val recorded = mutableListOf<RecordedRequest>()
    val requests: List<RecordedRequest> get() = recorded.toList()
    val missing = mutableListOf<String>()

    val clock: SessionClock = SessionClock { SwiftDate(SessionClock.demoInstant.timeIntervalSince1970 + scope.testScheduler.currentTime / 1000.0) }
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + storeJob)
    val prefs = ScreenMemoryPrefs()
    val vault = InMemoryTokenVault()

    private val engine = MockEngine(
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
                val body = override(entry) ?: fixtures.entry(entry, scenario)?.read()
                if (body == null) {
                    missing += fixtures.key(entry)
                    respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json"))
                } else {
                    respond(body, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }
        },
    )

    val service: SupabaseWorkService = SupabaseWorkService(
        projectURL = "https://golden.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = { clock.now() },
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )

    val session = SessionStore(
        service = service,
        vault = vault,
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
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

    val context: SessionContext = SessionContext(session, AppConfig())
    val ruby = RubyBalanceCell()

    init {
        scope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    fun signIn(userID: String = DemoFixtures.DEMO_USER, email: String = "dawn@aing.example") {
        session.adoptSignedInSession(SupabaseSession("tok-$userID", "ref-$userID", userID), email)
    }

    fun meContext(links: MeLinks = MeLinks.None): MeContext = MeContext(session, AppConfig(), ruby, links)

    fun meStore(links: MeLinks = MeLinks.None): MeStore = MeStore(
        context = meContext(links),
        parentScope = storeScope,
        drawableCharacters = DrawableCharacterSource.of(ALL_PORTRAITS),
        computeContext = StandardTestDispatcher(scope.testScheduler),
        newRequestID = { "AAAAAAAA-0000-4000-8000-000000000001" },
    )

    companion object {
        val ALL_PORTRAITS: Set<String> = setOf(
            "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
            "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
        )
    }
}

/** 이름 비교(시험용 — 글자 단위). 순위의 같은 점수 뒤 이름 순서에만 쓰인다(데모 픽스처에는 같은 점수 이름 겹침이 없다). */
object ScreenTestCollation : com.yehsung.aingcheck.core.foundation.platform.Collation {
    override fun compare(a: String, b: String): Int = a.compareTo(b)
}
