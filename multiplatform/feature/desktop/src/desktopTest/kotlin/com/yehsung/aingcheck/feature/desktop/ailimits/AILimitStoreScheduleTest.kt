// W2-h2 완료 기준 `AILimitStoreScheduleTest`(지시서 §5): 600/300초 · 영속 키 · 백오프 60→3600 · 트레일링 · 비우기 세대 · 꺼진 제공자 호출 0 · 기기 id null 업로드 0.
// 원본 규약: Sources/CheckCore/AILimitStore.swift(★ 18·168·189·194·260·520·525·568·697·769) · Sources/check/WorkTimerStoreAILimits.swift(★ 14·52·66·69·104·121).
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val T0 = 1_793_390_000.0

private fun snap(provider: AILimitProvider, used: Double, observed: Double) = AILimitProviderSnapshot(
    provider, listOf(AILimitWindowSnapshot(AILimitWindow.fiveHour, used, null, observed, AILimitSource.local)), null, null,
)

/** 부를 때마다 받은 집합을 적고, 그 집합 안 제공자만 값으로 돌려주는 러너. */
private class CountingRunner(private val defaults: InMemoryDesktopKeyValueStore? = null) : AILimitRunner {
    val asked = mutableListOf<Set<AILimitProvider>>()
    val stampAtCall = mutableListOf<String?>()
    var used = 10.0
    override suspend fun run(now: SwiftDate, providers: Set<AILimitProvider>): AILimitReadOutcome {
        asked += providers
        stampAtCall += defaults?.getString(AILimitStore.lastAttemptKey)
        return AILimitReadOutcome(providers.associateWith { AILimitOutcome.Ok(snap(it, used, now.timeIntervalSince1970)) })
    }
}

class AILimitStoreScheduleTest {
    @Test
    fun intervalIs600AndForcedFloorIs300AndStampPersistsBeforeRunner() = runTest {
        val defaults = InMemoryDesktopKeyValueStore()
        val runner = CountingRunner(defaults)
        val store = AILimitStore(defaults, { SwiftDate(T0) }, { null }, runner)
        store.refreshIfDue(SwiftDate(T0))
        assertEquals(1, store.runnerCallCount)
        assertEquals(T0.toString(), runner.stampAtCall.single(), "★18 시도 스탬프는 러너 **전에** 디스크로 내려간다")
        assertFalse(store.isDue(SwiftDate(T0 + 599)))
        assertTrue(store.isDue(SwiftDate(T0 + 600)))
        assertFalse(store.isDue(SwiftDate(T0 + 299), force = true))
        assertTrue(store.isDue(SwiftDate(T0 + 300), force = true))
        // 재시작: 간격은 프로세스 수명보다 오래 산다(★18) · 미래 스탬프는 지금으로 접는다.
        val restarted = AILimitStore(defaults, { SwiftDate(T0 + 100) }, { null }, runner)
        assertFalse(restarted.isDue(SwiftDate(T0 + 100), force = true))
        val skewed = InMemoryDesktopKeyValueStore(mapOf(AILimitStore.lastAttemptKey to (T0 + 99_999).toString(), AILimitStore.silentUntilKey to (T0 + 99_999).toString()))
        val folded = AILimitStore(skewed, { SwiftDate(T0) }, { null }, runner)
        assertEquals(SwiftDate(T0), folded.lastAttemptAt, "미래 스탬프 → 지금")
        assertEquals(SwiftDate(T0 + AILimitStore.defaultBackoff), folded.silentUntil, "금지창은 기본 백오프보다 길게 믿지 않는다")
    }

    @Test
    fun persistedKeysKeepTheirSwiftNames() = runTest {
        val defaults = InMemoryDesktopKeyValueStore()
        val store = AILimitStore(defaults, { SwiftDate(T0) }, { null }, CountingRunner())
        store.refreshIfDue(SwiftDate(T0))
        store.setProviderEnabled(AILimitProvider.codex, false)
        val keys = defaults.snapshot().keys
        for (k in listOf("check.aiLimits.snapshot", "check.aiLimits.failures", "check.aiLimits.lastAttemptAt", "check.aiLimits.show",
            "check.aiLimits.disabledProviders", "check.aiLimits.pendingClear")) assertTrue(k in keys, "영속 키 $k (★189 이름을 바꾸면 끈 설정이 켜짐으로 돌아간다)")
        assertEquals(listOf("codex"), Json.parseToJsonElement(defaults.getString(AILimitStore.disabledProvidersKey)!!).jsonArray.map { it.jsonPrimitive.content })
        assertEquals(listOf("codex"), Json.parseToJsonElement(defaults.getString(AILimitStore.pendingClearKey)!!).jsonArray.map { it.jsonPrimitive.content })
        // 묶음이 디스크에서 그대로 돌아온다.
        val restored = AILimitStore(defaults, { SwiftDate(T0) }, { null }, CountingRunner())
        assertEquals(store.bundle, restored.bundle)
        assertEquals(setOf(AILimitProvider.codex), restored.pendingClear, "★194 비우기 대기열은 재시작을 건넌다")
        assertFalse(restored.visibility.isProviderOn(AILimitProvider.codex))
        assertEquals(1, Json.parseToJsonElement(defaults.getString(AILimitStore.snapshotKey)!!).jsonObject["schemaVersion"]!!.jsonPrimitive.content.toInt())
    }

