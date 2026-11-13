// 원본: Sources/CheckMobileKit/Games/GamesAlkkagiScreen.swift @ 928d5562(폰 1.0.18 — 로비 · 판 · 관전 · 연습 한 화면) — Android 판 8
//
// 화면 고르기: 내 판이 있으면 판 → 관전 중이면 관전 → 연습 중이면 연습 → 로비. 상태 · 판정은 코어 [AlkkagiOnlineStore].
// 수명은 직접 코어를 부르지 않는다 — 나타남 → GamesStore.alkkagiScreenDidAppear(), 사라짐 → …DidDisappear().
// Android 판돈 깃발(G §8-17 #1): 꺼진 빌드는 [도전] · 판돈 시트 · [수락]을 그리지 않는다(스토어도 막는다). 연습 · 관전 · 순위는 연다.
package com.yehsung.aingcheck.ui.games.alkkagi

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiAvailability
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiInvite
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiLobbyUser
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiNoticeText
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiOnlineStore
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneText
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiStake
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.rememberRubyArt
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
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil

object AlkkagiLobbyTags {
    const val LOBBY = "alkkagi.lobby"
    const val PRACTICE = "alkkagi.practiceButton"
    fun challenge(userID: String) = "alkkagi.challenge.$userID"
    fun accept(inviteID: String) = "alkkagi.accept.$inviteID"
    fun decline(inviteID: String) = "alkkagi.decline.$inviteID"
    fun watch(matchID: String) = "alkkagi.watch.$matchID"
    const val STAKE_SEND = "alkkagi.stake.send"
}

@Composable
fun GamesAlkkagiScreen(
    store: GamesStore,
    alkkagi: AlkkagiOnlineStore,
    myUserID: String?,
    myName: String?,
    refreshHz: Int,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    reduceMotion: Boolean = false,
) {
    DisposableEffect(store) {
        store.alkkagiScreenDidAppear()
        onDispose { store.alkkagiScreenDidDisappear() }
    }
    var stakeTarget by remember { mutableStateOf<AlkkagiLobbyUser?>(null) }
    var practicing by remember { mutableStateOf(false) }
    LaunchedEffect(alkkagi.state?.id) {
        if (alkkagi.state != null) {
            practicing = false
            stakeTarget = null
        }
    }
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background)) {
        val state = alkkagi.state
        val watched = alkkagi.watched
        when {
            state != null -> {
                GamesHeaderBar(AlkkagiPhoneText.title, onBack = onBack)
                GamesAlkkagiMatchView(alkkagi, state, myName, refreshHz, reduceMotion)
            }
            watched != null -> {
                GamesHeaderBar(AlkkagiPhoneText.title, onBack = onBack)
                GamesAlkkagiWatchView(alkkagi, watched, refreshHz, onLeave = { alkkagi.stopWatching() })
            }
            practicing -> {
                GamesHeaderBar(AlkkagiPhoneText.practiceTitle, onBack = { practicing = false })
                GamesAlkkagiPracticeView(refreshHz, reduceMotion, onExit = { practicing = false })
            }
            else -> {
                GamesHeaderBar(AlkkagiPhoneText.title, onBack = onBack)
                AlkkagiLobby(store, alkkagi, myUserID, onChallenge = { stakeTarget = it }, onPractice = { practicing = true })
            }
        }
    }
    stakeTarget?.let { target -> AlkkagiStakeSheet(store, alkkagi, target, onDismiss = { stakeTarget = null }) }
}

private fun availabilityLine(availability: AlkkagiAvailability): String? = when (availability) {
    AlkkagiAvailability.available -> null
    AlkkagiAvailability.updateRequired -> AlkkagiNoticeText.updateMine
    AlkkagiAvailability.serverMissing -> AlkkagiPhoneText.unavailable
}

