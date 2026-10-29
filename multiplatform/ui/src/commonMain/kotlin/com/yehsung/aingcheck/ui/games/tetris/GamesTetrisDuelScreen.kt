// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift:185-984 @ 3bd04bd (화면 — 로비 · 상대 줄 · 받은/보낸 신청 · 지금 대결 중 · 판돈 시트 · 규칙 시트)
//
// 폰 1:1 테트리스 **화면 하나**(설계서 P6) — 로비 · 대결 · 결과를 한 화면이 갈아 끼운다. 판정(카드 · 신청 게이트 · 판돈 보내기 · 판돈 고르기 ·
// 못 쓰는 기기)은 core/stores `GamesTetrisLobby.kt`(W2-e)에 있고 이 화면은 받아 그리기만 한다.
// 수명은 **직접 코어를 부르지 않는다** — 나타남 → GamesStore.tetrisScreenDidAppear(), 사라짐 → …DidDisappear() 뿐이다(창 문 순서의 주인은 스토어).
//
// Android 첫 판 몫(G §8-17 1 · §8-18 5): 판돈 대결의 **신청·수락 진입은 `duelsEnabled` 가 켜진 빌드에서만 보인다** — 꺼진 빌드는 [신청]·판돈 시트·
// [수락]을 아예 그리지 않는다(게이트 판정은 core — 요청 0건은 스토어도 같은 깃발로 막는다). 판돈이 생기지 않는 [거절]·관전·순위·전적은 그대로다.
package com.yehsung.aingcheck.ui.games.tetris

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelAcceptGate
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelChallengeGate
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelRankingPlan
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelStakeSend
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelUnavailable
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisLobbyTab
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisStakeSelection
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisWatchPlan
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelInvite
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelLiveMatch
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelPhase
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStake
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelUser
import com.yehsung.aingcheck.core.stores.tetris.TetrisPhoneText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.rememberRubyArt
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
import com.yehsung.aingcheck.ui.games.minigame.sfIcon
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 화면 꼬리표(시험·계측). */
object TetrisDuelTags {
    const val LOBBY: String = "tetris.lobby"
    const val MATCH: String = "tetris.match"
    const val BOARD: String = "tetris.match.board"
    fun challenge(userID: String): String = "tetris.challenge.$userID"
    fun accept(inviteID: String): String = "tetris.accept.$inviteID"
    fun decline(inviteID: String): String = "tetris.decline.$inviteID"
    const val STAKE_SEND: String = "tetris.stake.send"
    fun stake(value: Int): String = "tetris.stake.$value"
}

/**
 * 1:1 테트리스 화면 — 코어 [TetrisDuelStore] 의 단계를 한 화면에서 갈아 끼운다.
 *
 * INV-GamesTab-b9aed5c5 이식: 이 화면의 수명 효과는 **스토어 하나에만** 묶는다(값이 흔들리는 상태를 키로 걸지 않는다). 수명 효과가 다시 서면
 *   tetrisScreenDidDisappear() 가 돌아 수락한 판이 화면 없이 15초 침묵으로 진다(D5). 로비 탭 선택은 화면 안에서 쥔다.
 *
 * @param appActive 앱이 앞에 있는가(Android ON_START·ON_STOP). 뒤로 가면 눌린 것을 놓는다 — 돌아왔을 때 유령 입력이 남지 않게.
 * @param meName 머리글의 내 이름(게임 탭이 이미 아는 값 — 새 서버 호출 없음). 모르면 "나".
 */
