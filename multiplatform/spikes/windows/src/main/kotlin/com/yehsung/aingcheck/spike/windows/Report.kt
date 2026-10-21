package com.yehsung.aingcheck.spike.windows

import java.io.File

/** 키 순서를 보존하는 작은 JSON 작성기. 보고서는 한 줄 JSON 이다(사람이 눈으로 판정하지 않는다). */
object Json {
    fun quote(s: String): String {
        val sb = StringBuilder(s.length + 2)
        sb.append('"')
        for (ch in s) {
            when {
                ch == '"' -> sb.append("\\\"")
                ch == '\\' -> sb.append("\\\\")
                ch == '\n' -> sb.append("\\n")
                ch == '\r' -> sb.append("\\r")
                ch == '\t' -> sb.append("\\t")
                ch < ' ' -> sb.append("\\u").append(String.format("%04x", ch.code))
                else -> sb.append(ch)
            }
        }
        sb.append('"')
        return sb.toString()
    }

    fun encode(v: Any?): String = when (v) {
        null -> "null"
        is String -> quote(v)
        is Boolean -> v.toString()
        is Int, is Long, is Short, is Byte -> v.toString()
        is Double -> if (v.isFinite()) v.toString() else quote(v.toString())
        is Float -> if (v.isFinite()) v.toString() else quote(v.toString())
        is Check -> encode(v.toMap())
        is Map<*, *> -> v.entries.joinToString(",", "{", "}") { quote(it.key.toString()) + ":" + encode(it.value) }
        is Iterable<*> -> v.joinToString(",", "[", "]") { encode(it) }
        is Array<*> -> encode(v.asList())
        else -> quote(v.toString())
    }
}

/** 실험 하나의 결과. required 가 참인 것만 종료 코드를 정한다. */
data class Check(
    val id: String,
    val ok: Boolean,
    val required: Boolean = true,
    val detail: Map<String, Any?> = emptyMap(),
) {
    fun toMap(): Map<String, Any?> = linkedMapOf("id" to id, "ok" to ok, "required" to required, "detail" to detail)
}

object Verdict {
    /**
     * 필수 검사가 하나도 없으면 실패다 — 아무것도 재지 않은 초록을 막는다(기억 tests-measure-shape-not-result).
     */
    fun exitCode(checks: List<Check>): Int {
        val required = checks.filter { it.required }
        return if (required.isNotEmpty() && required.all { it.ok }) 0 else 1
    }

    fun report(kind: String, checks: List<Check>, extra: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        linkedMapOf<String, Any?>(
            "kind" to kind,
            "exitCode" to exitCode(checks),
            "build" to buildInfoMap(),
        ).apply {
            putAll(extra)
            put("checks", checks)
        }

    fun buildInfoMap(): Map<String, Any?> = linkedMapOf(
        "version" to BuildInfo.VERSION,
        "build" to BuildInfo.BUILD,
        "buildTime" to BuildInfo.BUILDTIME,
        "gitSha" to BuildInfo.GITSHA,
        "treeSha" to BuildInfo.TREESHA,
    )

    /** 보고서를 파일(있으면)과 표준 출력 둘 다에 쓴다. GUI 서브시스템 런처는 stdout 이 없을 수 있어 파일이 정본이다. */
    fun emit(report: Map<String, Any?>, out: String?) {
        val line = Json.encode(report)
        if (out != null) {
            val f = File(out)
            f.absoluteFile.parentFile?.mkdirs()
            f.writeText(line + "\n", Charsets.UTF_8)
        }
        println(line)
    }
}
