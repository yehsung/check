// 원본: wt-phone-1017 2ad01732 Sources/CheckMobileKit/Messages/MessagesBubbleMarkdown.swift(폰 말풍선 서식 — 글꼴 · 색 · 여는 문 · 링크 동작) ·
//       99bd480d MessagesBubbleTextLayout.swift(링크 누름 판정 — 링크 구간 글자 상자 + 손가락 오차) · Sources/check/ChatMarkdownText.swift:236-246 @ 12624739(색 규칙).
// 판 7 Android 이식.
//
// 무엇을 그리는가(글자 · 제목 단계 · 굵게 · 링크 · 호스트 꼬리표)는 코어 ChatMarkdownPieces 한 곳이 정한다(맥 · 아이폰과 한 벌).
// 여기는 그 조각에 **Android 글꼴과 색**을 입혀 Compose AnnotatedString 한 장으로 옮기고, 링크를 여는 문 · TalkBack 동작 · 누름 판정을 둔다.
//
// ## 색 — 모든 글자 4.5:1(아이폰 MessagesBubbleMarkdown.Palette 와 같은 규칙)
//  · 받은 말풍선(bubbleIn): 본문 label · 링크 accent(밑줄) · 꼬리표 label2.
//  · 내 말풍선(accentFill): 본문 · 링크 · 꼬리표 모두 onAccentFill(흰색) — 링크는 밑줄로 가른다. 맥은 꼬리표를 흰색 75% 로 흐리지만
//    다크 accentFill 위 흰색은 꽉 찬 흰색이 겨우 4.5:1 이라 조금만 흐려도 무너진다(아이폰 1.0.17 결정 그대로).
//
// ## 제목 크기 — 글자 크기 설정을 따르되 상한
// 본문은 예전 그대로 titleSmall(iOS callout 16)이고, 제목은 아이폰과 같은 세 스타일(iOS title2 · title3 · headline → headlineSmall 22 · titleLarge 20 ·
// titleMedium 17)을 굵게 쓴다. 제목은 [HEADING_FONT_SCALE_CAP] 배를 넘어 자라지 않고, 본문보다 작아지지 않는다 — 큰 글자 설정에서 `#` 한 줄이
// 말풍선 폭을 몇 글자로 쪼개지 않게(아이폰: AX1 에서 멈춤 · 본문보다 작지 않음).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.ChatMarkdown
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPiece
import com.yehsung.aingcheck.core.rules.text.ChatMarkdownPieces
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme

// 고른 글 복사의 모양은 대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기"로 정해졌다 — 글 말풍선 자체가 고르기 칸이다(ChatBubbleSelection.kt).
// 판 7 초안의 메뉴 항목 → 시트 방식과 그 깃발은 걷어 냈다.

/** 말풍선 서식 문구(아이폰 원문). */
object ChatBubbleText {
    /** TalkBack 링크 동작 이름의 머리 — 뒤에 화면에 보이는 링크 글 + 꼬리표가 붙는다("링크 열기: 자료 (a.example)"). 아이폰 1.0.17 원문. */
    const val openLinkActionPrefix = "링크 열기: "
}

object ChatBubbleMarkdown {
    /** 링크 글자의 주소(값: absoluteString). 누름 판정 · TalkBack 동작이 이 값을 연다([follow] 를 지나서). */
    const val LINK_TAG = "aingcheck.chat.link"

    /** 제목 글꼴이 글자 크기 설정을 따라 자라는 상한(기본 크기의 배수). 아이폰 AX1 상한(title2 22 → 34pt ≈ 1.5배)의 Android 짝. */
    const val HEADING_FONT_SCALE_CAP = 1.5f

    /** 손가락 오차(아이폰 엔진 link(at:) 의 상자 + 4pt). */
    val LINK_TOUCH_SLOP = 4.dp

    /** 제목 한 단계의 글자 크기. */
    data class Heading(val fontSize: TextUnit)

    /** 말풍선 글꼴 표: 본문 스타일 + 제목 단계 1~3. */
    data class Style(val body: TextStyle, val headings: List<Heading>) {
        init {
            require(headings.size == 3) { "제목 단계는 셋이다" }
        }

        fun heading(step: Int): Heading = headings[(step - 1).coerceIn(0, 2)]

