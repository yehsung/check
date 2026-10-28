// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesText.swift(골든 생성기) @ 1b8260d
//       6차 c-fold: 그래핌 ART 판정을 API 수준별 잠금([GraphemeArtLocks] — G §8-17 2 (a))으로 바꿨다.
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 글자 골든 대조 몫(JVM 시험과 Android 계측이 같은 판정을 부른다 — G §8-16 · C§5.5). 골든을 읽는 자리(Golden.load · 자산)는 부르는 쪽이 정한다.
 *
 * [Runtime] 은 knownDivergence 의 허용 폭만 바꾼다: 그래핌 InCB 2줄은 데스크톱 JDK 21 이면 **옛 규칙 값이어야** 하고(JDK 가 고쳐지면 빨강 —
 * 목록을 다시 정한다). ART 는 기기 ICU 판이 API 마다 달라 **API 수준별 목록**([GraphemeArtLocks])으로 잠근다(G §8-17 2 (a) — minSdk 26 유지):
 * API 26 은 Swift 와 갈리는 줄 전부를 정확한 값으로, API 36 은 골든 knownDivergence(InCB 2줄)만 허용 폭으로. 재지 않은 API 는 빨강이다.
 */
enum class TextRuntime { DESKTOP_JDK, ANDROID_ART }

object TextGoldenChecks {
    fun cps(text: String): String = text.codePointArray().joinToString(" ") { it.toString(16).padStart(4, '0') }

    fun text(cps: String): String =
        if (cps.isEmpty()) "" else stringFromCodePoints(cps.split(' ').map { it.toInt(16) }.toIntArray())

    /** text/nfc — 표준 NFC. knownDivergence 줄은 standard, 나머지는 Foundation 값. 목록은 정확히 6줄. */
    fun nfc(golden: GoldenFile): Int {
        var divergent = 0
        for (case in golden.cases) {
            val id = case.string("id")
            val input = text(case.string("cps"))
            val got = cps(TextNormalization.nfc(input))
            val known = case["knownDivergence"] as? JsonObject
            if (known != null) {
                divergent++
                val standard = known.string("standard")
                assertTrue(standard != case.string("nfc"), golden.failure(id, "knownDivergence 의 standard 가 Foundation 값과 같다(목록이 낡았다)"))
                assertEquals(standard, got, golden.failure(id, "Foundation 과 어긋나는 줄인데 표준 NFC 를 내지 않았다"))
            } else {
                assertEquals(case.string("nfc"), got, golden.failure(id, "입력 ${case.string("cps")} 의 NFC — knownDivergence 밖에서 Swift 와 다르다"))
            }
        }
        assertEquals(6, divergent, "text/nfc knownDivergence 는 정확히 6줄이다(G §8-16 ①) — 늘거나 줄면 결정을 다시 본다")
        return divergent
    }

    /** 플랫폼 그래핌 → 그래핌마다 스칼라 수(골든 clusters 꼴). 시험은 가짜를 넣어 잠금 판정 자체를 잰다([GraphemeArtLocks] 자기 시험). */
    val platformSegmenter: (String) -> List<Int> = { Graphemes.scalarCounts(it).toList() }

    /** Swift 값과 다른 줄(id → 플랫폼이 낸 조각), 골든 차례. 기기에서 잴 때 근거 줄로 남긴다. */
    fun graphemeDifferences(golden: GoldenFile, segment: (String) -> List<Int> = platformSegmenter): List<Pair<String, List<Int>>> =
        golden.cases.mapNotNull { case ->
            val got = segment(text(case.string("cps")))
            val want = case.array("clusters").map { it.jsonPrimitive.int }
            if (got != want) case.string("id") to got else null
        }

