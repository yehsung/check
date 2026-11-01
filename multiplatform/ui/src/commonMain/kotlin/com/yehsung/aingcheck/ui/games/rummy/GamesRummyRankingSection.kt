// 원본: Sources/check/RummyPanelLobby.swift:401 (RummyRankList) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
// 자리표시 — 다음 갈래가 이 파일을 통째로 채운다(로비의 [순위] 탭이 부른다).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.rummy.RummyStore

/** 순위 — `rummy.ranking`(적재는 `rummy.refreshRanking()`) + 내 전적. */
@Composable
fun GamesRummyRankingSection(rummy: RummyStore, myUserID: String?, modifier: Modifier = Modifier) {
    Column(modifier) { }
}
