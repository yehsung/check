// 원본: Tests/checkTests/CheckTodoModelTests.swift:379-433(파일 저장소 — 상위 폴더 만들기 · 원자적 쓰기 · 손상 백업) @ 1b8260d
// 진짜 파일 시스템(임시 폴더)에서 잰다. 시험이 끝나면 폴더를 지운다(홈에 잔재를 남기지 않는다).
package com.yehsung.aingcheck.core.stores.now.todo

import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JvmTodoFileSystemTest {
    private val root: File = Files.createTempDirectory("aing-todo-fs").toFile()

    @AfterTest
    fun cleanUp() {
        root.deleteRecursively()
    }

    @Test
    fun writesAtomicallyIntoMissingFoldersAndRoundTrips() {
        val fs = JvmTodoFileSystem()
        val path = File(root, "nested/aing/todos.local.json").path
        assertNull(fs.read(path), "없는 파일은 null")
        val t = TodoRules.normalizedTime(1_726_500_000.123)
        val file = TodoFile(items = listOf(TodoItem("00000000-0000-4000-8000-000000000001", "한 줄", t, t, t, null, "20260916")),
            sync = TodoFileSyncState(1_726_500_000_000, emptyList()))
        TodoFileStore.save(fs, file, path)   // 상위 폴더가 없어도 만들어서 쓴다
        assertEquals(file, TodoFileStore.load(fs, path))
        // 임시 파일이 남지 않는다(이름 바꾸기로 덮었다).
        assertEquals(listOf("todos.local.json"), File(root, "nested/aing").list()!!.sorted())
        // 덮어쓰기도 같은 길.
        TodoFileStore.save(fs, file.copy(items = emptyList()), path)
        assertEquals(emptyList(), TodoFileStore.load(fs, path).items)
        assertEquals(listOf("todos.local.json"), File(root, "nested/aing").list()!!.sorted())
    }

    @Test
    fun corruptedFileIsMovedToBackupByTheStore() {
        val fs = JvmTodoFileSystem()
        val path = File(root, "todos.local.json").path
        File(path).writeText("{ 이건 JSON 이 아니다")
        val now = kst(2026, 8, 12, 13, 45)
        val list = TodoListStore(path, fs, clock = { now })
        assertEquals(emptyList(), list.items)
        val backup = File(TodoFileStore.corruptedBackupPath(path, now))
        assertTrue(backup.exists(), "원본을 백업으로 옮기지 않았다: ${root.list()?.toList()}")
        assertEquals("{ 이건 JSON 이 아니다", backup.readText())
        assertEquals("todos.local.json.corrupt-20260812-134500", backup.name)
        list.add("새로 시작")
        assertEquals(listOf("새로 시작"), TodoFileStore.load(fs, path).items.map { it.title })
        // 옮길 원본이 없어도 조용하다.
        fs.move(File(root, "없는 파일").path, File(root, "어디로").path)
    }
}
