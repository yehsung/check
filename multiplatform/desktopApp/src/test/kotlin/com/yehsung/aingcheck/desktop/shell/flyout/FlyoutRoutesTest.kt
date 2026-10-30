// 원본: Sources/check/CheckApp.swift:176-201 @ a90d8623 — ★3 보낸이를 알면 그 대화(진입 overlay·알림, [뒤로] = 홈),
//       모르면 상대 고르는 목록. nil 상대로 대화 화면을 열지 않는다. 판정은 shellapi FlyoutRoutes 하나(c1·c0·W5-b 공유).
package com.yehsung.aingcheck.desktop.shell.flyout

import com.yehsung.aingcheck.desktop.shell.notify.ShellNotice
import com.yehsung.aingcheck.desktop.shell.notify.ShellNotifier
import com.yehsung.aingcheck.desktop.shellapi.BalloonNotifier
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoutes
import com.yehsung.aingcheck.desktop.shellapi.NotifyContext
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FlyoutRoutesTest {
    @Test
    fun star3NullSenderNeverOpensAConversation() {
        var conversations = 0
        for (poke in listOf(true, false)) for (from in Entry.entries) {
            val r = FlyoutRoutes.forMessageArrival(null, poke, from)
            if (r is FlyoutRoute.Conversation) conversations++
            assertEquals(if (poke) FlyoutRoute.PokeList else FlyoutRoute.Messages, r)
        }
        assertEquals(0, conversations)
        assertEquals(FlyoutRoute.Conversation("u1", Entry.OVERLAY), FlyoutRoutes.forMessageArrival("u1", false, Entry.OVERLAY))
    }

    @Test
    fun star3BackFromOverlayOrNotificationConversationIsHome() {
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(FlyoutRoute.Conversation("u", Entry.OVERLAY)))
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(FlyoutRoute.Conversation("u", Entry.NOTIFICATION)))
        assertEquals(FlyoutRoute.Messages, FlyoutRoutes.backOf(FlyoutRoute.Conversation("u", Entry.MESSAGES)))
        assertEquals(null, FlyoutRoutes.backOf(FlyoutRoute.Home))
    }

    private class FakeBalloon : BalloonNotifier {
        var handler: ((NotifyKind) -> Unit)? = null
        val shown = mutableListOf<Pair<NotifyKind, Boolean>>()
        override fun showBalloon(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): Boolean {
            shown += kind to respectQuietTime
            return true
        }
        override fun setOnBalloonClick(handler: (NotifyKind) -> Unit) { this.handler = handler }
    }

    private val toastCtx = NotifyContext(overlayVisible = false, fullscreenQuiet = false, bubbleAllowedByFocus = true, toastEnabled = true)

    @Test
    fun star3BalloonClickOpensConversationOrListThroughTheOneDoor() {
        val balloon = FakeBalloon()
        val nav = FlyoutController(FakeSurface(), { SyntheticScreen.facts }, clock = { 0L })
        val n = ShellNotifier(DesktopAppConfig(chatToast = true), balloon, nav)
        assertEquals(NotifySurface.TOAST, n.deliver(ShellNotice(NotifyKind.MESSAGE, "새 메시지", "본문", senderId = null), toastCtx))
        assertEquals(listOf(NotifyKind.MESSAGE to true), balloon.shown, "NIIF_RESPECT_QUIET_TIME")
        balloon.handler!!(NotifyKind.MESSAGE)
        assertTrue(nav.visible.value)
        assertEquals(FlyoutRoute.Messages, nav.route.value, "보낸이 모름 + poke 꺼짐 → 목록")
        nav.hide()
        n.deliver(ShellNotice(NotifyKind.MESSAGE, "새 메시지", "본문", senderId = "peer-1"), toastCtx)
        balloon.handler!!(NotifyKind.MESSAGE)
        assertEquals(FlyoutRoute.Conversation("peer-1", Entry.NOTIFICATION), nav.route.value)
        nav.back()
        assertEquals(FlyoutRoute.Home, nav.route.value, "알림에서 온 대화의 뒤로 = 홈")
    }
}
