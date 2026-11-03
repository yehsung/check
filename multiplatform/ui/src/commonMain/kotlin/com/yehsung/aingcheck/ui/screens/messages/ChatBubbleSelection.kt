// 원본: 아이폰 0860faf1 Sources/CheckMobileKit/Messages/MessagesBubbleSelection.swift(편집 메뉴 거르기 · 공유 거절 · 복사 글 · 고르는 중 링크 · 고르기 색) ·
//       MessagesConversationView.swift(고를 수 있는 글 칸 · 여백 띠 고르기 · 다시 그려도 고르던 구간 유지) ·
//       Sources/check/ChatBubbleTextView.swift:101-159 @ 12624739(고른 글자 복사 — 링크는 실제 주소째 · 서식 없이).
// 판 7 Android 이식 — 대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기"(맥과 가장 비슷, 메뉴는 기본 편집 메뉴 + 신고).
//
// 글 말풍선 본문은 SelectionContainer 안의 Text 다(서식 켠 조립 — 폰만 · MessagesStore.chatMarkdown). 길게 누르면 Compose 기본 고르기가 시작되고
// 시스템 글 도구 막대(길게 누르기) · 드롭다운(마우스 오른쪽)이 뜬다. 판 7 초안의 길게 누르기 메뉴 항목 → 시트 방식은 걷어 냈다(글 말풍선 자체가 고르기 칸이다).
// 지키는 것:
//  ① 메뉴: 시스템이 내놓은 항목 가운데 [복사] · [모두 선택] · [번역](기기가 내놓을 때만)을 남기고, 받은 말풍선이면 끝에 [이 메시지 신고하기](같은 신고 흐름 —
//     고른 구간을 먼저 지우고 연다: 아이폰 reportFromMenu · 검토 F2).
//     공유 · 웹 검색(PROCESS_TEXT) · 똑똑한 선택 동작(링크 열기 · 전화 등)은 걸러 낸다 — 보이는 글자(호스트 꼬리표째)를 다른 앱으로 넘기고,
//     링크 열기는 여는 문(ChatBubbleMarkdown.follow — isOpenable)을 거치지 않는다.
//  ② [복사]: 고른 구간을 **서식 없이**, `[글](주소)` 링크는 꼬리표 대신 **실제 주소**째(코어 ChatMarkdownCopy.text — 맥 ⌘C · 아이폰 고른 글 복사와 한 함수).
//     고르기 칸의 기본 복사는 보이는 글자(꼬리표째)를 붙여넣기판에 쓰므로, 말풍선마다 붙여넣기판(LocalClipboard)을 갈아 끼워 그 쓰기를 가로챈다.
//  ③ 고르는 중(고른 글자가 있다)엔 한 번 누름이 링크를 열지 않는다 — 그 누름은 고른 것을 지우는 누름이다(누름 시작 · 끝 두 자리에서 본다).
//  ④ 여백 띠(위 8 · 좌우 13 · 아래 9)를 길게 눌러도 가장 가까운 낱말을 고른다 — 짧은 말풍선에서도 메뉴([신고])가 뜬다(아이폰 · 맥 검토 P1).
//  ⑤ 고르기 색: 내 말풍선은 본문 글자색(label), 받은 말풍선은 accent — 기본(MaterialTheme primary = accent)은 파란 내 말풍선 위에서 안 보인다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.text.contextmenu.data.TextContextMenuKeys
import androidx.compose.foundation.text.selection.SelectionState
import androidx.compose.foundation.text.selection.TextSelectionColors
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.NativeClipboard
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.buildAnnotatedString
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownCopy
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPiece
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPieces
import com.yehsung.aingcheck.ui.theme.AingColors

/** 말풍선 고르기 규칙(①~⑤). 화면 없이 잰다 — 부르는 자리는 ConversationScreen 의 BubbleContent · 손짓 상자다. */
object ChatBubbleSelection {
    /** [이 메시지 신고하기] 항목의 열쇠(받은 말풍선만 — 메뉴 끝). */
    val ReportKey: Any = ReportMenuKey

