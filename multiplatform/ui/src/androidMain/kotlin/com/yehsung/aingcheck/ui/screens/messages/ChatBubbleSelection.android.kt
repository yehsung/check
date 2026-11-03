// 말풍선 고르기(ChatBubbleSelection.kt ① · ②) — 안드로이드 몫. 판 7 · 대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기".
//  · 붙여넣기판: 검토 F4 를 부르는 자리에서 재다 찾은 결함의 수리(AndroidClipboard 짝) — 판 7 초안의 시트에서 옮겨 왔다.
//  · 메뉴: 시스템 글 도구 막대(길게 누르기) · 드롭다운(마우스 오른쪽)에 모인 항목을 이름째 거르고, 받은 말풍선이면 끝에 [이 메시지 신고하기]를 단다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.text.contextmenu.builder.item
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuComponent
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuItem
import androidx.compose.foundation.text.contextmenu.modifier.appendTextContextMenuComponents
import androidx.compose.foundation.text.contextmenu.modifier.filterTextContextMenuComponents
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.AndroidClipboard
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.NativeClipboard
import com.yehsung.aingcheck.core.rules.text.BlockReportText

/**
 * 도구 막대는 메뉴를 띄우기 전에 붙여넣기판의 기기 참조(`getNativeClipboardManager`)를 묻는다 — `AndroidClipboard` 가 아니면 IllegalArgumentException.
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

/**
 * 메뉴 항목의 이름 — 보통 항목(복사 · 모두 선택 · PROCESS_TEXT 앱: 번역 앱이면 "번역" · 웹 검색 앱 · 공유 앱 …)만 이름이 있다.
 * 글 분류기의 똑똑한 동작(링크 열기 · 전화 · 기기가 외국어 글에 내놓는 번역 등)은 Compose 가 그 항목 꼴(TextContextMenuTextClassificationItem)을
 * 모듈 안쪽(internal)으로 감춰 이름을 읽을 수 없다 — null 이라 모두 걸러진다. 그래서 [번역]은 번역 앱이 PROCESS_TEXT 로 내놓을 때만 남는다.
 */
internal fun chatBubbleMenuLabel(component: TextContextMenuComponent): String? = (component as? TextContextMenuItem)?.label

internal actual fun Modifier.chatBubbleSelectionMenu(onReport: (() -> Unit)?): Modifier {
    val filtered = filterTextContextMenuComponents { ChatBubbleSelection.keeps(it.key, chatBubbleMenuLabel(it)) }
    if (onReport == null) return filtered
    return filtered.appendTextContextMenuComponents {
        item(key = ChatBubbleSelection.ReportKey, label = BlockReportText.reportMessageAction) {
            close()
            onReport()
        }
    }
}
