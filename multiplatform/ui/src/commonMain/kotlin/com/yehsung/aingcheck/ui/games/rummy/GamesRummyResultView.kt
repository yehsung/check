// 원본: Sources/check/RummyPanelResult.swift:19 (RummyResultView) · :159 (RummyFinalBoard) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
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

/** 결과 — 등수 · 루비 ± · 최종 패 · [한 판 더](`RummyExitPolicy.rematchInvitees` → `rummy.createAndInvite`) · [최종 판 보기] · [나가기](`rummy.dismissResult`). */
@Composable
fun GamesRummyResultView(
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    reduceMotion: Boolean,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    Column(modifier) { GamesHeaderBar(RummyPhoneText.resultTitle, onBack = onBack) }
}
