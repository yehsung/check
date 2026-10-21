// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift @ 862be0f (title(_:)·sectionTitle·rowTitle·rowSubtitle·chip 의 스타일·굵기)
// 원본: Sources/CheckMobileKit/Components/AingButtons.swift @ 862be0f (작은 단추 글자 .subheadline semibold)
// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 862be0f (지금 탭 타이머 scaledFont(size: 48, weight: .semibold))
//
// 글자 크기 표(AingTypeScale)를 값으로 잰다 — 이 시험이 없을 때 bodyLarge 17→14 · headlineLarge 34/Bold→28/Normal ·
// labelSmall 11→9 를 바꿔도 전부 초록이었다(W1-e 검증 mv4). 기대값은 구현을 베끼지 않고 서로 독립한 두 출처에서 온다:
//  ① 크기·행간 = 애플 HIG "Large(기본)" Dynamic Type 표(iOS 스타일 이름 → pt) — 아래 HIG 상수, 원문 숫자 그대로
//  ② 굵기·스타일 = Swift 원문을 주석 걷어 읽은 값(MobileTheme·AingButtons·NowTab). 원문에 없는 자리(이식 판단)는 PORT 에 따로 적는다.
// 그리고 컴포지션 안에서 aingTypography() 를 꺼내 Typography 의 TextStyle 게터를 **반사로 전부** 열거(15개)해, 역할마다
// 크기·행간·굵기가 표와 같고 글꼴이 번들 Pretendard 다섯 굵기 묶음인지 잰다(기본 글꼴로 새면 빨강).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontListFontFamily
import androidx.compose.ui.text.font.FontWeight
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.fonts.Pretendard
import com.yehsung.aingcheck.ui.fonts.pretendardFontFamily
import java.lang.reflect.Modifier
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

class AingTypographyTest {
    /** 애플 HIG "Large(기본)" iOS Dynamic Type 크기·행간(pt). developer.apple.com/design/human-interface-guidelines/typography */
    private val hig: Map<String, Pair<Float, Float>> = mapOf(
        "largeTitle" to (34f to 41f), "title" to (28f to 34f), "title2" to (22f to 28f), "title3" to (20f to 25f),
        "headline" to (17f to 22f), "body" to (17f to 22f), "callout" to (16f to 21f), "subheadline" to (15f to 20f),
        "footnote" to (13f to 18f), "caption" to (12f to 16f), "caption2" to (11f to 13f),
    )

    /** HIG 표의 기본 굵기(스타일을 굵기 없이 쓰면 이 굵기다). */
    private val higDefaultWeight: Map<String, FontWeight> = hig.keys.associateWith { if (it == "headline") FontWeight.SemiBold else FontWeight.Normal }

    private fun swiftWeight(w: String): FontWeight = when (w) {
        "regular" -> FontWeight.Normal
        "medium" -> FontWeight.Medium
        "semibold" -> FontWeight.SemiBold
        "bold" -> FontWeight.Bold
        "heavy" -> FontWeight.ExtraBold
        else -> fail("모르는 Swift 굵기 .$w")
    }