    private object ReportMenuKey {
        override fun toString(): String = "ChatBubbleSelection.ReportKey"
    }

    /** 조각 표식 — 고른 글(그린 글의 부분 AnnotatedString)에서 그린 글 구간을 되찾는다. 값은 조각 차례(ChatMarkdownPieces.pieces 의 자리). */
    const val PIECE_TAG = "aingcheck.chat.piece"

    /** 고르기 강조의 옅기(Compose 기본 TextSelectionColors 와 같은 0.4). */
    const val SELECTION_BACKGROUND_ALPHA = 0.4f

    /**
     * [번역]인가 — Compose 에 [번역] 열쇠가 없어(기기의 번역 앱이 PROCESS_TEXT 항목으로 내놓는다) **이름**으로 알아본다
     * (아이폰도 비공개 선택자 대신 이름의 "translate" 로 알아본다). 기기 언어가 한국어면 "번역", 영어면 "Translate".
     * 글 분류기의 똑똑한 동작으로 오는 번역은 Compose 가 항목 꼴을 감춰 이름을 읽을 수 없어 걸러진다(안드로이드 몫 chatBubbleMenuLabel).
     */
    fun isTranslate(label: String?): Boolean {
        val name = label?.lowercase() ?: return false
        return "번역" in name || "translate" in name
    }

    /**
     * ① 메뉴에 남기는가: [복사] · [모두 선택] · [번역] · [신고]. 그 밖(공유 · 웹 검색 · 똑똑한 선택 동작 · 잘라내기 · 붙여넣기 · 자동 채움)은 거른다.
     * 구분선은 Compose 가 무리 사이에 스스로 두고 거름에 넘기지 않는다(2026-11-04 Robolectric 실측 — [복사] [모두 선택] | [번역] | [신고]).
     */
    fun keeps(key: Any, label: String?): Boolean =
        key == TextContextMenuKeys.CopyKey || key == TextContextMenuKeys.SelectAllKey || key == ReportKey || isTranslate(label)

    /** 그린 글([text] — ChatBubbleMarkdown.annotated(pieces, …))에 조각 표식을 단다. 그림은 바뀌지 않는다(글자 주석일 뿐이다). */
    fun marked(text: AnnotatedString, pieces: List<ChatMarkdownPiece>): AnnotatedString = buildAnnotatedString {
        append(text)
        var offset = 0
        for ((index, piece) in pieces.withIndex()) {
            val end = minOf(offset + piece.text.length, text.length)
            if (end > offset) addStringAnnotation(PIECE_TAG, index.toString(), offset, end)
            offset = end
        }
    }

    /**
     * 고른 글(그린 글의 부분 — 고르기 칸이 내주는 AnnotatedString, 조각 표식이 잘린 채 따라온다) → 그린 글 구간 `[start, end)`.
     *  · 조각 둘 이상에 걸치면: 첫 조각 표식의 길이가 그 조각 끝에서 몇 글자인지 말한다 → 시작이 하나로 정해진다.
     *  · 한 조각 안이면: 그 조각 글에서 고른 글자를 찾는다 — 같은 글자가 여럿이어도 복사 글은 같다(한 조각의 복사는 고른 글자 + 그 조각의 링크뿐이다).
     *  · 그린 글과 어긋나면(표식이 없다 등) 그린 글에서 처음 찾은 자리로 접는다. 그래도 없으면 null.
     */
    fun drawnRange(selected: AnnotatedString, pieces: List<ChatMarkdownPiece>): IntRange? {
        if (selected.isEmpty()) return null
        val drawn = ChatMarkdownPieces.drawn(pieces)
        val starts = IntArray(pieces.size)
        var offset = 0
        for (i in pieces.indices) {
            starts[i] = offset
            offset += pieces[i].text.length
        }
        val marks = selected.getStringAnnotations(PIECE_TAG, 0, selected.length).sortedBy { it.start }
        val first = marks.firstOrNull()
        val index = first?.item?.toIntOrNull()
        val candidate = when {
            first == null || index == null || index !in pieces.indices || first.start != 0 -> null
            marks.size > 1 -> starts[index] + pieces[index].text.length - (first.end - first.start)
            else -> pieces[index].text.indexOf(selected.text).takeIf { it >= 0 }?.let { starts[index] + it }
        }
        val start = candidate?.takeIf { it >= 0 && drawn.startsWith(selected.text, it) }
            ?: drawn.indexOf(selected.text).takeIf { it >= 0 }
            ?: return null
        return start until start + selected.length
    }

