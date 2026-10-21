// 원본: Sources/CheckMobileKit/Demo/MobileStubURLProtocol.swift @ a63fea2(스텁 서버 · 요청 기록)
// K2 MockEngine 라우터: 소켓 0개(인메모리). 모르는 요청은 **실패**한다 — Swift 스텁이 금지 호출을 판정하는 자리와 같다.
package com.yehsung.aingcheck.testkit.mock

import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.HttpResponseData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.io.IOException

/** 라우터가 받은 요청 한 건. 본문은 UTF-8 글자로 남긴다(키 집합 단언용). */
data class RecordedRequest(
    val method: String,
    val path: String,
    val query: List<Pair<String, String>>,
    val headers: Map<String, List<String>>,
    val bodyText: String,
) {
    /** `/rest/v1/rpc/<name>` 이면 name. */
    val rpcName: String?
        get() = if (path.startsWith(RPC_PREFIX)) path.removePrefix(RPC_PREFIX) else null

    fun queryValue(name: String): String? = query.firstOrNull { it.first == name }?.second

    /** 라우트 열쇠: "METHOD /path" (쿼리 제외). */
    val key: String get() = "$method $path"

    companion object {
        const val RPC_PREFIX = "/rest/v1/rpc/"
    }
}

/** 등록 안 된 요청. 코드 쪽에는 전송 실패로 보이고, 시험 끝 [MockRouter.assertAllRouted] 가 빨갛게 한다. */
class UnroutedRequestException(val request: RecordedRequest) :
    IllegalStateException("MockRouter: 등록 안 된 요청 ${request.key} — 모르는 요청은 실패한다")

/** 시험이 쓰는 응답 하나. */
sealed interface StubResponse {
    data class Json(val body: String, val status: Int = 200, val headers: Map<String, String> = emptyMap()) : StubResponse
    /** 전송 실패(오프라인·끊김) 재현 — 서비스는 일시 오류(transient)로 접어야 한다. */
    data class TransportFailure(val message: String = "offline") : StubResponse

    companion object {
        /** PostgREST 가 함수를 못 찾을 때(PGRST202) — 서버가 준비 안 된 응답(.databaseSchemaMissing). */
        fun missingFunction(name: String): StubResponse = Json(
            """{"code":"PGRST202","message":"Could not find the function public.$name in the schema cache"}""",
            status = 404,
        )

        /** 저장소 픽스처 파일(저장소 뿌리 기준 경로, 예: `Tests/checkTests/Fixtures/message-rpc/flow_a_reads_b__mark.json`). */
        fun fixture(repoRelativePath: String, status: Int = 200): StubResponse = Json(RepoFiles.readText(repoRelativePath), status)
    }
}

/**
 * Ktor [MockEngine] 라우터.
 *
 * - 라우트는 "METHOD /path"(쿼리 제외)로 찾는다. 같은 열쇠에 응답을 여러 번 등록하면 차례대로 쓰고, 마지막 것을 되풀이한다.
 * - 모든 요청을 기록한다([requests]). 등록 안 된 요청은 [unrouted] 에 쌓이고 그 호출은 실패한다.
 * - 시험 끝에 [assertAllRouted] 를 부른다. 폰 갈래는 [PhoneForbiddenCalls.violations] 도 단언한다.
 */
class MockRouter {
    private val routes = LinkedHashMap<String, ArrayDeque<StubResponse>>()
    private val recorded = mutableListOf<RecordedRequest>()
    private val unroutedList = mutableListOf<RecordedRequest>()

    val requests: List<RecordedRequest> get() = recorded.toList()
    val unrouted: List<RecordedRequest> get() = unroutedList.toList()

    fun on(method: HttpMethod, path: String, vararg responses: StubResponse): MockRouter {
        require(responses.isNotEmpty()) { "응답이 하나는 있어야 한다" }
        require(path.startsWith("/") && '?' !in path) { "경로는 /로 시작하고 쿼리를 넣지 않는다: $path" }
        routes.getOrPut("${method.value} $path") { ArrayDeque() }.addAll(responses)
        return this
    }

    fun rpc(name: String, vararg responses: StubResponse): MockRouter =
        on(HttpMethod.Post, RecordedRequest.RPC_PREFIX + name, *responses)

    fun assertAllRouted() {
        check(unroutedList.isEmpty()) {
            "MockRouter: 등록 안 된 요청 ${unroutedList.size}건 — " + unroutedList.joinToString { it.key }
        }
    }

    val engine: MockEngine = MockEngine { request -> handle(request) }

    private suspend fun MockRequestHandleScope.handle(request: HttpRequestData): HttpResponseData {
        val entry = RecordedRequest(
            method = request.method.value,
            path = request.url.encodedPath,
            query = request.url.parameters.entries().flatMap { (k, vs) -> vs.map { k to it } },
            headers = request.headers.entries().associate { it.key to it.value },
            bodyText = bodyText(request.body),
        )
        recorded += entry
        val queue = routes[entry.key]
        if (queue == null || queue.isEmpty()) {
            unroutedList += entry
            throw UnroutedRequestException(entry)
        }
        val response = if (queue.size > 1) queue.removeFirst() else queue.first()
        return when (response) {
            is StubResponse.TransportFailure -> throw IOException(response.message)
            is StubResponse.Json -> respond(
                content = response.body,
                status = HttpStatusCode.fromValue(response.status),
                headers = headersOf(
                    *(mapOf(HttpHeaders.ContentType to "application/json") + response.headers)
                        .map { (k, v) -> k to listOf(v) }.toTypedArray(),
                ),
            )
        }
    }

    private fun bodyText(body: OutgoingContent): String = when (body) {
        is OutgoingContent.ByteArrayContent -> body.bytes().decodeToString()
        is OutgoingContent.NoContent -> ""
        else -> "<${body::class.simpleName}>"
    }
}
