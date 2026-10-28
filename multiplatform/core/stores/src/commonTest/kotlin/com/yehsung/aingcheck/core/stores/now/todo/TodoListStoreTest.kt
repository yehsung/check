// 원본: Tests/checkTests/CheckTodoModelTests.swift:201-473(스토어 상태 전이 · 정리 · 파일 저장소) ·
//       V0330TodoFileTimeTests.swift:79-308(ms 격자 · 단조 증가 · 파일 세대) · V0330TodoHeldRejectTests.swift:313-438(붙잡기 파일·해제·정리) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now.todo

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.stores.now.InMemoryTodoFileSystem
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TodoListStoreTest {
    private val path = "/mem/aing/todos.local.json"

    @Test
    fun addRejectsOverLimitAndBlankWithoutTruncating() {
        val now = kst(2026, 8, 12, 9, 0)
        val store = memoryList(clock = { now })
        assertEquals(100, store.add("가".repeat(100))?.title?.length)
        assertEquals(1, store.items.size)
        assertNull(store.add("가".repeat(101)))
        assertEquals(1, store.items.size, "잘려서 들어간 항목이 있다")
        assertNull(store.add(""))
        assertNull(store.add("    "))
        assertNull(store.add("\n\t "))
        assertEquals(1, store.items.size)
    }

    @Test
    fun addPutsNewestFirstStampsOriginDayAndNormalizes() {
        var now = kst(2026, 8, 12, 9, 0)
        val store = memoryList(clock = { now })
        store.add("먼저 적은 일")
        now = kst(2026, 8, 12, 10, 0)
        store.add("  나중에   적은 일 ")
        assertEquals(listOf("나중에 적은 일", "먼저 적은 일"), store.items.map { it.title })
        assertTrue(store.items.all { it.originDayKey == "20260812" })
        assertEquals("20260812", store.todayKey)
        assertEquals(store.items.map { it.id }.toSet(), store.pendingIDs, "새 줄은 곧바로 보낼 것이다")
    }

    @Test
    fun toggleDoneRoundTripKeepsOriginDayKey() {
        var now = kst(2026, 8, 11, 15, 0)
        val store = memoryList(clock = { now })
        val item = store.add("어제 적은 일")!!
        now = kst(2026, 8, 12, 11, 0)
        store.toggleDone(item.id)
        assertTrue(store.items[0].isDone)
        assertEquals(now, store.items[0].completedAt)
        assertEquals("20260811", store.items[0].originDayKey)
        now = kst(2026, 8, 12, 11, 30)
        store.toggleDone(item.id)
        assertFalse(store.items[0].isDone)
        assertNull(store.items[0].completedAt)
        assertEquals("20260811", store.items[0].originDayKey)
        val days = TodoRules.carriedDays(store.items[0].originDayKey, store.todayKey)
        assertEquals("어제", TodoRules.carryBadge(days))
    }

    @Test
    fun deleteIsTombstoneAndUndoRestoresEverything() {
        var now = kst(2026, 8, 12, 9, 0)
        val store = memoryList(clock = { now })
        val item = store.add("지웠다 되살릴 일")!!
        store.toggleDone(item.id)
        val completedAt = store.items[0].completedAt
        now = kst(2026, 8, 12, 9, 5)
        store.delete(item.id)
        assertEquals(1, store.items.size, "물리 삭제가 아니다")
        assertEquals(now, store.items[0].deletedAt)
        assertEquals(emptyList(), TodoRules.visible(store.items, store.todayKey))
        now = kst(2026, 8, 12, 9, 8)
        store.undoDelete(item.id)
        assertNull(store.items[0].deletedAt)
        assertEquals(item.id, store.items[0].id)
        assertEquals("지웠다 되살릴 일", store.items[0].title)
        assertEquals(completedAt, store.items[0].completedAt)
        assertEquals(1, TodoRules.visible(store.items, store.todayKey).size)
        // 이미 지운 줄을 또 지우거나, 지우지 않은 줄을 되돌리면 아무 일도 없다.
        val before = store.items
        store.undoDelete(item.id)
        assertEquals(before, store.items)
    }

    @Test
    fun renameNormalizesAndIgnoresInvalidTitlesAndNoOps() {
        var now = kst(2026, 8, 12, 9, 0)
        val store = memoryList(clock = { now })
        val item = store.add("원래 제목")!!
        now = kst(2026, 8, 12, 9, 1)
        store.rename(item.id, "  고친   제목  ")
        assertEquals("고친 제목", store.items[0].title)
        assertEquals(now, store.items[0].updatedAt)
        store.rename(item.id, "   ")
        assertEquals("고친 제목", store.items[0].title)
        store.rename(item.id, "나".repeat(101))
        assertEquals("고친 제목", store.items[0].title)
        assertEquals(kst(2026, 8, 12, 9, 0), store.items[0].createdAt)
        assertEquals("20260812", store.items[0].originDayKey)
        // 내용이 그대로면 updatedAt 도 건드리지 않는다.
        now = kst(2026, 8, 12, 9, 2)
        store.rename(item.id, "고친 제목")
        assertEquals(kst(2026, 8, 12, 9, 1), store.items[0].updatedAt)
    }

    @Test
    fun stampsMillisecondGridOnEveryEditDoor() {
        var now = 1_726_500_000.1234567
        val files = InMemoryTodoFileSystem()
        val store = memoryList(files, path) { now }
        val item = store.add("정규화")!!
        assertEquals(msDate(1_726_500_000_123), item.createdAt)
        assertEquals(item.createdAt, item.updatedAt)
        now = 1_726_500_060.9876543
        store.toggleDone(item.id)
        assertEquals(msDate(1_726_500_060_988), store.items[0].completedAt)
        assertEquals(msDate(1_726_500_060_988), store.items[0].updatedAt)
        now = 1_726_500_120.4567891
        store.rename(item.id, "정규화 고침")
        assertEquals(msDate(1_726_500_120_457), store.items[0].updatedAt, "rename 이 소수 ms 시각을 그대로 적었다")
        now = 1_726_500_180.0004
        store.delete(item.id)
        assertEquals(msDate(1_726_500_180_000), store.items[0].deletedAt)
        assertEquals(msDate(1_726_500_180_000), store.items[0].updatedAt)
        now = 1_726_500_240.7777
        store.undoDelete(item.id)
        assertEquals(msDate(1_726_500_240_778), store.items[0].updatedAt)
        val reread = memoryList(files, path) { now }
        assertEquals(store.items, reread.items, "파일 왕복에서 시각이 비트까지 같지 않다")
    }

    @Test
    fun updatedAtIsStrictlyIncreasingEvenWithinOneMillisecondOrBackwardClock() {
        var now = 1_726_500_000.0
        val store = memoryList(clock = { now })
        val item = store.add("체크했다 곧바로 푼다")!!
        store.toggleDone(item.id)
        val first = store.items[0].updatedAtMs
        assertEquals(item.updatedAtMs + 1, first)
        store.toggleDone(item.id)
        assertEquals(first + 1, store.items[0].updatedAtMs)
        now -= 600
        store.rename(item.id, "시계가 돌아간 뒤 고침")
        assertEquals(first + 2, store.items[0].updatedAtMs)
    }

    @Test
    fun reloadPrunesAncientDoneAndRewritesFileAndPending() {
        val files = InMemoryTodoFileSystem()
        val now = kst(2026, 8, 12, 12, 0)
        val ancient = now - 100 * 86_400
        val old = com.yehsung.aingcheck.core.rules.todo.TodoItem(uuid(1), "100일 전에 끝낸 일", TodoRules.normalizedTime(ancient), TodoRules.normalizedTime(ancient),
            TodoRules.normalizedTime(ancient), null, "20260504")
        val alive = com.yehsung.aingcheck.core.rules.todo.TodoItem(uuid(2), "살아 있는 일", TodoRules.normalizedTime(now - 3 * 86_400),
            TodoRules.normalizedTime(now - 3 * 86_400), null, null, "20260809")
        TodoFileStore.save(files, TodoFile(items = listOf(old, alive), sync = TodoFileSyncState(5, listOf(old.id, alive.id))), path)
        val store = memoryList(files, path) { now }
        assertEquals(listOf("살아 있는 일"), store.items.map { it.title })
        assertEquals(setOf(alive.id), store.pendingIDs)
        val onDisk = TodoFileStore.load(files, path)
        assertEquals(listOf("살아 있는 일"), onDisk.items.map { it.title })
        assertEquals(listOf(alive.id), onDisk.sync.pendingIDs)
        assertEquals(5L, onDisk.sync.watermarkMs)
    }

    @Test
    fun corruptedFileIsBackedUpNotDiscarded() {
        val files = InMemoryTodoFileSystem()
        val garbage = "{ 이건 JSON 이 아니다"
        files.contents[path] = garbage.encodeToByteArray()
        assertFailsWith<SwiftDecodingError> { TodoFileStore.load(files, path) }
        val now = kst(2026, 8, 12, 13, 45)
        val backup = TodoFileStore.corruptedBackupPath(path, now)
        assertEquals("/mem/aing/todos.local.json.corrupt-20260812-134500", backup)
        val store = memoryList(files, path) { now }
        assertEquals(emptyList(), store.items)
        assertEquals(garbage, files.text(backup), "원본은 백업으로 살아 있어야 한다")
        store.add("새로 시작")
        assertEquals(listOf("새로 시작"), TodoFileStore.load(files, path).items.map { it.title })
    }

    @Test
    fun persistsAcrossInstancesIncludingTombstones() {
        val files = InMemoryTodoFileSystem()
        var now = kst(2026, 8, 12, 9, 0)
        val first = memoryList(files, path) { now }
        val keep = first.add("남길 일")!!
        val done = first.add("끝낼 일")!!
        val gone = first.add("지울 일")!!
        now = kst(2026, 8, 12, 9, 30)
        first.toggleDone(done.id)
        first.delete(gone.id)
        val second = memoryList(files, path) { now }
        assertEquals(3, second.items.size, "톰스톤까지 그대로 실린다")
        assertEquals("남길 일", second.items.first { it.id == keep.id }.title)
        assertEquals(kst(2026, 8, 12, 9, 30), second.items.first { it.id == done.id }.completedAt)
        assertEquals(kst(2026, 8, 12, 9, 30), second.items.first { it.id == gone.id }.deletedAt)
        assertEquals(listOf("남길 일", "끝낼 일"), TodoRules.visible(second.items, second.todayKey).map { it.title })
        assertEquals(setOf(keep.id, done.id, gone.id), second.pendingIDs)
    }

    @Test
    fun saveFailureIsSwallowedMemoryStaysTruth() {
        val files = InMemoryTodoFileSystem()
        val store = memoryList(files, path) { kst(2026, 8, 12, 9, 0) }
        files.failWrites = true
        val item = store.add("디스크가 말썽")
        assertNotNull(item, "저장 실패가 추가를 막았다")
        assertEquals(listOf("디스크가 말썽"), store.items.map { it.title })
        files.failWrites = false
        store.add("다음 변경")
        assertEquals(listOf("다음 변경", "디스크가 말썽"), TodoFileStore.load(files, path).items.map { it.title }, "다음 변경에서 통째로 다시 쓰지 않았다")
    }

    @Test
    fun firstGenerationFileMarksEverythingPendingAndRewritesAsGen2() {
        for (withVersionKey in listOf(true, false)) {
            val files = InMemoryTodoFileSystem()
            val version = if (withVersionKey) "\"version\":1," else ""
            // 옛 앱은 ms 로 자르지 않았다 — 소수 ms 가 남은 값(참조일 기준 초).
            val created = 1_726_400_000.0004 - 978_307_200.0
            files.contents[path] = ("{$version\"items\":[" +
                "{\"id\":\"${uuid(1).uppercase()}\",\"title\":\"하나\",\"createdAt\":$created,\"updatedAt\":$created,\"originDayKey\":\"20260915\"}," +
                "{\"id\":\"${uuid(2).uppercase()}\",\"title\":\"둘\",\"createdAt\":$created,\"updatedAt\":$created,\"originDayKey\":\"20260915\"}]}").encodeToByteArray()
            val decoded = TodoFileStore.load(files, path)
            assertEquals(1, decoded.version)
            assertEquals(setOf(uuid(1), uuid(2)), decoded.sync.pendingIDs.toSet(), "1세대 파일의 id 가 전부 pending 이 아니다")
            assertNull(decoded.sync.watermarkMs)

            val store = memoryList(files, path) { 1_726_500_000.0 }
            assertEquals(setOf(uuid(1), uuid(2)), store.pendingIDs)
            assertNull(store.watermarkMs)
            assertEquals(listOf("하나", "둘"), store.items.map { it.title })
            assertTrue(store.items.all { TodoRules.normalizedTime(it.updatedAt) == it.updatedAt })
            val raw = SwiftJson.parse(files.text(path)!!) as JsonObject
            assertEquals("2", raw["version"]!!.jsonPrimitive.content)
            val sync = raw["sync"] as JsonObject
            assertEquals(JsonNull, sync["watermarkMs"], "watermarkMs 는 키를 빼지 않고 null 로 싣는다")
            assertEquals(2, (sync["pendingIDs"] as JsonArray).size)
        }
        // 1세대 파일에 sync 칸이 실려 있어도(손으로 고친 파일 · 이상한 판) 믿지 않는다 — version < 2 는 언제나 전부 보낼 것 · watermark 없음.
        val files = InMemoryTodoFileSystem()
        val created = 1_726_400_000.0 - 978_307_200.0
        files.contents[path] = ("{\"version\":1,\"items\":[{\"id\":\"${uuid(3)}\",\"title\":\"셋\",\"createdAt\":$created,\"updatedAt\":$created," +
            "\"originDayKey\":\"20260915\"}],\"sync\":{\"watermarkMs\":5,\"pendingIDs\":[]}}").encodeToByteArray()
        val v1WithSync = TodoFileStore.load(files, path)
        assertEquals(listOf(uuid(3)), v1WithSync.sync.pendingIDs, "1세대 파일의 sync 칸을 믿었다")
        assertNull(v1WithSync.sync.watermarkMs)
    }

    @Test
    fun brokenSyncStateKeepsListAndFallsBackToAllPendingWithoutBackup() {
        val item = todoRow(uuid(7), "살아야 하는 줄", 1_726_400_000_000, createdMs = 1_726_400_000_000, origin = "20260915")
        val itemJSON = TodoFileStore.encode(TodoFile(items = listOf(item))).let { (SwiftJson.parse(it) as JsonObject)["items"].toString() }
        for (fragment in listOf("", ",\"sync\":{\"watermarkMs\":12,\"pendingIDs\":[\"not-a-uuid\"]}", ",\"sync\":42",
            ",\"sync\":{\"watermarkMs\":77,\"pendingIDs\":[],\"heldRejectedIDs\":\"not-a-uuid\"}",
            ",\"sync\":{\"watermarkMs\":77,\"pendingIDs\":[],\"heldRejectedIDs\":42}",
            ",\"sync\":{\"watermarkMs\":77,\"pendingIDs\":[],\"heldRejectedIDs\":[\"nope\"]}")) {
            val files = InMemoryTodoFileSystem()
            files.contents[path] = "{\"version\":2,\"items\":$itemJSON$fragment}".encodeToByteArray()
            val store = memoryList(files, path) { 1_726_500_000.0 }
            assertEquals(listOf(item), store.items, "sync 조각 $fragment 때문에 목록이 사라졌다")
            assertEquals(setOf(item.id), store.pendingIDs, fragment)
            assertNull(store.watermarkMs, fragment)
            assertEquals(emptySet(), store.heldRejectedIDs, fragment)
            assertTrue(files.contents.keys.none { "corrupt" in it }, "$fragment: 멀쩡한 목록을 손상 백업으로 치웠다")
        }
    }

    @Test
    fun brokenItemsOrVersionIsCorruption() {
        for (body in listOf("""{"version":2}""", """{"version":"2","items":[]}""", """[]""",
            """{"version":2,"items":[{"id":"x","title":"t","createdAt":1,"updatedAt":1,"originDayKey":"20260101"}]}""",
            """{"version":2,"items":[{"id":"${uuid(1)}","createdAt":1,"updatedAt":1,"originDayKey":"20260101"}]}""",
            """{"version":2,"items":[{"id":"${uuid(1)}","title":"t","createdAt":"1","updatedAt":1,"originDayKey":"20260101"}]}""",
            """{"version":2,"items":[{"id":"${uuid(1)}","title":"t","createdAt":1,"updatedAt":1,"completedAt":"x","originDayKey":"20260101"}]}""")) {
            val files = InMemoryTodoFileSystem()
            files.contents[path] = body.encodeToByteArray()
            assertFailsWith<SwiftDecodingError>(body) { TodoFileStore.load(files, path) }
        }
        // 빈 파일·없는 파일은 손상이 아니다(첫 실행).
        val empty = InMemoryTodoFileSystem().also { it.contents[path] = ByteArray(0) }
        assertEquals(emptyList(), TodoFileStore.load(empty, path).items)
        assertEquals(emptyList(), TodoFileStore.load(InMemoryTodoFileSystem(), path).items)
    }

    @Test
    fun secondGenerationSyncStateRoundTrips() {
        val files = InMemoryTodoFileSystem()
        val items = (0 until 3).map { todoRow(uuid(it + 1), "줄 $it", 1_726_400_000_000 + it, createdMs = 1_726_400_000_000 + it) }
        TodoFileStore.save(files, TodoFile(items = items, sync = TodoFileSyncState(1_726_499_999_999, listOf(items[1].id))), path)
        val store = memoryList(files, path) { 1_726_500_000.0 }
        assertEquals(setOf(items[1].id), store.pendingIDs)
        assertEquals(1_726_499_999_999L, store.watermarkMs)
        assertEquals(items, store.items)
        val writes = files.writeCount
        memoryList(files, path) { 1_726_500_000.0 }
        assertEquals(writes, files.writeCount, "읽기만 했는데 파일을 다시 썼다")
    }

    @Test
    fun fileShapeMatchesSwiftCodable() {
        val item = todoRow(uuid(9).uppercase().lowercase(), "모양", TODO_BASE_MS + 5, createdMs = TODO_BASE_MS, completedMs = TODO_BASE_MS + 5)
        val text = TodoFileStore.encode(TodoFile(items = listOf(item), sync = TodoFileSyncState(null, listOf(item.id), emptyList())))
        val root = SwiftJson.parse(text) as JsonObject
        assertEquals(listOf("version", "items", "sync"), root.keys.toList())
        val row = (root["items"] as JsonArray).single() as JsonObject
        assertEquals(listOf("id", "title", "createdAt", "updatedAt", "completedAt", "originDayKey"), row.keys.toList(), "nil 인 deletedAt 은 키를 뺀다")
        // 시각은 참조일(2001-01-01) 기준 초 — Swift 기본 Date 전략.
        assertEquals((TODO_BASE_MS / 1000.0) - 978_307_200.0, row["createdAt"]!!.jsonPrimitive.content.toDouble(), 1e-6)
        val sync = root["sync"] as JsonObject
        assertEquals(listOf("watermarkMs", "pendingIDs", "heldRejectedIDs"), sync.keys.toList())
        assertEquals(JsonNull, sync["watermarkMs"])
        // 대문자로 적힌 uuid(Swift 가 쓴 파일)도 읽고, 소문자로 접는다.
        val upper = text.replace(item.id, item.id.uppercase())
        assertEquals(item.id, TodoFileStore.decode(upper).items.single().id)
        assertEquals(listOf(item.id), TodoFileStore.decode(upper).sync.pendingIDs)
    }

    @Test
    fun heldRejectedReleasedByEveryUserEdit() {
        val edits: List<Pair<String, (TodoListStore, String) -> Unit>> = listOf(
            "toggleDone" to { s, id -> s.toggleDone(id) },
            "rename" to { s, id -> s.rename(id, "다시 고친 제목") },
            "delete" to { s, id -> s.delete(id) },
            "undoDelete" to { s, id -> s.undoDelete(id) },
        )
        for ((name, edit) in edits) {
            val files = InMemoryTodoFileSystem()
            val held = todoRow(uuid(1), "넘친 줄", TODO_BASE_MS + 1, deletedMs = if (name == "undoDelete") TODO_BASE_MS + 1 else null)
            val bystander = todoRow(uuid(2), "다른 붙잡힌 줄", TODO_BASE_MS + 2)
            TodoFileStore.save(files, TodoFile(items = listOf(held, bystander), sync = TodoFileSyncState(TODO_BASE_MS, emptyList(), listOf(held.id, bystander.id))), path)
            val list = memoryList(files, path) { msDate(TODO_BASE_MS + 60_000) }
            assertEquals(setOf(held.id, bystander.id), list.heldRejectedIDs, "$name: 파일의 붙잡기를 못 읽었다(전제)")
            edit(list, held.id)
            assertEquals(setOf(bystander.id), list.heldRejectedIDs, "$name: 다시 고쳤는데 붙잡기가 안 풀렸다")
            assertEquals(setOf(held.id), list.pendingIDs, name)
            val disk = TodoFileStore.load(files, path)
            assertEquals(listOf(bystander.id), disk.sync.heldRejectedIDs, "$name: 파일에 안 실렸다")
            assertEquals(listOf(held.id), disk.sync.pendingIDs, name)
        }
    }

    @Test
    fun heldDroppedWhenPrunedAndPendingWinsOverlap() {
        val files = InMemoryTodoFileSystem()
        val ancientMs = TODO_BASE_MS - 100L * 86_400_000
        val ancient = todoRow(uuid(1), "100일 전에 지운 넘친 줄", ancientMs, createdMs = ancientMs, deletedMs = ancientMs)
        val alive = todoRow(uuid(2), "살아 있는 붙잡힌 줄", TODO_BASE_MS)
        TodoFileStore.save(files, TodoFile(items = listOf(ancient, alive), sync = TodoFileSyncState(TODO_BASE_MS, emptyList(), listOf(ancient.id, alive.id))), path)
        val list = memoryList(files, path) { msDate(TODO_BASE_MS) }
        assertEquals(listOf(alive), list.items)
        assertEquals(setOf(alive.id), list.heldRejectedIDs)
        assertEquals(listOf(alive.id), TodoFileStore.load(files, path).sync.heldRejectedIDs, "정리 뒤 파일의 붙잡기를 다시 쓰지 않았다")

        val a = todoRow(uuid(3), "줄 a", TODO_BASE_MS + 1)
        val b = todoRow(uuid(4), "줄 b", TODO_BASE_MS + 2)
        val overlapFiles = InMemoryTodoFileSystem()
        TodoFileStore.save(overlapFiles, TodoFile(items = listOf(a, b), sync = TodoFileSyncState(TODO_BASE_MS, listOf(a.id), listOf(a.id, b.id))), path)
        val overlap = memoryList(overlapFiles, path) { msDate(TODO_BASE_MS + 60_000) }
        assertEquals(setOf(a.id), overlap.pendingIDs)
        assertEquals(setOf(b.id), overlap.heldRejectedIDs, "붙잡기와 pending 이 겹치면 pending 이 이긴다")
        assertEquals(listOf(b.id), TodoFileStore.load(overlapFiles, path).sync.heldRejectedIDs)
    }

    @Test
    fun pathSeparatesUsersAndResistsEscape() {
        assertEquals("/d/todos.local.json", TodoFileStore.path("/d", null))
        assertEquals("/d/todos.local.json", TodoFileStore.path("/d/", ""))
        assertEquals("/d/todos.7f3a-42bc.json", TodoFileStore.path("/d", "7f3a-42bc"))
        assertEquals("/d/todos.etcpasswd.json", TodoFileStore.path("/d", "../../etc/passwd"), "구분자·점이 섞여도 파일명 안에 머문다")
        assertEquals("/d/todos.local.json", TodoFileStore.path("/d", "한글.."), "안전한 글자가 없으면 로그아웃 파일")
    }

    @Test
    fun switchFileRaisesGenerationAndReadsTheOtherFile() {
        val files = InMemoryTodoFileSystem()
        val other = "/mem/aing/todos.$USER_B.json"
        TodoFileStore.save(files, TodoFile(items = listOf(todoRow(uuid(5), "B 의 줄", TODO_BASE_MS)), sync = TodoFileSyncState(TODO_BASE_MS, emptyList())), other)
        val list = memoryList(files, path) { msDate(TODO_BASE_MS) }
        list.add("로컬 줄")
        val generation = list.fileGeneration
        list.switchFile(other)
        assertEquals(generation + 1, list.fileGeneration)
        assertEquals(other, list.filePath)
        assertEquals(listOf("B 의 줄"), list.items.map { it.title })
        assertEquals(TODO_BASE_MS, list.watermarkMs)
        assertEquals(emptySet(), list.pendingIDs)
        // 같은 파일로 다시 바꿔도 세대는 오른다(진행 중 응답을 버린다).
        list.switchFile(other)
        assertEquals(generation + 2, list.fileGeneration)
        assertContentEquals(listOf("로컬 줄"), TodoFileStore.load(files, path).items.map { it.title })
    }
}
