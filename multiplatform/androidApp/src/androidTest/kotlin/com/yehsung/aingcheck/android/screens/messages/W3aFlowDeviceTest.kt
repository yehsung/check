// 원본: Sources/CheckMobileKit/Messages/MessagesConversationView.swift @ 3bd04bd (moreMenu · reportMessage · confirmBlock)
// 원본: Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift @ 3bd04bd (차단 확인 · 신고 시트 — 보내는 문은 하나)
// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (로그인)
//
// G §2-3 W3-a ② 계측(스텁 픽스처): 로그인 → 탭 → 메시지 보내기 → 차단·신고 세 입구. 에뮬레이터 ART 위에서 진짜 SessionStore · MessagesStore ·
// 진입 함수 · 화면을 돌리고, 서버로 나간 요청(스텁 기록)으로 판정한다(화면 글자가 아니라 나간 본문 · 대상 · 키).
// 세 입구(E§4.3): ① 대화 머리 ⋮ 메뉴 ② 받은 말풍선 길게 누르기 ③ 오목 채팅 서랍 ⋮(W4-a 가 다는 같은 단추 · 같은 시트 — 여기서는 그 단추를 홀로 세운다).
package com.yehsung.aingcheck.android.screens.messages

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.screens.now.NowTags
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.ui.screens.messages.MessagesBlockConfirmSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesTags
import com.yehsung.aingcheck.ui.screens.messages.ReportBlockMenuButton
import com.yehsung.aingcheck.ui.screens.session.SessionTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalTestApi::class)
class W3aFlowDeviceTest {
    @get:Rule
    val compose = createComposeRule()

    private lateinit var app: DeviceApp
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Before
    fun setUp() {
        instrumentation.runOnMainSync {
            app = DeviceApp(instrumentation.targetContext.filesDir)
            app.scope.launch { app.session.launch() }
        }
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { app.close() }
    }

    private fun exists(tag: String): Boolean = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitFor(tag: String, timeout: Long = 15_000) = compose.waitUntil(timeout) { exists(tag) }

    private fun waitGone(tag: String, timeout: Long = 15_000) = compose.waitUntil(timeout) { !exists(tag) }

    private fun fieldText(tag: String): String =
        compose.onNodeWithTag(tag).fetchSemanticsNode().config.getOrElseNullable(SemanticsProperties.EditableText) { null }?.text ?: "<없음>"

