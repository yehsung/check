// 원본: Sources/check/CheckApp.swift:344-440(presentWindow·dismissWindow 배선) · CheckMenuView.swift:970-980·1063-1085(창 먼저 열고 팝오버 나중 닫기)
//       (W4-d 창 공통 부품 — games.md §4)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind

/**
 * 게임·뽑기·케이크 창의 문. AppGraph(조정자 C3)가 스토어 문(presentWindow·dismissWindow)과 플라이아웃 게임 레일을 여기에 잇는다.
 *
 * 계약(맥 CheckMiniGameWindow 원형 — 나머지 창이 "그대로 베꼈다"):
 * ① 지연 생성 — 처음 열 때 창을 만든다. ② 멱등 열기 — 이미 열려 있으면 앞으로만, 최소화면 되살린다.
 * ③ 닫아도 파괴 안 함 — 자리·상태 보존(다시 열면 같은 창). ④ 창마다 고유 자리 키([GameWindowKind.boundsKey]).
 * ⑤ 시험 구현은 창 0(사용자 화면에 아무것도 띄우지 않는다).
 */
interface DesktopGameWindows {
    /** 미니게임 허브 창. [kind] 가 있으면 그 게임 화면으로 바로 간다. */
    fun openGames(kind: MiniGameKind? = null)
    fun openGomoku(focusMatchID: String? = null)
    fun openChess(focusMatchID: String? = null)
    fun openTetrisDuel(focusMatchID: String? = null)
    fun openGacha()
    fun openCakeGift()
    /** 로그아웃·계정 전환 — 창마다 [WindowEvent.AppClosed] 로 내린다(대결은 끝나지 않는다). */
    fun closeAll()

    /** 조립 전 자리(AppGraph 가 실제 구현을 넣기 전). 아무 창도 띄우지 않는다. */
    object None : DesktopGameWindows {
        override fun openGames(kind: MiniGameKind?) = Unit
        override fun openGomoku(focusMatchID: String?) = Unit
        override fun openChess(focusMatchID: String?) = Unit
        override fun openTetrisDuel(focusMatchID: String?) = Unit
        override fun openGacha() = Unit
        override fun openCakeGift() = Unit
        override fun closeAll() = Unit
    }
}
