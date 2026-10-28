// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift(GamesGomokuLobby · OpponentRow · InviteCard · OutgoingRow · RemainingText) · Sources/CheckMobileKit/Games/GamesComponents.swift(GamesLiveMatchRow) · Sources/CheckMobileKit/Games/GamesGomokuAIViews.swift(GamesGomokuAIEntryCard) @ 3bd04bd
//
// 로비(시안 B 08): 전적·내 루비 두 칸 · 규칙 한 줄 · 안내 · 받은 신청 · 보낸 신청 · [AI와 두기] · 상대 고르기 · 지금 대결 중 · 순위표(맨 아래).
//
// **상대 목록은 `games.gomokuLobbyUsers(roster)` 하나만 읽는다**(차단 확인 시트의 약속 "오목 신청에서 서로 보이지 않아요" — 코어 `users` 를
// 직접 읽으면 방금 차단한 사람이 [도전] 단추와 함께 그대로 선다. 6차 int-h '[조립 K11]').
//
// §8-17 #1(판돈 대결 빌드 깃발): 깃발이 꺼지면 [도전]을 **숨기고**(흐린 단추로도 두지 않는다 — 누를 수 없는 단추는 까닭을 못 말한다) 받은 신청은
// 스토어가 접은 한 줄(`incomingFoldedNotice` — "앱을 업데이트해야 대결할 수 있어요")로 선다. AI 대국 · 관전 · 순위는 그대로다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.games.GamesLobbyRoster
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuNoticeText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneChallengeGate
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.canStartAIMatch
import com.yehsung.aingcheck.core.stores.gomoku.isMine
import com.yehsung.aingcheck.core.stores.gomoku.startWatching
import com.yehsung.aingcheck.core.stores.gomoku.loadRanking
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

@Composable
internal fun GomokuLobby(games: GamesStore, gomoku: GomokuStore, roster: GamesLobbyRoster<GomokuUser>, state: GomokuScreenState) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag(GomokuScreenTags.lobby)
            .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space6),
    ) {
        BoardSummary(
            leftTitle = GomokuPhoneText.recordTitle,
            leftValue = gomoku.record?.let(GomokuScreenText::record) ?: "–",
            rightTitle = GomokuPhoneText.myRubyTitle,
            rubyBalance = games.rubyBalance?.toLong(),
            leftDescription = "내 오목 전적 ${GomokuScreenText.record(gomoku.record)}",
        )
        // 규칙 한 줄은 머리가 아니라 첫 카드 아래(바탕 위 4.7:1 — w15 검증 medium 5).
        BoardCaption(GomokuPhoneText.subtitle)
        gomoku.notice?.let { Spacer(Modifier.height(AingDimens.rowSpacing)); BoardNotice(it) }
        GomokuIncomingSection(gomoku)
        GomokuOutgoingSection(gomoku)
        Spacer(Modifier.height(AingDimens.rowSpacing))
        GomokuAIEntryCard(gomoku, onPlay = { state.showsAIPicker = true })
        GomokuOpponentsSection(games, gomoku, roster, onChallenge = { state.stakeTarget = it })
        GomokuLiveSection(gomoku)
        // 순위표는 맨 아래(로비엔 절이 다섯 — 위에 두면 관전 입구 "지금 대결 중"이 스크롤 밖으로 묻힌다).
        GomokuRankingSection(gomoku, state)
    }
}

/**
 * 받은 신청. 빈 받은함은 절을 통째로 접는다("없어요"는 할 일이 없는 줄). 깃발이 꺼진 빌드는 스토어가 신청을 배너·점에서 빼고
 * 한 줄로 접는다 — 그 한 줄을 여기 세운다(받은 신청이 **있다는 사실**은 숨기지 않는다).
 */
