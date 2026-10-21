// 원본: Tests/CheckGoldenSupport/GoldenMirror.swift(덤프 규칙) · Tests/checkTests/GoldenExport/_base/GoldenExportProbeW0b.swift(mirrorSamples) @ W0-b
package com.yehsung.aingcheck.testkit.golden

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.lang.reflect.Modifier
import java.net.URI
import java.util.Base64
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * C-X10 Kotlin 몫: Swift Mirror 정규 덤프(`w0b-probe/mirror-dump`)를 **Kotlin 리플렉션으로 같은 바이트**로 낼 수 있는가.
 * 이 파일의 덤프기는 타당성 탐침이다(JDK 리플렉션만 — testkit 에는 kotlin-reflect 가 없다). 운영 G6 덤프기는 W1-d 가
 * kotlin-reflect 로 짓는다(core/wire desktopTest). 규칙 정본: contract/README.md 「디코드 덤프 규칙(G6)」.
 *
 * Kotlin 쪽 모양 약속(덤프기가 기대는 것):
 *  · 연관값 없는 Swift 열거 → Kotlin `enum class`, 상수 이름 = Swift case 이름 그대로(`notSignedIn`).
 *  · 연관값 있는 Swift 열거 → `sealed interface` + 갈래마다 `data object`/`data class`. 갈래 클래스 이름은 Swift case 이름의
 *    첫 글자만 대문자로 써도 된다(덤프기가 첫 글자를 소문자로 접는다). 연관값 하나 → 칸 하나, 이름표 있는 둘 이상 → 같은 이름의 칸,
 *    이름표 없는 둘 이상 → `v0`·`v1`… (덤프기가 배열로 낸다).
 *  · Swift `Date` → [SwiftDate](1970 기준 초 Double — C§2.5 "Date 산술은 Double 초로 1:1"). Instant 로 바꾸면 비트가 갈릴 수 있다.
 *  · 겹친 Optional 은 없다(Swift 쪽 규칙이 null 로 접는다).
 */
class MirrorDumpProbeTest {
    data class SwiftDate(val since1970: Double)
    class SwiftData(val bytes: ByteArray)

    // ---- Swift 타입의 Kotlin 꼴(이름은 Swift 그대로 — C§2.3) ----
    @Suppress("EnumEntryName")
    enum class TetrisRPCStatus { ok, notSignedIn, unsupportedClient, invalid, unknown }

    sealed interface GachaPullStatus {
        data object Ok : GachaPullStatus
        data class Unknown(val value: String) : GachaPullStatus
    }

    @Suppress("EnumEntryName")
    enum class IdleReason { signedOut, suspended, disabled }

    @Suppress("EnumEntryName")
    enum class RealtimeFailure { unauthorized, topicDenied, exhausted }

    data class Backoff(val attempt: Int, val retryAt: SwiftDate, val failingSince: SwiftDate)

    sealed interface RealtimeState {
        data class Idle(val reason: IdleReason) : RealtimeState
        data class Connecting(val attempt: Int, val since: SwiftDate) : RealtimeState
        data class Subscribed(val since: SwiftDate, val lastHeardAt: SwiftDate) : RealtimeState
        data class Failed(val v0: Backoff, val v1: RealtimeFailure) : RealtimeState
    }

    sealed interface RealtimeJoinRejection {
        data class Unknown(val value: String) : RealtimeJoinRejection
    }

    sealed interface RealtimeTransportEvent {
        data class Closed(val code: Int?) : RealtimeTransportEvent
        data class JoinRejected(val rejection: RealtimeJoinRejection) : RealtimeTransportEvent
    }

    sealed interface Phase {
        data class LineClear(val remaining: Double) : Phase
    }

    data class GachaOddsEntry(val characterID: String, val percent: Double)
    data class GachaInfo(val price: Int?, val shards: Int?, val odds: List<GachaOddsEntry>?, val shardCosts: Map<String, Int>?)

    data class DumpSample(
        val tags: Set<String>, val byNumber: Map<Int, String>, val big: ULong, val small: Long, val ratio: Float,
        val blob: SwiftData, val token: UUID, val link: URI, val initial: Char, val maybe: List<Int?>, val nested: Int?,
    )

    open class DumpBase { val baseValue = 1 }
    class DumpDerived : DumpBase() { val derivedValue = "d" }

