// 원본: Sources/CheckMobileKit/Games/GamesTab.swift(navigationDestination `.alkkagi` → GamesAlkkagiScreen) @ 928d5562 — Android 판 8
//
// 1:1 알까기 화면의 Android 껍데기(본문은 ui/games/alkkagi GamesAlkkagiScreen). 떼어 내기 깃발이 꺼진 조립은 `games.alkkagi` 가 null — 곧바로 물러난다.
// 뒤로가기: 연습 · 관전은 화면이 자기 머리 막대로 접는다(시스템 뒤로는 화면을 떠난다 — 판은 서버 시계로 계속된다).
package com.yehsung.aingcheck.android.screens.games.alkkagi

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.screens.games.minigame.rememberDisplayRefreshHz
import com.yehsung.aingcheck.android.screens.games.minigame.rememberReduceMotion
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.games.alkkagi.GamesAlkkagiScreen

@Composable
fun AlkkagiRoute(store: GamesStore, myUserID: String?, myName: String?, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val alkkagi = store.alkkagi
    if (alkkagi == null) {
        LaunchedEffect(Unit) { onBack() }
        return
    }
    GamesAlkkagiScreen(store, alkkagi, myUserID, myName, rememberDisplayRefreshHz(), modifier, onBack, rememberReduceMotion())
}