@Composable
internal fun GomokuIncomingSection(gomoku: GomokuStore) {
    gomoku.incomingFoldedNotice?.let { folded ->
        Spacer(Modifier.height(AingDimens.rowSpacing))
        BoardNotice(folded, Modifier.testTag(GomokuScreenTags.incomingNotice))
    }
    when (MobileLoadKnowledge.placeholder(hasRows = gomoku.incoming.isNotEmpty(), hasLoaded = gomoku.hasLoadedInbox, lastFailed = gomoku.inboxLoadFailed)) {
        MobileLoadKnowledge.Placeholder.rows -> {
            val pending = gomoku.pendingIncomingInvites
            val first = pending.firstOrNull() ?: return
            rememberTicker()
            BoardSectionHeader(GomokuPhoneText.incomingTitle, trailing = GomokuPhoneText.remainingPhrase(first.expiresAt.timeIntervalSince(gomoku.clock())))
            BoardGroup {
                pending.forEachIndexed { index, invite ->
                    GomokuInviteCard(gomoku, invite, showsCountdown = index > 0, isLast = index == pending.size - 1)
                }
            }
        }
        MobileLoadKnowledge.Placeholder.empty -> Unit
        MobileLoadKnowledge.Placeholder.failed -> {
            BoardSectionHeader(GomokuPhoneText.incomingTitle)
            BoardGroup { BoardRow { BoardLoadFailure(GomokuPhoneText.incomingLoadFailed) { gomoku.scope.launch { gomoku.loadInbox() } } } }
        }
        MobileLoadKnowledge.Placeholder.loading -> {
            BoardSectionHeader(GomokuPhoneText.incomingTitle)
            BoardGroup { BoardRow { BoardLoading(GomokuPhoneText.loadingIncoming) } }
        }
    }
}

/**
 * 보낸 신청 한 줄 + [취소] — **로비와 관전 화면이 같이 쓴다**(관전이 로비 자리에 서면 이 줄이 통째로 사라져 루비를 걸어 둔 신청을 TTL 60초 동안
 * 거둘 길이 없었다 — Swift `GamesGomokuOutgoingRow` 머리말). 취소 문은 한 벌이다.
 */
@Composable
internal fun GomokuOutgoingSection(gomoku: GomokuStore) {
    val invite = gomoku.outgoing ?: return
    val colors = AingTheme.colors
    rememberTicker()
    BoardSectionHeader(GomokuPhoneText.outgoingTitle)
    BoardGroup {
        BoardRow(minHeight = 56.dp) {
            BoardAvatar(invite.peer.displayName, invite.peer.id, 36.dp, working = invite.peer.isWorking)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                Text(GomokuPhoneText.outgoingTitle(invite.peer.displayName), style = BoardText.rowTitle(), color = colors.label)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BoardStakeLine(invite.stake)
                    Text(" · " + GomokuPhoneText.remainingPhrase(invite.expiresAt.timeIntervalSince(gomoku.clock())), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
                }
            }
            BoardButton(GomokuPhoneText.cancel, kind = BoardButtonKind.Gray, small = true, enabled = !gomoku.isBusy) {
                gomoku.scope.launch { gomoku.cancelChallenge() }
            }
        }
    }
}

/** 받은 신청 한 건: 아바타 44 · "솜사탕님의 신청" + 센터 · 판돈 줄 · [거절 회색] [수락 채움](채운 단추는 이것 하나). */
@Composable
internal fun GomokuInviteCard(gomoku: GomokuStore, invite: GomokuInvite, showsCountdown: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, top = 14.dp, bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BoardAvatar(invite.peer.displayName, invite.peer.id, 44.dp, working = invite.peer.isWorking)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                BoardPersonName(GomokuPhoneText.incomingTitle(invite.peer.displayName), center = invite.peer.center)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BoardStakeLine(invite.stake, suffix = GomokuPhoneText.stakeGainSuffix(invite.stake.toInt()))
                    if (showsCountdown) {
                        Text(" · " + GomokuPhoneText.remainingPhrase(invite.expiresAt.timeIntervalSince(gomoku.clock())), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, bottom = AingDimens.cardPadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            BoardButton(GomokuPhoneText.decline, Modifier.weight(1f), kind = BoardButtonKind.Gray, enabled = !gomoku.isBusy, fillsWidth = true, testTag = GomokuScreenTags.decline(invite.id)) {
                gomoku.scope.launch { gomoku.respond(invite.id, accept = false) }
            }
            BoardButton(GomokuPhoneText.accept, Modifier.weight(1f), kind = BoardButtonKind.Filled, enabled = !gomoku.isBusy, fillsWidth = true, testTag = GomokuScreenTags.accept(invite.id)) {
                gomoku.scope.launch { gomoku.respond(invite.id, accept = true) }
            }
        }
        if (!isLast) Box(Modifier.padding(start = AingDimens.cardPadding).fillMaxWidth().height(AingDimens.hairline).background(colors.separator))
    }
}

