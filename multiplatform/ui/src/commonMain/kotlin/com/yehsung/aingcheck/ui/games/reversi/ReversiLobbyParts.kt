// 원본: Sources/CheckMobileKit/Games/GamesReversiLobby.swift:131-528(상대 한 줄 · 받은 신청 카드 · 보낸 신청 줄 · 남은 초 · 판 위 받은 신청 띠 · 판돈 시트) @ ios-1017-int 3e5051ed
//
// 폰 아잉 뒤집기 **로비 조각**. 로비 스크롤 자체(절의 순서)는 [ReversiLobby] 가 쥔다. 본은 폰 체스·1:1 테트리스의 같은 이름 조각이고 아잉 뒤집기에서 달라지는 자리만
// 바꿨다(iOS 와 같다): 받은 신청이 **여럿** · 막힌 [도전]의 까닭이 셋(옛 버전 · 대결 중 · 집중) · 로봇 연습 판이 로비를 덮는 동안 온 신청은 판 위 띠로 세우고
// [수락]은 두던 로봇 판을 끝내므로 **먼저 묻는다**. 판정은 core/stores(`GamesReversiChallengeGate` · `GamesReversiRespond` · `GamesReversiStakeSend`) 하나다.
// 큰 글자(글꼴 배율 1.3 이상 — iOS `isAccessibilitySize` 자리)에서는 단추를 글 아래 줄로 내린다(한 줄에 두면 이름이 글자 하나씩 꺾인다 — 오목·체스 실측).
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiChallengeGate
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiInviteBanner
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiRespond
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiStakeSend
import com.yehsung.aingcheck.core.stores.reversi.ReversiInvite
import com.yehsung.aingcheck.core.stores.reversi.ReversiOutgoing
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStake
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.send
import com.yehsung.aingcheck.core.stores.reversi.toggled
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardRuby
import com.yehsung.aingcheck.ui.games.gomoku.BoardSheetOverlay
import com.yehsung.aingcheck.ui.games.gomoku.BoardStakeLine
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.rememberTicker
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 큰 글자인가(iOS `dynamicTypeSize.isAccessibilitySize` 자리 — 글꼴 배율 1.3 이상). 게임 탭 타일과 같은 문턱. */
@Composable
internal fun reversiLargeFont(): Boolean = LocalDensity.current.fontScale >= 1.3f

// MARK: - 상대 한 줄

/**
 * 상대 한 줄(폰 체스·테트리스 줄과 같은 모양): 아바타(근무 중 점) · 이름 + 센터 · 부제(근무 축 + 버튼이 못 말한 까닭) · 오른쪽 [도전] 틴트(막혔으면 까닭 글자의
 * 회색 비활성). 판정은 `GamesReversiChallengeGate` 하나, 글자는 `ReversiPhoneText.opponentRow` 하나다. 판돈 깃발이 꺼진 빌드는 단추 자리를 비운다(§8-17 #1).
 */
@Composable
internal fun ReversiOpponentRow(games: GamesStore, reversi: ReversiStore, user: ReversiUser, isLast: Boolean, onChallenge: (ReversiUser) -> Unit) {
    val colors = AingTheme.colors
    val lines = ReversiPhoneText.opponentRow(user)
    val canChallenge = GamesReversiChallengeGate.isEnabled(user, reversi, games.reversiEntryBlock)
    val avatar: @Composable () -> Unit = {
        BoardAvatar(user.displayName, user.id, 36.dp, working = user.isWorking, url = user.avatarURL, characterHint = user.characterID)
    }
    val info: @Composable (Modifier) -> Unit = { m ->
        Column(m.semantics(mergeDescendants = true) {}) {
            BoardPersonName(user.displayName, center = user.center)
            Text(lines.subtitle, style = BoardText.rowSubtitle(), color = colors.label2)
        }
    }
    val button: @Composable () -> Unit = {
        if (!reversi.duelsLocked) {
            if (canChallenge) {
                BoardButton(ReversiPhoneText.challenge, kind = BoardButtonKind.Tinted, small = true, testTag = ReversiScreenTags.challenge(user.id),
                    hint = ReversiPhoneText.challengeHint(user.displayName)) { onChallenge(user) }
            } else {
                // 상대 쪽 까닭이 없으면(내 쪽 막힘 — 다른 게임 판 · 보낸 신청 · 요청 중) 버튼은 '도전' 그대로 흐려진다. 내 쪽 까닭은 로비 위 안내 줄이 말한다.
                BoardButton(lines.buttonTitle, kind = BoardButtonKind.Gray, small = true, enabled = false, testTag = ReversiScreenTags.challenge(user.id)) {}
            }
        }
    }
    BoardRow(divider = !isLast, dividerInset = AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
        if (reversiLargeFont()) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically) {
                    avatar()
                    info(Modifier.weight(1f))
                }
                button()
            }
        } else {
            avatar()
            info(Modifier.weight(1f))
            button()
        }
    }
}

