// 8b shell 증거(에뮬레이터): **조립된 셸**(AssemblyDeviceTest 와 같은 스텁 앱 한 벌)로 로그인해 탭 막대를 밝음 · 어두움으로 찍고,
// 알림 한 건을 앱 게시기(NotificationPoster)로 올려 상태 표시줄 · 펼친 알림을 찍는다. 찍기는 UiAutomation.takeScreenshot(화면 전체 —
// adb screencap 과 같은 판). PNG 는 앱 외부 파일 폴더 evidence/ 에 두고 호스트가 adb pull 한다(connectedAndroidTest 는 끝에 앱을 지워
// 폴더가 사라지므로 am instrument 로 돌린다 — xplat-r8b/shell 절차).
// 판정: 탭 막대 · 기호 칸 다섯이 서고, 메시지 배지가 서면 메시지 기호 칸 오른쪽 위에 얹힌다. 알림은 게시가 true.
package com.yehsung.aingcheck.android.shell

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.app.AssembledStubApp
import com.yehsung.aingcheck.android.push.AingChannel
import com.yehsung.aingcheck.android.push.NotificationChannels
import com.yehsung.aingcheck.android.push.NotificationPoster
import com.yehsung.aingcheck.android.push.NotificationSpec
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.android.screens.now.NowTags
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenTicking
import com.yehsung.aingcheck.ui.screens.session.SessionTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.receiveAsFlow
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class TabBarEvidenceDeviceTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private var app: AssembledStubApp? = null

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { app?.close() }
    }

    @Test fun lightTabBar() = tabBar(dark = false)
    @Test fun darkTabBar() = tabBar(dark = true)

    @Test
    fun notificationUsesAingIcon() {
        val context = instrumentation.targetContext
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, "android.permission.POST_NOTIFICATIONS")
        NotificationChannels.ensure(context)
        val spec = NotificationSpec(
            channel = AingChannel.entries.first(),
            title = "소라",
            body = "공지 채널에도 올려 두었어요",
            tag = "evidence-message",
            group = null,
            tap = RouteRequest(AingRoute.Messages),
            actions = emptyList(),
            category = android.app.Notification.CATEGORY_MESSAGE,
        )
        assertTrue("알림 게시 실패", NotificationPoster(context) { null }.post(spec))
        Thread.sleep(1500)
        shot("notification-statusbar")
        instrumentation.uiAutomation.executeShellCommand("cmd statusbar expand-notifications").close()
        Thread.sleep(2000)
        shot("notification-shade")
        instrumentation.uiAutomation.executeShellCommand("cmd statusbar collapse").close()
    }

    private fun tabBar(dark: Boolean) {
        val a = AssembledStubApp(instrumentation.targetContext.filesDir, duelsEnabled = false)
        app = a
        compose.setContent {
            AingTheme(dark = dark) {
                CompositionLocalProvider(LocalScreenTicking provides false) {
                    val phase by a.phone.session.phaseFlow.collectAsState()
                    val flow = remember { a.requests.receiveAsFlow() }
                    AingShell(ShellPhases.of(phase), flow, onVisibleRoute = {}, onAccept = {}, app = a.screens)
                }
            }
        }
        instrumentation.runOnMainSync { a.phone.start() }
        compose.waitUntil(20_000) { exists(SessionTags.LOGIN_SCREEN) }
        compose.onNodeWithTag(SessionTags.EMAIL).performTextInput("me@stub.invalid")
        compose.onNodeWithTag(SessionTags.PASSWORD).performTextInput("pw-123456")
        compose.onNodeWithTag(SessionTags.SIGN_IN).performClick()
        compose.waitUntil(20_000) { exists(ShellTabTags.BAR) && exists(NowTags.SCREEN) }
        for (tab in AingTab.entries) assertTrue("${tab.title} 기호 칸이 없다", exists(ShellTabTags.icon(tab)))
        // 메시지 배지(스텁의 안 읽은 줄)와 나 탭 초상이 읽히길 잠깐 기다린다 — 안 서도 찍는다(배지 위치는 섰을 때만 잰다).
        runCatching { compose.waitUntil(8_000) { exists(ShellTabTags.badge(AingTab.MESSAGES)) } }
        compose.waitForIdle()
        Thread.sleep(800)
        if (exists(ShellTabTags.badge(AingTab.MESSAGES))) {
            val badge = compose.onNodeWithTag(ShellTabTags.badge(AingTab.MESSAGES), useUnmergedTree = true).getBoundsInRoot()
            val icon = compose.onNodeWithTag(ShellTabTags.icon(AingTab.MESSAGES), useUnmergedTree = true).getBoundsInRoot()
            assertTrue("배지가 기호 오른쪽 위가 아니다 badge=$badge icon=$icon", badge.left > (icon.left + icon.right) / 2 && badge.top < icon.top)
        }
        shot("tab-bar-${if (dark) "dark" else "light"}")
    }

    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun shot(name: String) {
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot()) { "화면을 찍지 못했다" }
        val dir = File(instrumentation.targetContext.getExternalFilesDir(null), "evidence").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        println("AINGCHECK-EVIDENCE ${File(dir, "$name.png").path}")
    }
}
