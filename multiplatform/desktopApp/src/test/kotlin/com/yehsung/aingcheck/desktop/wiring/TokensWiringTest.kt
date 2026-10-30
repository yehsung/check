// 조정자 배선 시험 — TokensWiring 을 가짜 의존(MockRouter 녹음 서비스 · 가짜 세션 · InMemoryDesktopKeyValueStore · 합성 홈 · 가짜 리밋 러너)
// 으로 만든다. 합성 홈은 임시 폴더에 한 줄짜리 Claude 기록만(실제 홈·계정·네트워크 0, 바깥 연결은 MockEngine 이 막는다).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitRunner
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexProbeResult
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.testkit.mock.MockRouter
import com.yehsung.aingcheck.testkit.mock.StubResponse
import io.ktor.client.HttpClient
import io.ktor.http.HttpMethod
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime
import kotlin.io.path.createDirectories
import kotlin.io.path.writeText
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlin.time.Clock
import kotlin.time.Instant

class TokensWiringTest {
    /** 2026-10-20T03:00:00Z(KST 12:00) — 이번 KST 달 2026-10. */
    private val nowEpoch = 1_792_465_200L
    private val tempDirs = ArrayList<Path>()

    @AfterTest
    fun cleanUp() {
        tempDirs.forEach { it.toFile().deleteRecursively() }
    }

    private object PassTextRules : WireTextRules {
        override fun sanitized(raw: String): String = raw
        override fun hasVisibleContent(text: String): Boolean = text.isNotBlank()
        override fun statusMessageSanitized(raw: String): String = raw
    }

    private class FakeSession(override val service: SupabaseWorkService) : SessionHost {
        var current: SupabaseSession? = SupabaseSession("access-token-synthetic", null, "u-synthetic")
        override val session: SupabaseSession? get() = current
        override var sessionGeneration: Int = 1
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = operation(current ?: error("세션 없음"))
    }

    /** 합성 홈: Claude 기록 한 줄(이번 달 · 입력 1000 · 출력 200). Codex auth.json 없음(계정 프로브 0). */
    private fun syntheticHome(): Path {
        val home = Files.createTempDirectory("tokens-wiring-home")
        tempDirs.add(home) // Path 는 Iterable<Path> 라 += 는 plus 로 풀린다
        val dir = home.resolve(".claude/projects/-synthetic-wiring").createDirectories()
        val file = dir.resolve("s.jsonl")
        file.writeText(
            """{"parentUuid":null,"isSidechain":false,"type":"assistant","message":{"id":"w1","type":"message","role":"assistant",""" +
                """"model":"claude-synthetic","content":[{"type":"text","text":"합성"}],"usage":{"input_tokens":1000,""" +
                """"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":200}},""" +
                """"timestamp":"2026-10-19T23:00:00.000Z","sessionId":"00000000-0000-4000-8000-0000000000ww","requestId":"rw1"}""" + "\n",
        )
        Files.setLastModifiedTime(file, FileTime.fromMillis((nowEpoch - 3600) * 1000))
        return home
    }

