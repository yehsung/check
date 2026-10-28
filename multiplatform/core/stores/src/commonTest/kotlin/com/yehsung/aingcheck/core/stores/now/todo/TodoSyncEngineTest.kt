// 원본: Tests/checkTests/V0330TodoSyncEngineTests.swift:183-499 · 683-723 · 794-911(엔진 — 디바운스 · 한 번에 하나 · 500 분할 · 실패 · 계정 전환 ·
//       로그아웃 · 정리 · 보호 · 함수 없음 쿨다운 · 맞추는 때 · 주기) · V0330TodoHeldRejectTests.swift:89-208 · 438-474(붙잡기 엔진) @ 1b8260d
// 맥 보드 조정자(`TodoSyncCoordinator` · `CheckTodoBoardController`)는 맥 몫이다 — 보호·변경 알림 배선은 지금 탭(NowStore)이 하는 것과 같은 꼴로 손으로 건다.
package com.yehsung.aingcheck.core.stores.now.todo

import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResponse
import com.yehsung.aingcheck.core.stores.now.InMemoryTodoFileSystem
import com.yehsung.aingcheck.core.stores.now.ManualScheduler
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.io.IOException
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TodoSyncEngineTest {
    private val base = TODO_BASE_MS
    private val heavyTitle: String = ("x" + (0x0363 until 0x036D).joinToString("") { it.toChar().toString() }).repeat(100)

    private class Rig(val files: InMemoryTodoFileSystem, val list: TodoListStore, val transport: RecordingTransport, val scheduler: ManualScheduler, val sync: TodoSync)

    private fun TestScope.rig(
        transport: RecordingTransport,
        files: InMemoryTodoFileSystem = InMemoryTodoFileSystem(),
        path: String = "/mem/todos.local.json",
        clock: () -> Double = { msDate(base) },
    ): Rig {
        val list = TodoListStore(path, files, clock)
        val scheduler = ManualScheduler()
        val sync = TodoSync(list, transport, scheduler, this, clock)
        // 지금 탭(NowStore)과 같은 배선: 사용자 변경 → 디바운스.
        list.onLocalChange = { sync.noteLocalChange() }
        return Rig(files, list, transport, scheduler, sync)
    }

    @Test
    fun debouncesEditsToOneRequestAfterTheLastPlusOnePointFive() = runTest {
        val server = TodoServerModel(base)
        val r = rig(RecordingTransport.of(server))
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(1, r.transport.requests.size, "실행 직후 한 번")
        repeat(3) {
            r.list.add("연달아")
            r.scheduler.advance(1.0)
            advanceUntilIdle()
        }
        assertEquals(1, r.transport.requests.size, "디바운스 전에 보냈다")
        r.scheduler.advance(0.49)
        advanceUntilIdle()
        assertEquals(1, r.transport.requests.size)
        r.scheduler.advance(0.01)
        advanceUntilIdle()
        assertEquals(2, r.transport.requests.size)
        assertEquals(3, r.transport.requests[1].second.changes.size)
        assertEquals(emptySet(), r.list.pendingIDs)
        assertEquals(TodoSyncOutcome.synced, r.sync.lastOutcome)
    }

    @Test
    fun singleFlightCoalescesCallsWhileRunning() = runTest {
        val server = TodoServerModel(base)
        val transport = RecordingTransport.of(server)
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        val r = rig(transport)
        r.sync.activate(USER_A)
        runCurrent()
        assertEquals(1, transport.arrivals)
        assertTrue(r.sync.isRunning)
        repeat(3) { r.sync.requestSync(TodoSyncReason.boardOpened) }
        assertEquals(1, transport.requests.size)
        transport.gate = null
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(2, transport.requests.size, "도는 중의 세 번이 한 번으로 합쳐지지 않았다")
        assertFalse(r.sync.isRunning)
        assertEquals(TodoSyncOutcome.synced, r.sync.lastOutcome)
    }

    @Test
    fun splitsPendingIntoBatchesOf500AndChainsWatermark() = runTest {
        val server = TodoServerModel(base)
        val transport = RecordingTransport { userID, request -> server.respond(userID, request).also { server.nowMs += 1_000 } }
        val files = InMemoryTodoFileSystem()
        val items = (0 until 1203).map { todoRow(uuid(it + 1), "줄 $it", base) }
        TodoFileStore.save(files, TodoFile(version = 1, items = items), "/mem/todos.local.json")
        val r = rig(transport, files)
        assertEquals(1203, r.list.pendingIDs.size)
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(listOf(500, 500, 203), transport.requests.map { it.second.changes.size })
        assertEquals(listOf(null, base, base + 1_000), transport.requests.map { it.second.sinceMs })
        assertEquals(emptySet(), r.list.pendingIDs)
        assertEquals(base + 2_000, r.list.watermarkMs)
        assertEquals(1203, server.items(USER_A).size)
        val onDisk = TodoFileStore.load(files, "/mem/todos.local.json")
        assertEquals(emptyList(), onDisk.sync.pendingIDs)
        assertEquals(base + 2_000, onDisk.sync.watermarkMs)
        assertEquals(1203, onDisk.items.size)
        // 보내는 순서는 대문자 uuid 글자 순(맥과 같은 묶음).
        assertEquals(items.map { it.id }.sortedBy { it.uppercase() }.take(500), transport.requests[0].second.changes.map { it.id })
    }

    @Test
    fun networkFailureAndRefusedResponseKeepPendingWatermarkAndFile() = runTest {
        var mode = 0
        val transport = RecordingTransport { _, _ -> if (mode == 0) throw IOException("offline") else TodoSyncResponse(status = "invalid") }
        val r = rig(transport)
        val item = r.list.add("못 보낸 줄")!!
        val before = r.files.text("/mem/todos.local.json")
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(TodoSyncOutcome.failed, r.sync.lastOutcome)
        mode = 1
        r.sync.requestSync(TodoSyncReason.periodic)
        advanceUntilIdle()
        assertEquals(TodoSyncOutcome.refused("invalid"), r.sync.lastOutcome)
        assertEquals(setOf(item.id), r.list.pendingIDs)
        assertNull(r.list.watermarkMs)
        assertEquals(before, r.files.text("/mem/todos.local.json"))
    }

    @Test
    fun accountSwitchDropsLateResponseAndSyncsNewAccountAtOnce() = runTest {
        val server = TodoServerModel(base)
        val foreign = todoRow(uuid(900), "A 계정의 다른 기기 줄", base - 5_000, createdMs = base - 5_000)
        server.seed(USER_A, foreign)
        val transport = RecordingTransport.of(server)
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        val files = InMemoryTodoFileSystem()
        val fileA = "/mem/todos.A.json"
        val fileB = "/mem/todos.B.json"
        val bItem = todoRow(uuid(800), "B 의 줄", base - 1_000, createdMs = base - 1_000)
        TodoFileStore.save(files, TodoFile(items = listOf(bItem), sync = TodoFileSyncState(base - 1_000, emptyList())), fileB)
        val bBefore = files.text(fileB)
        val r = rig(transport, files, fileA)
        val aItem = r.list.add("A 의 줄")!!
        r.sync.activate(USER_A)
        runCurrent()
        assertEquals(1, transport.arrivals)

        r.sync.switchAccount(USER_B, fileB)
        assertEquals(fileB, r.list.filePath)
        assertEquals(listOf(bItem), r.list.items)
        transport.gate = null
        gate.complete(Unit)   // A 의 응답이 이제 도착한다 · 끝난 뒤 B 를 맞춘다
        advanceUntilIdle()
        assertEquals(listOf(USER_A, USER_B), transport.requests.map { it.first })
        assertEquals(base - 1_000, transport.requests[1].second.sinceMs)
        assertEquals(listOf(bItem), r.list.items, "앞 계정 응답이 새 계정 목록에 섞였다")
        assertEquals(TodoSyncOutcome.synced, r.sync.lastOutcome)
        val aFile = TodoFileStore.load(files, fileA)
        assertEquals(listOf(aItem.id), aFile.sync.pendingIDs, "A 파일은 늦은 응답을 받지 않았으니 여전히 보낼 것을 들고 있다")
        assertTrue(aFile.items.none { it.id == foreign.id })
        assertTrue(bBefore != null)
    }

    @Test
    fun lateResponseIsDiscardedStaleNotMerged() = runTest {
        val server = TodoServerModel(base)
        server.seed(USER_A, todoRow(uuid(901), "A 서버 줄", base - 5_000, createdMs = base - 5_000))
        val transport = RecordingTransport.of(server)
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        val r = rig(transport, path = "/mem/todos.A.json")
        r.sync.activate(USER_A)
        runCurrent()
        // 계정을 비워 로그아웃 파일로 — 그 사이 도착한 앞 계정 응답은 '버림'으로 끝난다.
        r.sync.switchAccount(null, "/mem/todos.local.json")
        transport.gate = null
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(TodoSyncOutcome.discardedStale, r.sync.lastOutcome)
        assertEquals(emptyList(), r.list.items)
        assertEquals(1, transport.requests.size, "로그아웃 파일을 서버로 보냈다")
    }

    @Test
    fun signedOutFileNeverSyncs() = runTest {
        val transport = RecordingTransport { _, _ -> TodoSyncResponse(status = "ok", items = emptyList(), watermarkMs = 1, rejected = emptyList(), full = false) }
        val r = rig(transport)
        r.sync.activate(null)
        r.list.add("로그인 전에 적은 줄")
        r.scheduler.advance(1_000.0)
        r.sync.requestSync(TodoSyncReason.wake)
        assertTrue(!r.sync.isRunning && r.sync.runTask == null, "로그아웃 상태에서 동기화 작업을 만들었다")
        advanceUntilIdle()
        assertEquals(0, transport.requests.size)
        assertEquals(0, r.scheduler.liveCount, "로그아웃인데 주기·디바운스 예약이 남았다")
    }

    @Test
    fun accountSwitchStopsRemainingBatchesOfPreviousAccount() = runTest {
        val server = TodoServerModel(base)
        server.seed(USER_A, todoRow(uuid(902), "A 계정 서버 줄", base - 5_000, createdMs = base - 5_000))
        val transport = RecordingTransport.of(server)
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        val files = InMemoryTodoFileSystem()
        val fileA = "/mem/todos.A.json"
        val fileB = "/mem/todos.B.json"
        TodoFileStore.save(files, TodoFile(version = 1, items = (0 until 501).map { todoRow(uuid(it + 1), "A 줄 $it", base) }), fileA)
        TodoFileStore.save(files, TodoFile(items = emptyList(), sync = TodoFileSyncState(base - 1_000, emptyList())), fileB)
        val r = rig(transport, files, fileA)
        r.sync.activate(USER_A)
        runCurrent()
        r.sync.switchAccount(USER_B, fileB)
        transport.gate = null
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf(USER_A, USER_B), transport.requests.map { it.first }, "앞 계정의 두 번째 묶음이 나갔다")
        assertEquals(emptyList(), r.list.items, "앞 계정의 서버 줄이 새 계정 목록에 섞였다")
    }

    @Test
    fun pruneAfterMergeDropsPendingEvenIfEditedMeanwhile() = runTest {
        var nowMs = base
        lateinit var list: TodoListStore
        val transport = RecordingTransport { _, _ ->
            // 응답 전에 제목을 또 고쳤다 → 스냅숏 규칙으로는 pending 에 남는 항목. 그래도 정리되면 pending 에서 빠져야 한다.
            list.rename(list.items.first().id, "응답 전에 고친 제목")
            TodoSyncResponse(status = "ok", items = emptyList(), watermarkMs = nowMs, rejected = emptyList(), full = false)
        }
        val r = rig(transport, clock = { msDate(nowMs) })
        list = r.list
        val item = r.list.add("오프라인에서 끝낸 줄")!!
        r.list.toggleDone(item.id)
        assertEquals(setOf(item.id), r.list.pendingIDs)
        nowMs += 91L * 86_400_000
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(emptyList(), r.list.items)
        assertEquals(emptySet(), r.list.pendingIDs, "정리된 항목 id 가 pending 에 남았다")
        assertEquals(emptyList(), TodoFileStore.load(r.files, "/mem/todos.local.json").sync.pendingIDs)
    }

    @Test
    fun protectedRowsDeferMergeThenConvergeWhenProtectionEnds() = runTest {
        var nowMs = base
        val server = TodoServerModel(base)
        val r = rig(RecordingTransport.of(server), clock = { msDate(nowMs) })
        var protected = emptySet<String>()
        r.list.syncProtectedIDs = { protected }
        val editing = r.list.add("고치는 중인 줄")!!
        nowMs += 1
        val undoing = r.list.add("되돌리기 창의 줄")!!
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(1, r.transport.requests.size)
        assertEquals(emptySet(), r.list.pendingIDs)

        nowMs += 10_000
        server.nowMs = nowMs
        val deletedElsewhere = editing.copy(deletedAt = msDate(nowMs), updatedAt = msDate(nowMs))
        server.seed(USER_A, deletedElsewhere)
        val renamedElsewhere = undoing.copy(title = "다른 기기에서 바꾼 제목", updatedAt = msDate(nowMs))
        server.seed(USER_A, renamedElsewhere)

        protected = setOf(editing.id, undoing.id)
        r.sync.requestSync(TodoSyncReason.periodic)
        advanceUntilIdle()
        assertEquals(editing, r.list.items.first { it.id == editing.id }, "편집 중인 줄이 병합으로 바뀌었다")
        assertEquals(undoing, r.list.items.first { it.id == undoing.id })
        assertEquals(setOf(editing.id, undoing.id), r.list.pendingIDs)

        // 앞 줄의 보호가 끝났다 → 미룬 병합이 있으니 한 번 더 맞춘다(1.5초 디바운스).
        protected = setOf(undoing.id)
        r.list.syncProtectionDidEnd()
        r.scheduler.advance(TodoSync.debounceSeconds)
        advanceUntilIdle()
        assertEquals(3, r.transport.requests.size, "보호가 끝났는데 미룬 병합을 다시 맞추지 않았다")
        assertEquals(deletedElsewhere, r.list.items.first { it.id == editing.id })
        assertEquals(undoing, r.list.items.first { it.id == undoing.id }, "아직 보호 중인 줄이 병합으로 바뀌었다")
        assertEquals(setOf(undoing.id), r.list.pendingIDs)

        protected = emptySet()
        r.list.syncProtectionDidEnd()
        r.scheduler.advance(TodoSync.debounceSeconds)
        advanceUntilIdle()
        assertEquals(4, r.transport.requests.size)
        assertEquals(renamedElsewhere, r.list.items.first { it.id == undoing.id })
        assertEquals(emptySet(), r.list.pendingIDs)

        // 미룬 것이 없으면 보호 종료가 요청을 더 만들지 않는다.
        r.list.syncProtectionDidEnd()
        r.scheduler.advance(TodoSync.debounceSeconds)
        advanceUntilIdle()
        assertEquals(4, r.transport.requests.size)
    }

    @Test
    fun missingFunctionFoldsQuietlyWithCooldownForEditsAndBoardButNotPeriodic() = runTest {
        var nowMs = base
        val transport = RecordingTransport { _, _ -> throw TodoSyncTransportException(TodoSyncTransportException.Kind.functionMissing) }
        val r = rig(transport, clock = { msDate(nowMs) })
        val item = r.list.add("서버보다 앱이 먼저 나갔다")!!
        val before = r.files.text("/mem/todos.local.json")
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(TodoSyncOutcome.serverMissing, r.sync.lastOutcome)
        assertEquals(setOf(item.id), r.list.pendingIDs)
        assertEquals(before, r.files.text("/mem/todos.local.json"))
        assertEquals(1, transport.requests.size)

        nowMs += 60_000
        r.sync.noteLocalChange()
        r.scheduler.advance(2.0)
        r.sync.requestSync(TodoSyncReason.boardOpened)
        advanceUntilIdle()
        assertEquals(1, transport.requests.size, "쿨다운 중에 404 를 또 쳤다")

        r.sync.requestSync(TodoSyncReason.periodic)
        advanceUntilIdle()
        assertEquals(2, transport.requests.size, "주기 동기화까지 막혔다")

        nowMs += 301_000
        r.sync.requestSync(TodoSyncReason.boardOpened)
        advanceUntilIdle()
        assertEquals(3, transport.requests.size, "쿨다운(5분)이 지났는데 보드 열기가 다시 치지 않았다")
    }

    @Test
    fun accountMismatchIsAPlainFailure() = runTest {
        val transport = RecordingTransport { _, _ -> throw TodoSyncTransportException(TodoSyncTransportException.Kind.accountMismatch) }
        val r = rig(transport)
        r.list.add("전환 중")
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(TodoSyncOutcome.failed, r.sync.lastOutcome)
        r.sync.requestSync(TodoSyncReason.boardOpened)
        advanceUntilIdle()
        assertEquals(2, transport.requests.size, "계정 불일치를 함수 없음처럼 쿨다운에 넣었다")
    }

    @Test
    fun periodicRepeatsStartsAtLoginAndPreSwitchDebounceDoesNotFire() = runTest {
        val server = TodoServerModel(base)
        val files = InMemoryTodoFileSystem()
        val r = rig(RecordingTransport.of(server), files, "/mem/todos.local.json")
        r.sync.activate(null)
        advanceUntilIdle()
        r.scheduler.advance(TodoSync.periodicSeconds * 2)
        advanceUntilIdle()
        assertEquals(0, r.transport.requests.size, "로그아웃 상태에서 맞췄다")

        r.sync.switchAccount(USER_B, "/mem/todos.B.json")
        advanceUntilIdle()
        assertEquals(1, r.transport.requests.size, "로그인 직후 맞추지 않았다")
        for (tick in 1..3) {
            r.scheduler.advance(TodoSync.periodicSeconds)
            advanceUntilIdle()
            assertEquals(1 + tick, r.transport.requests.size, "로그인 뒤 ${tick}번째 5분에 맞추지 않았다")
        }

        // B 에서 막 고치고 0.5초 만에 A 로 전환 → 로그인 맞춤 한 번뿐.
        r.list.add("B 가 막 적은 줄")
        r.scheduler.advance(0.5)
        r.sync.switchAccount(USER_A, "/mem/todos.A.json")
        advanceUntilIdle()
        assertEquals(5, r.transport.requests.size)
        assertEquals(USER_A, r.transport.requests.last().first)
        r.scheduler.advance(TodoSync.debounceSeconds)
        advanceUntilIdle()
        assertEquals(5, r.transport.requests.size, "전환 전에 B 에서 걸린 디바운스가 A 로 한 번 더 쐈다")
        r.scheduler.advance(TodoSync.periodicSeconds)
        advanceUntilIdle()
        assertEquals(6, r.transport.requests.size)
        assertEquals(USER_A, r.transport.requests.last().first)
    }

    @Test
    fun heldRejectedEditSurvivesOverlapAndOtherDeviceUntilUserEditsAgain() = runTest {
        for (window in listOf("inside60s", "outside60s")) {
            var nowMs = base
            val server = TodoServerModel(nowMs)
            val files = InMemoryTodoFileSystem()
            val path = "/mem/todos.$window.json"
            val r = rig(RecordingTransport.of(server), files, path) { msDate(nowMs) }
            val x = r.list.add("올라간 줄")!!
            r.sync.activate(USER_A)
            advanceUntilIdle()
            assertEquals(listOf("올라간 줄"), server.items(USER_A).map { it.title })
            if (window == "outside60s") {
                nowMs += 61_000
                server.nowMs = nowMs
                r.sync.requestSync(TodoSyncReason.periodic)
                advanceUntilIdle()
            }
            nowMs += 1_000
            server.nowMs = nowMs
            // 파일에 "서버가 거절할 수정"을 적고 다시 읽는다(보낼 것에 넣는다 · watermark 그대로).
            val file = TodoFileStore.load(files, path)
            TodoFileStore.save(files, file.copy(
                items = file.items.map { if (it.id == x.id) it.copy(title = heavyTitle, updatedAt = msDate(nowMs)) else it },
                sync = file.sync.copy(pendingIDs = (file.sync.pendingIDs + x.id).distinct()),
            ), path)
            r.list.reload()
            assertEquals(setOf(x.id), r.list.pendingIDs)
            r.sync.requestSync(TodoSyncReason.periodic)
            advanceUntilIdle()
            assertEquals(listOf(x.id), r.transport.requests.last().second.changes.map { it.id }, "$window: 주입한 수정을 싣지 않았다(검사 공허)")
            assertEquals(heavyTitle, r.list.items.first { it.id == x.id }.title, "$window: 거절된 수정이 서버 옛 값으로 되돌아갔다")
            assertFalse(x.id in r.list.pendingIDs, "$window: 거절된 수정이 보낼 것에 남았다")
            assertEquals(setOf(x.id), r.list.heldRejectedIDs, window)
            assertEquals(listOf("올라간 줄"), server.items(USER_A).map { it.title }, "$window: 서버 모형이 넘친 제목을 받았다")

            nowMs += 1_000
            server.nowMs = nowMs
            r.sync.requestSync(TodoSyncReason.periodic)
            advanceUntilIdle()
            assertEquals(heavyTitle, r.list.items.first { it.id == x.id }.title, "$window: 두 번째 맞춤에서 되돌아갔다")
            val reread = TodoListStore(path, files, clock = { msDate(nowMs) })
            assertEquals(setOf(x.id), reread.heldRejectedIDs, "$window: 붙잡기가 파일에 안 실렸다")

            // 다른 기기가 더 나중에 고쳤다 → 붙잡힌 동안은 덮지 않는다.
            nowMs += 5_000
            server.nowMs = nowMs
            server.seed(USER_A, server.items(USER_A).first().copy(title = "다른 기기가 고친 줄", updatedAt = msDate(nowMs)))
            r.sync.requestSync(TodoSyncReason.periodic)
            advanceUntilIdle()
            assertEquals(heavyTitle, r.list.items.first { it.id == x.id }.title, "$window: 붙잡힌 줄이 다른 기기 행에 덮였다")

            // 사용자가 다시 고친다 → 풀려서 서버 LWW 로 수렴.
            nowMs += 1_000
            server.nowMs = nowMs
            r.list.rename(x.id, "사용자가 다시 고친 줄")
            assertTrue(r.list.heldRejectedIDs.isEmpty() && r.list.pendingIDs == setOf(x.id), "$window: 다시 고쳤는데 붙잡기가 안 풀렸다")
            r.sync.requestSync(TodoSyncReason.edit)
            advanceUntilIdle()
            assertTrue(r.list.pendingIDs.isEmpty() && r.list.heldRejectedIDs.isEmpty())
            assertEquals(server.items(USER_A), r.list.items.sortedBy { it.id.uppercase() }, "$window: 풀린 뒤 서버와 갈렸다")
            assertEquals("사용자가 다시 고친 줄", server.items(USER_A).first().title)
        }
    }

    @Test
    fun quotaRejectedNewItemSurvivesFullSyncAndUploadsAfterReEdit() = runTest {
        var nowMs = base
        val server = TodoServerModel(nowMs)
        server.quota = 1
        val r = rig(RecordingTransport.of(server)) { msDate(nowMs) }
        val first = r.list.add("첫 줄")!!
        r.sync.activate(USER_A)
        advanceUntilIdle()
        assertEquals(listOf(first.id), server.items(USER_A).map { it.id })

        nowMs += 1_000
        server.nowMs = nowMs
        val over = r.list.add("quota 에 걸린 새 줄")!!
        r.sync.requestSync(TodoSyncReason.edit)
        advanceUntilIdle()
        assertTrue(r.list.items.any { it.id == over.id })
        assertFalse(over.id in r.list.pendingIDs)
        assertEquals(listOf(first.id), server.items(USER_A).map { it.id }, "서버 모형이 quota 를 안 걸었다(검사 공허)")

        nowMs += 81L * 86_400_000
        server.nowMs = nowMs
        r.sync.requestSync(TodoSyncReason.periodic)
        advanceUntilIdle()
        assertEquals(TodoSyncOutcome.synced, r.sync.lastOutcome)
        assertTrue(r.transport.requests.last().second.sinceMs!! < nowMs - 80L * 86_400_000, "full 조건이 아니다(검사 공허)")
        assertTrue(r.list.items.any { it.id == over.id }, "거절돼 로컬에만 남긴 새 줄이 full 동기화에서 조용히 지워졌다")
        assertTrue(r.list.items.any { it.id == first.id })
        assertEquals(setOf(over.id), r.list.heldRejectedIDs)

        server.quota = 5000
        nowMs += 1_000
        server.nowMs = nowMs
        r.list.toggleDone(over.id)
        assertTrue(r.list.heldRejectedIDs.isEmpty() && r.list.pendingIDs == setOf(over.id))
        r.sync.requestSync(TodoSyncReason.edit)
        advanceUntilIdle()
        assertTrue(server.items(USER_A).any { it.id == over.id && it.isDone }, "다시 고친 줄이 올라가지 않았다")
        assertTrue(r.list.pendingIDs.isEmpty() && r.list.heldRejectedIDs.isEmpty())
    }

    @Test
    fun heldStateFollowsAccountFileAndLateRejectionDoesNotLeak() = runTest {
        val files = InMemoryTodoFileSystem()
        val fileA = "/mem/todos.A.json"
        val fileB = "/mem/todos.B.json"
        val bItem = todoRow(uuid(700), "B 계정의 붙잡힌 줄", base + 1)
        TodoFileStore.save(files, TodoFile(items = listOf(bItem), sync = TodoFileSyncState(base, emptyList(), listOf(bItem.id))), fileB)
        val bBefore = files.text(fileB)
        val server = TodoServerModel(base)
        server.quota = 0
        val transport = RecordingTransport.of(server)
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        val r = rig(transport, files, fileA)
        val aItem = r.list.add("A 에서 거절될 줄")!!
        r.sync.activate(USER_A)
        runCurrent()
        r.sync.switchAccount(USER_B, fileB)
        assertEquals(setOf(bItem.id), r.list.heldRejectedIDs, "새 계정 파일의 붙잡기를 읽지 않았다")
        transport.gate = null
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(setOf(bItem.id), r.list.heldRejectedIDs, "앞 계정 응답의 거절이 새 계정 붙잡기에 섞였다")
        val aDisk = TodoFileStore.load(files, fileA)
        assertEquals(listOf(aItem.id), aDisk.sync.pendingIDs)
        assertEquals(emptyList(), aDisk.sync.heldRejectedIDs, "버려진 응답이 앞 계정 파일을 바꿨다")
        // B 파일은 B 의 동기화로만 바뀐다(B 응답이 붙잡힌 줄을 그대로 두는지 — 서버엔 그 줄이 없다).
        assertTrue(r.list.items.any { it.id == bItem.id }, "B 의 붙잡힌 줄이 full 응답에 지워졌다")
        assertTrue(bBefore != null)
    }

    @Test
    fun coroutineSchedulerFiresOnceAndCancelledNeverFires() = runTest {
        val scheduler = TodoSyncCoroutineScheduler(this)
        var fired = 0
        scheduler.schedule(1.5) { fired += 1 }
        val cancelled = scheduler.schedule(1.0) { fired += 100 }
        cancelled.cancel()
        testScheduler.advanceTimeBy(1_400)
        runCurrent()
        assertEquals(0, fired)
        testScheduler.advanceTimeBy(200)
        runCurrent()
        assertEquals(1, fired, "기다렸다가 한 번 쏘지 않았다")
        testScheduler.advanceTimeBy(10_000)
        runCurrent()
        assertEquals(1, fired, "취소한 예약이 쐈다")
        assertContentEquals(listOf(1), listOf(fired))
    }

    @Test
    fun rulesConstantsMatchSwift() {
        assertEquals(1.5, TodoSync.debounceSeconds)
        assertEquals(300.0, TodoSync.periodicSeconds)
        assertEquals(5.0, TodoRules.undoSeconds)
    }
}
