// 원본: Sources/CheckMobileKit/Games/GamesCrossyDuelScreen.swift · GamesCrossyDuelMatch.swift @ 928d5562(폰 1.0.18) — Android 판 8
//
// 1:1 길건너 폰 화면 하나 — 로비(받은 신청 · 보낸 신청 · 상대 고르기 · 내 전적 · 규칙 · 순위) → 판(준비 · 카운트다운 · 달리기) → 결과.
// 관전은 없다(SPEC Q1). 상태 · 판정은 전부 코어 [CrossyDuelStore] 다. 이 파일은 그리기와 손짓만 한다.
// 수명은 직접 코어를 부르지 않는다 — 나타남 → GamesStore.crossyDuelScreenDidAppear(), 사라짐 → …DidDisappear() 뿐이다.
// Android 판돈 깃발(G §8-17 #1): 꺼진 빌드는 [신청] · 판돈 시트 · [수락]을 그리지 않는다(스토어도 같은 깃발로 요청을 막는다).
package com.yehsung.aingcheck.ui.games.crossy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelAvailability
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelEndReason
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelInvite
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelMatchState
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelNoticeText
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelOutcome
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelPhase
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelPhoneOverlay
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelPhoneText
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelRaceSnapshot
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelStake
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelStore
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelUser
import com.yehsung.aingcheck.core.stores.crossy.forward
import com.yehsung.aingcheck.core.stores.crossy.hop
import com.yehsung.aingcheck.core.stores.crossy.opponentGhost
import com.yehsung.aingcheck.core.stores.crossy.raceSnapshot
import com.yehsung.aingcheck.core.stores.crossy.refreshRanking
import com.yehsung.aingcheck.core.stores.crossy.tick
import com.yehsung.aingcheck.core.stores.games.CrossyGestureTracker
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.MiniGameFrameLoop
import com.yehsung.aingcheck.ui.games.minigame.crossy.CrossyCanvas
import com.yehsung.aingcheck.ui.games.minigame.kit.EmptyState
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesSheet
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InlineNotice
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadingRow
import com.yehsung.aingcheck.ui.games.minigame.kit.NoticeKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.StakeLine
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.games.minigame.rememberMiniGameArt
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.max

object CrossyDuelTags {
    const val LOBBY: String = "crossyDuel.lobby"
    const val MATCH: String = "crossyDuel.match"
    const val CANVAS: String = "crossyDuel.canvas"
    fun challenge(userID: String): String = "crossyDuel.challenge.$userID"
    fun accept(inviteID: String): String = "crossyDuel.accept.$inviteID"
    fun decline(inviteID: String): String = "crossyDuel.decline.$inviteID"
    const val STAKE_SEND: String = "crossyDuel.stake.send"
    fun stake(value: Int): String = "crossyDuel.stake.$value"
    const val RESIGN: String = "crossyDuel.resign"
    const val BACK_TO_LOBBY: String = "crossyDuel.backToLobby"
}

/**
 * 1:1 길건너 화면 — 코어 [CrossyDuelStore] 의 단계를 한 화면에서 갈아 끼운다. 수명 효과는 **스토어 하나에만** 묶는다(값이 흔들리는 상태를 키로
 * 걸지 않는다 — 효과가 다시 서면 DidDisappear 가 돌아 끝난 판이 접히고 준비 문이 닫힌다).
 */
@Composable
fun GamesCrossyDuelScreen(
    store: GamesStore,
    duel: CrossyDuelStore,
    myUserID: String?,
    refreshHz: Int,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    reduceMotion: Boolean = false,
) {
    DisposableEffect(store) {
        store.crossyDuelScreenDidAppear()
        onDispose { store.crossyDuelScreenDidDisappear() }
    }
    var stakeTarget by remember { mutableStateOf<CrossyDuelUser?>(null) }
    LaunchedEffect(duel.match?.id) { stakeTarget = null }
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background)) {
        GamesHeaderBar(CrossyDuelPhoneText.title, onBack = onBack)
        when (duel.phase) {
            CrossyDuelPhase.lobby -> CrossyDuelLobby(store, duel, myUserID, onChallenge = { stakeTarget = it })
            else -> GamesCrossyDuelMatchView(duel, refreshHz, reduceMotion, Modifier.fillMaxSize().testTag(CrossyDuelTags.MATCH))
        }
    }
    stakeTarget?.let { target -> CrossyDuelStakeSheet(store, duel, target, onDismiss = { stakeTarget = null }) }
}

