// 원본: 없음(새 시험) — overlay.md §5 Windows 러너 OverlayChildProbeWindowsTest · CheckOverlayWindow.swift :2211(nonactivatingPanel)
//       기억 test-panels-steal-user-clicks(사람 PC 에서 입력 주입 금지 — CI·시험 VM 만)
package com.yehsung.aingcheck.desktop.overlay.surface.runner

import com.sun.jna.platform.win32.User32
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.surface.OverlaySurfaceListener
import com.yehsung.aingcheck.desktop.overlay.surface.WindowsOverlaySurface
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import org.junit.jupiter.api.Assumptions
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@EnabledOnOs(OS.WINDOWS)
class OverlayChildProbeWindowsTest {
    @Test
    fun childPresentsThirtyFramesClosesAndLeavesNoWindowOfItsClass() {
        val cls = "AingCheck.OverlayChild.${ProcessHandle.current().pid()}.${System.nanoTime()}"
        val r = OverlayRunnerKit.runChild(listOf("frames", cls, "30"))
        assertEquals(0, r.exitCode, "자식 종료 코드 — stdout=${r.stdout} stderr=${r.stderr}")
        assertTrue(r.stdout.contains("presented=30"), r.stdout)
        assertTrue(r.stdout.contains("windowsAfterClose=0"), r.stdout)
        assertEquals(0, OverlayRunnerKit.countWindowsOfClass(cls), "자식이 끝난 뒤 그 클래스 창")
    }

    /** CI 러너·시험 VM 에서만(실제 마우스를 움직인다). 불투명 → 오버레이가 받고 전경 불변(NOACTIVATE), 투명 → 뒤 창이 받는다. */
    @Test
    fun injectedClicksFollowPixelAlphaAndNeverActivateTheOverlay() {
        Assumptions.assumeTrue(RunnerSupport.inputInjectionAllowed(), "입력 주입은 GITHUB_ACTIONS 또는 AINGCHECK_ALLOW_INPUT_INJECTION=1 에서만")
        val tag = "AingCheck.OverlayClick.${ProcessHandle.current().pid()}.${System.nanoTime()}"
        val events = LinkedBlockingQueue<Pair<PointerKind, HitTarget>>()
        val thread = Win32MessageThread.start(className = "$tag.Msg", threadName = "overlay-click")
        val surface = WindowsOverlaySurface(thread, tag, OverlaySurfaceListener { kind, _, target -> events.add(kind to target) })
        val x = 260
        val y = 240
        try {
            OverlayRunnerKit.BackWindow(thread, "$tag.Back", x, y, OverlayRunnerKit.W, OverlayRunnerKit.H).use { back ->
                assertTrue(surface.present(OverlayRunnerKit.halfOpaque(), x, y).ok)
                Thread.sleep(200)
                val before = User32.INSTANCE.GetForegroundWindow()
                OverlayRunnerKit.clickAt(x + OverlayRunnerKit.W - 40, y + 170)
                val down = assertNotNull(events.poll(3, TimeUnit.SECONDS), "불투명 픽셀 클릭을 오버레이가 못 받았다")
                assertEquals(PointerKind.DOWN to HitTarget.Body, down)
                var up = assertNotNull(events.poll(3, TimeUnit.SECONDS), "놓기를 못 받았다")
                while (up.first == PointerKind.DRAG) up = assertNotNull(events.poll(3, TimeUnit.SECONDS), "놓기를 못 받았다")
                assertEquals(PointerKind.UP, up.first)
                val after = User32.INSTANCE.GetForegroundWindow()
                assertTrue(before?.pointer == after?.pointer, "오버레이 클릭이 전경 창을 바꿨다(NOACTIVATE 위반): ${OverlayRunnerKit.className(after)}")
                assertTrue(after?.pointer != surface.hwnd.pointer, "오버레이가 전경이 됐다")

                val backBefore = back.clicks.get()
                OverlayRunnerKit.clickAt(x + 40, y + 170)
                RunnerSupport.waitUntil(3_000, "투명 픽셀 클릭이 뒤 창에 간다") { back.clicks.get() > backBefore }
                assertEquals(null, events.poll(300, TimeUnit.MILLISECONDS), "투명 픽셀 클릭이 오버레이로 왔다")
            }
        } finally {
            surface.close()
            thread.close()
        }
    }
}
