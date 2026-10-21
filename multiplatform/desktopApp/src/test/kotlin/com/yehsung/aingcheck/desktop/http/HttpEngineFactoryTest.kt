package com.yehsung.aingcheck.desktop.http

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.engine.okhttp.OkHttpConfig
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.SocketEffect
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * G §8-12 · C-X6: 데스크톱 앱의 단일 HTTP 팩토리가 만든 클라이언트는 **재전송하지 않는다**.
 * 속성(`retryOnConnectionFailure == false`)만 보지 않고, 끊긴 재사용 연결을 localhost 에서 재현해 POST 도착 수를 센다.
 * 기준선은 다른 입력이다: 같은 시나리오에서 OkHttp·Ktor 기본값은 POST 를 2번 보낸다(시나리오가 재전송을 볼 수 있다는 증거).
 */
class HttpEngineFactoryTest {
    private val json = "application/json".toMediaType()

    /** 1) GET 으로 연결을 풀에 넣고 2) 같은 연결로 POST → 서버는 POST 를 읽고 응답 없이 끊는다 3) 다음 응답은 정상. */
    private fun MockWebServer.enqueueStalePooledConnection() {
        enqueue(MockResponse.Builder().code(200).body("warm").build())
        enqueue(MockResponse.Builder().onResponseStart(SocketEffect.ShutdownConnection).build())
        enqueue(MockResponse.Builder().code(200).body("second-attempt").build())
    }

    private fun MockWebServer.postCount(): Int {
        var posts = 0
        repeat(requestCount) { if (takeRequest().method == "POST") posts++ }
        return posts
    }

    private fun okHttpPosts(client: OkHttpClient): Pair<Int, String> = MockWebServer().use { server ->
        server.start()
        server.enqueueStalePooledConnection()
        client.newCall(Request.Builder().url(server.url("/warm")).build()).execute().use { it.body.string() }
        val outcome = try {
            client.newCall(Request.Builder().url(server.url("/rest/v1/rpc/poke_user")).post("{}".toRequestBody(json)).build())
                .execute().use { "ok:" + it.body.string() }
        } catch (e: IOException) {
            "failed:" + e.javaClass.simpleName
        }
        client.connectionPool.evictAll()
        server.postCount() to outcome
    }

    private fun ktorPosts(client: HttpClient): Pair<Int, String> = MockWebServer().use { server ->
        server.start()
        server.enqueueStalePooledConnection()
        val outcome = runBlocking {
            client.get(server.url("/warm").toString()).bodyAsText()
            try {
                "ok:" + client.post(server.url("/rest/v1/rpc/poke_user").toString()) { setBody("{}") }.bodyAsText()
            } catch (e: IOException) {
                "failed:" + e.javaClass.simpleName
            }
        }
        server.postCount() to outcome
    }

    @Test
    fun factoryClientsCarryRetryOff() {
        assertFalse(HttpEngineFactory.okHttpClient().retryOnConnectionFailure, "팩토리 OkHttp 가 재전송을 켠 채다")
        HttpEngineFactory.ktorClient().use { ktor ->
            val config = ktor.engine.config as OkHttpConfig
            val pre = assertNotNull(config.preconfigured, "Ktor 엔진이 팩토리 바탕(preconfigured)을 쓰지 않는다")
            assertFalse(pre.retryOnConnectionFailure, "Ktor 엔진 바탕이 재전송을 켠 채다")
        }
    }

    @Test
    fun factoryOkHttpNeverResendsPostOnBrokenPooledConnection() {
        val baseline = OkHttpClient.Builder().build()
        val (basePosts, baseOutcome) = okHttpPosts(baseline)
        baseline.dispatcher.executorService.shutdown()
        val (posts, outcome) = okHttpPosts(HttpEngineFactory.okHttpClient())
        println("AINGCHECK-HTTP-FACTORY desktop okhttp baseline posts=$basePosts($baseOutcome) factory posts=$posts($outcome)")
        assertEquals(2, basePosts, "기준선(기본값)이 재전송하지 않았다 — 시나리오가 재전송을 못 본다($baseOutcome)")
        assertEquals(1, posts, "팩토리 클라이언트가 POST 를 다시 보냈다($outcome)")
        assertTrue(outcome.startsWith("failed:"), "끊긴 연결은 호출자에게 실패로 보여야 한다($outcome)")
    }

    private fun waitUntil(ms: Long, cond: () -> Boolean): Boolean {
        val end = System.nanoTime() + ms * 1_000_000
        while (System.nanoTime() < end) {
            if (cond()) return true
            Thread.sleep(20)
        }
        return cond()
    }

    @Test
    fun closingAFactoryKtorClientLeavesTheSharedOkHttpAlive() = MockWebServer().use { server ->
        server.start()
        repeat(2) { server.enqueue(MockResponse.Builder().code(200).body("ok").build()) }
        // 기준선: 바탕 OkHttp 를 넘겨 지은 Ktor 클라이언트를 닫으면 그 바탕의 디스패처가 내려간다(공유하면 안 되는 이유의 실측).
        val pre = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
        HttpClient(OkHttp) { engine { preconfigured = pre } }.use { runBlocking { it.get(server.url("/a").toString()).bodyAsText() } }
        assertTrue(waitUntil(5_000) { pre.dispatcher.executorService.isShutdown }, "기준선: Ktor 가 닫힐 때 바탕 디스패처를 내리지 않았다 — 측정이 비었다")
        // 팩토리: Ktor 클라이언트를 닫아도 공용 원시 OkHttp 는 산다.
        HttpEngineFactory.ktorClient().use { runBlocking { it.get(server.url("/b").toString()).bodyAsText() } }
        assertFalse(waitUntil(2_000) { HttpEngineFactory.okHttpClient().dispatcher.executorService.isShutdown }, "Ktor 클라이언트를 닫자 공용 OkHttp 디스패처가 내려갔다")
    }

    @Test
    fun factoryKtorClientNeverResendsPostOnBrokenPooledConnection() {
        val (basePosts, baseOutcome) = HttpClient(OkHttp) { expectSuccess = false }.use { ktorPosts(it) }
        val (posts, outcome) = HttpEngineFactory.ktorClient { expectSuccess = false }.use { ktorPosts(it) }
        println("AINGCHECK-HTTP-FACTORY desktop ktor baseline posts=$basePosts($baseOutcome) factory posts=$posts($outcome)")
        assertEquals(2, basePosts, "기준선(Ktor OkHttp 기본값)이 재전송하지 않았다($baseOutcome)")
        assertEquals(1, posts, "팩토리 Ktor 클라이언트가 POST 를 다시 보냈다($outcome)")
    }
}
