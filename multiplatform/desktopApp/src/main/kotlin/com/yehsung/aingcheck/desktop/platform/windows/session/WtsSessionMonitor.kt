// 원본: Sources/check/CheckWorkNudge.swift:79-87 @ a63fea2 (consoleSessionUsable — 잠금 아님 + 온콘솔, 판독 실패면 막지 않음 fail-open)
//       · Sources/check/CheckOverlayWindow.swift:2149(깜빡 주기마다 직접 물어 낡은 잠금 사유를 걷는다)
//       · 설계 D§2-2(숨은 창 메시지 스레드) · D§2-3(JDK UserSessionListener)
//
// - WTSRegisterSessionNotification(NOTIFY_FOR_THIS_SESSION)을 [Win32MessageThread] 의 숨은 창에 걸고 WM_WTSSESSION_CHANGE 를 받는다.
//   lParam(바뀐 세션 id)이 우리 세션이 아니면 버린다.
// - JDK 도 같은 통지를 자기 창에 걸어 UserSessionListener 로 낸다(DesktopPowerEvents.sessionEvents). 두 길을 **합치고 상태 전이로만 거른다**
//   ([SessionTransitionFilter]) — 같은 잠금이 두 번 오지 않고, 우리 등록이 실패해도 JDK 길이 남는다. LOGOFF 는 종료 훅(onShutdown) 몫이라
//   WTS_SESSION_LOGOFF 는 내지 않는다(두 번 나지 않게).
// - [consoleSessionUsable] 은 맥처럼 **그때 묻는다**: WTSQuerySessionInformation(WTSSessionInfoEx) 의 SessionState == WTSActive 이고
//   SessionFlags != WTS_SESSIONSTATE_LOCK. RDP 로 들어온 활성 세션은 쓸 수 있다(그리기가 된다), 연결 끊김·사용자 전환으로 밀려난 세션은 못 쓴다.
//   판독 실패면 사건으로 쌓은 상태, 그것도 없으면 true(fail-open).
// - 리스너는 [events](앱 = EDT)에서 부른다 — JDK 길과 같은 줄기.
package com.yehsung.aingcheck.desktop.platform.windows.session

import com.sun.jna.Pointer
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.Wtsapi32
import com.sun.jna.ptr.IntByReference
import com.sun.jna.ptr.PointerByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executor

/** WM_WTSSESSION_CHANGE wParam → K3 사건(순수). 모르는 값·LOGON·LOGOFF·REMOTE_CONTROL·CREATE·TERMINATE 는 null. */
object WtsSessionCodes {
    const val WM_WTSSESSION_CHANGE = 0x02B1
    const val WTS_CONSOLE_CONNECT = 0x1
    const val WTS_CONSOLE_DISCONNECT = 0x2
    const val WTS_REMOTE_CONNECT = 0x3
    const val WTS_REMOTE_DISCONNECT = 0x4
    const val WTS_SESSION_LOGON = 0x5
    const val WTS_SESSION_LOGOFF = 0x6
    const val WTS_SESSION_LOCK = 0x7
    const val WTS_SESSION_UNLOCK = 0x8

    /** WTS_CONNECTSTATE_CLASS.WTSActive. */
    const val WTS_ACTIVE = 0
    /** WTSINFOEX_LEVEL1.SessionFlags(Windows 8+ 뜻 — Windows 7 은 뒤집혀 있다, 우리 대상 밖). */
    const val WTS_SESSIONSTATE_LOCK = 0
    const val WTS_SESSIONSTATE_UNLOCK = 1
    /** WTS_INFO_CLASS.WTSSessionInfoEx. */
    const val WTS_SESSION_INFO_EX = 25

    fun decode(wParam: Long): SessionEvent? = when (wParam.toInt()) {
        WTS_CONSOLE_CONNECT -> SessionEvent.CONSOLE_CONNECT
        WTS_CONSOLE_DISCONNECT -> SessionEvent.CONSOLE_DISCONNECT
        WTS_REMOTE_CONNECT -> SessionEvent.REMOTE_CONNECT
        WTS_REMOTE_DISCONNECT -> SessionEvent.REMOTE_DISCONNECT
        WTS_SESSION_LOCK -> SessionEvent.LOCK
        WTS_SESSION_UNLOCK -> SessionEvent.UNLOCK
        else -> null
    }

