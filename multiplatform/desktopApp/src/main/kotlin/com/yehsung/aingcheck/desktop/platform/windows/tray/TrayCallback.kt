// 원본: 없음(새 코드) — 설계 D§3-1(NOTIFYICON_VERSION_4 콜백: NIN_SELECT·NIN_KEYSELECT·WM_CONTEXTMENU, wParam 에 기준 좌표)
// learn.microsoft.com NOTIFYICONDATAW uCallbackMessage: v4 에서 LOWORD(lParam) = 알림 사건, HIWORD(lParam) = 아이콘 id,
// GET_X_LPARAM(wParam)·GET_Y_LPARAM(wParam) = 기준 좌표(화면 물리 픽셀). 좌표는 **부호 있는 16비트**다 —
// 주 모니터 왼쪽·위에 붙은 모니터는 음수 좌표를 쓴다(그래서 LOWORD 를 그대로 쓰면 65535 근처로 튄다).
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32

data class TrayEvent(val click: TrayClick, val iconId: Int, val screenX: Int, val screenY: Int, val viaKeyboard: Boolean)

object TrayCallbackDecoder {
    /** v4 콜백 한 건을 사건으로 푼다. 우리가 다루지 않는 사건(마우스 이동·단추 내림/올림·풍선 등)은 null. */
    fun decode(wParam: Long, lParam: Long): TrayEvent? {
        val event = (lParam and 0xFFFF).toInt()
        val iconId = ((lParam ushr 16) and 0xFFFF).toInt()
        val x = (wParam and 0xFFFF).toInt().toShort().toInt()
        val y = ((wParam ushr 16) and 0xFFFF).toInt().toShort().toInt()
        val (click, keyboard) = when (event) {
            Win32.NIN_SELECT -> TrayClick.PRIMARY to false
            Win32.NIN_KEYSELECT -> TrayClick.PRIMARY to true
            Win32.WM_CONTEXTMENU -> TrayClick.SECONDARY to false
            Win32.WM_LBUTTONDBLCLK -> TrayClick.DOUBLE to false
            else -> return null
        }
        return TrayEvent(click, iconId, x, y, keyboard)
    }

    /** 시험·재현용: [decode] 의 역. */
    fun encode(event: Int, iconId: Int, x: Int, y: Int): Pair<Long, Long> {
        val w = ((y.toLong() and 0xFFFF) shl 16) or (x.toLong() and 0xFFFF)
        val l = ((iconId.toLong() and 0xFFFF) shl 16) or (event.toLong() and 0xFFFF)
        return w to l
    }
}