    /** ② 고른 글 → 붙여넣기판에 쓸 글자(서식 없음 · `[글](주소)` 는 실제 주소째). 아무것도 안 골랐으면 null(아무것도 안 쓴다). */
    fun copyText(selected: AnnotatedString?, pieces: List<ChatMarkdownPiece>): String? {
        val range = selected?.let { drawnRange(it, pieces) } ?: return null
        return ChatMarkdownCopy.text(pieces, listOf(range))
    }

    /** ③ 한 번 누름이 열 링크 — 고르는 중이면 열지 않는다. 누른 자리가 링크가 아니면 null. */
    fun linkToOpen(selecting: Boolean, linkAtTap: String?): String? = if (selecting) null else linkAtTap

    /** ⑤ 고르기 강조 · 손잡이 색. 내 말풍선은 label(라이트 검정 · 다크 흰색 — 파란 바탕 위 강조와 말풍선 밖 손잡이가 둘 다 보인다), 받은 말풍선은 accent. */
    fun selectionColors(isMine: Boolean, palette: AingColors): TextSelectionColors {
        val tint = if (isMine) palette.label else palette.accent
        return TextSelectionColors(handleColor = tint, backgroundColor = tint.copy(alpha = SELECTION_BACKGROUND_ALPHA))
    }

    /**
     * ④ 글 칸 좌표 [position](여백 띠 위라 글자 밖일 수 있다) → 가장 가까운 낱말 구간. 글자 칸 안으로 당겨 그 자리 글자를 찾고, 빈칸이면 앞 글자로,
     * 낱말 경계가 비면 그 한 글자를 고른다. 글이 비었으면 null.
     */
    fun nearestWord(layout: TextLayoutResult, position: Offset): TextRange? {
        val text = layout.layoutInput.text.text
        if (text.isEmpty()) return null
        val clamped = Offset(position.x.coerceIn(0f, layout.size.width.toFloat()), position.y.coerceIn(0f, layout.size.height.toFloat()))
        var offset = layout.getOffsetForPosition(clamped).coerceIn(0, text.length - 1)
        if (text[offset].isWhitespace() && offset > 0 && !text[offset - 1].isWhitespace()) offset -= 1
        val word = layout.getWordBoundary(offset)
        return if (word.collapsed) TextRange(offset, offset + 1) else word
    }
}

/**
 * 서식 말풍선 한 장의 손짓 재료(판 7): 그린 글 · 글자 배치 · 글 칸과 손짓 상자의 자리 · 고르기 상태. 손짓은 말풍선 바깥 상자(여백 포함)가 받고,
 * 여기서 글 칸 좌표로 옮겨 링크 판정(ChatBubbleMarkdown.linkAt) · 여백 낱말 고르기(④)를 부른다. 상태가 아니다(그리기를 다시 부르지 않는다).
 */
internal class ChatBubbleTextHit {
    var text: AnnotatedString? = null
    var layout: TextLayoutResult? = null
    var inner: LayoutCoordinates? = null
    var outer: LayoutCoordinates? = null

    /** 글 말풍선의 고르기 상태(이모티콘 말풍선 · 꺼진 조립은 null). */
    var selection: SelectionState? = null

    /** 누름이 시작될 때 고르는 중이었는가(③의 첫 자리 — 그 누름이 끝날 땐 고르기 칸이 이미 지웠을 수 있다). */
    private var selectingAtPress = false

    fun isSelecting(): Boolean = selection?.selectedTexts?.any { it.isNotEmpty() } == true

    fun notePress() {
        selectingAtPress = isSelecting()
    }

