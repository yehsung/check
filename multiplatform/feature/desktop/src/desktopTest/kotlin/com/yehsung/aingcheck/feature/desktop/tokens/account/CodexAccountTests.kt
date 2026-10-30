// W2-h3 계정 — 골든(token-usage/upload/account) · 가짜 app-server 프로브(맥·Windows 둘 다 돈다) · 후보 거름 · 확정 규칙 · 스토어.
package com.yehsung.aingcheck.feature.desktop.tokens.account

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexDiagnosticsStamp
import com.yehsung.aingcheck.feature.desktop.tokens.upload.TokenUploadCoordinator
import com.yehsung.aingcheck.feature.desktop.tokens.upload.epoch
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** 가짜 `codex app-server` — `java -cp <시험 클래스패스> …FakeCodexAppServer <mode> [pidFile] app-server`. 실제 codex·로그인 0. */
object FakeCodexAppServer {
    @JvmStatic
    fun main(args: Array<String>) {
        val mode = args.firstOrNull() ?: "ok"
        when (mode) {
            "ok", "auth" -> {
                val lines = generateSequence { readlnOrNull() }.toList()   // EOF 까지 — 러너가 표준 입력을 닫아야 끝난다
                println("""{"method":"remoteControl/status/changed","params":{}}""")
                println("""{"id":1,"result":{"userAgent":"fake"}}""")
                if (mode == "auth") {
                    println("""{"id":2,"error":{"code":-32000,"message":"Not authenticated: run codex login"}}""")
                } else {
                    val third = if (lines.size == 3 && lines[2].contains("account/usage/read") && lines[0].contains("\"initialize\"")) 7 else 0
                    println("""{"id":2,"result":{"summary":{"lifetimeTokens":${lines.size}},"dailyUsageBuckets":[{"startDate":"2026-10-29","tokens":$third}]}}""")
                }
                System.out.flush()
                Thread.sleep(60_000)                                  // 응답 뒤에도 살아 있다 — 러너가 죽여야 한다
            }
            "hang" -> {
                val java = ProcessHandle.current().info().command().orElse("java")
                val child = ProcessBuilder(java, "-cp", System.getProperty("java.class.path"), FakeCodexAppServer::class.java.name, "sleep")
                    .redirectOutput(ProcessBuilder.Redirect.DISCARD).start()
                Files.writeString(Path.of(args[1]), child.pid().toString())
                Thread.sleep(120_000)
            }
            "sleep" -> Thread.sleep(120_000)
            "exit" -> return
        }
    }
}

class CodexAccountTests {
    private val fetchedAt = epoch(1_793_322_123)

    private fun longMap(e: JsonElement?) = (e as? JsonObject)?.mapValues { it.value.jsonPrimitive.long } ?: emptyMap()
    private fun opt(e: JsonElement?) = (e as? JsonPrimitive)?.longOrNull
    private fun acct(e: JsonElement?) = (e as? JsonObject)?.let { CodexAccountUsage(epoch(it["fetchedAtEpoch"]!!.jsonPrimitive.long), opt(it["lifetimeTokens"]), longMap(it["buckets"])) }

