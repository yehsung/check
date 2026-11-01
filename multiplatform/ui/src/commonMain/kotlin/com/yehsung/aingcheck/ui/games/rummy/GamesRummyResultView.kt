// 원본: Sources/check/RummyPanelResult.swift:19 (RummyResultView) · :100 (RummyResultRow) · :159 (RummyFinalBoard) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
//
// 결과 — 머리 줄 · 끝난 이유 · 등수 줄(또는 최종 판) · 단추. 판단은 값 쪽이다: 줄 순서·순수익·남은 타일 폭·판 배율은 core RummyResultSummary · RummyFinalBoardLayout,
// [한 판 더]는 스토어 playAgain(같은 판돈·공개 여부 · 끝까지 남은 사람). 맥은 창이 넓어 한 줄에 다 놓았고 폰은 줄마다 두 단이다(위: 등수·이름·루비 / 아래: 남은 타일).
// 이 화면에는 모션이 없다(말풍선은 껍데기의 층이 그린다).
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyFinalBoardLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyResultSummary
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.dismissResult
import com.yehsung.aingcheck.core.stores.rummy.playAgain
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.kit.AingChip
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 결과 화면 꼬리표(시험·계측). */
object GamesRummyResultTags {
    const val HEADLINE: String = "rummy.result.headline"
    const val RULES: String = "rummy.result.rules"
    const val PLAY_AGAIN: String = "rummy.result.playAgain"
    const val BOARD_TOGGLE: String = "rummy.result.boardToggle"
    const val TO_LOBBY: String = "rummy.result.toLobby"
    const val FINAL_BOARD: String = "rummy.result.finalBoard"
    const val BOARD_ZOOM: String = "rummy.result.boardZoom"

    fun row(seatNo: Long?): String = "rummy.result.row.$seatNo"
}

/** 결과 — 등수 · 루비 순수익 · 남은 타일 · 끝난 이유 · [한 판 더] · [최종 판 보기] · [나가기](`rummy.dismissResult` — 로비로). [onBack] 은 머리 줄 뒤로(화면을 떠난다). */
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
    block: GamesBusyGame? = null,
) {
    val match = rummy.match
    Column(modifier) {
        GamesHeaderBar(RummyPhoneText.resultTitle, onBack = onBack) { GamesRummyRulesButton(onRules, Modifier.testTag(GamesRummyResultTags.RULES)) }
        if (match != null) ResultBody(rummy, match, me, now, block, Modifier.weight(1f))
    }
}

@Composable
private fun ResultBody(rummy: RummyStore, match: RummyMatchState, me: RummySeatFace, now: () -> SwiftDate, block: GamesBusyGame?, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    var showsBoard by remember(match.id) { mutableStateOf(false) }
    val rows = remember(match) { RummyResultSummary.rows(match) }
    Column(modifier.fillMaxWidth()) {
        if (showsBoard) {
            GamesRummyFinalBoard(match.table ?: emptyList(), match.tableLayout, Modifier.weight(1f).fillMaxWidth())
        } else {
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(vertical = AingDimens.space2),
                verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
            ) {
                ResultHeadline(rummy, match, rows, now)
                for (seat in rows) ResultRow(seat, match.stake, RummyResultSummary.isMe(seat, match), me)
            }
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space1),
        ) {
            GamesBusyText.entryBlockHint(block, GamesBusyGame.rummy)?.let { Text(it, style = rowSubtitleStyle(), color = colors.pending) }
            PillButton(
                RummyPhoneText.playAgain,
                Modifier.testTag(GamesRummyResultTags.PLAY_AGAIN),
                kind = PillKind.Filled,
                size = PillSize.Lg,
                icon = AppIcon.Refresh,
                fillsWidth = true,
                // 잔액은 안 본다 — 로비 값은 정산 전 값이라 이긴 사람을 막을 수 있다(모자라면 서버가 말한다).
                enabled = !rummy.isWorking && block == null,
                onClick = { rummy.playAgain() },
            )
            Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                PillButton(
                    if (showsBoard) RummyPhoneText.ranks else RummyPhoneText.finalBoard,
                    Modifier.weight(1f).testTag(GamesRummyResultTags.BOARD_TOGGLE),
                    kind = PillKind.Gray,
                    icon = if (showsBoard) AppIcon.Checklist else AppIcon.GridOn,
                    fillsWidth = true,
                    onClick = { showsBoard = !showsBoard },
                )
                PillButton(
                    RummyPhoneText.toLobby,
                    Modifier.weight(1f).testTag(GamesRummyResultTags.TO_LOBBY),
                    kind = PillKind.Gray,
                    fillsWidth = true,
                    onClick = { rummy.dismissResult() },
                )
            }
        }
    }
}

