// int-w3(W-14 #5) 홈 배너 나머지 — 대결 신청(수락·거절·보기) · 제보 답장 · 케이크 선물.
// 맥 정답: CheckMenuView.swift:145-170(오목 [수락] 서버 응답 → 창 → 팝오버 닫기 · [거절] 응답만 · [보기] 창 → 팝오버 닫기) · 176-240(체스·테트리스 같은 순서)
// · 270-287(topBanner 순서) · 503-531(답장 [보기]=openFeedbackPanel · X=markFeedbackReplyBannerSeen · 케이크 [고르기], 닫기 없음).
// 순서는 사건 녹음으로, 깃발(duels) 꺼짐은 '읽기 0 · 부르기 0' 으로 잰다. 음성 대조: 공급자 없음(기본) · 깃발 켬(양성 짝).
package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.desktop.pages.banners.BannerCandidates
import com.yehsung.aingcheck.desktop.pages.banners.BannerQueue
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.pages.banners.TopBanner
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.wiring.PagesWiring
import com.yehsung.aingcheck.desktop.wiring.PagesWiringDeps
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class, ExperimentalTestApi::class)
class HomeBannerSourcesTest {
    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private val invite = DuelInviteBanner("m-1", "라이벌", 5, HomeTestKit.NOW.addingTimeInterval(60.0))

    /** 공급자 한 벌 + 사건 녹음. */
    private class Rig(scope: TestScope) {
        val events = mutableListOf<String>()
        var reads = 0
        var gomokuInvite: DuelInviteBanner? = null
        var unseen = false
        var cakeOpen = false
        fun duel(name: String) = DuelBannerSource(
            invite = { reads += 1; gomokuInvite },
            respond = { id, accept -> events += "$name.respond($id,$accept)" },
            openWindow = { id -> events += "$name.window($id)" },
        )
        val sources = HomeBannerSources(
            gomoku = duel("gomoku"),
            chess = duel("chess"),
            tetris = duel("tetris"),
            feedbackReply = FeedbackReplyBannerSource(unseen = { unseen }, markSeen = { events += "reply.seen" }),
            cakeGift = CakeGiftBannerSource(open = { cakeOpen }, choose = { events += "cake.choose" }),
            launch = { block -> scope.launch { block() } },
        )
    }

    private fun deps(duels: Boolean, base: HomeBannerActions = HomeBannerActions()): HomePageDeps {
        val w = HomeTestKit.FakeWork()
        return HomePageDeps(
            work = w, commands = w, teamStatuses = MutableStateFlow(emptyList()), clock = { HomeTestKit.NOW },
            isSignedIn = { true }, isTeamless = { false }, myUserId = { HomeTestKit.ME }, teamName = { "합성 팀" },
            teamGoalSeconds = { 40L * 3600 }, duelsEnabled = duels, actions = base, tickMillis = null,
        )
    }

    private fun pick(d: HomePageDeps): TopBanner? {
        val f = d.bannerFeed()
        return BannerQueue.pick(
            BannerCandidates(
                isSignedIn = true, isTeamless = false, gomoku = f.gomoku, chess = f.chess, tetris = f.tetris, retroDue = f.retroDue,
                feedbackReplyUnseen = f.feedbackReplyUnseen, cakeGiftOpen = f.cakeGiftOpen, duelsEnabled = d.duelsEnabled,
            ),
        )
    }

    /** 닫기도 사건으로 적는 내비(창·응답과 같은 줄에 놓여야 순서를 잰다). */
    private class RecNav(val events: MutableList<String>, private val inner: InMemoryFlyoutNavigator = InMemoryFlyoutNavigator()) : FlyoutNavigator by inner {
        override fun hide() {
            events += "nav.hide"
            inner.hide()
        }
    }

    private fun nav(r: Rig) = RecNav(r.events).also { it.open(FlyoutRoute.Home) }

