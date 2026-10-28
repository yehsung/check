// 원본: Sources/CheckMobileKit/Me/MeFeedbackView.swift · MeProfileView.swift · MeCharacterViews.swift:383-684 · MeBlockedPeopleView.swift @ 3bd04bd
//
// 나 탭 하위 화면의 누름이 제 길로 가는지 데모 픽스처 스텁 서버(ScreenHarness — 요청을 기록한다)로 잰다(java.awt.headless=true).
// 스토어의 일은 시험 스케줄러에서 돈다 — 누른 뒤 advanceUntilIdle 로 돌리고, 서버에 나간 요청(경로 · 본문)과 화면에 남은 글자를 본다.
// 기준선(다른 입력): 빈 초안의 [보내기] · 확인을 취소한 [차단 해제] · 안 가진 캐릭터 누름은 요청을 보내지 않는다.
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.blockedAtLine
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.screens.settingscommon.BlockedPeopleScreen
import com.yehsung.aingcheck.ui.screens.settingscommon.BlockedPeopleTags
import com.yehsung.aingcheck.ui.screens.settingscommon.DemoFixtures
import com.yehsung.aingcheck.ui.screens.settingscommon.RepoScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenHarness
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenScene
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenTestCollation
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class, ExperimentalCoroutinesApi::class)
class MeSubScreensInteractionDesktopTest {
    private val art = RepoScreenArt(DesktopSnapshots.DENSITY) { DesktopSnapshots.repoImage(it) }

    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private fun ComposeUiTest.show(content: @Composable () -> Unit) {
        setContent { ScreenScene(false, art, Modifier) { Box(Modifier.size(380.dp, 900.dp)) { content() } } }
    }

    private fun TestScope.signedIn(override: (com.yehsung.aingcheck.testkit.mock.RecordedRequest) -> String? = { null }): ScreenHarness {
        val h = ScreenHarness(this, DemoFixtures(DemoFixtures.me), scenario = "me", override = override)
        h.signIn()
        return h
    }

    private fun ScreenHarness.calls(path: String): Int = requests.count { it.path == path }