    /**
     * text/graphemes — 그래핌 경계. 돌려주는 값 = Swift 와 갈린 줄 수.
     *  - 데스크톱 JDK: knownDivergence(InCB 2줄)는 옛 규칙 값이어야 하고 나머지는 Swift 값.
     *  - ART: [artApi] 의 잠금([GraphemeArtLocks.forApi]) — 없으면 빨강(재지 않은 API). [GraphemeArtLocks.GoldenListOnly] 면 InCB 2줄만
     *    Swift 또는 옛 규칙 값, [GraphemeArtLocks.Exact] 면 Swift 와 갈리는 줄의 **집합과 값**이 목록과 정확히 같아야 한다(늘거나 줄면 빨강).
     */
    fun graphemes(golden: GoldenFile, runtime: TextRuntime, artApi: Int? = null, segment: (String) -> List<Int> = platformSegmenter): Int {
        val lock: GraphemeArtLocks.Lock? = when (runtime) {
            TextRuntime.DESKTOP_JDK -> null
            TextRuntime.ANDROID_ART -> {
                val api = artApi ?: fail("ART 그래핌 판정에는 API 수준이 있어야 한다")
                GraphemeArtLocks.forApi(api)
                    ?: fail("API $api 은 그래핌 갈림을 재지 않았다 — 이 기기에서 잰 목록을 GraphemeArtLocks 에 더한다(G §8-17 2 (a), 잰 API: ${GraphemeArtLocks.measuredApis})")
            }
        }
        val exact = lock as? GraphemeArtLocks.Exact
        var listed = 0
        var differ = 0
        val differIds = LinkedHashSet<String>()
        for (case in golden.cases) {
            val id = case.string("id")
            val input = text(case.string("cps"))
            val want = case.array("clusters").map { it.jsonPrimitive.int }
            val got = segment(input)
            assertEquals(input.codePointCountCompat(), got.sum(), golden.failure(id, "그래핌 조각의 스칼라 합이 입력과 다르다"))
            if (got != want) differIds += id
            val known = case["knownDivergence"] as? JsonObject
            if (known != null) listed++
            if (exact != null) {
                val locked = exact.lines[id]
                if (locked != null) {
                    assertEquals(locked, got, golden.failure(id, "API ${exact.api} 잠금 값과 다르다(입력 ${case.string("cps")}) — 기기 ICU 가 바뀌었으면 목록을 다시 잰다"))
                } else {
                    assertEquals(want, got, golden.failure(id, "입력 ${case.string("cps")} 의 그래핌 경계 — API ${exact.api} 잠금 목록 밖에서 Swift 와 다르다"))
                }
                if (got != want) differ++
                continue
            }
            if (known != null) {
                val legacy = known.array("legacyClusters").map { it.jsonPrimitive.int }
                when (runtime) {
                    TextRuntime.DESKTOP_JDK -> assertEquals(legacy, got, golden.failure(id, "JDK 21 BreakIterator 는 InCB 전 규칙 값을 내야 한다 — 달라졌으면 knownDivergence 를 다시 정한다"))
                    TextRuntime.ANDROID_ART -> assertTrue(got == want || got == legacy, golden.failure(id, "ART 가 Swift($want)도 옛 규칙($legacy)도 아닌 $got 을 냈다"))
                }
                if (got != want) differ++
                continue
            }
            assertEquals(want, got, golden.failure(id, "입력 ${case.string("cps")} 의 그래핌 경계 — knownDivergence 밖에서 Swift 와 다르다"))
            assertEquals(case.int("count"), got.size, golden.failure(id, "String.count"))
        }
        assertEquals(2, listed, "text/graphemes knownDivergence 는 정확히 2줄(InCB)이다(G §8-16 ③)")
        if (exact != null) {
            assertEquals(exact.lines.keys, differIds, "API ${exact.api} 에서 Swift 와 갈리는 줄이 잠금 목록과 다르다(늘거나 줄면 빨강 — G §8-17 2 (a))")
        }
        return differ
    }

