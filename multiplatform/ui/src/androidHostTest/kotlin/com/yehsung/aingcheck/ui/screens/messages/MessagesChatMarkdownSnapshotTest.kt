// 원본: wt-phone-1017 2ad01732 · 99bd480d Tests/CheckMobileKitTests/V1017ChatMarkdownMobileTests.swift(폰 말풍선 서식 · 링크 누름 · 여는 문 · 날것 자리) ·
//       Tests/checkTests/ChatMarkdownTests.swift:768-801 @ 12624739(## 가 실제로 더 크게 그려진다 · 기호가 사라진다 — 그린 결과로 잰다).
// 판 7 Android 짝 — 대화 화면이 서식을 **실제로 부르는가**를 그린 결과 · 손짓 · TalkBack 동작으로 잰다(규칙만 재면 화면이 안 부르는 결함이 초록으로 지나간다).
//
// 데모 장면 messages 를 그대로 쓰고, 한결과의 이력 본문 몇 줄만 ScreenHarness.override 로 서식 글로 바꾼다(저장소 픽스처는 고치지 않는다).
// 기준선: 같은 이력을 서식이 꺼진 스토어(Windows 조립 — chatMarkdown 기본값)로 그리면 기호째 보이고 링크가 열리지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.text.contextmenu.builder.item
import androidx.compose.foundation.text.contextmenu.data.ProcessTextKey
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuKeys
import androidx.compose.foundation.text.contextmenu.modifier.appendTextContextMenuComponents
import androidx.compose.foundation.text.contextmenu.provider.LocalTextContextMenuDropdownProvider
import androidx.compose.foundation.text.contextmenu.provider.LocalTextContextMenuToolbarProvider
import androidx.compose.foundation.text.contextmenu.provider.TextContextMenuDataProvider
import androidx.compose.foundation.text.contextmenu.provider.TextContextMenuProvider
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.click
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.test.performMouseInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.rightClick
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenFrame
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenHarness
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenSnapshots
import kotlinx.coroutines.delay
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
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xhdpi")
class MessagesChatMarkdownSnapshotTest {
    private val hangyeol = "d0000000-0000-4000-8000-0000000000b1"
    private val harness = ScreenHarness("messages", AndroidSnapshots.repoRoot).also { it.signIn() }
    private val art = ScreenArt.bundledOnly()

    /** 폰 조립과 같은 서식 켠 스토어 · 기준선용 서식 끈 스토어(Windows 조립). */
    private val store = harness.onStore {
        MessagesStore(harness.context, harness.scope, NaturalKoNameCollation, newLocalID = { "local-1" }, chatMarkdown = true)
    }
    private val plainStore = harness.onStore { MessagesStore(harness.context, harness.scope, NaturalKoNameCollation, newLocalID = { "local-2" }) }
    private val banner = harness.onStore {
        MegaphoneBannerStore(harness.session, harness.scope, null, clock = { harness.clock.now() }, schedule = { _, _ -> }).also { b ->
            store.megaphoneBanner = b
            plainStore.megaphoneBanner = b
        }
    }
    private val characters = harness.onStore { AppUserCharacterStore(harness.context, harness.scope, CharacterArt.portraitIds) }

    @After
    fun close() = harness.close()

    private fun id(tail: String) = "d0000000-0000-4000-8000-00000000$tail"

    /** 장면 이력: 한결과의 줄 넷을 서식 글로 바꾼다(받은 것 둘 · 보낸 것 둘). 나머지는 데모 그대로. */
    private val sceneBodies = mapOf(
        id("e005") to "## 점심 메뉴\n**12시**에 1층 [식당 안내](https://food.example/menu) 봐요",
        id("e006") to "좋아요! **12시**에 봬요\nhttps://aingcheck.app/map 참고",
        id("e00a") to "# 리뷰\n### 10분만\n[naver.com](https://evil.example/login) 은 *기울임* `코드` 그대로",
        id("e00b") to "[시안](https://figma.example/x) 2시 반 어때요?",
    )

    private fun history(bodies: Map<String, String>): String {
        val (_, text) = harness.fixtures.response("POST", "/rest/v1/rpc/message_history_with_pokes", "", "{}", "messages")
        val rows = Json.parseToJsonElement(text).jsonArray.map { row ->
            val o = row.jsonObject
            val body = bodies[o["id"]?.jsonPrimitive?.content]
            if (body == null) o else JsonObject(o + ("body" to JsonPrimitive(body)))
        }
        return JsonArray(rows).toString()
    }

