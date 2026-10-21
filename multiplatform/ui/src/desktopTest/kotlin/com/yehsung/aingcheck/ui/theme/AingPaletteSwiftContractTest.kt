// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f
// 원본: Sources/check/CheckGachaWindow.swift @ 862be0f (GachaWindowPalette)
//
// "iOS/맥 값 그대로"를 값으로 잰다: Swift 원문(MobileThemePalette.swift · CheckGachaWindow.swift)을 읽어 토큰마다 Kotlin 값과 대조한다.
// 원본 색이 바뀌거나 토큰이 늘고 줄면 이 시험이 먼저 빨개진다(두 벌 유지 — G §5-4). 주석은 걷어 내고 본다
// (기억 source-contract-tests-need-comment-stripping).
// 예외(G §8-13): accent 가족 여섯 토큰은 iOS 파랑 대신 M3 primary(브랜드 보라) — 값 대조 대신 "Swift 파랑이 Kotlin 어디에도 없다 ·
// 불투명도는 iOS 그대로"를 잰다(규칙 쪽 "accent = primary" 는 commonTest AingThemeRulesTest).
package com.yehsung.aingcheck.ui.theme

import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class AingPaletteSwiftContractTest {
    private val kotlinPairs: Map<String, AingPair> = mapOf(
        "background" to AingPalette.background, "surface" to AingPalette.surface, "surface2" to AingPalette.surface2,
        "fill" to AingPalette.fill, "fill2" to AingPalette.fill2, "separator" to AingPalette.separator,
        "glass" to AingPalette.glass, "glassLine" to AingPalette.glassLine, "bubbleIn" to AingPalette.bubbleIn,
        "label" to AingPalette.label, "label2" to AingPalette.label2, "label3" to AingPalette.label3, "label3Text" to AingPalette.label3Text,
        "accent" to AingPalette.accent, "accentFill" to AingPalette.accentFill, "accentTint" to AingPalette.accentTint,
        "accentLine" to AingPalette.accentLine, "onAccentFill" to AingPalette.onAccentFill, "tabSelected" to AingPalette.tabSelected,
        "working" to AingPalette.working, "workingDot" to AingPalette.workingDot, "workingTint" to AingPalette.workingTint,
        "offWork" to AingPalette.offWork, "offWorkDot" to AingPalette.offWorkDot,
        "pending" to AingPalette.pending, "pendingDot" to AingPalette.pendingDot, "pendingTint" to AingPalette.pendingTint,
        "danger" to AingPalette.danger, "dangerTint" to AingPalette.dangerTint, "aiToken" to AingPalette.aiToken, "badge" to AingPalette.badge,
        "gold" to AingPalette.gold, "silver" to AingPalette.silver, "bronze" to AingPalette.bronze,
        "goldInk" to AingPalette.goldInk, "silverInk" to AingPalette.silverInk, "bronzeInk" to AingPalette.bronzeInk,
        "crownInk" to AingPalette.crownInk, "widgetBackground" to AingPalette.widgetBackground,
    )

    @Test
    fun everySwiftPairTokenMatchesKotlinBothWays() {
        val swift = SwiftPalette.parse(RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileThemePalette.swift"))
        assertTrue(swift.pairs.size >= 39, "Swift 토큰을 ${swift.pairs.size}개만 읽었다 — 파서가 원문을 못 읽는다")
        assertEquals(swift.pairs.keys.sorted(), kotlinPairs.keys.sorted(), "토큰 이름 집합이 다르다(빠짐·고아)")
        val wrong = swift.pairs.filterKeys { it !in PRIMARY_SUBSTITUTED }.mapNotNull { (name, pair) ->
            val k = kotlinPairs.getValue(name)
            if (k.light.approximatelyEquals(pair.light) && k.dark.approximatelyEquals(pair.dark)) null else "$name: Swift=$pair Kotlin=$k"
        }
        assertTrue(wrong.isEmpty(), "Swift 와 값이 다르다:\n" + wrong.joinToString("\n"))
    }

    /**
     * G §8-13 대체를 결과로 잰다: Swift accent 가족의 색(파랑)이 Kotlin 토큰·M3 역할 **어디에도 없다**(한 자리라도 iOS 파랑을
     * 베껴 두면 주요색이 둘이 된다). 틴트·테두리의 불투명도는 iOS 와 같다(옅기는 그대로, 색만 바꾼다).
     */
    @Test
    fun accentFamilyIsReplacedByPrimaryAndNoIosBlueRemains() {
        val swift = SwiftPalette.parse(RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileThemePalette.swift")).pairs
        assertTrue(PRIMARY_SUBSTITUTED.all { it in swift }, "Swift 에 대체할 토큰이 없다: ${PRIMARY_SUBSTITUTED - swift.keys}")
        val white = AingRgb.hex(0xFFFFFF)
        val iosBlues = PRIMARY_SUBSTITUTED.flatMap { listOf(swift.getValue(it).light, swift.getValue(it).dark) }
            .map { it.opacity(1.0) }.filter { !it.approximatelyEquals(white) }
            .fold(emptyList<AingRgb>()) { acc, c -> if (acc.any { it.approximatelyEquals(c) }) acc else acc + c }
        // #1864CF · (0.33, 0.67, 1.0) · #2A74DE · #7DC0FF — 파서가 넷을 다 읽었는지.
        assertEquals(4, iosBlues.size, "Swift accent 가족의 파랑을 ${iosBlues.size}개 읽었다: $iosBlues")
        fun isIosBlue(c: AingRgb) = iosBlues.any { it.approximatelyEquals(c.opacity(1.0), 1.0 / 512) }
        val inPalette = kotlinPairs.flatMap { (name, pair) ->
            listOf("$name.light" to pair.light, "$name.dark" to pair.dark).filter { isIosBlue(it.second) }.map { it.first }
        }
        assertTrue(inPalette.isEmpty(), "Kotlin 토큰에 iOS 파랑이 남았다: $inPalette")
        val inScheme = listOf(false, true).flatMap { dark ->
            materialColorRoles().filter { role ->
                val c = role.read(AingColorScheme.of(dark))
                isIosBlue(AingRgb(c.red.toDouble(), c.green.toDouble(), c.blue.toDouble()))
            }.map { "${if (dark) "다크" else "라이트"} ${it.name}" }
        }
        assertTrue(inScheme.isEmpty(), "M3 역할에 iOS 파랑이 있다: $inScheme")
        for (name in listOf("accentTint", "accentLine")) {
            val s = swift.getValue(name)
            val k = kotlinPairs.getValue(name)
            assertEquals(s.light.alpha, k.light.alpha, "$name 라이트 불투명도")
            assertEquals(s.dark.alpha, k.dark.alpha, "$name 다크 불투명도")
            assertTrue(k.light.opacity(1.0).approximatelyEquals(AingPalette.brandInk.light), "$name 라이트 색 = primary")
            assertTrue(k.dark.opacity(1.0).approximatelyEquals(AingPalette.brandInk.dark), "$name 다크 색 = primary")
        }
    }

    @Test
    fun gradientsAndBrandScalarsMatch() {
        val swift = SwiftPalette.parse(RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileThemePalette.swift"))
        fun same(name: String, k: List<AingRgb>) {
            val s = swift.arrays[name] ?: fail("Swift 에 $name 배열이 없다")
            assertEquals(s.size, k.size, "$name 길이")
            s.zip(k).forEachIndexed { i, (a, b) -> assertTrue(a.approximatelyEquals(b), "$name[$i]: Swift=$a Kotlin=$b") }
        }
        same("gaugeStops", AingPalette.gaugeStops)
        same("startStops", AingPalette.startStops)
        same("woodStops", AingPalette.woodStops)
        assertTrue(swift.scalars.getValue("brandNavy").approximatelyEquals(AingPalette.brandNavy))
        assertTrue(swift.scalars.getValue("brandLavender").approximatelyEquals(AingPalette.brandLavender))
        val inks = swift.pairArrays.getValue("avatarInks")
        assertEquals(inks.size, AingPalette.avatarInks.size)
        inks.zip(AingPalette.avatarInks).forEachIndexed { i, (s, k) ->
            assertTrue(s.light.approximatelyEquals(k.light) && s.dark.approximatelyEquals(k.dark), "avatarInks[$i]: Swift=$s Kotlin=$k")
        }
    }

    @Test
    fun brandPurpleComesFromMacGachaWindowPalette() {
        val src = SwiftPalette.stripComments(RepoFiles.readText("Sources/check/CheckGachaWindow.swift"))
        fun hexColor(block: String, field: String): AingRgb {
            val m = Regex("""\b$field:\s*Color\(red:\s*0x([0-9A-Fa-f]{2})\s*/\s*255,\s*green:\s*0x([0-9A-Fa-f]{2})\s*/\s*255,\s*blue:\s*0x([0-9A-Fa-f]{2})\s*/\s*255\)""")
                .find(block) ?: fail("GachaWindowPalette $field 를 못 읽었다")
            return AingRgb.rgb255(m.groupValues[1].toInt(16), m.groupValues[2].toInt(16), m.groupValues[3].toInt(16))
        }
        val light = Regex("""static let light = GachaWindowPalette\((.*?)\n\s*rainbow:""", RegexOption.DOT_MATCHES_ALL).find(src)?.groupValues?.get(1)
            ?: fail("GachaWindowPalette.light 를 못 찾았다")
        val night = Regex("""static let night = GachaWindowPalette\((.*?)\n\s*rainbow:""", RegexOption.DOT_MATCHES_ALL).find(src)?.groupValues?.get(1)
            ?: fail("GachaWindowPalette.night 를 못 찾았다")
        assertTrue(hexColor(light, "ink").approximatelyEquals(AingPalette.brandInk.light), "brandInk.light")
        assertTrue(hexColor(night, "ink").approximatelyEquals(AingPalette.brandInk.dark), "brandInk.dark")
        assertTrue(hexColor(light, "title").approximatelyEquals(AingPalette.brandTitle.light), "brandTitle.light")
        assertTrue(hexColor(night, "title").approximatelyEquals(AingPalette.brandTitle.dark), "brandTitle.dark")
        assertTrue(hexColor(night, "card").approximatelyEquals(AingPalette.brandCard.dark), "brandCard.dark")
        assertTrue(Regex("""card:\s*Color\.white\.opacity\(0\.97\)""").containsMatchIn(light), "brandCard.light = 흰색 97%")
        assertEquals(0.97, AingPalette.brandCard.light.alpha)
    }

    /** 파서가 값을 실제로 본다: 원문 숫자 하나를 바꾸면 그 토큰이 어긋난다(심은 결함). */
    @Test
    fun parserSeesAPlantedChange() {
        val original = RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileThemePalette.swift")
        val planted = original.replace("background = Pair(light: RGB(hex: 0xF2F2F7)", "background = Pair(light: RGB(hex: 0xF2F2F8)")
        assertTrue(planted != original, "심을 자리를 못 찾았다")
        val parsed = SwiftPalette.parse(planted).pairs.getValue("background")
        assertTrue(!parsed.light.approximatelyEquals(AingPalette.background.light), "바꾼 값을 파서가 못 봤다")
        // 주석 속 토큰은 세지 않는다.
        val commented = SwiftPalette.parse("/// package static let ghost = Pair(both: RGB(hex: 0x000000))\n" + original)
        assertTrue("ghost" !in commented.pairs)
    }
}

/** G §8-13: iOS '선택·주요 동작' 파랑 가족 — 이식에서는 M3 primary(브랜드 보라)에서 나온다. */
private val PRIMARY_SUBSTITUTED = setOf("accent", "accentFill", "accentTint", "accentLine", "onAccentFill", "tabSelected")

/** MobileThemePalette.swift 의 숫자를 읽는 작은 파서(RGB 생성자 네 꼴: hex · r255 · 채널 셋 · alpha). */
internal object SwiftPalette {
    class Parsed(
        val pairs: Map<String, AingPair>,
        val arrays: Map<String, List<AingRgb>>,
        val pairArrays: Map<String, List<AingPair>>,
        val scalars: Map<String, AingRgb>,
    )

    private const val NUM = """[0-9]*\.?[0-9]+"""
    private val rgbExpr = Regex("""RGB\(([^()]*)\)""")

    fun stripComments(src: String): String {
        val out = StringBuilder()
        var i = 0
        var inString = false
        while (i < src.length) {
            val c = src[i]
            if (inString) {
                out.append(c)
                if (c == '\\' && i + 1 < src.length) { out.append(src[i + 1]); i += 2; continue }
                if (c == '"' || c == '\n') inString = false
                i++; continue
            }
            if (src.startsWith("//", i)) { while (i < src.length && src[i] != '\n') i++; continue }
            if (src.startsWith("/*", i)) {
                val end = src.indexOf("*/", i + 2).let { if (it < 0) src.length else it + 2 }
                for (k in i until end) if (src[k] == '\n') out.append('\n')
                i = end; continue
            }
            if (c == '"') inString = true
            out.append(c); i++
        }
        return out.toString()
    }

    fun rgb(args: String): AingRgb {
        val a = args.trim()
        val alpha = Regex("""alpha:\s*($NUM)""").find(a)?.groupValues?.get(1)?.toDouble() ?: 1.0
        Regex("""^hex:\s*0x([0-9A-Fa-f]{6})""").find(a)?.let { return AingRgb.hex(it.groupValues[1].toInt(16), alpha) }
        Regex("""^r255:\s*(\d+),\s*g255:\s*(\d+),\s*b255:\s*(\d+)""").find(a)?.let {
            return AingRgb.rgb255(it.groupValues[1].toInt(), it.groupValues[2].toInt(), it.groupValues[3].toInt(), alpha)
        }
        Regex("""^($NUM),\s*($NUM),\s*($NUM)""").find(a)?.let {
            return AingRgb(it.groupValues[1].toDouble(), it.groupValues[2].toDouble(), it.groupValues[3].toDouble(), alpha)
        }
        error("모르는 RGB 꼴: RGB($args)")
    }

    private fun pair(expr: String): AingPair {
        val both = Regex("""^Pair\(both:\s*(RGB\([^()]*\))\)""").find(expr.trim())
        if (both != null) return AingPair.both(rgb(rgbExpr.find(both.groupValues[1])!!.groupValues[1]))
        val m = Regex("""^Pair\(light:\s*RGB\(([^()]*)\),\s*dark:\s*RGB\(([^()]*)\)\)""").find(expr.trim()) ?: error("모르는 Pair 꼴: $expr")
        return AingPair(rgb(m.groupValues[1]), rgb(m.groupValues[2]))
    }

    fun parse(source: String): Parsed {
        val code = stripComments(source)
        val pairs = Regex("""static let (\w+) = (Pair\((?:[^()]|\([^()]*\))*\))""").findAll(code).associate { it.groupValues[1] to pair(it.groupValues[2]) }
        val arrays = Regex("""static let (\w+) = \[(RGB\([^\]]*)\]""").findAll(code).associate { m ->
            m.groupValues[1] to rgbExpr.findAll(m.groupValues[2]).map { rgb(it.groupValues[1]) }.toList()
        }
        val pairArrays = Regex("""static let (\w+): \[Pair\] = \[(.*?)\n\s*\]""", RegexOption.DOT_MATCHES_ALL).findAll(code).associate { m ->
            m.groupValues[1] to Regex("""Pair\(light:\s*RGB\([^()]*\),\s*dark:\s*RGB\([^()]*\)\)""").findAll(m.groupValues[2]).map { pair(it.value) }.toList()
        }
        val scalars = Regex("""static let (\w+) = RGB\(([^()]*)\)""").findAll(code).associate { it.groupValues[1] to rgb(it.groupValues[2]) }
        return Parsed(pairs, arrays, pairArrays, scalars)
    }
}
