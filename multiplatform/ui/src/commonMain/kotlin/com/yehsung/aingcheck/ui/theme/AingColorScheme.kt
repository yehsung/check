// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f (바탕·표면·글자·위험)
// 원본: Sources/check/CheckGachaWindow.swift @ 862be0f (브랜드 보라 — GachaWindowPalette 판·글자)
//
// M3 색 체계(사용자 결정 2026-10-21 "Material 3 뼈대 + 아잉체크 테마"): **동적 색은 쓰지 않는다**(기기 배경화면 색을
// 따르면 브랜드 보라가 흐려진다). 이 파일이 M3 역할 **48개 전부**(material3 1.9.0 · androidx 1.4.0 의 ColorScheme 게터 수)를
// 손으로 채운다 — 기본 보라(baseline)가 새어 들지 않게. 시험은 ColorScheme 의 Color 게터를 반사로 전부 열거해 기준값과 대조한다
// (M3 판이 올라 역할이 늘면 열거 수가 48 이 아니라서 빨강 — 그때 새 역할을 여기 채운다).
//
// 칠하는 갈래:
//  - 주요색 = 브랜드 보라 하나(primary·secondary·…Container). iOS 의 '선택·주요 동작' 파랑도 이 이식에서는 primary 다(G §8-13 —
//    AingPalette.accent 가족이 primary 에서 나온다).
//  - 바탕·카드·글자·구분선·위험 = iOS 토큰 그대로(뜻 색 working 초록·pending 주황·aiToken 보라 등은 AingTheme.colors 로 화면이 직접 쓴다).
//  - 반투명 토큰(유리·틴트)은 M3 가 불투명 색을 기대하므로 **놓일 면 위에 겹친 값**으로 굳힌다(compositedOver — 원본 숫자에서 계산).
//  - 고정 역할(…Fixed·…FixedDim·on…Fixed·on…FixedVariant, 12개)은 M3 정의대로 **라이트·다크가 같은 값**이다:
//    primary·secondary 쪽 = 라이트 보라 받침 · 다크 primary 라벤더 · 짙은 가지색 · 라이트 primary,
//    tertiary 쪽 = 라이트 근무 틴트 · 다크 근무 초록 · 남색 · 라이트 근무 글자(tertiary 가 근무 초록이라서).
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
        // 보라 채움 위 글자: 라이트 흰색 · 다크는 옅은 보라 위라 짙은 가지색(맥 라이트 제목색). accent 가족의 onAccentFill 과 같은 값.
        val onFilled = p(AingPalette.brandOnInk)
        // 고정 역할(두 모드 같은 값).
        val surfaceLight = AingPalette.surface.light
        val primaryFixed = AingPalette.brandLavender.opacity(0.16).compositedOver(surfaceLight)
        val primaryFixedDim = AingPalette.brandInk.dark
        val onPrimaryFixed = AingPalette.brandTitle.light
        val onPrimaryFixedVariant = AingPalette.brandInk.light
        val tertiaryFixed = AingPalette.workingTint.light.compositedOver(surfaceLight)
        val tertiaryFixedDim = AingPalette.working.dark
        val onTertiaryFixed = AingPalette.brandNavy
        val onTertiaryFixedVariant = AingPalette.working.light
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
                primaryFixed = Color(primaryFixed), primaryFixedDim = Color(primaryFixedDim),
                onPrimaryFixed = Color(onPrimaryFixed), onPrimaryFixedVariant = Color(onPrimaryFixedVariant),
                secondaryFixed = Color(primaryFixed), secondaryFixedDim = Color(primaryFixedDim),
                onSecondaryFixed = Color(onPrimaryFixed), onSecondaryFixedVariant = Color(onPrimaryFixedVariant),
                tertiaryFixed = Color(tertiaryFixed), tertiaryFixedDim = Color(tertiaryFixedDim),
                onTertiaryFixed = Color(onTertiaryFixed), onTertiaryFixedVariant = Color(onTertiaryFixedVariant),
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
                primaryFixed = Color(primaryFixed), primaryFixedDim = Color(primaryFixedDim),
                onPrimaryFixed = Color(onPrimaryFixed), onPrimaryFixedVariant = Color(onPrimaryFixedVariant),
                secondaryFixed = Color(primaryFixed), secondaryFixedDim = Color(primaryFixedDim),
                onSecondaryFixed = Color(onPrimaryFixed), onSecondaryFixedVariant = Color(onPrimaryFixedVariant),
                tertiaryFixed = Color(tertiaryFixed), tertiaryFixedDim = Color(tertiaryFixedDim),
                onTertiaryFixed = Color(onTertiaryFixed), onTertiaryFixedVariant = Color(onTertiaryFixedVariant),
            )
        }
    }
}