// MARK: - 로비

@Composable
private fun CrossyDuelLobby(store: GamesStore, duel: CrossyDuelStore, myUserID: String?, onChallenge: (CrossyDuelUser) -> Unit) {
    val colors = AingTheme.colors
    val blockedBy = store.crossyDuelEntryBlock
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
            .padding(top = AingDimens.space2, bottom = AingDimens.space6).testTag(CrossyDuelTags.LOBBY),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Text(
            CrossyDuelPhoneText.lobbyCaption, style = MaterialTheme.typography.bodySmall, color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin),
        )
        duel.notice?.let { InlineNotice(it, kind = NoticeKind.Info) }
        GamesBusyText.entryBlockNotice(blockedBy, GamesBusyGame.crossyDuel)?.let { InlineNotice(it, kind = NoticeKind.Warning) }
        if (duel.availability != CrossyDuelAvailability.available) {
            InlineNotice(
                if (duel.availability == CrossyDuelAvailability.updateRequired) CrossyDuelPhoneText.needsUpdate else CrossyDuelNoticeText.checkConnection,
                kind = NoticeKind.Error,
            )
        }
        val incoming = duel.visibleIncomingInvites
        if (incoming.isNotEmpty()) {
            SectionHeader(CrossyDuelPhoneText.incomingTitle, padded = true)
            incoming.forEach { invite -> InsetGroup { CrossyDuelInviteCard(store, duel, invite) } }
        }
        duel.outgoing?.let { outgoing ->
            SectionHeader(CrossyDuelPhoneText.outgoingTitle, padded = true)
            InsetGroup { CrossyDuelOutgoingRow(duel, outgoing) }
        }
        SectionHeader(CrossyDuelPhoneText.usersTitle, padded = true)
        InsetGroup { CrossyDuelUsers(duel, blockedBy, onChallenge) }
        SectionHeader(CrossyDuelPhoneText.recordTitle, padded = true)
        InsetGroup {
            Column(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(CrossyDuelPhoneText.record(duel.record), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = TNUM), color = colors.label)
                Text(CrossyDuelPhoneText.howTitle, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.label2)
                CrossyDuelPhoneText.howLines.forEach { line ->
                    Text("· $line", style = MaterialTheme.typography.bodySmall, color = colors.label2)
                }
            }
        }
        CrossyDuelRankingSection(duel, myUserID)
    }
}

@Composable
private fun CrossyDuelUsers(duel: CrossyDuelStore, blockedBy: GamesBusyGame?, onChallenge: (CrossyDuelUser) -> Unit) {
    val colors = AingTheme.colors
    val users = duel.visibleUsers
    if (users.isEmpty()) {
        GroupRow(dividerInset = null) {
            when {
                duel.lobbyLoadFailed -> LoadFailureRow(CrossyDuelPhoneText.usersLoadFailed) { duel.scope.launch { duel.refreshLobby() } }
                duel.hasLoadedLobby -> Text(CrossyDuelPhoneText.emptyUsers, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                else -> LoadingRow(CrossyDuelPhoneText.loadingUsers)
            }
        }
        return
    }
    users.forEachIndexed { index, user ->
        val status = CrossyDuelPhoneText.userStatus(user)
        val enabled = status.canChallenge && blockedBy == null && duel.outgoing == null && !duel.isBusy &&
            duel.availability == CrossyDuelAvailability.available
        GroupRow(dividerInset = if (index == users.size - 1) null else AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
            PersonAvatar(user.displayName, user.id, 36.dp, working = user.isWorking, url = user.avatarURL, characterHint = user.characterID)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                PersonName(user.displayName)
                Text(status.subtitle, style = rowSubtitleStyle(), color = colors.label2)
            }
            if (duel.duelsEnabled) {
                PillButton(
                    CrossyDuelPhoneText.challenge, Modifier.testTag(CrossyDuelTags.challenge(user.id)),
                    kind = if (enabled) PillKind.Tinted else PillKind.Gray, size = PillSize.Sm, enabled = enabled,
                ) { onChallenge(user) }
            }
        }
    }
}

