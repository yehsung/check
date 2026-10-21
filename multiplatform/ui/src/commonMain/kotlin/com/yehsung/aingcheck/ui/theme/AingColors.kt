// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift @ a63fea2
//
// 뜻 이름 색(라이트·다크 중 하나로 굳힌 Compose 색). 화면은 `AingTheme.colors.working` 처럼 쓴다 — 색 리터럴을 화면에 적지 않는다.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color

@Immutable
class AingColors private constructor(val isDark: Boolean) {
    private fun c(pair: AingPair): Color = pair.pick(isDark).toColor()

    // 바탕·표면
    val background = c(AingPalette.background)
    val surface = c(AingPalette.surface)
    val surface2 = c(AingPalette.surface2)
    val fill = c(AingPalette.fill)
    val fill2 = c(AingPalette.fill2)
    val separator = c(AingPalette.separator)
    val glass = c(AingPalette.glass)
    val glassLine = c(AingPalette.glassLine)
    val bubbleIn = c(AingPalette.bubbleIn)

    // 글자
    val label = c(AingPalette.label)
    val label2 = c(AingPalette.label2)
    /** 선·기호 전용(글자 금지 — 글자는 [label3Text]). */
    val label3 = c(AingPalette.label3)
    val label3Text = c(AingPalette.label3Text)

    // 뜻 색
    val accent = c(AingPalette.accent)
    val accentFill = c(AingPalette.accentFill)
    val accentTint = c(AingPalette.accentTint)
    val accentLine = c(AingPalette.accentLine)
    val onAccentFill = c(AingPalette.onAccentFill)
    val tabSelected = c(AingPalette.tabSelected)
    val working = c(AingPalette.working)
    val workingDot = c(AingPalette.workingDot)
    val workingTint = c(AingPalette.workingTint)
    val offWork = c(AingPalette.offWork)
    val offWorkDot = c(AingPalette.offWorkDot)
    val pending = c(AingPalette.pending)
    val pendingDot = c(AingPalette.pendingDot)
    val pendingTint = c(AingPalette.pendingTint)
    val danger = c(AingPalette.danger)
    val dangerTint = c(AingPalette.dangerTint)
    val aiToken = c(AingPalette.aiToken)
    val badge = c(AingPalette.badge)

    // 메달
    val gold = c(AingPalette.gold)
    val silver = c(AingPalette.silver)
    val bronze = c(AingPalette.bronze)
    val goldInk = c(AingPalette.goldInk)
    val silverInk = c(AingPalette.silverInk)
    val bronzeInk = c(AingPalette.bronzeInk)
    val crownInk = c(AingPalette.crownInk)

    // 그라디언트 정지점(뜻으로만 — '우리 팀' 게이지 · 로그인 단추 · 나무판)
    val gaugeStops: List<Color> = AingPalette.gaugeStops.map { it.toColor() }
    val startStops: List<Color> = AingPalette.startStops.map { it.toColor() }
    val woodStops: List<Color> = AingPalette.woodStops.map { it.toColor() }

    // 위젯
    val widgetBackground = c(AingPalette.widgetBackground)

    // 브랜드 보라(M3 뼈대 칠)
    val brandInk = c(AingPalette.brandInk)
    val brandTitle = c(AingPalette.brandTitle)
    val brandCard = c(AingPalette.brandCard)
    val brandLavender = AingPalette.brandLavender.toColor()
    val brandNavy = AingPalette.brandNavy.toColor()

    /** 이니셜 원: (글자 색, 원 바탕 색). */
    fun avatar(seed: String): Pair<Color, Color> {
        val ink = AingPalette.avatarInks[AingPalette.avatarIndex(seed)].pick(isDark)
        val tint = ink.opacity(if (isDark) AingPalette.AVATAR_TINT_OPACITY_DARK else AingPalette.AVATAR_TINT_OPACITY_LIGHT)
        return ink.toColor() to tint.toColor()
    }

    companion object {
        val Light = AingColors(isDark = false)
        val Dark = AingColors(isDark = true)

        fun of(dark: Boolean): AingColors = if (dark) Dark else Light
    }
}
