// 원본: 없음 — 탭 막대가 떠나는 문을 지나는 자리(ShellNavigator.tapTab)를 진짜 NavHost 로 잰다. 판단은 feature/phone PhoneRummyTabExitTest · iOS V1017RummyTabExitTests @ dba0c647.
package com.yehsung.aingcheck.android.nav

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runComposeUiTest
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.yehsung.aingcheck.android.routing.AingTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "w400dp-h800dp-mdpi")
class ShellDepartureTest {
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun tabBarGoesThroughTheDoorAndReselectStays() = runComposeUiTest {
        lateinit var nav: NavHostController
        setContent {
            nav = rememberNavController()
            TabsNavHost(nav)
        }
        waitForIdle()
        val navigator = runOnUiThread { ShellNavigator(nav) }
        runOnUiThread {
            navigator.selectTab(AingTab.GAMES)
        }
        waitForIdle()
        runOnUiThread { nav.navigate(Dest.Rummy) }
        waitForIdle()
        fun onRummy() = runOnUiThread { nav.currentDestination?.hasRoute(Dest.Rummy::class) == true }
        assertTrue("전제: 큐브 화면", onRummy())

        var asked = 0
        var after = 0
        var held: (() -> Unit)? = null
        val refuse: (() -> Unit) -> Unit = {
            asked += 1
            held = it
        }

        // 고른 탭 다시 누르기: 묻지 않고 그 화면에 머문다(뿌리로 안 간다 — 그래서 떠나는 길이 아니다).
        runOnUiThread { navigator.tapTab(AingTab.GAMES, refuse) { after += 1 } }
        waitForIdle()
        assertEquals("같은 탭을 이탈로 읽었다", 0, asked)
        assertTrue("탭 재선택이 큐브 화면을 떠났다 — 떠나는 문을 지나야 한다", onRummy())
        assertEquals(1, after)

        // 다른 탭: 문이 막으면 그대로다(방장이 묻는 중).
        runOnUiThread { navigator.tapTab(AingTab.ME, refuse) { after += 1 } }
        waitForIdle()
        assertEquals(1, asked)
        assertTrue("문이 막았는데 탭이 옮겨 갔다", onRummy())
        assertEquals(1, after)

        // 수락: 그제야 간다.
        runOnUiThread { held?.invoke() }
        waitForIdle()
        assertFalse("수락했는데 안 옮겨 갔다", onRummy())
        assertEquals(2, after)
        assertTrue(runOnUiThread { navigator.isCurrentTab(AingTab.ME) })

        // 돌아오면 그 탭 스택(큐브 화면 — 로비로 선다)이 돌아온다.
        runOnUiThread { navigator.tapTab(AingTab.GAMES, { it() }) { after += 1 } }
        waitForIdle()
        assertTrue("돌아오면 큐브 화면(로비)이어야 한다", onRummy())
    }

    /** 조립 셸의 탭 막대가 문을 지난다(자리표시 셸은 스토어가 없어 직행). 다른 길이 생기면 빨개진다. */
    @Test
    fun assembledShellTabBarUsesTheDoor() {
        val source = listOf("src/main/kotlin/com/yehsung/aingcheck/android/shell/AingShell.kt", "androidApp/src/main/kotlin/com/yehsung/aingcheck/android/shell/AingShell.kt")
            .map(::File).first { it.exists() }.readText()
            .lines().filterNot { it.trimStart().startsWith("//") }.joinToString("\n")
        val assembled = source.substringAfter("private fun SignedInTabs")
        assertTrue(assembled.contains("navigator.tapTab(tab, phone.router::departing)"))
        assertFalse("문을 안 지나는 탭 옮기기", assembled.substringBefore("internal object ShellMegaphoneDeferral").contains("navigator.selectTab("))
    }
}
