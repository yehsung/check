// 원본: CheckOverlayWindow.swift :2386-2420 OverlayMessageBubble.Metrics(캡슐 110 · 패딩 8/5 · 2줄 · font · lineHeight)
//       overlay.md §4 I-4 "판정 한 벌(b1), 재기는 b2" · W-3 #8(번들 Pretendard 로 잰다 — 맥 SF Rounded 와 경계가 다를 수 있음, 수용)
//
// 재기와 그리기가 **같은 문단 엔진(Skia Paragraph)·같은 글꼴 묶음**을 쓴다 — 두 벌이면 "판정은 inline 인데 그림은 잘린다"가
// 조용히 생긴다(맥 Metrics 주석과 같은 이유). 글꼴은 ui 모듈이 싣는 Pretendard SemiBold(번들 바이트)이고, 그 글꼴에 없는
// 글자(✉️ 등 그림 글자)만 OS 기본 글꼴로 넘긴다.
package com.yehsung.aingcheck.desktop.overlay.bubble

import com.yehsung.aingcheck.desktop.overlay.engine.BubbleMetrics
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleTextMeasure
import com.yehsung.aingcheck.ui.fonts.Pretendard
import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.skia.Data
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.paragraph.FontCollection
import org.jetbrains.skia.paragraph.Paragraph
import org.jetbrains.skia.paragraph.ParagraphBuilder
import org.jetbrains.skia.paragraph.ParagraphStyle
import org.jetbrains.skia.paragraph.TextStyle
import org.jetbrains.skia.paragraph.TypefaceFontProvider
import androidx.compose.ui.text.font.FontWeight

/** I-4 구현 — Pretendard SemiBold [BubbleMetrics.FONT_SIZE_PT] 로 잰다. 단위는 DIP(= 맥 pt). */
class PretendardBubbleMeasure private constructor(private val fonts: FontCollection) : BubbleTextMeasure {

    /** [text] 를 [maxWidth] 폭에 앉힌 문단(그리기도 이걸 쓴다). [maxLines] 0 이면 제한 없음. */
    fun paragraph(
        text: String,
        maxWidth: Double,
        color: Int = 0,
        sizePt: Double = BubbleMetrics.FONT_SIZE_PT,
        maxLines: Int = 0,
    ): Paragraph {
        val ts = TextStyle().apply {
            fontSize = sizePt.toFloat()
            fontFamilies = arrayOf(FAMILY)
            this.color = color
        }
        val ps = ParagraphStyle().apply {
            textStyle = ts
            if (maxLines > 0) {
                maxLinesCount = maxLines
                ellipsis = "…"
            }
        }
        return ParagraphBuilder(ps, fonts).pushStyle(ts).addText(text).build().layout(maxWidth.toFloat())
    }

    override fun width(t: String): Double = if (t.isEmpty()) 0.0 else paragraph(t, UNBOUNDED).maxIntrinsicWidth.toDouble()

    override fun lineCount(t: String, widthPt: Double): Int = if (t.isEmpty()) 0 else paragraph(t, widthPt).lineNumber

    /** 한 줄 높이(글꼴에서 파생 — 맥 defaultLineHeight 와 같은 자리). */
    val lineHeight: Double by lazy { paragraph("가", UNBOUNDED).height.toDouble() }

    companion object {
        /** 글꼴 묶음 안의 이름(OS 에 설치된 Pretendard 와 섞이지 않게 앱 전용 이름). */
        const val FAMILY = "AingCheckBubblePretendard"
        private const val UNBOUNDED = 100_000.0

        /** ui 모듈이 싣는 Pretendard SemiBold 경로(composeResources 안). */
        val SEMIBOLD_PATH: String = Pretendard.faces.first { it.weight == FontWeight.SemiBold }.path

        /** 번들 바이트로 한 벌 — 글꼴 해석은 비싸니 앱·시험이 같이 쓴다. */
        val bundled: PretendardBubbleMeasure by lazy { fromBytes(readBundledSemiBold()) }

        @OptIn(ExperimentalResourceApi::class)
        fun readBundledSemiBold(): ByteArray = runBlocking { Res.readBytes(SEMIBOLD_PATH) }

        fun fromBytes(bytes: ByteArray): PretendardBubbleMeasure {
            val face = requireNotNull(FontMgr.default.makeFromData(Data.makeFromBytes(bytes))) { "Skia 가 말풍선 글꼴을 못 열었다" }
            val provider = TypefaceFontProvider().registerTypeface(face, FAMILY)
            val fc = FontCollection().apply {
                setAssetFontManager(provider)
                // 번들 글꼴에 없는 글자(그림 글자 등)만 OS 글꼴로. 한글·라틴·문장 부호는 Pretendard 가 다 덮는다(PretendardBundleTest).
                setDefaultFontManager(FontMgr.default)
            }
            return PretendardBubbleMeasure(fc)
        }
    }
}