    @Test
    fun `대결 수락 — 서버 응답 → 창 → 플라이아웃 닫기(맥 145-147 순서) · 거절은 응답만 · 보기는 창 → 닫기`() = runTest {
        val r = Rig(this)
        r.gomokuInvite = invite
        val n = nav(r)
        val d = deps(duels = true).withBannerSources(r.sources, n)
        assertEquals(TopBanner.GOMOKU_INVITE, pick(d))
        assertEquals(invite, d.bannerFeed().gomoku)

        d.actions.declineDuel(TopBanner.GOMOKU_INVITE, invite)
        advanceUntilIdle()
        assertEquals(listOf("gomoku.respond(m-1,false)"), r.events, "거절이 응답 말고 다른 일을 했다")
        assertTrue(n.visible.value, "거절이 플라이아웃을 닫았다(맥은 하던 일을 계속한다)")

        r.events.clear()
        d.actions.acceptDuel(TopBanner.CHESS_INVITE, invite)
        advanceUntilIdle()
        // 응답 → 창 → 닫기: 닫기가 창보다 먼저면 한 틱 동안 아무 표면도 없다.
        assertEquals(listOf("chess.respond(m-1,true)", "chess.window(m-1)", "nav.hide"), r.events, "수락 순서가 맥과 다르다")
        assertFalse(n.visible.value, "수락 뒤 플라이아웃이 닫히지 않았다")

        r.events.clear()
        n.open(FlyoutRoute.Home)
        d.actions.openDuel(TopBanner.TETRIS_INVITE, invite)
        advanceUntilIdle()
        assertEquals(listOf("tetris.window(m-1)", "nav.hide"), r.events, "[보기]가 응답을 냈거나 순서가 다르다")
        assertFalse(n.visible.value)
    }

    @Test
    fun `깃발 꺼짐 — 대결 문은 읽기 0 · 부르기 0 · 대결 배너 0(양성 짝은 켬)`() = runTest {
        val r = Rig(this)
        r.gomokuInvite = invite
        val n = nav(r)
        val off = deps(duels = false).withBannerSources(r.sources, n)
        assertNull(off.bannerFeed().gomoku)
        assertEquals(null, pick(off), "깃발 꺼짐인데 대결 배너가 골라졌다")
        off.actions.acceptDuel(TopBanner.GOMOKU_INVITE, invite)
        off.actions.declineDuel(TopBanner.GOMOKU_INVITE, invite)
        off.actions.openDuel(TopBanner.GOMOKU_INVITE, invite)
        advanceUntilIdle()
        assertEquals(0, r.reads, "깃발 꺼짐인데 신청을 읽었다")
        assertEquals(emptyList(), r.events, "깃발 꺼짐인데 대결 문을 불렀다")
        assertTrue(n.visible.value)
        // 양성 짝: 같은 공급자 · 깃발 켬 → 읽고 고른다.
        val on = deps(duels = true).withBannerSources(r.sources, n)
        assertEquals(TopBanner.GOMOKU_INVITE, pick(on))
        assertTrue(r.reads > 0)
    }

    @Test
    fun `제보 답장 — 보기는 제보 화면 열기 · X 는 봤음 · 회고보다 뒤 케이크보다 앞(맥 278-280)`() = runTest {
        val r = Rig(this)
        r.unseen = true
        r.cakeOpen = true
        val n = nav(r)
        val d = deps(duels = true).withBannerSources(r.sources, n)
        assertEquals(TopBanner.FEEDBACK_REPLY, pick(d), "답장이 케이크보다 먼저가 아니다")
        d.actions.openFeedback()
        assertEquals(FlyoutRoute.Feedback, n.route.value, "[보기]가 제보 화면으로 가지 않았다")
        assertTrue(n.visible.value, "[보기]는 '열기'다 — 플라이아웃을 닫으면 안 된다")
        d.actions.dismissFeedbackReply()
        assertEquals(listOf("reply.seen"), r.events)
        r.unseen = false
        assertEquals(TopBanner.CAKE_GIFT, pick(d), "답장을 본 뒤 케이크가 서지 않았다")
        // 회고가 있으면 회고가 먼저(같은 공급자 + 회고).
        val withRetro = deps(duels = true).assembled(HomeRetroBanner(due = { true }, seen = {}, displayed = {}), null).withBannerSources(r.sources, n)
        r.unseen = true
        assertEquals(TopBanner.RETRO, pick(withRetro))
    }

