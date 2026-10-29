// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift:76 @ 3bd04bd (.hidesTabBar(for: .miniGamePlay))
// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelMatch.swift:356-361 @ 3bd04bd (.hidesTabBar(for: .tetrisMatch) — 판 시간이 단조 시계로 흐른다)
//
// 게임 화면에서 하단 탭 막대를 숨길 때(셸 AingShell 의 bottomBar 가 읽는다 — 조립 K11, assembly.md). 판정만 둔다(그리기는 셸).
package com.yehsung.aingcheck.android.screens.games.hub

import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.core.stores.games.GamesStore

object GamesTabBarPolicy {
    /**
     * 지금 목적지에서 탭 막대를 숨기는가.
     *  · 미니게임 화면 — 늘 숨긴다(판이 캔버스 폭을 다 쓰고, 탭을 잘못 눌러 나가면 판이 끝난다).
     *  · 1:1 테트리스 — **판을 들고 있는 동안만**(phase != lobby). 판 시간이 단조 시계로 흘러 탭을 잘못 눌러 나가면 **안 보이는 채로 조각이 계속
     *    떨어진다** — 판돈이 걸린 판이다. 로비에서는 보인다.
     */
    fun hidesTabBar(destination: Any?, store: GamesStore): Boolean = when (destination) {
        is Dest.MiniGame -> true
        is Dest.TetrisDuel -> store.tetris.match != null
        else -> false
    }
}