@Composable
fun GamesTetrisDuelScreen(
    store: GamesStore,
    myUserID: String?,
    refreshHz: Int,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    appActive: Boolean = true,
    reduceMotion: Boolean = false,
    meName: String? = null,
    now: () -> SwiftDate = { store.tetris.clock() },
) {
    DisposableEffect(store) {
        store.tetrisScreenDidAppear()
        onDispose { store.tetrisScreenDidDisappear() }
    }
    val tetris = store.tetris
    var stakeTarget by remember { mutableStateOf<TetrisDuelUser?>(null) }
    var rulesVisible by remember { mutableStateOf(false) }
    var tab by remember { mutableStateOf(GamesTetrisLobbyTab.opponents) }
    // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 시트를 들고 있으면 로비로 돌아올 때 되살아난다.
    LaunchedEffect(tetris.match?.id) { stakeTarget = null }
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background)) {
        val unavailable = GamesTetrisDuelUnavailable.title(tetris.availability)
        when {
            unavailable != null -> {
                // 대결을 할 수 없는 기기·서버 상태다 — 로비를 그리면 신청 버튼이 서고 그 요청은 전부 거절된다.
                GamesHeaderBar(TetrisPhoneText.title, onBack = onBack)
                EmptyState(sfIcon(GamesTetrisDuelUnavailable.icon(tetris.availability)), unavailable, Modifier.padding(horizontal = AingDimens.sideMargin))
            }
            tetris.phase == TetrisDuelPhase.lobby -> {
                GamesHeaderBar(TetrisPhoneText.title, onBack = onBack) {
                    Box(
                        Modifier.heightIn(min = AingDimens.minimumTarget).clickable(role = Role.Button) { rulesVisible = true }
                            .semantics { contentDescription = TetrisPhoneText.rulesTitle },
                        contentAlignment = Alignment.Center,
                    ) { AingIcon(AppIcon.MenuBook, contentDescription = null, size = 22.dp, tint = colors.accent) }
                }
                androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
                val viewport = maxHeight
                TetrisLobby(store, myUserID, tab, viewport, onTab = { value ->
                    // INV-GamesTetrisDuelScreen-fb1a52d2 이식: **먼저 관전을 거둔다.** 관전 판은 [상대] 탭의 "지금 대결 중" 자리에만 있어서 탭을 바꾸면
                    //   화면에서는 사라지는데 spectating 은 살아 2초 폴링이 계속 나간다(아무것도 안 보는 사람이 관전자로 잡히고 [나가기]는 사라진 절 안에
                    //   있다). 코어는 탭을 모르므로 **화면이 풀어야 하는 매듭**이다 — 판정은 GamesTetrisWatchPlan.tabDidChange 한 곳.
                    GamesTetrisWatchPlan.tabDidChange(tetris, value)
                    // 순위는 로비에서만 갱신된다 — 탭을 고른 그 순간이 조회를 낼 자리다(스로틀·단계 가드는 판정 한 곳).
                    GamesTetrisDuelRankingPlan.refreshIfNeeded(tetris, value)
                    tab = value
                }, onChallenge = { stakeTarget = it }, now = now)
                }
            }
            else ->
                // 준비·카운트다운·판·결과는 한 화면이 맡는다. phase != lobby 는 **판을 들고 있다는 뜻**이다(코어가 match 에서만 단계를 낸다).
                GamesTetrisDuelMatchView(store, refreshHz, appActive, reduceMotion, meName, Modifier.fillMaxSize().testTag(TetrisDuelTags.MATCH))
        }
    }
    stakeTarget?.let { target -> GamesTetrisStakeSheet(store, target, onDismiss = { stakeTarget = null }) }
    if (rulesVisible) GamesTetrisRulesSheet(onDismiss = { rulesVisible = false })
}

// MARK: 로비

@Composable
private fun TetrisLobby(
    store: GamesStore,
    myUserID: String?,
    tab: GamesTetrisLobbyTab,
    viewportHeight: androidx.compose.ui.unit.Dp,
    onTab: (GamesTetrisLobbyTab) -> Unit,
    onChallenge: (TetrisDuelUser) -> Unit,
    now: () -> SwiftDate,
) {
    val tetris = store.tetris
    val colors = AingTheme.colors
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
            .padding(top = AingDimens.space2, bottom = AingDimens.space6).testTag(TetrisDuelTags.LOBBY),
    ) {
        // INV-GamesTetrisDuelScreen-f3d8de30 이식: 받은 신청이 **맨 위**다(폰엔 전역 배너 부품도 탭 배지도 없다). 신청은 60초 뒤 사라지므로 스크롤을
        //   내려야 보이는 자리에 두면 그 사이 만료된다.
        IncomingSection(store, now)
        Summary(store)
        Text(
            TetrisPhoneText.subtitle, style = MaterialTheme.typography.bodySmall, color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
        )
        tetris.notice?.let { InlineNotice(it, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Warning) }
        // 한 사람 한 판(P3) — 오목·체스 판이 흐르는 동안은 테트리스를 신청·수락할 수 없다. 버튼만 흐려 두면 **왜**인지 알 길이 없어 절 위에 까닭을 세운다.
        // INV-GamesTetrisDuelScreen-1cadae6c 이식: **두 줄**이다(제목은 왜, 둘째 줄은 언제 풀리는지). 조립은 문구 표가 쥔다(GamesBusyText.entryBlockNotice —
        //   화면에서 이으면 한 화면만 둘째 줄을 빠뜨린다).
        GamesBusyText.entryBlockNotice(store.tetrisEntryBlock, GamesBusyGame.tetris)?.let {
            InlineNotice(it, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Warning)
        }
        OutgoingSection(store, now)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = AingDimens.rowSpacing)) {
            GamesTetrisLobbyTab.entries.forEachIndexed { index, value ->
                SegmentedButton(
                    selected = tab == value,
                    onClick = { if (tab != value) onTab(value) },
                    shape = SegmentedButtonDefaults.itemShape(index, GamesTetrisLobbyTab.entries.size),
                    icon = {},
                ) { Text(value.title, style = MaterialTheme.typography.labelLarge) }
            }
        }
        when (tab) {
            GamesTetrisLobbyTab.opponents -> {
                Opponents(store, onChallenge)
                LiveMatches(tetris, viewportHeight)
            }
            GamesTetrisLobbyTab.ranking -> GamesTetrisDuelRankingSection(tetris, myUserID)
        }
    }
}

