// 원본: 없음 — C§4 #3(전송 실패 = 세션 유지) · #9(상점 번호 깃발 5분 · 시계 주입) · #18(실시간 하트비트 25초 ≠ 근무 30초) · #39(HTTP 15/30초 · 캐시 끔)
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.HttpTimeoutCapability
import io.ktor.client.plugins.cache.HttpCache
import io.ktor.client.plugins.pluginOrNull
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonObject
import java.io.File
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NetContractsTest {
    private val t0 = SwiftDate(1_789_621_500.0)

    /** 응답 대본 + 본문 녹음(상점 본문에 p_protocol 이 실렸는지). */
    private class Scripted(private val script: List<Pair<Int, String>>) {
        val bodies = mutableListOf<String>()
        var timeouts = mutableListOf<Triple<Long?, Long?, Long?>>()
        private var next = 0
        val engine = MockEngine { request ->
            val bytes = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()
            val timeout = request.getCapabilityOrNull(HttpTimeoutCapability)
            synchronized(this) {
                bodies += bytes?.decodeToString() ?: ""
                timeouts += Triple(timeout?.requestTimeoutMillis, timeout?.socketTimeoutMillis, timeout?.connectTimeoutMillis)
            }
            val (status, text) = synchronized(this) { if (next < script.size) script[next++] else 200 to "{}" }
            respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
        }
    }

    private fun service(engine: MockEngine, clock: () -> SwiftDate): Pair<SupabaseWorkService, HttpClient> {
        val client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }
        return SupabaseWorkService("https://golden.invalid", "k", client, clock, UnusedTextRules) { "ABCDEF12-0000-4000-8000-000000000000" } to client
    }

    /**
     * 이 시험들(전송 실패 · 상점 깃발 · 시간 제한 · 캐시)은 글자 규칙을 부르지 않는다 — 부르면 시끄럽게 실패한다(근사를 두지 않는다).
     * 글자 규칙까지 재는 G5 골든 대조는 실제 구현(rules `RulesWireTextRules`)을 꽂고 core/stores 에서 돈다(6차 c-fold).
     */
    private object UnusedTextRules : WireTextRules {
        override fun sanitized(raw: String): String = error("NetContractsTest 는 글자 규칙을 쓰지 않는다")
        override fun hasVisibleContent(text: String): Boolean = error("NetContractsTest 는 글자 규칙을 쓰지 않는다")
        override fun statusMessageSanitized(raw: String): String = error("NetContractsTest 는 글자 규칙을 쓰지 않는다")
    }

    private fun protocolOf(body: String): String? = (SwiftJson.parse(body) as JsonObject)["p_protocol"]?.toString()

    /** C§4 #9: 함수 없음(PGRST202)으로 깃발이 서면 **300초 미만** 옛 모양, 300초부터 새 모양을 다시 묻는다(시계 주입 — 5분을 기다리지 않는다). */
    @Test
    fun shopProtocolFlagExpiresAfterFiveMinutes() {
        var now = t0
        val pgrst202 = 404 to """{"code":"PGRST202","message":"Could not find the function public.shop_state(p_protocol) in the schema cache"}"""
        val s = Scripted(listOf(pgrst202, 200 to "{}", 200 to "{}", 200 to "{}", 200 to "{}"))
        val (svc, client) = service(s.engine) { now }
        runBlocking {
            svc.fetchShopState("a", 4) // 새 모양 → 404 → 옛 모양(깃발 t0)
            now = t0.addingTimeInterval(1.0)
            svc.fetchShopState("a", 4)
            now = t0.addingTimeInterval(299.999)
            svc.fetchShopState("a", 4)
            now = t0.addingTimeInterval(300.0)
            svc.fetchShopState("a", 4)
        }
        client.close()
        assertEquals(listOf("4", null, null, null, "4"), s.bodies.map(::protocolOf), "깃발: 0초 새→옛 · 1초 옛 · 299.999초 옛 · 300초 새")
    }

    /** INV-SupabaseWorkService-50250b14: 맨 404(본문이 PostgREST 오류가 아님)는 되묻되 깃발을 세우지 않는다 — 다음 호출은 다시 새 모양. */
    @Test
    fun plain404RetriesWithoutFlag() {
        val s = Scripted(listOf(404 to "<html>404 Not Found</html>", 200 to "{}", 200 to "{}"))
        val (svc, client) = service(s.engine) { t0 }
        runBlocking {
            svc.fetchShopState("a", 4)
            svc.fetchShopState("a", 4)
        }
        client.close()
        assertEquals(listOf("4", null, "4"), s.bodies.map(::protocolOf))
    }

    /** 되묻기까지 실패하면 깃발을 세우지 않는다(아픈 서버 한 번에 앱을 강등시키지 않는다) — 다음 호출은 새 모양. */
    @Test
    fun failedLegacyRetryDoesNotFlag() {
        val pgrst202 = 404 to """{"code":"PGRST202","message":"Could not find the function public.shop_state(p_protocol) in the schema cache"}"""
        val s = Scripted(listOf(pgrst202, 503 to "", 200 to "{}"))
        val (svc, client) = service(s.engine) { t0 }
        val first = runBlocking { runCatching { svc.fetchShopState("a", 4) } }
        runBlocking { svc.fetchShopState("a", 4) }
        client.close()
        assertEquals(SupabaseWorkServiceError.InvalidResponse(503), first.exceptionOrNull())
        assertEquals(listOf("4", null, "4"), s.bodies.map(::protocolOf))
    }

    /** C§4 #39: 요청마다 Ktor HttpTimeout 이 싣는 값 = 리소스(요청 전체) 30초 · 소켓(패킷 사이) 15초. 캐시 플러그인 없음. */
    @Test
    fun clientConfigIs15And30SecondsWithoutCache() {
        val s = Scripted(listOf(200 to "[]"))
        val (svc, client) = service(s.engine) { t0 }
        runBlocking { svc.fetchMyInviteCode("a") }
        assertNull(client.pluginOrNull(HttpCache), "응답 캐시는 끈다(SupabaseWorkService.swift:19-33)")
        client.close()
        assertEquals(listOf(Triple<Long?, Long?, Long?>(30_000L, 15_000L, null)), s.timeouts, "HttpTimeout(요청 30초 · 소켓 15초 · 연결은 요청 상한 안)")
    }

    /** C§4 #3: 전송 실패(IOException 계열 전체 · 원인 사슬)는 세션 유지, 디코드·논리 오류는 치명, 취소는 아무것도 안 바뀜. */
    @Test
    fun transportFailuresKeepTheSession() {
        val transient = listOf(
            java.io.IOException("x"), java.io.InterruptedIOException("timeout"), java.io.EOFException("eof"),
            java.net.SocketTimeoutException("t"), java.net.ConnectException("c"), java.net.UnknownHostException("h"),
            java.net.ProtocolException("p"), java.net.SocketException("reset"), java.net.NoRouteToHostException("r"),
            javax.net.ssl.SSLException("s"), javax.net.ssl.SSLHandshakeException("h"), javax.net.ssl.SSLPeerUnverifiedException("v"),
            okhttp3.internal.http2.StreamResetException(okhttp3.internal.http2.ErrorCode.INTERNAL_ERROR),
            io.ktor.client.plugins.HttpRequestTimeoutException("https://golden.invalid", 30_000),
            io.ktor.client.network.sockets.ConnectTimeoutException("c"),
            io.ktor.client.network.sockets.SocketTimeoutException("s"),
            java.nio.channels.UnresolvedAddressException(),
            RuntimeException("감쌈", java.io.IOException("안쪽")),
            SupabaseWorkServiceError.InvalidResponse(503), SupabaseWorkServiceError.RateLimited(null), SupabaseWorkServiceError.InvalidResponse(429),
        )
        for (e in transient) assertEquals(AuthErrorDisposition.transient, AuthErrorRules.classify(e), "세션 유지여야 한다: ${e::class.qualifiedName}")
        val fatal = listOf(
            IllegalStateException("논리"), SerializationException("디코드"), SupabaseWorkServiceError.SessionExpired,
            SupabaseWorkServiceError.InvalidResponse(401), RuntimeException("감쌈", IllegalArgumentException("x")),
        )
        for (e in fatal) assertEquals(AuthErrorDisposition.fatal, AuthErrorRules.classify(e), "치명이어야 한다: ${e::class.qualifiedName}")
        assertEquals(AuthErrorDisposition.cancelled, AuthErrorRules.classify(CancellationException("x")))
    }

    /**
     * C§4 #18: 실시간 하트비트 25초와 근무 하트비트 30초는 **이름도 값도 다르다**(RealtimeLink.swift:76-84) — 소스 계약(주석을 걷고 잰다).
     *  · 실시간 상수는 `RealtimeLinkConstants.heartbeatIntervalSeconds = 25.0` 한 곳이고, 링 코드는 그 이름으로만 25 를 쓴다(맨 숫자 25 금지).
     *  · `multiplatform/` 의 다른 어떤 선언도 `heartbeatIntervalSeconds` 라는 이름을 쓰지 않는다(근무 하트비트 — W2-g·W2-f — 는 다른 이름).
     *  · 이름에 heartbeat 가 든 다른 상수는 25 가 아니다(근무 30초가 실시간 값에 묶이지 않게).
     */
    @Test
    fun realtimeHeartbeatIsNotTheWorkHeartbeat() {
        assertEquals(25.0, RealtimeLinkConstants.heartbeatIntervalSeconds)
        val root = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "settings.gradle.kts").exists() }
        val sources = root.walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" && !it.name.startsWith(".") }
            .filter { it.isFile && it.extension == "kt" }
            .toList()
        assertTrue(sources.size > 50, "소스를 못 찾았다(${sources.size}) — 뿌리 ${root.path}")
        val decl = Regex("""\b(?:const\s+)?va[lr]\s+(\w*[Hh]eartbeat\w*)\s*(?::\s*\w+)?\s*=\s*([0-9][0-9_.]*)""")
        val realtimeDecls = mutableListOf<String>()
        val problems = mutableListOf<String>()
        for (f in sources) {
            val code = stripComments(f.readText())
            for (m in decl.findAll(code)) {
                val name = m.groupValues[1]
                val value = m.groupValues[2].replace("_", "").toDouble()
                val where = "${f.relativeTo(root)}: $name = ${m.groupValues[2]}"
                if (name == "heartbeatIntervalSeconds") {
                    if (f.name == "RealtimeLink.kt") realtimeDecls += where else problems += "실시간 하트비트 이름을 다른 곳이 쓴다 — $where"
                } else if (value == 25.0) {
                    problems += "하트비트 이름의 다른 상수가 25 다 — $where"
                }
            }
        }
        assertEquals(1, realtimeDecls.size, "실시간 하트비트 선언은 RealtimeLink.kt 한 곳: $realtimeDecls")
        val link = stripComments(sources.single { it.name == "RealtimeLink.kt" }.readText())
        val literal25 = Regex("""(?<![\w.])25(?:\.0)?(?![\w.])""").findAll(link).map { m ->
            link.substring(maxOf(0, m.range.first - 40), minOf(link.length, m.range.last + 20)).replace("\n", " ")
        }.filterNot { it.contains("heartbeatIntervalSeconds: Double = 25") }.toList()
        assertTrue(literal25.isEmpty(), "링 코드가 25 를 맨 숫자로 쓴다(상수 이름으로만): $literal25")
        assertTrue(problems.isEmpty(), problems.joinToString("\n"))
    }

    private fun stripComments(src: String): String {
        val out = StringBuilder()
        var i = 0
        var inString = false
        while (i < src.length) {
            val c = src[i]
            if (inString) {
                out.append(c)
                if (c == '\\' && i + 1 < src.length) { out.append(src[i + 1]); i += 2; continue }
                if (c == '"') inString = false
                i++
                continue
            }
            if (c == '"') { inString = true; out.append(c); i++; continue }
            if (src.startsWith("//", i)) { while (i < src.length && src[i] != '\n') i++; continue }
            if (src.startsWith("/*", i)) { val end = src.indexOf("*/", i + 2); i = if (end < 0) src.length else end + 2; continue }
            out.append(c)
            i++
        }
        return out.toString()
    }

    @Test
    fun swiftTryAllSwallowsServiceErrorsButNotCancellation() {
        assertNull(swiftTryAll<Int> { throw SupabaseWorkServiceError.InvalidResponse(500) })
        assertNull(swiftTryAll<Int> { throw java.io.IOException("x") })
        assertNotNull(runCatching { swiftTryAll<Int> { throw CancellationException("x") } }.exceptionOrNull())
    }
}
