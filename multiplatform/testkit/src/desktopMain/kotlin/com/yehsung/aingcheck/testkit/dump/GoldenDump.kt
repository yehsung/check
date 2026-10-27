// 원본: Tests/CheckGoldenSupport/GoldenMirror.swift(G6 정규 덤프 규칙) @ 1b8260d · contract/README.md §2-3
package com.yehsung.aingcheck.testkit.dump

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.URI
import java.util.Base64
import java.util.UUID
import kotlin.reflect.KClass
import kotlin.reflect.KProperty1
import kotlin.reflect.full.memberProperties
import kotlin.reflect.jvm.isAccessible
import kotlin.reflect.jvm.javaField

/**
 * G6 디코드 덤프기 — Swift `GoldenMirror.dump` 와 **같은 바이트**를 낸다(규칙 정본 contract/README.md §2-3, C-X10).
 *
 * kotlin-reflect 의 **선언 타입**으로 칸을 읽는다(JDK 리플렉션은 `ULong` 같은 인라인 값 클래스를 밑 타입으로 보여
 * `UInt64.max` 가 -1 로 나온다 — MirrorDumpProbeTest 실측). 저장 칸 = 뒷받침 필드가 있는 프로퍼티(계산 프로퍼티는 Swift
 * Mirror 처럼 빠진다). 클래스는 상위 클래스 칸까지.
 *
 * 모양 약속(Kotlin 쪽 — README):
 *  · 연관값 없는 Swift 열거 → `enum class`(상수 이름 = Swift case 이름).
 *  · 연관값 있는 Swift 열거 → sealed 갈래(data object/data class). 갈래 이름은 첫 글자만 대문자여도 된다(여기서 내린다).
 *    칸 하나 → 그 값, 칸 이름이 `v0`·`v1`… → 위치 배열, 아니면 객체.
 *  · Swift `Date`·`URL`·`Data` 는 갈래가 쓰는 Kotlin 타입이 모듈마다 달라 [leaf] 갈고리로 받는다(예: core/wire 의 SwiftDate).
 *  · 그 밖의 값(람다·모르는 플랫폼 타입)은 실패한다 — 조용히 toString 으로 접지 않는다.
 */
class GoldenDump(
    /** 잎 값 갈고리: 처리하면 덤프를, 모르면 null. */
    private val leaf: (Any) -> JsonElement? = { null },
) {
    fun dump(value: Any?): JsonElement = dump(value, 0, "$")

    private fun dump(value: Any?, depth: Int, path: String): JsonElement {
        check(depth < MAX_DEPTH) { "$path: 깊이 $MAX_DEPTH 를 넘는다(순환 참조?)" }
        if (value == null) return JsonNull
        leaf(value)?.let { return it }
        return when (value) {
            is Boolean -> JsonPrimitive(value)
            is String -> JsonPrimitive(value)
            is Char -> JsonPrimitive(value.toString())
            is Int -> integer(value.toLong())
            is Long -> integer(value)
            is Short -> integer(value.toLong())
            is Byte -> integer(value.toLong())
            is UInt -> integer(value.toLong())
            is UShort -> integer(value.toLong())
            is UByte -> integer(value.toLong())
            is ULong -> if (value <= GoldenCanonical.MAX_SAFE_INTEGER.toULong()) JsonPrimitive(value.toLong())
                else JsonObject(mapOf("\$int" to JsonPrimitive(Golden.hex64Text(value))))
            is Double -> f64(value)
            is Float -> f64(value.toDouble())
            is UUID -> JsonObject(mapOf("\$uuid" to JsonPrimitive(value.toString().lowercase())))
            is URI -> JsonObject(mapOf("\$url" to JsonPrimitive(value.toString())))
            is ByteArray -> JsonObject(mapOf("\$data" to JsonPrimitive(Base64.getEncoder().encodeToString(value))))
            is Enum<*> -> JsonPrimitive(value.name)
            is Set<*> -> sortedByText(value.mapIndexed { i, v -> dump(v, depth + 1, "$path{$i}") })
            is List<*> -> JsonArray(value.mapIndexed { i, v -> dump(v, depth + 1, "$path[$i]") })
            is Map<*, *> -> if (value.keys.all { it is String }) {
                JsonObject(value.entries.associate { (k, v) -> k as String to dump(v, depth + 1, "$path.$k") })
            } else {
                sortedByText(value.entries.map { (k, v) -> JsonArray(listOf(dump(k, depth + 1, "$path{key}"), dump(v, depth + 1, "$path{value}"))) })
            }
            else -> structure(value, depth, path)
        }
    }

    private fun structure(value: Any, depth: Int, path: String): JsonElement {
        val cls = value::class
        check(!cls.java.isSynthetic && !cls.java.name.contains("\$\$Lambda")) { "$path: 덤프 규칙에 없는 값(람다) ${cls.java.name}" }
        check(!cls.java.name.startsWith("java.") && !cls.java.name.startsWith("kotlin.")) {
            "$path: 덤프 규칙에 없는 플랫폼 값 ${cls.java.name}"
        }
        val props = storedProperties(cls)
        if (isSealedCase(cls)) {
            val name = cls.simpleName!!.replaceFirstChar { it.lowercaseChar() }
            return when {
                props.isEmpty() -> JsonPrimitive(name)
                props.size == 1 -> JsonObject(mapOf("\$case" to JsonPrimitive(name), "\$value" to read(props[0], value, depth, "$path.$name")))
                props.all { POSITIONAL.matches(it.name) } -> JsonObject(mapOf(
                    "\$case" to JsonPrimitive(name),
                    "\$value" to JsonArray(props.sortedBy { it.name.drop(1).toInt() }.map { read(it, value, depth, "$path.$name.${it.name}") }),
                ))
                else -> JsonObject(mapOf(
                    "\$case" to JsonPrimitive(name),
                    "\$value" to JsonObject(props.associate { it.name to read(it, value, depth, "$path.$name.${it.name}") }),
                ))
            }
        }
        return JsonObject(props.associate { it.name to read(it, value, depth, "$path.${it.name}") })
    }

    private fun read(prop: KProperty1<Any, *>, owner: Any, depth: Int, path: String): JsonElement {
        prop.isAccessible = true
        return dump(prop.get(owner), depth + 1, path)
    }

    @Suppress("UNCHECKED_CAST")
    private fun storedProperties(cls: KClass<*>): List<KProperty1<Any, *>> =
        cls.memberProperties.filter { it.javaField != null && !java.lang.reflect.Modifier.isStatic(it.javaField!!.modifiers) }
            .map { it as KProperty1<Any, *> }
            .sortedBy { it.name }

    private fun isSealedCase(cls: KClass<*>): Boolean =
        cls.supertypes.any { (it.classifier as? KClass<*>)?.isSealed == true }

    private fun sortedByText(items: List<JsonElement>): JsonArray =
        JsonArray(items.map { it to GoldenCanonical.text(it) }
            .sortedWith { a, b -> GoldenCanonical.codePointOrder.compare(a.second, b.second) }
            .map { it.first })

    companion object {
        const val MAX_DEPTH = 48
        private val POSITIONAL = Regex("""v\d+""")

        fun integer(x: Long): JsonElement =
            if (x in -GoldenCanonical.MAX_SAFE_INTEGER..GoldenCanonical.MAX_SAFE_INTEGER) JsonPrimitive(x)
            else JsonObject(mapOf("\$int" to JsonPrimitive(Golden.hex64Text(x.toULong()))))

        fun f64(x: Double): JsonElement = JsonObject(mapOf("\$f64" to JsonPrimitive(Golden.bitsText(x))))

        /** Swift `Date` 꼴 — 1970 기준 초 Double 의 비트. */
        fun date(since1970: Double): JsonElement = JsonObject(mapOf("\$date" to JsonPrimitive(Golden.bitsText(since1970))))
    }
}

