// 원본: Sources/CheckCore/ReversiWire.swift:487-559(서비스 호출 10개) · DuelRPC.swift(40P01 한 번 재시도) @ 12624739 — 요청 본문·결과 대조는 G5 요청 골든(core/stores WireRequestsGoldenTest 의 reversi* 12 case)이 한다. 이 시험은 그와 별개로 RPC 열 개 전부의 경로·본문 키와 교착 재시도 횟수를 잰다
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.games.ReversiRPCStatus
import com.yehsung.aingcheck.core.wire.games.ReversiWire
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기 서비스 호출 10개 — 실제로 나간 요청(경로 · 방법 · 본문)과 교착(40P01) 한 번 재시도를 MockEngine 으로 잰다(망 0).
 * ① 경로는 `/rest/v1/rpc/reversi_*` 그대로 ② 본문은 `p_protocol` 1 을 **언제나** 싣고 키가 서버 인자 이름과 같다 ③ 쓰기 전부 + reversi_state 만
 * 교착 둘 중 정확히 한 번 더(2회), 로비·순위·관전 둘은 다시 보내지 않는다(1회). G5 골든은 교착 case 가 없어(오목·체스·큐브의 `#deadlock` 과 달리) 재시도 횟수는 여기서만 잡힌다.
 */
class ReversiRpcTest {
    private class Scripted(private val script: List<Pair<Int, String>>) {
        val calls = mutableListOf<Triple<String, String, String>>()
        private var next = 0
        val engine = MockEngine { request ->
            val bytes = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()
            synchronized(this@Scripted) { calls += Triple(request.method.value, request.url.encodedPath, bytes?.decodeToString() ?: "") }
            val (status, text) = synchronized(this@Scripted) { if (next < script.size) script[next++] else 200 to """{"status":"ok"}""" }
            respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
        }
    }

    private object UnusedTextRules : WireTextRules {
        override fun sanitized(raw: String): String = error("ReversiRpcTest 는 글자 규칙을 쓰지 않는다")
        override fun hasVisibleContent(text: String): Boolean = error("ReversiRpcTest 는 글자 규칙을 쓰지 않는다")
        override fun statusMessageSanitized(raw: String): String = error("ReversiRpcTest 는 글자 규칙을 쓰지 않는다")
    }

