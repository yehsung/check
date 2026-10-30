// W4-f 오프스크린 스냅숏(ImageComposeScene — 창 0). 비교 정책은 testsupport 임시 사본(W-3 #19) 그대로:
// 기록 맥(Mac aarch64)은 픽셀 그대로, 그 밖 러너는 굵은 대조. 매 장면 음성 대조 — 한 군데 다른 기준선이 반드시 빨개져야 한다.
// 골든은 갈래 글롭 아래 `<자리>/golden/<이름>.png`(W1-f tray·flyout 선례). 기록: AINGCHECK_SNAPSHOT_RECORD=1 로 한 번(실패로 끝난다).
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

object W4fSnapshots {
    private const val TEST_ROOT = "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop"

    /** [area] = 테스트 패키지 아래 자리(예 "pages/shop", "windows/gacha"). */
    fun golden(area: String, name: String): File = File(DesktopSnapshots.mpRoot, "$TEST_ROOT/$area/golden/$name.png")

    /** 스냅숏 픽셀 사각형(왼·위 포함, 오른·아래 제외). */
    data class PxBox(val left: Int, val top: Int, val right: Int, val bottom: Int) {
        init {
            require(left in 0 until right && top in 0 until bottom) { "빈 사각형: $this" }
        }

        val area: Int get() = (right - left) * (bottom - top)

        /** 굵은 대조 칸 격자로 넓힌다 — 칸 하나가 반만 덮이면 남은 반의 차이가 칸 평균에 그대로 섞인다. */
        fun snapped(w: Int, h: Int, block: Int = SnapshotPolicy.BLOCK): PxBox =
            PxBox(max(0, left / block * block), max(0, top / block * block), min(w, (right + block - 1) / block * block), min(h, (bottom + block - 1) / block * block))
    }

    /** 가린 칸 넓이 상한(그림 비율) — 가리개가 장면을 삼키면 대조가 아니다. */
    const val MAX_IGNORED_FRACTION = 0.02

    /**
     * 굵은 대조용 [actual] — [ignore] 칸(격자로 넓혀서)에 [expected] 픽셀을 덮는다. 기록 맥(exact)에는 쓰지 않는다.
     * 쓰임: OS 글꼴로 그리는 그림 글자 칸(Apple Color Emoji · Segoe UI Emoji · Noto — 모양이 OS 마다 다르다, ui CakeGiftTitleParts 가 칸을 고정해 둔 까닭).
     */
    fun maskedForCoarse(expected: PixelImage, actual: PixelImage, ignore: List<PxBox>): PixelImage {
        require(expected.width == actual.width && expected.height == actual.height) { "크기가 다르다" }
        val w = actual.width
        val out = actual.argb.copyOf()
        for (b in ignore.map { it.snapped(w, actual.height) }) {
            for (y in b.top until b.bottom) for (x in b.left until b.right) out[y * w + x] = expected.argb[y * w + x]
        }
        return PixelImage(w, actual.height, out)
    }

    /**
     * [maxChangedFraction] — 기준선이 바꿔도 되는 픽셀 비율 상한(기본 1/10). 바뀐 한 군데가 넓은 판(고른 칸의 받침)이면 그 장면만 넓힌다.
     * [coarseIgnore] — 비기록 러너의 굵은 대조에서만 빼는 칸(스냅숏 px). 기록 맥은 그 칸까지 픽셀 그대로 본다.
     */
    fun check(
        area: String, name: String, widthDp: Int, heightDp: Int, scene: @Composable () -> Unit, baseline: @Composable () -> Unit,
        maxChangedFraction: Double = 0.1,
        coarseIgnore: List<PxBox> = emptyList(),
    ) {
        val renders = List(3) { DesktopSnapshots.render(widthDp, heightDp, content = scene) }
        val out = DesktopSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertTrue(actual.distinctColors() >= 64, "$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = golden(area, name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue(golden.isFile, "$name: 골든이 없다(${golden.path}) — 기록 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다")
        val expected = DesktopSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val ignored = coarseIgnore.sumOf { it.snapped(actual.width, actual.height).area }
        assertTrue(ignored <= actual.argb.size * MAX_IGNORED_FRACTION, "$name: 가린 칸 ${ignored}px — 상한 ${MAX_IGNORED_FRACTION * 100}%")
        val coarse = SnapshotCompare.coarse(expected, if (coarseIgnore.isEmpty()) actual else maskedForCoarse(expected, actual, coarseIgnore))
        println("AINGCHECK-SNAPSHOT desktop $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse ignore=$coarseIgnore")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            DesktopSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff · $coarse) — build/aingcheck-snapshots/desktop/$name-{actual,diff}.png")
        }
        negative(name, actual, DesktopSnapshots.render(widthDp, heightDp, content = baseline), maxChangedFraction)
    }

    /** 음성 대조: 한 군데만 다른 기준선이 같은 픽셀이면 비교가 내용을 못 보는 것이다. */
    private fun negative(name: String, actual: PixelImage, other: PixelImage, maxChangedFraction: Double) {
        assertEquals(actual.width to actual.height, other.width to other.height, "$name: 기준선 크기가 다르다")
        val negative = SnapshotCompare.diff(actual, other)
        val negativeCoarse = SnapshotCompare.coarse(actual, other)
        println("AINGCHECK-SNAPSHOT-NEGATIVE desktop $name diff=$negative coarse=$negativeCoarse")
        assertFalse(negative.identical, "$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다")
        assertTrue(negative.differingPixels in 1 until (actual.argb.size * maxChangedFraction).toInt(), "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
        assertFalse(negativeCoarse.withinTolerance, "$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)")
    }
}
