// 원본: Sources/check/MiniGamePanel.swift:153-156(물리 키 자리 — 한글 입력 상태) · CheckMiniGameWindow.swift:225-233(창이 선 뒤 주사율) ·
//       CheckApp.swift:344-440(requestAttention — 앱이 뒤면 주의 끌기) · CheckGomokuWindow.swift:340-346(occlusion)
//       (W4-d 창 공통 부품 — games.md §4. Windows 가 아니면 전부 아무 일도 안 한다 — 맥 JVM 시험은 창 0·네이티브 호출 0)
package com.yehsung.aingcheck.desktop.windows.kit

import com.sun.jna.Library
import com.sun.jna.Memory
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.WString
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.desktop.platform.windows.HostOs
import java.awt.Container
import java.awt.DisplayMode
import java.awt.Window

/**
 * 게임 창의 IME 를 뗀다/붙인다. ★ **미니게임·테트리스 대결 창만** 부른다(ImeGateScopeContractTest 가 소스에서 잰다).
 * 오목·체스는 떼지 않는다 — 오목 창엔 채팅 칸이 있고 판은 마우스로 둔다(games.md §6 위험 ①).
 * Compose 의 입력 HWND 는 자식이라 IACE_CHILDREN 이 필요하다(위험 ② — AWT enableInputMethods 와 VM 에서 비교).
 */
object ImeGate {
    fun detach(window: Window) {
        if (!HostOs.isWindows()) return
        setAwtInputMethods(window, enabled = false)
        val hwnd = KitWin32.hwndOf(window) ?: return
        runCatching {
            KitWin32.imm32.ImmAssociateContextEx(hwnd, null, 0)
            KitWin32.imm32.ImmAssociateContextEx(hwnd, null, KitWin32.IACE_CHILDREN)
        }
    }

    fun reattach(window: Window) {
        if (!HostOs.isWindows()) return
        setAwtInputMethods(window, enabled = true)
        val hwnd = KitWin32.hwndOf(window) ?: return
        runCatching {
            KitWin32.imm32.ImmAssociateContextEx(hwnd, null, KitWin32.IACE_DEFAULT)
            User32.INSTANCE.EnumChildWindows(hwnd, { child, _ ->
                KitWin32.imm32.ImmAssociateContextEx(child, null, KitWin32.IACE_DEFAULT)
                true
            }, null)
        }
    }

    private fun setAwtInputMethods(c: java.awt.Component, enabled: Boolean) {
        c.enableInputMethods(enabled)
        if (c is Container) c.components.forEach { setAwtInputMethods(it, enabled) }
    }
}

/** 앱이 뒤에 있을 때 작업 표시줄 단추를 깜빡인다 — 창이 앞으로 오면 멈춘다(FLASHW_ALL | FLASHW_TIMERNOFG). */
object AttentionFlash {
    const val FLASHW_ALL = 0x3
    const val FLASHW_TIMERNOFG = 0xC

    fun flashUntilForeground(window: Window) {
        if (!HostOs.isWindows()) return
        val hwnd = KitWin32.hwndOf(window) ?: return
        runCatching {
            val info = WinUser.FLASHWINFO()
            info.cbSize = info.size()
            info.hWnd = hwnd
            info.dwFlags = FLASHW_ALL or FLASHW_TIMERNOFG
            info.uCount = 0
            info.dwTimeout = 0
            User32.INSTANCE.FlashWindowEx(info)
        }
    }
}

/**
 * 창이 걸린 모니터의 주사율(Hz). **값만** — 간격 판정은 core `MiniGameFrameRate`(다시 만들지 마라).
 * 창이 선 **뒤**에 부른다(맥 CheckMiniGameWindow.swift:225-233 — 서기 전엔 화면이 정해지지 않았다).
 */
object RefreshRateProbe {
    const val FALLBACK_HZ = 60

