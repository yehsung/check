// 원본: 없음(새 코드) — int-w3 overlay 갈래 unresolved[4] · int-w4a polish ④. 맥은 NSApplication.didChangeScreenParametersNotification 하나가
// 모든 화면의 배율 변경을 알린다(CheckOverlayWindow 가 자리를 다시 조인다). Windows 의 WM_DPICHANGED 는 **그 창이 있는 모니터**의 배율이 바뀌었을 때
// 그 창에만 온다 — 앱 숨은 창(Win32DisplayChangeSource)은 주 모니터에 있으므로, 캐릭터가 보조 모니터에 있을 때 그 모니터 배율을 바꾸면
// 숨은 창은 아무것도 받지 않는다. 그래서 오버레이 창 자신의 WM_DPICHANGED 도 같은 "화면 바뀜" 으로 낸다(OverlayWiring.onDisplayChanged).
package com.yehsung.aingcheck.desktop.overlay.surface

import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayChange
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayChangeSource
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayMessages
import java.util.concurrent.CopyOnWriteArrayList

/**
 * 오버레이 창 프로시저(WindowsOverlaySurface.handle)가 맨 먼저 묻는 몫. WM_DPICHANGED 면 듣는 이에게 [DisplayChange.DPI] 를 알리고 0 을 돌려준다
 * (MSDN: 처리했으면 0 — 제안 사각형으로 창을 옮기지 않는다: 레이어드 창이라 다음 그림의 UpdateLayeredWindow 가 크기·자리를 정한다).
 * 다른 메시지는 null(창 프로시저가 그대로 처리). 듣는 이는 메시지 스레드에서 불린다 — 받는 쪽은 명령 채널에 넣기만 한다.
 */
class OverlayWindowDpiRelay : DisplayChangeSource {
    private val listeners = CopyOnWriteArrayList<(DisplayChange) -> Unit>()

    override fun addListener(listener: (DisplayChange) -> Unit): Registration {
        listeners += listener
        return Registration { listeners.remove(listener) }
    }

    /** 이 창 메시지 하나. WM_DPICHANGED 만 맡는다(WM_DISPLAYCHANGE·작업 영역은 숨은 창이 이미 받는다 — 두 번 다시 읽지 않게). */
    fun handle(message: Int): WinDef.LRESULT? {
        if (message != DisplayMessages.WM_DPICHANGED) return null
        listeners.forEach { runCatching { it(DisplayChange.DPI) } }
        return WinDef.LRESULT(0)
    }

    /** 듣는 이 수(시험 · 진단). */
    val listenerCount: Int get() = listeners.size
}