/** [AI와 두기] 입구(사람 목록 바로 위 — 시간이 흐르는 받은·보낸 신청보다 아래). 루비·전적 없이 연습한다. */
@Composable
internal fun GomokuAIEntryCard(gomoku: GomokuStore, onPlay: () -> Unit) {
    val colors = AingTheme.colors
    val enabled = gomoku.canStartAIMatch
    BoardGroup(Modifier.testTag(GomokuScreenTags.aiEntry).let { if (enabled) it.clickable(onClick = onPlay) else it }) {
        BoardRow(minHeight = 56.dp) {
            GomokuAIPortrait(36.dp, Modifier.alpha(if (enabled) 1f else 0.5f))
            Column(Modifier.weight(1f)) {
                Text(GomokuPhoneText.aiButton, style = BoardText.rowTitle(), color = if (enabled) colors.label else colors.label2)
                Text(GomokuPhoneText.aiButtonHelp, style = BoardText.rowSubtitle(), color = colors.label2)
            }
            if (enabled) AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 18.dp, tint = colors.label3)
        }
    }
}

/** 상대 고르기 — 머리 "N명"은 **차단해 숨긴 사람을 빼고** 센다(목록에서만 빠지고 숫자는 그대로면 그 자리가 빈 것처럼 읽힌다). */
@Composable
internal fun GomokuOpponentsSection(games: GamesStore, gomoku: GomokuStore, roster: GamesLobbyRoster<GomokuUser>, onChallenge: (GomokuUser) -> Unit) {
    val colors = AingTheme.colors
    val users = games.gomokuLobbyUsers(roster)
    BoardSectionHeader(GomokuPhoneText.lobbyTitle, trailing = if (users.isEmpty()) null else GomokuPhoneText.peopleCount(users.size))
    BoardGroup {
        if (gomoku.lobbyLoadFailed) {
            BoardRow(divider = users.isNotEmpty()) { BoardLoadFailure(GomokuPhoneText.usersLoadFailed) { gomoku.scope.launch { gomoku.refreshLobby() } } }
        }
        if (users.isEmpty()) {
            if (!gomoku.lobbyLoadFailed) {
                BoardRow {
                    if (gomoku.hasLoadedLobby) Text(GomokuPhoneText.emptyUsers, style = BoardText.subheadline(), color = colors.label2)
                    else BoardLoading(GomokuPhoneText.loadingUsers)
                }
            }
        } else {
            users.forEachIndexed { index, user ->
                GomokuOpponentRow(gomoku, user, isLast = index == users.size - 1, onChallenge = onChallenge)
            }
        }
    }
    BoardCaption(GomokuPhoneText.lobbyCaption)
}

/**
 * 상대 한 줄: 아바타(근무 중 점) · 이름 + 센터 · 회색 부제 · 오른쪽 [도전](또는 회색 비활성 "대국 중"/"도전").
 * 깃발이 꺼진 빌드(`duelsLocked`)는 단추 자리를 **비운다**(§8-17 #1 — 신청 진입을 숨긴다). 활성 판정은 [GomokuPhoneChallengeGate] 하나다.
 */
