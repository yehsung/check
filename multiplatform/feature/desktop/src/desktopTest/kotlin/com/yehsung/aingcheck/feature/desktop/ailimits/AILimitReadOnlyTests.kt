// W2-h2 완료 기준(지시서 §5): Claude 자격 증명 읽기 전용 · Codex auth.json 부재 = 연결 안 됨 · 안티그래비티 0.
// 픽스처는 synthetic-home/limits/{valid,expired,keyring} 의 합성 파일을 임시 홈으로 복사해 쓴다(실제 홈 0).
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

private const val NOW = 1_793_390_000.0   // 합성 '지금' — valid 픽스처의 만료(1793404800) 전, expired 픽스처(1793300000) 뒤

class ClaudeCredentialsReadOnlyTest {
    private val homes = mutableListOf<java.nio.file.Path>()
    private fun home(name: String) = LimitsFixtures.home(name).also { homes.add(it) }

    @AfterTest
    fun cleanup() = homes.forEach(LimitsFixtures::delete)

    /** ① 파일 읽기 전용 속성 + 전후 내용·mtime·폴더 목록 동일 · 유효면 GET 1회(베타 헤더) · 갱신 경로 요청 0. */
    @Test
    fun validCredentialsAreReadOnlyAndCallUsageOnce() = runTest {
        val home = home("valid")
        Files.delete(home.resolve(".codex/auth.json"))   // Claude 만 본다
        val credentials = home.resolve(".claude/.credentials.json")
        assertTrue(credentials.toFile().setWritable(false), "읽기 전용 속성을 걸 수 있어야 한다")
        val before = LimitsFixtures.state(home)
        val http = RecordingHttp(RecordingHttp.usage)
        val outcome = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), http.fetcher, "9.9.9")
            .run(SwiftDate(NOW), setOf(AILimitProvider.claude, AILimitProvider.codex))
        assertEquals(before, LimitsFixtures.state(home), "자격 증명·폴더가 한 글자도 바뀌면 안 된다")
        assertFalse(Files.isWritable(credentials), "읽기 전용 속성이 그대로여야 한다")
        val ok = assertIs<AILimitOutcome.Ok<*>>(outcome.results[AILimitProvider.claude])
        assertEquals(27.0, (ok.value as com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot).windows.first().usedPercent)
        assertEquals(1, http.requests.size, "유효하면 GET 한 번")
        val r = http.requests.single()
        assertEquals(HttpMethod.Get, r.method)
        assertEquals(AILimitClaudeReader.usageURL, r.url.toString())
        assertEquals(AILimitClaudeReader.betaHeader, r.headers["anthropic-beta"])
        assertEquals("Bearer synthetic-claude-access", r.headers["Authorization"])
        assertEquals("check/9.9.9 (ai-limits)", r.headers["User-Agent"])
        assertNoRefreshRequests(http)
        assertEquals(AILimitReadFailure.notInstalled, (outcome.results[AILimitProvider.codex] as AILimitOutcome.Err).error.failure)
    }

    /** ② 만료면 호출 0 · 갱신 0(★ 갱신 책임을 지지 않는다). */
    @Test
    fun expiredCredentialsMakeZeroCalls() = runTest {
        val home = home("expired")
        val before = LimitsFixtures.state(home)
        val http = RecordingHttp(RecordingHttp.usage)
        val outcome = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), http.fetcher, "1")
            .run(SwiftDate(NOW), setOf(AILimitProvider.claude, AILimitProvider.codex))
        assertEquals(0, http.requests.size, "만료면 네트워크 0")
        assertEquals(AILimitReadFailure.expired, (outcome.results[AILimitProvider.claude] as AILimitOutcome.Err).error.failure)
        assertEquals(AILimitReadFailure.expired, (outcome.results[AILimitProvider.codex] as AILimitOutcome.Err).error.failure)
        assertEquals(before, LimitsFixtures.state(home))
    }

    /**
     * ③ 429 를 받으면 retry-after 가 끝날 때까지 침묵(5분 5회 상한) — 300초 하한·600초 주기가 **가리지 못하게** retry-after 를 900초로 둔다:
     * 하한·주기가 찬 +300(강제)·+600(평소)에도 호출 0, 재시작한 스토어(+305, 강제)도 0(금지창 영속 ★18), +900 에 한 번.
     */
    @Test
    fun rateLimitSilencesForRetryAfterEvenAcrossRestart() = runTest {
        val home = home("valid")
        Files.delete(home.resolve(".codex/auth.json"))
        val http = RecordingHttp { respond("""{"error":"rate"}""", HttpStatusCode.TooManyRequests, headersOf("Retry-After", "900")) }
        val runner = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), http.fetcher, "1")
        val defaults = InMemoryDesktopKeyValueStore()
        val clock = FakeClock(NOW)
        val store = AILimitStore(defaults, clock.read, { "PC" }, runner)
        store.refreshIfDue(SwiftDate(NOW))
        assertEquals(1, http.requests.size)
        assertEquals(AILimitReadFailure.rateLimited, store.failures[AILimitProvider.claude])
        assertEquals("잠시 뒤 다시", store.noticeText(AILimitProvider.claude))
        for (dt in listOf(1.0, 299.0, 300.0, 600.0, 899.0)) {
            store.refreshIfDue(SwiftDate(NOW + dt), force = true)
            store.refreshIfDue(SwiftDate(NOW + dt))
        }
        clock.now = NOW + 305
        AILimitStore(defaults, clock.read, { "PC" }, runner).refreshIfDue(SwiftDate(NOW + 305), force = true)
        assertEquals(1, http.requests.size, "429 금지창 안에서는 하한·주기가 차도, 재시작한 스토어도 노크하지 않는다")
        store.refreshIfDue(SwiftDate(NOW + 900), force = true)
        assertEquals(2, http.requests.size, "금지창이 끝나면 다시 한 번")
        assertNoRefreshRequests(http)
    }
}

