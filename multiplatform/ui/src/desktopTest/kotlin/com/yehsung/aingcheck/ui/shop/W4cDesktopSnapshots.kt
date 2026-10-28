// 원본: 없음 — 상점 · 뽑기 · 미션 화면 스냅숏 하네스(데스크톱 오프스크린, java.awt.headless=true). 부품 진열장 시험(GallerySnapshotDesktopTest)과 같은 세 판정.
//
// 한 장면마다 세 가지를 잰다:
//  ① 같은 장면을 새로 세 번 그리면 픽셀이 같다(굳은 렌더 — 기억 imagerenderer-first-two-renders-differ)
//  ② 골든과 같다(기록은 AINGCHECK_SNAPSHOT_RECORD=1, 이 맥에서만 — 기록 실행은 실패로 끝난다). 기록 기계가 아닌 러너는 굵은 대조(SnapshotPolicy)
//  ③ 같은 크기에 한 군데만 다른 장면(음성 기준선)은 골든과 다르다 — 비교가 내용을 본다는 증거(기억 comparison-baseline-must-differ)
// 골든: ui/snapshots/<group>/desktop/<name>.png (group = shop · gacha · missions — 이 갈래 소유 자리).
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

object W4cDesktopSnapshots {
    val art: RepoMeArt by lazy {
        RepoMeArt { path -> File(DesktopSnapshots.repoRoot, path).takeIf { it.isFile }?.readBytes() }
    }

    /** 장면 틀: 그림 창구 · 테마 · 바탕 칠한 고정 크기 판. */
    fun frame(dark: Boolean, widthDp: Int, heightDp: Int, content: @Composable () -> Unit): @Composable () -> Unit = {
        CompositionLocalProvider(LocalMeArt provides art) {
            AingTheme(dark = dark) {
                Box(Modifier.size(widthDp.dp, heightDp.dp).background(AingTheme.colors.background)) { content() }
            }
        }
    }

    fun render(widthDp: Int, heightDp: Int, scene: @Composable () -> Unit): PixelImage = DesktopSnapshots.render(widthDp, heightDp, content = scene)

    /**
     * [maxChangedFraction] — 음성 기준선이 바꿔도 되는 픽셀 비율 상한(기본 1/10). 바뀐 한 군데가 넓은 판(고른 칸의 받침)이면 그 장면만 넓힌다.
     */
    fun check(group: String, name: String, widthDp: Int, heightDp: Int, scene: @Composable () -> Unit, baseline: @Composable () -> Unit, maxChangedFraction: Double = 0.1) {
        val renders = List(3) { render(widthDp, heightDp, scene) }
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
        val golden = DesktopSnapshots.golden(group, name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue(golden.isFile, "$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다")
        val expected = DesktopSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT desktop $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            DesktopSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다(${if (exact) "픽셀 그대로" else "굵은 대조"} — $diff · $coarse) — build/aingcheck-snapshots/desktop/$name-{actual,diff}.png")
        }
        val other = render(widthDp, heightDp, baseline)
        assertEquals(actual.width to actual.height, other.width to other.height, "$name: 기준선 크기가 다르다")
        val negative = SnapshotCompare.diff(actual, other)
        val negativeCoarse = SnapshotCompare.coarse(actual, other)
        println("AINGCHECK-SNAPSHOT-NEGATIVE desktop $name diff=$negative coarse=$negativeCoarse")
        assertFalse(negative.identical, "$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다")
        assertTrue(negative.differingPixels in 1 until (actual.argb.size * maxChangedFraction).toInt(), "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
        assertFalse(negativeCoarse.withinTolerance, "$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)")
    }
}
