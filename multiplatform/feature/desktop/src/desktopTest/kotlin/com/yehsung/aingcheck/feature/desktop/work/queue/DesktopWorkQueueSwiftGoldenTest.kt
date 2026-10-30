// 골든: contract/golden/desktop-work-queue/scenarios.json ← Swift Tests/checkTests/GoldenExport/desktop-work-queue/GoldenExportDesktopWorkQueue.swift
// (맥 WorkTimerStore 의 retryPendingSync 를 스크립트 응답 위에서 실제로 돌린 녹음). 규약 번호: work.md §2 wq ⑪ 순서 보존 · ⑫ 해소기 1·2(5분 스로틀)·3a·3b·3c·3d.
// 같은 입력(줄 · 근무 중 세션 · 마지막 스캐빈저)과 같은 응답으로 DesktopWorkQueue 를 돌려 요청열 · 남은 항목 · 도장 · 실패 여부 · 실패 문구를 대조한다.
package com.yehsung.aingcheck.feature.desktop.work.queue

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.service.FakeSessionHost
import com.yehsung.aingcheck.feature.desktop.work.service.GOLDEN_NOW
import com.yehsung.aingcheck.feature.desktop.work.service.GOLDEN_USER
import com.yehsung.aingcheck.feature.desktop.work.service.GoldenRecorder
import com.yehsung.aingcheck.feature.desktop.work.service.WALL_CLOCK_KEYS
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.long
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class DesktopWorkQueueSwiftGoldenTest {
    private val golden = Golden.load("desktop-work-queue/scenarios")
    private val outcomeKeys = listOf("requests", "remaining", "confirmedServerSessionID", "failed", "syncMessage", "drainedRefresh")

    private fun str(o: JsonObject, k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun num(o: JsonObject, k: String): Long? = (o[k] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull

    private fun item(o: JsonObject): PendingWorkItem = PendingWorkItem(
        id = o.string("id"),
        operation = if (o.string("op") == "stop") PendingWorkOperation.Stop(o.long("durationSeconds")) else PendingWorkOperation.Start,
        sessionId = o.string("sessionID"),
        sessionStartedAt = num(o, "sessionStartedAtSince1970")?.let { SwiftDate(it.toDouble()) },
        endedAt = num(o, "endedAtSince1970")?.let { SwiftDate(it.toDouble()) },
        ownerUserId = str(o, "ownerUserID"),
        autoCloseReason = null,
    )

    /** Swift: pendingItems = items → retryPendingSync. Kotlin: 오프라인으로 쌓고(드레인 0) 로그인 뒤 retryPending 한 번. */
    private fun replay(input: JsonObject, lastScavengeAgo: Long? = num(input, "lastScavengeAgoSeconds")): JsonObject {
        val script = input.array("script").map { (it as JsonObject).int("status") to it.string("body") }
        val recorder = GoldenRecorder(script)
        val (service, client) = recorder.service()
        val session = FakeSessionHost(service)
        val host = DesktopWorkQueueScenarioTest.Host().apply { live = str(input, "liveSessionID") }
        lateinit var queue: DesktopWorkQueue
        runBlocking {
            queue = DesktopWorkQueue(session, host, InMemoryDesktopKeyValueStore(), this, clock = { GOLDEN_NOW })
            lastScavengeAgo?.let { queue.scavenge.tryAcquire(GOLDEN_NOW.addingTimeInterval(-it.toDouble())) }
            val saved = session.current
            session.current = null
            input.array("items").forEach { queue.enqueue(item(it as JsonObject)) }
            queue.awaitIdle(10_000)
            session.current = saved
            queue.retryPending()
            queue.awaitIdle(10_000)
        }
        client.close()
        val failed = host.failures.isNotEmpty()
        return JsonObject(
            mapOf(
                "requests" to JsonArray(GoldenRecorder.masked(recorder.requests).map { r -> JsonObject(r.filterKeys { it != "headers" }) }),
                "remaining" to JsonArray(queue.items.value.map { JsonPrimitive(it.id) }),
                // 도장: 한 번도 안 찍었으면 드레인 전 값, 찍었으면 마지막 값(nil 을 찍은 것도 값이다).
                "confirmedServerSessionID" to
                    ((if (host.stamps.isEmpty()) str(input, "confirmedBeforeSessionID") else host.stamps.last())?.let(::JsonPrimitive) ?: JsonNull),
                "failed" to JsonPrimitive(failed),
                "syncMessage" to (if (failed) JsonPrimitive(host.failures.last()) else JsonNull),
                "drainedRefresh" to JsonPrimitive(host.drained > 0),
            ),
        )
    }

    private fun expected(c: JsonObject) = JsonObject(outcomeKeys.associateWith { c[it] ?: error("${c.string("id")}: '$it' 칸이 없다") })

    @Test
    fun goldenValuesMatchKotlinFixtures() {
        val v = golden.spec.obj("values")
        assertEquals(GOLDEN_USER, v.string("userID"))
        assertEquals(GOLDEN_NOW, SwiftDate(v.long("nowSince1970").toDouble()))
        assertEquals(DesktopWorkQueue.scavengeThrottleSeconds, v.long("scavengeThrottleSeconds").toDouble(), "⑫(2) 스로틀 = Swift scavengeThrottleSeconds")
        assertEquals(WALL_CLOCK_KEYS, golden.spec.array("wallClockKeys").map { (it as JsonPrimitive).content }.toSet())
    }

    @Test
    fun everySwiftScenarioReplaysIdentically() {
        val problems = mutableListOf<String>()
        for (c in golden.cases) {
            val want = GoldenCanonical.text(expected(c))
            val got = GoldenCanonical.text(replay(c.obj("input")))
            if (want != got) problems += "${c.string("id")}\n  Swift : $want\n  Kotlin: $got"
        }
        println("AINGCHECK-DESKTOP-WORK-QUEUE cases=${golden.cases.size} problems=${problems.size}")
        assertTrue(problems.isEmpty(), problems.joinToString("\n"))
    }

    @Test
    fun goldenCoversEveryResolverBranch() {
        val ids = golden.cases.map { it.string("id") }
        val need = listOf(
            "drain/start-then-stop", "drain/start-zero-rows-keeps-stamp", "drain/failure-stops-in-place", "resolver/1-blocker-is-mine", "resolver/1-blocker-invisible-retry-once",
            "resolver/2-scavenge-then-retry", "resolver/2-throttle-4m59s", "resolver/2-throttle-5m00s", "resolver/3a-stop-queued",
            "resolver/3b-coverage-earliest-row", "resolver/3b-coverage-open-row", "resolver/3b-sub-second", "resolver/3c-stale-draft", "resolver/3d-rethrow",
        )
        assertEquals(emptyList(), need - ids.toSet(), "골든에 빠진 갈래")
    }

    /** 시험 안 음성 대조: 스로틀 경계를 1초 옮겨 돌리면(5분 정각 → 4분 59초) Swift 녹음과 달라져야 한다 — 같으면 이 대조는 경계를 못 잰다. */
    @Test
    fun negative_throttleBoundaryShiftedOneSecondDiverges() {
        val c = golden.cases.first { it.string("id") == "resolver/2-throttle-5m00s" }
        val shifted = replay(c.obj("input"), lastScavengeAgo = 299)
        assertNotEquals(GoldenCanonical.text(expected(c)), GoldenCanonical.text(shifted))
        val rpc = shifted.array("requests").count { (it as JsonObject).string("path").endsWith("rpc/close_abandoned_work_sessions") }
        assertEquals(0, rpc, "4분 59초면 스캐빈저를 쏘지 않는다")
    }

    /** 시험 안 음성 대조: (3-b) 근무 중 표식을 빼면 (3-d) 되던짐으로 가 Swift 녹음과 달라야 한다. */
    @Test
    fun negative_dropLiveSessionDiverges() {
        val c = golden.cases.first { it.string("id") == "resolver/3b-coverage-open-row" }
        val input = JsonObject(c.obj("input") + ("liveSessionID" to JsonNull))
        assertNotEquals(GoldenCanonical.text(expected(c)), GoldenCanonical.text(replay(input)))
    }
}
