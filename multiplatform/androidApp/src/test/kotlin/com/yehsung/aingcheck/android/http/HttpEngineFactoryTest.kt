package com.yehsung.aingcheck.android.http

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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException

/**
 * G §8-12 · C-X6: Android 앱의 단일 HTTP 팩토리가 만든 클라이언트는 재전송하지 않는다(호스트 JVM + Robolectric —
 * OkHttp 의 Android 변형이 android.jar 를 부르므로 Robolectric 위에서 돈다). 기기(ART) 몫은 DeviceScaffoldTest.
 * 기준선은 다른 입력이다: 같은 시나리오에서 OkHttp 기본값은 POST 를 2번 보낸다.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class HttpEngineFactoryTest {
    private val json = "application/json".toMediaType()

    private fun MockWebServer.stalePooledConnection() {
        start()
        enqueue(MockResponse.Builder().code(200).body("warm").build())
        enqueue(MockResponse.Builder().onResponseStart(SocketEffect.ShutdownConnection).build())
        enqueue(MockResponse.Builder().code(200).body("second-attempt").build())
    }

    private fun MockWebServer.postCount(): Int {
        var n = 0
        repeat(requestCount) { if (takeRequest().method == "POST") n++ }
        return n
    }

    private fun ktorPosts(client: HttpClient): Pair<Int, String> = MockWebServer().use { server ->
        server.stalePooledConnection()
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

    private fun posts(client: OkHttpClient): Pair<Int, String> = MockWebServer().use { server ->
        server.stalePooledConnection()
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

    @Test
    fun factoryClientsCarryRetryOff() {
        assertFalse("팩토리 OkHttp 가 재전송을 켠 채다", HttpEngineFactory.okHttpClient().retryOnConnectionFailure)
        val ktor = HttpEngineFactory.ktorClient()
        try {
            val pre = (ktor.engine.config as OkHttpConfig).preconfigured
            assertNotNull("Ktor 엔진이 팩토리 바탕(preconfigured)을 쓰지 않는다", pre)
            assertFalse("Ktor 엔진 바탕이 재전송을 켠 채다", pre!!.retryOnConnectionFailure)
        } finally {
            ktor.close()
        }
    }

    @Test
    fun factoryOkHttpNeverResendsPostOnBrokenPooledConnection() {
        val baseline = OkHttpClient.Builder().build()
        val (basePosts, baseOutcome) = posts(baseline)
        val (factoryPosts, outcome) = posts(HttpEngineFactory.okHttpClient())
        println("AINGCHECK-HTTP-FACTORY android-host okhttp baseline posts=$basePosts($baseOutcome) factory posts=$factoryPosts($outcome)")
        assertEquals("기준선(기본값)이 재전송하지 않았다 — 시나리오가 재전송을 못 본다($baseOutcome)", 2, basePosts)
        assertEquals("팩토리 클라이언트가 POST 를 다시 보냈다($outcome)", 1, factoryPosts)
        assertTrue("끊긴 연결은 호출자에게 실패로 보여야 한다($outcome)", outcome.startsWith("failed:"))
    }

    /** Ktor 쪽은 속성으로 못 잰다(엔진 OkHttp 는 요청 때 지어지고, Ktor 기본 config 가 바탕의 retry(false) 를 덮는다 — 실측). */
    @Test
    fun factoryKtorClientNeverResendsPostOnBrokenPooledConnection() {
        val baseline = HttpClient(OkHttp) { expectSuccess = false }
        val (basePosts, baseOutcome) = try { ktorPosts(baseline) } finally { baseline.close() }
        val factory = HttpEngineFactory.ktorClient { expectSuccess = false }
        val (factoryPosts, outcome) = try { ktorPosts(factory) } finally { factory.close() }
        println("AINGCHECK-HTTP-FACTORY android-host ktor baseline posts=$basePosts($baseOutcome) factory posts=$factoryPosts($outcome)")
        assertEquals("기준선(Ktor OkHttp 기본값)이 재전송하지 않았다($baseOutcome)", 2, basePosts)
        assertEquals("팩토리 Ktor 클라이언트가 POST 를 다시 보냈다($outcome)", 1, factoryPosts)
    }
}
