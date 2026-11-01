// 원본: Sources/check/RummyPanelLobby.swift:401 (RummyRankList) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5 · 꼴은 GamesTetrisDuelRankingSection
//
// 로비 [순위] 탭. 순위·배열 순서 모두 서버 것이다(다시 줄 세우지 않는다). 주기 갱신은 스토어 폴링이 돌고(60초), 이 뷰는 **탭을 처음 볼 때 빈 표면 한 번** 읽는다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyRankingPlan
import com.yehsung.aingcheck.core.stores.rummy.RummyLobbyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.loadRanking
import com.yehsung.aingcheck.core.stores.rummy.refreshRanking
import com.yehsung.aingcheck.core.wire.games.RummyRankRow
import com.yehsung.aingcheck.core.wire.games.RummyRankingMe
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadingRow
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.RankBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 앞선 조회가 날고 있으면 `loadRanking` 이 곧바로 돌아온다 — 그 답을 이만큼 기다린 뒤에야 실패로 말한다(밀리초). */
private const val IN_FLIGHT_GRACE_MILLIS: Long = 1500

/** 순위 — `rummy.ranking`(적재는 `rummy.loadRanking()`) + 내 전적. [myUserID] 는 화면이 넘긴다(내 행 강조). */
@Composable
fun GamesRummyRankingSection(rummy: RummyStore, myUserID: String?, modifier: Modifier = Modifier) {
    var attempted by remember { mutableStateOf(false) }
    // 키는 스토어 하나다(이 효과 안에서 바꾸는 값을 키로 걸지 않는다 — 재생성 고리 금지). 일은 스토어 범위에서 돈다: 탭을 바꿔도 요청이 취소되지 않는다.
    LaunchedEffect(rummy) {
        if (rummy.ranking != null) return@LaunchedEffect
        rummy.scope.launch { rummy.loadRanking() }.join()
        if (rummy.ranking == null) delay(IN_FLIGHT_GRACE_MILLIS)
        attempted = true
    }
    val ranking = rummy.ranking
    Column(modifier) {
        SectionHeader(RummyPhoneText.rankTab, trailing = SectionTrailing.Label(RummyPhoneText.rankHeader), padded = true)
        when (GamesRummyRankingPlan.content(ranking, attempted)) {
            GamesRummyRankingPlan.Content.rows -> {
                ranking?.me?.let { MyRankRow(it) }
                val rows = ranking?.rows ?: emptyList()
                InsetGroup {
                    rows.forEachIndexed { index, row ->
                        RankRow(row, GamesRummyRankingPlan.isMe(row.id, myUserID), isLast = index == rows.size - 1)
                    }
                }
            }
            GamesRummyRankingPlan.Content.empty -> {
                ranking?.me?.let { MyRankRow(it) }
                InsetGroup {
                    GroupRow(dividerInset = null) {
                        Text(RummyPhoneText.emptyRanking, style = MaterialTheme.typography.bodyMedium, color = AingTheme.colors.label2)
                    }
                }
            }
            GamesRummyRankingPlan.Content.loading -> InsetGroup {
                GroupRow(dividerInset = null) { LoadingRow(RummyLobbyPhoneText.rankingLoading) }
            }
            GamesRummyRankingPlan.Content.failed -> InsetGroup {
                GroupRow(dividerInset = null) {
                    LoadFailureRow(RummyLobbyPhoneText.rankingFailed, Modifier.weight(1f)) { rummy.refreshRanking() }
                }
            }
        }
    }
}

/** 내 줄 — 내 순위 · 판 수 · 1등. 행 목록 위에 늘 선다(내가 목록 밖이어도 보이게). */
@Composable
private fun MyRankRow(me: RummyRankingMe) {
    InsetGroup(Modifier.padding(bottom = AingDimens.rowSpacing)) {
        GroupRow(dividerInset = null, isHighlighted = true, modifier = Modifier.semantics(mergeDescendants = true) { }) {
            Text(RummyLobbyPhoneText.myRank(me), style = rowTitleStyle().copy(fontFeatureSettings = TNUM), color = AingTheme.colors.label)
        }
    }
}

/** 순위 한 줄 — 순위 원 · 얼굴 · 이름 · 판 수와 1등 수. 큰 글자에서는 전적을 이름 아래로 쌓는다(빼지 않는다). */
@Composable
private fun RankRow(row: RummyRankRow, isMe: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    val name = row.displayName ?: "?"
    val stacked = LocalDensity.current.fontScale >= 1.3f
    val record: @Composable () -> Unit = {
        Text(RummyPhoneText.record(row.games, row.wins), style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2, maxLines = 1)
    }
    GroupRow(
        dividerInset = if (isLast) null else AingDimens.cardPadding + 24.dp + AingDimens.space3 + 30.dp + AingDimens.space3,
        minHeight = 48.dp,
        padding = PaddingValues(horizontal = AingDimens.cardPadding, vertical = 7.dp),
        isHighlighted = isMe,
        modifier = Modifier.clearAndSetSemantics { contentDescription = RummyLobbyPhoneText.rankRowAccessibility(row.rank, name, row.games, row.wins, isMe) },
    ) {
        val rank = row.rank
        if (rank != null) {
            RankBadge(rank.toInt())
        } else {
            Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                Text(RummyLobbyPhoneText.unknownNumber, style = rowSubtitleStyle(), color = colors.label2)
            }
        }
        PersonAvatar(name, row.id.lowercased, 30.dp, url = row.avatarUrl, characterHint = row.character)
        if (stacked) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                PersonName(name, isMe = isMe)
                record()
            }
        } else {
            PersonName(name, Modifier.weight(1f), isMe = isMe)
            record()
        }
    }
}
