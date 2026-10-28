// 원본: Sources/CheckMobileKit/Games/GamesChessRanking.swift @ 3bd04bd
//
// 체스 **순위표 절** — 승점(승 − 패) 순위와 그 안의 내 자리. 새 목적지가 아니라 로비 안의 절이다(폴링이 죽는다). 판정([ChessRankingPlan])은 순수 —
// 데스크톱 시험이 결과를 값으로 잰다. 순위 실패는 이 절 안에서만 말한다(안내줄로 올리지 않는다 — 대국 상태줄을 가린다).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.chess.ChessMyRank
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessRankEntry
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.loadRanking
import com.yehsung.aingcheck.core.stores.chess.myRankConsistentWithRecord
import com.yehsung.aingcheck.core.stores.chess.myUserID
import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardCaption
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoadFailure
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardSectionHeader
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.RankBadge
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 순위 절의 순수 판정(색·글꼴은 고르지 않는다). */
object ChessRankingPlan {
    enum class Content { rows, soon, empty, failed, loading }

    /**
     * INV-GamesChessRanking-aea526b0 이식: **0판인 사람은 안 낀다.** 서버가 이미 걸러 주지만 그 약속을 화면이 다시 지킨다 — 전적 컷 직후 0승 0패 0무 줄이
     *   사용자 수만큼 생겨 순위표가 통째로 덮일 수 있다.
     */
    fun playable(entries: List<ChessRankEntry>): List<ChessRankEntry> = entries.filter { it.wins + it.losses + it.draws > 0 }

    /** 들고 있는 행 — **재정렬하지 않는다**(서버 순서가 권위). 거르고 자르기만. */
    fun held(store: ChessStore): List<ChessRankEntry> = playable(store.ranking?.entries.orEmpty())

    fun visible(store: ChessStore, isExpanded: Boolean): List<ChessRankEntry> =
        held(store).take(if (isExpanded) ChessPhoneText.rankRowLimit else ChessPhoneText.rankCollapsedRows)

    fun total(store: ChessStore): Int = minOf(held(store).size, ChessPhoneText.rankRowLimit)

    fun showsToggle(store: ChessStore): Boolean = total(store) > ChessPhoneText.rankCollapsedRows

    /**
     * INV-GamesChessRanking-6e285014 이식: **분기 순서** — 행 → 준비 중 → 빈·실패·로딩. ① 행 갈래가 맨 앞(관전 PGRST202 가 세운 깃발이 받아 둔 행을 버리지 않게)
     *   ② 준비 중은 placeholder 보다 먼저(코어가 PGRST202 창을 "받은 것"으로 세어 `.empty` 로 떨어진다).
     */
    fun content(hasRows: Boolean, rankingUnavailable: Boolean, hasLoaded: Boolean, lastFailed: Boolean): Content {
        if (hasRows) return Content.rows
        if (rankingUnavailable) return Content.soon
        return when (MobileLoadKnowledge.placeholder(hasRows = false, hasLoaded = hasLoaded, lastFailed = lastFailed)) {
            MobileLoadKnowledge.Placeholder.rows -> Content.loading
            MobileLoadKnowledge.Placeholder.empty -> Content.empty
            MobileLoadKnowledge.Placeholder.failed -> Content.failed
            MobileLoadKnowledge.Placeholder.loading -> Content.loading
        }
    }

    fun content(store: ChessStore): Content =
        content(held(store).isNotEmpty(), store.rankingUnavailable, store.hasLoadedRanking, store.rankingLoadFailed)

    /**
     * 목록 **밖**의 내 순위.
     * INV-GamesChessRanking-b9bb69ac 이식: 접힌 상태에서 내가 5위 밖이면 이 줄이 그 정보를 맡으므로 **행 갈래와 무관하게** 늘 본다(목록에 내 행이 있어도 중복은
     *   해롭지 않다 — 없는 쪽이 사고다). 값은 `myRankConsistentWithRecord` 하나에서만(로비 전적과 어긋나면 null — 자기모순 문장을 만들지 않는다).
     */
    fun myRank(store: ChessStore): ChessMyRank? = store.myRankConsistentWithRecord

    /** 머리 오른쪽 캡션 — 한 번도 못 받았으면 아무것도 말하지 않는다. */
    fun sinceCaption(store: ChessStore): String? {
        val ranking = store.ranking ?: return null
        return ranking.recordSince?.let(ChessPhoneText::rankSince) ?: ChessPhoneText.rankWholePeriod
    }
}

