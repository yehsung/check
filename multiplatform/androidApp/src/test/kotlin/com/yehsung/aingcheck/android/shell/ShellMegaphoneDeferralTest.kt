// 원본: Sources/CheckMobileKit/Messages/MegaphoneBannerPhoneRules.swift MegaphoneBannerModalProbe.isModalPresented @ a6791165(57810a8e)
// 확성기 배너 미룸 · 화면 안 시트·대화상자. 진짜 AlertDialog(액티비티 위 별도 창)를 띄우는 if 갈래가 ModalPresenceMark 로 알리면 셸의 판정
// (ShellMegaphoneDeferral.modalProbe — AingShell 이 쓰는 그 함수)이 참이 되고, 떠 있던 배너가 줄로 돌아간다. 닫으면 다시 뜬다.
// 배너 스토어는 진짜(세션 없음 — 푸시로 안 확성기만), 타이머는 걸지 않는다(8초가 흐르지 않게).
package com.yehsung.aingcheck.android.shell

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.LocalModalPresence
import com.yehsung.aingcheck.ui.components.ModalPresence
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ShellMegaphoneDeferralTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun sheetShownInsideAScreenDefersTheBannerAndClosingShowsItAgain() {
        val store = MegaphoneBannerStore(null, CoroutineScope(Dispatchers.Unconfined), null, clock = { SwiftDate(1_800_000_000.0) }, schedule = { _, _ -> })
        // 셸과 같은 배선: 창 수가 바뀌면 미룸을 다시 맞춘다 · 판정은 셸의 함수(지금 목적지는 화면 — 대화상자 목적지가 아니다).
        val modals = ModalPresence(onChange = { store.deferralChanged() })
        store.isBannerDeferred = ShellMegaphoneDeferral.modalProbe({ "composable" }, modals)
        var shows by mutableStateOf(false)
        compose.setContent {
            CompositionLocalProvider(LocalModalPresence provides modals) {
                if (shows) {
                    ModalPresenceMark()
                    AlertDialog(onDismissRequest = { shows = false }, confirmButton = {}, text = { Text("이모티콘") })
                }
            }
        }
        store.presentFromPush("mp-1", senderName = "보낸사람", body = "다들 화이팅")
        assertEquals("전제: 시트가 없으면 배너가 뜬다", "mp-1", store.current?.megaphoneID)

        shows = true
        compose.waitForIdle()
        assertEquals(1, modals.depth)
        assertNull("화면 안 시트가 떴는데 배너가 그 밑에서 8초를 쓴다", store.current)
        assertEquals("떠 있던 배너가 줄 맨 앞으로 돌아가지 않았다", listOf("mp-1"), store.queue.map { it.megaphoneID })

        shows = false
        compose.waitForIdle()
        assertEquals(0, modals.depth)
        assertEquals("시트를 닫았는데 배너가 다시 안 떴다", "mp-1", store.current?.megaphoneID)

        // 기준선: 대화상자 목적지는 계수기 없이도 미룬다 · 둘 다 없으면 미루지 않는다.
        assertTrue(ShellMegaphoneDeferral.modalProbe({ "dialog" }, ModalPresence())())
        assertFalse(ShellMegaphoneDeferral.modalProbe({ "composable" }, ModalPresence())())
    }
}
