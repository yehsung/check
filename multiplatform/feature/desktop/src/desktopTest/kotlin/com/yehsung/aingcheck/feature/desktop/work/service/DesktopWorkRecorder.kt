// 원본(시험 기반): multiplatform/core/stores/src/desktopTest/kotlin/com/yehsung/aingcheck/core/stores/wiregolden/WireRequestsGoldenTest.kt
//   `GoldenRecorder` · `dumpError` · `canonical`(G5 녹음기 — 헤더 6 화이트리스트 · 쿼리 쌍 · 정규 본문). 시험 소스는 모듈을 건너
//   나눠 쓸 수 없어(공용 패치 7 전) 여기 본뜬 한 벌을 둔다. 더한 것: 벽시계 키 표식(spec.wallClockKeys) · 가짜 SessionHost.
package com.yehsung.aingcheck.feature.desktop.work.service

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySyncUnavailable
import com.yehsung.aingcheck.feature.desktop.work.wire.WorkTickFailure
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.dump.GoldenScrub
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.decodeURLQueryComponent
import io.ktor.http.headersOf
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.util.Base64
import kotlin.coroutines.cancellation.CancellationException

const val ACCESS = "golden-access-token"
const val ANON = "golden-anon-key"
const val GOLDEN_USER = "aa000000-0000-4000-8000-0000000000a1"
/** 2026-09-17 05:05:00Z(Swift WireGoldenValues.now). */
val GOLDEN_NOW = SwiftDate(1_789_621_500.0)
val WALL_CLOCK_KEYS = setOf("last_seen_at", "updated_at", "auto_closed_at")

/** 녹음한 요청 한 건(쿼리는 디코드한 쌍, 본문은 정규 JSON — 벽시계 표식 **전**). */
class GoldenRecorder(private val script: List<Pair<Int, String>>) {
    val requests = mutableListOf<JsonObject>()
    private var next = 0

    val engine = MockEngine { request ->
        val bodyBytes: ByteArray? = when (val b = request.body) {
            is OutgoingContent.ByteArrayContent -> b.bytes()
            is OutgoingContent.NoContent -> null
            else -> error("모르는 본문 ${b::class.simpleName}")
        }
        val headers = linkedMapOf<String, JsonElement>()
        for ((k, vs) in request.headers.entries()) {
            if (k.lowercase() in WHITELIST) headers[k.lowercase()] = JsonPrimitive(scrub(vs.joinToString(",")))
        }
        request.body.contentType?.let { if (bodyBytes != null) headers["content-type"] = JsonPrimitive(it.toString()) }
        val rawQuery = request.url.encodedQuery
        val query = if (rawQuery.isEmpty()) emptyList() else rawQuery.split('&').map { kv ->
            val i = kv.indexOf('=')
            val name = (if (i < 0) kv else kv.substring(0, i)).decodeURLQueryComponent(plusIsSpace = false)
            val value = if (i < 0) "" else kv.substring(i + 1).decodeURLQueryComponent(plusIsSpace = false)
            JsonArray(listOf(JsonPrimitive(name), JsonPrimitive(scrub(value))))
        }
        val body: JsonElement = when {
            bodyBytes == null || bodyBytes.isEmpty() -> JsonNull
            else -> try {
                val parsed = SwiftJson.parse(bodyBytes.decodeToString())
                require(parsed is JsonObject || parsed is JsonArray) { "JSON 객체·배열이 아니다" }
                SwiftJson.parse(scrub(GoldenCanonical.text(canonical(parsed))))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                JsonObject(mapOf("\$bytes" to JsonPrimitive(Base64.getEncoder().encodeToString(bodyBytes))))
            }
        }
        val recorded = JsonObject(
            mapOf(
                "method" to JsonPrimitive(request.method.value),
                "path" to JsonPrimitive(request.url.encodedPath),
                "query" to JsonArray(query),
                "headers" to JsonObject(headers),
                "body" to body,
            ),
        )
        synchronized(this@GoldenRecorder) { requests += recorded }
        val (status, text) = synchronized(this@GoldenRecorder) { if (next < script.size) script[next++] else 200 to "{}" }
        respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
    }

    fun service(clock: () -> SwiftDate = { GOLDEN_NOW }): Pair<SupabaseWorkService, HttpClient> {
        val client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }
        return SupabaseWorkService(
            projectURL = "https://golden.invalid", anonKey = ANON, client = client,
            clock = clock, text = RulesWireTextRules, newUUIDString = { "ABCDEF12-3456-4789-8ABC-DEF012345678" },
        ) to client
    }

    companion object {
        val WHITELIST = setOf("apikey", "authorization", "accept", "content-type", "prefer", "x-upsert")
        private val INT = Regex("""-?(0|[1-9][0-9]*)""")

        fun scrub(text: String): String = text.replace(ACCESS, "<ACCESS>").replace(ANON, "<ANON>")

        fun canonical(e: JsonElement): JsonElement = when (e) {
            is JsonObject -> JsonObject(e.mapValues { canonical(it.value) })
            is JsonArray -> JsonArray(e.map { canonical(it) })
            is JsonNull -> JsonNull
            is JsonPrimitive -> when {
                e.isString -> e
                e.booleanOrNull != null -> e
                INT.matches(e.content) && (e.content.toLongOrNull()?.let { kotlin.math.abs(it) <= GoldenCanonical.MAX_SAFE_INTEGER } == true) ->
                    JsonPrimitive(e.content.toLong())
                else -> JsonObject(mapOf("\$num" to JsonPrimitive(e.content)))
            }
        }

        /** spec.wallClockKeys: 본문 객체의 그 키 값(글자)을 "<WALL>" 로(Swift `maskWall` 과 같은 규칙). */
        fun maskWall(e: JsonElement): JsonElement = when (e) {
            is JsonObject -> JsonObject(
                e.mapValues { (k, v) -> if (k in WALL_CLOCK_KEYS && v is JsonPrimitive && v.isString) JsonPrimitive("<WALL>") else maskWall(v) },
            )
            is JsonArray -> JsonArray(e.map { maskWall(it) })
            else -> e
        }

        fun masked(requests: List<JsonObject>): List<JsonObject> =
            requests.map { r -> JsonObject(r.toMutableMap().apply { put("body", maskWall(r["body"]!!)) }) }
    }
}

