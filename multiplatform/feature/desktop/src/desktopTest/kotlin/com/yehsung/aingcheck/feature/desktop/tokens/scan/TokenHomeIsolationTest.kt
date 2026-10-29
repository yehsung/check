// W2-h1 완료 기준(tokens.md §5) 홈 격리 — ★ INV-CheckTokenUsage-1e4bfd85(맥 '실홈 차단 단일 지점'의 Windows 대체).
// ① 시험 시작에 user.home 을 1e9 토큰 카나리 로그가 든 임시 홈으로 바꾸고, 합성 홈(DesktopAiHomes.synthetic)으로 스캔 → 카나리 0.
//    양성 대조: 같은 카나리 홈을 DesktopAiHomes 로 넘기면 카나리가 보인다(카나리가 실제로 잡히는 모양임을 먼저 증명).
// ② 소스 계약(주석 걷기): feature/desktop 본문 소스의 tokens/**·ailimits/** 에 user.home|getenv|USERPROFILE|LOCALAPPDATA 0건.
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime
import kotlin.io.path.extension
import kotlin.io.path.invariantSeparatorsPathString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TokenHomeIsolationTest {
    private val now = 1_792_033_200L   // 2026-10-15T03:00:00Z (KST 12:00) — 합성 픽스처와 같은 시각
    private val canary = 1_000_000_000L

    private fun write(home: Path, rel: String, text: String) {
        val p = TokenScanGoldenSupport.resolve(home, rel)
        Files.createDirectories(p.parent)
        Files.writeString(p, text)
        Files.setLastModifiedTime(p, FileTime.fromMillis((now - 3_600) * 1000))
    }

    private fun canaryHome(): Path {
        val home = Files.createTempDirectory("token-canary-home").toRealPath()
        write(home, ".claude/projects/-canary/c.jsonl",
            """{"type":"assistant","timestamp":"2026-10-15T01:00:00.000Z","requestId":"canary","message":{"id":"canary","usage":{"input_tokens":$canary,"output_tokens":$canary,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}""" + "\n")
        write(home, ".codex/sessions/2026/10/15/rollout-2026-10-15T00-00-00-canary.jsonl",
            listOf(
                """{"timestamp":"2026-10-15T00:00:00.000Z","type":"session_meta","payload":{"id":"canary"}}""",
                """{"timestamp":"2026-10-15T00:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"output_tokens":1,"cached_input_tokens":0}}}}""",
                """{"timestamp":"2026-10-15T00:10:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":$canary,"output_tokens":$canary,"cached_input_tokens":0}}}}""",
            ).joinToString("\n", postfix = "\n"))
        return home
    }

    private fun syntheticHome(): Path {
        val home = Files.createTempDirectory("token-synthetic-home").toRealPath()
        write(home, ".claude/projects/-synthetic/s.jsonl",
            """{"type":"assistant","timestamp":"2026-10-15T01:00:00.000Z","requestId":"r","message":{"id":"m","usage":{"input_tokens":3,"output_tokens":4,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}""" + "\n")
        return home
    }

    @Test fun realHomePropertyNeverReachesTheScanner() = runTest {
        val canaryHome = canaryHome()
        val synthetic = syntheticHome()
        val saved = System.getProperty("user.home")
        try {
            // 양성 대조 — 카나리 홈을 직접 넘기면 1e9 가 보인다.
            val seen = TokenUsageIncrementalScanner.scan(DesktopAiHomes.synthetic(canaryHome), SwiftDate(now.toDouble()))
            assertTrue(seen.claudeInput >= canary && seen.codexInput >= canary - 1, "카나리가 안 보인다 — 대조가 무의미하다: $seen")

            System.setProperty("user.home", canaryHome.toString())
            val r = TokenUsageIncrementalScanner.update(TokenUsageCache(), DesktopAiHomes.synthetic(synthetic), SwiftDate(now.toDouble()))
            assertEquals(7, r.usage.total, "합성 홈만 세야 한다: ${r.usage}")
            assertTrue((r.cache.claudeFileStates.keys + r.cache.codexFileStates.keys).all { Path.of(it).startsWith(synthetic) })

            val store = TokenUsageStore(DesktopAiHomes.synthetic(synthetic), InMemoryDesktopKeyValueStore(), cacheBase = null,
                clock = { SwiftDate(now.toDouble()) }, ioDispatcher = kotlinx.coroutines.Dispatchers.Unconfined)
            store.refreshNow()
            val usage = store.currentMonthUsage.value!!
            assertEquals(7, usage.total)
            assertTrue(usage.claudeDaily.values.all { it < canary } && usage.codexDailyUTC.values.all { it < canary })
        } finally {
            System.setProperty("user.home", saved)
            canaryHome.toFile().deleteRecursively()
            synthetic.toFile().deleteRecursively()
        }
    }

    @Test fun tokensAndAilimitsSourcesNeverReadHomeOrEnvironment() {
        val src = TokenScanGoldenSupport.repoRoot().resolve("multiplatform/feature/desktop/src")
        val files = Files.walk(src).use { s ->
            s.filter { Files.isRegularFile(it) && it.extension == "kt" }
                .filter { p ->
                    val rel = src.relativize(p).invariantSeparatorsPathString
                    !rel.substringBefore('/').endsWith("Test") && (rel.contains("/tokens/") || rel.contains("/ailimits/"))
                }
                .toList()
        }
        assertTrue(files.size >= 6, "검사한 파일이 너무 적다(${files.size}) — 경로 규칙이 틀렸다")
        val banned = Regex("""user\.home|getenv|USERPROFILE|LOCALAPPDATA""")
        val hits = files.flatMap { f ->
            stripComments(Files.readString(f)).lines().withIndex()
                .filter { banned.containsMatchIn(it.value) }
                .map { "${src.relativize(f)}:${it.index + 1}: ${it.value.trim()}" }
        }
        assertTrue(hits.isEmpty(), "홈·환경 변수 직접 읽기 — 경로는 DesktopAiHomes 로만:\n" + hits.joinToString("\n"))
    }

    @Test fun commentStripperKeepsCodeAndDropsComments() {
        val code = "val a = \"// not a comment\" // getenv\n/* user.home /* nested */ */ val b = 1\nval c = System.getenv(\"X\")"
        val stripped = stripComments(code)
        assertTrue("\"// not a comment\"" in stripped && "val b = 1" in stripped && "System.getenv" in stripped)
        assertTrue("user.home" !in stripped && "// getenv" !in stripped)
        assertEquals(3, stripped.lines().size, "줄 번호가 유지돼야 한다")
    }

    companion object {
        /** Kotlin 주석(줄·중첩 블록)을 걷는다. 글자 리터럴("…"·"""…""")은 그대로, 개행은 남겨 줄 번호를 지킨다. */
        fun stripComments(s: String): String {
            val out = StringBuilder(s.length)
            var i = 0
            var depth = 0
            while (i < s.length) {
                val c = s[i]
                val next = if (i + 1 < s.length) s[i + 1] else '\u0000'
                when {
                    depth > 0 -> {
                        when {
                            c == '/' && next == '*' -> { depth++; i += 2 }
                            c == '*' && next == '/' -> { depth--; i += 2 }
                            else -> { if (c == '\n') out.append('\n'); i++ }
                        }
                    }
                    c == '/' && next == '*' -> { depth = 1; i += 2 }
                    c == '/' && next == '/' -> { while (i < s.length && s[i] != '\n') i++ }
                    s.startsWith("\"\"\"", i) -> {
                        val end = s.indexOf("\"\"\"", i + 3).let { if (it < 0) s.length else it + 3 }
                        out.append(s, i, end); i = end
                    }
                    c == '"' || c == '\'' -> {
                        var j = i + 1
                        while (j < s.length && s[j] != c && s[j] != '\n') j += if (s[j] == '\\') 2 else 1
                        val end = minOf(j + 1, s.length)
                        out.append(s, i, end); i = end
                    }
                    else -> { out.append(c); i++ }
                }
            }
            return out.toString()
        }
    }
}
