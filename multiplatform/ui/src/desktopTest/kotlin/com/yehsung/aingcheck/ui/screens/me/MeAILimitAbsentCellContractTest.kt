// 원본: Tests/CheckMobileKitTests/MeAILimitsTests.swift(columnPaletteIsOneTableAcrossSurfaces ⓓⓔⓕ · absentCellSaysWhyAndKeepsItsCueWithoutColor ⑤) ·
//       Sources/CheckMobileShared/AILimitColumnStyle.swift @ 4137751e
// 없는 칸 계약(docs/plan/ai-limit-absent-cell-contract.md): 글자가 읽히되 숫자보다 조용하다 · 새 회색이 아니다 · 해치는 공유 세 수 · 없는 칸만 받는다.
// 값은 Swift 원문을 읽어 대조한다(두 벌 유지). 부르는 자리는 소스로 잰다 — "상수가 있다"는 "그 칸에 사선이 깔린다"의 증거가 아니다. 그림은 스냅숏(me-ailimits-absent-*)이 잰다.
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.ui.graphics.Color
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingPalette
import com.yehsung.aingcheck.ui.theme.AingRgb
import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MeAILimitAbsentCellContractTest {
    private val swift = SwiftStyleComments.strip(RepoFiles.readText("Sources/CheckMobileShared/AILimitColumnStyle.swift"))
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private val card = SwiftStyleComments.strip(File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/me/MeAILimitsCard.kt").readText())

    private fun swiftPair(name: String): Pair<Int, Int> {
        val m = assertNotNull(Regex("""$name = Pair\(light: 0x([0-9A-F_]+), dark: 0x([0-9A-F_]+)\)""").find(swift), "Swift 에서 $name 을 못 읽었다")
        return m.groupValues[1].replace("_", "").toInt(16) to m.groupValues[2].replace("_", "").toInt(16)
    }

    private fun swiftDouble(name: String): Double =
        assertNotNull(Regex("""static let $name = ([0-9.]+)""").find(swift), "Swift 에서 $name 을 못 읽었다").groupValues[1].toDouble()

    private fun Color.rgb() = AingRgb(red.toDouble(), green.toDouble(), blue.toDouble())

    @Test
    fun absentColorsAndHatchNumbersMatchTheSwiftTable() {
        val (light, dark) = swiftPair("absentText")
        assertEquals(0x717176, light, "대조: Swift 승인본")
        assertEquals(0x9798A4, dark, "대조: Swift 승인본")
        assertEquals(Color(0xFF000000 or light.toLong()), MeAILimitColumnColor.absentText(AingColors.Light))
        assertEquals(Color(0xFF000000 or dark.toLong()), MeAILimitColumnColor.absentText(AingColors.Dark))
        val (trackLight, trackDark) = swiftPair("absentTrack")
        assertEquals(Color(0xFF000000 or trackLight.toLong()), MeAILimitColumnColor.absentTrack(AingColors.Light))
        assertEquals(Color(0xFF000000 or trackDark.toLong()), MeAILimitColumnColor.absentTrack(AingColors.Dark))
        assertEquals(swiftDouble("absentHatchSpacing"), MeAILimitColumnColor.absentHatchSpacing)
        assertEquals(swiftDouble("absentHatchLineWidth"), MeAILimitColumnColor.absentHatchLineWidth)
        assertEquals(swiftDouble("absentHatchOpacity"), MeAILimitColumnColor.absentHatchOpacity)
        assertEquals(4.0, MeAILimitColumnColor.absentHatchSpacing)
        assertEquals(1.0, MeAILimitColumnColor.absentHatchLineWidth)
        assertEquals(0.45, MeAILimitColumnColor.absentHatchOpacity)
        // 해치는 `없음` 글자와 같은 잉크에 알파만 다르다(셋째 색이 아니다).
        val hatch = MeAILimitColumnColor.absentHatch(AingColors.Dark)
        assertEquals(MeAILimitColumnColor.absentText(AingColors.Dark).copy(alpha = 1f), hatch.copy(alpha = 1f))
        assertEquals(0.45f, hatch.alpha, 0.01f)
    }

    /** `4.5 ≤ 없음 대비 < 숫자 대비`(옛 단언은 `< 4.5` 로 읽히는 것을 금지했고 그 금지가 다크 2.06:1 을 낳았다) · 새 회색이 아니라 label3Text 합성값 · 위젯 바탕에서도 읽힌다. */
    @Test
    fun absentTextIsReadableButQuieterThanTheNumber() {
        val surface = AingPalette.surface
        val widget = AingPalette.widgetBackground
        for ((name, ink, number, backdrop, widgetBackdrop) in listOf(
            Quint("라이트", AingRgb.hex(0x717176), AingPalette.label.light, surface.light, widget.light),
            Quint("다크", AingRgb.hex(0x9798A4), AingPalette.label.dark, surface.dark, widget.dark),
        )) {
            val ratio = ink.contrast(backdrop)
            assertTrue(ratio >= 4.5, "`없음` 글자가 $name $ratio:1 로 안 읽힌다")
            assertTrue(ratio < number.contrast(backdrop), "`없음`($name $ratio:1)이 숫자만큼 눈에 띈다")
            val onWidget = ink.contrast(widgetBackdrop)
            assertTrue(onWidget >= 4.5, "위젯 바탕에서 `없음` 글자가 $name $onWidget:1 다")
            assertTrue(onWidget < number.contrast(widgetBackdrop), "위젯에서 `없음` 이 숫자만큼 눈에 띈다")
        }
        assertEquals(0x717176, AingPalette.label3Text.light.compositedOver(surface.light).hex, "없는 칸 라이트 글자가 label3Text 합성값이 아니다")
        assertEquals(0x9798A4, AingPalette.label3Text.dark.compositedOver(surface.dark).hex, "없는 칸 다크 글자가 label3Text 합성값이 아니다")
        assertEquals(Color(0xFF9798A4).rgb().hex, MeAILimitColumnColor.absentText(AingColors.Dark).rgb().hex)
    }

    private data class Quint(val name: String, val ink: AingRgb, val number: AingRgb, val backdrop: AingRgb, val widgetBackdrop: AingRgb)

    /** 왼쪽 밖에서 시작해 45°(가로 = 세로)로 오른쪽 끝까지 간다 — 캡슐 양끝도 선을 받는다. */
    @Test
    fun hatchStartsLeftOfTheCapsuleAndCoversTheWidth() {
        val starts = MeAILimitColumnColor.absentHatchStarts(width = 22f, height = 6f, spacing = 4f)
        assertEquals(listOf(-6f, -2f, 2f, 6f, 10f, 14f, 18f), starts)
        assertEquals(emptyList(), MeAILimitColumnColor.absentHatchStarts(22f, 6f, 0f), "간격 0 이면 끝나지 않는다")
        assertTrue(MeAILimitColumnColor.absentHatchSpacing > MeAILimitColumnColor.absentHatchLineWidth, "사선 간격이 굵기보다 좁으면 '꽉 찬 바'로 보인다")
    }

    /** 부르는 자리: 바 둘(격자 · 큰 글자)이 깃발을 `display == null` 로 넘기고, 바는 그 안에서만 해치를 깐다. 깃발에 기본값이 없다. */
    @Test
    fun bothCallSitesPassAbsenceByDisplayNullOnly() {
        val calls = Regex("""(?<!fun )MeAILimitBar\(""").findAll(card).count()
        assertEquals(2, calls, "폰 카드의 리밋 바는 격자와 큰 글자 쌓은 모양 둘이어야 한다")
        assertEquals(calls, card.split("isAbsent = display == null").size - 1, "바 가운데 '그 창이 없다'를 display == null 로 받지 않는 것이 있다")
        assertFalse("isAbsent = percent" in card || "isAbsent = display?.percent" in card, "없는 칸을 퍼센트로 가른다 — 판정 불가와 0% 칸이 함께 사선을 받는다")
        assertTrue("isAbsent: Boolean, modifier" in card, "바의 isAbsent 에 기본값이 생겼다 — 새 호출부가 조용히 '값이 있는 칸'으로 떨어진다")
        val bar = card.substringAfter("fun MeAILimitBar(")
        assertTrue("if (isAbsent) {" in bar && "clipPath(" in bar, "해치가 isAbsent 밖이거나 캡슐 클립이 없다")
        assertEquals(1, bar.split("drawLine(").size - 1, "바가 사선을 두 자리에서 그린다")
    }

    /** 옛 값이 소스에 안 남았다(구주석 포함 — 옛 대비 수를 근거로 다시 내리는 일이 없게). */
    @Test
    fun oldValuesAreGone() {
        val raw = File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/me/MeAILimitsCard.kt").readText()
        assertFalse("0xFF595E67" in raw || "0xFF9BA1AC" in raw, "옛 없음 글자 값이 코드에 남았다")
        assertFalse("대비 2.1:1 수준" in raw, "옛 주석('가장 조용하다 2.1:1 — 글자를 올리려면…')이 남았다")
    }
}
