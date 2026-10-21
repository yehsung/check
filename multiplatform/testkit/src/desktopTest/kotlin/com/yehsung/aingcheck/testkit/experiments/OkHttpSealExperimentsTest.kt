package com.yehsung.aingcheck.testkit.experiments

import com.yehsung.aingcheck.testkit.tripwire.NetworkTripwire
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
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
import java.net.URI
import java.net.UnknownHostException
import java.net.http.HttpClient as JdkHttpClient
import java.net.http.HttpRequest as JdkHttpRequest
import java.net.http.HttpResponse as JdkHttpResponse
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * 봉인 실험(W0-a ⑥). localhost(mockwebserver3)만 쓴다 — 바깥으로 나가는 시험이 아니다.
 *
 * C-X6: OkHttp 는 기본값(retryOnConnectionFailure=true)에서 **재사용한 연결이 끊기면 POST 를 몰래 다시 보낸다**.
 *       서버가 요청을 읽고 응답 없이 끊으면 같은 POST 가 두 번 도착한다(찌르기·메시지 이중 전송 위험).
 *       앱의 엔진 팩토리는 retryOnConnectionFailure(false) 여야 한다 — 그때 재전송 0.
 * C-X8: 트립와이어(②층)가 OkHttp·Ktor(OkHttp)·JDK HttpClient 의 이름 풀이를 모두 막는다.
 */
class OkHttpSealExperimentsTest {
    private val json = "application/json".toMediaType()

    /** 1) GET 으로 연결을 풀에 넣고 2) 같은 연결로 POST → 서버는 POST 를 읽고 응답 없이 끊는다 3) 다음 응답은 정상. */
    private fun MockWebServer.enqueueStalePooledConnectionScenario() {
        enqueue(MockResponse.Builder().code(200).body("warm").build())
        enqueue(MockResponse.Builder().onResponseStart(SocketEffect.ShutdownConnection).build())
        enqueue(MockResponse.Builder().code(200).body("second-attempt").build())
    }

    private fun MockWebServer.postCount(): Int {
        var posts = 0
        repeat(requestCount) { if (takeRequest().method == "POST") posts++ }
        return posts
    }

    private fun okHttpPostAfterStaleConnection(retryOnConnectionFailure: Boolean): Pair<Int, String> {
        MockWebServer().use { server ->
            server.start()
            server.enqueueStalePooledConnectionScenario()
            val client = OkHttpClient.Builder().retryOnConnectionFailure(retryOnConnectionFailure).build()
            try {
                client.newCall(Request.Builder().url(server.url("/warm")).build()).execute().use { it.body.string() }
                val outcome = try {
                    client.newCall(
                        Request.Builder().url(server.url("/rest/v1/rpc/poke_user")).post("{}".toRequestBody(json)).build(),
                    ).execute().use { "ok:" + it.body.string() }
                } catch (e: IOException) {
                    "failed:" + e.javaClass.simpleName
                }
                return server.postCount() to outcome
            } finally {
                client.connectionPool.evictAll()
                client.dispatcher.executorService.shutdown()
            }
        }
    }

    @Test
    fun okHttpDefaultResendsPostOnBrokenPooledConnection() {
        val (posts, outcome) = okHttpPostAfterStaleConnection(retryOnConnectionFailure = true)
        println("AINGCHECK-CX6 okhttp retryOnConnectionFailure=true posts=$posts outcome=$outcome")
        // 위험의 실측(기준선): 기본값은 같은 POST 를 두 번 보낸다.
        assertEquals(2, posts, "OkHttp 기본값의 재전송 동작이 바뀌었다(outcome=$outcome)")
    }

    @Test
    fun okHttpWithRetryOffNeverResendsPost() {
        val (posts, outcome) = okHttpPostAfterStaleConnection(retryOnConnectionFailure = false)
        println("AINGCHECK-CX6 okhttp retryOnConnectionFailure=false posts=$posts outcome=$outcome")
        assertEquals(1, posts, "재전송이 일어났다(outcome=$outcome)")
        assertTrue(outcome.startsWith("failed:"), "끊긴 연결은 호출자에게 실패로 보여야 한다(outcome=$outcome)")
    }

    private fun ktorPostAfterStaleConnection(retryOff: Boolean): Pair<Int, String> {
        MockWebServer().use { server ->
            server.start()
            server.enqueueStalePooledConnectionScenario()
            val client = HttpClient(OkHttp) {
                expectSuccess = false
                if (retryOff) engine { config { retryOnConnectionFailure(false) } }
            }
            client.use {
                val outcome = runBlocking {
                    it.get(server.url("/warm").toString()).bodyAsText()
                    try {
                        "ok:" + it.post(server.url("/rest/v1/rpc/poke_user").toString()) { setBody("{}") }.bodyAsText()
                    } catch (e: IOException) {
                        "failed:" + e.javaClass.simpleName
                    }
                }
                return server.postCount() to outcome
            }
        }
    }

    @Test
    fun ktorOkHttpEngineInheritsTheResendUnlessConfigured() {
        val (defaultPosts, defaultOutcome) = ktorPostAfterStaleConnection(retryOff = false)
        val (fixedPosts, fixedOutcome) = ktorPostAfterStaleConnection(retryOff = true)
        println("AINGCHECK-CX6 ktor-okhttp default posts=$defaultPosts outcome=$defaultOutcome · retryOff posts=$fixedPosts outcome=$fixedOutcome")
        assertEquals(2, defaultPosts, "Ktor OkHttp 엔진 기본값의 재전송 동작이 바뀌었다")
        assertEquals(1, fixedPosts, "engine { config { retryOnConnectionFailure(false) } } 인데 재전송이 일어났다")
    }

    @Test
    fun tripwireBlocksOkHttpKtorAndJdkClientNameLookups() {
        val okhttp = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
        val recorded = NetworkTripwire.expectBlocked {
            val e1 = assertFailsWith<UnknownHostException> {
                okhttp.newCall(Request.Builder().url("http://example.com/").build()).execute().close()
            }
            assertTrue(e1.message.orEmpty().contains("aingcheck tripwire"), "OkHttp: ${e1.message}")

            val e2 = assertFailsWith<UnknownHostException> {
                runBlocking { HttpClient(OkHttp).use { it.get("http://example.org/") } }
            }
            assertTrue(e2.message.orEmpty().contains("aingcheck tripwire"), "Ktor(OkHttp): ${e2.message}")

            val jdk = JdkHttpClient.newHttpClient()
            val e3 = assertFailsWith<IOException> {
                jdk.send(JdkHttpRequest.newBuilder(URI("http://example.net/")).build(), JdkHttpResponse.BodyHandlers.discarding())
            }
            println("AINGCHECK-CX8 jdk-httpclient ${e3.javaClass.simpleName}: ${e3.message} cause=${e3.cause?.message}")
        }
        okhttp.dispatcher.executorService.shutdown()
        println("AINGCHECK-CX8 recorded=$recorded")
        assertTrue("lookup example.com" in recorded, "OkHttp 경로가 트립와이어를 지나지 않았다: $recorded")
        assertTrue("lookup example.org" in recorded, "Ktor(OkHttp) 경로가 트립와이어를 지나지 않았다: $recorded")
        assertTrue("lookup example.net" in recorded, "JDK HttpClient 경로가 트립와이어를 지나지 않았다: $recorded")
    }
}
