// 원본: 없음(새 코드) — 설계 D-windows-platform §3-3 · learn.microsoft.com: WS_EX_TOOLWINDOW(작업 표시줄·Alt+Tab 에 안 뜬다),
//       WS_EX_APPWINDOW(있으면 작업 표시줄에 뜬다 — 뺀다), DWMWA_WINDOW_CORNER_PREFERENCE=33 · DWMWCP_ROUND=2(Windows 11 22000+,
//       그 전은 E_INVALIDARG — 실패해도 창은 쓴다), SetWindowPos 는 물리 픽셀(Per-Monitor V2 프로세스).
// shell/** 에서 JNA 는 이 폴더만 쓴다(ShellStructureTest).
package com.yehsung.aingcheck.desktop.shell.flyout.native

import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.ptr.IntByReference
import com.sun.jna.win32.StdCallLibrary
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import java.awt.Window

internal interface DwmApi : StdCallLibrary {
    fun DwmSetWindowAttribute(hwnd: WinDef.HWND, attribute: Int, value: IntByReference, size: Int): Int

    companion object {
        val INSTANCE: DwmApi by lazy { Native.load("dwmapi", DwmApi::class.java) }
    }
}

object FlyoutNative {
    const val GWL_EXSTYLE = -20
    const val WS_EX_TOOLWINDOW = 0x00000080L
    const val WS_EX_APPWINDOW = 0x00040000L
    const val DWMWA_WINDOW_CORNER_PREFERENCE = 33
    const val DWMWCP_ROUND = 2
    private const val SWP_NOSIZE = 0x0001
    private const val SWP_NOMOVE = 0x0002
    private const val SWP_NOZORDER = 0x0004
    private const val SWP_NOACTIVATE = 0x0010
    private const val SWP_FRAMECHANGED = 0x0020

    /** HWND_TOPMOST = (HWND)-1. */
    private val HWND_TOPMOST = WinDef.HWND(Pointer.createConstant(-1L))

    fun hwnd(window: Window): WinDef.HWND = WinDef.HWND(Native.getWindowPointer(window))

    /** 작업 표시줄 단추를 없앤다: TOOLWINDOW 켜고 APPWINDOW 끈다. 새 확장 스타일을 돌려준다. */
    fun applyToolWindowStyle(window: Window): Long {
        val h = hwnd(window)
        val ex = User32.INSTANCE.GetWindowLongPtr(h, GWL_EXSTYLE).toLong()
        val next = (ex or WS_EX_TOOLWINDOW) and WS_EX_APPWINDOW.inv()
        User32.INSTANCE.SetWindowLongPtr(h, GWL_EXSTYLE, Pointer.createConstant(next))
        User32.INSTANCE.SetWindowPos(h, null, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED)
        return next
    }

    /** Windows 11 둥근 모서리. HRESULT(0 = 성공). */
    fun roundCorners(window: Window): Int = runCatching {
        DwmApi.INSTANCE.DwmSetWindowAttribute(hwnd(window), DWMWA_WINDOW_CORNER_PREFERENCE, IntByReference(DWMWCP_ROUND), 4)
    }.getOrDefault(-1)

    /** 물리 픽셀 자리·크기(맨 위 고정, 활성화 안 함 — 활성화는 [bringToFront]). */
    fun place(window: Window, rect: PxRect): Boolean =
        User32.INSTANCE.SetWindowPos(hwnd(window), HWND_TOPMOST, rect.left, rect.top, rect.width, rect.height, SWP_NOACTIVATE)

    /** 트레이 콜백 직후라 전경 권한이 있다(마지막 입력을 받은 프로세스 — D-E04 가 VM 에서 확인). */
    fun bringToFront(window: Window): Boolean = User32.INSTANCE.SetForegroundWindow(hwnd(window))

    /** 진단: 지금 확장 스타일. */
    fun exStyle(window: Window): Long = User32.INSTANCE.GetWindowLongPtr(hwnd(window), GWL_EXSTYLE).toLong()
}
