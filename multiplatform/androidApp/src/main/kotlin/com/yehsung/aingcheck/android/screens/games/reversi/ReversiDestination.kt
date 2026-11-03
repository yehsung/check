// 원본: Sources/CheckMobileKit/Games/GamesTab.swift(navigationDestination `.reversi` → GamesReversiScreen) @ ios-1017-int 91ea495d
//
// 아잉 뒤집기 목적지(Dest.Reversi)의 **진입 함수** — 화면 본문은 ui 모듈의 [ReversiScreen](한 화면 안 탭). 체스 목적지와 같은 꼴이다.
//  ① 섹션 인자가 없다 — 딥링크·푸시 글자가 없고(결정 "채팅·푸시 없음"), 내 판은 코어가 로비 `me.active_match_id` 로 스스로 연다.
//  ② Android 뒤로가기 → [ReversiBackPlan](덮개 닫기 · 사람과의 판이면 확인 · 관전 나가기 · 떠나기).
//  ③ 떼어 내기 깃발(`AppConfig.reversiEnabled`)이 꺼진 조립은 `games.reversi` 가 null 이다 — 입구가 하나도 서지 않으니 닿지 않지만, 닿아도 화면이 곧바로 물러난다.
package com.yehsung.aingcheck.android.screens.games.reversi

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.reversi.ReversiBackPlan
import com.yehsung.aingcheck.ui.games.reversi.ReversiScreen
import com.yehsung.aingcheck.ui.games.reversi.handleBack
import com.yehsung.aingcheck.ui.games.reversi.rememberReversiScreenState

@Composable
fun ReversiDestination(
    games: GamesStore,
    me: BoardGameMe,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val state = rememberReversiScreenState()
    val reversi = games.reversi
    BackHandler(enabled = reversi != null && ReversiBackPlan.step(state, reversi) != BoardBackStep.Leave) {
        if (reversi != null) state.handleBack(reversi)
    }
    ReversiScreen(games, me, onLeave, modifier, state = state, onTabBarHidden = onTabBarHidden)
}