    @Test
    fun loginThenTabsThenSendThenReportAndBlockFromConversation() {
        compose.setContent { W3aDeviceShell(app) }

        // --- 로그인(로그아웃 단계 → 로그인 화면 → 토큰 왕복 → 탭) ---
        waitFor(SessionTags.LOGIN_SCREEN)
        compose.onNodeWithTag(SessionTags.EMAIL).performTextInput("me@stub.invalid")
        compose.onNodeWithTag(SessionTags.PASSWORD).performTextInput("pw-123456")
        compose.onNodeWithTag(SessionTags.SIGN_IN).performClick()
        waitFor("tab-bar")
        val token = app.server.calls.single { it.path == "/auth/v1/token" }
        assertTrue("로그인 본문에 친 이메일이 없다: ${token.body}", token.body.contains("me@stub.invalid"))
        waitFor(NowTags.SCREEN)

        // --- 메시지 탭: 네 무리 정렬(안 읽음 소라가 위) ---
        compose.onNodeWithTag("tab:messages").performClick()
        waitFor(MessagesTags.threadRow(StubPeople.HANGYEOL))
        waitFor(MessagesTags.threadRow(StubPeople.SORA))
        val soraTop = compose.onNodeWithTag(MessagesTags.threadRow(StubPeople.SORA)).fetchSemanticsNode().boundsInRoot.top
        val hangyeolTop = compose.onNodeWithTag(MessagesTags.threadRow(StubPeople.HANGYEOL)).fetchSemanticsNode().boundsInRoot.top
        assertTrue("안 읽은 소라가 다 읽은 한결보다 위가 아니다", soraTop < hangyeolTop)

        // --- 대화 열기 → 보내기 ---
        compose.onNodeWithTag(MessagesTags.threadRow(StubPeople.HANGYEOL)).performClick()
        waitFor(MessagesTags.CONVERSATION_SCREEN)
        waitFor(MessagesTags.bubble(StubPeople.RECEIVED_MESSAGE))
        compose.onNodeWithTag(MessagesTags.COMPOSER_FIELD).performTextInput("오늘 회의 몇 시예요?")
        compose.onNodeWithTag(MessagesTags.SEND).performClick()
        compose.waitUntil(15_000) { app.server.rpcCalls("send_message").isNotEmpty() }
        val send = app.server.rpcCalls("send_message").single()
        assertEquals(StubPeople.HANGYEOL, send.field("p_to"))
        assertEquals("오늘 회의 몇 시예요?", send.field("p_body"))
        assertEquals("보낸 뒤 입력칸이 비어야 한다", "", fieldText(MessagesTags.COMPOSER_FIELD))
        // 서버 행으로 선다(자리 말풍선은 다음 이력이 거둔다).
        waitFor(MessagesTags.bubble("d0000000-0000-4000-8000-0000000a0000"))

        // --- 입구 ①: 머리 ⋮ → 신고하기 → 사유 → (차단 끔) → 보내기 ---
        compose.onNodeWithTag(MessagesTags.MORE_MENU).performClick()
        waitFor(MessagesTags.MENU_REPORT)
        compose.onNodeWithTag(MessagesTags.MENU_REPORT).performClick()
        waitFor(MessagesTags.REPORT_SHEET)
        compose.onNodeWithTag(MessagesTags.reportReason("spam")).performClick()
        compose.onNodeWithTag(MessagesTags.REPORT_ALSO_BLOCK).performClick()
        compose.onNodeWithTag(MessagesTags.REPORT_SUBMIT).performClick()
        compose.waitUntil(15_000) { app.server.rpcCalls("report_content").size == 1 }
        val personReport = app.server.rpcCalls("report_content")[0]
        assertEquals(StubPeople.HANGYEOL, personReport.field("p_target"))
        assertEquals("spam", personReport.field("p_reason"))
        assertNull("사람 신고에 메시지 id 가 실렸다", personReport.field("p_message_id"))
        assertEquals("false", personReport.field("p_block"))
        waitGone(MessagesTags.REPORT_SHEET)
        assertTrue("신고 뒤에도 대화는 그대로다(차단 끔)", exists(MessagesTags.CONVERSATION_SCREEN))
        assertTrue(app.server.rpcCalls("block_user").isEmpty())

        // --- 입구 ②: 받은 말풍선 길게 누르기 → 이 메시지 신고하기 → (신고하면서 차단 — 기본 켬) ---
        compose.onNodeWithTag(MessagesTags.bubble(StubPeople.RECEIVED_MESSAGE)).performTouchInput { longClick(Offset(60f, centerY)) }
        waitFor(MessagesTags.MENU_REPORT_MESSAGE)
        compose.onNodeWithTag(MessagesTags.MENU_REPORT_MESSAGE).performClick()
        waitFor(MessagesTags.REPORT_SHEET)
        compose.onNodeWithTag(MessagesTags.reportReason("harassment")).performClick()
        compose.onNodeWithTag(MessagesTags.REPORT_SUBMIT).performClick()
        compose.waitUntil(15_000) { app.server.rpcCalls("report_content").size == 2 }
        val messageReport = app.server.rpcCalls("report_content")[1]
        assertEquals(StubPeople.HANGYEOL, messageReport.field("p_target"))
        assertEquals(StubPeople.RECEIVED_MESSAGE, messageReport.field("p_message_id"))
        assertEquals("true", messageReport.field("p_block"))
        // 신고하면서 차단 → 그 대화는 사라졌다 — 목록으로 빠져나오고 한결 줄이 없다.
        waitFor(MessagesTags.LIST_SCREEN)
        waitGone(MessagesTags.threadRow(StubPeople.HANGYEOL))

        // --- 차단(확인 시트 하나): 소라 대화 ⋮ → 차단하기 → 확인 ---
        compose.onNodeWithTag(MessagesTags.threadRow(StubPeople.SORA)).performClick()
        waitFor(MessagesTags.CONVERSATION_SCREEN)
        compose.onNodeWithTag(MessagesTags.MORE_MENU).performClick()
        waitFor(MessagesTags.MENU_BLOCK)
        compose.onNodeWithTag(MessagesTags.MENU_BLOCK).performClick()
        waitFor(MessagesTags.BLOCK_SHEET)
        assertTrue("확인 전에 차단이 나갔다", app.server.rpcCalls("block_user").isEmpty())
        compose.onNodeWithTag(MessagesTags.BLOCK_CONFIRM).performClick()
        compose.waitUntil(15_000) { app.server.rpcCalls("block_user").isNotEmpty() }
        assertEquals(StubPeople.SORA, app.server.rpcCalls("block_user").single().field("p_user"))
        waitFor(MessagesTags.LIST_SCREEN)
        waitGone(MessagesTags.threadRow(StubPeople.SORA))
        println("AINGCHECK-W3A-FLOW calls=${app.server.calls.size} send=1 report=2 block=1")
    }

