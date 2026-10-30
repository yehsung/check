// 첫 실행 화면(W-13 #5·#6) — 순수 모델이 DesktopSettingsStore 에 두 값을 쓰는지 · 언제 뜨는지 · 단추가 실제로 그 길을 타는지 · 스냅숏.
// 골든: desktopApp/src/test/kotlin/…/pages/onboarding/golden/first-run-<배율>-<밝기>.png (기록은 맥 arm64 — AINGCHECK_SNAPSHOT_RECORD=1).
package com.yehsung.aingcheck.desktop.pages.onboarding

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class FirstRunOnboardingTest {
    @Test
    fun `처음 — 띄울 때, 기본은 동의 꺼짐·자동 실행 켬`() {
        val kv = InMemoryDesktopKeyValueStore()
        val settings = DesktopSettingsStore(kv)
        val model = FirstRunModel(settings)
        assertTrue(model.pending.value)
        assertTrue(model.launchAtLogin.value, "W-13 #6 기본 켬")
        assertFalse(FirstRunModel.DEFAULT_CONSENT)
        assertFalse(settings.tokenUsageCollect.value, "첫 실행 전 동의는 거절(스캔 0)")
    }

    @Test
    fun `나중에 — 거절을 적고 자동 실행은 켬으로 적는다, 다시 안 뜬다`() {
        val kv = InMemoryDesktopKeyValueStore()
        val settings = DesktopSettingsStore(kv)
        val model = FirstRunModel(settings)
        assertEquals(FirstRunResult(consent = false, launchAtLogin = true), model.finish(consent = false))
        assertEquals(false, kv.getBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT), "없음이 아니라 거절이 적혀야 다시 안 묻는다")
        assertEquals(false, kv.getBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF))
        assertFalse(model.pending.value)
        assertFalse(settings.firstRunPending())
        assertNull(model.finish(consent = true), "두 번째 누름이 동의를 바꿨다")
        assertFalse(settings.tokenUsageCollect.value)
        assertFalse(FirstRunModel(DesktopSettingsStore(kv)).pending.value, "다시 켜도 또 뜬다")
    }

    @Test
    fun `켜기 + 자동 실행 끔 — 동의 참, 사용자가 끈 사실을 남긴다`() {
        val kv = InMemoryDesktopKeyValueStore()
        val settings = DesktopSettingsStore(kv)
        val model = FirstRunModel(settings)
        model.setLaunchAtLogin(false)
        assertEquals(FirstRunResult(consent = true, launchAtLogin = false), model.finish(consent = true))
        assertTrue(settings.tokenUsageCollect.value)
        assertFalse(settings.launchAtLogin.value)
        assertEquals(true, kv.getBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF))
    }

    @Test
    fun `띄울 때 — 동의·자동 실행 중 하나라도 없으면`() {
        fun pendingWith(vararg keys: String): Boolean {
            val kv = InMemoryDesktopKeyValueStore()
            for (k in keys) kv.putBoolean(k, false)
            return DesktopSettingsStore(kv).firstRunPending()
        }
        assertTrue(pendingWith())
        assertTrue(pendingWith(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT))
        assertTrue(pendingWith(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF))
        assertFalse(pendingWith(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF))
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun `단추 — 켜기를 누르면 동의가 적히고 조립 콜백이 동의를 받는다`() = runComposeUiTest {
        val settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        val results = mutableListOf<FirstRunResult>()
        val page = FirstRunOnboarding(settings) { results += it }
        setContent { AingTheme(dark = false) { page.Content(InMemoryFlyoutNavigator(), 414.0) } }
        onNodeWithText(FirstRunText.LAUNCH_TITLE).assertExists()
        onNodeWithTag(FirstRunTags.ALLOW).performClick()
        waitForIdle()
        assertEquals(listOf(FirstRunResult(consent = true, launchAtLogin = true)), results)
        assertTrue(settings.tokenUsageCollect.value)
        assertFalse(page.pending.value)
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun `단추 — 나중에는 동의 거절`() = runComposeUiTest {
        val settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        val results = mutableListOf<FirstRunResult>()
        val page = FirstRunOnboarding(settings) { results += it }
        setContent { AingTheme(dark = true) { page.Content(InMemoryFlyoutNavigator(), 414.0) } }
        onNodeWithTag(FirstRunTags.LATER).performClick()
        waitForIdle()
        assertEquals(listOf(FirstRunResult(consent = false, launchAtLogin = true)), results)
        assertFalse(settings.tokenUsageCollect.value)
    }

    // ── 스냅숏(100·150 × 밝음·어두움) ──
    private enum class Scale(val percent: Int, val density: Float) { S100(100, 1f), S150(150, 1.5f) }

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(dark: Boolean, scale: Scale): PixelImage {
        val page = FirstRunOnboarding(DesktopSettingsStore(InMemoryDesktopKeyValueStore()))
        val width = (WIDTH_DIP * scale.density).toInt()
        val height = (HEIGHT_DIP * scale.density).toInt()
        val ics = ImageComposeScene(width = width, height = height, density = Density(scale.density)) {
            AingTheme(dark = dark) { page.Content(InMemoryFlyoutNavigator(), WIDTH_DIP.toDouble()) }
        }
        try {
            var image: Image? = null
            for (i in 0 until FRAMES) {
                image?.close()
                image = ics.render(i * 16_666_667L)
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(width * height)
            for (y in 0 until height) for (x in 0 until width) pixels[y * width + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(width, height, pixels)
        } finally {
            ics.close()
        }
    }

    @Test
    fun firstRunScenes() {
        val failures = mutableListOf<String>()
        val recorded = mutableListOf<String>()
        for (dark in listOf(false, true)) for (scale in Scale.entries) {
            val name = "first-run-${scale.percent}-${if (dark) "dark" else "light"}"
            val actual = render(dark, scale)
            assertTrue(actual.distinctColors() > 2, "$name: 장면이 비었다")
            DesktopSnapshots.writePng(actual, File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/pages-onboarding/$name.png"))
            val file = File(DesktopSnapshots.mpRoot, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/pages/onboarding/golden/$name.png")
            if (DesktopSnapshots.recording()) {
                DesktopSnapshots.writePng(actual, file)
                recorded += name
                continue
            }
            if (!file.isFile) {
                failures += "$name: 골든 없음"
                continue
            }
            val expected = DesktopSnapshots.readPng(file)
            if (SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))) {
                val d = SnapshotCompare.diff(expected, actual)
                if (!d.identical) failures += "$name: $d"
            } else {
                val c = SnapshotCompare.coarse(expected, actual)
                if (!c.withinTolerance) failures += "$name: $c"
            }
        }
        if (recorded.isNotEmpty()) fail("기록 실행(${recorded.size}장) — 골든을 다시 썼다: $recorded")
        if (failures.isNotEmpty()) fail("스냅숏 ${failures.size}건: $failures")
    }

    private companion object {
        const val WIDTH_DIP = 414
        const val HEIGHT_DIP = 560
        const val FRAMES = 4
    }
}
