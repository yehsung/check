// 원본: Sources/CheckMobileKit/Games/GamesGomokuRanking.swift @ 3bd04bd
//
// 오목 로비 맨 아래 **순위표 절**(0.3.41) — 승점(승 − 패) 순위와 그 안의 내 자리. 새 목적지가 아니라 로비 안의 절이다: 스토어 `loadRanking` 은
// `phase == lobby` 와 창 표시를 요구하고, 자식 목적지를 밀면 폴링이 죽는다. 이 절은 타이머를 만들지 않고(순위 주기는 스토어 폴링),
// 순위 실패를 안내줄(notice)로 올리지 않는다(코어가 일부러 안 한다 — 대국 상태줄을 가린다). 실패는 이 절 안에서만 말한다.
//
// 분기 판정은 [GomokuRankingPlan] 한 곳(순수 — 데스크톱 시험이 값으로 잰다). 그림은 판정을 받아 그리기만 한다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRankEntry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.loadRanking
import com.yehsung.aingcheck.core.stores.gomoku.myRankConsistentWithRecord
import com.yehsung.aingcheck.core.stores.gomoku.myUserID
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 순위 절이 그릴 것(순수 판정). */
object GomokuRankingPlan {
    enum class Content { rows, soon, empty, failed, loading }

    /**
     * 분기: 행 → 준비 중 → 빈·실패·로딩.
     * INV-GamesGomokuRanking-ac5aefa8 이식: **행 갈래가 맨 앞이다.** `rankingUnavailable` 을 먼저 보면, 순위 조회는 성공해 행을 들고 있는데
     *   `gomoku_watch` 만 PGRST202 인 창에서 코어가 그 깃발을 세워 받아 둔 행을 통째로 버리고 "곧 열려요"를 말했다(폰 공용 규칙 위반 — 절이 이미
     *   줄을 들고 있으면 실패를 조용히 둔다).
     * INV-GamesGomokuRanking-e7809428 이식: 준비 중(서버에 함수가 아직 없다)은 **`placeholder` 분기보다 먼저** 본다 — 코어가 그 창을 "받은 것"으로
     *   세기 때문에(`rankingUnavailable = true · rankingLoadFailed = false · hasLoadedRanking = true`) `placeholder` 는 `.empty` 로 떨어진다.
     *   뒤로 미루면 "곧 열려요" 대신 "아직 전적이 없어요"가 뜬다.
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

    fun content(gomoku: GomokuStore): Content = content(
        hasRows = gomoku.ranking?.entries?.isNotEmpty() == true,
        rankingUnavailable = gomoku.rankingUnavailable,
        hasLoaded = gomoku.hasLoadedRanking,
        lastFailed = gomoku.rankingLoadFailed,
    )

    /** 보여 줄 행 — **재정렬하지 않는다**(서버 순서가 권위다). 앞에서부터 자르기만 한다. */
    fun visible(entries: List<GomokuRankEntry>, isExpanded: Boolean): List<GomokuRankEntry> =
        entries.take(if (isExpanded) GomokuScreenText.rankRowLimit else GomokuScreenText.rankCollapsedRows)

    fun total(entries: List<GomokuRankEntry>): Int = minOf(entries.size, GomokuScreenText.rankRowLimit)
}

@Composable
internal fun GomokuRankingSection(gomoku: GomokuStore, state: GomokuScreenState) {
    val colors = AingTheme.colors
    val ranking = gomoku.ranking
    // 머리 오른쪽 = 전적 기준 기간. 한 번도 못 받았으면 아무것도 말하지 않는다(컷을 모르는데 "전체 기간"은 거짓이다).
    val since = ranking?.let { r -> r.recordSince?.let(GomokuScreenText::rankSince) ?: GomokuScreenText.rankWholePeriod }
    Column(Modifier.fillMaxWidth().testTag("gomoku-ranking")) {
        when (GomokuRankingPlan.content(gomoku)) {
            GomokuRankingPlan.Content.rows -> {
                val entries = ranking?.entries.orEmpty()
                val total = GomokuRankingPlan.total(entries)
                val visible = GomokuRankingPlan.visible(entries, state.rankingExpanded)
                val showsToggle = total > GomokuScreenText.rankCollapsedRows
                BoardSectionHeader(GomokuScreenText.rankTitle, trailing = since)
                // 목록 밖의 내 순위 한 줄 — 값은 `myRankConsistentWithRecord` 하나에서만(순위 전적이 로비 전적과 어긋나면 null — 자기모순 문장을 만들지 않는다).
                gomoku.myRankConsistentWithRecord?.let { mine ->
                    BoardGroup {
                        BoardRow(highlighted = true) {
                            Column(Modifier.weight(1f)) {
                                Text(GomokuScreenText.myRankTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                                Text(GomokuScreenText.myRankLine(mine), style = BoardText.digits(BoardText.rowTitle()), color = colors.label)
                            }
                        }
                    }
                    Spacer(Modifier.height(AingDimens.rowSpacing))
                }
                BoardGroup {
                    // 내 행은 `myUserID` 로 고른다(순위 응답의 `me` 와 무관하게 **행 자체가 나인가** — 맥과 같은 판정).
                    val mine = gomoku.myUserID
                    visible.forEachIndexed { index, entry ->
                        GomokuRankRow(entry, isMe = entry.id == mine, isLast = !showsToggle && index == visible.size - 1)
                    }
                    if (showsToggle) {
                        BoardRow {
                            BoardButton(
                                if (state.rankingExpanded) GomokuScreenText.rankCollapse else GomokuScreenText.rankSeeAll(total),
                                kind = BoardButtonKind.Plain, small = true,
                                icon = if (state.rankingExpanded) AppIcon.ExpandLess else AppIcon.ExpandMore,
                                testTag = GomokuScreenTags.rankingToggle,
                            ) { state.rankingExpanded = !state.rankingExpanded }
                        }
                    }
                }
                BoardCaption(GomokuScreenText.rankCaption)
            }
            GomokuRankingPlan.Content.soon -> {
                BoardSectionHeader(GomokuScreenText.rankTitle, trailing = since)
                BoardGroup { BoardRow { Text(GomokuScreenText.rankingUnavailable, style = BoardText.subheadline(), color = colors.label2) } }
            }
            GomokuRankingPlan.Content.empty -> {
                BoardSectionHeader(GomokuScreenText.rankTitle, trailing = since)
                BoardGroup {
                    BoardRow {
                        Column {
                            Text(GomokuScreenText.noRanking, style = BoardText.subheadline(), color = colors.label2)
                            Text(GomokuScreenText.noRankingHint, style = BoardText.rowSubtitle(), color = colors.label2)
                        }
                    }
                }
            }
            GomokuRankingPlan.Content.failed -> {
                BoardSectionHeader(GomokuScreenText.rankTitle, trailing = since)
                BoardGroup {
                    BoardRow {
                        // 실패 한 줄 + [다시 시도] 위에, 왜 다시 시도가 안 먹을 수도 있는지 한 줄(구버전이면 서버가 같은 거절을 준다 — 뷰는 두 원인을 못 가린다).
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                            BoardLoadFailure(GomokuScreenText.rankingLoadFailed) { gomoku.scope.launch { gomoku.loadRanking() } }
                            Text(GomokuScreenText.rankingLoadFailedHint, style = BoardText.rowSubtitle(), color = colors.label2)
                        }
                    }
                }
            }
            // 절을 통째로 접는다 — 첫 조회 전에 머리만 번쩍이지 않게.
            GomokuRankingPlan.Content.loading -> Unit
        }
    }
}

