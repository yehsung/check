// 원본: CheckOverlayWindow.swift :2211-2250 makePanel(경계 없음 · nonactivatingPanel · floating · hasShadow false · sharingType none) ·
//       :2250-2300 히트 뷰(몸 위만 클릭을 받고 밖은 뒤 창으로) · 설계 D §9-1 · §9-4(울트라 흐림 창 클릭 통과) · W-3 #10
//       overlay.md §5 Windows 러너 OverlayWindowSmokeWindowsTest
package com.yehsung.aingcheck.desktop.overlay.surface.runner

import com.yehsung.aingcheck.desktop.overlay.surface.ScreenRectPx
import com.yehsung.aingcheck.desktop.overlay.surface.WindowsOverlaySurface
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWin32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import org.junit.jupiter.api.Assumptions
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@EnabledOnOs(OS.WINDOWS)
class OverlayWindowSmokeWindowsTest {
    private val tag = "AingCheck.OverlaySmoke.${ProcessHandle.current().pid()}.${System.nanoTime()}"
    private val thread = Win32MessageThread.start(className = "$tag.Msg", threadName = "overlay-smoke")
    private val surface = WindowsOverlaySurface(thread, className = tag)
    private val x = 240
    private val y = 220

    @AfterTest
    fun tearDown() {
        surface.close()
        thread.close()
    }

    @Test
    fun layeredToolTopmostNoActivateAndUpdateLayeredWindowSucceeds() {
        val ex = surface.exStyle()
        for ((name, bit) in listOf(
            "LAYERED" to OverlayWin32.WS_EX_LAYERED, "TOOLWINDOW" to OverlayWin32.WS_EX_TOOLWINDOW,
            "NOACTIVATE" to OverlayWin32.WS_EX_NOACTIVATE, "TOPMOST" to OverlayWin32.WS_EX_TOPMOST,
        )) assertTrue(ex and bit != 0, "GWL_EXSTYLE 에 $name 이 없다: 0x${Integer.toHexString(ex)}")
        assertEquals(0, ex and OverlayWin32.WS_EX_TRANSPARENT, "캐릭터 창은 TRANSPARENT 가 아니다(몸 클릭을 받아야 한다)")
        val r = surface.present(OverlayRunnerKit.halfOpaque(), x, y)
        assertTrue(r.ok, "UpdateLayeredWindow(280×340) 실패 err=${r.errorCode}")
        assertTrue(surface.isShown)
        // 같은 크기 두 번째 프레임은 DIB 를 다시 쓴다.
        assertTrue(surface.present(OverlayRunnerKit.halfOpaque(90), x, y).ok)
    }

    /** W-3 #10 — 러너에 DWM 합성이 없어 실패하면 오류 코드만 남기고 건너뛴다(VM 묶음에서 판정). */
    @Test
    fun captureExclusionIsAppliedOrTheErrorCodeIsRecorded() {
        val ce = surface.captureExclusion
        println("OVERLAY_CAPTURE_EXCLUSION ${ce.describe()}")
        Assumptions.assumeTrue(ce.applied, "캡처 제외 실패 — VM 묶음으로: ${ce.describe()}")
        assertEquals(OverlayWin32.WDA_EXCLUDEFROMCAPTURE, ce.affinity, "GetWindowDisplayAffinity")
    }

    @Test
    fun transparentPixelsFallThroughToTheWindowBehindOpaquePixelsHitTheOverlay() {
        OverlayRunnerKit.BackWindow(thread, "$tag.Back", x, y, OverlayRunnerKit.W, OverlayRunnerKit.H).use { back ->
            assertTrue(surface.present(OverlayRunnerKit.halfOpaque(), x, y).ok)
            Thread.sleep(150)
            val clear = OverlayRunnerKit.windowFromPoint(x + 40, y + 170)
            val solid = OverlayRunnerKit.windowFromPoint(x + OverlayRunnerKit.W - 40, y + 170)
            assertTrue(OverlayRunnerKit.same(clear, back.hwnd), "투명 픽셀 → 뒤 창이어야 한다: ${OverlayRunnerKit.className(clear)}")
            assertTrue(OverlayRunnerKit.same(solid, surface.hwnd), "불투명 픽셀 → 오버레이여야 한다: ${OverlayRunnerKit.className(solid)}")
        }
    }

    @Test
    fun ultraDimWindowLetsClicksThrough() {
        OverlayRunnerKit.BackWindow(thread, "$tag.Back", x, y, OverlayRunnerKit.W, OverlayRunnerKit.H).use { back ->
            assertTrue(surface.present(OverlayRunnerKit.halfOpaque(), x, y).ok)
            surface.showUltraDim(ScreenRectPx(x - 60, y - 60, OverlayRunnerKit.W + 120, OverlayRunnerKit.H + 120), alpha = 140)
            Thread.sleep(150)
            val dim = surface.dimHwnd!!
            val dimEx = com.yehsung.aingcheck.desktop.overlay.win32.OverlayWindowClass.exStyle(dim)
            assertTrue(dimEx and OverlayWin32.WS_EX_TRANSPARENT != 0 && dimEx and OverlayWin32.WS_EX_LAYERED != 0, "흐림 창 스타일 0x${Integer.toHexString(dimEx)}")
            // 흐림 창만 덮은 자리(뒤 창 밖) — 흐림 창이 잡히면 안 된다.
            val edge = OverlayRunnerKit.windowFromPoint(x - 30, y - 30)
            assertTrue(!OverlayRunnerKit.same(edge, dim), "흐림 창이 클릭을 먹었다")
            // 캐릭터 투명 픽셀 + 흐림 창 아래 = 뒤 창.
            val clear = OverlayRunnerKit.windowFromPoint(x + 40, y + 170)
            assertTrue(OverlayRunnerKit.same(clear, back.hwnd), "흐림 창 너머 뒤 창이어야 한다: ${OverlayRunnerKit.className(clear)}")
            // 캐릭터 불투명 픽셀은 흐림 창 위의 오버레이.
            val solid = OverlayRunnerKit.windowFromPoint(x + OverlayRunnerKit.W - 40, y + 170)
            assertTrue(OverlayRunnerKit.same(solid, surface.hwnd), "오버레이가 흐림 창 위에 있어야 한다: ${OverlayRunnerKit.className(solid)}")
            surface.hideUltraDim()
        }
    }
}