/** 머리 카드 — 내 등수 · 끝난 까닭 · 내 루비 · [반응]. 큰 글자에서는 까닭과 루비를 아래로 내린다(한 줄에 두면 까닭이 글자 하나 폭으로 접힌다). */
@Composable
private fun ResultHeadline(rummy: RummyStore, match: RummyMatchState, rows: List<RummyMatchSeat>, now: () -> SwiftDate) {
    val colors = AingTheme.colors
    val mine = rows.firstOrNull { RummyResultSummary.isMe(it, match) }
    val winner = rows.firstOrNull { it.isWinner == true }
    val winnerIsMe = winner != null && winner === mine
    val title = mine?.let { RummyPhoneText.myResult(it.finalRank, it.state == RummySeatState.forfeit) } ?: RummyPhoneText.resultTitle
    val reason = RummyPhoneText.endReason(match.endReason, RummyResultSummary.winnerName(rows), winnerIsMe)
    val net = mine?.let { RummyResultSummary.net(it, match.stake) }
    val stacked = LocalDensity.current.fontScale >= 1.3f
    InsetGroup {
        Column(
            Modifier.padding(start = AingDimens.cardPadding, end = 6.dp, top = 10.dp, bottom = 10.dp).testTag(GamesRummyResultTags.HEADLINE),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space1),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                if (!stacked) {
                    AingIcon(
                        if (mine?.isWinner == true) AppIcon.TrophyFill else AppIcon.SportsScore, contentDescription = null, size = 22.dp,
                        tint = if (mine?.isWinner == true) colors.gold else colors.label2,
                    )
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = colors.label)
                    if (!stacked) Text(reason, style = rowSubtitleStyle(), color = colors.label2)
                }
                if (!stacked && net != null) RubyNet(net)
                GamesRummyReactionButton(rummy, now)
            }
            if (stacked) {
                Text(reason, style = rowSubtitleStyle(), color = colors.label2)
                if (net != null) RubyNet(net)
            }
        }
    }
}

/** 등수 줄 한 사람. 말풍선 앵커가 이 줄이다(맥 `.rummyReactionAnchor(seatNo:)`). */
@Composable
private fun ResultRow(seat: RummyMatchSeat, stake: Long?, isMe: Boolean, me: RummySeatFace) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.innerRadius)
    val winner = seat.isWinner == true
    val anchors = LocalGamesRummyReactionAnchors.current
    val name = seat.displayName ?: if (isMe) me.name else "?"
    Column(
        Modifier.fillMaxWidth()
            .rummyReactionAnchor(anchors, seat.seatNo)
            .testTag(GamesRummyResultTags.row(seat.seatNo))
            .clip(shape)
            .background(if (winner) colors.pendingTint else colors.surface, shape)
            .then(if (isMe) Modifier.border(2.dp, colors.accent.copy(alpha = 0.6f), shape) else Modifier)
            .padding(AingDimens.space3),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Row(
            Modifier.fillMaxWidth().semantics(mergeDescendants = true) { },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            Text(
                RummyPhoneText.rank(seat.finalRank),
                Modifier.width(40.dp),
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
                color = if (seat.finalRank == 1L) colors.pending else colors.label,
                maxLines = 1,
                softWrap = false,
            )
            PersonAvatar(
                name,
                seat.userId.lowercased,
                36.dp,
                url = seat.avatarUrl ?: if (isMe) me.avatarUrl else null,
                characterHint = seat.character ?: if (isMe) me.characterId else null,
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
                    Text(name, Modifier.weight(1f, fill = false), style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (winner) AingIcon(AppIcon.CrownFill, contentDescription = null, size = 16.dp, tint = colors.pending)
                    if (isMe) AingChip(RummyPhoneText.me, small = true)
                    if (seat.state == RummySeatState.forfeit) AingChip(RummyPhoneText.forfeit, tint = colors.danger, small = true)
                }
                Text(
                    RummyPhoneText.score(seat.finalScore),
                    style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM),
                    color = colors.label2,
                    maxLines = 1,
                )
            }
            RubyNet(RummyResultSummary.net(seat, stake))
        }
        RackLine(seat.finalRack ?: emptyList())
    }
}