    /** text/sanitize — MessageBody · StatusMessage. */
    fun sanitize(golden: GoldenFile) {
        for (case in golden.cases) {
            val id = case.string("id")
            val raw = text(case.string("cps"))
            val message = case.obj("message")
            assertEquals(message.string("sanitized"), cps(MessageBody.sanitized(raw)), golden.failure(id, "MessageBody.sanitized"))
            assertEquals(message.int("length"), MessageBody.length(raw), golden.failure(id, "MessageBody.length"))
            assertEquals(message["visible"]!!.jsonPrimitive.content.toBoolean(), MessageBody.hasVisibleContent(raw), golden.failure(id, "MessageBody.hasVisibleContent"))
            assertEquals(validation(message.obj("validate")), describe(MessageBody.validate(raw)), golden.failure(id, "MessageBody.validate"))
            val status = case.obj("status")
            assertEquals(status.string("sanitized"), cps(StatusMessage.sanitized(raw)), golden.failure(id, "StatusMessage.sanitized"))
            assertEquals(status.int("length"), StatusMessage.length(raw), golden.failure(id, "StatusMessage.length"))
            assertEquals(validation(status.obj("validate")), describe(StatusMessage.validate(raw)), golden.failure(id, "StatusMessage.validate"))
            val display = status["display"]
            val wantDisplay = if (display == null || display is JsonNull) null else display.jsonPrimitive.content
            assertEquals(wantDisplay, StatusMessage.display(raw)?.let(::cps), golden.failure(id, "StatusMessage.display"))
            assertEquals(status.string("counter"), StatusMessage.counterText(raw), golden.failure(id, "StatusMessage.counterText"))
        }
    }

    private fun validation(obj: JsonObject): String = when (val kind = obj.string("kind")) {
        "ok" -> "ok:" + obj.string("cps")
        "empty" -> "empty"
        "tooLong" -> "tooLong:" + obj.int("maxLength")
        else -> fail("모르는 validate kind $kind")
    }

    private fun describe(value: MessageBodyValidation): String = when (value) {
        is MessageBodyValidation.ok -> "ok:" + cps(value.value)
        MessageBodyValidation.empty -> "empty"
        is MessageBodyValidation.tooLong -> "tooLong:" + value.maxLength
    }

    private fun describe(value: StatusMessageValidation): String = when (value) {
        is StatusMessageValidation.ok -> "ok:" + cps(value.value)
        StatusMessageValidation.empty -> "empty"
        is StatusMessageValidation.tooLong -> "tooLong:" + value.maxLength
    }

    /** text/status-message — 디코드한 응답 세 칸 → 저장 결과 → 문구(오류 여부) · 결과 여섯의 문구 · 고정 문구. 돌려주는 값 = 응답 줄 수. */
    fun statusMessage(golden: GoldenFile): Int {
        var responses = 0
        for (case in golden.cases.filter { it.string("id").startsWith("r-") }) {
            val id = case.string("id")
            val message = case["statusMessage"]
            val maxLength = case["maxLength"]
            val outcome = StatusMessageSaveOutcome.from(
                status = case.string("status"),
                statusMessage = if (message == null || message is JsonNull) null else text(message.jsonPrimitive.content),
                maxLength = if (maxLength == null || maxLength is JsonNull) null else maxLength.jsonPrimitive.content.toLong(),
            )
            assertEquals(statusOutcome(case.obj("outcome")), describe(outcome), golden.failure(id, "StatusMessageSaveOutcome.from"))
            assertEquals(statusNotice(case.obj("notice")), describeNotice(outcome), golden.failure(id, "StatusMessageText.notice"))
            responses++
        }
        val notices = golden.case("notices").array("rows")
        for ((index, row) in notices.withIndex()) {
            val obj = row as JsonObject
            val want = obj.obj("outcome")
            val outcome = when (val kind = want.string("kind")) {
                "saved" -> StatusMessageSaveOutcome.saved(text(want.string("cps")))
                "cleared" -> StatusMessageSaveOutcome.cleared
                "tooLong" -> StatusMessageSaveOutcome.tooLong(want.int("maxLength"))
                "notText" -> StatusMessageSaveOutcome.notText
                "serverNotReady" -> StatusMessageSaveOutcome.serverNotReady
                "invalid" -> StatusMessageSaveOutcome.invalid
                else -> fail("모르는 결과 kind $kind")
            }
            assertEquals(statusNotice(obj.obj("notice")), describeNotice(outcome), golden.failure("notices#$index", "StatusMessageText.notice"))
        }
        assertEquals(7, notices.size, "notices 는 결과 여섯(tooLong 두 값)을 다 싣는다")
        val texts = golden.case("texts")
        val got = mapOf(
            "title" to StatusMessageText.title, "placeholder" to StatusMessageText.placeholder, "save" to StatusMessageText.save,
            "clear" to StatusMessageText.clear, "saved" to StatusMessageText.saved, "cleared" to StatusMessageText.cleared,
            "notText" to StatusMessageText.notText, "invalid" to StatusMessageText.invalid, "serverNotReady" to StatusMessageText.serverNotReady,
            "network" to StatusMessageText.network, "hint" to StatusMessageText.hint, "tooLong40" to StatusMessageText.tooLong(40),
        )
        for ((key, value) in got) assertEquals(texts.string(key), value, golden.failure("texts", "StatusMessageText.$key"))
        assertEquals(texts.int("maxLength"), StatusMessage.maxLength, golden.failure("texts", "StatusMessage.maxLength"))
        return responses
    }