/**
 * 두 덤프의 다른 점(G6 변형 골든 "원본과 다른 점만" — Swift 내보내기의 `GoldenWireDiff` 와 같은 규칙):
 * 객체는 키 합집합을 코드포인트 순서로 돌며 한쪽에만 있으면 `"$absent"`, 배열은 길이가 다르면 배열 통째, 같으면 원소마다,
 * 잎은 정규 글자가 다르면 그 자리의 새 값. 결과는 `[[경로, 새 값], …]`(경로 순서 = 걷는 순서).
 */
object GoldenDumpDiff {
    val ABSENT: JsonElement = JsonPrimitive("\$absent")

    fun diff(old: JsonElement, new: JsonElement): JsonArray {
        val out = mutableListOf<JsonElement>()
        walk(old, new, "$", out)
        return JsonArray(out)
    }

    private fun walk(old: JsonElement, new: JsonElement, path: String, out: MutableList<JsonElement>) {
        if (old is JsonObject && new is JsonObject) {
            val keys = (old.keys + new.keys).sortedWith(GoldenCanonical.codePointOrder)
            for (k in keys) {
                val a = old[k]
                val b = new[k]
                when {
                    a == null -> out.add(pair("$path.$k", b!!))
                    b == null -> out.add(pair("$path.$k", ABSENT))
                    else -> walk(a, b, "$path.$k", out)
                }
            }
            return
        }
        if (old is JsonArray && new is JsonArray && old.size == new.size) {
            for (i in old.indices) walk(old[i], new[i], "$path[$i]", out)
            return
        }
        if (GoldenCanonical.text(old) != GoldenCanonical.text(new)) out.add(pair(path, new))
    }

    private fun pair(path: String, value: JsonElement) = JsonArray(listOf(JsonPrimitive(path), value))
}

/**
 * 골든에 JWT 모양 글자(`eyJ` + 20자 이상)를 싣지 않는 규칙(Swift `WireScrub` 과 같다 — 공개 저장소 비밀 검사가 막는다).
 * 그런 글자는 `<jwt:길이>` 로 바꾼다. Kotlin 은 자기 값을 같은 규칙으로 바꾼 뒤 골든과 견준다.
 */
object GoldenScrub {
    private val JWT = Regex("eyJ[A-Za-z0-9_-]{20,}")

    fun text(s: String): String = JWT.replace(s) { "<jwt:${it.value.length}>" }

    fun json(v: JsonElement): JsonElement = when (v) {
        is JsonObject -> JsonObject(v.mapValues { json(it.value) })
        is JsonArray -> JsonArray(v.map { json(it) })
        is JsonPrimitive -> if (v.isString) JsonPrimitive(text(v.content)) else v
        else -> v
    }
}