// MARK: - 받은 신청 · 보낸 신청

/**
 * 받은 신청 한 건: 아바타 44 · "솜사탕님의 신청" + 센터 · 판돈 줄 + 남은 초 · [거절 회색] [수락 채움].
 * ★ 수락이 **루비가 실제로 빠지는 순간**이다(신청만 받은 상태에서는 0원도 안 움직인다). [수락]은 화면 루트로 올린다(로봇 판 확인의 주인이 루트다).
 * [bannerTitle] 이 있으면 판 위 띠 모양(머리 글자만 띠 문장), [more] 는 띠에 못 실은 나머지 신청 수.
 */
@Composable
internal fun ReversiInviteCard(games: GamesStore, reversi: ReversiStore, invite: ReversiInvite, bannerTitle: String? = null, more: Int = 0, onAccept: (ReversiInvite) -> Unit) {
    val colors = AingTheme.colors
    val large = reversiLargeFont()
    val header: @Composable (Modifier) -> Unit = { m ->
        Column(m.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            if (bannerTitle != null) {
                Text(bannerTitle, style = BoardText.rowTitle(), color = colors.label)
            } else {
                BoardPersonName(ReversiPhoneText.incomingTitle(invite.peer.displayName), center = invite.peer.center)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                BoardStakeLine(invite.stake.toLong(), prefix = ReversiPhoneText.stakeTitle, suffix = ReversiPhoneText.stakeGainSuffix(invite.stake))
                ReversiRemainingText(reversi, invite.expiresAt, prefix = " · ")
                if (more > 0) Text(" · " + ReversiPhoneText.incomingMore(more), style = BoardText.rowSubtitle(), color = colors.label2)
            }
        }
    }
    val avatar: @Composable () -> Unit = {
        BoardAvatar(invite.peer.displayName, invite.peer.id, 44.dp, working = invite.peer.isWorking, url = invite.peer.avatarURL, characterHint = invite.peer.characterID)
    }
    if (large) {
        Column(Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, top = 14.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            avatar()
            header(Modifier.fillMaxWidth())
        }
    } else {
        Row(Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, top = 14.dp, bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically) {
            avatar()
            header(Modifier.weight(1f))
        }
    }
    val acceptButton: @Composable (Modifier) -> Unit = { m ->
        BoardButton(ReversiPhoneText.accept, m, kind = BoardButtonKind.Filled, enabled = GamesReversiRespond.canAccept(games), fillsWidth = true,
            testTag = ReversiScreenTags.accept(invite.id)) { onAccept(invite) }
    }
    val declineButton: @Composable (Modifier) -> Unit = { m ->
        BoardButton(ReversiPhoneText.decline, m, kind = BoardButtonKind.Gray, enabled = GamesReversiRespond.canDecline(games), fillsWidth = true,
            testTag = ReversiScreenTags.decline(invite.id)) { reversi.scope.launch { GamesReversiRespond.decline(games, invite.id) } }
    }
    if (large) {
        Column(Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, bottom = AingDimens.cardPadding),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            acceptButton(Modifier)
            declineButton(Modifier)
        }
    } else {
        Row(Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, bottom = AingDimens.cardPadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            declineButton(Modifier.weight(1f))
            acceptButton(Modifier.weight(1f))
        }
    }
}

