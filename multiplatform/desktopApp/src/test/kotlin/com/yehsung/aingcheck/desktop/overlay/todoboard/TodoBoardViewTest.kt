// 원본: Tests/checkTests/CheckTodoBoardViewTests.swift:214-311(스냅숏) · :680-799(빈 상태 가운데) · TodoBoardIntegrationTests.swift(입력 왕복) @ ef9fab11
// 창 0 — ImageComposeScene·runComposeUiTest(오프스크린, java.awt.headless=true).
package com.yehsung.aingcheck.desktop.overlay.todoboard

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.doubleClick
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.jetbrains.skia.Bitmap
import java.io.File
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TodoBoardViewTest {
    private val W = TodoBoardAnchor.BOARD_WIDTH.toInt()
    private val H = TodoBoardAnchor.BOARD_HEIGHT.toInt()

    // ───────────────────────── 입력 왕복(가짜 파일 위 실제 TodoListStore) ─────────────────────────

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun typingEnterCheckEditEscapeAndUndoDriveTheStore() = runComposeUiTest {
        val f = BoardFixture()
        f.controller.open(OverlayRect(1200.0, 130.0, 140.0, 170.0), OverlayRect(0.0, 0.0, 1440.0, 900.0))
        setContent { AingTheme(dark = true) { Box(Modifier.size(W.dp, H.dp)) { TodoBoardRoot(f.controller) } } }

        // 추가: 적고 Enter.
        onNodeWithTag(TodoBoardTags.DRAFT).performTextInput("우유 사기")
        onNodeWithTag(TodoBoardTags.DRAFT).performKeyInput { pressKey(Key.Enter) }
        waitForIdle()
        val id = f.store.items.single().id
        assertEquals("우유 사기", f.store.items.single().title)
        assertEquals("", f.controller.ui.draft)

        // 완료: 체크 원.
        onNodeWithTag(TodoBoardTags.check(id)).performClick()
        waitForIdle()
        assertTrue(f.store.items.single().isDone)
        onNodeWithTag(TodoBoardTags.check(id)).performClick()
        waitForIdle()

        // 편집: 두 번 눌러 열고 Esc 로 취소.
        onNodeWithTag(TodoBoardTags.title(id)).performTouchInput { doubleClick() }
        waitForIdle()
        assertEquals(id, f.controller.ui.editingID)
        onNodeWithTag(TodoBoardTags.editor(id)).performKeyInput { pressKey(Key.Escape) }
        waitForIdle()
        assertNull(f.controller.ui.editingID)
        assertEquals("우유 사기", f.store.items.single().title)

        // 편집: 고쳐 Enter.
        onNodeWithTag(TodoBoardTags.title(id)).performTouchInput { doubleClick() }
        waitForIdle()
        onNodeWithTag(TodoBoardTags.editor(id)).performTextClearance()
        onNodeWithTag(TodoBoardTags.editor(id)).performTextInput("두부 사기")
        onNodeWithTag(TodoBoardTags.editor(id)).performKeyInput { pressKey(Key.Enter) }
        waitForIdle()
        assertEquals("두부 사기", f.store.items.single().title)
        assertNull(f.controller.ui.editingID)

        // 지우기 → '삭제됨 [되돌리기]' → 되돌리기.
        onNodeWithTag(TodoBoardTags.delete(id)).performClick()
        waitForIdle()
        assertEquals(id, f.controller.ui.pendingDeleteID)
        onNodeWithTag(TodoBoardTags.undo(id)).performClick()
        waitForIdle()
        assertNull(f.controller.ui.pendingDeleteID)
        assertNull(f.store.items.single().deletedAt)

        // 닫기 단추.
        onNodeWithTag(TodoBoardTags.CLOSE).performClick()
        waitForIdle()
        assertTrue(!f.controller.isOpen())
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun emptyStateIsCentredInTheListAreaAndStopsCentringOnceThereAreRows() = runComposeUiTest {
        val f = BoardFixture()
        setContent { AingTheme(dark = true) { Box(Modifier.size(W.dp, H.dp)) { TodoBoardRoot(f.controller) } } }
        val b = onNodeWithTag(TodoBoardTags.EMPTY).getBoundsInRoot()
        val cx = (b.left + b.right).value / 2
        assertTrue(abs(cx - W / 2f) <= 1f, "빈 상태 가로 중심 $cx ≠ ${W / 2}")
        val cy = (b.top + b.bottom).value / 2
        // 목록 영역(입력칸 아래 ~ 바닥 캡션 위)의 가운데 근처 — 위에 붙지 않는다.
        assertTrue(cy > 160f && cy < 300f, "빈 상태 세로 중심 $cy 가 목록 영역 가운데가 아니다")
        f.add("하나")
        waitForIdle()
        onNodeWithTag(TodoBoardTags.EMPTY).assertDoesNotExist() // 항목이 생기면 빈 상태는 사라진다
    }

    // ───────────────────────── 스냅숏: 밝음·어둠 × 1x·2x(테마 토큰만) ─────────────────────────

    private fun fixtureState(): TodoBoardViewState {
        val today = "20260921"
        fun item(n: Int, title: String, done: Boolean = false, origin: String = today) =
            TodoItem("00000000-0000-4000-8000-00000000000$n", title, 1.0, 1.0, if (done) 2.0 else null, null, origin)
        val items = listOf(item(1, "기획서 초안 보내기"), item(2, "점심 약속 확인", done = true), item(3, "이월된 일", origin = "20260918"))
        return TodoBoardViewState(TodoBoardSections(items, emptyList()), today, draft = "", pendingDeleteID = null)
    }

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(density: Float, content: @Composable () -> Unit): PixelImage {
        val w = (W * density).toInt()
        val h = (H * density).toInt()
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

    private fun luminance(argb: Int): Double = 0.2126 * ((argb shr 16) and 0xFF) + 0.7152 * ((argb shr 8) and 0xFF) + 0.0722 * (argb and 0xFF)

    @Test
    // ★2 CheckTodoBoardWindow.swift:495 — 맥 보드는 어두운 외관 고정(재질이 시스템 외관을 따라가 밝은 테마에서 흰 글자 대비가 무너져서).
    //    Windows 1차엔 재질(블러·틴트)이 없어 테마 토큰을 따른다(overlay.md §5 밝음·어둠). 외양 갈래(W-3 #9)가 재질을 넣을 때 다시 정한다.
    fun boardSnapshotsInLightAndDarkAtOneAndTwoX() {
        val out = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/todoboard").apply { mkdirs() }
        val surfaceLum = HashMap<Boolean, Double>()
        for (dark in listOf(false, true)) for (density in listOf(1f, 2f)) {
            val state = fixtureState()
            val img = render(density) { AingTheme(dark = dark) { TodoBoardView(state, TodoBoardActions(), autoFocusDraft = false) } }
            DesktopSnapshots.writePng(img, File(out, "board-${if (dark) "dark" else "light"}-${density.toInt()}x.png"))
            assertEquals((W * density).toInt(), img.width)
            assertEquals((H * density).toInt(), img.height)
            fun at(xDp: Int, yDp: Int) = img.argb[(yDp * density).toInt() * img.width + (xDp * density).toInt()]
            assertEquals(0, at(0, 0) ushr 24, "둥근 모서리 밖은 투명($dark ${density}x)")
            val token = AingColors.of(dark).surface.toArgb()
            // 왼쪽 여백(패딩 12 안쪽, 글자 없는 자리)은 테마 토큰 surface 그대로.
            assertEquals(token, at(6, 200), "바탕은 AingColors.surface 토큰($dark ${density}x)")
            surfaceLum[dark] = luminance(token)
            // 머리 줄(제목 글자)에 바탕과 다른 픽셀이 있다.
            var ink = 0
            for (y in (14 * density).toInt() until (34 * density).toInt()) for (x in (12 * density).toInt() until (90 * density).toInt()) {
                if (img.argb[y * img.width + x] != token) ink++
            }
            assertTrue(ink > 20 * density * density, "제목 글자가 그려지지 않았다($dark ${density}x, ink=$ink)")
        }
        assertTrue(surfaceLum.getValue(true) < surfaceLum.getValue(false), "어둠 바탕이 밝음보다 어둡다")
    }

    // ───────────────────────── 색 리터럴 0(D5) ─────────────────────────

    @Test
    fun todoBoardSourcesUseThemeTokensOnly() {
        val dir = File(DesktopSnapshots.mpRoot, "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/overlay/todoboard")
        val files = dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue(files.size >= 5, "보드 소스를 못 찾았다: $dir")
        val hits = files.flatMap { f ->
            f.readLines().mapIndexedNotNull { i, line ->
                val code = line.substringBefore("//")
                if (Regex("""Color\(\s*0x""").containsMatchIn(code) || Regex("""Color\.(White|Black|Red|Gray|Blue)\b""").containsMatchIn(code)) "${f.name}:${i + 1}" else null
            }
        }
        assertEquals(emptyList(), hits, "보드 색은 AingTheme.colors 토큰만")
    }

    @Test
    fun snapshotFixtureSanity() {
        assertNotNull(fixtureState().sections.active.firstOrNull { it.originDayKey != "20260921" })
    }
}
