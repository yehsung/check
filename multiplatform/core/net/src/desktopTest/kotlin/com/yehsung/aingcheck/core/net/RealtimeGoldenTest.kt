// 원본: 없음 — 실시간 G4 10,000걸음 · 프레임 골든 대조(G §2-3 W1-d ④) + Ktor/OkHttp WebSocket 의 localhost Phoenix 흉내 왕복(⑤, A-X10)
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.KtorRealtimeTransport
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeFrame
import com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection
import com.yehsung.aingcheck.core.net.realtime.RealtimeLink
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.dump.GoldenScrub
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class RealtimeGoldenTest {
    private val dumper = GoldenDump(leaf = { v -> if (v is SwiftDate) GoldenDump.date(v.timeIntervalSince1970) else null })

    private object Walk {
        const val START = 1_790_000_000.0
        fun jwt(exp: Long): String =
            "eyJhbGciOiJIUzI1NiJ9." + Base64.getUrlEncoder().withoutPadding().encodeToString("{\"exp\":$exp}".encodeToByteArray()) + ".c2ln"
        val tokOK = jwt((START + 2_592_000).toLong())
        val tokSoon = jwt((START + 100).toLong())
        const val tokBad = "not-a-jwt"

        /** Swift `RealtimeWalk.event` 와 같은 갈래 · 같은 rng 차례. */
        fun event(rng: SplitMix64): RealtimeEvent = when ((rng.next() % 34uL).toInt()) {
            0 -> RealtimeEvent.SignedIn(tokOK)
            1 -> RealtimeEvent.SignedIn(tokSoon)
            2 -> RealtimeEvent.SignedIn(tokBad)
            3 -> RealtimeEvent.SignedOut
            4 -> RealtimeEvent.WillSleep
            5 -> RealtimeEvent.DidWake
            6 -> RealtimeEvent.Transport(RealtimeTransportEvent.Opened)
            7, 8 -> RealtimeEvent.Transport(RealtimeTransportEvent.Joined)
            9 -> RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.ExpiredToken))
            10 -> RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.Unauthorized))
            11 -> RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.Unknown("boom")))
            12 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("gomoku"))
            13 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("chess"))
            14 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("tetris"))
            15 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("message_read"))
            16 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("poke"))
            17 -> RealtimeEvent.Transport(RealtimeTransportEvent.HeartbeatAck)
            18 -> RealtimeEvent.Transport(RealtimeTransportEvent.HeartbeatTimedOut)
            19 -> RealtimeEvent.Transport(RealtimeTransportEvent.Closed(if (rng.next() % 2uL == 0uL) null else 1006))
            20, 21 -> RealtimeEvent.BackoffElapsed
            in 22..27 -> RealtimeEvent.Tick
            28 -> RealtimeEvent.TokenRefreshed(tokOK)
            29 -> RealtimeEvent.TokenRefreshed(tokSoon)
            30 -> RealtimeEvent.TokenRefreshFailed(rng.next() % 2uL == 0uL)
            31 -> RealtimeEvent.UserRequestedRetry
            else -> RealtimeEvent.Tick
        }
    }

    private fun bits(d: Double): JsonElement = JsonPrimitive(Golden.bitsText(d))

    private fun record(link: RealtimeLink, event: RealtimeEvent, effects: List<RealtimeEffect>, now: SwiftDate): JsonObject = JsonObject(
        mapOf(
            "now" to bits(now.timeIntervalSince1970),
            "e" to dumper.dump(event),
            "fx" to dumper.dump(effects),
            "s" to dumper.dump(link.state),
            "tok" to (link.accessToken?.let { JsonPrimitive(it) } ?: JsonNull),
            "fs" to (link.failingSince?.let { bits(it.timeIntervalSince1970) } ?: JsonNull),
            "fr" to JsonPrimitive(link.forcedRefreshUsedThisAttempt),
            "hb" to (link.lastHeartbeatSentAt?.let { bits(it.timeIntervalSince1970) } ?: JsonNull),
        ),
    )

    private fun fnv(text: String, h0: ULong): ULong {
        var h = h0
        for (b in text.encodeToByteArray()) {
            h = h xor (b.toULong() and 0xFFuL)
            h *= 0x00000100000001B3uL
        }
        return h
    }

    @Test
    fun linkWalkMatchesSwiftCheckpoints() {
        val golden = Golden.load("realtime/link-walk")
        var totalSteps = 0
        for (c in golden.cases) {
            val rng = SplitMix64(c.hex64("seed"))
            val steps = c.int("steps")
            val link = RealtimeLink(transportAvailable = (c["transportAvailable"] as JsonPrimitive).content == "true")
            var now = SwiftDate(Walk.START)
            var h = 0xCBF29CE484222325uL
            val checkpoints = mutableListOf<String>()
            val head = c.array("head")
            for (step in 1..steps) {
                var dt = (rng.next() % 20_001uL).toDouble() / 1000
                if (rng.next() % 50uL == 0uL) dt += 60
                now = now.addingTimeInterval(dt)
                val event = Walk.event(rng)
                val effects = link.apply(event, now) { ceiling -> ceiling * (0.5 + 0.5 * rng.unit()) }
                val rec = record(link, event, effects, now)
                val text = GoldenCanonical.text(rec)
                if (step <= head.size) {
                    val shown = GoldenCanonical.text(GoldenScrub.json(rec))
                    if (shown != GoldenCanonical.text(head[step - 1])) {
                        fail(golden.failure(c.string("id"), "걸음 $step 이 다르다\n  Swift : ${GoldenCanonical.text(head[step - 1])}\n  Kotlin: $shown"))
                    }
                }
                h = fnv(text, h)
                if (step % 500 == 0) checkpoints += Golden.hex64Text(h)
            }
            totalSteps += steps
            val want = c.array("checkpoints").map { it.jsonPrimitive.content }
            val firstBad = want.indices.firstOrNull { it >= checkpoints.size || want[it] != checkpoints[it] }
            if (firstBad != null) {
                fail(golden.failure(c.string("id"), "체크포인트 #$firstBad(걸음 ${(firstBad) * 500 + 1}~${(firstBad + 1) * 500}) 가 다르다: Swift ${want[firstBad]} · Kotlin ${checkpoints.getOrNull(firstBad)}"))
            }
            assertEquals(c.string("final"), Golden.hex64Text(h), golden.failure(c.string("id"), "끝 해시"))
        }
        println("AINGCHECK-G4 walks=${golden.cases.size} steps=$totalSteps")
        assertTrue(totalSteps >= 10_000, "G4 걸음이 1만 미만($totalSteps)")
    }

    @Test
    fun framesMatchSwift() {
        val golden = Golden.load("realtime/frames")
        val problems = mutableListOf<String>()
        fun parse(s: String): JsonElement = Json.parseToJsonElement(s)
        for (c in golden.cases) {
            val id = c.string("id")
            val (want, got) = when {
                id == "join-private" -> c["frame"]!! to parse(RealtimeFrame.join("poke:u1", "tok", true, "1"))
                id == "join-public" -> c["frame"]!! to parse(RealtimeFrame.join("poke:u1", "tok", false, "7"))
                id == "heartbeat" -> c["frame"]!! to parse(RealtimeFrame.heartbeat("12"))
                id == "access-token" -> c["frame"]!! to parse(RealtimeFrame.accessToken("poke:u1", "new", "3", "1"))
                id.startsWith("socket-url-") ->
                    c["socketURL"]!! to (RealtimeFrame.socketURL(c.string("projectURL"), "k&y")?.let { JsonPrimitive(it) } ?: JsonNull)
                id.startsWith("decode-") -> {
                    val joinRef = (c["joinRef"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
                    c["event"]!! to (RealtimeFrame.decode(c.string("text"), "poke:u1", joinRef)?.let { dumper.dump(it) } ?: JsonNull)
                }
                id.startsWith("classify-") -> c["rejection"]!! to dumper.dump(RealtimeFrame.classifyJoinError(c.string("reason")))
                else -> error("모르는 case $id")
            }
            if (GoldenCanonical.text(want) != GoldenCanonical.text(got)) {
                problems += golden.failure(id, "Swift ${GoldenCanonical.text(want).trim()} · Kotlin ${GoldenCanonical.text(got).trim()}")
            }
        }
        println("AINGCHECK-FRAMES cases=${golden.cases.size} problems=${problems.size}")
        if (problems.isNotEmpty()) fail(problems.joinToString("\n\n"))
    }

    /** C§4 #17: 실 전송자는 시험 프로세스에서 태어나지 못한다(CHECK_E2E=1 만 예외). */
    @Test
    fun liveTransportRefusesTestProcess() {
        val client = HttpClient(OkHttp) { KtorRealtimeTransport.clientConfig(this) }
        val scope = CoroutineScope(SupervisorJob())
        val testing = object : RunningTests { override val isRunningTests = true }
        assertNull(KtorRealtimeTransport.create(client, scope, testing, emptyMap()), "시험 프로세스에서 실 전송자가 생겼다")
        assertTrue(KtorRealtimeTransport.create(client, scope, testing, mapOf("CHECK_E2E" to "1")) != null)
        scope.cancel()
        client.close()
    }

    /**
     * Ktor(OkHttp 엔진) WebSocket ↔ localhost Phoenix 흉내(mockwebserver3) 왕복(봉인 아래 — localhost 만): 조인(private · 토큰)
     * → phx_reply ok → 방송 → 하트비트 → 답 → 토큰 밀기 → 서버가 닫음. 사건열을 링에 먹여 구독·신호·재연결까지 확인한다.
     */
    @Test
    fun ktorOkHttpWebSocketRoundTripsWithLocalPhoenix() {
        val serverFrames = CopyOnWriteArrayList<String>()
        val listener = object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                serverFrames += text
                val o = Json.parseToJsonElement(text).jsonObject
                val event = o["event"]!!.jsonPrimitive.content
                val ref = o["ref"]!!.jsonPrimitive.content
                when (event) {
                    "phx_join" -> {
                        webSocket.send("""{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"$ref"}""")
                        webSocket.send("""{"topic":"realtime:poke:u1","event":"broadcast","payload":{"event":"gomoku","payload":{}}}""")
                        webSocket.send("""{"topic":"realtime:poke:other","event":"broadcast","payload":{"event":"chess"}}""")
                    }
                    "heartbeat" -> webSocket.send("""{"topic":"phoenix","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"$ref"}""")
                    "access_token" -> webSocket.close(1000, "bye")
                }
            }
        }
        val single = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val scope = CoroutineScope(SupervisorJob() + single)
        val events = CopyOnWriteArrayList<RealtimeTransportEvent>()
        MockWebServer().use { server ->
            server.enqueue(MockResponse.Builder().webSocketUpgrade(listener).build())
            server.start()
            val client = HttpClient(OkHttp) {
                engine { config { retryOnConnectionFailure(false) } }
                KtorRealtimeTransport.clientConfig(this)
            }
            val testing = object : RunningTests { override val isRunningTests = true }
            val transport = KtorRealtimeTransport.create(client, scope, testing, mapOf("CHECK_E2E" to "1"))!!
            runBlocking {
                withContext(single) {
                    transport.onEvent = { events += it }
                    transport.connect(server.url("/").toString().trimEnd('/').replace("https://", "http://"), "anon-k", "tok-1", "poke:u1", isPrivate = true)
                }
                waitFor { events.any { it is RealtimeTransportEvent.Broadcast } }
                withContext(single) { transport.sendHeartbeat() }
                waitFor { events.contains(RealtimeTransportEvent.HeartbeatAck) }
                withContext(single) { transport.pushAccessToken("tok-2") }
                waitFor { events.any { it is RealtimeTransportEvent.Closed } }
                withContext(single) { transport.disconnect() }
            }
            val request = server.takeRequest(5, TimeUnit.SECONDS)!!
            assertEquals("/realtime/v1/websocket", request.url.encodedPath)
            assertEquals("anon-k", request.url.queryParameter("apikey"))
            assertEquals("1.0.0", request.url.queryParameter("vsn"))
            client.close()
        }
        scope.cancel()
        single.close()

        assertEquals(
            listOf(
                RealtimeTransportEvent.Opened, RealtimeTransportEvent.Joined, RealtimeTransportEvent.Broadcast("gomoku"),
                RealtimeTransportEvent.HeartbeatAck, RealtimeTransportEvent.Closed(null),
            ),
            events.toList(),
            "전송자 사건열(남의 채널 방송은 버린다)",
        )
        val join = Json.parseToJsonElement(serverFrames[0]).jsonObject
        assertEquals("realtime:poke:u1", join["topic"]!!.jsonPrimitive.content)
        assertEquals("phx_join", join["event"]!!.jsonPrimitive.content)
        assertEquals("1", join["join_ref"]!!.jsonPrimitive.content)
        val config = join["payload"]!!.jsonObject["config"]!!.jsonObject
        assertEquals("true", config["private"]!!.jsonPrimitive.content, "조인은 private=true(C§4 #16)")
        assertEquals("tok-1", join["payload"]!!.jsonObject["access_token"]!!.jsonPrimitive.content)
        assertEquals("phoenix", Json.parseToJsonElement(serverFrames[1]).jsonObject["topic"]!!.jsonPrimitive.content)
        val push = Json.parseToJsonElement(serverFrames[2]).jsonObject
        assertEquals("access_token", push["event"]!!.jsonPrimitive.content)
        assertEquals("1", push["join_ref"]!!.jsonPrimitive.content)
        assertEquals("tok-2", push["payload"]!!.jsonObject["access_token"]!!.jsonPrimitive.content)

        // 같은 사건열을 링에 먹인다: 로그인 → 연결 → 구독(catchUp) → 오목 신호 → 하트비트 답 → 닫힘 → 재연결 대기.
        val link = RealtimeLink(transportAvailable = true)
        var now = SwiftDate(1_790_000_000.0)
        val fx = mutableListOf<RealtimeEffect>()
        fx += link.apply(RealtimeEvent.SignedIn("tok-1"), now) { it }
        for (e in events) {
            now = now.addingTimeInterval(1.0)
            fx += link.apply(RealtimeEvent.Transport(e), now) { it }
        }
        assertTrue(RealtimeEffect.CatchUp in fx && RealtimeEffect.GomokuSignal in fx, "링 효과: $fx")
        assertTrue(link.state is RealtimeState.Reconnecting, "닫힘 뒤 재연결 대기여야 한다: ${link.state}")
        assertTrue(link.state != RealtimeState.Idle(IdleReason.disabled))
    }

    private suspend fun waitFor(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!condition()) {
            if (System.nanoTime() > deadline) fail("10초 안에 사건이 오지 않았다")
            kotlinx.coroutines.delay(10)
        }
    }

    @Suppress("unused")
    private val keep = JsonArray(emptyList())
}
