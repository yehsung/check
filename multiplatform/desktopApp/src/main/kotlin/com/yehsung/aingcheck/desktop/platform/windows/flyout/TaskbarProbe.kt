// 원본: 없음(새 코드) — 설계 D§3-3(작업 표시줄 정보: SHAppBarMessage(ABM_GETTASKBARPOS)·ABM_GETSTATE(자동 숨김),
// 아이콘은 주 모니터 작업 표시줄에만 있으므로 플라이아웃은 아이콘이 있는 모니터에 뜬다) · D§13-4(GetDpiForMonitor, Per-Monitor V2)
// 프로세스가 Per-Monitor V2 로 돌아야 물리 픽셀이 온다 — jpackage 런처·java.exe 둘 다 PMv2 다(W0-e D-E22 실측).
package com.yehsung.aingcheck.desktop.platform.windows.flyout

import com.sun.jna.platform.win32.Shell32
import com.sun.jna.platform.win32.ShellAPI
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.desktop.platform.windows.jna.ShcoreX
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32

/** 플라이아웃 배치에 넣을 화면 사실(기준점·아이콘·내용 높이만 빠졌다). */
data class ScreenFacts(val monitor: PxRect, val workArea: PxRect, val taskbar: TaskbarInfo, val dpi: Int) {
    val scale: Double get() = ScreenSpace.scaleForDpi(dpi)

    fun request(anchor: PxPoint, iconRect: PxRect?, contentHeightDip: Double, widthDip: Double = FlyoutPlacer.WIDTH_DIP) =
        FlyoutRequest(anchor, iconRect, monitor, workArea, taskbar, scale, contentHeightDip, widthDip)
}

object TaskbarProbe {
    /** 지금 화면. [near] 가 있으면 그 점이 있는 모니터(아이콘 자리), 없으면 작업 표시줄이 있는 모니터. 실패면 null. */
    fun probe(near: PxPoint? = null): ScreenFacts? {
        val abd = ShellAPI.APPBARDATA()
        abd.cbSize = WinDef.DWORD(abd.size().toLong())
        val got = Shell32.INSTANCE.SHAppBarMessage(WinDef.DWORD(Win32.ABM_GETTASKBARPOS.toLong()), abd)
        if (got.toLong() == 0L) return null
        val tbRect = abd.rc.let { PxRect(it.left, it.top, it.right, it.bottom) }
        val edge = when (abd.uEdge.toInt()) {
            Win32.ABE_LEFT -> TaskbarEdge.LEFT
            Win32.ABE_TOP -> TaskbarEdge.TOP
            Win32.ABE_RIGHT -> TaskbarEdge.RIGHT
            else -> TaskbarEdge.BOTTOM
        }
        val state = ShellAPI.APPBARDATA()
        state.cbSize = WinDef.DWORD(state.size().toLong())
        val autoHide = (Shell32.INSTANCE.SHAppBarMessage(WinDef.DWORD(Win32.ABM_GETSTATE.toLong()), state).toLong() and Win32.ABS_AUTOHIDE.toLong()) != 0L

        val probeRect = WinDef.RECT()
        if (near != null) {
            probeRect.left = near.x; probeRect.top = near.y; probeRect.right = near.x + 1; probeRect.bottom = near.y + 1
        } else {
            probeRect.left = tbRect.left; probeRect.top = tbRect.top; probeRect.right = tbRect.right; probeRect.bottom = tbRect.bottom
        }
        val monitor = User32.INSTANCE.MonitorFromRect(probeRect, Win32.MONITOR_DEFAULTTONEAREST) ?: return null
        val info = WinUser.MONITORINFO()
        if (!User32.INSTANCE.GetMonitorInfo(monitor, info).booleanValue()) return null
        val dpiX = IntByReference(0)
        val dpiY = IntByReference(0)
        val hr = runCatching { ShcoreX.INSTANCE.GetDpiForMonitor(monitor, Win32.MDT_EFFECTIVE_DPI, dpiX, dpiY) }.getOrDefault(-1)
        val dpi = if (hr == 0 && dpiX.value > 0) dpiX.value else ScreenSpace.BASE_DPI
        return ScreenFacts(
            monitor = info.rcMonitor.let { PxRect(it.left, it.top, it.right, it.bottom) },
            workArea = info.rcWork.let { PxRect(it.left, it.top, it.right, it.bottom) },
            taskbar = TaskbarInfo(edge, tbRect, autoHide),
            dpi = dpi,
        )
    }
}
