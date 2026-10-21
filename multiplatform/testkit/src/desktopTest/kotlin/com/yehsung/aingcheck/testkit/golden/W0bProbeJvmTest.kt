// 원본: Tests/checkTests/GoldenExport/_base/GoldenExportProbeW0b.swift(실험 표 생성기) @ W0-b
package com.yehsung.aingcheck.testkit.golden

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.foundation.time.KST
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.offsetAt
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import java.text.BreakIterator
import java.text.Normalizer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Instant

/**
 * W0-b 실험의 **JVM 몫**(C-X1 · 덤으로 C-X4 · C-X12 · C-X13). ART 몫은 W0-f ③ 이 같은 표(`Golden.loadProbe`)로 잰다.
 *
 * 실험이라 **플랫폼 차이 수는 단언하지 않고 기록한다**(`AINGCHECK-PROBE …` 줄 — 게이트 로그·시험 결과 XML 에 남는다).
 * 단언하는 것은 표 자체의 온전함이다: Kotlin 이 표를 읽어 Swift 값을 **되살렸을 때 Swift 가 박은 지문과 같다**
 * (pow3: x·ref·Darwin pow 의 FNV 세 개 / text-scalars: 0..10FFFF 를 빈틈없이 덮는다 / …). 그래야 W0-f 가 같은 읽기로 ART 를 잰다.
 */
class W0bProbeJvmTest {
    private fun probe(line: String) = println("AINGCHECK-PROBE $line")

    /** pow3 의 deltas 글자 → (chunk 안 위치 → ulp 차). */
    private fun decodeDeltas(tokens: String): Map<Int, Long> {
        val out = HashMap<Int, Long>()
        var pos = -1
        var i = 0
        while (i < tokens.length) {
            var j = i
            while (j < tokens.length && (tokens[j].isDigit() || tokens[j] in 'a'..'z')) j++
            pos += tokens.substring(i, j).toInt(36) + 1
            when (tokens[j]) {
                '+' -> { out[pos] = 1L; i = j + 1 }
                '-' -> { out[pos] = -1L; i = j + 1 }
                '=' -> {
                    val end = tokens.indexOf(';', j)
                    out[pos] = tokens.substring(j + 1, end).toLong()
                    i = end + 1
                }
                else -> error("pow3 deltas 를 못 읽었다: '${tokens[j]}' @ $j")
            }
        }
        return out
    }