    // ---- JDK 리플렉션 덤프기(타당성 탐침) ----
    object JvmDump {
        private fun integer(x: Long): JsonElement =
            if (x in -GoldenCanonical.MAX_SAFE_INTEGER..GoldenCanonical.MAX_SAFE_INTEGER) JsonPrimitive(x)
            else JsonObject(mapOf("\$int" to JsonPrimitive(Golden.hex64Text(x.toULong()))))

        private fun f64(x: Double) = JsonObject(mapOf("\$f64" to JsonPrimitive(Golden.bitsText(x))))

        private fun fields(cls: Class<*>): List<java.lang.reflect.Field> {
            val out = mutableListOf<java.lang.reflect.Field>()
            var c: Class<*>? = cls
            while (c != null && c != Any::class.java) {
                out += c.declaredFields.filter { !Modifier.isStatic(it.modifiers) && !it.isSynthetic && '$' !in it.name }
                c = c.superclass
            }
            return out
        }

        private fun isCase(cls: Class<*>): Boolean =
            (cls.superclass?.isSealed == true) || cls.interfaces.any { it.isSealed }

        private fun sortedByText(items: List<JsonElement>) =
            JsonArray(items.map { it to GoldenCanonical.text(it) }.sortedWith { a, b -> GoldenCanonical.codePointOrder.compare(a.second, b.second) }.map { it.first })

        fun dump(value: Any?): JsonElement = when (value) {
            null -> JsonNull
            is Boolean -> JsonPrimitive(value)
            is String -> JsonPrimitive(value)
            is Char -> JsonPrimitive(value.toString())
            is Int -> integer(value.toLong())
            is Long -> integer(value)
            is ULong -> if (value <= GoldenCanonical.MAX_SAFE_INTEGER.toULong()) JsonPrimitive(value.toLong())
                else JsonObject(mapOf("\$int" to JsonPrimitive(Golden.hex64Text(value))))
            is Double -> f64(value)
            is Float -> f64(value.toDouble())
            is SwiftDate -> JsonObject(mapOf("\$date" to JsonPrimitive(Golden.bitsText(value.since1970))))
            is SwiftData -> JsonObject(mapOf("\$data" to JsonPrimitive(Base64.getEncoder().encodeToString(value.bytes))))
            is UUID -> JsonObject(mapOf("\$uuid" to JsonPrimitive(value.toString().lowercase())))
            is URI -> JsonObject(mapOf("\$url" to JsonPrimitive(value.toString())))
            is Enum<*> -> JsonPrimitive(value.name)
            is Set<*> -> sortedByText(value.map { dump(it) })
            is List<*> -> JsonArray(value.map { dump(it) })
            is Map<*, *> -> if (value.keys.all { it is String }) {
                JsonObject(value.entries.associate { (k, v) -> k as String to dump(v) })
            } else {
                sortedByText(value.entries.map { (k, v) -> JsonArray(listOf(dump(k), dump(v))) })
            }
            else -> {
                val cls = value.javaClass
                val fs = fields(cls).onEach { it.isAccessible = true }
                if (isCase(cls)) {
                    val name = cls.simpleName.replaceFirstChar { it.lowercaseChar() }
                    when {
                        fs.isEmpty() -> JsonPrimitive(name)
                        fs.size == 1 -> JsonObject(mapOf("\$case" to JsonPrimitive(name), "\$value" to dump(fs[0].get(value))))
                        fs.all { Regex("""v\d+""").matches(it.name) } ->
                            JsonObject(mapOf("\$case" to JsonPrimitive(name), "\$value" to JsonArray(fs.sortedBy { it.name.drop(1).toInt() }.map { dump(it.get(value)) })))
                        else -> JsonObject(mapOf("\$case" to JsonPrimitive(name), "\$value" to JsonObject(fs.associate { it.name to dump(it.get(value)) })))
                    }
                } else {
                    JsonObject(fs.associate { it.name to dump(it.get(value)) })
                }
            }
        }
    }

    private val t0 = SwiftDate(1_790_000_000.25)
    private val t1 = SwiftDate(1_790_000_030.5)

