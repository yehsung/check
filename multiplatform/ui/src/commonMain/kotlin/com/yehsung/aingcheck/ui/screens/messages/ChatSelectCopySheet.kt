// 원본: Sources/check/ChatBubbleTextView.swift:101-159 @ 12624739(고른 글자 복사 — 링크는 실제 주소째 · 서식 없이 · 끌어 놓기 · 서비스 메뉴도 같은 글) ·
//       phone-1017 impl-args chat "받은 말풍선 글을 골라 복사" 추천안 A(메뉴 [골라 복사] → 시트에서 끌어 고르기) · critic "공유 · 번역 · 찾아보기 · 웹 검색이 꼬리표 글을 넘긴다".
// 판 7 Android 이식(대표 결정 "받은 말풍선도 드래그, 우클릭에 신고 유지" — 폰은 길게 누르기 메뉴가 그 자리다. 골라 복사 모양은 대표 결정 대기 —
// 추천안 A 로 만들고 ChatBubbleMarkdownSettings.selectCopy 하나로 끈다).
//
// 시트 안의 글은 말풍선과 **같은 조각 · 같은 서식**(ChatBubbleMarkdown.annotated)을 읽기 전용 글 칸에 그린다 — 길게 눌러 낱말을 고르고 손잡이로 넓힌다.
// 지키는 것 셋:
//  ① 복사는 **서식 없는 글**이고, 고른 구간에 `[글](주소)` 링크가 걸치면 꼬리표 " (호스트)" 대신 " (실제 주소)" 를 담는다(코어 ChatMarkdownCopy.text — 맥 표 그대로).
//     글 칸의 기본 복사는 보이는 글자(꼬리표째)를 붙여넣기판에 쓰므로, 이 시트는 붙여넣기판(LocalClipboard)을 갈아 끼워 그 쓰기를 가로챈다.
//  ② 글 칸 메뉴는 [복사] · [모두 선택]만 남긴다. 공유 · 번역 · 웹 검색(PROCESS_TEXT) · 똑똑한 선택 동작(링크 열기 · 전화 등)은 보이는 글자를 다른 앱에 넘긴다 —
//     꼬리표가 붙은 글이 나가고, 링크 열기는 여는 문(isOpenable)을 거치지 않는다. 그래서 걸러 낸다([ChatSelectCopyMenu.keeps]).
//  ③ 글은 바뀌지 않는다(읽기 전용 · 바뀐 값이 와도 글은 원래 글로 되돌린다). 키보드가 뜨지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.contextmenu.data.TextContextMenuKeys
import androidx.compose.foundation.text.contextmenu.modifier.filterTextContextMenuComponents
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.NativeClipboard
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownCopy
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPieces
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 골라 복사 시트의 글 · 고른 구간. 글 칸의 값은 여기 있고, 복사는 마지막으로 고른(접히지 않은) 구간을 코어 규칙으로 옮긴다. */
class ChatSelectCopyState(shown: String) {
    val pieces = ChatMarkdownPieces.pieces(shown)

    /** 시트에 보이는 글자 전부(꼬리표 포함 — 말풍선과 같은 글). */
    val drawn: String = ChatMarkdownPieces.drawn(pieces)

    var value: TextFieldValue by mutableStateOf(TextFieldValue(drawn, TextRange(0)))
        private set

    /**
     * 마지막으로 고른 구간. 글 칸의 복사는 붙여넣기판 쓰기를 **코루틴으로 미루고 그 사이 고른 것을 접는다** — 쓰는 순간의 값은 이미 접혀 있다.
     * 복사는 고른 것이 있을 때만 일어나므로, 그때 쓰일 구간은 언제나 마지막으로 고른 구간이다.
     */
    var lastSelection: TextRange? = null
        private set

    fun onValueChange(next: TextFieldValue) {
        // 읽기 전용 — 글은 바꾸지 않는다(고른 구간 · 조합만 받는다).
        val selection = TextRange(next.selection.start.coerceIn(0, drawn.length), next.selection.end.coerceIn(0, drawn.length))
        value = TextFieldValue(drawn, selection)
        if (!selection.collapsed) lastSelection = selection
    }

    /** 지금 복사할 글(서식 없음 · 링크는 실제 주소째). 고른 것이 없었으면 null. */
    fun copyText(): String? = lastSelection?.let { ChatMarkdownCopy.text(pieces, listOf(it.min until it.max)) }
}

/** 시트 글 칸 메뉴의 거름(②). */
object ChatSelectCopyMenu {
    /** 남기는 것은 [복사] · [모두 선택]뿐이다(그 밖 — 공유 · 번역 · 웹 검색 · 똑똑한 선택 동작 · 자동 채움 — 은 보이는 글자를 넘기거나 쓸 일이 없다). */
    fun keeps(key: Any): Boolean = key == TextContextMenuKeys.CopyKey || key == TextContextMenuKeys.SelectAllKey
}

/**
 * 글 칸의 복사가 쓰는 붙여넣기판을 갈아 끼운 것(①). 쓰기 요청이 오면 그 내용(보이는 글자)을 버리고 [text] 를 서식 없이 쓴다.
 * 읽기 · 기기 붙여넣기판은 원래 것에 그대로 넘긴다.
 */
private class ChatSelectClipboard(
    private val real: Clipboard,
    @Suppress("DEPRECATION") private val writer: ClipboardManager,
    private val text: () -> String?,
) : Clipboard {
    override suspend fun getClipEntry(): ClipEntry? = real.getClipEntry()

    override suspend fun setClipEntry(clipEntry: ClipEntry?) {
        val plain = text() ?: return
        writer.setText(AnnotatedString(plain))
    }

    override val nativeClipboard: NativeClipboard get() = real.nativeClipboard
}

/** 골라 복사 시트 본문 — 말풍선 모양 그대로(받은 말풍선 색 — 시트 바탕 위에서 읽히게) 읽기 전용 글 칸. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatSelectCopySheet(state: ChatSelectCopyState, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val style = rememberChatBubbleStyle()
    val bubbleColors = chatBubbleColors(isMine = false)
    val annotated = remember(state, style, bubbleColors) { ChatBubbleMarkdown.annotated(state.pieces, bubbleColors, style) }
    val transformation = remember(annotated) { VisualTransformation { TransformedText(annotated, OffsetMapping.Identity) } }
    @Suppress("DEPRECATION") val writer = LocalClipboardManager.current
    val real = LocalClipboard.current
    val clipboard = remember(real, writer, state) { ChatSelectClipboard(real, writer) { state.copyText() } }
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).testTag(MessagesTags.SELECT_COPY_SHEET)) {
        CompositionLocalProvider(LocalClipboard provides clipboard) {
            Box(
                Modifier
                    .filterTextContextMenuComponents { ChatSelectCopyMenu.keeps(it.key) }
                    .background(colors.bubbleIn, RoundedCornerShape(19.dp))
                    .padding(start = 13.dp, end = 13.dp, top = 8.dp, bottom = 9.dp),
            ) {
                BasicTextField(
                    value = state.value,
                    onValueChange = state::onValueChange,
                    readOnly = true,
                    textStyle = style.textStyle(state.pieces).copy(color = bubbleColors.text),
                    visualTransformation = transformation,
                    cursorBrush = SolidColor(Color.Transparent),
                    modifier = Modifier.fillMaxWidth().testTag(MessagesTags.SELECT_COPY_FIELD),
                )
            }
        }
    }
}
