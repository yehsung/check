package com.yehsung.aingcheck.testkit

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.testkit.clock.FakeClock
import com.yehsung.aingcheck.testkit.clock.fakeClock
import com.yehsung.aingcheck.testkit.clock.fakeMonotonicClock
import com.yehsung.aingcheck.testkit.mock.MockRouter
import com.yehsung.aingcheck.testkit.mock.PhoneForbiddenCalls
import com.yehsung.aingcheck.testkit.mock.StubResponse
import com.yehsung.aingcheck.testkit.mock.UnroutedRequestException
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.testkit.vault.TokenVaultContract
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/** InMemory 금고가 계약을 통과한다(계약 자체가 도는지의 기준선). */
class InMemoryTokenVaultContractTest : TokenVaultContract() {
    override fun createSubject(): Subject = object : Subject {
        private val memory = InMemoryTokenVault()
        override val vault: TokenVault = memory
        override fun breakWrites() { memory.failsWrites = true }
    }
}

/** 계약이 결함을 잡는가(심은 결함 → 빨강). 기준선(InMemory)과 **다른 입력**이다. */
class TokenVaultContractCatchesDefectsTest {
    /** 결함: write 실패 때 낡은 값을 남긴다(Swift 주석이 경고한 사고 그대로). */
    private class StaleOnFailureVault : TokenVault {
        val map = HashMap<String, String>()
        var broken = false
        override fun read(key: String) = map[key]
        override fun write(value: String, key: String) { if (!broken) map[key] = value }
        override fun delete(key: String) { map.remove(key) }
    }

    private fun contractFor(vault: StaleOnFailureVault) = object : TokenVaultContract() {
        override fun createSubject(): Subject = object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() { vault.broken = true }
        }
    }

    @Test
    fun staleOnFailureVaultFailsTheContract() {
        assertFailsWith<AssertionError> { contractFor(StaleOnFailureVault()).failedWriteMakesReadNullInsteadOfStale() }
    }
}

class FakeClockTest {
    @Test
    fun clockFollowsVirtualTimeFromKstBase() = runTest {
        val clock = fakeClock()
        val mono = fakeMonotonicClock()
        assertEquals(FakeClock.BASE, clock.now())
        assertEquals("2026-09-17T05:05:00Z", FakeClock.BASE.toString())
        delay(90.seconds)
        assertEquals(FakeClock.BASE + 90.seconds, clock.now())
        assertEquals(90.seconds.inWholeNanoseconds, mono.elapsedNanos())
        testScheduler.advanceTimeBy(2.minutes)
        assertEquals(FakeClock.BASE + 210.seconds, clock.now())
    }
}

class MockRouterTest {
    @Test
    fun routesRecordsAndFailsUnknownRequests() = runTest {
        val router = MockRouter()
            .rpc("message_unread_summary", StubResponse.Json("""{"unread":1}"""), StubResponse.Json("""{"unread":0}"""))
            .on(HttpMethod.Get, "/rest/v1/profiles", StubResponse.Json("[]"))
        val client = HttpClient(router.engine) { expectSuccess = false }

        assertEquals("""{"unread":1}""", client.post("https://aingcheck.invalid/rest/v1/rpc/message_unread_summary") { setBody("{}") }.bodyAsText())
        assertEquals("""{"unread":0}""", client.post("https://aingcheck.invalid/rest/v1/rpc/message_unread_summary") { setBody("{}") }.bodyAsText())
        // 마지막 응답은 되풀이된다
        assertEquals("""{"unread":0}""", client.post("https://aingcheck.invalid/rest/v1/rpc/message_unread_summary") { setBody("{}") }.bodyAsText())
        assertEquals("[]", client.get("https://aingcheck.invalid/rest/v1/profiles?select=id&id=eq.1").bodyAsText())
        router.assertAllRouted()

        assertFailsWith<UnroutedRequestException> { client.post("https://aingcheck.invalid/rest/v1/rpc/take_pokes") { setBody("{}") } }
        assertEquals(1, router.unrouted.size)
        assertFailsWith<IllegalStateException> { router.assertAllRouted() }

        val get = router.requests.single { it.method == "GET" }
        assertEquals("id", get.queryValue("select"))
        assertEquals("eq.1", get.queryValue("id"))
        assertEquals("message_unread_summary", router.requests.first().rpcName)
        assertEquals("{}", router.requests.first().bodyText)
    }

    @Test
    fun transportFailureAndMissingFunctionShapes() = runTest {
        val router = MockRouter()
            .rpc("a", StubResponse.TransportFailure())
            .rpc("b", StubResponse.missingFunction("b"))
        val client = HttpClient(router.engine) { expectSuccess = false }
        assertFailsWith<IOException> { client.post("https://aingcheck.invalid/rest/v1/rpc/a") }
        val missing = client.post("https://aingcheck.invalid/rest/v1/rpc/b")
        assertEquals(HttpStatusCode.NotFound, missing.status)
        assertEquals(true, missing.bodyAsText().contains("PGRST202"))
    }

    @Test
    fun phoneForbiddenCallsAreDetected() = runTest {
        val router = MockRouter()
            .rpc("take_pokes", StubResponse.Json("[]"))
            .rpc("join_team", StubResponse.Json("{}"))
            .on(HttpMethod.Post, "/rest/v1/work_sessions", StubResponse.Json("[]"))
            .on(HttpMethod.Get, "/rest/v1/work_sessions", StubResponse.Json("[]"))
            .on(HttpMethod.Patch, "/rest/v1/profiles", StubResponse.Json("[]"))
        val client = HttpClient(router.engine) { expectSuccess = false }
        client.post("https://aingcheck.invalid/rest/v1/rpc/take_pokes")
        client.post("https://aingcheck.invalid/rest/v1/rpc/join_team")
        client.post("https://aingcheck.invalid/rest/v1/work_sessions") { setBody("{}") }
        client.get("https://aingcheck.invalid/rest/v1/work_sessions")
        client.patch("https://aingcheck.invalid/rest/v1/profiles") { setBody("""{"p_app_build":3,"nickname":"a"}""") }
        client.patch("https://aingcheck.invalid/rest/v1/profiles") { setBody("""{"app_build":3}""") }
        assertEquals(
            listOf("POST rpc/take_pokes", "POST work_sessions", "PATCH profiles.app_build"),
            PhoneForbiddenCalls.violations(router.requests),
        )
    }
}
