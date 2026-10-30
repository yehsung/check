// 원본: Tests/CheckMobileKitTests/MegaphoneBannerPhoneViewTests.swift `cardHasOnlyCloseButton` · `voiceOverHoldsTheBanner` @ a3d59e74
// 확성기 배너 카드의 단추는 [닫기] 하나(2026-10-30 사용자 결정 — [답장]을 걷었다). 소스 모양이 아니라 **그려진 카드**를 잰다:
// 상대를 아는 남의 배너(옛 [답장]이 붙던 바로 그 경우)를 띄워 누를 수 있는 것이 [닫기] 하나뿐이고, 누르면 배너가 닫히는지.
// 화면 읽기(TalkBack): 오버레이가 켬 여부를 코어에 넘기고, 켬·끔 알림에 다시 판단하는지 — 걸린 타이머 길이로 잰다.
// 배너 스토어는 진짜(세션 없음 — 푸시로 안 확성기만), 타이머는 걸지 않는다(보여 주는 시간이 흐르지 않게).
package com.yehsung.aingcheck.android.shell

import android.view.accessibility.AccessibilityManager
import androidx.compose.ui.test.assertCountEquals
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.core.rules.text.MegaphoneBannerRules
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.phone.messages.MegaphoneBannerPhoneText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class MegaphoneBannerCardTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun cardHasOnlyTheCloseButtonAndItDismisses() {
        val store = MegaphoneBannerStore(null, CoroutineScope(Dispatchers.Unconfined), null, clock = { SwiftDate(1_800_000_000.0) }, schedule = { _, _ -> })
        compose.setContent { MegaphoneBannerOverlay(store) }
        // 상대를 아는 남의 배너 — 예전에는 여기에 [답장]이 붙었다.
        store.presentFromPush("mp-1", senderName = "보낸사람", body = "다들 화이팅", senderID = "00000000-0000-4000-8000-0000000000aa")
        compose.waitForIdle()
        assertEquals("전제: 배너가 떴다", "mp-1", store.current?.megaphoneID)

        // 기준선: 같은 카드에서 [닫기]는 찾힌다 — 아래 '없다'가 빈 화면으로 초록이 되지 않게.
        compose.onAllNodesWithTag(MegaphoneBannerTags.CARD).assertCountEquals(1)
        compose.onAllNodesWithText(MegaphoneBannerPhoneText.close).assertCountEquals(1)
        compose.onAllNodesWithText("답장").assertCountEquals(0)
        compose.onAllNodes(hasClickAction()).assertCountEquals(1)

        compose.onNodeWithTag(MegaphoneBannerTags.CLOSE).performClick()
        compose.waitForIdle()
        assertNull("[닫기]를 눌렀는데 배너가 남았다", store.current)
    }

    // 2026-10-31 모바일 세션 지적: 5초 안에 본문(최대 198자)을 다 못 듣고, "누르고 있으면 멈춤"은 화면 읽기 조작이 아니다.
    @Test
    fun talkBackHoldsAutoDismissAndTurningItOffCountsAgain() {
        val manager = ApplicationProvider.getApplicationContext<android.content.Context>().getSystemService(AccessibilityManager::class.java)
        shadowOf(manager).setTouchExplorationEnabled(true)
        val delays = mutableListOf<Double>()
        val store = MegaphoneBannerStore(null, CoroutineScope(Dispatchers.Unconfined), null, clock = { SwiftDate(1_800_000_000.0) }, schedule = { after, _ -> delays += after })
        compose.setContent { MegaphoneBannerOverlay(store) }
        compose.waitForIdle()
        assertTrue("오버레이가 TalkBack 켬 여부를 코어에 안 넘긴다", store.holdsAutoDismiss())
        store.presentFromPush("mp-2", senderName = "보낸사람", body = "천천히 들어요")
        compose.waitForIdle()
        assertEquals("전제: 배너가 떴다", "mp-2", store.current?.megaphoneID)
        assertFalse("TalkBack 이 켜져 있는데 저절로 닫는 타이머가 걸렸다: $delays", MegaphoneBannerRules.displaySeconds in delays)

        // 끄면(알림) 떠 있는 배너를 처음부터 5초 센다.
        shadowOf(manager).setTouchExplorationEnabled(false)
        compose.waitForIdle()
        assertFalse(store.holdsAutoDismiss())
        assertEquals("TalkBack 을 껐는데 다시 판단하지 않았다", listOf(MegaphoneBannerRules.displaySeconds), delays)
        assertTrue("힌트가 닫는 길을 안 알린다", MegaphoneBannerPhoneText.accessibilityHint.contains("저절로 닫히지 않아요") &&
            MegaphoneBannerPhoneText.accessibilityHint.contains(MegaphoneBannerPhoneText.close))
        assertFalse("힌트가 화면 읽기 사용자가 못 하는 손짓을 말한다", MegaphoneBannerPhoneText.accessibilityHint.contains("누르고 있으면"))
    }
}
