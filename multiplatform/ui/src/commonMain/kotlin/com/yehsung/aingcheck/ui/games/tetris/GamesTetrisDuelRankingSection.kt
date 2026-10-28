// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelRanking.swift:123-392 @ 3bd04bd (순위 탭 절 · 순위 한 줄)
//
// 1:1 테트리스 로비 **순위 탭**. 상태는 전부 코어 TetrisDuelStore 가 들고, 판정은 GamesTetrisDuelRankingPlan(core)이 한다. 이 뷰는 타이머를 만들지
// 않는다 — 순위 주기는 스토어 폴링 루프가 돌고, 여기엔 초 단위로 변하는 글자가 없다.
package com.yehsung.aingcheck.ui.games.tetris

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelRankingPlan
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisLobbyTab
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelRankEntry
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisPhoneText
import com.yehsung.aingcheck.core.stores.tetris.loadRanking
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadingRow
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.RankBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/**
 * 순위 탭 절. [myUserID] 는 **화면이 넘긴다**(폰 세션 — 미니게임 순위와 같은 자리) — 코어 host 를 뒤지지 않는다(로그아웃 틈에 그쪽이 비면 내 행 강조만
 * 조용히 사라지는 갈래가 생긴다).
 */
@Composable
fun GamesTetrisDuelRankingSection(store: TetrisDuelStore, myUserID: String?) {
    var isExpanded by remember { mutableStateOf(false) }
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    // 탭을 고른 순간 말고 **탭이 선 채로 화면이 다시 뜬 길**도 있다(앱을 나갔다 돌아옴 · 판이 끝나 로비로) — 판정은 같은 한 곳이다.
    LaunchedEffect(store) { GamesTetrisDuelRankingPlan.refreshIfNeeded(store, GamesTetrisLobbyTab.ranking) }
    val header: @Composable () -> Unit = {
        SectionHeader(
            TetrisPhoneText.rankTitle,
            trailing = GamesTetrisDuelRankingPlan.sinceCaption(store)?.let { SectionTrailing.Label(it) } ?: SectionTrailing.None,
            padded = true,
        )
    }
    // 분기 순서의 근거는 GamesTetrisDuelRankingPlan.content 머리말에 있다. 뷰는 **다시 판정하지 않는다.**
    when (GamesTetrisDuelRankingPlan.content(store)) {
        GamesTetrisDuelRankingPlan.Content.rows -> {
            val visible = GamesTetrisDuelRankingPlan.visible(store, isExpanded)
            val showsToggle = GamesTetrisDuelRankingPlan.showsToggle(store)
            header()
            MyRankRow(store)
            InsetGroup {
                // 내 행은 순위 응답의 me 와 무관하게 **행 자체가 나인가**로 고른다.
                visible.forEachIndexed { index, entry ->
                    RankRow(entry, entry.id == myUserID, isLast = !showsToggle && index == visible.size - 1)
                }
                if (showsToggle) {
                    // 그룹 맨 아래 [전체 보기] · [접기] — **제자리에서** 펴고 접는다(새 화면을 밀지 않는다 · 폴링이 죽는다).
                    GroupRow(dividerInset = null, padding = PaddingValues(start = AingDimens.cardPadding - 13.dp, end = AingDimens.cardPadding, top = 2.dp, bottom = 2.dp)) {
                        PillButton(
                            if (isExpanded) TetrisPhoneText.rankCollapse else TetrisPhoneText.rankSeeAll(GamesTetrisDuelRankingPlan.total(store)),
                            kind = PillKind.Plain, size = PillSize.Sm, icon = if (isExpanded) AppIcon.ExpandLess else AppIcon.ExpandMore,
                        ) { isExpanded = !isExpanded }
                    }
                }
            }
            // 탭 아래 작은 두 줄: 승점의 뜻 + **0판인 사람은 안 낀다**는 사실(빈 순위·짧은 목록을 사고로 읽지 않게).
            Column(
                Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2).semantics(mergeDescendants = true) { },
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(TetrisPhoneText.rankCaption, style = rowSubtitleStyle(), color = colors.label2)
                Text(TetrisPhoneText.rankZeroGamesNote, style = rowSubtitleStyle(), color = colors.label2)
            }
        }
        GamesTetrisDuelRankingPlan.Content.soon -> {
            header()
            InsetGroup { MessageRow(TetrisPhoneText.rankSoon, null) }
        }
        GamesTetrisDuelRankingPlan.Content.empty -> {
            header()
            InsetGroup { MessageRow(TetrisPhoneText.rankEmpty, TetrisPhoneText.rankEmptyHint) }
        }
        GamesTetrisDuelRankingPlan.Content.failed -> {
            header()
            InsetGroup {
                GroupRow(dividerInset = null) {
                    // 세로 한 칸: 실패 한 줄 + [다시 시도], 아래 **왜 다시 시도가 안 먹을 수도 있는지** 한 줄.
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                        LoadFailureRow(TetrisPhoneText.rankLoadFailed) { scope.launch { store.loadRanking() } }
                        Text(TetrisPhoneText.rankLoadFailedHint, style = rowSubtitleStyle(), color = colors.label2)
                    }
                }
            }
        }
        GamesTetrisDuelRankingPlan.Content.loading -> {
            // INV-GamesTetrisDuelRanking-de7363e6 이식: 체스 순위 절과 **다르게** 접지 않는다 — 저쪽은 로비 맨 아래 절이라 접어도 위에 볼 것이 남지만,
            //   이쪽은 **탭 하나가 통째로 이 절**이다(접으면 순위 탭을 눌렀는데 빈 화면이 선다). 머리 + 불러오는 중 한 줄을 그린다.
            header()
            InsetGroup { GroupRow(dividerInset = null) { LoadingRow(TetrisPhoneText.rankLoading) } }
        }
    }
}

