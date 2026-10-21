package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** NOTIFYICON_VERSION_4 콜백 풀기. wParam·lParam 은 손으로 비트를 짜서 넣는다(encode 를 기대값 만들기에 쓰지 않는다). */
class TrayCallbackDecoderTest {
    @Test
    fun selectCarriesSignedAnchorCoordinates() {
        // x = -1500(0xFA24), y = 1060(0x0424), 사건 NIN_SELECT(0x400), 아이콘 1.
        val ev = TrayCallbackDecoder.decode(wParam = 0x0424_FA24L, lParam = 0x0001_0400L)
        assertEquals(TrayEvent(TrayClick.PRIMARY, iconId = 1, screenX = -1500, screenY = 1060, viaKeyboard = false), ev)
    }

    @Test
    fun negativeYFromMonitorAbovePrimary() {
        // x = 300(0x012C), y = -20(0xFFEC).
        val ev = TrayCallbackDecoder.decode(wParam = 0xFFEC_012CL, lParam = 0x0001_0400L)!!
        assertEquals(300, ev.screenX)
        assertEquals(-20, ev.screenY)
    }

    @Test
    fun keyboardContextAndDoubleClick() {
        assertEquals(TrayClick.PRIMARY, TrayCallbackDecoder.decode(0x0010_0010L, 0x0001_0401L)!!.click)
        assertEquals(true, TrayCallbackDecoder.decode(0x0010_0010L, 0x0001_0401L)!!.viaKeyboard)
        assertEquals(TrayClick.SECONDARY, TrayCallbackDecoder.decode(0x0010_0010L, 0x0001_007BL)!!.click)
        assertEquals(TrayClick.DOUBLE, TrayCallbackDecoder.decode(0x0010_0010L, 0x0001_0203L)!!.click)
    }

    @Test
    fun otherNotificationsAreIgnored() {
        // WM_MOUSEMOVE(0x200) · WM_LBUTTONDOWN(0x201) · WM_LBUTTONUP(0x202) · NIN_POPUPOPEN(0x406) · NIN_BALLOONSHOW(0x402)
        for (event in listOf(0x200, 0x201, 0x202, 0x406, 0x402)) {
            assertNull(TrayCallbackDecoder.decode(0x0010_0010L, 0x0001_0000L or event.toLong()), "0x${event.toString(16)}")
        }
    }

    @Test
    fun iconIdComesFromHighWordAndHigh64BitsAreIgnored() {
        val ev = TrayCallbackDecoder.decode(0x7777_0000_0005_0006L, 0x5555_0000_0007_0400L)!!
        assertEquals(7, ev.iconId)
        assertEquals(6, ev.screenX)
        assertEquals(5, ev.screenY)
    }

    @Test
    fun encodeIsTheInverseOfDecode() {
        for ((x, y) in listOf(0 to 0, -1 to -1, -32768 to 32767, 2559 to -1439)) {
            val (w, l) = TrayCallbackDecoder.encode(0x400, 3, x, y)
            assertEquals(TrayEvent(TrayClick.PRIMARY, 3, x, y, false), TrayCallbackDecoder.decode(w, l))
        }
    }
}
