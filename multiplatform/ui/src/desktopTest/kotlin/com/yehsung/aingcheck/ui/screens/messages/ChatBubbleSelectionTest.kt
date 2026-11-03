// 원본: 아이폰 0860faf1 Tests/CheckMobileKitTests/V1017BubbleSelectionMobileTests.swift(메뉴 거르기 · 공유 거절 · 복사 글 · 고르는 중 링크 · 고르기 색).
// 판 7 Android: 말풍선 고르기 규칙(ChatBubbleSelection)을 **값으로** 잰다 — 화면이 실제로 부르는지는 Android 호스트 시험(MessagesChatMarkdownSnapshotTest)이 잰다.
// 복사의 핵심: 고르기 칸은 고른 글을 "그린 글의 부분 AnnotatedString" 으로만 내준다(구간 숫자를 안 준다). 조각 표식으로 구간을 되찾아 코어
// ChatMarkdownCopy.text 하나를 부르므로, 모든 구간에서 코어와 같은 글이 나와야 한다(기준선: 표식이 없으면 같은 글자 둘이 있는 글에서 다른 링크를 담는다).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.text.contextmenu.data.TextContextMenuKeys
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownCopy
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPieces
import com.yehsung.aingcheck.ui.theme.AingColors
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChatBubbleSelectionTest {
    private val colors = ChatBubbleMarkdown.Colors(text = Color(0xFF111111), link = Color(0xFF0066FF), disclosure = Color(0xFF888888))
    private val style = ChatBubbleMarkdown.style(
        TextStyle(fontSize = 16.sp, lineHeight = 21.sp),
        listOf(TextStyle(fontSize = 22.sp), TextStyle(fontSize = 20.sp), TextStyle(fontSize = 17.sp)),
        Density(2f, 1f),
    )

    private val bodies = listOf(
        "**굵게** [자료](https://a.example/doc) 끝",
        "## 제목\n[naver.com](https://evil.example/login) 은 *기울임* 그대로",
        // 같은 보이는 글자("자료 (a.example)")가 둘 — 여는 곳이 다르다(첫 자리로 찾으면 둘째를 고른 복사가 틀린다).
        "[자료](https://a.example/1) 와 [자료](https://a.example/2)",
        "https://aingcheck.app/map 참고 **굵게**\n둘째 줄",
        "평범한 말 그대로",
    )

    @Test
    fun everySelectedRangeCopiesWhatTheCoreRuleCopies() {
        var ranges = 0
        for (body in bodies) {
            val pieces = ChatMarkdownPieces.pieces(body)
            val drawn = ChatMarkdownPieces.drawn(pieces)
            val marked = ChatBubbleSelection.marked(ChatBubbleMarkdown.annotated(pieces, colors, style), pieces)
            assertEquals(drawn, marked.text, "표식이 글자를 바꿨다")
            for (start in 0 until drawn.length) {
                for (end in start + 1..drawn.length) {
                    // 고르기 칸이 내주는 것과 같은 꼴: 그린 글의 부분(표식이 잘린 채 따라온다).
                    val selected = marked.subSequence(start, end)
                    assertEquals(ChatMarkdownCopy.text(pieces, start, end), ChatBubbleSelection.copyText(selected, pieces), "\"$body\" [$start, $end) \"${selected.text}\"")
                    ranges++
                }
            }
        }
        assertTrue(ranges > 1_000, "잰 구간이 적다: $ranges")
    }

    @Test
    fun withoutPieceMarksTheSecondOfTwoSameLabelsCopiesTheWrongAddress() {
        // 기준선: 표식이 없으면(그린 글에서 처음 찾은 자리로 접힌다) 둘째 [자료] 를 골라도 첫째 주소를 담는다 — 위 시험이 표식을 재는 증거.
        val body = "[자료](https://a.example/1) 와 [자료](https://a.example/2)"
        val pieces = ChatMarkdownPieces.pieces(body)
        val drawn = ChatMarkdownPieces.drawn(pieces)
        val second = drawn.lastIndexOf("자료 (a.example)")
        val range = second until second + "자료 (a.example)".length
        val marked = ChatBubbleSelection.marked(ChatBubbleMarkdown.annotated(pieces, colors, style), pieces)
        val withMarks = ChatBubbleSelection.copyText(marked.subSequence(range.first, range.last + 1), pieces)
        val withoutMarks = ChatBubbleSelection.copyText(AnnotatedString(drawn.substring(range.first, range.last + 1)), pieces)
        assertEquals("자료 (https://a.example/2)", withMarks)
        assertEquals("자료 (https://a.example/1)", withoutMarks)
        assertNotEquals(withMarks, withoutMarks)
    }

    @Test
    fun copyIsPlainTextWithRealAddresses() {
        val pieces = ChatMarkdownPieces.pieces("**굵게** [자료](https://a.example/doc) 끝")
        val marked = ChatBubbleSelection.marked(ChatBubbleMarkdown.annotated(pieces, colors, style), pieces)
        assertEquals("굵게 자료 (https://a.example/doc) 끝", ChatBubbleSelection.copyText(marked, pieces))
        // 꼬리표만 골라도 주소를 담는다(맥 표 그대로).
        val tag = marked.text.indexOf(" (a.example)")
        assertEquals("(https://a.example/doc)", ChatBubbleSelection.copyText(marked.subSequence(tag + 2, tag + 5), pieces))
        // 아무것도 안 골랐으면 아무것도 안 쓴다(보이는 글자가 새지 않는다).
        assertNull(ChatBubbleSelection.copyText(null, pieces))
        assertNull(ChatBubbleSelection.copyText(AnnotatedString(""), pieces))
        // 그린 글에 없는 글자(다른 말풍선의 글)는 접지 않는다.
        assertNull(ChatBubbleSelection.copyText(AnnotatedString("없는 글"), pieces))
    }

    @Test
    fun menuKeepsCopySelectAllTranslateAndReportOnly() {
        assertTrue(ChatBubbleSelection.keeps(TextContextMenuKeys.CopyKey, "Copy"))
        assertTrue(ChatBubbleSelection.keeps(TextContextMenuKeys.SelectAllKey, "모두 선택"))
        assertTrue(ChatBubbleSelection.keeps(ChatBubbleSelection.ReportKey, "이 메시지 신고하기"))
        // [번역]은 열쇠가 없어(PROCESS_TEXT 앱) 이름으로 — 한국어 · 영어 기기.
        for (label in listOf("번역", "Google 번역", "Translate", "translate")) assertTrue(ChatBubbleSelection.keeps(Any(), label), label)
        // 공유 · 웹 검색 · 찾아보기 · 똑똑한 선택 동작(이름 없음) · 잘라내기 · 붙여넣기 · 자동 채움은 거른다.
        for (label in listOf("공유", "Share", "웹 검색", "Web search", "검색", "찾아보기", "Look up", "열기", null)) {
            assertFalse(ChatBubbleSelection.keeps(Any(), label), "$label 를 남겼다")
        }
        for (key in listOf(TextContextMenuKeys.CutKey, TextContextMenuKeys.PasteKey, TextContextMenuKeys.AutofillKey)) {
            assertFalse(ChatBubbleSelection.keeps(key, null), "$key 를 남겼다")
        }
    }

    @Test
    fun aTapWhileSelectingNeverOpensALink() {
        assertEquals("https://a.example/doc", ChatBubbleSelection.linkToOpen(selecting = false, linkAtTap = "https://a.example/doc"))
        assertNull(ChatBubbleSelection.linkToOpen(selecting = true, linkAtTap = "https://a.example/doc"))
        assertNull(ChatBubbleSelection.linkToOpen(selecting = false, linkAtTap = null))
    }

    @Test
    fun selectionTintIsLabelOnMyBubbleAndAccentOnReceived() {
        for (palette in listOf(AingColors.Light, AingColors.Dark)) {
            val mine = ChatBubbleSelection.selectionColors(isMine = true, palette = palette)
            val received = ChatBubbleSelection.selectionColors(isMine = false, palette = palette)
            assertEquals(palette.label, mine.handleColor)
            assertEquals(palette.label.copy(alpha = ChatBubbleSelection.SELECTION_BACKGROUND_ALPHA), mine.backgroundColor)
            assertEquals(palette.accent, received.handleColor)
            assertEquals(palette.accent.copy(alpha = ChatBubbleSelection.SELECTION_BACKGROUND_ALPHA), received.backgroundColor)
            // 까닭: 기본(accent)은 내 말풍선 바탕(accentFill)과 같은 파랑 계열이다 — 내 말풍선에서는 다른 색이어야 한다.
            assertNotEquals(received.handleColor, mine.handleColor)
        }
    }
}
