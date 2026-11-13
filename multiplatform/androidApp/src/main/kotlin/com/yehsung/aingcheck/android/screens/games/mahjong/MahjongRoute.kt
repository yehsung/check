// 원본: Sources/CheckMobileKit/Games/GamesTab.swift(navigationDestination `.mahjong` → GamesMahjongScreen) @ 928d5562 — Android 판 8
//
// 아잉 마작 화면의 Android 껍데기(본문은 ui/games/mahjong GamesMahjongScreen). 떼어 내기 깃발이 꺼진 조립은 `games.mahjong` 이 null — 곧바로 물러난다.
// 방향은 큐브와 같은 길(RummyOrientationDriver)이다 — GamesStore.rummyInterfaceOrientation 이 마작 판이면 가로를 답한다. 가로인 동안 가장자리 쓸기를
// 뒤로 제스처에서 빼고(손패를 누르다 화면을 떠나지 않게) 화면 구멍 쪽 여백을 둔다. 시스템 뒤로는 화면을 떠난다 — 판은 서버 시계로 계속된다(기권 아님).
package com.yehsung.aingcheck.android.screens.games.mahjong

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.ui.games.mahjong.GamesMahjongScreen

@Composable
fun MahjongRoute(store: GamesStore, myName: String?, myCharacter: String?, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val mahjong = store.mahjong
    if (mahjong == null) {
        LaunchedEffect(Unit) { onBack() }
        return
    }
    val landscape = store.mahjongWantsLandscape && store.rummyInterfaceOrientation == GamesRummyInterfaceOrientation.landscape
    val shaped = if (landscape) {
        modifier.systemGestureExclusion().windowInsetsPadding(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal))
    } else {
        modifier
    }
    GamesMahjongScreen(store, mahjong, myName, myCharacter, shaped, onBack)
}
