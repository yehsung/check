// 원본: Sources/CheckMobileShared/WidgetSnapshot.swift:348-362(WidgetSnapshotCodec.read · write(.atomic) · remove) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.wire.SwiftDate
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FileWidgetSnapshotFileTest {
    private val root: File = Files.createTempDirectory("aing-widget").toFile()

    @AfterTest
    fun cleanUp() {
        root.deleteRecursively()
    }

    @Test
    fun atomicWriteCreatesFolderLeavesNoTempFilesAndRoundTrips() {
        val target = File(root, "files/${WidgetSnapshotWriter.FILE_NAME}")
        val file = FileWidgetSnapshotFile(target)
        assertNull(file.read(), "파일이 없으면 null(= 로그아웃 화면)")
        val snapshot = WidgetSnapshot(generatedAt = SwiftDate(1_789_621_500.0), characterID = "aing")
        file.writeAtomically(WidgetSnapshotCodec.encode(snapshot))
        assertTrue(target.isFile, "상위 폴더를 만들고 쓴다")
        assertEquals(listOf(WidgetSnapshotWriter.FILE_NAME), target.parentFile.list()!!.toList(), "임시 파일을 남기지 않는다")
        assertEquals(snapshot, WidgetSnapshotCodec.decode(file.read()!!))
        // 덮어쓰기도 원자적이다(이름 바꾸기 — 반쯤 쓰인 파일이 보이지 않는다).
        val next = snapshot.copy(characterID = "fox")
        file.writeAtomically(WidgetSnapshotCodec.encode(next))
        assertContentEquals(WidgetSnapshotCodec.encode(next), target.readBytes())
        file.remove()
        assertFalse(target.exists())
        file.remove()
        assertNull(file.read(), "두 번 지워도 조용하다")
    }

    @Test
    fun unreadablePathIsNullNotACrash() {
        val folder = File(root, "dir-not-file").apply { mkdirs() }
        assertNull(FileWidgetSnapshotFile(folder).read(), "폴더 자리면 읽을 것이 없다")
    }
}
