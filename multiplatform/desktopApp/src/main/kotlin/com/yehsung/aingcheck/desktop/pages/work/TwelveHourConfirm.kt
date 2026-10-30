// 원본: Sources/check/CheckComponents.swift:480-544(LongSessionBanner — 문구 넷 · [네, 근무 중이에요] 주 · [지금 종료] 보조)
//       · CheckMenuView.swift:551-558(onConfirm = store.confirmStillWorking() · onStopNow = store.stop())
//       · WorkTimerStore.swift:2383-2387(confirmStillWorking — 활성일 때만 · 기준점을 지금으로)
// W3-c2 — 12시간 확인. 두 갈래뿐이다: 계속 = confirmStillWorking 한 번, 종료 = stop 한 번(수동 종료 — 자동 시작 억제가 붙는다,
// WorkTimerStore.swift:2140-2151). 명령은 [DesktopWorkCommands] 로만 낸다(store 직접 stop 은 소셜 생명주기를 뺀다 — WorkWiring 머리말).
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkCommands
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot

object TwelveHourConfirm {
    /** CheckComponents.swift:492. */
    const val title = "12시간 넘게 근무 중이에요"
    /** CheckComponents.swift:496. */
    const val subtitle = "아직 근무 중이신가요?"
    /** CheckComponents.swift:506. */
    const val confirm = "네, 근무 중이에요"
    /** CheckComponents.swift:517. */
    const val stopNow = "지금 종료"

    enum class Choice { CONTINUE, STOP_NOW }

    /** 맥 `isLongSessionPromptActive` 에 해당 — ws 가 promptShownAt 을 스냅숏에 올렸을 때만. */
    fun isActive(snapshot: DesktopWorkSnapshot): Boolean = snapshot.longSessionPromptShownAt != null

    /** 한 번 눌림 = 명령 한 번. 계속은 종료를, 종료는 확인을 부르지 않는다. */
    fun choose(choice: Choice, commands: DesktopWorkCommands) {
        when (choice) {
            Choice.CONTINUE -> commands.confirmStillWorking()
            Choice.STOP_NOW -> commands.stop()
        }
    }
}
