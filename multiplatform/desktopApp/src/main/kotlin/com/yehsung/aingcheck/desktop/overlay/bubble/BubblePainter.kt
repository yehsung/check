// 원본: CheckOverlayWindow.swift :2386-2420 Metrics · CheckGreetingBubble/CheckMessageArrivalBubble 그리기(같은 파일 ~:2700 —
//       .padding(8/5) · RoundedRectangle(10).fill(white 0.92) · stroke(black 0.10, 0.5) · 글자 black 0.85 · 화살표 7pt bold black 0.45 ·
//       .shadow(black 0.25, r3, y1)) · 설계 D §9-1(레이어드 창은 알파>0 픽셀이 클릭을 먹는다 → 그림자를 옮기지 않는다)
//
// 판정(어떤 문구·도착 꼴)은 b1 BubbleForm, 여기는 받은 문구를 [BubbleMetrics] 숫자 그대로 그린다(I-4).
// 색은 테마 말풍선 토큰(AingColors.overlayBubble* — 공용 패치 6)에서만 — 이 폴더에 색 리터럴 0(OverlayColorLiteralTest, D5).
// 맥 말풍선은 어둠 모드에서도 흰 캡슐이라 토큰도 두 모드가 같은 값이다(여기는 Light 를 읽는다).
package com.yehsung.aingcheck.desktop.overlay.bubble

import androidx.compose.ui.graphics.toArgb
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleMetrics
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayBubble
import com.yehsung.aingcheck.ui.theme.AingColors
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.FilterBlurMode
import org.jetbrains.skia.MaskFilter
import org.jetbrains.skia.Paint
import org.jetbrains.skia.PaintMode
import org.jetbrains.skia.RRect

object BubbleStyle {
    const val CORNER_RADIUS = 10.0
    const val STROKE_WIDTH = 0.5
    const val ARROW_FONT_PT = 7.0
    const val ARROW = "›"
    /** 누를 수 있는 말풍선(도착·대결)은 화살표 몫만큼 캡슐을 **늘려** 글자 폭 94 를 지킨다(맥 CheckMessageArrivalBubble.capsuleMaxWidth). */
    const val ARROW_EXTRA_WIDTH = 8.0

    /**
     * 그림자 불투명도(0..1, 맥 0.25). **Windows 는 0** — 레이어드 창은 알파>0 픽셀이 클릭을 받으므로 맥 그림자(0.25·r3·y1)를 옮기면
     * 캡슐 둘레 몇 픽셀이 뒤 창 클릭을 먹는다(D §9-1). 음성 대조는 이 값을 1 로 바꿔 OverlayCompositorTest 가 빨개지는 것을 본다.
     * (0..255 의 1 은 블러 뒤 8비트 반올림으로 0 이 되어 클릭도 안 먹는다 — 시험이 초록인 게 맞다. 그래서 불투명도 단위로 둔다.)
     */
    const val SHADOW_ALPHA = 0f
    const val SHADOW_BLUR_SIGMA = 1.5
    const val SHADOW_OFFSET_Y = 1.0

    private val tokens get() = AingColors.Light
    val fill: Int get() = tokens.overlayBubbleFill.toArgb()
    val stroke: Int get() = tokens.overlayBubbleStroke.toArgb()
    val text: Int get() = tokens.overlayBubbleText.toArgb()
    val arrow: Int get() = tokens.overlayBubbleArrival.toArgb()
    val shadow: Int get() = tokens.label.copy(alpha = SHADOW_ALPHA).toArgb()

    fun clickable(kind: BubbleKind): Boolean = kind is BubbleKind.Arrival || kind is BubbleKind.Invite
}

/** 창 왼쪽 위 기준 DIP 사각형. */
data class DipRect(val left: Double, val top: Double, val width: Double, val height: Double) {
    val right: Double get() = left + width
    val bottom: Double get() = top + height
}

/** 말풍선 한 장의 자리(DIP). 재기·그리기·히트가 이 한 값을 본다. */
data class BubbleLayout(val capsule: DipRect, val textWidth: Double, val textHeight: Double, val arrow: Boolean)

