// 아잉체크 테마 = Material 3 뼈대 + 아잉체크 색·글꼴(사용자 결정 2026-10-21, G §8-12).
//  - 탭 막대·시트·대화상자·스위치는 M3 부품을 그대로 쓰고, 색은 AingColorScheme(브랜드 보라 · iOS 바탕) 이 칠한다.
//  - **동적 색(Material You)은 쓰지 않는다** — dynamic*ColorScheme 를 부르는 자리가 ui main 에 0 이어야 한다(구조 시험).
//  - 캐릭터 무대·루비·잔디·초상 같은 브랜드 부품은 AingTheme.colors(iOS 토큰 그대로)로 그린다.
//  - 글꼴은 번들 Pretendard 하나.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.foundation.shape.RoundedCornerShape

val LocalAingColors = staticCompositionLocalOf { AingColors.Dark }

/** 모양: M3 다섯 단을 iOS 치수(12 · 16 · 22)에 맞춘다. 시트·대화상자는 extraLarge(28) 를 M3 그대로 둔다. */
val AingShapes = Shapes(
    extraSmall = RoundedCornerShape(8),
    small = RoundedCornerShape(AingDimens.innerRadius),
    medium = RoundedCornerShape(AingDimens.tileRadius),
    large = RoundedCornerShape(AingDimens.groupRadius),
    extraLarge = RoundedCornerShape(28),
)

object AingTheme {
    val colors: AingColors
        @Composable @ReadOnlyComposable
        get() = LocalAingColors.current

    val dimens: AingDimens get() = AingDimens
}

/** 화면 모드로 고르는 입구(앱 셸이 쓴다). System 이면 OS 다크 설정을 따른다. */
@Composable
fun AingTheme(mode: AingAppearanceMode, content: @Composable () -> Unit) {
    AingTheme(dark = mode.isDark(isSystemInDarkTheme()), content = content)
}

/** 다크 여부로 직접 고르는 입구(스냅숏·미리보기). [typography] 는 시험이 글꼴을 갈아 끼울 때만 준다. */
@Composable
fun AingTheme(dark: Boolean, typography: Typography? = null, content: @Composable () -> Unit) {
    val colors = AingColors.of(dark)
    MaterialTheme(
        colorScheme = AingColorScheme.of(dark),
        typography = typography ?: aingTypography(),
        shapes = AingShapes,
    ) {
        CompositionLocalProvider(
            LocalAingColors provides colors,
            LocalContentColor provides colors.label,
            content = content,
        )
    }
}
