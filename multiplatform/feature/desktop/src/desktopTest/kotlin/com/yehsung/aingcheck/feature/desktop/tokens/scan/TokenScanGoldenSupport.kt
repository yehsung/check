// W2-h1 시험 도우미 — 골든(contract/golden/token-usage/scan/scanner.json)의 ops 를 합성 홈에 되풀이하고 Swift 와 같은 JSON 모양으로 결과를 만든다.
// 모양 정본: Tests/checkTests/GoldenExport/token-usage/GoldenExportTokenScan.swift(usageJSON · statsJSON · claudeFiles · claudeEntries · codexFiles).
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.FileTime

internal object TokenScanGoldenSupport {
    const val FIXTURE_DIR = "multiplatform/feature/desktop/src/desktopTest/resources/synthetic-home/scan"

    fun repoRoot(): Path = Path.of(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다(test-seal 규약)" })

    fun fixtures(): Path = repoRoot().resolve(FIXTURE_DIR)

    /** put = 조각 복사(덮어쓰기) · append = 덧붙이기 · delete. mtime 은 초(골든 그대로). 경로 글자는 '/' — 플랫폼 구분자로 푼다. */
    fun apply(op: JsonObject, home: Path, fixtures: Path = fixtures()) {
        val target = resolve(home, op.str("to"))
        when (val kind = op.str("op")) {
            "delete" -> {
                Files.delete(target)
                return
            }
            "put", "append" -> {
                val bytes = Files.readAllBytes(resolve(fixtures, op.str("from")))
                Files.createDirectories(target.parent)
                if (kind == "put" || !Files.exists(target)) {
                    Files.write(target, bytes)
                } else {
                    Files.write(target, bytes, StandardOpenOption.APPEND)
                }
            }
            else -> error("모르는 op $kind")
        }
        (op["mtime"] as? JsonPrimitive)?.let { Files.setLastModifiedTime(target, FileTime.fromMillis(it.long * 1000)) }
    }

    fun resolve(base: Path, slashPath: String): Path = slashPath.split('/').fold(base) { p, part -> p.resolve(part) }

    fun usageJson(u: TokenUsageMonthly): JsonObject = JsonObject(
        mapOf(
            "month" to JsonPrimitive(u.month),
            "claudeInput" to JsonPrimitive(u.claudeInput), "claudeOutput" to JsonPrimitive(u.claudeOutput),
            "claudeCacheRead" to JsonPrimitive(u.claudeCacheRead), "claudeCacheCreation" to JsonPrimitive(u.claudeCacheCreation),
            "codexInput" to JsonPrimitive(u.codexInput), "codexOutput" to JsonPrimitive(u.codexOutput),
            "codexCacheRead" to JsonPrimitive(u.codexCacheRead),
            "antigravityInput" to JsonPrimitive(u.antigravityInput), "antigravityOutput" to JsonPrimitive(u.antigravityOutput),
            "antigravityThinking" to JsonPrimitive(u.antigravityThinking), "antigravityCacheRead" to JsonPrimitive(u.antigravityCacheRead),
            "todayTotal" to JsonPrimitive(u.todayTotal), "todayDate" to JsonPrimitive(u.todayDate),
            "claudeDaily" to longMap(u.claudeDaily), "codexDaily" to longMap(u.codexDaily), "codexDailyUTC" to longMap(u.codexDailyUTC),
            "antigravityDaily" to longMap(u.antigravityDaily),
            "windowStart" to JsonPrimitive(u.windowStart), "claudeCompleteFrom" to JsonPrimitive(u.claudeCompleteFrom),
            "total" to JsonPrimitive(u.total),
        ),
    )

    fun statsJson(s: TokenUsageIncrementalScanner.Stats): JsonObject = JsonObject(
        mapOf(
            "claudeFilesStatted" to JsonPrimitive(s.claudeFilesStatted), "claudeFilesRead" to JsonPrimitive(s.claudeFilesRead),
            "claudeBytesRead" to JsonPrimitive(s.claudeBytesRead),
            "codexFilesStatted" to JsonPrimitive(s.codexFilesStatted), "codexFilesRead" to JsonPrimitive(s.codexFilesRead),
            "codexBytesRead" to JsonPrimitive(s.codexBytesRead), "codexForkCopyEvents" to JsonPrimitive(s.codexForkCopyEvents),
            "entriesChanged" to JsonPrimitive(s.entriesChanged), "statesChanged" to JsonPrimitive(s.statesChanged),
        ),
    )

    fun claudeFilesJson(cache: TokenUsageCache, home: Path): JsonArray = JsonArray(
        cache.claudeFileStates.map { (k, p) -> rel(home, k) to p }.sortedBy { it.first }.map { (rel, p) ->
            JsonArray(listOf(JsonPrimitive(rel), JsonPrimitive(p.size), JsonPrimitive(p.mtimeMicros), JsonPrimitive(p.consumedOffset)))
        },
    )

    fun claudeEntriesJson(cache: TokenUsageCache): JsonArray = JsonArray(
        cache.claudeEntries.map { (k, e) -> k.hex to e }.sortedBy { it.first }.map { (hex, e) ->
            JsonArray(listOf(JsonPrimitive(hex), JsonPrimitive(e.ts14), JsonPrimitive(e.input), JsonPrimitive(e.output),
                JsonPrimitive(e.cacheRead), JsonPrimitive(e.cacheCreation)))
        },
    )

    fun codexFilesJson(cache: TokenUsageCache, home: Path): JsonArray = JsonArray(
        cache.codexFileStates.map { (k, p) -> rel(home, k) to p }.sortedBy { it.first }.map { (rel, p) ->
            JsonArray(listOf(JsonPrimitive(rel), JsonPrimitive(p.size), JsonPrimitive(p.mtimeMicros), JsonPrimitive(p.consumedOffset),
                JsonPrimitive(p.prevInput), JsonPrimitive(p.prevOutput), JsonPrimitive(p.prevCached), JsonPrimitive(p.monthKey),
                JsonPrimitive(p.monthInput), JsonPrimitive(p.monthOutput), JsonPrimitive(p.monthCached), longMap(p.dayContrib),
                JsonPrimitive(p.forkCopyDeadlineMicros), longMap(p.dayContribUTC)))
        },
    )

    /** 홈 기준 상대 경로('/' 구분). 홈 밖 경로면 실패 — 상태에 합성 홈 밖이 섞이면 안 된다. */
    fun rel(home: Path, key: String): String {
        val p = Path.of(key)
        check(p.startsWith(home)) { "홈 밖 경로가 상태에 있다: $key" }
        return home.relativize(p).joinToString("/") { it.toString() }
    }

    /** Swift 의 Swift 문자열 비교(유니코드 스칼라 순)와 같게 — 골든 경로·키는 ASCII 라 글자 순과 같다. */
    private fun longMap(m: Map<String, Long>): JsonObject = JsonObject(m.mapValues { JsonPrimitive(it.value) })

    private fun JsonObject.str(key: String): String = requireNotNull(this[key]) { "op 에 $key 가 없다" }.jsonPrimitive.content

    /** JsonElement 를 같은 값끼리 같게 비교(숫자는 글자 그대로 — 골든은 정수만). */
    fun same(a: JsonElement?, b: JsonElement?): Boolean = a == b
}
