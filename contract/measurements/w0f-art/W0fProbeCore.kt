// 원본: 없음 (W0-f ③ 측정기 — contract/README §6-1 스냅숏의 원문, 빌드에 들지 않는다. W0bProbeJvmTest 의 계산을 ART·JVM 두 런타임에서 **같은 소스**로 돌려 결과를 낸다)
package com.yehsung.aingcheck.w0fprobe

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.foundation.time.KST
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.GoldenFnv1a64
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.long
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.offsetAt
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlin.time.Instant

/**
 * 표(`w0b-probe/<이름>`)를 읽는 함수와 런타임별 연산(공백 판정·그래핌 분할기·NFC)을 받아 결과 JSON 을 낸다.
 * run() 은 단언하지 않는다 — 표 온전성(지문)도 결과 칸으로 낸다(한 칸이 어긋나도 나머지를 다 잰다).
 * 시험(ART·JVM)이 덤프를 쓴 **뒤** [problems] 로 측정기·표가 온전한지 단언한다(빈 목록이 아니면 빨강).
 */
class W0fProbeCore(
    private val load: (String) -> GoldenFile,
    private val whiteSpace: (String) -> Boolean,
    private val breakers: Map<String, (String) -> List<Int>>,
    private val normalizers: Map<String, (String) -> String>,
    private val generalCategories: Map<String, (Int) -> String>,
) {
    fun run(): JsonObject = buildJsonObject {
        put("env", env())
        put("pow3", timed { pow3() })
        put("gravity", timed { gravity() })
        put("scalars", timed { scalars() })
        put("graphemes", timed { graphemes() })
        put("nfc", timed { nfc() })
        put("kst", timed { kst() })
    }

    private fun timed(block: () -> JsonObject): JsonObject {
        val t0 = System.nanoTime()
        val out = runCatching(block).getOrElse { e -> buildJsonObject { put("error", "${e::class.java.name}: ${e.message}") } }
        return JsonObject(out + ("millis" to JsonPrimitive((System.nanoTime() - t0) / 1_000_000)))
    }

    private fun env(): JsonObject = buildJsonObject {
        for (k in listOf("java.vm.name", "java.vm.version", "java.runtime.version", "java.version", "os.arch", "java.specification.version")) {
            put(k, System.getProperty(k) ?: "")
        }
        put("tzdbVersions", runCatching { java.time.zone.ZoneRulesProvider.getVersions("Asia/Seoul").keys.joinToString(",") }.getOrElse { "error:${it::class.java.simpleName}" })
    }

    // ---------------- C-X1 pow ----------------

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

    private fun pow3(): JsonObject {
        val table = load("pow3")
        val rng = SplitMix64(Golden.hex64(table.spec.string("seed")))
        var total = 0
        var mathVsDarwin = 0
        var strictVsDarwin = 0
        var refVsDarwin = 0
        var mathVsStrict = 0
        val mathHash = GoldenFnv1a64()
        val strictHash = GoldenFnv1a64()
        val integrity = mutableListOf<String>()
        val chunkMath = mutableListOf<Int>()
        val samples = mutableListOf<String>()
        for (case in table.cases.filter { it.string("id").startsWith("chunk-") }) {
            val deltas = decodeDeltas(case.string("deltas"))
            val xHash = GoldenFnv1a64()
            val refHash = GoldenFnv1a64()
            val powHash = GoldenFnv1a64()
            var chunkDiff = 0
            for (i in 0 until case.int("count")) {
                val x = rng.unit()
                val ref = x * x * x
                val darwin = Double.fromBits(ref.toRawBits() + (deltas[i] ?: 0L))
                xHash.add(x); refHash.add(ref); powHash.add(darwin)
                val math = Math.pow(x, 3.0)
                val strict = StrictMath.pow(x, 3.0)
                mathHash.add(math); strictHash.add(strict)
                if (math.toRawBits() != darwin.toRawBits()) {
                    mathVsDarwin++; chunkDiff++
                    if (samples.size < 6) samples += "x=${Golden.bitsText(x)} darwin=${Golden.bitsText(darwin)} math=${Golden.bitsText(math)}"
                }
                if (strict.toRawBits() != darwin.toRawBits()) strictVsDarwin++
                if (ref.toRawBits() != darwin.toRawBits()) refVsDarwin++
                if (math.toRawBits() != strict.toRawBits()) mathVsStrict++
                total++
            }
            chunkMath += chunkDiff
            val id = case.string("id")
            if (case.hex64("xDigest") != xHash.value) integrity += "$id:x"
            if (case.hex64("refDigest") != refHash.value) integrity += "$id:ref"
            if (case.hex64("powDigest") != powHash.value) integrity += "$id:pow"
        }
        val edges = table.case("edges")
        val xs = edges.array("xBits").map { Golden.bits(it.stringValue()) }
        val darwin = edges.array("powBits").map { Golden.bits(it.stringValue()) }
        return buildJsonObject {
            put("n", total)
            put("mathVsDarwin", mathVsDarwin)
            put("strictVsDarwin", strictVsDarwin)
            put("refVsDarwin", refVsDarwin)
            put("mathVsStrict", mathVsStrict)
            put("mathDigest", Golden.hex64Text(mathHash.value))
            put("strictDigest", Golden.hex64Text(strictHash.value))
            putJsonArray("chunkMathVsDarwin") { chunkMath.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("integrityFailures") { integrity.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("samples") { samples.forEach { add(JsonPrimitive(it)) } }
            put("edgesN", xs.size)
            put("edgesMathVsDarwin", xs.indices.count { Math.pow(xs[it], 3.0).toRawBits() != darwin[it].toRawBits() })
            put("edgesStrictVsDarwin", xs.indices.count { StrictMath.pow(xs[it], 3.0).toRawBits() != darwin[it].toRawBits() })
        }
    }

    private fun gravity(): JsonObject {
        val table = load("gravity")
        val math = mutableListOf<String>()
        val strict = mutableListOf<String>()
        val baseBad = mutableListOf<Int>()
        val mathBits = mutableListOf<String>()
        for (case in table.cases) {
            val stage = case.int("stage")
            val e = stage.toDouble()
            val base = 0.8 - 0.007 * (e - 1)
            if (case.string("baseBits") != Golden.bitsText(base)) baseBad += stage
            val want = case.string("powBits")
            val viaMath = Math.pow(base, e - 1)
            val viaStrict = StrictMath.pow(base, e - 1)
            mathBits += Golden.bitsText(viaMath)
            if (Golden.bitsText(viaMath) != want) math += "$stage(darwin=$want got=${Golden.bitsText(viaMath)})"
            if (Golden.bitsText(viaStrict) != want) strict += "$stage(darwin=$want got=${Golden.bitsText(viaStrict)})"
        }
        return buildJsonObject {
            put("stages", table.cases.size)
            putJsonArray("baseBitsMismatch") { baseBad.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("mathVsDarwin") { math.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("strictVsDarwin") { strict.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("mathBits") { mathBits.forEach { add(JsonPrimitive(it)) } }
        }
    }

    // ---------------- C-X4 글자 분류 ----------------

    private val fillers = setOf(0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800)
    private val invisible = setOf("Cc", "Cf", "Cs", "Cn", "Zs", "Zl", "Zp")

    /** Swift 표와 같은 꼴의 구간 글자(`lo-hi:GGwvn`)를 이 런타임 값으로 만들고, Swift 표와 칸별 차이를 센다. 분류기마다 한 벌. */
    private fun scalars(): JsonObject {
        val table = load("text-scalars")
        // Swift 값을 칸별 배열로 편다(0..10FFFF).
        val swift = arrayOfNulls<String>(0x110000)
        var next = 0
        var gapBroken = false
        for (case in table.cases) {
            for (token in case.string("ranges").split(',')) {
                val (span, klass) = token.split(':')
                val (lo, hi) = span.split('-').map { it.toInt(16) }
                if (lo != next) gapBroken = true
                next = hi + 1
                for (cp in lo..hi) swift[cp] = klass
            }
        }
        return buildJsonObject {
            put("tableCovers", !gapBroken && next == 0x110000)
            for ((name, gcOf) in generalCategories) {
                val ranges = StringBuilder()
                var runStart = 0
                var runClass: String? = null
                val diff = IntArray(4)
                val samples = Array(4) { mutableListOf<String>() }
                fun flush(endInclusive: Int) {
                    val c = runClass ?: return
                    if (ranges.isNotEmpty()) ranges.append(',')
                    ranges.append(runStart.toString(16).padStart(4, '0')).append('-')
                        .append(endInclusive.toString(16).padStart(4, '0')).append(':').append(c)
                }
                for (cp in 0..0x10FFFF) {
                    val klass = if (cp in 0xD800..0xDFFF) "Cs000" else {
                        val text = String(Character.toChars(cp))
                        val gc = gcOf(cp)
                        val ws = if (whiteSpace(text)) "1" else "0"
                        val visible = if (ws == "0" && cp !in fillers && gc !in invisible) "1" else "0"
                        val nfc = if (java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFC) == text) "1" else "0"
                        gc + ws + visible + nfc
                    }
                    if (klass != runClass) { flush(cp - 1); runStart = cp; runClass = klass }
                    if (cp !in 0xD800..0xDFFF) {
                        val want = swift[cp] ?: continue
                        val parts = listOf(0 to 2, 2 to 3, 3 to 4, 4 to 5)
                        for (k in 0..3) {
                            val (a, b) = parts[k]
                            if (klass.substring(a, b) != want.substring(a, b)) {
                                diff[k]++
                                if (samples[k].size < 8) samples[k] += "U+%04X swift=%s got=%s".format(cp, want.substring(a, b), klass.substring(a, b))
                            }
                        }
                    }
                }
                flush(0x10FFFF)
                putJsonObject(name) {
                    put("generalCategoryVsSwift", diff[0])
                    put("whiteSpaceVsSwift", diff[1])
                    put("visibleVsSwift", diff[2])
                    put("nfcStableVsSwift", diff[3])
                    putJsonArray("samplesGc") { samples[0].forEach { add(JsonPrimitive(it)) } }
                    putJsonArray("samplesWs") { samples[1].forEach { add(JsonPrimitive(it)) } }
                    putJsonArray("samplesVisible") { samples[2].forEach { add(JsonPrimitive(it)) } }
                    putJsonArray("samplesNfc") { samples[3].forEach { add(JsonPrimitive(it)) } }
                    put("ranges", ranges.toString())
                }
            }
        }
    }

    private fun codePoints(cps: String): IntArray = cps.split(' ').map { it.toInt(16) }.toIntArray()

    // ---------------- C-X13 그래핌 ----------------

    private fun graphemes(): JsonObject {
        val table = load("graphemes")
        return buildJsonObject {
            put("n", table.cases.size)
            for ((name, split) in breakers) {
                var diff = 0
                val bad = mutableListOf<String>()
                putJsonObject(name) {
                    putJsonObject("clusters") {
                        for (case in table.cases) {
                            val cps = codePoints(case.string("cps"))
                            val text = String(cps, 0, cps.size)
                            val want = case.array("clusters").map { it.jsonPrimitive.int }
                            val got = runCatching { split(text) }.getOrElse { listOf(-1) }
                            put(case.string("id"), got.joinToString(","))
                            if (got != want) { diff++; bad += "${case.string("id")}[${case.string("cps")}] swift=$want got=$got" }
                        }
                    }
                    put("vsSwift", diff)
                    putJsonArray("mismatches") { bad.forEach { add(JsonPrimitive(it)) } }
                }
            }
        }
    }

    // ---------------- C-X4 NFC ----------------

    private fun nfc(): JsonObject {
        val table = load("nfc")
        return buildJsonObject {
            put("n", table.cases.size)
            for ((name, normalize) in normalizers) {
                var diff = 0
                val bad = mutableListOf<String>()
                putJsonObject(name) {
                    putJsonObject("results") {
                        for (case in table.cases) {
                            val input = codePoints(case.string("cps"))
                            val text = String(input, 0, input.size)
                            val got = runCatching {
                                val out = normalize(text)
                                out.codePoints().toArray().joinToString(" ") { it.toString(16).padStart(4, '0') }
                            }.getOrElse { "error:${it::class.java.simpleName}" }
                            put(case.string("id"), got)
                            if (got != case.string("nfc")) { diff++; bad += "${case.string("id")} in=${case.string("cps")} swift=${case.string("nfc")} got=$got" }
                        }
                    }
                    put("vsSwift", diff)
                    putJsonArray("mismatches") { bad.forEach { add(JsonPrimitive(it)) } }
                }
            }
        }
    }

    // ---------------- C-X12 KST ----------------

    private fun kst(): JsonObject {
        val table = load("kst")
        var diff = 0
        val ids = mutableListOf<String>()
        val samples = mutableListOf<String>()
        var mondayCompared = 0
        for (case in table.cases) {
            val instant = Instant.fromEpochSeconds(case.long("epoch"))
            val local = instant.toLocalDateTime(KST)
            val swiftWeekday = local.dayOfWeek.ordinal.let { (it + 1) % 7 + 1 }
            val dayKey = "%04d%02d%02d".format(local.year, local.month.ordinal + 1, local.day)
            val monday = local.date.minus(DatePeriod(days = local.dayOfWeek.ordinal))
            val mondayEpoch = monday.atStartOfDayIn(KST).epochSeconds
            val got = listOf(local.year, local.month.ordinal + 1, local.day, local.hour, local.minute, local.second,
                swiftWeekday, KST.offsetAt(instant).totalSeconds)
            val want = listOf("y", "mo", "d", "h", "mi", "s", "weekday", "offset").map { case.int(it) }
            val wantMonday = (case["mondayEpoch"] as? JsonPrimitive)?.content?.toLongOrNull()
            if (wantMonday != null) mondayCompared++
            if (got != want || dayKey != case.string("dayKey") || (wantMonday != null && wantMonday != mondayEpoch)) {
                diff++
                ids += case.string("id")
                if (samples.size < 10) samples += "${case.string("id")} swift=$want/${case.string("dayKey")}/$wantMonday got=$got/$dayKey/$mondayEpoch"
            }
        }
        return buildJsonObject {
            put("n", table.cases.size)
            put("mondayCompared", mondayCompared)
            put("vsSwift", diff)
            putJsonArray("ids") { ids.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("samples") { samples.forEach { add(JsonPrimitive(it)) } }
        }
    }

    companion object {
        /**
         * W0-b 골든 표의 sha256 — 저장소 `multiplatform/testkit/src/desktopTest/resources/golden/w0b-probe/<이름>.json`
         * (xplat/main 87ead0b, 2026-10-28 에 shasum -a 256 으로 잰 값). 측정기가 읽은 표 바이트가 이것과 다르면 덤프는 W0-b 기준이 아니다.
         */
        val EXPECTED_TABLE_SHA256: Map<String, String> = linkedMapOf(
            "pow3" to "6072327d593a313f5de4b88394eaa505b02e6d3634aa4bf9d453250db7e49c24",
            "gravity" to "12dae11ebf9cd796d32b116f372e634df5818dc3f75b9263940c72d980d517b9",
            "text-scalars" to "ac0fde1ed0fc3a9368dc3318a6f78d63164c6e68759f13ffaca49b77fed85578",
            "graphemes" to "d0c40b9692c0a16ffa512ade3b5510359d3147895da6c732b11f73f6619718a9",
            "nfc" to "83fe30c2fe96c35132d02aa8b2135d56998ac9fd91cafae70ae553811d186e57",
            "kst" to "dbb0be871a5cd4ce096771890647a491444ea1393c56c8fb9cab3aac5bc470f3",
        )

        fun sha256Hex(bytes: ByteArray): String =
            java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

        /**
         * 덤프가 '측정'으로 쓸 만한지(단언용 — 검증 지적: 계측 시험이 단언 없이 언제나 OK 였다). 빈 목록이면 통과.
         * 런타임 차이(범주·그래핌·NFC·pow 의 vsSwift 수)는 측정값이라 여기서 보지 않는다 — 보는 것은 측정기·표가 온전한가뿐:
         * 표 바이트 sha256 = W0-b 골든 · 칸마다 error 없음 · pow 표 지문(x·ref·pow) 실패 0 · 중력 바탕 비트 일치 ·
         * 범위 표 0..10FFFF 연속 · 표 크기(W0-b 실측 1,000,000 · 20 · 20 · 300 · 300 · 1,375) · 분할기 예외(-1)·NFC 예외 0.
         */
        fun problems(result: JsonObject, tableSha256: Map<String, String>): List<String> {
            val out = mutableListOf<String>()
            for ((name, want) in EXPECTED_TABLE_SHA256) {
                val got = tableSha256[name]
                if (got != want) out += "표 $name sha256=$got (W0-b 골든 $want)"
            }
            fun section(key: String): JsonObject? {
                val s = result[key] as? JsonObject
                if (s == null) { out += "$key 칸이 없다"; return null }
                (s["error"] as? JsonPrimitive)?.let { out += "$key 오류: ${it.content}"; return null }
                return s
            }
            fun intOf(s: JsonObject, k: String): Int? = (s[k] as? JsonPrimitive)?.content?.toIntOrNull()
            fun expectInt(where: String, s: JsonObject, k: String, want: Int) {
                val got = intOf(s, k)
                if (got != want) out += "$where.$k=$got (기대 $want)"
            }
            section("pow3")?.let { s ->
                val bad = (s["integrityFailures"] as? kotlinx.serialization.json.JsonArray)
                if (bad == null || bad.isNotEmpty()) out += "pow3 표 지문 실패: $bad"
                expectInt("pow3", s, "n", 1_000_000)
                expectInt("pow3", s, "edgesN", 20)
            }
            section("gravity")?.let { s ->
                val bad = (s["baseBitsMismatch"] as? kotlinx.serialization.json.JsonArray)
                if (bad == null || bad.isNotEmpty()) out += "중력 바탕 비트 불일치: $bad"
                expectInt("gravity", s, "stages", 20)
            }
            section("scalars")?.let { s ->
                if ((s["tableCovers"] as? JsonPrimitive)?.content != "true") out += "text-scalars 범위 표가 0..10FFFF 를 잇지 못한다(tableCovers=${s["tableCovers"]})"
            }
            section("graphemes")?.let { s ->
                expectInt("graphemes", s, "n", 300)
                for ((breaker, v) in s) {
                    val clusters = ((v as? JsonObject)?.get("clusters") as? JsonObject) ?: continue
                    val thrown = clusters.filterValues { (it as? JsonPrimitive)?.content == "-1" }.keys
                    if (thrown.isNotEmpty()) out += "그래핌 $breaker 예외 ${thrown.size}줄: ${thrown.take(5)}"
                }
            }
            section("nfc")?.let { s ->
                expectInt("nfc", s, "n", 300)
                for ((normalizer, v) in s) {
                    val results = ((v as? JsonObject)?.get("results") as? JsonObject) ?: continue
                    val thrown = results.filterValues { (it as? JsonPrimitive)?.content?.startsWith("error:") == true }.keys
                    if (thrown.isNotEmpty()) out += "NFC $normalizer 예외 ${thrown.size}줄: ${thrown.take(5)}"
                }
            }
            section("kst")?.let { s ->
                expectInt("kst", s, "n", 1375)
                expectInt("kst", s, "mondayCompared", 1375)
            }
            return out
        }

        /** java.lang.Character.getType → 두 글자(W0bProbeJvmTest 와 같은 표). */
        fun javaGc(cp: Int): String = when (Character.getType(cp).toByte()) {
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

        /** java.text.BreakIterator(Locale.ROOT) 로 그래핌마다 스칼라 수. */
        fun javaBreak(text: String): List<Int> {
            val boundary = java.text.BreakIterator.getCharacterInstance(java.util.Locale.ROOT)
            boundary.setText(text)
            val out = mutableListOf<Int>()
            var start = boundary.first()
            var end = boundary.next()
            while (end != java.text.BreakIterator.DONE) {
                out += text.codePointCount(start, end)
                start = end
                end = boundary.next()
            }
            return out
        }

        private val regexX by lazy { Regex("""\X""") }

        fun regexBreak(text: String): List<Int> =
            regexX.findAll(text).map { text.codePointCount(it.range.first, it.range.last + 1) }.toList()

        fun javaNfc(text: String): String = java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFC)
    }
}
