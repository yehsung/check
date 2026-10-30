// 원본: Sources/check/CheckMenuView.swift:1633-1643(TodayTimerText — store.todayDuration = displayNow 파생, 매초 이 텍스트만 무효화)
//       · Sources/check/WorkTimerStore.swift:3432-3436(tick() — 팝오버가 열려 있으면 displayNow = clock(), 1초 주기)
//       · CheckMenuView.swift:547-579(대결 신청 배너 — 대결 깃발 꺼짐이면 후보가 있어도 안 그린다)
// W3-c2 — 깃발·박자를 **부르는 자리(HomePage.Content)** 에서 잰다. BannerQueue.pick·HomePageModel.build 만 재는 시험은
// 페이지가 깃발을 안 넘기거나 박자를 끊어도 초록이라(반박 검증 mut1·mut2), 여기서 화면 마디로 단언한다.
// 픽스처는 합성(실제 사람·팀 없음). 박자 시험은 mainClock 을 손으로 민다 — 무한 박자는 runDesktopComposeUiTest 가 끝에 조합을 버려 닫힌다.
@file:OptIn(ExperimentalTestApi::class)

package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlin.test.Test
import kotlin.test.assertEquals

class HomePageGateAndTickTest {
    private val invite = DuelInviteBanner("m-1", "합성상대", 5, HomeTestKit.NOW.addingTimeInterval(45.0))

    /** 박자는 기본값(맥 1초)을 쓴다 — [tickMillis] 를 넘기지 않으면 HomePageDeps 기본 박자가 그대로 재진다. */
    private fun deps(w: HomeTestKit.FakeWork, duels: Boolean, clock: () -> SwiftDate) = HomePageDeps(
        work = w,
        commands = w,
        teamStatuses = MutableStateFlow(emptyList()),
        clock = clock,
        isSignedIn = { true },
        isTeamless = { false },
        myUserId = { HomeTestKit.ME },
        teamName = { "합성 팀" },
        teamGoalSeconds = { 40L * 3600 },
        duelsEnabled = duels,
        bannerFeed = { HomeBannerFeed(gomoku = invite) },
    )

    private fun acceptCount(duels: Boolean): Int {
        var n = -1
        runDesktopComposeUiTest(width = 414, height = 700) {
            val w = HomeTestKit.FakeWork()
            mainClock.autoAdvance = false
            setContent { AingTheme(dark = false) { HomePage(deps(w, duels) { HomeTestKit.NOW }).Content(InMemoryFlyoutNavigator(), 414.0) } }
            mainClock.advanceTimeByFrame()
            n = onAllNodesWithText(BUTTON_ACCEPT).fetchSemanticsNodes().size +
                onAllNodesWithText(invite.peerName, substring = true).fetchSemanticsNodes().size
        }
        return n
    }

    /**
     * 대결 깃발 꺼짐(duels=false) + 오목 신청 후보 → 페이지에 '수락'·상대 이름이 하나도 없다.
     * 기준선: 같은 후보·깃발 켜짐이면 둘 다 보인다(같은 입력이면 영원히 초록인 비교를 막는다).
     */
    @Test
    fun duelsOffHidesInviteOnPage() {
        val on = acceptCount(duels = true)
        assertEquals(2, on, "기준선: 깃발 켜짐이면 '수락' 1 + 상대 이름 1")
        assertEquals(0, acceptCount(duels = false), "깃발 꺼짐이면 대결 신청 배너가 페이지에 없다")
    }

    /**
     * 화면 시계: 기본 박자(1초)마다 clock 을 다시 읽어 오늘 타이머가 흐른다(맥 TodayTimerText · displayNow).
     * 박자 전에는 시계를 옮겨도 화면이 그대로다(값은 박자로만 들어온다) — 박자 뒤에는 새 값.
     */
    @Test
    fun todayTimerTicksEverySecondOnPage() = runDesktopComposeUiTest(width = 414, height = 700) {
        val w = HomeTestKit.FakeWork(DesktopWorkSnapshot(isWorking = true, startedAt = HomeTestKit.ago(307)))
        var t = HomeTestKit.NOW
        mainClock.autoAdvance = false
        setContent { AingTheme(dark = false) { HomePage(deps(w, duels = false) { t }).Content(InMemoryFlyoutNavigator(), 414.0) } }
        mainClock.advanceTimeByFrame()
        assertEquals(1, onAllNodesWithText("05:07").fetchSemanticsNodes().size, "처음 그림")

        t = HomeTestKit.NOW.addingTimeInterval(3.0)
        mainClock.advanceTimeBy(400)
        assertEquals(1, onAllNodesWithText("05:07").fetchSemanticsNodes().size, "박자 전에는 그대로")
        assertEquals(0, onAllNodesWithText("05:10").fetchSemanticsNodes().size, "박자 전에는 새 값 없음")

        mainClock.advanceTimeBy(700)
        assertEquals(1, onAllNodesWithText("05:10").fetchSemanticsNodes().size, "1초 박자 뒤 새 값")
        assertEquals(0, onAllNodesWithText("05:07").fetchSemanticsNodes().size, "옛 값은 사라진다")

        t = HomeTestKit.NOW.addingTimeInterval(4.0)
        mainClock.advanceTimeBy(1000)
        assertEquals(1, onAllNodesWithText("05:11").fetchSemanticsNodes().size, "다음 박자도 이어 흐른다")
    }

    private companion object {
        const val BUTTON_ACCEPT = "수락"
    }
}
