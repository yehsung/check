// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift:445-477(TabBarPolicy) · Components/SheetChrome.swift:192(.hidesTabBar(for:)) @ 3bd04bd
// 부르는 자리(iOS): MessagesTab.swift:39 · GamesGomokuMatch.swift:75·430 · GamesChessMatch.swift:375 · GamesTetrisDuelMatch.swift:360 ·
//   MeCharacterViews.swift:143 · GamesMiniGameScreen.swift:76 · MeGrassDetailView.swift:74
//
// 셸(AingShell)의 탭 막대 숨김 표 — **목적지 표가 한 자리다**. iOS 는 화면마다 `.hidesTabBar(for:)` 를 부르고, Android 는 셸이 이 표를 읽는다.
// 7차 로컬 e2e: 숨김 판정이 목적지 값 변환(CurrentDest — 푸시 숨김용)을 거쳤는데 그 변환이 테트리스 대결을 몰라 1:1 테트리스 판에서만
// 탭 막대가 보였다('판 중에 앱을 나가면 져요' 바로 아래). 이제 NavDestination.hasRoute 로 이 표를 직접 맞춘다.
package com.yehsung.aingcheck.android.nav

import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hasRoute
import com.yehsung.aingcheck.core.stores.rankings.TabBarPolicy
import kotlin.reflect.KClass

object ShellTabBarRules {
    /** 판 상태 — 셸이 스토어와 화면 알림에서 읽어 넘긴다. */
    data class Play(
        /** 1:1 테트리스 판을 들고 있다(GamesStore.tetris.match != null). 로비에서는 보인다(iOS 는 판 화면에만 붙였다). */
        val tetrisMatch: Boolean = false,
        /** 오목·체스 화면이 '판(대국·결과·로봇 화면)'이라고 알렸다(GomokuTabBarPolicy · ChessTabBarPolicy → onTabBarHidden). 로비·관전은 거짓. */
        val boardScreenHides: Boolean = false,
    )

    /** 표 한 줄: 목적지 · iOS 화면(없으면 Android 만의 줄) · 판 상태에 따른 숨김. */
    class Row(val route: KClass<*>, val screen: TabBarPolicy.Screen?, val hides: (Play) -> Boolean)

    val rows: List<Row> = listOf(
        Row(Dest.Conversation::class, TabBarPolicy.Screen.conversation) { true },
        Row(Dest.Gomoku::class, TabBarPolicy.Screen.gomokuMatch) { it.boardScreenHides },
        Row(Dest.Chess::class, TabBarPolicy.Screen.chessMatch) { it.boardScreenHides },
        // 판 시간이 단조 시계로 흐른다 — 탭을 잘못 눌러 나가면 안 보이는 채로 조각이 계속 떨어진다(판돈이 걸린 판).
        Row(Dest.TetrisDuel::class, TabBarPolicy.Screen.tetrisMatch) { it.tetrisMatch },
        Row(Dest.Shop::class, TabBarPolicy.Screen.shop) { true },
        Row(Dest.MiniGame::class, TabBarPolicy.Screen.miniGamePlay) { true },
        Row(Dest.GrassDetail::class, TabBarPolicy.Screen.grassDetail) { true },
        // Android 만: 뽑기 기계는 전체 화면 목적지다(iOS 는 fullScreenCover 라 탭 막대를 덮는다 — iOS 표에 없는 까닭).
        Row(Dest.GachaMachine::class, null) { true },
    )

    /** [route] 목적지에서 탭 막대를 숨기는가. iOS 화면이 있는 줄은 iOS 답([TabBarPolicy.hidesTabBar])을 지나서 숨긴다. */
    fun hidesTabBar(route: KClass<*>?, play: Play): Boolean {
        val row = rows.firstOrNull { it.route == route } ?: return false
        if (!row.hides(play)) return false
        return row.screen?.let(TabBarPolicy::hidesTabBar) ?: true
    }

    /** 셸이 부르는 쪽 — 지금 백스택 꼭대기 목적지. */
    fun hidesTabBar(destination: NavDestination?, play: Play): Boolean {
        if (destination == null) return false
        val row = rows.firstOrNull { destination.hasRoute(it.route) } ?: return false
        return hidesTabBar(row.route, play)
    }
}
