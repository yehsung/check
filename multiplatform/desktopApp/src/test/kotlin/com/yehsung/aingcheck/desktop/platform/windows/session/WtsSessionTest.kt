// 원본: Sources/check/CheckWorkNudge.swift:79-87 @ a63fea2 (잠금 아님 + 온콘솔, 판독 실패면 fail-open) — 시험은 새 코드.
// 가짜만: 가짜 JDK 길(upstream) · 가짜 판독. 메시지 스레드 없음(맥에서도 돈다).
package com.yehsung.aingcheck.desktop.platform.windows.session

import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WtsSessionTest {
    private class FakeUpstream : SessionEvents {
        val listeners = mutableListOf<(SessionEvent) -> Unit>()
        override fun addListener(listener: (SessionEvent) -> Unit): Registration {
            listeners += listener
            return Registration { listeners -= listener }
        }
        fun emit(e: SessionEvent) = listeners.toList().forEach { it(e) }
    }

    @Test
    fun `wParam 표 — 잠금·콘솔·원격 여섯만 사건, 로그온·로그오프·원격 제어·생성·종료는 null`() {
        val table = (0x0..0xC).associateWith { WtsSessionCodes.decode(it.toLong()) }
        assertEquals(
            mapOf(
                0x0 to null, 0x1 to SessionEvent.CONSOLE_CONNECT, 0x2 to SessionEvent.CONSOLE_DISCONNECT,
                0x3 to SessionEvent.REMOTE_CONNECT, 0x4 to SessionEvent.REMOTE_DISCONNECT, 0x5 to null, 0x6 to null,
                0x7 to SessionEvent.LOCK, 0x8 to SessionEvent.UNLOCK, 0x9 to null, 0xA to null, 0xB to null, 0xC to null,
            ),
            table,
        )
        assertEquals(0x02B1, WtsSessionCodes.WM_WTSSESSION_CHANGE)
    }

    @Test
    fun `두 길이 같은 잠금을 내도 리스너는 한 번 — 전이만 통과, LOGOFF 는 늘`() {
        val up = FakeUpstream()
        val m = WtsSessionMonitor(thread = null, upstream = up).start()
        val got = mutableListOf<SessionEvent>()
        m.addListener { got += it }
        m.offer(SessionEvent.LOCK) // WTS 길
        up.emit(SessionEvent.LOCK) // JDK 길(같은 통지)
        up.emit(SessionEvent.UNLOCK)
        m.offer(SessionEvent.UNLOCK)
        m.offer(SessionEvent.REMOTE_CONNECT)
        up.emit(SessionEvent.REMOTE_CONNECT)
        up.emit(SessionEvent.LOGOFF)
        up.emit(SessionEvent.LOGOFF)
        assertEquals(
            listOf(SessionEvent.LOCK, SessionEvent.UNLOCK, SessionEvent.REMOTE_CONNECT, SessionEvent.LOGOFF, SessionEvent.LOGOFF),
            got,
        )
        m.close()
        up.emit(SessionEvent.LOCK)
        assertEquals(5, got.size, "close 뒤에도 JDK 길이 붙어 있다")
        assertTrue(up.listeners.isEmpty())
    }

    @Test
    fun `consoleSessionUsable — 판독이 이긴다, 실패면 사건 상태, 그것도 없으면 true`() {
        var info: SessionInfo? = SessionInfo(1, WtsSessionCodes.WTS_ACTIVE, WtsSessionCodes.WTS_SESSIONSTATE_UNLOCK)
        val m = WtsSessionMonitor(thread = null, upstream = null, query = { info })
        assertTrue(m.consoleSessionUsable())
        info = SessionInfo(1, WtsSessionCodes.WTS_ACTIVE, WtsSessionCodes.WTS_SESSIONSTATE_LOCK)
        assertFalse(m.consoleSessionUsable(), "잠긴 세션을 쓸 수 있다고 했다")
        info = SessionInfo(1, 4 /* WTSDisconnected */, WtsSessionCodes.WTS_SESSIONSTATE_UNLOCK)
        assertFalse(m.consoleSessionUsable(), "연결 끊긴 세션(사용자 전환·RDP 끊김)을 쓸 수 있다고 했다")
        info = SessionInfo(1, WtsSessionCodes.WTS_ACTIVE, -1 /* UNKNOWN */)
        assertTrue(m.consoleSessionUsable(), "모르는 잠금 표시에 막았다(fail-open)")

        info = null
        assertTrue(m.consoleSessionUsable(), "판독도 사건도 없을 때 막았다")
        m.offer(SessionEvent.LOCK)
        assertFalse(m.consoleSessionUsable())
        m.offer(SessionEvent.UNLOCK)
        m.offer(SessionEvent.CONSOLE_DISCONNECT)
        assertFalse(m.consoleSessionUsable())
        m.offer(SessionEvent.REMOTE_CONNECT)
        assertTrue(m.consoleSessionUsable(), "원격으로 붙은 활성 세션은 쓸 수 있다")
        val throwing = WtsSessionMonitor(thread = null, upstream = null, query = { error("WTS 판독 실패") })
        assertTrue(throwing.consoleSessionUsable())
    }

    @Test
    fun `리스너 하나가 던져도 다른 리스너는 받는다`() {
        val m = WtsSessionMonitor(thread = null, upstream = null)
        val got = mutableListOf<SessionEvent>()
        m.addListener { error("망가진 구독자") }
        val reg = m.addListener { got += it }
        m.offer(SessionEvent.LOCK)
        reg.close()
        m.offer(SessionEvent.UNLOCK)
        assertEquals(listOf(SessionEvent.LOCK), got)
        assertNull(WtsSessionCodes.decode(0x6))
    }
}
