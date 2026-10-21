// 원본: 없음 — 이식 규칙 시험(기억 두 가지).
//
// 기억 두 가지를 값으로 잰다: 불투명도에 이징 금지(easing-must-not-drive-opacity) · 짧은 글자에 그라데이션 금지(short-text-kills-gradients).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.TweenSpec
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AingMotionAndPaintTest {
    @Test
    fun fadeSpecIsLinearAndMoveSpecIsEased() {
        val fade = AingMotion.fade<Float>(220) as TweenSpec<Float>
        assertEquals(LinearEasing, fade.easing, "흐려짐 사양에 이징이 걸렸다")
        assertEquals(220, fade.durationMillis)
        val move = AingMotion.move<Float>(220) as TweenSpec<Float>
        assertTrue(move.easing != LinearEasing, "이동 사양은 이징이 있어야 한다(같으면 순서가 사라지는 건 아니지만 이 토큰의 뜻이 없다)")
    }

    /**
     * 체스 잡힘 모션 실측표를 되묻는다: 진행도 0.5·0.8 에서 선형 불투명도는 이징 낀 값과 **달라야** 한다.
     * (이징 낀 식이면 0.5 → 0.192 · 0.8 → 0.012 — "밀려나기 전에 사라진다")
     */
    @Test
    fun fadeOutOpacityIsRawProgressNotEased() {
        val hold = 0.35f
        fun eased(k: Float) = minOf(1f, (1f - AingMotion.moveProgress(k)) / (1f - hold))
        assertClose(0.769f, AingMotion.fadeOutOpacity(0.5f, hold))
        assertClose(0.308f, AingMotion.fadeOutOpacity(0.8f, hold))
        assertClose(0.192f, eased(0.5f))
        assertClose(0.012f, eased(0.8f))
        assertTrue(AingMotion.fadeOutOpacity(0.5f, hold) - eased(0.5f) > 0.5f)
        // 불투명도 1 인 창의 길이: 0.22초 동안 60Hz 프레임 중 1.0 인 것 — 선형이면 4.62프레임(77ms), 이징이면 1.77프레임(29.4ms).
        val durationMs = 220.0
        val frameMs = 1000.0 / 60.0
        val opaqueMs = (0 until 10_000).count { i ->
            val k = (i / 10_000.0).toFloat()
            AingMotion.fadeOutOpacity(k, hold) >= 1f
        } * durationMs / 10_000.0
        assertTrue(opaqueMs / frameMs in 4.5..4.7, "불투명 창 ${opaqueMs}ms = ${opaqueMs / frameMs}프레임 — 4.62 여야 한다")
        assertEquals(1f, AingMotion.fadeOutOpacity(0f, hold))
        assertEquals(0f, AingMotion.fadeOutOpacity(1f, hold))
    }

    @Test
    fun shortTextGetsNoGradient() {
        val stops = AingTextPaint.rainbowStops(dark = false)
        assertEquals(2, AingTextPaint.glyphCount("2%"))
        assertEquals(2, AingTextPaint.glyphCount("3%"))
        assertEquals(6, AingTextPaint.glyphCount("무지개 아잉이"))
        assertNull(AingTextPaint.textBrushOrNull("2%", stops), "두 글자에 그라데이션")
        assertNull(AingTextPaint.textBrushOrNull("15%", stops), "세 글자에 그라데이션")
        assertNull(AingTextPaint.textBrushOrNull(" 2 % ", stops), "공백으로 길이를 부풀려도 짧은 글자다")
        assertNotNull(AingTextPaint.textBrushOrNull("무지개 아잉이", stops), "긴 이름은 그라데이션")
        assertNull(AingTextPaint.textBrushOrNull("무지개 아잉이", stops.take(1)), "정지점 하나는 그라데이션이 아니다")
        // 조합형(NFD) 한글 두 음절 = 낱자 다섯이지만 글자 둘.
        assertEquals(2, AingTextPaint.glyphCount("가난"))
        // 단색은 일곱 빛 중 보라(여섯 번째) — 새 색이 아니다.
        assertEquals(stops[5], AingTextPaint.solidFor(stops, AingTheme_fallback))
        assertEquals(AingTextPaint.rainbowOnDark[5], AingTextPaint.solidFor(AingTextPaint.rainbowStops(dark = true), AingTheme_fallback))
        assertEquals(stops[5], AingTextPaint.sparkle(stops, AingTheme_fallback), "기호도 단색")
    }

    private val AingTheme_fallback = androidx.compose.ui.graphics.Color.Magenta

    private fun assertClose(expected: Float, actual: Float) =
        assertTrue(abs(expected - actual) < 0.0015f, "기대 $expected · 실제 $actual")
}
