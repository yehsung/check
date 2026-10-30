// 원본: Sources/check/CheckApp.swift:176-201 @ a90d8623 (★3 말풍선/알림 클릭 → 보낸이를 알면 그 대화, 모르면 상대 고르는 목록 —
//       nil 상대로 대화 화면을 열지 않는다) · W-3 #7(대결 깃발 꺼짐 → Windows 에 신청 안내 없음) · pins.md E 조정 ⑨(풍선 = BalloonNotifier)
//
// 사건 하나 → 깃발 문 → 중재(ShellNotifyArbiter) → 표면 하나. 토스트는 트레이 풍선, 클릭은 플라이아웃 한 문(★4 open)으로 간다.
// 라우트는 FlyoutRoutes 만 부른다(판정 공유 — c0·W5-b 와 같은 함수).
package com.yehsung.aingcheck.desktop.shell.notify

import com.yehsung.aingcheck.desktop.shellapi.BalloonNotifier
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoutes
import com.yehsung.aingcheck.desktop.shellapi.NotifyArbiter
import com.yehsung.aingcheck.desktop.shellapi.NotifyContext
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import java.util.concurrent.ConcurrentHashMap

/** 알릴 사건 하나. 메시지는 [senderId] 를 싣는다(모르면 null — ★3). */
data class ShellNotice(val kind: NotifyKind, val title: String, val body: String, val senderId: String? = null)

class ShellNotifier(
    private val flags: DesktopAppConfig,
    private val balloon: BalloonNotifier,
    private val nav: FlyoutNavigator,
    /** 말풍선(W5-b 오버레이). 띄웠으면 true. 조립 전엔 띄우지 않는다. */
    private val bubble: (ShellNotice) -> Boolean = { false },
    private val arbiter: NotifyArbiter = ShellNotifyArbiter,
) {
    /** 풍선 클릭은 종류만 알려 준다 — 종류마다 마지막으로 띄운 풍선의 목적지를 기억한다(풍선은 한 번에 하나씩 뜬다). */
    private val balloonTargets = ConcurrentHashMap<NotifyKind, FlyoutRoute>()

    init {
        balloon.setOnBalloonClick { kind -> onBalloonClick(kind) }
    }

    /** 이 빌드가 이 종류를 알리나. 대결은 duels, 찌르기는 poke 깃발(꺼진 기능은 토스트·라우트를 숨긴다 — shell.md §4-7). */
    fun enabled(kind: NotifyKind): Boolean = when (kind) {
        NotifyKind.DUEL_INVITE -> flags.duels
        NotifyKind.POKE -> flags.poke
        NotifyKind.MESSAGE, NotifyKind.UPDATE -> true
    }

    /** 사건을 한 표면에 올린다. 깃발로 꺼진 종류면 null(아무 데도 — 점 사유도 TrayDotReasons.of 가 같은 깃발로 끈다). */
    fun deliver(notice: ShellNotice, ctx: NotifyContext): NotifySurface? {
        if (!enabled(notice.kind)) return null
        val effective = ctx.copy(toastEnabled = ctx.toastEnabled && toastAllowed(notice.kind))
        val chosen = arbiter.surface(notice.kind, effective)
        // 오버레이 문이 못 받으면(꺼짐·잠김·큐 가득) 오버레이가 없는 것처럼 다시 고른다(토스트 → 점) — 사건 하나가 아무 데도 안 뜨는 일 0(D §10-2 한 표면).
        val surface = if (chosen == NotifySurface.BUBBLE && !bubble(notice)) {
            arbiter.surface(notice.kind, effective.copy(overlayVisible = false))
        } else {
            chosen
        }
        when (surface) {
            NotifySurface.BUBBLE -> Unit
            NotifySurface.TOAST -> {
                balloonTargets[notice.kind] = routeFor(notice)
                balloon.showBalloon(notice.title, notice.body, notice.kind, respectQuietTime = true)
            }
            NotifySurface.DOT_ONLY -> Unit
        }
        return surface
    }

    /** 메시지 토스트는 chatToast 깃발이 켜진 빌드에서만(DesktopAppConfig.chatToast, 기본 꺼짐). */
    private fun toastAllowed(kind: NotifyKind): Boolean = kind != NotifyKind.MESSAGE || flags.chatToast

    /** ★3 목적지. 메시지는 FlyoutRoutes.forMessageArrival(보낸이 null 이면 대화가 아니라 목록). 신청·업데이트는 홈(배너·게임 창은 다음 웨이브). */
    fun routeFor(notice: ShellNotice): FlyoutRoute = when (notice.kind) {
        NotifyKind.MESSAGE -> FlyoutRoutes.forMessageArrival(notice.senderId, flags.poke, Entry.NOTIFICATION)
        NotifyKind.POKE -> FlyoutRoutes.forMessageArrival(null, flags.poke, Entry.NOTIFICATION)
        NotifyKind.DUEL_INVITE, NotifyKind.UPDATE -> FlyoutRoute.Home
    }

    private fun onBalloonClick(kind: NotifyKind) {
        nav.open(balloonTargets.remove(kind) ?: FlyoutRoute.Home)
    }
}