        /**
         * 이 조각들을 그릴 글자 스타일. 제목 줄이 있으면 **고정 행간을 푼다**(줄마다 그 줄 글꼴의 높이 — 큰 제목 줄은 높고 본문 줄은 본문 높이).
         * 고정 행간(본문 21sp)을 두면 22sp 제목 글자가 줄 밖으로 넘친다. 문단 스타일로 제목 줄만 행간을 바꾸면 Compose 는 문단 끝 줄바꿈마다 빈 줄을
         * 하나 더 그린다(2026-11-03 Robolectric 실측 — 제목 아래 빈 줄) — 그래서 문단을 나누지 않는다. 제목이 없는 글은 예전 행간 그대로다.
         */
        fun textStyle(pieces: List<ChatMarkdownPiece>): TextStyle =
            if (pieces.any { it.headingStep > 0 }) body.copy(lineHeight = TextUnit.Unspecified) else body
    }

    /** 말풍선 바탕별 글자 색. */
    data class Colors(val text: Color, val link: Color, val disclosure: Color)

    fun colors(isMine: Boolean, palette: AingColors): Colors =
        if (isMine) Colors(palette.onAccentFill, palette.onAccentFill, palette.onAccentFill)
        else Colors(palette.label, palette.accent, palette.label2)

    /**
     * 제목 단계의 글자 크기를 정한다(밀도 · 글자 크기 설정이 든 [density] 로). 스타일 크기를 설정대로 키우되 [HEADING_FONT_SCALE_CAP] 배에서 멈추고,
     * 본문(설정대로 자란 크기)보다 작아지지 않는다.
     */
    fun style(body: TextStyle, headingStyles: List<TextStyle>, density: Density): Style {
        val bodyDp = with(density) { body.fontSize.toDp() }
        val headings = headingStyles.map { style ->
            val scaled = with(density) { style.fontSize.toDp() }
            val cap = (style.fontSize.value * HEADING_FONT_SCALE_CAP).dp
            val chosen = maxOf(minOf(scaled, cap), bodyDp)
            Heading(fontSize = with(density) { chosen.toSp() })
        }
        return Style(body, headings)
    }

    /**
     * 말풍선에 보일 글([shown] — **이모티콘 폴백을 이미 지난** 본문, AingStickerText.preview) → AnnotatedString.
     *  · 평문 조각에는 꾸밈을 하나도 달지 않는다 — 기호 없는 메시지는 예전 Text(String) 과 같은 글자로 그려진다(바탕 글꼴 · 색은 Text 가 정한다).
     *  · 제목 줄: 단계 글꼴(굵게 — 행간은 [Style.textStyle] 이 푼다). `**굵게**`: 굵게. 링크: [LINK_TAG] 주석(주소) + 링크 색 + 밑줄. 꼬리표 " (호스트)": 꼬리표 색 · 보통 굵기.
     */
    fun annotated(shown: String, colors: Colors, style: Style): AnnotatedString = annotated(ChatMarkdownPieces.pieces(shown), colors, style)

    fun annotated(pieces: List<ChatMarkdownPiece>, colors: Colors, style: Style): AnnotatedString = buildAnnotatedString {
        for (piece in pieces) {
            val start = length
            append(piece.text)
            val end = length
            when (piece.kind) {
                ChatMarkdownPiece.Kind.lineBreak -> Unit
                ChatMarkdownPiece.Kind.span -> {
                    val step = piece.headingStep
                    val size = if (step > 0) style.heading(step).fontSize else TextUnit.Unspecified
                    val weight = if (piece.isBold) FontWeight.Bold else null
                    val link = piece.link
                    if (link != null) {
                        addStyle(SpanStyle(color = colors.link, fontSize = size, fontWeight = weight, textDecoration = TextDecoration.Underline), start, end)
                        addStringAnnotation(LINK_TAG, link.absoluteString, start, end)
                    } else if (step > 0 || weight != null) {
                        addStyle(SpanStyle(fontSize = size, fontWeight = weight), start, end)
                    }
                }
                ChatMarkdownPiece.Kind.disclosure -> {
                    val step = piece.headingStep
                    addStyle(
                        SpanStyle(color = colors.disclosure, fontSize = if (step > 0) style.heading(step).fontSize else TextUnit.Unspecified, fontWeight = FontWeight.Normal),
                        start, end,
                    )
                }
            }
        }
    }

