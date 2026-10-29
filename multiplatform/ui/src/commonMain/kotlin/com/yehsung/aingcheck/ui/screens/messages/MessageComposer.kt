// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd
//
// 입력줄(시안 B 04): 전송 실패 안내 한 줄 · 180자부터 카운터 · 여러 줄 입력칸(최대 5줄까지 자라고 그 뒤 스크롤) 안 오른쪽 [보내기] ·
// 캡슐 왼쪽 바깥 이모티콘 단추.
//
// INV-MessagesComposerView-ee560ff3 이식: 한글 조합 중에는 보내지 않는다 — [보내기]는 ComposerInputRules.sendPlan(코어 sendAction)이 정한다.
//   조합 중이면 조합 영역을 확정 글로 치고(commitThenSend) 그 글로 다시 판정해 보낸 뒤, 입력칸을 프로그램 편집으로 비운다 — 그 편집이 조합을
//   끝내고 IME 를 다시 시작해 비운 칸에 조합 글자가 되살아나지 않는다(E§8.2 ②③). 스토어 sendDraft(isComposing) 가 이중으로 막는다.
//   IME 재생 시험(androidApp androidTest ImeReplayDeviceTest · Gboard 녹화)이 "보낸 글 = 기대 · 비운 뒤 빈칸 · 예외 0"을 기기에서 잰다.
// INV-MessagesComposerView-db024955 이식: 줄바꿈은 키보드의 return(엔터)이다 — 키보드 동작에 보내기를 걸지 않는다(onKeyboardAction 없음). 보내기는 단추 하나.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.stores.messages.MessagesComposerRules
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingTextInput
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.StickerArt
import com.yehsung.aingcheck.ui.screens.session.kit.StickerArtState
import com.yehsung.aingcheck.ui.screens.session.kit.hairlineBorder
import com.yehsung.aingcheck.ui.screens.session.kit.isComposing
import com.yehsung.aingcheck.ui.screens.session.kit.rememberStickerArt
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/**
 * 대화 입력줄. [state] 를 바깥이 쥐면(계측 시험 · 미리보기) 그것을 쓰고, 아니면 상대마다 하나를 만든다(프로세스 죽음 뒤에도 남는다).
 * [onStickerSheet] 는 이모티콘 시트를 연다(시트는 대화 화면이 그린다).
 */