@Composable
private fun GomokuOpponentRow(gomoku: GomokuStore, user: GomokuUser, isLast: Boolean, onChallenge: (GomokuUser) -> Unit) {
    val colors = AingTheme.colors
    BoardRow(Modifier.testTag(GomokuScreenTags.opponent(user.id)), divider = !isLast, dividerInset = AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
        BoardAvatar(user.displayName, user.id, 36.dp, working = user.isWorking)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(user.displayName, center = user.center)
            Text(GomokuScreenText.opponentStatus(user, gomoku.liveMatches), style = BoardText.rowSubtitle(), color = colors.label2)
        }
        if (!gomoku.duelsLocked) {
            if (GomokuPhoneChallengeGate.isEnabled(user, gomoku)) {
                BoardButton(GomokuPhoneText.challenge, kind = BoardButtonKind.Tinted, small = true, testTag = GomokuScreenTags.challenge(user.id)) { onChallenge(user) }
            } else {
                BoardButton(if (user.inMatch) GomokuPhoneText.inMatchButton else GomokuPhoneText.challenge, kind = BoardButtonKind.Gray, small = true, enabled = false,
                    testTag = GomokuScreenTags.challenge(user.id)) {}
            }
        }
    }
}

/** 지금 대결 중 — 관전 입구는 **이 목록뿐**이다(관전 화면이 로비 자리에 서므로 허브에서 누르면 화면이 안 바뀐다). */
@Composable
internal fun GomokuLiveSection(gomoku: GomokuStore) {
    val colors = AingTheme.colors
    val lives = gomoku.liveMatches
    when (MobileLoadKnowledge.placeholder(hasRows = lives.isNotEmpty(), hasLoaded = gomoku.hasLoadedLobby, lastFailed = gomoku.lobbyLoadFailed)) {
        MobileLoadKnowledge.Placeholder.rows -> {
            BoardSectionHeader(GomokuPhoneText.liveTitle, trailing = GomokuPhoneText.liveCount(lives.size))
            BoardGroup { lives.forEachIndexed { index, live -> GomokuLiveMatchRow(gomoku, live, isLast = index == lives.size - 1) } }
        }
        MobileLoadKnowledge.Placeholder.empty -> {
            BoardSectionHeader(GomokuPhoneText.liveTitle)
            BoardGroup { BoardRow { Text(GomokuPhoneText.noLiveMatches, style = BoardText.subheadline(), color = colors.label2) } }
        }
        // 같은 조회(로비)의 [다시 시도]는 위 상대 고르기 절에 있다 — 여기선 한 줄만.
        MobileLoadKnowledge.Placeholder.failed -> {
            BoardSectionHeader(GomokuPhoneText.liveTitle)
            BoardGroup { BoardRow { BoardLoadFailure(GomokuPhoneText.liveLoadFailed, onRetry = null) } }
        }
        MobileLoadKnowledge.Placeholder.loading -> Unit
    }
}

/**
 * "지금 대결 중" 한 줄(Swift `GamesLiveMatchRow`): 두 얼굴 vs · 이름 둘 · 판돈 [보석]10 · 1분 35초째 · 오른쪽 끝 관전자 수 + 관전 입구.
 * INV-GamesComponents-4a509409 이식: 좁은 폭·큰 글자에서 접는 꼴을 **한 벌**로 둔다 — 이 행은 오른쪽 슬롯이 있으면 늘 글 아래 줄로 내린다(접는 결론이
 *   하나라 두 갈래가 싸우지 않는다. 판돈·경과가 줄임표로 잘리던 320pt 실측의 대책).
 */
@Composable
internal fun GomokuLiveMatchRow(gomoku: GomokuStore, live: GomokuLiveMatch, isLast: Boolean) {
    val colors = AingTheme.colors
    // 관전 입구는 주 스위치가 켜졌을 때만(꺼진 배선에서는 `startWatching` 이 조용히 돌아서 눌러도 아무 일이 없는 단추가 된다).
    val hasWatchEntry = gomoku.spectatorFeaturesEnabled
    // INV-GamesComponents-836dfabe 이식: 관전자 수는 **주 스위치와 무관**하다 — 로비 응답이 실어 온 사실(`live.watchers`)이고, 관전에 들어갈 수 있는가와는
    //   다른 축이다. 그래서 오른쪽 슬롯 판정이 둘을 **합쳐서** 본다(한 술어 — 두 곳에 적으면 한쪽만 고쳐진다).
    val hasTrailing = hasWatchEntry || GamesWatcherCount.shows(live.watchers.toInt())
    rememberTicker()
    BoardRow(divider = !isLast) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                BoardAvatar(live.a.displayName, live.a.id, 30.dp)
                Text("vs", style = BoardText.rowSubtitle(), color = colors.label2)
                BoardAvatar(live.b.displayName, live.b.id, 30.dp)
            }
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                Text(GomokuScreenText.livePair(live), style = BoardText.rowTitle(), color = colors.label)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // 남의 판 — 판돈 **액수만**(접미사 없음).
                    BoardStakeLine(live.stake.rawValue)
                    Text(" · " + GomokuPhoneText.elapsedPhrase(gomoku.clock().timeIntervalSince(live.startedAt)), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
                }
            }
            if (hasTrailing) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    WatcherBadge(live.watchers)
                    if (hasWatchEntry) GomokuWatchEntry(gomoku, live)
                }
            }
        }
    }
}