@Composable
private fun AlkkagiLobby(store: GamesStore, alkkagi: AlkkagiOnlineStore, myUserID: String?, onChallenge: (AlkkagiLobbyUser) -> Unit, onPractice: () -> Unit) {
    val colors = AingTheme.colors
    val blockedBy = store.alkkagiEntryBlock
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
            .padding(top = AingDimens.space2, bottom = AingDimens.space6).testTag(AlkkagiLobbyTags.LOBBY),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Text(AlkkagiPhoneText.lobbyCaption, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
        alkkagi.notice?.takeIf { it != availabilityLine(alkkagi.availability) }?.let { InlineNotice(it, kind = NoticeKind.Info) }
        GamesBusyText.entryBlockNotice(blockedBy, GamesBusyGame.alkkagi)?.let { InlineNotice(it, kind = NoticeKind.Warning) }
        when (alkkagi.availability) {
            AlkkagiAvailability.available -> Unit
            AlkkagiAvailability.updateRequired -> InlineNotice(AlkkagiNoticeText.updateMine, kind = NoticeKind.Error)
            AlkkagiAvailability.serverMissing -> InlineNotice(AlkkagiPhoneText.unavailable, kind = NoticeKind.Info)
        }
        val incoming = alkkagi.visibleIncomingInvites
        if (incoming.isNotEmpty()) {
            SectionHeader(AlkkagiPhoneText.incomingTitle, padded = true)
            incoming.forEach { invite -> InsetGroup { InviteCard(store, alkkagi, invite) } }
        }
        alkkagi.outgoing?.let { sent ->
            SectionHeader(AlkkagiPhoneText.outgoingTitle, padded = true)
            InsetGroup { OutgoingRow(alkkagi, sent) }
        }
        SectionHeader(AlkkagiPhoneText.usersTitle, padded = true)
        InsetGroup { Users(alkkagi, blockedBy, onChallenge) }
        if (alkkagi.spectatorFeaturesEnabled) {
            SectionHeader(AlkkagiPhoneText.liveTitle, padded = true)
            InsetGroup {
                val live = alkkagi.liveMatches
                if (live.isEmpty()) {
                    GroupRow(dividerInset = null) { Text(AlkkagiPhoneText.noLive, style = MaterialTheme.typography.bodySmall, color = colors.label2) }
                } else {
                    live.forEachIndexed { index, match ->
                        GroupRow(dividerInset = if (index == live.size - 1) null else AingDimens.cardPadding, minHeight = 52.dp) {
                            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                Text(AlkkagiPhoneText.liveLine(match), style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(AlkkagiPhoneText.liveDetail(match), style = rowSubtitleStyle(), color = colors.label2)
                            }
                            PillButton(AlkkagiPhoneText.watch, Modifier.testTag(AlkkagiLobbyTags.watch(match.id)), kind = PillKind.Tinted, size = PillSize.Sm) {
                                alkkagi.watch(match.id)
                            }
                        }
                    }
                }
            }
        }
        SectionHeader(AlkkagiPhoneText.recordTitle, padded = true)
        InsetGroup {
            Column(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(AlkkagiPhoneText.record(alkkagi.record), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = TNUM), color = colors.label)
                Text(AlkkagiPhoneText.rulesTitle, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.label2)
                AlkkagiPhoneText.rulesLines.forEach { Text("· $it", style = MaterialTheme.typography.bodySmall, color = colors.label2) }
                PillButton(AlkkagiPhoneText.practiceButton, Modifier.testTag(AlkkagiLobbyTags.PRACTICE), kind = PillKind.Tinted, fillsWidth = true) { onPractice() }
                Text(AlkkagiPhoneText.practiceHelp, style = MaterialTheme.typography.labelSmall, color = colors.label2)
            }
        }
        Ranking(alkkagi, myUserID)
    }
}

@Composable
private fun Users(alkkagi: AlkkagiOnlineStore, blockedBy: GamesBusyGame?, onChallenge: (AlkkagiLobbyUser) -> Unit) {
    val colors = AingTheme.colors
    val users = alkkagi.visibleUsers
    if (users.isEmpty()) {
        GroupRow(dividerInset = null) {
            when {
                alkkagi.lobbyLoadFailed -> LoadFailureRow(AlkkagiPhoneText.usersLoadFailed) { alkkagi.scope.launch { alkkagi.refreshLobby() } }
                alkkagi.hasLoadedLobby -> Text(AlkkagiPhoneText.emptyUsers, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                else -> LoadingRow(AlkkagiPhoneText.loadingUsers)
            }
        }
        return
    }
    users.forEachIndexed { index, user ->
        val status = AlkkagiPhoneText.userStatus(user)
        val enabled = status.canChallenge && blockedBy == null && !alkkagi.isBusy && alkkagi.availability == AlkkagiAvailability.available
        GroupRow(dividerInset = if (index == users.size - 1) null else AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
            PersonAvatar(user.displayName, user.id, 36.dp, working = user.isWorking, url = user.avatarURL, characterHint = user.characterID)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                PersonName(AlkkagiPhoneText.displayName(user.displayName))
                Text(status.subtitle, style = rowSubtitleStyle(), color = colors.label2)
            }
            if (alkkagi.duelsEnabled) {
                PillButton(
                    AlkkagiPhoneText.challenge, Modifier.testTag(AlkkagiLobbyTags.challenge(user.id)),
                    kind = if (enabled) PillKind.Tinted else PillKind.Gray, size = PillSize.Sm, enabled = enabled,
                ) { onChallenge(user) }
            }
        }
    }
}