/** 머리 두 칸 — 내 전적 · 내 루비. 루비는 공유 미러 먼저(나 탭 상점 구매도 적는다 — GamesStore.rubyBalance 와 같은 순서). */
@Composable
private fun Summary(store: GamesStore) {
    val tetris = store.tetris
    val colors = AingTheme.colors
    InsetGroup(Modifier.padding(top = AingDimens.rowSpacing)) {
        Row(Modifier.fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
            Column(
                Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp)
                    .semantics(mergeDescendants = true) { contentDescription = TetrisPhoneText.myRecordAccessibility(tetris.record) },
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(TetrisPhoneText.recordTitle, style = rowSubtitleStyle(), color = colors.label2)
                Text(TetrisPhoneText.record(tetris.record), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = TNUM), color = colors.label)
            }
            Box(Modifier.width(AingDimens.hairline).fillMaxSize().background(colors.separator))
            Column(Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(TetrisPhoneText.myRubyTitle, style = rowSubtitleStyle(), color = colors.label2)
                val balance = store.rubyBalance
                if (balance != null) RubyPrice(balance, isShort = false, art = rememberRubyArt(17f), fontSize = 17f)
                else Text(TetrisPhoneText.unknownNumber, style = MaterialTheme.typography.titleMedium, color = colors.label)
            }
        }
    }
}

// MARK: 받은 신청 · 보낸 신청

@Composable
private fun IncomingSection(store: GamesStore, now: () -> SwiftDate) {
    val tetris = store.tetris
    val invite = tetris.visibleIncoming ?: return
    val more = tetris.visibleIncomingInvites.size - 1
    SectionHeader(
        TetrisPhoneText.incomingTitle,
        trailing = SectionTrailing.Label(if (more > 0) TetrisPhoneText.incomingMore(more) else TetrisPhoneText.inviteTtlHint(tetris.inviteTTLSeconds.toInt())),
        padded = true,
    )
    InsetGroup { InviteCard(store, invite, now) }
}

/**
 * 받은 신청 한 건: 아바타 44 · "OO님의 신청" · 판돈 줄 + 남은 초 · [거절 회색] [수락 채움].
 * INV-GamesTetrisDuelScreen-3ca63f4f 이식: 수락이 **루비가 실제로 빠지는 순간**이다(신청만 받은 상태에서는 0원도 안 움직인다) — 그래서 [수락]만
 *   판돈 대결 깃발·한 사람 한 판 게이트(GamesTetrisDuelAcceptGate)를 지나고, 깃발이 꺼진 빌드는 [수락]을 그리지 않는다. [거절]은 판돈이 움직이지
 *   않아 막지 않는다(G §8-18 5).
 */
