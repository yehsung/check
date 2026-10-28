// 원본: 없음 (구운 자산 JSON 읽기 보조 — 형식은 multiplatform/scripts/bake-aing 이 쓴 그대로)
package com.yehsung.aingcheck.character.bake

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

/** 구운 자산의 모양이 기대와 다르다(칸 이름 · 기대한 꼴). 재생기는 이걸 받으면 그 캐릭터를 아잉 · legacy 로 접는다. */
class BakeFormatException(message: String) : Exception(message)

internal object BakeJson {
    private val json = Json { isLenient = false }

    fun parse(text: String): JsonObject = try {
        json.parseToJsonElement(text).jsonObject
    } catch (e: Exception) {
        if (e is BakeFormatException) throw e
        throw BakeFormatException("JSON 이 아니거나 객체가 아니다: ${e.message}")
    }

    fun JsonObject.req(key: String): JsonElement = this[key]?.takeIf { it !is JsonNull } ?: throw BakeFormatException("칸 '$key' 가 없다")
    fun JsonObject.opt(key: String): JsonElement? = this[key]?.takeIf { it !is JsonNull }

    fun JsonElement.obj(): JsonObject = this as? JsonObject ?: throw BakeFormatException("객체가 아니다: $this")
    fun JsonElement.arr(): JsonArray = this as? JsonArray ?: throw BakeFormatException("배열이 아니다: $this")
    fun JsonElement.str(): String = (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw BakeFormatException("글자가 아니다: $this")
    fun JsonElement.dbl(): Double = (this as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull ?: throw BakeFormatException("수가 아니다: $this")
    fun JsonElement.int(): Int = (this as? JsonPrimitive)?.takeIf { !it.isString }?.let { it.intOrNull ?: it.doubleOrNull?.let { d -> if (d == kotlin.math.floor(d)) d.toInt() else null } }
        ?: throw BakeFormatException("정수가 아니다: $this")
    fun JsonElement.bool(): Boolean = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: throw BakeFormatException("참거짓이 아니다: $this")
    fun JsonElement.doubles(): List<Double> = arr().map { it.dbl() }
    fun JsonElement.ints(): List<Int> = arr().map { it.int() }
    fun JsonElement.strs(): List<String> = arr().map { it.str() }
}
