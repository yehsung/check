// 원본: Tests/CheckMobileKitTests/NowStoreTests.swift:392-440 · 528-762(할 일 — 편집 · 동기화 · 보호 · background · 위젯이 고친 파일 다시 읽기 ·
//       계정 전환 · 전송 가드 · 세대 가드 · 미리보기) @ 1b8260d
// 위젯의 체크(`WidgetTodoToggle` — W2-f)는 아직 없다: 위젯이 하는 일(같은 파일을 읽고-고치고-쓰기)을 파일에 직접 흉내 낸다.
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.stores.now.NowRig.Companion.nowRig
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncTransportException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class NowTodoStoreTest {
    private val me = StoreHarness.ME

    private fun JsonObject.isNumber(key: String): Boolean = this[key].let { it is JsonPrimitive && it !is JsonNull && it.longOrNull != null }

    @Test
    fun editsLandInFileAndSyncAfterDebounce() = runTest {
        val rig = nowRig()
        val (store, server) = rig.store to rig.server
        rig.activate()
        val path = rig.storage.todoFilePath(me)
        assertEquals(path, store.todos.filePath)
        assertTrue(store.canEditTodos)
        val firstSyncs = server.todo.calls
        assertEquals(1, firstSyncs, "active 진입에 한 번 맞춘다")

        assertTrue(store.addTodo("  회고   쓰기 "))
        assertFalse(store.addTodo("   "), "빈 제목은 거절")
        assertFalse(store.addTodo("가".repeat(101)), "100자 초과는 잘라 넣지 않고 거절")
        val item = store.todos.items.first()
        assertEquals("회고 쓰기", item.title)
        store.toggleTodo(item.id)
        assertTrue(item.id in store.todos.pendingIDs)
        val file = TodoFileStore.load(rig.files, path)
        assertTrue(file.items.first().completedAt != null && item.id in file.sync.pendingIDs, "변경은 곧바로 파일에")

        assertEquals(firstSyncs, server.todo.calls, "디바운스 전에는 보내지 않는다")
        rig.scheduler.advance(1.49)
        rig.settle()
        assertEquals(firstSyncs, server.todo.calls)
        rig.scheduler.advance(0.01)
        rig.settle()
        assertEquals(firstSyncs + 1, server.todo.calls)
        assertEquals(listOf(item.id), server.todo.changeIDs)
        assertEquals(emptySet(), store.todos.pendingIDs)

        val preview = store.widgetTodoPreviewRows()!!.first()
        assertEquals(item.id, preview.id)
        assertEquals("회고 쓰기", preview.title)
        assertTrue(preview.isDone)

        // 수정
        store.beginEditing(item.id)
        assertEquals(item.id, store.editingTodoID)
        store.commitEditing(item.id, "주간 회고 쓰기")
        assertNull(store.editingTodoID)
        assertEquals("주간 회고 쓰기", store.todos.items.first().title)

        // 삭제 → 5초 되돌리기
        store.deleteTodo(item.id)
        assertEquals(item.id, store.undoTodoID)
        assertEquals(emptyList(), store.todoRows().main, "지운 줄은 곧바로 목록에서 빠진다")
        store.undoDelete()
        assertNull(store.undoTodoID)
        assertEquals(listOf(item.id), store.todoRows().main.map { it.id })
        store.deleteTodo(item.id)
        rig.scheduler.advance(4.9)
        assertEquals(item.id, store.undoTodoID)
        rig.scheduler.advance(0.2)
        assertNull(store.undoTodoID, "5초 뒤 토스트가 닫힌다")
        rig.settle()
        assertTrue(server.todo.row(item.id)!!.isNumber("deleted_at_ms"), "삭제 톰스톤이 서버에 올라갔다")
        rig.h.assertClean()
    }

    @Test
    fun editingRowIsProtectedThenConverges() = runTest {
        val rig = nowRig()
        val (store, server) = rig.store to rig.server
        rig.activate()
        assertTrue(store.addTodo("원래 제목"))
        rig.scheduler.advance(1.5)
        rig.settle()
        val item = store.todos.items.first()

        // 다른 기기가 제목을 바꿨다(서버 행이 더 새롭다).
        val remote = server.todo.row(item.id)!!
        server.todo.seed(JsonObject(remote + mapOf("title" to JsonPrimitive("다른 기기 제목"), "updated_at_ms" to JsonPrimitive(item.updatedAtMs + 10_000))))

        store.beginEditing(item.id)
        store.todoSync.requestSync(com.yehsung.aingcheck.core.stores.now.todo.TodoSyncReason.periodic)
        rig.settle()
        assertEquals("원래 제목", store.todos.items.first().title, "편집 중인 줄을 덮었다")
        assertTrue(item.id in store.todos.pendingIDs)
        store.cancelEditing()
        rig.scheduler.advance(1.5)
        rig.settle()
        assertEquals("다른 기기 제목", store.todos.items.first().title, "보호가 끝나면 서버 값으로 수렴")
        rig.h.assertClean()
    }

    @Test
    fun backgroundFlushesPendingAndPausesTimersUntilActive() = runTest {
        val rig = nowRig()
        val (store, server) = rig.store to rig.server
        rig.activate()
        val refreshes = store.refreshCount
        rig.scheduler.advance(60.0)
        rig.settle()
        assertEquals(refreshes + 1, store.refreshCount, "active 동안은 60초마다 새로고침")

        assertTrue(store.addTodo("잠그기 직전"))
        val syncs = server.todo.calls
        store.appDidEnterBackground()
        rig.settle()
        assertEquals(syncs + 1, server.todo.calls, "background 직전의 변경은 1.5초를 기다리지 않고 보낸다")
        assertEquals(emptySet(), store.todos.pendingIDs)
        assertTrue(store.todoScheduler.isPaused)

        val pausedRefreshes = store.refreshCount
        val pausedSyncs = server.todo.calls
        rig.scheduler.advance(900.0)
        rig.settle()
        assertEquals(pausedRefreshes, store.refreshCount, "background 에서 새로고침이 돌았다")
        assertEquals(pausedSyncs, server.todo.calls, "background 에서 주기 동기화가 돌았다")
        assertTrue(store.todoScheduler.droppedCount > 0, "멈춘 동안 깨어난 주기 예약을 버리지 않았다")

        store.appDidBecomeActive()
        rig.settle()
        assertFalse(store.todoScheduler.isPaused)
        assertEquals(pausedRefreshes + 1, store.refreshCount)
        assertEquals(pausedSyncs + 1, server.todo.calls)
        rig.scheduler.advance(300.0)
        rig.settle()
        assertTrue(server.todo.calls >= pausedSyncs + 2, "active 로 돌아오면 5분 주기가 다시 걸린다")
        rig.h.assertClean()
    }

    @Test
    fun activeReloadsFileTheWidgetChanged() = runTest {
        val rig = nowRig()
        val (store, server) = rig.store to rig.server
        rig.activate()
        assertTrue(store.addTodo("위젯에서 체크할 일"))
        rig.scheduler.advance(1.5)
        rig.settle()
        val item = store.todos.items.first()
        store.appDidEnterBackground()
        rig.settle()

        // 위젯 동작(같은 프로세스의 다른 스레드)이 같은 조정 구간에서 파일을 읽고-고치고-쓴다.
        val path = rig.storage.todoFilePath(me)
        NowTodoFileAccess.coordinated(path) {
            val file = TodoFileStore.load(rig.files, path)
            val now = TodoRules.normalizedTime(rig.h.now().timeIntervalSince1970 + 60)
            val toggled = file.items.map { if (it.id == item.id) it.copy(completedAt = now, updatedAt = now) else it }
            TodoFileStore.save(rig.files, file.copy(items = toggled, sync = file.sync.copy(pendingIDs = file.sync.pendingIDs + item.id)), path)
        }
        assertEquals(false, store.todos.items.first().isDone, "아직 앱 메모리는 옛 값")

        store.appDidBecomeActive()
        assertEquals(true, store.todos.items.first().isDone, "active 진입에 파일을 다시 읽었다")
        assertTrue(item.id in store.todos.pendingIDs)
        rig.settle()
        assertTrue(server.todo.row(item.id)!!.isNumber("completed_at_ms"), "위젯 체크가 앱 동기화로 올라갔다")
        rig.h.assertClean()
    }

    @Test
    fun accountSwitchStopsSyncClearsListAndDropsLateResponse() = runTest {
        val rig = nowRig()
        val (h, store, server) = Triple(rig.h, rig.store, rig.server)
        rig.activate()
        assertTrue(store.addTodo("앞 계정 할 일"))
        val gate = CompletableDeferred<Unit>()
        server.todoGate = gate
        store.todoSync.requestSync(com.yehsung.aingcheck.core.stores.now.todo.TodoSyncReason.periodic)
        runCurrent()
        val lateRun = store.todoSync.runTask!!

        h.session.signOut()
        store.reset()
        assertEquals(emptyList(), store.todos.items, "앞 계정 목록이 메모리에 남았다")
        assertFalse(store.canEditTodos)
        assertFalse(store.addTodo("로그아웃 중"))
        assertNull(store.todoSync.userID)
        server.todoGate = null
        gate.complete(Unit)
        lateRun.join()
        rig.settle()
        assertEquals(emptyList(), store.todos.items, "앞 계정의 늦은 응답이 들어왔다")
        val firstFile = TodoFileStore.load(rig.files, rig.storage.todoFilePath(me))
        assertEquals(listOf("앞 계정 할 일"), firstFile.items.map { it.title }, "로그아웃은 파일을 지우지 않는다")

        h.signInAs("u-other")
        store.appDidBecomeActive()
        rig.settle()
        assertEquals(rig.storage.todoFilePath("u-other"), store.todos.filePath)
        assertEquals("u-other", store.todoSync.userID)
        // 새 계정 파일로 맞췄다(가짜 서버는 계정을 가르지 않아 목록 내용은 재지 않는다 — Swift 시험과 같다).
        assertTrue(rig.files.contents.containsKey(rig.storage.todoFilePath("u-other")), "새 계정 파일을 쓰지 않았다")
        h.assertClean()
    }

    @Test
    fun transportGuardsAccountRefreshesOnUnauthorizedAndFoldsMissingFunction() = runTest {
        val rig = nowRig()
        val (h, server) = rig.h to rig.server
        val transport = NowTodoSyncTransport(h.context)
        val request = TodoSyncRequest(emptyList(), null)

        val mismatch = assertFailsWith<TodoSyncTransportException> { transport.todoSync("u-someone-else", request) }
        assertEquals(TodoSyncTransportException.Kind.accountMismatch, mismatch.kind)
        assertEquals(0, server.todo.calls, "다른 계정 요청을 지금 세션 토큰으로 보냈다")

        transport.todoSync(me, request)
        assertEquals(1, server.todo.calls)

        // 200 {"status":"unauthorized"} → 조정자 경유 갱신 → 새 토큰으로 한 번 더.
        val fresh = h.jwt(me, "fresh")
        h.tokenReply = Reply.Json("""{"access_token":"$fresh","refresh_token":"refresh-2","user":{"id":"$me"}}""")
        server.todo.failure = Reply.Json("""{"status":"unauthorized"}""")
        val before = server.todo.calls
        runCatching { transport.todoSync(me, request) }
        assertEquals(before + 2, server.todo.calls, "unauthorized 뒤 갱신·재시도가 없었다")
        assertEquals(1, h.storeRequests.count { it.path == "/auth/v1/token" })
        assertEquals(fresh, h.session.session?.accessToken)

        server.todo.failure = Reply.missingFunction
        val missing = assertFailsWith<TodoSyncTransportException> { transport.todoSync(me, request) }
        assertEquals(TodoSyncTransportException.Kind.functionMissing, missing.kind)

        server.todo.failure = null
        h.session.signOut()
        val afterSignOut = server.todo.calls
        val signedOut = assertFailsWith<TodoSyncTransportException> { transport.todoSync(me, request) }
        assertEquals(TodoSyncTransportException.Kind.accountMismatch, signedOut.kind)
        assertEquals(afterSignOut, server.todo.calls)
        h.assertClean()
    }

    @Test
    fun transportDropsResponseAcrossGenerationsEvenForSameAccount() = runTest {
        val rig = nowRig()
        val (h, server) = rig.h to rig.server
        val transport = NowTodoSyncTransport(h.context)
        val gate = CompletableDeferred<Unit>()
        server.todoGate = gate
        val call = async { runCatching { transport.todoSync(me, TodoSyncRequest(emptyList(), null)) } }
        runCurrent()
        assertEquals(1, server.todo.calls)
        h.session.signOut()
        h.signInAs(me, idle = false)
        server.todoGate = null
        gate.complete(Unit)
        val result = call.await()
        val error = result.exceptionOrNull() as? TodoSyncTransportException
        assertEquals(TodoSyncTransportException.Kind.accountMismatch, error?.kind, "앞 세대의 응답을 돌려줬다: $result")
        rig.settle()
        h.assertClean()
    }

    @Test
    fun backgroundClosesUndoWindowButKeepsTheDelete() = runTest {
        val rig = nowRig()
        val store = rig.store
        rig.activate()
        assertTrue(store.addTodo("지울 일"))
        val item = store.todos.items.first()
        store.deleteTodo(item.id)
        assertEquals(item.id, store.undoTodoID)
        store.appDidEnterBackground()
        assertNull(store.undoTodoID, "돌아왔을 때 몇 시간 지난 되돌리기 토스트가 남는다")
        assertEquals(emptyList(), store.todoRows().main)
        assertNotNull(store.todos.items.first().deletedAt, "삭제는 파일에 남는다")
        rig.settle()
        rig.h.assertClean()
    }

    @Test
    fun widgetPreviewNeedsCurrentAccountFile() = runTest {
        val rig = nowRig()
        val (h, store) = rig.h to rig.store
        rig.activate()
        h.session.signOut()
        store.reset()
        store.todos.add("로그아웃 파일의 줄")   // todos.local.json
        h.signInAs("u-other")
        assertTrue(store.todoSync.userID == null && h.session.isSignedIn)
        assertNull(store.widgetTodoPreviewRows(), "로그아웃 파일의 할 일이 새 계정 위젯에 샜다")
        // 대조: active 로 그 계정 파일을 열면 미리보기가 선다(그 파일엔 로그아웃 줄이 없다).
        store.appDidBecomeActive()
        rig.settle()
        assertEquals(emptyList(), store.widgetTodoPreviewRows())
        h.assertClean()
    }

    /** 오늘 목록과 '오래된 항목'(7일 넘게 이월된 미완료) · 남은 개수 · 이월 배지(Swift `todoRows` · `remainingTodoCount`). */
    @Test
    fun todoRowsSplitOldItemsAndCountRemaining() = runTest {
        val rig = nowRig()
        val (h, store) = rig.h to rig.store
        val now = TodoRules.normalizedTime(h.now().timeIntervalSince1970)
        val day = 86_400.0
        fun item(id: String, title: String, ageDays: Int, done: Boolean = false) = TodoItem(
            id, title, now - ageDays * day, now - ageDays * day, if (done) now else null, null, TodoRules.dayKey(now - ageDays * day),
        )
        val seeded = listOf(
            item("00000000-0000-4000-8000-000000000001", "오늘 적은 일", 0),
            item("00000000-0000-4000-8000-000000000002", "어제 적은 일", 1),
            item("00000000-0000-4000-8000-000000000003", "8일 전 적은 일", 8),
            item("00000000-0000-4000-8000-000000000004", "오늘 끝낸 일", 2, done = true),
        )
        // 전부 보낼 것으로 둔다(서버에 없는 줄을 full 병합이 지우지 않게 — 첫 동기화가 올린다).
        TodoFileStore.save(rig.files, TodoFile(items = seeded), rig.storage.todoFilePath(me))
        rig.activate()
        val rows = store.todoRows()
        assertEquals(listOf("오늘 적은 일", "어제 적은 일", "오늘 끝낸 일"), rows.main.map { it.title }, "미완료(최신 먼저) → 완료")
        assertEquals(listOf(null, "어제", "2일 전"), rows.main.map { it.carryBadge })
        assertEquals(listOf("8일 전 적은 일"), rows.old.map { it.title })
        assertEquals("8일 전", rows.old.single().carryBadge)
        assertEquals(8, rows.old.single().carryOverDays)
        assertEquals(3, store.remainingTodoCount)
        assertEquals(4, store.widgetTodoPreviewRows()!!.size, "미리보기는 오늘 목록 + 오래된 항목")
        h.assertClean()
    }
}
