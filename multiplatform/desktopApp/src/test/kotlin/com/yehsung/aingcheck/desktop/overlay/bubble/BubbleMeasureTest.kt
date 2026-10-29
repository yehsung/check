// 원본: CheckOverlayWindow.swift :2386-2420 Metrics · :2565 measuredForm · CheckOverlayTests 의 말풍선 inline/도착 시나리오
//       overlay.md §5 b2 BubbleMeasureTest · W-3 #8(번들 Pretendard 로 잰 경계를 Kotlin 시험으로 잠근다 — 맥 SF Rounded 와 달라도 수용)
package com.yehsung.aingcheck.desktop.overlay.bubble

import com.yehsung.aingcheck.desktop.overlay.engine.BubbleForm
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleMetrics
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayBubble
import androidx.compose.ui.text.font.FontWeight
import com.yehsung.aingcheck.ui.fonts.Pretendard
import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.ExperimentalResourceApi
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BubbleMeasureTest {
    private val m = PretendardBubbleMeasure.bundled

    @Test
    fun measuresWithTheBundledSemiBoldAtTenPoints() {
        assertEquals(0.0, m.width(""))
        assertEquals(0, m.lineCount("", BubbleMetrics.TEXT_WIDTH))
        // Pretendard 한글 낱자는 거의 전각 — 10pt 에서 한 자 폭이 8~11 DIP 안. (시스템 글꼴로 새면 폭이 달라져 아래 잠금이 깨진다.)
        val ga = m.width("가")
        assertTrue(ga in 8.0..11.0, "가 폭=$ga")
        assertEquals(LOCKED_GA_WIDTH_X100, Math.round(ga * 100).toInt(), "번들 Pretendard SemiBold 10pt '가' 폭(×100) 잠금")
        assertTrue(m.width("가가") > ga)
        assertEquals(1, m.lineCount("고생했어요", BubbleMetrics.TEXT_WIDTH))
        assertTrue(m.lineHeight in 10.0..16.0, "줄 높이=${m.lineHeight}")
    }

    /**
     * 재는 글꼴이 정말 번들 SemiBold 인지 — 한글 낱자 폭은 Pretendard 굵기마다 같아서(위 '가' 잠금만으로는) Regular 로 바뀌거나
     * OS 글꼴로 새도 못 본다. 라틴 폭은 굵기마다 다르다.
     */
    @OptIn(ExperimentalResourceApi::class)
    @Test
    fun theBundledSemiBoldFaceIsWhatGetsMeasured() {
        val regular = PretendardBubbleMeasure.fromBytes(runBlocking { Res.readBytes(Pretendard.faces.first { it.weight == FontWeight.Normal }.path) })
        val sample = "Aing check 2026"
        assertTrue(m.width(sample) > regular.width(sample) + 0.3, "SemiBold ${m.width(sample)} vs Regular ${regular.width(sample)}")
        assertEquals(LOCKED_LATIN_WIDTH_X100, Math.round(m.width(sample) * 100).toInt(), "'$sample' 폭(×100) 잠금")
    }

    @Test
    fun shortThanksStayInlineAndTwoHundredCharactersBecomeArrival() {
        assertEquals(BubbleForm.Form.Inline("민수님: 고생했어요"), BubbleForm.messageBubble("민수", "고생했어요", m))
        assertEquals(BubbleForm.Form.Inline("민수님: 오늘 고생했어요"), BubbleForm.messageBubble("민수", "오늘 고생했어요", m))
        val long = "가나다라마바사아자차".repeat(20)
        assertEquals(200, long.length)
        assertEquals(BubbleForm.Form.Arrival("✉️ 민수님 메시지 도착!"), BubbleForm.messageBubble("민수", long, m))
    }

    /** W-3 #8 — 이 측정기로 inline 이 되는 가장 긴 "가…가" 본문(띄어쓰기 없음 = 낱말 하나 규칙 ③). 글꼴·패딩·폭이 바뀌면 빨개진다. */
    @Test
    fun inlineBoundaryIsLockedForTheBundledFont() {
        fun inline(n: Int) = BubbleForm.messageBubble("민수", "가".repeat(n), m) is BubbleForm.Form.Inline
        val longest = (1..40).last { inline(it) }
        // 띄어 쓴 한글은 두 줄까지 — 낱말 하나 경계보다 길게 들어간다.
        fun spaced(n: Int) = BubbleForm.messageBubble("민수", List(n) { "가나" }.joinToString(" "), m) is BubbleForm.Form.Inline
        val longestSpaced = (1..20).last { spaced(it) }
        assertEquals(
            listOf(LOCKED_LONGEST_SINGLE_WORD, LOCKED_LONGEST_SPACED_PAIRS), listOf(longest, longestSpaced),
            "inline 경계 [낱말 하나 '가'×n, 띄어 쓴 '가나'×n]",
        )
    }

    @Test
    fun painterLayoutKeepsTheCapsuleWithinMetrics() {
        val inline = BubblePainter.layout(OverlayBubble("민수님: 고생했어요", BubbleKind.Normal, 0.0, 6.0), m)
        assertTrue(inline.capsule.width <= BubbleMetrics.CAPSULE_MAX_WIDTH, "${inline.capsule}")
        assertEquals(BubbleMetrics.INSET_X, inline.capsule.left)
        assertEquals(BubbleMetrics.INSET_Y, inline.capsule.top)
        assertEquals(false, inline.arrow)
        val twoLines = BubblePainter.layout(OverlayBubble("가나 ".repeat(12).trim(), BubbleKind.Normal, 0.0, 6.0), m)
        assertTrue(twoLines.textWidth <= BubbleMetrics.TEXT_WIDTH && twoLines.textWidth > BubbleMetrics.TEXT_WIDTH - 12, "두 줄 글자 폭 ${twoLines.textWidth}")
        assertTrue(twoLines.textHeight > inline.textHeight * 1.5, "두 줄 높이 ${twoLines.textHeight} vs ${inline.textHeight}")
        val invite = BubblePainter.layout(OverlayBubble("가나 ".repeat(12).trim(), BubbleKind.Arrival(null), 0.0, 6.0), m)
        // 누를 수 있는 말풍선은 화살표 몫만큼 늘려 글자 폭 94 를 지킨다.
        assertEquals(twoLines.capsule.width + BubbleStyle.ARROW_EXTRA_WIDTH, invite.capsule.width, 1e-9)
        assertEquals(twoLines.textWidth, invite.textWidth, 1e-9)
    }

    companion object {
        const val LOCKED_GA_WIDTH_X100 = 864
        const val LOCKED_LONGEST_SINGLE_WORD = 10
        const val LOCKED_LONGEST_SPACED_PAIRS = 7
        const val LOCKED_LATIN_WIDTH_X100 = 7878
    }
}
