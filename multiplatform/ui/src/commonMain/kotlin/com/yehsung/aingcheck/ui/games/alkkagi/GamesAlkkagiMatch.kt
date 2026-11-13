// 원본: Sources/CheckMobileKit/Games/GamesAlkkagiMatch.swift @ 928d5562(폰 1.0.18 — 판 · 연습 · 관전 · 결과 카드 · 배치 막대) — Android 판 8
package com.yehsung.aingcheck.ui.games.alkkagi

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiEndReason
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiMatch
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiNoticeText
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiOnlineStore
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiOutcome
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneText
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiWatchState
import com.yehsung.aingcheck.core.stores.alkkagi.GamesAlkkagiBoardModel
import com.yehsung.aingcheck.core.stores.alkkagi.endReason
import com.yehsung.aingcheck.core.stores.alkkagi.isFinished
import com.yehsung.aingcheck.core.stores.alkkagi.rules
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.core.wire.games.AlkkagiPeer
import com.yehsung.aingcheck.core.wire.games.AlkkagiPlayerWire
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.gomoku.GomokuBoardInk
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.StakeLine
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.max

object AlkkagiTags {
    const val MATCH = "alkkagi.match"
    const val PRACTICE = "alkkagi.practice"
    const val WATCH = "alkkagi.watch"
    const val RESIGN = "alkkagi.resign"
    const val READY = "alkkagi.ready"
    const val BACK_TO_LOBBY = "alkkagi.backToLobby"
}

/** 서버 판(배치 · 조준 · 굴림 · 결과). 판 그림 · 손짓은 [GamesAlkkagiBoardView], 판 값은 [GamesAlkkagiBoardModel]. */
@Composable
fun GamesAlkkagiMatchView(
    alkkagi: AlkkagiOnlineStore,
    state: AlkkagiMatch,
    myName: String?,
    refreshHz: Int,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val model = remember(alkkagi) { GamesAlkkagiBoardModel() }
    LaunchedEffect(alkkagi, model) { model.attachOnline(alkkagi) }
    var confirmingResign by remember { mutableStateOf(false) }
    val myColor = state.myColor.rules()
    val myPeer = if (state.myColor == AlkkagiPlayerWire.black) state.black else state.white
    val opponent = if (state.myColor == AlkkagiPlayerWire.black) state.white else state.black
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().testTag(AlkkagiTags.MATCH)) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            state.stake?.let { stake ->
                StakeLine(stake.toInt(), prefix = AlkkagiPhoneText.stakeTitle, suffix = AlkkagiPhoneText.stakeGainSuffix(stake.toInt()))
            }
            if (state.phase == AlkkagiMatchPhase.finished) GamesAlkkagiResultCard(alkkagi.outcome, alkkagi.endReason, alkkagi.rubyDelta)
            PlayerRow(opponent, null, myColor.opponent, detail(model, myColor.opponent, state, state.opponentMissedTurns), isTurn(myColor.opponent, state), alkkagi)
            GamesAlkkagiBoardView(model, if (state.phase == AlkkagiMatchPhase.placing) myColor else null, refreshHz, reduceMotion)
            PlayerRow(myPeer, myName, myColor, detail(model, myColor, state, state.myMissedTurns), isTurn(myColor, state), alkkagi)
            StatusLine(alkkagi, model, state)
            if (state.phase == AlkkagiMatchPhase.placing) GamesAlkkagiPlacementBar(model, state.myReady)
        }
        Row(
            Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (state.phase == AlkkagiMatchPhase.finished) {
                PillButton(AlkkagiPhoneText.backToLobby, Modifier.weight(1f).testTag(AlkkagiTags.BACK_TO_LOBBY), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true) {
                    alkkagi.backToLobby()
                }
            } else {
                Text(AlkkagiPhoneText.leaveKeepsMatch, style = MaterialTheme.typography.labelSmall, color = colors.label3Text, modifier = Modifier.weight(1f))
                PillButton(AlkkagiPhoneText.resign, Modifier.testTag(AlkkagiTags.RESIGN), kind = PillKind.Gray, size = PillSize.Sm, enabled = !alkkagi.isBusy) {
                    confirmingResign = true
                }
            }
        }
    }
    if (confirmingResign) {
        AlertDialog(
            onDismissRequest = { confirmingResign = false },
            title = { Text(AlkkagiPhoneText.resignWarning(state.stake?.toInt())) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingResign = false
                    alkkagi.scope.launch { alkkagi.resign() }
                }) { Text(AlkkagiPhoneText.confirmResign, color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmingResign = false }) { Text(AlkkagiPhoneText.keepPlaying) } },
        )
    }
}