    @Test
    fun disabledProvidersAreNeverAskedAndAllOffMeansNoTimer() = runTest {
        val defaults = InMemoryDesktopKeyValueStore()
        val runner = CountingRunner()
        val store = AILimitStore(defaults, { SwiftDate(T0) }, { null }, runner)
        store.refreshIfDue(SwiftDate(T0))
        store.setProviderEnabled(AILimitProvider.claude, false)
        store.refreshIfDue(SwiftDate(T0 + 600))
        assertEquals(listOf(setOf(AILimitProvider.claude, AILimitProvider.codex), setOf(AILimitProvider.codex)), runner.asked, "★168 꺼진 제공자는 러너 집합에 없다")
        store.setMasterEnabled(false)
        val stampBefore = defaults.getString(AILimitStore.lastAttemptKey)
        assertFalse(store.isDue(SwiftDate(T0 + 99_999)), "★520 꺼진 축은 타이머가 돌지 않는다")
        store.refreshIfDue(SwiftDate(T0 + 99_999))
        assertEquals(2, runner.asked.size)
        assertEquals(stampBefore, defaults.getString(AILimitStore.lastAttemptKey), "꺼진 축은 스탬프도 안 찍는다")
        assertEquals(setOf(AILimitProvider.claude, AILimitProvider.codex), store.pendingClear, "마스터 끄기 = 연동된 전부를 비운다")
        // ★525: 줄이 선 제공자를 전부 끄면(연동 안 된 제공자가 켜져 있어도) 돌지 않는다.
        val lone = AILimitStore(InMemoryDesktopKeyValueStore(), { SwiftDate(T0) }, { null }, AILimitRunner { _, p ->
            AILimitReadOutcome(p.associateWith { if (it == AILimitProvider.claude) AILimitOutcome.Ok(snap(it, 5.0, T0)) else fail(AILimitReadFailure.notInstalled) })
        })
        lone.refreshIfDue(SwiftDate(T0))
        lone.setProviderEnabled(AILimitProvider.claude, false)
        assertFalse(lone.isDue(SwiftDate(T0 + 9_999)))
    }

    @Test
    fun uploadBackoffDoublesFrom60To3600AndSuccessResets() {
        val store = AILimitStore(InMemoryDesktopKeyValueStore(), { SwiftDate(T0) }, { null }, CountingRunner())
        val waits = (1..8).map {
            store.noteUploadFailed(SwiftDate(T0))
            store.uploadRetryNotBeforeForTest!!.timeIntervalSince(SwiftDate(T0))
        }
        assertEquals(listOf(60.0, 120.0, 240.0, 480.0, 960.0, 1920.0, 3600.0, 3600.0), waits)
        assertFalse(store.uploadRetryAllowed(SwiftDate(T0 + 3599)))
        assertTrue(store.uploadRetryAllowed(SwiftDate(T0 + 3600)))
        store.noteUploadSucceeded()
        assertNull(store.uploadRetryNotBeforeForTest)
        assertEquals(0, store.uploadFailureStreak)
    }

    @Test
    fun clearGenerationsSurviveReToggleWhileInFlight() = runTest {
        val store = AILimitStore(InMemoryDesktopKeyValueStore(), { SwiftDate(T0) }, { null }, CountingRunner())
        store.refreshIfDue(SwiftDate(T0))
        store.setProviderEnabled(AILimitProvider.codex, false)
        val claim = store.claimPendingClear()
        assertEquals(listOf(AILimitProvider.codex), claim.providers)
        store.setProviderEnabled(AILimitProvider.codex, true)
        assertTrue(store.pendingClear.isEmpty(), "다시 켜면 대기열에서 뺀다(같은 PK 값·비우기 섞임 21000)")
        store.setProviderEnabled(AILimitProvider.codex, false)
        store.markCleared(claim)
        assertEquals(setOf(AILimitProvider.codex), store.pendingClear, "★697 보낸 뒤 다시 끈 끄기(새 세대)는 살아남는다")
        store.markCleared(store.claimPendingClear())
        assertTrue(store.pendingClear.isEmpty())
    }

    @Test
    fun failuresOnlyReplaceProvidersWithResultsAndHidingFailuresDropValues() {
        val store = AILimitStore(InMemoryDesktopKeyValueStore(), { SwiftDate(T0) }, { null }, CountingRunner())
        store.apply(AILimitReadOutcome(mapOf(AILimitProvider.claude to AILimitOutcome.Ok(snap(AILimitProvider.claude, 30.0, T0)),
            AILimitProvider.codex to fail(AILimitReadFailure.network))), SwiftDate(T0))
        store.apply(AILimitReadOutcome(mapOf(AILimitProvider.claude to fail(AILimitReadFailure.expired))), SwiftDate(T0 + 600))
        assertEquals(30.0, store.bundle!!.provider(AILimitProvider.claude)!!.windows.single().usedPercent, "만료는 값을 남긴다(하한)")
        assertEquals(AILimitReadFailure.network, store.failures[AILimitProvider.codex], "★769 결과 없는 제공자의 실패는 그대로")
        assertEquals("클로드 코드를 한 번 실행해 주세요", store.noticeText(AILimitProvider.claude))
        store.apply(AILimitReadOutcome(mapOf(AILimitProvider.claude to fail(AILimitReadFailure.notInstalled))), SwiftDate(T0 + 1200))
        assertNull(store.bundle!!.provider(AILimitProvider.claude), "숨기는 실패는 값까지 지운다")
    }

