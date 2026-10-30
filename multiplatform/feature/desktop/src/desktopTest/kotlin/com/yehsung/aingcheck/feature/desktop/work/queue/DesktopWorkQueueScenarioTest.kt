// 시나리오 원본: Tests/checkTests/V0345StartConflictStubTests.swift · V0236SyncTests.swift(큐 순서 · 세대 · 23505 해소기) @ a90d8623
// 규약 번호: xplat-w1/briefs/work.md §2 wq ⑪(순서·세대 가드 앞 제거·소유자) ⑫(해소기 1·2·3a·3b·3c·3d, ★끝 시각을 고르지 않는다 C#24).
// 이 파일의 기대값은 위 Swift 시험과 WorkTimerStoreSync.swift 1669-1968 에서 옮겼다. 같은 갈래를 Swift 로 실제로 돌린 녹음은
// contract/golden/desktop-work-queue/scenarios.json — DesktopWorkQueueSwiftGoldenTest 가 대조한다.
package com.yehsung.aingcheck.feature.desktop.work.queue

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.WorkQueueHost
import com.yehsung.aingcheck.feature.desktop.work.service.FakeSessionHost
import com.yehsung.aingcheck.feature.desktop.work.service.GOLDEN_NOW
import com.yehsung.aingcheck.feature.desktop.work.service.GOLDEN_USER
import com.yehsung.aingcheck.feature.desktop.work.service.GoldenRecorder
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DesktopWorkQueueScenarioTest {
    private val team = "ee000000-0000-4000-8000-0000000000e5"
    private val sid = "ab000000-0000-4000-8000-0000000000f6"
    private val other = "cd000000-0000-4000-8000-0000000000c7"
    private val mineStart = GOLDEN_NOW.addingTimeInterval(-3600.0)   // 04:05:00Z

    class Host(var teamId: String? = "ee000000-0000-4000-8000-0000000000e5") : WorkQueueHost {
        override val currentTeamId: String? get() = teamId
        var writeGeneration = 0
        override val workStateWriteGeneration: Int get() = writeGeneration
        var live: String? = null
        override val liveSessionId: String? get() = live
        val stamps = mutableListOf<String?>()
        var drained = 0
        val failures = mutableListOf<String>()
        var wakeGate: suspend () -> Unit = {}
        override fun setConfirmedServerSessionId(id: String?) { stamps += id }
        override suspend fun awaitWakeGate() = wakeGate()
        override suspend fun onDrained() { drained++ }
        override fun onSyncFailed(message: String) { failures += message }
    }

    private fun row(id: String, started: String, ended: String? = null) =
        """{"id":"$id","user_id":"$GOLDEN_USER","started_at":"$started","ended_at":${ended?.let { "\"$it\"" } ?: "null"}}"""

    private val conflict = 409 to """{"code":"23505","message":"duplicate key value violates unique constraint \"work_sessions_one_open_per_user\""}"""

    private fun start(id: String = sid, owner: String? = GOLDEN_USER, at: SwiftDate? = mineStart) =
        PendingWorkItem("start-$id", PendingWorkOperation.Start, id, at, null, owner, null)

    private fun stop(id: String = sid, owner: String? = GOLDEN_USER, reason: AutoCloseReason? = null) =
        PendingWorkItem("stop-$id", PendingWorkOperation.Stop(3540), id, mineStart, GOLDEN_NOW.addingTimeInterval(-60.0), owner, reason)

    class Run(val recorder: GoldenRecorder, val session: FakeSessionHost, val host: Host, val store: InMemoryDesktopKeyValueStore, val queue: DesktopWorkQueue) {
        fun sigs(): List<String> = recorder.requests.map { r ->
            val q = (r["query"] as JsonArray).joinToString("&") { p -> (p as JsonArray).let { "${(it[0] as JsonPrimitive).content}=${(it[1] as JsonPrimitive).content}" } }
            "${(r["method"] as JsonPrimitive).content} ${(r["path"] as JsonPrimitive).content.removePrefix("/rest/v1/")}" + if (q.isEmpty()) "" else "?$q"
        }
        fun bodies(): List<JsonObject?> = recorder.requests.map { it["body"] as? JsonObject }
    }

    private fun scenario(
        script: List<Pair<Int, String>>,
        host: Host = Host(),
        store: InMemoryDesktopKeyValueStore = InMemoryDesktopKeyValueStore(),
        clock: () -> SwiftDate = { GOLDEN_NOW },
        body: suspend Run.() -> Unit,
    ): Run {
        val recorder = GoldenRecorder(script)
        val (service, client) = recorder.service(clock)
        val session = FakeSessionHost(service)
        lateinit var run: Run
        runBlocking {
            val queue = DesktopWorkQueue(session, host, store, this, clock = clock)
            run = Run(recorder, session, host, store, queue)
            run.body()
            queue.awaitIdle(10_000)
        }
        client.close()
        return run
    }

    /** 줄을 오프라인으로 쌓고(체인 칸마다 드레인하지 않게) 로그인 뒤 한 번만 드레인한다(Swift retryPendingSync). */
    private suspend fun Run.offlineThenDrain(vararg items: PendingWorkItem) {
        val saved = session.current
        session.current = null
        items.forEach { queue.enqueue(it) }
        queue.awaitIdle(10_000)
        session.current = saved
        queue.retryPending()
    }

    @Test
    fun offlineStartThenStop_drainsInOrderAfterLogin() {
        val r = scenario(listOf(200 to "[${row(sid.uppercase(), "2026-09-17T04:05:00Z")}]", 200 to "{}",
            200 to "[${row(sid, "2026-09-17T04:05:00Z", "2026-09-17T05:04:00Z")}]", 200 to "{}")) {
            session.current = null
            queue.enqueue(start())
            queue.enqueue(stop())
            queue.awaitIdle(10_000)
            assertEquals(0, recorder.requests.size, "로그아웃 중엔 요청 0")
            assertEquals(2, queue.items.value.size)
            assertTrue(store.getString(DesktopWorkQueue.pendingWorkQueueKey) != null, "줄은 영속된다")
            session.current = com.yehsung.aingcheck.core.wire.SupabaseSession("golden-access-token", null, GOLDEN_USER)
            queue.retryPending()
        }
        assertEquals(listOf(
            "POST work_sessions?on_conflict=id", "POST work_statuses?on_conflict=team_id,user_id",
            "PATCH work_sessions?id=eq.$sid&team_id=eq.$team&user_id=eq.$GOLDEN_USER&ended_at=is.null", "POST work_statuses?on_conflict=team_id,user_id",
        ), r.sigs())
        assertEquals(emptyList(), r.queue.items.value)
        assertNull(r.store.getString(DesktopWorkQueue.pendingWorkQueueKey), "빈 큐는 키째 지운다")
        assertEquals(listOf<String?>(sid), r.host.stamps, "도장 (a): 서버가 돌려준 행(소문자)")
        assertEquals(1, r.host.drained)
    }

    @Test
    fun failureStopsInPlace_orderPreserved() {
        val r = scenario(listOf(500 to """{"message":"boom"}""")) {
            offlineThenDrain(start(), stop())
        }
        assertEquals(1, r.recorder.requests.size, "첫 항목 실패 뒤 다음 항목을 보내지 않는다")
        assertEquals(listOf("start-$sid", "stop-$sid"), r.queue.items.value.map { it.id })
        assertEquals(1, r.host.failures.size)
        assertEquals(0, r.host.drained)
    }

    @Test
    fun logoutMidDrain_removesFinishedBeforeGenerationGuard_keepsRest() {
        val r = scenario(listOf(200 to "[${row(sid, "2026-09-17T04:05:00Z")}]", 200 to "{}")) {
            session.onCall = { n -> if (n == 1) session.generation++ }
            offlineThenDrain(start(), stop())
        }
        assertEquals(listOf("stop-$sid"), r.queue.items.value.map { it.id }, "끝난 start 는 빠지고(⑪) 남은 stop 은 보존")
        assertEquals(2, r.recorder.requests.size)
        assertEquals(0, r.host.drained)
        assertEquals(emptyList(), r.host.failures)
    }

    @Test
    fun foreignOwnerItemsAreDroppedOnAdopt() {
        val r = scenario(listOf(200 to "[]", 200 to "{}")) {
            session.current = null
            queue.enqueue(start(id = other, owner = "someone-else"))
            queue.enqueue(start(id = "ff000000-0000-4000-8000-000000000001", owner = null))
            queue.enqueue(start())
            queue.awaitIdle(10_000)
            queue.retainOwnedBy(GOLDEN_USER)
            session.current = com.yehsung.aingcheck.core.wire.SupabaseSession("golden-access-token", null, GOLDEN_USER)
            queue.retryPending()
        }
        assertEquals(2, r.recorder.requests.size, "내 항목 하나만 재생")
        assertTrue((r.bodies()[0]!!["id"] as JsonPrimitive).content == sid)
        assertEquals(emptyList<String?>(), r.host.stamps, "0행(이미 있다)은 도장을 찍지 않는다")
    }

    @Test
    fun resolver1_blockerIsMine_done() {
        val r = scenario(listOf(conflict, 200 to "[${row(sid.uppercase(), "2026-09-17T04:05:00Z")}]")) { queue.enqueue(start()) }
        assertEquals(listOf("POST work_sessions?on_conflict=id",
            "GET work_sessions?select=id,user_id,started_at,ended_at,duration_seconds&user_id=eq.$GOLDEN_USER&or=(ended_at.is.null,ended_at.gte.2026-09-17T04:05:00Z)&order=started_at.asc&limit=50"),
            r.sigs())
        assertEquals(listOf<String?>(sid), r.host.stamps)
        assertEquals(emptyList(), r.queue.items.value)
    }

    @Test
    fun resolver2_scavengeThenRetryStart() {
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]", 200 to "1",
            200 to "[${row(sid, "2026-09-17T04:05:00Z")}]", 200 to "{}")) { queue.enqueue(start()) }
        assertEquals(listOf("POST work_sessions", "GET work_sessions", "POST rpc/close_abandoned_work_sessions", "POST work_sessions", "POST work_statuses"),
            r.sigs().map { it.substringBefore('?') })
        assertEquals(listOf<String?>(sid), r.host.stamps)
        assertEquals(emptyList(), r.queue.items.value)
    }

    // ⑫(2) 5분 스로틀(Swift WorkTimerStore.swift:76 scavengeThrottleSeconds · WorkTimerStoreSync.swift:1842 `>= 300` 이면 발사).
    // 시나리오 시계를 마지막 발사에서 4분 59초 / 5분 뒤로 둬 경계 양쪽을 잰다 — 같은 순간에 막고 같은 순간에 재면 0 보다 큰 어떤 스로틀도 통과한다.
    @Test
    fun rule12_2_scavengeThrottle_fiveMinuteBoundary() {
        assertEquals(300.0, DesktopWorkQueue.scavengeThrottleSeconds)
        val recorder = GoldenRecorder(emptyList())
        val (service, client) = recorder.service()
        runBlocking {
            val queue = DesktopWorkQueue(FakeSessionHost(service), Host(), InMemoryDesktopKeyValueStore(), this, clock = { GOLDEN_NOW })
            val t = GOLDEN_NOW
            assertTrue(queue.scavenge.tryAcquire(t), "처음은 언제나 발사(Swift lastScavengeAt = .distantPast)")
            assertFalse(queue.scavenge.tryAcquire(t.addingTimeInterval(1.0)))
            assertFalse(queue.scavenge.tryAcquire(t.addingTimeInterval(299.0)), "4분 59초 — 아직 막힌다")
            assertTrue(queue.scavenge.tryAcquire(t.addingTimeInterval(300.0)), "5분 정각 — 다시 발사")
            assertFalse(queue.scavenge.tryAcquire(t.addingTimeInterval(599.0)), "기준은 마지막 **발사** 시각(막힌 시도는 기준을 옮기지 않는다)")
            assertTrue(queue.scavenge.tryAcquire(t.addingTimeInterval(600.0)))
        }
        client.close()
    }

    @Test
    fun rule12_2_resolver_4m59sAfterLastScavenge_noRpc_rethrows() {
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]")) {
            queue.scavenge.tryAcquire(GOLDEN_NOW.addingTimeInterval(-299.0))
            queue.enqueue(start())
        }
        assertEquals(listOf("POST work_sessions", "GET work_sessions"), r.sigs().map { it.substringBefore('?') },
            "스로틀 안(4분 59초)이면 close_abandoned_work_sessions 를 쏘지 않고 (3-d) 로")
        assertEquals(listOf("start-$sid"), r.queue.items.value.map { it.id })
        assertEquals(1, r.host.failures.size)
    }

    @Test
    fun rule12_2_resolver_5m00sAfterLastScavenge_firesRpc_thenRetryStart() {
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]", 200 to "1",
            200 to "[${row(sid, "2026-09-17T04:05:00Z")}]", 200 to "{}")) {
            queue.scavenge.tryAcquire(GOLDEN_NOW.addingTimeInterval(-300.0))
            queue.enqueue(start())
        }
        assertEquals(listOf("POST work_sessions", "GET work_sessions", "POST rpc/close_abandoned_work_sessions", "POST work_sessions", "POST work_statuses"),
            r.sigs().map { it.substringBefore('?') }, "5분 정각이면 다시 쏜다")
        assertEquals(emptyList(), r.queue.items.value)
        assertEquals(listOf<String?>(sid), r.host.stamps)
    }

    @Test
    fun rule12_2_resolver_throttleReadsTheQueueClock() {
        // 시계가 움직이는 시나리오: 같은 큐에서 첫 해소가 쏜 뒤 4분 59초 뒤의 둘째 해소는 막히고, 5분 뒤의 셋째는 다시 쏜다.
        var now = GOLDEN_NOW
        val r = scenario(listOf(
            conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]", 200 to "1", conflict,
            conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]",
            conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]", 200 to "1", 200 to "[${row(sid, "2026-09-17T04:05:00Z")}]", 200 to "{}",
        ), clock = { now }) {
            queue.enqueue(start())
            queue.awaitIdle(10_000)
            now = GOLDEN_NOW.addingTimeInterval(299.0)
            queue.retryPending()
            now = GOLDEN_NOW.addingTimeInterval(300.0)
            queue.retryPending()
        }
        assertEquals(listOf(
            "POST work_sessions", "GET work_sessions", "POST rpc/close_abandoned_work_sessions", "POST work_sessions",
            "POST work_sessions", "GET work_sessions",
            "POST work_sessions", "GET work_sessions", "POST rpc/close_abandoned_work_sessions", "POST work_sessions", "POST work_statuses",
        ), r.sigs().map { it.substringBefore('?') })
        assertEquals(emptyList(), r.queue.items.value)
        assertEquals(2, r.host.failures.size)
    }

    @Test
    fun resolver3a_stopQueuedForSameSession_endsWithStopsFallback() {
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]",
            200 to "[]", 200 to "{}", 200 to "[${row(other, "2026-09-17T04:35:00Z")}]")) {
            queue.scavenge.tryAcquire(GOLDEN_NOW)   // (2) 스로틀이 막혀 있다
            queue.enqueue(start())
            queue.enqueue(stop())
        }
        assertEquals(listOf("POST work_sessions", "GET work_sessions", "PATCH work_sessions", "POST work_sessions", "GET work_sessions"),
            r.sigs().map { it.substringBefore('?') }, "(3-a) 앞 구간을 적지 않는다 — stop 의 폴백 POST 가 정본 닫힌 행")
        assertEquals(emptyList(), r.queue.items.value)
    }

    @Test
    fun resolver3b_livingSession_insertsOnlyUpToCoverage_neverPicksEnd() {
        val host = Host().apply { live = sid }
        // 열린 남의 행(04:35)과 그 사이 닫힌 행(04:20~04:30) — 덮기 시작 = 둘 중 이른 04:20.
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")},${row("x", "2026-09-17T04:20:00Z", "2026-09-17T04:30:00Z")}]", 200 to "{}"), host) {
            queue.scavenge.tryAcquire(GOLDEN_NOW)
            queue.enqueue(start())
        }
        assertEquals(listOf("POST work_sessions", "GET work_sessions", "POST work_sessions"), r.sigs().map { it.substringBefore('?') })
        val insert = r.bodies()[2]!!
        assertEquals("2026-09-17T04:05:00Z", (insert["started_at"] as JsonPrimitive).content)
        assertEquals("2026-09-17T04:20:00Z", (insert["ended_at"] as JsonPrimitive).content)
        assertEquals("900", insert["duration_seconds"].toString())
        assertEquals(listOf<String?>(null), host.stamps, "(3-b) 도장 null — 이 id 는 열린 행으로 서버에 없다")
    }

    @Test
    fun resolver3b_coverage_endIsServerCoverageStartNotNow() {
        val host = Host().apply { live = sid }
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]", 200 to "{}"), host) {
            queue.scavenge.tryAcquire(GOLDEN_NOW)
            queue.enqueue(start())
        }
        val insert = r.bodies()[2]!!
        assertEquals("2026-09-17T04:35:00Z", (insert["ended_at"] as JsonPrimitive).content, "★ 끝 = 서버가 덮기 시작하는 지점(지금 아님 — C#24)")
        assertEquals("1800", insert["duration_seconds"].toString())
        assertEquals(emptyList(), r.queue.items.value)
    }

    @Test
    fun resolver3b_subSecondSpanWritesNothing() {
        val host = Host().apply { live = sid }
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:05:00.500Z")}]"), host) {
            queue.scavenge.tryAcquire(GOLDEN_NOW)
            queue.enqueue(start())
        }
        assertEquals(2, r.recorder.requests.size, "1초 미만 구간은 쓰지 않는다")
        assertEquals(listOf<String?>(null), host.stamps)
    }

    @Test
    fun resolver3c_staleDraftIsDropped() {
        val host = Host().apply { live = other }
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]"), host) {
            queue.scavenge.tryAcquire(GOLDEN_NOW)
            queue.enqueue(start())
        }
        assertEquals(2, r.recorder.requests.size)
        assertEquals(emptyList(), r.queue.items.value)
        assertEquals(emptyList<String?>(), host.stamps)
    }

    @Test
    fun resolver3d_rethrowsAndKeepsOrder() {
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]")) {
            queue.scavenge.tryAcquire(GOLDEN_NOW)
            offlineThenDrain(start(), stop(id = other))   // 같은 세션 Stop 이 없어야 (3-a) 가 아니다
        }
        assertEquals(2, r.recorder.requests.size)
        assertEquals(listOf("start-$sid", "stop-$other"), r.queue.items.value.map { it.id }, "(3-d) 되던짐 — 순서 그대로")
        assertEquals(1, r.host.failures.size)
    }

    @Test
    fun resolver_writeGenerationMovedDuringFetch_rethrows() {
        val host = Host().apply { live = sid }
        val r = scenario(listOf(conflict, 200 to "[${row(other, "2026-09-17T04:35:00Z")}]"), host) {
            session.onCall = { n -> if (n == 1) host.writeGeneration++ }
            queue.enqueue(start())
        }
        assertEquals(2, r.recorder.requests.size, "낡은 사실로 정산하지 않는다")
        assertEquals(1, r.queue.items.value.size)
        assertEquals(1, host.failures.size)
    }

    @Test
    fun noTeam_failsWithJoinMessage() {
        val host = Host(teamId = null)
        val r = scenario(emptyList(), host) { queue.enqueue(start()) }
        assertEquals(0, r.recorder.requests.size)
        assertEquals(listOf(DesktopWorkQueue.noTeamMessage), host.failures)
    }

    @Test
    fun persistedQueueRestores_brokenDataFoldsToEmpty() {
        val store = InMemoryDesktopKeyValueStore()
        scenario(emptyList(), store = store) {
            session.current = null
            queue.enqueue(start(at = SwiftDate(1_789_617_900.25)))
            queue.enqueue(stop(reason = AutoCloseReason.SLEEP))
        }
        val restored = DesktopWorkQueue.restore(store)
        assertEquals(listOf(start(at = SwiftDate(1_789_617_900.25)), stop(reason = AutoCloseReason.SLEEP)), restored)
        assertEquals(emptyList(), DesktopWorkQueue.restore(InMemoryDesktopKeyValueStore(mapOf(DesktopWorkQueue.pendingWorkQueueKey to "[{\"id\":1}"))))
    }

    @Test
    fun awaitIdle_isBounded_andDoesNotCancelChain() {
        val recorder = GoldenRecorder(emptyList())
        val (service, client) = recorder.service()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val gate = CompletableDeferred<Unit>()
        val host = Host().apply { wakeGate = { gate.await() } }
        val queue = DesktopWorkQueue(FakeSessionHost(service), host, InMemoryDesktopKeyValueStore(), scope, clock = { GOLDEN_NOW })
        queue.enqueue(start())
        val began = System.nanoTime()
        runBlocking { queue.awaitIdle(200) }
        val ms = (System.nanoTime() - began) / 1_000_000
        assertTrue(ms in 150..5_000, "상한에서 돌아온다($ms ms)")
        assertEquals(0, recorder.requests.size)
        gate.complete(Unit)
        runBlocking { queue.awaitIdle(10_000) }
        assertEquals(2, recorder.requests.size, "진 쪽(체인)은 취소되지 않고 이어 간다")
        scope.cancel()
        client.close()
    }
}
