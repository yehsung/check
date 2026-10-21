// 원본: 없음(새 코드) — 설계 D§2-2·§2-4·§3·§5-1·§6·§13-4, W0-e 탐침 Win32.kt(multiplatform/spikes/windows) 의 서명·크기 실측
// jna-platform 에 없거나 서명이 불확실한 Win32 함수·구조체만 여기 둔다. 함수 이름에 W 를 직접 붙여 이름 매퍼를 쓰지 않는다
// (JNA 의 Java char 는 Windows wchar_t 2바이트로 간다). 이 파일의 어떤 것도 Windows 밖에서 **로드**하지 않는다 —
// 인터페이스 인스턴스는 lazy 라 맥 JVM 시험이 이 파일의 상수만 써도 user32.dll 을 찾지 않는다.
package com.yehsung.aingcheck.desktop.platform.windows.jna

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.Structure
import com.sun.jna.platform.win32.Guid
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinGDI
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference

/** 메시지·상수. 숫자는 winuser.h·shellapi.h 그대로다. */
object Win32 {
    const val WM_CLOSE = 0x0010
    const val WM_DESTROY = 0x0002
    const val WM_INPUT = 0x00FF
    const val WM_HOTKEY = 0x0312
    const val WM_CONTEXTMENU = 0x007B
    const val WM_LBUTTONDBLCLK = 0x0203
    const val WM_USER = 0x0400
    const val WM_APP = 0x8000

    /** 숨은 창으로 "이 스레드에서 실행해 달라" 를 보내는 우리 메시지(WM_APP 대역). */
    const val WM_APP_INVOKE = WM_APP + 0x10

    /** 트레이 콜백 메시지 기본값(WM_APP + 1). */
    const val WM_APP_TRAY = WM_APP + 1

    const val WS_POPUP = 0x80000000.toInt()
    const val WS_EX_TOOLWINDOW = 0x00000080

    // 단축키(RegisterHotKey)
    const val MOD_ALT = 0x0001
    const val MOD_CONTROL = 0x0002
    const val MOD_SHIFT = 0x0004
    const val MOD_WIN = 0x0008
    const val MOD_NOREPEAT = 0x4000
    const val ERROR_HOTKEY_ALREADY_REGISTERED = 1409
    const val ERROR_ALREADY_EXISTS = 183
    const val ERROR_CLASS_ALREADY_EXISTS = 1410

    // 트레이(Shell_NotifyIcon, NOTIFYICON_VERSION_4)
    const val NIM_ADD = 0
    const val NIM_MODIFY = 1
    const val NIM_DELETE = 2
    const val NIM_SETVERSION = 4
    const val NIF_MESSAGE = 0x01
    const val NIF_ICON = 0x02
    const val NIF_TIP = 0x04
    const val NIF_SHOWTIP = 0x80
    const val NOTIFYICON_VERSION_4 = 4
    const val NIN_SELECT = WM_USER + 0
    const val NIN_KEYSELECT = WM_USER + 1

    // Raw Input
    const val RIDEV_REMOVE = 0x00000001
    const val RIDEV_INPUTSINK = 0x00000100
    const val RID_INPUT = 0x10000003
    const val HID_USAGE_PAGE_GENERIC = 0x01
    const val HID_USAGE_GENERIC_MOUSE = 0x02
    const val HID_USAGE_GENERIC_KEYBOARD = 0x06

    // 작업 표시줄(SHAppBarMessage)
    const val ABM_GETSTATE = 0x00000004
    const val ABM_GETTASKBARPOS = 0x00000005
    const val ABS_AUTOHIDE = 0x0000001
    const val ABE_LEFT = 0
    const val ABE_TOP = 1
    const val ABE_RIGHT = 2
    const val ABE_BOTTOM = 3

    const val MONITOR_DEFAULTTONEAREST = 0x00000002
    const val MDT_EFFECTIVE_DPI = 0

    const val MSGFLT_ALLOW = 1

    const val APPMODEL_ERROR_NO_PACKAGE = 15700
    const val ERROR_INSUFFICIENT_BUFFER = 122

    /** RAWINPUTHEADER 크기: DWORD 둘 + HANDLE + WPARAM(64비트 24, 32비트 16). */
    fun rawInputHeaderSize(pointerSize: Int = Native.POINTER_SIZE): Int = 8 + 2 * pointerSize
}

interface User32X : Library {
    fun CreateIconIndirect(piconinfo: WinGDI.ICONINFO): WinDef.HICON?
    fun RegisterRawInputDevices(pRawInputDevices: Array<RAWINPUTDEVICE>, uiNumDevices: Int, cbSize: Int): Boolean
    fun GetRegisteredRawInputDevices(pRawInputDevices: Array<RAWINPUTDEVICE>?, puiNumDevices: IntByReference, cbSize: Int): Int
    fun GetRawInputData(hRawInput: Pointer?, uiCommand: Int, pData: Pointer?, pcbSize: IntByReference, cbSizeHeader: Int): Int
    fun ChangeWindowMessageFilterEx(hwnd: WinDef.HWND, message: Int, action: Int, pChangeFilterStruct: Pointer?): Boolean
    fun PostMessageW(hWnd: WinDef.HWND?, msg: Int, wParam: WinDef.WPARAM?, lParam: WinDef.LPARAM?): Boolean
    fun PostQuitMessage(nExitCode: Int)
    fun AllowSetForegroundWindow(dwProcessId: Int): Boolean

