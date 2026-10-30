// 원본: Sources/check/CheckTodoBoardView.swift :470-472(바탕 = 재질 + CheckTheme.panel × tintAlpha) · :453(테두리 흰색 0.18) · :485(조절 버튼은 닫기 왼쪽) ·
//       :498-525(조절 행 — 슬라이더 0.20…0.95 · 0.05 · 퍼센트) · CheckTodoBoardAppearance.swift :323(backgroundLevel 합성 순서)
// 창 0 — ImageComposeScene·runComposeUiTest(오프스크린). 스냅숏: 바탕 밝음(순백 바탕화면 = 최악) · 어두움 × 100%·150%.
package com.yehsung.aingcheck.desktop.overlay.todoboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.jetbrains.skia.Bitmap
import java.io.File
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TodoBoardAppearanceViewTest {
    private val W = TodoBoardAnchor.BOARD_WIDTH.toInt()
    private val H = TodoBoardAnchor.BOARD_HEIGHT.toInt()
    private val today = "20260918"

    private fun item(n: Int, title: String, done: Boolean = false) =
        TodoItem("00000000-0000-4000-8000-00000000000$n", title, 1.0, 1.0, if (done) 2.0 else null, null, today)

    private fun state() = TodoBoardViewState(
        TodoBoardSections(listOf(item(1, "기획서 초안 보내기"), item(2, "점심 약속 확인", done = true)), emptyList()), today, draft = "",
    )

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(density: Float, content: @Composable () -> Unit): PixelImage {
        val w = (W * density).roundToInt()
        val h = (H * density).roundToInt()
        val scene = ImageComposeScene(w, h, Density(density), content = content)
        try {
            var image: org.jetbrains.skia.Image? = null
            for (i in 0 until 3) { image?.close(); image = scene.render(i * 16_666_667L) }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val px = IntArray(w * h)
            for (y in 0 until h) for (x in 0 until w) px[y * w + x] = bitmap.getColor(x, y)
            bitmap.close(); image.close()
            return PixelImage(w, h, px)
        } finally {
            scene.close()
        }
    }

    private fun gray(level: Double) = Color(level.toFloat(), level.toFloat(), level.toFloat())
    private fun channels(argb: Int) = intArrayOf((argb shr 16) and 0xFF, (argb shr 8) and 0xFF, argb and 0xFF)

    @Test
    fun translucentBoardOverLightAndDarkBackdropsAtOneAndOneAndAHalfX() {
        val out = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/todoboard-appearance").apply { mkdirs() }
        val backdrops = listOf("light" to 1.0, "dark" to 0.12)
        val cases = listOf(TodoBoardAppearance.DEFAULT_OPACITY, TodoBoardAppearance.MIN_OPACITY, TodoBoardAppearance.MAX_OPACITY)
        val bgSeen = HashMap<Pair<String, Double>, Int>()
        for ((name, backdrop) in backdrops) for (density in listOf(1f, 1.5f)) for (op in cases) {
            if (density != 1f && op != TodoBoardAppearance.DEFAULT_OPACITY) continue // 150% 는 출고값만
            val ap = TodoBoardAppearance(op)
            // 시스템 테마는 밝음이어도 보드는 어두움 고정(맥 :499) — 창이 AingTheme(dark = true) 를 건다.
            val img = render(density) {
                AingTheme(dark = true) {
                    Box(Modifier.size(W.dp, H.dp).background(gray(backdrop))) {
                        TodoBoardView(state(), TodoBoardActions(), autoFocusDraft = false, appearance = ap, initiallyExpandsOpacityRow = true)
                    }
                }
            }
            val pct = (op * 100).roundToInt()
            DesktopSnapshots.writePng(img, File(out, "board-$name-$pct-${if (density == 1f) "100" else "150"}.png"))
            fun at(x: Int, y: Int) = img.argb[(y * density).toInt() * img.width + (x * density).toInt()]
            // 바탕 = 바탕화면 → 재질 겹 → 패널 틴트(맥 backgroundLevel 순서) — 8비트 ±2.
            val expected = ap.backgroundOver(backdrop)
            val got = channels(at(6, 200))
            val want = intArrayOf((expected.r * 255).roundToInt(), (expected.g * 255).roundToInt(), (expected.b * 255).roundToInt())
            for (c in 0..2) assertTrue(abs(got[c] - want[c]) <= 2, "바탕 $name ${pct}% ${density}x 채널 $c: ${got[c]} ≠ ${want[c]}")
            if (density == 1f) bgSeen[name to op] = at(6, 200)
            // 둥근 모서리 밖은 바탕화면 그대로.
            assertEquals(channels(at(0, 0)).toList(), listOf(1, 1, 1).map { (backdrop * 255).roundToInt() }, "모서리 밖 $name")
        }
        // 진할수록 밝은 바탕이 덜 비친다 · 어두운 바탕 위에선 차이가 작다.
        fun lum(argb: Int) = channels(argb).sum()
        assertTrue(lum(bgSeen.getValue("light" to 0.20)) > lum(bgSeen.getValue("light" to 0.55)))
        assertTrue(lum(bgSeen.getValue("light" to 0.55)) > lum(bgSeen.getValue("light" to 0.95)))
        assertTrue(lum(bgSeen.getValue("light" to 0.20)) - lum(bgSeen.getValue("light" to 0.95)) > 3 * abs(lum(bgSeen.getValue("dark" to 0.20)) - lum(bgSeen.getValue("dark" to 0.95))))
    }

    private class MapKv : DesktopKeyValueStore {
        val m = HashMap<String, String>()
        override fun getString(key: String): String? = m[key]
        override fun putString(key: String, value: String?) { if (value == null) m.remove(key) else m[key] = value }
        override fun keys(prefix: String): List<String> = m.keys.filter { it.startsWith(prefix) }.sorted()
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun opacityButtonOpensTheRowAndTheSliderWritesTheMacKey() = runComposeUiTest {
        val f = BoardFixture()
        f.controller.open(OverlayRect(1200.0, 130.0, 140.0, 170.0), OverlayRect(0.0, 0.0, 1440.0, 900.0))
        val kv = MapKv().apply { m[TodoBoardAppearanceStore.DEFAULTS_KEY] = "0.4" }
        val store = TodoBoardAppearanceStore(kv)
        setContent { AingTheme(dark = true) { Box(Modifier.size(W.dp, H.dp)) { TodoBoardRoot(f.controller, appearanceStore = store) } } }
        // 평소엔 행이 없다(맥 :492).
        onNodeWithTag(TodoBoardTags.OPACITY_SLIDER).assertDoesNotExist()
        onNodeWithTag(TodoBoardTags.OPACITY_BUTTON).performClick()
        waitForIdle()
        onNodeWithText("40%").assertExists()
        onNodeWithTag(TodoBoardTags.OPACITY_SLIDER).performSemanticsAction(SemanticsActions.SetProgress) { it(0.7f) }
        waitForIdle()
        assertEquals(0.7, store.appearance.opacity, 1e-9)
        assertEquals("0.7", kv.m[TodoBoardAppearanceStore.DEFAULTS_KEY])
        onNodeWithText("70%").assertExists()
        // 바깥에서 바뀐 값도 따라온다(⌥+스크롤 길과 같은 스토어).
        store.nudge(-TodoBoardAppearance.STEP * 20)
        waitForIdle()
        onNodeWithText("20%").assertExists()
        onNodeWithTag(TodoBoardTags.OPACITY_BUTTON).performClick()
        waitForIdle()
        onNodeWithTag(TodoBoardTags.OPACITY_SLIDER).assertDoesNotExist()
    }
}
