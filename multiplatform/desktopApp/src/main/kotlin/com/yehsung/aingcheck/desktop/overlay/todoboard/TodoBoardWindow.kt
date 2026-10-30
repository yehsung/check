// 원본: Sources/check/CheckTodoBoardWindow.swift:18-20(키를 받는 패널) · :368-505(지연 생성·makePanel) · :548-560(open — 띄우기) ·
//       :660-668(close — orderOut, 파괴 안 함) · :764-777(재배치 — 위치만) @ ef9fab11 · 설계 D §9-5
package com.yehsung.aingcheck.desktop.overlay.todoboard

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.awt.ComposeWindow
import com.sun.jna.Native
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.overlay.todoboard.win32.BoardWin32
import com.yehsung.aingcheck.ui.theme.AingTheme
import java.awt.Window
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import kotlin.math.roundToInt

/**
 * Windows 보드 창 — **활성화되는** 맨 위 도구 창(Compose 창 + `WS_EX_TOOLWINDOW`), 화면 공유에서 뺀다(D §9-5).
 * 맥은 nonactivating 패널이 첫 클릭에 키를 받지만 Windows 의 NOACTIVATE 창은 글자를 못 받으므로, 보드는 뜰 때 앞으로 나온다.
 * 다른 앱으로 활성이 넘어가면 [onDeactivated](바깥을 누르면 닫힌다). 캐릭터 창은 NOACTIVATE 라 캐릭터를 눌러도 활성이 안 넘어간다 —
 * 그 클릭은 엔진이 [TodoBoardController.toggle] 로 닫는다.
 *
 * 모든 호출은 UI(EDT) 스레드에서. 좌표는 DIP(AWT 사용자 공간).
 */
class TodoBoardWindow(
    private val content: @Composable () -> Unit,
    private val onDeactivated: () -> Unit = {},
    private val excludeFromCapture: Boolean = true,
    /**
     * 외양을 쓰면(조립 기본) 창을 **투명**으로 만들고(반투명 바탕이 뒤 화면을 비친다 — D §9-5 Compose 투명 창, DComp 판정은 VM)
     * 테마를 **어두움 고정**으로 한다(맥 CheckTodoBoardWindow.swift:499 `panel.appearance = .darkAqua` — 대비 수식이 흰 글자·어두운 판 전제).
     * false 면 W5-b3 1차 그대로(불투명 · 시스템 테마).
     */
    private val translucent: Boolean = false,
) : TodoBoardSurface {
    private var window: ComposeWindow? = null

    /** 마지막으로 건 Win32 성질(진단·러너 시험). */
    var lastApplied: BoardWin32.Applied? = null
        private set

    override val hasWindow: Boolean get() = window != null

    /** 창 핸들(만들어졌을 때만). */
    val hwnd: WinDef.HWND? get() = window?.let { WinDef.HWND(Native.getComponentPointer(it)) }

    override fun show(frame: OverlayRect) {
        val w = window ?: create().also { window = it }
        w.setBounds(frame.left.roundToInt(), frame.top.roundToInt(), frame.width.roundToInt(), frame.height.roundToInt())
        if (!w.isVisible) w.isVisible = true
        w.toFront()
        w.requestFocus()
        hwnd?.let { BoardWin32.bringToForeground(it) }
    }

    override fun move(frame: OverlayRect) {
        // 위치만 — 보이기·초점은 건드리지 않는다(맥 repositionNeverShowsOrFocusesThePanel).
        window?.setLocation(frame.left.roundToInt(), frame.top.roundToInt())
    }

    override fun hide() {
        window?.isVisible = false
    }

    /** 앱 종료 때만. 평소 닫기는 [hide](파괴하지 않는다). */
    fun dispose() {
        window?.dispose()
        window = null
    }

    private fun create(): ComposeWindow {
        val w = ComposeWindow()
        w.isUndecorated = true
        w.type = Window.Type.UTILITY
        w.isAlwaysOnTop = true
        w.isResizable = false
        w.title = TodoBoardStrings.TITLE
        // 투명은 창이 표시 가능해지기(addNotify) 전에만 걸린다.
        if (translucent) w.isTransparent = true
        w.setContent {
            AingTheme(dark = translucent || isSystemInDarkTheme()) { content() }
        }
        w.addWindowFocusListener(object : WindowAdapter() {
            override fun windowLostFocus(e: WindowEvent) {
                // 상대 창이 null = 다른 앱으로 갔다. 우리 창끼리(캐릭터·대화상자)의 이동은 닫을 이유가 아니다.
                if (e.oppositeWindow == null) onDeactivated()
            }
        })
        // 보이기 전에 성질을 건다(작업 표시줄 단추는 보인 뒤 바꾸면 안 빠진다).
        w.addNotify()
        lastApplied = BoardWin32.apply(WinDef.HWND(Native.getComponentPointer(w)), excludeFromCapture)
        return w
    }
}
