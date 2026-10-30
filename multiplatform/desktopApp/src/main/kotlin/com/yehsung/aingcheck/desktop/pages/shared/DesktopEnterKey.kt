// 원본: Sources/check/CheckTextEditor.swift @ a90d8623 (맥 NSTextView: hasMarkedText 이면 Return 은 조합 확정만, 보내지 않는다)
// 원본: multiplatform/ui/…/screens/messages/ComposerInputRules.kt(sendPlan — 코어 MessagesComposerRules.sendAction 한 벌)
//
// W3-c0 ⑥ — 데스크톱 대화 입력칸의 Enter. 폰은 IME [보내기] 단추가 보내지만 데스크톱은 하드웨어 Enter 가 보낸다(맥과 같다).
//  ① 조합 중(한글 IME 가 글자를 잡고 있다) Enter 는 **보내지 않는다** — 그 Enter 는 IME 의 '확정' 몫이다(가로채면 마지막 글자가 빠지거나 두 번 간다).
//  ② Shift+Enter 는 줄바꿈(입력칸에 넘긴다).
//  ③ 보낼 때는 ui 의 sendPlan 판정(조합 아님 · 왕복 중 아님 · 본문 경계 안)을 그대로 거친다 — 판정을 여기서 다시 만들지 않는다.
// 스토어 sendDraft(isComposing) 가 한 번 더 막는다(이중 가드).
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.ui.screens.messages.ComposerInputRules

object DesktopEnterKey {
    enum class Decision { SEND, PASS }

    fun decide(isEnterDown: Boolean, shift: Boolean, composing: Boolean): Decision =
        if (isEnterDown && !shift && !composing) Decision.SEND else Decision.PASS

    /**
     * 키 하나를 처리한다. 돌려주는 값 = 키를 먹었는가(true 면 입력칸에 가지 않는다). 조합 중·Shift·다른 키는 false(입력칸·IME 몫).
     * [send] 는 확정 글로 보낸다(조립: 스토어 setDraft → sendDraft(isComposing=false) → 칸 비우기). 보낼 글이 없으면 먹기만 한다(빈 줄 0).
     */
    fun handle(isEnterDown: Boolean, shift: Boolean, composing: Boolean, text: String, isSending: Boolean, send: (String) -> Unit): Boolean {
        if (decide(isEnterDown, shift, composing) != Decision.SEND) return false
        when (val plan = ComposerInputRules.sendPlan(text, composing = false, isSending = isSending)) {
            is ComposerInputRules.SendPlan.Send -> send(plan.text)
            is ComposerInputRules.SendPlan.CommitThenSend -> send(plan.text)
            ComposerInputRules.SendPlan.None -> Unit
        }
        return true
    }
}
