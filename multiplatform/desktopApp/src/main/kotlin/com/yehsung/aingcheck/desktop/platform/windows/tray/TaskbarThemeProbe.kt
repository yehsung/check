// 원본: 없음(새 코드) — 설계 D§3-2(작업 표시줄 밝음·어두움: HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize
// SystemUsesLightTheme, WM_SETTINGCHANGE("ImmersiveColorSet") 를 받으면 다시 읽는다 — 그 배선은 껍데기 W3-c1)
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.sun.jna.platform.win32.Advapi32Util
import com.sun.jna.platform.win32.WinReg

object TaskbarThemeProbe {
    const val PERSONALIZE_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
    const val VALUE = "SystemUsesLightTheme"

    /** 값 없음·읽기 실패 = 어두움(Windows 11 기본 작업 표시줄). */
    fun fromRegistryValue(value: Int?): TaskbarTheme = if (value == 1) TaskbarTheme.LIGHT else TaskbarTheme.DARK

    fun current(): TaskbarTheme = fromRegistryValue(
        runCatching {
            if (Advapi32Util.registryValueExists(WinReg.HKEY_CURRENT_USER, PERSONALIZE_KEY, VALUE)) {
                Advapi32Util.registryGetIntValue(WinReg.HKEY_CURRENT_USER, PERSONALIZE_KEY, VALUE)
            } else {
                null
            }
        }.getOrNull(),
    )
}