    /** 세션 판독(WTSINFOEXW 앞부분) → 쓸 수 있나. */
    fun usable(info: SessionInfo): Boolean = info.state == WTS_ACTIVE && info.flags != WTS_SESSIONSTATE_LOCK
}

/** WTSINFOEXW Level1 앞 세 칸. */
data class SessionInfo(val sessionId: Int, val state: Int, val flags: Int)

/**
 * 두 길(WTS·JDK)에서 온 사건을 **상태가 바뀔 때만** 통과시킨다(순수 — 자물쇠 안에서 판정만). 첫 사건은 늘 통과(모르는 상태에서 시작).
 * LOGOFF 는 늘 통과. 사건으로 쌓은 [usable] 은 판독 실패 때의 대체값.
 */
class SessionTransitionFilter {
    private var locked: Boolean? = null
    private var console: Boolean? = null
    private var remote: Boolean? = null

    @Synchronized
    fun admit(e: SessionEvent): Boolean = when (e) {
        SessionEvent.LOCK -> change(locked, true) { locked = it }
        SessionEvent.UNLOCK -> change(locked, false) { locked = it }
        SessionEvent.CONSOLE_CONNECT -> change(console, true) { console = it }
        SessionEvent.CONSOLE_DISCONNECT -> change(console, false) { console = it }
        SessionEvent.REMOTE_CONNECT -> change(remote, true) { remote = it }
        SessionEvent.REMOTE_DISCONNECT -> change(remote, false) { remote = it }
        SessionEvent.LOGOFF -> true
    }

    private inline fun change(current: Boolean?, next: Boolean, set: (Boolean) -> Unit): Boolean {
        if (current == next) return false
        set(next)
        return true
    }

    /** 잠기지 않았고, 콘솔이나 원격 중 하나에 붙어 있다(모르면 붙은 것으로 — fail-open). */
    val usable: Boolean
        @Synchronized get() = locked != true && (console != false || remote == true)
}

/**
 * WTS 세션 관측 + JDK 길 합치기. [start] 로 등록, [close] 로 해제. Windows 밖(맥 개발·시험)에서는 [thread] 없이 만들어 [upstream] 만 거른다.
 */
