// 원본: CheckOverlayWindow.swift :2211-2250 makePanel(경계 없음·비활성·떠 있음·그림자 없음·클릭 통과·sharingType none) — Win32 대역
//       설계 D §9-1(픽셀 알파 히트) · §9-4(울트라 두 창) · overlay.md §3 "모자란 JNA 선언은 b2 가 overlay/win32 안에"
//
// jna-platform 에 없는 선언만 여기 둔다(WindowFromPoint · Set/GetWindowDisplayAffinity · SetCapture · GetDpiForWindow ·
// GetStockObject · DwmIsCompositionEnabled). platform/windows/jna(닫힌 W1-f) 는 건드리지 않는다.
package com.yehsung.aingcheck.desktop.overlay.win32

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.ptr.IntByReference

/** 오버레이 창이 쓰는 Win32 상수(값은 winuser.h · wingdi.h · dwmapi.h). */
object OverlayWin32 {
    const val WS_POPUP = 0x80000000.toInt()

    const val WS_EX_TOPMOST = 0x00000008
    const val WS_EX_TRANSPARENT = 0x00000020
    const val WS_EX_TOOLWINDOW = 0x00000080
    const val WS_EX_LAYERED = 0x00080000
    const val WS_EX_NOACTIVATE = 0x08000000

    /** 캐릭터 창: 픽셀 알파 히트(알파 0 은 뒤 창으로) · 작업 표시줄·Alt+Tab 제외 · 눌러도 활성화 안 됨 · 맨 위. */
    const val OVERLAY_EX_STYLE = WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE or WS_EX_TOPMOST

    /** 울트라 흐림 창(D §9-4): 위와 같고 + TRANSPARENT(클릭이 언제나 통과). 상수 알파(LWA_ALPHA)로 칠한다. */
    const val ULTRA_DIM_EX_STYLE = OVERLAY_EX_STYLE or WS_EX_TRANSPARENT

    const val GWL_EXSTYLE = -20

    const val ULW_ALPHA = 0x00000002
    const val LWA_ALPHA = 0x00000002
    const val AC_SRC_OVER: Byte = 0x00
    const val AC_SRC_ALPHA: Byte = 0x01

    const val WDA_NONE = 0x00000000
    /** Windows 10 2004+ — 캡처·화면 공유에서 빠진다(맥 sharingType = .none). */
    const val WDA_EXCLUDEFROMCAPTURE = 0x00000011

    const val SW_HIDE = 0
    const val SW_SHOWNOACTIVATE = 4

    const val SWP_NOSIZE = 0x0001
    const val SWP_NOMOVE = 0x0002
    const val SWP_NOZORDER = 0x0004
    const val SWP_NOACTIVATE = 0x0010
    val HWND_TOPMOST: WinDef.HWND = WinDef.HWND(Pointer.createConstant(-1L))

    const val WM_DESTROY = 0x0002
    const val WM_MOUSEACTIVATE = 0x0021
    const val WM_MOUSEMOVE = 0x0200
    const val WM_LBUTTONDOWN = 0x0201
    const val WM_LBUTTONUP = 0x0202
    const val WM_CAPTURECHANGED = 0x0215
    const val MA_NOACTIVATE = 3
    const val MK_LBUTTON = 0x0001

    const val BI_RGB = 0
    const val DIB_RGB_COLORS = 0
    const val BLACK_BRUSH = 4

    const val USER_DEFAULT_DPI = 96

    /** lParam 의 아래·위 16비트(부호 있는 클라이언트 좌표 — 멀티 모니터에서 음수가 된다). */
    fun loWordSigned(lParam: Long): Int = (lParam and 0xFFFF).toInt().toShort().toInt()
    fun hiWordSigned(lParam: Long): Int = ((lParam shr 16) and 0xFFFF).toInt().toShort().toInt()
}

/** user32 의 모자란 선언. 이름에 A/W 가 없는 함수들이라 함수 매퍼 없이 싣는다. */
interface OverlayUser32 : Library {
    fun WindowFromPoint(point: WinDef.POINT.ByValue): WinDef.HWND?
    fun SetWindowDisplayAffinity(hWnd: WinDef.HWND, dwAffinity: Int): Boolean
    fun GetWindowDisplayAffinity(hWnd: WinDef.HWND, pdwAffinity: IntByReference): Boolean
    fun SetCapture(hWnd: WinDef.HWND): WinDef.HWND?
    fun ReleaseCapture(): Boolean
    fun GetCapture(): WinDef.HWND?
    /** Windows 10 1607+. 0 이면 잘못된 창. */
    fun GetDpiForWindow(hwnd: WinDef.HWND): Int

    companion object {
        val INSTANCE: OverlayUser32 by lazy { Native.load("user32", OverlayUser32::class.java) }
    }
}

interface OverlayGdi32 : Library {
    fun GetStockObject(i: Int): Pointer?

    companion object {
        val INSTANCE: OverlayGdi32 by lazy { Native.load("gdi32", OverlayGdi32::class.java) }
    }
}

/** dwmapi — 러너에 DWM 합성이 없으면 캡처 제외가 실패한다(W-3 #10: 오류 코드만 기록하고 VM 으로). */
interface OverlayDwmApi : Library {
    /** HRESULT. Windows 8+ 에서는 늘 TRUE 를 돌려준다(합성을 끌 수 없다). */
    fun DwmIsCompositionEnabled(pfEnabled: IntByReference): Int

    companion object {
        val INSTANCE: OverlayDwmApi by lazy { Native.load("dwmapi", OverlayDwmApi::class.java) }
    }
}