    /** 바깥 상자 좌표 [position] 의 링크 주소(손가락 오차 [slop]). 고르는 중이었거나 고르는 중이면 null(③). */
    fun linkToOpen(position: Offset, slop: Float): String? =
        ChatBubbleSelection.linkToOpen(selecting = selectingAtPress || isSelecting(), linkAtTap = linkAt(position, slop))

    fun linkAt(position: Offset, slop: Float): String? {
        val text = text ?: return null
        val layout = layout ?: return null
        val inner = inner?.takeIf { it.isAttached } ?: return null
        val outer = outer?.takeIf { it.isAttached } ?: return null
        return ChatBubbleMarkdown.linkAt(text, layout, inner.localPositionOf(outer, position), slop)
    }

    /**
     * ④ 바깥 상자 좌표 [position] 의 길게 누름 — 글자 칸 **밖**(여백 띠)이면 가장 가까운 낱말을 고른다(도구 막대가 뜬다). 글자 칸 안은 고르기 칸이
     * 스스로 받으므로 아무것도 안 한다. 골랐으면 true.
     */
    fun selectNearestWord(position: Offset): Boolean {
        val selection = selection ?: return false
        val layout = layout ?: return false
        val inner = inner?.takeIf { it.isAttached } ?: return false
        val outer = outer?.takeIf { it.isAttached } ?: return false
        val local = inner.localPositionOf(outer, position)
        val size = inner.size
        if (local.x >= 0f && local.y >= 0f && local.x < size.width && local.y < size.height) return false
        val range = ChatBubbleSelection.nearestWord(layout, local) ?: return false
        selection.select(range)
        return true
    }
}

/** 고르기 칸이 마지막으로 내준(비지 않은) 고른 글 — [복사]의 쓰기가 미뤄져 고르기가 먼저 지워져도 쓰일 글을 잃지 않게 쥔다(②). */
internal class ChatSelectionMemory {
    var last: AnnotatedString? = null

    fun note(texts: List<AnnotatedString>) {
        texts.firstOrNull { it.isNotEmpty() }?.let { last = it }
    }

    /** 지금 고른 글, 없으면 마지막으로 고른 글. */
    fun current(selection: SelectionState): AnnotatedString? = selection.selectedTexts.firstOrNull { it.isNotEmpty() } ?: last
}

/**
 * 고르기 칸의 복사가 쓰는 붙여넣기판을 갈아 끼운 것(②). 쓰기 요청이 오면 그 내용(보이는 글자 · 꼬리표째)을 버리고 [text] 를 서식 없이 쓴다
 * ([text] 가 null 이면 아무것도 쓰지 않는다 — 보이는 글자가 새지 않는다). 읽기 · 기기 붙여넣기판은 원래 것에 그대로 넘긴다.
 *
 * ★ 안드로이드에서는 이것이 `AndroidClipboard` 여야 한다([chatSelectClipboard] 의 안드로이드 몫이 그 짝을 단다). 글 칸 · 도구 막대는 메뉴를 띄우기 전에
 *   붙여넣기 가능 여부를 이 붙여넣기판의 기기 참조(getNativeClipboardManager)로 묻는데, AndroidClipboard 가 아니면 IllegalArgumentException 으로 죽는다
 *   (판 7 검토 F4 를 부르는 자리에서 재다 찾음).
 */
internal open class ChatSelectClipboard(
    protected val real: Clipboard,
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

/** 플랫폼별 [ChatSelectClipboard] — 안드로이드는 `AndroidClipboard` 짝까지 단다(위 ★). */
@Suppress("DEPRECATION")
internal expect fun chatSelectClipboard(real: Clipboard, writer: ClipboardManager, text: () -> String?): Clipboard

/**
 * ① 고르기 메뉴의 거름 + 받은 말풍선의 [이 메시지 신고하기]([onReport] 가 있을 때 — 내 말풍선 · 보내는 중 말풍선은 null). 고르기 칸의 **조상**에 단다.
 * 항목 이름을 읽는 법 · 항목을 짓는 함수가 플랫폼마다 달라 몫을 나눈다.
 */
internal expect fun Modifier.chatBubbleSelectionMenu(onReport: (() -> Unit)?): Modifier
