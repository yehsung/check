// 원본(시험 기반): G5 녹음기는 testkit `com.yehsung.aingcheck.core.stores.wiregolden.GoldenRecorder`(공용 패치 13 — core/stores 시험에서 옮김)를
//   그대로 쓴다. 여기는 데스크톱 근무 골든의 몫만: 벽시계 키 표식(spec.wallClockKeys) · 녹음기 위 서비스 짓기 · 가짜 SessionHost · 결과 덤프.
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

const val ACCESS = com.yehsung.aingcheck.core.stores.wiregolden.ACCESS
const val ANON = com.yehsung.aingcheck.core.stores.wiregolden.ANON
const val GOLDEN_USER = "aa000000-0000-4000-8000-0000000000a1"
/** 2026-09-17 05:05:00Z(Swift WireGoldenValues.now). */
val GOLDEN_NOW = SwiftDate(1_789_621_500.0)
val WALL_CLOCK_KEYS = setOf("last_seen_at", "updated_at", "auto_closed_at")

/** G5 녹음기 — testkit 한 벌(공용 패치 13, core/stores 와 같은 클래스). 이 파일은 데스크톱 몫(벽시계 표식·서비스 짓기·가짜 세션)만 더한다. */
typealias GoldenRecorder = com.yehsung.aingcheck.core.stores.wiregolden.GoldenRecorder

fun GoldenRecorder.service(clock: () -> SwiftDate = { GOLDEN_NOW }): Pair<SupabaseWorkService, HttpClient> {
    val client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }
    return SupabaseWorkService(
        projectURL = "https://golden.invalid", anonKey = ANON, client = client,
        clock = clock, text = RulesWireTextRules, newUUIDString = { "ABCDEF12-3456-4789-8ABC-DEF012345678" },
    ) to client
}

/** spec.wallClockKeys: 본문 객체의 그 키 값(글자)을 "<WALL>" 로(Swift `maskWall` 과 같은 규칙). */
fun com.yehsung.aingcheck.core.stores.wiregolden.GoldenRecorder.Companion.maskWall(e: JsonElement): JsonElement = when (e) {
    is JsonObject -> JsonObject(
        e.mapValues { (k, v) -> if (k in WALL_CLOCK_KEYS && v is JsonPrimitive && v.isString) JsonPrimitive("<WALL>") else maskWall(v) },
    )
    is JsonArray -> JsonArray(e.map { maskWall(it) })
    else -> e
}

fun com.yehsung.aingcheck.core.stores.wiregolden.GoldenRecorder.Companion.masked(requests: List<JsonObject>): List<JsonObject> =
    requests.map { r -> JsonObject(r.toMutableMap().apply { put("body", maskWall(r["body"]!!)) }) }

/** Swift `GoldenMirror.dump(SupabaseWorkServiceError)` 모양(core 시험 `dumpError` 와 같은 꼴). */
fun dumpError(e: SupabaseWorkServiceError): JsonElement = com.yehsung.aingcheck.core.stores.wiregolden.dumpError(e)

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
