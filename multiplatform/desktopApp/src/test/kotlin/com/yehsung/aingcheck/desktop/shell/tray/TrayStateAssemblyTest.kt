// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift:51-62 @ a90d8623 (★1 대기 > 근무 > 오프, 시:분만)
//       · 골든 desktopApp/src/test/kotlin/…/platform/windows/golden/tray (W1-f 소유 — 여기선 **읽기만**, 기록하지 않는다)
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconRenderer
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconStatus
import java.io.File
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class TrayStateAssemblyTest {
    private val sizes = listOf(16, 20, 24, 28, 32)

    private fun goldenPixels(name: String): Triple<Int, Int, IntArray> {
        val mp = System.getProperty("aingcheck.mpRoot") ?: fail("aingcheck.mpRoot 시스템 속성이 없다")
        val f = File(mp, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/platform/windows/golden/tray/$name")
        val img = ImageIO.read(f) ?: fail("골든 PNG 를 못 읽었다: $f")
        val px = IntArray(img.width * img.height)
        img.getRGB(0, 0, img.width, img.height, px, 0, img.width)
        return Triple(img.width, img.height, px)
    }

    private fun work(sec: Long, pending: Boolean = false) = WorkStatusSnapshot(WorkStatus.working, sec, pending)
    private fun off(sec: Long = 0, pending: Boolean = false) = WorkStatusSnapshot(WorkStatus.offWork, sec, pending)

    /** 근무 값 → 조립 → 렌더 결과가 기존 골든과 픽셀까지 같다(초는 분으로 내려도 같은 그림). */
    @Test
    fun star1AssembledFramesMatchExistingTrayGoldens() {
        val cases = listOf(
            "working-0123" to (work(1 * 3600 + 23 * 60 + 59) to TrayDotReasons()),
            "working-1247-dot" to (work(12 * 3600 + 47 * 60 + 30) to TrayDotReasons(unreadMessages = true)),
            "off-dot" to (off() to TrayDotReasons(updateAvailable = true)),
            // 대기 > 근무: 근무 중이어도 대기면 대기 그림
            "pending" to (work(1 * 3600 + 23 * 60, pending = true) to TrayDotReasons()),
            // 대기 > 오프
            "pending" to (off(500, pending = true) to TrayDotReasons()),
        )
        var n = 0
        for (size in sizes) for (theme in TaskbarTheme.entries) for ((name, input) in cases) {
            val frame = TrayStateAssembly.frame(input.first, input.second, theme, size)
            val img = TrayIconRenderer.render(frame.spec)
            val (w, h, px) = goldenPixels("$name-${theme.name.lowercase()}-$size.png")
            assertEquals(w to h, img.width to img.height, "$name $theme $size 크기")
            val diff = px.indices.firstOrNull { px[it] != img.argb[it] }
            assertEquals(null, diff, "$name $theme $size: 픽셀 ${diff?.let { it % w to it / w }} 이 골든과 다르다")
            n++
        }
        assertEquals(50, n)
    }

    @Test
    fun star1PriorityPendingThenWorkingThenOff() {
        assertEquals(TrayIconStatus.Pending, TrayStateAssembly.status(work(100, pending = true)))
        assertEquals(TrayIconStatus.Pending, TrayStateAssembly.status(off(pending = true)))
        assertEquals(TrayIconStatus.Working(60), TrayStateAssembly.status(work(119)))
        assertEquals(TrayIconStatus.Off, TrayStateAssembly.status(off(4000)))
        assertEquals(TrayIconStatus.Working(0), TrayStateAssembly.status(work(-5)))
    }

    @Test
    fun star1TooltipIsHourMinuteWithDotReasonLine() {
        val t = TrayStateAssembly.frame(work(3 * 3600 + 7 * 60 + 42), TrayDotReasons(unreadMessages = true, updateAvailable = true), TaskbarTheme.DARK, 16).tooltip
        assertEquals("아잉체크 · 근무중 03:07\n새 메시지 · 업데이트 있음", t)
        assertTrue(!Regex("""\d\d:\d\d:\d\d""").containsMatchIn(t), "초를 말하지 않는다")
        assertEquals("아잉체크 · 근무종료", TrayStateAssembly.frame(off(), TrayDotReasons(), TaskbarTheme.LIGHT, 16).tooltip)
        val same = TrayStateAssembly.frame(work(600), TrayDotReasons(), TaskbarTheme.DARK, 20)
        assertEquals(same, TrayStateAssembly.frame(work(659), TrayDotReasons(), TaskbarTheme.DARK, 20), "같은 분이면 같은 장")
    }

    @Test
    fun tooltipClipsAt127Utf16UnitsWithoutSplittingSurrogates() {
        val long = "가".repeat(200)
        assertEquals(127, TrayStateAssembly.clip(long).length)
        val emoji = "a".repeat(126) + "\uD83D\uDE00" + "b"
        val clipped = TrayStateAssembly.clip(emoji)
        assertEquals(126, clipped.length)
        assertTrue(!Character.isHighSurrogate(clipped.last()))
    }
}
