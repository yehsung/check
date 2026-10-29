// W2-h2 시험 바탕: 합성 홈 복사 · 파일 상태 지문 · MockEngine 기록기 · 가짜 서비스 · 주석 걷기. 실제 홈·실제 계정·네트워크 0.
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.HttpResponseData
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.Collections
import kotlin.io.path.isDirectory
import kotlin.io.path.relativeTo

internal object LimitsFixtures {
    /**
     * `synthetic-home/limits/<name>` 을 새 임시 폴더로 복사한 홈. 저장소의 `.claude/` 는 .gitignore 라 픽스처는 `dot-` 이름으로 두고
     * 복사할 때 마디마다 `dot-x` → `.x` 로 바꾼다(`dot-claude/dot-credentials.json` → `.claude/.credentials.json`).
     */
    fun home(name: String): Path {
        val url = requireNotNull(javaClass.classLoader.getResource("synthetic-home/limits/$name")) { "픽스처 $name 없음" }
        val src = File(url.toURI()).toPath()
        val dest = Files.createTempDirectory("w2h2-$name-")
        Files.walk(src).use { paths ->
            paths.forEach { p ->
                val rel = p.relativeTo(src).toString().split('/', '\\').joinToString(File.separator) { seg ->
                    if (seg.startsWith("dot-")) "." + seg.removePrefix("dot-") else seg
                }
                val target = dest.resolve(rel)
                if (p.isDirectory()) Files.createDirectories(target) else Files.copy(p, target)
            }
        }
        return dest
    }

    fun delete(home: Path) {
        home.toFile().walkBottomUp().forEach { it.setWritable(true); it.delete() }
    }

    /** 홈 아래 전부: 상대 경로 → (종류 · 크기 · mtime 밀리초 · sha256). 전후 같아야 '읽기만'. */
    fun state(home: Path): Map<String, String> {
        val out = sortedMapOf<String, String>()
        Files.walk(home).use { paths ->
            paths.forEach { p ->
                val rel = p.relativeTo(home).toString().replace('\\', '/')
                out[rel] = if (p.isDirectory()) "dir" else {
                    val bytes = Files.readAllBytes(p)
                    val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                    "file ${bytes.size} ${Files.getLastModifiedTime(p).toMillis()} $sha"
                }
            }
        }
        return out
    }
}

/** MockEngine + 요청 기록. `respond` 는 요청마다 부른다. */
internal class RecordingHttp(private val respond: suspend MockRequestHandleScope.(HttpRequestData) -> HttpResponseData) {
    val requests: MutableList<HttpRequestData> = Collections.synchronizedList(mutableListOf())
    val client = HttpClient(MockEngine { request ->
        requests += request
        respond(request)
    })
    val fetcher: AILimitHTTPFetcher = AILimitHTTPKtor.fetcher(client)

    companion object {
        fun ok(body: String): suspend MockRequestHandleScope.(HttpRequestData) -> HttpResponseData = {
            respond(body, HttpStatusCode.OK, headersOf("Content-Type", "application/json"))
        }

        /** 제공자 둘에 맞는 200 본문. */
        val usage: suspend MockRequestHandleScope.(HttpRequestData) -> HttpResponseData = { request ->
            val body = if (request.url.host == "api.anthropic.com") {
                """{"five_hour":{"utilization":27,"resets_at":"2026-10-30T05:00:00Z"},"seven_day":{"utilization":61.5,"resets_at":"2026-11-02T00:00:00Z"}}"""
            } else {
                """{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12.5,"limit_window_seconds":18000,"reset_after_seconds":9000,"reset_at":1793399000}}}"""
            }
            respond(body, HttpStatusCode.OK, headersOf("Content-Type", "application/json"))
        }
    }
}

internal fun HttpRequestData.bodyBytes(): ByteArray = when (val b = body) {
    is OutgoingContent.ByteArrayContent -> b.bytes()
    else -> ByteArray(0)
}

internal object NoTextRules : WireTextRules {
    override fun sanitized(raw: String): String = error("리밋 시험은 글자 규칙을 쓰지 않는다")
    override fun hasVisibleContent(text: String): Boolean = error("리밋 시험은 글자 규칙을 쓰지 않는다")
    override fun statusMessageSanitized(raw: String): String = error("리밋 시험은 글자 규칙을 쓰지 않는다")
}

internal fun fakeService(http: RecordingHttp): SupabaseWorkService =
    SupabaseWorkService("https://golden.invalid", "anon-synthetic", http.client, { SwiftDate(0.0) }, NoTextRules) { "ABCDEF12-0000-4000-8000-000000000000" }

/** 바늘을 돌리는 시계. */
internal class FakeClock(var now: Double) {
    val read: () -> SwiftDate = { SwiftDate(now) }
}

/** Kotlin 소스의 주석을 걷는다(글자 리터럴 안의 `//` 는 지키되 리터럴 내용은 남긴다). 소스 계약 시험용. */
internal object CommentStripper {
    fun strip(src: String): String {
        val out = StringBuilder()
        var i = 0
        var inString = false
        var raw = false
        while (i < src.length) {
            val c = src[i]
            if (!inString && src.startsWith("//", i)) {
                while (i < src.length && src[i] != '\n') i++
                continue
            }
            if (!inString && src.startsWith("/*", i)) {
                val end = src.indexOf("*/", i + 2)
                i = if (end < 0) src.length else end + 2
                continue
            }
            if (!inString && src.startsWith("\"\"\"", i)) { inString = true; raw = true; out.append("\"\"\""); i += 3; continue }
            if (inString && raw && src.startsWith("\"\"\"", i)) { inString = false; raw = false; out.append("\"\"\""); i += 3; continue }
            if (!inString && c == '"') { inString = true; out.append(c); i++; continue }
            if (inString && !raw && c == '\\' && i + 1 < src.length) { out.append(c).append(src[i + 1]); i += 2; continue }
            if (inString && !raw && c == '"') { inString = false; out.append(c); i++; continue }
            out.append(c)
            i++
        }
        return out.toString()
    }

    /** ailimits 본문(commonMain·desktopMain) 파일들 — 저장소 뿌리는 시험 속성 `aingcheck.repoRoot`. */
    fun ailimitsMainSources(): Map<String, String> {
        val root = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 없음" })
        val base = File(root, "multiplatform/feature/desktop/src")
        return base.listFiles().orEmpty().filter { it.name.endsWith("Main") }.flatMap { set ->
            File(set, "kotlin/com/yehsung/aingcheck/feature/desktop/ailimits").walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList()
        }.associate { it.relativeTo(root).path to strip(it.readText()) }
    }
}
