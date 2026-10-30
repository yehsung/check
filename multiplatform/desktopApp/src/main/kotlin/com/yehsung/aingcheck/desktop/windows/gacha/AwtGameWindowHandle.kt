// 원본: Sources/check/CheckGachaWindow.swift:441-500 · CheckCakeGiftWindow.swift:340-380(창 사건 · 고정 크기 · 고착 감시)
//       (W4-f — 뽑기·케이크 창의 실제 창. 사건을 kit WindowEvent 로 옮기기만 한다. 시험은 이 파일을 만들지 않는다 — 창 0)
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.runtime.Composable
import androidx.compose.ui.awt.ComposeWindow
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.windows.kit.CloakProbe
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowSlot
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import java.awt.Frame
import java.awt.event.WindowAdapter
import java.awt.event.WindowFocusListener
import javax.swing.Timer
import javax.swing.WindowConstants
import kotlin.math.roundToInt
import java.awt.event.WindowEvent as AwtWindowEvent

/** 다음 열기가 키(포커스)를 가져가는가. 케이크 선물을 스스로 띄울 때는 거짓(맥 show(activating: false) — 다른 창에서 치던 키를 가로채지 않는다). */
class ShowFocus {
    @Volatile
    var activate: Boolean = true
}

/**
 * 고정 크기 ComposeWindow 하나(맥 windowWillResize 가 고정 크기를 돌려준다). 닫기(×)는 숨기기만 한다 — 판정·숨김은 GameWindowSlot.
 * 가림: Windows 엔 occlusionState 가 없다 — 가상 데스크톱 cloak 만 [CLOAK_POLL_MS] 주기로 읽어 [WindowEvent.Visibility] 로 낸다
 * (위험 ③: '다른 창에 완전히 덮임'은 보임으로 남는다 — 기계가 조금 더 돈다, 수용).
 */
class AwtGameWindowHandle(
    title: String,
    private val focus: ShowFocus,
    private val onEvent: (WindowEvent) -> Unit,
    content: @Composable () -> Unit,
) : GameWindowHandle {
    private val window = ComposeWindow().apply {
        this.title = title
        defaultCloseOperation = WindowConstants.DO_NOTHING_ON_CLOSE
        isResizable = false
        setContent { content() }
    }
    private var lastCloaked = false
    private val cloakTimer = Timer(CLOAK_POLL_MS) { pollCloak() }.apply { isRepeats = true }

    init {
        window.addWindowListener(object : WindowAdapter() {
            override fun windowClosing(e: AwtWindowEvent) = onEvent(WindowEvent.UserClosed)
            override fun windowIconified(e: AwtWindowEvent) = onEvent(WindowEvent.Minimized)
            override fun windowDeiconified(e: AwtWindowEvent) = onEvent(WindowEvent.Restored)
        })
        window.addWindowFocusListener(object : WindowFocusListener {
            override fun windowGainedFocus(e: AwtWindowEvent) = onEvent(WindowEvent.FocusGained)
            override fun windowLostFocus(e: AwtWindowEvent) = onEvent(WindowEvent.FocusLost)
        })
    }

    override val isMinimized: Boolean get() = (window.extendedState and Frame.ICONIFIED) != 0
    override val isOnScreen: Boolean get() = window.isShowing && !isMinimized

    override fun restoreFromMinimized() {
        window.extendedState = window.extendedState and Frame.ICONIFIED.inv()
    }

    override fun showAndFocus() {
        window.isAutoRequestFocus = focus.activate
        window.isVisible = true
        window.toFront()
        if (focus.activate) window.requestFocus()
        lastCloaked = false
        cloakTimer.start()
    }

    override fun hide() {
        cloakTimer.stop()
        window.isVisible = false
    }

    override fun boundsPx(): PxRect {
        val k = scale()
        val b = window.bounds
        return PxRect((b.x * k).roundToInt(), (b.y * k).roundToInt(), ((b.x + b.width) * k).roundToInt(), ((b.y + b.height) * k).roundToInt())
    }

    override fun setBoundsPx(rect: PxRect) {
        val k = scale()
        window.setBounds((rect.left / k).roundToInt(), (rect.top / k).roundToInt(), (rect.width / k).roundToInt(), (rect.height / k).roundToInt())
    }

    override fun dispose() {
        cloakTimer.stop()
        window.dispose()
    }

    private fun scale(): Double = window.graphicsConfiguration?.defaultTransform?.scaleX?.takeIf { it > 0 } ?: 1.0

    private fun pollCloak() {
        val cloaked = CloakProbe.isCloaked(window)
        if (cloaked != lastCloaked) {
            lastCloaked = cloaked
            onEvent(WindowEvent.Visibility(!cloaked))
        }
    }

    companion object {
        const val CLOAK_POLL_MS = 1_000
    }
}

/** 고착 감시(맥 armStuckWindowWatchdog — 열기 0.5초 뒤 한 번). 다시 만들기 상한은 GameWindowSlot.MAX_RECREATIONS. */
fun armStuckWatchdog(slot: GameWindowSlot) {
    Timer(GameWindowSlot.STUCK_CHECK_DELAY_MS.toInt()) { slot.checkStuck() }.apply { isRepeats = false }.start()
}
