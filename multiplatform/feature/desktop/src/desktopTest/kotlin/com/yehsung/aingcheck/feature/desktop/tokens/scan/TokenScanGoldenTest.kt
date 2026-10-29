// W2-h1 완료 기준(tokens.md §5): Swift GoldenExportTokenScan 이 합성 홈(SH/scan)으로 만든 골든과 Kotlin 스캐너가 비트 일치한다.
// 사례마다 시험 하나 — 음성 대조(포크 규칙 끔·동결 끔·requestId 키 뺌·첫 이벤트 델타)가 어느 사례를 빨갛게 하는지 이름으로 보인다.
// 비교 칸: usage(월 합·claudeDaily·codexDaily·codexDailyUTC·today·windowStart·claudeCompleteFrom·total) · stats(읽은 파일·바이트·포크 복사 수) ·
// claudeFiles(오프셋) · claudeEntries(SHA-256 키·값) · codexFiles(기준선·월/일 기여·포크 마감). fresh 단계는 빈 캐시 재스캔 = 증분.
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TokenScanGoldenTest {
    private val golden = Golden.load("token-usage/scan/scanner")

    private fun case(id: String): JsonObject =
        golden.cases.firstOrNull { it["id"]?.jsonPrimitive?.content == id } ?: error("골든에 사례 $id 가 없다")

    private fun run(id: String) {
        val c = case(id)
        val home = Files.createTempDirectory("token-scan-$id").toRealPath()
        val failures = mutableListOf<String>()
        try {
            val homes = DesktopAiHomes.synthetic(home)
            var cache = TokenUsageCache()
            for ((i, el) in c["steps"]!!.jsonArray.withIndex()) {
                val step = el.jsonObject
                for (op in step["ops"]!!.jsonArray) TokenScanGoldenSupport.apply(op.jsonObject, home)
                val now = SwiftDate(step["now"]!!.jsonPrimitive.long.toDouble())
                val r = TokenUsageIncrementalScanner.update(cache, homes, now)
                cache = r.cache
                val mine = mapOf(
                    "usage" to TokenScanGoldenSupport.usageJson(r.usage),
                    "stats" to TokenScanGoldenSupport.statsJson(r.stats),
                    "claudeFiles" to TokenScanGoldenSupport.claudeFilesJson(cache, home),
                    "claudeEntries" to TokenScanGoldenSupport.claudeEntriesJson(cache),
                    "codexFiles" to TokenScanGoldenSupport.codexFilesJson(cache, home),
                )
                for ((field, value) in mine) {
                    if (step[field] != value) failures += "$id 단계 ${i + 1} $field\n  Swift : ${step[field]}\n  Kotlin: $value"
                }
                if (step["fresh"]!!.jsonPrimitive.boolean) {
                    val fresh = TokenUsageIncrementalScanner.update(TokenUsageCache(), homes, now)
                    if (fresh.usage != r.usage) failures += "$id 단계 ${i + 1}: 처음부터 스캔(${fresh.usage}) ≠ 증분(${r.usage})"
                }
            }
        } finally {
            home.toFile().deleteRecursively()
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    @Test fun goldenHasEveryBriefCase() {
        val ids = golden.cases.map { it["id"]!!.jsonPrimitive.content }.toSet()
        assertEquals(
            setOf("claude-dedupe", "claude-kst-boundary", "claude-transcripts", "codex-baseline-first", "codex-resume-prev-month",
                "codex-fork-copy", "codex-zst-freeze", "codex-zst-no-twin", "codex-info-null", "codex-cum-reset", "append-equals-full",
                "partial-tail", "crlf-lines", "month-rollover"),
            ids,
        )
        assertEquals(listOf("Sources/CheckCore/CheckTokenUsage.swift"), golden.swiftSources)
        assertTrue(golden.cases.none { it.toString().contains("/Users/") || it.toString().contains(":\\\\") }, "골든에 절대 경로가 있다")
    }

    @Test fun claudeDedupe() = run("claude-dedupe")
    @Test fun claudeKstBoundary() = run("claude-kst-boundary")
    @Test fun claudeTranscripts() = run("claude-transcripts")
    @Test fun codexBaselineFirst() = run("codex-baseline-first")
    @Test fun codexResumePrevMonth() = run("codex-resume-prev-month")
    @Test fun codexForkCopy() = run("codex-fork-copy")
    @Test fun codexZstFreeze() = run("codex-zst-freeze")
    @Test fun codexZstNoTwin() = run("codex-zst-no-twin")
    @Test fun codexInfoNull() = run("codex-info-null")
    @Test fun codexCumReset() = run("codex-cum-reset")
    @Test fun appendEqualsFull() = run("append-equals-full")
    @Test fun partialTail() = run("partial-tail")
    @Test fun crlfLines() = run("crlf-lines")
    @Test fun monthRollover() = run("month-rollover")
}