/** 받은 신청 한 장(수락 · 거절). 수락하면 판으로 넘어간다(코어가 phase 를 바꾼다). */
@Composable
private fun CrossyDuelInviteCard(store: GamesStore, duel: CrossyDuelStore, invite: CrossyDuelInvite) {
    val canAccept = store.crossyDuelEntryBlock == null && !duel.isBusy && (store.rubyBalance?.let { it >= invite.stake } ?: true)
    Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            PersonAvatar(invite.peer.displayName, invite.peer.id, 44.dp, url = invite.peer.avatarURL, characterHint = invite.peer.characterID)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                PersonName(CrossyDuelPhoneText.incomingFrom(invite.peer.displayName))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StakeLine(invite.stake, prefix = CrossyDuelPhoneText.stakeTitle, suffix = CrossyDuelPhoneText.stakeGainSuffix(invite.stake))
                    RemainingText(duel, invite.expiresAt)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PillButton(
                CrossyDuelPhoneText.decline, Modifier.weight(1f).testTag(CrossyDuelTags.decline(invite.id)), kind = PillKind.Gray, fillsWidth = true,
                enabled = !duel.isBusy,
            ) { duel.scope.launch { duel.respond(invite.id, accept = false) } }
            if (duel.duelsEnabled) {
                PillButton(
                    CrossyDuelPhoneText.accept, Modifier.weight(1f).testTag(CrossyDuelTags.accept(invite.id)), kind = PillKind.Filled, fillsWidth = true,
                    enabled = canAccept,
                ) { duel.scope.launch { duel.respond(invite.id, accept = true) } }
            }
        }
    }
}

/** 보낸 신청 한 줄(취소). */
@Composable
private fun CrossyDuelOutgoingRow(duel: CrossyDuelStore, invite: CrossyDuelInvite) {
    val colors = AingTheme.colors
    GroupRow(dividerInset = null, minHeight = 56.dp) {
        PersonAvatar(invite.peer.displayName, invite.peer.id, 36.dp, url = invite.peer.avatarURL, characterHint = invite.peer.characterID)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(CrossyDuelPhoneText.outgoingTo(invite.peer.displayName), style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                StakeLine(invite.stake, prefix = CrossyDuelPhoneText.stakeTitle)
                RemainingText(duel, invite.expiresAt)
            }
        }
        PillButton(CrossyDuelPhoneText.cancel, kind = PillKind.Gray, size = PillSize.Sm, enabled = !duel.isBusy) {
            duel.scope.launch { duel.cancelChallenge() }
        }
    }
}

/** " · 42초 남음"(1초마다 — 잎만 다시 그린다). */
@Composable
private fun RemainingText(duel: CrossyDuelStore, expiresAt: SwiftDate) {
    fun seconds(): Int = ceil(expiresAt.timeIntervalSince(duel.clock())).toInt()
    var remaining by remember(expiresAt) { mutableIntStateOf(seconds()) }
    LaunchedEffect(expiresAt) {
        while (true) {
            remaining = seconds()
            delay(1000)
        }
    }
    Text(" · " + CrossyDuelPhoneText.remaining(remaining), style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = AingTheme.colors.label2)
}

// MARK: - 판돈 시트

