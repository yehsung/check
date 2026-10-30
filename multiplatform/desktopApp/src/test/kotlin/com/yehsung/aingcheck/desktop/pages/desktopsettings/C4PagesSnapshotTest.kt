package com.yehsung.aingcheck.desktop.pages.desktopsettings

import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsFixture
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsFlyoutPage
import com.yehsung.aingcheck.desktop.pages.aitokens.AiTokensFlyoutPage
import com.yehsung.aingcheck.desktop.pages.aitokens.AiTokensPageDeps
import com.yehsung.aingcheck.desktop.pages.devices.DevicesFlyoutPage
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail

/** c4 네 페이지 × 100·150% × 밝음·어두움. 기록: AINGCHECK_SNAPSHOT_RECORD=1. 장면은 합성(실제 홈·서버 0). */
class C4PagesSnapshotTest {
    private enum class Scale(val percent: Int, val density: Float) { S100(100, 1f), S150(150, 1.5f) }

    private val failures = mutableListOf<String>()

    private fun golden(pkg: String, name: String) =
        File(DesktopSnapshots.mpRoot, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/pages/$pkg/golden/$name.png")

    private fun outFile(name: String) = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/pages-c4/$name.png")

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(scale: Scale, heightDip: Int, content: @Composable () -> Unit): PixelImage {
        val w = (WIDTH_DIP * scale.density).toInt()
        val h = (heightDip * scale.density).toInt()
        val scene = ImageComposeScene(width = w, height = h, density = Density(scale.density)) { content() }
        try {
            var image: Image? = null
            for (i in 0 until FRAMES) {
                image?.close()
                image = scene.render(i * 16_666_667L)
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(w * h)
            for (y in 0 until h) for (x in 0 until w) pixels[y * w + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(w, h, pixels)
        } finally {
            scene.close()
        }
    }

    private fun check(pkg: String, name: String, actual: PixelImage) {
        assertTrue(actual.distinctColors() > 2, "$name: 장면이 비었다")
        DesktopSnapshots.writePng(actual, outFile(name))
        val file = golden(pkg, name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, file)
            return
        }
        if (!file.isFile) {
            failures += "$name: 골든 없음($file)"
            return
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

    private fun shoot(pkg: String, name: String, heightDip: Int, page: () -> FlyoutPageHost) {
        for (dark in listOf(false, true)) for (scale in Scale.entries) {
            val host = page() // 밝기·배율마다 새 장면(상태가 장면 사이로 새지 않게)
            val nav = InMemoryFlyoutNavigator(FlyoutRoute.Home)
            check(pkg, "$name-${scale.percent}-${if (dark) "dark" else "light"}", render(scale, heightDip) {
                AingTheme(dark = dark) { host.Content(nav, WIDTH_DIP.toDouble()) }
            })
        }
    }

    private fun usage() = TokenUsageMonthly(month = "2026-10", claudeInput = 900_000, claudeOutput = 134_567, codexInput = 180_000, codexOutput = 20_000)

    private fun tokensPage(consent: Boolean): FlyoutPageHost {
        val settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore()).apply { setTokenUsageCollect(consent) }
        return AiTokensFlyoutPage(
            AiTokensPageDeps(
                settings = settings,
                usage = MutableStateFlow(if (consent) usage() else null),
                scanning = MutableStateFlow(false),
                account = { null },
                serverRow = { null },
                userID = { "u1" },
                currentMonth = { "2026-10" },
                onConsentGranted = {},
            ),
        )
    }

    @Test
    fun c4Pages() {
        shoot("desktopsettings", "desktop-settings", 1080) {
            val settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore()).apply {
                setTokenUsageCollect(true)
                setHotkey(HotkeyChord(ctrl = true, alt = true, shift = false, win = false, keyCode = 0x4B))
                noteHotkeyStatus(HotkeyRegistrationStatus.CONFLICT)
            }
            val limits = AiLimitsFixture.store()
            DesktopSettingsFlyoutPage(DesktopSettingsDeps(settings, limits, AiLimitsFixture.FakeActions(limits)))
        }
        shoot("aitokens", "ai-tokens", 420) { tokensPage(consent = true) }
        shoot("aitokens", "ai-tokens-consent", 420) { tokensPage(consent = false) }
        shoot("ailimits", "ai-limits", 520) {
            val limits = AiLimitsFixture.store()
            AiLimitsFlyoutPage(limits, AiLimitsFixture.FakeActions(limits), clock = { AiLimitsFixture.now }, zone = AiLimitsFixture.seoul)
        }
        shoot("devices", "devices", 320) {
            val limits = AiLimitsFixture.store()
            DevicesFlyoutPage(limits, AiLimitsFixture.FakeActions(limits))
        }
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    private companion object {
        const val WIDTH_DIP = 380
        const val FRAMES = 4
    }
}
