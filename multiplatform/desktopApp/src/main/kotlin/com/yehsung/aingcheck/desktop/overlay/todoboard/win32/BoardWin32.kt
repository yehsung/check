// 원본: Sources/check/CheckTodoBoardWindow.swift:469-505(makePanel — 도구 창·떠 있음·sharingType none) @ ef9fab11 · 설계 D §9-5 · D-windows-platform.md:304
// platform/windows/jna 는 닫힌 갈래(W1-f)라 모자란 선언을 이 갈래 안 자기 Library 로 둔다(overlay.md §3).
package com.yehsung.aingcheck.desktop.overlay.todoboard.win32

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference

internal interface BoardUser32 : Library {
    fun SetWindowDisplayAffinity(hWnd: WinDef.HWND, dwAffinity: Int): Boolean
    fun GetWindowDisplayAffinity(hWnd: WinDef.HWND, pdwAffinity: IntByReference): Boolean

    companion object {
        val INSTANCE: BoardUser32 by lazy { Native.load("user32", BoardUser32::class.java) }
    }
}

internal interface BoardDwmapi : Library {
    fun DwmSetWindowAttribute(hwnd: WinDef.HWND, dwAttribute: Int, pvAttribute: IntByReference, cbAttribute: Int): Int

    companion object {
        val INSTANCE: BoardDwmapi by lazy { Native.load("dwmapi", BoardDwmapi::class.java) }
    }
}

/** 보드 창에 거는 Win32 성질. 전부 UI(EDT) 스레드에서 부른다. */
object BoardWin32 {
    const val WS_EX_TOPMOST = 0x00000008
    const val WS_EX_TOOLWINDOW = 0x00000080
    const val WS_EX_APPWINDOW = 0x00040000
    const val WS_EX_NOACTIVATE = 0x08000000
    /** Windows 10 2004+. DWM 합성 중일 때만 유효(러너에 합성이 없으면 실패 — 오류 코드만 기록, W-3 #10). */
    const val WDA_EXCLUDEFROMCAPTURE = 0x00000011
    private const val DWMWA_WINDOW_CORNER_PREFERENCE = 33
    private const val DWMWCP_ROUND = 2
    private const val SWP_NOSIZE = 0x0001
    private const val SWP_NOMOVE = 0x0002
    private const val SWP_NOACTIVATE = 0x0010
    private const val SWP_FRAMECHANGED = 0x0020
    private val HWND_TOPMOST = WinDef.HWND(Pointer.createConstant(-1))

    /** 결과(시험·진단용 값). [affinityError] 는 SetWindowDisplayAffinity 실패 때 GetLastError, 성공이면 0. */
    data class Applied(val exStyle: Int, val affinityError: Int)

    /**
     * 도구 창(작업 표시줄·Alt+Tab 에 안 뜸)·맨 위·캡처 제외·둥근 모서리(Windows 11). **활성화는 막지 않는다** —
     * 보드는 글자를 받아야 해서 NOACTIVATE 를 쓰면 안 된다(D §9-5).
     */
    fun apply(hwnd: WinDef.HWND, excludeFromCapture: Boolean): Applied {
        val u = User32.INSTANCE
        val before = u.GetWindowLong(hwnd, WinUser.GWL_EXSTYLE)
        val wanted = (before or WS_EX_TOOLWINDOW or WS_EX_TOPMOST) and WS_EX_APPWINDOW.inv() and WS_EX_NOACTIVATE.inv()
        if (wanted != before) u.SetWindowLong(hwnd, WinUser.GWL_EXSTYLE, wanted)
        u.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_FRAMECHANGED)
        var affinityError = 0
        if (excludeFromCapture && !BoardUser32.INSTANCE.SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)) {
            affinityError = Native.getLastError().takeIf { it != 0 } ?: -1
        }
        runCatching { BoardDwmapi.INSTANCE.DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, IntByReference(DWMWCP_ROUND), 4) }
        return Applied(u.GetWindowLong(hwnd, WinUser.GWL_EXSTYLE), affinityError)
    }

    /** 앞으로 가져온다. 캐릭터를 누른 직후라 우리 프로세스가 마지막 입력을 받은 프로세스다(전경 권한). */
    fun bringToForeground(hwnd: WinDef.HWND): Boolean = User32.INSTANCE.SetForegroundWindow(hwnd)

    fun displayAffinity(hwnd: WinDef.HWND): Int? {
        val out = IntByReference()
        return if (BoardUser32.INSTANCE.GetWindowDisplayAffinity(hwnd, out)) out.value else null
    }
}
