// 원본: wt-phone-1017 62f9115c Sources/CheckMobileKit/Messages/MessagesConversationView.swift · MessagesComposerView.swift · MessagesNewConversationSheet.swift
// (아이폰 1.0.17 집중 — 이름표 '집중 중' 칩 · 잠긴 입력줄과 사유 줄 · 새 대화 사람 줄 '집중' 칩) — 판 7 Android 짝.
//
// 데모 장면 messages 를 그대로 쓰고, 저장소 픽스처에 아직 없는 서버 칸만 ScreenHarness.override 로 얹는다:
//  · 상대 집중 = 명부 app_user_directory 에서 한결(b1)의 focus_mode 를 켠 판(운영 20261108120500 의 8칸 모양).
//  · 내 집중 = profiles GET select=focus_mode 가 [{"focus_mode":true}].
// 음성 기준선: 대화 = 입력칸에 "안녕" 이 든 같은 화면(글이 있어도 [보내기]는 잠겨 있다) · 새 대화 = 게이트가 꺼진 스토어(Windows 조립 — 칩이 없다).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.core.stores.messages.MessagesFocusBlock
import com.yehsung.aingcheck.core.stores.messages.MessagesFocusText
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenFrame
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenHarness
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenSnapshots
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xhdpi")
class MessagesFocusSnapshotTest {
    private val hangyeol = "d0000000-0000-4000-8000-0000000000b1"
    private val sora = "d0000000-0000-4000-8000-0000000000b2"
    private val harness = ScreenHarness("messages", AndroidSnapshots.repoRoot).also { it.signIn() }
    private val art = ScreenArt.bundledOnly()

    /** 폰 조립과 같은 게이트 켠 스토어 · 기준선용 게이트 끈 스토어(Windows 조립). */
    private val store = harness.onStore {
        MessagesStore(harness.context, harness.scope, NaturalKoNameCollation, newLocalID = { "local-1" }, focusSendGate = true)
    }
    private val gateOff = harness.onStore { MessagesStore(harness.context, harness.scope, NaturalKoNameCollation, newLocalID = { "local-2" }) }
    private val banner = harness.onStore {
        MegaphoneBannerStore(harness.session, harness.scope, null, clock = { harness.clock.now() }, schedule = { _, _ -> }).also { b ->
            store.megaphoneBanner = b
            gateOff.megaphoneBanner = b
        }
    }
    private val characters = harness.onStore { AppUserCharacterStore(harness.context, harness.scope, CharacterArt.portraitIds) }

    @After
    fun close() = harness.close()

    /** 데모 명부에서 [focused] 사람만 focus_mode 를 켠 8칸 판. */
    private fun directoryWithFocus(focused: Set<String>): String {
        val (_, text) = harness.fixtures.response("POST", "/rest/v1/rpc/app_user_directory", "", "{}", "messages")
        val rows = Json.parseToJsonElement(text).jsonArray.map { row ->
            val o = row.jsonObject
            JsonObject(o + ("focus_mode" to JsonPrimitive(o["user_id"]!!.jsonPrimitive.content in focused)))
        }
        return JsonArray(rows).toString()
    }

    private fun load(peerFocus: Set<String>, myFocus: Boolean?) {
        val directory = directoryWithFocus(peerFocus)
        harness.override = { method, path, query ->
            when {
                path == "/rest/v1/rpc/app_user_directory" -> 200 to directory
                method == "GET" && path == "/rest/v1/profiles" && query.contains("select=focus_mode") ->
                    if (myFocus == null) null else 200 to """[{"focus_mode":$myFocus}]"""
                else -> null
            }
        }
        harness.onStore {
            for (s in listOf(store, gateOff)) {
                s.appDidBecomeActive()
                s.listDidAppear()
                s.refreshNow()
                s.loadDirectory(force = true)
            }
            characters.refresh()
            characters.inflight?.join()
        }
        harness.awaitStore("사람 목록") { store.directoryLoaded && !store.directoryLoading && gateOff.directoryLoaded && !gateOff.directoryLoading }
        harness.onStore {
            store.conversationDidAppear(hangyeol, "warmup")
            store.refreshNow()
            delay(50)
        }
        harness.awaitStore("내 집중") { !store.isFetchingMyFocusMode && !store.historyLoading }
        harness.onStore { store.conversationDidDisappear("warmup") }
        assertTrue("데모 이력을 못 받았다", store.historyLoaded)
        harness.freeze()
    }

