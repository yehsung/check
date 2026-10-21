// 원본: Sources/check/CheckWorkNudge.swift:63-65 @ a63fea2 (lastTickAt — 루프가 사는 동안의 벽시계 간격으로 잠자기 공백을 잰다)
//       · 설계 D§2-3(JDK 가 이미 처리: SystemSleepListener·UserSessionListener·로그오프 때 SIGTERM → shutdown hook)
//       · D§5-2(2차 신호 필수: 1초 티커에서 벽시계 차이가 기대보다 30초 넘게 크면 잠잔 것으로 본다 — Modern Standby 에서
//         PBT_APMSUSPEND 를 못 받았다는 보고, 실제 PC 확인은 E06)
//
// - `Desktop.getDesktop()` 을 처음 부를 때 세션 통지가 등록된다(awt_Desktop.cpp:65-70) — 앱 시작 때 [install] 이 한 번 부른다.
// - `Desktop.disableSuddenTermination()` 은 부르지 않는다: WM_QUERYENDSESSION 에 FALSE 를 돌려 Windows 종료를 막는다.
// - 시험은 java.awt.headless=true 라 JDK 통지는 붙지 않는다(isDesktopSupported=false) — 공백 감지는 순수 함수로 잰다.
package com.yehsung.aingcheck.desktop.platform.windows.power

import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import java.awt.Desktop
import java.awt.desktop.SystemSleepEvent
import java.awt.desktop.SystemSleepListener
import java.awt.desktop.UserSessionEvent
import java.awt.desktop.UserSessionListener
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

/**
 * 벽시계 공백 감지(순수). 티커가 [tick] 을 부를 때마다 직전 시각과 비교해, 간격이 [expectedInterval] + [threshold] 보다 크면
 * 그 구간(직전 시각 ~ 지금)을 '잔 것'으로 돌려준다. 시계가 뒤로 가면(사용자가 시간을 바꿈) 공백으로 치지 않고 기준만 옮긴다.
 */
class WallClockGapDetector(
    private val expectedInterval: Duration = 1.seconds,
    private val threshold: Duration = 30.seconds,
) {
    data class Gap(val from: Instant, val to: Instant) {
        val length: Duration get() = to - from
    }

    private var last: Instant? = null

    fun tick(now: Instant): Gap? {
        val prev = last
        last = now
        if (prev == null || now <= prev) return null
        return if (now - prev > expectedInterval + threshold) Gap(prev, now) else null
    }

    /** 루프가 꺼져 있던 구간은 공백의 증거가 아니다(맥 start() 가 lastTickAt 을 nil 로) — 루프를 다시 켤 때 부른다. */
    fun reset() {
        last = null
    }
}

/**
 * JDK java.awt.desktop 통지 → K3 [PowerEvents]·[SessionEvents]([sessionEvents]). 두 인터페이스의 addListener 가 JVM 에서 같은 서명이라
 * 세션 쪽은 [sessionEvents] 로 따로 낸다. 데스크톱 통지를 못 붙이면(headless 등) 리스너는 조용히 남는다.
 */
class DesktopPowerEvents : PowerEvents {
    private val power = CopyOnWriteArrayList<(PowerEvent) -> Unit>()
    private val session = CopyOnWriteArrayList<(SessionEvent) -> Unit>()

    @Volatile var installed: Boolean = false
        private set

    /** 앱 시작 때 한 번. 붙였으면 true. 로그오프·종료는 shutdown hook 이 [onShutdown] 으로 LOGOFF 를 알린다. */
    fun install(): Boolean {
        if (installed) return true
        if (!Desktop.isDesktopSupported()) return false
        val desktop = runCatching { Desktop.getDesktop() }.getOrNull() ?: return false
        var any = false
        if (desktop.isSupported(Desktop.Action.APP_EVENT_SYSTEM_SLEEP)) {
            desktop.addAppEventListener(object : SystemSleepListener {
                override fun systemAboutToSleep(e: SystemSleepEvent) = emitPower(PowerEvent.SLEEP)
                override fun systemAwoke(e: SystemSleepEvent) = emitPower(PowerEvent.WAKE)
            })
            any = true
        }
        if (desktop.isSupported(Desktop.Action.APP_EVENT_USER_SESSION)) {
            desktop.addAppEventListener(object : UserSessionListener {
                override fun userSessionDeactivated(e: UserSessionEvent) = emitSession(mapReason(e.reason, active = false))
                override fun userSessionActivated(e: UserSessionEvent) = emitSession(mapReason(e.reason, active = true))
            })
            any = true
        }
        installed = any
        return any
    }

    /** shutdown hook 에서 부른다(WM_QUERYENDSESSION → SIGTERM → hook, D§2-3). */
    fun onShutdown() = emitSession(SessionEvent.LOGOFF)

    fun emitPower(e: PowerEvent) = power.forEach { it(e) }

    fun emitSession(e: SessionEvent) = session.forEach { it(e) }

    override fun addListener(listener: (PowerEvent) -> Unit): Registration {
        power += listener
        return Registration { power -= listener }
    }

    // PowerEvents·SessionEvents 가 같은 이름을 쓰므로 세션 쪽은 이 이름으로 받는다(K3 서명은 그대로).
    private val sessionFacade = object : SessionEvents {
        override fun addListener(listener: (SessionEvent) -> Unit): Registration {
            session += listener
            return Registration { session -= listener }
        }
    }

    val sessionEvents: SessionEvents get() = sessionFacade

    companion object {
        /** UserSessionEvent.Reason → K3 SessionEvent. LOCK·CONSOLE·REMOTE 를 활성/비활성으로 가른다. */
        fun mapReason(reason: UserSessionEvent.Reason, active: Boolean): SessionEvent = when (reason) {
            UserSessionEvent.Reason.LOCK -> if (active) SessionEvent.UNLOCK else SessionEvent.LOCK
            UserSessionEvent.Reason.CONSOLE -> if (active) SessionEvent.CONSOLE_CONNECT else SessionEvent.CONSOLE_DISCONNECT
            UserSessionEvent.Reason.REMOTE -> if (active) SessionEvent.REMOTE_CONNECT else SessionEvent.REMOTE_DISCONNECT
            UserSessionEvent.Reason.UNSPECIFIED -> if (active) SessionEvent.CONSOLE_CONNECT else SessionEvent.CONSOLE_DISCONNECT
        }
    }
}
