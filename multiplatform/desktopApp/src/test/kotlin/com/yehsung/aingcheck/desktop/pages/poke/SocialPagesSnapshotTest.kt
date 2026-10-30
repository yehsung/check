// 원본: desktopApp/src/test/…/pages/shared/SharedPagesSnapshotDesktopTest.kt @ bcd545f7 (오프스크린 ImageComposeScene · 골든 대조 · 기록은 맥 arm64 만)
// W3-c3 콕 목록·울트라 페이지 스냅숏 — 배율 100·150 × 밝음·어두움. 장면은 값(ViewState)만 그린다(네트워크 0).
// 골든: pages/poke/golden/poke-<장면>-<배율>-<밝기>.png · pages/ultra/golden/ultra-<장면>-….png. 기록 실행(AINGCHECK_SNAPSHOT_RECORD=1)은 실패로 끝난다.
// 한눈 보기: desktopApp/build/aingcheck-snapshots/pages-social/contact-<배율>.png(윗줄 밝음 · 아랫줄 어두움).
package com.yehsung.aingcheck.desktop.pages.poke

import androidx.compose.runtime.Composable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.desktop.pages.focus.FocusModeControl
import com.yehsung.aingcheck.desktop.pages.focus.FocusModeText
import com.yehsung.aingcheck.desktop.pages.ultra.UltraContent
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPurchaseView
import com.yehsung.aingcheck.desktop.pages.ultra.UltraViewState
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageFace
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeRules
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail

class SocialPagesSnapshotTest {
    private enum class Scale(val percent: Int, val density: Float) { S100(100, 1f), S150(150, 1.5f) }

    private val failures = mutableListOf<String>()
    private val recorded = mutableListOf<String>()
    private val shots = linkedMapOf<String, PixelImage>()

    private fun golden(name: String): File {
        val lane = if (name.startsWith("ultra-")) "ultra" else "poke"
        return File(DesktopSnapshots.mpRoot, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/pages/$lane/golden/$name.png")
    }

    private fun outDir(): File = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/pages-social")

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(scale: Scale, dark: Boolean, content: @Composable () -> Unit): PixelImage {
        val w = (WIDTH_DIP * scale.density).toInt()
        val h = (HEIGHT_DIP * scale.density).toInt()
        val scene = ImageComposeScene(width = w, height = h, density = Density(scale.density)) {
            AingTheme(dark = dark) { content() }
        }
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

    private fun check(name: String, actual: PixelImage) {
        assertTrue(actual.distinctColors() > 2, "$name: 장면이 비었다(색 ${actual.distinctColors()})")
        shots[name] = actual
        DesktopSnapshots.writePng(actual, File(outDir(), "$name.png"))
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
        if (SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))) {
            val d = SnapshotCompare.diff(expected, actual)
            if (!d.identical) failures += "$name: $d"
        } else {
            val c = SnapshotCompare.coarse(expected, actual)
            if (!c.withinTolerance) failures += "$name: $c"
        }
    }

    private fun shoot(name: String, content: @Composable () -> Unit) {
        for (dark in listOf(false, true)) for (scale in Scale.entries) {
            check("$name-${scale.percent}-${if (dark) "dark" else "light"}", render(scale, dark, content))
        }
    }

    /** 장면 이름 순서대로 윗줄 밝음 · 아랫줄 어두움(사람이 한 장으로 본다). */
    private fun contactSheets(names: List<String>) {
        for (scale in Scale.entries) {
            val tiles = listOf("light", "dark").map { t -> names.map { n -> shots.getValue("$n-${scale.percent}-$t") } }
            val tw = tiles[0][0].width
            val th = tiles[0][0].height
            val gap = 8
            val w = names.size * tw + (names.size - 1) * gap
            val h = 2 * th + gap
            val px = IntArray(w * h) { 0xFF808080.toInt() }
            tiles.forEachIndexed { row, list ->
                list.forEachIndexed { col, img ->
                    for (y in 0 until th) for (x in 0 until tw) px[(row * (th + gap) + y) * w + col * (tw + gap) + x] = img.argb[y * tw + x]
                }
            }
            DesktopSnapshots.writePng(PixelImage(w, h, px), File(outDir(), "contact-${scale.percent}.png"))
        }
    }