class CodexAuthReadOnlyTest {
    private val homes = mutableListOf<java.nio.file.Path>()
    @AfterTest
    fun cleanup() = homes.forEach(LimitsFixtures::delete)

    /** auth.json 없음(keyring 모드) = 연결 안 됨 · 호출 0 · 섹션 숨김(W-3 #11 — 부재로만 판정, config.toml 은 읽지 않는다). */
    @Test
    fun missingAuthJsonMeansNotLinkedAndZeroCalls() = runTest {
        val home = LimitsFixtures.home("keyring").also { homes.add(it) }
        val before = LimitsFixtures.state(home)
        val http = RecordingHttp(RecordingHttp.usage)
        val runner = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), http.fetcher, "1")
        val store = AILimitStore(InMemoryDesktopKeyValueStore(), { SwiftDate(NOW) }, { null }, runner)
        store.refreshIfDue(SwiftDate(NOW))
        assertEquals(0, http.requests.size)
        assertEquals(AILimitReadFailure.notInstalled, store.failures[AILimitProvider.codex])
        assertFalse(store.isAvailable, "연결 안 된 PC 에는 섹션이 없다")
        assertTrue(store.configurableProviders.isEmpty())
        assertEquals(before, LimitsFixtures.state(home))
    }

    /** 있으면 읽기만: GET 1회(ChatGPT-Account-Id) · 파일 전후 동일. */
    @Test
    fun presentAuthJsonIsReadOnly() = runTest {
        val home = LimitsFixtures.home("valid").also { homes.add(it) }
        Files.delete(home.resolve(".claude/.credentials.json"))
        val before = LimitsFixtures.state(home)
        val http = RecordingHttp(RecordingHttp.usage)
        val outcome = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), http.fetcher, "1").run(SwiftDate(NOW), setOf(AILimitProvider.codex))
        assertIs<AILimitOutcome.Ok<*>>(outcome.results[AILimitProvider.codex])
        assertEquals(1, http.requests.size)
        assertEquals(AILimitCodexReader.usageURL, http.requests.single().url.toString())
        assertEquals("acct-synthetic", http.requests.single().headers["ChatGPT-Account-Id"])
        assertEquals(before, LimitsFixtures.state(home))
        assertNoRefreshRequests(http)
    }
}

