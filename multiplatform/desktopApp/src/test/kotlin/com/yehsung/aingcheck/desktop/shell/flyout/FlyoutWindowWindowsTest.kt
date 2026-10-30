// 원본: 없음(새 시험) — xplat-w1/briefs/shell.md §5 Windows 러너: 자식 JVM 에서 WS_EX_TOOLWINDOW 비트 · GetWindowRect = FlyoutPlacer.place
//       (시험 JVM 은 java.awt.headless=true — 창은 자식 JVM 에서만 만든다). 성공은 우리 상태값이 아니라 OS 에 다시 물어서 잰다.
package com.yehsung.aingcheck.desktop.shell.flyout

import com.sun.jna.Native
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.platform.windows.flyout.TaskbarProbe
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import javax.swing.JPanel
import javax.swing.SwingUtilities
import kotlin.system.exitProcess
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

@EnabledOnOs(OS.WINDOWS)
class FlyoutWindowWindowsTest {
    @Test
    fun toolWindowBitAndRectEqualPlacerResult() {
        val r = RunnerSupport.runChild(emptyList(), timeoutSeconds = 90, mainClass = FlyoutWindowChild::class.java.name)
        assertEquals(0, r.exitCode, "자식 실패\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}")
        val kv = r.stdout.lines().mapNotNull { l -> l.split('=', limit = 2).takeIf { it.size == 2 }?.let { it[0].trim() to it[1].trim() } }.toMap()
        val ex = kv["exstyle"]?.toLong() ?: fail("exstyle 없음: ${r.stdout}")
        assertTrue(ex and 0x80L != 0L, "WS_EX_TOOLWINDOW 비트가 없다: 0x${ex.toString(16)}")
        assertTrue(ex and 0x40000L == 0L, "WS_EX_APPWINDOW 가 남았다(작업 표시줄 단추): 0x${ex.toString(16)}")
        assertEquals(kv["expected"], kv["rect"], "GetWindowRect 가 FlyoutPlacer.place 결과와 다르다")
        assertEquals("true", kv["visible"])
        assertEquals("false", kv["hiddenVisible"], "숨긴 뒤에도 보인다")
        println("둥근 모서리 HRESULT=${kv["corner"]} (Windows 10 은 실패가 정상)")
    }
}

/** 자식 JVM: 창을 미리 만들고 → 합성 내용으로 열고 → OS 에 스타일·자리를 묻는다. */
object FlyoutWindowChild {
    @JvmStatic
    fun main(args: Array<String>) {
        try {
            val win = FlyoutWindow(JPanel())
            win.precreate()
            val facts = TaskbarProbe.probe() ?: SyntheticScreen.facts
            val placement = FlyoutPlacer.place(facts.request(FlyoutAnchors.fallback(facts), null, 480.0))
            win.show(placement)
            Thread.sleep(500)
            val hwnd = WinDef.HWND(Native.getWindowPointer(win.window))
            val ex = User32.INSTANCE.GetWindowLongPtr(hwnd, -20).toLong()
            val rect = WinDef.RECT()
            User32.INSTANCE.GetWindowRect(hwnd, rect)
            val p = placement.rect
            println("exstyle=$ex")
            println("rect=${rect.left},${rect.top},${rect.right},${rect.bottom}")
            println("expected=${p.left},${p.top},${p.right},${p.bottom}")
            println("visible=${User32.INSTANCE.IsWindowVisible(hwnd)}")
            win.hide()
            Thread.sleep(200)
            println("hiddenVisible=${User32.INSTANCE.IsWindowVisible(hwnd)}")
            println("corner=${win.cornerResult}")
            SwingUtilities.invokeAndWait { win.window.dispose() }
            System.out.flush()
            exitProcess(0)
        } catch (t: Throwable) {
            t.printStackTrace()
            exitProcess(3)
        }
    }
}
