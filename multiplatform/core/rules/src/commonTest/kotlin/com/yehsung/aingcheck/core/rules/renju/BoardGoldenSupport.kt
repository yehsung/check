// 원본: 없음 — W1-b 골든(renju · chess · duel-fee) 소비 시험이 같이 쓰는 칸 읽기 도우미(형식 정본: contract/README.md §2).
package com.yehsung.aingcheck.core.rules.renju

import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/** 코드 포인트 16진 목록("0048 0038") → 글자. 빈 글자는 "". (골든 생성기 `cps`) */
internal fun cpsText(cps: String): String {
    if (cps.isEmpty()) return ""
    val out = StringBuilder()
    for (part in cps.split(' ')) {
        val cp = part.toInt(16)
        if (cp >= 0x10000) {
            val v = cp - 0x10000
            out.append((0xD800 + (v shr 10)).toChar())
            out.append((0xDC00 + (v and 0x3FF)).toChar())
        } else {
            out.append(cp.toChar())
        }
    }
    return out.toString()
}

internal fun JsonObject.isNull(key: String): Boolean = this[key] == null || this[key] is JsonNull

/** 글자 칸(null 이면 null). 글자가 아닌 값이면 실패한다. */
internal fun JsonObject.optString(key: String): String? {
    val value = this[key] ?: return null
    if (value is JsonNull) return null
    return (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: error("골든 칸 '$key' 가 글자가 아니다: $value")
}

internal fun JsonObject.optInt(key: String): Int? {
    val value = this[key] ?: return null
    if (value is JsonNull) return null
    return (value as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull ?: error("골든 칸 '$key' 가 정수가 아니다: $value")
}

internal fun JsonObject.bool(key: String): Boolean =
    (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: error("골든 칸 '$key' 가 불이 아니다: ${this[key]}")

internal fun JsonObject.optBool(key: String): Boolean? {
    val value = this[key] ?: return null
    if (value is JsonNull) return null
    return (value as? JsonPrimitive)?.booleanOrNull ?: error("골든 칸 '$key' 가 불이 아니다: $value")
}

internal fun JsonObject.optBits(key: String): Double? = optString(key)?.let { Golden.bits(it) }

internal fun JsonElement.asObject(): JsonObject = this as? JsonObject ?: error("골든 값이 객체가 아니다: $this")

internal fun JsonElement.asArray(): JsonArray = this as? JsonArray ?: error("골든 값이 배열이 아니다: $this")

/** 배열 원소를 글자 목록으로(null 원소는 null). */
internal fun JsonArray.optStrings(): List<String?> = map { element ->
    if (element is JsonNull) null else (element as? JsonPrimitive)?.takeIf { it.isString }?.content ?: error("글자가 아니다: $element")
}

internal fun JsonArray.strings(): List<String> = optStrings().map { it ?: error("null 이 섞였다") }

internal fun JsonElement.intValue(): Int = (this as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull ?: error("정수가 아니다: $this")

internal fun JsonElement.optStringValue(): String? =
    if (this is JsonNull) null else (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: error("글자가 아니다: $this")

/** Double 을 골든 비트 글자로(비교 실패 문구용). */
internal fun bitsOf(value: Double): String = Golden.bitsText(value)
