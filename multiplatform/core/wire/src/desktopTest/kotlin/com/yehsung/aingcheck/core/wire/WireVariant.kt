// 원본: 없음 — Tests/CheckMobileKitTests/GoldenExport/wire/GoldenWireSupport.swift 의 `WireVariant` 와 같은 문법·뜻(G6 변형 가하기)
package com.yehsung.aingcheck.core.wire

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral

/** 경로 `$.a[0].b` 에 op 를 가한다(Swift 와 같은 문법). 숫자 글자는 원문 그대로 이어 붙인다(`3` → `3.0`). */
@OptIn(ExperimentalSerializationApi::class)
object WireVariant {
    private sealed interface Step {
        data class Key(val key: String) : Step
        data class Index(val index: Int) : Step
    }

    private fun steps(path: String): List<Step> {
        require(path.startsWith("$")) { "경로 문법: $path" }
        val out = mutableListOf<Step>()
        var i = 1
        while (i < path.length) {
            when (path[i]) {
                '.' -> {
                    var end = i + 1
                    while (end < path.length && path[end] != '.' && path[end] != '[') end++
                    out += Step.Key(path.substring(i + 1, end))
                    i = end
                }
                '[' -> {
                    val close = path.indexOf(']', i)
                    out += Step.Index(path.substring(i + 1, close).toInt())
                    i = close + 1
                }
                else -> error("경로 문법: $path")
            }
        }
        return out
    }

    fun apply(root: JsonElement, path: String, op: String): JsonElement = go(root, steps(path), op)

    private fun go(v: JsonElement, steps: List<Step>, op: String): JsonElement {
        val step = steps.firstOrNull() ?: return replacement(v, op)
        val rest = steps.drop(1)
        return when {
            v is JsonObject && step is Step.Key -> {
                if (step.key !in v) return v
                if (rest.isEmpty() && op == "remove") JsonObject(v.filterKeys { it != step.key })
                else JsonObject(v.mapValues { (k, child) -> if (k == step.key) go(child, rest, op) else child })
            }
            v is JsonArray && step is Step.Index -> {
                if (step.index !in v.indices) return v
                if (rest.isEmpty() && op == "remove") JsonArray(v.filterIndexed { i, _ -> i != step.index })
                else JsonArray(v.mapIndexed { i, child -> if (i == step.index) go(child, rest, op) else child })
            }
            else -> v
        }
    }

    fun replacement(v: JsonElement, op: String): JsonElement = when (op) {
        "null" -> JsonNull
        "str" -> JsonPrimitive("3")
        "num", "int" -> JsonUnquotedLiteral("3")
        "enum" -> JsonPrimitive("zz_unknown_value")
        "bool" -> JsonPrimitive(true)
        "empty" -> JsonArray(emptyList())
        "big" -> JsonUnquotedLiteral("4294967296")
        "float0", "float5" -> {
            val p = v as? JsonPrimitive
            if (p == null || p.isString || p is JsonNull) v else JsonUnquotedLiteral(p.content + if (op == "float0") ".0" else ".5")
        }
        else -> v
    }
}
