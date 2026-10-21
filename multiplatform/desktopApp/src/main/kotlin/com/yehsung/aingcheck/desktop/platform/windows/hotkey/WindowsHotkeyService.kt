// 원본: 없음(새 코드) — 설계 D§2-2(RegisterHotKey 는 창을 만든 스레드에서만) · D§6(겹치면 실패 코드로 안다)
// W0-e 실측: 같은 조합 두 번째 등록은 1409(ERROR_HOTKEY_ALREADY_REGISTERED) — 맥 Carbon 과 달리 겹침을 알 수 있다.
package com.yehsung.aingcheck.desktop.platform.windows.hotkey

import com.sun.jna.Native
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger

class WindowsHotkeyService(
    private val thread: Win32MessageThread,
    private val events: Executor = Executor { it.run() },
) : HotkeyService, AutoCloseable {
    private val callbacks = ConcurrentHashMap<Int, () -> Unit>()
    // 0xC000 이상은 GlobalAddAtom 자리라 앱 id 는 0x0000..0xBFFF 에서 고른다(RegisterHotKey 문서).
    private val nextId = AtomicInteger(0xA100)
    private val handler = thread.addHandler(Win32.WM_HOTKEY) { _, _, wParam, _ ->
        val cb = callbacks[wParam.toInt()]
        if (cb != null) events.execute(cb)
        WinDef.LRESULT(0)
    }

    /**
     * 잘못된 조합([HotkeyPolicy.validate] 가 거절)은 [IllegalArgumentException] — 설정 화면이 먼저 거른다.
     * 다른 앱·시스템과 겹치면 [HotkeyRegistrationResult.Conflict] 와 Win32 오류 코드(보통 1409).
     */
    override fun register(chord: HotkeyChord, onPressed: () -> Unit): HotkeyRegistrationResult {
        val verdict = HotkeyPolicy.validate(chord)
        require(verdict == HotkeyPolicy.Verdict.Ok) { "단축키 조합이 규칙에 맞지 않는다: $verdict" }
        val id = nextId.getAndIncrement()
        return thread.call { hwnd ->
            if (User32.INSTANCE.RegisterHotKey(hwnd, id, HotkeyPolicy.modifiers(chord), chord.keyCode)) {
                callbacks[id] = onPressed
                HotkeyRegistrationResult.Registered(
                    Registration {
                        callbacks.remove(id)
                        if (thread.isAlive) thread.call { h -> User32.INSTANCE.UnregisterHotKey(h.pointer, id) }
                    },
                )
            } else {
                HotkeyRegistrationResult.Conflict(Native.getLastError())
            }
        }
    }

    override fun close() {
        handler.close()
        val ids = callbacks.keys.toList()
        callbacks.clear()
        if (thread.isAlive) thread.call { h -> ids.forEach { User32.INSTANCE.UnregisterHotKey(h.pointer, it) } }
    }
}
