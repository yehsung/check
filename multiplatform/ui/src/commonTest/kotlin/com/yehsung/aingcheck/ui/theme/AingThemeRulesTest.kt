// 테마 규칙(플랫폼 무관 — 데스크톱·Android 호스트 둘 다에서 돈다).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
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
        }
    }

    /**
     * 동적 색 없음 + 기본 보라(baseline) 새어 듦 없음: M3 역할을 전부 손으로 채웠다.
     * 스크림(검정)·표면 틴트(투명)만 기준값과 같을 수 있다 — 나머지가 기준값과 같으면 그 역할을 빠뜨린 것이다.
     */
    @Test
    fun everyMaterialRoleIsFilledFromBrandNotBaseline() {
        val roles: List<Pair<String, (ColorScheme) -> Color>> = listOf(
            "primary" to { it.primary }, "onPrimary" to { it.onPrimary }, "primaryContainer" to { it.primaryContainer },
            "onPrimaryContainer" to { it.onPrimaryContainer }, "inversePrimary" to { it.inversePrimary },
            "secondary" to { it.secondary }, "onSecondary" to { it.onSecondary }, "secondaryContainer" to { it.secondaryContainer },
            "onSecondaryContainer" to { it.onSecondaryContainer }, "tertiary" to { it.tertiary }, "onTertiary" to { it.onTertiary },
            "tertiaryContainer" to { it.tertiaryContainer }, "onTertiaryContainer" to { it.onTertiaryContainer },
            "background" to { it.background }, "onBackground" to { it.onBackground }, "surface" to { it.surface }, "onSurface" to { it.onSurface },
            "surfaceVariant" to { it.surfaceVariant }, "onSurfaceVariant" to { it.onSurfaceVariant },
            "inverseSurface" to { it.inverseSurface }, "inverseOnSurface" to { it.inverseOnSurface },
            "error" to { it.error }, "onError" to { it.onError }, "errorContainer" to { it.errorContainer }, "onErrorContainer" to { it.onErrorContainer },
            "outline" to { it.outline }, "outlineVariant" to { it.outlineVariant },
            "surfaceBright" to { it.surfaceBright }, "surfaceContainer" to { it.surfaceContainer }, "surfaceContainerHigh" to { it.surfaceContainerHigh },
            "surfaceContainerHighest" to { it.surfaceContainerHighest }, "surfaceContainerLow" to { it.surfaceContainerLow },
            "surfaceContainerLowest" to { it.surfaceContainerLowest }, "surfaceDim" to { it.surfaceDim },
        )
        // 기준값과 우연히 같은 흰색인 자리(라이트 채움 위 흰 글자 · 가장 낮은 면 = 흰 카드)는 우리 값으로 따로 확인한다.
        val whiteByDesign = setOf("onPrimary", "onSecondary", "onTertiary", "onError", "surfaceContainerLowest")
        val leaked = mutableListOf<String>()
        for ((dark, baseline) in listOf(false to lightColorScheme(), true to darkColorScheme())) {
            val ours = AingColorScheme.of(dark)
            for ((name, get) in roles) {
                if (get(ours) != get(baseline)) continue
                if (!dark && name in whiteByDesign && get(ours) == AingPalette.surface.light.toColor()) continue
                leaked += "${if (dark) "다크" else "라이트"} $name = 기준값 ${get(baseline)}"
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
}
