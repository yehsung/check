// 원본: Sources/check/RummyPanelMatch.swift:247 (RummyMatchView) · Sources/check/RummyTableCanvas.swift:192 (RummyTableCanvasView) · Sources/check/RummyRackView.swift:90 (RummyRackView) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §4
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

/** 판 — 머리 줄 · 상대 줄 · 판 · 상태 줄 · 받침대 · 동작 줄. [onBack] 은 [나가기](껍데기가 기권 확인을 띄운다). */
@Composable
fun GamesRummyMatchView(
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    reduceMotion: Boolean,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    Column(modifier) { GamesHeaderBar(RummyPhoneText.title, onBack = onBack) }
}
