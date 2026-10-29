// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (send() · sendEnabled · sendLooksEnabled · updateUIView 의 "조합 중에는 바깥 값으로 덮지 않는다")
// 원본: Sources/CheckMobileKit/Now/NowTodoSection.swift @ 3bd04bd (할 일 입력 — 상한 · 카운터)
//
// 입력줄 판정(순수 함수 — JVM 시험이 잰다, E§8.2 ⑤ "판정은 순수 함수로 두어 JVM 에서 잰다"). Composable 은 그리기만 한다.
//
// Compose 의 TextFieldState 는 조합 중인 글자(composition)를 **글 안에** 든다 — iOS SwiftUI 가 "마지막 음절이 바인딩에 없다"던 문제와
// 반대로, Android 의 위험은 "비운 뒤 되살아남" · "글자 수 상한에서 자모가 깨짐"이다(E§8.1). 그래서 판정 셋:
//   ① [보내기]: 조합 중이면 조합 영역을 확정된 글로 치고 보낸다(commitThenSend) — 스토어 `sendDraft(isComposing:)` 는 조합 중이면 이중으로 막는다.
//   ② 바깥 값(스토어 초안)으로 입력칸을 덮는 것은 **조합 중이 아닐 때만** · 내가 밀어 넣은 값의 메아리가 아닐 때만.
//   ③ 상한은 자르지 않는다 — 카운터를 빨갛게 하고 [보내기]/[추가]를 막는다.
package com.yehsung.aingcheck.ui.screens.messages

import com.yehsung.aingcheck.core.rules.text.MessageBody
import com.yehsung.aingcheck.core.rules.text.MessageBodyValidation
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.stores.messages.MessagesComposerRules

object ComposerInputRules {
    /** [보내기]를 눌렀을 때의 계획. [text] 는 그 순간 입력칸 글 전체(조합 영역 포함 — Compose 는 조합 글을 글 안에 든다). */
    sealed interface SendPlan {
        data object None : SendPlan

        /** 확정된 글을 그대로 보낸다. */
        data class Send(val text: String) : SendPlan

        /** 조합을 먼저 확정하고(조합 영역 = 확정 글) 그 글로 다시 판정해 보낸다. */
        data class CommitThenSend(val text: String) : SendPlan
    }

    /**
     * 판정은 코어 `MessagesComposerRules.sendAction` 한 벌을 부른다. 확정 글로 보낼 수 있는가 = 왕복 중이 아니고 본문이 서버 경계 안
     * (`MessageBody.validate` — 스토어 `canSend` 와 같은 판정). 조합 중이면 확정한 뒤 다시 판정하므로, 확정 글이 경계 밖이면 아무것도 안 한다.
     */
    fun sendPlan(text: String, composing: Boolean, isSending: Boolean): SendPlan {
        val sendable = !isSending && MessageBody.validate(text) is MessageBodyValidation.ok
        return when (MessagesComposerRules.sendAction(isComposing = composing, canSendCommittedDraft = sendable)) {
            MessagesComposerRules.SendAction.none -> SendPlan.None
            MessagesComposerRules.SendAction.send -> SendPlan.Send(text)
            MessagesComposerRules.SendAction.commitThenSend ->
                if (sendable) SendPlan.CommitThenSend(text) else SendPlan.None
        }
    }

    /** 단추를 켤지: 조합 중이면 켠다(누르면 확정한 뒤 판정한다) — 아니면 스토어 판정 그대로. 왕복 중이면 끈다. */
    fun sendEnabled(composing: Boolean, canSend: Boolean, isSending: Boolean): Boolean = !isSending && (composing || canSend)

    /** 보내기 원을 파랑으로 칠할지(보내는 중에도 파랑 — 돌림표가 흰색이다). */
    fun sendLooksEnabled(isSending: Boolean, sendEnabled: Boolean): Boolean = isSending || sendEnabled

    /**
     * 스토어 초안(바깥 값)을 입력칸에 옮길지 — 옮길 글을 돌려주고, 옮기지 않으면 null.
     * - 조합 중이면 덮지 않는다(덮으면 조합이 깨지고 글자가 되살아나거나 빠진다 — iOS `updateUIView`).
     * - 바깥 값이 내가 마지막으로 밀어 넣은 값([lastPushed])이면 메아리다 — 그 사이 더 친 글을 옛 값으로 되돌리지 않는다.
     * - 같으면 할 일이 없다.
     * 옮기는 경우: 보내기 실패로 스토어가 글을 되돌렸을 때(입력칸이 비어 있을 때만 — 스토어 규칙) · 대화를 다시 열었을 때.
     */
    fun externalDraft(storeDraft: String, lastPushed: String?, fieldText: String, composing: Boolean): String? {
        if (composing) return null
        if (storeDraft == fieldText) return null
        if (lastPushed != null && storeDraft == lastPushed) return null
        return storeDraft
    }

    /** 카운터를 빨갛게(넘침) — 보내기가 막힌다. 자르지 않는다. */
    fun isOverflowing(text: String): Boolean = MessagesComposerRules.isOverflowing(text)
}

/** 할 일 입력(새 줄 · 고치기) — 상한은 자르지 않고 막는다(iOS 는 넘는 입력을 되돌렸다 — 조합 중 되돌리기는 IME 를 깬다, E§8.2 ④). */
object TodoInputRules {
    /** [추가]·[완료]를 받을지: 다듬은 제목이 비지 않았고 상한(100자 · 코드포인트 1000) 안. */
    fun canSubmit(text: String): Boolean = TodoRules.normalizedTitle(text).isNotEmpty() && TodoRules.titleFitsLimits(text)

    /** 상한을 넘었는가(카운터 빨강). */
    fun isOverLimit(text: String): Boolean = !TodoRules.titleFitsLimits(text)

    /** [추가] 단추를 보일지(다듬은 제목이 있으면 — 넘쳐도 보이되 꺼진다). */
    fun showsAdd(text: String): Boolean = TodoRules.normalizedTitle(text).isNotEmpty()
}
