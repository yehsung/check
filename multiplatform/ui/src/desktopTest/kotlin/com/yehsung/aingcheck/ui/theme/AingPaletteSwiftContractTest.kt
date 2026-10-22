// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f
// 원본: Sources/check/CheckGachaWindow.swift @ 862be0f (GachaWindowPalette)
//
// "iOS/맥 값 그대로"를 값으로 잰다: Swift 원문(MobileThemePalette.swift · CheckGachaWindow.swift)을 읽어 토큰마다 Kotlin 값과 대조한다.
// 원본 색이 바뀌거나 토큰이 늘고 줄면 이 시험이 먼저 빨개진다(두 벌 유지 — G §5-4). 주석은 걷어 내고 본다
// (기억 source-contract-tests-need-comment-stripping).
// 주요색은 iOS 파랑(G §8-15 — §8-13 의 대체 예외를 없앴다): accent 가족 여섯 토큰도 다른 토큰과 똑같이 Swift 값과 대조하고,
// M3 primary·secondary 가족이 Swift accent 가족 숫자에서 나오는지 · 브랜드 보라가 M3 역할·뜻 색 토큰 어디에도 없는지를 잰다.
// 브랜드 보라가 맥 뽑기 창(GachaWindowPalette) 값에서 온다는 대조는 그대로 둔다(브랜드 자리 전용 토큰).
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
        assertTrue(ACCENT_FAMILY.all { it in swift.pairs }, "Swift 에 accent 가족이 없다: ${ACCENT_FAMILY - swift.pairs.keys}")
        val wrong = swift.pairs.mapNotNull { (name, pair) ->
            val k = kotlinPairs.getValue(name)
            if (k.light.approximatelyEquals(pair.light) && k.dark.approximatelyEquals(pair.dark)) null else "$name: Swift=$pair Kotlin=$k"
        }
        assertTrue(wrong.isEmpty(), "Swift 와 값이 다르다:\n" + wrong.joinToString("\n"))
    }

    /**
     * G §8-15 를 결과로 잰다: M3 뼈대의 주요색 역할이 Swift accent 가족 **숫자**에서 나온다(기대값은 Swift 원문을 읽은 값 —
     * 라이트 primary = accent · 다크 primary = accent(글자로도 쓰는 밝은 파랑) · secondary·받침 위 글자 = tabSelected ·
     * 받침 = accentTint 를 카드 위에 겹친 값 · 라이트 onPrimary = onAccentFill). 그리고 브랜드 보라(뽑기 창 판·글자·아잉이 라벤더)는
     * M3 역할 48개와 뜻 색 토큰 **어디에도 없다**(한 자리라도 보라를 베껴 두면 한 화면에 보라 단추와 파랑 선택이 섞인다).
     */
    @Test
    fun materialPrimaryFamilyIsSwiftAccentAndBrandPurpleIsNowhereInIt() {
        val swift = SwiftPalette.parse(RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileThemePalette.swift")).pairs
        fun sw(name: String) = swift[name] ?: fail("Swift 에 $name 이 없다")
        val accent = sw("accent")
        val tab = sw("tabSelected")
        val tint = sw("accentTint")
        val surface = sw("surface")
        val wrong = mutableListOf<String>()
        fun same(label: String, want: AingRgb, got: androidx.compose.ui.graphics.Color) {
            if (want.toColor() != got) wrong += "$label: Swift=$want → ${want.toColor()} · M3=$got"
        }
        for (dark in listOf(false, true)) {
            val s = AingColorScheme.of(dark)
            val mode = if (dark) "다크" else "라이트"
            same("$mode primary = accent", accent.pick(dark), s.primary)
            same("$mode secondary = tabSelected", tab.pick(dark), s.secondary)
            same("$mode onPrimaryContainer = tabSelected", tab.pick(dark), s.onPrimaryContainer)
            same("$mode onSecondaryContainer = tabSelected", tab.pick(dark), s.onSecondaryContainer)
            same("$mode primaryContainer = accentTint/카드", tint.pick(dark).compositedOver(surface.pick(dark)), s.primaryContainer)
            same("$mode secondaryContainer = accentTint/카드", tint.pick(dark).compositedOver(surface.pick(dark)), s.secondaryContainer)
            same("$mode inversePrimary = 반대 모드 accent", accent.pick(!dark), s.inversePrimary)
            same("$mode primaryFixed = 라이트 accentTint/카드", tint.light.compositedOver(surface.light), s.primaryFixed)
            same("$mode primaryFixedDim = 다크 accent", accent.dark, s.primaryFixedDim)
            same("$mode onPrimaryFixedVariant = 라이트 accent", accent.light, s.onPrimaryFixedVariant)
        }
        same("라이트 onPrimary = onAccentFill", sw("onAccentFill").light, AingColorScheme.Light.onPrimary)
        same("라이트 accentFill = primary(채운 단추와 손으로 칠한 채움이 같은 값)", sw("accentFill").light, AingColorScheme.Light.primary)
        assertTrue(wrong.isEmpty(), "M3 주요색 가족이 Swift accent 가족과 다르다:\n" + wrong.joinToString("\n"))

        // 브랜드 보라 = 맥 뽑기 창 판·글자(brandInk·brandTitle·다크 brandCard) + 아잉이 라벤더. 흰 판(라이트 brandCard 97% 흰색)은 보라가 아니라 뺀다.
        val purples = listOf(
            "brandInk.light" to AingPalette.brandInk.light, "brandInk.dark" to AingPalette.brandInk.dark,
            "brandTitle.light" to AingPalette.brandTitle.light, "brandTitle.dark" to AingPalette.brandTitle.dark,
            "brandCard.dark" to AingPalette.brandCard.dark, "brandLavender" to AingPalette.brandLavender,
        )
        fun purpleName(c: AingRgb) = purples.firstOrNull { it.second.approximatelyEquals(c.opacity(1.0), 1.0 / 512) }?.first
        val inScheme = listOf(false, true).flatMap { dark ->
            materialColorRoles().mapNotNull { role ->
                val c = role.read(AingColorScheme.of(dark))
                purpleName(AingRgb(c.red.toDouble(), c.green.toDouble(), c.blue.toDouble()))?.let { "${if (dark) "다크" else "라이트"} ${role.name} = $it" }
            }
        }
        assertTrue(inScheme.isEmpty(), "M3 역할에 브랜드 보라가 있다: $inScheme")
        val inTokens = kotlinPairs.flatMap { (name, pair) ->
            listOf("$name.light" to pair.light, "$name.dark" to pair.dark).mapNotNull { (k, v) -> purpleName(v)?.let { "$k = $it" } }
        }
        assertTrue(inTokens.isEmpty(), "뜻 색 토큰에 브랜드 보라가 있다: $inTokens")
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

/** iOS '선택·주요 동작' 파랑 가족(G §8-15 — 대체 예외 없이 Swift 값 그대로). 파서가 이 여섯을 읽었는지 먼저 확인한다. */
private val ACCENT_FAMILY = setOf("accent", "accentFill", "accentTint", "accentLine", "onAccentFill", "tabSelected")

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
