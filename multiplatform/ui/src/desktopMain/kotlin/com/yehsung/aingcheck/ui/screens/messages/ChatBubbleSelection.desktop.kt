// 말풍선 고르기(ChatBubbleSelection.kt ① · ②) — 데스크톱 몫. 데스크톱은 서식이 꺼져(Windows v1 동결 — MessagesStore.chatMarkdown 기본값 false)
// 고르기 말풍선이 서지 않는다(대화 화면은 판 7 전 그대로 — 길게 누르기 메뉴 [복사] · [신고]). 공용 코드라 짝만 두고 아무것도 바꾸지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.ClipboardManager

@Suppress("DEPRECATION")
internal actual fun chatSelectClipboard(real: Clipboard, writer: ClipboardManager, text: () -> String?): Clipboard =
    ChatSelectClipboard(real, writer, text)

internal actual fun Modifier.chatBubbleSelectionMenu(onReport: (() -> Unit)?): Modifier = this
