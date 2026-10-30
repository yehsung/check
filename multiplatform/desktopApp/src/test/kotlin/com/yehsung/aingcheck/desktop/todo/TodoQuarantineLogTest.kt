// 원본: 없음 — int-w4a polish ⑤(할 일 격리 보고 → 앱 로그 폴더 파일 한 줄 · 크기 상한·한 세대 회전). 맥 로그 자리: CheckUpdateCheck.swift:1027.
package com.yehsung.aingcheck.desktop.todo

import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Instant

class TodoQuarantineLogTest {
    private val dirs = mutableListOf<Path>()

    @AfterTest
    fun cleanup() = dirs.forEach { it.toFile().deleteRecursively() }

    private fun newDir(): Path = Files.createTempDirectory("todo-qlog").also { dirs.add(it) }

    private fun paths(data: String, log: String) = object : AppPaths {
        override val dataDir = data; override val cacheDir = "C"; override val logDir = log; override val userHome = "H"
    }

    private val q = TodoQuarantine("/d/todos.local.json", "/d/todos.local.json.corrupt", bytes = 12, moved = true, preserved = true)

    @Test
    fun `로그 폴더 — 절대 logDir 는 그대로, 비었거나 상대 경로면 dataDir 아래 logs`() {
        val d = newDir()
        val l = newDir()
        assertEquals(l, TodoQuarantineLog.dir(paths(d.toString(), l.toString())))
        assertEquals(d.resolve("logs"), TodoQuarantineLog.dir(paths(d.toString(), "")))
        assertEquals(d.resolve("logs"), TodoQuarantineLog.dir(paths(d.toString(), "L")), "작업 폴더에 따라 바뀌는 상대 경로는 쓰지 않는다")
    }

    @Test
    fun `격리 한 건 → 로그 파일 한 줄(시각·경로·크기·보존), 폴더가 없으면 만든다`() {
        val d = newDir()
        val sink = TodoQuarantineLog.sink(paths(d.toString(), ""), now = { Instant.fromEpochSeconds(1_792_465_200) })
        sink(q)
        sink(q.copy(moved = false, preserved = false, bytes = -1))
        val lines = Files.readAllLines(d.resolve("logs").resolve(TodoQuarantineLog.FILE_NAME))
        assertEquals(2, lines.size)
        assertEquals(
            "2026-10-20T03:00:00Z todo quarantine original=/d/todos.local.json backup=/d/todos.local.json.corrupt bytes=12 moved=true preserved=true",
            lines[0],
        )
        assertTrue(lines[1].endsWith("bytes=-1 moved=false preserved=false"), lines[1])
    }

    @Test
    fun `크기 상한 — 넘으면 앞 세대를 이름_1 로 옮기고 새 파일에 쓴다(앞의 앞 세대는 덮는다), 상한 아래면 덧붙인다`() {
        val d = newDir()
        val f = RotatingLogFile(d.resolve("x.log"), maxBytes = 25)
        assertTrue(f.append("a".repeat(20)))
        assertTrue(f.append("b".repeat(5)))
        assertEquals(listOf("a".repeat(20), "b".repeat(5)), Files.readAllLines(f.file), "21바이트 < 25 — 덧붙임")
        assertFalse(Files.exists(f.rotated))
        assertTrue(f.append("c"))
        assertEquals(listOf("c"), Files.readAllLines(f.file))
        assertEquals(listOf("a".repeat(20), "b".repeat(5)), Files.readAllLines(f.rotated))
        f.append("d".repeat(40)) // 상한을 혼자 넘는 줄도 쓴다(다음 쓰기에서 돈다)
        f.append("e")
        assertEquals(listOf("c", "d".repeat(40)), Files.readAllLines(f.rotated), "앞의 앞 세대는 덮인다")
        assertEquals(listOf("e"), Files.readAllLines(f.file))
    }

    @Test
    fun `쓰기 실패는 삼킨다 — 파일 자리에 폴더가 있으면 false, 던지지 않는다`() {
        val d = newDir()
        Files.createDirectories(d.resolve("x.log").resolve("child"))
        assertFalse(RotatingLogFile(d.resolve("x.log")).append("z"))
    }
}
