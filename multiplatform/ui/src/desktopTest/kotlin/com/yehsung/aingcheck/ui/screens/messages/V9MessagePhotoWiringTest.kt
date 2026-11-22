// 원본: Tests/CheckMobileKitTests/V1019MessagePhotoTests.swift(wiring) @ 5b6ab3ac — 판 9 메시지 사진
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.stores.messages.MessagesPhotoLoadState
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoText
import com.yehsung.aingcheck.core.wire.models.MessagePhotoAttachment
import com.yehsung.aingcheck.ui.theme.AingTheme
import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import javax.imageio.ImageIO
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 판 9 — 입력줄 [사진]은 문 값으로만 · 대화 화면이 미리 보기 시트 · 크게 보기 · 사진 말풍선 · 저장 길 없음. 주석을 걷고 본다 + 말풍선을 그려 본다. */
class V9MessagePhotoWiringTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private fun code(rel: String) = SwiftStyleComments.strip(File(mp, rel).readText()).filter { !it.isWhitespace() }

    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    @Test
    fun composerConversationAndAndroidShellAreWiredToTheStore() {
        val composer = code("ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessageComposer.kt")
        assertTrue(composer.contains("if(onPickPhoto!=null&&store.showsPhotoButton(peerID))PhotoButton(store,peerID,onPickPhoto)"))
        assertTrue(composer.contains(".clickable(enabled=enabled,role=Role.Button,onClick=onPick)") && composer.contains("valenabled=store.canSendPhoto(peerID)"))
        val view = code("ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/ConversationScreen.kt")
        assertTrue(view.contains("if(store.photoEncoder==null)nullelseMessagesPhotoHooks.of(store){photoViewer=it}"), "Windows v1 은 사진 묶음이 없어야 한다")
        assertTrue(view.contains("MessagesPhotoPreviewSheet(store,peerID,draft)"))
        assertTrue(view.contains("confirmValueChange={it!=androidx.compose.material3.SheetValue.Hidden||!store.isSending}"), "보내는 중에 미리 보기를 밀어 닫을 수 있다")
        assertTrue(view.contains("MessagesPhotoBubble(photo,photoHooks,entry.id,onLongPress=onReport?.let{{menu=true}})"), "받은 사진만 길게 눌러 신고")
        val photos = code("ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessagesPhotoViews.kt")
        assertFalse(photos.contains("MediaStore") || photos.contains("저장"), "사진 저장 길을 열면 사진 보관함 권한이 필요하다")
        val shell = code("androidApp/src/main/kotlin/com/yehsung/aingcheck/android/screens/messages/MessagesEntries.kt")
        assertTrue(shell.contains("ActivityResultContracts.PickVisualMedia()"), "시스템 사진 고르기(권한 창 없음)가 아니다")
        assertTrue(shell.contains("store.preparePhoto(data?:ByteArray(0),peerId)"), "못 읽은 사진을 조용히 버린다")
        val manifest = File(mp, "androidApp/src/main/AndroidManifest.xml").readText()
        assertFalse(manifest.contains("READ_MEDIA_IMAGES") || manifest.contains("READ_EXTERNAL_STORAGE"), "사진 권한을 묻게 됐다")
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun bubbleLoadsOnceRetriesOnFailureAndOpensWhenLoaded() = runComposeUiTest {
        val photo = MessagePhotoAttachment("6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b/0f8fad5b-d9cb-469f-a165-70867728950e.jpg", 800, 600)
        // 스토어처럼 관찰되는 칸(캐시의 states 는 Compose 상태다).
        val state = androidx.compose.runtime.mutableStateOf<MessagesPhotoLoadState?>(MessagesPhotoLoadState.failed)
        val bytes = androidx.compose.runtime.mutableStateOf<ByteArray?>(null)
        val requested = mutableListOf<String>()
        var retried = 0
        var opened = 0
        val hooks = MessagesPhotoHooks(
            image = { bytes.value }, state = { state.value }, request = { requested += it }, retry = { retried += 1 }, open = { opened += 1 },
        )
        setContent { AingTheme(dark = false) { MessagesPhotoBubble(photo, hooks, "m1", onLongPress = null) } }
        waitForIdle()
        assertEquals(listOf(photo.path), requested, "보일 때 한 번 받아야 한다")
        onNodeWithText(MessagePhotoText.unavailable).assertExists()
        onNodeWithTag(MessagesTags.photoBubble("m1")).performClick()
        assertEquals(1, retried, "실패 칸을 눌렀는데 다시 받지 않았다")
        assertEquals(0, opened)
        // 받았다 → 그림 · 누르면 크게.
        val png = ByteArrayOutputStream().also { ImageIO.write(BufferedImage(8, 6, BufferedImage.TYPE_INT_RGB), "png", it) }.toByteArray()
        state.value = MessagesPhotoLoadState.loaded
        bytes.value = png
        waitForIdle()
        onNodeWithText(MessagePhotoText.unavailable).assertDoesNotExist()
        onNodeWithContentDescription(MessagePhotoText.openLabel).performClick()
        assertEquals(1, opened)
        assertEquals(1, requested.size, "다시 그릴 때 또 받았다")
    }
}