    fun hz(window: Window): Int {
        val native = if (HostOs.isWindows()) runCatching { KitWin32.monitorHz(window) }.getOrNull() else null
        if (native != null && native > 1) return native
        val awt = runCatching { window.graphicsConfiguration?.device?.displayMode?.refreshRate }.getOrNull()
        return normalize(awt)
    }

    /** 0·1(하드웨어 기본)·모름·음수 → 60(안드로이드 DisplayRefreshRate.kt:27 의 0·NaN → 60 과 같은 규약). */
    fun normalize(raw: Int?): Int =
        if (raw == null || raw <= 1 || raw == DisplayMode.REFRESH_RATE_UNKNOWN) FALLBACK_HZ else raw
}

/** 가상 데스크톱 전환으로 창이 cloak 됐는가(DwmGetWindowAttribute DWMWA_CLOAKED) — [WindowEvent.Visibility] 의 근거. */
object CloakProbe {
    fun isCloaked(window: Window): Boolean {
        if (!HostOs.isWindows()) return false
        val hwnd = KitWin32.hwndOf(window) ?: return false
        return runCatching {
            val out = IntByReference(0)
            KitWin32.dwmapi.DwmGetWindowAttribute(hwnd, KitWin32.DWMWA_CLOAKED, out, 4) == 0 && out.value != 0
        }.getOrDefault(false)
    }
}

/** 이 갈래가 쓰는 Win32 심볼(JnaSymbolSmokeTest 가 러너에서 조회만 한다). */
internal object KitWin32 {
    const val IACE_CHILDREN = 0x0001
    const val IACE_DEFAULT = 0x0010
    const val DWMWA_CLOAKED = 14
    const val ENUM_CURRENT_SETTINGS = -1
    const val MONITOR_DEFAULTTONEAREST = 2

    /** DEVMODEW: sizeof 220 · dmSize @68 · dmDisplayFrequency @184. */
    const val DEVMODEW_SIZE = 220
    const val DEVMODEW_DMSIZE_OFFSET = 68L
    const val DEVMODEW_FREQUENCY_OFFSET = 184L

    interface Imm32Kit : Library {
        fun ImmAssociateContextEx(hWnd: WinDef.HWND, hIMC: Pointer?, dwFlags: Int): Boolean
    }

    interface User32Kit : Library {
        fun EnumDisplaySettingsW(lpszDeviceName: WString, iModeNum: Int, lpDevMode: Pointer): Boolean
    }

    interface DwmapiKit : Library {
        fun DwmGetWindowAttribute(hwnd: WinDef.HWND, dwAttribute: Int, pvAttribute: IntByReference, cbAttribute: Int): Int
    }

    val imm32: Imm32Kit by lazy { Native.load("imm32", Imm32Kit::class.java) }
    val user32: User32Kit by lazy { Native.load("user32", User32Kit::class.java) }
    val dwmapi: DwmapiKit by lazy { Native.load("dwmapi", DwmapiKit::class.java) }

    fun hwndOf(window: Window): WinDef.HWND? = runCatching {
        if (!window.isDisplayable) null else WinDef.HWND(Native.getWindowPointer(window))
    }.getOrNull()

    fun monitorHz(window: Window): Int? {
        val hwnd = hwndOf(window) ?: return null
        val monitor = User32.INSTANCE.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) ?: return null
        val info = WinUser.MONITORINFOEX()
        if (!User32.INSTANCE.GetMonitorInfo(monitor, info).booleanValue()) return null
        val device = Native.toString(info.szDevice)
        val mode = Memory(DEVMODEW_SIZE.toLong())
        mode.clear()
        mode.setShort(DEVMODEW_DMSIZE_OFFSET, DEVMODEW_SIZE.toShort())
        if (!user32.EnumDisplaySettingsW(WString(device), ENUM_CURRENT_SETTINGS, mode)) return null
        return mode.getInt(DEVMODEW_FREQUENCY_OFFSET)
    }
}
