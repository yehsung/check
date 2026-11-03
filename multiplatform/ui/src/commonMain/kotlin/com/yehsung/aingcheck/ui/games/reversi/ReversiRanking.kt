// 원본: Sources/CheckMobileKit/Games/GamesReversiRanking.swift:74-286(순위 절 뷰 — 판정 몫은 core/stores GamesReversiRankingPlan) @ ios-1017-int 3e5051ed
//
// 폰 아잉 뒤집기 로비 **순위표 절** — 승점(승 − 패) 순위와 그 안의 내 자리. 서버 `reversi_ranking` 은 전적 컷 이후 **누적 한 벌**만 준다(주간 순위가 없다).
// 머리 오른쪽 캡션이 그 기간을 말한다("10월 1일부터" · 컷이 없으면 "전체 기간"). **새 목적지가 아니라 로비 안의 절이다**(목적지를 밀면 60초 폴링이 죽는다).
// 실패 갈래는 Android 스토어만 아는 깃발(`rankingLoadFailed`)이다 — 문구는 체스 표의 같은 두 줄을 빌린다(새 글자 없음). 받은 행은 다음 실패에 지우지 않는다.
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiRankingPlan
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiRankEntry
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.myUserID
import com.yehsung.aingcheck.core.stores.reversi.refreshRanking
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardCaption
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoadFailure
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoading
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardSectionHeader
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.RankBadge
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 아잉 뒤집기 로비 **순위표 절**. 상태는 코어가, 판정은 `GamesReversiRankingPlan` 이 한다. 이 절은 타이머를 만들지 않는다. */
@Composable
internal fun ReversiRankingSection(reversi: ReversiStore, state: ReversiScreenState) {
    val colors = AingTheme.colors
    val since = GamesReversiRankingPlan.sinceCaption(reversi)
    Column(Modifier.fillMaxWidth().testTag(ReversiScreenTags.ranking)) {
        BoardSectionHeader(ReversiPhoneText.rankTitle, trailing = since)
        when (GamesReversiRankingPlan.content(reversi)) {
            GamesReversiRankingPlan.Content.rows -> {
                GamesReversiRankingPlan.myRank(reversi)?.let { mine ->
                    // 강조 줄의 바탕이 그룹의 둥근 모서리 밖으로 새지 않게 자른다(첫·끝 줄이 강조여도 같은 모서리).
                    BoardGroup(Modifier.clip(RoundedCornerShape(AingDimens.groupRadius))) {
                        BoardRow(highlighted = true, modifier = Modifier.semantics(mergeDescendants = true) {}) {
                            Column(Modifier.weight(1f)) {
                                Text(ReversiPhoneText.myRankTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                                Text(ReversiPhoneText.myRankLine(mine), style = BoardText.digits(BoardText.rowTitle()), color = colors.label)
                            }
                        }
                    }
                    Spacer(Modifier.height(AingDimens.rowSpacing))
                }
                val visible = GamesReversiRankingPlan.visible(reversi, state.rankingExpanded)
                val showsToggle = GamesReversiRankingPlan.showsToggle(reversi)
                // 내 행은 `myUserID` 로 고른다(순위 응답의 `me` 와 무관하게 **행 자체가 나인가** — 맥과 같은 판정).
                val mine = reversi.myUserID
                BoardGroup(Modifier.clip(RoundedCornerShape(AingDimens.groupRadius))) {
                    visible.forEachIndexed { index, entry -> ReversiRankRow(entry, isMe = entry.id == mine, isLast = !showsToggle && index == visible.size - 1) }
                    if (showsToggle) {
                        // [전체 보기] · [접기] — **제자리에서** 펴고 접는다(새 화면을 밀면 폴링이 죽는다).
                        BoardRow {
                            BoardButton(
                                if (state.rankingExpanded) ReversiPhoneText.rankCollapse else ReversiPhoneText.rankSeeAll(GamesReversiRankingPlan.total(reversi)),
                                kind = BoardButtonKind.Plain, small = true, icon = if (state.rankingExpanded) AppIcon.ExpandLess else AppIcon.ExpandMore,
                                testTag = ReversiScreenTags.rankingToggle,
                            ) { state.rankingExpanded = !state.rankingExpanded }
                        }
                    }
                }
                // 절 아래 작은 두 줄: 승점의 뜻 + 0판인 사람은 안 낀다는 사실(짧은 목록을 사고로 읽지 않게).
                Column(Modifier.semantics(mergeDescendants = true) {}) {
                    BoardCaption(ReversiPhoneText.rankCaption)
                    BoardCaption(ReversiPhoneText.rankZeroGamesNote)
                }
            }
            GamesReversiRankingPlan.Content.soon -> BoardGroup { BoardRow { Text(ReversiPhoneText.rankingUnavailable, style = BoardText.subheadline(), color = colors.label2) } }
            GamesReversiRankingPlan.Content.empty -> BoardGroup {
                BoardRow(modifier = Modifier.semantics(mergeDescendants = true) {}) {
                    Column(Modifier.weight(1f)) {
                        Text(ReversiPhoneText.noRanking, style = BoardText.subheadline(), color = colors.label2)
                        Text(ReversiPhoneText.noRankingHint, style = BoardText.rowSubtitle(), color = colors.label2)
                    }
                }
            }
            GamesReversiRankingPlan.Content.failed -> BoardGroup {
                BoardRow {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                        BoardLoadFailure(ChessPhoneText.rankingLoadFailed) { reversi.scope.launch { reversi.refreshRanking() } }
                        Text(ChessPhoneText.rankingLoadFailedHint, style = BoardText.rowSubtitle(), color = colors.label2)
                    }
                }
            }
            GamesReversiRankingPlan.Content.loading -> BoardGroup { BoardRow { BoardLoading(ReversiPhoneText.rankLoading) } }
        }
    }
}

