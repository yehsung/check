// 원본: 없음(러너 연기 시험) — games.md §5 Windows 러너: imm32 ImmAssociateContextEx · user32 FlashWindowEx·EnumDisplaySettingsW ·
//       dwmapi DwmGetWindowAttribute 심볼 조회만, 창 0 (W4-d)
package com.yehsung.aingcheck.desktop.windows.kit

import com.sun.jna.NativeLibrary
import com.yehsung.aingcheck.desktop.platform.windows.HostOs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import org.junit.jupiter.api.Assumptions.assumeTrue

class JnaSymbolSmokeTest {
    private val symbols = mapOf(
        "imm32" to listOf("ImmAssociateContextEx"),
        "user32" to listOf("FlashWindowEx", "EnumDisplaySettingsW", "MonitorFromWindow", "GetMonitorInfoW", "EnumChildWindows"),
        "dwmapi" to listOf("DwmGetWindowAttribute"),
    )

    @Test
    fun symbolsResolveOnWindows() {
        assumeTrue(HostOs.isWindows(), "Windows 러너에서만(맥·리눅스는 건너뛴다)")
        for ((lib, names) in symbols) {
            val l = NativeLibrary.getInstance(lib)
            for (name in names) assertNotNull(l.getFunction(name), "$lib!$name")
        }
        // 이 갈래의 바인딩 프록시가 실제로 로드된다(호출은 하지 않는다 — 창 0).
        assertNotNull(KitWin32.imm32)
        assertNotNull(KitWin32.user32)
        assertNotNull(KitWin32.dwmapi)
    }

    /** 맥·리눅스에서는 네이티브 문이 아무 일도 하지 않는다(헤드리스 창 0 — 부르는 자리만 잰다). */
    @Test
    fun nonWindowsIsNoOpAndRefreshFallsBackTo60() {
        assertEquals(60, RefreshRateProbe.normalize(null))
        assertEquals(60, RefreshRateProbe.normalize(0))
        assertEquals(60, RefreshRateProbe.normalize(1))
        assertEquals(60, RefreshRateProbe.normalize(java.awt.DisplayMode.REFRESH_RATE_UNKNOWN))
        assertEquals(144, RefreshRateProbe.normalize(144))
        assertEquals(0x3 or 0xC, AttentionFlash.FLASHW_ALL or AttentionFlash.FLASHW_TIMERNOFG)
        assertEquals(220, KitWin32.DEVMODEW_SIZE)
    }
}