private fun isTurn(player: AlkkagiGame.Player, state: AlkkagiMatch): Boolean = when (state.phase) {
    AlkkagiMatchPhase.placing -> if (player == state.myColor.rules()) !state.myReady else !state.opponentReady
    AlkkagiMatchPhase.aiming -> state.currentPlayer.rules() == player
    else -> false
}

private fun detail(model: GamesAlkkagiBoardModel, player: AlkkagiGame.Player, state: AlkkagiMatch, missed: Long?): String {
    val parts = mutableListOf(AlkkagiPhoneText.stoneTitle(player))
    if (state.phase == AlkkagiMatchPhase.placing) {
        val ready = if (player == state.myColor.rules()) state.myReady else state.opponentReady
        parts += if (ready) AlkkagiPhoneText.readyDone else "숨겨 놓는 중"
    } else {
        parts += AlkkagiPhoneText.stonesLeft(model.game.remaining(player))
    }
    if (missed != null && missed > 0) parts += AlkkagiPhoneText.missedLine(missed.toInt(), (state.forfeitAfter ?: 3).toInt())
    return parts.joinToString(" · ")
}

@Composable
private fun StatusLine(alkkagi: AlkkagiOnlineStore, model: GamesAlkkagiBoardModel, state: AlkkagiMatch) {
    val colors = AingTheme.colors
    val warning = alkkagi.missedTurnWarning?.let { AlkkagiNoticeText.missedTurn(it.first, it.second) }
    val (text, tint) = when {
        alkkagi.notice != null -> alkkagi.notice!! to colors.pending
        warning != null -> warning to colors.pending
        model.notice != null -> model.notice!! to colors.pending
        alkkagi.isMyTurn && state.phase != AlkkagiMatchPhase.finished -> model.status to colors.working
        else -> model.status to colors.label2
    }
    Row(Modifier.fillMaxWidth().heightIn(min = 22.dp).semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = tint, maxLines = 2, modifier = Modifier.weight(1f))
        if (model.selectedID != null) {
            Text(AlkkagiPhoneText.power(model.power), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = colors.accent)
        }
    }
}

/** 한 사람 줄 — 돌 표시 · 이름 · 돌 수/준비 · 차례면 남은 초. */
@Composable
private fun PlayerRow(peer: AlkkagiPeer, name: String?, color: AlkkagiGame.Player, detail: String, active: Boolean, store: AlkkagiOnlineStore?, deadlineMs: Double? = null) {
    val colors = AingTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).background(if (active) colors.accentTint else colors.surface, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp).semantics(mergeDescendants = true) { },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        PersonAvatar(peer.displayName, peer.id, 32.dp, url = peer.avatarURL, characterHint = peer.characterID)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(AlkkagiPhoneText.displayName(name ?: peer.displayName), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label, maxLines = 1)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                GamesAlkkagiStoneMark(color, 14.dp)
                Text(detail, style = MaterialTheme.typography.labelSmall, color = colors.label2, maxLines = 1)
            }
        }
        if (active && store != null) {
            ClockLeaf { if (deadlineMs != null) max(0.0, (deadlineMs - store.estimatedServerNowMs) / 1000) else store.remainingSeconds }
        }
    }
}

/** 남은 초(0.5초마다 — 잎만 다시 그린다). 5초 이하 빨강 · 10초 이하 주황. */
@Composable
private fun ClockLeaf(remaining: () -> Double) {
    var value by remember { mutableIntStateOf(ceil(max(0.0, remaining())).toInt()) }
    LaunchedEffect(Unit) {
        while (true) {
            value = ceil(max(0.0, remaining())).toInt()
            delay(500)
        }
    }
    val colors = AingTheme.colors
    val tint = if (value <= 5) colors.danger else if (value <= 10) colors.pending else colors.working
    Text("${value}초", style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = tint)
}

