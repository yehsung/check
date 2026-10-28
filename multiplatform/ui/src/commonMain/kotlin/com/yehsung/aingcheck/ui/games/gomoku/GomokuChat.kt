// 원본: Sources/CheckMobileKit/Games/GamesGomokuChat.swift @ 3bd04bd
//
// 대국·결과 화면 아래 **반쯤 올라온 대화 서랍**(시안 B 09) — 판과 함께 보인다.
//  · 접힘: 머리(대화 · [대화 끄기] · ⋯) · 최근 말 둘 · 빠른 문구 가로 줄 + [키보드].
//  · 펼침: 대화 전체(높이 상한) · 빠른 문구 · 상태 줄 · 입력칸(100자, 80자부터 카운터).
// 맥 `GomokuChatCard` 와 같은 규칙: 음소거는 서버가 아는 판 상태라 상대에게도 표시된다 · 실패한 말은 초안에 남는다 · 채팅 왕복은 착수·기권을 잠그지 않는다.
//
// 신고·차단(애플 심사 지침 1.2 · Play UGC 정책): 이 서랍은 자유 입력 100자를 주고받는 UGC 면이라 머리 ⋯ 에 [신고하기]·[차단하기]를 둔다. 시트는 메시지 탭과
// **같은 것**을 쓴다 — 조립이 넣는 [BoardGameSafety](메시지 스토어 문)가 없으면 메뉴를 세우지 않는다. 차단 뒤에는 이 판의 채팅을 끈다(판은 그대로 —
// 판돈이 걸려 있다).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuChatMessage
import com.yehsung.aingcheck.core.stores.gomoku.GomokuNoticeText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuQuickPhrase
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

