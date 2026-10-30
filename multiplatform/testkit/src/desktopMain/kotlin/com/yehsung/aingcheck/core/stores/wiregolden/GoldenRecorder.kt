// 원본: multiplatform/core/stores/src/desktopTest/kotlin/com/yehsung/aingcheck/core/stores/wiregolden/WireRequestsGoldenTest.kt — G5 녹음기
//   (`GoldenRecorder` · `GoldenRoute` · `dumpError` · `GoldenRecorder.canonical`). 공용 패치 13: 몸 그대로 testkit 으로 옮겼다(FQN 그대로) —
//   데스크톱 갈래 시험(feature/desktop)이 본뜬 사본을 두지 않게. dumpError 만 private → public(모듈을 건너 보이게).
package com.yehsung.aingcheck.core.stores.wiregolden

import com.yehsung.aingcheck.core.net.*
import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.stores.service.achievementClaim
import com.yehsung.aingcheck.core.stores.service.achievementsStatus
import com.yehsung.aingcheck.core.stores.service.dailyMissionClaim
import com.yehsung.aingcheck.core.stores.service.fetchMyAILimits
import com.yehsung.aingcheck.core.stores.service.megaphoneInfo
import com.yehsung.aingcheck.core.stores.service.sendMegaphone
import com.yehsung.aingcheck.core.stores.service.setStatusMessageOutcome
import com.yehsung.aingcheck.core.stores.service.weeklyWorkClaim
import com.yehsung.aingcheck.core.stores.service.weeklyWorkStatus
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.CharacterSyncFetchError
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.dump.GoldenScrub
import kotlinx.serialization.SerializationException
import com.yehsung.aingcheck.core.wire.games.GomokuChatKind
import com.yehsung.aingcheck.core.wire.games.TetrisReportRequest
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import com.yehsung.aingcheck.core.wire.models.FeedbackKind
import com.yehsung.aingcheck.core.wire.models.FeedbackStatus
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.core.wire.models.TodoSyncRequest
import com.yehsung.aingcheck.core.wire.models.TodoSyncWireItem
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.decodeURLQueryComponent
import io.ktor.http.headersOf
import io.ktor.client.request.get
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.util.Base64
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

const val ACCESS = "golden-access-token"
const val ANON = "golden-anon-key"

/**
 * Swift `GoldenMirror.dump(SupabaseWorkServiceError)` 와 같은 모양(core/net 시험 `ErrorsJwtGoldenTest.dumpError` 와 같은 꼴 — 시험 소스는
 * 모듈을 건너 나눠 쓸 수 없어 여기 한 벌 둔다. 모양이 갈리면 G5 의 throws 결과가 빨개진다).
 */
fun dumpError(e: SupabaseWorkServiceError): JsonElement = when (e) {
    is SupabaseWorkServiceError.RateLimited -> JsonObject(
        mapOf("\$case" to JsonPrimitive("rateLimited"), "\$value" to (e.retryAfterSeconds?.let { JsonPrimitive(it) } ?: JsonNull)),
    )
    is SupabaseWorkServiceError.AuthMessage -> JsonObject(mapOf("\$case" to JsonPrimitive("authMessage"), "\$value" to JsonPrimitive(e.text)))
    is SupabaseWorkServiceError.InvalidResponse -> JsonObject(mapOf("\$case" to JsonPrimitive("invalidResponse"), "\$value" to JsonPrimitive(e.statusCode)))
    else -> JsonPrimitive(e.caseName)
}

/** 동시에 떠나는 요청의 응답 고르기(Swift `WireRoute`): 경로가 같고, 쿼리 쌍이 있으면 디코드한 쿼리에 그 쌍이 있어야 한다. */
data class GoldenRoute(val path: String, val query: Pair<String, String>?, val status: Int, val body: String)

/** 요청 녹음 + 응답 대본(차례대로, 끝나면 200 `{}`). 길이 있으면 차례 대신 요청 모양으로 고른다. */
class GoldenRecorder(private val script: List<Pair<Int, String>>, private val routes: List<GoldenRoute> = emptyList()) {
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
                // 요청 본문 JSON 은 언제나 객체·배열이다. 맨 글자("JPEG-BYTES")는 kotlinx 가 낱말로 읽어도 바이트로 본다(Swift 파서는 실패).
                require(parsed is JsonObject || parsed is JsonArray) { "JSON 객체·배열이 아니다" }
                val canon = GoldenCanonical.text(canonical(parsed))
                SwiftJson.parse(scrub(canon))
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
        // ★ 처리기 람다의 this 는 요청마다 새 MockRequestHandleScope 다 — synchronized(this) 는 아무것도 막지 않아 동시 요청(팀 상태 4 GET)이
        //   ArrayList 에 겹쳐 써서 요청을 잃거나 AIOOBE 를 냈다(Windows CI 실측 `fetchTeamStatuses#devicesFail`). 녹음기 자신으로 잠근다.
        synchronized(this@GoldenRecorder) { requests += recorded }
        val (status, text) = if (routes.isNotEmpty()) {
            val decoded = query.map { (it as JsonArray).let { p -> (p[0] as JsonPrimitive).content to (p[1] as JsonPrimitive).content } }
            routes.firstOrNull { r -> r.path == request.url.encodedPath && (r.query == null || decoded.contains(r.query)) }
                ?.let { it.status to it.body } ?: (200 to "{}")
        } else {
            synchronized(this@GoldenRecorder) { if (next < script.size) script[next++] else 200 to "{}" }
        }
        respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
    }

    companion object {
        val WHITELIST = setOf("apikey", "authorization", "accept", "content-type", "prefer", "x-upsert")
        private val INT = Regex("""-?(0|[1-9][0-9]*)""")

        fun scrub(text: String): String = text.replace(ACCESS, "<ACCESS>").replace(ANON, "<ANON>")
            .replace(Regex("""\?v=[0-9]+-[0-9A-F]{8}"""), "?v=<CACHE_BUSTER>")

        /** Swift `WireJSON.golden` 과 같은 정규화: 정수 글자 → 숫자, 그 밖 숫자 → {"$num": 글자}. */
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
    }
}
