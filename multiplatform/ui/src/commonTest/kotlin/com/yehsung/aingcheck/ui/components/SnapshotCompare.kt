// 스냅숏 대조(플랫폼 무관 부분). 렌더·PNG 읽고 쓰기는 각 시험 소스셋(desktopTest·androidHostTest)이 한다.
//
// 대조는 **픽셀 그대로**(ARGB 정수 배열 일치)다. PNG 바이트는 인코더마다 달라 비교하지 않는다.
// 기록은 이 맥에서만(A§4-3): AINGCHECK_SNAPSHOT_RECORD=1 이면 골든을 다시 쓰고 **시험은 실패로 끝난다**(기록 실행이 초록으로 읽히지 않게).
package com.yehsung.aingcheck.ui.components

class PixelImage(val width: Int, val height: Int, val argb: IntArray) {
    init {
        require(argb.size == width * height) { "픽셀 수 ${argb.size} ≠ $width×$height" }
    }

    /** 서로 다른 색 수(장면이 실제로 그려졌는지 재는 데 쓴다). */
    fun distinctColors(): Int = argb.toHashSet().size

    /** 완전히 투명하지 않은 픽셀 수. */
    fun opaqueCount(): Int = argb.count { (it ushr 24) != 0 }
}

data class SnapshotDiff(val sizeMismatch: Boolean, val differingPixels: Int, val maxChannelDelta: Int) {
    val identical: Boolean get() = !sizeMismatch && differingPixels == 0
}

object SnapshotCompare {
    const val RECORD_ENV = "AINGCHECK_SNAPSHOT_RECORD"

    fun diff(expected: PixelImage, actual: PixelImage): SnapshotDiff {
        if (expected.width != actual.width || expected.height != actual.height) return SnapshotDiff(true, -1, -1)
        var differing = 0
        var maxDelta = 0
        for (i in expected.argb.indices) {
            val a = expected.argb[i]
            val b = actual.argb[i]
            if (a != b) {
                differing++
                for (shift in intArrayOf(0, 8, 16, 24)) {
                    val d = kotlin.math.abs(((a ushr shift) and 0xFF) - ((b ushr shift) and 0xFF))
                    if (d > maxDelta) maxDelta = d
                }
            }
        }
        return SnapshotDiff(false, differing, maxDelta)
    }

    /** 다른 픽셀을 빨강, 같은 픽셀을 흐린 회색으로 칠한 차이 그림. */
    fun diffImage(expected: PixelImage, actual: PixelImage): PixelImage? {
        if (expected.width != actual.width || expected.height != actual.height) return null
        val out = IntArray(expected.argb.size) { i ->
            if (expected.argb[i] != actual.argb[i]) 0xFFFF0000.toInt() else 0x40808080
        }
        return PixelImage(expected.width, expected.height, out)
    }
}
