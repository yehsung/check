// 원본: Sources/check/CheckGachaWindow.swift @ a63fea2 (GachaWindowPalette.light.rainbow — 흰 판 위 진한 일곱 빛)
// 원본: Sources/check/CheckGachaPanel.swift @ a63fea2 (GachaPalette.rainbowColors — 어두운·보라 판 위 밝은 파스텔)
//
// 글자 칠 규칙(기억 short-text-kills-gradients, 2026-10-20 폰 1.0.10 실측):
//
//   **그라데이션은 글자가 길어야 그라데이션으로 읽힌다.** 「2%」처럼 두세 글자에 일곱 빛을 깔면 한두 색만 지나가 탁한 단색이 되고,
//   바로 윗줄 황금 「3%」와 같은 흙빛으로 읽혔다. 사용자 선택: 긴 글자(이름)는 그라데이션, 짧은 글자(확률 숫자)·작은 기호는 단색.
//
// 그래서 글자에 붓(Brush)을 거는 길은 [textBrushOrNull] 하나다(ui main 에서 TextStyle 에 brush 를 직접 거는 것은
// `AingTextPaintStructureTest` 가 소스로 막는다). 기호(장식)는 글자가 아니라 4.5:1 규칙을 쓰지 않고 [sparkle] 단색을 쓴다 —
// 「글자 색」과 「기호 색」을 가르는 이유가 이것이다(합치지 말 것).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle

object AingTextPaint {
    /** 그라데이션을 허락하는 최소 글자 수(공백 뺀 글자 묶음 기준). 「무지개 아잉이」(6) 는 되고 「2%」(2)·「3%」 는 안 된다. */
    const val MIN_GRADIENT_GLYPHS = 4

    /** 흰 판(라이트) 위 무지개 일곱 빛 — 글자 대비용 진한 쪽. */
    val rainbowOnLight: List<Color> = listOf(
        Color(0.85f, 0.22f, 0.33f), Color(0.86f, 0.45f, 0.08f), Color(0.70f, 0.58f, 0.00f), Color(0.16f, 0.60f, 0.27f),
        Color(0.13f, 0.47f, 0.85f), Color(0.36f, 0.29f, 0.86f), Color(0.66f, 0.24f, 0.82f),
    )

    /** 어두운·보라 판(다크) 위 무지개 일곱 빛 — 밝은 파스텔. */
    val rainbowOnDark: List<Color> = listOf(
        Color(1.00f, 0.56f, 0.64f), Color(1.00f, 0.72f, 0.44f), Color(1.00f, 0.90f, 0.43f), Color(0.56f, 0.90f, 0.61f),
        Color(0.49f, 0.76f, 1.00f), Color(0.65f, 0.61f, 1.00f), Color(0.91f, 0.61f, 1.00f),
    )

    fun rainbowStops(dark: Boolean): List<Color> = if (dark) rainbowOnDark else rainbowOnLight

    /**
     * 짧은 글자·작은 기호의 단색 = 일곱 빛 중 **보라(여섯 번째)** — 새 색이 아니라 그 일곱 중 하나라 신원이 흔들리지 않는다
     * (폰 1.0.10 B안: 라이트 흰 카드 위 5.09:1). iOS 1.0.10 은 다크의 짧은 글자에 일곱 빛을 그대로 두었지만, 이 이식은
     * "두세 글자에는 그라데이션을 깔지 않는다"를 두 모드 모두에 건다(조정자 지시 — 다크도 같은 함정이 생길 수 있다).
     */
    fun solidFor(stops: List<Color>, fallback: Color): Color = stops.getOrNull(5) ?: stops.lastOrNull() ?: fallback

    /**
     * 글자 수를 센다: 공백을 빼고, 결합 문자(한글 자모 조합·이모지 수식)는 앞 글자에 붙인다.
     * 정확한 그래핌 분할은 W1-c(rules/text) 몫이다 — 여기서는 "넷 이상인가"만 가르면 된다.
     */
    fun glyphCount(text: String): Int {
        var count = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAtCompat(i)
            val width = if (cp >= 0x10000) 2 else 1
            val isSpace = cp == 0x20 || cp == 0x3000 || cp == 0x09 || cp == 0x0A || cp == 0xA0
            val isJoiner = cp == 0x200D || cp in 0xFE00..0xFE0F || cp in 0x1F3FB..0x1F3FF ||
                cp in 0x0300..0x036F || cp in 0x1160..0x11FF // 조합 중성·종성(낱자 NFD)
            if (!isSpace && !isJoiner) count++
            i += width
        }
        return count
    }

    /** 이 글자에 그라데이션을 깔아도 되는가. */
    fun allowsGradient(text: String): Boolean = glyphCount(text) >= MIN_GRADIENT_GLYPHS

    /**
     * 글자 붓: 길면 [stops] 가로 그라데이션, 짧으면 null(→ 부르는 쪽이 [solidFor] 단색으로 칠한다).
     * 정지점이 둘 미만이어도 null.
     */
    fun textBrushOrNull(text: String, stops: List<Color>): Brush? =
        if (stops.size >= 2 && allowsGradient(text)) Brush.horizontalGradient(stops) else null

    /** 글자 스타일에 붓을 거는 유일한 자리([textBrushOrNull] 이 고른 붓만 넘긴다). */
    fun withBrush(style: TextStyle, brush: Brush): TextStyle = style.copy(brush = brush)

    /** 작은 기호(sparkles 등): 장식이라 대비 규칙 밖이지만 짧은 자리라 그라데이션을 깔지 않는다 — 단색. */
    fun sparkle(stops: List<Color>, fallback: Color): Color = solidFor(stops, fallback)
}