    // ------------------------------------------------------------------ 업로드(DesktopAILimitSync)

    private class Fixture(deviceId: String? = "win:5f1c0de0") {
        val defaults = InMemoryDesktopKeyValueStore()
        val clock = FakeClock(T0)
        val runner = CountingRunner()
        val gate = CompletableDeferred<Unit>()
        var holdFirst = false
        val http: RecordingHttp = RecordingHttp {
            if (holdFirst && it == firstRequest()) gate.await()
            respond("", HttpStatusCode.Created)
        }
        fun firstRequest(): io.ktor.client.request.HttpRequestData? = http.requests.firstOrNull()
        val store = AILimitStore(defaults, clock.read, { "  DESKTOP-SYNTH \n" }, runner)
        val sync = DesktopAILimitSync(store, fakeService(http), { AILimitSession("tok", "user-1") }, { deviceId })
    }

    @Test
    fun nullDeviceIdMeansZeroUploads() = runTest {
        val f = Fixture(deviceId = null)
        f.sync.refreshAILimitsIfNeeded(SwiftDate(T0))
        f.sync.setAILimitProviderEnabled(AILimitProvider.codex, false)
        assertEquals(1, f.runner.asked.size, "읽기는 한다")
        assertEquals(0, f.http.requests.size, "★14 기기 id 가 없으면 서버 쓰기 0(새로 짓지 않는다)")
    }

    @Test
    fun inFlightUploadCollapsesToOneTrailingAtThatTimesNow() = runTest {
        val f = Fixture()
        f.store.refreshIfDue(SwiftDate(T0))
        f.holdFirst = true
        val first = async { f.sync.uploadAILimitsIfNeeded(SwiftDate(T0)) }
        while (f.http.requests.isEmpty()) yield()
        // 비행 중: 끄기 둘 + 틱 하나 → 새로 쏘지 않고 트레일링 한 번.
        f.clock.now = T0 + 42
        f.store.setProviderEnabled(AILimitProvider.codex, false)
        f.sync.uploadAILimitsIfNeeded(SwiftDate(T0 + 1))
        f.sync.setAILimitProviderEnabled(AILimitProvider.claude, false)
        assertEquals(1, f.http.requests.size, "★52 비행 중이면 새로 쏘지 않는다")
        f.gate.complete(Unit)
        first.await()
        assertEquals(2, f.http.requests.size, "트레일링은 한 번")
        assertEquals(1, f.store.uploadPeakConcurrency)
        val trailing = Json.parseToJsonElement(f.http.requests[1].bodyBytes().decodeToString()).jsonArray.map { it.jsonObject }
        assertEquals(setOf("claude", "codex"), trailing.map { it["provider"]!!.jsonPrimitive.content }.toSet())
        assertTrue(trailing.all { it["five_hour_percent"].toString() == "null" }, "트레일링은 마지막 상태(둘 다 끔) = 비우는 행")
        assertTrue(trailing.all { it["observed_at"]!!.jsonPrimitive.content == "2026-10-30T19:54:02Z" }, "★69 트레일링은 그 시점의 now(T0+42)")
        assertTrue(trailing.all { it["device_label"]!!.jsonPrimitive.content == "DESKTOP-SYNTH" })
        assertTrue(f.store.pendingClear.isEmpty())
        assertFalse(f.store.uploadInFlight)
    }

    @Test
    fun failedUploadBacksOffValueUploadsToo() = runTest {
        val f = Fixture()
        val failing = RecordingHttp { respond("""{"code":"PGRST205"}""", HttpStatusCode.NotFound) }
        val sync = DesktopAILimitSync(f.store, fakeService(failing), { AILimitSession("tok", "u") }, { "win:1" })
        f.store.refreshIfDue(SwiftDate(T0))
        sync.uploadAILimitsIfNeeded(SwiftDate(T0))
        f.runner.used = 20.0
        f.store.refreshIfDue(SwiftDate(T0 + 600))
        sync.uploadAILimitsIfNeeded(SwiftDate(T0 + 30))
        assertEquals(1, failing.requests.size, "★121 값이 바뀌어도 백오프 창(60초) 안에서는 보내지 않는다")
        sync.uploadAILimitsIfNeeded(SwiftDate(T0 + 60))
        assertEquals(2, failing.requests.size)
        assertEquals(2, f.store.uploadFailureStreak)
        assertNull(sync.lastUploadedAILimits, "장부는 성공에만")
    }
}
