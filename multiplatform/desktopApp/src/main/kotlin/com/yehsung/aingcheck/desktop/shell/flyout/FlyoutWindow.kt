// 원본: 없음(새 코드) — 설계 D-windows-platform §3-3(미리 만들어 숨긴다 · 작업 표시줄 단추 없음(TOOLWINDOW) · 둥근 모서리(Win11 DWM)
//       · 열 때 SetForegroundWindow 가 성공해야 비활성화로 닫을 수 있다 · WM_ACTIVATE(WA_INACTIVE) 면 숨김 · Esc)
// OS 호출(JNA)은 shell/flyout/native 만 한다(ShellStructureTest). 이 파일은 AWT 창과 사건 배선만.
package com.yehsung.aingcheck.desktop.shell.flyout

import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacement
import com.yehsung.aingcheck.desktop.shell.flyout.native.FlyoutNative
import java.awt.Component
import java.awt.Window
import java.awt.event.KeyEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import javax.swing.JComponent
import javax.swing.JFrame
import javax.swing.KeyStroke
import javax.swing.SwingUtilities
import javax.swing.WindowConstants

/**
 * 조립 순서(내용이 navigator 를 필요로 하므로 순환을 끊는다):
 * `val w = FlyoutWindow(); val c = FlyoutController(w, …); w.setContent(FlyoutComposeContent.create(host, c, c::widthDip, c::onContentHeight));
 *  w.onDeactivated = c::onDeactivated; w.onEscape = c::onEscape; w.precreate()`.
 */
class FlyoutWindow(content: Component? = null, title: String = TITLE) : FlyoutSurface {
    private val frame = JFrame(title).apply {
        isUndecorated = true
        type = Window.Type.UTILITY
        isAlwaysOnTop = true
        defaultCloseOperation = WindowConstants.HIDE_ON_CLOSE
        if (content != null) contentPane.add(content)
    }

    /** 내용을 바꿔 끼운다(조립 때 한 번). */
    fun setContent(content: Component) = onEdt {
        frame.contentPane.removeAll()
        frame.contentPane.add(content)
        frame.contentPane.revalidate()
    }

    /** 비활성화(바깥 클릭) → FlyoutController.onDeactivated. */
    @Volatile var onDeactivated: () -> Unit = {}

    /** Esc → FlyoutController.onEscape. */
    @Volatile var onEscape: () -> Unit = {}

    /** DwmSetWindowAttribute(둥근 모서리) HRESULT — Windows 10 은 실패가 정상(모서리 각진 채). 진단용. */
    @Volatile var cornerResult: Int? = null
        private set

    val window: Window get() = frame

    init {
        frame.addWindowListener(object : WindowAdapter() {
            override fun windowDeactivated(e: WindowEvent) {
                if (frame.isVisible) onDeactivated()
            }
        })
        frame.rootPane.registerKeyboardAction(
            { onEscape() },
            KeyStroke.getKeyStroke(KeyEvent.VK_ESCAPE, 0),
            JComponent.WHEN_IN_FOCUSED_WINDOW,
        )
    }

    /** 미리 만든다(숨긴 채 HWND 를 만들고 TOOLWINDOW·둥근 모서리를 건다). 첫 열기 지연을 없앤다. EDT 에서. */
    fun precreate() = onEdt {
        frame.addNotify()
        FlyoutNative.applyToolWindowStyle(frame)
        cornerResult = FlyoutNative.roundCorners(frame)
    }

    override fun show(placement: FlyoutPlacement) = onEdt {
        if (!frame.isDisplayable) precreate()
        // 숨은 채 자리를 먼저 옮기고(번쩍임 방지) 보인 뒤 한 번 더 — AWT 가 보일 때 옛 크기를 밀어 넣는 경우를 덮는다.
        FlyoutNative.place(frame, placement.rect)
        if (!frame.isVisible) frame.isVisible = true
        FlyoutNative.place(frame, placement.rect)
        FlyoutNative.bringToFront(frame)
        frame.toFront()
        frame.requestFocus()
    }

    override fun hide() = onEdt {
        if (frame.isVisible) frame.isVisible = false
    }

    fun dispose() = onEdt { frame.dispose() }

    private fun onEdt(block: () -> Unit) {
        if (SwingUtilities.isEventDispatchThread()) block() else SwingUtilities.invokeAndWait(block)
    }

    companion object {
        const val TITLE = "아잉체크"
    }
}
