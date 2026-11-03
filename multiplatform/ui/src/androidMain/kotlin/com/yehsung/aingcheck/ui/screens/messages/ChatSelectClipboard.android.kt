// 골라 복사 시트의 붙여넣기판(ChatSelectCopySheet.kt ①) — 안드로이드 몫. 판 7 · 검토 F4 를 부르는 자리에서 재다 찾은 결함의 수리.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.platform.AndroidClipboard
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.NativeClipboard

/**
 * 글 칸이 메뉴를 띄우기 전에 붙여넣기판의 기기 참조(`getNativeClipboardManager`)를 묻는다 — `AndroidClipboard` 가 아니면 IllegalArgumentException.
 * 기기 참조는 원래 붙여넣기판의 것을 그대로 준다(읽기 · 붙여넣기 가능 여부는 기기 그대로 — 쓰기만 [ChatSelectClipboard] 가 가로챈다).
 */
private class AndroidChatSelectClipboard(
    real: Clipboard,
    @Suppress("DEPRECATION") writer: ClipboardManager,
    text: () -> String?,
) : ChatSelectClipboard(real, writer, text), AndroidClipboard {
    override val clipboardManager: android.content.ClipboardManager get() = real.nativeClipboard

    override val nativeClipboard: NativeClipboard get() = real.nativeClipboard
}

@Suppress("DEPRECATION")
internal actual fun chatSelectClipboard(real: Clipboard, writer: ClipboardManager, text: () -> String?): Clipboard =
    AndroidChatSelectClipboard(real, writer, text)