/** 판돈 고르기(3 · 5 · 10) → 신청. 잔액이 모자라는 칸은 흐리다(서버도 막는다). */
@Composable
private fun CrossyDuelStakeSheet(store: GamesStore, duel: CrossyDuelStore, target: CrossyDuelUser, onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    var selected by remember(target.id) { mutableStateOf<CrossyDuelStake?>(null) }
    val balance = store.rubyBalance
    GamesSheet(onDismiss) {
        GamesHeaderBar(CrossyDuelPhoneText.stakeTitle, subtitle = CrossyDuelPhoneText.stakePromptTitle(target.displayName), onBack = onDismiss, backIcon = AppIcon.Close)
        Column(Modifier.padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2), verticalArrangement = Arrangement.spacedBy(AingDimens.space4)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CrossyDuelStake.entries.forEach { stake ->
                    val affordable = balance?.let { it >= stake.rawValue } ?: true
                    val isSelected = selected == stake
                    val shape = RoundedCornerShape(AingDimens.tileRadius)
                    Box(
                        Modifier.weight(1f).heightIn(min = 72.dp).clip(shape).background(if (isSelected) colors.accentTint else colors.surface, shape)
                            .then(if (isSelected) Modifier.border(1.5.dp, colors.accent, shape) else Modifier)
                            .clickable(enabled = affordable && !duel.isBusy, role = Role.Button) { selected = stake }
                            .semantics {
                                contentDescription = "판돈 ${stake.rawValue}"
                                this.selected = isSelected
                            }
                            .testTag(CrossyDuelTags.stake(stake.rawValue)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(Modifier.padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            RubyPrice(stake.rawValue.toLong(), isShort = !affordable, art = rememberRubyArt(16f), gemSize = 16.dp, fontSize = 20f)
                            Text(
                                "이기면 +${DuelFee.winnerNet(stake.rawValue)}",
                                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal, fontFeatureSettings = TNUM),
                                color = if (affordable) colors.label2 else colors.label3Text,
                            )
                        }
                    }
                }
            }
            if (balance != null && CrossyDuelStake.entries.any { balance < it.rawValue }) {
                Text(CrossyDuelPhoneText.stakeShortfall, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
            PillButton(
                selected?.let { CrossyDuelPhoneText.challengeWithStake(it.rawValue) } ?: CrossyDuelPhoneText.stakePromptCaption,
                Modifier.testTag(CrossyDuelTags.STAKE_SEND).padding(bottom = AingDimens.space3), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true,
                enabled = selected != null && store.crossyDuelEntryBlock == null && !duel.isBusy && duel.duelsEnabled,
            ) {
                val stake = selected ?: return@PillButton
                onDismiss()
                // 스토어 범위로 띄운다 — onDismiss 가 이 시트를 컴포지션에서 빼므로 시트 범위면 응답 전에 취소된다.
                duel.scope.launch { duel.challenge(target.id, stake) }
            }
        }
    }
}

// MARK: - 순위

/** 순위(승점 = 승 − 패) — 맥 · 아이폰과 같은 서버(`crossy_duel_ranking`). 위 20줄. */
@Composable
private fun CrossyDuelRankingSection(duel: CrossyDuelStore, myUserID: String?) {
    val colors = AingTheme.colors
    LaunchedEffect(duel) { duel.refreshRanking() }
    SectionHeader(CrossyDuelPhoneText.rankTitle, trailing = SectionTrailing.Label(CrossyDuelPhoneText.rankHelp), padded = true)
    InsetGroup {
        val board = duel.ranking
        if (board != null && board.entries.isNotEmpty()) {
            val rows = board.entries.take(20)
            rows.forEachIndexed { index, entry ->
                GroupRow(dividerInset = if (index == rows.size - 1) null else AingDimens.cardPadding, minHeight = 48.dp, isHighlighted = entry.id == myUserID?.lowercase()) {
                    Text(
                        "${entry.rank}", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
                        color = colors.label, modifier = Modifier.width(28.dp), textAlign = TextAlign.Center,
                    )
                    PersonAvatar(entry.user.displayName, entry.user.id, 28.dp, url = entry.user.avatarURL, characterHint = entry.user.characterID)
                    PersonName(entry.user.displayName, Modifier.weight(1f))
                    Text(
                        CrossyDuelPhoneText.points(entry.points),
                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = colors.label2,
                    )
                }
            }
        } else {
            GroupRow(dividerInset = null) {
                Text(
                    if (board == null) CrossyDuelPhoneText.rankLoading else CrossyDuelPhoneText.rankEmpty,
                    style = MaterialTheme.typography.bodySmall, color = colors.label2,
                )
            }
        }
    }
}

// MARK: - 판

