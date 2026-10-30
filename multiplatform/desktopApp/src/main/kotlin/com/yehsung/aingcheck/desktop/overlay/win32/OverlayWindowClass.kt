// 원본: CheckOverlayWindow.swift :2211-2250 makePanel(경계 없음 · 비활성 패널 · 떠 있음 · 배경 투명 · 그림자 없음 · sharingType none)
//       설계 D §9-1 · §9-4 · W-3 #10(러너에 DWM 이 없으면 오류 코드만 기록)
//
// 창 클래스 하나(창 프로시저 하나)에 창 여럿 — 캐릭터 창과 울트라 흐림 창이 같은 메시지 스레드에서 산다.
// **이 클래스의 모든 함수는 창을 만든 메시지 스레드에서만 부른다**(Win32MessageThread.call 안). 창 프로시저 콜백은
// GC 되면 사라진 주소를 부르므로 필드로 붙잡는다.
package com.yehsung.aingcheck.desktop.overlay.win32

import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference
import java.util.concurrent.ConcurrentHashMap

/** 창 하나의 메시지 처리기. null 이면 DefWindowProc. */
fun interface OverlayWindowProc {
    fun handle(hwnd: WinDef.HWND, msg: Int, wParam: WinDef.WPARAM, lParam: WinDef.LPARAM): WinDef.LRESULT?
}

class OverlayWindowClass(val name: String, private val blackBackground: Boolean = false) : AutoCloseable {
    private val handlers = ConcurrentHashMap<Long, OverlayWindowProc>()
    private val proc = WinUser.WindowProc { h, m, w, l ->
        handlers[Pointer.nativeValue(h.pointer)]?.handle(h, m, w, l) ?: User32.INSTANCE.DefWindowProc(h, m, w, l)
    }
    private val hInst = Kernel32.INSTANCE.GetModuleHandle(null)
    private var wc: WinUser.WNDCLASSEX? = null

    fun register() {
        if (wc != null) return
        val c = WinUser.WNDCLASSEX()
        c.hInstance = hInst
        c.lpfnWndProc = proc
        c.lpszClassName = name
        if (blackBackground) OverlayGdi32.INSTANCE.GetStockObject(OverlayWin32.BLACK_BRUSH)?.let { c.hbrBackground = WinDef.HBRUSH(it) }
        val atom = User32.INSTANCE.RegisterClassEx(c)
        check(atom != null && atom.toInt() != 0) { "RegisterClassEx('$name') 실패 err=${Native.getLastError()}" }
        wc = c
    }

    /** 숨은 채로 만든다(WS_VISIBLE 없음). 레이어드 창은 UpdateLayeredWindow/SetLayeredWindowAttributes 전엔 그려지지 않는다. */
    fun create(exStyle: Int, xPx: Int, yPx: Int, wPx: Int, hPx: Int, handler: OverlayWindowProc): WinDef.HWND {
        register()
        val hwnd = User32.INSTANCE.CreateWindowEx(exStyle, name, "", OverlayWin32.WS_POPUP, xPx, yPx, wPx, hPx, null, null, hInst, null)
            ?: error("CreateWindowEx('$name') 실패 err=${Native.getLastError()}")
        handlers[Pointer.nativeValue(hwnd.pointer)] = handler
        return hwnd
    }

    fun destroy(hwnd: WinDef.HWND) {
        User32.INSTANCE.DestroyWindow(hwnd)
        handlers.remove(Pointer.nativeValue(hwnd.pointer))
    }

    override fun close() {
        if (wc == null) return
        User32.INSTANCE.UnregisterClass(name, hInst)
        java.lang.ref.Reference.reachabilityFence(proc)
        wc = null
    }

    companion object {
        /** 맥 sharingType = .none 의 대역. 실패해도 창은 쓴다(W-3 #10: 오류 코드만 기록하고 VM 묶음으로). */
        fun excludeFromCapture(hwnd: WinDef.HWND): CaptureExclusion {
            val u = OverlayUser32.INSTANCE
            val ok = u.SetWindowDisplayAffinity(hwnd, OverlayWin32.WDA_EXCLUDEFROMCAPTURE)
            val err = if (ok) 0 else Native.getLastError()
            val read = IntByReference(-1)
            val readOk = u.GetWindowDisplayAffinity(hwnd, read)
            return CaptureExclusion(ok, err, if (readOk) read.value else -1, dwmCompositionEnabled())
        }

        /** null = dwmapi 를 못 불렀다. */
        fun dwmCompositionEnabled(): Boolean? = runCatching {
            val b = IntByReference(0)
            if (OverlayDwmApi.INSTANCE.DwmIsCompositionEnabled(b) == 0) b.value != 0 else null
        }.getOrNull()

        fun exStyle(hwnd: WinDef.HWND): Int = User32.INSTANCE.GetWindowLong(hwnd, OverlayWin32.GWL_EXSTYLE)

        fun showNoActivate(hwnd: WinDef.HWND) {
            User32.INSTANCE.ShowWindow(hwnd, OverlayWin32.SW_SHOWNOACTIVATE)
            User32.INSTANCE.SetWindowPos(
                hwnd, OverlayWin32.HWND_TOPMOST, 0, 0, 0, 0,
                OverlayWin32.SWP_NOMOVE or OverlayWin32.SWP_NOSIZE or OverlayWin32.SWP_NOACTIVATE,
            )
        }

        fun hide(hwnd: WinDef.HWND) {
            User32.INSTANCE.ShowWindow(hwnd, OverlayWin32.SW_HIDE)
        }

        fun dpiScale(hwnd: WinDef.HWND): Double {
            val dpi = runCatching { OverlayUser32.INSTANCE.GetDpiForWindow(hwnd) }.getOrDefault(0)
            return if (dpi <= 0) 1.0 else dpi.toDouble() / OverlayWin32.USER_DEFAULT_DPI
        }
    }
}

/** 캡처 제외 시도 결과. affinity 는 읽어 온 값(못 읽으면 −1). */
data class CaptureExclusion(val applied: Boolean, val errorCode: Int, val affinity: Int, val dwmComposition: Boolean?) {
    val excluded: Boolean get() = affinity == OverlayWin32.WDA_EXCLUDEFROMCAPTURE
    fun describe(): String = "applied=$applied err=$errorCode affinity=0x${Integer.toHexString(affinity)} dwm=$dwmComposition"
}