@Composable
private fun InviteCard(store: GamesStore, invite: TetrisDuelInvite, now: () -> SwiftDate) {
    val tetris = store.tetris
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    Column {
        Row(
            Modifier.padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, top = 14.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            PersonAvatar(invite.peer.displayName, invite.peer.id, 44.dp, working = invite.peer.isWorking)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                PersonName(TetrisPhoneText.incomingTitle(invite.peer.displayName))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StakeLine(invite.stake, prefix = TetrisPhoneText.stakeTitle, suffix = TetrisPhoneText.stakeGainSuffix(invite.stake))
                    RemainingText(invite.expiresAt, now, prefix = " · ")
                }
            }
        }
        Row(
            Modifier.padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, bottom = AingDimens.cardPadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            PillButton(
                TetrisPhoneText.decline, Modifier.weight(1f).testTag(TetrisDuelTags.decline(invite.id)), kind = PillKind.Gray, fillsWidth = true,
                enabled = !tetris.isBusy,
            ) { scope.launch { tetris.respond(invite.id, accept = false) } }
            if (tetris.duelsEnabled) {
                PillButton(
                    TetrisPhoneText.accept, Modifier.weight(1f).testTag(TetrisDuelTags.accept(invite.id)), kind = PillKind.Filled, fillsWidth = true,
                    enabled = GamesTetrisDuelAcceptGate.isEnabled(tetris, store.tetrisEntryBlock),
                ) { scope.launch { tetris.respond(invite.id, accept = true) } }
            }
        }
    }
}

@Composable
private fun OutgoingSection(store: GamesStore, now: () -> SwiftDate) {
    val tetris = store.tetris
    val invite = tetris.outgoing ?: return
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    SectionHeader(TetrisPhoneText.outgoingTitle, padded = true)
    InsetGroup {
        GroupRow(dividerInset = null, minHeight = 56.dp) {
            PersonAvatar(invite.peer.displayName, invite.peer.id, 36.dp, working = invite.peer.isWorking)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(TetrisPhoneText.outgoingTitle(invite.peer.displayName), style = rowTitleStyle(), color = colors.label)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StakeLine(invite.stake, prefix = TetrisPhoneText.stakeTitle)
                    RemainingText(invite.expiresAt, now, prefix = " · ")
                }
            }
            PillButton(TetrisPhoneText.cancel, kind = PillKind.Gray, size = PillSize.Sm, enabled = !tetris.isBusy) {
                scope.launch { tetris.cancelChallenge() }
            }
        }
    }
    Text(
        TetrisPhoneText.stakeNotHeldYet(tetris.inviteTTLSeconds.toInt()), style = rowSubtitleStyle(), color = colors.label2,
        modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
    )
}

/** 신청 만료까지 남은 초("42초 남음") — **잎**이다(초 단위 값은 잎만 읽는다. 스토어는 매초 아무것도 대입하지 않는다). */
@Composable
private fun RemainingText(expiresAt: SwiftDate, now: () -> SwiftDate, prefix: String = "") {
    var remaining by remember(expiresAt) { mutableStateOf(expiresAt.timeIntervalSince(now())) }
    LaunchedEffect(expiresAt) {
        while (true) {
            remaining = expiresAt.timeIntervalSince(now())
            delay(1000)
        }
    }
    Text(
        prefix + TetrisPhoneText.remainingPhrase(remaining),
        style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = AingTheme.colors.label2,
        modifier = Modifier.semantics { contentDescription = TetrisPhoneText.remainingAccessibility(remaining) },
    )
}

// MARK: 상대 고르기

