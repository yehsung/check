// 원본: Tests/CheckMobileKitTests/V1019MessageOlderTests.swift(wiring) @ 7142916e
package com.yehsung.aingcheck.ui.screens.messages

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/** 판 9 — 대화 화면이 맨 위 줄 · 30일 문장 · 붙인 뒤 제자리 맞추기를 스토어 값으로만 그린다. 주석을 걷고 본다. */
class V9MessageOlderWiringTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private fun code(rel: String) = SwiftStyleComments.strip(File(mp, rel).readText()).filter { !it.isWhitespace() }

    @Test
    fun conversationDrawsOlderRowAndExpiryFromTheStore() {
        val view = code("ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/ConversationScreen.kt")
        assertTrue(view.contains("expiryText=store.expiryNotice"))
        assertTrue(view.contains("olderRow=store.olderRowState(peerID)"))
        assertTrue(view.contains("onOlder={store.loadOlderMessages(peerID)}"))
        assertTrue(view.contains("LaunchedEffect(olderAnchor?.serial)"))
        val store = code("core/stores/src/commonMain/kotlin/com/yehsung/aingcheck/core/stores/messages/MessagesStore.kt")
        assertTrue(store.contains("messages=conversationMessages(peerID)"), "대화 줄이 지난 쪽을 안 잇는다")
        assertTrue(store.contains("carryOlderMessagesAcrossHeadSlide(threads.flatMap{it.messages}.map{it.wire},sorted.map{it.wire})"))
    }
}
