// 원본: 없음 — 스냅숏 대조기(A§4-3). iOS 는 ImageRenderer 바이트 비교라 옮길 원본이 없다.
//
// 스냅숏 대조(플랫폼 무관 부분). 렌더·PNG 읽고 쓰기는 각 시험 소스셋(desktopTest·androidHostTest)이 한다.
//
// 대조는 **픽셀 그대로**(ARGB 정수 배열 일치)다. PNG 바이트는 인코더마다 달라 비교하지 않는다.
// 기록은 이 맥에서만(A§4-3): AINGCHECK_SNAPSHOT_RECORD=1 이면 골든을 다시 쓰고 **시험은 실패로 끝난다**(기록 실행이 초록으로 읽히지 않게).
//
// 기록 기계(macOS arm64)가 아닌 러너는 글자 래스터라이저가 다르다(맥 CoreText · Linux FreeType · Windows DirectWrite — 같은 글꼴도
// 가장자리 픽셀이 갈린다. W1-e CI 실측: ubuntu 54k·windows 52k px 차이, 같은 러너 3회는 동일). 그래서 A§4-3 대로 그 러너는
// "굵은 대조"로 낮춘다: 8px 칸 평균색끼리 재서 문턱([SnapshotPolicy])을 넘는 칸이 있으면 빨강. 글자 가장자리 차이는 칸 평균에서
// 녹고, 색·배치·부품이 바뀌면 칸이 통째로 바뀐다. 기록 기계에서는 언제나 픽셀 그대로다.
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

    /**
     * 굵은 대조: [block]px 칸마다 RGB 평균을 내 채널별 차의 최댓값을 잰다(알파는 장면이 불투명이라 뺀다).
     * 돌려주는 값: 칸 수 · 최대 칸 차 · 문턱별 넘은 칸 수.
     */
    fun coarse(expected: PixelImage, actual: PixelImage, block: Int = SnapshotPolicy.BLOCK): CoarseDiff {
        if (expected.width != actual.width || expected.height != actual.height) return CoarseDiff(0, 255, IntArray(SnapshotPolicy.BUCKETS.size) { Int.MAX_VALUE })
        val cols = (expected.width + block - 1) / block
        val rows = (expected.height + block - 1) / block
        val over = IntArray(SnapshotPolicy.BUCKETS.size)
        var maxDelta = 0
        for (by in 0 until rows) for (bx in 0 until cols) {
            val sa = LongArray(3)
            val sb = LongArray(3)
            var n = 0
            for (y in by * block until minOf((by + 1) * block, expected.height)) for (x in bx * block until minOf((bx + 1) * block, expected.width)) {
                val a = expected.argb[y * expected.width + x]
                val b = actual.argb[y * actual.width + x]
                for (c in 0 until 3) {
                    sa[c] += ((a ushr (16 - 8 * c)) and 0xFF).toLong()
                    sb[c] += ((b ushr (16 - 8 * c)) and 0xFF).toLong()
                }
                n++
            }
            var d = 0
            for (c in 0 until 3) d = maxOf(d, kotlin.math.abs(((sa[c] - sb[c]) / n).toInt()))
            if (d > maxDelta) maxDelta = d
            SnapshotPolicy.BUCKETS.forEachIndexed { i, t -> if (d > t) over[i]++ }
        }
        return CoarseDiff(cols * rows, maxDelta, over)
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

class CoarseDiff(val blocks: Int, val maxBlockDelta: Int, val over: IntArray) {
    /** 문턱 [threshold] 를 넘은 칸 수(BUCKETS 에 있는 값만). */
    fun blocksOver(threshold: Int): Int = over[SnapshotPolicy.BUCKETS.indexOf(threshold).also { require(it >= 0) { "문턱 $threshold 는 BUCKETS 에 없다" } }]

    val withinTolerance: Boolean
        get() = maxBlockDelta <= SnapshotPolicy.COARSE_MAX_BLOCK_DELTA &&
            blocksOver(SnapshotPolicy.COARSE_COUNTED_DELTA) <= blocks * SnapshotPolicy.COARSE_MAX_RATIO

    override fun toString(): String =
        "CoarseDiff(blocks=$blocks, max=$maxBlockDelta, " + SnapshotPolicy.BUCKETS.mapIndexed { i, t -> ">$t:${over[i]}" }.joinToString(" ") + ")"
}

object SnapshotPolicy {
    /** 골든을 기록한 기계(이 맥): 여기서는 픽셀 그대로 대조한다. */
    fun isRecordingHost(osName: String?, arch: String?): Boolean = osName?.startsWith("Mac") == true && arch == "aarch64"

    /** 굵은 대조 칸 한 변(px, 배율 2 에서 4dp). */
    const val BLOCK = 8
    val BUCKETS = intArrayOf(8, 16, 24, 32, 48, 64, 96)
    /**
     * 칸 평균 차 상한(0…255). 글자 가장자리 차이는 칸 평균에서 이보다 작다 — G §8-13 으로 96 → 64.
     * 근거(CI 실측, 맥 골든 대비 비기록 러너): ubuntu 칸 최대차 37~55 · windows 37~48. 한 군데만 다른 장면(음성 기준선)은 145~187.
     * 64 는 실측 러너 최대(55) 바로 위라 그보다 큰 색·배치 회귀(칸 평균 65 이상)는 CI 러너에서도 빨강이다.
     */
    const val COARSE_MAX_BLOCK_DELTA = 64
    /** 이 문턱을 넘은 칸의 비율 상한. */
    const val COARSE_COUNTED_DELTA = 48
    const val COARSE_MAX_RATIO = 0.03
}