@Composable
private fun Opponents(store: GamesStore, onChallenge: (TetrisDuelUser) -> Unit) {
    val tetris = store.tetris
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    // INV-GamesTetrisDuelScreen-3f51e35a 이식: **정렬하지 않는다** — 코어가 서버와 같은 규칙으로 이미 맞췄다(GamesStore.tetrisLobbyUsers — 차단 거르기 포함).
    val users = store.tetrisLobbyUsers
    SectionHeader(
        TetrisPhoneText.usersTab,
        trailing = if (users.isEmpty()) SectionTrailing.None else SectionTrailing.Label(TetrisPhoneText.peopleCount(users.size)),
        padded = true,
    )
    InsetGroup {
        if (tetris.lobbyLoadFailed) {
            GroupRow(dividerInset = if (users.isEmpty()) null else AingDimens.cardPadding) {
                LoadFailureRow(TetrisPhoneText.usersLoadFailed) { scope.launch { tetris.refreshLobby() } }
            }
        }
        // 빈 목록을 "없다"로 말하는 것은 **한 번 받았고 마지막 조회가 실패하지 않았을 때만**.
        if (users.isEmpty()) {
            if (!tetris.lobbyLoadFailed) {
                GroupRow(dividerInset = null) {
                    if (tetris.hasLoadedLobby) Text(TetrisPhoneText.emptyUsers, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                    else LoadingRow(TetrisPhoneText.loadingUsers)
                }
            }
        } else {
            users.forEachIndexed { index, user -> OpponentRow(store, user, index == users.size - 1, onChallenge) }
        }
    }
    Text(
        TetrisPhoneText.lobbyCaption, style = rowSubtitleStyle(), color = colors.label2,
        modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
    )
}

/**
 * 상대 한 줄: 아바타(근무 중 점) · 이름 · 상태 부제 · 오른쪽 [신청] 틴트(또는 회색 비활성).
 * INV-GamesTetrisDuelScreen-1f17e802 이식: 부제와 버튼 글자를 **문구 표가 한 번에** 고른다(TetrisPhoneText.opponentRow) — 자리마다 따로 고르면 한 줄에
 *   같은 문장이 두 번 나오고 근무 축이 덮인다.
 * 판돈 대결 깃발이 꺼진 빌드(G §8-17 1)는 버튼 자리를 **비운다**(신청 진입을 세우지 않는다) — 부제(근무·대결 중·집중)는 그대로다.
 */
@Composable
private fun OpponentRow(store: GamesStore, user: TetrisDuelUser, isLast: Boolean, onChallenge: (TetrisDuelUser) -> Unit) {
    val tetris = store.tetris
    val colors = AingTheme.colors
    val lines = TetrisPhoneText.opponentRow(user)
    val canChallenge = GamesTetrisDuelChallengeGate.isEnabled(user, tetris, store.tetrisEntryBlock)
    val stacked = LocalDensity.current.fontScale >= 1.3f
    val button: @Composable () -> Unit = {
        if (tetris.duelsEnabled) {
            if (canChallenge) {
                PillButton(TetrisPhoneText.challenge, Modifier.testTag(TetrisDuelTags.challenge(user.id)), kind = PillKind.Tinted, size = PillSize.Sm) { onChallenge(user) }
            } else {
                // 막힌 까닭은 **버튼**이 말하고(짧게), 근무 축은 부제가 말한다.
                PillButton(lines.buttonTitle, Modifier.testTag(TetrisDuelTags.challenge(user.id)), kind = PillKind.Gray, size = PillSize.Sm, enabled = false) {}
            }
        }
    }
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically) {
                    PersonAvatar(user.displayName, user.id, 36.dp, working = user.isWorking)
                    OpponentInfo(user, lines.subtitle, Modifier.weight(1f))
                }
                button()
            }
        } else {
            PersonAvatar(user.displayName, user.id, 36.dp, working = user.isWorking)
            OpponentInfo(user, lines.subtitle, Modifier.weight(1f))
            button()
        }
    }
}

@Composable
private fun OpponentInfo(user: TetrisDuelUser, subtitle: String, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        PersonName(user.displayName)
        Text(subtitle, style = rowSubtitleStyle(), color = AingTheme.colors.label2)
    }
}

// MARK: 지금 대결 중 (관전 입구 — 0.3.65)

/** 관전 중이면 **이 자리가 관전 판으로 바뀐다**(새 화면을 밀지 않는다 — 밀면 이 화면이 사라져 폴링이 죽는다). */
@Composable
private fun LiveMatches(tetris: TetrisDuelStore, viewportHeight: androidx.compose.ui.unit.Dp) {
    val watch = tetris.spectating
    if (watch != null) {
        GamesTetrisWatchPanel(tetris, watch, viewportHeight)
        return
    }
    val colors = AingTheme.colors
    val lives = tetris.liveMatches
    // 한 번도 안 받았으면 절을 통째로 접는다(머리만 번쩍이지 않게).
    if (lives.isNotEmpty()) {
        SectionHeader(TetrisPhoneText.liveTitle, trailing = SectionTrailing.Label(TetrisPhoneText.liveCount(lives.size)), padded = true)
        InsetGroup { lives.forEachIndexed { index, live -> LiveRow(tetris, live, index == lives.size - 1) } }
    } else if (tetris.hasLoadedLobby && !tetris.lobbyLoadFailed) {
        SectionHeader(TetrisPhoneText.liveTitle, padded = true)
        InsetGroup { GroupRow(dividerInset = null) { Text(TetrisPhoneText.noLive, style = MaterialTheme.typography.bodyMedium, color = colors.label2) } }
    }
}

