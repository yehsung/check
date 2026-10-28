// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (send() 의 세 갈래 · sendEnabled · updateUIView 의 "조합 중에는 덮지 않는다")
// Swift 짝 시험: Tests/CheckMobileKitTests 의 MessagesComposerRules.sendAction 표 — 여기는 그 위에 얹은 화면 판정(입력칸 글 · 조합 · 왕복)을 잰다.
package com.yehsung.aingcheck.ui.screens.messages

import com.yehsung.aingcheck.ui.screens.messages.ComposerInputRules.SendPlan
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ComposerInputRulesTest {
    @Test
    fun composingTextIsCommittedThenSent() {
        // 조합 중 [보내기] = 조합 영역을 확정 글로 치고 보낸다(마지막 음절 "요"가 빠지지 않는다).
        assertEquals(SendPlan.CommitThenSend("안녕하세요"), ComposerInputRules.sendPlan("안녕하세요", composing = true, isSending = false))
        assertEquals(SendPlan.Send("안녕"), ComposerInputRules.sendPlan("안녕", composing = false, isSending = false))
    }

    @Test
    fun nothingToSendIsNone() {
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan("", composing = false, isSending = false))
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan("   \n ", composing = false, isSending = false))
        // 조합 중이어도 확정 글이 서버 경계 밖이면(공백뿐) 보내지 않는다 — 확정한 뒤 다시 판정한다.
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan(" ", composing = true, isSending = false))
        // 왕복 중이면 아무것도 안 한다(한 번에 하나 — 순서가 곧 상대가 읽는 순서).
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan("안녕", composing = false, isSending = true))
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan("안녕", composing = true, isSending = true))
    }

    @Test
    fun overLimitIsNotSentAndNotTruncated() {
        val long = "가".repeat(201)
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan(long, composing = false, isSending = false))
        assertEquals(SendPlan.None, ComposerInputRules.sendPlan(long, composing = true, isSending = false))
        assertTrue(ComposerInputRules.isOverflowing(long))
        assertFalse(ComposerInputRules.isOverflowing("가".repeat(200)))
        // 200 경계 안이면 그대로 보낸다(앞뒤 공백 다듬기는 스토어 MessageBody 가 한다 — 화면은 글을 자르지 않는다).
        assertEquals(SendPlan.Send("가".repeat(200)), ComposerInputRules.sendPlan("가".repeat(200), composing = false, isSending = false))
    }

    @Test
    fun sendButtonStates() {
        // 조합 중이면 켠다(누르면 확정한 뒤 판정) · 아니면 스토어 판정 · 왕복 중이면 끈다.
        assertTrue(ComposerInputRules.sendEnabled(composing = true, canSend = false, isSending = false))
        assertTrue(ComposerInputRules.sendEnabled(composing = false, canSend = true, isSending = false))
        assertFalse(ComposerInputRules.sendEnabled(composing = false, canSend = false, isSending = false))
        assertFalse(ComposerInputRules.sendEnabled(composing = true, canSend = true, isSending = true))
        // 보내는 중에도 원은 파랑(흰 돌림표).
        assertTrue(ComposerInputRules.sendLooksEnabled(isSending = true, sendEnabled = false))
        assertFalse(ComposerInputRules.sendLooksEnabled(isSending = false, sendEnabled = false))
    }

    @Test
    fun externalDraftNeverOverwritesComposition() {
        // 보내기 실패로 스토어가 글을 되돌렸다 — 칸이 비어 있고 조합 중이 아니면 옮긴다.
        assertEquals("안녕", ComposerInputRules.externalDraft(storeDraft = "안녕", lastPushed = "", fieldText = "", composing = false))
        // 조합 중이면 어떤 바깥 값도 덮지 않는다(되살아남·빠짐의 원인).
        assertNull(ComposerInputRules.externalDraft(storeDraft = "안녕", lastPushed = "", fieldText = "아", composing = true))
        // 내가 밀어 넣은 값의 메아리(한 박자 늦게 온 옛 값)로 더 친 글을 되돌리지 않는다.
        assertNull(ComposerInputRules.externalDraft(storeDraft = "안", lastPushed = "안", fieldText = "안녕", composing = false))
        // 같으면 할 일이 없다.
        assertNull(ComposerInputRules.externalDraft(storeDraft = "안녕", lastPushed = null, fieldText = "안녕", composing = false))
        // 대화를 다시 열었다(처음 밀어 넣기 전) — 스토어 초안이 칸에 선다.
        assertEquals("쓰던 글", ComposerInputRules.externalDraft(storeDraft = "쓰던 글", lastPushed = null, fieldText = "", composing = false))
    }
}

class TodoInputRulesTest {
    @Test
    fun limitBlocksInsteadOfCutting() {
        val hundred = "가".repeat(100)
        assertTrue(TodoInputRules.canSubmit(hundred))
        assertFalse(TodoInputRules.isOverLimit(hundred))
        val over = "가".repeat(101)
        // 넘친 글은 받지 않되(추가 막힘) 단추는 보인다(꺼진 채) — 글을 되돌리거나 자르지 않는다.
        assertFalse(TodoInputRules.canSubmit(over))
        assertTrue(TodoInputRules.isOverLimit(over))
        assertTrue(TodoInputRules.showsAdd(over))
    }

    @Test
    fun blankIsNotATodo() {
        assertFalse(TodoInputRules.canSubmit("   "))
        assertFalse(TodoInputRules.showsAdd(" \n"))
        assertTrue(TodoInputRules.canSubmit(" 빨래 "))
    }
}