    private inner class Rig(
        val scope: TestScope,
        config: DesktopAppConfig,
        consentChanges: Flow<Boolean> = emptyFlow(),
        codexLoggedIn: Boolean = false,
        consent: () -> Boolean = { true },
    ) {
        val router = MockRouter()
            .on(HttpMethod.Post, "/rest/v1/ai_limits", StubResponse.Json("", status = 201))
            .on(HttpMethod.Post, "/rest/v1/token_usage_device_monthly", StubResponse.Json("", status = 201))
            .on(HttpMethod.Post, "/rest/v1/token_usage_device_daily", StubResponse.Json("", status = 201))
        val service = SupabaseWorkService(
            "https://golden.invalid", "anon-test-key", HttpClient(router.engine) { SupabaseWorkService.clientConfig(this) },
            { SwiftDate.fromEpochMillis(nowEpoch * 1000) }, PassTextRules,
        ) { "ABCDEF12-0000-4000-8000-000000000000" }
        val session = FakeSession(service)
        val kv = InMemoryDesktopKeyValueStore()
        val home = syntheticHome().also { h ->
            if (codexLoggedIn) h.resolve(".codex").createDirectories().resolve("auth.json").writeText("{}")
        }
        val work = InMemoryDesktopWorkState(DesktopWorkSnapshot(isWorking = true))
        var accountRunnerCalls = 0
        var limitRunnerCalls = 0
        val wiring = TokensWiring(
            TokensWiringDeps(
                desktopConfig = config,
                sessionStore = session,
                service = service,
                keyValueStore = kv,
                clock = object : Clock {
                    override fun now(): Instant = Instant.fromEpochMilliseconds(nowEpoch * 1000 + scope.testScheduler.currentTime)
                },
                deviceId = { "win:00000000-0000-4000-8000-00000000beef" },
                homes = DesktopAiHomes.synthetic(home),
                cacheBase = home.resolve("token-usage-cache.json"),
                appBuild = 0,
                tokenUsageCollect = { true },
                aiToolDataAllowed = consent,
                aiToolDataConsentChanges = consentChanges,
                workState = work,
                aiLimitRunner = AILimitRunner { now, providers ->
                    limitRunnerCalls += 1
                    AILimitReadOutcome(providers.associateWith {
                        AILimitOutcome.Ok(
                            AILimitProviderSnapshot(
                                it,
                                listOf(AILimitWindowSnapshot(AILimitWindow.fiveHour, 42.0, null, now.timeIntervalSince1970, AILimitSource.local)),
                                null,
                                null,
                            ),
                        )
                    })
                },
                deviceLabel = { "SYNTHETIC-PC" },
                codexAccountRunner = { accountRunnerCalls += 1; CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "합성") },
                computeDiagnostics = { _, _ -> null },
                ioDispatcher = StandardTestDispatcher(scope.testScheduler),
            ),
        )