    @Test
    fun cx1PowBitsDarwinVersusJvm() {
        val table = Golden.loadProbe("w0b-probe/pow3")
        val rng = SplitMix64(Golden.hex64(table.spec.string("seed")))
        var total = 0
        var mathVsDarwin = 0
        var strictVsDarwin = 0
        var refVsDarwin = 0
        var mathVsStrict = 0
        for (case in table.cases.filter { it.string("id").startsWith("chunk-") }) {
            val deltas = decodeDeltas(case.string("deltas"))
            assertEquals(case.int("plus") + case.int("minus") + case.int("other"), deltas.size, table.failure(case.string("id"), "δ 개수"))
            val xHash = GoldenFnv1a64()
            val refHash = GoldenFnv1a64()
            val powHash = GoldenFnv1a64()
            for (i in 0 until case.int("count")) {
                val x = rng.unit()
                val ref = x * x * x
                val darwin = Double.fromBits(ref.toRawBits() + (deltas[i] ?: 0L))
                xHash.add(x); refHash.add(ref); powHash.add(darwin)
                val math = Math.pow(x, 3.0)
                val strict = StrictMath.pow(x, 3.0)
                if (math.toRawBits() != darwin.toRawBits()) mathVsDarwin++
                if (strict.toRawBits() != darwin.toRawBits()) strictVsDarwin++
                if (ref.toRawBits() != darwin.toRawBits()) refVsDarwin++
                if (math.toRawBits() != strict.toRawBits()) mathVsStrict++
                total++
            }
            val id = case.string("id")
            assertEquals(case.hex64("xDigest"), xHash.value, table.failure(id, "x 지문 — Kotlin SplitMix64.unit() 열이 Swift 와 다르다"))
            assertEquals(case.hex64("refDigest"), refHash.value, table.failure(id, "(x*x)*x 지문 — 곱셈 비트가 다르다(FMA?)"))
            assertEquals(case.hex64("powDigest"), powHash.value, table.failure(id, "되살린 Darwin pow 지문 — deltas 읽기가 틀렸다"))
        }
        assertEquals(1_000_000, total)
        probe("C-X1 pow(x,3) n=$total Math.pow≠Darwin=$mathVsDarwin StrictMath.pow≠Darwin=$strictVsDarwin " +
            "(x*x)*x≠Darwin=$refVsDarwin Math≠StrictMath=$mathVsStrict jvm=${System.getProperty("java.vm.name")} " +
            "${System.getProperty("java.runtime.version")} arch=${System.getProperty("os.arch")}")
        val edges = table.case("edges")
        val xs = edges.array("xBits").map { Golden.bits(it.stringValue()) }
        val darwin = edges.array("powBits").map { Golden.bits(it.stringValue()) }
        val edgeMath = xs.indices.count { Math.pow(xs[it], 3.0).toRawBits() != darwin[it].toRawBits() }
        val edgeStrict = xs.indices.count { StrictMath.pow(xs[it], 3.0).toRawBits() != darwin[it].toRawBits() }
        probe("C-X1 pow edges n=${xs.size} Math.pow≠Darwin=$edgeMath StrictMath.pow≠Darwin=$edgeStrict")
    }

    @Test
    fun cx1TetrisGravityDarwinVersusJvm() {
        val table = Golden.loadProbe("w0b-probe/gravity")
        val math = mutableListOf<String>()
        val strict = mutableListOf<String>()
        for (case in table.cases) {
            val e = case.int("stage").toDouble()
            val base = 0.8 - 0.007 * (e - 1)
            assertEquals(case.string("baseBits"), Golden.bitsText(base), table.failure(case.string("id"), "밑 비트(곱셈·뺄셈)가 다르다"))
            val want = case.bits("powBits").toRawBits()
            val viaMath = Math.pow(base, e - 1)
            if (viaMath.toRawBits() != want) math += "${case.int("stage")}(darwin=${case.string("powBits")} jvm=${Golden.bitsText(viaMath)})"
            if (StrictMath.pow(base, e - 1).toRawBits() != want) strict += "${case.int("stage")}"
        }
        assertEquals(20, table.cases.size)
        probe("C-X1 gravity stages=20 Math.pow≠Darwin=${math.size} $math StrictMath.pow≠Darwin=${strict.size} $strict")
    }

