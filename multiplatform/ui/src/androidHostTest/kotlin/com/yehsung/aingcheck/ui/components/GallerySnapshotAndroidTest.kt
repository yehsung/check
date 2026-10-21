// 원본: Sources/CheckMobileKit/Components/MobileComponentsGallery.swift @ 862be0f (진열장 장면 — 스냅숏은 이식 시험)
//
// 부품 스냅숏(폰 = Android xhdpi 배율 2 × 밝음·어두움). 골든: ui/snapshots/{theme,components}/android/<장면>-<light|dark>.png
// 데스크톱 판(GallerySnapshotDesktopTest)과 같은 세 가지를 잰다: ① 새로 세 번 그려도 같다 ② 골든과 같다 ③ 한 군데 다른 같은 크기 장면은 다르다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h1000dp-xhdpi")
class GallerySnapshotAndroidTest {
    private val art by lazy { AndroidSnapshots.galleryArt() }

    private fun themeScene(dark: Boolean, variant: GalleryVariant = GalleryVariant()): @Composable () -> Unit = {
        AingTheme(dark = dark) { ThemeGallery(art, Modifier.size(GalleryFrame.phoneWidth, GalleryFrame.themeHeight), variant) }
    }

    private fun componentsScene(dark: Boolean, variant: GalleryVariant = GalleryVariant()): @Composable () -> Unit = {
        AingTheme(dark = dark) { ComponentsGallery(art, Modifier.size(GalleryFrame.phoneWidth, GalleryFrame.componentsHeight), variant) }
    }

    @Test fun themeLight() = check("theme", "theme-light", themeScene(false), themeScene(false, GalleryVariant(switchOn = false)))
    @Test fun themeDark() = check("theme", "theme-dark", themeScene(true), themeScene(true, GalleryVariant(switchOn = false)))
    @Test fun componentsLight() = check("components", "components-light", componentsScene(false), componentsScene(false, GalleryVariant(rubyCount = 31)))
    @Test fun componentsDark() = check("components", "components-dark", componentsScene(true), componentsScene(true, GalleryVariant(rubyCount = 31)))

    @OptIn(ExperimentalTestApi::class)
    private fun render(content: @Composable () -> Unit): PixelImage {
        var out: PixelImage? = null
        runComposeUiTest {
            setContent {
                Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) { content() }
            }
            waitForIdle()
            out = AndroidSnapshots.pixels(onNodeWithTag(TAG).captureToImage())
        }
        return requireNotNull(out)
    }

    private fun check(group: String, name: String, scene: @Composable () -> Unit, other: @Composable () -> Unit) {
        val renders = List(3) { render(scene) }
        val out = AndroidSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                AndroidSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertTrue("$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다", actual.distinctColors() >= 64)
        val golden = AndroidSnapshots.golden(group, name)
        if (AndroidSnapshots.recording()) {
            AndroidSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue("$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다", golden.isFile)
        val expected = AndroidSnapshots.readPng(golden)
        // 기록 기계(macOS arm64)는 픽셀 그대로, 다른 러너는 굵은 대조(SnapshotPolicy — 데스크톱 판과 같은 판정·문턱 64, A§4-3·G §8-13).
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT android $name os=${System.getProperty("os.name")} arch=${System.getProperty("os.arch")} mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            AndroidSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { AndroidSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다(${if (exact) "픽셀 그대로" else "굵은 대조"} — $diff · $coarse) — build/aingcheck-snapshots/android/$name-{actual,diff}.png")
        }
        val baseline = render(other)
        assertEquals("$name: 기준선 크기가 다르다 — 크기로 갈리는 비교는 빈 비교다", actual.width to actual.height, baseline.width to baseline.height)
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android $name diff=$negative coarse=$negativeCoarse")
        assertFalse("$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다", negative.identical)
        assertTrue("$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다", negative.differingPixels in 1 until actual.argb.size / 10)
        assertFalse("$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)", negativeCoarse.withinTolerance)
    }

    private companion object {
        const val TAG = "aingcheck-scene"
    }
}
