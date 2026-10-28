// 원본: Tests/CheckMobileKitTests/BaseWidgetSnapshotTests.swift @ 3bd04bd (위젯 체크 — 파일 조정 → 스냅숏 → todo_sync 1회 · 토큰 60초 · 갱신 없음 · 병합)
//
// ③ 위젯 체크 순서(G §2-3 W3-b): ① 조정 구간에서 파일 뒤집기 → ② 스냅숏 그 줄 → ③ `todo_sync` **한 번**(토큰 60초 이상일 때만, 재시도·갱신 없음)
// → ④ 응답을 그 순간 파일에 병합. 사건 기록기 하나에 파일 쓰기 · 스냅숏 고치기 · 전송을 차례로 적어 순서를 그대로 잰다.
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResponse
import com.yehsung.aingcheck.core.rules.todo.TodoSyncWireItem
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class WidgetTodoToggleTest {
    private val user = "d0000000-0000-4000-8000-000000000001"
    private val todoA = "0a000000-0000-4000-8000-00000000000a"
    private val todoB = "0b000000-0000-4000-8000-00000000000b"

    /** 2026-09-17 14:05 KST(데모 시각). */
    private val now = 1_789_621_500.0
    private val events = mutableListOf<String>()

    private inner class RecordingFiles : TodoFileSystem {
        val data = HashMap<String, ByteArray>()
        override fun read(path: String): ByteArray? = data[path]
        override fun writeAtomically(path: String, bytes: ByteArray) {
            events += "file:write"
            data[path] = bytes
        }
        override fun move(from: String, to: String) {
            data.remove(from)?.let { data[to] = it }
        }
    }

    private class Prefs(userID: String?) : KeyValueStore {
        val values = HashMap<String, Any>().apply { if (userID != null) put(SessionPrefsKeys.userID, userID) }
        override fun getString(key: String): String? = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String): Long? = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }

    /** 읽은 칸을 적는 금고 — 위젯은 refresh token 을 읽지도 않는다. */
    private class RecordingVault(access: String?) : TokenVault {
        val reads = mutableListOf<String>()
        private val values = HashMap<String, String>().apply {
            if (access != null) put(SessionVaultKeys.accessToken, access)
            put(SessionVaultKeys.refreshToken, "refresh-secret")
        }
        override fun read(key: String): String? = values[key].also { reads += key }
        override fun write(value: String, key: String) { values[key] = value }
        override fun delete(key: String) { values.remove(key) }
    }

    private fun jwt(expiresIn: Double): String {
        val payload = """{"sub":"$user","exp":${(now + expiresIn).toLong()}}"""
        return "hdr." + Base64.getUrlEncoder().withoutPadding().encodeToString(payload.toByteArray()) + ".sig"
    }

    private fun item(id: String, done: Boolean = false) = TodoItem(
        id = id, title = "할 일 $id".take(12), createdAt = now - 3_600, updatedAt = now - 3_600,
        completedAt = if (done) now - 60 else null, deletedAt = null, originDayKey = "2026-09-17",
    )

    private class Fixture(val shared: AndroidWidgetSharedData, val files: TodoFileSystem, val vault: RecordingVault, val path: String)

    private fun fixture(userID: String? = user, access: String? = jwt(3_600.0)): Fixture {
        val files = RecordingFiles()
        val storage = NowTodoStorage("/app/todos", files)
        val path = storage.todoFilePath(user)
        // 앱이 남긴 파일(2세대 · 보낼 것 없음). 시험 준비 쓰기는 사건에서 뺀다.
        TodoFileStore.save(files, TodoFile(items = listOf(item(todoA), item(todoB)), sync = com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState(500L, emptyList())), path)
        events.clear()
        val vault = RecordingVault(access)
        val shared = AndroidWidgetSharedData(Prefs(userID), vault, storage) { id, done -> events += "snapshot:$id=$done" }
        return Fixture(shared, files, vault, path)
    }

    /** 보낸 변경을 그대로 돌려주는 서버(병합 가능). */
    private fun echoServer(calls: MutableList<TodoSyncRequest>) = WidgetTodoToggle.Sync { token, request ->
        events += "sync"
        calls += request
        assertTrue("위젯은 금고의 access token 을 그대로 싣는다", token.startsWith("hdr."))
        TodoSyncResponse(status = "ok", items = request.changes, watermarkMs = 900L, rejected = emptyList(), full = false)
    }

    @Test
    fun orderIsFileThenSnapshotThenOneSyncThenMerge() = runBlocking {
        val f = fixture()
        val calls = mutableListOf<TodoSyncRequest>()
        val outcome = WidgetTodoToggle.run(todoA.uppercase(), f.shared, { now }, echoServer(calls))
        assertEquals(WidgetTodoToggle.Outcome.Synced, outcome)
        assertEquals(listOf("file:write", "snapshot:$todoA=true", "sync", "file:write"), events)
        assertEquals(1, calls.size)
        assertEquals("보낼 것은 뒤집은 줄 하나(파일에 쌓인 pending 전부)", listOf(todoA), calls.single().changes.map { it.id })
        val saved = TodoFileStore.load(f.files, f.path)
        assertTrue("완료가 파일에 남는다", saved.items.single { it.id == todoA }.isDone)
        assertEquals("병합 뒤 보낼 것이 비었다", emptyList<String>(), saved.sync.pendingIDs)
        assertEquals(900L, saved.sync.watermarkMs)
        assertEquals("위젯은 refresh token 을 읽지 않는다", listOf(SessionVaultKeys.accessToken), f.vault.reads.distinct())
    }

    @Test
    fun tokenExpiringWithinSixtySecondsSkipsSyncAndKeepsPending() = runBlocking {
        val f = fixture(access = jwt(30.0))
        val calls = mutableListOf<TodoSyncRequest>()
        val outcome = WidgetTodoToggle.run(todoA, f.shared, { now }, echoServer(calls))
        assertEquals(WidgetTodoToggle.Outcome.SavedLocally(WidgetTodoToggle.SkipReason.TokenUnusable), outcome)
        assertEquals(listOf("file:write", "snapshot:$todoA=true"), events)
        assertEquals("앱이 active 가 될 때 올린다", listOf(todoA), TodoFileStore.load(f.files, f.path).sync.pendingIDs)
        // 기준선: 60초 남은 토큰은 쓴다(경계 포함).
        events.clear()
        val g = fixture(access = jwt(60.0))
        assertEquals(WidgetTodoToggle.Outcome.Synced, WidgetTodoToggle.run(todoB, g.shared, { now }, echoServer(mutableListOf())))
    }

    @Test
    fun failureIsNotRetriedAndUnauthorizedIsNotRefreshed() = runBlocking {
        var attempts = 0
        val failing = WidgetTodoToggle.Sync { _, _ ->
            events += "sync"
            attempts += 1
            throw SupabaseWorkServiceError.SessionExpired
        }
        val f = fixture()
        val outcome = WidgetTodoToggle.run(todoA, f.shared, { now }, failing)
        assertEquals(WidgetTodoToggle.Outcome.SavedLocally(WidgetTodoToggle.SkipReason.Failed), outcome)
        assertEquals("401 이어도 갱신·재시도 없이 한 번", 1, attempts)
        assertEquals("실패면 병합 쓰기가 없다", listOf("file:write", "snapshot:$todoA=true", "sync"), events)
        assertEquals(listOf(todoA), TodoFileStore.load(f.files, f.path).sync.pendingIDs)

        val missing = WidgetTodoToggle.Sync { _, _ -> throw SupabaseWorkServiceError.InvalidResponse(404) }
        assertEquals(
            WidgetTodoToggle.Outcome.SavedLocally(WidgetTodoToggle.SkipReason.ServerMissing),
            WidgetTodoToggle.run(todoB, fixture().shared, { now }, missing),
        )
        val refused = WidgetTodoToggle.Sync { _, _ -> TodoSyncResponse(status = "unauthorized") }
        assertEquals(
            WidgetTodoToggle.Outcome.SavedLocally(WidgetTodoToggle.SkipReason.Refused("unauthorized")),
            WidgetTodoToggle.run(todoB, fixture().shared, { now }, refused),
        )
    }

    @Test
    fun signedOutOrUnknownIdTouchesNothing() = runBlocking {
        val calls = mutableListOf<TodoSyncRequest>()
        val out = fixture(userID = null)
        assertEquals(WidgetTodoToggle.Outcome.SignedOut, WidgetTodoToggle.run(todoA, out.shared, { now }, echoServer(calls)))
        assertEquals(emptyList<String>(), events)
        val f = fixture()
        assertEquals(WidgetTodoToggle.Outcome.NotFound, WidgetTodoToggle.run("0c000000-0000-4000-8000-00000000000c", f.shared, { now }, echoServer(calls)))
        assertEquals(WidgetTodoToggle.Outcome.NotFound, WidgetTodoToggle.run("not-a-uuid", f.shared, { now }, echoServer(calls)))
        assertEquals("목록에 없는 id 는 파일·스냅숏·전송 0", emptyList<String>(), events)
        assertEquals(0, calls.size)
        assertFalse(TodoFileStore.load(f.files, f.path).items.any { it.isDone })
    }

    /** 이미 끝난 줄을 다시 누르면 완료 취소 — 스냅숏에도 false 로 간다. */
    @Test
    fun toggleBackSendsUndone() = runBlocking {
        val files = RecordingFiles()
        val storage = NowTodoStorage("/app/todos", files)
        val path = storage.todoFilePath(user)
        TodoFileStore.save(files, TodoFile(items = listOf(item(todoA, done = true))), path)
        events.clear()
        val shared = AndroidWidgetSharedData(Prefs(user), RecordingVault(jwt(3_600.0)), storage) { id, done -> events += "snapshot:$id=$done" }
        val calls = mutableListOf<TodoSyncRequest>()
        WidgetTodoToggle.run(todoA, shared, { now }, echoServer(calls))
        assertEquals("snapshot:$todoA=false", events[1])
        assertEquals(null, calls.single().changes.single { it.id == todoA }.completedAtMs)
        assertEquals(TodoSyncWireItem::class, calls.single().changes.first()::class)
    }
}
