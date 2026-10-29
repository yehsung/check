// 원본: 없음 — Swift 에는 `app_current_notice_for` 를 부르는 함수가 없다(맥은 app_current_notice = 'mac' 만). 그래서 Swift 골든을 지어내지 않고
//   [WireRequestsGoldenTest] 의 녹음기·자리표시 관례 그대로 **Kotlin 요청 모양**을 여기서 잠근다. 반환 디코드는 [appCurrentNotice] 와 같은 AppNotice 경로다.
package com.yehsung.aingcheck.core.stores.wiregolden

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.appCurrentNotice
import com.yehsung.aingcheck.core.net.appCurrentNoticeFor
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class AppNoticeForRequestTest {
    private class Recorded(val requests: List<JsonObject>, val result: AppNotice?)

    private fun service(engine: MockEngine): Pair<SupabaseWorkService, HttpClient> {
        val client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }
        val service = SupabaseWorkService(
            projectURL = "https://golden.invalid", anonKey = ANON, client = client,
            clock = { SwiftDate(1_789_621_500.0) }, text = RulesWireTextRules, newUUIDString = { "ABCDEF12-3456-4789-8ABC-DEF012345678" },
        )
        return service to client
    }

    private fun record(script: List<Pair<Int, String>>, call: suspend (SupabaseWorkService) -> AppNotice?): Recorded {
        val recorder = GoldenRecorder(script)
        val (service, client) = service(recorder.engine)
        try {
            val result = runBlocking { call(service) }
            return Recorded(recorder.requests.toList(), result)
        } finally {
            client.close()
        }
    }

    private val notice = """{"v":1,"id":"n-1","title":" 공지 ","body":"본문","link_url":"https://example.invalid/a","link_label":""}"""

    /** 요청 한 건: POST · rpc 경로 · 쿼리 없음 · anon 헤더(apikey·Bearer anon) · Prefer 없음 · 본문 `{"p_platform": …}` 키 하나. */
    @Test
    fun requestShapeIsLocked() {
        for (platform in listOf("windows", "android", "mac")) {
            val got = record(emptyList()) { s -> s.appCurrentNoticeFor(platform) }.requests.single()
            val want = JsonObject(
                mapOf(
                    "method" to JsonPrimitive("POST"),
                    "path" to JsonPrimitive("/rest/v1/rpc/app_current_notice_for"),
                    "query" to JsonArray(emptyList()),
                    "headers" to JsonObject(
                        mapOf(
                            "accept" to JsonPrimitive("application/json"),
                            "apikey" to JsonPrimitive("<ANON>"),
                            "authorization" to JsonPrimitive("Bearer <ANON>"),
                            "content-type" to JsonPrimitive("application/json"),
                        ),
                    ),
                    "body" to JsonObject(mapOf("p_platform" to JsonPrimitive(platform))),
                ),
            )
            assertEquals(GoldenCanonical.text(want), GoldenCanonical.text(got), platform)
        }
    }

    /** 반환은 [appCurrentNotice] 와 **같은 디코드**다 — 같은 응답이면 같은 AppNotice(앞뒤 공백 자르기 · 빈 링크 이름 null 포함). */
    @Test
    fun decodesTheSameNoticeAsTheMacCall() {
        val mac = record(listOf(200 to notice)) { s -> s.appCurrentNotice() }.result
        val windows = record(listOf(200 to notice)) { s -> s.appCurrentNoticeFor("windows") }.result
        assertNotNull(windows)
        assertEquals(mac, windows)
        assertEquals("공지", windows.title)
        assertNull(windows.linkLabel)
    }

    /** null 규칙: 공지 없음(`{}`)·디코드 실패·서비스 오류(비2xx)는 null, 전송 오류만 던진다. */
    @Test
    fun nullRulesMatchTheMacCall() {
        for ((status, body) in listOf(200 to "{}", 200 to """{"id":"n-1","title":"","body":"b"}""", 200 to "[]", 500 to "", 404 to """{"code":"PGRST202"}""", 401 to "")) {
            assertNull(record(listOf(status to body)) { s -> s.appCurrentNoticeFor("windows") }.result, "$status $body")
            assertNull(record(listOf(status to body)) { s -> s.appCurrentNotice() }.result, "mac $status $body")
        }
        val failing = MockEngine { throw IOException("오프라인(합성)") }
        val (service, client) = service(failing)
        try {
            assertFailsWith<IOException> { runBlocking { service.appCurrentNoticeFor("windows") } }
        } finally {
            client.close()
        }
    }
}