/** "지금 대결 중" 한 줄 — 이름 둘 · 판돈 · 오른쪽 끝 관전자 수 + [관전] 입구. 큰 글자·입구가 붙는 행은 입구를 글 아래로 내린다(접는 꼴 하나). */
@Composable
private fun LiveRow(tetris: TetrisDuelStore, live: TetrisDuelLiveMatch, isLast: Boolean) {
    val colors = AingTheme.colors
    val hasEntry = GamesTetrisWatchPlan.hasTrailingContent(tetris, live)
    val stacked = LocalDensity.current.fontScale >= 1.3f
    val texts: @Composable (Modifier) -> Unit = { m ->
        // 합치기는 **이 글 묶음에만** — 행 전체를 합치면 [관전]이 삼켜져 보이스오버가 누를 수 없다.
        Column(m.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(TetrisPhoneText.liveRow(live.a.displayName, live.b.displayName), style = rowTitleStyle(), color = colors.label)
            StakeLine(live.stake.rawValue, prefix = TetrisPhoneText.stakeTitle)
        }
    }
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding, minHeight = 48.dp) {
        if (stacked && hasEntry) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                texts(Modifier)
                GamesTetrisWatchEntry(tetris, live)
            }
        } else {
            texts(Modifier.weight(1f))
            GamesTetrisWatchEntry(tetris, live)
        }
    }
}

// MARK: 판돈 시트

/**
 * 판돈 시트: **아무것도 안 골라진 채** 열리고, 판돈은 고르기만(다시 누르면 해제), 신청은 맨 아래 채운 버튼 하나.
 * INV-GamesTetrisDuelScreen-f4a00bd4 이식: 캡션이 **거짓말을 하지 않는 것**이 이 시트의 계약이다 — 신청만 한 상태에서는 0원도 안 움직이고 양쪽에서
 *   빠지는 것은 **수락하는 순간**이다(서버 §2.4). 그래서 캡션은 문구 표 TetrisPhoneText.stakeCaption 한 줄 그대로다("신청하면 빠져요"로 적지 않는다).
 */