@Composable
private fun InviteCard(store: GamesStore, alkkagi: AlkkagiOnlineStore, invite: AlkkagiInvite) {
    val stake = invite.stake?.toInt()
    val canAccept = store.alkkagiEntryBlock == null && !alkkagi.isBusy && (stake == null || (store.rubyBalance?.let { it >= stake } ?: true))
    Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            PersonAvatar(invite.opponent.displayName, invite.opponent.id, 44.dp, url = invite.opponent.avatarURL, characterHint = invite.opponent.characterID)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                PersonName(AlkkagiPhoneText.incomingFrom(invite.opponent.displayName))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (stake != null) StakeLine(stake, prefix = AlkkagiPhoneText.stakeTitle, suffix = AlkkagiPhoneText.stakeGainSuffix(stake))
                    RemainingLeaf(alkkagi, invite.expiresAtMs)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PillButton(AlkkagiPhoneText.decline, Modifier.weight(1f).testTag(AlkkagiLobbyTags.decline(invite.id)), kind = PillKind.Gray, fillsWidth = true, enabled = !alkkagi.isBusy) {
                alkkagi.scope.launch { alkkagi.respond(invite.id, accept = false) }
            }
            if (alkkagi.duelsEnabled) {
                PillButton(AlkkagiPhoneText.accept, Modifier.weight(1f).testTag(AlkkagiLobbyTags.accept(invite.id)), kind = PillKind.Filled, fillsWidth = true, enabled = canAccept) {
                    alkkagi.scope.launch { alkkagi.respond(invite.id, accept = true) }
                }
            }
        }
    }
}

@Composable
private fun OutgoingRow(alkkagi: AlkkagiOnlineStore, invite: AlkkagiInvite) {
    val colors = AingTheme.colors
    GroupRow(dividerInset = null, minHeight = 56.dp) {
        PersonAvatar(invite.opponent.displayName, invite.opponent.id, 36.dp, url = invite.opponent.avatarURL, characterHint = invite.opponent.characterID)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(AlkkagiPhoneText.outgoingTo(invite.opponent.displayName), style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                invite.stake?.let { StakeLine(it.toInt(), prefix = AlkkagiPhoneText.stakeTitle) }
                RemainingLeaf(alkkagi, invite.expiresAtMs)
            }
        }
        PillButton(AlkkagiPhoneText.cancel, kind = PillKind.Gray, size = PillSize.Sm, enabled = !alkkagi.isBusy) { alkkagi.scope.launch { alkkagi.cancelChallenge() } }
    }
}

/** " · 42초 남음"(1초마다 — 서버 시계 보정 값으로 센다). */
@Composable
private fun RemainingLeaf(alkkagi: AlkkagiOnlineStore, expiresAtMs: Double) {
    fun seconds(): Int = ceil((expiresAtMs - alkkagi.estimatedServerNowMs) / 1000).toInt()
    var value by remember(expiresAtMs) { mutableIntStateOf(seconds()) }
    LaunchedEffect(expiresAtMs) {
        while (true) {
            value = seconds()
            delay(1000)
        }
    }
    Text(" · " + AlkkagiPhoneText.remaining(value), style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = AingTheme.colors.label2)
}

