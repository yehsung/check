// 원본: 없음 — 스냅숏 대조기 시험.
//
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

    /**
     * 문턱 64(G §8-13): 칸 하나가 고르게 65 만큼 옅어지면(테두리 굵기·투명도 같은 작은 색 회귀) 비기록 러너에서도 빨강,
     * 실측 러너 잡음 상한(칸 차 55)은 초록. 문턱 96 이던 때는 앞쪽이 초록으로 빠져나갔다.
     */
    @Test
    fun coarseThresholdCatchesSixtyFiveButNotRunnerNoise() {
        // 256×256 = 칸 1,024개 — 칸 하나만 달라 비율 조건(3%)은 늘 통과한다. 그래서 갈리는 것은 칸 차 상한 하나다.
        val base = image(w = 256, h = 256)
        fun shifted(by: Int) = image(w = 256, h = 256) { x, y ->
            if (x in 8 until 16 && y in 8 until 16) (0xFF shl 24) or ((255 - by) shl 16) or ((255 - by) shl 8) or (255 - by) else white
        }
        val regression = SnapshotCompare.coarse(base, shifted(65))
        assertEquals(65, regression.maxBlockDelta)
        assertEquals(1, regression.blocksOver(SnapshotPolicy.COARSE_COUNTED_DELTA))
        assertFalse(regression.withinTolerance, "칸 차 65 를 굵은 대조가 넘겼다($regression)")
        val runnerNoise = SnapshotCompare.coarse(base, shifted(55))
        assertEquals(55, runnerNoise.maxBlockDelta)
        assertTrue(runnerNoise.withinTolerance, "실측 러너 잡음 상한(칸 차 55)이 빨강이다($runnerNoise)")
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