/** 보낸 신청 한 줄: 아바타 · "구름빵님에게 신청했어요" · 판돈 · 남은 초 · [취소] 회색 알약. */
@Composable
internal fun ReversiOutgoingRow(reversi: ReversiStore, invite: ReversiOutgoing) {
    val colors = AingTheme.colors
    val name = invite.peer.displayName.ifEmpty { ReversiPhoneText.opponentFallbackName }
    val texts: @Composable (Modifier) -> Unit = { m ->
        Column(m.semantics(mergeDescendants = true) {}) {
            Text(ReversiPhoneText.outgoingTitle(name), style = BoardText.rowTitle(), color = colors.label)
            Row(verticalAlignment = Alignment.CenterVertically) {
                BoardStakeLine(invite.stake.toLong(), prefix = ReversiPhoneText.stakeTitle)
                ReversiRemainingText(reversi, invite.expiresAt, prefix = " · ")
            }
        }
    }
    val avatar: @Composable () -> Unit = {
        BoardAvatar(invite.peer.displayName, invite.peer.id, 36.dp, working = invite.peer.isWorking, url = invite.peer.avatarURL, characterHint = invite.peer.characterID)
    }
    val cancel: @Composable () -> Unit = {
        BoardButton(ReversiPhoneText.cancel, kind = BoardButtonKind.Gray, small = true, enabled = !reversi.isBusy) { reversi.scope.launch { reversi.cancelChallenge() } }
    }
    BoardRow(minHeight = 56.dp) {
        if (reversiLargeFont()) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically) {
                    avatar()
                    texts(Modifier.weight(1f))
                }
                cancel()
            }
        } else {
            avatar()
            texts(Modifier.weight(1f))
            cancel()
        }
    }
}

/**
 * 신청 만료까지 남은 초("42초 남음") — **잎**(초 단위 값은 잎만 읽는다 · 스토어는 매초 아무것도 대입하지 않는다). 시계는 스토어 시계.
 * 만료된 신청은 코어 타이머가 걷는다(`scheduleInviteExpiry`).
 */
@Composable
internal fun ReversiRemainingText(reversi: ReversiStore, expiresAt: SwiftDate, prefix: String = "") {
    val colors = AingTheme.colors
    val tick = rememberTicker()
    val remaining = tick.let { expiresAt.timeIntervalSince(reversi.clock()) }
    Text(prefix + ReversiPhoneText.remainingPhrase(remaining), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2,
        modifier = Modifier.semantics { contentDescription = ReversiPhoneText.clockAccessibility(remaining) })
}

// MARK: - 판 화면 위 받은 신청 띠

/** 로봇 연습·끝난 판 화면 위 받은 신청 띠(판정 `GamesReversiInviteBanner`). 카드는 로비와 같은 부품이고 머리 글자만 띠 문장이다. */
@Composable
internal fun ReversiInviteBannerView(games: GamesStore, reversi: ReversiStore, onAccept: (ReversiInvite) -> Unit) {
    val invite = GamesReversiInviteBanner.invite(reversi) ?: return
    val colors = AingTheme.colors
    Box(Modifier.fillMaxWidth().background(colors.background).padding(start = AingDimens.sideMargin, end = AingDimens.sideMargin, top = AingDimens.space1, bottom = AingDimens.space2)
        .testTag(ReversiScreenTags.banner)) {
        BoardGroup {
            ReversiInviteCard(games, reversi, invite, bannerTitle = ReversiPhoneText.bannerTitle(invite.peer.displayName),
                more = GamesReversiInviteBanner.moreCount(reversi), onAccept = onAccept)
        }
    }
}

// MARK: - 판돈 시트

/**
 * 판돈 시트(폰 체스·테트리스 시트와 같은 모양): **아무것도 안 골라진 채** 열리고, 판돈은 고르기만(다시 누르면 해제), 신청은 맨 아래 채운 단추 하나.
 * ★ 캡션이 **거짓말을 하지 않는 것**이 이 시트의 계약이다: 신청만 한 상태에서는 0원도 안 움직이고, 양쪽에서 빠지는 것은 **수락하는 순간**이다.
 * 신청을 낼 수 있는가는 `GamesReversiStakeSend.sendable` **한 곳**이다(요청이 나가는 마지막 문 — §8-17 깃발 · 잔액 · 다른 게임 판 · 내 판 · 보낸 신청).
 */