/**
 * 판 화면. 판 루프는 코어가 돌리고(창과 무관 — 0.05초), 이 화면은 프레임마다 `tick()` 을 더 자주 부를 뿐이다(같은 시각이면 멱등).
 * 쓸기 = 그 방향 한 칸(떼기를 기다리지 않는다) · 짧은 탭 = 앞으로 한 칸 — 혼자 하는 길건너와 같은 손짓([CrossyGestureTracker]).
 * 겹(결과 > 판정 기다림 > 부활 > 카운트다운)은 [CrossyDuelPhoneOverlay] 한 곳이 정한다.
 */
@Composable
fun GamesCrossyDuelMatchView(duel: CrossyDuelStore, refreshHz: Int, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val phase = duel.phase
    val live = phase == CrossyDuelPhase.countdown || phase == CrossyDuelPhase.playing
    // 판 값은 관찰 대상이 아니다 — 프레임마다 이 칸을 올려 머리 · 판 · 겹을 다시 그린다(끝나면 멈춘다).
    var frame by remember { mutableLongStateOf(0L) }
    MiniGameFrameLoop(running = live, refreshHz = refreshHz) {
        duel.tick()
        frame += 1
    }
    var confirmingResign by remember { mutableStateOf(false) }
    @Suppress("UNUSED_VARIABLE") val redraw = frame
    val snapshot = duel.raceSnapshot()
    Column(
        modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space3),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
    ) {
        MatchHeader(duel, snapshot)
        Box(
            Modifier.fillMaxWidth().aspectRatio(0.8f).clip(RoundedCornerShape(14.dp)).testTag(CrossyDuelTags.CANVAS)
                .then(if (phase == CrossyDuelPhase.playing) Modifier.crossyDuelGesture(duel) else Modifier)
                .clearAndSetSemantics {
                    contentDescription = CrossyDuelPhoneText.touchLine
                    customActions = listOf(CustomAccessibilityAction(CrossyDuelPhoneText.forwardAction) { duel.forward(); true })
                },
        ) {
            MatchCanvas(duel, phase, reduceMotion)
            MatchOverlay(duel, phase, snapshot)
        }
        MatchFooter(duel, phase, snapshot, onResign = { confirmingResign = true })
    }
    if (confirmingResign) {
        AlertDialog(
            onDismissRequest = { confirmingResign = false },
            title = { Text(CrossyDuelPhoneText.resignWarning) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingResign = false
                    duel.scope.launch { duel.resign() }
                }) { Text(CrossyDuelPhoneText.confirmResign, color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmingResign = false }) { Text(CrossyDuelPhoneText.keepPlaying) } },
        )
    }
}

/** 머리 — 내 점수 · 목표와 남은 시간 · 상대 점수, 경주 띠, 죽은 횟수 · 연결 확인. */
@Composable
private fun MatchHeader(duel: CrossyDuelStore, snapshot: CrossyDuelRaceSnapshot?) {
    val colors = AingTheme.colors
    val match = duel.match
    val name = match?.opponent?.displayName?.takeIf { it.isNotEmpty() } ?: CrossyDuelPhoneText.opponentTitle
    val score = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TNUM)
    Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(CrossyDuelPhoneText.me, style = MaterialTheme.typography.labelSmall, color = colors.label2)
                Text("${snapshot?.myScore ?: match?.myServerScore ?: 0}", style = score, color = colors.label)
            }
            Spacer(Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(CrossyDuelPhoneText.goalLine(snapshot?.goal ?: 100), style = MaterialTheme.typography.labelSmall, color = colors.label2)
                snapshot?.remaining?.let {
                    Text(CrossyDuelPhoneText.clock(it), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = TNUM), color = colors.label)
                }
            }
            Spacer(Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(name, style = MaterialTheme.typography.labelSmall, color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${snapshot?.opponentScore ?: match?.opponentScore ?: 0}", style = score, color = colors.label2)
            }
        }
        if (snapshot != null) {
            RaceBar(snapshot.myScore, snapshot.opponentScore, snapshot.goal)
            Row {
                Text(CrossyDuelPhoneText.deathsLine(snapshot.myDeaths, snapshot.opponentDeaths), style = MaterialTheme.typography.labelSmall, color = colors.label2)
                Spacer(Modifier.weight(1f))
                if (snapshot.opponentQuiet || duel.connectionTrouble) {
                    Text(CrossyDuelPhoneText.opponentQuiet, style = MaterialTheme.typography.labelSmall, color = colors.label2)
                }
            }
        }
    }
}