    private fun load(bodies: Map<String, String> = sceneBodies) {
        val history = history(bodies)
        harness.override = { _, path, _ -> if (path == "/rest/v1/rpc/message_history_with_pokes") 200 to history else null }
        harness.onStore {
            for (s in listOf(store, plainStore)) {
                s.appDidBecomeActive()
                s.listDidAppear()
                s.refreshNow()
                s.loadDirectory(force = true)
            }
            characters.refresh()
            characters.inflight?.join()
        }
        harness.awaitStore("사람 목록") { store.directoryLoaded && !store.directoryLoading && plainStore.directoryLoaded && !plainStore.directoryLoading }
        harness.onStore {
            store.conversationDidAppear(hangyeol, "warmup")
            plainStore.conversationDidAppear(hangyeol, "warmup2")
            store.refreshNow()
            plainStore.refreshNow()
            delay(50)
            store.conversationDidDisappear("warmup")
            plainStore.conversationDidDisappear("warmup2")
        }
        harness.awaitStore("이력") { store.historyLoaded && !store.historyLoading && plainStore.historyLoaded && !plainStore.historyLoading }
        for (s in listOf(store, plainStore)) {
            for ((message, body) in bodies) assertEquals("이력이 장면 글을 안 실었다", body, s.history.firstOrNull { it.id == message }?.body)
        }
        harness.freeze()
    }

