// 원본: 없음(새 코드) — 설계 D§2-5(HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid + 사용자 SID)
// - MachineGuid 는 64비트 보기(KEY_WOW64_64KEY)로 읽는다: 32비트 프로세스가 WOW6432Node 로 돌려져 다른 값을 읽는 일을 막는다.
// - SID 는 이 프로세스 토큰의 사용자(TokenUser)다 — 환경 변수 USERNAME 처럼 바꿀 수 있는 값을 쓰지 않는다.
//   MSIX(전체 신뢰 데스크톱 앱)도 같은 사용자 토큰으로 돈다.
package com.yehsung.aingcheck.desktop.platform.windows.identity

import com.sun.jna.platform.win32.Advapi32
import com.sun.jna.platform.win32.Advapi32Util
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.WinNT
import com.sun.jna.platform.win32.WinReg

class RegistryMachineIdentitySource : MachineIdentitySource {
    override fun machineGuid(): String? = runCatching {
        Advapi32Util.registryGetStringValue(WinReg.HKEY_LOCAL_MACHINE, CRYPTOGRAPHY_KEY, "MachineGuid", WinNT.KEY_WOW64_64KEY)
    }.getOrNull()

    override fun userSid(): String? {
        val token = WinNT.HANDLEByReference()
        if (!Advapi32.INSTANCE.OpenProcessToken(Kernel32.INSTANCE.GetCurrentProcess(), WinNT.TOKEN_QUERY, token)) return null
        return try {
            Advapi32Util.getTokenAccount(token.value).sidString
        } catch (_: Exception) {
            null
        } finally {
            Kernel32.INSTANCE.CloseHandle(token.value)
        }
    }

    companion object {
        const val CRYPTOGRAPHY_KEY = "SOFTWARE\\Microsoft\\Cryptography"
    }
}
