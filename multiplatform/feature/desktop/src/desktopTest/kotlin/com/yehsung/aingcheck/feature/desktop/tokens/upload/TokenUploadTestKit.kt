// W2-h3 시험 도우미 — MockEngine 가 받은 요청을 골든과 같은 모양({method, path, query, prefer, body})으로 적는다. 바깥 연결 0.
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

class RecordingBackend(private val statusFor: (path: String) -> Int = { 201 }) {
    val requests = ArrayList<JsonObject>()
    val engine = MockEngine { request ->
        val bytes = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()
        val body: JsonElement = if (bytes == null || bytes.isEmpty()) JsonNull else Json.parseToJsonElement(bytes.decodeToString())
        val query = JsonArray(request.url.parameters.entries().flatMap { (k, vs) -> vs.map { JsonArray(listOf(JsonPrimitive(k), JsonPrimitive(it))) } })
        synchronized(requests) {
            requests += JsonObject(mapOf(
                "method" to JsonPrimitive(request.method.value),
                "path" to JsonPrimitive(request.url.encodedPath),
                "query" to query,
                "prefer" to (request.headers["Prefer"]?.let { JsonPrimitive(it) } ?: JsonNull),
                "body" to body,
            ))
        }
        val status = statusFor(request.url.encodedPath)
        val text = if (request.url.encodedPath.contains("/rpc/")) "[]" else ""
        respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
    }
    val service: SupabaseWorkService = SupabaseWorkService(
        "https://golden.invalid", "anon-test-key", HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
        { SwiftDate.fromEpochMillis(1_793_322_123_000) }, UnusedTextRules,
    ) { "ABCDEF12-0000-4000-8000-000000000000" }

    fun take(): JsonArray = synchronized(requests) { JsonArray(requests.toList()).also { requests.clear() } }
    fun paths(): List<String> = synchronized(requests) { requests.map { (it["path"] as JsonPrimitive).content } }

    private object UnusedTextRules : WireTextRules {
        override fun sanitized(raw: String): String = error("토큰 업로드 시험은 글자 규칙을 쓰지 않는다")
        override fun hasVisibleContent(text: String): Boolean = error("토큰 업로드 시험은 글자 규칙을 쓰지 않는다")
        override fun statusMessageSanitized(raw: String): String = error("토큰 업로드 시험은 글자 규칙을 쓰지 않는다")
    }
}

/** 세션 문 가짜 — 401 재시도 없이 지금 세션으로 한 번. */
class FakeSessionHost(override val service: SupabaseWorkService, var current: SupabaseSession? = SupabaseSession("access-token", null, "u-1")) : SessionHost {
    override val session: SupabaseSession? get() = current
    override var sessionGeneration: Int = 1
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(current ?: error("세션 없음"))
}

fun epoch(seconds: Long): SwiftDate = SwiftDate.fromEpochMillis(seconds * 1000)
