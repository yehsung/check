// 골라 복사 시트의 붙여넣기판(ChatSelectCopySheet.kt ①) — 데스크톱 몫. 데스크톱은 서식이 꺼져(Windows v1 동결) 시트가 서지 않지만, 공용 코드라 짝은 둔다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.ClipboardManager

@Suppress("DEPRECATION")
internal actual fun chatSelectClipboard(real: Clipboard, writer: ClipboardManager, text: () -> String?): Clipboard =
    ChatSelectClipboard(real, writer, text)
