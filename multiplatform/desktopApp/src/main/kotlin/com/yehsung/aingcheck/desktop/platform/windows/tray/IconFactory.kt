// 원본: 없음(새 코드) — 설계 D§3-2(현재 DPI 의 SM_CXSMICON 크기로 직접 그린 HICON)
// 32bpp 위→아래(biHeight 음수) DIB 에 ARGB 를 그대로 쓴다: 리틀 엔디언에서 0xAARRGGBB 정수는 메모리에 B,G,R,A 로 놓여
// 아이콘의 BGRA 와 같다. 아이콘의 32비트 색은 **직선 알파**다(미리 곱하지 않는다) — 렌더러 출력과 같다.
// 마스크는 0 으로 채운 1비트 비트맵(알파가 있는 32비트 아이콘에서는 쓰이지 않지만 CreateIconIndirect 가 요구한다).
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.sun.jna.Memory
import com.sun.jna.platform.win32.GDI32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinGDI
import com.sun.jna.ptr.PointerByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.desktop.platform.windows.jna.Gdi32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X

internal object IconFactory {
    private const val BI_RGB = 0
    private const val DIB_RGB_COLORS = 0

    fun create(image: RasterImage): WinDef.HICON {
        val w = image.width
        val h = image.height
        val bmi = WinGDI.BITMAPINFO()
        bmi.bmiHeader.biSize = bmi.bmiHeader.size()
        bmi.bmiHeader.biWidth = w
        bmi.bmiHeader.biHeight = -h
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = BI_RGB
        val bits = PointerByReference()
        val color = GDI32.INSTANCE.CreateDIBSection(null, bmi, DIB_RGB_COLORS, bits, null, 0)
            ?: error("CreateDIBSection 실패")
        try {
            bits.value.write(0, image.argb, 0, w * h)
            val rowBytes = ((w + 15) / 16) * 2
            val maskBits = Memory((rowBytes * h).toLong()).also { it.clear() }
            val mask = Gdi32X.INSTANCE.CreateBitmap(w, h, 1, 1, maskBits) ?: error("CreateBitmap(마스크) 실패")
            try {
                val info = WinGDI.ICONINFO()
                info.fIcon = true
                info.hbmMask = mask
                info.hbmColor = color
                return User32X.INSTANCE.CreateIconIndirect(info) ?: error("CreateIconIndirect 실패")
            } finally {
                GDI32.INSTANCE.DeleteObject(mask)
            }
        } finally {
            GDI32.INSTANCE.DeleteObject(color)
        }
    }
}