    companion object {
        val INSTANCE: User32X by lazy { Native.load("user32", User32X::class.java) }
    }
}

interface Shell32X : Library {
    fun Shell_NotifyIconW(dwMessage: Int, lpData: NOTIFYICONDATAW): Boolean
    fun Shell_NotifyIconGetRect(identifier: NOTIFYICONIDENTIFIER, iconLocation: WinDef.RECT): Int

    companion object {
        val INSTANCE: Shell32X by lazy { Native.load("shell32", Shell32X::class.java) }
    }
}

interface Gdi32X : Library {
    fun CreateBitmap(nWidth: Int, nHeight: Int, nPlanes: Int, nBitCount: Int, lpBits: Pointer?): WinDef.HBITMAP?

    companion object {
        val INSTANCE: Gdi32X by lazy { Native.load("gdi32", Gdi32X::class.java) }
    }
}

interface Kernel32X : Library {
    /** Windows 8+. 패키지 밖이면 APPMODEL_ERROR_NO_PACKAGE(15700). */
    fun GetCurrentPackageFamilyName(packageFamilyNameLength: IntByReference, packageFamilyName: CharArray?): Int

    companion object {
        val INSTANCE: Kernel32X by lazy { Native.load("kernel32", Kernel32X::class.java) }
    }
}

interface ShcoreX : Library {
    /** Windows 8.1+. HRESULT. */
    fun GetDpiForMonitor(hmonitor: WinUser.HMONITOR, dpiType: Int, dpiX: IntByReference, dpiY: IntByReference): Int

    companion object {
        val INSTANCE: ShcoreX by lazy { Native.load("shcore", ShcoreX::class.java) }
    }
}

/**
 * NOTIFYICONDATAW(Vista+ 전체판). 64비트 Windows(x64·arm64, LLP64)에서 976바이트(W0-e 러너 2종 실측).
 * uTimeout/uVersion 공용체는 uVersion 한 칸으로 둔다.
 */
@Structure.FieldOrder(
    "cbSize", "hWnd", "uID", "uFlags", "uCallbackMessage", "hIcon", "szTip", "dwState", "dwStateMask",
    "szInfo", "uVersion", "szInfoTitle", "dwInfoFlags", "guidItem", "hBalloonIcon",
)
class NOTIFYICONDATAW : Structure() {
    @JvmField var cbSize: Int = 0
    @JvmField var hWnd: WinDef.HWND? = null
    @JvmField var uID: Int = 0
    @JvmField var uFlags: Int = 0
    @JvmField var uCallbackMessage: Int = 0
    @JvmField var hIcon: WinDef.HICON? = null
    @JvmField var szTip: CharArray = CharArray(128)
    @JvmField var dwState: Int = 0
    @JvmField var dwStateMask: Int = 0
    @JvmField var szInfo: CharArray = CharArray(256)
    @JvmField var uVersion: Int = 0
    @JvmField var szInfoTitle: CharArray = CharArray(64)
    @JvmField var dwInfoFlags: Int = 0
    @JvmField var guidItem: Guid.GUID = Guid.GUID()
    @JvmField var hBalloonIcon: WinDef.HICON? = null

    /** 툴팁은 127자에서 자른다(끝 NUL 자리). 서로게이트 쌍을 반으로 가르지 않는다. */
    fun setTip(text: String) {
        val clipped = clipUtf16(text, szTip.size - 1)
        szTip.fill('\u0000')
        clipped.toCharArray().copyInto(szTip)
    }

    companion object {
        const val EXPECTED_SIZE_64 = 976

        /** UTF-16 단위로 [max] 이하로 자르되 서로게이트 쌍의 앞쪽만 남기지 않는다. */
        fun clipUtf16(text: String, max: Int): String {
            if (text.length <= max) return text
            val end = if (Character.isHighSurrogate(text[max - 1])) max - 1 else max
            return text.substring(0, end)
        }
    }
}

@Structure.FieldOrder("cbSize", "hWnd", "uID", "guidItem")
class NOTIFYICONIDENTIFIER : Structure() {
    @JvmField var cbSize: Int = 0
    @JvmField var hWnd: WinDef.HWND? = null
    @JvmField var uID: Int = 0
    @JvmField var guidItem: Guid.GUID = Guid.GUID()
}

/** RAWINPUTDEVICE: USHORT 둘 + DWORD + HWND(64비트 16바이트). 배열로 넘기려면 [Structure.toArray] 로 연속 메모리를 만든다. */
@Structure.FieldOrder("usUsagePage", "usUsage", "dwFlags", "hwndTarget")
class RAWINPUTDEVICE : Structure() {
    @JvmField var usUsagePage: Short = 0
    @JvmField var usUsage: Short = 0
    @JvmField var dwFlags: Int = 0
    @JvmField var hwndTarget: WinDef.HWND? = null
}
