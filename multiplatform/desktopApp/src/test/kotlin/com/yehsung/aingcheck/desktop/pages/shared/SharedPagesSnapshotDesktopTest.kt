// 원본: multiplatform/ui/src/desktopTest/…/screens/settingscommon/ScreenSnapshotDesktopTest.kt @ a90d8623 (장면 · 밝음/어두움 · 골든 대조)
//
// W3-c0 SharedPagesSnapshotDesktopTest — 플라이아웃 페이지 호스트(SharedFlyoutPageHost.Content)를 데스크톱 폭 414 DIP 로 오프스크린
// (ImageComposeScene, java.awt.headless) 그려 골든과 픽셀 대조한다. 배율 100·150(밀도 1 · 1.5) × 밝음·어두움.
// 골든: desktopApp/src/test/kotlin/…/pages/shared/golden/<페이지>-<배율>-<밝기>.png. 기록은 맥 arm64 에서만
// (AINGCHECK_SNAPSHOT_RECORD=1 — 기록 실행은 실패로 끝난다). 다른 러너는 굵은 대조(testsupport SnapshotCompare.coarse — W-3 #19 임시 사본).
// 장면은 진짜 스토어 + 합성 스텁 서버(SharedTestHarness)다 — 화면을 흉내 낸 가짜가 아니라 조립이 부를 그 호스트를 그린다.
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail

@OptIn(ExperimentalCoroutinesApi::class)
class SharedPagesSnapshotDesktopTest {
    private enum class Scale(val percent: Int, val density: Float) { S100(100, 1f), S150(150, 1.5f) }

    private val failures = mutableListOf<String>()
    private val recorded = mutableListOf<String>()

    private fun golden(name: String): File =
        File(DesktopSnapshots.mpRoot, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/pages/shared/golden/$name.png")

    private fun outFile(name: String): File = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/pages-shared/$name.png")

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(h: SharedTestHarness, scale: Scale): PixelImage {
        val w = (WIDTH_DIP * scale.density).toInt()
        val ht = (HEIGHT_DIP * scale.density).toInt()
        val scene = ImageComposeScene(width = w, height = ht, density = Density(scale.density)) {
            h.host.Content(h.nav, WIDTH_DIP.toDouble())
        }
        try {
            var image: Image? = null
            for (i in 0 until FRAMES) {
                image?.close()
                image = scene.render(i * 16_666_667L)
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(w * ht)
            for (y in 0 until ht) for (x in 0 until w) pixels[y * w + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(w, ht, pixels)
        } finally {
            scene.close()
        }
    }

    private fun check(name: String, actual: PixelImage) {
        assertTrue(actual.distinctColors() > 2, "$name: 장면이 비었다(색 ${actual.distinctColors()})")
        DesktopSnapshots.writePng(actual, outFile(name))
        val file = golden(name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, file)
            recorded += name
            return
        }
        if (!file.isFile) {
            failures += "$name: 골든 없음($file)"
            return
        }
        val expected = DesktopSnapshots.readPng(file)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        if (exact) {
            val d = SnapshotCompare.diff(expected, actual)
            if (!d.identical) failures += "$name: $d"
        } else {
            val c = SnapshotCompare.coarse(expected, actual)
            if (!c.withinTolerance) failures += "$name: $c"
        }
    }

    /** 한 장면을 배율 둘로. [prepare] 는 하네스를 그 장면까지 데려간다(밝기마다 새 하네스 — 설정 저장소가 밝기를 쥔다). */
    private suspend fun TestScope.shoot(name: String, dark: Boolean, answer: (String) -> String?, prepare: suspend TestScope.(SharedTestHarness) -> Unit) {
        val h = SharedTestHarness(this, answer = answer, dark = dark)
        prepare(h)
        advanceUntilIdle()
        for (scale in Scale.entries) check("$name-${scale.percent}-${if (dark) "dark" else "light"}", render(h, scale))
        advanceUntilIdle()
    }

    private suspend fun TestScope.both(name: String, answer: (String) -> String? = { null }, prepare: suspend TestScope.(SharedTestHarness) -> Unit) {
        shoot(name, false, answer, prepare)
        shoot(name, true, answer, prepare)
    }

    @Test
    fun `공용 페이지 — 배율 100·150 × 밝음·어두움`() = runTest {
        both("launch") { h -> h.nav.open(FlyoutRoute.Home) }
        both("needs-update", { p -> if (p.endsWith("/rpc/client_release")) SharedTestHarness.RELEASE_NEEDS_UPDATE else null }) { h ->
            h.session.launch()
            h.nav.open(FlyoutRoute.Home)
        }
        both("signed-out") { h ->
            h.session.launch()
            h.nav.open(FlyoutRoute.Home)
        }
        both("teamless", SharedTestHarness.teamless) { h ->
            h.signIn()
            advanceUntilIdle()
            h.nav.open(FlyoutRoute.Home)
        }
        both("messages", SharedTestHarness.withTeam) { h ->
            h.signIn()
            advanceUntilIdle()
            h.nav.open(FlyoutRoute.Messages)
        }
        both("pending-home", SharedTestHarness.withTeam) { h ->
            h.signIn()
            advanceUntilIdle()
            h.nav.open(FlyoutRoute.Home)
        }
        if (recorded.isNotEmpty()) fail("기록 실행(${recorded.size}장) — 골든을 다시 썼다. 기록 실행은 초록으로 끝나지 않는다: $recorded")
        if (failures.isNotEmpty()) fail("스냅숏 불일치 ${failures.size}건:\n" + failures.joinToString("\n"))
    }

    @Test
    fun `숨은 플라이아웃은 페이지를 그리지 않는다 — 배경색 한 가지`() = runTest {
        val h = SharedTestHarness(this, answer = SharedTestHarness.withTeam)
        h.signIn()
        advanceUntilIdle()
        h.nav.open(FlyoutRoute.Home)
        val shown = render(h, Scale.S100)
        h.nav.hide()
        val hidden = render(h, Scale.S100)
        assertTrue(shown.distinctColors() > 2, "보일 때 장면이 있다")
        assertTrue(hidden.distinctColors() <= 1, "숨김: 색 ${hidden.distinctColors()}가지")
    }

    companion object {
        const val WIDTH_DIP = 414
        const val HEIGHT_DIP = 600
        const val FRAMES = 4
    }
}
