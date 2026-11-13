// 원본: Sources/CheckMobileKit/Games/GamesTab.swift(navigationDestination `.crossyDuel` → GamesCrossyDuelScreen) @ 928d5562 — Android 판 8
//
// 1:1 길건너 화면의 Android 껍데기(본문은 ui/games/crossy GamesCrossyDuelScreen). 셸이 Dest.CrossyDuel 자리에 둔다.
// 떼어 내기 깃발(`AppConfig.crossyDuelEnabled`)이 꺼진 조립은 `games.crossyDuel` 이 null 이다 — 입구가 서지 않으니 닿지 않지만, 닿아도 곧바로 물러난다.
// 판돈 대결 신청·수락 진입은 **duelsEnabled** 가 켜진 빌드에서만 보인다(G §8-17 1 — 깃발은 스토어가 문맥으로 읽는다).
package com.yehsung.aingcheck.android.screens.games.crossy

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.screens.games.minigame.rememberDisplayRefreshHz
import com.yehsung.aingcheck.android.screens.games.minigame.rememberReduceMotion
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.games.crossy.GamesCrossyDuelScreen

@Composable
fun CrossyDuelRoute(
    store: GamesStore,
    myUserID: String?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val duel = store.crossyDuel
    if (duel == null) {
        LaunchedEffect(Unit) { onBack() }
        return
    }
    GamesCrossyDuelScreen(
        store = store,
        duel = duel,
        myUserID = myUserID,
        refreshHz = rememberDisplayRefreshHz(),
        modifier = modifier,
        onBack = onBack,
        reduceMotion = rememberReduceMotion(),
    )
}