    @Test
    fun `콕 목록·울트라 — 배율 100·150 × 밝음·어두움`() {
        val surfaces = SocialPageFlags.surfaces(DesktopAppConfig(poke = true, ultra = true))
        val noop: (String) -> Unit = {}
        @Composable
        fun poke(state: PokeListViewState, focus: FocusStageFace) {
            PokeListContent(state, {}, noop, noop, noop, {}, focusButton = { FocusModeControl(focus, {}) }, modifier = Modifier.fillMaxSize())
        }
        fun entry(id: String, name: String, working: Boolean, status: String? = null) =
            PokeDirectoryEntry(userID = id, name = name, avatarURL = null, isWorking = working, statusMessage = status)

        shoot("poke-empty") {
            poke(PokeListViewState(emptyList(), hasLoaded = true, notice = null, ultraBalance = 2, ultraUnlimited = false, surfaces = surfaces), FocusStageFace.OFF)
        }
        val timed = FocusStageFace(FocusStage.TIMED, 10_000)
        shoot("poke-many") {
            poke(
                PokeListViewState(
                    rows = listOf(
                        PokeRowView(entry("u1", "나비", false), PokeButtonState.TARGET_AWAY, PokeRowUnreadMark.MESSAGES),
                        PokeRowView(entry("u2", "다람", true, "집중해서 일하는 중"), PokeButtonState.READY, PokeRowUnreadMark.NONE),
                        PokeRowView(entry("u3", "라온", true), PokeButtonState.READY, PokeRowUnreadMark.POKES_ONLY),
                        PokeRowView(entry("u4", "바다", false), PokeButtonState.TARGET_AWAY, PokeRowUnreadMark.NONE),
                    ),
                    hasLoaded = true,
                    notice = PokeListRules.noticeLine(false, null, null, true, timed.stage),
                    ultraBalance = 3, ultraUnlimited = false, surfaces = surfaces,
                ),
                timed,
            )
        }
        shoot("poke-cooldown") {
            poke(
                PokeListViewState(
                    rows = listOf(
                        PokeRowView(entry("u2", "다람", true), PokeButtonState.READY, PokeRowUnreadMark.NONE),
                        PokeRowView(entry("u3", "라온", true), PokeButtonState.COOLDOWN, PokeRowUnreadMark.NONE),
                    ),
                    hasLoaded = true,
                    notice = PokeListRules.noticeLine(false, null, DesktopPokeRules.ULTRA_COOLDOWN_NOTICE, true, FocusStage.ALWAYS),
                    ultraBalance = 0, ultraUnlimited = false, surfaces = surfaces,
                ),
                FocusStageFace(FocusStage.ALWAYS),
            )
        }
        shoot("ultra-confirm") {
            UltraContent(
                UltraViewState(balance = 2, unlimited = false, failed = false, purchase = UltraPurchaseView(true, false, null, price = 30, ruby = 100, canConfirm = true)),
                {}, {}, {}, {}, rubyArt = null, modifier = Modifier.fillMaxSize(),
            )
        }
        shoot("ultra-short") {
            UltraContent(
                UltraViewState(balance = 0, unlimited = false, failed = false, purchase = UltraPurchaseView(true, false, null, price = 30, ruby = 10, canConfirm = false)),
                {}, {}, {}, {}, rubyArt = null, modifier = Modifier.fillMaxSize(),
            )
        }
        contactSheets(listOf("poke-empty", "poke-many", "poke-cooldown", "ultra-confirm", "ultra-short"))
        assertTrue(FocusModeText.label(timed) == "1단")
        if (recorded.isNotEmpty()) fail("기록 실행(${recorded.size}장) — 골든을 다시 썼다. 기록 실행은 초록으로 끝나지 않는다: $recorded")
        if (failures.isNotEmpty()) fail("스냅숏 불일치 ${failures.size}건:\n" + failures.joinToString("\n"))
    }

    private companion object {
        const val WIDTH_DIP = 340
        const val HEIGHT_DIP = 420
        const val FRAMES = 4
    }
}
