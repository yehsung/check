// 원본: 없음(새 코드) — 설계 D§2-5(두 번째 실행은 첫 실행의 숨은 창을 찾아 "플라이아웃 열기"를 보내고 끝난다 — 트레이 아이콘이
// 숨겨진 사람의 탈출구, §3-4) · 이 갈래는 신호 길만 놓는다. 신호를 받아 무엇을 열지는 껍데기(W3-c1 shell/instance)가 정한다.
package com.yehsung.aingcheck.desktop.platform.windows.instance

import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import java.util.concurrent.Executor

object InstanceSignal {
    /** 방송이 아니라 한 창으로 보내는 등록 메시지. 판을 붙여 둔다(뜻이 바뀌면 이름을 바꾼다). */
    const val ACTIVATE_MESSAGE_NAME = "AingCheck.Activate.v1"

    /**
     * 첫 실행의 숨은 창([className])을 찾아 "열어 달라"를 보낸다. 찾아서 보냈으면 true.
     * 받는 쪽이 앞으로 나올 수 있게 AllowSetForegroundWindow 로 전경 권한을 넘긴다(우리가 마지막 입력을 받은 프로세스다).
     */
    fun activateExisting(className: String = Win32MessageThread.DEFAULT_CLASS_NAME): Boolean {
        val hwnd = User32.INSTANCE.FindWindow(className, null) ?: return false
        val pid = IntByReference(0)
        User32.INSTANCE.GetWindowThreadProcessId(hwnd, pid)
        if (pid.value != 0) runCatching { User32X.INSTANCE.AllowSetForegroundWindow(pid.value) }
        val msg = User32.INSTANCE.RegisterWindowMessage(ACTIVATE_MESSAGE_NAME)
        return User32X.INSTANCE.PostMessageW(hwnd, msg, WinDef.WPARAM(0), WinDef.LPARAM(0))
    }

    /** 첫 실행 쪽: 신호를 받으면 [onActivate] 를 [events] 에서 부른다. */
    fun listen(thread: Win32MessageThread, events: Executor = Executor { it.run() }, onActivate: () -> Unit): Registration {
        val msg = thread.call { hwnd ->
            val m = User32.INSTANCE.RegisterWindowMessage(ACTIVATE_MESSAGE_NAME)
            runCatching { User32X.INSTANCE.ChangeWindowMessageFilterEx(hwnd, m, Win32.MSGFLT_ALLOW, null) }
            m
        }
        return thread.addHandler(msg) { _, _, _, _ ->
            events.execute(onActivate)
            WinDef.LRESULT(0)
        }
    }
}
