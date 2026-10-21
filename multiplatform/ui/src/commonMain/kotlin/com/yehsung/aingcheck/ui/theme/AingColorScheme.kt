// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ a63fea2 (바탕·표면·글자·위험)
// 원본: Sources/check/CheckGachaWindow.swift @ a63fea2 (브랜드 보라 — GachaWindowPalette 판·글자)
//
// M3 색 체계(사용자 결정 2026-10-21 "Material 3 뼈대 + 아잉체크 테마"): **동적 색은 쓰지 않는다**(기기 배경화면 색을
// 따르면 브랜드 보라가 흐려진다). 이 파일이 M3 역할 전부를 손으로 채운다 — 기본 보라(baseline)가 새어 들지 않게.
//
// 칠하는 갈래:
//  - M3 뼈대(탭 막대·스위치·대화상자·시트·단추)의 강조 = 브랜드 보라(primary·secondaryContainer).
//  - 바탕·카드·글자·구분선·위험 = iOS 토큰 그대로(뜻 색 accent 파랑·working 초록 등은 AingTheme.colors 로 화면이 직접 쓴다).
//  - 반투명 토큰(유리·틴트)은 M3 가 불투명 색을 기대하므로 **놓일 면 위에 겹친 값**으로 굳힌다(compositedOver — 원본 숫자에서 계산).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

object AingColorScheme {
    private val white = AingRgb.hex(0xFFFFFF)
    private val black = AingRgb.hex(0x000000)

    val Light: ColorScheme = build(dark = false)
    val Dark: ColorScheme = build(dark = true)

    fun of(dark: Boolean): ColorScheme = if (dark) Dark else Light

    private fun build(dark: Boolean): ColorScheme {
        fun p(pair: AingPair) = pair.pick(dark)
        val background = p(AingPalette.background)
        val surface = p(AingPalette.surface)
        val surface2 = p(AingPalette.surface2)
        // 탭 막대 = 유리(iOS 하단 막대)를 바탕 위에 겹친 값.
        val bar = p(AingPalette.glass).compositedOver(background)
        val label = p(AingPalette.label).compositedOver(surface)
        val label2 = p(AingPalette.label2).compositedOver(surface)
        val separator = p(AingPalette.separator).compositedOver(surface)
        val ink = p(AingPalette.brandInk)
        val title = p(AingPalette.brandTitle)
        // 보라 받침(primaryContainer·secondaryContainer — 탭 막대 선택 알약·토널 단추): 라이트는 라벤더 16% 를 카드 위에, 다크는 맥 보라 판.
        val brandContainer = if (dark) p(AingPalette.brandCard) else AingPalette.brandLavender.opacity(0.16).compositedOver(surface)
        val danger = p(AingPalette.danger)
        val dangerContainer = p(AingPalette.dangerTint).compositedOver(surface)
        val working = p(AingPalette.working)
        val workingContainer = p(AingPalette.workingTint).compositedOver(surface)
        // 보라 채움 위 글자: 라이트 흰색 · 다크는 옅은 보라 위라 짙은 가지색(맥 라이트 제목색).
        val onFilled = if (dark) AingPalette.brandTitle.light else white
        val inverseSurface = if (dark) AingPalette.background.light else AingPalette.surface.dark
        val inverseOn = if (dark) AingPalette.label.light else white

        fun Color(rgb: AingRgb) = rgb.toColor()
        return if (dark) {
            darkColorScheme(
                primary = Color(ink), onPrimary = Color(onFilled),
                primaryContainer = Color(brandContainer), onPrimaryContainer = Color(title),
                inversePrimary = Color(AingPalette.brandInk.light),
                secondary = Color(ink), onSecondary = Color(onFilled),
                secondaryContainer = Color(brandContainer), onSecondaryContainer = Color(title),
                tertiary = Color(working), onTertiary = Color(AingPalette.brandNavy),
                tertiaryContainer = Color(workingContainer), onTertiaryContainer = Color(working),
                background = Color(background), onBackground = Color(label),
                surface = Color(background), onSurface = Color(label),
                surfaceVariant = Color(surface2), onSurfaceVariant = Color(label2),
                surfaceTint = Color.Transparent,
                inverseSurface = Color(inverseSurface), inverseOnSurface = Color(inverseOn),
                error = Color(danger), onError = Color(AingPalette.brandNavy),
                errorContainer = Color(dangerContainer), onErrorContainer = Color(danger),
                outline = Color(label2), outlineVariant = Color(separator),
                scrim = Color(black),
                surfaceBright = Color(surface2),
                surfaceContainer = Color(bar),
                surfaceContainerHigh = Color(surface2),
                surfaceContainerHighest = Color(surface2),
                surfaceContainerLow = Color(surface),
                surfaceContainerLowest = Color(background),
                surfaceDim = Color(background),
            )
        } else {
            lightColorScheme(
                primary = Color(ink), onPrimary = Color(onFilled),
                primaryContainer = Color(brandContainer), onPrimaryContainer = Color(title),
                inversePrimary = Color(AingPalette.brandInk.dark),
                secondary = Color(ink), onSecondary = Color(onFilled),
                secondaryContainer = Color(brandContainer), onSecondaryContainer = Color(title),
                tertiary = Color(working), onTertiary = Color(white),
                tertiaryContainer = Color(workingContainer), onTertiaryContainer = Color(working),
                background = Color(background), onBackground = Color(label),
                surface = Color(background), onSurface = Color(label),
                surfaceVariant = Color(surface2), onSurfaceVariant = Color(label2),
                surfaceTint = Color.Transparent,
                inverseSurface = Color(inverseSurface), inverseOnSurface = Color(inverseOn),
                error = Color(danger), onError = Color(white),
                errorContainer = Color(dangerContainer), onErrorContainer = Color(danger),
                outline = Color(label2), outlineVariant = Color(separator),
                scrim = Color(black),
                surfaceBright = Color(surface),
                surfaceContainer = Color(bar),
                surfaceContainerHigh = Color(surface),
                surfaceContainerHighest = Color(surface2),
                surfaceContainerLow = Color(surface),
                surfaceContainerLowest = Color(surface),
                surfaceDim = Color(background),
            )
        }
    }
}
