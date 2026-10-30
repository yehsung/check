// int-w3(W-14 #5) — 홈 배너 대결 문을 **진짜 스토어**(GomokuStore·ChessStore)에 묶은 채 깃발 꺼짐에서 응답 RPC 0 인지 MockEngine 녹음으로 잰다.
// 스토어의 거절 경로는 깃발을 보지 않는다(GomokuStore.respond: 'accept && duelsLocked' 만 막는다) — 그래서 문을 막는 것은 홈 배너 쪽이어야 한다.
// 양성 짝(깃발 켬)이 같은 동작으로 그 경로를 내야 기준선이 갈린다. 창 0 · 네트워크 0(FakeServer = MockEngine).
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.pages.banners.TopBanner
import com.yehsung.aingcheck.desktop.pages.ultra.FakeServer
import com.yehsung.aingcheck.desktop.pages.ultra.FakeSessionHost
import com.yehsung.aingcheck.desktop.pages.ultra.TestClock
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.desktop.wiring.HomeBannerStores
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class HomeBannerStoresRequestsTest {
    private class Host(base: SessionHost, duels: Boolean, private val clock: TestClock) : GomokuStoreHost, SessionHost by base {
        override val realtimeState: RealtimeState = RealtimeState.Idle(IdleReason.disabled)
        override var rubyBalance: Long? = 100
        override val appConfig: AppConfig = AppConfig(duelsEnabled = duels)
        override fun now(): SwiftDate = clock.now()
    }

    private class Windows : DesktopGameWindows {
        val opened = mutableListOf<String>()
        override fun openGames(kind: com.yehsung.aingcheck.core.rules.minigame.MiniGameKind?) = Unit
        override fun openGomoku(focusMatchID: String?) { opened += "gomoku:$focusMatchID" }
        override fun openChess(focusMatchID: String?) { opened += "chess:$focusMatchID" }
        override fun openTetrisDuel(focusMatchID: String?) { opened += "tetris:$focusMatchID" }
        override fun openGacha() = Unit
        override fun openCakeGift() = Unit
        override fun closeAll() = Unit
    }

    private val invite = DuelInviteBanner("abcdef12-0000-4000-8000-00000000000a", "라이벌", 5, SwiftDate(1_793_000_060.0))

    private fun homeDeps(duels: Boolean): HomePageDeps {
        val w = HomeTestKit.FakeWork()
        return HomePageDeps(
            work = w, commands = w, teamStatuses = MutableStateFlow(emptyList()), clock = { HomeTestKit.NOW },
            isSignedIn = { true }, isTeamless = { false }, myUserId = { HomeTestKit.ME }, teamName = { "합성 팀" },
            teamGoalSeconds = { 40L * 3600 }, duelsEnabled = duels, tickMillis = null,
        )
    }

    private fun TestScope.rig(duels: Boolean): Triple<FakeServer, Windows, HomePageDeps> {
        val server = FakeServer(this)
        val clock = TestClock()
        val host = Host(FakeSessionHost(server.service(clock::now)), duels, clock)
        val gomoku = GomokuStore(this, host)
        val chess = ChessStore(this, host)
        val windows = Windows()
        val sources = HomeBannerSources(
            gomoku = HomeBannerStores.gomoku(gomoku) { windows },
            chess = HomeBannerStores.chess(chess) { windows },
            launch = { block -> launch { block() } },
        )
        val nav = InMemoryFlyoutNavigator().also { it.open(FlyoutRoute.Home) }
        return Triple(server, windows, homeDeps(duels).withBannerSources(sources, nav))
    }

    @Test
    fun `깃발 켬(양성 짝) — 거절은 gomoku_respond·chess_respond 를 낸다 · 보기는 그 판에 초점 둔 창`() = runTest {
        val (server, windows, d) = rig(duels = true)
        d.actions.declineDuel(TopBanner.GOMOKU_INVITE, invite)
        advanceUntilIdle()
        d.actions.declineDuel(TopBanner.CHESS_INVITE, invite)
        advanceUntilIdle()
        assertEquals(1, server.count("POST", GOMOKU_RESPOND), "양성 짝이 오목 응답을 안 냈다 — 기준선이 갈리지 않는다")
        assertEquals(1, server.count("POST", CHESS_RESPOND), "양성 짝이 체스 응답을 안 냈다")
        assertTrue(server.bodies("POST", GOMOKU_RESPOND).single().contains("\"p_accept\":false"))
        d.actions.openDuel(TopBanner.CHESS_INVITE, invite)
        assertEquals(listOf("chess:${invite.matchId}"), windows.opened)
    }

    @Test
    fun `깃발 끔 — 수락·거절·보기 모두 응답 RPC 0 · 서버 요청 0 · 창 0`() = runTest {
        val (server, windows, d) = rig(duels = false)
        for (banner in listOf(TopBanner.GOMOKU_INVITE, TopBanner.CHESS_INVITE)) {
            d.actions.acceptDuel(banner, invite)
            d.actions.declineDuel(banner, invite)
            d.actions.openDuel(banner, invite)
        }
        advanceUntilIdle()
        assertEquals(0, server.count("POST", GOMOKU_RESPOND))
        assertEquals(0, server.count("POST", CHESS_RESPOND))
        assertEquals(0, server.calls.size, "깃발 끈 빌드가 서버에 무언가 보냈다: ${server.calls.map { it.path }}")
        assertEquals(emptyList(), windows.opened, "깃발 끈 빌드가 대결 창을 열었다")
    }

    private companion object {
        const val GOMOKU_RESPOND = "/rest/v1/rpc/gomoku_respond"
        const val CHESS_RESPOND = "/rest/v1/rpc/chess_respond"
    }
}