@Composable
private fun GamesTetrisStakeSheet(store: GamesStore, target: TetrisDuelUser, onDismiss: () -> Unit) {
    val tetris = store.tetris
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    var selected by remember(target.id) { mutableStateOf<TetrisDuelStake?>(null) }
    val balance = store.rubyBalance
    // 지금 신청을 **낼 수 있는 판돈**(못 내면 null). 판정은 GamesTetrisDuelStakeSend 한 곳 — 요청이 나가는 마지막 문.
    val sendable = GamesTetrisDuelStakeSend.sendable(selected, tetris, balance, store.tetrisEntryBlock)
    GamesSheet(onDismiss) {
        GamesHeaderBar(TetrisPhoneText.stakeTitle, subtitle = TetrisPhoneText.stakePromptTitle(target.displayName), onBack = onDismiss, backIcon = AppIcon.Close)
        Column(Modifier.padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2), verticalArrangement = Arrangement.spacedBy(AingDimens.space4)) {
            InsetGroup {
                GroupRow(dividerInset = null, minHeight = 64.dp) {
                    PersonAvatar(target.displayName, target.id, 44.dp, working = target.isWorking)
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        PersonName(target.displayName)
                        Text(
                            selected?.let { TetrisPhoneText.stakePromptChosen(it.rawValue) } ?: TetrisPhoneText.stakePromptCaption,
                            style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = if (selected == null) colors.label2 else colors.accent,
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TetrisDuelStake.entries.forEach { stake ->
                    StakeOption(stake, selected == stake, GamesTetrisStakeSelection.affordable(stake, balance), !tetris.isBusy, Modifier.weight(1f)) {
                        selected = GamesTetrisStakeSelection.toggled(selected, stake)
                    }
                }
            }
            Column(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(TetrisPhoneText.myRubyTitle, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                    if (balance != null) RubyPrice(balance, isShort = false, art = rememberRubyArt(14f), gemSize = 14.dp, fontSize = 13f)
                    else Text(TetrisPhoneText.unknownNumber, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                    if (TetrisDuelStake.entries.any { !GamesTetrisStakeSelection.affordable(it, balance) }) {
                        Text(TetrisPhoneText.bulletPrefix + TetrisPhoneText.stakeShortfall, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                    }
                }
                Text(TetrisPhoneText.stakeCaption, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
            // INV-GamesTetrisDuelScreen-2718eb7c 이식: 아무것도 안 고르면 글자가 "판돈을 고르세요" 이고 **비활성**이다 — 골라야 [신청]이 생긴다.
            PillButton(
                selected?.let { TetrisPhoneText.challengeWithStake(it.rawValue) } ?: TetrisPhoneText.stakePromptCaption,
                Modifier.testTag(TetrisDuelTags.STAKE_SEND).padding(bottom = AingDimens.space3), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true,
                enabled = sendable != null,
            ) {
                val stake = sendable ?: return@PillButton
                onDismiss()
                scope.launch { tetris.challenge(target.id, stake) }
            }
        }
    }
}

/** 판돈 칸 하나 — **고르기만** 한다(선택 = 파랑 틴트 + 파랑 테두리 + 체크). 모자라면 흐린 가격 + 비활성, 잔액을 모르면 막지 않는다. */
@Composable
private fun StakeOption(stake: TetrisDuelStake, isSelected: Boolean, affordable: Boolean, notBusy: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    Box(
        modifier.heightIn(min = 72.dp).clip(shape).background(if (isSelected) colors.accentTint else colors.surface, shape)
            .then(if (isSelected) Modifier.border(2.dp, colors.accent, shape) else Modifier)
            .clickable(enabled = affordable && notBusy, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = TetrisPhoneText.stakeOptionAccessibility(stake.rawValue)
                stateDescription = if (isSelected) TetrisPhoneText.selected else if (affordable) "" else TetrisPhoneText.stakeShortfall
                selected = isSelected
            }
            .testTag(TetrisDuelTags.stake(stake.rawValue)),
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            RubyPrice(stake.rawValue.toLong(), isShort = !affordable, art = rememberRubyArt(20f), gemSize = 20.dp, fontSize = 20f)
            Text(
                TetrisPhoneText.stakeGain(stake.rawValue), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal, fontFeatureSettings = TNUM),
                color = if (affordable) colors.label2 else colors.label3Text,
            )
        }
        if (isSelected) {
            Box(Modifier.align(Alignment.TopEnd).padding(7.dp)) {
                AingIcon(AppIcon.CheckCircleFill, contentDescription = null, size = 16.dp, tint = colors.accent)
            }
        }
    }
}

// MARK: 규칙 시트

/**
 * 규칙 시트 — 문구 표의 rules 를 그대로 그린다.
 * INV-GamesTetrisDuelScreen-f9c0f0ec 이식: "앱을 나가면" 항목이 **맥과 다른 사실**이다(P7) — 맥은 "창을 가려도 판은 흘러간다"가 안심이고, 폰은 앱을
 *   나가면 15초 침묵으로 **진다**. 문장은 문구 표(TetrisPhoneText.rules) 한 곳이 쥐고 이 시트는 지어내지 않는다.
 */
@Composable
private fun GamesTetrisRulesSheet(onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    GamesSheet(onDismiss) {
        GamesHeaderBar(TetrisPhoneText.rulesTitle, onBack = onDismiss, backIcon = AppIcon.Close)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space3)) {
            InsetGroup {
                TetrisPhoneText.rules.forEachIndexed { index, (title, detail) ->
                    GroupRow(dividerInset = if (index == TetrisPhoneText.rules.size - 1) null else AingDimens.cardPadding, modifier = Modifier.semantics(mergeDescendants = true) { }) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(title, style = rowTitleStyle(), color = colors.label)
                            Text(detail, style = rowSubtitleStyle(), color = colors.label2)
                        }
                    }
                }
            }
            SectionHeader(TetrisPhoneText.controlsTitle, padded = true)
            InsetGroup {
                TetrisPhoneText.controls.forEachIndexed { index, (gesture, action) ->
                    GroupRow(dividerInset = if (index == TetrisPhoneText.controls.size - 1) null else AingDimens.cardPadding, modifier = Modifier.semantics(mergeDescendants = true) { }) {
                        Text(gesture, style = rowSubtitleStyle(), color = colors.label, modifier = Modifier.weight(1f))
                        Text(action, style = rowSubtitleStyle(), color = colors.label2)
                    }
                }
            }
            Spacer(Modifier.height(AingDimens.space6))
        }
    }
}