/** 흑 · 백 돌 표시(오목 돌 그림). */
@Composable
fun GamesAlkkagiStoneMark(player: AlkkagiGame.Player, size: androidx.compose.ui.unit.Dp = 26.dp) {
    Canvas(Modifier.size(size)) {
        GamesAlkkagiDrawing.disc(this, Offset(this.size.width / 2, this.size.height / 2), this.size.width * 0.45f, player)
    }
}

/** 숨겨 놓기 막대 — 놓을 돌 고르기 다섯 칸 · [배치 완료 n/5] · 도움 한 줄. */
@Composable
fun GamesAlkkagiPlacementBar(model: GamesAlkkagiBoardModel, ready: Boolean) {
    val colors = AingTheme.colors
    val game = model.game
    val mine = game.stones.filter { it.owner == game.currentPlayer }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            mine.forEach { stone ->
                Box(
                    Modifier.size(30.dp).border(2.dp, if (model.placementID == stone.id) colors.accent else Color.Transparent, CircleShape)
                        .clickable(role = Role.Button) { model.placementID = stone.id }
                        .semantics { contentDescription = "${AlkkagiPhoneText.stoneTitle(stone.owner)} ${stone.id % 5 + 1}번 돌 선택" },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(24.dp)) { GamesAlkkagiStoneMark(stone.owner, 24.dp) }
                    if (stone.isPlaced) Box(Modifier.size(6.dp).background(colors.working, CircleShape).align(Alignment.BottomEnd))
                }
            }
            Spacer(Modifier.weight(1f))
            val placed = game.placedCount(game.currentPlayer)
            PillButton(
                if (ready) AlkkagiPhoneText.readyDone else AlkkagiPhoneText.placementDone(placed), Modifier.testTag(AlkkagiTags.READY),
                kind = PillKind.Filled, size = PillSize.Sm, enabled = !ready && placed >= 5 && model.canInteract,
            ) { model.confirmPlacement() }
        }
        Text(
            if (model.isOnline) AlkkagiPhoneText.placingHelpOnline else AlkkagiPhoneText.placingHelpPractice,
            style = MaterialTheme.typography.labelSmall, color = colors.label2,
        )
    }
}

/** 결과 카드 — 결과 · 사유 · 루비. */
@Composable
fun GamesAlkkagiResultCard(outcome: AlkkagiOutcome?, reason: AlkkagiEndReason?, rubyDelta: Int?) {
    val colors = AingTheme.colors
    val tint = when (outcome) {
        AlkkagiOutcome.win -> colors.working
        AlkkagiOutcome.loss -> colors.danger
        else -> colors.label2
    }
    val reasonText = AlkkagiNoticeText.endReason(reason, outcome)
    Column(
        Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(12.dp).semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(AlkkagiPhoneText.outcomeTitle(outcome), style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = tint)
        if (reasonText.isNotEmpty()) Text(reasonText, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center)
        if (rubyDelta != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                RubyIcon(rememberRubyArt(16f), size = 16.dp)
                Text(
                    AlkkagiPhoneText.rubyLine(rubyDelta), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
                    color = if (rubyDelta > 0) colors.working else if (rubyDelta < 0) colors.danger else colors.label2,
                )
            }
        }
    }
}

