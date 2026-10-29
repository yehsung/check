// 원본: Sources/check/CheckTextEditor.swift @ a90d8623 (hasMarkedText 이면 Return 은 조합 확정만) · ui ComposerInputRules.sendPlan
//
// W3-c0 ⑥ MessageEnterGuardDesktopTest — 조합 중 Enter 는 보내지 않는다(키를 먹지도 않는다 — IME 확정 몫). Shift+Enter 는 줄바꿈.
// 진짜 메시지 스토어에 이어 '보낸 건수'로 잰다(모양이 아니라 결과 — 기억 tests-measure-shape-not-result).
package com.yehsung.aingcheck.desktop.pages.shared

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessageEnterGuardDesktopTest {
    private val sent = mutableListOf<String>()

    private fun press(enter: Boolean = true, shift: Boolean = false, composing: Boolean = false, text: String = "안녕", sending: Boolean = false): Boolean =
        DesktopEnterKey.handle(enter, shift, composing, text, sending) { sent += it }

    @Test
    fun `⑥-1 조합 중 Enter 는 보내지 않고 키도 먹지 않는다`() {
        assertFalse(press(composing = true))
        assertEquals(emptyList(), sent)
    }

    @Test
    fun `⑥-2 조합이 끝난 Enter 는 확정 글을 한 번 보내고 키를 먹는다`() {
        assertTrue(press())
        assertEquals(listOf("안녕"), sent)
    }

    @Test
    fun `⑥-3 Shift+Enter 는 줄바꿈 · 다른 키는 입력칸 몫`() {
        assertFalse(press(shift = true))
        assertFalse(press(enter = false))
        assertEquals(emptyList(), sent)
    }

    @Test
    fun `⑥-4 빈 글·왕복 중은 먹기만 하고 보내지 않는다(빈 줄 0)`() {
        assertTrue(press(text = "   "))
        assertTrue(press(sending = true))
        assertEquals(emptyList(), sent)
    }

    @Test
    fun `⑥-5 진짜 스토어 — 조합 중 Enter 뒤 보낸 요청 0 · 조합 끝난 Enter 뒤 1`() = runTest {
        val h = SharedTestHarness(this, answer = SharedTestHarness.withTeam)
        h.signIn()
        advanceUntilIdle()
        val peer = "d0000000-0000-4000-8000-0000000000b2"
        val send: (String) -> Unit = { text ->
            h.messages.setDraft(text, peer)
            h.messages.sendDraft(peer, isComposing = false)
        }
        h.paths.clear()
        DesktopEnterKey.handle(true, false, composing = true, text = "안녕하세", isSending = false, send = send)
        advanceUntilIdle()
        assertEquals(0, h.paths.count { it.endsWith("/rpc/send_message") }, "조합 중: ${h.paths}")
        DesktopEnterKey.handle(true, false, composing = false, text = "안녕하세요", isSending = false, send = send)
        advanceUntilIdle()
        assertEquals(1, h.paths.count { it.endsWith("/rpc/send_message") }, "확정 뒤: ${h.paths}")
    }
}
