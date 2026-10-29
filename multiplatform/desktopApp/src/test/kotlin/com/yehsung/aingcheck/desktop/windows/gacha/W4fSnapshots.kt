// W4-f 오프스크린 스냅숏(ImageComposeScene — 창 0). 비교 정책은 testsupport 임시 사본(W-3 #19) 그대로:
// 기록 맥(Mac aarch64)은 픽셀 그대로, 그 밖 러너는 굵은 대조. 매 장면 음성 대조 — 한 군데 다른 기준선이 반드시 빨개져야 한다.
// 골든은 갈래 글롭 아래 `<자리>/golden/<이름>.png`(W1-f tray·flyout 선례). 기록: AINGCHECK_SNAPSHOT_RECORD=1 로 한 번(실패로 끝난다).
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.desktop.testsupport.DesktopSnapshots
import com.yehsung.aingcheck.desktop.testsupport.PixelImage
import com.yehsung.aingcheck.desktop.testsupport.SnapshotCompare
import com.yehsung.aingcheck.desktop.testsupport.SnapshotPolicy
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

object W4fSnapshots {
    private const val TEST_ROOT = "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop"

    /** [area] = 테스트 패키지 아래 자리(예 "pages/shop", "windows/gacha"). */
    fun golden(area: String, name: String): File = File(DesktopSnapshots.mpRoot, "$TEST_ROOT/$area/golden/$name.png")

    /** [maxChangedFraction] — 기준선이 바꿔도 되는 픽셀 비율 상한(기본 1/10). 바뀐 한 군데가 넓은 판(고른 칸의 받침)이면 그 장면만 넓힌다. */
    fun check(
        area: String, name: String, widthDp: Int, heightDp: Int, scene: @Composable () -> Unit, baseline: @Composable () -> Unit,
        maxChangedFraction: Double = 0.1,
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
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT desktop $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
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
