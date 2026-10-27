// 원본: 없음 — 와이어 파일 안 규칙(역대 순위 정렬·날짜 캡션 · 상점 판정 · 선물 선택지 · 마이크로초 · 결과 갈래)과 숫자 판정 골든 대조, C-X3 키 변환 표 대조
package com.yehsung.aingcheck.core.wire

import com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.SwiftKeys
import com.yehsung.aingcheck.core.wire.models.DisplayNameChangeOutcome
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
                else -> problems += "모르는 case $id"
            }
        }
        println("AINGCHECK-WIRE-RULES cases=${golden.cases.size} problems=${problems.size}")
        if (problems.isNotEmpty()) fail(problems.joinToString("\n\n"))
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
