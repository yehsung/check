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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    /** 이 시험은 셸(탭 · 딥링크 · 수락 증표)만 잰다 — 조립 화면 대신 자리표시 셸(K11 뒤 단계를 주입한다, W2-f §1). */
    @org.junit.Before
    fun placeholderShell() {
        androidx.test.core.app.ApplicationProvider.getApplicationContext<com.yehsung.aingcheck.android.app.AingApplication>().container.usePlaceholderShell()
    }

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
        ActivityScenario.launch<MainActivity>(real).use { scenario ->
            compose.onNodeWithText(route.url).assertExists()
            compose.waitUntil { app.container.pendingInviteAccept.value == route }
            // 처리한 Intent 는 라우트·수락 extra 가 지워져 있다(getIntent() 를 다시 읽어도 수락이 다시 실리지 않는다).
            scenario.onActivity { activity ->
                val kept = listOf(RouteIntents.EXTRA_ROUTE, RouteIntents.EXTRA_ACCEPT, RouteIntents.EXTRA_PROOF).filter(activity.intent::hasExtra)
                assertEquals("처리한 Intent 에 extra 가 남았다", emptyList<String>(), kept)
            }
        }
    }

    /**
     * G §8-13: 최근 앱(기록)에서 다시 띄우면 작업 뿌리 Intent 가 증표째 다시 온다(FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY).
     * 증표가 맞아도 수락은 버리고 화면만 연다. 기준선은 위 시험의 같은 증표·같은 라우트(기록 표시 없음 → 수락).
     */
    @Test
    fun historyRelaunchOfAcceptOpensTheInviteWithoutAccepting() {
        val route = AingRoute.GomokuInvite("m1")
        val proof = app.container.routeProof.value()!!
        val replay = RouteIntents.explicit(app, RouteRequest(route, accept = true), proof = proof)
            .addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)
        ActivityScenario.launch<MainActivity>(replay).use { scenario ->
            compose.onNodeWithText(route.url).assertExists()
            compose.waitForIdle()
            assertNull("기록에서 다시 온 수락이 통과했다", app.container.pendingInviteAccept.value)
            scenario.onActivity { activity ->
                assertFalse("기록 Intent 의 증표가 남았다", activity.intent.hasExtra(RouteIntents.EXTRA_PROOF))
            }
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