    @Test
    fun feedbackSendsOnlyWithTextThenClearsTheDraft() = runTest {
        val h = signedIn()
        advanceUntilIdle()
        val store = h.meStore()
        runComposeUiTest {
            show { FeedbackScreen(store, h.storeScope) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            // 데모 목록 세 줄이 선다(접힌 줄엔 버전이 없다 → 누르면 펼쳐 버전 줄).
            val row = "d0000000-0000-4000-8000-00000000fb02"
            onNodeWithTag(FeedbackTags.LIST).performScrollToNode(hasTestTag(FeedbackTags.row(row)))
            onNodeWithText("0.3.31 (84) · 15.6.1", substring = true).assertDoesNotExist()
            onNodeWithTag(FeedbackTags.row(row)).performClick()
            waitForIdle()
            onNodeWithText("0.3.31 (84) · 15.6.1", substring = true).assertExists()

            // 기준선: 빈 초안은 못 보낸다.
            onNodeWithTag(FeedbackTags.LIST).performScrollToNode(hasTestTag(FeedbackTags.SEND))
            onNodeWithTag(FeedbackTags.SEND).assertIsNotEnabled()
            assertEquals(0, h.calls("/rest/v1/rpc/submit_feedback"))
            onNodeWithTag(FeedbackTags.EDITOR).performTextInput("위젯이 안 보여요")
            waitForIdle()
            onNodeWithText("9/1000").assertExists()
            onNodeWithTag(FeedbackTags.SEND).assertIsEnabled().performClick()
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(1, h.calls("/rest/v1/rpc/submit_feedback"))
            val body = h.requests.last { it.path == "/rest/v1/rpc/submit_feedback" }.bodyText
            assertTrue("위젯이 안 보여요" in body && "\"p_app_version\":\"Android 0.1.0 (1)\"" in body, "보낸 본문 · 앱 버전: $body")
            assertEquals("", store.feedbackDraft, "보낸 뒤에만 초안을 비운다")
            onNodeWithText(FeedbackText.sendSuccess).assertExists()
        }
    }

    /** 딥링크 feedback/<id> → 그 제보만 펼쳐 보인다(버전 줄은 펼친 줄에만). 기준선 = 가리키지 않은 다른 제보는 접힌 채. */
    @Test
    fun deepLinkedReportOpensExpanded() = runTest {
        val h = signedIn()
        advanceUntilIdle()
        val store = h.meStore()
        store.open(com.yehsung.aingcheck.core.stores.me.MeRoute.Feedback("d0000000-0000-4000-8000-00000000fb02"))
        runComposeUiTest {
            show { FeedbackScreen(store, h.storeScope) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            onNodeWithTag(FeedbackTags.LIST).performScrollToNode(hasTestTag(FeedbackTags.row("d0000000-0000-4000-8000-00000000fb02")))
            onNodeWithText("0.3.31 (84) · 15.6.1", substring = true).assertExists()
            // 가리키지 않은 첫 제보(iOS 0.1.0)는 접힌 채 — 버전 줄이 없다.
            onNodeWithTag(FeedbackTags.LIST).performScrollToNode(hasTestTag(FeedbackTags.row("d0000000-0000-4000-8000-00000000fb03")))
            onNodeWithText("0.1.0 (1) · iOS 26.5", substring = true).assertDoesNotExist()
        }
    }

    @Test
    fun pickerChoosesOwnedAndExplainsLocked() = runTest {
        val h = signedIn()
        advanceUntilIdle()
        val store = h.meStore()
        runComposeUiTest {
            show { CharacterPickerScreen(store, openShop = {}, openGachaMachine = {}) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            // 기준선: 안 가진(값 있는) 다람쥐 — 서버에 묻지 않고 얻는 길을 말한다.
            onNodeWithTag(CharacterPickerTags.tile("squirrel")).performScrollTo().performClick()
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(0, h.calls("/rest/v1/rpc/set_character"))
            assertTrue(store.characterNotice?.contains("상점에서 살 수 있어요") == true, "잠긴 캐릭터 안내: ${store.characterNotice}")
            // 가진 시바 → set_character 한 번.
            onNodeWithTag(CharacterPickerTags.tile("shiba")).performScrollTo().performClick()
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(1, h.calls("/rest/v1/rpc/set_character"))
            assertTrue("\"shiba\"" in h.requests.last { it.path == "/rest/v1/rpc/set_character" }.bodyText)
        }
    }

    @Test
    fun profileStatusCounterAndSave() = runTest {
        val h = signedIn()
        advanceUntilIdle()
        val store = h.meStore()
        runComposeUiTest {
            show { ProfileScreen(store, h.storeScope, onPickPhoto = {}, openCharacters = {}) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            // 저장된 상태가 있으면 입력이 그 값으로 차고 [지우기]가 선다.
            assertEquals("오후엔 리뷰 몰아서 해요 📝", store.statusMessageDraft)
            onNodeWithTag(ProfileTags.STATUS_CLEAR).performScrollTo().assertExists()
            onNodeWithTag(ProfileTags.STATUS_SAVE).assertIsNotEnabled()
            onNodeWithTag(ProfileTags.STATUS_FIELD).performTextInput("!")
            waitForIdle()
            onNodeWithText("16/40").assertExists()
            onNodeWithTag(ProfileTags.STATUS_SAVE).assertIsEnabled().performClick()
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(1, h.calls("/rest/v1/rpc/set_status_message"))
        }
    }

    @Test
    fun unblockGoesThroughConfirmation() = runTest {
        val listJson = """[{"user_id":"d0000000-0000-4000-8000-0000000000b9","display_name":"민트","avatar_url":null,"created_at":"2026-09-16T03:00:00+00:00"},
            {"user_id":"d0000000-0000-4000-8000-0000000000c1","display_name":"노을","avatar_url":null,"created_at":"2026-09-10T03:00:00+00:00"}]"""
        val h = signedIn { r ->
            when (r.path) {
                "/rest/v1/rpc/list_blocks" -> listJson
                "/rest/v1/rpc/unblock_user" -> "null"
                else -> null
            }
        }
        advanceUntilIdle()
        val messages = MessagesStore(h.context, h.storeScope, ScreenTestCollation)
        runComposeUiTest {
            show { BlockedPeopleScreen(messages) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            onNodeWithText("민트").assertExists()
            // 2026-09-16 03:00Z 차단 · 지금 2026-09-17 05:05Z — 시각 줄은 메시지 스토어의 상대 시각 눈금 그대로.
            onNodeWithText(BlockReportText.blockedAtLine(SwiftDate(1_789_527_600.0), h.clock.now())).assertExists()
            // 기준선: 확인을 취소하면 풀리지 않는다.
            onNodeWithTag(BlockedPeopleTags.unblock("d0000000-0000-4000-8000-0000000000b9")).performClick()
            waitForIdle()
            onNodeWithText(BlockReportText.unblockConfirmTitle("민트")).assertExists()
            onNodeWithText(BlockReportText.blockCancel).performClick()
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(0, h.calls("/rest/v1/rpc/unblock_user"))
            // 확인을 지나면 그 사람만 풀린다.
            onNodeWithTag(BlockedPeopleTags.unblock("d0000000-0000-4000-8000-0000000000b9")).performClick()
            waitForIdle()
            onNodeWithTag(BlockedPeopleTags.CONFIRM).performClick()
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(1, h.calls("/rest/v1/rpc/unblock_user"))
            onNodeWithText("민트").assertDoesNotExist()
            onNodeWithText("노을").assertExists()
        }
    }
}
