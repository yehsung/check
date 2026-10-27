// 원본: 없음 — 와이어 파일 안 규칙(역대 순위 정렬·날짜 캡션 · 상점 판정 · 선물 선택지 · 마이크로초 · 결과 갈래)과 숫자 판정 골든 대조, C-X3 키 변환 표 대조
package com.yehsung.aingcheck.core.wire

import com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.SwiftKeys
import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.wire.models.AppUserAvatar
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterRow
import com.yehsung.aingcheck.core.wire.models.DisplayNameChangeOutcome
import com.yehsung.aingcheck.core.wire.models.FeedbackComposer
import com.yehsung.aingcheck.core.wire.models.FeedbackStatus
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import com.yehsung.aingcheck.core.wire.models.PhoneWorkOutcome
import com.yehsung.aingcheck.core.wire.models.PhoneWorkResponse
import com.yehsung.aingcheck.core.wire.models.TodoSyncResponse
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.core.wire.models.DisplayNameChangeResponse
import com.yehsung.aingcheck.core.wire.models.MessageSendOutcome
import com.yehsung.aingcheck.core.wire.models.MiniGameAllTimeEntry
import com.yehsung.aingcheck.core.wire.models.PokeSendOutcome
import com.yehsung.aingcheck.core.wire.models.PokeSendResponse
import com.yehsung.aingcheck.core.wire.models.ShopCharacterRow
import com.yehsung.aingcheck.core.wire.models.microsecondsSinceEpoch
import com.yehsung.aingcheck.core.wire.models.sortedForMiniGameAllTimeBoard
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class WireRulesGoldenTest {
    private val dump = WireDecodeGoldenTest.dumper

    @Test
    fun wireFileRulesMatchSwift() {
        val golden = Golden.load("wire/rules")
        val problems = mutableListOf<String>()
        fun check(id: String, want: JsonElement, got: JsonElement) {
            if (GoldenCanonical.text(want) != GoldenCanonical.text(got)) problems += golden.failure(id, "Swift ${GoldenCanonical.text(want).trim()} · Kotlin ${GoldenCanonical.text(got).trim()}")
        }
        for (c in golden.cases) {
            val id = c.string("id")
            when {
                id == "alltime-sort" -> {
                    val entries = c.array("input").map { e ->
                        val o = e as JsonObject
                        val bits = (o["bestAtBits"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                        MiniGameAllTimeEntry(
                            userID = o.string("userID"), name = "", avatarURL = null,
                            bestScore = o["bestScore"]!!.jsonPrimitive.content.toLong(),
                            bestAt = bits?.let { SwiftDate(Golden.bits(it)) }, day = null,
                        )
                    }
                    check(id, c["sorted"]!!, JsonArray(entries.sortedForMiniGameAllTimeBoard().map { JsonPrimitive(it.userID) }))
                }
                id.startsWith("day-caption") -> {
                    val day = (c["day"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
                    check(id, c["caption"]!!, MiniGameAllTimeEntry.dayCaption(day)?.let { JsonPrimitive(it) } ?: JsonNull)
                }
                id.startsWith("shop-row-") -> {
                    val row = SwiftJson.decode(ShopRowDump.serializer(), c.obj("row")).toRow()
                    check(id, JsonObject(mapOf("a" to c["isPurchasable"]!!, "b" to c["isGiftOnly"]!!, "c" to c["isGachaOnly"]!!)),
                        JsonObject(mapOf("a" to JsonPrimitive(row.isPurchasable), "b" to JsonPrimitive(row.isGiftOnly), "c" to JsonPrimitive(row.isGachaOnly))))
                }
                id.startsWith("gift-choosable-") ->
                    check(id, c["choosable"]!!, JsonArray(CharacterGiftOffer.choosable(c.array("raw").map { it.jsonPrimitive.content }).map { JsonPrimitive(it) }))
                id.startsWith("micros-") -> {
                    val got = microsecondsSinceEpoch(c.string("text")) { s -> if ('.' in s.substringAfter('T')) null else SwiftISO8601.parse(s) }
                    check(id, c["micros"]!!, got?.let { JsonPrimitive(Golden.hex64Text(it.toULong())) } ?: JsonNull)
                }
                id.startsWith("send-outcome-") -> {
                    val r = SwiftJson.decode(PokeSendResponse.serializer(), c.obj("response").toSnake())
                    check(id, JsonObject(mapOf("p" to c["poke"]!!, "m" to c["message"]!!)),
                        JsonObject(mapOf("p" to dump.dump(PokeSendOutcome.of(r)), "m" to dump.dump(MessageSendOutcome.of(r)))))
                }
                id.startsWith("display-name-") -> {
                    val r = SwiftJson.decode(DisplayNameChangeResponse.serializer(), c.obj("response").toSnake())
                    check(id, c["outcome"]!!, dump.dump(DisplayNameChangeOutcome.of(r)))
                }
                id.startsWith("url-") -> {
                    val got = SwiftURL.parse(c.string("text"))?.let { JsonPrimitive(it.absoluteString) } ?: JsonNull
                    if (GoldenCanonical.text(c["url"]!!) != GoldenCanonical.text(got)) {
                        urlDiverged += id
                        if (id !in urlAllowed) check(id, c["url"]!!, got)
                    }
                }
                id.startsWith("date-") -> {
                    val got = SwiftISO8601.parse(c.string("text"))?.let { GoldenDump.date(it.timeIntervalSince1970) } ?: JsonNull
                    if (GoldenCanonical.text(c["date"]!!) != GoldenCanonical.text(got)) {
                        dateDiverged += id
                        if (id !in dateAllowed) check(id, c["date"]!!, got)
                    }
                }
                id.startsWith("todo-response-") -> {
                    val got = try {
                        dump.dump(SwiftJson.decode(TodoSyncResponse.serializer(), c.string("json")))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        JsonPrimitive("error")
                    }
                    check(id, c["decoded"]!!, got)
                }
                id.startsWith("app-user-characters-fold-") -> {
                    val raw = (c["raw"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
                    check(id, JsonObject(mapOf("f" to c["folded"]!!, "u" to c["userKey"]!!)), JsonObject(mapOf(
                        "f" to JsonPrimitive(AppUserCharacterDirectory.foldedEquippedID(raw)),
                        "u" to (AppUserCharacterDirectory.normalizedUserID(raw)?.let { JsonPrimitive(it) } ?: JsonNull),
                    )))
                }
                id.startsWith("app-user-characters-") -> {
                    val stage = id.removePrefix("app-user-characters-")
                    check(id, c["snapshot"]!!, directorySnapshot(directoryAt(stage)))
                    directoryStages += stage
                }
                id.startsWith("feedback-compose-") -> {
                    val text = c.string("text")
                    val note = FeedbackComposer.normalizedNote(text, Graphemes)
                    check(id, JsonObject(c.filterKeys { it != "id" && it != "text" }), JsonObject(mapOf(
                        "normalized" to JsonPrimitive(FeedbackComposer.normalized(text)),
                        "isSendable" to JsonPrimitive(FeedbackComposer.isSendable(text, Graphemes)),
                        "counterText" to JsonPrimitive(FeedbackComposer.counterText(text, Graphemes)),
                        "isCounterWarning" to JsonPrimitive(FeedbackComposer.isCounterWarning(text, Graphemes)),
                        "normalizedNote" to (note?.let { JsonPrimitive(it) } ?: JsonNull),
                        "isSendableReplyNil" to JsonPrimitive(FeedbackComposer.isSendableReply(text, null, Graphemes)),
                        "isSendableReplySame" to JsonPrimitive(FeedbackComposer.isSendableReply(text, note, Graphemes)),
                    )))
                }
                id.startsWith("feedback-text-") -> {
                    val name = c.string("name")
                    val value = feedbackConstant(name)
                    check(id, JsonObject(mapOf("v" to c["value"]!!, "s" to c["isSuccessNotice"]!!)),
                        JsonObject(mapOf("v" to JsonPrimitive(value), "s" to JsonPrimitive(FeedbackText.isSuccessNotice(value)))))
                }
                id.startsWith("feedback-filter-empty-") ->
                    check(id, c["text"]!!, JsonPrimitive(FeedbackText.inboxFilterEmpty(FeedbackStatus.of(c.string("status")))))
                id.startsWith("feedback-auto-attach-") -> {
                    val build = (c["build"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content?.toLong()
                    check(id, c["text"]!!, JsonPrimitive(FeedbackText.autoAttachNotice(c.string("appVersion"), build, c.string("osVersion"))))
                }
                id.startsWith("feedback-age-") -> {
                    val ago = (c["secondsAgo"] as? JsonObject)?.let { Golden.bits((it["\$f64"] as JsonPrimitive).content) }
                    val now = SwiftDate(1_789_621_500.0)
                    check(id, c["text"]!!, JsonPrimitive(FeedbackText.ageText(ago?.let { now.addingTimeInterval(-it) }, now)))
                }
                id.startsWith("phone-work-outcome-") -> {
                    val response = SwiftJson.decode(PhoneWorkResponse.serializer(), c.string("json"))
                    check(id, c["outcome"]!!, phoneWorkOutcome(PhoneWorkOutcome.from(response)))
                }
                else -> problems += "모르는 case $id"
            }
        }
        // 알려진 갈림(골든 spec 이 이유와 함께 적은 목록)은 **정확히** 그 집합이어야 한다 — 늘어도(새 갈림) 줄어도(고쳤으면 목록부터) 빨강.
        assertEquals(urlAllowed, urlDiverged, "URL(string:) 갈림이 spec.urlKnownDivergence 와 다르다")
        assertEquals(dateAllowed, dateDiverged, "parseDate 갈림이 spec.dateKnownDivergence 와 다르다")
        assertEquals(setOf("built", "setEquipped", "replaced", "removed"), directoryStages, "아바타 디렉터리 대본 단계")
        println(
            "AINGCHECK-WIRE-RULES cases=${golden.cases.size} problems=${problems.size} " +
                "urlDivergence=${urlDiverged.size} dateDivergence=${dateDiverged.size}",
        )
        if (problems.isNotEmpty()) fail(problems.joinToString("\n\n"))
    }

    private val urlDiverged = mutableSetOf<String>()
    private val dateDiverged = mutableSetOf<String>()
    private val directoryStages = mutableSetOf<String>()
    private val urlAllowed: Set<String> by lazy { Golden.load("wire/rules").spec.array("urlKnownDivergence").map { (it as JsonObject).string("id") }.toSet() }
    private val dateAllowed: Set<String> by lazy { Golden.load("wire/rules").spec.array("dateKnownDivergence").map { (it as JsonObject).string("id") }.toSet() }

    /** JVM 그래핌(데스크톱 = JDK BreakIterator — 앱 조립의 GraphemeCounter 와 같은 몫). */
    private object Graphemes : GraphemeCounter {
        override fun count(text: String): Int {
            val it = java.text.BreakIterator.getCharacterInstance()
            it.setText(text)
            var n = 0
            while (it.next() != java.text.BreakIterator.DONE) n++
            return n
        }
    }

    private fun feedbackConstant(name: String): String = when (name) {
        "windowTitle" -> FeedbackText.windowTitle; "sendTab" -> FeedbackText.sendTab; "inboxTab" -> FeedbackText.inboxTab
        "placeholder" -> FeedbackText.placeholder; "sendAction" -> FeedbackText.sendAction; "sending" -> FeedbackText.sending
        "sendSuccess" -> FeedbackText.sendSuccess; "rateLimited" -> FeedbackText.rateLimited; "sendFailed" -> FeedbackText.sendFailed
        "sendSchemaMissing" -> FeedbackText.sendSchemaMissing; "forbidden" -> FeedbackText.forbidden; "statusFailed" -> FeedbackText.statusFailed
        "mineTitle" -> FeedbackText.mineTitle; "mineEmpty" -> FeedbackText.mineEmpty; "inboxEmpty" -> FeedbackText.inboxEmpty
        "inboxEmptyHint" -> FeedbackText.inboxEmptyHint; "inboxFilterEmptyHint" -> FeedbackText.inboxFilterEmptyHint
        "filterAll" -> FeedbackText.filterAll; "loading" -> FeedbackText.loading; "failed" -> FeedbackText.failed; "retry" -> FeedbackText.retry
        "notePlaceholder" -> FeedbackText.notePlaceholder; "noteSave" -> FeedbackText.noteSave; "replyAction" -> FeedbackText.replyAction
        "replySending" -> FeedbackText.replySending; "replyBlockTitle" -> FeedbackText.replyBlockTitle; "replySent" -> FeedbackText.replySent
        "replyFailed" -> FeedbackText.replyFailed; "replySchemaMissing" -> FeedbackText.replySchemaMissing; "replyEmpty" -> FeedbackText.replyEmpty
        "replyTooLong" -> FeedbackText.replyTooLong; "replyNotFound" -> FeedbackText.replyNotFound
        "maxBodyLength" -> FeedbackComposer.maxBodyLength.toString(); "warnBodyLength" -> FeedbackComposer.warnBodyLength.toString()
        "maxNoteLength" -> FeedbackComposer.maxNoteLength.toString()
        else -> error("모르는 FeedbackText 이름 $name — Kotlin 에 옮겼는가")
    }

    private fun phoneWorkOutcome(o: PhoneWorkOutcome): JsonElement = when (o) {
        is PhoneWorkOutcome.Working -> JsonObject(mapOf("case" to JsonPrimitive("working"), "session" to dump.dump(o.session), "alreadyWorking" to JsonPrimitive(o.alreadyWorking)))
        is PhoneWorkOutcome.Stopped -> JsonObject(mapOf("case" to JsonPrimitive("stopped"), "session" to (o.session?.let { dump.dump(it) } ?: JsonNull)))
        is PhoneWorkOutcome.NotWorking -> JsonObject(mapOf("case" to JsonPrimitive("notWorking"), "last" to (o.last?.let { dump.dump(it) } ?: JsonNull)))
        PhoneWorkOutcome.Mismatch -> JsonObject(mapOf("case" to JsonPrimitive("mismatch")))
        PhoneWorkOutcome.NoTeam -> JsonObject(mapOf("case" to JsonPrimitive("noTeam")))
        PhoneWorkOutcome.Unauthorized -> JsonObject(mapOf("case" to JsonPrimitive("unauthorized")))
        PhoneWorkOutcome.Failed -> JsonObject(mapOf("case" to JsonPrimitive("failed")))
    }

    // ---- 아바타 디렉터리 대본(Swift appUserCharacterCases 와 같은 입력·순서) ----

    private fun row(user: String?, character: String?) = AppUserCharacterRow(user, character)

    private fun directoryAt(stage: String): AppUserCharacterDirectory {
        val d = AppUserCharacterDirectory(
            listOf("robot", " fox ", "", "aing_cake_choco", "ROBOT"),
            listOf(
                row("AA-1", "robot"), row("bb-2", null), row("cc-3", "  "), row("dd-4", "unicorn"), row(" ee-5 ", " fox "),
                row(null, "fox"), row("  ", "robot"), row("aa-1", "aing_cake_choco"),
            ),
        )
        if (stage == "built") return d
        d.setEquipped("unicorn", "aa-1")
        d.setEquipped(null, "ZZ-9")
        d.setEquipped("robot", "  ")
        if (stage == "setEquipped") return d
        d.replace(listOf(row("dd-4", "fox"), row("ff-6", null)))
        if (stage == "replaced") return d
        d.removeAll()
        return d
    }

    private fun avatar(a: AppUserAvatar): JsonElement = when (a) {
        is AppUserAvatar.Photo -> JsonObject(mapOf("kind" to JsonPrimitive("photo"), "url" to JsonPrimitive(a.url.absoluteString), "fallback" to (a.fallbackCharacterID?.let { JsonPrimitive(it) } ?: JsonNull)))
        is AppUserAvatar.Character -> JsonObject(mapOf("kind" to JsonPrimitive("character"), "id" to JsonPrimitive(a.id)))
        AppUserAvatar.Initials -> JsonObject(mapOf("kind" to JsonPrimitive("initials")))
    }

    private fun directorySnapshot(d: AppUserCharacterDirectory): JsonElement {
        val users = listOf("aa-1", "AA-1", " aa-1 ", "bb-2", "cc-3", "dd-4", "ee-5", "zz-9", null, "")
        val hints = listOf(null, "robot", "fox", "unicorn", " robot ", "", "aing")
        val photo = SwiftURL.parse("https://golden.invalid/p.jpg")!!
        fun s(v: String?): JsonElement = v?.let { JsonPrimitive(it) } ?: JsonNull
        return JsonObject(mapOf(
            "count" to JsonPrimitive(d.count), "isEmpty" to JsonPrimitive(d.isEmpty),
            "knownIDs" to JsonArray(d.knownIDs.sorted().map { JsonPrimitive(it) }),
            "users" to JsonArray(users.map { user ->
                JsonObject(mapOf(
                    "user" to s(user),
                    "characterID" to s(d.characterID(user)),
                    "equippedID" to s(d.equippedID(user)),
                    "avatarNoPhoto" to avatar(d.avatar(user, null)),
                    "avatarPhoto" to avatar(d.avatar(user, photo)),
                    "afterPhotoFailure" to avatar(d.avatar(user, photo).afterPhotoFailure),
                    "hinted" to JsonArray(hints.map { h -> JsonArray(listOf(avatar(d.avatar(user, null, h)), avatar(d.avatar(user, photo, h)))) }),
                ))
            }),
        ))
    }

    /** 덤프(camel 키)를 전선 키(snake)로 — 같은 디코더로 다시 읽게. */
    private fun JsonObject.toSnake(): JsonObject = JsonObject(entries.associate { (k, v) -> SwiftKeys.toSnakeCase(k) to v })

    @Serializable
    private data class ShopRowDump(
        @SerialName("id") val id: String,
        @SerialName("price") val price: Long? = null,
        @SerialName("owned") val owned: Boolean? = null,
        @SerialName("gacha_only") val gachaOnly: Boolean? = null,
        @SerialName("gift_only") val giftOnly: Boolean? = null,
    ) {
        fun toRow() = ShopCharacterRow(id, price, owned, gachaOnly, giftOnly)
    }

    @Serializable private data class I(@SerialName("v") val v: Long)
    @Serializable private data class D(@SerialName("v") val v: Double)
    @Serializable private data class B(@SerialName("v") val v: Boolean)
    @Serializable private data class S(@SerialName("v") val v: String)
    @Serializable private data class O(@SerialName("v") val v: Long? = null)

    private fun <T> run(text: String, ser: kotlinx.serialization.KSerializer<T>, show: (T) -> JsonElement): JsonElement = try {
        show(SwiftJson.decode(ser, text))
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        JsonPrimitive("error")
    }

    private fun int(v: Long) = JsonObject(mapOf("\$int" to JsonPrimitive(Golden.hex64Text(v.toULong()))))

    @Test
    fun numbersMatchSwift() {
        val golden = Golden.load("wire/numbers")
        val problems = mutableListOf<String>()
        for (c in golden.cases) {
            val lit = c.string("id")
            val text = """{"v":$lit}"""
            val got = JsonObject(
                mapOf(
                    "Int" to run(text, I.serializer()) { int(it.v) },
                    "Double" to run(text, D.serializer()) { JsonObject(mapOf("\$f64" to JsonPrimitive(Golden.bitsText(it.v)))) },
                    "Bool" to run(text, B.serializer()) { JsonPrimitive(it.v) },
                    "String" to run(text, S.serializer()) { JsonPrimitive(it.v) },
                    "OptionalInt" to run(text, O.serializer()) { o -> o.v?.let { int(it) } ?: JsonNull },
                ),
            )
            val want = JsonObject(c.filterKeys { it != "id" })
            if (GoldenCanonical.text(want) != GoldenCanonical.text(got)) problems += golden.failure(lit, "Swift ${GoldenCanonical.text(want)} Kotlin ${GoldenCanonical.text(got)}")
        }
        println("AINGCHECK-NUMBERS cases=${golden.cases.size} problems=${problems.size}")
        assertTrue(golden.cases.size >= 40)
        if (problems.isNotEmpty()) fail(problems.joinToString("\n\n"))
    }

    /** C-X3 실험 표(W0-b 탐침 — "Kotlin 대조는 W1-d")의 키 변환 두 표를 [SwiftKeys] 가 그대로 낸다. */
    @Test
    fun keyConversionMatchesDecoderProbe() {
        val probe = Golden.loadProbe("w0b-probe/decoder")
        fun cps(s: String) = s.split(' ').filter { it.isNotEmpty() }.map { it.toInt(16) }.joinToString("") { String(Character.toChars(it)) }
        val decoded = probe.case("keys-decoded").obj("map")
        val encoded = probe.case("keys-encoded").obj("map")
        var n = 0
        for ((k, v) in decoded) {
            assertEquals(cps(v.jsonPrimitive.content), SwiftKeys.fromSnakeCase(cps(k)), "convertFromSnakeCase(${cps(k)})")
            n++
        }
        for ((k, v) in encoded) {
            assertEquals(v.jsonPrimitive.content, SwiftKeys.toSnakeCase(k), "convertToSnakeCase($k)")
            n++
        }
        assertTrue(n >= 30, "키 표가 비었다($n)")
    }

    /** C-X3 실험 표의 값 판정(Int·Int64·Int32·Double·Bool·String·OptionalInt). UInt64 칸은 와이어 타입에 없어 재지 않는다. */
    @Test
    fun valueDecodingMatchesDecoderProbe() {
        val probe = Golden.loadProbe("w0b-probe/decoder")
        @Serializable data class I32(@SerialName("value") val value: Int)
        @Serializable data class L(@SerialName("value") val value: Long)
        @Serializable data class DD(@SerialName("value") val value: Double)
        @Serializable data class BB(@SerialName("value") val value: Boolean)
        @Serializable data class SS(@SerialName("value") val value: String)
        @Serializable data class OO(@SerialName("value") val value: Long? = null)
        val problems = mutableListOf<String>()
        var n = 0
        for (c in probe.cases) {
            val results = (c["results"] as? JsonObject) ?: continue
            val json = c.string("json")
            fun okOrError(block: () -> String): String = try { "ok:" + block() } catch (e: CancellationException) { throw e } catch (e: Exception) { "error" }
            val got = mapOf(
                "Int" to okOrError { SwiftJson.decode(L.serializer(), json).value.toString() },
                "Int64" to okOrError { SwiftJson.decode(L.serializer(), json).value.toString() },
                "Int32" to okOrError { SwiftJson.decode(I32.serializer(), json).value.toString() },
                "Double" to okOrError { Golden.bitsText(SwiftJson.decode(DD.serializer(), json).value) },
                "Bool" to okOrError { SwiftJson.decode(BB.serializer(), json).value.toString() },
                "String" to okOrError { SwiftJson.decode(SS.serializer(), json).value },
                "OptionalInt" to okOrError { SwiftJson.decode(OO.serializer(), json).value?.toString() ?: "nil" },
            )
            for ((kind, value) in got) {
                val want = results[kind]?.jsonPrimitive?.content ?: continue
                val wantNorm = if (want.startsWith("error")) "error" else want
                n++
                if (wantNorm != value) problems += "${c.string("id")} $kind: Swift $want · Kotlin $value"
            }
        }
        println("AINGCHECK-CX3 checks=$n problems=${problems.size}")
        assertTrue(n >= 150, "C-X3 값 표가 비었다($n)")
        if (problems.isNotEmpty()) fail(problems.joinToString("\n"))
    }
}
