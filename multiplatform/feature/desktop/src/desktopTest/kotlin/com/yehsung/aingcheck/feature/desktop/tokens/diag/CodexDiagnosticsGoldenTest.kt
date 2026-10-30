// W2-h3 진단 골든(token-usage/upload/diagnostics) — 합성 홈 SH/upload/diag-* 위 compute(appBuild 1) 가 Swift 와 비트 일치.
// + 소스 계약(주석 걷기): tokens/{upload,account,diag} 본문에 옛 표 이름 · 환경 직접 읽기 · cmd.exe 0건.
package com.yehsung.aingcheck.feature.desktop.tokens.diag

import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.extension
import kotlin.io.path.readText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CodexDiagnosticsGoldenTest {
    private fun resourceRoot(): Path {
        val url = javaClass.getResource("/synthetic-home/upload") ?: error("합성 홈 synthetic-home/upload 가 시험 자원에 없다")
        return Path.of(url.toURI())
    }

    @Test
    fun computeMatchesSwiftOnSyntheticHomes() {
        val golden = Golden.load("token-usage/upload/diagnostics")
        val root = resourceRoot()
        val encoder = Json { encodeDefaults = true }
        for (c in golden.cases) {
            val id = c["id"]!!.jsonPrimitive.content
            val home = root.resolve(c["home"]!!.jsonPrimitive.content)
            val result = CodexUsageDiagnosticsScanner.compute(home.resolve(".codex"), c["month"]!!.jsonPrimitive.content, c["appBuild"]!!.jsonPrimitive.long)
            assertEquals(c["result"], encoder.encodeToJsonElement(CodexUsageDiagnostics.serializer(), result), id)
        }
        assertTrue(golden.cases.size >= 4)
    }

    /** 주석(// · /* */)을 걷은 본문. 글자 상수 안의 '//' 는 이 패키지에 없다(URL 은 core/net 이 붙인다). */
    private fun stripComments(text: String): String =
        text.replace(Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL), "").lines().joinToString("\n") { it.substringBefore("//") }

    @Test
    fun sourceContract_noLegacyTableNoEnvReadsNoCmdExe() {
        val base = listOf(Path.of("src"), Path.of("feature/desktop/src"), Path.of("multiplatform/feature/desktop/src")).first { Files.isDirectory(it) }
        val files = listOf("commonMain", "desktopMain").flatMap { set ->
            listOf("upload", "account", "diag").flatMap { pkg ->
                val dir = base.resolve("$set/kotlin/com/yehsung/aingcheck/feature/desktop/tokens/$pkg")
                if (Files.isDirectory(dir)) Files.walk(dir).use { s -> s.filter { it.extension == "kt" }.toList() } else emptyList()
            }
        }
        assertTrue(files.size >= 6, "본문 파일을 못 찾았다: $files")
        val banned = listOf("token_usage_monthly", "user.home", "getenv", "USERPROFILE", "LOCALAPPDATA", "cmd.exe", "System.getProperty")
        for (f in files) {
            val body = stripComments(f.readText())
            for (word in banned) assertTrue(word !in body, "$f 에 금지어 '$word'")
        }
    }
}
