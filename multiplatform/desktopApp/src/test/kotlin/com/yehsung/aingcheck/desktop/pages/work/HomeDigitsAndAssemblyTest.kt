// W-13 #1 — 홈 숫자: 번들 Pretendard + "tnum" 이면 숫자 폭이 같다(맥 .monospacedDigit 대응 — 타이머가 초마다 출렁이지 않는다).
// 기준선: tnum 없이는 같은 글꼴에서 '1111' 과 '0000' 폭이 다르다(그래야 이 시험이 무언가를 잰다).
// + 홈 조립(공용 19 회고 배너 손잡이 · 헤더 아래 자리) — 손잡이가 있으면 배너 후보·동작에 실리고, 없으면 그대로.
package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.fonts.pretendardFontFamily
import kotlinx.coroutines.flow.MutableStateFlow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue

class HomeDigitsAndAssemblyTest {
    @OptIn(ExperimentalComposeUiApi::class)
    private fun widths(features: String?): Pair<Int, Int> {
        var ones = 0
        var zeros = 0
        val scene = ImageComposeScene(400, 100, Density(1f)) {
            val m = rememberTextMeasurer()
            val style = TextStyle(fontFamily = pretendardFontFamily(), fontSize = 24.sp, fontFeatureSettings = features)
            ones = m.measure("11:11:11", style).size.width
            zeros = m.measure("00:00:00", style).size.width
        }
        try {
            repeat(3) { scene.render(it * 16_666_667L).close() }
        } finally {
            scene.close()
        }
        return ones to zeros
    }

    @Test
    fun `tnum 이면 숫자 폭이 같다 — 기준선(없으면 다르다)이 먼저`() {
        val (plainOnes, plainZeros) = widths(null)
        assertNotEquals(plainOnes, plainZeros, "기준선이 같다 — 비례 숫자 글꼴이 아니라 이 시험이 아무것도 못 잰다")
        val (ones, zeros) = widths(HomeDigits.TABULAR)
        assertEquals(ones, zeros, "tnum 을 줘도 숫자 폭이 갈린다(번들 글꼴에 tnum 이 없거나 기능 문자열이 틀렸다)")
    }

    private fun base(feed: HomeBannerFeed = HomeBannerFeed(), actions: HomeBannerActions = HomeBannerActions()): HomePageDeps {
        val w = HomeTestKit.FakeWork(DesktopWorkSnapshot())
        return HomePageDeps(
            work = w, commands = w, teamStatuses = MutableStateFlow(emptyList()), clock = { HomeTestKit.NOW }, isSignedIn = { true },
            isTeamless = { false }, myUserId = { HomeTestKit.ME }, teamName = { "합성 팀" }, teamGoalSeconds = { 40L * 3600 }, duelsEnabled = true,
            bannerFeed = { feed }, actions = actions, tickMillis = null,
        )
    }

    @Test
    fun `회고 손잡이 — 있으면 후보에 실리고 X·그려짐이 손잡이와 원래 동작을 함께 부른다`() {
        var due = true
        val log = mutableListOf<String>()
        val retro = HomeRetroBanner(due = { due }, seen = { log += "seen" }, displayed = { log += "displayed" })
        val d = base(actions = HomeBannerActions(dismissRetro = { log += "orig-dismiss" }, retroDisplayed = { log += "orig-displayed" }))
            .assembled(retro, middle = null)
        assertTrue(d.bannerFeed().retroDue)
        due = false
        assertFalse(d.bannerFeed().retroDue, "공급자를 매번 다시 읽지 않는다")
        d.actions.dismissRetro()
        d.actions.retroDisplayed()
        assertEquals(listOf("seen", "orig-dismiss", "displayed", "orig-displayed"), log)
    }

    @Test
    fun `회고 손잡이 없음(기본 null) — 배너 후보·동작이 그대로`() {
        val feed = HomeBannerFeed(feedbackReplyUnseen = true)
        val actions = HomeBannerActions()
        val src = base(feed, actions)
        val d = src.assembled(null, middle = null)
        assertSame(actions, d.actions)
        assertEquals(feed, d.bannerFeed())
        assertFalse(d.bannerFeed().retroDue)
        assertSame(src.middle, d.middle)
    }
}