    /** M3 역할 → (iOS 스타일, 굵기) — 굵기는 Swift 원문에서 읽는다. */
    private fun expectedFromSwift(): Map<String, Triple<Float, Float, FontWeight>> {
        val theme = SwiftPalette.stripComments(RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileTheme.swift"))
        val buttons = SwiftPalette.stripComments(RepoFiles.readText("Sources/CheckMobileKit/Components/AingButtons.swift"))
        val now = SwiftPalette.stripComments(RepoFiles.readText("Sources/CheckMobileKit/Now/NowTab.swift"))
        fun one(re: String, src: String, what: String): MatchResult = Regex(re).find(src) ?: fail("Swift 에서 $what 를 못 읽었다")
        // title(_ style: Font.TextStyle = .title2) -> Font { .system(style, design: .default, weight: .bold) }
        val title = one("""static func title\(_ style: Font\.TextStyle = \.(\w+)\) -> Font \{\s*\.system\(style, design: \.default, weight: \.(\w+)\)""", theme, "title(_:)")
        val titleWeight = swiftWeight(title.groupValues[2])
        assertEquals("title2", title.groupValues[1], "title(_:) 기본 스타일")
        fun swiftLet(name: String): Pair<String, FontWeight> {
            Regex("""static let $name = Font\.system\(\.(\w+), design: \.default, weight: \.(\w+)\)""").find(theme)?.let {
                return it.groupValues[1] to swiftWeight(it.groupValues[2])
            }
            val plain = one("""static let $name = Font\.(\w+)\b""", theme, name)
            return plain.groupValues[1] to higDefaultWeight.getValue(plain.groupValues[1])
        }
        val section = swiftLet("sectionTitle")
        val row = swiftLet("rowTitle")
        val subtitle = swiftLet("rowSubtitle")
        val chip = swiftLet("chip")
        val smallButton = one("""case \.sm: return \.system\(\.(\w+), weight: \.(\w+)\)""", buttons, "작은 단추 글꼴")
        val timer = one("""\.scaledFont\(size: (\d+), weight: \.(\w+)\)""", now, "타이머 글꼴")
        fun fromHig(style: String, weight: FontWeight): Triple<Float, Float, FontWeight> {
            val (size, leading) = hig[style] ?: fail("HIG 표에 .$style 가 없다")
            return Triple(size, leading, weight)
        }
        return mapOf(
            "headlineLarge" to fromHig("largeTitle", titleWeight),
            "headlineMedium" to fromHig("title", titleWeight),
            "headlineSmall" to fromHig(title.groupValues[1], titleWeight),
            "titleLarge" to fromHig(section.first, section.second),
            "titleMedium" to fromHig("headline", higDefaultWeight.getValue("headline")),
            "titleSmall" to fromHig(row.first, row.second),
            "bodyLarge" to fromHig("body", higDefaultWeight.getValue("body")),
            "bodyMedium" to fromHig("subheadline", higDefaultWeight.getValue("subheadline")),
            "bodySmall" to fromHig(subtitle.first, subtitle.second),
            "labelLarge" to fromHig(smallButton.groupValues[1], swiftWeight(smallButton.groupValues[2])),
            "labelMedium" to fromHig("caption", PORT_LABEL_MEDIUM_WEIGHT),
            "labelSmall" to fromHig(chip.first, chip.second),
            "displayLarge" to Triple(timer.groupValues[1].toFloat(), PORT_DISPLAY_LARGE_LEADING, swiftWeight(timer.groupValues[2])),
        ) + PORT_DISPLAY
    }

    @Test
    fun typeScaleMatchesHigTableAndSwiftWeights() {
        val expected = expectedFromSwift()
        assertEquals(15, expected.size, "기대 표가 15역할이 아니다")
        val actual = AingTypeScale.steps.associateBy { it.role }
        assertEquals(expected.keys, actual.keys, "역할 집합")
        val wrong = expected.mapNotNull { (role, e) ->
            val s = actual.getValue(role)
            if (s.size == e.first && s.lineHeight == e.second && s.weight == e.third) null
            else "$role: 표 ${s.size}/${s.lineHeight} ${s.weight.weight} ≠ 기대 ${e.first}/${e.second} ${e.third.weight}"
        }
        assertTrue(wrong.isEmpty(), "글자 크기 표가 HIG·Swift 와 다르다:\n" + wrong.joinToString("\n"))
    }

    /** 앱이 실제로 쓰는 Typography(컴포지션 안 aingTypography())의 15역할 전부: 표 값 그대로 + 글꼴 = Pretendard. */
    @Test
    fun everyRoleOfTheComposedTypographyUsesPretendardAndTheTable() {
        var typography: Typography? = null
        var pretendard: FontFamily? = null
        DesktopSnapshots.render(4, 4, frames = 3) {
            typography = aingTypography()
            pretendard = pretendardFontFamily()
        }
        val typo = assertNotNull(typography, "컴포지션이 돌지 않았다")
        val family = assertNotNull(pretendard)
        val roles = Typography::class.java.methods.filter { m ->
            Modifier.isPublic(m.modifiers) && !Modifier.isStatic(m.modifiers) && m.parameterCount == 0 &&
                m.returnType == TextStyle::class.java && m.name.startsWith("get") && '$' !in m.name
        }.associate { m -> m.name.removePrefix("get").replaceFirstChar { it.lowercaseChar() } to (m.invoke(typo) as TextStyle) }
        assertEquals(15, roles.size, "Typography 공개 역할 수가 바뀌었다(M3 판 변경?): ${roles.keys.sorted()}")
        val table = expectedFromSwift()
        assertEquals(table.keys, roles.keys, "Typography 역할 ↔ 기대 표")
        val faces = Pretendard.faces.map { it.weight }
        val wrong = mutableListOf<String>()
        for ((role, style) in roles.toSortedMap()) {
            val (size, leading, weight) = table.getValue(role)
            if (style.fontSize.value != size || style.lineHeight.value != leading || style.fontWeight != weight) {
                wrong += "$role: ${style.fontSize}/${style.lineHeight} ${style.fontWeight} ≠ $size/$leading ${weight.weight}"
            }
            val f = style.fontFamily
            if (f !is FontListFontFamily || f.fonts.map { it.weight } != faces || f != family) {
                wrong += "$role: 글꼴이 Pretendard 묶음이 아니다($f)"
            }
        }
        assertTrue(wrong.isEmpty(), "aingTypography():\n" + wrong.joinToString("\n"))
        // 비교 대상이 정말 Pretendard 다: 묶음의 글꼴 다섯이 번들 리소스(pretendard_*.otf)를 가리킨다.
        val fonts = (family as FontListFontFamily).fonts.map { it.toString() }
        assertTrue(fonts.size == 5 && fonts.all { "pretendard_" in it }, "Pretendard 묶음이 번들 글꼴을 가리키지 않는다: $fonts")
    }

    private companion object {
        /** 이식 판단(iOS 원본 없음): caption1 자리 라벨은 칩처럼 semibold. */
        val PORT_LABEL_MEDIUM_WEIGHT = FontWeight.SemiBold
        /** 이식 판단: 타이머 48 의 행간. */
        const val PORT_DISPLAY_LARGE_LEADING = 56f
        /** 이식 판단: 48 과 largeTitle 34 사이 표시 글자 계단(iOS 원본 없음). */
        val PORT_DISPLAY = mapOf(
            "displayMedium" to Triple(40f, 48f, FontWeight.SemiBold),
            "displaySmall" to Triple(36f, 43f, FontWeight.SemiBold),
        )
    }
}
