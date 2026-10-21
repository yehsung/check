// 스냅숏 비교기 자체를 잰다: 픽셀 대조는 한 픽셀 차이도 본다 · 굵은 대조는 가장자리 한두 픽셀 차이는 녹이고 칸 하나가 통째로 바뀌면 잡는다.
package com.yehsung.aingcheck.ui.components

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SnapshotCompareTest {
    private val white = 0xFFFFFFFF.toInt()
    private val black = 0xFF000000.toInt()

    private fun image(w: Int = 32, h: Int = 32, paint: (x: Int, y: Int) -> Int = { _, _ -> white }) =
        PixelImage(w, h, IntArray(w * h) { paint(it % w, it / w) })

    @Test
    fun exactDiffSeesOnePixel() {
        val a = image()
        val b = image { x, y -> if (x == 5 && y == 7) 0xFFFFFFFE.toInt() else white }
        val d = SnapshotCompare.diff(a, b)
        assertFalse(d.identical)
        assertEquals(1, d.differingPixels)
        assertEquals(1, d.maxChannelDelta)
        assertTrue(SnapshotCompare.diff(a, image()).identical)
        assertTrue(SnapshotCompare.diff(a, image(w = 31)).sizeMismatch)
    }

    @Test
    fun coarseMeltsEdgeNoiseButCatchesABlockChange() {
        val base = image()
        // 가장자리 잡음: 칸마다 두 픽셀을 검게(글자 가장자리 한두 픽셀이 갈린 꼴) → 칸 평균 차 255×2/64 ≈ 7.
        val noisy = image { x, y -> if ((x % 8 == 3 && y % 8 == 4) || (x % 8 == 4 && y % 8 == 4)) black else white }
        val c1 = SnapshotCompare.coarse(base, noisy)
        assertEquals(16, c1.blocks)
        assertTrue(c1.maxBlockDelta < SnapshotPolicy.COARSE_COUNTED_DELTA, "$c1")
        assertTrue(c1.withinTolerance)
        // 칸 하나가 통째로 바뀜(색 바뀜·부품 이동) → 255.
        val moved = image { x, y -> if (x in 8 until 16 && y in 16 until 24) black else white }
        val c2 = SnapshotCompare.coarse(base, moved)
        assertEquals(255, c2.maxBlockDelta)
        assertEquals(1, c2.blocksOver(SnapshotPolicy.COARSE_COUNTED_DELTA))
        assertFalse(c2.withinTolerance)
        assertFalse(SnapshotCompare.coarse(base, image(w = 24)).withinTolerance, "크기가 다르면 굵은 대조도 빨강")
    }

    @Test
    fun onlyTheRecordingMacComparesExactly() {
        assertTrue(SnapshotPolicy.isRecordingHost("Mac OS X", "aarch64"))
        assertFalse(SnapshotPolicy.isRecordingHost("Linux", "amd64"))
        assertFalse(SnapshotPolicy.isRecordingHost("Windows Server 2025", "amd64"))
        assertFalse(SnapshotPolicy.isRecordingHost("Mac OS X", "x86_64"))
        assertFalse(SnapshotPolicy.isRecordingHost(null, null))
    }
}
