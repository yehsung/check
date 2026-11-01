// 원본: Sources/check/RummyPanelLobby.swift:516 (RummyTableCard) · :684 (RummyTableStage) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
// 자리표시 — 다음 갈래가 이 파일을 통째로 채운다(서명은 껍데기 GamesRummyScreen 이 부른다).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar

/** 방 — 의자 넷(`RummyTableSeating.chairs`) · 방장 [시작] · 초대 줄 · 시작 남은 시간(`rummy.roomRemaining`). */
@Composable
fun GamesRummyRoomView(
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    Column(modifier) { GamesHeaderBar(RummyPhoneText.myRoomTitle, onBack = onBack) }
}
