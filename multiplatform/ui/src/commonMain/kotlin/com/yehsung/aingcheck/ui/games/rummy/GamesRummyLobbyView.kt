// 원본: Sources/check/RummyPanelLobby.swift:128 (RummyLobbyView) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
// 자리표시 — 다음 갈래가 이 파일을 통째로 채운다(서명은 껍데기 GamesRummyScreen 이 부른다).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar

/** 로비 — 받은 초대 · 공개 방 · 사람 · 판돈 · 순위 탭. 다른 게임 판 막기는 [store] 의 `rummyEntryBlock`. */
@Composable
fun GamesRummyLobbyView(
    store: GamesStore,
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    Column(modifier) { GamesHeaderBar(RummyPhoneText.title, onBack = onBack) }
}
