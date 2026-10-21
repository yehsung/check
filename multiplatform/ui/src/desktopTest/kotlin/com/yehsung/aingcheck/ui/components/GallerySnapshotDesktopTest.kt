// 부품 스냅숏(데스크톱 배율 2 × 밝음·어두움). 골든: ui/snapshots/{theme,components}/desktop/<장면>-<light|dark>.png
//
// 한 장면마다 세 가지를 잰다:
//  ① 같은 장면을 새로 세 번 그리면 픽셀이 같다(굳은 렌더 — 기억 imagerenderer-first-two-renders-differ)
//  ② 골든과 픽셀이 같다(기록은 AINGCHECK_SNAPSHOT_RECORD=1, 이 맥에서만 — 기록 실행은 실패로 끝난다)
//  ③ 같은 크기에 한 군데만 다른 장면(음성 기준선)은 골든과 다르다 — 비교가 내용을 본다는 증거(기억 comparison-baseline-must-differ)
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class GallerySnapshotDesktopTest {
    private val art by lazy { DesktopSnapshots.galleryArt() }
    private val width = GalleryFrame.desktopWidth.value.toInt()

    private fun themeScene(dark: Boolean, variant: GalleryVariant = GalleryVariant()): @Composable () -> Unit = {
        AingTheme(dark = dark) {
            ThemeGallery(art, Modifier.size(GalleryFrame.desktopWidth, GalleryFrame.themeHeight), variant)
        }
    }

    private fun componentsScene(dark: Boolean, variant: GalleryVariant = GalleryVariant()): @Composable () -> Unit = {
        AingTheme(dark = dark) {
            ComponentsGallery(art, Modifier.size(GalleryFrame.desktopWidth, GalleryFrame.componentsHeight), variant)
        }
    }

    @Test fun themeLight() = check("theme", "theme-light", GalleryFrame.themeHeight.value.toInt(), themeScene(false), themeScene(false, GalleryVariant(switchOn = false)))
    @Test fun themeDark() = check("theme", "theme-dark", GalleryFrame.themeHeight.value.toInt(), themeScene(true), themeScene(true, GalleryVariant(switchOn = false)))
    @Test fun componentsLight() = check("components", "components-light", GalleryFrame.componentsHeight.value.toInt(), componentsScene(false), componentsScene(false, GalleryVariant(rubyCount = 31)))
    @Test fun componentsDark() = check("components", "components-dark", GalleryFrame.componentsHeight.value.toInt(), componentsScene(true), componentsScene(true, GalleryVariant(rubyCount = 31)))

    private fun check(group: String, name: String, heightDp: Int, scene: @Composable () -> Unit, other: @Composable () -> Unit) {
        val renders = List(3) { DesktopSnapshots.render(width, heightDp, content = scene) }
        val out = DesktopSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], java.io.File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        // 장면이 실제로 그려졌다(빈 그림이면 세 장이 같아도 빈 비교다).
        assertTrue(actual.distinctColors() >= 64, "$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = DesktopSnapshots.golden(group, name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue(golden.isFile, "$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다")
        val expected = DesktopSnapshots.readPng(golden)
        val diff = SnapshotCompare.diff(expected, actual)
        println("AINGCHECK-SNAPSHOT desktop $name os=${System.getProperty("os.name")} arch=${System.getProperty("os.arch")} ${actual.width}x${actual.height} diff=$diff")
        if (!diff.identical) {
            DesktopSnapshots.writePng(actual, java.io.File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, java.io.File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff) — build/aingcheck-snapshots/desktop/$name-{actual,diff}.png")
        }
        // 음성 기준선: 같은 크기·한 군데만 다른 장면.
        val baseline = DesktopSnapshots.render(width, heightDp, content = other)
        assertEquals(actual.width to actual.height, baseline.width to baseline.height, "$name: 기준선 크기가 다르다 — 크기로 갈리는 비교는 빈 비교다")
        val negative = SnapshotCompare.diff(expected, baseline)
        assertFalse(negative.identical, "$name: 한 군데 다른 장면인데 골든과 같다 — 비교가 내용을 못 본다")
        assertTrue(negative.differingPixels in 1 until actual.argb.size / 10, "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
    }
}