@Composable
internal fun GomokuChatDrawer(gomoku: GomokuStore, opponent: GomokuUser, safety: BoardGameSafety?, state: GomokuScreenState) {
    val colors = AingTheme.colors
    val expanded = state.chatExpanded
    val opponentName = opponent.displayName.ifEmpty { GomokuPhoneText.opponentFallbackName }
    var menuOpen by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp)
            .background(colors.glass, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
            .padding(horizontal = 14.dp)
            .testTag("gomoku-chat-drawer"),
    ) {
        // 끌개
        Box(
            Modifier.fillMaxWidth().heightIn(min = 16.dp).clickable { state.chatExpanded = !expanded }
                .semantics { contentDescription = if (expanded) GomokuPhoneText.chatClose else GomokuPhoneText.chatOpen },
            contentAlignment = Alignment.Center,
        ) { Box(Modifier.size(36.dp, 5.dp).background(colors.label3, CircleShape)) }
        // 머리
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                Modifier.heightIn(min = AingDimens.minimumTarget).clickable { state.chatExpanded = !expanded },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(GomokuPhoneText.chatTitle, style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = colors.label)
                AingIcon(if (expanded) AppIcon.ExpandMore else AppIcon.ExpandLess, contentDescription = null, size = 16.dp, tint = colors.label2)
            }
            Spacer(Modifier.weight(1f))
            Row(
                Modifier.heightIn(min = AingDimens.minimumTarget).clickable(enabled = !gomoku.isSendingChat) { gomoku.setChatMuted(!gomoku.isMuted) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                AingIcon(if (gomoku.isMuted) AppIcon.Notifications else AppIcon.NotificationsOff, contentDescription = null, size = 16.dp, tint = colors.accent)
                Text(if (gomoku.isMuted) GomokuPhoneText.chatUnmuteAction else GomokuPhoneText.chatMuteAction, style = BoardText.subheadline(), color = colors.accent)
            }
            if (safety != null && opponent.id.isNotEmpty()) {
                Box {
                    BarIcon(AppIcon.MoreHoriz, GomokuPhoneText.moreMenu, "gomoku-chat-safety") { menuOpen = true }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        // 신고 대상은 **사람**이다(대국 채팅 줄은 1:1 메시지와 다른 표라 그 id 로는 운영자가 못 찾는다).
                        DropdownMenuItem(text = { Text("신고하기") }, onClick = { menuOpen = false; safety.report(opponent.id, opponentName) })
                        DropdownMenuItem(text = { Text("차단하기", color = colors.danger) }, onClick = {
                            menuOpen = false
                            safety.block(opponent.id)
                            if (!gomoku.isMuted) gomoku.setChatMuted(true)
                        })
                    }
                }
            }
        }
        // 대화
        when {
            gomoku.isMuted -> CenteredLine(GomokuNoticeText.chatMutedByMe)
            gomoku.chat.isEmpty() -> CenteredLine(GomokuPhoneText.chatEmpty)
            expanded -> Column(Modifier.fillMaxWidth().heightIn(min = 60.dp, max = 220.dp).verticalScroll(rememberScrollState(Int.MAX_VALUE)), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                gomoku.chat.forEach { ChatBubble(it) }
            }
            else -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { gomoku.chat.takeLast(2).forEach { ChatBubble(it) } }
        }
        // 빠른 문구(회색 알약 — 말풍선과 모양을 갈라 둔다)
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                GomokuQuickPhrase.entries.forEach { phrase ->
                    Text(
                        phrase.text, style = BoardText.subheadline(), color = colors.label, maxLines = 1,
                        modifier = Modifier.heightIn(min = AingDimens.minimumTarget).padding(vertical = 6.dp)
                            .background(colors.fill, CircleShape).clickable(enabled = !gomoku.isSendingChat) { gomoku.sendQuick(phrase) }
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }
            if (!expanded) {
                Box(
                    Modifier.size(AingDimens.minimumTarget).clickable { state.chatExpanded = true }.semantics { contentDescription = GomokuPhoneText.chatWrite },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(32.dp).background(colors.fill, CircleShape), contentAlignment = Alignment.Center) {
                        AingIcon(AppIcon.Keyboard, contentDescription = null, size = 16.dp, tint = colors.label)
                    }
                }
            }
        }
        // 상태 줄 — 조건이 참인 동안 서 있다.
        gomoku.chatNotice?.takeIf { it.isNotEmpty() }?.let { StatusLine(it, colors.pending) }
        if (gomoku.isOpponentMuted) StatusLine(GomokuNoticeText.chatMutedByOpponent, colors.pending)
        if (!gomoku.opponentChatCapable) StatusLine(GomokuNoticeText.chatOpponentOutdated, colors.label2)
        if (expanded) {
            val length = gomoku.chatDraftLength
            val showsCounter = length >= gomoku.chatMaxLength * GomokuPhoneText.chatCounterFromRatio
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // 한 줄 입력칸 — 키보드의 보내기 키가 곧 전송(IME 조합 중에는 키가 먼저 조합을 확정한다).
                OutlinedTextField(
                    value = gomoku.chatDraft,
                    onValueChange = { gomoku.chatDraft = it },
                    modifier = Modifier.weight(1f).testTag("gomoku-chat-input"),
                    placeholder = { Text(GomokuPhoneText.chatPlaceholder, color = colors.label3Text) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                    keyboardActions = KeyboardActions(onSend = { gomoku.sendChatDraft() }),
                    supportingText = if (showsCounter) ({ Text("$length/${gomoku.chatMaxLength}", color = if (length > gomoku.chatMaxLength) colors.danger else colors.label2) }) else null,
                )
                BoardButton(GomokuPhoneText.chatSend, kind = BoardButtonKind.Filled, small = true, enabled = gomoku.canSendChatNow) { gomoku.sendChatDraft() }
            }
        } else {
            Spacer(Modifier.width(1.dp).heightIn(min = 8.dp))
        }
    }
}

@Composable
private fun CenteredLine(text: String) {
    Text(text, style = BoardText.rowSubtitle(), color = AingTheme.colors.label2, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
}

@Composable
private fun StatusLine(text: String, color: androidx.compose.ui.graphics.Color) {
    Text(text, style = BoardText.rowSubtitle(), color = color, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
}

/** 말풍선(둥근 네모 · 받은 회색 / 보낸 파랑). 빠른 문구 알약과 모양을 갈라 둔다(비평: 둘이 거의 같아 헷갈렸다). */
@Composable
private fun ChatBubble(message: GomokuChatMessage) {
    val colors = AingTheme.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (message.isMine) Arrangement.End else Arrangement.Start) {
        Text(
            message.body,
            style = BoardText.subheadline(),
            color = if (message.isMine) colors.onAccentFill else colors.label,
            modifier = Modifier.background(if (message.isMine) colors.accentFill else colors.bubbleIn, RoundedCornerShape(14.dp)).padding(horizontal = 10.dp, vertical = 6.dp),
        )
    }
}
