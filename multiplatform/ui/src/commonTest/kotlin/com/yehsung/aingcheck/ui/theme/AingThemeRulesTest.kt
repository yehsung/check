// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f (대비 규칙 — iOS BaseThemeTests 와 같은 묶음)
// 원본: Sources/CheckMobileKit/Theme/MobileAppearance.swift @ 862be0f (화면 모드 저장값)
//
// 테마 규칙(플랫폼 무관 — 데스크톱·Android 호스트 둘 다에서 돈다).
//  - 글자·부품 대비(WCAG) · M3 역할 48개 전부 손으로 채움(반사 열거, 기준값 누수 0) · 고정 역할은 두 모드 같은 값
//  - 주요색 하나(G §8-13): accent 가족 = M3 primary · AI 토큰 보라는 primary 와 다른 값이고 나란히 구분된다(CIEDE2000)
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class AingThemeRulesTest {
    private fun Color.rgb() = AingRgb(red.toDouble(), green.toDouble(), blue.toDouble(), alpha.toDouble())

    /** iOS BaseThemeTests 와 같은 규칙: 글자 토큰은 라이트·다크 모두 카드와 바탕 위 4.5:1. */
    @Test
    fun textTokensReachFourPointFiveOnCardAndBackground() {
        val failures = mutableListOf<String>()
        for (dark in listOf(false, true)) for ((name, pair) in AingPalette.textTokens) {
            for ((surfaceName, surface) in listOf("surface" to AingPalette.surface, "background" to AingPalette.background)) {
                val c = pair.pick(dark).contrast(surface.pick(dark))
                if (c < 4.5) failures += "${if (dark) "다크" else "라이트"} $name on $surfaceName = ${r2(c)}"
            }
        }
        for (dark in listOf(false, true)) for ((name, text, tint) in AingPalette.tintedTextPairs) {
            val surface = AingPalette.surface.pick(dark)
            val c = text.pick(dark).contrast(tint.pick(dark).compositedOver(surface))
            if (c < 4.5) failures += "${if (dark) "다크" else "라이트"} $name = ${r2(c)}"
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    /** M3 뼈대 글자·부품 대비: 채움 위 글자 4.5:1, 스위치 트랙·테두리는 면 위 3:1(WCAG 1.4.11). */
    @Test
    fun materialRolesKeepContrast() {
        for (dark in listOf(false, true)) {
            val s = AingColorScheme.of(dark)
            val mode = if (dark) "다크" else "라이트"
            fun ratio(fg: Color, bg: Color) = fg.rgb().contrast(bg.rgb())
            assertTrue(ratio(s.onPrimary, s.primary) >= 4.5, "$mode onPrimary/primary ${ratio(s.onPrimary, s.primary)}")
            assertTrue(ratio(s.onSecondaryContainer, s.secondaryContainer) >= 4.5, "$mode onSecondaryContainer")
            assertTrue(ratio(s.onPrimaryContainer, s.primaryContainer) >= 4.5, "$mode onPrimaryContainer")
            assertTrue(ratio(s.onSurface, s.surface) >= 4.5, "$mode onSurface")
            assertTrue(ratio(s.onSurfaceVariant, s.surfaceContainerLow) >= 4.5, "$mode onSurfaceVariant on sheet")
            assertTrue(ratio(s.primary, s.surfaceContainerHigh) >= 3.0, "$mode primary(대화상자 단추 글자) on dialog ${ratio(s.primary, s.surfaceContainerHigh)}")
            assertTrue(ratio(s.primary, AingPalette.surface.pick(dark).toColor()) >= 3.0, "$mode 스위치 트랙 on card")
            assertTrue(ratio(s.outline, AingPalette.surface.pick(dark).toColor()) >= 3.0, "$mode outline on card")
            assertTrue(ratio(s.onError, s.error) >= 4.5, "$mode onError/error")
            // 탭 막대 선택 글자(= primary)는 선택 알약(secondaryContainer) 위 4.5:1 — iOS 가 다크에서 한 단계 밝힌 이유를 보라가 넘는다.
            val tab = AingColors.of(dark).tabSelected
            assertTrue(ratio(tab, s.secondaryContainer) >= 4.5, "$mode tabSelected on 선택 알약 ${ratio(tab, s.secondaryContainer)}")
            // 고정 역할: on…Fixed 는 …Fixed·…FixedDim 위, on…FixedVariant 는 …Fixed 위 4.5:1.
            for ((name, fixed, dim, on, onVariant) in listOf(
                FixedSet("primary", s.primaryFixed, s.primaryFixedDim, s.onPrimaryFixed, s.onPrimaryFixedVariant),
                FixedSet("secondary", s.secondaryFixed, s.secondaryFixedDim, s.onSecondaryFixed, s.onSecondaryFixedVariant),
                FixedSet("tertiary", s.tertiaryFixed, s.tertiaryFixedDim, s.onTertiaryFixed, s.onTertiaryFixedVariant),
            )) {
                assertTrue(ratio(on, fixed) >= 4.5, "$mode on${name}Fixed/${name}Fixed ${ratio(on, fixed)}")
                assertTrue(ratio(on, dim) >= 4.5, "$mode on${name}Fixed/${name}FixedDim ${ratio(on, dim)}")
                assertTrue(ratio(onVariant, fixed) >= 4.5, "$mode on${name}FixedVariant/${name}Fixed ${ratio(onVariant, fixed)}")
            }
        }
    }

    private data class FixedSet(val name: String, val fixed: Color, val dim: Color, val on: Color, val onVariant: Color)

    /**
     * 동적 색 없음 + 기본 보라(baseline) 새어 듦 없음: M3 역할을 **반사로 전부 열거해**(손 목록이 아니다) 기준값과 대조한다.
     * material3 1.9.0(데스크톱)·androidx 1.4.0(Android) 의 ColorScheme 은 48역할 — 판이 올라 역할이 늘면 수가 달라져 빨강이다.
     * 기준값과 같을 수 있는 자리는 설계상 같은 값인 곳뿐이다: 스크림(검정)과 라이트의 흰 자리(채움 위 흰 글자 · 가장 낮은 면 = 흰 카드).
     */
    @Test
    fun everyMaterialRoleIsFilledFromBrandNotBaseline() {
        val roles = materialColorRoles()
        assertEquals(EXPECTED_ROLE_COUNT, roles.size, "ColorScheme 색 역할 수가 바뀌었다(M3 판 변경?) — AingColorScheme 에 새 역할을 채운다: ${roles.map { it.name }}")
        assertEquals(roles.size, roles.map { it.name }.toSet().size, "역할 이름이 겹친다")
        for (fixedRole in FIXED_ROLES) assertTrue(roles.any { it.name == fixedRole }, "열거에 $fixedRole 가 없다 — 열거기가 고정 역할을 못 본다")
        val whiteByDesign = setOf("onPrimary", "onSecondary", "onTertiary", "onError", "surfaceContainerLowest")
        val leaked = mutableListOf<String>()
        for ((dark, baseline) in listOf(false to lightColorScheme(), true to darkColorScheme())) {
            val ours = AingColorScheme.of(dark)
            for (role in roles) {
                val v = role.read(ours)
                if (v != role.read(baseline)) continue
                if (role.name == "scrim" && v == Color.Black) continue
                if (!dark && role.name in whiteByDesign && v == AingPalette.surface.light.toColor()) continue
                leaked += "${if (dark) "다크" else "라이트"} ${role.name} = 기준값 $v"
            }
            assertEquals(Color.Transparent, ours.surfaceTint, "표면 틴트는 투명(iOS 처럼 평평한 면 — 올림 그림자에 보라가 끼지 않게)")
        }
        assertTrue(leaked.isEmpty(), "M3 기준 색이 새어 들었다:\n" + leaked.joinToString("\n"))
        // 브랜드 보라가 실제로 뼈대를 칠한다.
        assertEquals(AingPalette.brandInk.light.toColor(), AingColorScheme.Light.primary)
        assertEquals(AingPalette.brandInk.dark.toColor(), AingColorScheme.Dark.primary)
        assertEquals(AingPalette.background.dark.toColor(), AingColorScheme.Dark.background)
        assertEquals(AingPalette.danger.light.toColor(), AingColorScheme.Light.error)
    }

    /** M3 정의: 고정 역할은 밝음·어두움에서 같은 값이다(두 모드 사이를 오가도 고정 받침이 그대로). */
    @Test
    fun fixedRolesAreTheSameInBothModes() {
        val roles = materialColorRoles().filter { it.name in FIXED_ROLES }
        assertEquals(FIXED_ROLES.size, roles.size)
        val differ = roles.filter { it.read(AingColorScheme.Light) != it.read(AingColorScheme.Dark) }.map { it.name }
        assertTrue(differ.isEmpty(), "라이트·다크가 다른 고정 역할: $differ")
        // 고정 primary 받침은 브랜드 보라 가족이다(기준 보라 #EADDFF 아님은 위 누수 시험이 잰다).
        assertEquals(AingPalette.brandInk.dark.toColor(), AingColorScheme.Light.primaryFixedDim)
        assertEquals(AingPalette.brandTitle.light.toColor(), AingColorScheme.Dark.onPrimaryFixed)
    }

    /** 주요색은 하나(G §8-13): iOS 의 '선택·주요 동작' 파랑 자리(accent 가족)를 M3 primary 가 칠한다. */
    @Test
    fun accentFamilyIsMaterialPrimary() {
        for (dark in listOf(false, true)) {
            val s = AingColorScheme.of(dark)
            val c = AingColors.of(dark)
            val mode = if (dark) "다크" else "라이트"
            assertEquals(s.primary, c.accent, "$mode accent")
            assertEquals(s.primary, c.accentFill, "$mode accentFill")
            assertEquals(s.onPrimary, c.onAccentFill, "$mode onAccentFill")
            assertEquals(s.primary, c.tabSelected, "$mode tabSelected")
            for ((name, tinted) in listOf("accentTint" to c.accentTint, "accentLine" to c.accentLine)) {
                assertEquals(s.primary.copy(alpha = 1f), tinted.copy(alpha = 1f), "$mode $name 의 색은 primary(불투명도만 다르다)")
                assertTrue(tinted.alpha < 0.5f, "$mode $name 은 옅은 틴트·테두리다(알파 ${tinted.alpha})")
            }
        }
    }

    /**
     * AI 토큰 보라(iOS 값 그대로)는 primary 와 **다른 값**이고 나란히 놓여도 구분된다: CIEDE2000 ≥ [ColorDifference.SIDE_BY_SIDE_DISTINCT].
     * (진열장 "뜻 색" 줄에서 선택·AI 토큰 점이 나란히 있다.)
     */
    @Test
    fun aiTokenPurpleIsDistinctFromPrimarySideBySide() {
        for (dark in listOf(false, true)) {
            val ai = AingPalette.aiToken.pick(dark)
            val primary = AingPalette.brandInk.pick(dark)
            val mode = if (dark) "다크" else "라이트"
            assertNotEquals(primary.hex, ai.hex, "$mode AI 토큰과 primary 가 같은 값")
            val de = ColorDifference.ciede2000(ai, primary)
            println("AINGCHECK-AI-VS-PRIMARY $mode ΔE00=${r2(de)} ai=#${ai.hex.toString(16)} primary=#${primary.hex.toString(16)}")
            assertTrue(de >= ColorDifference.SIDE_BY_SIDE_DISTINCT, "$mode AI 토큰 보라와 primary 가 나란히 구분되지 않는다(ΔE00 ${r2(de)})")
            // 화면이 쓰는 값(AingColors·M3)도 같은 둘이다.
            assertEquals(ai.toColor(), AingColors.of(dark).aiToken)
            assertEquals(primary.toColor(), AingColorScheme.of(dark).primary)
        }
    }

    /** 색 차 식 검산: Sharma·Wu·Dalal(2005) 표 1 의 기준 쌍 + sRGB 빨강·흰색의 L*a*b*. 식이 틀리면 위 단언은 뜻이 없다. */
    @Test
    fun ciede2000MatchesPublishedReferencePairs() {
        val ref = listOf(
            Triple(ColorDifference.Lab(50.0, 2.6772, -79.7751), ColorDifference.Lab(50.0, 0.0, -82.7485), 2.0425),
            Triple(ColorDifference.Lab(50.0, 3.1571, -77.2803), ColorDifference.Lab(50.0, 0.0, -82.7485), 2.8615),
            Triple(ColorDifference.Lab(50.0, 0.0, 0.0), ColorDifference.Lab(50.0, -1.0, 2.0), 2.3669),
            Triple(ColorDifference.Lab(50.0, 2.49, -0.001), ColorDifference.Lab(50.0, -2.49, 0.0011), 7.2195),
            Triple(ColorDifference.Lab(50.0, 2.5, 0.0), ColorDifference.Lab(73.0, 25.0, -18.0), 27.1492),
            Triple(ColorDifference.Lab(60.2574, -34.0099, 36.2677), ColorDifference.Lab(60.4626, -34.1751, 39.4387), 1.2644),
            Triple(ColorDifference.Lab(2.0776, 0.0795, -1.1350), ColorDifference.Lab(0.9033, -0.0636, -0.5514), 0.9082),
        )
        for ((a, b, expected) in ref) {
            val got = ColorDifference.ciede2000(a, b)
            assertTrue(abs(got - expected) < 1e-4, "ΔE00($a, $b) = $got ≠ $expected")
            assertTrue(abs(ColorDifference.ciede2000(b, a) - expected) < 1e-4, "대칭")
        }
        val red = ColorDifference.lab(AingRgb.hex(0xFF0000))
        assertTrue(abs(red.l - 53.2408) < 1e-3 && abs(red.a - 80.0925) < 1e-3 && abs(red.b - 67.2032) < 1e-3, "sRGB 빨강 L*a*b* = $red")
        val white = ColorDifference.lab(AingRgb.hex(0xFFFFFF))
        assertTrue(abs(white.l - 100) < 1e-3 && abs(white.a) < 1e-3 && abs(white.b) < 1e-3, "흰색 L*a*b* = $white")
    }

    @Test
    fun appearanceModeDefaultsToDarkAndFoldsUnknownToDark() {
        assertEquals(AingAppearanceMode.Dark, AingAppearanceMode.fromStored(null))
        assertEquals(AingAppearanceMode.Dark, AingAppearanceMode.fromStored("dark"))
        assertEquals(AingAppearanceMode.Light, AingAppearanceMode.fromStored("light"))
        assertEquals(AingAppearanceMode.System, AingAppearanceMode.fromStored("system"))
        assertEquals(AingAppearanceMode.Dark, AingAppearanceMode.fromStored("sepia"))
        assertEquals(AingAppearanceMode.Dark, AingAppearanceMode.fromStored(1))
        assertEquals(listOf("dark", "light", "system"), AingAppearanceMode.entries.map { it.storedValue }, "목록 순서 = iOS allCases(기본이 맨 위)")
        assertEquals("aingcheck.appearance.mode", AingAppearanceMode.STORAGE_KEY)
        assertTrue(AingAppearanceMode.System.isDark(systemIsDark = true))
        assertTrue(!AingAppearanceMode.System.isDark(systemIsDark = false))
        assertTrue(AingAppearanceMode.Dark.isDark(systemIsDark = false))
        assertTrue(!AingAppearanceMode.Light.isDark(systemIsDark = true))
    }

    @Test
    fun avatarIndexMatchesMacHash() {
        // 맥 CheckTheme.avatarColor: 유니코드 스칼라 합 mod 6. "아잉" = 0xC544 + 0xC789 = 101,581 → 101581 % 6 = 1.
        assertEquals(1, AingPalette.avatarIndex("아잉"))
        assertEquals(('A'.code + 'B'.code) % 6, AingPalette.avatarIndex("AB"))
        // 보조 평면 문자는 스칼라 하나(UTF-16 대리 쌍 둘이 아니다): U+1F600 = 128,512 → 128512 % 6 = 4.
        assertEquals(128512 % 6, AingPalette.avatarIndex("😀"))
        assertNotEquals(AingPalette.avatarIndex("😀"), (0xD83D + 0xDE00) % 6, "대리 쌍을 따로 더하면 다른 칸이 나와야 이 단언이 뜻이 있다")
    }

    private fun r2(v: Double): String = ((v * 100).toLong() / 100.0).toString()

    private companion object {
        const val EXPECTED_ROLE_COUNT = 48
        val FIXED_ROLES = listOf("primary", "secondary", "tertiary").flatMap { r ->
            val cap = r.replaceFirstChar { it.uppercaseChar() }
            listOf("${r}Fixed", "${r}FixedDim", "on${cap}Fixed", "on${cap}FixedVariant")
        }
    }
}
