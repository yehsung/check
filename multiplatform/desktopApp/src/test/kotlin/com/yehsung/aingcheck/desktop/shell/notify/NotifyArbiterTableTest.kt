// 원본: W-windows-resume W-3 #6 · 설계 D-windows-platform §10-1·2 — ★2 같은 사건은 한 표면만: 말풍선 > 토스트 > 빨간 점(점은 늘),
//       집중 모드는 말풍선과 같은 규칙으로 토스트도 막는다 · W-3 #7(대결 깃발 꺼짐 → 신청 안내 없음)
package com.yehsung.aingcheck.desktop.shell.notify

import com.yehsung.aingcheck.desktop.shellapi.BalloonNotifier
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.NotifyContext
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface.BUBBLE
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface.DOT_ONLY
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface.TOAST
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NotifyArbiterTableTest {
    // 손으로 쓴 16줄(overlay, fullscreenQuiet, focusAllows, toast) → 표면. 규칙 식을 다시 쓰지 않는다.
    private val table: List<Pair<BooleanArray, NotifySurface>> = listOf(
        booleanArrayOf(false, false, false, false) to DOT_ONLY,
        booleanArrayOf(false, false, false, true) to DOT_ONLY,
        booleanArrayOf(false, false, true, false) to DOT_ONLY,
        booleanArrayOf(false, false, true, true) to TOAST,
        booleanArrayOf(false, true, false, false) to DOT_ONLY,
        booleanArrayOf(false, true, false, true) to DOT_ONLY,
        booleanArrayOf(false, true, true, false) to DOT_ONLY,
        booleanArrayOf(false, true, true, true) to TOAST,
        booleanArrayOf(true, false, false, false) to DOT_ONLY,
        booleanArrayOf(true, false, false, true) to DOT_ONLY,
        booleanArrayOf(true, false, true, false) to BUBBLE,
        booleanArrayOf(true, false, true, true) to BUBBLE,
        booleanArrayOf(true, true, false, false) to DOT_ONLY,
        booleanArrayOf(true, true, false, true) to DOT_ONLY,
        booleanArrayOf(true, true, true, false) to DOT_ONLY,
        booleanArrayOf(true, true, true, true) to TOAST,
    )

    @Test
    fun star2FourKindsTimesSixteenContextsAndDotAlwaysOn() {
        var checked = 0
        for (kind in NotifyKind.entries) for ((b, expected) in table) {
            val ctx = NotifyContext(overlayVisible = b[0], fullscreenQuiet = b[1], bubbleAllowedByFocus = b[2], toastEnabled = b[3])
            val outcome = ShellNotifyArbiter.decide(kind, ctx)
            assertEquals(expected, outcome.surface, "$kind $ctx")
            assertEquals(expected, ShellNotifyArbiter.surface(kind, ctx))
            assertTrue(outcome.dot, "점은 늘 켜진다: $kind $ctx")
            checked++
        }
        assertEquals(64, checked)
        assertEquals(16, table.map { it.first.toList() }.toSet().size, "2⁴ 전수")
    }

    private class FakeBalloon : BalloonNotifier {
        val shown = mutableListOf<NotifyKind>()
        override fun showBalloon(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): Boolean {
            shown += kind
            return true
        }
        override fun setOnBalloonClick(handler: (NotifyKind) -> Unit) {}
    }

    private val toast = NotifyContext(overlayVisible = false, fullscreenQuiet = false, bubbleAllowedByFocus = true, toastEnabled = true)
    private val bubbleCtx = toast.copy(overlayVisible = true)

    @Test
    fun w3n7DuelsAndPokeOffMeanNoSurfaceAtAll() {
        val b = FakeBalloon()
        val n = ShellNotifier(DesktopAppConfig(), b, InMemoryFlyoutNavigator())
        assertNull(n.deliver(ShellNotice(NotifyKind.DUEL_INVITE, "오목 신청", "x"), toast))
        assertNull(n.deliver(ShellNotice(NotifyKind.POKE, "콕", "x"), toast))
        assertEquals(emptyList(), b.shown)
        val on = ShellNotifier(DesktopAppConfig(duels = true), b, InMemoryFlyoutNavigator())
        assertEquals(TOAST, on.deliver(ShellNotice(NotifyKind.DUEL_INVITE, "오목 신청", "x"), toast))
    }

    @Test
    fun oneSurfaceOnlyBubbleDoesNotAlsoToastAndChatToastFlagGatesMessageToasts() {
        val b = FakeBalloon()
        val bubbles = mutableListOf<ShellNotice>()
        val n = ShellNotifier(DesktopAppConfig(chatToast = false), b, InMemoryFlyoutNavigator(), bubble = { bubbles += it; true })
        assertEquals(BUBBLE, n.deliver(ShellNotice(NotifyKind.MESSAGE, "t", "b", "u"), bubbleCtx))
        assertEquals(1, bubbles.size)
        assertEquals(emptyList(), b.shown, "말풍선을 띄운 사건은 토스트로 또 뜨지 않는다")
        assertEquals(DOT_ONLY, n.deliver(ShellNotice(NotifyKind.MESSAGE, "t", "b", "u"), toast), "chatToast 꺼짐 → 메시지 토스트 없음")
        assertEquals(TOAST, n.deliver(ShellNotice(NotifyKind.UPDATE, "새 버전", "b"), toast))
        assertEquals(listOf(NotifyKind.UPDATE), b.shown)
    }

    /** W-14 #4: 말풍선 문이 못 받으면(false — 캐릭터 꺼짐·stop 뒤) 오버레이가 없는 것처럼 다시 고른다 — 토스트, 토스트도 꺼졌으면 점. 사건이 사라지지 않는다. */
    @Test
    fun refusedBubbleFallsBackToToastOrDotNeverNowhere() {
        val b = FakeBalloon()
        val offered = mutableListOf<ShellNotice>()
        val n = ShellNotifier(DesktopAppConfig(chatToast = false), b, InMemoryFlyoutNavigator(), bubble = { offered += it; false })
        assertEquals(TOAST, n.deliver(ShellNotice(NotifyKind.UPDATE, "새 버전", "b"), bubbleCtx))
        assertEquals(listOf(NotifyKind.UPDATE), b.shown, "말풍선을 거절당한 사건이 토스트로 내려가지 않았다")
        assertEquals(DOT_ONLY, n.deliver(ShellNotice(NotifyKind.MESSAGE, "t", "b", "u"), bubbleCtx), "chatToast 꺼짐 → 거절된 말풍선은 점만")
        assertEquals(listOf(NotifyKind.UPDATE), b.shown)
        assertEquals(2, offered.size, "말풍선 문을 먼저 두드리지 않았다")
    }
}
