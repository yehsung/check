// 원본: multiplatform/ui/src/commonTest/…/screens/settingscommon/ScreenHarness.kt @ a90d8623 (스텁 서버 + 로그인 문맥 + 진짜 스토어) — ui 시험 소스는
//       desktopApp 시험에서 보이지 않아 필요한 몫만 줄여 옮겼다(픽스처 고르기 없음 — 경로 뒤 글자로 답을 고른다).
//
// W3-c0 시험 조립: 스텁 서버(MockEngine · 시험 디스패처) + 진짜 SessionStore·MessagesStore·RankingsStore·MeStore. 픽스처는 합성뿐이다
// (실제 홈·실제 계정 없음). 모르는 요청은 404(PGRST202 — 서버 준비 전과 같은 접힘)로 답한다. 시계는 고정.
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.Collation
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
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope

/** 비밀 아닌 설정(메모리판). */
class SharedMemoryPrefs : KeyValueStore {
    val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

object SharedTestCollation : Collation {
    override fun compare(a: String, b: String): Int = a.compareTo(b)
}

@OptIn(ExperimentalCoroutinesApi::class)
class SharedTestHarness(
    val scope: TestScope,
    /** 경로(…/rpc/<이름> · …/rest/v1/<표>) → 본문. null 이면 404. */
    var answer: (path: String) -> String? = { null },
    val config: DesktopAppConfig = DesktopAppConfig(),
    dark: Boolean = false,
    /** int-w3: 3차 페이지 묶음(시험 탐침 페이지를 꽂는 자리). */
    routePages: RoutePages = RoutePages.NONE,
    /** int-w3: 업데이트 필요 화면 목적지(기본 = 생성 상수 — 시험 빌드에선 비어 null). */
    updateDestination: String? = com.yehsung.aingcheck.desktop.shell.update.StoreUpdateDestination.windows,
) {
    /** 링크 열기 녹음(업데이트 단추 대조). */
    val opened = mutableListOf<String>()
    val paths = mutableListOf<String>()
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + storeJob)
    val prefs = SharedMemoryPrefs().apply { putString(AingAppearanceMode.STORAGE_KEY, if (dark) AingAppearanceMode.Dark.storedValue else AingAppearanceMode.Light.storedValue) }
    val clock = SessionClock { SwiftDate(1_789_623_900.0 + scope.testScheduler.currentTime / 1000.0) }

    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(scope.testScheduler)
            addHandler { request ->
                val path = request.url.encodedPath
                paths += path
                val body = answer(path)
                if (body == null) {
                    respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json"))
                } else {
                    respond(body, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }
        },
    )

    val service = SupabaseWorkService(
        projectURL = "https://golden.invalid",
        anonKey = "stub-anon-key",
        client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        clock = { clock.now() },
        text = RulesWireTextRules,
        newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
    )

    val session = SessionStore(
        service = service,
        vault = InMemoryTokenVault(),
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.WINDOWS, BUILD, "0.1.0"), "Windows 11"),
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

    val context = SessionContext(session, AppConfig())
    val messages = MessagesStore(context, storeScope, SharedTestCollation)
    val rankings = RankingsStore(context, storeScope, SharedTestCollation)
    val me = MeStore(
        context = MeContext(session, AppConfig(), RubyBalanceCell(), MeLinks.None),
        parentScope = storeScope,
        drawableCharacters = DrawableCharacterSource.of(setOf("aing", "fox")),
        computeContext = StandardTestDispatcher(scope.testScheduler),
        newRequestID = { "AAAAAAAA-0000-4000-8000-000000000001" },
    )
    val appearance = AppearanceStore(prefs)
    val nav = InMemoryFlyoutNavigator()

    val host = SharedFlyoutPageHost(
        SharedPagesDeps(
            session = session,
            sessionContext = context,
            messages = messages,
            rankings = rankings,
            me = me,
            appearance = appearance,
            config = config,
            currentBuild = BUILD,
            rankingsFace = { RankingsMyFace("aing", CharacterMood.entries.first()) },
            openUrl = { opened += it },
            routePages = routePages,
            updateDestination = updateDestination,
        ),
    )

    init {
        scope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    fun signIn(userID: String = USER, email: String = "dawn@aing.example") {
        session.adoptSignedInSession(SupabaseSession("tok-$userID", "ref-$userID", userID), email)
    }

    companion object {
        const val BUILD = 7L
        const val USER = "d0000000-0000-4000-8000-000000000001"

        /** 합성 소속 한 줄(팀 있음). 모양은 PostgREST memberships 임베드(teams) — 데모 픽스처와 같은 칸. */
        const val MEMBERSHIP = """[{"team_id":"d0000000-0000-4000-8000-000000007ea1","role":"member","teams":{"name":"합성 팀","weekly_goal_hours":40}}]"""

        /** 서버가 이 빌드보다 높은 최소 빌드를 말한다(업데이트 필요). */
        const val RELEASE_NEEDS_UPDATE = """{"status":"ok","platform":"windows","min_build":99,"latest_build":99}"""

        /** 소속 있음 · 나머지 404. */
        val withTeam: (String) -> String? = { path -> if (path.endsWith("/rest/v1/memberships")) MEMBERSHIP else null }

        /** 소속 없음(빈 배열) · 나머지 404. */
        val teamless: (String) -> String? = { path -> if (path.endsWith("/rest/v1/memberships")) "[]" else null }
    }
}
