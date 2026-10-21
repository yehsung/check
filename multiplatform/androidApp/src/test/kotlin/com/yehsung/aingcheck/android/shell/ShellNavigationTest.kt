// 셸: 딥링크가 그 탭 위에 화면을 쌓는다 · 탭마다 자기 백스택 · 다시 만들어진 Activity 는 같은 딥링크를 다시 열지 않는다 ·
// 보이는 라우트가 VisibleRoute 에 적힌다(푸시 숨김). 기기 위 작업·인스턴스(E-U16)는 에뮬레이터 시나리오가 잰다.
package com.yehsung.aingcheck.android.shell

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class ShellNavigationTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app get() = ApplicationProvider.getApplicationContext<AingApplication>()

    private fun deepLink(url: String) = Intent(Intent.ACTION_VIEW, Uri.parse(url), app, MainActivity::class.java)

    @Test
    fun deepLinkStacksOnItsTabAndTabsKeepTheirStacks() {
        val conversation = AingRoute.Message("abc-123")
        ActivityScenario.launch<MainActivity>(deepLink(conversation.url)).use { scenario ->
            compose.onNodeWithText(conversation.url).assertExists()
            compose.onNodeWithTag("tab:messages").assertIsSelected()
            compose.waitUntil { app.container.visibleRoute.route.value == conversation }

            compose.onNodeWithTag("tab:now").performClick()
            compose.onNodeWithText(AingRoute.Now.url).assertExists()
            compose.waitUntil { app.container.visibleRoute.route.value == AingRoute.Now }

            // 메시지 탭으로 돌아오면 그 탭의 스택(대화)이 그대로다.
            compose.onNodeWithTag("tab:messages").performClick()
            compose.onNodeWithText(conversation.url).assertExists()

            // 다시 만들어져도(저장 상태 복원) 처음 딥링크를 다시 열지 않는다: 지금 탭에 둔 채 다시 만들면 지금 탭이다.
            compose.onNodeWithTag("tab:now").performClick()
            scenario.recreate()
            compose.onNodeWithText(AingRoute.Now.url).assertExists()
            compose.onNodeWithTag("tab:now").assertIsSelected()
            // 메시지 탭의 대화는 복원된 저장 상태에서 돌아온다.
            compose.onNodeWithTag("tab:messages").performClick()
            compose.onNodeWithText(conversation.url).assertExists()
        }
    }

    @Test
    fun rankingsDeepLinkReplacesTheRootSegment() {
        ActivityScenario.launch<MainActivity>(deepLink("aingcheck://rankings/tokens")).use {
            compose.onNodeWithText("aingcheck://rankings/tokens").assertExists()
            compose.onNodeWithTag("tab:rankings").assertIsSelected()
        }
    }

    /** 알림 [수락]: 증표가 맞으면 신청 화면 + 수락 요청 한 번, 틀리면 화면만(다른 앱이 흉내 낸 Intent). */
    @Test
    fun notificationAcceptNeedsProofAndOpensTheInvite() {
        val route = AingRoute.GomokuInvite("m1")
        val proof = app.container.routeProof.value()!!
        val forged = RouteIntents.explicit(app, RouteRequest(route, accept = true), proof = "0".repeat(64))
        ActivityScenario.launch<MainActivity>(forged).use {
            compose.onNodeWithText(route.url).assertExists()
            compose.waitForIdle()
            assertNull("증표가 틀린 수락이 통과했다", app.container.pendingInviteAccept.value)
        }
        val real = RouteIntents.explicit(app, RouteRequest(route, accept = true), proof = proof)
        ActivityScenario.launch<MainActivity>(real).use {
            compose.onNodeWithText(route.url).assertExists()
            compose.waitUntil { app.container.pendingInviteAccept.value == route }
        }
    }

    @Test
    fun unknownDeepLinkStaysOnTheStartTab() {
        ActivityScenario.launch<MainActivity>(deepLink("aingcheck://nope/1")).use {
            compose.onNodeWithText(AingRoute.Now.url).assertExists()
            compose.onNodeWithTag("tab:now").assertIsSelected()
            compose.waitUntil { app.container.visibleRoute.route.value == AingRoute.Now }
        }
    }
}