/** 연습 판 — 한 폰에서 둘이 번갈아(루비 · 전적에 남지 않는다). */
@Composable
fun GamesAlkkagiPracticeView(refreshHz: Int, reduceMotion: Boolean, onExit: () -> Unit, modifier: Modifier = Modifier) {
    val model = remember { GamesAlkkagiBoardModel() }
    val game = model.game
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().testTag(AlkkagiTags.PRACTICE)) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            Text(AlkkagiPhoneText.practiceSubtitle, style = MaterialTheme.typography.labelSmall, color = colors.label2)
            PracticeRow(model, AlkkagiGame.Player.white)
            GamesAlkkagiBoardView(model, if (game.phase == AlkkagiGame.Phase.placing) game.currentPlayer else null, refreshHz, reduceMotion)
            PracticeRow(model, AlkkagiGame.Player.black)
            Row(Modifier.fillMaxWidth().heightIn(min = 22.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    model.notice ?: model.status, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    color = if (model.notice == null) colors.label2 else colors.pending, maxLines = 2, modifier = Modifier.weight(1f),
                )
                if (model.selectedID != null) {
                    Text(AlkkagiPhoneText.power(model.power), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = colors.accent)
                }
            }
            if (game.phase == AlkkagiGame.Phase.placing) GamesAlkkagiPlacementBar(model, false)
        }
        Row(
            Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            PillButton(AlkkagiPhoneText.backToLobby, Modifier.weight(1f), kind = PillKind.Gray, fillsWidth = true) { onExit() }
            PillButton(
                AlkkagiPhoneText.practiceRestart, Modifier.weight(1f), kind = if (game.phase == AlkkagiGame.Phase.finished) PillKind.Filled else PillKind.Tinted,
                fillsWidth = true,
            ) { model.restartPractice() }
        }
    }
}

@Composable
private fun PracticeRow(model: GamesAlkkagiBoardModel, player: AlkkagiGame.Player) {
    val colors = AingTheme.colors
    val game = model.game
    val active = (game.phase == AlkkagiGame.Phase.placing || game.phase == AlkkagiGame.Phase.aiming) && game.currentPlayer == player
    Row(
        Modifier.fillMaxWidth().height(40.dp).background(if (active) colors.accentTint else colors.surface, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp)
            .semantics(mergeDescendants = true) { },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        GamesAlkkagiStoneMark(player)
        Text(AlkkagiPhoneText.stoneTitle(player), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
        Text(AlkkagiPhoneText.stonesLeft(game.remaining(player)), style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = TNUM), color = colors.label2)
        Spacer(Modifier.weight(1f))
        if (active) ClockLeaf { model.remainingSeconds }
    }
}

/** 관전 판(입력 없음 · 3인칭 문장). */
@Composable
fun GamesAlkkagiWatchView(alkkagi: AlkkagiOnlineStore, watch: AlkkagiWatchState, refreshHz: Int, onLeave: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().testTag(AlkkagiTags.WATCH)) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            if (watch.isFinished) {
                Column(
                    Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(12.dp).semantics(mergeDescendants = true) { },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(AlkkagiPhoneText.watchOutcome(watch.result), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = colors.label)
                    val reason = AlkkagiPhoneText.watchEndReason(watch.endReason, watch.result)
                    if (reason.isNotEmpty()) Text(reason, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center)
                }
            }
            WatchRow(alkkagi, watch, AlkkagiGame.Player.white)
            GamesAlkkagiWatchBoard(alkkagi, watch, refreshHz)
            WatchRow(alkkagi, watch, AlkkagiGame.Player.black)
            Text(AlkkagiPhoneText.watchHeadline(watch), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.label2)
        }
        Row(Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2)) {
            PillButton(AlkkagiPhoneText.leaveWatch, Modifier.weight(1f), kind = PillKind.Gray, fillsWidth = true) { onLeave() }
        }
    }
}

@Composable
private fun WatchRow(alkkagi: AlkkagiOnlineStore, watch: AlkkagiWatchState, player: AlkkagiGame.Player) {
    val peer = if (player == AlkkagiGame.Player.black) watch.black else watch.white
    val ready = if (player == AlkkagiGame.Player.black) watch.blackReady else watch.whiteReady
    val active = if (watch.phase == AlkkagiMatchPhase.placing) !ready else (watch.phase == AlkkagiMatchPhase.aiming && watch.currentPlayer.rules() == player)
    val parts = mutableListOf(AlkkagiPhoneText.stoneTitle(player))
    parts += if (watch.phase == AlkkagiMatchPhase.placing) (if (ready) AlkkagiPhoneText.readyDone else "숨겨 놓는 중") else AlkkagiPhoneText.stonesLeft(AlkkagiPhoneText.remaining(watch.stones, player))
    PlayerRow(peer, null, player, parts.joinToString(" · "), active, alkkagi, if (active) watch.deadlineMs else null)
}