/**
 * 목록 밖의 내 순위 한 줄. 판정은 GamesTetrisDuelRankingPlan.myRank 하나다.
 * INV-GamesTetrisDuelRanking-efdc02b0 이식: 접힌 상태에서 내가 5위 밖이면 이 줄이 그 정보를 맡으므로 **행 갈래와 무관하게** 늘 본다(접힘·펼침 어느 쪽에서도
 *   행 목록 위에 선다).
 */
@Composable
private fun MyRankRow(store: TetrisDuelStore) {
    val mine = GamesTetrisDuelRankingPlan.myRank(store) ?: return
    val colors = AingTheme.colors
    InsetGroup(Modifier.padding(bottom = AingDimens.rowSpacing)) {
        GroupRow(dividerInset = null, isHighlighted = true, modifier = Modifier.semantics(mergeDescendants = true) { }) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(TetrisPhoneText.myRankTitle, style = rowSubtitleStyle(), color = colors.label2)
                Text(TetrisPhoneText.myRankLine(mine), style = rowTitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label)
            }
        }
    }
}

@Composable
private fun MessageRow(text: String, hint: String?) {
    val colors = AingTheme.colors
    GroupRow(dividerInset = null, modifier = Modifier.semantics(mergeDescendants = true) { }) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
            if (hint != null) Text(hint, style = rowSubtitleStyle(), color = colors.label2)
        }
    }
}

/**
 * 순위 한 줄 — 순위 원 24 · 얼굴 30 · 이름 · 오른쪽 승점과 승·패·무. 내 행은 파랑 6% + '나' 칩. 동률은 서버가 같은 rank 를 주고 다음 숫자를
 * 건너뛴다(4,4,6) — 받은 숫자를 그대로 그린다.
 * INV-GamesTetrisDuelRanking-7253994c 이식: **여섯 칸을 다 그린다**(순위 · 아바타 · 이름 · 승점 · 승 · 패 · 무). 승점만 띄우는 것은 사용자가 금지했다 —
 *   큰 글자에서는 숫자를 이름 아래로 쌓을 뿐 빼지 않는다.
 * INV-GamesTetrisDuelRanking-fb369db0 이식: 얼굴은 **그 행의 entry.user** 로 그린다(색 씨앗 = 그 행의 id) — 순위판은 근무 상태판이 아니라 상태 점을 달지
 *   않는다(행의 user 는 코어 경계에서 근무가 전부 false 라 점을 달면 전원이 "근무 안 함"이 된다). 착용 캐릭터 힌트를 쓰는 사진 얼굴은 공용 부품 통합(W3) 몫이다.
 */
@Composable
private fun RankRow(entry: TetrisDuelRankEntry, isMe: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    val stacked = LocalDensity.current.fontScale >= 1.3f
    GroupRow(
        dividerInset = if (isLast) null else AingDimens.cardPadding + 24.dp + AingDimens.space3 + 30.dp + AingDimens.space3,
        minHeight = 48.dp,
        padding = PaddingValues(horizontal = AingDimens.cardPadding, vertical = 7.dp),
        isHighlighted = isMe,
        modifier = Modifier.clearAndSetSemantics { contentDescription = TetrisPhoneText.rankRowAccessibility(entry, isMe) },
    ) {
        RankBadge(entry.rank)
        PersonAvatar(entry.user.displayName, entry.user.id, 30.dp)
        val points: @Composable () -> Unit = {
            // 승점은 **부호를 보이게**("+4" · "−2" · "0") — 색으로 말하지 않는다(초록·앰버는 근무·연결 끊김의 뜻이라 갈린다).
            Text(TetrisPhoneText.points(entry.points), style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = colors.label)
        }
        val record: @Composable () -> Unit = {
            Text(TetrisPhoneText.record(entry.wins, entry.losses, entry.draws), style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2)
        }
        if (stacked) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                PersonName(entry.user.displayName, isMe = isMe)
                points()
                record()
            }
        } else {
            PersonName(entry.user.displayName, Modifier.weight(1f), isMe = isMe)
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                points()
                record()
            }
        }
    }
}
