// 원본: Sources/check/WorkShortcut.swift:36-46 @ a63fea2 (수식키만 있는 조합을 막는다) · 설계 D§6
// Windows 전역 단축키 조합 규칙(순수 함수). 설정 화면은 저장 전에 이 판정을 부르고, [WindowsHotkeyService.register] 도
// 같은 판정으로 잘못된 조합을 거절한다.
//  - Win 키 조합은 OS 예약이다("Keyboard shortcuts that involve the WINDOWS key are reserved for use by the operating system").
//  - F12 는 디버거 예약이다(RegisterHotKey 문서).
//  - 단독 키·수식키 하나짜리 조합은 저장하지 않는다(D§6) — 글자 입력·앱 단축키와 겹친다.
//  - 키 자리에 수식키·한/영·한자·IME 처리 키(VK_PROCESSKEY)가 오면 안 된다(한글 모드에서 글자 키는 VK_PROCESSKEY 로 온다, D§13-1).
package com.yehsung.aingcheck.desktop.platform.windows.hotkey

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32

object HotkeyPolicy {
    const val VK_SPACE = 0x20
    const val VK_F12 = 0x7B

    /** 기본 조합 Ctrl+Alt+Shift+Space(§5-4 확정 — 맥 ⌃⌥⌘Space 의 ⌘ 자리를 Shift 로). */
    val DEFAULT: HotkeyChord = HotkeyChord(ctrl = true, alt = true, shift = true, win = false, keyCode = VK_SPACE)

    enum class Rejection { WIN_KEY_RESERVED, TOO_FEW_MODIFIERS, KEY_IS_MODIFIER, KEY_IS_IME, RESERVED_KEY, KEY_OUT_OF_RANGE }

    sealed interface Verdict {
        data object Ok : Verdict
        data class Rejected(val reason: Rejection) : Verdict
    }

    private val MODIFIER_KEYS = setOf(
        0x10, 0x11, 0x12, // SHIFT · CONTROL · MENU(Alt)
        0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, // 좌우 SHIFT · CONTROL · MENU
        0x5B, 0x5C, // LWIN · RWIN
        0x14, // CAPITAL
    )

    /** VK_HANGUL(=KANA 0x15) · VK_JUNJA · VK_FINAL · VK_HANJA(0x19) · IME 켜기/끄기 · VK_PROCESSKEY(0xE5). */
    private val IME_KEYS = setOf(0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0xE5)

    fun validate(chord: HotkeyChord): Verdict {
        if (chord.keyCode !in 0x01..0xFE) return Verdict.Rejected(Rejection.KEY_OUT_OF_RANGE)
        if (chord.win) return Verdict.Rejected(Rejection.WIN_KEY_RESERVED)
        if (chord.keyCode in MODIFIER_KEYS) return Verdict.Rejected(Rejection.KEY_IS_MODIFIER)
        if (chord.keyCode in IME_KEYS) return Verdict.Rejected(Rejection.KEY_IS_IME)
        if (chord.keyCode == VK_F12) return Verdict.Rejected(Rejection.RESERVED_KEY)
        val count = listOf(chord.ctrl, chord.alt, chord.shift).count { it }
        if (count < 2) return Verdict.Rejected(Rejection.TOO_FEW_MODIFIERS)
        return Verdict.Ok
    }

    /** RegisterHotKey 의 fsModifiers. 길게 눌러도 한 번만 오게 MOD_NOREPEAT 를 늘 싣는다(D§6). */
    fun modifiers(chord: HotkeyChord): Int {
        var m = Win32.MOD_NOREPEAT
        if (chord.ctrl) m = m or Win32.MOD_CONTROL
        if (chord.alt) m = m or Win32.MOD_ALT
        if (chord.shift) m = m or Win32.MOD_SHIFT
        if (chord.win) m = m or Win32.MOD_WIN
        return m
    }
}