@Composable
internal fun ChessRankingSection(chess: ChessStore, state: ChessScreenState) {
    val colors = AingTheme.colors
    val since = ChessRankingPlan.sinceCaption(chess)
    Column(Modifier.fillMaxWidth().testTag("chess-ranking")) {
        when (ChessRankingPlan.content(chess)) {
            ChessRankingPlan.Content.rows -> {
                BoardSectionHeader(ChessPhoneText.rankTitle, trailing = since)
                ChessRankingPlan.myRank(chess)?.let { mine ->
                    BoardGroup {
                        BoardRow(highlighted = true) {
                            Column(Modifier.weight(1f)) {
                                Text(ChessPhoneText.myRankTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                                Text(ChessPhoneText.myRankLine(mine), style = BoardText.digits(BoardText.rowTitle()), color = colors.label)
                            }
                        }
                    }
                    Spacer(Modifier.height(AingDimens.rowSpacing))
                }
                val visible = ChessRankingPlan.visible(chess, state.rankingExpanded)
                val showsToggle = ChessRankingPlan.showsToggle(chess)
                val mine = chess.myUserID
                BoardGroup {
                    visible.forEachIndexed { index, entry -> ChessRankRow(entry, isMe = entry.id == mine, isLast = !showsToggle && index == visible.size - 1) }
                    if (showsToggle) {
                        BoardRow {
                            BoardButton(
                                if (state.rankingExpanded) ChessPhoneText.rankCollapse else ChessPhoneText.rankSeeAll(ChessRankingPlan.total(chess)),
                                kind = BoardButtonKind.Plain, small = true, icon = if (state.rankingExpanded) AppIcon.ExpandLess else AppIcon.ExpandMore,
                                testTag = ChessScreenTags.rankingToggle,
                            ) { state.rankingExpanded = !state.rankingExpanded }
                        }
                    }
                }
                BoardCaption(ChessPhoneText.rankCaption)
            }
            ChessRankingPlan.Content.soon -> {
                BoardSectionHeader(ChessPhoneText.rankTitle, trailing = since)
                BoardGroup { BoardRow { Text(ChessPhoneText.rankingUnavailable, style = BoardText.subheadline(), color = colors.label2) } }
            }
            ChessRankingPlan.Content.empty -> {
                BoardSectionHeader(ChessPhoneText.rankTitle, trailing = since)
                BoardGroup {
                    BoardRow {
                        Column {
                            Text(ChessPhoneText.noRanking, style = BoardText.subheadline(), color = colors.label2)
                            Text(ChessPhoneText.noRankingHint, style = BoardText.rowSubtitle(), color = colors.label2)
                        }
                    }
                }
            }
            ChessRankingPlan.Content.failed -> {
                BoardSectionHeader(ChessPhoneText.rankTitle, trailing = since)
                BoardGroup {
                    BoardRow {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                            BoardLoadFailure(ChessPhoneText.rankingLoadFailed) { chess.scope.launch { chess.loadRanking() } }
                            Text(ChessPhoneText.rankingLoadFailedHint, style = BoardText.rowSubtitle(), color = colors.label2)
                        }
                    }
                }
            }
            ChessRankingPlan.Content.loading -> Unit
        }
    }
}

/**
 * 순위 한 줄 — 순위 원 · 얼굴 · 이름(+센터) · 오른쪽 승점과 승·패·무.
 * INV-GamesChessRanking-ff383cb1 이식: **일곱 칸을 다 그린다**(순위 · 아바타 · 이름 · 승점 · 승 · 패 · 무). 승점만 띄우는 것은 사용자가 금지했다.
 * INV-GamesChessRanking-f5ba88f8 이식: 얼굴은 그 행의 `entry.user` 로 — 행이 받은 착용값(`characterID`)을 버리지 않는다(착용 표가 빈 세션에서 전원이 이니셜이 되던
 *   꼴). 이 판은 사진·착용 초상 적재 전이라 이니셜 원이고, 공용 아바타 갈래(W3)가 이 값으로 초상을 얹는다(보고).
 * INV-GamesChessRanking-1b8add38 이식: 가로 고정은 승점·전적 조각이 들지 않는다 — **쓰는 자리에서** 정한다(오른쪽 열이 세로 둘이라 글자가 접힐 수 있다).
 */
@Composable
private fun ChessRankRow(entry: ChessRankEntry, isMe: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    BoardRow(
        modifier = Modifier.clearAndSetSemantics { contentDescription = ChessPhoneText.rankRowAccessibility(entry, isMe) },
        divider = !isLast, dividerInset = AingDimens.cardPadding + 24.dp + 30.dp + AingDimens.space3 * 2, minHeight = 48.dp, highlighted = isMe,
    ) {
        RankBadge(entry.rank)
        BoardAvatar(entry.user.displayName, entry.user.id, 30.dp)
        BoardPersonName(entry.user.displayName, Modifier.weight(1f), center = entry.user.center, isMe = isMe)
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(ChessPhoneText.points(entry.points), style = BoardText.digits(BoardText.rowTitle()).copy(fontWeight = FontWeight.Bold), color = colors.label)
            Text(ChessPhoneText.record(entry.wins, entry.losses, entry.draws), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
        }
    }
}
