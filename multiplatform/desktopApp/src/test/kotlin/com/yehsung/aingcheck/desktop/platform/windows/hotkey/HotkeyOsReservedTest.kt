// W-13 #3: OS 예약 조합은 등록 전에 거른다(RESERVED_KEY → 설정 화면 '시스템이 쓰는 조합' 안내). 맥 대응: 시스템 단축키 목록 대조(.conflict).
package com.yehsung.aingcheck.desktop.platform.windows.hotkey

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy.Rejection
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy.Verdict
import kotlin.test.Test
import kotlin.test.assertEquals

class HotkeyOsReservedTest {
    private fun chord(ctrl: Boolean = false, alt: Boolean = false, shift: Boolean = false, win: Boolean = false, key: Int) =
        HotkeyChord(ctrl = ctrl, alt = alt, shift = shift, win = win, keyCode = key)

    private val reserved = Verdict.Rejected(Rejection.RESERVED_KEY)

    @Test
    fun 다섯_예약_조합은_RESERVED_KEY() {
        assertEquals(reserved, HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = HotkeyPolicy.VK_DELETE)), "Ctrl+Alt+Del")
        assertEquals(reserved, HotkeyPolicy.validate(chord(ctrl = true, shift = true, key = HotkeyPolicy.VK_ESCAPE)), "Ctrl+Shift+Esc")
        assertEquals(reserved, HotkeyPolicy.validate(chord(win = true, key = HotkeyPolicy.VK_L)), "Win+L")
        assertEquals(reserved, HotkeyPolicy.validate(chord(alt = true, key = HotkeyPolicy.VK_TAB)), "Alt+Tab")
        assertEquals(reserved, HotkeyPolicy.validate(chord(alt = true, key = HotkeyPolicy.VK_F4)), "Alt+F4")
    }

    @Test
    fun 수식키를_더해도_OS_가_먼저_먹는_조합() {
        assertEquals(reserved, HotkeyPolicy.validate(chord(ctrl = true, alt = true, shift = true, key = HotkeyPolicy.VK_DELETE)), "SAS 는 Shift 무관")
        assertEquals(reserved, HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = HotkeyPolicy.VK_TAB)), "Ctrl+Alt+Tab 전환기")
        assertEquals(reserved, HotkeyPolicy.validate(chord(alt = true, shift = true, key = HotkeyPolicy.VK_TAB)), "Shift+Alt+Tab")
    }

    /** 음성 대조: 이웃 조합은 통과(과하게 막지 않는다). */
    @Test
    fun 이웃_조합은_통과() {
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(chord(ctrl = true, shift = true, key = HotkeyPolicy.VK_DELETE)), "Ctrl+Shift+Del")
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(chord(ctrl = true, alt = true, shift = true, key = HotkeyPolicy.VK_ESCAPE)), "Ctrl+Alt+Shift+Esc")
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = HotkeyPolicy.VK_F4)), "Ctrl+Alt+F4")
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = HotkeyPolicy.VK_L)), "Ctrl+Alt+L")
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(chord(ctrl = true, shift = true, key = HotkeyPolicy.VK_TAB)), "Ctrl+Shift+Tab(Alt 없음)")
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(HotkeyPolicy.DEFAULT), "기본 Ctrl+Alt+Shift+Space")
    }
}