    @Test
    fun accountGoldenMatchesSwift() {
        val golden = Golden.load("token-usage/upload/account")
        val kinds = HashSet<String>()
        for (c in golden.cases) {
            val id = c["id"]!!.jsonPrimitive.content
            when (c["kind"]!!.jsonPrimitive.content.also { kinds += it }) {
                "parse" -> {
                    val lines = (c["lines"] as JsonArray).map { it.jsonPrimitive.content }
                    val r = CodexAccountProbeProtocol.parse(lines, fetchedAt = epoch(c["fetchedAtEpoch"]!!.jsonPrimitive.long))
                    assertEquals(c["confirms"]!!.jsonPrimitive.content.toBoolean(), CodexAccountProbeProtocol.confirmsToolchain(r), id)
                    when (r) {
                        is CodexProbeResult.Success -> {
                            assertEquals(1L, opt(c["status"]), id)
                            assertEquals(opt(c["lifetimeTokens"]), r.usage.lifetimeTokens, id)
                            assertEquals(longMap(c["buckets"]), r.usage.buckets, id)
                        }
                        is CodexProbeResult.Failure -> {
                            assertEquals(opt(c["status"])?.toInt(), r.status.raw, id)
                            assertEquals(c["reason"]!!.jsonPrimitive.content, r.reason, id)
                        }
                    }
                }
                "requestLines" -> assertEquals((c["lines"] as JsonArray).map { it.jsonPrimitive.content },
                    CodexAccountProbeProtocol.requestLines(c["appVersion"]!!.jsonPrimitive.content), id)
                "accountKey" -> assertEquals((c["key"] as? JsonPrimitive)?.takeIf { it.isString }?.content,
                    TokenUploadCoordinator.accountUploadKey(acct(c["account"]), c["month"]!!.jsonPrimitive.content,
                        opt(c["accountStatus"])?.let { CodexAccountProbeStatus.ofRaw(it.toInt()) }), id)
                "stamp" -> assertEquals(c["stamp"]!!.jsonPrimitive.content, CodexDiagnosticsStamp.stamp(1, epoch(c["nowEpoch"]!!.jsonPrimitive.long)), id)
                "month" -> {
                    val a = acct(c["account"])!!
                    val month = c["month"]!!.jsonPrimitive.content
                    assertEquals(c["monthTotal"]!!.jsonPrimitive.long, a.monthTotal(month), id)
                    assertEquals((c["latestBucketDate"] as? JsonPrimitive)?.takeIf { it.isString }?.content, a.latestBucketDate(month), id)
                }
                "pruned" -> assertEquals(longMap(c["result"]), acct(c["account"])!!.pruned().buckets, id)
                else -> error("모르는 kind")
            }
        }
        assertEquals(setOf("parse", "requestLines", "accountKey", "stamp", "month", "pruned"), kinds)
        assertTrue(c0(golden.cases).isNotEmpty())
    }

    private fun c0(cases: List<JsonObject>) = cases.filter { it["status"] != null && it["status"] != JsonNull }

    // MARK: 가짜 app-server

    private fun fake(mode: String, vararg extra: String): CodexToolchain {
        val java = ProcessHandle.current().info().command().orElse(Path.of(System.getProperty("java.home"), "bin", "java").toString())
        return CodexToolchain(listOf(java, "-cp", System.getProperty("java.class.path"), FakeCodexAppServer::class.java.name, mode) + extra)
    }

    private fun assertDead(pid: Long?) {
        assertNotNull(pid)
        val handle = ProcessHandle.of(pid)
        if (handle.isPresent) {
            try { handle.get().onExit().get(5, java.util.concurrent.TimeUnit.SECONDS) } catch (_: Exception) { }
        }
        assertFalse(ProcessHandle.of(pid).map { it.isAlive }.orElse(false), "pid $pid 가 살아 있다")
    }

    @Test
    fun probeWritesThreeLinesClosesStdinParsesIdTwoAndKillsTheServer() {
        val outcome = CodexAppServerSession.run(fake("ok"), "1.0.1", fetchedAt, deadlineMillis = 20_000)
        assertEquals(CodexSessionKind.RESPONDED, outcome.kind)
        val usage = (outcome.result as CodexProbeResult.Success).usage
        assertEquals(3L, usage.lifetimeTokens, "표준 입력 3줄")
        assertEquals(mapOf("2026-10-29" to 7L), usage.buckets, "initialize · account/usage/read 순서")
        assertDead(outcome.pid)
    }

    @Test
    fun probeAuthErrorIsNotLoggedInAndConfirmsToolchain() {
        val outcome = CodexAppServerSession.run(fake("auth"), "1", fetchedAt, deadlineMillis = 20_000)
        assertEquals(CodexAccountProbeStatus.NOT_LOGGED_IN, (outcome.result as CodexProbeResult.Failure).status)
        assertTrue(CodexAccountProbeProtocol.confirmsToolchain(outcome.result))
        assertDead(outcome.pid)
    }

    @Test
    fun probeTimeoutKillsTheWholeProcessTree() {
        val pidFile = Files.createTempFile("h3-fake-child", ".pid")
        try {
            val outcome = CodexAppServerSession.run(fake("hang", pidFile.toString()), "1", fetchedAt, deadlineMillis = 4_000)
            assertEquals(CodexSessionKind.TIMEOUT, outcome.kind)
            assertEquals(CodexAccountProbeStatus.TIMEOUT, (outcome.result as CodexProbeResult.Failure).status)
            assertDead(outcome.pid)
            val child = Files.readString(pidFile).trim().toLong()
            assertDead(child)
        } finally {
            Files.deleteIfExists(pidFile)
        }
    }