/** 경주 띠 — 두 사람이 목표(100점)까지 어디쯤인지(한 줄 두 점). */
@Composable
private fun RaceBar(my: Int, opponent: Int, goal: Int) {
    val colors = AingTheme.colors
    Canvas(Modifier.fillMaxWidth().height(14.dp).clearAndSetSemantics { }) {
        val g = max(1, goal).toFloat()
        fun fraction(score: Int) = (score.coerceIn(0, max(1, goal)) / g)
        val trackH = 6.dp.toPx()
        drawRoundRect(colors.fill, Offset(0f, (size.height - trackH) / 2), Size(size.width, trackH), CornerRadius(trackH / 2))
        val r1 = 6.dp.toPx()
        drawCircle(colors.label2, r1, Offset((fraction(opponent) * size.width).coerceIn(r1, size.width - r1), size.height / 2))
        val r2 = 7.dp.toPx()
        drawCircle(colors.accent, r2, Offset((fraction(my) * size.width).coerceIn(r2, size.width - r2), size.height / 2))
    }
}

@Composable
private fun MatchCanvas(duel: CrossyDuelStore, phase: CrossyDuelPhase, reduceMotion: Boolean) {
    val match = duel.match
    if ((phase == CrossyDuelPhase.countdown || phase == CrossyDuelPhase.playing || phase == CrossyDuelPhase.finished) && match != null) {
        val game = duel.duel?.game ?: remember(match.id) { CrossyGame(maxOf(0L, match.seed ?: 0L).toULong(), CrossyGame.Rules.duel) }
        CrossyCanvas(
            game, bestScore = 0, reduceMotion = reduceMotion, art = rememberMiniGameArt(), modifier = Modifier.fillMaxSize(),
            touchControls = true, ghost = duel.opponentGhost, soloChrome = false,
        )
    } else {
        Box(Modifier.fillMaxSize().background(Color(0xFF5C9E54)), contentAlignment = Alignment.Center) {
            Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(CrossyDuelPhoneText.waitingTitle, style = MaterialTheme.typography.titleMedium, color = Color.White, textAlign = TextAlign.Center)
                match?.readyDeadline?.let { deadline -> WaitingSeconds(duel, deadline) }
                if (duel.playingElsewhere) {
                    Text(CrossyDuelPhoneText.otherDeviceSubtitle, style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun WaitingSeconds(duel: CrossyDuelStore, deadline: SwiftDate) {
    fun seconds(): Int = max(0, ceil(deadline.timeIntervalSince(duel.clock())).toInt())
    var value by remember(deadline) { mutableIntStateOf(seconds()) }
    LaunchedEffect(deadline) {
        while (true) {
            value = seconds()
            delay(1000)
        }
    }
    Text(
        CrossyDuelPhoneText.waitingSubtitle(value), style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = TNUM),
        color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center,
    )
}

@Composable
private fun MatchOverlay(duel: CrossyDuelStore, phase: CrossyDuelPhase, snapshot: CrossyDuelRaceSnapshot?) {
    val match = duel.match
    when (val overlay = CrossyDuelPhoneOverlay.resolve(phase, match?.isFinished ?: false, match?.outcome, snapshot)) {
        is CrossyDuelPhoneOverlay.Countdown, is CrossyDuelPhoneOverlay.Respawn -> {
            val digit = (overlay as? CrossyDuelPhoneOverlay.Countdown)?.digit ?: (overlay as CrossyDuelPhoneOverlay.Respawn).digit
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(digit, style = MaterialTheme.typography.displayLarge.copy(fontSize = 64.sp, fontWeight = FontWeight.ExtraBold), color = Color.White)
            }
        }
        is CrossyDuelPhoneOverlay.Waiting -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                if (overlay.goal) CrossyDuelPhoneText.goalWaiting else CrossyDuelPhoneText.timeWaiting,
                style = MaterialTheme.typography.titleMedium, color = Color.White,
                modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(50)).padding(12.dp),
            )
        }
        is CrossyDuelPhoneOverlay.Result -> if (match != null) {
            Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) { ResultCard(duel, match) }
        }
        null -> Unit
    }
}

