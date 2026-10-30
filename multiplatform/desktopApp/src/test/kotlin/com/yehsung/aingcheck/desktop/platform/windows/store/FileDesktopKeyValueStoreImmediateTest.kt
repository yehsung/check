// W-13 #2: 근무 큐 키는 put 자리에서 바로 디스크에, 나머지는 250ms 묶음(+ 종료 flush). 강제 종료가 묶음 창 안에 와도 큐는 남는다.
package com.yehsung.aingcheck.desktop.platform.windows.store

import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FileDesktopKeyValueStoreImmediateTest {
    private val dir: Path = Files.createTempDirectory("kv-immediate")
    private val opened = mutableListOf<FileDesktopKeyValueStore>()

    @AfterTest
    fun cleanup() {
        opened.forEach { runCatching { it.close() } }
        dir.toFile().deleteRecursively()
    }

    /** 다른 프로세스가 지금 파일을 읽으면 무엇이 보이나(= 강제 종료 직후 다음 실행이 읽을 것). */
    private fun onDisk(file: Path): Map<String, String> =
        if (Files.exists(file)) FileDesktopKeyValueStore.decode(Files.readString(file)) else emptyMap()

    @Test
    fun 앱_자리는_근무_큐_키를_즉시_쓰기로_연다() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        assertEquals(FileDesktopKeyValueStore.WORK_IMMEDIATE_KEYS, kv.immediateKeys)
        assertTrue(DesktopWorkQueue.pendingWorkQueueKey in kv.immediateKeys)
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, """[{"op":"start"}]""")
        assertEquals("""[{"op":"start"}]""", onDisk(kv.file)[DesktopWorkQueue.pendingWorkQueueKey], "묶음 창(60초)을 기다리지 않는다")
        assertFalse(kv.isDirty)
    }

    @Test
    fun 다른_키는_묶음_창_안에선_디스크에_없다__음성_대조() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        kv.putString("check.overlay.position", "1,2")
        assertNull(onDisk(kv.file)["check.overlay.position"])
        assertTrue(kv.isDirty)
        // 큐 쓰기가 오면 그때까지의 다른 변경도 같은 스냅숏에 실린다(잃는 것 없음).
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[]")
        assertEquals("1,2", onDisk(kv.file)["check.overlay.position"])
        assertFalse(kv.isDirty)
    }

    @Test
    fun 즉시_키가_없으면_큐도_묶음__음성_대조() {
        val kv = FileDesktopKeyValueStore(dir.resolve("plain.json"), debounceMillis = 60_000).also { opened += it }
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[]")
        assertNull(onDisk(kv.file)[DesktopWorkQueue.pendingWorkQueueKey])
        assertTrue(kv.flush())
        assertEquals("[]", onDisk(kv.file)[DesktopWorkQueue.pendingWorkQueueKey])
    }

    @Test
    fun 큐_지움도_즉시() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[1]")
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, null)
        assertFalse(onDisk(kv.file).containsKey(DesktopWorkQueue.pendingWorkQueueKey), "드레인 뒤 빈 큐가 다음 실행에서 되살아나지 않게")
    }
}