/** 루비 순수익(+ 초록 · − 빨강 · 0 기본 글자). 루비 표시는 언제나 RubyIcon + 숫자다. */
@Composable
private fun RubyNet(net: Long) {
    val colors = AingTheme.colors
    val text = RummyPhoneText.net(net)
    Row(
        Modifier.semantics(mergeDescendants = true) { contentDescription = "루비 $text" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        RubyIcon(rememberRubyArt(18f), size = 18.dp, modifier = Modifier.alpha(if (net < 0) 0.5f else 1f))
        Text(
            text,
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            color = if (net > 0) colors.working else if (net < 0) colors.danger else colors.label,
            maxLines = 1,
            softWrap = false,
        )
    }
}

/** 남은 타일 — 전부 보인다(줄을 넘기면 다음 줄로). 빈 랙은 말하지 않는다(랙을 비운 사람). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RackLine(rack: List<RummyFace>) {
    if (rack.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
        Text(RummyPhoneText.remainingCount(rack.size), style = MaterialTheme.typography.labelSmall, color = AingTheme.colors.label2)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(RACK_TILE_GAP.dp),
            verticalArrangement = Arrangement.spacedBy(RACK_TILE_GAP.dp),
        ) {
            for (face in rack) GamesRummyTile(face, RummyResultSummary.rackTile)
        }
    }
}

private const val RACK_TILE_GAP: Int = 3

/**
 * 끝난 판 — 확정 묶음을 서버 배치 그대로. 읽기 전용(타일 입력 0). 판 화면 기본 보기처럼 높이에 맞추고 가로는 밀어 보며, [전체 보기]로 한눈에 본다.
 * 끌기·편집 장치가 필요 없는 판이라 판 화면 캔버스를 부르지 않고 RummyTableLayout 값으로 직접 그린다.
 */
@Composable
fun GamesRummyFinalBoard(sets: List<List<RummyFace>>, layout: RummyLayout?, modifier: Modifier = Modifier) {
    val tiles = remember(sets, layout) { RummyResultSummary.boardTiles(sets, layout) }
    var whole by remember { mutableStateOf(false) }
    BoxWithConstraints(modifier.testTag(GamesRummyResultTags.FINAL_BOARD)) {
        val viewWidth = maxWidth.value.toDouble()
        val viewHeight = maxHeight.value.toDouble()
        val board = RummyFinalBoardLayout.make(viewWidth, viewHeight, whole)
        val scroll = rememberScrollState()
        Box(
            Modifier.fillMaxSize().then(if (board.scrolls) Modifier.horizontalScroll(scroll) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.padding(horizontal = RummyFinalBoardLayout.inset.dp).size(board.width.dp, board.height.dp)) {
                GamesRummyTableSurface(Modifier.fillMaxSize())
                if (tiles.isEmpty()) {
                    // 펠트는 테마와 무관하게 어둡다 — 글자도 테마 토큰이 아니라 흰색이다.
                    Text(
                        RummyPhoneText.emptyBoard,
                        Modifier.align(Alignment.Center),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.75f),
                    )
                }
                val tileSize = board.tile
                for (tile in tiles) {
                    GamesRummyTile(
                        tile.face,
                        tileSize,
                        Modifier.offset((tile.x * board.scale).dp, (tile.y * board.scale).dp),
                    )
                }
            }
        }
        if (RummyFinalBoardLayout.canZoom(viewWidth, viewHeight)) {
            PillButton(
                if (whole) RummyPhoneText.zoomIn else RummyPhoneText.zoomOut,
                Modifier.align(Alignment.TopEnd).padding(end = AingDimens.space5).testTag(GamesRummyResultTags.BOARD_ZOOM),
                kind = PillKind.Gray,
                size = PillSize.Sm,
                onClick = { whole = !whole },
            )
        }
    }
}