    private fun statusOutcome(obj: JsonObject): String = when (val kind = obj.string("kind")) {
        "saved" -> "saved:" + obj.string("cps")
        "tooLong" -> "tooLong:" + obj.int("maxLength")
        "cleared", "notText", "serverNotReady", "invalid" -> kind
        else -> fail("모르는 결과 kind $kind")
    }

    private fun describe(value: StatusMessageSaveOutcome): String = when (value) {
        is StatusMessageSaveOutcome.saved -> "saved:" + cps(value.value)
        StatusMessageSaveOutcome.cleared -> "cleared"
        is StatusMessageSaveOutcome.tooLong -> "tooLong:" + value.maxLength
        StatusMessageSaveOutcome.notText -> "notText"
        StatusMessageSaveOutcome.serverNotReady -> "serverNotReady"
        StatusMessageSaveOutcome.invalid -> "invalid"
    }

    private fun statusNotice(obj: JsonObject): String = obj.string("text") + "|error=" + obj["isError"]!!.jsonPrimitive.content

    private fun describeNotice(outcome: StatusMessageSaveOutcome): String =
        StatusMessageText.notice(outcome).let { (text, isError) -> "$text|error=$isError" }

    /** stickers/tokens — 여섯 토큰 · 판정 · 미리보기. */
    fun stickers(golden: GoldenFile) {
        val stickers = golden.cases.filter { it.string("id").startsWith("sticker-") }.sortedBy { it.int("order") }
        assertEquals(stickers.map { it.string("rawValue") }, AingSticker.entries.map { it.rawValue }, "이모티콘 차례(그리드 순서)가 다르다")
        for ((case, sticker) in stickers.zip(AingSticker.entries)) {
            val id = case.string("id")
            assertEquals(case.string("token"), cps(sticker.token), golden.failure(id, "token(전선 계약)"))
            assertEquals(case.string("label"), cps(sticker.label), golden.failure(id, "label"))
            assertEquals(case.string("resourceName"), sticker.resourceName, golden.failure(id, "resourceName"))
            assertEquals(case.string("accessibilityLabel"), cps(AingStickerText.accessibilityLabel(sticker)), golden.failure(id, "accessibilityLabel"))
        }
        val constants = golden.case("constants")
        assertEquals(constants.string("tokenPrefix"), cps(AingSticker.tokenPrefix))
        assertEquals(constants.int("count"), AingSticker.entries.size)
        assertEquals(constants.string("gridTitle"), cps(AingStickerText.gridTitle))
        assertEquals(constants.string("buttonLabel"), cps(AingStickerText.buttonLabel))
        assertEquals(constants.string("closeGridLabel"), cps(AingStickerText.closeGridLabel))
        assertEquals(constants.string("sendingNowNotice"), cps(AingStickerText.sendingNowNotice))
        assertEquals(constants.string("folderName"), AingStickerArtNames.folderName)
        var parsed = 0
        for (case in golden.cases.filter { it.string("id").startsWith("parse-") }) {
            val id = case.string("id")
            val raw = text(case.string("cps"))
            val want = case["parsed"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content }
            assertEquals(want, AingSticker.parse(raw)?.rawValue, golden.failure(id, "AingSticker.parse"))
            assertEquals(case.string("preview"), cps(AingStickerText.preview(raw)), golden.failure(id, "AingStickerText.preview"))
            // 판정은 한 자리(INV-AingSticker-a6bb0ef6): 그림이 있으면 parse 와 같은 표정, 그림이 없으면 null 이고 글자는 preview 로 접는다.
            assertEquals(want, AingStickerArtNames.drawable(raw) { "art:" + it.rawValue }?.first?.rawValue, golden.failure(id, "drawable(그림 있음)"))
            if (want != null) assertEquals("art:$want", AingStickerArtNames.drawable(raw) { "art:" + it.rawValue }?.second, golden.failure(id, "drawable 그림"))
            assertEquals(null, AingStickerArtNames.drawable<String>(raw) { null }, golden.failure(id, "drawable(그림 없음)"))
            assertEquals(case.string("preview"), cps(AingStickerArtNames.fallbackText(raw)), golden.failure(id, "fallbackText"))
            parsed++
        }
        assertTrue(parsed > 40, "stickers/tokens 판정 줄이 너무 적다($parsed)")
    }

