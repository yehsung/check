// 원본: Sources/check/CheckComponents.swift:480-544(LongSessionBanner) · CheckMenuView.swift:551-558(배선) · WorkTimerStore.swift:2383-2387
// W3-c2 TwelveHourConfirmTest — 맥 문구 넷 그대로 · 분기 둘(계속 = 확인 한 번, 종료 = 종료 한 번) · 활성 판정 · 화면 클릭까지.
@file:OptIn(ExperimentalTestApi::class)

package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.desktop.pages.banners.BannerCandidates
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.pages.banners.TopBanner
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TwelveHourConfirmTest {
    private val working = DesktopWorkSnapshot(isWorking = true, startedAt = HomeTestKit.ago(12L * 3600 + 60))
    private val prompted = working.copy(longSessionPromptShownAt = HomeTestKit.ago(30))

    /** 맥 LongSessionBanner 의 Text(" … ") 넷이 코틀린 문구와 글자까지 같다(주석 걷고 대조). */
    @Test
    fun copyMatchesMacLiterally() {
        val src = HomeTestKit.stripLineComments(HomeTestKit.swiftSource("Sources/check/CheckComponents.swift"))
        val block = src.substringAfter("struct LongSessionBanner: View {").substringBefore("struct InlineActionBanner: View {")
        val texts = Regex("""Text\("([^"]+)"\)""").findAll(block).map { it.groupValues[1] }.toList()
        assertEquals(listOf(TwelveHourConfirm.title, TwelveHourConfirm.subtitle, TwelveHourConfirm.confirm, TwelveHourConfirm.stopNow), texts)
        val menu = HomeTestKit.stripLineComments(HomeTestKit.swiftSource("Sources/check/CheckMenuView.swift"))
        assertTrue("onConfirm: { store.confirmStillWorking() }" in menu, "맥 [네] = confirmStillWorking")
        assertTrue("onStopNow: { store.stop() }" in menu, "맥 [지금 종료] = stop(수동 종료)")
    }

    @Test
    fun continueConfirmsOnceAndNeverStops() {
        val w = HomeTestKit.FakeWork(prompted)
        TwelveHourConfirm.choose(TwelveHourConfirm.Choice.CONTINUE, w)
        assertEquals(listOf("confirm"), w.log)
        assertTrue(w.flow.value.isWorking, "계속이면 근무는 그대로")
    }

    @Test
    fun stopNowStopsOnceAndNeverConfirms() {
        val w = HomeTestKit.FakeWork(prompted)
        TwelveHourConfirm.choose(TwelveHourConfirm.Choice.STOP_NOW, w)
        assertEquals(listOf("stop"), w.log)
        assertFalse(w.flow.value.isWorking)
    }

    /** 활성 = promptShownAt 있음(맥 isLongSessionPromptActive). 활성이면 대결 신청·업데이트보다 먼저 선다. */
    @Test
    fun activeOnlyWhenPromptShownAndBeatsOtherBanners() {
        assertFalse(TwelveHourConfirm.isActive(working))
        assertTrue(TwelveHourConfirm.isActive(prompted))
        val invite = DuelInviteBanner("m", "합성상대", 3, HomeTestKit.NOW)
        val banners = BannerCandidates(isSignedIn = true, isTeamless = false, gomoku = invite, updateAvailable = true, duelsEnabled = true)
        assertEquals(TopBanner.LONG_SESSION, HomePageModel.build(HomeTestKit.inputs(snapshot = prompted, banners = banners), HomeTestKit.NOW).banner)
        assertEquals(TopBanner.GOMOKU_INVITE, HomePageModel.build(HomeTestKit.inputs(snapshot = working, banners = banners), HomeTestKit.NOW).banner)
    }

    /** 화면에서 [네, 근무 중이에요] 한 번 = confirm 한 번 → 배너가 걷힌다. [지금 종료] 한 번 = stop 한 번. */
    @Test
    fun bannerButtonsIssueExactlyOneCommand() = runDesktopComposeUiTest(width = 414, height = 700) {
        val w = HomeTestKit.FakeWork(prompted)
        val page = HomePage(homeDeps(w))
        setContent { AingTheme(dark = false) { page.Content(InMemoryFlyoutNavigator(), 414.0) } }
        onNodeWithText(TwelveHourConfirm.confirm).performClick()
        waitForIdle()
        assertEquals(listOf("confirm"), w.log)
        onNodeWithText(TwelveHourConfirm.confirm).assertDoesNotExist()

        w.flow.value = prompted
        waitForIdle()
        onNodeWithText(TwelveHourConfirm.stopNow).performClick()
        waitForIdle()
        assertEquals(listOf("confirm", "stop"), w.log)
    }

    companion object {
        internal fun homeDeps(w: HomeTestKit.FakeWork, members: MutableStateFlow<List<com.yehsung.aingcheck.core.wire.models.TeamMemberStatus>> = MutableStateFlow(emptyList())) =
            HomePageDeps(
                work = w,
                commands = w,
                teamStatuses = members,
                clock = { HomeTestKit.NOW },
                isSignedIn = { true },
                isTeamless = { false },
                myUserId = { HomeTestKit.ME },
                teamName = { "합성 팀" },
                teamGoalSeconds = { 40L * 3600 },
                duelsEnabled = false,
                tickMillis = null,
            )
    }
}