    @Test
    fun probeExitWithoutResponseIsExitedFailed() {
        val outcome = CodexAppServerSession.run(fake("exit"), "1", fetchedAt, deadlineMillis = 20_000)
        assertEquals(CodexSessionKind.EXITED, outcome.kind)
        assertEquals(CodexAccountProbeStatus.FAILED, (outcome.result as CodexProbeResult.Failure).status)
    }

    @Test
    fun launchFailureIsReportedNotThrown() {
        val outcome = CodexAppServerSession.run(CodexToolchain(listOf("/nonexistent/h3/codex.exe")), "1", fetchedAt)
        assertEquals(CodexSessionKind.LAUNCH_FAILED, outcome.kind)
    }

    @Test
    fun onlyNativeExeCandidates_cmdAndBatAreFiltered() {
        val dir = Files.createTempDirectory("h3-candidates")
        try {
            val bin = Files.createDirectories(dir.resolve("bin"))
            val npm = Files.createDirectories(dir.resolve("npm"))
            for (n in listOf("codex.cmd", "codex.bat", "codex", "codex.ps1")) Files.writeString(npm.resolve(n), "@echo off")
            Files.writeString(bin.resolve("codex.exe"), "MZ")
            val other = Files.createDirectories(dir.resolve("other"))
            Files.writeString(other.resolve("Codex.EXE"), "MZ")   // 대소문자 무시(파일 시스템이 대소문자를 가리든 말든 같은 답)
            val found = CodexToolchainCandidates.nativeCandidates(listOf(npm, bin, dir.resolve("missing")),
                extra = listOf(npm.resolve("codex.cmd"), npm.resolve("codex.bat"), other.resolve("Codex.EXE"), bin.resolve("codex.exe")))
            assertEquals(listOf(bin.resolve("codex.exe"), other.resolve("Codex.EXE")), found)
            assertTrue(found.none { it.toString().lowercase().endsWith(".cmd") || it.toString().lowercase().endsWith(".bat") })
        } finally {
            dir.toFile().deleteRecursively()
        }
    }

    // MARK: 확정 규칙(Swift fetch) — 가짜 러너, 프로세스 0

    private fun tc(name: String) = CodexToolchain(listOf(name))

