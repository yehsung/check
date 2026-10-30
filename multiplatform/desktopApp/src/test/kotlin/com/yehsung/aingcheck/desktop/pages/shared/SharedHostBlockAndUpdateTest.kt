// int-w3(W-14 #2·#9) — 플라이아웃 뿌리(SharedFlyoutPageHost)가 ① 차단 문구 판을 맥으로 주는지(공용 20 LocalBlockReportPlatform — 맥
// WorkTimerStoreBlocks.swift:126 `.mac`: '설정 → 차단한 사람') ② 업데이트 필요 화면 [업데이트] 목적지를 스스로 읽는지(StoreUpdateDestination —
// 껍데기 덮개 없이) 실제 호스트 컴포지션으로 잰다. 음성 대조: 호스트 밖에서 같은 시트(폰 문구) · 목적지 없음(단추 0).
// 기대 글자는 규칙 함수를 다시 부르지 않고 박는다(시험이 같은 갈래로 규칙을 따라 읽으면 틀려도 초록). 창 0 · 네트워크 0(MockEngine).
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.desktop.shell.update.StoreUpdateDestination
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.screens.messages.MessagesBlockConfirmSheet
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalTestApi::class, ExperimentalCoroutinesApi::class)
class SharedHostBlockAndUpdateTest {
    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private companion object {
        const val MAC_UNDO = "설정 → 차단한 사람에서 언제든 풀 수 있어요."
        const val PHONE_UNDO = "나 → 설정 → 차단한 사람에서 언제든 풀 수 있어요."
        const val MAC_ITEM = "콕 찌르기·울트라를 서로 보낼 수 없어요"
        const val PHONE_ITEM = "이 대화가 목록에서 사라져요"
        const val MAC_LEDE = "차단한 사람과는 메시지·콕 찌르기를 주고받을 수 없고, 콕 찌르기 목록과 오목 신청에서도 서로 보이지 않아요."
        const val PHONE_LEDE = "차단한 사람과는 메시지를 주고받을 수 없고, 사람 찾기와 오목 신청에서도 서로 보이지 않아요."
        const val STORE_URL = "ms-windows-store://pdp/?ProductId=9NBLGGH4R315"
        const val STORE_BUTTON = "Microsoft Store 열기"
        val withTeamAndBlocks: (String) -> String? = { p -> SharedTestHarness.withTeam(p) ?: if (p.endsWith("/rpc/list_blocks")) "[]" else null }
        val needsUpdate: (String) -> String? = { p -> if (p.endsWith("/rpc/client_release")) SharedTestHarness.RELEASE_NEEDS_UPDATE else null }
    }

    private fun ComposeUiTest.count(text: String): Int = onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().size

    /** 스토어 일(시험 스케줄러)과 컴포즈 일을 번갈아 돌린다 — 무한 박자가 있어도 매달리지 않게 시간은 조금씩만. */
    private fun ComposeUiTest.settle(scope: TestScope) {
        repeat(8) {
            scope.testScheduler.advanceTimeBy(50)
            scope.testScheduler.runCurrent()
            waitForIdle()
        }
    }

    @Test
    fun `차단한 사람 — 플라이아웃 뿌리가 맥 판을 준다 · 폰 '나 →' 문구 0`() = runTest {
        val h = SharedTestHarness(this, answer = withTeamAndBlocks)
        h.signIn()
        advanceUntilIdle()
        h.nav.open(FlyoutRoute.Blocked)
        runDesktopComposeUiTest(360, 900) {
            setContent { h.host.Content(h.nav, 360.0) }
            settle(this@runTest)
            assertEquals(1, count(MAC_LEDE), "차단한 사람 머리말이 맥 판(콕 찌르기 목록)이 아니다")
            assertEquals(0, count(PHONE_LEDE), "플라이아웃 안 차단한 사람 화면에 폰 문구가 남았다")
        }
    }

