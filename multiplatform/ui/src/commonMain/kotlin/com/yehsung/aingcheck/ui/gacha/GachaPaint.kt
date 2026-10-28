// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift @ 3bd04bd (희귀 강조 — rare · ink · sparkle · rareTint · tint(Finish) · rainbowSolid)
//
// 뽑기 화면의 희귀 강조 칠(황금 · 무지개). 판정은 3D 마감과 한 곳(rules `CharacterManifest.Finish`) — 케이크는 희귀가 아니다(칠 없음).
// 글자 칠은 [AingTextPaint] 규칙을 따른다: 긴 글자(이름)는 일곱 빛 그라데이션, 짧은 글자(확률 숫자 "2%")·작은 기호는 단색.
// iOS 1.0.10 은 다크의 짧은 글자에 일곱 빛을 남겼지만 이식은 두 모드 모두 단색이다(AingTextPaint.solidFor — 조정자 지시).
package com.yehsung.aingcheck.ui.gacha

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.ui.theme.AingPalette
import com.yehsung.aingcheck.ui.theme.AingTextPaint
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 글자 한 줄의 칠: 단색 또는 붓(긴 글자만). */
sealed interface GachaInk {
    data class Solid(val color: Color) : GachaInk
    data class Painted(val brush: Brush) : GachaInk
}

object GachaPaint {
    /** 희귀 강조 글자 칠(황금 = 금빛 글자색 · 무지개 = 일곱 빛 · 평범 = null). 짧은 글자면 무지개도 단색(보라). */
    @Composable
    fun rare(finish: CharacterManifest.Finish, text: String): GachaInk? {
        val c = AingTheme.colors
        return when (finish) {
            CharacterManifest.Finish.gold -> GachaInk.Solid(c.goldText)
            CharacterManifest.Finish.rainbow -> AingTextPaint.textBrushOrNull(text, c.rainbowStops)?.let { GachaInk.Painted(it) }
                ?: GachaInk.Solid(AingTextPaint.solidFor(c.rainbowStops, c.label))
            CharacterManifest.Finish.standard, CharacterManifest.Finish.cakeStrawberry, CharacterManifest.Finish.cakeChoco -> null
        }
    }

    /** 희귀면 그 칠, 아니면 [otherwise]. */
    @Composable
    fun ink(finish: CharacterManifest.Finish, text: String, otherwise: Color): GachaInk = rare(finish, text) ?: GachaInk.Solid(otherwise)

    /**
     * 반짝임 **기호**(뽑기 전용 타일의 sparkles) 전용 빛깔 — 글자(ink)와 규칙이 갈린다(폰 1.0.10): 기호는 장식이라 메달 금(1.8:1 이어도 된다),
     * 무지개는 짧은 자리라 일곱 중 보라 한 색. 평범(서버 표식만 준 id) · 케이크는 금.
     */
    @Composable
    fun sparkle(finish: CharacterManifest.Finish): Color {
        val c = AingTheme.colors
        return when (finish) {
            CharacterManifest.Finish.rainbow -> AingTextPaint.sparkle(c.rainbowStops, c.gold)
            else -> c.gold
        }
    }

    /** 희귀 받침(금빛 14% · 무지개 일곱 빛 14%). 평범은 null. */
    @Composable
    fun rareTint(finish: CharacterManifest.Finish): Brush? {
        val c = AingTheme.colors
        return when (finish) {
            CharacterManifest.Finish.gold -> Brush.horizontalGradient(listOf(c.gold.copy(alpha = AingPalette.RARE_TINT_OPACITY.toFloat()), c.gold.copy(alpha = AingPalette.RARE_TINT_OPACITY.toFloat())))
            CharacterManifest.Finish.rainbow -> Brush.horizontalGradient(c.rainbowStops.map { it.copy(alpha = AingPalette.RARE_TINT_OPACITY.toFloat()) })
            else -> null
        }
    }

    /** 희귀 테두리 칠(결과 줄의 1pt 테). */
    @Composable
    fun rareStroke(finish: CharacterManifest.Finish): Brush? {
        val c = AingTheme.colors
        return when (finish) {
            CharacterManifest.Finish.gold -> Brush.horizontalGradient(listOf(c.goldText, c.goldText))
            CharacterManifest.Finish.rainbow -> Brush.horizontalGradient(c.rainbowStops)
            else -> null
        }
    }

    /** 글자 스타일에 칠을 건다(붓은 [AingTextPaint.withBrush] 로만 — 짧은 글자 그라데이션 금지 규칙). */
    fun styled(style: TextStyle, ink: GachaInk): TextStyle = when (ink) {
        is GachaInk.Solid -> style.copy(color = ink.color)
        is GachaInk.Painted -> AingTextPaint.withBrush(style, ink.brush)
    }
}
