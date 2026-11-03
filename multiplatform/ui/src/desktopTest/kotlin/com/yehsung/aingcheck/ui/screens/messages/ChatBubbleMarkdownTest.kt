// 원본: wt-phone-1017 2ad01732 Tests/CheckMobileKitTests/V1017ChatMarkdownMobileTests.swift(속성 글 · 색 · 제목 글꼴 상한 · 링크 동작 이름) ·
//       Tests/checkTests/ChatMarkdownTests.swift:746-766 @ 12624739(링크 글자는 링크 속성 · 내 말풍선 링크는 흰색 + 밑줄).
// 판 7 Android: 말풍선 AnnotatedString 의 꾸밈을 **값으로** 잰다(그림은 Android 호스트 스냅숏이 잰다). 기준선: 평문은 꾸밈이 하나도 없다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPieces
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ChatBubbleMarkdownTest {
    private val colors = ChatBubbleMarkdown.Colors(text = Color(0xFF111111), link = Color(0xFF0066FF), disclosure = Color(0xFF888888))
    private val body = TextStyle(fontSize = 16.sp, lineHeight = 21.sp)
    private val headings = listOf(TextStyle(fontSize = 22.sp, lineHeight = 28.sp), TextStyle(fontSize = 20.sp, lineHeight = 25.sp), TextStyle(fontSize = 17.sp, lineHeight = 22.sp))
    private val style = ChatBubbleMarkdown.style(body, headings, Density(2f, 1f))

    @Test
    fun plainBodiesCarryNoDecoration() {
        for (text in listOf("화이팅", "*기울임* `코드` ~~취소~~", "- 항목\n> 인용", "2 * 3 = 6", "[글](javascript:alert(1))")) {
            val annotated = ChatBubbleMarkdown.annotated(text, colors, style)
            assertEquals(text, annotated.text)
            assertTrue(annotated.spanStyles.isEmpty(), "\"$text\" 에 꾸밈이 붙었다: ${annotated.spanStyles}")
            assertTrue(annotated.paragraphStyles.isEmpty())
            assertTrue(annotated.getStringAnnotations(ChatBubbleMarkdown.LINK_TAG, 0, annotated.length).isEmpty())
            assertEquals(body, style.textStyle(ChatMarkdownPieces.pieces(text)), "제목 없는 글의 행간이 바뀌었다")
        }
    }

    @Test
    fun headingsBoldAndLinksAreDecorated() {
        val annotated = ChatBubbleMarkdown.annotated("## 제목\n**굵게** [자료](https://a.example/doc) 끝", colors, style)
        assertEquals("제목\n굵게 자료 (a.example) 끝", annotated.text)
        fun styleAt(part: String) = annotated.spanStyles.filter { annotated.text.indexOf(part) in it.start until it.end }.map { it.item }
        val heading = styleAt("제목").single()
        assertEquals(20.sp, heading.fontSize, "## 는 titleLarge(20)")
        assertEquals(FontWeight.Bold, heading.fontWeight)
        assertEquals(FontWeight.Bold, styleAt("굵게").single().fontWeight)
        val link = styleAt("자료").single()
        assertEquals(colors.link, link.color)
        assertEquals(TextDecoration.Underline, link.textDecoration)
        val tag = styleAt("(a.example)").single()
        assertEquals(colors.disclosure, tag.color)
        assertEquals(null, tag.textDecoration, "꼬리표에 밑줄 — 누르는 자리처럼 보인다")
        // 링크 주석은 글 조각에만(꼬리표는 누르는 자리가 아니다).
        val links = annotated.getStringAnnotations(ChatBubbleMarkdown.LINK_TAG, 0, annotated.length)
        assertEquals(listOf("https://a.example/doc"), links.map { it.item })
        assertEquals("자료", annotated.text.substring(links.single().start, links.single().end))
        // 제목이 있는 글은 고정 행간을 푼다(큰 글자가 줄 밖으로 넘치지 않게).
        assertEquals(TextUnit.Unspecified, style.textStyle(ChatMarkdownPieces.pieces("## 제목\n본문")).lineHeight)
    }

    @Test
    fun myBubbleUsesOnAccentForLinksAndTags() {
        val palette = com.yehsung.aingcheck.ui.theme.AingColors.of(dark = false)
        val mine = ChatBubbleMarkdown.colors(isMine = true, palette)
        assertEquals(ChatBubbleMarkdown.Colors(palette.onAccentFill, palette.onAccentFill, palette.onAccentFill), mine)
        val received = ChatBubbleMarkdown.colors(isMine = false, palette)
        assertEquals(ChatBubbleMarkdown.Colors(palette.label, palette.accent, palette.label2), received)
        assertTrue(mine.link != palette.accent, "내 말풍선 링크가 바탕(강조색)에 묻힌다")
    }

    /** 제목 크기: 단계별로 크고(22 · 20 · 17) · 글자 크기 설정을 따르되 1.5배에서 멈추고 · 본문보다 작아지지 않는다. */
    @Test
    fun headingSizesFollowFontScaleWithACap() {
        fun sizes(fontScale: Float) = ChatBubbleMarkdown.style(body, headings, Density(2f, fontScale)).headings.map { it.fontSize.value }
        assertEquals(listOf(22f, 20f, 17f), sizes(1f))
        // 1.3배: 그대로 자란다(상한 아래) — sp 값은 같다(글자 크기 설정이 곱한다).
        assertEquals(listOf(22f, 20f, 17f), sizes(1.3f).map { (it * 100).toInt() / 100f })
        // 2배: 제목은 1.5배에서 멈춘다(22 → 33dp = 16.5sp) · 20 · 17 은 상한(30 · 25.5dp)이 본문(16·2 = 32dp)보다 작아 본문 크기(16sp)다.
        assertEquals(listOf(16.5f, 16f, 16f), sizes(2f))
        // 1.6배: 22·1.5 = 33dp(> 본문 25.6dp) → 33/1.6 = 20.625sp · 20·1.5 = 30dp → 18.75sp · 17·1.5 = 25.5dp < 본문 25.6dp → 본문 16sp.
        val at16 = sizes(1.6f)
        assertEquals(20.625f, at16[0], 0.01f)
        assertEquals(18.75f, at16[1], 0.01f)
        assertEquals(16f, at16[2], 0.01f)
    }

    @Test
    fun talkBackLinkActionsNameTheLabelAndTheRealHost() {
        assertEquals(
            listOf(
                ChatBubbleMarkdown.LinkAction("https://a.example/doc", "링크 열기: 자료 (a.example)"),
                ChatBubbleMarkdown.LinkAction("https://b.example/x", "링크 열기: https://b.example/x"),
            ),
            ChatBubbleMarkdown.linkActions("[자료](https://a.example/doc) 와 https://b.example/x 그리고 [자료](https://a.example/doc)"),
        )
        assertTrue(ChatBubbleMarkdown.linkActions("링크 없음 [글](javascript:x)").isEmpty())
        assertEquals(listOf("https://a.example/x%7Cy"), ChatBubbleMarkdown.linkActions("[a](https://a.example/x|y)").map { it.address })
    }

    @Test
    fun theDoorOpensOnlyHttpAndHttps() {
        val opened = ArrayList<String>()
        for (address in listOf("javascript:alert(1)", "intent://x#Intent;end", "file:///a", "content://a/b", "https://u@evil.com", "https://%61.com", "")) {
            assertTrue(!ChatBubbleMarkdown.follow(address) { opened += it }, address)
        }
        assertTrue(opened.isEmpty())
        assertTrue(ChatBubbleMarkdown.follow("HTTPS://A.EXAMPLE/x") { opened += it })
        assertEquals(listOf("HTTPS://A.EXAMPLE/x"), opened)
    }
}