    /** sort/collation-table — 번들 순위표가 골든과 토큰 하나까지 같은가. 다르면 기대 글자를 돌려준다(재생성용). */
    fun collationTableExpected(golden: GoldenFile): Triple<String, String, String> {
        val order = golden.cases.filter { it.string("id").startsWith("order-") }.sortedBy { it.int("start") }
            .joinToString(" ") { it.string("tokens") }
        return Triple(order, golden.case("ignorable").string("cps"), golden.case("primary-ignorable").string("cps"))
    }

    /** sort/natural-ko — 반대칭인 쌍은 Swift 값 그대로, 반대칭이 깨진 쌍은 Kotlin 이 반대칭만. 돌려주는 값 = (한자 갈림 쌍, 깨진 쌍). */
    fun naturalSort(golden: GoldenFile): Pair<List<String>, Int> {
        val hanMismatch = ArrayList<String>()
        var inconsistent = 0
        var checked = 0
        for (case in golden.cases.filter { it.string("id").startsWith("pairs-") }) {
            for ((index, row) in case.array("pairs").withIndex()) {
                val cells = row.jsonArray
                val a = text(cells[0].jsonPrimitive.content)
                val b = text(cells[1].jsonPrimitive.content)
                val ab = cells[2].jsonPrimitive.int
                val ba = cells[3].jsonPrimitive.int
                val got = NaturalKoCollation.compare(a, b)
                val back = NaturalKoCollation.compare(b, a)
                assertEquals(-got, back, golden.failure(case.string("id"), "[$index] Kotlin 비교가 반대칭이 아니다: '$a' / '$b'"))
                if (ab != -ba) {
                    inconsistent++
                    continue
                }
                checked++
                if (got != ab) {
                    val involvesHan = (a + b).codePointArray().any { it in 0x4E00..0x9FFF || it in 0x3400..0x4DBF || it in 0xF900..0xFAFF }
                    assertTrue(involvesHan, golden.failure(case.string("id"), "[$index] '$a'(${cps(a)}) / '$b'(${cps(b)}): Swift $ab, Kotlin $got"))
                    hanMismatch += "${cps(a)} / ${cps(b)}"
                }
            }
        }
        val summary = golden.case("summary")
        assertEquals(summary.int("inconsistent"), inconsistent, "Swift 반대칭 깨짐 쌍 수가 요약과 다르다")
        assertTrue(checked > 2000, "대조한 쌍이 너무 적다($checked)")
        return hanMismatch to inconsistent
    }
}
