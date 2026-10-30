// 원본: CheckOverlayWindow.swift :2211-2250 makePanel(경계 없음 · nonactivating · floating · sharingType none) · :2009-2036 reposition ·
//       :1702-1706 울트라 덮기 · :817-822 울트라 클릭 통과 · W-3 #10(DWM 없으면 캡처 제외 오류 코드만) · W-9 #1 W5-b4
// Windows 러너 전용 — 조립(OverlaySurfaces.createOn)이 만든 실제 레이어드 창이 FrameIntent 대로 그 자리·크기에 서는지.
package com.yehsung.aingcheck.desktop.overlay.surface.runner

import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlayFramePlacement
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlayFrameComposer
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacePresenter
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfaces
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacesConfig
import com.yehsung.aingcheck.desktop.overlay.assembly.WindowsSurfacePort
import com.yehsung.aingcheck.desktop.overlay.engine.FrameIntent
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayGeometry
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.overlay.surface.WindowsMonitors
import com.yehsung.aingcheck.desktop.overlay.surface.WindowsOverlaySurface
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWin32
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWindowClass
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import org.junit.jupiter.api.Assumptions
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@EnabledOnOs(OS.WINDOWS)
class OverlaySurfacesWindowsTest {
    private val tag = "AingCheck.OverlaySurfaces.${ProcessHandle.current().pid()}.${System.nanoTime()}"
    private val thread = Win32MessageThread.start(className = "$tag.Msg", threadName = "overlay-surfaces")
    private val surface = WindowsOverlaySurface(thread, className = tag)

    /** 몸 자리만 반투명인 합성 프레임(캐릭터 없이도 레이어드 창이 선다). */
    private val composer = OverlayFrameComposer { _, w, h, _, _ ->
        val px = ByteArray(w * h * 4)
        for (y in h / 3 until h) for (x in w / 4 until w * 3 / 4) {
            val i = (y * w + x) * 4
            px[i] = 100; px[i + 1] = 100; px[i + 2] = 100; px[i + 3] = 200.toByte()
        }
        ComposedOverlay(w, h, px)
    }

    private fun view(frame: FrameIntent, mode: OverlayMode = OverlayMode.Normal) = OverlayView(
        mode = mode, characterId = "aing", bubble = null, activeReaction = null, reactionStartedAt = null, sleeping = false,
        facing = 0, walking = false, particles = emptyList(), frame = frame, renderSuspended = false,
    )

    private fun windowRect(h: WinDef.HWND): WinDef.RECT = thread.call { _ -> WinDef.RECT().also { User32.INSTANCE.GetWindowRect(h, it) } }

    @AfterTest
    fun tearDown() {
        surface.close()
        thread.close()
    }