    @Test
    fun `메시지 차단 확인 시트 — 호스트 안은 '설정 → 차단한 사람' · 호스트 밖(음성 대조)은 폰 문구`() = runTest {
        // 본문 자리에 탐침 페이지(메시지 화면이 여는 그 시트)를 꽂는다 — 대화 화면의 ··· → 차단하기가 여는 것과 같은 컴포저블.
        val probe = FlyoutPageHost { _, _ -> MessagesBlockConfirmSheet("라이벌", onConfirm = {}, onClose = {}) }
        val h = SharedTestHarness(this, answer = withTeamAndBlocks, routePages = RoutePages(home = probe))
        h.signIn()
        advanceUntilIdle()
        h.nav.open(FlyoutRoute.Home)
        runDesktopComposeUiTest(360, 900) {
            setContent { h.host.Content(h.nav, 360.0) }
            settle(this@runTest)
            assertEquals(1, count(MAC_UNDO), "호스트 안 차단 확인 되돌림 줄이 '설정 → 차단한 사람'이 아니다")
            assertEquals(1, count(MAC_ITEM), "호스트 안 차단 확인 항목이 맥 판(콕·울트라)이 아니다")
            assertEquals(0, count(PHONE_UNDO) + count(PHONE_ITEM), "호스트 안에 폰 문구가 남았다")
        }
        // 음성 대조: 같은 시트를 호스트 밖에서 그리면 폰 문구 — 탐침이 갈래를 가른다는 증거.
        runDesktopComposeUiTest(360, 900) {
            setContent { AingTheme(dark = false) { MessagesBlockConfirmSheet("라이벌", onConfirm = {}, onClose = {}) } }
            waitForIdle()
            assertEquals(1, count(PHONE_UNDO), "음성 대조가 폰 문구가 아니다 — 기준선이 갈리지 않는다")
            assertEquals(0, count(MAC_UNDO))
        }
    }

    @Test
    fun `업데이트 필요 — 목적지가 있으면 호스트가 Store 단추를 그리고 누르면 그 주소를 연다`() = runTest {
        val h = SharedTestHarness(this, answer = needsUpdate, updateDestination = STORE_URL)
        h.session.launch()
        advanceUntilIdle()
        h.nav.open(FlyoutRoute.Home)
        runDesktopComposeUiTest(360, 900) {
            setContent { h.host.Content(h.nav, 360.0) }
            settle(this@runTest)
            assertEquals(1, count("새 버전이 필요해요"), "업데이트 필요 화면이 아니다")
            assertEquals(1, count(STORE_BUTTON), "목적지가 있는데 [Microsoft Store 열기] 단추가 없다")
            onNodeWithText(STORE_BUTTON, useUnmergedTree = true).performClick()
            waitForIdle()
        }
        assertEquals(listOf(STORE_URL), h.opened, "단추가 Store 제품 페이지를 열지 않았다")
    }

    @Test
    fun `업데이트 필요 — 목적지 없음(음성 대조)이면 단추 0 · 여는 것 0 · 기본값은 생성 상수`() = runTest {
        val h = SharedTestHarness(this, answer = needsUpdate, updateDestination = null)
        h.session.launch()
        advanceUntilIdle()
        h.nav.open(FlyoutRoute.Home)
        runDesktopComposeUiTest(360, 900) {
            setContent { h.host.Content(h.nav, 360.0) }
            settle(this@runTest)
            assertEquals(1, count("새 버전이 필요해요"), "업데이트 필요 화면이 아니다")
            assertEquals(0, count(STORE_BUTTON), "목적지가 없는데 단추가 섰다")
        }
        assertEquals(emptyList(), h.opened)
        // 기본값(하네스 기본 = SharedPagesDeps 기본)은 생성 상수를 읽는다 — 시험 빌드는 자리표시라 null(단추 숨김, 골든 그대로).
        val defaults = SharedPagesDeps(
            session = h.session, sessionContext = h.context, messages = h.messages, rankings = h.rankings, me = h.me,
            appearance = h.appearance, config = h.config, currentBuild = SharedTestHarness.BUILD,
            rankingsFace = { RankingsMyFace("aing", CharacterMood.entries.first()) },
        )
        assertEquals(StoreUpdateDestination.windows, defaults.updateDestination, "SharedPagesDeps 기본 목적지가 생성 상수가 아니다")
    }
}
