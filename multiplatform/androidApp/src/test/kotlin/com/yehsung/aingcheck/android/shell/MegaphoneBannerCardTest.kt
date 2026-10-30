// 원본: Tests/CheckMobileKitTests/MegaphoneBannerPhoneViewTests.swift `cardHasOnlyCloseButton` @ f3360b47(8e83aa35)
// 확성기 배너 카드의 단추는 [닫기] 하나(2026-10-30 사용자 결정 — [답장]을 걷었다). 소스 모양이 아니라 **그려진 카드**를 잰다:
// 상대를 아는 남의 배너(옛 [답장]이 붙던 바로 그 경우)를 띄워 누를 수 있는 것이 [닫기] 하나뿐이고, 누르면 배너가 닫히는지.
// 배너 스토어는 진짜(세션 없음 — 푸시로 안 확성기만), 타이머는 걸지 않는다(보여 주는 시간이 흐르지 않게).
package com.yehsung.aingcheck.android.shell

import androidx.compose.ui.test.assertCountEquals
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
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
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
}
