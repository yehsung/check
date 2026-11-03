// 원본: wt-phone-1017 2ad01732 · 99bd480d Tests/CheckMobileKitTests/V1017ChatMarkdownMobileTests.swift(폰 말풍선 서식 · 링크 누름 · 여는 문 · 날것 자리) ·
//       Tests/checkTests/ChatMarkdownTests.swift:768-801 @ 12624739(## 가 실제로 더 크게 그려진다 · 기호가 사라진다 — 그린 결과로 잰다).
// 판 7 Android 짝 — 대화 화면이 서식을 **실제로 부르는가**를 그린 결과 · 손짓 · TalkBack 동작으로 잰다(규칙만 재면 화면이 안 부르는 결함이 초록으로 지나간다).
//
// 데모 장면 messages 를 그대로 쓰고, 한결과의 이력 본문 몇 줄만 ScreenHarness.override 로 서식 글로 바꾼다(저장소 픽스처는 고치지 않는다).
// 기준선: 같은 이력을 서식이 꺼진 스토어(Windows 조립 — chatMarkdown 기본값)로 그리면 기호째 보이고 링크가 열리지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

import android.content.ClipboardManager
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import androidx.compose.foundation.text.contextmenu.builder.TextContextMenuBuilderScope
import androidx.compose.foundation.text.contextmenu.builder.item
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuComponent
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuItem
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuSeparator
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuSession
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
import androidx.compose.ui.test.performMouseInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.rightClick
import androidx.compose.ui.test.runComposeUiTest
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
            assertEquals(listOf(ConversationText.copy, "링크 열기: 시안 (figma.example)"), titles)
            assertTrue(actions.first { it.label.startsWith(ChatBubbleText.openLinkActionPrefix) }.action())
            assertEquals("https://figma.example/x%7Cy", handler.opened.last())
            // 받은 말풍선의 동작 순서: [복사] · 링크 · [이 메시지 신고하기](아이폰과 같은 차례 — 판 7 바로 고르기 뒤에도 TalkBack 줄 동작은 그대로다).
            val received = onNodeWithTag(MessagesTags.bubble(id("e005"))).fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }
            assertEquals(listOf(ConversationText.copy, "링크 열기: https://b.example/x", com.yehsung.aingcheck.core.rules.text.BlockReportText.reportMessageAction), received)
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

    // ---------------------------------------------------------------- 말풍선에서 바로 고르기(판 7 · 대표 답 #d_M9wR9l9VLNvx)
    //
    // 대표 답 원문: "말풍선에서 바로 길게 눌러 고르기"(맥과 가장 비슷, 메뉴는 기본 편집 메뉴 + 신고). 모두 **대화 화면을 그려 손짓으로** 잰다 —
    // 길게 누르기 → Compose 고르기 → 시스템 메뉴 판(도구 막대 · 드롭다운)에 넘어간 메뉴 자료 · 그 항목을 눌렀을 때 붙여넣기판에 실제로 쓰인 글.
    // 메뉴 판은 가짜 제공자([RecordingMenu])로 받는다(Robolectric 에는 떠다니는 도구 막대가 없다 — 고르기 칸이 메뉴를 띄울 때 그 제공자에게 자료를 넘긴다).
    // ★ Robolectric 의 플랫폼 돋보기(API 28+)는 표면이 없어 길게 누른 뒤 닫다가 죽는다 — 손가락 시험 동안만 돋보기 없는 판(27)으로 보인다([withTouchSelection]).

    /**
     * 시험용 메뉴 판: 고르기 칸이 띄우는 메뉴 자료를 받아 둔다(화면에는 아무것도 안 띄운다). [click] 은 그 항목을 사람이 누른 것과 같다.
     * [keys] · [labels] 는 구분선을 뺀 항목들이다(구분선은 Compose 가 무리 사이에 스스로 넣고 거름에 걸리지 않는다 — 판에 보이는 항목이 아니다).
     */
    private class RecordingMenu : TextContextMenuProvider {
        val shown = mutableListOf<List<TextContextMenuComponent>>()

        override suspend fun showTextContextMenu(dataProvider: TextContextMenuDataProvider) {
            shown += dataProvider.data().components
            kotlinx.coroutines.awaitCancellation()
        }

        private val items: List<TextContextMenuComponent> get() = shown.last().filter { it !== TextContextMenuSeparator }
        val keys: List<Any> get() = items.map { it.key }
        val labels: List<String?> get() = items.map { (it as? TextContextMenuItem)?.label }

        fun click(key: Any) {
            val item = shown.last().first { it.key == key } as TextContextMenuItem
            item.onClick(object : TextContextMenuSession {
                override fun close() {}
            })
        }
    }

    private fun <T> withTouchSelection(block: () -> T): T {
        val sdk = android.os.Build.VERSION.SDK_INT
        org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", 27)
        try {
            return block()
        } finally {
            org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", sdk)
        }
    }

    /**
     * 기기의 PROCESS_TEXT 앱(번역 · 웹 검색 등)을 흉내 낸다 — Compose 가 고르기 칸 **자기 항목**으로 싣는 바로 그 길(ProcessTextApi23Impl 의 조회 함수 —
     * 시험용으로 열어 둔 자리)을 갈아 끼우고 끝나면 되돌린다. 실제 기기에서 [번역]은 이 길로 온다(Google 번역 · 파파고 등).
     */
    private fun <T> withProcessTextApps(labels: List<String>, block: () -> T): T {
        val impl = Class.forName("androidx.compose.foundation.text.contextmenu.ProcessTextApi23Impl")
        val instance = impl.getField("INSTANCE").get(null)
        val getter = impl.getMethod("getProcessTextActivitiesQuery")
        val setter = impl.getMethod("setProcessTextActivitiesQuery", Function1::class.java)
        val original = getter.invoke(instance)
        val fake: (Context) -> List<ResolveInfo> = { _ ->
            labels.mapIndexed { index, label ->
                ResolveInfo().apply {
                    nonLocalizedLabel = label
                    activityInfo = ActivityInfo().apply {
                        packageName = "test.process$index"
                        name = "test.process$index.ProcessTextActivity"
                        exported = true
                        nonLocalizedLabel = label
                        applicationInfo = ApplicationInfo().apply { packageName = "test.process$index" }
                    }
                }
            }
        }
        setter.invoke(instance, fake)
        try {
            return block()
        } finally {
            setter.invoke(instance, original)
        }
    }

    /** 고르기 시험 장면: 대화 화면 + 가짜 메뉴 판 + 링크 기록 + (있으면) 바깥에서 끼운 항목(공유 흉내 — 거름이 위아래 가리지 않고 걸리는지 본다). */
    @androidx.compose.runtime.Composable
    private fun SelectingScene(
        menu: RecordingMenu,
        uri: UriHandler = RecordingUriHandler(),
        dark: Boolean = false,
        outer: (TextContextMenuBuilderScope.() -> Unit)? = null,
    ) {
        CompositionLocalProvider(
            LocalUriHandler provides uri,
            LocalTextContextMenuToolbarProvider provides menu,
            LocalTextContextMenuDropdownProvider provides menu,
        ) {
            ScreenSnapshots.Frame(dark, art, characters.directory) {
                Box(if (outer != null) Modifier.appendTextContextMenuComponents(outer) else Modifier) {
                    ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState())
                }
            }
        }
    }

    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.awaitMenu(menu: RecordingMenu, count: Int) {
        waitForIdle()
        // 메뉴는 누름이 끝난 뒤 다음 프레임들에서 뜬다 — 시계를 밀며 기다리되 시한이 지나도 던지지 않는다(아래 전제 단언이 말한다).
        runCatching { waitUntil(timeoutMillis = 3_000) { menu.shown.size >= count } }
        assertTrue("길게 눌러 골랐는데 메뉴가 뜨지 않았다(전제 — ${menu.shown.size}/$count)", menu.shown.size >= count)
    }

    private val systemClipboard get() = ApplicationProvider.getApplicationContext<Context>().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private fun clip(): CharSequence? = systemClipboard.primaryClip?.getItemAt(0)?.text

    private fun assertPlain(clip: CharSequence?) =
        assertTrue("붙여넣기판에 서식이 실렸다: ${clip?.javaClass}", clip is String || (clip as? android.text.Spanned)?.getSpans(0, clip.length, Any::class.java).isNullOrEmpty())

    /**
     * 메뉴 거름을 **부르는 자리에서** 잰다: 받은 글 말풍선을 길게 누르면 [복사] · [모두 선택] · [번역](PROCESS_TEXT 앱) · [이 메시지 신고하기] 만 이 차례로 남고,
     * 웹 검색(PROCESS_TEXT) · 바깥에서 끼운 공유는 걸러진다. 내 말풍선에는 [신고]가 없다. 판 7 전의 길게 누르기 메뉴([복사] 단추)는 글 말풍선에 서지 않는다.
     * 기준선: 같은 앱 · 같은 끼움 · 같은 손짓을 거름 없는 고르기 칸에 하면 웹 검색 · 공유가 그대로 뜬다(이 시험이 거름을 재는 증거).
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun longPressingATextBubbleSelectsAndTheToolbarKeepsCopySelectAllTranslateAndReport() {
        load(mapOf(id("e00a") to "[자료](https://a.example/doc) 끝 **굵게**", id("e00b") to "내 말 **굵게** 끝"))
        val menu = RecordingMenu()
        val baseline = RecordingMenu()
        withProcessTextApps(listOf("번역", "웹 검색")) {
            withTouchSelection {
                runComposeUiTest {
                    setContent { SelectingScene(menu) { item(key = "test-share", label = "공유") {} } }
                    waitForIdle()
                    onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(38f, 26f)) }
                    awaitMenu(menu, 1)
                    println("AINGCHECK-SELECT received keys=${menu.keys} labels=${menu.labels}")
                    assertEquals(listOf(TextContextMenuKeys.CopyKey, TextContextMenuKeys.SelectAllKey), menu.keys.take(2))
                    assertTrue("셋째가 PROCESS_TEXT [번역]이 아니다: ${menu.keys}", menu.keys.getOrNull(2) is ProcessTextKey)
                    assertEquals("번역", menu.labels.getOrNull(2))
                    assertEquals(ChatBubbleSelection.ReportKey, menu.keys.getOrNull(3))
                    assertEquals(com.yehsung.aingcheck.core.rules.text.BlockReportText.reportMessageAction, menu.labels.getOrNull(3))
                    assertEquals("남은 항목: ${menu.labels}", 4, menu.keys.size)
                    // 예전 길게 누르기 메뉴는 글 말풍선에 서지 않는다.
                    onNodeWithTag(MessagesTags.MENU_COPY).assertDoesNotExistCompat()
                    onNodeWithTag(MessagesTags.MENU_REPORT_MESSAGE).assertDoesNotExistCompat()
                    // 내 말풍선: [복사] · [모두 선택] · [번역] — [신고] 없음.
                    val before = menu.shown.size
                    onNodeWithTag(MessagesTags.bubble(id("e00b"))).performTouchInput { longClick(Offset(right - 38f, centerY)) }
                    awaitMenu(menu, before + 1)
                    println("AINGCHECK-SELECT mine keys=${menu.keys} labels=${menu.labels}")
                    assertEquals(listOf(TextContextMenuKeys.CopyKey, TextContextMenuKeys.SelectAllKey), menu.keys.take(2))
                    assertEquals(listOf("번역"), menu.labels.drop(2))
                    assertFalse(ChatBubbleSelection.ReportKey in menu.keys)
                }
                // 기준선: 거름 없는 고르기 칸 — 같은 앱 · 같은 끼움이 그대로 뜬다.
                runComposeUiTest {
                    setContent {
                        CompositionLocalProvider(LocalTextContextMenuToolbarProvider provides baseline, LocalTextContextMenuDropdownProvider provides baseline) {
                            ScreenSnapshots.Frame(false, art, characters.directory) {
                                Box(Modifier.appendTextContextMenuComponents { item(key = "test-share", label = "공유") {} }) {
                                    androidx.compose.foundation.text.selection.SelectionContainer {
                                        androidx.compose.material3.Text("자료 (a.example) 끝 굵게", Modifier.testTag("baseline-text"))
                                    }
                                }
                            }
                        }
                    }
                    waitForIdle()
                    onNodeWithTag("baseline-text").performTouchInput { longClick(Offset(12f, centerY)) }
                    awaitMenu(baseline, 1)
                }
            }
        }
        println("AINGCHECK-SELECT baseline keys=${baseline.keys} labels=${baseline.labels}")
        assertTrue("기준선: 거름 없는 칸에 끼운 공유가 없다 — 이 시험이 거름을 못 잰다: ${baseline.keys}", "test-share" in baseline.keys)
        assertTrue("기준선: 거름 없는 칸에 PROCESS_TEXT 웹 검색이 없다: ${baseline.labels}", "웹 검색" in baseline.labels)
    }

    /** 마우스(크롬북 · 블루투스 마우스) — 글 위 오른쪽 누르기 드롭다운도 같은 거름이다(공유 · 웹 검색 없음 · 받은 말풍선이면 [신고]). */
    @OptIn(ExperimentalTestApi::class)
    @Test fun rightClickMenuOnATextBubbleHasTheSameFilter() {
        load(mapOf(id("e00a") to "[자료](https://a.example/doc) 끝 **굵게**"))
        val menu = RecordingMenu()
        withProcessTextApps(listOf("번역", "웹 검색")) {
            runComposeUiTest {
                setContent { SelectingScene(menu) { item(key = "test-share", label = "공유") {} } }
                waitForIdle()
                onNodeWithTag(MessagesTags.bubble(id("e00a"))).performMouseInput { rightClick(Offset(38f, 26f)) }
                awaitMenu(menu, 1)
            }
        }
        println("AINGCHECK-SELECT right-click keys=${menu.keys} labels=${menu.labels}")
        // 고른 것 없이 오른쪽을 누르면 [모두 선택] · [신고]만 선다([복사] · PROCESS_TEXT 는 고른 글이 있어야 선다 — Compose 규칙).
        assertFalse("test-share" in menu.keys)
        assertFalse("웹 검색" in menu.labels)
        assertTrue("남은 항목: ${menu.labels}", menu.keys.all { it == TextContextMenuKeys.CopyKey || it == TextContextMenuKeys.SelectAllKey || it == ChatBubbleSelection.ReportKey || it is ProcessTextKey })
        assertEquals(listOf(TextContextMenuKeys.SelectAllKey, ChatBubbleSelection.ReportKey), menu.keys)
    }

    /**
     * [복사]를 **부르는 자리에서** 잰다: 고른 낱말이 `[글](주소)` 링크면 꼬리표 대신 실제 주소째 · 서식 없는 글(기본 복사는 보이는 글자 "자료 (a.example)" 를 쓴다).
     * [모두 선택] → [복사]는 서식 기호 없이 전부. 새 메시지가 와서 화면이 다시 그려져도 고르던 구간이 남는다(그 뒤의 [복사]가 같은 글을 쓴다).
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun copyWritesTheRealAddressAsPlainTextAndTheSelectionSurvivesANewMessage() {
        load(mapOf(id("e00a") to "[자료](https://a.example/doc) 끝 **굵게**"))
        val menu = RecordingMenu()
        withTouchSelection {
            runComposeUiTest {
                setContent { SelectingScene(menu) }
                waitForIdle()
                systemClipboard.setPrimaryClip(android.content.ClipData.newPlainText("", "전"))
                onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(38f, 26f)) }
                awaitMenu(menu, 1)
                menu.click(TextContextMenuKeys.CopyKey)
                waitForIdle()
                assertEquals("자료 (https://a.example/doc)", clip()?.toString())
                assertPlain(clip())

                // 모두 선택 → 복사: 기호 없이 · 꼬리표 대신 주소. (떠 있는 판은 다시 뜨지 않고 같은 항목이 지금 고른 것을 복사한다.)
                mainClock.advanceTimeBy(1_000)
                onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(38f, 26f)) }
                awaitMenu(menu, 2)
                menu.click(TextContextMenuKeys.SelectAllKey)
                waitForIdle()
                menu.click(TextContextMenuKeys.CopyKey)
                waitForIdle()
                assertEquals("자료 (https://a.example/doc) 끝 굵게", clip()?.toString())
                assertPlain(clip())

                // 고른 채로 새 메시지가 온다(보이는 대화에 바로 넣는 길 — 실시간 도착과 같은 자리) → 다시 그려진 뒤에도 같은 구간을 복사한다.
                mainClock.advanceTimeBy(1_000)
                val beforeArrival = menu.shown.size
                onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(38f, 26f)) }
                awaitMenu(menu, beforeArrival + 1)
                val arrived = id("e0ff")
                harness.onStore {
                    val template = store.history.first { it.peerUserID == hangyeol && !it.isMine }.wire
                    val added = store.insertConsumedMessagesIntoVisibleConversation(
                        listOf(com.yehsung.aingcheck.core.stores.messages.MessageEntry(template.copy(id = arrived, body = "새 메시지 도착", createdAt = harness.clock.now()))),
                    )
                    assertEquals("새 메시지가 대화에 안 들어갔다(전제)", 1, added)
                }
                waitForIdle()
                onNodeWithTag(MessagesTags.bubble(arrived)).assertExistsCompat()
                systemClipboard.setPrimaryClip(android.content.ClipData.newPlainText("", "전"))
                menu.click(TextContextMenuKeys.CopyKey)
                waitForIdle()
                assertEquals("새 메시지 뒤에 고르던 구간이 날아갔다", "자료 (https://a.example/doc)", clip()?.toString())
            }
        }
    }

    /** 고르는 중이면 링크 위 한 번 누름은 고른 것을 지울 뿐 열지 않는다 — 다음 누름(고르는 중 아님)은 연다. */
    @OptIn(ExperimentalTestApi::class)
    @Test fun aTapWhileSelectingClearsTheSelectionInsteadOfOpeningTheLink() {
        load(mapOf(id("e00a") to "[자료](https://a.example/doc) 끝"))
        val menu = RecordingMenu()
        val handler = RecordingUriHandler()
        withTouchSelection {
            runComposeUiTest {
                setContent { SelectingScene(menu, handler) }
                waitForIdle()
                val bubble = onNodeWithTag(MessagesTags.bubble(id("e00a")))
                bubble.performTouchInput { longClick(Offset(38f, 26f)) }
                awaitMenu(menu, 1)
                assertTrue("길게 누르기가 링크를 열었다: ${handler.opened}", handler.opened.isEmpty())
                bubble.performTouchInput { click(Offset(38f, 26f)) }
                waitForIdle()
                assertTrue("고르는 중 링크 누름이 링크를 열었다: ${handler.opened}", handler.opened.isEmpty())
                // 그 누름이 고른 것을 지웠다 — [복사]가 아무것도 안 쓴다.
                systemClipboard.setPrimaryClip(android.content.ClipData.newPlainText("", "전"))
                menu.click(TextContextMenuKeys.CopyKey)
                waitForIdle()
                assertEquals("링크 위 누름이 고르기를 안 지웠다", "전", clip()?.toString())
                // 두 번 누름(두 번 눌러 낱말 고르기)으로 읽히지 않게 시계를 민다.
                mainClock.advanceTimeBy(1_000)
                bubble.performTouchInput { click(Offset(38f, 26f)) }
                waitForIdle()
                assertEquals("고르기가 풀린 뒤 누름은 연다", listOf("https://a.example/doc"), handler.opened)
            }
        }
    }

    /**
     * 여백 띠(좌우 13dp)를 길게 눌러도 가장 가까운 낱말을 고르고 메뉴([신고])가 뜬다 — 짧은 말풍선은 대부분이 여백이다(아이폰 · 맥 검토 P1).
     * ★ 글자 칸이 48dp 보다 작으면 Compose 가 누름 자리를 최소 크기까지 넓혀 여백 누름도 글자 칸이 받는다(한 줄 높이 21dp — 위아래 여백은 늘 그렇다).
     *   그래서 이 시험은 48dp 보다 **넓은** 한 줄 글의 왼쪽 여백을 누른다 — 넓힘이 닿지 않는 자리라 여백 고르기(ChatBubbleTextHit.selectNearestWord)만 받는다
     *   (그 함수를 끄면 메뉴가 안 뜬다 — 2026-11-04 변이 실측. 한 글자 "응" 은 넓힘이 받아 변이가 살았다).
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun longPressingTheBubblePaddingSelectsTheNearestWord() {
        load(mapOf(id("e00a") to "응 알겠어요"))
        val menu = RecordingMenu()
        withTouchSelection {
            runComposeUiTest {
                setContent { SelectingScene(menu) }
                waitForIdle()
                // 받은 말풍선 왼쪽 여백 띠(13dp = 26px 안) · 줄 가운데 높이.
                onNodeWithTag(MessagesTags.bubble(id("e00a"))).performTouchInput { longClick(Offset(8f, centerY)) }
                awaitMenu(menu, 1)
                assertEquals(ChatBubbleSelection.ReportKey, menu.keys.last())
                systemClipboard.setPrimaryClip(android.content.ClipData.newPlainText("", "전"))
                menu.click(TextContextMenuKeys.CopyKey)
                waitForIdle()
                assertEquals("응", clip()?.toString())
            }
        }
    }

    /** 이모티콘 말풍선은 판 7 전 길게 누르기 메뉴 그대로다: [복사](원문 토큰 — 붙여넣어 다시 보내면 그림) · [이 메시지 신고하기]. 고르기 메뉴는 뜨지 않는다. */
    @OptIn(ExperimentalTestApi::class)
    @Test fun stickerBubbleKeepsTheLongPressMenu() {
        load(mapOf(id("e005") to "[아잉:기쁨]"))
        val menu = RecordingMenu()
        withTouchSelection {
            runComposeUiTest {
                kotlinx.coroutines.runBlocking { ScreenSnapshots.prewarm(art) }
                setContent { SelectingScene(menu) }
                waitForIdle()
                onNodeWithTag(MessagesTags.bubble(id("e005"))).performTouchInput { longClick(Offset(60f, centerY)) }
                waitForIdle()
                onNodeWithTag(MessagesTags.MENU_COPY).assertExistsCompat()
                onNodeWithTag(MessagesTags.MENU_REPORT_MESSAGE).assertExistsCompat()
                onNodeWithTag(MessagesTags.MENU_COPY).performSemanticsAction(SemanticsActions.OnClick)
                waitForIdle()
                assertEquals("[아잉:기쁨]", clip()?.toString())
            }
        }
        assertTrue("이모티콘 말풍선에 고르기 메뉴가 떴다: ${menu.shown.map { c -> c.map { it.key } }}", menu.shown.isEmpty())
    }

    /** 보내는 중 말풍선도 같은 고르기 칸이다 — [신고] 없음(내 말이다). */
    @OptIn(ExperimentalTestApi::class)
    @Test fun pendingBubbleIsSelectableWithoutReport() {
        load(mapOf(id("e00a") to "받은 말"))
        harness.onStore {
            store.setDraft("보내는 중 **굵게**", hangyeol)
            assertTrue("보내기가 안 떴다(전제)", store.sendDraft(hangyeol, isComposing = false))
        }
        val menu = RecordingMenu()
        withTouchSelection {
            runComposeUiTest {
                setContent { SelectingScene(menu) }
                waitForIdle()
                onNodeWithTag(MessagesTags.pending("local-1")).performTouchInput { longClick(Offset(right - 38f, centerY)) }
                awaitMenu(menu, 1)
                println("AINGCHECK-SELECT pending keys=${menu.keys} labels=${menu.labels}")
                assertEquals(listOf(TextContextMenuKeys.CopyKey, TextContextMenuKeys.SelectAllKey), menu.keys)
                systemClipboard.setPrimaryClip(android.content.ClipData.newPlainText("", "전"))
                menu.click(TextContextMenuKeys.CopyKey)
                waitForIdle()
                assertEquals("굵게", clip()?.toString())
            }
        }
    }

    /**
     * 고르는 중 모습(골든 — 사람이 PNG 를 연다): 내 말풍선(파란 바탕)에서 낱말 하나를 고르면 강조가 본문 글자색(label)으로 깔려 보인다
     * (기본 accent 강조는 파란 바탕에서 안 보인다 — ChatBubbleSelection ⑤). 말풍선 크기 · 줄바꿈은 고르지 않은 장면과 같다.
     * 음성 기준선: 같은 장면 · 고르지 않음(다른 곳은 강조 한 군데뿐).
     */
    @OptIn(ExperimentalTestApi::class)
    @Test fun conversationSelectingPhoneLight() {
        load()
        withTouchSelection {
            ScreenSnapshots.check(
                "screens/messages", "conversation-selecting-phone-light", ScreenFrame.Phone, art,
                scene = { SelectingScene(RecordingMenu()) },
                other = { SelectingScene(RecordingMenu()) },
                // 내 말풍선 첫 줄 오른쪽 끝 낱말(위 여백 8dp + 줄 가운데 ≈ 37px · 오른쪽 여백 13dp 안쪽).
                sceneAct = { onNodeWithTag(MessagesTags.bubble(id("e00b"))).performTouchInput { longClick(Offset(right - 60f, 37f)) } },
            )
        }
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertExistsCompat() = apply { assertExists() }
    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertDoesNotExistCompat() = apply { assertDoesNotExist() }
}
