// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f (대비 규칙 — iOS BaseThemeTests 와 같은 묶음)
// 원본: Sources/CheckMobileKit/Theme/MobileAppearance.swift @ 862be0f (화면 모드 저장값)
//
// 테마 규칙(플랫폼 무관 — 데스크톱·Android 호스트 둘 다에서 돈다).
//  - 글자·부품 대비(WCAG) · M3 역할 48개 전부 손으로 채움(반사 열거, 기준값 누수 0) · 고정 역할은 두 모드 같은 값
//  - 주요색은 iOS 파랑(G §8-15 — §8-13 의 '주요색 = 브랜드 보라'를 뒤집었다): accent 가족 = iOS 값 · M3 primary·secondary 가 그 가족에서 나온다
//    (다크는 글자 accent · 채움 accentFill · 탭 선택 tabSelected 가 갈린다) · 48역할 값 표 · AI 토큰 보라는 primary 와 다른 값이고 나란히 구분된다(CIEDE2000)
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
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

    /**
     * M3 뼈대 글자·부품 대비(G §8-15 — 라이트·다크 각각): 글자로 쓰는 주요색·채움 위 글자·받침 위 글자 4.5:1, 스위치 트랙·테두리는 면 위 3:1(WCAG 1.4.11).
     * M3 가 primary 를 글자로 쓰는 부품(글자 단추·대화상자 단추)과 secondary 를 글자로 쓰는 탭 막대 선택 글자를 그 부품이 놓이는 면 위에서 잰다.
     * 잰 값은 AINGCHECK-CONTRAST 줄로 남긴다(보고서 근거).
     */
    @Test
    fun materialRolesKeepContrast() {
        val failures = mutableListOf<String>()
        for (dark in listOf(false, true)) {
            val s = AingColorScheme.of(dark)
            val c = AingColors.of(dark)
            val mode = if (dark) "다크" else "라이트"
            val card = AingPalette.surface.pick(dark).toColor()
            fun need(name: String, fg: Color, bg: Color, min: Double) {
                val r = fg.rgb().contrast(bg.rgb())
                println("AINGCHECK-CONTRAST $mode $name = ${r2(r)} (≥ $min)")
                if (r < min) failures += "$mode $name = ${r2(r)} < $min"
            }
            // 글자로 쓰는 주요색(글자 단추·링크·대화상자 단추): 바탕·카드·대화상자 면 위.
            need("primary on surface(M3)", s.primary, s.surface, 4.5)
            need("primary on background", s.primary, s.background, 4.5)
            need("primary on card", s.primary, card, 4.5)
            need("primary on dialog(surfaceContainerHigh)", s.primary, s.surfaceContainerHigh, 4.5)
            // 채움 위 글자: M3 채운 단추(primary) · 손으로 칠한 채움(accentFill — 보낸 말풍선·체크된 원·초상 붓 원).
            need("onPrimary on primary", s.onPrimary, s.primary, 4.5)
            need("onSecondary on secondary", s.onSecondary, s.secondary, 4.5)
            need("onAccentFill on accentFill", c.onAccentFill, c.accentFill, 4.5)
            // 받침 위 글자: 탭 선택 알약(secondaryContainer) 위 선택 글자·기호, 토널 단추.
            need("tabSelected on 선택 알약(secondaryContainer)", c.tabSelected, s.secondaryContainer, 4.5)
            need("onSecondaryContainer on secondaryContainer", s.onSecondaryContainer, s.secondaryContainer, 4.5)
            need("onPrimaryContainer on primaryContainer", s.onPrimaryContainer, s.primaryContainer, 4.5)
            // 탭 막대 선택 글자(M3 NavigationBar 는 secondary 를 막대 면 위에 쓴다).
            need("secondary(탭 선택 글자) on 탭 막대(surfaceContainer)", s.secondary, s.surfaceContainer, 4.5)
            need("onSurface on surface", s.onSurface, s.surface, 4.5)
            need("onSurfaceVariant on sheet(surfaceContainerLow)", s.onSurfaceVariant, s.surfaceContainerLow, 4.5)
            need("onError on error", s.onError, s.error, 4.5)
            // 반대 면(스낵바): 글자와 동작 글자(M3 SnackbarTokens — 동작은 inversePrimary).
            need("inverseOnSurface(스낵바 글자) on inverseSurface", s.inverseOnSurface, s.inverseSurface, 4.5)
            need("inversePrimary(스낵바 동작) on inverseSurface", s.inversePrimary, s.inverseSurface, 4.5)
            // 부품(글자 아님): 스위치 켠 트랙·켠 체크 칸·고른 라디오·슬라이더 채운 트랙(primary) · 테두리 · 빈 체크·라디오 테두리(onSurfaceVariant).
            // 빈 트랙(슬라이더·진행 표시 = secondaryContainer)은 재지 않는다: §8-15 받침 정의(accentTint 겹침)를 따르면 카드 위 1.15:1 · 다크 1.21:1 로
            // M3 기준 팔레트(1.23:1)·iOS 슬라이더 빈 트랙과 같은 결이다 — 값은 채운 트랙·손잡이가 알린다(xplat/int-c 마무리 결정).
            need("primary(스위치 트랙·체크·라디오·슬라이더) on card", s.primary, card, 3.0)
            need("outline on card", s.outline, card, 3.0)
            need("onSurfaceVariant(빈 체크·라디오 테두리) on card", s.onSurfaceVariant, card, 3.0)
            // 고정 역할: on…Fixed 는 …Fixed·…FixedDim 위, on…FixedVariant 는 …Fixed 위 4.5:1.
            for ((name, fixed, dim, on, onVariant) in listOf(
                FixedSet("primary", s.primaryFixed, s.primaryFixedDim, s.onPrimaryFixed, s.onPrimaryFixedVariant),
                FixedSet("secondary", s.secondaryFixed, s.secondaryFixedDim, s.onSecondaryFixed, s.onSecondaryFixedVariant),
                FixedSet("tertiary", s.tertiaryFixed, s.tertiaryFixedDim, s.onTertiaryFixed, s.onTertiaryFixedVariant),
            )) {
                need("on${name}Fixed/${name}Fixed", on, fixed, 4.5)
                need("on${name}Fixed/${name}FixedDim", on, dim, 4.5)
                need("on${name}FixedVariant/${name}Fixed", onVariant, fixed, 4.5)
            }
        }
        assertTrue(failures.isEmpty(), "대비 부족:\n" + failures.joinToString("\n"))
    }

    private data class FixedSet(val name: String, val fixed: Color, val dim: Color, val on: Color, val onVariant: Color)

    /**
     * 동적 색 없음 + 기본 보라(baseline) 새어 듦 없음: M3 역할을 **반사로 전부 열거해**(손 목록이 아니다) 기준값과 대조한다.
     * material3 1.9.0(데스크톱)·androidx 1.4.0(Android) 의 ColorScheme 은 48역할 — 판이 올라 역할이 늘면 수가 달라져 빨강이다.
     * 기준값과 같을 수 있는 자리는 설계상 같은 값인 곳뿐이다: 스크림(검정)과 라이트의 흰 자리(채움 위 흰 글자 · 가장 낮은 면 = 흰 카드).
     */
    @Test
    fun everyMaterialRoleIsFilledByAingNotBaseline() {
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
            assertEquals(Color.Transparent, ours.surfaceTint, "표면 틴트는 투명(iOS 처럼 평평한 면 — 올림 그림자에 색이 끼지 않게)")
        }
        assertTrue(leaked.isEmpty(), "M3 기준 색이 새어 들었다:\n" + leaked.joinToString("\n"))
        // iOS 파랑이 실제로 뼈대를 칠한다(기대값은 Swift MobileThemePalette.accent 의 숫자).
        assertEquals(AingRgb.hex(0x1864CF).toColor(), AingColorScheme.Light.primary)
        assertEquals(AingRgb(0.33, 0.67, 1.0).toColor(), AingColorScheme.Dark.primary)
        assertEquals(AingPalette.background.dark.toColor(), AingColorScheme.Dark.background)
        assertEquals(AingPalette.danger.light.toColor(), AingColorScheme.Light.error)
    }

    /**
     * M3 역할 48개 × 두 모드의 값 표(G §8-15). 기대값은 손으로 적은 ARGB 다 — Swift MobileThemePalette 숫자를 §8-15 매핑대로 겹쳐
     * 따로 계산해 적었고(반투명 토큰은 카드·바탕 위에 겹친 값), 한 칸씩 눈으로 읽어 보라가 없는지 확인했다:
     * 파랑 = 1864CF·54ABFF·7DC0FF·E8F0FA·303C52 · 남색 1A1A2E · 초록 127A51·59E0A1·E2F7ED·31474B · 빨강 C83238·FF7375·FAEBEB·3C3442 · 나머지는 회색·남색 면.
     * 표의 이름 집합은 반사 열거와 같아야 한다(역할이 늘면 표도 빨강).
     */
    @Test
    fun everyMaterialRoleMatchesTheTable() {
        val roles = materialColorRoles()
        assertEquals(ROLE_TABLE.keys.sorted(), roles.map { it.name }.sorted(), "역할 표와 반사 열거의 이름 집합이 다르다")
        val wrong = mutableListOf<String>()
        for (role in roles) {
            val (light, dark) = ROLE_TABLE.getValue(role.name)
            for ((mode, scheme, want) in listOf(Triple("라이트", AingColorScheme.Light, light), Triple("다크", AingColorScheme.Dark, dark))) {
                val got = role.read(scheme).toArgb()
                if (got != want) wrong += "$mode ${role.name}: 표 #${argbHex(want)} · 실제 #${argbHex(got)}"
            }
        }
        assertTrue(wrong.isEmpty(), "M3 역할 값이 표와 다르다:\n" + wrong.joinToString("\n"))
    }

    /** M3 정의: 고정 역할은 밝음·어두움에서 같은 값이다(두 모드 사이를 오가도 고정 받침이 그대로). */
    @Test
    fun fixedRolesAreTheSameInBothModes() {
        val roles = materialColorRoles().filter { it.name in FIXED_ROLES }
        assertEquals(FIXED_ROLES.size, roles.size)
        val differ = roles.filter { it.read(AingColorScheme.Light) != it.read(AingColorScheme.Dark) }.map { it.name }
        assertTrue(differ.isEmpty(), "라이트·다크가 다른 고정 역할: $differ")
        // 고정 primary 가족은 파랑 가족이다(G §8-15): 고정 받침 = 다크 primary(밝은 파랑) · 그 위 글자 = 짙은 남색 · 변형 글자 = 라이트 primary.
        assertEquals(AingRgb(0.33, 0.67, 1.0).toColor(), AingColorScheme.Light.primaryFixedDim)
        assertEquals(AingRgb.hex(0x1A1A2E).toColor(), AingColorScheme.Dark.onPrimaryFixed)
        assertEquals(AingRgb.hex(0x1864CF).toColor(), AingColorScheme.Dark.onSecondaryFixedVariant)
    }

    /**
     * 주요색은 iOS 파랑(G §8-15): accent 가족 여섯 토큰이 iOS 값 그대로이고, M3 primary·secondary 가 그 가족에서 나온다.
     * 라이트는 글자·채움·탭 선택이 한 값(#1864CF)이고, 다크는 셋이 갈린다(글자 = 밝은 파랑 · 채움 = #2A74DE · 탭 선택 = #7DC0FF).
     * 기대값은 Swift MobileThemePalette 의 숫자를 손으로 옮긴 것이다(구현 식을 다시 쓰지 않는다).
     */
    @Test
    fun primaryFamilyIsIosBlue() {
        val white = AingRgb.hex(0xFFFFFF).toColor()
        val l = AingColors.Light
        val ls = AingColorScheme.Light
        val lightBlue = AingRgb.hex(0x1864CF).toColor()
        assertEquals(lightBlue, l.accent, "라이트 accent")
        assertEquals(lightBlue, l.accentFill, "라이트 accentFill")
        assertEquals(lightBlue, l.tabSelected, "라이트 tabSelected")
        assertEquals(lightBlue, ls.primary, "라이트 primary")
        assertEquals(lightBlue, ls.secondary, "라이트 secondary(탭 선택 글자)")
        assertEquals(l.accentFill, ls.primary, "라이트: 채운 단추(primary) = 손으로 칠한 채움(accentFill)")
        assertEquals(white, l.onAccentFill, "라이트 onAccentFill")
        assertEquals(white, ls.onPrimary, "라이트 onPrimary 흰색")

        val d = AingColors.Dark
        val ds = AingColorScheme.Dark
        assertEquals(AingRgb(0.33, 0.67, 1.0).toColor(), d.accent, "다크 accent")
        assertEquals(d.accent, ds.primary, "다크 primary = accent(글자로도 쓰는 밝은 파랑)")
        assertEquals(AingRgb.hex(0x2A74DE).toColor(), d.accentFill, "다크 accentFill")
        assertNotEquals(ds.primary, d.accentFill, "다크: accentFill(#2A74DE)은 카드 위 글자 대비가 모자라 primary 가 아니다")
        assertEquals(AingRgb.hex(0x7DC0FF).toColor(), d.tabSelected, "다크 tabSelected(iOS 그대로)")
        assertNotEquals(ds.primary, d.tabSelected, "다크 tabSelected 는 primary 보다 한 단계 밝다")
        assertEquals(d.tabSelected, ds.secondary, "다크 secondary = 탭 선택 글자")
        assertEquals(d.tabSelected, ds.onSecondaryContainer, "다크 선택 알약 위 기호 = 탭 선택색")
        assertEquals(white, d.onAccentFill, "다크 onAccentFill 흰색(채움은 #2A74DE)")
        assertEquals(AingRgb.hex(0x1A1A2E).toColor(), ds.onPrimary, "다크 onPrimary = 짙은 남색(밝은 파랑 위)")

        // 틴트·테두리는 iOS 불투명도 그대로(라이트 10%·30% · 다크 11%·38%), 색은 accent.
        assertEquals(AingRgb.hex(0x1864CF, 0.10).toColor(), l.accentTint)
        assertEquals(AingRgb.hex(0x1864CF, 0.30).toColor(), l.accentLine)
        assertEquals(AingRgb(0.33, 0.67, 1.0, 0.11).toColor(), d.accentTint)
        assertEquals(AingRgb(0.33, 0.67, 1.0, 0.38).toColor(), d.accentLine)
        // 받침(탭 선택 알약·토널 단추) = accentTint 를 카드 위에 겹친 값: 라이트 #E8F0FA · 다크 #303C52(손으로 겹쳐 적은 값).
        assertEquals(0xFFE8F0FA.toInt(), ls.secondaryContainer.toArgb())
        assertEquals(0xFF303C52.toInt(), ds.secondaryContainer.toArgb())
    }

    /**
     * AI 토큰 보라(iOS 값 그대로)는 primary(iOS 파랑)와 **다른 값**이고 나란히 놓여도 구분된다: CIEDE2000 ≥ [ColorDifference.SIDE_BY_SIDE_DISTINCT].
     * (진열장 "뜻 색" 줄에서 선택·AI 토큰 점이 나란히 있다.)
     */
    @Test
    fun aiTokenPurpleIsDistinctFromPrimarySideBySide() {
        for (dark in listOf(false, true)) {
            val ai = AingPalette.aiToken.pick(dark)
            val primary = AingPalette.accent.pick(dark)
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

    private fun argbHex(v: Int): String = (v.toLong() and 0xFFFFFFFFL).toString(16).uppercase().padStart(8, '0')

    private companion object {
        const val EXPECTED_ROLE_COUNT = 48

        /** 역할 → (라이트 ARGB, 다크 ARGB). G §8-15 매핑을 Swift 숫자로 따로 계산해 손으로 적은 값(위 everyMaterialRoleMatchesTheTable). */
        val ROLE_TABLE: Map<String, Pair<Int, Int>> = mapOf(
            "background" to (0xFFF2F2F7 to 0xFF1A1C26),
            "error" to (0xFFC83238 to 0xFFFF7375),
            "errorContainer" to (0xFFFAEBEB to 0xFF3C3442),
            "inverseOnSurface" to (0xFFFFFFFF to 0xFF0B0B10),
            "inversePrimary" to (0xFF54ABFF to 0xFF1864CF),
            "inverseSurface" to (0xFF2B2E3D to 0xFFF2F2F7),
            "onBackground" to (0xFF0B0B10 to 0xFFF4F5F5),
            "onError" to (0xFFFFFFFF to 0xFF1A1A2E),
            "onErrorContainer" to (0xFFC83238 to 0xFFFF7375),
            "onPrimary" to (0xFFFFFFFF to 0xFF1A1A2E),
            "onPrimaryContainer" to (0xFF1864CF to 0xFF7DC0FF),
            "onPrimaryFixed" to (0xFF1A1A2E to 0xFF1A1A2E),
            "onPrimaryFixedVariant" to (0xFF1864CF to 0xFF1864CF),
            "onSecondary" to (0xFFFFFFFF to 0xFF1A1A2E),
            "onSecondaryContainer" to (0xFF1864CF to 0xFF7DC0FF),
            "onSecondaryFixed" to (0xFF1A1A2E to 0xFF1A1A2E),
            "onSecondaryFixedVariant" to (0xFF1864CF to 0xFF1864CF),
            "onSurface" to (0xFF0B0B10 to 0xFFF4F5F5),
            "onSurfaceVariant" to (0xFF6F6F74 to 0xFFA6A8B3),
            "onTertiary" to (0xFFFFFFFF to 0xFF1A1A2E),
            "onTertiaryContainer" to (0xFF127A51 to 0xFF59E0A1),
            "onTertiaryFixed" to (0xFF1A1A2E to 0xFF1A1A2E),
            "onTertiaryFixedVariant" to (0xFF127A51 to 0xFF127A51),
            "outline" to (0xFF6F6F74 to 0xFFA6A8B3),
            "outlineVariant" to (0xFFDEDEDF to 0xFF404350),
            "primary" to (0xFF1864CF to 0xFF54ABFF),
            "primaryContainer" to (0xFFE8F0FA to 0xFF303C52),
            "primaryFixed" to (0xFFE8F0FA to 0xFFE8F0FA),
            "primaryFixedDim" to (0xFF54ABFF to 0xFF54ABFF),
            "scrim" to (0xFF000000 to 0xFF000000),
            "secondary" to (0xFF1864CF to 0xFF7DC0FF),
            "secondaryContainer" to (0xFFE8F0FA to 0xFF303C52),
            "secondaryFixed" to (0xFFE8F0FA to 0xFFE8F0FA),
            "secondaryFixedDim" to (0xFF54ABFF to 0xFF54ABFF),
            "surface" to (0xFFF2F2F7 to 0xFF1A1C26),
            "surfaceBright" to (0xFFFFFFFF to 0xFF353848),
            "surfaceContainer" to (0xFFFCFCFD to 0xFF2F3144),
            "surfaceContainerHigh" to (0xFFFFFFFF to 0xFF353848),
            "surfaceContainerHighest" to (0xFFF4F4F8 to 0xFF353848),
            "surfaceContainerLow" to (0xFFFFFFFF to 0xFF2B2E3D),
            "surfaceContainerLowest" to (0xFFFFFFFF to 0xFF1A1C26),
            "surfaceDim" to (0xFFF2F2F7 to 0xFF1A1C26),
            "surfaceTint" to (0x00000000L to 0x00000000L),
            "surfaceVariant" to (0xFFF4F4F8 to 0xFF353848),
            "tertiary" to (0xFF127A51 to 0xFF59E0A1),
            "tertiaryContainer" to (0xFFE2F7ED to 0xFF31474B),
            "tertiaryFixed" to (0xFFE2F7ED to 0xFFE2F7ED),
            "tertiaryFixedDim" to (0xFF59E0A1 to 0xFF59E0A1),
        ).mapValues { (_, v) -> v.first.toInt() to v.second.toInt() }
        val FIXED_ROLES = listOf("primary", "secondary", "tertiary").flatMap { r ->
            val cap = r.replaceFirstChar { it.uppercaseChar() }
            listOf("${r}Fixed", "${r}FixedDim", "on${cap}Fixed", "on${cap}FixedVariant")
        }
    }
}