object BubblePainter {
    fun layout(bubble: OverlayBubble, m: PretendardBubbleMeasure): BubbleLayout {
        val p = m.paragraph(bubble.text, BubbleMetrics.TEXT_WIDTH, maxLines = BubbleMetrics.LINE_LIMIT)
        val textW = minOf(p.longestLine.toDouble(), BubbleMetrics.TEXT_WIDTH)
        val textH = p.height.toDouble()
        val arrow = BubbleStyle.clickable(bubble.kind)
        val w = textW + BubbleMetrics.HORIZONTAL_PADDING * 2 + if (arrow) BubbleStyle.ARROW_EXTRA_WIDTH else 0.0
        val h = textH + BubbleMetrics.VERTICAL_PADDING * 2
        return BubbleLayout(DipRect(BubbleMetrics.INSET_X, BubbleMetrics.INSET_Y, w, h), textW, textH, arrow)
    }

    /** [canvas](픽셀) 에 배율 [scale] 로 그린다. 돌려주는 값은 DIP 자리(히트·시험용). */
    fun paint(canvas: Canvas, bubble: OverlayBubble, m: PretendardBubbleMeasure, scale: Double): BubbleLayout {
        val l = layout(bubble, m)
        val c = l.capsule
        val rr = RRect.makeXYWH(c.left.toFloat(), c.top.toFloat(), c.width.toFloat(), c.height.toFloat(), BubbleStyle.CORNER_RADIUS.toFloat())
        canvas.save()
        canvas.scale(scale.toFloat(), scale.toFloat())
        try {
            if (BubbleStyle.SHADOW_ALPHA > 0f) {
                val shadowRect = RRect.makeXYWH(
                    c.left.toFloat(), (c.top + BubbleStyle.SHADOW_OFFSET_Y).toFloat(), c.width.toFloat(), c.height.toFloat(),
                    BubbleStyle.CORNER_RADIUS.toFloat(),
                )
                Paint().let { sp ->
                    sp.color = BubbleStyle.shadow
                    sp.isAntiAlias = true
                    sp.maskFilter = MaskFilter.makeBlur(FilterBlurMode.NORMAL, BubbleStyle.SHADOW_BLUR_SIGMA.toFloat())
                    canvas.drawRRect(shadowRect, sp)
                }
            }
            Paint().let { fp ->
                fp.color = BubbleStyle.fill
                fp.isAntiAlias = true
                canvas.drawRRect(rr, fp)
            }
            Paint().let { st ->
                st.color = BubbleStyle.stroke
                st.isAntiAlias = true
                st.mode = PaintMode.STROKE
                st.strokeWidth = BubbleStyle.STROKE_WIDTH.toFloat()
                // 획은 경계 안쪽으로 반 폭 들여 그린다 — 캡슐 사각형 밖으로 알파가 새지 않게.
                val inset = (BubbleStyle.STROKE_WIDTH / 2).toFloat()
                canvas.drawRRect(
                    RRect.makeXYWH(
                        c.left.toFloat() + inset, c.top.toFloat() + inset, c.width.toFloat() - 2 * inset, c.height.toFloat() - 2 * inset,
                        BubbleStyle.CORNER_RADIUS.toFloat() - inset,
                    ),
                    st,
                )
            }
            m.paragraph(bubble.text, BubbleMetrics.TEXT_WIDTH, color = BubbleStyle.text, maxLines = BubbleMetrics.LINE_LIMIT)
                .paint(canvas, (c.left + BubbleMetrics.HORIZONTAL_PADDING).toFloat(), (c.top + BubbleMetrics.VERTICAL_PADDING).toFloat())
            if (l.arrow) {
                val a = m.paragraph(BubbleStyle.ARROW, 100.0, color = BubbleStyle.arrow, sizePt = BubbleStyle.ARROW_FONT_PT)
                val ax = c.right - BubbleMetrics.HORIZONTAL_PADDING - a.maxIntrinsicWidth
                val ay = c.top + (c.height - a.height) / 2
                a.paint(canvas, ax.toFloat(), ay.toFloat())
            }
        } finally {
            canvas.restore()
        }
        return l
    }
}
