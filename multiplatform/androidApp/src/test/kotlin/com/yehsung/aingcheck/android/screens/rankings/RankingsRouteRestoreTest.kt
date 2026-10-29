// 원본: 없음 — ⑥ 프로세스가 죽은 뒤 딥링크 복원(G §2-3 W3-b · E§5.1 "프로세스 죽음이 흔하다"). iOS 는 프로세스가 오래 살아 짝 시험이 없다.
//
// 딥링크 `aingcheck://rankings/tokens` 를 셸 길(ShellNavigator.open — 탭 그래프 뿌리 RankingsHome(board) 를 갈아 끼운다)로 연 뒤, 프로세스 죽음을
// StateRestorationTester 로 흉내 낸다(저장 상태만 남고 컴포지션·스토어가 새로 만들어진다 — 새 프로세스의 RankingsStore 는 기본 팀 리그다).
// 복원된 화면이 새 스토어를 인자가 정한 판으로 되돌리는지, 사용자가 그 뒤 고른 판이 인자보다 이기는지 잰다. 기준선: 딥링크 없이 열면 리그.
package com.yehsung.aingcheck.android.screens.rankings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.navigation
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.ShellNavigator
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.rankings.RankingsTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class RankingsRouteRestoreTest {
    @get:Rule
    val compose = createComposeRule()

    private val face = RankingsMyFace("fox", CharacterMood.Working)

    /** 새 프로세스의 순위 스토어(로그아웃 상태 — 판 고르기만 재고 서버는 두드리지 않는다). */
    private fun freshProcessStore(): RankingsStore {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val prefs = object : KeyValueStore {
            override fun getString(key: String): String? = null
            override fun putString(key: String, value: String) {}
            override fun getLong(key: String): Long? = null
            override fun putLong(key: String, value: Long) {}
            override fun getBoolean(key: String): Boolean? = null
            override fun putBoolean(key: String, value: Boolean) {}
            override fun remove(key: String) {}
        }
        val session = SessionStore(
            service = SupabaseWorkService(
                projectURL = "https://golden.invalid",
                anonKey = "stub",
                client = HttpClient(MockEngine { respond("", HttpStatusCode.NotFound) }) { SupabaseWorkService.clientConfig(this) },
                clock = { SessionClock.demoInstant },
                text = RulesWireTextRules,
                newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
            ),
            vault = InMemoryTokenVault(),
            prefs = prefs,
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String? = null
            },
            clock = SessionClock.fixed(SessionClock.demoInstant),
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = scope,
        )
        return RankingsStore(SessionContext(session), scope, object : Collation {
            override fun compare(a: String, b: String): Int = a.compareTo(b)
        })
    }

    private class Shell {
        var store: RankingsStore? by mutableStateOf(null)
        var navigator: ShellNavigator? = null
    }

    private fun setUp(shell: Shell): StateRestorationTester {
        val tester = StateRestorationTester(compose)
        tester.setContent {
            AingTheme(dark = false) {
                val nav = rememberNavController()
                shell.navigator = remember(nav) { ShellNavigator(nav) }
                NavHost(nav, startDestination = Dest.NowGraph) {
                    navigation<Dest.NowGraph>(startDestination = Dest.NowHome) { composable<Dest.NowHome> {} }
                    navigation<Dest.RankingsGraph>(startDestination = Dest.RankingsHome()) {
                        composable<Dest.RankingsHome> { entry ->
                            RankingsRouteScreen(requireNotNull(shell.store), entry.toRoute<Dest.RankingsHome>().board, face)
                        }
                    }
                }
            }
        }
        return tester
    }

    @Test
    fun deepLinkedBoardIsRestoredOnAFreshStoreAfterProcessDeath() {
        val shell = Shell().apply { store = freshProcessStore() }
        val tester = setUp(shell)
        compose.runOnIdle { requireNotNull(shell.navigator).open(AingRoute.Rankings(com.yehsung.aingcheck.android.routing.RankingsBoard.TOKENS)) }
        compose.waitForIdle()
        val first = requireNotNull(shell.store)
        assertEquals(RankingsBoard.tokens, first.board)
        compose.onNodeWithTag(RankingsTags.SECTION_PREFIX + "tokens").assertExists()

        // 프로세스 죽음: 저장 상태만 남고, 새 프로세스의 스토어는 기본(리그)이다.
        val fresh = freshProcessStore()
        assertEquals(RankingsBoard.league, fresh.board)
        shell.store = fresh
        tester.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        assertNotSame(first, shell.store)
        assertEquals("복원된 목적지 인자가 새 스토어를 딥링크 판으로 되돌려야 한다", RankingsBoard.tokens, fresh.board)
        compose.onNodeWithTag(RankingsTags.SECTION_PREFIX + "tokens").assertExists()
    }

    @Test
    fun userSelectionAfterDeepLinkWinsOverTheArgument() {
        val shell = Shell().apply { store = freshProcessStore() }
        val tester = setUp(shell)
        compose.runOnIdle { requireNotNull(shell.navigator).open(AingRoute.Rankings(com.yehsung.aingcheck.android.routing.RankingsBoard.TOKENS)) }
        compose.waitForIdle()
        compose.onNodeWithTag(RankingsTags.SEGMENT_PREFIX + "minigame").performClick()
        compose.waitForIdle()
        assertEquals(RankingsBoard.minigame, requireNotNull(shell.store).board)

        val fresh = freshProcessStore()
        shell.store = fresh
        tester.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        assertEquals("사용자가 고른 판(저장 상태)이 딥링크 인자보다 이긴다", RankingsBoard.minigame, fresh.board)
    }

    /** 기준선(다른 입력): 딥링크 없이 순위 탭을 열면 새 스토어는 리그 그대로다. */
    @Test
    fun withoutDeepLinkFreshStoreStaysOnLeague() {
        val shell = Shell().apply { store = freshProcessStore() }
        val tester = setUp(shell)
        compose.runOnIdle { requireNotNull(shell.navigator).selectTab(com.yehsung.aingcheck.android.routing.AingTab.RANKINGS) }
        compose.waitForIdle()
        val fresh = freshProcessStore()
        shell.store = fresh
        tester.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        assertEquals(RankingsBoard.league, fresh.board)
        compose.onNodeWithTag(RankingsTags.SECTION_PREFIX + "league").assertExists()
    }
}
