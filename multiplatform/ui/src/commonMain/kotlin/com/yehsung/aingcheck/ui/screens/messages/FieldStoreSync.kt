// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (MessagesComposerTextView.updateUIView — 조합 중에는 바깥 값으로 덮지 않는다 ·
//       Binding(get: store.draft, set: store.setDraft))
//
// 입력칸 ↔ 스토어 초안 동기화 한 벌(대화 입력줄 · 확성기 글 칸). Compose 칸이 글의 주인이고, 스토어 초안은 그 그림자다.
//   칸 → 스토어: 칸 글이 바뀔 때마다 싣는다(조합 글 포함 — 스토어는 늘 마지막 음절까지 본다).
//   스토어 → 칸: 스토어가 **스스로** 글을 바꿨을 때만(보내기 실패로 되돌림 · 보냄으로 비움) — 판정은 ComposerInputRules.externalDraft 하나.
//   시작: 칸이 이긴다(칸은 스토어 초안으로 만들어졌거나 — 같다 — 프로세스 죽음 뒤 칸이 되살린 글이다).
//
// 바깥 값은 그 순간의 스토어 값을 읽어 판정한다(snapshotFlow) — 그리기 때 붙잡은 옛 값으로 판정하면, 그 사이 친 글을 옛 초안으로 되돌린다
// (화면 스냅숏의 음성 기준선이 처음 잡은 결함: 칸에 넣은 "안녕"이 빈 초안으로 지워졌다).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import com.yehsung.aingcheck.ui.screens.session.kit.isComposing
import kotlinx.coroutines.launch

/** 칸이 스토어에 마지막으로 실은 글(바깥 값의 메아리를 가르는 기준). [handedOver] 는 글을 스토어에 넘긴 순간(보내기) 기준을 비운 칸으로 옮긴다. */
class FieldStoreSync {
    var lastPushed: String? = null
        internal set

    fun handedOver(fieldText: String = "") {
        lastPushed = fieldText
    }
}

@Composable
fun rememberFieldStoreSync(key: Any?): FieldStoreSync = remember(key) { FieldStoreSync() }

/** 칸과 스토어 글을 잇는다([read] · [write] 는 스토어의 그 칸). */
@Composable
fun BindFieldToStore(state: TextFieldState, sync: FieldStoreSync, read: () -> String, write: (String) -> Unit) {
    LaunchedEffect(state, sync) {
        val initial = state.text.toString()
        if (read() != initial) write(initial)
        sync.lastPushed = initial
        launch {
            snapshotFlow { state.text.toString() }.collect { text ->
                if (read() != text) {
                    sync.lastPushed = text
                    write(text)
                }
            }
        }
        launch {
            snapshotFlow { read() }.collect { stored ->
                ComposerInputRules.externalDraft(stored, sync.lastPushed, state.text.toString(), state.isComposing)?.let { state.setTextAndPlaceCursorAtEnd(it) }
            }
        }
    }
}