@Composable
private fun Ranking(alkkagi: AlkkagiOnlineStore, myUserID: String?) {
    val colors = AingTheme.colors
    LaunchedEffect(alkkagi) { alkkagi.refreshRanking() }
    SectionHeader(AlkkagiPhoneText.rankTitle, trailing = SectionTrailing.Label(AlkkagiPhoneText.rankHelp), padded = true)
    InsetGroup {
        val board = alkkagi.ranking
        when {
            alkkagi.rankingUnavailable -> GroupRow(dividerInset = null) { Text(AlkkagiPhoneText.rankSoon, style = MaterialTheme.typography.bodySmall, color = colors.label2) }
            board != null && board.entries.isNotEmpty() -> {
                val rows = board.entries.take(20)
                rows.forEachIndexed { index, entry ->
                    GroupRow(dividerInset = if (index == rows.size - 1) null else AingDimens.cardPadding, minHeight = 48.dp, isHighlighted = entry.id == myUserID?.lowercase()) {
                        Text("${entry.rank}", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = colors.label, modifier = Modifier.width(28.dp), textAlign = TextAlign.Center)
                        PersonAvatar(entry.displayName, entry.id, 28.dp, url = entry.avatarURL, characterHint = entry.characterID)
                        PersonName(AlkkagiPhoneText.displayName(entry.displayName), Modifier.weight(1f))
                        Text(AlkkagiPhoneText.points(entry.points), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = colors.label2)
                    }
                }
            }
            else -> GroupRow(dividerInset = null) {
                Text(if (board == null) AlkkagiPhoneText.rankLoading else AlkkagiPhoneText.rankEmpty, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
        }
    }
}

/** 판돈 고르기(3 · 5 · 10) → 도전. 잔액이 모자라는 칸은 흐리다(서버도 막는다). 고른 판돈은 스토어가 기억한다. */
@Composable
private fun AlkkagiStakeSheet(store: GamesStore, alkkagi: AlkkagiOnlineStore, target: AlkkagiLobbyUser, onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    var selected by remember(target.id) { mutableStateOf<AlkkagiStake?>(alkkagi.selectedStake) }
    val balance = store.rubyBalance
    GamesSheet(onDismiss) {
        GamesHeaderBar(AlkkagiPhoneText.stakeTitle, subtitle = AlkkagiPhoneText.stakePromptTitle(AlkkagiPhoneText.displayName(target.displayName)), onBack = onDismiss, backIcon = AppIcon.Close)
        Column(Modifier.padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2), verticalArrangement = Arrangement.spacedBy(AingDimens.space4)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AlkkagiStake.entries.forEach { stake ->
                    val affordable = balance?.let { it >= stake.rawValue } ?: true
                    val isSelected = selected == stake && affordable
                    val shape = RoundedCornerShape(AingDimens.tileRadius)
                    Box(
                        Modifier.weight(1f).heightIn(min = 72.dp).clip(shape).background(if (isSelected) colors.accentTint else colors.surface, shape)
                            .then(if (isSelected) Modifier.border(1.5.dp, colors.accent, shape) else Modifier)
                            .clickable(enabled = affordable && !alkkagi.isBusy, role = Role.Button) { selected = stake }
                            .semantics {
                                contentDescription = "판돈 ${stake.rawValue}"
                                this.selected = isSelected
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(Modifier.padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            RubyPrice(stake.rawValue.toLong(), isShort = !affordable, art = rememberRubyArt(16f), gemSize = 16.dp, fontSize = 20f)
                            Text("이기면 +${DuelFee.winnerNet(stake.rawValue)}", style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = TNUM), color = if (affordable) colors.label2 else colors.label3Text)
                        }
                    }
                }
            }
            if (balance != null && AlkkagiStake.entries.any { balance < it.rawValue }) Text(AlkkagiPhoneText.stakeShortfall, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            val stake = selected?.takeIf { s -> balance?.let { it >= s.rawValue } ?: true }
            PillButton(
                stake?.let { AlkkagiPhoneText.challengeWithStake(it.rawValue) } ?: AlkkagiPhoneText.stakePromptCaption,
                Modifier.testTag(AlkkagiLobbyTags.STAKE_SEND).padding(bottom = AingDimens.space3), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true,
                enabled = stake != null && store.alkkagiEntryBlock == null && !alkkagi.isBusy && alkkagi.duelsEnabled,
            ) {
                val chosen = stake ?: return@PillButton
                onDismiss()
                alkkagi.scope.launch { alkkagi.challenge(target.id, chosen) }
            }
        }
    }
}
