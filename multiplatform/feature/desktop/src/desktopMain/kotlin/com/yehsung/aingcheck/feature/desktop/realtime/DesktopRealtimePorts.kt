// 원본: Sources/check/WorkTimerStoreRealtime.swift @ c4e0ebfc — 러너가 부르는 바깥 몫(메시지·게임). 값 없는 신호만 넘긴다.
// 판정은 여기 없다: 메시지 요약·읽음 장부는 메시지 스토어, 대국 상태는 각 게임 스토어가 권위다(조회는 소비가 아니다).
package com.yehsung.aingcheck.feature.desktop.realtime

/**
 * 메시지 쪽 문 두 개(Swift `requestMessageActivityRefresh` · `requestMessageActivityRefreshCoalesced` 의 창 닫힘).
 * 조립(AppGraph)이 MessagesStore 에 잇는다 — 겹친 조회를 뒤따르는 한 번으로 합치는 일은 스토어 몫(MessagesStore.requestActivityRefresh:633).
 */
interface DesktopRealtimeMessages {
    /** 서버 표를 한 번 읽는다(take_pokes 아님). `.drain` 이 게이트에 막혔을 때 · 조인 직후 따라잡기에서 부른다. */
    fun requestActivityRefresh()

    /** 읽음 신호(`message_read`)가 올 때마다(창에 얹기 전) 부른다 — 계기 순간을 적는다(공용 패치 8 `MessagesStore.readSignalArrived`). */
    fun readSignalArrived() {}

    /** 읽음 신호(`message_read`)를 1초 창으로 모은 뒤 **창 하나에 한 번** 부른다(Swift m-fix2 · 부록 B-2). */
    fun readSignalWindowClosed()

    /** 조립 전·시험 자리. */
    object None : DesktopRealtimeMessages {
        override fun requestActivityRefresh() {}
        override fun readSignalWindowClosed() {}
    }
}

/**
 * 게임 한 벌(오목·체스·테트리스)의 실시간 몫. Swift `gomoku/chess/tetris.{handleSignal, realtimeDidJoin, systemDidWake}`.
 * ★ R5: 셋 다 **조회뿐**이라 소비 게이트를 지나지 않는다(두 기기가 모두 받아도 누구의 것을 훔치지 않는다).
 */
interface DesktopRealtimeGame {
    fun handleSignal()
    fun realtimeDidJoin()
    fun systemDidWake()
}

/** 순서는 Swift 그대로(오목 → 체스 → 테트리스). 없는 게임은 null(Windows 1차 웨이브에서 꺼진 판). */
data class DesktopRealtimeGames(
    val gomoku: DesktopRealtimeGame? = null,
    val chess: DesktopRealtimeGame? = null,
    val tetris: DesktopRealtimeGame? = null,
) {
    internal val inOrder: List<DesktopRealtimeGame> get() = listOfNotNull(gomoku, chess, tetris)

    companion object {
        val NONE = DesktopRealtimeGames()
    }
}