class AntigravityZeroTest {
    /** Windows 제공자 집합에 없음 · 러너가 받는 집합에도 없음 · 디스크에 남은 안티그래비티 값·실패는 복원하지 않는다. */
    @Test
    fun antigravityIsNeverRequestedOrListed() = runTest {
        assertEquals(setOf(AILimitProvider.claude, AILimitProvider.codex), AILimitStore.windowsProviders)
        val defaults = InMemoryDesktopKeyValueStore(mapOf(
            AILimitStore.failuresKey to """{"antigravity":"expired","claude":"network"}""",
            AILimitStore.snapshotKey to """{"schemaVersion":1,"providers":[{"provider":"antigravity","planLabel":null,"accountFingerprint":null,"windows":[{"window":"five_hour","usedPercent":10.0,"resetsAt":null,"observedAt":1.7933E9,"source":"local"}]}]}""",
        ))
        val asked = mutableListOf<Set<AILimitProvider>>()
        val store = AILimitStore(defaults, { SwiftDate(NOW) }, { null }, AILimitRunner { _, p -> asked += p; AILimitReadOutcome() })
        assertEquals(listOf(AILimitProvider.claude), store.configurableProviders)
        assertTrue(store.bundle!!.providers.none { it.provider == AILimitProvider.antigravity })
        store.refreshIfDue(SwiftDate(NOW))
        assertEquals(listOf(setOf(AILimitProvider.claude, AILimitProvider.codex)), asked)
    }

    /** 실제 Windows 러너에 안티그래비티만 물어도 결과 0 · 요청 0(프로세스·`.gemini` 접근 0). */
    @Test
    fun liveRunnerIgnoresAntigravity() = runTest {
        val home = LimitsFixtures.home("valid")
        try {
            val before = LimitsFixtures.state(home)
            val http = RecordingHttp(RecordingHttp.usage)
            val outcome = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), http.fetcher, "1").run(SwiftDate(NOW), setOf(AILimitProvider.antigravity))
            assertTrue(outcome.results.isEmpty())
            assertEquals(0, http.requests.size)
            assertEquals(before, LimitsFixtures.state(home))
        } finally {
            LimitsFixtures.delete(home)
        }
    }

    /** 소스 계약(주석 걷기): ailimits 본문에 프로세스 실행·agy·.gemini·홈 직접 읽기 0건. */
    @Test
    fun sourcesHaveNoProcessOrHomeReads() {
        val sources = CommentStripper.ailimitsMainSources()
        assertTrue(sources.size >= 6, "ailimits 본문 파일을 찾아야 한다: ${sources.keys}")
        // 금지 낱말은 조각으로 짓는다(이 시험 파일이 다른 갈래의 홈 격리 소스 계약에 걸리지 않게).
        val forbidden = listOf("Process" + "Builder", "Runtime." + "getRuntime", "\"" + "agy", "." + "gemini",
            "user" + ".home", "get" + "env", "USER" + "PROFILE", "LOCAL" + "APPDATA")
        val hits = sources.flatMap { (path, text) -> forbidden.filter { it in text }.map { "$path: $it" } }
        assertEquals(emptyList(), hits)
    }
}

/** 토큰 갱신 경로(Anthropic·OpenAI OAuth 토큰 엔드포인트) 요청 0 — 요청은 사용량 URL 둘뿐. */
internal fun assertNoRefreshRequests(http: RecordingHttp) {
    val allowed = setOf(AILimitClaudeReader.usageURL, AILimitCodexReader.usageURL)
    val others = http.requests.map { it.url.toString() }.filter { it !in allowed }
    assertEquals(emptyList(), others, "사용량 URL 밖 요청(갱신 경로 포함)이 있다")
    assertTrue(http.requests.all { it.method == HttpMethod.Get })
}
