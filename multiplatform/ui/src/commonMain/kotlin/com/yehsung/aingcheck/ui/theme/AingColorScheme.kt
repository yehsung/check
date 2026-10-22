// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f (주요색 accent 가족·바탕·표면·글자·위험)
//
// M3 색 체계(사용자 결정 2026-10-21 "Material 3 뼈대 + 아잉체크 테마"): **동적 색은 쓰지 않는다**(기기 배경화면 색을
// 따르면 아잉체크 색이 흐려진다). 이 파일이 M3 역할 **48개 전부**(material3 1.9.0 · androidx 1.4.0 의 ColorScheme 게터 수)를
// 손으로 채운다 — 기본 보라(baseline)가 새어 들지 않게. 시험은 ColorScheme 의 Color 게터를 반사로 전부 열거해 기준값·역할 표와 대조한다
// (M3 판이 올라 역할이 늘면 열거 수가 48 이 아니라서 빨강 — 그때 새 역할을 여기 채운다).
//
// 칠하는 갈래(G §8-15 — 주요색은 iOS 파랑. §8-13 의 "주요색 = 브랜드 보라"를 뒤집었다):
//  - 주요색 = iOS accent 가족(primary·secondary·inversePrimary·…Container). M3 뼈대 전부(채운·토널·글자 단추, 스위치, 탭 막대 선택 알약·글자,
//    대화상자 단추, 체크·라디오·슬라이더·진행 표시)가 파랑이다 — 한 화면에 보라 단추와 파랑 선택이 섞이지 않게.
//    · primary = accent: 라이트 #1864CF(흰 글자) · 다크 (0.33, 0.67, 1.0). 다크에서 accentFill(#2A74DE)이 아닌 이유 — M3 는 primary 를
//      글자로도 쓰는데(대화상자·글자 단추) #2A74DE 는 다크 카드 위 2.98:1 이다. 그래서 다크 onPrimary 는 밝은 파랑 위 짙은 남색(brandNavy).
//    · secondary = tabSelected: M3 가 secondary 를 글자로 쓰는 대표 자리가 탭 막대 선택 글자다(NavigationBar active label) — iOS 탭 선택색 그대로.
//    · 받침(primaryContainer·secondaryContainer — 탭 선택 알약·토널 단추) = accentTint 를 카드 위에 겹친 값, 그 위 글자 = tabSelected.
//  - 바탕·카드·글자·구분선·위험 = iOS 토큰 그대로(뜻 색 working 초록·pending 주황·aiToken 보라 등은 AingTheme.colors 로 화면이 직접 쓴다).
//  - 반투명 토큰(유리·틴트)은 M3 가 불투명 색을 기대하므로 **놓일 면 위에 겹친 값**으로 굳힌다(compositedOver — 원본 숫자에서 계산).
//  - 고정 역할(…Fixed·…FixedDim·on…Fixed·on…FixedVariant, 12개)은 M3 정의대로 **라이트·다크가 같은 값**이다:
//    primary·secondary 쪽 = 라이트 파랑 받침 · 다크 primary(밝은 파랑) · 짙은 남색 · 라이트 primary,
//    tertiary 쪽 = 라이트 근무 틴트 · 다크 근무 초록 · 남색 · 라이트 근무 글자(tertiary 가 근무 초록이라서).
//  - 브랜드 보라(AingPalette.brand*)는 어느 역할에도 쓰지 않는다(브랜드 자리 전용 — AingPaletteSwiftContractTest 가 잰다).
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
        // 주요색(iOS 파랑): 글자·채움 겸용 primary 와 탭 선택색 secondary.
        val accent = p(AingPalette.accent)
        val tabSelected = p(AingPalette.tabSelected)
        // primary·secondary 채움 위 글자: 라이트 흰색(onAccentFill) · 다크는 밝은 파랑 위라 짙은 남색.
        val onFilled = if (dark) AingPalette.brandNavy else p(AingPalette.onAccentFill)
        // 파랑 받침(primaryContainer·secondaryContainer — 탭 막대 선택 알약·토널 단추): accentTint 를 카드 위에 겹친 값.
        val accentContainer = p(AingPalette.accentTint).compositedOver(surface)
        val danger = p(AingPalette.danger)
        val dangerContainer = p(AingPalette.dangerTint).compositedOver(surface)
        val working = p(AingPalette.working)
        val workingContainer = p(AingPalette.workingTint).compositedOver(surface)
        // 고정 역할(두 모드 같은 값).
        val surfaceLight = AingPalette.surface.light
        val primaryFixed = AingPalette.accentTint.light.compositedOver(surfaceLight)
        val primaryFixedDim = AingPalette.accent.dark
        val onPrimaryFixed = AingPalette.brandNavy
        val onPrimaryFixedVariant = AingPalette.accent.light
        val tertiaryFixed = AingPalette.workingTint.light.compositedOver(surfaceLight)
        val tertiaryFixedDim = AingPalette.working.dark
        val onTertiaryFixed = AingPalette.brandNavy
        val onTertiaryFixedVariant = AingPalette.working.light
        val inverseSurface = if (dark) AingPalette.background.light else AingPalette.surface.dark
        val inverseOn = if (dark) AingPalette.label.light else white
        // 반대 면(inverseSurface — 스낵바) 위 주요색: 라이트 모드의 반대 면은 다크 카드라 다크 accent, 다크 모드는 라이트 accent.
        val inversePrimary = AingPalette.accent.pick(!dark)

        fun Color(rgb: AingRgb) = rgb.toColor()
        return if (dark) {
            darkColorScheme(
                primary = Color(accent), onPrimary = Color(onFilled),
                primaryContainer = Color(accentContainer), onPrimaryContainer = Color(tabSelected),
                inversePrimary = Color(inversePrimary),
                secondary = Color(tabSelected), onSecondary = Color(onFilled),
                secondaryContainer = Color(accentContainer), onSecondaryContainer = Color(tabSelected),
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
                primary = Color(accent), onPrimary = Color(onFilled),
                primaryContainer = Color(accentContainer), onPrimaryContainer = Color(tabSelected),
                inversePrimary = Color(inversePrimary),
                secondary = Color(tabSelected), onSecondary = Color(onFilled),
                secondaryContainer = Color(accentContainer), onSecondaryContainer = Color(tabSelected),
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
