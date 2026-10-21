package com.yehsung.aingcheck.spike.windows

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.Structure
import com.sun.jna.WString
import com.sun.jna.platform.win32.Guid
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.ptr.IntByReference

/**
 * jna-platform 에 없거나 서명이 불확실한 Win32 함수만 따로 묶는다. 이름에 W 를 직접 붙여 함수 이름 매퍼를 쓰지 않는다.
 * JNA 의 Java char 는 native wchar_t(Windows 2바이트)로 간다.
 */
interface Kernel32X : Library {
    fun ProcessIdToSessionId(dwProcessId: Int, pSessionId: IntByReference): Boolean
    fun WTSGetActiveConsoleSessionId(): Int
    fun GetCurrentProcessId(): Int
    fun GetCurrentThreadId(): Int

    companion object {
        val INSTANCE: Kernel32X by lazy { Native.load("kernel32", Kernel32X::class.java) }
    }
}

interface User32X : Library {
    fun GetProcessWindowStation(): Pointer?
    fun GetThreadDesktop(dwThreadId: Int): Pointer?
    fun GetUserObjectInformationW(hObj: Pointer?, nIndex: Int, pvInfo: Pointer?, nLength: Int, lpnLengthNeeded: IntByReference?): Boolean
    fun RegisterWindowMessageW(lpString: WString): Int
    fun LoadIconW(hInstance: Pointer?, lpIconName: Pointer?): Pointer?

    companion object {
        const val UOI_FLAGS = 1
        const val UOI_NAME = 2
        const val WSF_VISIBLE = 1
        const val IDI_APPLICATION = 32512L
        val INSTANCE: User32X by lazy { Native.load("user32", User32X::class.java) }
    }
}

interface Shell32X : Library {
    fun Shell_NotifyIconW(dwMessage: Int, lpData: NOTIFYICONDATAW): Boolean
    fun Shell_NotifyIconGetRect(identifier: NOTIFYICONIDENTIFIER, iconLocation: WinDef.RECT): Int

    companion object {
        const val NIM_ADD = 0
        const val NIM_MODIFY = 1
        const val NIM_DELETE = 2
        const val NIM_SETVERSION = 4
        const val NIF_MESSAGE = 0x1
        const val NIF_ICON = 0x2
        const val NIF_TIP = 0x4
        const val NIF_SHOWTIP = 0x80
        const val NOTIFYICON_VERSION_4 = 4
        val INSTANCE: Shell32X by lazy { Native.load("shell32", Shell32X::class.java) }
    }
}

/**
 * NOTIFYICONDATAW(Vista+ 전체판). 64비트 Windows(x64·arm64, LLP64)에서 976바이트여야 한다 — 탐침이 이 크기를 단언한다.
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
    @JvmField var hIcon: Pointer? = null
    @JvmField var szTip: CharArray = CharArray(128)
    @JvmField var dwState: Int = 0
    @JvmField var dwStateMask: Int = 0
    @JvmField var szInfo: CharArray = CharArray(256)
    @JvmField var uVersion: Int = 0
    @JvmField var szInfoTitle: CharArray = CharArray(64)
    @JvmField var dwInfoFlags: Int = 0
    @JvmField var guidItem: Guid.GUID = Guid.GUID()
    @JvmField var hBalloonIcon: Pointer? = null

    fun setTip(text: String) {
        val chars = text.toCharArray()
        val n = minOf(chars.size, szTip.size - 1)
        System.arraycopy(chars, 0, szTip, 0, n)
        szTip[n] = '\u0000'
    }

    companion object {
        const val EXPECTED_SIZE_64 = 976
    }
}

@Structure.FieldOrder("cbSize", "hWnd", "uID", "guidItem")
class NOTIFYICONIDENTIFIER : Structure() {
    @JvmField var cbSize: Int = 0
    @JvmField var hWnd: WinDef.HWND? = null
    @JvmField var uID: Int = 0
    @JvmField var guidItem: Guid.GUID = Guid.GUID()
}

@Structure.FieldOrder("fInherit", "fReserved", "dwFlags")
class USEROBJECTFLAGS : Structure() {
    @JvmField var fInherit: Int = 0
    @JvmField var fReserved: Int = 0
    @JvmField var dwFlags: Int = 0
}