    @Test
    fun presenterPlacesTheLayeredWindowAtTheGeometryPixelsAndUltraIsClickThrough() {
        val port = WindowsSurfacePort(surface)
        val monitors = port.monitors()
        println("OVERLAY_SURFACES monitors=${monitors.size} scale=${port.dpiScale()} capture=${surface.captureExclusion.describe()}")
        Assumptions.assumeTrue(monitors.isNotEmpty(), "모니터를 못 읽었다(세션 0?) — VM 묶음")
        val p = OverlaySurfacePresenter(port, composer) { null }
        p.present(view(FrameIntent.Default(0)), 0.0)
        val expected = OverlayFramePlacement.toPx(OverlayGeometry.restore(null, monitors, OverlayFramePlacement.primaryWork(monitors)), port.dpiScale())
        val r = windowRect(surface.hwnd)
        assertEquals(listOf(expected.x, expected.y, expected.width, expected.height), listOf(r.left, r.top, r.right - r.left, r.bottom - r.top), "기본 자리(오른쪽 위 24)")
        assertTrue(surface.isShown)
        val ex = surface.exStyle()
        for ((name, bit) in listOf("LAYERED" to OverlayWin32.WS_EX_LAYERED, "TOOLWINDOW" to OverlayWin32.WS_EX_TOOLWINDOW, "NOACTIVATE" to OverlayWin32.WS_EX_NOACTIVATE, "TOPMOST" to OverlayWin32.WS_EX_TOPMOST)) {
            assertTrue(ex and bit != 0, "GWL_EXSTYLE 에 $name 없음 0x${Integer.toHexString(ex)}")
        }
        assertEquals(0, ex and OverlayWin32.WS_EX_TRANSPARENT, "평소엔 클릭을 받는다")

        // 울트라: 화면 높이 띠 + 클릭 통과.
        p.present(view(FrameIntent.UltraCover(1), OverlayMode.Ultra), 0.1)
        val band = OverlayFramePlacement.toPx(p.frameDip!!, port.dpiScale())
        val u = windowRect(surface.hwnd)
        assertEquals(listOf(band.x, band.y, band.width, band.height), listOf(u.left, u.top, u.right - u.left, u.bottom - u.top), "울트라 띠")
        assertTrue(surface.exStyle() and OverlayWin32.WS_EX_TRANSPARENT != 0, "울트라 동안 클릭 통과")

        // 복원: 원래 자리 · 클릭 다시 받음.
        p.present(view(FrameIntent.Restore(OverlayGeometry.restore(null, monitors, OverlayFramePlacement.primaryWork(monitors)), 2)), 5.2)
        val back = windowRect(surface.hwnd)
        assertEquals(listOf(expected.x, expected.y), listOf(back.left, back.top))
        assertEquals(0, surface.exStyle() and OverlayWin32.WS_EX_TRANSPARENT)

        // 숨김 → 창이 내려간다.
        p.present(view(FrameIntent.Restore(OverlayGeometry.restore(null, monitors, OverlayFramePlacement.primaryWork(monitors)), 2), OverlayMode.Hidden), 6.0)
        assertTrue(!surface.isShown && !thread.call { _ -> User32.INSTANCE.IsWindowVisible(surface.hwnd) })
    }

    /** W-3 #10 — 러너에 DWM 합성이 없어 실패하면 오류 코드만 남기고 건너뛴다(VM 묶음에서 판정). */
    @Test
    fun captureExclusionIsTriedAndItsResultIsRecorded() {
        val ce = surface.captureExclusion
        println("OVERLAY_SURFACES_CAPTURE_EXCLUSION ${ce.describe()}")
        Assumptions.assumeTrue(ce.applied, "캡처 제외 실패 — VM 묶음으로: ${ce.describe()}")
        assertEquals(OverlayWin32.WDA_EXCLUDEFROMCAPTURE, ce.affinity)
    }

    @Test
    fun assemblyOnAWindowsMessageThreadIsLiveAndCleansUpItsWindow() {
        val kv = object : DesktopKeyValueStore {
            val m = HashMap<String, String>()
            override fun getString(key: String): String? = m[key]
            override fun putString(key: String, value: String?) { if (value == null) m.remove(key) else m[key] = value }
            override fun keys(prefix: String): List<String> = m.keys.filter { it.startsWith(prefix) }.sorted()
        }
        val before = OverlayRunnerKit.countWindowsOfClass(WindowsOverlaySurface.DEFAULT_CLASS_NAME)
        val s = OverlaySurfaces.createOn(thread, OverlaySurfacesConfig(kv, bakeRoot = null), isWindows = true)
        try {
            assertTrue(s.isLive, "Windows 메시지 스레드 위 조립은 실물")
            assertEquals(before + 1, OverlayRunnerKit.countWindowsOfClass(WindowsOverlaySurface.DEFAULT_CLASS_NAME))
            s.presenter.present(view(FrameIntent.Default(0)), 0.0)
            println("OVERLAY_SURFACES_ASSEMBLY frame=${s.surfacePresenter?.frameDip} monitors=${WindowsMonitors.list().size}")
        } finally {
            s.close()
        }
        assertEquals(before, OverlayRunnerKit.countWindowsOfClass(WindowsOverlaySurface.DEFAULT_CLASS_NAME), "닫으면 창 0")
        assertTrue(OverlayWindowClass.dpiScale(surface.hwnd) > 0)
    }
}
