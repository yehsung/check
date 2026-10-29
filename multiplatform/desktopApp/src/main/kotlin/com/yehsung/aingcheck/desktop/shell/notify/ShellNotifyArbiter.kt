// 원본: Sources/check/CheckApp.swift:176-201·351-441 @ a90d8623 (맥은 OS 알림 0건 — 근무 중 말풍선, 그 밖 빨간 점·배너)
//       · 설계 D-windows-platform §10-1·2 · W-windows-resume W-3 #6(★2 같은 사건은 한 표면만: 말풍선 > 토스트 > 빨간 점, 점은 늘)
//
// 규칙(위에서 먼저 맞는 것):
//  ① 앱 집중 모드가 말풍선을 막으면(bubbleAllowedByFocus=false) 토스트도 막는다 → DOT_ONLY (D §10-2 "같은 규칙으로 토스트도 막는다").
//  ② 오버레이가 보이고(peek 가능 포함 — W5-b 가 넘긴다) 전체 화면 숨김이 아니면 → BUBBLE.
//  ③ 토스트가 켜져 있으면 → TOAST (오버레이 꺼짐·근무 밖·전체 화면 숨김. OS 방해 금지는 NIIF_RESPECT_QUIET_TIME 이 맡는다).
//  ④ 그 밖 → DOT_ONLY.
// 점은 어느 경우에도 켠다(NotifyOutcome.dot). 종류(kind)는 표면을 가르지 않는다 — 깃발로 끄는 일은 ShellNotifier 가 먼저 한다.
package com.yehsung.aingcheck.desktop.shell.notify

import com.yehsung.aingcheck.desktop.shellapi.NotifyArbiter
import com.yehsung.aingcheck.desktop.shellapi.NotifyContext
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface

/** 한 사건의 결과: 고른 표면 하나 + 점(늘 참). */
data class NotifyOutcome(val surface: NotifySurface, val dot: Boolean)

object ShellNotifyArbiter : NotifyArbiter {
    override fun surface(kind: NotifyKind, ctx: NotifyContext): NotifySurface = when {
        !ctx.bubbleAllowedByFocus -> NotifySurface.DOT_ONLY
        ctx.overlayVisible && !ctx.fullscreenQuiet -> NotifySurface.BUBBLE
        ctx.toastEnabled -> NotifySurface.TOAST
        else -> NotifySurface.DOT_ONLY
    }

    fun decide(kind: NotifyKind, ctx: NotifyContext): NotifyOutcome = NotifyOutcome(surface(kind, ctx), dot = true)
}
