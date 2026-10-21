// 원본: Sources/check/CheckApp.swift:222-241 @ a63fea2 (기본 켜짐, 사용자가 끈 것은 존중, 등록이 사라졌으면 되살림)
//       · 설계 D§5-5(MSI 길: HKCU\…\Run 에 "<exe>" --autostart, 작업 관리자에서 끈 표시(…\Explorer\StartupApproved\Run)가
//         있으면 **되살리지 않는다** — 그 값의 형식은 문서화되지 않았다 → 미확인 E11)
// MSIX 길은 매니페스트 StartupTask(Enabled=true)라 이 클래스를 쓰지 않는다(HKCU 쓰기가 앱별 사본으로 가상화된다, R7 W19).
package com.yehsung.aingcheck.desktop.platform.windows.login

import com.sun.jna.platform.win32.Advapi32Util
import com.sun.jna.platform.win32.WinReg
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem

object StartupApproved {
    /**
     * StartupApproved\Run 값(REG_BINARY 12바이트: 상태 4바이트 + FILETIME)의 뜻. **문서화되지 않은 형식**이라 알려진 꼴만 읽는다:
     * 첫 바이트가 짝수(0x02·0x06)면 켜짐, 홀수(0x03·0x07)면 사용자가 끔. 값이 없거나 모르는 꼴이면 null(= 사용자가 건드리지 않음).
     * 실측 대조는 VM E11.
     */
    fun disabledByUser(value: ByteArray?): Boolean? {
        if (value == null || value.isEmpty()) return null
        return when (value[0].toInt() and 0xFF) {
            0x02, 0x06 -> false
            0x03, 0x07 -> true
            else -> null
        }
    }
}

class RunKeyLoginItem(
    /** 실행 파일 경로(따옴표 없이). 명령은 `"<exe>" --autostart`. */
    private val executable: String,
    private val valueName: String = DEFAULT_VALUE_NAME,
    private val root: WinReg.HKEY = WinReg.HKEY_CURRENT_USER,
    private val runKey: String = RUN_KEY,
    private val approvedKey: String = APPROVED_KEY,
) : LoginItem {
    val command: String get() = "\"$executable\" $AUTOSTART_ARG"

    /** Run 값이 우리 명령이고, 사용자가 작업 관리자에서 끄지 않았다. */
    override fun isEnabled(): Boolean {
        val current = runCatching {
            if (Advapi32Util.registryValueExists(root, runKey, valueName)) Advapi32Util.registryGetStringValue(root, runKey, valueName) else null
        }.getOrNull() ?: return false
        if (current != command) return false
        return userDisabled() != true
    }

    fun userDisabled(): Boolean? = runCatching {
        if (!Advapi32Util.registryKeyExists(root, approvedKey) || !Advapi32Util.registryValueExists(root, approvedKey, valueName)) {
            null
        } else {
            StartupApproved.disabledByUser(Advapi32Util.registryGetBinaryValue(root, approvedKey, valueName))
        }
    }.getOrNull()

    /**
     * 켜기: 사용자가 작업 관리자에서 끈 표시가 있으면 **되살리지 않는다**(false). 끄기: Run 값을 지운다.
     * 실제로 바뀌었으면 true.
     */
    override fun setEnabled(enabled: Boolean): Boolean = runCatching {
        if (enabled) {
            if (userDisabled() == true) return@runCatching false
            val before = if (Advapi32Util.registryValueExists(root, runKey, valueName)) Advapi32Util.registryGetStringValue(root, runKey, valueName) else null
            if (before == command) return@runCatching false
            if (!Advapi32Util.registryKeyExists(root, runKey)) Advapi32Util.registryCreateKey(root, runKey)
            Advapi32Util.registrySetStringValue(root, runKey, valueName, command)
            true
        } else {
            if (!Advapi32Util.registryKeyExists(root, runKey) || !Advapi32Util.registryValueExists(root, runKey, valueName)) return@runCatching false
            Advapi32Util.registryDeleteValue(root, runKey, valueName)
            true
        }
    }.getOrDefault(false)

    companion object {
        const val DEFAULT_VALUE_NAME = "AingCheck"
        const val AUTOSTART_ARG = "--autostart"
        const val RUN_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
        const val APPROVED_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run"
    }
}
