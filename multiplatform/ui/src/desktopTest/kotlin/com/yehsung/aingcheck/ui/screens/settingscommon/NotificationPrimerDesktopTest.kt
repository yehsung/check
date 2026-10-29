// 원본: Sources/CheckMobileKit/Push/PushPermissionPrimerView.swift @ 3bd04bd ([알림 켜기] · [나중에] — 권한 창이 떠 있는 동안 둘 다 잠긴다)
//
// 설명 시트의 누름(java.awt.headless=true). 받은 종류를 받은 순서로 세우고(체스 신청은 Android 에만 — 받으면 선다), 기호는 종류마다 정해져 있다.
// 기준선(다른 입력): 권한 창이 떠 있는 동안(isRequesting)에는 같은 누름이 아무것도 부르지 않는다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.icons.AppIcon
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalTestApi::class)
class NotificationPrimerDesktopTest {
    private val art = RepoScreenArt(DesktopSnapshots.DENSITY) { DesktopSnapshots.repoImage(it) }

    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private fun press(requesting: Boolean): Pair<Int, Int> {
        var allow = 0
        var later = 0
        runComposeUiTest {
            setContent {
                ScreenScene(false, art, Modifier) {
                    Box(Modifier.size(380.dp, 820.dp)) {
                        NotificationPrimerSheet(PrimerFixture.content(), requesting, onAllow = { allow += 1 }, onLater = { later += 1 })
                    }
                }
            }
            listOf("message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check").forEach { onNodeWithTag(NotificationPrimerTags.kind(it)).assertExists() }
            if (requesting) onNodeWithTag(NotificationPrimerTags.ALLOW).assertIsNotEnabled()
            onNodeWithTag(NotificationPrimerTags.ALLOW).performClick()
            onNodeWithTag(NotificationPrimerTags.LATER).performClick()
            waitForIdle()
        }
        return allow to later
    }

    @Test
    fun buttonsCallOnceAndLockWhileRequesting() {
        assertEquals(1 to 1, press(requesting = false))
        assertEquals(0 to 0, press(requesting = true), "권한 창이 떠 있는 동안 다시 묻지 않는다")
    }

    @Test
    fun kindIconsAreFixedAndUnknownFallsBackToBell() {
        assertEquals(AppIcon.ChatBubbleFill, NotificationPrimerIcons.of("message"))
        assertEquals(AppIcon.AppsFill, NotificationPrimerIcons.of("gomoku_invite"))
        assertEquals(AppIcon.Chess, NotificationPrimerIcons.of("chess_invite"))
        assertEquals(AppIcon.DraftsFill, NotificationPrimerIcons.of("feedback_reply"))
        assertEquals(AppIcon.ScheduleFill, NotificationPrimerIcons.of("work_check"))
        assertEquals(AppIcon.NotificationsFill, NotificationPrimerIcons.of("future_kind"))
    }
}
