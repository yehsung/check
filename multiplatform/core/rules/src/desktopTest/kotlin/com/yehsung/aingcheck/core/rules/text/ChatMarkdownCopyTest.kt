// 원본: Tests/checkTests/ChatBubbleSelectionTests.swift:475-528 @ 12624739(고른_링크는_실제_주소째_복사한다 — 열세 칸 표) · ChatBubbleTextView.swift:103-142.
// 판 7 Android 이식: 고른 구간 → 복사 글 규칙(ChatMarkdownCopy)을 맥 표 그대로 잰다. 시트의 손짓 · 붙여넣기판 배선은 ui 시험 몫이다.
package com.yehsung.aingcheck.core.rules.text

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ChatMarkdownCopyTest {
    private fun select(drawn: String, part: String): IntRange {
        val start = drawn.indexOf(part)
        check(start >= 0) { "$part 가 말풍선에 없다" }
        return start until start + part.length
    }

    /** 고른 글자에 `[글](주소)` 링크가 걸치면 실제 주소를 담는다. 기준선: 보이는 글자(같은 구간의 drawn)는 꼬리표 그대로다 — 결과가 다르다. */
    @Test
    fun selectedLinksCopyTheirRealAddress() {
        val pieces = ChatMarkdownPieces.pieces("**굵게** [자료](https://a.example/doc) 끝")
        val drawn = ChatMarkdownPieces.drawn(pieces)
        assertEquals("굵게 자료 (a.example) 끝", drawn)
        val cases = listOf(
            "굵게 자료 (a.example) 끝" to "굵게 자료 (https://a.example/doc) 끝", // 통째로
            "자료" to "자료 (https://a.example/doc)", // 글만
            "자" to "자 (https://a.example/doc)", // 글 일부
            "(a.example)" to "(https://a.example/doc)", // 꼬리표만
            "굵게 자" to "굵게 자 (https://a.example/doc)",
            "굵게" to "굵게", // 링크 밖
            " 끝" to " 끝",
        )
        for ((part, expected) in cases) {
            val range = select(drawn, part)
            assertEquals(expected, ChatMarkdownCopy.text(pieces, listOf(range)), "${part} 를 고른 복사")
        }
        // 기준선: 보이는 글자 그대로라면 꼬리표가 들어가고 주소가 빠진다.
        assertEquals("굵게 자료 (a.example) 끝", drawn.substring(select(drawn, "굵게 자료 (a.example) 끝")))

        // 글이 호스트와 같아 꼬리표가 없는 링크도 주소가 다르면 주소를 담는다. 글이 곧 주소면(맨 주소 · 같은 주소) 보이는 그대로다.
        for ((body, expected) in listOf(
            "[a.example](https://a.example/doc) 봐" to "a.example (https://a.example/doc) 봐",
            "https://a.example/doc 봐" to "https://a.example/doc 봐",
            "[https://a.example/](https://a.example) 봐" to "https://a.example/ 봐",
            "[가](https://a.example)와 [나](https://b.example)" to "가 (https://a.example)와 나 (https://b.example)",
            "**[굵은 링크](https://a.example/x)**" to "굵은 링크 (https://a.example/x)",
            "줄 하나\n[둘](https://b.example/y)" to "줄 하나\n둘 (https://b.example/y)",
        )) {
            val other = ChatMarkdownPieces.pieces(body)
            val all = 0 until ChatMarkdownPieces.drawn(other).length
            assertEquals(expected, ChatMarkdownCopy.text(other, listOf(all)), "${body} 전체 복사")
        }
    }

    /** 여러 구간은 줄바꿈으로 잇고, 빈 · 글자 밖 구간은 버린다. 남는 것이 없으면 null(= 고른 것 없음 → [복사]는 원문). */
    @Test
    fun rangesAndMenuFallBackToRaw() {
        val raw = "**굵게** [자료](https://a.example/doc) 끝"
        val pieces = ChatMarkdownPieces.pieces(raw)
        val drawn = ChatMarkdownPieces.drawn(pieces)
        assertEquals("굵게\n끝", ChatMarkdownCopy.text(pieces, listOf(select(drawn, "굵게"), select(drawn, "끝"))))
        assertNull(ChatMarkdownCopy.text(pieces, emptyList()))
        assertNull(ChatMarkdownCopy.text(pieces, listOf(IntRange.EMPTY, 0 until drawn.length + 1)))
        assertEquals(raw, ChatMarkdownCopy.menuText(null, raw), "고른 것 없는 [복사]가 원문이 아니다")
        assertEquals("굵게", ChatMarkdownCopy.menuText("굵게", raw))
    }
}