    private fun gcCode(cp: Int): String = when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER -> "Lu"; Character.LOWERCASE_LETTER -> "Ll"; Character.TITLECASE_LETTER -> "Lt"
        Character.MODIFIER_LETTER -> "Lm"; Character.OTHER_LETTER -> "Lo"; Character.NON_SPACING_MARK -> "Mn"
        Character.COMBINING_SPACING_MARK -> "Mc"; Character.ENCLOSING_MARK -> "Me"; Character.DECIMAL_DIGIT_NUMBER -> "Nd"
        Character.LETTER_NUMBER -> "Nl"; Character.OTHER_NUMBER -> "No"; Character.CONNECTOR_PUNCTUATION -> "Pc"
        Character.DASH_PUNCTUATION -> "Pd"; Character.START_PUNCTUATION -> "Ps"; Character.END_PUNCTUATION -> "Pe"
        Character.INITIAL_QUOTE_PUNCTUATION -> "Pi"; Character.FINAL_QUOTE_PUNCTUATION -> "Pf"; Character.OTHER_PUNCTUATION -> "Po"
        Character.MATH_SYMBOL -> "Sm"; Character.CURRENCY_SYMBOL -> "Sc"; Character.MODIFIER_SYMBOL -> "Sk"
        Character.OTHER_SYMBOL -> "So"; Character.SPACE_SEPARATOR -> "Zs"; Character.LINE_SEPARATOR -> "Zl"
        Character.PARAGRAPH_SEPARATOR -> "Zp"; Character.CONTROL -> "Cc"; Character.FORMAT -> "Cf"
        Character.SURROGATE -> "Cs"; Character.PRIVATE_USE -> "Co"; Character.UNASSIGNED -> "Cn"
        else -> "??"
    }

    @Test
    fun cx4ScalarClassesDarwinVersusJvm() {
        val table = Golden.loadProbe("w0b-probe/text-scalars")
        val whiteSpace = Regex("""\p{IsWhite_Space}""")
        val fillers = setOf(0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800)
        val invisible = setOf("Cc", "Cf", "Cs", "Cn", "Zs", "Zl", "Zp")
        var covered = 0
        var next = 0
        val diff = IntArray(4)
        val samples = Array(4) { mutableListOf<String>() }
        for (case in table.cases) {
            for (token in case.string("ranges").split(',')) {
                val (span, klass) = token.split(':')
                val (lo, hi) = span.split('-').map { it.toInt(16) }
                assertEquals(next, lo, "text-scalars 구간이 이어지지 않는다(${case.string("id")} $token)")
                next = hi + 1
                val want = listOf(klass.substring(0, 2), klass.substring(2, 3), klass.substring(3, 4), klass.substring(4, 5))
                for (cp in lo..hi) {
                    covered++
                    if (cp in 0xD800..0xDFFF) continue
                    val text = String(Character.toChars(cp))
                    val gc = gcCode(cp)
                    val ws = if (whiteSpace.matches(text)) "1" else "0"
                    val visible = if (ws == "0" && cp !in fillers && gc !in invisible) "1" else "0"
                    val nfc = if (Normalizer.normalize(text, Normalizer.Form.NFC) == text) "1" else "0"
                    val got = listOf(gc, ws, visible, nfc)
                    for (k in 0..3) if (got[k] != want[k]) {
                        diff[k]++
                        if (samples[k].size < 6) samples[k] += "U+%04X swift=%s jvm=%s".format(cp, want[k], got[k])
                    }
                }
            }
        }
        assertEquals(0x110000, covered, "text-scalars 가 U+0000..U+10FFFF 를 다 덮지 않는다")
        probe("C-X4 scalars(JDK ${System.getProperty("java.runtime.version")}) generalCategory≠=${diff[0]} whiteSpace≠=${diff[1]} " +
            "visible≠=${diff[2]} nfcStable≠=${diff[3]} examples gc=${samples[0]} ws=${samples[1]} vis=${samples[2]} nfc=${samples[3]}")
    }

    private fun codePoints(cps: String): IntArray = cps.split(' ').map { it.toInt(16) }.toIntArray()

    @Test
    fun cx13GraphemesDarwinVersusJvm() {
        val table = Golden.loadProbe("w0b-probe/graphemes")
        val boundary = BreakIterator.getCharacterInstance(java.util.Locale.ROOT)
        val regexX = Regex("""\X""")
        var breakIteratorDiff = 0
        var regexDiff = 0
        val samples = mutableListOf<String>()
        for (case in table.cases) {
            val text = String(codePoints(case.string("cps")), 0, codePoints(case.string("cps")).size)
            val want = case.array("clusters").map { it.jsonPrimitive.int }
            assertEquals(codePoints(case.string("cps")).size, want.sum(), table.failure(case.string("id"), "그래핌 길이 합"))
            boundary.setText(text)
            val viaBreak = mutableListOf<Int>()
            var start = boundary.first()
            var end = boundary.next()
            while (end != BreakIterator.DONE) {
                viaBreak += text.codePointCount(start, end)
                start = end
                end = boundary.next()
            }
            val viaRegex = regexX.findAll(text).map { text.codePointCount(it.range.first, it.range.last + 1) }.toList()
            if (viaBreak != want) { breakIteratorDiff++; if (samples.size < 8) samples += "${case.string("id")}[${case.string("cps")}] swift=$want jvm=$viaBreak" }
            if (viaRegex != want) regexDiff++
        }
        probe("C-X13 graphemes n=${table.cases.size} BreakIterator≠Swift=$breakIteratorDiff regex\\X≠Swift=$regexDiff examples=$samples")
    }

    @Test
    fun cx4NfcDarwinVersusJvm() {
        val table = Golden.loadProbe("w0b-probe/nfc")
        var diff = 0
        val samples = mutableListOf<String>()
        for (case in table.cases) {
            val input = codePoints(case.string("cps"))
            val text = String(input, 0, input.size)
            val got = Normalizer.normalize(text, Normalizer.Form.NFC).codePoints().toArray()
                .joinToString(" ") { it.toString(16).padStart(4, '0') }
            if (got != case.string("nfc")) { diff++; if (samples.size < 8) samples += "${case.string("id")} in=${case.string("cps")} swift=${case.string("nfc")} jvm=$got" }
        }
        assertEquals(300, table.cases.size)
        probe("C-X4 nfc n=${table.cases.size} Normalizer≠Swift=$diff examples=$samples")
    }

    @Test
    fun cx12KstDarwinVersusJvm() {
        val table = Golden.loadProbe("w0b-probe/kst")
        var diff = 0
        val samples = mutableListOf<String>()
        for (case in table.cases) {
            val instant = Instant.fromEpochSeconds(case.long("epoch"))
            val local = instant.toLocalDateTime(KST)
            val swiftWeekday = local.dayOfWeek.ordinal.let { (it + 1) % 7 + 1 }   // ISO 월=0 … 일=6 → Swift 일=1 … 토=7
            val dayKey = "%04d%02d%02d".format(local.year, local.month.ordinal + 1, local.day)
            val monday = local.date.minus(DatePeriod(days = local.dayOfWeek.ordinal))
            val mondayEpoch = monday.atStartOfDayIn(KST).epochSeconds
            val got = listOf(local.year, local.month.ordinal + 1, local.day, local.hour, local.minute, local.second,
                swiftWeekday, KST.offsetAt(instant).totalSeconds)
            val want = listOf("y", "mo", "d", "h", "mi", "s", "weekday", "offset").map { case.int(it) }
            val wantMonday = (case["mondayEpoch"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toLongOrNull()
            if (got != want || dayKey != case.string("dayKey") || (wantMonday != null && wantMonday != mondayEpoch)) {
                diff++
                if (samples.size < 6) samples += "${case.string("id")} swift=$want/${case.string("dayKey")}/$wantMonday jvm=$got/$dayKey/$mondayEpoch"
            }
        }
        assertTrue(table.cases.size > 1000, "kst 표가 비었다")
        probe("C-X12 kst n=${table.cases.size} kotlinx-datetime≠Swift=$diff examples=$samples")
    }

    /** 표 읽기 도우미가 Swift 값과 같은 것을 읽는지 — 기준선이 다른 입력: x 지문 하나를 틀리게 주면 빨강이어야 한다. */
    @Test
    fun pow3ReaderRejectsAWrongDigest() {
        val table = Golden.loadProbe("w0b-probe/pow3")
        val first = table.cases.first { it.string("id") == "chunk-00" }
        val rng = SplitMix64(Golden.hex64(table.spec.string("seed")))
        val hash = GoldenFnv1a64()
        repeat(first.int("count")) { hash.add(rng.unit()) }
        assertEquals(first.hex64("xDigest"), hash.value)
        val shifted = SplitMix64(Golden.hex64(table.spec.string("seed")) + 1uL)
        val other = GoldenFnv1a64()
        repeat(first.int("count")) { other.add(shifted.unit()) }
        assertTrue(other.value != first.hex64("xDigest"), "시드를 바꿔도 x 지문이 같다 — 지문이 x 를 안 본다")
    }
}
