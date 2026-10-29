// 원본: Sources/CheckMobileKit/App/MobileRootView.swift · MobileAppModel.swift @ ios-1014 (루트 단계 → 탭 다섯 · 이동 요청)
//
// 7차 조립(K11) 계측: 에뮬레이터 ART 위에서 **조립된 셸**(AingShell → NavGraph → 화면 갈래 진입 함수)과 폰 앱 모델(W2-f) 한 벌을 돌린다.
// 서버는 W3-a 기기 스텁(DeviceStubServer — Ktor MockEngine, 소켓 0)이다. 판정은 화면 표식(testTag)과 스토어 값으로 한다.
//   ① 진짜 앱(MainActivity)이 뜬다 — 시험 프로세스는 세션을 시작하지 않으니 실행 중 화면에 머문다(망 0).
//   ② 로그인 → 탭 다섯 → 화면 진입 · 뒤로가기(게임 · 나 · 메시지 · 상점은 탭 막대 숨김) — 판돈 깃발 꺼짐: 오목 로비에 신청 안내 줄이 없다.
//   ③ 판돈 깃발 켜짐: 같은 로비에 신청 안내 줄이 선다(§8-17 #1 — 깃발은 AppConfig 한 문).
package com.yehsung.aingcheck.android.app

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.lifecycle.AppLifecycle
import com.yehsung.aingcheck.android.nav.AppScreens
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.android.screens.account.DefaultAndroidAccountCleanup
import com.yehsung.aingcheck.android.screens.messages.DeviceStubServer
import com.yehsung.aingcheck.android.screens.messages.StubPeople
import com.yehsung.aingcheck.android.screens.now.NowTags
import com.yehsung.aingcheck.android.shell.AingShell
import com.yehsung.aingcheck.android.shell.MainActivity
import com.yehsung.aingcheck.android.shell.ShellPhases
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.JvmTodoFileSystem
import com.yehsung.aingcheck.feature.phone.app.PhoneAppModel
import com.yehsung.aingcheck.feature.phone.app.PhoneEnvironment
import com.yehsung.aingcheck.feature.phone.widget.FileWidgetSnapshotFile
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreenTags
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubTags
import com.yehsung.aingcheck.ui.screens.me.MeAnchor
import com.yehsung.aingcheck.ui.screens.messages.MessagesTags
import com.yehsung.aingcheck.ui.screens.rankings.RankingsTags
import com.yehsung.aingcheck.ui.screens.session.SessionTags
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenTicking
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.screens.settingscommon.SettingsTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.HttpClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** 조립 앱 한 벌(스텁 서버 · 폰 앱 모델 · 화면 의존). 깃발은 [duelsEnabled] 하나로만 바꾼다. */
class AssembledStubApp(filesDir: File, duelsEnabled: Boolean) {
    val clock = SessionClock.fixed(SessionClock.demoInstant)
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val server = DeviceStubServer(clock.now())
    private val prefs = object : KeyValueStore {
        val values = HashMap<String, Any>()
        override fun getString(key: String) = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String) = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String) = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }
    private val dir = File(filesDir, "assembly-${System.nanoTime()}").also { it.mkdirs() }
    val phone = PhoneAppModel(
        PhoneEnvironment(
            service = SupabaseWorkService("https://stub.invalid", "stub-anon-key", HttpClient(server.engine) { SupabaseWorkService.clientConfig(this) },
                { clock.now() }, RulesWireTextRules, { "ABCDEF12-0000-4000-8000-000000000000" }),
            vault = InMemoryTokenVault(),
            prefs = prefs,
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
            installationIdentity = object : InstallationIdentity { override fun installationId() = "d0000000-0000-4000-8000-0000000000aa" },
            clock = clock,
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire() = true
                override fun release() {}
            },
            appConfig = AppConfig(duelsEnabled = duelsEnabled),
            scope = scope,
            realtimeTransport = null,
            runsTimers = false,
            widgetFile = FileWidgetSnapshotFile(File(dir, "widget-snapshot.json")),
            reloadWidgetTimelines = {},
            todoStorage = NowTodoStorage(File(dir, "todos").path, JvmTodoFileSystem()),
            collation = NaturalKoNameCollation,
            drawableCharacters = CharacterArt.drawableCharacterSource,
            knownCharacterIDs = CharacterArt.portraitIds,
            isDemo = true, // 설명 시트를 띄우지 않는다(알림 권한 창 없이)
        ),
    )
    val screens = AppScreens(
        phone = phone,
        appearance = AppearanceStore(prefs),
        prefs = prefs,
        lifecycle = AppLifecycle(),
        currentBuild = 1,
        accountCleanup = DefaultAndroidAccountCleanup(InstrumentationRegistry.getInstrumentation().targetContext),
        screenArt = ScreenArt(null),
    )
    val requests = Channel<RouteRequest>(Channel.BUFFERED)

    fun close() = scope.cancel()
}