@Composable
fun MessageComposer(
    store: MessagesStore,
    peerID: String,
    modifier: Modifier = Modifier,
    onStickerSheet: () -> Unit,
    state: TextFieldState = rememberSaveable(peerID, saver = TextFieldState.Saver) { TextFieldState(store.draft(peerID)) },
) {
    val colors = AingTheme.colors
    // 칸 ↔ 스토어 초안(상대별 · 대화를 나갔다 와도 남는다). 조합 중에는 바깥 값으로 덮지 않는다(FieldStoreSync).
    val sync = rememberFieldStoreSync(peerID)
    BindFieldToStore(state, sync, read = { store.draft(peerID) }, write = { store.setDraft(it, peerID) })

    val text = state.text.toString()
    val composing = state.isComposing
    val counter = MessagesComposerRules.counterText(text)
    val overflowing = ComposerInputRules.isOverflowing(text)
    val sendEnabled = ComposerInputRules.sendEnabled(composing, store.canSend(peerID) || isSendableField(text), store.isSending)
    val looksEnabled = ComposerInputRules.sendLooksEnabled(store.isSending, sendEnabled)
    val metrics = MessagesComposerRules.sendButtonMetrics(MessagesComposerRules.minimumTouchTarget)

    fun send() {
        val current = state.text.toString()
        when (val plan = ComposerInputRules.sendPlan(current, state.isComposing, store.isSending)) {
            ComposerInputRules.SendPlan.None -> Unit
            is ComposerInputRules.SendPlan.Send, is ComposerInputRules.SendPlan.CommitThenSend -> {
                val committed = if (plan is ComposerInputRules.SendPlan.Send) plan.text else (plan as ComposerInputRules.SendPlan.CommitThenSend).text
                // 확정 글을 스토어에 먼저 싣고(입력칸 → 스토어 흐름은 한 박자 늦다) 확정된 것으로 보낸다.
                store.setDraft(committed, peerID)
                if (store.sendDraft(peerID, isComposing = false)) {
                    // 보낸 글은 스토어가 넘겨받았다 — 메아리 기준을 비운 칸으로 옮겨, 실패 때 스토어가 되돌린 글이 입력칸에 서게 한다.
                    sync.handedOver("")
                    state.clearText()
                }
            }
        }
    }

    Column(
        modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(horizontal = AingDimens.sideMargin)
            .padding(top = 6.dp, bottom = 8.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        store.sendNotices[peerID]?.let { InlineNotice(it, NoticeKind.Warning, Modifier.testTag(MessagesTags.SEND_NOTICE)) }
        if (counter != null) {
            Text(
                counter,
                style = MaterialTheme.typography.labelSmall,
                color = if (overflowing) colors.danger else colors.label2,
                modifier = Modifier.padding(end = 8.dp).testTag(MessagesTags.COUNTER)
                    .semantics { contentDescription = counter.replace("/", "자 중 ") + "자" },
            )
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            StickerButton(onStickerSheet)
            val shape = RoundedCornerShape((MessagesComposerRules.minimumTouchTarget / 2).dp)
            Row(
                Modifier
                    .weight(1f)
                    .background(colors.surface, shape)
                    .hairlineBorder(if (overflowing) colors.danger else colors.separator, (MessagesComposerRules.minimumTouchTarget / 2).dp,
                        if (overflowing) 1.dp else AingDimens.hairline),
                verticalAlignment = Alignment.Bottom,
            ) {
                AingTextInput(
                    state = state,
                    placeholder = MessagesComposerRules.placeholder,
                    modifier = Modifier.weight(1f).heightIn(min = 44.dp).padding(start = 16.dp, top = 11.dp, bottom = 11.dp, end = 4.dp),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    lineLimits = TextFieldLineLimits.MultiLine(minHeightInLines = 1, maxHeightInLines = 5),
                    tag = MessagesTags.COMPOSER_FIELD,
                )
                Box(
                    Modifier
                        .size(metrics.diameter.dp)
                        .clickable(enabled = sendEnabled, role = Role.Button, onClick = ::send)
                        .semantics { contentDescription = if (store.isSending) "보내는 중" else "보내기" }
                        .testTag(MessagesTags.SEND),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.size(metrics.visibleDiameter.dp).background(if (looksEnabled) colors.accentFill else colors.fill, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (store.isSending) {
                            CircularProgressIndicator(Modifier.size(14.dp), color = colors.onAccentFill, strokeWidth = 2.dp)
                        } else {
                            AingIcon(sf("arrow.up", AppIcon.ArrowUpward), null, size = metrics.visibleGlyphSize.dp,
                                tint = if (looksEnabled) colors.onAccentFill else colors.label3)
                        }
                    }
                }
            }
        }
    }
}

/** 스토어 초안이 한 박자 늦을 때(방금 친 글) 단추가 꺼져 보이지 않게 — 입력칸 글로도 판정한다(같은 MessageBody 판정). */
private fun isSendableField(text: String): Boolean =
    com.yehsung.aingcheck.core.rules.text.MessageBody.validate(text) is com.yehsung.aingcheck.core.rules.text.MessageBodyValidation.ok

/**
 * 입력칸 왼쪽 바깥의 이모티콘 단추. 누르면 고르는 **시트**가 뜬다.
 * INV-MessagesComposerView-f4a8e522 이식: 시트를 고른 까닭 — 맥 인라인 그리드는 좁은 화면 × 전송 왕복에서 닫을 길이 0 이 됐다. 폰 시트는 아래로
 *   밀어 닫기가 구조적으로 살아 있고 머리의 ✕ 가 명시적 출구다(MessagesStickerSheet).
 * INV-MessagesComposerView-1f534abe 이식: 보내는 중에도 이 단추를 끄지 않는다 — 끄면 왜 못 보내는지 말할 자리가 없어진다(시트가 까닭 한 줄을 세운다).
 * 그림은 아잉이 기쁨이고 못 읽으면 얼굴 기호다(빈 자리를 만들지 않는다).
 */
@Composable
private fun StickerButton(onClick: () -> Unit) {
    val colors = AingTheme.colors
    val state = rememberStickerArt()
    val metrics = MessagesComposerRules.sendButtonMetrics(MessagesComposerRules.minimumTouchTarget)
    Box(
        Modifier
            .size(metrics.diameter.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = AingStickerText.buttonLabel }
            .testTag(MessagesTags.STICKER_BUTTON),
        contentAlignment = Alignment.Center,
    ) {
        val art = (state as? StickerArtState.Ready)?.art?.get(AingSticker.joy)
        if (art != null) {
            Image(art, contentDescription = null, modifier = Modifier.size(metrics.visibleDiameter.dp))
        } else if (state is StickerArtState.Ready) {
            AingIcon(sf("face.smiling", AppIcon.Mood), null, size = (metrics.visibleDiameter * 0.7).dp, tint = colors.label2)
        }
    }
}

/** 이모티콘 판정의 단일 자리를 화면 밖에서도 쓰게(자리 말풍선 · 말풍선 둘 다 이것을 부른다). */
internal fun stickerOf(body: String, state: StickerArtState) = StickerArt.drawable(body, state)
