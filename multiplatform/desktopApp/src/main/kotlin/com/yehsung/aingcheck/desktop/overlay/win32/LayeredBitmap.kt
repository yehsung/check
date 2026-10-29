// 원본: 없음(새 코드) — 설계 D §9-1(UpdateLayeredWindow 픽셀 알파) · F §5.4(오프스크린 프리멀티 → 창)
//
// 32bpp 위에서 아래(biHeight 음수) DIB 하나를 메모리 DC 에 골라 두고, 프레임마다 프리멀티 BGRA 바이트를 덮어써
// UpdateLayeredWindow(ULW_ALPHA, AC_SRC_ALPHA)로 창에 올린다. 크기가 바뀔 때만 DIB 를 새로 만든다(30fps 에서 GDI 개체 churn 0).
package com.yehsung.aingcheck.desktop.overlay.win32

import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.platform.win32.GDI32
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinGDI
import com.sun.jna.platform.win32.WinNT
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.PointerByReference

/** UpdateLayeredWindow 한 번의 결과. ok 거짓이면 errorCode = GetLastError. */
data class LayeredUpdate(val ok: Boolean, val errorCode: Int)

/** 창 하나에 딸린 DIB. 그 창을 만든 스레드(메시지 스레드)에서만 부른다. */
class LayeredBitmap : AutoCloseable {
    private var memDc: WinDef.HDC? = null
    private var bitmap: WinDef.HBITMAP? = null
    private var previous: WinNT.HANDLE? = null
    private var bits: Pointer? = null
    var width: Int = 0
        private set
    var height: Int = 0
        private set

    private fun ensure(w: Int, h: Int) {
        if (bitmap != null && w == width && h == height) return
        release()
        val g = GDI32.INSTANCE
        val dc = g.CreateCompatibleDC(null) ?: error("CreateCompatibleDC 실패 err=${Native.getLastError()}")
        val bmi = WinGDI.BITMAPINFO()
        bmi.bmiHeader.biSize = bmi.bmiHeader.size()
        bmi.bmiHeader.biWidth = w
        bmi.bmiHeader.biHeight = -h // 위에서 아래 — 행 0 이 위(Skia 표면과 같은 순서)
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = OverlayWin32.BI_RGB
        val ppv = PointerByReference()
        val hbm = g.CreateDIBSection(dc, bmi, OverlayWin32.DIB_RGB_COLORS, ppv, null, 0)
        if (hbm == null || ppv.value == null) {
            val err = Native.getLastError()
            g.DeleteDC(dc)
            error("CreateDIBSection(${w}x$h) 실패 err=$err")
        }
        memDc = dc
        bitmap = hbm
        bits = ppv.value
        previous = g.SelectObject(dc, hbm)
        width = w
        height = h
    }

    /**
     * [bgraPremultiplied](행 0 = 위, 4바이트 B·G·R·A, 프리멀티)를 창 [hwnd] 의 화면 [xPx],[yPx] 에 올린다.
     * 레이어드 창은 이 호출 전까지 화면에 안 보인다 — 보이기(ShowWindow)는 첫 성공 뒤에.
     */
    fun present(hwnd: WinDef.HWND, bgraPremultiplied: ByteArray, w: Int, h: Int, xPx: Int, yPx: Int): LayeredUpdate {
        require(bgraPremultiplied.size == w * h * 4) { "바이트 수가 ${w}x$h 와 다르다: ${bgraPremultiplied.size}" }
        ensure(w, h)
        bits!!.write(0, bgraPremultiplied, 0, bgraPremultiplied.size)
        val blend = WinUser.BLENDFUNCTION().apply {
            BlendOp = OverlayWin32.AC_SRC_OVER
            BlendFlags = 0
            SourceConstantAlpha = 255.toByte()
            AlphaFormat = OverlayWin32.AC_SRC_ALPHA
        }
        val u = User32.INSTANCE
        val screenDc = u.GetDC(null)
        try {
            val ok = u.UpdateLayeredWindow(
                hwnd, screenDc, WinDef.POINT(xPx, yPx), WinUser.SIZE(w, h), memDc, WinDef.POINT(0, 0), 0, blend, OverlayWin32.ULW_ALPHA,
            )
            return LayeredUpdate(ok, if (ok) 0 else Native.getLastError())
        } finally {
            if (screenDc != null) u.ReleaseDC(null, screenDc)
        }
    }

    private fun release() {
        val g = GDI32.INSTANCE
        val dc = memDc
        if (dc != null) {
            previous?.let { g.SelectObject(dc, it) }
            bitmap?.let { g.DeleteObject(it) }
            g.DeleteDC(dc)
        }
        memDc = null
        bitmap = null
        previous = null
        bits = null
        width = 0
        height = 0
    }

    override fun close() = release()
}
