// 원본: 맥 UserDefaults 영속(재시작을 넘는 큐·잠자기 마커·세션 prefs) — 시험은 새 코드(W-9 #1 W3-d 완료 기준).
// 픽스처는 합성만(임시 폴더). 실제 키 이름은 소비자 상수를 그대로 쓴다(이름이 바뀌면 여기도 따라온다).
package com.yehsung.aingcheck.desktop.platform.windows.store

import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.desktop.DesktopPrefs
import com.yehsung.aingcheck.feature.desktop.work.policy.SleepCloseMarkerStore
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.io.path.exists
import kotlin.io.path.readText
import kotlin.io.path.writeText
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FileDesktopKeyValueStoreTest {
    private val dir: Path = Files.createTempDirectory("aingcheck-kv-test")
    private val file: Path = dir.resolve(FileDesktopKeyValueStore.FILE_NAME)
    private val opened = mutableListOf<FileDesktopKeyValueStore>()

    private fun open(debounce: Long = 10_000, commit: ((Path, Path) -> Unit)? = null): FileDesktopKeyValueStore =
        FileDesktopKeyValueStore(file, debounce, commit ?: FileDesktopKeyValueStore::atomicReplace) { }.also { opened += it }

    @AfterTest
    fun cleanup() {
        opened.forEach { runCatching { it.close() } }
        dir.toFile().deleteRecursively()
    }

    @Test
    fun `재시작 왕복 — 근무 큐 항목 · 잠자기 마커 · 세션 prefs 키가 살아남는다`() {
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.MISSING, a.loadOutcome)
        val queueJson = """[{"id":"8F14E45F-CEEA-467A-9575-1C2D3B4A5E6F","kind":"start","at":1761800000.5}]"""
        a.putString(DesktopWorkQueue.pendingWorkQueueKey, queueJson)
        a.putString(SleepCloseMarkerStore.KEY, "1761800123.25")
        val prefs = DesktopPrefs(a)
        prefs.putString(SessionPrefsKeys.email, "합성@example.invalid")
        prefs.putBoolean("aingcheck.test.flag", true)
        prefs.putLong("aingcheck.test.long", 42L)
        a.putString("check.gone", "x")
        a.putString("check.gone", null)
        assertTrue(a.flush())
        a.close()

        val b = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.LOADED, b.loadOutcome)
        assertEquals(queueJson, b.getString(DesktopWorkQueue.pendingWorkQueueKey))
        assertEquals("1761800123.25", b.getString(SleepCloseMarkerStore.KEY))
        val prefsB = DesktopPrefs(b)
        assertEquals("합성@example.invalid", prefsB.getString(SessionPrefsKeys.email))
        assertEquals(true, prefsB.getBoolean("aingcheck.test.flag"))
        assertEquals(42L, prefsB.getLong("aingcheck.test.long"))
        assertNull(b.getString("check.gone"))
        assertEquals(listOf("check.sleepClose.pending", "check.workQueue.pending"), b.keys("check."))
    }

    @Test
    fun `묶어 쓰기 — flush 전에는 디스크가 그대로, 예약 쓰기는 간격 뒤에 한 번`() {
        val a = open(debounce = 10_000)
        a.putString("k", "1")
        assertFalse(file.exists(), "묶는 간격 안에 썼다")
        assertTrue(a.isDirty)
        a.close() // close 가 남은 변경을 쓴다(종료 단계 flush 와 같은 길)
        assertEquals("1", open().getString("k"))

        val fast = FileDesktopKeyValueStore(file, debounceMillis = 20, FileDesktopKeyValueStore::atomicReplace) { }.also { opened += it }
        fast.putString("k", "2")
        val deadline = System.nanoTime() + 5_000_000_000
        while (fast.isDirty && System.nanoTime() < deadline) Thread.sleep(10)
        assertFalse(fast.isDirty, "예약 쓰기가 5초 안에 안 돌았다")
        assertTrue(file.readText().contains("\"k\":\"2\""))
    }

    @Test
    fun `쓰기 도중 죽음 — 교체 전에 멈추면 임시만 남고 다음 시작은 옛 값`() {
        val a = open()
        a.putString("check.workQueue.pending", "old")
        assertTrue(a.flush())
        a.close()
        val before = file.readText()

        // 임시를 다 쓰고 fsync 까지 한 뒤 교체 직전에 프로세스가 죽은 꼴: commit 이 던진다 → 대상 파일은 손대지 않는다.
        val dying = open(commit = { _, _ -> throw IllegalStateException("교체 전에 죽음") })
        dying.putString("check.workQueue.pending", "new")
        assertFalse(dying.flush(), "교체 실패를 성공으로 셌다")
        assertEquals(before, file.readText(), "교체 전에 죽었는데 대상 파일이 바뀌었다")
        assertEquals("new", dying.getString("check.workQueue.pending"), "메모리 값까지 잃었다")
        // 반쯤 쓴 임시가 남아 있는 상태(실제 죽음)를 만든다.
        file.resolveSibling(file.fileName.toString() + ".tmp").writeText("{\"v\":1,\"values\":{\"check.workQueue.pending\":\"ne")

        val c = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.LOADED, c.loadOutcome)
        assertEquals("old", c.getString("check.workQueue.pending"))
        assertFalse(file.resolveSibling(file.fileName.toString() + ".tmp").exists(), "남은 임시를 치우지 않았다")
    }

    @Test
    fun `깨진 JSON — corrupt-n 으로 옮기고 빈 상태로 시작, 다음 깨짐은 다음 번호`() {
        file.writeText("{\"v\":1,\"values\":{\"a\":")
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.CORRUPT_QUARANTINED, a.loadOutcome)
        assertEquals(emptyList(), a.keys())
        val q1 = assertNotNull(a.quarantinedTo)
        assertEquals("${FileDesktopKeyValueStore.FILE_NAME}.corrupt-1", q1.fileName.toString())
        assertEquals("{\"v\":1,\"values\":{\"a\":", q1.readText(), "깨진 원본을 보존하지 않았다")
        a.putString("a", "fresh")
        a.close()
        assertEquals("fresh", open().getString("a"))

        // 모양이 다른 JSON(값이 문자열 아님 · 판 다름)도 깨진 것으로.
        file.writeText("{\"v\":1,\"values\":{\"a\":5}}")
        val b = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.CORRUPT_QUARANTINED, b.loadOutcome)
        assertEquals("${FileDesktopKeyValueStore.FILE_NAME}.corrupt-2", b.quarantinedTo?.fileName.toString())
        file.writeText("{\"v\":2,\"values\":{}}")
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.CORRUPT_QUARANTINED, open().loadOutcome)
    }

    @Test
    fun `동시 쓰기 직렬화 — 여러 스레드의 put 이 하나도 빠지지 않고 파일은 늘 온전한 JSON`() {
        val a = open(debounce = 1)
        val pool = Executors.newFixedThreadPool(8)
        val go = CountDownLatch(1)
        val done = CountDownLatch(8)
        repeat(8) { t ->
            pool.execute {
                go.await()
                repeat(200) { i -> a.putString("t$t.k$i", "v$i") }
                a.flush()
                done.countDown()
            }
        }
        go.countDown()
        assertTrue(done.await(30, TimeUnit.SECONDS))
        pool.shutdown()
        a.close()
        val decoded = FileDesktopKeyValueStore.decode(file.readText())
        assertEquals(1600, decoded.size)
        assertEquals("v199", decoded["t7.k199"])
    }

    @Test
    fun `음성 대조 — 같은 내용이면 같은 바이트, 다른 값이면 다른 바이트(기준선이 다르다)`() {
        val x = FileDesktopKeyValueStore.encode(mapOf("b" to "2", "a" to "1"))
        val y = FileDesktopKeyValueStore.encode(mapOf("a" to "1", "b" to "2"))
        val z = FileDesktopKeyValueStore.encode(mapOf("a" to "1", "b" to "3"))
        assertEquals(x, y)
        assertNotEquals(x, z)
        // 재시작 왕복이 '아무 값이나 통과'가 아님: 다른 파일에서 열면 값이 없다.
        val a = open()
        a.putString("k", "v")
        a.close()
        val other = FileDesktopKeyValueStore(dir.resolve("other.json"), 10_000, FileDesktopKeyValueStore::atomicReplace) { }.also { opened += it }
        assertNull(other.getString("k"))
    }
}