    // ---------------------------------------------------------------- 링크 — 여는 문 · TalkBack 동작 · 누름 판정

    /**
     * 링크를 여는 **한 문**(손가락 누름 · TalkBack 동작). **여는 자리에서 [ChatMarkdown.isOpenable] 을 한 번 더 본다** — 해석이 이미 http·https 만 링크로
     * 만들지만, 이 문을 지나는 값은 글자 주석에서 온 것이라 해석 밖의 길이 생겨도 여기서 막힌다(맥 followLink · 아이폰 follow 와 같은 두 겹).
     * `javascript:` · `intent:` · `file:` · `content:` · 사용자 정보 · 호스트 `%` 주소는 절대 열지 않는다. 열었으면 true.
     */
    fun follow(address: String, open: (String) -> Unit): Boolean {
        val link = ChatMarkdown.openableLink(address) ?: return false
        open(link.absoluteString)
        return true
    }

    /** TalkBack 동작 하나(말풍선 줄은 요소 하나라 링크 글자에 닿을 수 없다 — 링크마다 동작을 단다). */
    data class LinkAction(val address: String, val title: String)

    /** 말풍선 글의 링크들 → TalkBack 동작(보이는 차례 · 같은 이름 · 같은 주소는 한 번). 이름 = "링크 열기: " + 링크 글 + 꼬리표(아이폰 linkActions 그대로). */
    fun linkActions(shown: String): List<LinkAction> {
        val pieces = ChatMarkdownPieces.pieces(shown)
        val out = ArrayList<LinkAction>()
        var index = 0
        while (index < pieces.size) {
            val url = pieces[index].link
            if (pieces[index].kind != ChatMarkdownPiece.Kind.span || url == null) {
                index++
                continue
            }
            var end = index
            val label = StringBuilder()
            while (end < pieces.size && pieces[end].kind == ChatMarkdownPiece.Kind.span && pieces[end].link == url) {
                label.append(pieces[end].text)
                end++
            }
            if (end < pieces.size && pieces[end].kind == ChatMarkdownPiece.Kind.disclosure) label.append(pieces[end].text)
            val action = LinkAction(url.absoluteString, ChatBubbleText.openLinkActionPrefix + TextScalars.trimmingWhitespaces(label.toString()))
            if (action !in out) out += action
            index = end
        }
        return out
    }

    /**
     * 글자 배치 [layout] 위 [position](글자 칸 좌표)에 있는 링크의 주소. 링크 구간의 **글자 상자마다** [slop] 만큼 넓혀 손가락이 그 안이면 그 링크다
     * (줄 끝 너머 · 꼬리표 · 링크 아닌 글자는 null — 아이폰 99bd480d 의 "링크 구간의 줄 조각별 상자 + 손가락 오차").
     */
    fun linkAt(text: AnnotatedString, layout: TextLayoutResult, position: Offset, slop: Float): String? {
        for (link in text.getStringAnnotations(LINK_TAG, 0, text.length)) {
            for (offset in link.start until minOf(link.end, layout.layoutInput.text.length)) {
                val box = layout.getBoundingBox(offset)
                if (position.x >= box.left - slop && position.x <= box.right + slop && position.y >= box.top - slop && position.y <= box.bottom + slop) {
                    return link.item
                }
            }
        }
        return null
    }
}

/** 지금 테마 · 글자 크기 설정의 말풍선 글꼴 표(본문 = titleSmall 보통 굵기 · 어절 줄바꿈 / 제목 = headlineSmall · titleLarge · titleMedium). */
@Composable
internal fun rememberChatBubbleStyle(): ChatBubbleMarkdown.Style {
    val typography = MaterialTheme.typography
    val density = LocalDensity.current
    return remember(typography, density) {
        ChatBubbleMarkdown.style(
            body = typography.titleSmall.copy(fontWeight = FontWeight.Normal, lineBreak = BubbleLineBreak),
            headingStyles = listOf(typography.headlineSmall, typography.titleLarge, typography.titleMedium),
            density = density,
        )
    }
}

/** 말풍선 바탕별 색(지금 테마). */
@Composable
internal fun chatBubbleColors(isMine: Boolean): ChatBubbleMarkdown.Colors = ChatBubbleMarkdown.colors(isMine, AingTheme.colors)