    private fun conversation(dark: Boolean, name: String) {
        ScreenSnapshots.check(
            "screens/messages", name, ScreenFrame.Phone, art,
            scene = { ScreenSnapshots.Frame(dark, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } },
            other = {
                ScreenSnapshots.Frame(dark, art, characters.directory) {
                    ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState("안녕"))
                }
            },
        )
    }

    // ---------------------------------------------------------------- 상대 집중: 이름표 '집중 중' 칩 · 잠긴 [보내기] · 사유 줄

    private fun peerFocusScene() {
        load(peerFocus = setOf(hangyeol), myFocus = false)
        assertEquals(false, store.myFocusMode)
        assertTrue(store.isPeerFocused(hangyeol))
        assertFalse(store.isPeerFocused(sora))
        assertEquals(MessagesFocusBlock.peer, store.focusBlock(hangyeol))
        assertFalse("게이트 끈 스토어(Windows)가 칩·잠금을 냈다", gateOff.isPeerFocused(hangyeol))
    }

    @Test fun conversationPeerFocusPhoneLight() {
        peerFocusScene()
        conversation(false, "conversation-peer-focus-phone-light")
    }

    @Test fun conversationPeerFocusPhoneDark() {
        peerFocusScene()
        conversation(true, "conversation-peer-focus-phone-dark")
    }

    // ---------------------------------------------------------------- 내 집중: 칩 없이 사유 줄(맥에서 끄라)만

    @Test fun conversationMyFocusPhoneLight() {
        load(peerFocus = emptySet(), myFocus = true)
        assertEquals(true, store.myFocusMode)
        assertFalse(store.isPeerFocused(hangyeol))
        assertEquals(MessagesFocusBlock.myself, store.focusBlock(hangyeol))
        conversation(false, "conversation-my-focus-phone-light")
    }

    // ---------------------------------------------------------------- 새 대화 시트: 사람 줄 '집중' 칩

    @Test fun newConversationPeerFocusPhoneLight() {
        peerFocusScene()
        ScreenSnapshots.check(
            "screens/messages", "new-conversation-focus-phone-light", ScreenFrame.Phone, art,
            scene = { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesNewConversationSheet(store, {}, {}) } },
            // 기준선: 게이트가 꺼진 조립(Windows) — 같은 명부인데 칩이 없다(한 군데만 다르다).
            other = { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesNewConversationSheet(gateOff, {}, {}) } },
        )
    }

    // ---------------------------------------------------------------- TalkBack · 잠금 배선(화면이 스토어 규칙을 실제로 부르는가)

    @OptIn(ExperimentalTestApi::class)
    @Test fun talkBackReadsFocusAndTheSendButtonIsLocked() {
        peerFocusScene()
        runComposeUiTest {
            setContent {
                ScreenSnapshots.Frame(false, art, characters.directory) {
                    ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState("안녕"))
                }
            }
            waitForIdle()
            // 이름표: 이름 다음에 "집중 중"(iOS 와 같은 자리).
            onNode(hasContentDescription("한결, ${MessagesFocusText.accessibility}", substring = true)).assertExists()
            // 글이 있어도 [보내기]는 잠겨 있고, 사유 줄은 서버 거절과 같은 문장이다.
            onNodeWithTag(MessagesTags.SEND).assertIsNotEnabled()
            onNodeWithText(MessageNoticeText.targetFocused).assertExists()
        }
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesNewConversationSheet(store, {}, {}) } }
            waitForIdle()
            onNode(hasContentDescription("한결, 서울센터, 근무 중, ${MessagesFocusText.accessibility}", substring = true)).assertExists()
            // 기준선: 집중 아닌 사람 줄에는 그 말이 없다.
            val soraRow = onNodeWithTag(MessagesTags.person(sora)).fetchSemanticsNode()
            val soraLabel = soraRow.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString() ?: ""
            assertTrue(soraLabel, soraLabel.startsWith("소라"))
            assertFalse(soraLabel, soraLabel.contains(MessagesFocusText.accessibility))
        }
        assertNull(gateOff.focusBlock(hangyeol))
    }

    /** 이모티콘 시트: 고르기 **전에** 집중 사유가 서고, 골라도 요청 없이 시트가 열린 채 '보내는 중'으로 접지 않는다(iOS 1.0.17 · 맥 blockedHelp 짝). */
    @OptIn(ExperimentalTestApi::class)
    @Test fun stickerSheetSpeaksFocusBeforeAndAfterPicking() {
        peerFocusScene()
        val sentBefore = harness.requests.count { it.endsWith("/rpc/send_message") }
        var closed = false
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesStickerSheet(store, hangyeol, onClose = { closed = true }) } }
            waitForIdle()
            onNodeWithText(MessageNoticeText.targetFocused).assertExists()
            onNodeWithTag(MessagesTags.stickerCell(com.yehsung.aingcheck.core.rules.text.AingSticker.joy.rawValue)).performClick()
            waitForIdle()
            onNodeWithText(MessageNoticeText.targetFocused).assertExists()
            onNodeWithText(com.yehsung.aingcheck.core.rules.text.AingStickerText.sendingNowNotice).assertDoesNotExist()
        }
        assertFalse("집중이 막는데 시트를 닫았다", closed)
        assertEquals("집중이 막는데 이모티콘 요청이 나갔다", sentBefore, harness.requests.count { it.endsWith("/rpc/send_message") })
    }

    /**
     * 검토 F5 — 새 대화 시트의 [다시 시도]가 명부 **둘**(메시지 + 지금 탭)을 받는가(부르는 자리를 잰다 — 스토어 시험은 refreshPeopleDirectories 만 잰다).
     * 기준선: 게이트가 꺼진 스토어(Windows 조립)는 같은 단추가 메시지 명부만 받는다(지금과 같다).
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun newConversationRetryRefetchesBothDirectories() {
        val files = object : TodoFileSystem {
            val contents = HashMap<String, ByteArray>()
            override fun read(path: String): ByteArray? = contents[path]
            override fun writeAtomically(path: String, bytes: ByteArray) { contents[path] = bytes }
            override fun move(from: String, to: String) { contents.remove(from)?.let { contents[to] = it } }
        }
        val now = harness.onStore { NowStore(harness.context, harness.scope, NowTodoStorage("/mem/now", files)) }
        harness.override = { _, path, _ -> if (path == "/rest/v1/rpc/app_user_directory") 500 to """{"message":"down"}""" else null }
        harness.onStore {
            for (s in listOf(store, gateOff)) {
                s.nowStore = now
                s.appDidBecomeActive()
                s.loadDirectory(force = true)
            }
        }
        harness.awaitStore("명부 실패") { store.directoryFailed && !store.directoryLoading && gateOff.directoryFailed && !gateOff.directoryLoading }
        fun directoryRequests() = harness.requests.count { it == "POST /rest/v1/rpc/app_user_directory" }
        for ((s, gate) in listOf(store to true, gateOff to false)) {
            runComposeUiTest {
                setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesNewConversationSheet(s, {}, {}) } }
                waitForIdle()
                // 시트가 서며 부르는 loadDirectory()(실패 뒤라 스로틀 없이 한 번)가 끝나기를 기다린다.
                harness.awaitStore("시트 첫 조회") { !s.directoryLoading && !now.isRefreshing }
                waitForIdle()
                val requestsBefore = directoryRequests()
                val nowBefore = harness.onStore { now.refreshCount }
                onNodeWithText(MobileLoadText.retry).performClick()
                waitForIdle()
                // 기대 수까지 기다리되 시한이 지나도 던지지 않는다 — 모자라면 아래 단언이 무엇이 모자란지 말한다.
                harness.onStore {
                    withTimeoutOrNull(3_000) {
                        while (directoryRequests() < requestsBefore + (if (gate) 2 else 1) || s.directoryLoading || now.isRefreshing) delay(10)
                    }
                    delay(100)
                }
                assertEquals("gate=$gate 지금 탭 명부 재조회 수", if (gate) nowBefore + 1 else nowBefore, harness.onStore { now.refreshCount })
                assertEquals("gate=$gate 명부 요청 수", requestsBefore + (if (gate) 2 else 1), directoryRequests())
            }
        }
    }
}
