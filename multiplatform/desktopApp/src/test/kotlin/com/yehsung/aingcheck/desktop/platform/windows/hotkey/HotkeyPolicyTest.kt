// 원본: Sources/check/WorkShortcut.swift:36-46 @ a63fea2 (수식키만 있는 조합을 막는다) — 시험은 새 코드: 설계 D§6(Win 키 예약·수식키 둘 이상·IME 키 금지)
package com.yehsung.aingcheck.desktop.platform.windows.hotkey

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy.Rejection
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy.Verdict
import kotlin.test.Test
import kotlin.test.assertEquals

class HotkeyPolicyTest {
    private fun chord(ctrl: Boolean = false, alt: Boolean = false, shift: Boolean = false, win: Boolean = false, key: Int = 0x20) =
        HotkeyChord(ctrl, alt, shift, win, key)

    @Test
    fun defaultIsCtrlAltShiftSpaceAndValid() {
        assertEquals(chord(ctrl = true, alt = true, shift = true, key = 0x20), HotkeyPolicy.DEFAULT)
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(HotkeyPolicy.DEFAULT))
        // RegisterHotKey 깃발: Ctrl(2)|Alt(1)|Shift(4)|NOREPEAT(0x4000) — winuser.h 값으로 손계산.
        assertEquals(0x4007, HotkeyPolicy.modifiers(HotkeyPolicy.DEFAULT))
    }

    @Test
    fun winKeyIsReservedByTheOs() {
        assertEquals(Verdict.Rejected(Rejection.WIN_KEY_RESERVED), HotkeyPolicy.validate(chord(ctrl = true, alt = true, win = true)))
    }

    @Test
    fun singleKeyAndSingleModifierAreRejected() {
        assertEquals(Verdict.Rejected(Rejection.TOO_FEW_MODIFIERS), HotkeyPolicy.validate(chord(key = 0x41)))
        assertEquals(Verdict.Rejected(Rejection.TOO_FEW_MODIFIERS), HotkeyPolicy.validate(chord(ctrl = true, key = 0x41)))
        assertEquals(Verdict.Rejected(Rejection.TOO_FEW_MODIFIERS), HotkeyPolicy.validate(chord(shift = true, key = 0x41)))
        assertEquals(Verdict.Ok, HotkeyPolicy.validate(chord(ctrl = true, shift = true, key = 0x41)))
    }

    @Test
    fun modifierImeAndReservedKeysCannotBeTheKey() {
        for (vk in listOf(0x10, 0x11, 0x12, 0xA0, 0xA5, 0x5B, 0x5C)) {
            assertEquals(Verdict.Rejected(Rejection.KEY_IS_MODIFIER), HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = vk)), "vk 0x${vk.toString(16)}")
        }
        // 한/영(VK_HANGUL 0x15)·한자(0x19)·한글 모드의 글자 키(VK_PROCESSKEY 0xE5)
        for (vk in listOf(0x15, 0x19, 0xE5)) {
            assertEquals(Verdict.Rejected(Rejection.KEY_IS_IME), HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = vk)), "vk 0x${vk.toString(16)}")
        }
        assertEquals(Verdict.Rejected(Rejection.RESERVED_KEY), HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = 0x7B)))
        assertEquals(Verdict.Rejected(Rejection.KEY_OUT_OF_RANGE), HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = 0)))
        assertEquals(Verdict.Rejected(Rejection.KEY_OUT_OF_RANGE), HotkeyPolicy.validate(chord(ctrl = true, alt = true, key = 0x1FF)))
    }

    @Test
    fun noRepeatIsAlwaysSet() {
        assertEquals(0x4000 or 0x2 or 0x1, HotkeyPolicy.modifiers(chord(ctrl = true, alt = true)))
        assertEquals(0x4000 or 0x4 or 0x2, HotkeyPolicy.modifiers(chord(ctrl = true, shift = true)))
    }
}