    private fun conversation(dark: Boolean, name: String, fontScale: Float? = null) {
        @androidx.compose.runtime.Composable
        fun scaled(content: @androidx.compose.runtime.Composable () -> Unit) {
            if (fontScale == null) {
                content()
            } else {
                val base = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale), content = content)
            }
        }
        ScreenSnapshots.check(
            "screens/messages", name, ScreenFrame.Phone, art,
            scene = {
                ScreenSnapshots.Frame(dark, art, characters.directory) {
                    scaled { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) }
                }
            },
            // 음성 기준선: 입력칸에 "안녕" 이 든 같은 화면(한 군데만 다르다 — 비교가 내용을 본다).
            other = {
                ScreenSnapshots.Frame(dark, art, characters.directory) {
                    scaled { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState("안녕")) }
                }
            },
        )
    }

    // ---------------------------------------------------------------- 그린 결과(골든 — 사람이 PNG 를 연다)

    @Test fun conversationMarkdownPhoneLight() {
        load()
        conversation(false, "conversation-markdown-phone-light")
    }

    @Test fun conversationMarkdownPhoneDark() {
        load()
        conversation(true, "conversation-markdown-phone-dark")
    }

    /** 큰 글자(1.6배): 본문은 따라 자라고 제목은 상한(1.5배)에서 멈춘다 — 말풍선 폭을 몇 글자로 쪼개지 않는다. */
    @Test fun conversationMarkdownPhoneLargeFont() {
        load()
        conversation(false, "conversation-markdown-phone-large-font", fontScale = 1.6f)
    }

    // ---------------------------------------------------------------- 그린 결과를 값으로 — 제목은 더 높고, 꺼진 조립은 기호째

    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.rowHeight(tag: String): Float = onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot.height

    @OptIn(ExperimentalTestApi::class)
    @Test fun headingsAreTallerAndWindowsAssemblyStaysPlain() {
        load(mapOf(id("e00a") to "## 큰 제목", id("e00b") to "큰 제목"))
        var formattedHeading = 0f
        var formattedPlain = 0f
        var plainHeading = 0f
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } }
            waitForIdle()
            formattedHeading = rowHeight(MessagesTags.bubble(id("e00a")))
            formattedPlain = rowHeight(MessagesTags.bubble(id("e00b")))
            // TalkBack 줄 라벨은 기호를 벗겨 읽는다.
            val label = onNodeWithTag(MessagesTags.bubble(id("e00a"))).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
            assertTrue(label, label!!.startsWith("한결: 큰 제목,"))
        }
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(plainStore, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } }
            waitForIdle()
            plainHeading = rowHeight(MessagesTags.bubble(id("e00a")))
            val label = onNodeWithTag(MessagesTags.bubble(id("e00a"))).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
            assertTrue("꺼진 조립(Windows)의 줄 라벨이 바뀌었다: $label", label!!.startsWith("한결: ## 큰 제목,"))
        }
        println("AINGCHECK-CHATMD heading row px: formatted ## $formattedHeading · formatted plain $formattedPlain · windows ## $plainHeading")
        assertTrue("## 가 본문보다 높지 않다($formattedHeading · 본문 $formattedPlain)", formattedHeading - formattedPlain >= 8f)
        assertEquals("꺼진 조립에서 ## 줄 높이가 본문과 다르다 — 서식이 새었다", formattedPlain, plainHeading, 0.5f)
    }

    // ---------------------------------------------------------------- 링크 누름 — 링크 글자 위에서만 · 여는 문 · TalkBack 동작

    private class RecordingUriHandler : UriHandler {
        val opened = ArrayList<String>()
        override fun openUri(uri: String) {
            opened += uri
        }
    }

    @OptIn(ExperimentalTestApi::class)
    @Test fun tappingALinkOpensTheBrowserOnlyOnLinkGlyphs() {
        load(mapOf(id("e00a") to "https://a.example/tap", id("e005") to "가나다라마바사아 https://b.example/x", id("e00b") to "[시안](https://figma.example/x|y) 봐요"))
        val handler = RecordingUriHandler()
        val off = RecordingUriHandler()
        runComposeUiTest {
            setContent {
                CompositionLocalProvider(LocalUriHandler provides handler) {
                    ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) }
                }
            }
            waitForIdle()
            // 받은 말풍선은 왼쪽 위에 붙는다: 줄 왼쪽 + 말풍선 여백 13dp + 6dp(xhdpi 38px) · 위 여백 8dp + 5dp(26px) 자리가 첫 줄 첫 글자다.
            fun firstGlyph(tag: String) {
                onNodeWithTag(tag).performTouchInput { click(Offset(38f, 26f)) }
                waitForIdle()
            }
            firstGlyph(MessagesTags.bubble(id("e00a")))
            assertEquals("맨 주소를 눌렀는데 안 열었다", listOf("https://a.example/tap"), handler.opened)
            firstGlyph(MessagesTags.bubble(id("e005")))
            assertEquals("링크가 아닌 글자를 눌렀는데 열었다", listOf("https://a.example/tap"), handler.opened)
            // 말풍선 밖(줄 오른쪽 빈자리)도 아무 일 없다.
            onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { click(Offset(right - 4f, centerY)) }
            waitForIdle()
            assertEquals(listOf("https://a.example/tap"), handler.opened)
            // 내 말풍선(오른쪽)의 [글](주소) — 링크 글자를 누르면 Foundation 과 같은 인코딩 주소(| → %7C)가 브라우저로 간다. 첫 글자 자리는 TalkBack 동작으로 잰다.
            val actions = onNodeWithTag(MessagesTags.bubble(id("e00b"))).fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty()
            val titles = actions.map { it.label }
            assertEquals(listOf(ConversationText.copy, ChatBubbleText.selectCopy, "링크 열기: 시안 (figma.example)"), titles)
            assertTrue(actions.first { it.label.startsWith(ChatBubbleText.openLinkActionPrefix) }.action())
            assertEquals("https://figma.example/x%7Cy", handler.opened.last())
            // 받은 말풍선의 동작 순서: [복사] · [골라 복사] · 링크 · [이 메시지 신고하기](아이폰과 같은 차례).
            val received = onNodeWithTag(MessagesTags.bubble(id("e005"))).fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }
            assertEquals(listOf(ConversationText.copy, ChatBubbleText.selectCopy, "링크 열기: https://b.example/x", com.yehsung.aingcheck.core.rules.text.BlockReportText.reportMessageAction), received)
        }
        // 기준선: 꺼진 조립(Windows)은 같은 자리를 눌러도 열지 않고 링크 동작도 없다.
        runComposeUiTest {
            setContent {
                CompositionLocalProvider(LocalUriHandler provides off) {
                    ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(plainStore, hangyeol, onBack = {}, composerState = rememberTextFieldState()) }
                }
            }
            waitForIdle()
            onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { click(Offset(38f, centerY)) }
            waitForIdle()
            val titles = onNodeWithTag(MessagesTags.bubble(id("e00a"))).fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }
            assertEquals(listOf(ConversationText.copy, com.yehsung.aingcheck.core.rules.text.BlockReportText.reportMessageAction), titles)
        }
        assertTrue("꺼진 조립이 링크를 열었다: ${off.opened}", off.opened.isEmpty())
    }

    /** 여는 문은 http·https 만 넘긴다 — 해석 밖의 길(주석에 실린 값)이 생겨도 위험 스킴은 열리지 않는다. */
    @Test fun theDoorRefusesDangerousAddresses() {
        val opened = ArrayList<String>()
        for (address in listOf(
            "javascript:alert(1)", "JAVASCRIPT:alert(1)", "intent://scan/#Intent;scheme=zxing;end", "file:///sdcard/a.txt", "content://media/external/images/1",
            "market://details?id=x", "tel:010", "data:text/html,<b>x</b>", "https://naver.com:443@evil.com", "https://n%D0%B0ver.com", "https://", "aingcheck://message/x", "",
        )) {
            assertFalse("$address 를 열었다", ChatBubbleMarkdown.follow(address) { opened += it })
        }
        assertTrue(opened.isEmpty())
        assertTrue(ChatBubbleMarkdown.follow("https://a.example/x|y") { opened += it })
        assertEquals(listOf("https://a.example/x%7Cy"), opened)
    }

    // ---------------------------------------------------------------- 길게 누르기 메뉴 · 골라 복사 시트

    @OptIn(ExperimentalTestApi::class)
    @Test fun longPressMenuAndSelectCopySheetCopyRealAddressesAsPlainText() {
        load(mapOf(id("e00a") to "**굵게** [자료](https://a.example/doc) 끝", id("e00b") to "내 말 **굵게**", id("e005") to "[아잉:기쁨]"))
        val clipboard = ApplicationProvider.getApplicationContext<Context>().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } }
            waitForIdle()
            // 받은 말풍선: [복사] · [골라 복사] · [이 메시지 신고하기].
            onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(38f, centerY)) }
            waitForIdle()
            onNodeWithTag(MessagesTags.MENU_COPY).assertExistsCompat()
            onNodeWithTag(MessagesTags.MENU_REPORT_MESSAGE).assertExistsCompat()
            // [복사]는 원문 전체(기호째 — 붙여넣어 다시 보내면 같은 꾸밈).
            onNodeWithTag(MessagesTags.MENU_COPY).performSemanticsAction(SemanticsActions.OnClick)
            waitForIdle()
            assertEquals("**굵게** [자료](https://a.example/doc) 끝", clipboard.primaryClip?.getItemAt(0)?.text?.toString())
            onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(38f, centerY)) }
            waitForIdle()
            onNodeWithTag(MessagesTags.MENU_SELECT_COPY).performSemanticsAction(SemanticsActions.OnClick)
            waitForIdle()
            // 시트: 말풍선과 같은 글(꼬리표째)을 고른다 → 복사는 꼬리표 대신 실제 주소 · 서식 없는 글.
            val field = onNodeWithTag(MessagesTags.SELECT_COPY_FIELD)
            val shown = field.fetchSemanticsNode().config.getOrNull(SemanticsProperties.EditableText)?.text
            assertEquals("굵게 자료 (a.example) 끝", shown)
            field.performTextInputSelection(TextRange(3, 15))
            waitForIdle()
            field.performSemanticsAction(SemanticsActions.CopyText)
            waitForIdle()
            val clip = clipboard.primaryClip?.getItemAt(0)?.text
            assertEquals("자료 (https://a.example/doc)", clip?.toString())
            assertTrue("붙여넣기판에 서식이 실렸다: ${clip?.javaClass}", clip is String || (clip as? android.text.Spanned)?.getSpans(0, clip.length, Any::class.java).isNullOrEmpty())
        }
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } }
            waitForIdle()
            // 내 말풍선: [복사] · [골라 복사] — 신고 없음.
            onNodeWithTag(MessagesTags.bubble(id("e00b"))).performTouchInput { longClick(Offset(right - 38f, centerY)) }
            waitForIdle()
            onNodeWithTag(MessagesTags.MENU_SELECT_COPY).assertExistsCompat()
            onNodeWithTag(MessagesTags.MENU_REPORT_MESSAGE).assertDoesNotExistCompat()
        }
        runComposeUiTest {
            setContent { ScreenSnapshots.Frame(false, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } }
            waitForIdle()
            // 이모티콘 말풍선: [골라 복사] 없음(동작도 없음).
            val titles = onNodeWithTag(MessagesTags.bubble(id("e005"))).fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }
            assertFalse("이모티콘 말풍선에 [골라 복사]가 섰다: $titles", ChatBubbleText.selectCopy in titles)
        }
    }

    /** 골라 복사 시트(추천안 A): 말풍선과 같은 서식 · 같은 꼬리표 글을 받은 말풍선 색으로 그린다(시트 바탕 위에서 내 말풍선 흰 글자가 묻히지 않게). */
    @Test fun selectCopySheetPhoneLight() {
        val body = "## 회의 자료\n**오늘** [자료](https://a.example/doc) 확인 `코드` 그대로"
        ScreenSnapshots.check(
            "screens/messages", "select-copy-sheet-phone-light", ScreenFrame.Phone, art,
            scene = { ScreenSnapshots.Frame(false, art, characters.directory) { ChatSelectCopySheet(ChatSelectCopyState(body)) } },
            other = { ScreenSnapshots.Frame(false, art, characters.directory) { ChatSelectCopySheet(ChatSelectCopyState("$body!")) } },
        )
    }

    /** 시트 글 칸 메뉴는 [복사] · [모두 선택]만 — 공유 · 번역 · 웹 검색(PROCESS_TEXT) · 자동 채움은 꼬리표 글을 넘기므로 걸러 낸다. */
    @Test fun selectSheetMenuKeepsOnlyCopyAndSelectAll() {
        assertTrue(ChatSelectCopyMenu.keeps(TextContextMenuKeys.CopyKey))
        assertTrue(ChatSelectCopyMenu.keeps(TextContextMenuKeys.SelectAllKey))
        // PROCESS_TEXT 항목(번역 · 웹 검색 · 공유 앱)의 열쇠 — 생성자가 모듈 안쪽이라 반사로 짓는다(Compose 가 메뉴에 싣는 값과 같은 꼴).
        fun processText(id: Int): Any = ProcessTextKey::class.java.getDeclaredConstructor(Int::class.javaPrimitiveType).apply { isAccessible = true }.newInstance(id)
        for (key in listOf(TextContextMenuKeys.CutKey, TextContextMenuKeys.PasteKey, TextContextMenuKeys.AutofillKey, processText(1), processText(2), "share")) {
            assertFalse("$key 를 남겼다", ChatSelectCopyMenu.keeps(key))
        }
    }

    /**
     * 검토 F4 — 시트가 실제로 띄우는 글 칸 메뉴를 부르는 자리에서 잰다(위 시험은 술어 ChatSelectCopyMenu.keeps 만 잰다 — 시트가 거름을 안 걸어도 초록).
     * 메뉴 판은 가짜 제공자(LocalTextContextMenuToolbarProvider · LocalTextContextMenuDropdownProvider)로 받는다 — 글 칸이 메뉴를 띄울 때 그 제공자에게
     * 메뉴 자료를 넘긴다. 길은 둘: 손가락 길게 누르기(도구 막대 — 폰의 실제 손짓) · 고른 글 위 마우스 오른쪽(드롭다운).
     * Robolectric 에는 PROCESS_TEXT 앱(번역 · 웹 검색)이 없어, 바깥에서 그 자리의 항목 둘(공유 · 번역 흉내)을 끼워 넣어 거름이 실제로 걷는지 본다
     * (거름은 위아래 가리지 않고 모은 항목 전부에 걸린다). 기준선: 같은 끼움 · 같은 손짓을 거름 없는 글 칸에 하면 끼운 항목이 남는다(이 시험이 거름을 재는 증거).
     *
     * ★ 두 길 모두 메뉴를 띄우기 전에 붙여넣기판의 기기 참조(getNativeClipboardManager)를 묻는다 — 시트가 갈아 끼운 붙여넣기판이 AndroidClipboard 가
     *   아니면 IllegalArgumentException 으로 죽는다(이 시험이 처음 찾은 결함 — 시트에서 길게 누르면 앱이 죽었다).
     */
    @OptIn(ExperimentalTestApi::class)
    private fun shownMenuKeys(touch: Boolean, sheet: @androidx.compose.runtime.Composable () -> Unit): List<Any> {
        val shown = mutableListOf<List<Any>>()
        val provider = object : TextContextMenuProvider {
            override suspend fun showTextContextMenu(dataProvider: TextContextMenuDataProvider) {
                shown += dataProvider.data().components.map { it.key }
                kotlinx.coroutines.awaitCancellation()
            }
        }
        // 손가락 길: Robolectric 의 플랫폼 돋보기(API 28+)는 표면이 없어 길게 누른 뒤 닫다가 죽는다 — 이 시험 동안만 돋보기 없는 판(27)으로 보인다.
        val sdk = android.os.Build.VERSION.SDK_INT
        if (touch) org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", 27)
        try {
            runComposeUiTest {
                setContent {
                    ScreenSnapshots.Frame(false, art, characters.directory) {
                        CompositionLocalProvider(
                            LocalTextContextMenuToolbarProvider provides provider,
                            LocalTextContextMenuDropdownProvider provides provider,
                        ) {
                            Box(Modifier.appendTextContextMenuComponents {
                                item(key = "test-share", label = "공유") {}
                                item(key = ProcessTextKey::class.java.getDeclaredConstructor(Int::class.javaPrimitiveType).apply { isAccessible = true }.newInstance(7), label = "번역") {}
                            }) { sheet() }
                        }
                    }
                }
                waitForIdle()
                val field = onNodeWithTag(MessagesTags.SELECT_COPY_FIELD)
                if (touch) {
                    field.performTouchInput { longClick(Offset(30f, centerY)) }
                } else {
                    field.performTextInputSelection(TextRange(0, 5))
                    waitForIdle()
                    field.performMouseInput { rightClick(Offset(12f, centerY)) }
                }
                waitForIdle()
                // 메뉴는 누름이 끝난 뒤 다음 프레임들에서 뜬다(드롭다운은 특히 늦다) — 시계를 밀며 기다리되 시한이 지나도 던지지 않는다(아래 전제 단언이 말한다).
                runCatching { waitUntil(timeoutMillis = 3_000) { shown.isNotEmpty() } }
            }
        } finally {
            if (touch) org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", sdk)
        }
        assertTrue("touch=$touch 글을 고르고 메뉴를 청했는데 글 칸 메뉴가 뜨지 않았다(전제)", shown.isNotEmpty())
        return shown.last()
    }

    private fun assertSheetMenu(touch: Boolean) {
        val keys = shownMenuKeys(touch) { ChatSelectCopySheet(ChatSelectCopyState("**굵게** [자료](https://a.example/doc) 끝")) }
        assertEquals("touch=$touch 시트 글 칸 메뉴: $keys", setOf<Any>(TextContextMenuKeys.CopyKey, TextContextMenuKeys.SelectAllKey), keys.toSet())
        // 기준선: 거름 없는 같은 모양 글 칸 — 끼운 항목이 그대로 뜬다.
        val unfiltered = shownMenuKeys(touch) {
            androidx.compose.foundation.text.BasicTextField(
                state = androidx.compose.runtime.remember { androidx.compose.foundation.text.input.TextFieldState("굵게 자료 (a.example) 끝") },
                readOnly = true,
                modifier = Modifier.testTag(MessagesTags.SELECT_COPY_FIELD),
            )
        }
        assertTrue("touch=$touch 기준선: 거름 없는 글 칸에 끼운 공유가 없다 — 이 시험이 거름을 못 잰다: $unfiltered", "test-share" in unfiltered)
        assertTrue("touch=$touch 기준선: 거름 없는 글 칸에 끼운 PROCESS_TEXT 가 없다: $unfiltered", unfiltered.any { it is ProcessTextKey })
    }

    /** 폰의 실제 손짓 — 시트 글을 길게 눌러 고르면 도구 막대가 [복사] · [모두 선택]만 싣고 뜬다(죽지 않는다). */
    @Test fun selectSheetLongPressToolbarKeepsOnlyCopyAndSelectAll() = assertSheetMenu(touch = true)

    /** 마우스(크롬북 · 블루투스 마우스) — 고른 글 위 오른쪽 누르기 드롭다운도 같은 거름(죽지 않는다). */
    @Test fun selectSheetRightClickMenuKeepsOnlyCopyAndSelectAll() = assertSheetMenu(touch = false)

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertExistsCompat() = apply { assertExists() }
    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertDoesNotExistCompat() = apply { assertDoesNotExist() }
}
