// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift:133·174 @ 3bd04bd (뽑기 기계 = fullScreenCover — 나가는 상점은 제자리에 있다)
//
// 8d 미해결: 셸 여백을 NavHost 한 벌에 입혀서, 뽑기 진입 · 종료 페이드(700ms) 동안 여백이 목적지 기준으로 즉시 바뀌었다 —
// 나가는 상점 화면이 상태 바 높이만큼 올라갔다 내려왔다. 전환 **가운데**(두 화면이 다 컴포지션에 있는 동안) 각 화면의 위치를 잰다.
package com.yehsung.aingcheck.android.nav

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.rememberNavController
import androidx.navigation.NavHostController
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "w400dp-h800dp-mdpi") // mdpi: 1dp = 1px — 좌표를 dp 로 바로 읽는다
class ShellBarsTransitionTest {
    private val shop = "placeholder:상점"
    private val machine = "placeholder:뽑기 기계"
    private val statusBar = 30f
    private val placeholderInset = 24f // PlaceholderScreen 안쪽 여백

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun outgoingScreenStaysPutWhileTheMachineFadesInAndOut() = runComposeUiTest {
        lateinit var nav: NavHostController
        setContent {
            nav = rememberNavController()
            TabsNavHost(nav, shellBars = PaddingValues(top = statusBar.dp, bottom = 48.dp))
        }
        waitForIdle()
        runOnUiThread { nav.navigate(Dest.Shop) }
        waitForIdle()
        fun top(tag: String) = onNode(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top
        assertEquals("상점은 셸 여백을 받는다", statusBar + placeholderInset, top(shop), 0.5f)

        mainClock.autoAdvance = false
        runOnUiThread { nav.navigate(Dest.GachaMachine) }
        mainClock.advanceTimeBy(150)
        assertEquals("뽑기 진입 전환 가운데 나가는 상점이 튄다", statusBar + placeholderInset, top(shop), 0.5f)
        assertEquals("뽑기 기계가 전환 가운데 셸 여백 안에 있다 — 끝날 때 튄다", placeholderInset, top(machine), 0.5f)
        mainClock.advanceTimeBy(1500)
        mainClock.autoAdvance = true
        waitForIdle()
        assertEquals("뽑기 기계가 셸 여백을 받는다 — 상태 바 자리에 띠가 남는다", placeholderInset, top(machine), 0.5f)

        mainClock.autoAdvance = false
        runOnUiThread { nav.popBackStack() }
        mainClock.advanceTimeBy(150)
        assertEquals("뽑기 종료 전환 가운데 나가는 뽑기 기계가 튄다", placeholderInset, top(machine), 0.5f)
        assertEquals("뽑기 종료 전환 가운데 돌아오는 상점이 튄다", statusBar + placeholderInset, top(shop), 0.5f)
        mainClock.advanceTimeBy(1500)
        mainClock.autoAdvance = true
        waitForIdle()
        assertEquals("돌아온 상점이 셸 여백을 잃었다", statusBar + placeholderInset, top(shop), 0.5f)
    }
}