    /** 입구 ③: 오목 채팅 서랍(W4-a)이 다는 ⋮ 단추 — 같은 메뉴 · 같은 두 시트 · 같은 스토어 문(신고 ReportSheetEntry · 차단 확인). */
    @Test
    fun chatDrawerMenuReachesTheSameReportAndBlockSheets() {
        instrumentation.runOnMainSync { app.scope.launch { app.session.signIn("me@stub.invalid", "pw-123456") } }
        compose.waitUntil(15_000) { app.session.isSignedIn }
        compose.setContent {
            AingTheme(dark = false) {
                var reporting by remember { mutableStateOf(false) }
                var blocking by remember { mutableStateOf(false) }
                Column {
                    ReportBlockMenuButton(onReport = { reporting = true }, onBlock = { blocking = true })
                    if (reporting) ReportSheetEntry(app.messages, ReportSubject.person(StubPeople.HANGYEOL), dismiss = { reporting = false }, leaveToList = {})
                    if (blocking) {
                        MessagesBlockConfirmSheet("한결", onConfirm = {
                            blocking = false
                            app.messages.blockPeer(StubPeople.HANGYEOL)
                        }, onClose = { blocking = false })
                    }
                }
            }
        }
        compose.onNodeWithTag(MessagesTags.MORE_MENU).performClick()
        waitFor(MessagesTags.MENU_REPORT)
        compose.onNodeWithTag(MessagesTags.MENU_REPORT).performClick()
        waitFor(MessagesTags.REPORT_SHEET)
        compose.onNodeWithTag(MessagesTags.reportReason("inappropriate")).performClick()
        compose.onNodeWithTag(MessagesTags.REPORT_ALSO_BLOCK).performClick()
        compose.onNodeWithTag(MessagesTags.REPORT_SUBMIT).performClick()
        compose.waitUntil(15_000) { app.server.rpcCalls("report_content").isNotEmpty() }
        assertEquals("inappropriate", app.server.rpcCalls("report_content").single().field("p_reason"))
        waitGone(MessagesTags.REPORT_SHEET)

        compose.onNodeWithTag(MessagesTags.MORE_MENU).performClick()
        waitFor(MessagesTags.MENU_BLOCK)
        compose.onNodeWithTag(MessagesTags.MENU_BLOCK).performClick()
        waitFor(MessagesTags.BLOCK_SHEET)
        assertFalse(app.server.rpcCalls("block_user").isNotEmpty())
        compose.onNodeWithTag(MessagesTags.BLOCK_CONFIRM).performClick()
        compose.waitUntil(15_000) { app.server.rpcCalls("block_user").isNotEmpty() }
        assertEquals(StubPeople.HANGYEOL, app.server.rpcCalls("block_user").single().field("p_user"))
        println("AINGCHECK-W3A-DRAWER report=1 block=1")
    }
}