    @Test
    fun fetchTriesAtMostFourCandidatesAndCachesFailureForThirtyMinutes() {
        val calls = ArrayList<String>()
        val probe = CodexAccountProbe({ (1..6).map { tc("c$it.exe") } }) { t, _ ->
            calls += t.executable; CodexProbeOutcome(CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "x"), CodexSessionKind.EXITED)
        }
        val t0 = epoch(1_793_322_123)
        probe.fetch(t0)
        assertEquals(4, calls.size)
        probe.fetch(t0.addingTimeInterval(1799.0))
        assertEquals(4, calls.size, "30분 안엔 다시 띄우지 않는다")
        probe.fetch(t0.addingTimeInterval(1800.0))
        assertEquals(8, calls.size)
    }

    @Test
    fun fetchStopsOnTimeoutAndReusesConfirmedToolchain() {
        val calls = ArrayList<String>()
        val probe = CodexAccountProbe({ listOf(tc("a.exe"), tc("b.exe")) }) { t, now ->
            calls += t.executable
            if (t.executable == "a.exe") CodexProbeOutcome(CodexProbeResult.Failure(CodexAccountProbeStatus.TIMEOUT, "t"), CodexSessionKind.TIMEOUT)
            else CodexProbeOutcome(CodexProbeResult.Success(CodexAccountUsage(now, 1, emptyMap())), CodexSessionKind.RESPONDED)
        }
        assertEquals(CodexAccountProbeStatus.TIMEOUT, (probe.fetch(fetchedAt) as CodexProbeResult.Failure).status)
        assertEquals(listOf("a.exe"), calls)
        val none = CodexAccountProbe({ emptyList() }) { _, _ -> error("후보가 없으면 띄우지 않는다") }
        assertEquals(CodexAccountProbeStatus.CODEX_NOT_INSTALLED, (none.fetch(fetchedAt) as CodexProbeResult.Failure).status)
        val ok = CodexAccountProbe({ listOf(tc("b.exe")) }) { t, now ->
            calls += "ok:" + t.executable; CodexProbeOutcome(CodexProbeResult.Success(CodexAccountUsage(now, 1, emptyMap())), CodexSessionKind.RESPONDED)
        }
        ok.fetch(fetchedAt); ok.fetch(fetchedAt)
        assertEquals(tc("b.exe"), ok.confirmedToolchain)
    }

    // MARK: 스토어

    @Test
    fun storeWithoutAuthJsonIsNotLoggedInWithZeroProcesses_andHonorsThirtyMinuteFloor() = runTest {
        val home = Files.createTempDirectory("h3-codex-home")
        try {
            var runs = 0
            val kv = InMemoryDesktopKeyValueStore()
            val store = CodexAccountUsageStore(kv, { home }) { now -> runs += 1; CodexProbeResult.Success(CodexAccountUsage(now, 9, mapOf("2026-10-29" to 4L))) }
            store.refreshIfDue(fetchedAt)
            assertEquals(CodexAccountProbeStatus.NOT_LOGGED_IN, store.lastStatus)
            assertEquals(0, runs, "auth.json 이 없는데(keyring 모드 포함) 프로세스를 띄웠다")
            Files.writeString(home.resolve("auth.json"), "{}")
            store.refreshIfDue(fetchedAt.addingTimeInterval(10.0))
            assertEquals(0, runs, "30분 하한")
            store.refreshIfDue(fetchedAt.addingTimeInterval(1800.0))
            assertEquals(1, runs)
            assertEquals(CodexAccountProbeStatus.OK, store.lastStatus)
            store.refreshIfDue(fetchedAt.addingTimeInterval(1830.0), force = true)
            assertEquals(1, runs, "강제도 60초 하한")
            store.refreshIfDue(fetchedAt.addingTimeInterval(1861.0), force = true)
            assertEquals(2, runs)
            val restored = CodexAccountUsageStore(kv, { home }) { error("복원만") }
            assertEquals(mapOf("2026-10-29" to 4L), restored.snapshot?.buckets)
        } finally {
            home.toFile().deleteRecursively()
        }
    }

    /**
     * W-13 #5: 동의 전이면 auth.json 이 있어도 codex.exe 실행 0 · 주기도 쓰지 않는다(맥 WorkTimerStoreSync.swift:790 aiToolDataAllowed).
     * 켜면 같은 시각에 바로 돈다(양성 짝), 끄면 하한이 지나도 다시 0(음성 대조).
     */
    @Test
    fun consentGatesTheCodexProcess_beforeGrantZeroRuns_grantRuns_revokeZeroAgain() = runTest {
        val home = Files.createTempDirectory("h3-codex-consent")
        try {
            Files.writeString(home.resolve("auth.json"), "{}")
            var runs = 0
            var consent = false
            val store = CodexAccountUsageStore(InMemoryDesktopKeyValueStore(), { home }, isPermitted = { consent }) { now ->
                runs += 1
                CodexProbeResult.Success(CodexAccountUsage(now, 9, mapOf("2026-10-29" to 4L)))
            }
            store.refreshIfDue(fetchedAt, force = true)
            store.refreshIfDue(fetchedAt.addingTimeInterval(3600.0))
            assertEquals(0, runs, "동의 전: 실행 0")
            assertEquals(null, store.lastProbeAt, "동의 전: 주기를 쓰지 않는다")
            assertEquals(null, store.lastStatus, "동의 전: '미로그인'으로도 적지 않는다(auth.json 확인조차 0)")
            consent = true
            store.refreshIfDue(fetchedAt.addingTimeInterval(3600.0))
            assertEquals(1, runs, "동의 뒤: 같은 시각에 바로 돈다")
            consent = false
            store.refreshIfDue(fetchedAt.addingTimeInterval(3600.0 * 3), force = true)
            assertEquals(1, runs, "철회 뒤: 하한이 지나도 실행 0")
        } finally {
            home.toFile().deleteRecursively()
        }
    }

    @Suppress("unused")
    private fun unusedSwiftDate(): SwiftDate = fetchedAt
}
