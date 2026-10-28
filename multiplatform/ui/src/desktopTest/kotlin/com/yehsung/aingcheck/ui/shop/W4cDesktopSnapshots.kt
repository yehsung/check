// 원본: 없음 — 상점 · 뽑기 · 미션 화면 스냅숏 하네스(데스크톱 오프스크린, java.awt.headless=true). 부품 진열장 시험(GallerySnapshotDesktopTest)과 같은 세 판정.
//
// 한 장면마다 세 가지를 잰다:
//  ① 같은 장면을 새로 세 번 그리면 픽셀이 같다(굳은 렌더 — 기억 imagerenderer-first-two-renders-differ)
//  ② 골든과 같다(기록은 AINGCHECK_SNAPSHOT_RECORD=1, 이 맥에서만 — 기록 실행은 실패로 끝난다). 기록 기계가 아닌 러너는 굵은 대조(SnapshotPolicy)
//  ③ 같은 크기에 한 군데만 다른 장면(음성 기준선)은 골든과 다르다 — 비교가 내용을 본다는 증거(기억 comparison-baseline-must-differ)
// 골든: ui/snapshots/<group>/desktop/<name>.png (group = shop · gacha · missions — 이 갈래 소유 자리).
//
// OS 그림 글자 칸([check] platformGlyphs): 그림 글자(🎂)는 OS 글꼴로 그려진다(맥 Apple Color Emoji · Linux Noto/없음 · Windows Segoe) —
// 래스터라이저 차이가 아니라 **다른 그림**이라 굵은 대조로도 녹지 않는다(CI 실측: cake-gift-light 칸 최대 156 · 171). 그래서 기록 기계가 아닌
// 러너의 굵은 대조에서만 그 칸(고정 크기 — 글자 자리는 그 칸 폭과 무관하게 만든다)을 골든 픽셀로 덮는다. 기록 기계(맥)는 언제나 통째 픽셀 그대로.
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpRect
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
     * [platformGlyphs] — OS 그림 글자 칸(dp, 장면 좌표). 기록 기계가 아닌 러너의 굵은 대조에서만 골든 픽셀로 덮는다(머리말). 합쳐 화면의 1% 이하.
     */
    fun check(
        group: String, name: String, widthDp: Int, heightDp: Int, scene: @Composable () -> Unit, baseline: @Composable () -> Unit,
        maxChangedFraction: Double = 0.1, platformGlyphs: List<DpRect> = emptyList(),
    ) {
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
        val glyphPx = platformGlyphs.map { it.toPx(actual.width, actual.height) }
        assertTrue(glyphPx.sumOf { (it.last - it.first + 1) * (it.bottom - it.top + 1) } <= actual.argb.size / 100, "$name: 그림 글자 칸이 화면의 1% 를 넘는다($glyphPx)")
        val coarse = SnapshotCompare.coarse(expected, if (exact) actual else actual.withRegionsFrom(expected, glyphPx))
        val maskNote = if (exact || glyphPx.isEmpty()) "" else " glyphMask=$glyphPx"
        println("AINGCHECK-SNAPSHOT desktop $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse$maskNote")
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

    /** 픽셀 칸(가로 first..last · 세로 top..bottom, 양끝 포함). 그림 글자 가장자리 번짐 몫으로 4px 넓힌다. */
    data class PxRect(val first: Int, val top: Int, val last: Int, val bottom: Int)

    private fun DpRect.toPx(width: Int, height: Int): PxRect {
        val k = DesktopSnapshots.DENSITY
        val pad = 4
        return PxRect(
            ((left.value * k).toInt() - pad).coerceAtLeast(0), ((top.value * k).toInt() - pad).coerceAtLeast(0),
            ((right.value * k).toInt() + pad).coerceAtMost(width - 1), ((bottom.value * k).toInt() + pad).coerceAtMost(height - 1),
        )
    }

    /** [regions] 안 픽셀만 [source] 것으로 바꾼 사본(원본은 그대로). */
    private fun PixelImage.withRegionsFrom(source: PixelImage, regions: List<PxRect>): PixelImage {
        if (regions.isEmpty()) return this
        val out = argb.copyOf()
        for (r in regions) for (y in r.top..r.bottom) for (x in r.first..r.last) out[y * width + x] = source.argb[y * width + x]
        return PixelImage(width, height, out)
    }
}
