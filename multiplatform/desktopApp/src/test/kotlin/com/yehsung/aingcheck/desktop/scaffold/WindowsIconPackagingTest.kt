// W-6 #5(W6-b1 P3): 패키징이 **실제로 쓰는** windows.iconFile 을 잰다(빌드 파일 글자가 아니라 평가된 값 — 기억 tests-measure-shape-not-result).
package com.yehsung.aingcheck.desktop.scaffold

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class WindowsIconPackagingTest {
    @Test
    fun packagingUsesCommittedIcoWithAllSizesAsPng() {
        val path = System.getProperty("aingcheck.msiIconFile") ?: fail("aingcheck.msiIconFile 시스템 속성이 없다(aingcheck.desktop-app 밖 실행)")
        assertTrue(path.isNotEmpty(), "nativeDistributions.windows.iconFile 이 비었다")
        val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
        val ico = File(path)
        assertEquals(File(mp, "desktopApp/packaging/AingCheck.ico").canonicalFile, ico.canonicalFile)
        val b = ByteBuffer.wrap(ico.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(0, b.getShort(0).toInt(), "ICONDIR reserved")
        assertEquals(1, b.getShort(2).toInt(), "ICONDIR type = 아이콘")
        val count = b.getShort(4).toInt()
        val sizes = (0 until count).map { i ->
            val e = 6 + 16 * i
            val w = (b.get(e).toInt() and 0xFF).let { if (it == 0) 256 else it }
            val size = b.getInt(e + 8)
            val offset = b.getInt(e + 12)
            assertTrue(offset + size <= b.capacity(), "항목 $w 이 파일 밖을 가리킨다")
            assertEquals(0x89, b.get(offset).toInt() and 0xFF, "항목 $w 은 PNG")
            w
        }
        assertEquals(listOf(16, 24, 32, 48, 256), sizes.sorted())
    }
}