        fun paths(): List<String> = router.requests.map { "${it.method} ${it.path}" }
        fun tokenWrites(): List<String> = paths().filter { it.contains("/rest/v1/token_usage") }
        fun limitWrites(): List<String> = paths().filter { it.contains("/rest/v1/ai_limits") }
    }

    private fun TestScope.step(ms: Long) { advanceTimeBy(ms); runCurrent() }

    /** MockEngine 은 자기 스레드에서 응답한다 — 가상 시간만 밀면 응답 뒤 이어지는 일이 아직 안 돌았을 수 있다. 실제 시간으로 조건을 기다린다. */
    private fun TestScope.settle(what: String, cond: () -> Boolean) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (true) {
            runCurrent()
            if (cond()) return
            if (System.nanoTime() > deadline) fail("기다림 초과: $what")
            Thread.sleep(5)
        }
    }

    @Test
    fun `start→stop 한 바퀴 — 첫 틱이 리밋을 읽어 올리고 근무 중 배경 스캔을 돌린다, stop 뒤 틱 0`() = runTest {
        val rig = Rig(this, DesktopAppConfig(tokenUpload = true))
        rig.wiring.start(backgroundScope)
        step(100)
        settle("첫 틱") { rig.wiring.ticks >= 1 }
        assertEquals(1, rig.wiring.ticks)
        assertEquals(1, rig.limitRunnerCalls)
        assertTrue("POST /rest/v1/ai_limits" in rig.paths(), "리밋 업로드: ${rig.paths()}")
        assertTrue((rig.wiring.scan.currentMonthUsage.value?.total ?: 0) > 0, "합성 홈 스캔 → 이번 달 합 > 0")
        assertEquals(0, rig.accountRunnerCalls, "auth.json 없음 → 계정 프로브 0")

        step(TokensWiring.TICK_MILLIS)
        settle("둘째 틱") { rig.wiring.ticks >= 2 }
        assertEquals(2, rig.wiring.ticks)
        rig.wiring.stop()
        step(TokensWiring.TICK_MILLIS * 3)
        assertEquals(2, rig.wiring.ticks, "stop 뒤 틱 0")
    }

    @Test
    fun `깃발 꺼짐 — tokenUpload=false 면 token_usage 쓰기 0, ai_limits 는 연다(W-3 #11) · 켜면 같은 입력이 기기 월 표에 쓴다`() = runTest {
        val off = Rig(this, DesktopAppConfig(tokenUpload = false))
        off.wiring.start(backgroundScope)
        step(100)
        settle("첫 틱") { off.wiring.ticks >= 1 }
        step(TokensWiring.TICK_MILLIS)
        settle("둘째 틱") { off.wiring.ticks >= 2 }
        off.wiring.onFlyoutOpened()
        step(100)
        // 플라이아웃 몫(스캔 → 내 행 읽기 RPC)이 끝날 때까지 — 끝난 뒤에 '쓰기 0' 을 본다.
        settle("플라이아웃 스캔·내 행 읽기") { off.wiring.scan.scanCount >= 2 && off.router.requests.any { it.path.contains("/rpc/") } }
        assertTrue((off.wiring.scan.currentMonthUsage.value?.total ?: 0) > 0, "스캔은 깃발과 무관(로컬 표시) — 올릴 값이 있다")
        assertEquals(emptyList(), off.tokenWrites(), "꺼진 깃발: token_usage_* 요청 0")
        assertTrue("POST /rest/v1/ai_limits" in off.paths(), "리밋은 깃발 없이 연다: ${off.paths()}")
        off.wiring.stop()

        val on = Rig(this, DesktopAppConfig(tokenUpload = true))
        on.wiring.start(backgroundScope)
        step(100)
        settle("켠 깃발 첫 틱") { on.wiring.ticks >= 1 }
        assertTrue("POST /rest/v1/token_usage_device_monthly" in on.tokenWrites(), "켠 깃발: ${on.paths()}")
        on.wiring.stop()
    }

    @Test
    fun `scanSource 는 h1 스캔 스토어를 그대로 비춘다 — W2-h3 TokenScanSource 이음`() = runTest {
        val rig = Rig(this, DesktopAppConfig())
        assertEquals(null, rig.wiring.scanSource.lastScanAt)
        rig.wiring.scanSource.refreshNow()
        runCurrent()
        assertNotNull(rig.wiring.scanSource.lastScanAt)
        assertEquals(rig.wiring.scan.currentMonthUsage.value, rig.wiring.scanSource.currentMonthUsage)
        assertTrue(rig.wiring.scanSource.lastScanFileCount >= 1)
    }

    @Test
    fun `근무 아님이면 배경 스캔·업로드 0 · 플라이아웃 열림은 즉시 스캔`() = runTest {
        val rig = Rig(this, DesktopAppConfig(tokenUpload = true))
        rig.work.set(DesktopWorkSnapshot(isWorking = false))
        rig.wiring.start(backgroundScope)
        step(100)
        assertEquals(0, rig.wiring.scan.scanCount, "근무 아님 → 배경 스캔 0")
        assertEquals(emptyList(), rig.tokenWrites())
        rig.wiring.onFlyoutOpened()
        step(100)
        assertEquals(1, rig.wiring.scan.scanCount, "플라이아웃 열림 → 즉시 스캔")
        rig.wiring.onFlyoutClosed()
        rig.wiring.stop()
    }

    /**
     * 동의(W-13 #5 · Store 10.5.2): 맥 aiToolDataAllowed(WorkTimerStoreMacEdition.swift:54-64)처럼 스캔 문과 업로드 문 둘 다 동의를 본다.
     * 동의 전엔 근무 중 틱·플라이아웃·지금 스캔 어느 입구로도 스캔 0 · token_usage_* 쓰기 0. 같은 장치에서 동의하면 다음 틱이 스캔하고 올린다(양성 짝).
     */
    @Test
    fun `동의 전이면 근무 중이어도 스캔·token_usage 쓰기 0 · 동의하면 같은 입력이 스캔하고 올린다(W-13 #5)`() = runTest {
        var consent = false
        val rig = Rig(this, DesktopAppConfig(tokenUpload = true)) { consent }
        rig.wiring.start(backgroundScope)
        step(100)
        settle("첫 틱") { rig.wiring.ticks >= 1 }
        rig.wiring.onFlyoutOpened()
        step(100)
        rig.wiring.scanSource.refreshNow()
        runCurrent()
        assertEquals(0, rig.wiring.scan.scanCount, "동의 전: 배경·플라이아웃·지금 스캔 0")
        assertEquals(emptyList(), rig.tokenWrites(), "동의 전: token_usage_* 요청 0")
        rig.wiring.onFlyoutClosed()

        consent = true
        step(TokensWiring.TICK_MILLIS)
        settle("동의 뒤 틱이 스캔하고 올린다") {
            rig.wiring.scan.scanCount >= 1 && "POST /rest/v1/token_usage_device_monthly" in rig.tokenWrites()
        }
        rig.wiring.stop()
    }

    /**
     * W-13 #5 끝까지: 동의 전엔 토큰 스캔·AI 리밋 자격 파일 읽기(가짜 리더)·codex.exe 실행(가짜 실행기)·업로드 0. 켜면(흐름) 다 돈다.
     * 끄면 그 자리에서 다시 0 — 리밋 마스터는 같은 문으로 꺼져 올라가 있던 행을 비우는 행 한 번만 나간다(맥 setAIToolDataConsent).
     */
    @Test
    fun `동의 끝까지 — 전엔 리밋 읽기·codex 실행·스캔·업로드 0, 켜면 돈다, 끄면 즉시 다시 0(W-13 #5)`() = runTest {
        val consent = MutableStateFlow(false)
        val rig = Rig(this, DesktopAppConfig(tokenUpload = true), consentChanges = consent, codexLoggedIn = true) { consent.value }
        rig.wiring.start(backgroundScope)
        step(100)
        settle("첫 틱") { rig.wiring.ticks >= 1 }
        rig.wiring.onFlyoutOpened()
        ticks(rig, 20)                            // 600초 — 리밋 주기·스캔 주기를 여러 번 넘긴다
        assertEquals(0, rig.limitRunnerCalls, "동의 전: 자격 파일 읽기(리밋 러너) 0")
        assertEquals(0, rig.accountRunnerCalls, "동의 전: codex.exe 실행 0(auth.json 있음)")
        assertEquals(0, rig.wiring.scan.scanCount, "동의 전: 스캔 0")
        assertEquals(emptyList(), rig.limitWrites() + rig.tokenWrites(), "동의 전: ai_limits·token_usage_* 요청 0")

        consent.value = true
        step(TokensWiring.TICK_MILLIS)
        settle("동의 뒤 리밋·프로브·스캔·업로드") {
            rig.limitRunnerCalls >= 1 && rig.accountRunnerCalls >= 1 && rig.wiring.scan.scanCount >= 1 &&
                "POST /rest/v1/ai_limits" in rig.limitWrites() && "POST /rest/v1/token_usage_device_monthly" in rig.tokenWrites()
        }
        val limitWritesAtGrant = rig.limitWrites().size

        consent.value = false
        step(100)
        settle("철회 → 비우는 행 한 번") { rig.limitWrites().size == limitWritesAtGrant + 1 }
        val reads = rig.limitRunnerCalls
        val runs = rig.accountRunnerCalls
        val scans = rig.wiring.scan.scanCount
        val writes = rig.paths().size
        ticks(rig, 70)                            // 35분 — 리밋 10분·프로브 30분·플라이아웃 스캔 2분 주기를 모두 넘긴다
        assertEquals(reads, rig.limitRunnerCalls, "철회 뒤: 자격 파일 읽기 0")
        assertEquals(runs, rig.accountRunnerCalls, "철회 뒤: codex.exe 실행 0")
        assertEquals(scans, rig.wiring.scan.scanCount, "철회 뒤: 스캔 0(플라이아웃 주기도 내렸다)")
        assertEquals(writes, rig.paths().size, "철회 뒤: 요청 0 — ${rig.paths().drop(writes)}")
        assertFalse(rig.wiring.aiLimits.visibility.masterEnabled, "철회 → 리밋 마스터 끔")
        rig.wiring.onFlyoutClosed()
        rig.wiring.stop()
    }

    /** 30초 틱을 하나씩 민다(틱이 MockEngine 응답을 기다리는 동안 가상 시간만 앞서 가지 않게). */
    private fun TestScope.ticks(rig: Rig, n: Int) {
        repeat(n) {
            val target = rig.wiring.ticks + 1
            step(TokensWiring.TICK_MILLIS)
            settle("틱 $target") { rig.wiring.ticks >= target }
        }
    }

    @Test
    fun `finishForQuit 은 더러운 스캔 캐시를 강제 저장한다(맥 willTerminate)`() = runTest {
        val rig = Rig(this, DesktopAppConfig())
        rig.wiring.scanSource.refreshNow()
        runCurrent()
        assertEquals(0, rig.wiring.scan.saveCount, "300초 저장 간격 안 — 스캔만으로는 아직 내리지 않는다")
        rig.wiring.finishForQuit()
        assertEquals(1, rig.wiring.scan.saveCount, "종료 훅이 강제 저장")
        val saved = Files.list(rig.home).use { s -> s.map { it.fileName.toString() }.toList() }.filter { it.startsWith("token-usage-cache") }
        assertTrue(saved.isNotEmpty(), "캐시 파일: $saved")
    }
}
