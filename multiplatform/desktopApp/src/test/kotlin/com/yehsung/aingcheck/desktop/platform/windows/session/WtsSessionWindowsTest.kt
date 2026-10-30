// 원본: 없음(새 시험) — 설계 D§2-2(숨은 창 메시지 스레드) · G §2-3(러너 2종) · 기억 comparison-baseline-must-differ
// 실제 잠금은 러너에서 못 한다 → 숨은 창에 WM_WTSSESSION_CHANGE 를 직접 보내 등록·해석·거르기 길 전체를 잰다.
// WTSINFOEXW 칸 자리(@8·@12)는 다른 API(ProcessIdToSessionId · WTSConnectState)와 대조한다.
package com.yehsung.aingcheck.desktop.platform.windows.session

import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@EnabledOnOs(OS.WINDOWS)
class WtsSessionWindowsTest {
    private val none = object : SessionEvents {
        override fun addListener(listener: (SessionEvent) -> Unit) = Registration { }
    }

    @Test
    fun sessionInfoOffsetsMatchOtherApis() {
        val own = assertNotNull(WtsSessionProbe.ownSessionId(), "ProcessIdToSessionId 실패")
        val info = assertNotNull(WtsSessionProbe.query(own), "WTSSessionInfoEx 판독 실패")
        assertEquals(own, info.sessionId, "SessionId@8 이 ProcessIdToSessionId 와 다르다 — 칸 자리가 틀렸다")
        assertEquals(WtsSessionProbe.connectState(own), info.state, "SessionState@12 가 WTSConnectState 와 다르다")
        assertTrue(info.flags in setOf(-1, 0, 1), "SessionFlags 모양: ${info.flags}")
    }

    @Test
    fun registeredMonitorDecodesPostedSessionChangesAndIgnoresOtherSessions() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Wts")).use { thread ->
            val own = assertNotNull(WtsSessionProbe.ownSessionId())
            val m = WtsSessionMonitor(thread, none, query = { WtsSessionProbe.query(own) }, ownSessionId = own).start()
            try {
                assertTrue(m.wtsRegistered, "WTSRegisterSessionNotification 실패: ${m.wtsRegisterError}")
                val got = CopyOnWriteArrayList<SessionEvent>()
                m.addListener { got += it }
                fun post(code: Int, session: Int) =
                    User32X.INSTANCE.PostMessageW(thread.hwnd, WtsSessionCodes.WM_WTSSESSION_CHANGE, WinDef.WPARAM(code.toLong()), WinDef.LPARAM(session.toLong()))
                post(WtsSessionCodes.WTS_SESSION_LOCK, own + 1000) // 남의 세션 — 버린다
                post(WtsSessionCodes.WTS_SESSION_LOCK, own)
                post(WtsSessionCodes.WTS_SESSION_LOCK, own) // 같은 잠금 두 번 — 한 번만
                post(WtsSessionCodes.WTS_SESSION_LOGOFF, own) // 종료 훅 몫 — 내지 않는다
                post(WtsSessionCodes.WTS_SESSION_UNLOCK, own)
                RunnerSupport.waitUntil(5_000, "LOCK·UNLOCK 이 리스너에 온다") { got.size >= 2 }
                Thread.sleep(200)
                assertEquals(listOf(SessionEvent.LOCK, SessionEvent.UNLOCK), got.toList())
                // 판독 길이 실제로 돈다(러너 세션은 활성이어야 창·단축키 시험이 돈다).
                assertTrue(m.consoleSessionUsable(), "러너 세션을 못 쓴다고 했다: ${WtsSessionProbe.query(own)}")
            } finally {
                m.close()
            }
        }
    }
}
