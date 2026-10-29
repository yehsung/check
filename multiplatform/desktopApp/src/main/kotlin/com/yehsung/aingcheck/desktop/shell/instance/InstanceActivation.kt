// 원본: 없음(새 코드) — 설계 D-windows-platform §2-5(두 번째 실행은 첫 실행에 "플라이아웃 열기"를 보내고 끝난다 — 트레이 아이콘이
//       숨겨진 사람의 탈출구) · W-windows-resume W-3 #5(두 번째 실행은 플라이아웃을 연다) · ★4 여는 문은 하나(FlyoutNavigator.open)
package com.yehsung.aingcheck.desktop.shell.instance

import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.instance.InstanceSignal
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import java.util.concurrent.Executor

object InstanceActivation {
    /** 신호 하나 → open() 한 번(지금 화면 그대로 연다 — 라우트를 바꾸지 않는다). [listen] 은 신호 길(InstanceSignal.listen). */
    fun bind(listen: (onActivate: () -> Unit) -> Registration, nav: FlyoutNavigator): Registration = listen { nav.open() }

    /** Windows: 첫 실행의 숨은 메시지 창에 붙인다. [events] = 창을 만질 스레드(Swing EDT). */
    fun bindWindows(thread: Win32MessageThread, nav: FlyoutNavigator, events: Executor): Registration =
        bind({ onActivate -> InstanceSignal.listen(thread, events, onActivate) }, nav)
}
