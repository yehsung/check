// 원본: wt-phone-1017 62f9115c Sources/CheckMobileKit/Messages/MessagesConversationView.swift · MessagesComposerView.swift · MessagesNewConversationSheet.swift
// (아이폰 1.0.17 집중 — 이름표 '집중 중' 칩 · 잠긴 입력줄과 사유 줄 · 새 대화 사람 줄 '집중' 칩) — 판 7 Android 짝.
//
// 데모 장면 messages 를 그대로 쓰고, 저장소 픽스처에 아직 없는 서버 칸만 ScreenHarness.override 로 얹는다:
//  · 상대 집중 = 명부 app_user_directory 에서 한결(b1)의 focus_mode 를 켠 판(운영 20261108120500 의 8칸 모양).
//  · 내 집중 = profiles GET select=focus_mode 가 [{"focus_mode":true}].
// 음성 기준선: 대화 = 입력칸에 "안녕" 이 든 같은 화면(글이 있어도 [보내기]는 잠겨 있다) · 새 대화 = 게이트가 꺼진 스토어(Windows 조립 — 칩이 없다).
//
// 집중 표시 넓히기(ios-1017-int 1776440d — 대표 답 #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부"): 대화 목록 줄 '집중' 칩(하린 — 아이폰 데모와 같은 사람) ·
// 얼굴 띠 TalkBack · 내 집중이면 목록 위 한 줄. 기준선: 목록 줄 칩 = 게이트가 꺼진 스토어(Windows — 같은 명부인데 칩이 없다) · 목록 위 한 줄 =
// 한결 한 사람만 다른 캐릭터를 입은 같은 장면(한 줄이 없는 장면은 아래가 통째로 밀려 '한 군데'가 아니다).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
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
import com.yehsung.aingcheck.core.stores.messages.MessagesFocusRules
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
    private val harin = "d0000000-0000-4000-8000-0000000000b5"
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

    /** 목록 위 한 줄의 음성 기준선 표 — 한결 한 사람만 다른 캐릭터(MessagesScreensSnapshotTest 의 목록 기준선과 같은 판). */
    private val otherCharacters = harness.onStore { AppUserCharacterStore(harness.context, harness.scope, CharacterArt.portraitIds) }

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
            otherCharacters.refresh()
            characters.inflight?.join()
            otherCharacters.inflight?.join()
        }
        harness.awaitStore("사람 목록") { store.directoryLoaded && !store.directoryLoading && gateOff.directoryLoaded && !gateOff.directoryLoading }
        otherCharacters.directory.setEquipped("ghost", hangyeol)
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

    /**
     * 검토 F6 — 공용 이름표의 이름 줄은 집중이 아닐 때 예전 그림 그대로다(Windows 플라이아웃도 같은 ConversationScreen 을 쓰고 게이트가 꺼져 칩이 없다):
     * 넘치는 긴 이름은 잘린다(Clip — 말줄임표 없음). 칩이 설 때만 이름이 폭을 양보하며 말줄임표로 끝난다(기준선 — 같은 이름 · 같은 폭).
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun nameplateTitleKeepsTheOldClipUnlessTheChipStands() {
        val long = "아주아주아주아주아주아주아주아주긴이름의동료입니다"
        for (focused in listOf(false, true)) {
            runComposeUiTest {
                setContent {
                    ScreenSnapshots.Frame(false, art, characters.directory) { Box(Modifier.width(120.dp)) { NameplateTitle(long, focused) } }
                }
                waitForIdle()
                val layouts = mutableListOf<TextLayoutResult>()
                onNodeWithText(long).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
                val layout = layouts.single()
                assertTrue("전제: 이름이 폭을 넘쳐야 한다(focused=$focused)", layout.hasVisualOverflow || layout.isLineEllipsized(0))
                assertEquals("focused=$focused 이름 줄 말줄임", focused, layout.isLineEllipsized(0))
            }
        }
    }

    // ---------------------------------------------------------------- 대화 목록(대표 답 #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부")

    @Composable
    private fun Scaled(fontScale: Float?, content: @Composable () -> Unit) {
        if (fontScale == null) {
            content()
        } else {
            val base = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale), content = content)
        }
    }

    /** 하린(아이폰 데모와 같은 사람 — 대화 목록 맨 윗줄 · 얼굴 띠)만 집중을 켠 판. 내 집중은 꺼짐(목록 위 한 줄 없음). */
    private fun listPeerFocusScene() {
        load(peerFocus = setOf(harin), myFocus = false)
        assertEquals(setOf(harin), store.focusedPeerIDs)
        assertEquals("게이트 끈 스토어(Windows)가 집중 집합을 냈다", emptySet<String>(), gateOff.focusedPeerIDs)
        assertEquals(false, store.myFocusMode)
        assertNull(MessagesFocusRules.listNotice(store.myFocusMode))
        assertEquals("하린", store.threadItems(harness.clock.now()).first().peerName)
    }

    /** 목록 줄 칩: 장면 = 게이트 켠 스토어(하린 줄 이름 뒤 '집중') · 기준선 = 게이트 끈 스토어(같은 명부 · 같은 이력 — 칩만 없다). */
    private fun listPeerFocus(dark: Boolean, name: String, fontScale: Float? = null) {
        listPeerFocusScene()
        ScreenSnapshots.check(
            "screens/messages", name, ScreenFrame.Phone, art,
            scene = { Scaled(fontScale) { ScreenSnapshots.Frame(dark, art, characters.directory) { MessagesListScreen(store, {}, {}, {}) } } },
            other = { Scaled(fontScale) { ScreenSnapshots.Frame(dark, art, characters.directory) { MessagesListScreen(gateOff, {}, {}, {}) } } },
        )
    }

    @Test fun listPeerFocusPhoneLight() = listPeerFocus(false, "list-peer-focus-phone-light")

    @Test fun listPeerFocusPhoneDark() = listPeerFocus(true, "list-peer-focus-phone-dark")

    @Test fun listPeerFocusPhoneLargeFont() = listPeerFocus(false, "list-peer-focus-phone-large-font", fontScale = 1.6f)

    /** 내가 집중 중: 목록 위 한 줄(입력줄 사유 · sender_focused 와 같은 문장 — 폰엔 [집중 끄기] 단추가 없다). */
    private fun listMyFocus(dark: Boolean, name: String) {
        load(peerFocus = emptySet(), myFocus = true)
        assertEquals(true, store.myFocusMode)
        assertEquals(MessageNoticeText.senderFocused, MessagesFocusRules.listNotice(store.myFocusMode))
        assertNull("게이트 끈 스토어(Windows)가 내 집중을 물었다", gateOff.myFocusMode)
        ScreenSnapshots.check(
            "screens/messages", name, ScreenFrame.Phone, art,
            scene = { ScreenSnapshots.Frame(dark, art, characters.directory) { MessagesListScreen(store, {}, {}, {}) } },
            other = { ScreenSnapshots.Frame(dark, art, otherCharacters.directory) { MessagesListScreen(store, {}, {}, {}) } },
        )
    }

    @Test fun listMyFocusPhoneLight() = listMyFocus(false, "list-my-focus-phone-light")

    @Test fun listMyFocusPhoneDark() = listMyFocus(true, "list-my-focus-phone-dark")

    /**
     * 부르는 자리(화면이 스토어 값을 실제로 읽는가): 목록 줄 TalkBack 에 '집중 중' · 얼굴 띠 TalkBack(칩 없이 말만) · 목록 위 한 줄.
     * 기준선: 집중 아닌 줄 · 게이트 끈 스토어(Windows)는 판 7 전 문장 그대로이고 한 줄이 없다.
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun listTalkBackAndNoticeFollowTheStore() {
        listPeerFocusScene()
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesListScreen(store, {}, {}, {}) } }
            waitForIdle()
            val harinRow = onNodeWithTag(MessagesTags.threadRow(harin)).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString() ?: ""
            assertTrue(harinRow, harinRow.startsWith("하린, 근무 중 · 서울, ${MessagesFocusText.accessibility}, "))
            val soraRow = onNodeWithTag(MessagesTags.threadRow(sora)).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString() ?: ""
            assertFalse(soraRow, soraRow.contains(MessagesFocusText.accessibility))
            // 얼굴 띠: 칩 없이 말만.
            onNode(hasContentDescription("하린, 근무 중, ${MessagesFocusText.accessibility}")).assertExists()
            onNode(hasContentDescription("소라, 근무 중")).assertExists()
            onNodeWithTag(MessagesTags.LIST_FOCUS_NOTICE).assertDoesNotExist()
        }
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesListScreen(gateOff, {}, {}, {}) } }
            waitForIdle()
            val harinRow = onNodeWithTag(MessagesTags.threadRow(harin)).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString() ?: ""
            assertFalse("게이트 끈 목록(Windows)이 집중을 읽었다: $harinRow", harinRow.contains(MessagesFocusText.accessibility))
            onNode(hasContentDescription("하린, 근무 중")).assertExists()
            onNode(hasContentDescription("하린, 근무 중, ${MessagesFocusText.accessibility}")).assertDoesNotExist()
        }
    }

    /**
     * 목록 위 한 줄은 한글 어절 사이에서만 꺾인다(검토 F4 — 아이폰 InlineNotice 와 같다). 폰 폭 360dp 에서 두 줄이 되는 문장으로,
     * 둘째 줄부터 각 줄의 첫 글자 앞이 빈칸인가를 실제 배치(GetTextLayoutResult)로 잰다 — 판 7 첫 골든은 "…맥에서 집중 / 을 끄면…"이었다.
     * 기준선: 같은 문장 · 같은 폭 · 같은 글꼴을 줄바꿈 설정 없는 Text 로 그리면 어절 가운데서 꺾인다(이 재기가 꺾인 자리를 본다).
     * ★ 어구(Phrase) 줄바꿈은 글 언어가 한국어일 때만 어절 단위다(minikin — 기기 언어 ko). 이 시험만 기기 언어를 한국어로 둔다(아래 Config).
     */
    @OptIn(ExperimentalTestApi::class)
    @Config(qualifiers = "ko-rKR-w360dp-h800dp-xhdpi")
    @Test fun listFocusNoticeBreaksOnlyBetweenWords() {
        assertEquals("전제: 기기 언어가 한국어여야 한다", "ko", java.util.Locale.getDefault().language)
        load(peerFocus = emptySet(), myFocus = true)
        fun midWordBreaks(layout: TextLayoutResult): List<Int> {
            val text = layout.layoutInput.text.text
            return (1 until layout.lineCount).map { layout.getLineStart(it) }.filter { start -> start in 1 until text.length && !text[start - 1].isWhitespace() }
        }
        var width = 0
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesListScreen(store, {}, {}, {}) } }
            waitForIdle()
            val layouts = mutableListOf<TextLayoutResult>()
            onNodeWithText(MessageNoticeText.senderFocused, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
            val layout = layouts.single()
            assertTrue("전제: 폰 폭에서 안내가 두 줄 이상이어야 한다(${layout.lineCount})", layout.lineCount >= 2)
            assertEquals("목록 위 한 줄이 어절 가운데서 꺾였다(줄 시작 ${midWordBreaks(layout)})", emptyList<Int>(), midWordBreaks(layout))
            width = layout.layoutInput.constraints.maxWidth
        }
        runComposeUiTest {
            setContent {
                ScreenSnapshots.Frame(false, art, characters.directory) {
                    val dp = with(LocalDensity.current) { width.toDp() }
                    androidx.compose.material3.Text(MessageNoticeText.senderFocused, style = androidx.compose.material3.MaterialTheme.typography.bodySmall, modifier = Modifier.width(dp))
                }
            }
            waitForIdle()
            val layouts = mutableListOf<TextLayoutResult>()
            onNodeWithText(MessageNoticeText.senderFocused).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
            assertTrue("기준선: 줄바꿈 설정 없는 글은 어절 가운데서 꺾여야 한다 — 이 시험이 꺾인 자리를 못 본다", midWordBreaks(layouts.single()).isNotEmpty())
        }
    }

    /** 목록 위 한 줄의 부르는 자리: 내 집중이 켜짐이면 서고 문장은 입력줄 사유와 같다 · 게이트 끈 스토어(Windows)는 같은 순간에도 없다(기준선). */
    @OptIn(ExperimentalTestApi::class)
    @Test fun listFocusNoticeStandsOnlyForMyFocus() {
        load(peerFocus = emptySet(), myFocus = true)
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesListScreen(store, {}, {}, {}) } }
            waitForIdle()
            onNodeWithTag(MessagesTags.LIST_FOCUS_NOTICE).assertExists()
            onNodeWithText(MessageNoticeText.senderFocused).assertExists()
        }
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { MessagesListScreen(gateOff, {}, {}, {}) } }
            waitForIdle()
            onNodeWithTag(MessagesTags.LIST_FOCUS_NOTICE).assertDoesNotExist()
            onNodeWithText(MessageNoticeText.senderFocused).assertDoesNotExist()
        }
    }
}
