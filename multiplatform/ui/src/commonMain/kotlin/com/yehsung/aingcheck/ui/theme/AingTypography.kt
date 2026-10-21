// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift @ a63fea2 (글꼴 — 큰 제목 34 · 섹션 19~20 bold · 행 이름 16 semibold · 부제 13 · 칩 11 semibold)
//
// iOS 는 Dynamic Type 텍스트 스타일(시스템 SF)만 쓴다. 여기서는 같은 크기·행간(애플 HIG 기본 크기 표)을 Pretendard 로 M3 역할에 앉힌다.
// sp 라 시스템 글자 크기를 따른다(iOS Dynamic Type 과 같은 뜻).
//
//   iOS 스타일(크기/행간)          → M3 역할
//   largeTitle 34/41 bold         → headlineLarge
//   title1 28/34 bold             → headlineMedium
//   title2 22/28 bold             → headlineSmall
//   title3 20/25 bold(섹션 머리)   → titleLarge
//   headline 17/22 semibold       → titleMedium
//   callout 16/21 semibold(행 이름)→ titleSmall
//   body 17/22                    → bodyLarge
//   subheadline 15/20             → bodyMedium
//   footnote 13/18(행 부제)        → bodySmall
//   subheadline 15/20 semibold    → labelLarge(단추 글자)
//   caption1 12/16 semibold        → labelMedium
//   caption2 11/13 semibold(칩)    → labelSmall
//   타이머 48 · 위젯 큰 수 40 · 36  → displayLarge·Medium·Small(semibold, 고정 크기 글꼴 자리 — iOS scaledFont)
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.ui.fonts.pretendardFontFamily

object AingTypeScale {
    /** (M3 역할, 크기 sp, 행간 sp, 굵기). 시험이 iOS 표와 대조한다. */
    data class Step(val role: String, val size: Float, val lineHeight: Float, val weight: FontWeight)

    val steps: List<Step> = listOf(
        Step("displayLarge", 48f, 56f, FontWeight.SemiBold),
        Step("displayMedium", 40f, 48f, FontWeight.SemiBold),
        Step("displaySmall", 36f, 43f, FontWeight.SemiBold),
        Step("headlineLarge", 34f, 41f, FontWeight.Bold),
        Step("headlineMedium", 28f, 34f, FontWeight.Bold),
        Step("headlineSmall", 22f, 28f, FontWeight.Bold),
        Step("titleLarge", 20f, 25f, FontWeight.Bold),
        Step("titleMedium", 17f, 22f, FontWeight.SemiBold),
        Step("titleSmall", 16f, 21f, FontWeight.SemiBold),
        Step("bodyLarge", 17f, 22f, FontWeight.Normal),
        Step("bodyMedium", 15f, 20f, FontWeight.Normal),
        Step("bodySmall", 13f, 18f, FontWeight.Normal),
        Step("labelLarge", 15f, 20f, FontWeight.SemiBold),
        Step("labelMedium", 12f, 16f, FontWeight.SemiBold),
        Step("labelSmall", 11f, 13f, FontWeight.SemiBold),
    )

    fun typography(family: FontFamily): Typography {
        val byRole = steps.associateBy { it.role }
        fun style(role: String): TextStyle {
            val s = byRole.getValue(role)
            return TextStyle(
                fontFamily = family,
                fontWeight = s.weight,
                fontSize = s.size.sp,
                lineHeight = s.lineHeight.sp,
                letterSpacing = 0.sp,
            )
        }
        return Typography(
            displayLarge = style("displayLarge"), displayMedium = style("displayMedium"), displaySmall = style("displaySmall"),
            headlineLarge = style("headlineLarge"), headlineMedium = style("headlineMedium"), headlineSmall = style("headlineSmall"),
            titleLarge = style("titleLarge"), titleMedium = style("titleMedium"), titleSmall = style("titleSmall"),
            bodyLarge = style("bodyLarge"), bodyMedium = style("bodyMedium"), bodySmall = style("bodySmall"),
            labelLarge = style("labelLarge"), labelMedium = style("labelMedium"), labelSmall = style("labelSmall"),
        )
    }
}

/** 앱 글꼴 체계(Pretendard). */
@Composable
fun aingTypography(): Typography = AingTypeScale.typography(pretendardFontFamily())