/** Swift `GoldenMirror.dump(SupabaseWorkServiceError)` 모양(core 시험 `dumpError` 와 같은 꼴). */
fun dumpError(e: SupabaseWorkServiceError): JsonElement = when (e) {
    is SupabaseWorkServiceError.RateLimited -> JsonObject(
        mapOf("\$case" to JsonPrimitive("rateLimited"), "\$value" to (e.retryAfterSeconds?.let { JsonPrimitive(it) } ?: JsonNull)),
    )
    is SupabaseWorkServiceError.AuthMessage -> JsonObject(mapOf("\$case" to JsonPrimitive("authMessage"), "\$value" to JsonPrimitive(e.text)))
    is SupabaseWorkServiceError.InvalidResponse -> JsonObject(mapOf("\$case" to JsonPrimitive("invalidResponse"), "\$value" to JsonPrimitive(e.statusCode)))
    else -> JsonPrimitive(e.caseName)
}

/** Swift `GoldenMirror.dump(WorkTickFailure)` — 연관값 하나면 그 값, 둘이면 이름표 객체. */
fun dumpTickFailure(e: WorkTickFailure): JsonElement {
    fun case(name: String, value: JsonElement) = JsonObject(mapOf("\$case" to JsonPrimitive(name), "\$value" to value))
    fun s(v: String?) = v?.let(::JsonPrimitive) ?: JsonNull
    return when (e) {
        is WorkTickFailure.FunctionMissing -> case("functionMissing", s(e.code))
        is WorkTickFailure.Forbidden -> case("forbidden", s(e.code))
        is WorkTickFailure.ContractMismatch -> case("contractMismatch", e.version?.let(::JsonPrimitive) ?: JsonNull)
        WorkTickFailure.Undecodable -> JsonPrimitive("undecodable")
        is WorkTickFailure.ServerError -> case("serverError", JsonPrimitive(e.status))
        is WorkTickFailure.Rejected -> case("rejected", JsonObject(mapOf("status" to JsonPrimitive(e.status), "code" to s(e.code))))
    }
}

val dumper = GoldenDump(leaf = { v -> if (v is SwiftDate) GoldenDump.date(v.timeIntervalSince1970) else null })

private fun scrubLeaves(e: JsonElement): JsonElement = when (e) {
    is JsonObject -> JsonObject(e.mapValues { scrubLeaves(it.value) })
    is JsonArray -> JsonArray(e.map { scrubLeaves(it) })
    is JsonPrimitive -> if (e.isString) JsonPrimitive(GoldenScrub.text(GoldenRecorder.scrub(e.content))) else e
    else -> e
}

/** Swift `WireResult`: {"ok": 덤프} · {"throws": …}. */
fun resultOf(value: Any?): JsonElement = when (value) {
    null -> JsonObject(mapOf("ok" to JsonNull))
    Unit -> JsonObject(mapOf("ok" to JsonPrimitive("\$void")))
    else -> JsonObject(mapOf("ok" to scrubLeaves(dumper.dump(value))))
}

fun thrownOf(e: Throwable): JsonElement {
    fun typed(name: String, dump: JsonElement) = JsonObject(mapOf("\$type" to JsonPrimitive(name), "\$dump" to dump))
    return JsonObject(
        mapOf(
            "throws" to when (e) {
                is SupabaseWorkServiceError -> dumpError(e)
                is SerializationException -> JsonPrimitive("\$decoding")
                is WorkTickFailure -> typed("WorkTickFailure", dumpTickFailure(e))
                is AwaySyncUnavailable -> typed("AwaySyncUnavailable", JsonObject(emptyMap()))
                else -> JsonObject(mapOf("\$type" to JsonPrimitive(e::class.qualifiedName ?: "?"), "\$message" to JsonPrimitive(e.message ?: "")))
            },
        ),
    )
}

/** 시험용 SessionHost — 세션 하나, 세대는 시험이 올린다. withSessionRetry 는 그대로 한 번(401 갱신은 core 몫). */
class FakeSessionHost(override val service: SupabaseWorkService, userID: String = GOLDEN_USER) : SessionHost {
    @Volatile var current: SupabaseSession? = SupabaseSession(ACCESS, null, userID)
    @Volatile var generation = 0
    /** withSessionRetry 가 불릴 때마다(테스트가 세대를 옮기는 갈고리). */
    var onCall: (Int) -> Unit = {}
    private var calls = 0
    override val session: SupabaseSession? get() = current
    override val sessionGeneration: Int get() = generation
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T {
        val s = current ?: throw SupabaseWorkServiceError.SessionExpired
        val r = operation(s)
        onCall(++calls)
        return r
    }
}