/**
 * 순위 한 줄 — 순위 원 · 얼굴 30 · 이름(+ 센터) · 승점과 승·패·무. ★ **일곱 칸을 다 그린다**(순위 · 얼굴 · 이름 · 승점 · 승 · 패 · 무) — 승점만 띄우는 것은
 * 사용자가 금지했다. 상태 점은 달지 않는다(순위 행 사람은 코어 경계에서 근무가 늘 거짓이다). 얼굴은 행이 실은 착용값까지 넘긴다.
 */
@Composable
private fun ReversiRankRow(entry: ReversiRankEntry, isMe: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    BoardRow(
        modifier = Modifier.clearAndSetSemantics { contentDescription = ReversiPhoneText.rankRowAccessibility(entry, isMe) },
        divider = !isLast, dividerInset = AingDimens.cardPadding + 24.dp + 30.dp + AingDimens.space3 * 2, minHeight = 48.dp, highlighted = isMe,
    ) {
        RankBadge(entry.rank.toLong())
        BoardAvatar(entry.user.displayName, entry.user.id, 30.dp, url = entry.user.avatarURL, characterHint = entry.user.characterID)
        if (reversiLargeFont()) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                BoardPersonName(entry.user.displayName, center = entry.user.center, isMe = isMe)
                Text(ReversiPhoneText.points(entry.points), style = BoardText.digits(BoardText.rowTitle()).copy(fontWeight = FontWeight.Bold), color = colors.label)
                Text(ReversiPhoneText.record(entry.wins, entry.losses, entry.draws), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
            }
        } else {
            BoardPersonName(entry.user.displayName, Modifier.weight(1f), center = entry.user.center, isMe = isMe)
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(ReversiPhoneText.points(entry.points), style = BoardText.digits(BoardText.rowTitle()).copy(fontWeight = FontWeight.Bold), color = colors.label)
                Text(ReversiPhoneText.record(entry.wins, entry.losses, entry.draws), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
            }
        }
    }
}
