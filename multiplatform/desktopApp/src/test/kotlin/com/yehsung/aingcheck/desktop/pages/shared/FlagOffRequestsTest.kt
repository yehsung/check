// int-w2 배선(pages) — 깃발 꺼짐(poke·ultra)이면 그 페이지의 서버 경로 요청이 0 인지 **실제 컴포지션 + MockEngine 녹음**으로 잰다.
// 두 문을 따로 잰다: ① 라우트 문(SharedRouter.resolve — 페이지가 있어도 꺼진 라우트는 홈으로 접혀 컴포지션에 안 들어온다)
// ② 짓기 문(PagesWiring — 꺼진 기능의 페이지는 짓지도 않는다). 양성 짝(깃발 켬)이 같은 경로로 요청을 내야 기준선이 갈린다.
// 창 0 · 네트워크 0(FakeServer = MockEngine) · 박자 1시간(무한 박자 없음 — 장면은 use 로 닫는다).
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.pages.poke.PokeListDeps
import com.yehsung.aingcheck.desktop.pages.poke.PokeListPage
import com.yehsung.aingcheck.desktop.pages.ultra.DIRECTORY_PATH
import com.yehsung.aingcheck.desktop.pages.ultra.FakeServer
import com.yehsung.aingcheck.desktop.pages.ultra.FakeSessionHost
import com.yehsung.aingcheck.desktop.pages.ultra.FakeWorkState
import com.yehsung.aingcheck.desktop.pages.ultra.NO_LAPS
import com.yehsung.aingcheck.desktop.pages.ultra.TestClock
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPage
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPageDeps
import com.yehsung.aingcheck.desktop.pages.ultra.WALLET_PATH
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.wiring.PagesWiring
import com.yehsung.aingcheck.desktop.wiring.PagesWiringDeps
import com.yehsung.aingcheck.desktop.wiring.UltraPageInputs
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeSender
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraChargedSink
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraWalletTrigger
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletState
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class, ExperimentalComposeUiApi::class)
class FlagOffRequestsTest {
    private val profile = SessionProfile("u1", "a@b.c", teamID = "t1")

    /** 페이지 재료 한 벌(조립 꼴 — 지갑·발신자·콕 목록 의존). */
    private class Rig(scope: TestScope, server: FakeServer, config: DesktopAppConfig) {
        val clock = TestClock()
        val host = FakeSessionHost(server.service(clock::now))
        val work = FakeWorkState(true)
        val wallet = UltraWalletStore(host, FakeWorkState(), NO_LAPS, UltraChargedSink { }, scope, clock::now, initial = UltraWalletState(balance = 2))
        val pokeDeps = PokeListDeps(
            host = host, config = config,
            sender = DesktopPokeSender(host, scope, clock::now, localSessionOpen = { true }, wallet = UltraWalletTrigger { }),
            wallet = wallet, focus = null, scope = scope, clock = clock::now, localSessionOpen = { true }, workChanges = work.snapshot,
            clockTickMillis = 3_600_000L,
        )
        val ultraInputs = UltraPageInputs(wallet = wallet, purchase = null, ruby = RubyBalanceCell())
    }

    /** SharedFlyoutPageHost.PageBody 와 같은 길: 라우트 → SharedRouter.resolve → RoutePages.hostFor → Content. */
    private fun show(scope: TestScope, config: DesktopAppConfig, pages: RoutePages, route: FlyoutRoute): SharedPage {
        val nav = InMemoryFlyoutNavigator(route).also { it.open() }
        var shown: SharedPage = SharedPage.Launching
        val scene = ImageComposeScene(360, 420, Density(1f)) {
            AingTheme(dark = false) {
                val r by nav.route.collectAsState()
                val page = SharedRouter.resolve(SessionPhase.SignedIn, profile, true, r, config, pages.runtimeShown)
                shown = page
                pages.hostFor(page)?.Content(nav, 360.0)
            }
        }
        try {
            repeat(6) { i ->
                Snapshot.sendApplyNotifications()
                scope.testScheduler.runCurrent()
                scene.render(i * 16_666_667L).close()
                scope.testScheduler.runCurrent()
            }
        } finally {
            scene.close()
        }
        return shown
    }