class WtsSessionMonitor(
    private val thread: Win32MessageThread?,
    private val upstream: SessionEvents?,
    private val events: Executor = Executor { it.run() },
    /** 지금 세션 판독. 앱 = [WtsSessionProbe.query], 시험 = 가짜. null 이면 판독 실패. */
    private val query: () -> SessionInfo? = { null },
    /** 우리 세션 id. 앱 = ProcessIdToSessionId. null 이면 lParam 을 거르지 않는다. */
    private val ownSessionId: Int? = null,
) : SessionEvents, AutoCloseable {
    private val listeners = CopyOnWriteArrayList<(SessionEvent) -> Unit>()
    private val filter = SessionTransitionFilter()
    private var handler: Registration? = null
    private var upstreamReg: Registration? = null

    /** WTSRegisterSessionNotification 결과(진단·시험). 등록 전·Windows 밖은 false. */
    @Volatile var wtsRegistered: Boolean = false
        private set

    /** 등록 실패 때의 GetLastError. */
    @Volatile var wtsRegisterError: Int = 0
        private set

    fun start(): WtsSessionMonitor {
        upstreamReg = upstream?.addListener { e -> offer(e) }
        val t = thread ?: return this
        handler = t.addHandler(WtsSessionCodes.WM_WTSSESSION_CHANGE) { _, _, wParam, lParam ->
            val sid = lParam.toLong().toInt()
            if (ownSessionId == null || sid == ownSessionId) {
                WtsSessionCodes.decode(wParam.toLong())?.let { e -> events.execute { offer(e) } }
            }
            WinDef.LRESULT(0)
        }
        runCatching {
            t.call { hwnd ->
                val ok = Wtsapi32.INSTANCE.WTSRegisterSessionNotification(hwnd, Wtsapi32.NOTIFY_FOR_THIS_SESSION)
                wtsRegistered = ok
                if (!ok) wtsRegisterError = Kernel32.INSTANCE.GetLastError()
            }
        }
        return this
    }

    /** 두 길이 같이 부른다. 상태가 바뀐 것만 리스너로. */
    fun offer(e: SessionEvent) {
        if (!filter.admit(e)) return
        listeners.forEach { runCatching { it(e) } }
    }

    /** OverlayWiringDeps.consoleSessionUsable. 판독 → 사건 상태 → true 순. */
    fun consoleSessionUsable(): Boolean {
        val info = runCatching(query).getOrNull()
        return if (info != null) WtsSessionCodes.usable(info) else filter.usable
    }

    override fun addListener(listener: (SessionEvent) -> Unit): Registration {
        listeners += listener
        return Registration { listeners -= listener }
    }

    override fun close() {
        upstreamReg?.close()
        upstreamReg = null
        handler?.close()
        handler = null
        val t = thread
        if (t != null && wtsRegistered && t.isAlive) {
            runCatching { t.call { hwnd -> Wtsapi32.INSTANCE.WTSUnRegisterSessionNotification(hwnd) } }
        }
        wtsRegistered = false
    }

    companion object {
        /** 앱 조립: 메시지 스레드 + JDK 길(DesktopPowerEvents.sessionEvents) + 실제 판독. */
        fun live(thread: Win32MessageThread, upstream: SessionEvents, events: Executor): WtsSessionMonitor {
            val own = WtsSessionProbe.ownSessionId()
            return WtsSessionMonitor(thread, upstream, events, query = { own?.let { WtsSessionProbe.query(it) } }, ownSessionId = own).start()
        }
    }
}

/** 실제 판독(Windows 에서만 부른다). */
object WtsSessionProbe {
    fun ownSessionId(): Int? {
        val out = IntByReference()
        return if (Kernel32.INSTANCE.ProcessIdToSessionId(Kernel32.INSTANCE.GetCurrentProcessId(), out)) out.value else null
    }

    /**
     * WTSINFOEXW: DWORD Level(0) + 채움 4 + 공용체(LARGE_INTEGER 가 있어 8 맞춤) → Level1 의 SessionId@8 · SessionState@12 · SessionFlags@16.
     * Level != 1 이면 null. 러너 시험이 SessionId@8 을 ProcessIdToSessionId 와, SessionState@12 를 WTSConnectState 와 대조한다.
     */
    fun query(sessionId: Int): SessionInfo? {
        val buf = PointerByReference()
        val bytes = IntByReference()
        if (!Wtsapi32.INSTANCE.WTSQuerySessionInformation(Wtsapi32.WTS_CURRENT_SERVER_HANDLE, sessionId, WtsSessionCodes.WTS_SESSION_INFO_EX, buf, bytes)) {
            return null
        }
        val p: Pointer = buf.value ?: return null
        try {
            if (bytes.value < 20 || p.getInt(0) != 1) return null
            return SessionInfo(sessionId = p.getInt(8), state = p.getInt(12), flags = p.getInt(16))
        } finally {
            Wtsapi32.INSTANCE.WTSFreeMemory(p)
        }
    }

    /** WTSConnectState(=8) 로 따로 묻는다 — [query] 의 SessionState@12 대조용(다른 정보 갈래). */
    fun connectState(sessionId: Int): Int? {
        val buf = PointerByReference()
        val bytes = IntByReference()
        if (!Wtsapi32.INSTANCE.WTSQuerySessionInformation(Wtsapi32.WTS_CURRENT_SERVER_HANDLE, sessionId, Wtsapi32.WTS_INFO_CLASS.WTSConnectState, buf, bytes)) {
            return null
        }
        val p = buf.value ?: return null
        try {
            return if (bytes.value >= 4) p.getInt(0) else null
        } finally {
            Wtsapi32.INSTANCE.WTSFreeMemory(p)
        }
    }
}
