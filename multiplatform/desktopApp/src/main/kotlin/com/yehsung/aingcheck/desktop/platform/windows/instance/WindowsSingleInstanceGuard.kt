// 원본: 없음(새 코드) — 설계 D§2-5(이름 있는 뮤텍스 Local\AingCheck.Instance, 세션마다 따로) · C§3.4 · C§9-10
// **세션 시작 전 필수**(K3): 두 번 실행되면 토큰 갱신 주체가 둘이 되어 GoTrue 재사용 감지가 강제 로그아웃을 만든다.
// 판정은 커널 객체의 존재로 한다: CreateMutex 가 ERROR_ALREADY_EXISTS 면 다른 실행이 쥐고 있다. 소유(bInitialOwner)는 쓰지 않는다 —
// 쥔 프로세스가 죽으면 핸들이 닫혀 객체가 사라지므로 '버려진 뮤텍스' 처리가 필요 없다.
// 실패(핸들 null)는 '못 잡았다'로 닫는다 — 세션을 시작하지 않는 쪽이 갱신 주체 둘보다 낫다.
package com.yehsung.aingcheck.desktop.platform.windows.instance

import com.sun.jna.Native
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.WinNT
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32

class WindowsSingleInstanceGuard(
    /** 앱은 [DEFAULT_NAME]. 시험은 고유 이름을 써서 실제 실행과 부딪히지 않는다. */
    val mutexName: String = DEFAULT_NAME,
) : SingleInstanceGuard {
    private var handle: WinNT.HANDLE? = null

    /** 마지막 시도의 Win32 오류 코드(진단). 0 = 잡음, 183 = 다른 실행이 쥐고 있음. */
    @Volatile var lastError: Int = 0
        private set

    @Synchronized
    override fun tryAcquire(): Boolean {
        if (handle != null) return true
        val h = Kernel32.INSTANCE.CreateMutex(null, false, mutexName)
        val err = Native.getLastError()
        lastError = err
        if (h == null) return false
        if (err == Win32.ERROR_ALREADY_EXISTS) {
            Kernel32.INSTANCE.CloseHandle(h)
            return false
        }
        handle = h
        return true
    }

    @Synchronized
    override fun release() {
        handle?.let { Kernel32.INSTANCE.CloseHandle(it) }
        handle = null
    }

    companion object {
        /** `Local\` = 로그인 세션마다 따로(빠른 사용자 전환으로 다른 사람이 같은 PC 에서 각자 실행할 수 있다). */
        const val DEFAULT_NAME = "Local\\AingCheck.Instance"
    }
}
