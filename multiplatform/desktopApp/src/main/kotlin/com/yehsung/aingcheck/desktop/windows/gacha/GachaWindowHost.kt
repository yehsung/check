// 원본: Sources/check/CheckGachaWindow.swift:330-440(창 만들기 · 제목 · 자동저장 이름) · WorkTimerStoreGacha.swift:149-158(openGachaWindow)
//       (W4-f — 뽑기 창의 조립 자리. AppGraph(조정자 C3)가 DesktopGameWindows.openGacha 를 [open] 에, 로그아웃을 [close] 에 잇는다)
package com.yehsung.aingcheck.desktop.windows.gacha

import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent

/** 뽑기 창(실제 ComposeWindow). EDT 에서 부른다. 시험은 [GachaWindowController] 에 가짜 손잡이를 넣어 잰다(창 0). */
class GachaWindowHost(
    private val store: MeStore,
    bounds: WindowBoundsStore,
    workAreas: () -> List<PxRect>,
    scale: () -> Double,
    private val reduceMotion: () -> Boolean = { false },
    private val unrevealed: GachaUnrevealedCell = GachaUnrevealedCell(),
) {
    private val focus = ShowFocus()
    val controller = GachaWindowController(store.gachaMachineFacts(unrevealed), ::createHandle, bounds, workAreas, scale)

    /** 맥 openGachaWindow 의 창 몫(가용성 안내·상점 새로 읽기는 상점 화면이 이미 한다). 열고 0.5초 뒤 고착 감시. */
    fun open() {
        focus.activate = true
        controller.open()
        armStuckWatchdog(controller.slot)
    }

    fun close() = controller.close()

    private fun createHandle(onEvent: (WindowEvent) -> Unit): GameWindowHandle =
        AwtGameWindowHandle(GachaText.title, focus, onEvent) {
            GachaWindowContent(store, controller.state, onClose = ::close, reduceMotion = reduceMotion(), unrevealed = unrevealed)
        }
}