@RunWith(AndroidJUnit4::class)
class AssemblyDeviceTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private var app: AssembledStubApp? = null

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { app?.close() }
    }

    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun existsPrefix(prefix: String) = compose.onAllNodes(
        androidx.compose.ui.test.SemanticsMatcher("tag^$prefix") { it.config.getOrElseNullable(SemanticsProperties.TestTag) { null }?.startsWith(prefix) == true },
        useUnmergedTree = true,
    ).fetchSemanticsNodes().isNotEmpty()

    private fun hasText(text: String) = compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitFor(tag: String) = compose.waitUntil(20_000) { exists(tag) }

    private fun back() = instrumentation.runOnMainSync { compose.activity.onBackPressedDispatcher.onBackPressed() }

    private fun open(route: AingRoute) {
        app!!.requests.trySend(RouteRequest(route, accept = false))
    }

    /** 조립 셸을 그리고 로그인해 탭에 선다. */
    private fun signIn(duelsEnabled: Boolean): AssembledStubApp {
        val a = AssembledStubApp(instrumentation.targetContext.filesDir, duelsEnabled)
        app = a
        compose.setContent {
            AingTheme(dark = false) {
                CompositionLocalProvider(LocalScreenTicking provides false) {
                    val phase by a.phone.session.phaseFlow.collectAsState()
                    val flow = remember { a.requests.receiveAsFlow() }
                    AingShell(ShellPhases.of(phase), flow, onVisibleRoute = {}, onAccept = {}, app = a.screens)
                }
            }
        }
        instrumentation.runOnMainSync { a.phone.start() }
        waitFor(SessionTags.LOGIN_SCREEN)
        compose.onNodeWithTag(SessionTags.EMAIL).performTextInput("me@stub.invalid")
        compose.onNodeWithTag(SessionTags.PASSWORD).performTextInput("pw-123456")
        compose.onNodeWithTag(SessionTags.SIGN_IN).performClick()
        waitFor("tab-bar")
        waitFor(NowTags.SCREEN)
        return a
    }

    /** 오목 로비를 딥링크로 열고 신청 안내 줄이 서는지(로비 제목이 선 뒤에 판정). */
    private fun gomokuLobbyShowsDuelCaption(): Boolean {
        open(AingRoute.GomokuLobby)
        waitFor(GomokuScreenTags.screen)
        compose.waitUntil(20_000) { hasText(GomokuPhoneText.lobbyTitle) }
        compose.waitForIdle()
        return hasText(GomokuPhoneText.lobbyCaption)
    }

    @Test
    fun signInWalksFiveTabsEntersScreensAndBacksOutWithDuelsOff() {
        val a = signIn(duelsEnabled = false)

        // --- 탭 다섯 ---
        compose.onNodeWithTag("tab:messages").performClick()
        waitFor(MessagesTags.LIST_SCREEN)
        compose.onNodeWithTag("tab:rankings").performClick()
        compose.waitUntil(20_000) { existsPrefix(RankingsTags.SEGMENT_PREFIX) || existsPrefix(RankingsTags.SECTION_PREFIX) }
        compose.onNodeWithTag("tab:games").performClick()
        waitFor(GamesHubTags.GOMOKU)
        compose.onNodeWithTag("tab:me").performClick()
        waitFor(MeAnchor.Header.tag)
        compose.onNodeWithTag("tab:now").performClick()
        waitFor(NowTags.SCREEN)

        // --- 메시지: 목록 → 대화 → 뒤로 ---
        compose.onNodeWithTag("tab:messages").performClick()
        waitFor(MessagesTags.threadRow(StubPeople.HANGYEOL))
        compose.onNodeWithTag(MessagesTags.threadRow(StubPeople.HANGYEOL)).performClick()
        waitFor(MessagesTags.CONVERSATION_SCREEN)
        back()
        waitFor(MessagesTags.LIST_SCREEN)

        // --- 게임: 허브 → 오목(탭 막대 그대로 — 로비) → 뒤로 ---
        compose.onNodeWithTag("tab:games").performClick()
        waitFor(GamesHubTags.GOMOKU)
        compose.onNodeWithTag(GamesHubTags.GOMOKU).performClick()
        waitFor(GomokuScreenTags.screen)
        back()
        waitFor(GamesHubTags.GOMOKU)

        // --- 나: 설정(딥링크 — 라우터 한 문) → 뒤로 · 상점(탭 막대 숨김) → 뒤로(탭 막대 돌아옴) ---
        open(AingRoute.Settings)
        waitFor(SettingsTags.VERSION)
        back()
        waitFor(MeAnchor.Header.tag)
        open(AingRoute.Shop)
        compose.waitUntil(20_000) { exists("shop.screen") && !exists("tab-bar") }
        back()
        waitFor(MeAnchor.Header.tag)
        waitFor("tab-bar")

        // --- 판돈 깃발 꺼짐: 코어가 잠그고 로비에 신청 안내 줄이 없다 ---
        assertTrue("깃발 꺼짐인데 오목 판돈이 열려 있다", a.phone.gomoku.duelsLocked)
        assertFalse("깃발 꺼짐인데 신청 안내 줄이 섰다", gomokuLobbyShowsDuelCaption())
        assertEquals("로그인 요청이 한 번이 아니다", 1, a.server.calls.count { it.path == "/auth/v1/token" })
    }

    @Test
    fun duelsOnBuildShowsTheDuelEntry() {
        val a = signIn(duelsEnabled = true)
        assertFalse("깃발 켜짐인데 오목 판돈이 잠겼다", a.phone.gomoku.duelsLocked)
        assertTrue("깃발 켜짐인데 신청 안내 줄이 없다", gomokuLobbyShowsDuelCaption())
    }
}

/** 진짜 앱이 뜬다(MainActivity · AingApplication 조립). 시험 프로세스는 세션을 시작하지 않는다 — 실행 중 화면에 선다(망 0). */
@RunWith(AndroidJUnit4::class)
class AppLaunchDeviceTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    fun realAppLaunchesIntoTheAssembledShell() {
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(20_000) { compose.onAllNodesWithTag(SessionTags.LAUNCH, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as AingApplication
            assertTrue("조립 셸이 아니다(자리표시 셸)", app.container.shellScreens != null)
        }
    }
}
