// 원본: Tests/CheckGoldenSupport/GoldenJSON.swift(정규 작성기) · GoldenBits.swift(FNV-1a 64) @ W0-b
package com.yehsung.aingcheck.testkit.golden

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/**
 * 정규 JSON 글자(contract/README.md 「정규 바이트」) — Swift `GoldenJSON.canonicalText` · 파이썬
 * `json.dumps(indent=2, sort_keys=True, ensure_ascii=False) + "\n"` 과 바이트가 같다.
 * Kotlin 은 골든을 **쓰지 않는다**. 이것은 Kotlin 이 만든 값(G6 덤프 등)을 골든과 바이트로 견줄 때 쓴다.
 * 키 정렬은 **코드포인트** 순서다(Kotlin `String.compareTo` 는 UTF-16 단위라 U+FFxx 와 보조 평면 글자에서 순서가 뒤집힌다).
 */
object GoldenCanonical {
    const val MAX_SAFE_INTEGER: Long = 9_007_199_254_740_992L

    fun text(value: JsonElement): String = StringBuilder().also { write(value, 0, it) }.append('\n').toString()

    /** (코드포인트, UTF-16 단위 수). 짝 없는 서로게이트는 그 단위 하나로 본다. */
    private fun codePointAt(s: String, i: Int): Pair<Int, Int> {
        val c = s[i]
        if (c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate()) {
            return (((c.code - 0xD800) shl 10) + (s[i + 1].code - 0xDC00) + 0x10000) to 2
        }
        return c.code to 1
    }

    val codePointOrder: Comparator<String> = Comparator { a, b ->
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val (ca, na) = codePointAt(a, i)
            val (cb, nb) = codePointAt(b, j)
            if (ca != cb) return@Comparator ca.compareTo(cb)
            i += na
            j += nb
        }
        (a.length - i).compareTo(b.length - j)
    }

    private fun indent(level: Int, out: StringBuilder) {
        repeat(level * 2) { out.append(' ') }
    }

    private fun write(value: JsonElement, level: Int, out: StringBuilder) {
        when (value) {
            is JsonNull -> out.append("null")
            is JsonPrimitive -> when {
                value.isString -> writeString(value.content, out)
                value.booleanOrNull != null -> out.append(if (value.booleanOrNull == true) "true" else "false")
                else -> {
                    val n = value.longOrNull ?: error("정규 JSON 에는 실수 숫자가 없다: ${value.content}")
                    require(n in -MAX_SAFE_INTEGER..MAX_SAFE_INTEGER) { "정수 $n 이 ±2^53 밖이다" }
                    out.append(n.toString())
                }
            }
            is JsonArray -> {
                if (value.isEmpty()) { out.append("[]"); return }
                out.append("[\n")
                value.forEachIndexed { i, item ->
                    indent(level + 1, out)
                    write(item, level + 1, out)
                    out.append(if (i == value.size - 1) "\n" else ",\n")
                }
                indent(level, out)
                out.append(']')
            }
            is JsonObject -> {
                if (value.isEmpty()) { out.append("{}"); return }
                val keys = value.keys.sortedWith(codePointOrder)
                out.append("{\n")
                keys.forEachIndexed { i, key ->
                    indent(level + 1, out)
                    writeString(key, out)
                    out.append(": ")
                    write(value.getValue(key), level + 1, out)
                    out.append(if (i == keys.size - 1) "\n" else ",\n")
                }
                indent(level, out)
                out.append('}')
            }
        }
    }

    private fun writeString(text: String, out: StringBuilder) {
        out.append('"')
        for (ch in text) {
            when (ch) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> if (ch.code < 0x20) out.append("\\u").append(ch.code.toString(16).padStart(4, '0')) else out.append(ch)
            }
        }
        out.append('"')
    }
}

/** FNV-1a 64 — Swift `GoldenFNV1a64`(= V0360 `GoldHasher`)과 같은 정의: 64비트 값 하나를 작은 끝부터 8바이트로 접는다. */
class GoldenFnv1a64 {
    var value: ULong = OFFSET_BASIS
        private set

    fun add(x: ULong) {
        var shift = 0
        while (shift < 64) {
            value = value xor ((x shr shift) and 0xFFuL)
            value *= PRIME
            shift += 8
        }
    }

    fun add(x: Long) = add(x.toULong())
    fun add(x: Int) = add(x.toLong().toULong())
    fun add(x: Double) = add(x.toRawBits().toULong())
    fun add(x: Boolean) = add(if (x) 1uL else 0uL)

    companion object {
        const val OFFSET_BASIS: ULong = 0xCBF29CE484222325uL
        const val PRIME: ULong = 0x00000100000001B3uL
    }
}