/** 결과 카드(맥 `CrossyDuelResultCard` 와 같은 내용). */
@Composable
private fun ResultCard(duel: CrossyDuelStore, match: CrossyDuelMatchState) {
    val colors = AingTheme.colors
    val delta = CrossyDuelPhoneText.rubyDelta(match)
    val tint = when (match.outcome) {
        CrossyDuelOutcome.win -> colors.working
        CrossyDuelOutcome.loss -> colors.danger
        else -> colors.label2
    }
    val reason = CrossyDuelNoticeText.endReason(match.endReason, match.outcome, match.meReady, match.opponentReady)
    Column(
        Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(16.dp).semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(CrossyDuelPhoneText.outcomeTitle(match.outcome), style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold), color = tint)
        if (reason.isNotEmpty()) Text(reason, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center)
        if (match.endReason != CrossyDuelEndReason.noShow) {
            Text(
                CrossyDuelPhoneText.finalScoreLine(match.finalMyScore ?: duel.duel?.game?.score ?: match.myServerScore, match.finalOpponentScore ?: match.opponentScore),
                style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = TNUM), color = colors.label,
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            RubyIcon(rememberRubyArt(16f), size = 16.dp)
            Text(
                CrossyDuelPhoneText.rubyLine(delta),
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
                color = if (delta > 0) colors.working else if (delta < 0) colors.danger else colors.label2,
            )
        }
    }
}

/** 아래 — 결과면 [로비로], 판 중이면 조작 안내 + [기권]. */
@Composable
private fun MatchFooter(duel: CrossyDuelStore, phase: CrossyDuelPhase, snapshot: CrossyDuelRaceSnapshot?, onResign: () -> Unit) {
    val colors = AingTheme.colors
    when (phase) {
        CrossyDuelPhase.finished -> PillButton(
            CrossyDuelPhoneText.backToLobby, Modifier.testTag(CrossyDuelTags.BACK_TO_LOBBY), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true,
        ) { duel.backToLobby() }
        CrossyDuelPhase.playing, CrossyDuelPhase.countdown -> Row(verticalAlignment = Alignment.CenterVertically) {
            Text(CrossyDuelPhoneText.touchLine, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            PillButton(
                CrossyDuelPhoneText.resign, Modifier.testTag(CrossyDuelTags.RESIGN), kind = PillKind.Gray, size = PillSize.Sm,
                enabled = !duel.isBusy && snapshot?.waitingForResult != true,
            ) { onResign() }
        }
        else -> Unit
    }
}

/** 손짓 — 쓸기 = 그 방향 한 칸(떼기를 기다리지 않는다) · 짧은 탭 = 앞으로 한 칸(혼자 하는 길건너와 같은 트래커). */
private fun Modifier.crossyDuelGesture(duel: CrossyDuelStore): Modifier = pointerInput(duel) {
    val tracker = CrossyGestureTracker()
    val density = density
    fun toPoints(px: Float): Double = px / density.toDouble()
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val start = MiniGamePoint(toPoints(down.position.x), toPoints(down.position.y))
        val startMillis = down.uptimeMillis
        down.consume()
        tracker.drag(start, MiniGameSize(0.0, 0.0))?.let { duel.hop(it) }
        var last = MiniGameSize(0.0, 0.0)
        var lastMillis = startMillis
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            last = MiniGameSize(toPoints(change.position.x) - start.x, toPoints(change.position.y) - start.y)
            lastMillis = change.uptimeMillis
            if (!change.pressed) break
            change.consume()
            tracker.drag(start, last)?.let { duel.hop(it) }
        }
        if (tracker.end(last, (lastMillis - startMillis) / 1000.0)) duel.forward()
    }
}