    private fun service(engine: MockEngine): SupabaseWorkService {
        val client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }
        return SupabaseWorkService("https://golden.invalid", "k", client, { SwiftDate(1_793_659_950.0) }, UnusedTextRules) { "ABCDEF12-0000-4000-8000-000000000000" }
    }

    private val match = "c3000000-0000-4000-8000-000000000003"
    private val peer = "b2000000-0000-4000-8000-000000000002"

    /** RPC 하나를 부르는 길(응답 status 를 돌려준다). */
    private val callers: Map<ReversiWire.RPC, suspend (SupabaseWorkService) -> ReversiRPCStatus> = mapOf(
        ReversiWire.RPC.lobby to { s -> s.reversiLobby("token").status },
        ReversiWire.RPC.challenge to { s -> s.reversiChallenge("token", peer, 5).status },
        ReversiWire.RPC.cancel to { s -> s.reversiCancel("token", match).status },
        ReversiWire.RPC.respond to { s -> s.reversiRespond("token", match, accept = true).status },
        ReversiWire.RPC.state to { s -> s.reversiState("token", match, sinceSeq = 4).status },
        ReversiWire.RPC.move to { s -> s.reversiMove("token", match, expectedSeq = 3, idx = 19).status },
        ReversiWire.RPC.resign to { s -> s.reversiResign("token", match).status },
        ReversiWire.RPC.ranking to { s -> s.reversiRanking("token").status },
        ReversiWire.RPC.watch to { s -> s.reversiWatch("token", match, sinceSeq = 2).status },
        ReversiWire.RPC.watchLive to { s -> s.reversiWatchLive("token", match).status },
    )

    /** 본문 기대(키 → 값 글자). p_protocol 은 언제나 1. */
    private val expectedBodies: Map<ReversiWire.RPC, Map<String, String>> = mapOf(
        ReversiWire.RPC.lobby to mapOf("p_protocol" to "1"),
        ReversiWire.RPC.challenge to mapOf("p_protocol" to "1", "p_opponent" to peer, "p_stake" to "5"),
        ReversiWire.RPC.cancel to mapOf("p_protocol" to "1", "p_match_id" to match),
        ReversiWire.RPC.respond to mapOf("p_protocol" to "1", "p_match_id" to match, "p_accept" to "true"),
        ReversiWire.RPC.state to mapOf("p_protocol" to "1", "p_match_id" to match, "p_since_seq" to "4"),
        ReversiWire.RPC.move to mapOf("p_protocol" to "1", "p_match_id" to match, "p_expected_seq" to "3", "p_idx" to "19"),
        ReversiWire.RPC.resign to mapOf("p_protocol" to "1", "p_match_id" to match),
        ReversiWire.RPC.ranking to mapOf("p_protocol" to "1"),
        ReversiWire.RPC.watch to mapOf("p_protocol" to "1", "p_match_id" to match, "p_since_seq" to "2"),
        ReversiWire.RPC.watchLive to mapOf("p_protocol" to "1", "p_match_id" to match, "p_since_seq" to "0"),
    )

    private fun bodyMap(body: String): Map<String, String> =
        (SwiftJson.parse(body) as JsonObject).mapValues { (_, v) -> (v as JsonPrimitive).content }

    // 없으면: 경로·본문 키가 서버 함수와 한 글자만 달라도(PGRST202) 스토어 스텁 시험은 전부 초록이다. 빈 `{}` 본문도 여기서만 잡힌다.
    @Test
    fun everyCallPostsTheRightPathAndBody() = runBlocking {
        assertEquals(ReversiWire.RPC.entries.toSet(), callers.keys)
        for (rpc in ReversiWire.RPC.entries) {
            val script = Scripted(emptyList())
            assertEquals(ReversiRPCStatus.ok, callers.getValue(rpc)(service(script.engine)), rpc.rawValue)
            assertEquals(1, script.calls.size, rpc.rawValue)
            val (method, path, body) = script.calls.single()
            assertEquals("POST", method, rpc.rawValue)
            assertEquals("/rest/v1/rpc/${rpc.rawValue}", path)
            assertEquals(expectedBodies.getValue(rpc), bodyMap(body), "${rpc.rawValue} 본문")
        }
    }

    // 없으면: 쓰기 RPC 가 교착 한 번에 실패를 띄우거나(재시도 없음), 읽기 RPC 가 교착마다 다시 보내 요청을 태우거나, 두 번째 교착에도 계속 보내는 결함이 지나간다.
    @Test
    fun deadlockRetriesOnceForWritesAndStateOnly() = runBlocking {
        val deadlock = 500 to """{"code":"40P01","message":"deadlock detected","details":null,"hint":null}"""
        for (rpc in ReversiWire.RPC.entries) {
            val once = Scripted(listOf(deadlock))
            val result = runCatching { callers.getValue(rpc)(service(once.engine)) }
            if (rpc.retriesDeadlockOnce) {
                assertEquals(ReversiRPCStatus.ok, result.getOrNull(), "${rpc.rawValue}: 교착 한 번은 넘겨야 한다")
                assertEquals(2, once.calls.size, "${rpc.rawValue}: 정확히 한 번 더")
                assertEquals(once.calls[0], once.calls[1], "${rpc.rawValue}: 재시도는 같은 요청이다")
            } else {
                assertTrue(result.isFailure, "${rpc.rawValue}: 읽기 전용은 교착을 그대로 던진다")
                assertEquals(1, once.calls.size, "${rpc.rawValue}: 다시 보내지 않는다")
            }
            val twice = Scripted(listOf(deadlock, deadlock, deadlock))
            assertTrue(runCatching { callers.getValue(rpc)(service(twice.engine)) }.isFailure, "${rpc.rawValue}: 두 번째 교착이면 던진다")
            assertEquals(if (rpc.retriesDeadlockOnce) 2 else 1, twice.calls.size, "${rpc.rawValue}: 무한 재시도 금지")
        }
    }
}