    /** Swift `GoldenExportProbeW0b.mirrorSamples()` 와 같은 id · 같은 값. */
    private fun samples(): Map<String, Any?> = mapOf(
        "tetris-rpc-status" to TetrisRPCStatus.notSignedIn,
        "tetris-rpc-status-unknown" to TetrisRPCStatus.unknown,
        "gacha-pull-status-ok" to GachaPullStatus.Ok,
        "gacha-pull-status-unknown" to GachaPullStatus.Unknown("weird_status"),
        "realtime-idle" to RealtimeState.Idle(IdleReason.disabled),
        "realtime-connecting" to RealtimeState.Connecting(3, t0),
        "realtime-subscribed" to RealtimeState.Subscribed(t0, t1),
        "realtime-failed" to RealtimeState.Failed(Backoff(2, t1, t0), RealtimeFailure.topicDenied),
        "transport-closed-nil" to RealtimeTransportEvent.Closed(null),
        "transport-closed-1006" to RealtimeTransportEvent.Closed(1006),
        "transport-join-rejected" to RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.Unknown("x")),
        "tetris-phase-line-clear" to Phase.LineClear(0.25),
        "gacha-info" to GachaInfo(50, null, listOf(GachaOddsEntry("aing_gold", 3.0), GachaOddsEntry("robot", 97.0)),
            mapOf("aing_gold" to 20, "robot" to 4)),
        "gacha-info-empty" to GachaInfo(null, null, null, null),
        "optional-some-nil" to null,
        "optional-some-some" to 5,
        "optional-none" to null,
        "sample-struct" to DumpSample(setOf("b", "a", "가"), mapOf(10 to "ten", 2 to "two"), ULong.MAX_VALUE, Long.MIN_VALUE,
            0.1f, SwiftData(byteArrayOf(0, 1, 2, 250.toByte())), UUID.fromString("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"),
            URI("https://aingcheck.invalid/a?b=1"), '한', listOf(1, null, 3), null),
        "class-derived" to DumpDerived(),
    )

    @Test
    fun kotlinReflectionReproducesSwiftMirrorDumpBytes() {
        val table = Golden.loadProbe("w0b-probe/mirror-dump")
        val values = samples()
        val mismatches = mutableListOf<String>()
        for (case in table.cases) {
            val id = case.string("id")
            assertTrue(id in values, "Swift 표본 '$id' 의 Kotlin 꼴이 없다(표본을 더했으면 여기에도)")
            val want = GoldenCanonical.text(case["dump"]!!)
            val got = GoldenCanonical.text(JvmDump.dump(values[id]))
            if (want != got) mismatches += id
        }
        println("AINGCHECK-PROBE C-X10 mirror-dump cases=${table.cases.size} kotlinMatches=${table.cases.size - mismatches.size} mismatches=$mismatches")
        // 알려진 한계 하나(측정값): JDK 리플렉션은 data class 의 ULong 칸을 밑 타입 long 으로 본다(인라인 값 클래스) — "big" 이
        // {"$int":"0xffff…"} 대신 -1 로 나온다. 그래서 운영 G6 덤프기(W1-d)는 kotlin-reflect 의 선언 타입으로 칸을 읽어야 한다.
        // 그 칸 하나를 빼면 나머지는 바이트까지 같아야 한다(예외를 칸 하나로 좁힌다 — 다른 불일치가 생기면 빨강).
        assertEquals(listOf("sample-struct"), mismatches, "Swift 덤프와 다른 표본")
        val sample = table.case("sample-struct")["dump"] as JsonObject
        val kotlinSample = JvmDump.dump(values["sample-struct"]) as JsonObject
        assertEquals(JsonPrimitive(-1L), kotlinSample["big"], "ULong 칸의 JDK 리플렉션 한계가 사라졌다 — 측정을 다시 하라")
        assertEquals(GoldenCanonical.text(JsonObject(sample - "big")), GoldenCanonical.text(JsonObject(kotlinSample - "big")))
    }

    /** 대조: 갈래 이름 하나·Double 비트 하나만 달라도 덤프가 갈린다(덤프기가 값을 실제로 본다). */
    @Test
    fun dumpSeesTheValues() {
        val a = GoldenCanonical.text(JvmDump.dump(RealtimeState.Connecting(3, t0)))
        val b = GoldenCanonical.text(JvmDump.dump(RealtimeState.Connecting(3, SwiftDate(Math.nextUp(t0.since1970)))))
        val c = GoldenCanonical.text(JvmDump.dump(RealtimeState.Idle(IdleReason.disabled)))
        assertTrue(a != b && a != c)
        assertTrue(JvmDump.dump(GachaPullStatus.Ok) == JsonPrimitive("ok"), "isSealed 로 갈래를 못 알아봤다(data object → 이름 글자여야)")
    }
}
