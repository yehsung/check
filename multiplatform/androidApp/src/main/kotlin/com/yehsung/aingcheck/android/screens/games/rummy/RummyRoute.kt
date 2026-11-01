// 원본: Sources/check/CheckRummyWindow.swift (창 수명 · 닫기 판단 — 폰은 뒤로 가기) @ 1a5eeca6 · 껍데기 꼴은 screens/games/tetris/TetrisDuelRoute.kt
//
// 아잉 큐브 화면의 Android 껍데기(본문은 ui/games/rummy GamesRummyScreen). 셸이 Dest.Rummy 자리에 둔다.
// 시스템 뒤로 가기를 화면 판단(GamesRummyBackState → 스토어 requestBack·confirmBack)에 잇는다 — 판 중이면 기권 확인을 묻고, 시스템이 그냥 pop 하지 못하게 늘 먹는다
// (떠나도 되는 판단이면 [onLeave] 가 pop 한다). 앱 앞/뒤는 GamesLifecycleBridge → GamesStore 가 나르고, 화면 꺼짐은 GamesKeepScreenOn 싱크가 GamesStore 값을 따른다.
// 방향은 RummyOrientationDriver 한 곳이다. 가로인 동안 가장자리 쓸기를 뒤로 제스처에서 뺀다(끌기와 겹치면 기권 확인이 뜬다 — iOS 는 내비 막대를 숨겨 뒤로 쓸기를 끈다). [최종 판]의 뒤로는 등수로 돌아간다.
package com.yehsung.aingcheck.android.screens.games.rummy

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.screens.games.minigame.rememberReduceMotion
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.ui.games.rummy.GamesRummyArt
import com.yehsung.aingcheck.ui.games.rummy.GamesRummyScreen
import com.yehsung.aingcheck.ui.games.rummy.rememberGamesRummyBackState

@Composable
fun RummyRoute(
    store: GamesStore,
    art: GamesRummyArt,
    myUserID: String?,
    me: RummySeatFace,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val back = rememberGamesRummyBackState()
    val rummy = store.context.rummy
    BackHandler(enabled = rummy != null) {
        if (store.isRummyFinalBoardShown) store.setRummyFinalBoardShown(false) else rummy?.let { back.handleBack(it, onLeave) }
    }
    val landscape = store.rummyInterfaceOrientation == GamesRummyInterfaceOrientation.landscape
    GamesRummyScreen(
        store = store,
        myUserID = myUserID,
        me = me,
        modifier = if (landscape) modifier.systemGestureExclusion() else modifier,
        art = art,
        back = back,
        onLeave = onLeave,
        reduceMotion = rememberReduceMotion(),
    )
}