/**
 * 관전 입구: [관전] 틴트 알약 — 누를 수 없는 두 경우(내 판 · 서버에 관전이 아직 없다)에는 칩 대신 **그 이유를 말하는 회색 캡션**이 같은 자리에 선다.
 * INV-GamesComponents-407e1efc 이식: 잠금은 **`watchUnavailable`** 하나로 본다(`rankingUnavailable` 이 아니다 — 그 깃발은 순위표가 없다는 뜻이고,
 *   행을 들고 있는 사람에게는 이 게이트가 영영 열려 같은 카드를 눌러 404 를 무한히 냈다).
 * INV-GamesComponents-b397ecd3 이식: 흐린 칩(`disabled`)으로 두지 않는다 — 폰엔 호버가 없어 이유가 화면 반대쪽 끝에만 있었다. 칩을 빼고 그 자리에
 *   이유를 **짧은 글자**로 둔다('내 판' 갈래와 같은 관용구 · 접근성은 온전한 문장).
 */
@Composable
private fun GomokuWatchEntry(gomoku: GomokuStore, live: GomokuLiveMatch) {
    val colors = AingTheme.colors
    when {
        gomoku.isMine(live) -> Text(GomokuScreenText.myMatchCaption, style = BoardText.rowSubtitle(), color = colors.label2)
        gomoku.watchUnavailable -> Text(
            GomokuScreenText.watchSoonCaption, style = BoardText.rowSubtitle(), color = colors.label2,
            modifier = Modifier.semantics { contentDescription = GomokuNoticeText.watchUnavailable },
        )
        else -> BoardButton(GomokuScreenText.watchChip, kind = BoardButtonKind.Tinted, small = true, testTag = GomokuScreenTags.watch(live.id)) {
            gomoku.startWatching(live.id)
        }
    }
}

/** AI 상대 얼굴(파랑 틴트 원 + cpu 기호 · 돌 배지). */
@Composable
internal fun GomokuAIPortrait(size: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier, stoneIsBlack: Boolean? = null) {
    val colors = AingTheme.colors
    Box(modifier.size(size).semantics { contentDescription = GomokuUser.gomokuAI.displayName }) {
        Box(Modifier.fillMaxSize().background(colors.accentTint, CircleShape), contentAlignment = Alignment.Center) {
            AingIcon(AppIcon.Memory, contentDescription = null, size = size * 0.46f, tint = colors.accent)
        }
        if (stoneIsBlack != null) {
            BoardPortraitStoneDot(stoneIsBlack, (size.value * 0.3f).coerceIn(12f, 20f).dp, Modifier.align(Alignment.BottomEnd))
        }
    }
}

@Composable
internal fun BoardPortraitStoneDot(isBlack: Boolean, side: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Box(
        modifier.size(side)
            .background(colors.surface, CircleShape)
            .padding(2.dp)
            .background(if (isBlack) GomokuStoneInk.black else GomokuStoneInk.white, CircleShape),
    )
}

/** 돌 점 색(물건 — 외관과 무관). */
internal object GomokuStoneInk {
    val black = androidx.compose.ui.graphics.Color(0.10f, 0.10f, 0.10f)
    val white = androidx.compose.ui.graphics.Color(0.96f, 0.96f, 0.96f)
}