    @Test
    fun `케이크 — 고르기는 창(choose) 먼저 플라이아웃 나중 · 닫기 없음`() = runTest {
        val r = Rig(this)
        r.cakeOpen = true
        val n = nav(r)
        val d = deps(duels = true).withBannerSources(r.sources, n)
        assertEquals(TopBanner.CAKE_GIFT, pick(d))
        d.actions.openCakeGift()
        advanceUntilIdle()
        assertEquals(listOf("cake.choose", "nav.hide"), r.events, "창(고르기)보다 플라이아웃이 먼저 닫혔다")
    }

    @Test
    fun `공급자 없음(음성 대조) — 후보·동작이 원래 그대로`() = runTest {
        var feedbackOpened = 0
        val base = deps(duels = true, base = HomeBannerActions(openFeedback = { feedbackOpened += 1 }))
        val d = base.withBannerSources(null, InMemoryFlyoutNavigator())
        assertSame(base, d)
        assertEquals(HomeBannerFeed(), d.bannerFeed())
        assertEquals(null, pick(d))
        d.actions.openFeedback()
        assertEquals(1, feedbackOpened)
    }

    private fun ComposeUiTest.count(text: String): Int = onAllNodesWithText(text, substring = true, useUnmergedTree = true).fetchSemanticsNodes().size

    @Test
    fun `조립 — PagesWiring 홈이 공급자를 그린다 · 답장 보기 클릭 → 제보 화면 · 깃발 꺼짐이면 대결 글 0`() = runTest {
        for (duels in listOf(true, false)) {
            val r = Rig(this)
            r.gomokuInvite = invite
            r.unseen = true
            val n = nav(r)
            val w = PagesWiring(
                PagesWiringDeps(
                    desktopConfig = DesktopAppConfig(duels = duels),
                    settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore()),
                    wallNow = { HomeTestKit.NOW },
                    home = { deps(duels) },
                    homeBanners = r.sources,
                ),
            )
            val home = requireNotNull(w.homePage)
            runDesktopComposeUiTest(360, 900) {
                setContent { AingTheme(dark = false) { home.Content(n, 360.0) } }
                waitForIdle()
                if (duels) {
                    assertEquals(1, count("라이벌님이 오목 대결을 신청했어요"), "깃발 켬인데 대결 배너가 안 섰다")
                    // 배너는 한 번에 하나 — 대결이 답장보다 급하다.
                    assertEquals(0, count("제보에 답장이 왔어요"))
                    onNodeWithText("수락", useUnmergedTree = true).performClick()
                    waitForIdle()
                } else {
                    assertEquals(0, count("대결을 신청했어요"), "깃발 꺼짐인데 대결 배너가 섰다")
                    assertEquals(1, count("제보에 답장이 왔어요"), "답장 배너가 안 섰다")
                    onNodeWithText("보기", useUnmergedTree = true).performClick()
                    waitForIdle()
                }
            }
            advanceUntilIdle()
            if (duels) {
                assertEquals(listOf("gomoku.respond(m-1,true)", "gomoku.window(m-1)", "nav.hide"), r.events)
                assertFalse(n.visible.value)
            } else {
                assertEquals(0, r.reads)
                assertEquals(FlyoutRoute.Feedback, n.route.value)
                assertEquals(emptyList(), r.events)
            }
        }
    }
}
