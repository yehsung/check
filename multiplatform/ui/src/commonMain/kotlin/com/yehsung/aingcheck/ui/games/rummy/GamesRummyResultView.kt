// 원본: Sources/check/RummyPanelResult.swift:19 (RummyResultView) · :100 (RummyResultRow) · :159 (RummyFinalBoard) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
//
// 결과 — 머리 줄 · 끝난 이유 · 등수 줄 · 단추(세로). [최종 판]은 펼친 동안만 가로다(설계서 §10.1 · 펼침 값은 GamesStore 가 쥔다). 판단은 값 쪽이다: 줄 순서·순수익·남은 타일 폭은 core RummyResultSummary,
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
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyResultSummary
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.dismissResult
import com.yehsung.aingcheck.core.stores.rummy.playAgain
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyFace
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
    const val BOARD_INPUT: String = "rummy.result.boardInput"
    const val BOARD_RANKS: String = "rummy.result.boardRanks"
    const val BOARD_LOBBY: String = "rummy.result.boardLobby"

    fun row(seatNo: Long?): String = "rummy.result.row.$seatNo"
}

/** 결과 — 등수 · 루비 순수익 · 남은 타일 · 끝난 이유 · [한 판 더] · [최종 판] · [나가기](`rummy.dismissResult` — 로비로). [onBack] 은 머리 줄 뒤로(화면을 떠난다). */
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
    showsBoard: Boolean = false,
    onShowBoard: (Boolean) -> Unit = {},
) {
    val match = rummy.match
    if (match != null && showsBoard) {
        GamesRummyFinalBoard(match, reduceMotion, onRanks = { onShowBoard(false) }, onLobby = { rummy.dismissResult() }, modifier = modifier)
        return
    }
    Column(modifier) {
        GamesHeaderBar(RummyPhoneText.resultTitle, onBack = onBack) { GamesRummyRulesButton(onRules, Modifier.testTag(GamesRummyResultTags.RULES)) }
        if (match != null) ResultBody(rummy, match, me, now, block, onShowBoard, Modifier.weight(1f))
    }
}

@Composable
private fun ResultBody(rummy: RummyStore, match: RummyMatchState, me: RummySeatFace, now: () -> SwiftDate, block: GamesBusyGame?, onShowBoard: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val rows = remember(match) { RummyResultSummary.rows(match) }
    Column(modifier.fillMaxWidth()) {
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(vertical = AingDimens.space2),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            ResultHeadline(rummy, match, rows, now)
            for (seat in rows) ResultRow(seat, match.stake, RummyResultSummary.isMe(seat, match), me)
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
                    RummyPhoneText.finalBoard,
                    Modifier.weight(1f).testTag(GamesRummyResultTags.BOARD_TOGGLE),
                    kind = PillKind.Gray,
                    icon = AppIcon.GridOn,
                    fillsWidth = true,
                    onClick = { onShowBoard(true) },
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
 * 끝난 판(가로) — 판 화면과 같은 칸을 읽기 전용으로 쓴다(보기 값 · 밀기 · 핀치 · [전체 보기] · 화면 밖 배지가 같다). 손은 판을 밀고 키울 뿐 타일을 집지 않는다.
 * 왼쪽은 판 전부, 오른쪽 열은 판 화면과 같은 폭이다. 전환 중 세로 크기로 불리면 판을 세우지 않고 안내만 그린다.
 */
@Composable
internal fun GamesRummyFinalBoard(match: RummyMatchState, reduceMotion: Boolean, onRanks: () -> Unit, onLobby: () -> Unit, modifier: Modifier = Modifier, model: GamesRummyMatchModel = remember(match.id) { GamesRummyMatchModel() }) {
    val scene = remember(match) { GamesRummyBoardScene.make(match, null, false, null) }
    BoxWithConstraints(modifier) {
        val whole = RummyCanvasSize(maxWidth.value.toDouble(), maxHeight.value.toDouble())
        SideEffect { model.screenSizeChanged(whole) }
        if (!GamesRummyMatchLayout.canStand(whole)) {
            GamesRummyRotatingView(onRanks)
            return@BoxWithConstraints
        }
        val tableSize = RummyCanvasSize(maxOf(0.0, whole.width - GamesRummyMatchLayout.rightColumnWidth), whole.height)
        SideEffect { model.tableSizeChanged(tableSize) }
        Row(Modifier.fillMaxSize().testTag(GamesRummyResultTags.FINAL_BOARD)) {
            Box(Modifier.width(tableSize.width.dp).fillMaxHeight().clipToBounds()) {
                GamesRummyTablePane(model, scene, editable = false, Modifier.fillMaxSize(), reduceMotion = reduceMotion)
                if (scene.melds.isEmpty()) {
                    // 펠트는 테마와 무관하게 어둡다 — 글자도 테마 토큰이 아니라 흰색이다.
                    Text(RummyPhoneText.emptyBoard, Modifier.align(Alignment.Center), style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.75f))
                }
                Box(Modifier.matchParentSize().rummyReadOnlyBoardInput(model).testTag(GamesRummyResultTags.BOARD_INPUT))
                GamesRummyTableControls(model, scene.layout.frames, reduceMotion, Modifier.fillMaxSize())
            }
            Column(
                Modifier.width(GamesRummyMatchLayout.rightColumnWidth.dp).fillMaxHeight().padding(GamesRummyMatchLayout.columnPadding.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(GamesRummyMatchLayout.actionGap.dp),
            ) {
                GamesRummyZoomButton(model, tag = GamesRummyResultTags.BOARD_ZOOM)
                Spacer(Modifier.weight(1f))
                GamesRummyCappedText(1.15f) {
                    PillButton(RummyPhoneText.ranks, Modifier.testTag(GamesRummyResultTags.BOARD_RANKS), kind = PillKind.Gray, fillsWidth = true, onClick = onRanks)
                    PillButton(RummyPhoneText.toLobby, Modifier.testTag(GamesRummyResultTags.BOARD_LOBBY), kind = PillKind.Gray, fillsWidth = true, onClick = onLobby)
                }
            }
        }
    }
}

/** 읽기 전용 판의 손 — 한 손가락은 밀기 · 두 손가락은 핀치. 시스템이 손을 거두면 핀치를 닫는다(안 닫으면 다음 핀치까지 밀기가 죽는다). */
private fun Modifier.rummyReadOnlyBoardInput(model: GamesRummyMatchModel): Modifier =
    pointerInput(model) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            down.consume()
            var magnification = 1.0
            var anchor: RummyCanvasPoint? = null
            var last = down.position
            try {
                while (true) {
                    val event = awaitPointerEvent()
                    val pressed = event.changes.count { it.pressed }
                    if (pressed == 0) break
                    if (pressed >= 2) {
                        val at = anchor ?: event.calculateCentroid(useCurrent = true).let { RummyCanvasPoint(it.x.toDouble() / density, it.y.toDouble() / density) }.also { anchor = it }
                        magnification *= event.calculateZoom().toDouble()
                        model.readOnlyPinch(magnification, at)
                    } else {
                        if (anchor != null) {
                            model.pinchEnded()
                            anchor = null
                            magnification = 1.0
                        }
                        val change = event.changes.firstOrNull { it.pressed }
                        if (change != null) {
                            if (change.id == down.id && change.positionChanged()) model.readOnlyPan(((change.position.x - last.x) / density).toDouble(), ((change.position.y - last.y) / density).toDouble())
                            last = change.position
                        }
                    }
                    event.changes.forEach { it.consume() }
                }
            } finally {
                model.pinchEnded()
            }
        }
    }