/**
 * 순위 한 줄 — 순위 원 24 · 얼굴 30 · 이름(+ 센터) · 오른쪽 승점과 승·패·무. 내 행은 파랑 칠 + '나' 칩. 동률은 서버가 같은 rank 를 준다(받은 숫자 그대로).
 * INV-GamesGomokuRanking-a1379c0d 이식: **승점만 띄우지 않는다**(사용자 지시) — 승점 아래 "6승 2패 1무"를 늘 같이 그린다.
 * INV-GamesGomokuRanking-77996c18 이식: 승점·전적은 **세로로 쌓고 접히게** 둔다 — 두 조각을 한 가로 줄에 고정 폭으로 두면 큰 글자에서 카드가 오른쪽을
 *   잘라 뒤에 선 **전적**이 사라졌다(금지된 '승점만' 화면). 여기서는 오른쪽 열이 세로 둘이고 글자는 줄바꿈으로 접힌다(잘리지 않는다).
 * INV-GamesGomokuRanking-2bf10d1d 이식: 얼굴은 **그 행의 `entry.user`** 로 그리고 행이 받은 착용값(`characterID`)을 버리지 않는다 — 착용 표가 비어 있는 세션에서
 *   순위표 전원이 이니셜이 되던 꼴. 이 판은 사진 적재 전이라 이니셜 원이고, 착용 초상을 얹는 일은 공용 아바타 갈래(W3)가 이 값으로 한다(보고).
 * INV-GamesGomokuRanking-d5ca3d27 이식: 가로 고정은 **이 조각이 들지 않는다** — 승점·전적 글자는 제 폭을 고집하지 않고, 쓰는 자리(오른쪽 열)가 정한다.
 */
@Composable
private fun GomokuRankRow(entry: GomokuRankEntry, isMe: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    BoardRow(
        modifier = Modifier.clearAndSetSemantics { contentDescription = GomokuScreenText.rankRowAccessibility(entry, isMe) },
        divider = !isLast, dividerInset = AingDimens.cardPadding + 24.dp + 30.dp + AingDimens.space3 * 2, minHeight = 48.dp, highlighted = isMe,
    ) {
        RankBadge(entry.rank)
        BoardAvatar(entry.user.displayName, entry.user.id, 30.dp)
        BoardPersonName(entry.user.displayName, Modifier.weight(1f), center = entry.user.center, isMe = isMe)
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            // 승점은 **부호로** 말한다(초록·앰버는 근무 중·연결 끊김의 뜻이라 쓰지 않는다).
            Text(GomokuScreenText.signedPoints(entry.points), style = BoardText.digits(BoardText.rowTitle()).copy(fontWeight = FontWeight.Bold), color = colors.label)
            Text(GomokuScreenText.record(entry.wins, entry.losses, entry.draws), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
        }
    }
}

/** 순위 원(1~3위 메달색 — 동률이면 둘 다 받는다). */
@Composable
internal fun RankBadge(rank: Long) {
    val colors = AingTheme.colors
    val (fill, ink) = when (rank) {
        1L -> colors.gold to colors.goldInk
        2L -> colors.silver to colors.silverInk
        3L -> colors.bronze to colors.bronzeInk
        else -> colors.fill to colors.label2
    }
    Box(Modifier.size(24.dp).background(fill, CircleShape), contentAlignment = Alignment.Center) {
        Text("$rank", style = BoardText.digits(BoardText.caption()).copy(fontWeight = FontWeight.Bold), color = ink, maxLines = 1)
    }
}
