// 원본: Sources/CheckMobileKit/Messages/MessagesTab.swift · MessagesConversationView.swift @ 3bd04bd (데모 장면 messages — 목록 · 한결과의 대화)
// Swift 짝: Tests/CheckMobileKitTests/MessagesDemoFixtureTests.swift(같은 픽스처로 스토어 값을 잰다 — 여기는 그 값을 그린 화면).
//
// G §2-3 W3-a ① Roborazzi: 메시지 목록 · 대화 — 폰(밝음 · 어두움) · sw600dp. 스토어는 진짜(데모 픽스처 · 찌르기 기록 · 네 무리 정렬 · 이모티콘).
// 음성 기준선: 목록 = 한 사람의 착용 캐릭터만 다른 표 · 대화 = 입력칸에 "안녕" 이 든 같은 화면.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.text.input.rememberTextFieldState
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenFrame
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenHarness
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenSnapshots
import kotlinx.coroutines.delay
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xhdpi")
class MessagesScreensSnapshotTest {
    private val hangyeol = "d0000000-0000-4000-8000-0000000000b1"
    private val harness = ScreenHarness("messages", AndroidSnapshots.repoRoot).also { it.signIn() }
    private val art = ScreenArt.bundledOnly()
    private val store = harness.onStore { MessagesStore(harness.context, harness.scope, NaturalKoNameCollation, newLocalID = { "local-1" }) }
    private val characters = harness.onStore { AppUserCharacterStore(harness.context, harness.scope, CharacterArt.portraitIds) }
    private val otherCharacters = harness.onStore { AppUserCharacterStore(harness.context, harness.scope, CharacterArt.portraitIds) }

    @After
    fun close() = harness.close()

    /** 데모 장면을 다 받는다(요약 · 이력 · 찌르기 · 사람 목록 · 캐릭터 표) — 그 뒤 얼린다. */
    private fun load(conversation: String? = null) {
        harness.onStore {
            store.appDidBecomeActive()
            store.listDidAppear()
            store.refreshNow()
            store.loadDirectory(force = true)
            characters.refresh()
            otherCharacters.refresh()
            characters.inflight?.join()
            otherCharacters.inflight?.join()
        }
        harness.awaitStore("사람 목록") { store.directoryLoaded && !store.directoryLoading }
        if (conversation != null) {
            harness.onStore {
                store.conversationDidAppear(conversation, "warmup")
                store.refreshNow()
                delay(50)
                store.conversationDidDisappear("warmup")
            }
            harness.awaitStore("읽음 정리") { !store.historyLoading }
        }
        // 음성 기준선 표: 한결 한 사람만 다른 캐릭터를 입었다.
        otherCharacters.directory.setEquipped("ghost", hangyeol)
        assertTrue("데모 이력을 못 받았다", store.historyLoaded && store.pokeLogAvailable)
        harness.freeze()
    }

    private fun list(dark: Boolean, frame: ScreenFrame, name: String) {
        load()
        assertEquals(listOf("하린", "소라", "도윤", "한결", "민재"), store.threadItems(harness.clock.now()).map { it.peerName })
        ScreenSnapshots.check(
            "screens/messages", name, frame, art,
            scene = { ScreenSnapshots.Frame(dark, art, characters.directory) { MessagesListScreen(store, {}, {}, {}) } },
            other = { ScreenSnapshots.Frame(dark, art, otherCharacters.directory) { MessagesListScreen(store, {}, {}, {}) } },
        )
    }

    private fun conversation(dark: Boolean, frame: ScreenFrame, name: String) {
        load(conversation = hangyeol)
        ScreenSnapshots.check(
            "screens/messages", name, frame, art,
            scene = { ScreenSnapshots.Frame(dark, art, characters.directory) { ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState()) } },
            other = {
                ScreenSnapshots.Frame(dark, art, characters.directory) {
                    ConversationScreen(store, hangyeol, onBack = {}, composerState = rememberTextFieldState("안녕"))
                }
            },
        )
    }

    @Test fun listPhoneLight() = list(false, ScreenFrame.Phone, "list-phone-light")

    @Test fun listPhoneDark() = list(true, ScreenFrame.Phone, "list-phone-dark")

    @Test @Config(qualifiers = "w600dp-h960dp-xhdpi")
    fun listTabletLight() = list(false, ScreenFrame.Tablet, "list-sw600dp-light")

    @Test fun conversationPhoneLight() = conversation(false, ScreenFrame.Phone, "conversation-phone-light")

    @Test fun conversationPhoneDark() = conversation(true, ScreenFrame.Phone, "conversation-phone-dark")

    @Test @Config(qualifiers = "w600dp-h960dp-xhdpi")
    fun conversationTabletLight() = conversation(false, ScreenFrame.Tablet, "conversation-sw600dp-light")
}