    private fun wiring(rig: Rig, config: DesktopAppConfig) = PagesWiring(
        PagesWiringDeps(
            desktopConfig = config,
            settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore()),
            wallNow = { SwiftDate(1_793_000_000.0) },
            pokeList = rig.pokeDeps,
            ultra = rig.ultraInputs,
        ),
    )

    @Test
    fun `깃발 켬(양성 짝) — 콕 목록은 app_user_directory, 울트라는 ultra_wallet_sync 를 낸다`() = runTest {
        val config = DesktopAppConfig(poke = true, ultra = true)
        val server = FakeServer(this)
        val w = wiring(Rig(this, server, config), config)
        assertNotNull(w.pokeListPage)
        assertNotNull(w.ultraPage)
        assertEquals(SharedPage.PokeList, show(this, config, w.routePages, FlyoutRoute.PokeList))
        assertTrue(server.count("POST", DIRECTORY_PATH) >= 1, "양성 짝이 디렉터리를 안 읽었다 — 기준선이 갈리지 않는다")
        assertEquals(SharedPage.Ultra, show(this, config, w.routePages, FlyoutRoute.Ultra))
        assertTrue(server.count("POST", WALLET_PATH) >= 1, "양성 짝이 지갑 sync 를 안 냈다")
    }

    @Test
    fun `깃발 끔 — 짓기 문 — 페이지를 짓지 않고 라우트는 홈으로 접혀 두 경로 요청 0`() = runTest {
        val config = DesktopAppConfig(poke = false, ultra = false)
        val server = FakeServer(this)
        val w = wiring(Rig(this, server, config), config)
        assertNull(w.pokeListPage, "poke=false 인데 콕 목록을 지었다")
        assertNull(w.ultraPage, "ultra=false 인데 울트라 화면을 지었다")
        assertEquals(SharedPage.Home, show(this, config, w.routePages, FlyoutRoute.PokeList))
        assertEquals(SharedPage.Home, show(this, config, w.routePages, FlyoutRoute.Ultra))
        assertEquals(0, server.count("POST", DIRECTORY_PATH))
        assertEquals(0, server.count("POST", WALLET_PATH))
        assertEquals(0, server.calls.size, "깃발 끈 빌드가 서버에 무언가 보냈다: ${server.calls.map { it.path }}")
    }

    @Test
    fun `깃발 끔 — 라우트 문만으로도 — 페이지가 있어도 꺼진 라우트는 컴포지션에 안 들어온다`() = runTest {
        val off = DesktopAppConfig(poke = false, ultra = false)
        val server = FakeServer(this)
        val rig = Rig(this, server, DesktopAppConfig(poke = true, ultra = true))
        // 짓기 문을 우회해 페이지를 손으로 꽂는다 — 라우트 문 하나가 막는지 본다.
        val pages = RoutePages(
            pokeList = PokeListPage(rig.pokeDeps),
            ultra = UltraPage(UltraPageDeps(wallet = rig.wallet, purchase = null, ruby = RubyBalanceCell(), ultraPrice = { null })),
        )
        assertEquals(SharedPage.Home, show(this, off, pages, FlyoutRoute.PokeList))
        assertEquals(SharedPage.Home, show(this, off, pages, FlyoutRoute.Ultra))
        assertEquals(0, server.count("POST", DIRECTORY_PATH))
        assertEquals(0, server.count("POST", WALLET_PATH))
        // 같은 페이지 묶음 · 콕만 켬 → 콕은 요청, 울트라는 여전히 0(깃발 하나가 하나만 연다).
        val pokeOnly = DesktopAppConfig(poke = true, ultra = false)
        assertEquals(SharedPage.PokeList, show(this, pokeOnly, pages, FlyoutRoute.PokeList))
        assertEquals(SharedPage.Home, show(this, pokeOnly, pages, FlyoutRoute.Ultra))
        assertTrue(server.count("POST", DIRECTORY_PATH) >= 1)
    }
}
