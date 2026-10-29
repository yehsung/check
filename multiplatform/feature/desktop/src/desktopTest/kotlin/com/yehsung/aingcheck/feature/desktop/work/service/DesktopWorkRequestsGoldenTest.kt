// 골든: contract/golden/desktop-work/requests.json ← Swift Tests/CheckMobileKitTests/GoldenExport/desktop-work/GoldenExportDesktopWorkRequests.swift
// (원본 Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 근무 몫). 규약 번호는 xplat-w1/briefs/work.md §2 wq ①~⑩ · C§4.1 #20~#24·#36.
package com.yehsung.aingcheck.feature.desktop.work.service

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class DesktopWorkRequestsGoldenTest {
    private val u = GOLDEN_USER
    private val t = ACCESS
    private val team = "ee000000-0000-4000-8000-0000000000e5"
    private val sid = "ab000000-0000-4000-8000-0000000000f6"
    private val device = "win:0f000000-0000-4000-8000-0000000000a7"
    private val now = GOLDEN_NOW
    private val startedAt = now.addingTimeInterval(-3600.0)
    private val endedAt = now.addingTimeInterval(-60.0)
    private val lastInput = now.addingTimeInterval(-30.0)

    private fun SupabaseWorkService.tick() =
        makeWorkTickRequest(team, heartbeat = true, sessionID = null, deviceID = device, openedSession = false, lastInputAt = null, includeMeta = false, now = now)

    private val stop: suspend SupabaseWorkService.(Long, AutoCloseReason?, Boolean) -> Unit = { d, r, shared ->
        stopWork(t, team, u, startedAt, endedAt, d, sid, r, shared)
    }

    /** Swift `GoldenExportDesktopWorkRequests.calls` 와 같은 id · 같은 인자. 여기 없는 id 가 골든에 있으면 "미이식". */
    val registry: Map<String, suspend (SupabaseWorkService) -> Any?> = linkedMapOf(
        "startWork#rows" to { s -> s.startWork(t, team, u, sid, startedAt) },
        "startWork#zeroRows" to { s -> s.startWork(t, team, u, sid, startedAt) },
        "startWork#undecodable" to { s -> s.startWork(t, team, u, sid, startedAt) },
        "startWork#23505" to { s -> s.startWork(t, team, u, sid, startedAt) },
        "stopWork#manual" to { s -> s.stop(3540, null, true) },
        "stopWork#autoReason" to { s -> s.stop(3540, AutoCloseReason.AWAY, true) },
        "stopWork#reasonColumnMissing" to { s -> s.stop(3540, AutoCloseReason.LONG_SESSION, true) },
        "stopWork#zeroRowsFallback" to { s -> s.stop(-5, null, true) },
        "stopWork#zeroRowsSleepCorrect" to { s -> s.stop(3540, AutoCloseReason.SLEEP, true) },
        "stopWork#zeroRowsOtherOpen" to { s -> s.stop(3540, null, true) },
        "stopWork#zeroRowsOpenLookupFails" to { s -> s.stop(3540, null, true) },
        "stopWork#noSharedStatus" to { s -> s.stop(3540, null, false) },
        "heartbeat#input" to { s -> s.heartbeat(t, team, u, sid, lastInput) },
        "heartbeat#noInput" to { s -> s.heartbeat(t, team, u, sid) },
        "heartbeat#inputColumnMissing" to { s -> s.heartbeat(t, team, u, sid, lastInput) },
        "upsertStatusDevice#opened" to { s -> s.upsertStatusDevice(t, team, u, device, sid, true, lastInput) },
        "upsertStatusDevice#weak" to { s -> s.upsertStatusDevice(t, team, u, device, sid, false) },
        "upsertStatusDevice#inputColumnMissing" to { s -> s.upsertStatusDevice(t, team, u, device, sid, true, lastInput) },
        "reportDeviceInput" to { s -> s.reportDeviceInput(t, team, u, device, lastInput) },
        "closeAbandonedSessions#int" to { s -> s.closeAbandonedSessions(t) },
        "closeAbandonedSessions#empty" to { s -> s.closeAbandonedSessions(t) },
        "awaySync#ok" to { s -> s.awaySync(t) },
        "awaySync#thresholdZero" to { s -> s.awaySync(t) },
        "awaySync#eligibleMissing" to { s -> s.awaySync(t) },
        "awaySync#unavailable" to { s -> s.awaySync(t) },
        "awaySync#garbage" to { s -> s.awaySync(t) },
        "makeWorkTickRequest#owner" to { s -> s.makeWorkTickRequest(team, true, sid, device, true, lastInput, false, now) },
        "makeWorkTickRequest#adopted" to { s -> s.makeWorkTickRequest(team, false, null, device, false, lastInput, false, now) },
        "makeWorkTickRequest#unconfirmed" to { s -> s.makeWorkTickRequest(team, false, null, null, false, lastInput, true, now) },
        "makeWorkTickRequest#none" to { s -> s.makeWorkTickRequest(null, false, null, null, false, null, false, now) },
        "workTick#ok" to { s -> s.workTick(t, s.tick()) },
        "workTick#401" to { s -> s.workTick(t, s.tick()) },
        "workTick#404" to { s -> s.workTick(t, s.tick()) },
        "workTick#PGRST202" to { s -> s.workTick(t, s.tick()) },
        "workTick#403" to { s -> s.workTick(t, s.tick()) },
        "workTick#42501" to { s -> s.workTick(t, s.tick()) },
        "workTick#503" to { s -> s.workTick(t, s.tick()) },
        "workTick#409" to { s -> s.workTick(t, s.tick()) },
        "workTick#v2" to { s -> s.workTick(t, s.tick()) },
        "workTick#garbage" to { s -> s.workTick(t, s.tick()) },
        "reopenSession#rows" to { s -> s.reopenSession(t, team, u, sid) },
        "reopenSession#zero" to { s -> s.reopenSession(t, team, u, sid) },
        "reopenSession#reasonColumnMissing" to { s -> s.reopenSession(t, team, u, sid) },
        "openSessionIDs" to { s -> s.openSessionIDs(t, u) },
        "fetchMyOverlappingSessions" to { s -> s.fetchMyOverlappingSessions(t, u, startedAt) },
        "insertClosedSession" to { s -> s.insertClosedSession(t, team, u, sid, startedAt, endedAt) },
    )

    class Recorded(val requests: List<JsonObject>, val result: JsonElement)

    fun record(script: List<Pair<Int, String>>, clock: () -> SwiftDate = { now }, call: suspend (SupabaseWorkService) -> Any?): Recorded {
        val recorder = GoldenRecorder(script)
        val (service, client) = recorder.service(clock)
        val result = runBlocking {
            try {
                resultOf(call(service))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                thrownOf(e)
            }
        }
        client.close()
        return Recorded(recorder.requests.toList(), result)
    }

    private fun scriptOf(c: JsonObject) = c.array("responses").map { (it as JsonObject).int("status") to it.string("body") }

    /** 골든 case 하나를 Kotlin 으로 녹음해 (요청 · 결과) 불일치를 돌려준다(빈 목록 = 같다). */
    fun compareCase(c: JsonObject, call: suspend (SupabaseWorkService) -> Any?): List<String> {
        val recorded = record(scriptOf(c), call = call)
        val out = mutableListOf<String>()
        val want = GoldenCanonical.text(c.array("requests"))
        val got = GoldenCanonical.text(JsonArray(GoldenRecorder.masked(recorded.requests)))
        if (want != got) out += "요청이 다르다\n  Swift : $want\n  Kotlin: $got"
        val wantResult = GoldenCanonical.text(c["result"]!!)
        val gotResult = GoldenCanonical.text(recorded.result)
        if (wantResult != gotResult) out += "결과가 다르다\n  Swift : $wantResult\n  Kotlin: $gotResult"
        return out
    }

    @Test
    fun everyDesktopWorkRequestIsPortedAndMatches() {
        val golden = Golden.load("desktop-work/requests")
        val problems = mutableListOf<String>()
        val missing = mutableListOf<String>()
        for (c in golden.cases) {
            val id = c.string("id")
            val call = registry[id] ?: run { missing += id; null } ?: continue
            compareCase(c, call).forEach { problems += golden.failure(id, it) }
        }
        val ids = golden.cases.map { it.string("id") }
        val extra = registry.keys - ids.toSet()
        // 이름 누락 단언(work.md §5): 근무 H 이름이 모두 case 를 가진다.
        val names = golden.spec.array("names").map { (it as JsonPrimitive).content }
        val unnamed = names.filter { n -> ids.none { it == n || it.startsWith("$n#") } }
        val wall = golden.spec.array("wallClockKeys").map { (it as JsonPrimitive).content }.toSet()
        println("AINGCHECK-DESKTOP-WORK cases=${golden.cases.size} 미이식=${missing.size} names=${names.size} problems=${problems.size}")
        assertEquals(WALL_CLOCK_KEYS, wall, "벽시계 키 목록이 Swift 와 다르다")
        assertTrue(unnamed.isEmpty(), "case 가 없는 근무 이름: $unnamed")
        assertTrue(missing.isEmpty(), "미이식 ${missing.size}: $missing")
        assertTrue(extra.isEmpty(), "골든에 없는 Kotlin id: $extra")
        assertTrue(golden.cases.size >= 45, "case 가 적다(${golden.cases.size})")
        if (problems.isNotEmpty()) fail("데스크톱 근무 골든 불일치 ${problems.size}건(처음 12):\n" + problems.take(12).joinToString("\n\n"))
    }

    /** 벽시계 키는 Swift 쪽에선 `Date()` 라 표식으로 지웠다 — Kotlin 은 주입 시계 그대로 찍는지 따로 잰다(표식 전 값). */
    @Test
    fun wallClockStampsUseInjectedClock() {
        val r = record(listOf(200 to "[]", 200 to "{}", 200 to "[]", 200 to "{}", 200 to "[]", 200 to "{}")) { s -> s.stop(3540, AutoCloseReason.SLEEP, true) }
        val stamps = r.requests.flatMap { req ->
            (req["body"] as? JsonObject)?.filterKeys { it in WALL_CLOCK_KEYS }?.values?.map { (it as JsonPrimitive).content } ?: emptyList()
        }
        assertTrue(stamps.size >= 4, "벽시계 칸이 적다: $stamps")
        assertEquals(setOf("2026-09-17T05:05:00Z"), stamps.toSet())
    }

    // ---- 음성 대조(비교기가 늘 초록이 아님을 본다 — 규칙 하나를 깬 녹음을 같은 비교기에 넣는다) ----

    private fun goldenCase(id: String): JsonObject = Golden.load("desktop-work/requests").cases.first { it.string("id") == id }

    /** C#21 stop 에서 id 필터를 뺀 PATCH 는 골든과 다르다. */
    @Test
    fun negative_stopWithoutIdFilterIsRed() {
        val diffs = compareCase(goldenCase("stopWork#manual")) { s ->
            s.send(DesktopWorkPaths.workSessions, "PATCH", listOf("team_id" to "eq.$team", "user_id" to "eq.$u", "ended_at" to "is.null"),
                """{"ended_at":"2026-09-17T05:04:00Z","duration_seconds":3540}""".encodeToByteArray(), t, "return=representation")
            s.heartbeat(t, team, u, sid)
        }
        assertNotEquals(emptyList(), diffs)
    }

    /** C#20 0행을 "남의 세션"(오류)으로 읽으면 결과가 다르다. */
    @Test
    fun negative_zeroRowsAsForeignIsRed() {
        val diffs = compareCase(goldenCase("startWork#zeroRows")) { s ->
            s.startWork(t, team, u, sid, startedAt) ?: throw com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError.SessionAlreadyOpen
        }
        assertTrue(diffs.any { it.startsWith("결과가 다르다") }, "$diffs")
    }

    /** C#22 세션 id 를 대문자로 보내면 요청이 다르다. */
    @Test
    fun negative_uppercaseSessionIdIsRed() {
        val diffs = compareCase(goldenCase("startWork#rows")) { s -> s.startWork(t, team, u, sid.uppercase(), startedAt) }
        assertTrue(diffs.any { it.startsWith("요청이 다르다") }, "$diffs")
    }

    /** C#36 디코드 실패를 던지면 결과가 다르다. */
    @Test
    fun negative_decodeFailureThrowsIsRed() {
        val diffs = compareCase(goldenCase("startWork#undecodable")) { s ->
            s.startWork(t, team, u, sid, startedAt)
            throw kotlinx.serialization.SerializationException("x")
        }
        assertTrue(diffs.any { it.startsWith("결과가 다르다") }, "$diffs")
    }
}