@Composable
internal fun BoxScope.ReversiStakeSheet(games: GamesStore, reversi: ReversiStore, target: ReversiUser, onClose: () -> Unit) {
    val colors = AingTheme.colors
    var selected by remember(target.id) { mutableStateOf<ReversiStake?>(null) }
    val balance: Long? = games.rubyBalance
    val sendable = GamesReversiStakeSend.sendable(selected, reversi, balance, games.reversiEntryBlock)
    BoardSheetOverlay(ReversiPhoneText.stakeTitle, onDismiss = onClose, subtitle = ReversiPhoneText.stakePromptTitle(target.displayName), testTag = ReversiScreenTags.stakeSheet) {
        BoardGroup {
            BoardRow(minHeight = 64.dp) {
                BoardAvatar(target.displayName, target.id, 44.dp, working = target.isWorking, url = target.avatarURL, characterHint = target.characterID)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    BoardPersonName(target.displayName, center = target.center)
                    Text(selected?.let { ReversiPhoneText.stakePromptChosen(it.rawValue) } ?: ReversiPhoneText.stakePromptCaption,
                        style = BoardText.digits(BoardText.rowSubtitle()), color = if (selected == null) colors.label2 else colors.accent)
                }
            }
        }
        // 큰 글자에서는 세로로 — 가로 셋에 "10" 이 줄바꿈되어 "1/0" 으로 읽혔다(오목 AX 실측).
        val option: @Composable (ReversiStake, Modifier) -> Unit = { stake, m -> ReversiStakeOption(stake, selected, balance, reversi.isBusy, m) { selected = GamesReversiStakeSend.toggled(selected, stake) } }
        if (reversiLargeFont()) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (stake in ReversiStake.entries) option(stake, Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (stake in ReversiStake.entries) option(stake, Modifier.weight(1f))
            }
        }
        Column(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(ReversiPhoneText.myRubyTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                if (balance != null) {
                    BoardRuby(14.dp)
                    Text("$balance", style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label)
                } else {
                    Text(ReversiPhoneText.unknownNumber, style = BoardText.rowSubtitle(), color = colors.label2)
                }
                if (ReversiStake.entries.any { !GamesReversiStakeSend.affordable(it, balance) }) {
                    Text(ReversiPhoneText.bulletPrefix + ReversiPhoneText.stakeShortfall, style = BoardText.rowSubtitle(), color = colors.label2)
                }
            }
            Text(ReversiPhoneText.stakeCaption, style = BoardText.rowSubtitle(), color = colors.label2)
            Text(ReversiPhoneText.stakeNotHeldYet(reversi.inviteTTLSeconds.toInt()), style = BoardText.rowSubtitle(), color = colors.label2)
        }
        // ★ 아무것도 안 고르면 글자가 "판돈을 고르세요" 이고 **비활성**이다 — 골라야 [도전하기]가 생긴다.
        BoardButton(
            selected?.let { ReversiPhoneText.challengeWithStake(it.rawValue) } ?: ReversiPhoneText.stakePromptCaption,
            kind = BoardButtonKind.Filled, fillsWidth = true, enabled = sendable != null, testTag = ReversiScreenTags.stakeSend,
        ) {
            if (sendable == null) return@BoardButton
            val choice = selected
            val targetID = target.id
            onClose()
            reversi.scope.launch { GamesReversiStakeSend.send(choice, targetID, games) }
        }
    }
}

/** 판돈 칸 하나 — **고르기만** 한다(선택 = 파랑 틴트 + 파랑 테두리 + 체크). 모자라면 흐린 가격 + 비활성, **잔액을 모르면 막지 않는다**. */
@Composable
private fun ReversiStakeOption(stake: ReversiStake, selected: ReversiStake?, balance: Long?, isBusy: Boolean, modifier: Modifier, onToggle: () -> Unit) {
    val colors = AingTheme.colors
    val isSelected = selected == stake
    val affordable = GamesReversiStakeSend.affordable(stake, balance)
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    Column(
        modifier.defaultMinSize(minHeight = 72.dp)
            .background(if (isSelected) colors.accentTint else colors.surface, shape)
            .border(2.dp, if (isSelected) colors.accent else Color.Transparent, shape)
            .clickable(enabled = affordable && !isBusy, onClick = onToggle)
            .padding(vertical = 12.dp).testTag(ReversiScreenTags.stakeOption(stake.rawValue))
            .clearAndSetSemantics {
                contentDescription = ReversiPhoneText.stakeOptionAccessibility(stake.rawValue)
                this.selected = isSelected
                val value = if (isSelected) ReversiPhoneText.selected else if (affordable) "" else ReversiPhoneText.stakeShortfall
                if (value.isNotEmpty()) stateDescription = value
            },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            BoardRuby(20.dp, Modifier.alpha(if (affordable) 1f else 0.5f))
            Text("${stake.rawValue}", style = BoardText.digits(BoardText.title3()), color = if (affordable) colors.label else colors.label3Text)
        }
        Text(ReversiPhoneText.stakeGain(stake.rawValue), style = BoardText.digits(BoardText.caption()), color = if (affordable) colors.label2 else colors.label3Text)
        if (isSelected) AingIcon(AppIcon.CheckCircleFill, contentDescription = null, size = 16.dp, tint = colors.accent)
    }
}
