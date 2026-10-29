// 원본: Sources/CheckMobileKit/Games/GamesChessScreen.swift @ 3bd04bd
//
// 1:1 체스 화면 — 코어 `ChessStore` 의 단계(로비 · 대국 · 결과)를 한 화면에서 갈아 끼운다. 본은 오목 화면이고 체스에서 달라지는 자리만 바꿨다.
// 수명: 나타나면 `GamesStore.chessScreenDidAppear`, 사라지면 `chessScreenDidDisappear`(관전을 먼저 내리고 창을 내린다 — 그 순서가 계약이다).
//
// INV-GamesChessScreen-0143e42f 이식: **순위·관전은 로비 안 절이다 — 새 목적지로 밀지 마라.** 스토어가 `phase == lobby` 를 요구하고(`shouldPollWatch` ·
//   `startWatching` 의 가드), 자식 목적지를 밀면 이 화면이 컴포지션에서 빠져 `windowDidHide()` 로 폴링이 죽는다. 로봇 판 화면·판돈·규칙·승격·확인도
//   전부 **화면 안 덮개**다(이 파일의 [ChessScreen] Box 안).
// INV-GamesChessScreen-cf0d3a18 이식: **로그인을 보지 않는다.** 로봇 판(`ChessStoreAI`)은 서버를 한 번도 안 타므로 비로그인 사용자도 둔다 — 이 화면은 세션을
//   묻지 않고, 1:1 절들만 스토어가 세션 없이 조용히 비어 있다.
// INV-GamesChessScreen-0f1d0758 이식: 체스 로비만 데모 바닥 닻이 없어 순위·관전 절을 아무도 눈으로 못 봤다(D5) — Android 는 데모 경로를 옮기지 않는다(C§3.2).
//   같은 목적(맨 아래 두 절이 실제로 그려지는가)은 스냅숏 시험이 로비 전체 높이로 그려 잰다(ChessScreenSnapshot*Test).
// INV-GamesChessScreen-bfc84bce 이식: 데모 닻 둘을 게임 탭이 아니라 화면에 둔 까닭(목적지 클로저에서 관전 여부를 읽으면 체스 화면이 헐려 관전이 영영 안 섰다) —
//   Android 는 관전 여부를 **목적지 쪽에서 읽지 않는다**: 목적지(androidApp ChessDestination)는 섹션 인자만 넘기고 관전 상태는 이 화면 안에서만 읽는다.
// INV-GamesChessScreen-719627c6 이식: 데모 라우트 꼬리는 DEBUG 전용 값이다 — Android 는 데모 경로 자체가 없어(C§3.2) 출시물에 데모 타입 이름이 0 이다.
//
// 판돈 대결 진입(§8-17 #1): 깃발이 꺼지면 [도전]과 "신청하고 받을 수 있어요" 캡션을 숨기고, 받은 신청은 카드 통째([거절]·[수락])가 스토어의 접힌
// 한 줄로 선다. 판돈 시트의 보내기 문(`GamesChessStakeSend.sendable`)도 깃발을 본다. 로봇 판·관전·순위·무승부 왕복은 그대로다.
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.chess.ChessInvite
import com.yehsung.aingcheck.core.stores.chess.ChessMatchOutcome
import com.yehsung.aingcheck.core.stores.chess.ChessPhase
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.core.stores.chess.leaveWatch
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesChessChallengeGate
import com.yehsung.aingcheck.core.stores.games.GamesLobbyRoster
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.gomoku.BarIcon
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardCaption
import com.yehsung.aingcheck.ui.games.gomoku.BoardConfirmOverlay
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoadFailure
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoading
import com.yehsung.aingcheck.ui.games.gomoku.BoardMatchFeedback
import com.yehsung.aingcheck.ui.games.gomoku.BoardScreenPresence
import com.yehsung.aingcheck.ui.games.gomoku.BoardNotice
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardSectionHeader
import com.yehsung.aingcheck.ui.games.gomoku.BoardStakeLine
import com.yehsung.aingcheck.ui.games.gomoku.BoardSummary
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.WatcherBadge
import com.yehsung.aingcheck.ui.games.gomoku.rememberTicker
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

object ChessScreenTags {
    const val screen = "chess-screen"
    const val lobby = "chess-lobby"
    const val lobbyRefresh = "chess-lobby-refresh"
    const val match = "chess-match"
    const val board = "chess-board"
    const val watchBoard = "chess-watch-board"
    const val back = "chess-back"
    const val rules = "chess-rules"
    const val stakeSheet = "chess-stake-sheet"
    const val stakeSend = "chess-stake-send"
    const val rulesSheet = "chess-rules-sheet"
    const val promotionSheet = "chess-promotion-sheet"
    const val robotConfirm = "chess-robot-confirm"
    const val resignConfirm = "chess-resign-confirm"
    const val leaveConfirm = "chess-leave-confirm"
    const val robotEntry = "chess-robot-entry"
    const val robotScreen = "chess-robot-screen"
    const val rankingToggle = "chess-ranking-toggle"
    const val incomingNotice = "chess-incoming-folded"
    const val blockedNotice = "chess-blocked-notice"
    const val leaveWatch = "chess-leave-watch"
    const val resign = "chess-resign"
    const val offerDraw = "chess-offer-draw"
    fun challenge(userID: String): String = "chess-challenge-$userID"
    fun accept(inviteID: String): String = "chess-accept-$inviteID"
    fun decline(inviteID: String): String = "chess-decline-$inviteID"
    fun watch(matchID: String): String = "chess-watch-$matchID"
    fun stakeOption(stake: Long): String = "chess-stake-$stake"
}

/** 화면 상태(Swift `@State` 묶음 + 판마다 하나씩 쥐는 애니메이션 주인 둘). */
@Stable
class ChessScreenState {
    var stakeTarget: ChessUser? by mutableStateOf(null)
    /** 로봇 판을 두는 중에 누른 [수락] — 확인을 거쳐야 보낸다. */
    var acceptNeedsRobotConfirm: ChessInvite? by mutableStateOf(null)
    var confirmsResign: Boolean by mutableStateOf(false)
    var confirmingLeave: Boolean by mutableStateOf(false)
    var rankingExpanded: Boolean by mutableStateOf(false)
    /** [로봇과 두기] 화면(덮개 — iOS fullScreenCover 자리). */
    var robotScreenOpen: Boolean by mutableStateOf(false)
    var shownAt: SwiftDate? = null
    /** 내 판(1:1 · 로봇) 애니메이션 주인과 관전 판 주인(Swift 세 깔때기 중 둘씩). */
    val matchFlight: ChessFlightTracker = ChessFlightTracker()
    val watchFlight: ChessFlightTracker = ChessFlightTracker()
    /** 애니메이션 다시 그리기 펌프(주인은 상태가 아니다 — 거둘 때 이 칸을 올린다). */
    var flightVersion: Int by mutableStateOf(0)

    /**
     * 두 판의 날던 수를 거둔다(INV-ChessStore-635cb077 · 221d2393 — 창 숨김 · 가림 순간).
     * 화면 루트가 관찰 가능한 숨김·가림 신호의 **전환 순간**에 부른다([ChessScreen] — 재조성을 기다리지 않는다).
     */
    fun clearFlights() {
        if (matchFlight.flight == null && watchFlight.flight == null) return
        matchFlight.clear()
        watchFlight.clear()
        flightVersion += 1
    }

    fun hasOverlay(chess: ChessStore): Boolean =
        stakeTarget != null || acceptNeedsRobotConfirm != null || confirmsResign || confirmingLeave || chess.isRulesVisible || chess.promotion != null

    private var observedMatch = false
    private var lastMatchID: String? = null

    /** 화면이 본 판 id 를 적는다 — 처음 본 값은 변화가 아니다(Swift `onChange(of:)` 는 나타날 때 안 불린다). 그다음 바뀌면 [matchChanged]. */
    fun observeMatch(id: String?) {
        if (observedMatch && id != lastMatchID) matchChanged()
        observedMatch = true
        lastMatchID = id
    }

    fun matchChanged() {
        stakeTarget = null
        acceptNeedsRobotConfirm = null
        confirmsResign = false
    }
}

object ChessBackPlan {
    /**
     * Android 뒤로가기(E:56): 덮개 → 로봇 판 화면(닫기 — 판은 남는다) → 사람과의 판이 흐른다(확인) → 관전 중(관전만 나간다) → 떠난다.
     * 로봇 판은 확인하지 않는다(떠나면 로봇 시계가 멈춘다 — 잃을 것이 없다).
     */
    fun step(hasOverlay: Boolean, robotScreenOpen: Boolean, hasLiveHumanMatch: Boolean, isSpectating: Boolean): BoardBackStep = when {
        hasOverlay || robotScreenOpen -> BoardBackStep.CloseOverlay
        hasLiveHumanMatch -> BoardBackStep.ConfirmLeave
        isSpectating -> BoardBackStep.LeaveWatch
        else -> BoardBackStep.Leave
    }

    fun step(state: ChessScreenState, chess: ChessStore): BoardBackStep = step(
        hasOverlay = state.hasOverlay(chess),
        robotScreenOpen = state.robotScreenOpen,
        hasLiveHumanMatch = chess.match?.let { !it.isFinished } == true && !chess.isAIMatch,
        isSpectating = chess.spectating != null,
    )
}

@Composable
fun rememberChessScreenState(): ChessScreenState = remember { ChessScreenState() }

/** 뒤로가기 한 번. 소비했으면 true, 떠나야 하면 false. 승격 고르기는 **`cancelPromotion()` 하나**로만 닫는다(시트의 ✕ 와 같은 문). */
fun ChessScreenState.handleBack(chess: ChessStore): Boolean = when (ChessBackPlan.step(this, chess)) {
    BoardBackStep.CloseOverlay -> {
        when {
            confirmingLeave -> confirmingLeave = false
            confirmsResign -> confirmsResign = false
            acceptNeedsRobotConfirm != null -> acceptNeedsRobotConfirm = null
            stakeTarget != null -> stakeTarget = null
            chess.promotion != null -> chess.cancelPromotion()
            chess.isRulesVisible -> chess.isRulesVisible = false
            robotScreenOpen -> robotScreenOpen = false
        }
        true
    }
    BoardBackStep.ConfirmLeave -> { confirmingLeave = true; true }
    BoardBackStep.LeaveWatch -> { chess.leaveWatch(); true }
    BoardBackStep.Leave -> false
}

/** GamesBusyGame → 문구 표의 BusyGame(같은 rawValue — 두 열거를 한 자리에서만 잇는다). */
internal fun GamesBusyGame.chessText(): ChessPhoneText.BusyGame = ChessPhoneText.BusyGame.entries.first { it.rawValue == rawValue }

/**
 * 체스 화면 루트. **로비 상대 목록은 `games.chessLobbyUsers(roster)` 만 읽는다**(차단 약속 — 6차 int-h '[조립 K11]').
 */
@Composable
fun ChessScreen(
    games: GamesStore,
    chess: ChessStore,
    me: BoardGameMe,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    roster: GamesLobbyRoster<ChessUser> = remember(chess) { ChessLobbyRoster(chess) },
    state: ChessScreenState = rememberChessScreenState(),
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val colors = AingTheme.colors
    DisposableEffect(games) {
        // 같은 목적지가 겹쳐 쌓여도 마지막 하나가 내려갈 때만 창을 내린다(오목과 같은 셈 — BoardScreenPresence).
        BoardScreenPresence.enter(games, "chess")
        games.chessScreenDidAppear()
        onDispose {
            if (BoardScreenPresence.leave(games, "chess")) {
                games.chessScreenDidDisappear()
                onTabBarHidden(false)
            }
        }
    }
    // INV-ChessStore-635cb077 · 221d2393(화면 몫): 창이 숨거나 **가려지는 순간** 날던 수를 거둔다. 코어 `isWindowOccluded` 는 관찰 상태가 아니라(W2-d)
    //   가림만 바뀌면 재조성이 안 일어난다 — 폰의 가림은 게임 탭 스토어의 `appDidEnterBackground` 한 문에서만 서므로(`isAppActive` 를 내리고 같은 호출에서
    //   가린다) 관찰 상태 둘(`chess.isWindowVisible` · `games.isAppActive`)의 전환을 snapshotFlow 로 받는다. 배경에서는 프레임 시계가 멈춰 재조성이
    //   안 돌지만 이 수집은 메인 디스패처에서 돈다(돌아온 순간 끝나던 수의 토막이 다시 미끄러지지 않는다).
    LaunchedEffect(games, chess, state) {
        snapshotFlow { !chess.isWindowVisible || !games.isAppActive }
            .collect { hidden -> if (hidden) state.clearFlights() }
    }
    // 1:1 대국·결과와 로봇 판 화면(iOS fullScreenCover)은 탭 막대를 숨긴다(ChessTabBarPolicy — 셸이 그린다, assembly.md).
    val hidesTabBar = ChessTabBarPolicy.hidesTabBar(chess.match != null && !chess.isAIMatch && chess.phase != ChessPhase.lobby) || state.robotScreenOpen
    LaunchedEffect(hidesTabBar) { onTabBarHidden(hidesTabBar) }
    LaunchedEffect(chess.match?.id) {
        state.observeMatch(chess.match?.id)
        state.shownAt = chess.clock()
    }
    // 햅틱(Swift 대국 화면 `.sensoryFeedback(won ? .success : .warning, trigger: match.isFinished)`) — 1:1 판이 보는 동안 끝나면 한 번.
    val haptics = LocalHapticFeedback.current
    val feedback = remember { BoardMatchFeedback() }
    val humanMatchID = chess.match?.takeIf { !chess.isAIMatch }?.id
    val humanFinished = chess.match?.takeIf { !chess.isAIMatch }?.isFinished
    LaunchedEffect(humanMatchID, humanFinished) {
        if (feedback.ended(humanMatchID, humanFinished)) {
            haptics.performHapticFeedback(if (chess.match?.outcome == ChessMatchOutcome.won) HapticFeedbackType.Confirm else HapticFeedbackType.Reject)
        }
    }
    Box(modifier.fillMaxSize().background(colors.background).testTag(ChessScreenTags.screen)) {
        Column(Modifier.fillMaxSize()) {
            ChessTopBar(chess, onBack = { if (!state.handleBack(chess)) onLeave() })
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (chess.phase) {
                    // 대국·결과는 한 화면이 맡는다. 판이 없으면 로비(늦게 온 응답이 단계만 올려 놓고 판을 못 세운 틈). 로봇 판은 로봇 화면(덮개)이 그린다.
                    ChessPhase.playing, ChessPhase.result ->
                        if (chess.match != null && !chess.isAIMatch) ChessMatchView(chess, me, state) else ChessLobby(games, chess, roster, state)
                    ChessPhase.lobby -> ChessLobby(games, chess, roster, state)
                }
            }
        }
        if (state.robotScreenOpen) ChessRobotScreen(chess, state, onClose = { state.robotScreenOpen = false })
        // INV-GamesChessScreen-e7b934ee 이식: 규칙 시트의 TTL 은 **로비 응답이 말한 값**이다(코어 `inviteTTLSeconds` — 없으면 60). 상수를 베껴 넘기면 서버가 TTL 을
        //   바꾼 날 규칙 시트만 옛 숫자를 말한다.
        if (chess.isRulesVisible) ChessRulesSheet(chess.initialMs, chess.incrementMs, chess.inviteTTLSeconds.toInt(), onClose = { chess.isRulesVisible = false })
        state.stakeTarget?.let { target -> ChessStakeSheet(games, chess, target, onClose = { state.stakeTarget = null }) }
        chess.promotion?.let { prompt -> ChessPromotionSheet(chess, prompt, myColor = chess.match?.myColor ?: com.yehsung.aingcheck.core.rules.chess.ChessColor.white) }
        state.acceptNeedsRobotConfirm?.let { invite ->
            // INV-GamesChessScreen-649661c9 이식: 로봇 판을 두는 중에 1:1 을 수락하려 하면 **먼저 묻는다** — 안 물으면 두던 로봇 판이 문구도 확인도 없이 사라진다
            //   (서버 `chess__busy` 는 로봇 판을 볼 수 없고 코어 `respond` 에도 가드가 없다). 걸린 루비가 0이라 손실은 없다 — 막지 않고 **묻는다**(60초 TTL).
            BoardConfirmOverlay(
                title = ChessPhoneText.acceptEndsRobotTitle, message = ChessPhoneText.acceptEndsRobotMessage,
                confirmTitle = ChessPhoneText.acceptEndsRobotConfirm, cancelTitle = ChessPhoneText.acceptEndsRobotCancel,
                onConfirm = {
                    state.acceptNeedsRobotConfirm = null
                    chess.scope.launch { chess.respond(invite.id, accept = true) }
                },
                onCancel = { state.acceptNeedsRobotConfirm = null },
                testTag = ChessScreenTags.robotConfirm,
            )
        }
        if (state.confirmsResign) {
            val robot = chess.isAIMatch
            BoardConfirmOverlay(
                title = if (robot) ChessPhoneText.robotResignConfirmTitle else ChessPhoneText.resignConfirmTitle,
                message = if (robot) ChessPhoneText.robotNoRecord else ChessPhoneText.resignConfirmMessage,
                confirmTitle = ChessPhoneText.resignNow, cancelTitle = ChessPhoneText.keepPlaying,
                onConfirm = {
                    state.confirmsResign = false
                    chess.scope.launch { chess.resign() }
                },
                onCancel = { state.confirmsResign = false },
                testTag = ChessScreenTags.resignConfirm,
            )
        }
        if (state.confirmingLeave) {
            BoardConfirmOverlay(
                title = ChessScreenText.leaveConfirmTitle, message = ChessScreenText.leaveConfirmMessage,
                confirmTitle = ChessScreenText.leaveConfirm, cancelTitle = ChessScreenText.leaveCancel,
                onConfirm = { state.confirmingLeave = false; onLeave() },
                onCancel = { state.confirmingLeave = false },
                testTag = ChessScreenTags.leaveConfirm,
            )
        }
    }
}

/** 머리 줄: 뒤로 · 가운데 제목(대국 중이면 판돈 부제 + 관전자 수) · 규칙 책. */
@Composable
private fun ChessTopBar(chess: ChessStore, onBack: () -> Unit) {
    val colors = AingTheme.colors
    val match = chess.match
    val inMatch = match != null && !chess.isAIMatch && chess.phase != ChessPhase.lobby
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        BarIcon(AppIcon.ChevronLeft, "뒤로", ChessScreenTags.back, onClick = onBack)
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(ChessPhoneText.title, style = BoardText.headline(), color = colors.label, maxLines = 1, modifier = Modifier.semantics { heading() })
            if (inMatch && match != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    BoardStakeLine(match.stake, prefix = ChessPhoneText.stakeTitle, suffix = ChessPhoneText.stakeGainSuffix(match.stake), gemSize = 13.dp, style = BoardText.caption())
                    // 내 판을 보는 사람 수(0.3.65) — 판돈 칩 줄에 같이. 0 이면 서지 않는다.
                    if (chess.phase == ChessPhase.playing) WatcherBadge(chess.spectatorCount, style = BoardText.caption())
                }
            }
        }
        BarIcon(AppIcon.MenuBook, ChessPhoneText.rulesTitle, ChessScreenTags.rules) { chess.isRulesVisible = true }
        Spacer(Modifier.size(AingDimens.minimumTarget))
    }
}

// MARK: - 로비

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ChessLobby(games: GamesStore, chess: ChessStore, roster: GamesLobbyRoster<ChessUser>, state: ChessScreenState) {
    // 당겨서 새로고침(Swift `.refreshable { await chess.refreshLobby() }` — 체스는 받은함 RPC 가 없어 로비 한 번).
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            refreshing = true
            chess.scope.launch {
                try { chess.refreshLobby() } finally { refreshing = false }
            }
        },
        modifier = Modifier.fillMaxSize().testTag(ChessScreenTags.lobbyRefresh),
    ) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
    val viewportHeight = maxHeight
    val columnWidth = maxWidth - AingDimens.sideMargin * 2
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag(ChessScreenTags.lobby)
            .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space6),
    ) {
        BoardSummary(
            leftTitle = ChessPhoneText.recordTitle, leftValue = ChessPhoneText.record(chess.record),
            rightTitle = ChessPhoneText.myRubyTitle, rubyBalance = games.rubyBalance?.toLong(),
            leftDescription = ChessPhoneText.myRecordAccessibility(chess.record),
        )
        // 규칙 한 줄 — 시간 수치는 서버가 말한 값에서 만든다.
        BoardCaption(ChessPhoneText.subtitle(chess.initialMs, chess.incrementMs))
        chess.notice?.let { Spacer(Modifier.height(AingDimens.rowSpacing)); BoardNotice(it) }
        ChessBlockedByOtherGame(games)
        chess.incomingFoldedNotice?.let { folded ->
            Spacer(Modifier.height(AingDimens.rowSpacing))
            BoardNotice(folded, Modifier.testTag(ChessScreenTags.incomingNotice))
        }
        ChessIncoming(games, chess, state)
        ChessOutgoing(chess)
        Spacer(Modifier.height(AingDimens.rowSpacing))
        // 로봇과 두기 — 사람 목록 바로 위. 판돈도 순위도 없고 로그인을 보지 않는다.
        ChessRobotEntry(chess, onOpen = { state.robotScreenOpen = true })
        ChessOpponents(games, chess, roster, onChallenge = { state.stakeTarget = it })
        // 관전("지금 대결 중" 목록 + 관전 판)과 순위는 제자리 절이다.
        ChessWatchSection(chess, state, viewportHeight, columnWidth)
        ChessRankingSection(chess, state)
    }
    }
    }
}

/** 한 사람 한 판(B8) — 다른 게임 판이 흐르는 동안 체스를 신청·수락할 수 없다. 버튼만 흐리면 까닭을 모른다(폰엔 호버가 없다) — 절 위에 두 줄로 세운다. */
@Composable
private fun ChessBlockedByOtherGame(games: GamesStore) {
    val playing = games.chessEntryBlock
    if (playing != null) {
        // INV-GamesChessScreen-25d2da86 이식: **두 줄**이다 — 제목(busyTitle)만 그리면 왜 막혔는지만 알고 **언제 풀리는지**를 모른다(둘째 줄 busyHint). 조립은 문구 표가 쥔다.
        // INV-GamesChessScreen-3c1f19b1 이식: 막는 게임을 **박아 두지 않는다** — 체스를 막는 판이 오목·테트리스 둘이다(박아 두면 테트리스 대결 중에 안내가 사라진다).
        val text = ChessPhoneText.entryBlockNotice(playing.chessText(), ChessPhoneText.BusyGame.chess) ?: return
        Spacer(Modifier.height(AingDimens.rowSpacing))
        BoardNotice(text, Modifier.testTag(ChessScreenTags.blockedNotice))
    } else if (games.hasLiveChessRobotGame) {
        // 로봇 판 중에는 [도전]이 막힌다 — 왜인지 말한다. 받은 신청은 막지 않는다(묻고 수락한다).
        Spacer(Modifier.height(AingDimens.rowSpacing))
        BoardNotice(ChessPhoneText.blockedByRobot, Modifier.testTag(ChessScreenTags.blockedNotice), warning = false)
    }
}

/** 받은 신청 — 서버가 한 번에 하나만 말해 준다. */
@Composable
private fun ChessIncoming(games: GamesStore, chess: ChessStore, state: ChessScreenState) {
    val invite = chess.visibleIncoming ?: return
    val colors = AingTheme.colors
    rememberTicker()
    BoardSectionHeader(ChessPhoneText.incomingTitle, trailing = ChessPhoneText.inviteTtlHint(chess.inviteTTLSeconds.toInt()))
    // INV-GamesChessScreen-7e1110b7 이식: 수락이 **루비가 실제로 빠지는 순간**이다(신청만 한 상태에서는 0원도 안 움직인다).
    val canRespond = !chess.isBusy && games.chessEntryBlock == null
    BoardGroup {
        Row(Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, top = 14.dp, bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically) {
            BoardAvatar(invite.peer.displayName, invite.peer.id, 44.dp, working = invite.peer.isWorking)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                BoardPersonName(ChessPhoneText.incomingTitle(invite.peer.displayName), center = invite.peer.center)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BoardStakeLine(invite.stake, prefix = ChessPhoneText.stakeTitle, suffix = ChessPhoneText.stakeGainSuffix(invite.stake))
                    Text(" · " + ChessPhoneText.remainingPhrase(invite.expiresAt.timeIntervalSince(chess.clock())), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2,
                        modifier = Modifier.semantics { contentDescription = ChessPhoneText.remainingAccessibility(invite.expiresAt.timeIntervalSince(chess.clock())) })
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, bottom = AingDimens.cardPadding), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BoardButton(ChessPhoneText.decline, Modifier.weight(1f), kind = BoardButtonKind.Gray, enabled = !chess.isBusy, fillsWidth = true, testTag = ChessScreenTags.decline(invite.id)) {
                chess.scope.launch { chess.respond(invite.id, accept = false) }
            }
            BoardButton(ChessPhoneText.accept, Modifier.weight(1f), kind = BoardButtonKind.Filled, enabled = canRespond, fillsWidth = true, testTag = ChessScreenTags.accept(invite.id)) {
                // INV-GamesChessScreen-4772be4b 이식: 로봇 판을 두는 중이면 **여기서 요청을 내지 않는다** — 확인을 거친다(화면 루트의 확인 덮개).
                if (games.hasLiveChessRobotGame) state.acceptNeedsRobotConfirm = invite
                else chess.scope.launch { chess.respond(invite.id, accept = true) }
            }
        }
    }
}

@Composable
private fun ChessOutgoing(chess: ChessStore) {
    val invite = chess.outgoing ?: return
    val colors = AingTheme.colors
    rememberTicker()
    BoardSectionHeader(ChessPhoneText.outgoingTitle)
    BoardGroup {
        BoardRow(minHeight = 56.dp) {
            BoardAvatar(invite.peer.displayName, invite.peer.id, 36.dp, working = invite.peer.isWorking)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                Text(ChessPhoneText.outgoingTitle(invite.peer.displayName), style = BoardText.rowTitle(), color = colors.label)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BoardStakeLine(invite.stake, prefix = ChessPhoneText.stakeTitle)
                    Text(" · " + ChessPhoneText.remainingPhrase(invite.expiresAt.timeIntervalSince(chess.clock())), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
                }
            }
            BoardButton(ChessPhoneText.cancel, kind = BoardButtonKind.Gray, small = true, enabled = !chess.isBusy) { chess.scope.launch { chess.cancelChallenge() } }
        }
    }
    BoardCaption(ChessPhoneText.stakeNotHeldYet(chess.inviteTTLSeconds.toInt()))
}

/** 상대 고르기 — 근무 중 먼저(코어 순서 그대로) · 대국 중 배지 · 옛 버전 배지. */
@Composable
private fun ChessOpponents(games: GamesStore, chess: ChessStore, roster: GamesLobbyRoster<ChessUser>, onChallenge: (ChessUser) -> Unit) {
    val colors = AingTheme.colors
    val users = games.chessLobbyUsers(roster)
    val facts = remember(chess) { ChessGateFacts(chess) }
    BoardSectionHeader(ChessPhoneText.lobbyTitle, trailing = if (users.isEmpty()) null else ChessPhoneText.peopleCount(users.size))
    BoardGroup {
        if (chess.lobbyLoadFailed) BoardRow(divider = users.isNotEmpty()) { BoardLoadFailure(ChessPhoneText.usersLoadFailed) { chess.scope.launch { chess.refreshLobby() } } }
        if (users.isEmpty()) {
            if (!chess.lobbyLoadFailed) BoardRow {
                if (chess.hasLoadedLobby) Text(ChessPhoneText.emptyUsers, style = BoardText.subheadline(), color = colors.label2) else BoardLoading(ChessPhoneText.loadingUsers)
            }
        } else {
            users.forEachIndexed { index, user ->
                // INV-GamesChessScreen-b5847199 이식: **옛 버전 배지는 단추가 쥐고**("업데이트 필요") 부제는 **근무 축**을 쥔다 — 고르는 자리를 `opponentRow(user)` 하나로
                //   모았다(두 자리가 각자 고르면 한 줄이 같은 문장을 두 번 말하고 근무 중 표시가 사라졌다). 서버 capable 이 null 이면 false(모르는 상대는 불가).
                val lines = ChessPhoneText.opponentRow(user)
                BoardRow(divider = index != users.size - 1, dividerInset = AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
                    BoardAvatar(user.displayName, user.id, 36.dp, working = user.isWorking)
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                        BoardPersonName(user.displayName, center = user.center)
                        Text(lines.subtitle, style = BoardText.rowSubtitle(), color = colors.label2)
                    }
                    // §8-17 #1: 깃발이 꺼지면 단추 자리를 비운다(신청 진입을 숨긴다).
                    if (!chess.duelsLocked) {
                        val enabled = GamesChessChallengeGate.isEnabled(user.isCapable, user.inMatch, facts, games.chessEntryBlock, duelsEnabled = !chess.duelsLocked)
                        if (enabled) {
                            BoardButton(ChessPhoneText.challenge, kind = BoardButtonKind.Tinted, small = true, testTag = ChessScreenTags.challenge(user.id),
                                hint = ChessPhoneText.challengeHint(user.displayName)) { onChallenge(user) }
                        } else {
                            BoardButton(lines.buttonTitle, kind = BoardButtonKind.Gray, small = true, enabled = false, testTag = ChessScreenTags.challenge(user.id)) {}
                        }
                    }
                }
            }
        }
    }
    // 깃발이 꺼진 빌드엔 신청 입구가 없다 — "신청하고 받을 수 있어요"도 세우지 않는다.
    if (!chess.duelsLocked) BoardCaption(ChessPhoneText.lobbyCaption)
}

/** Android 몫 문구(뒤로가기 확인 — E:56). 폰 */
object ChessScreenText {
    const val leaveConfirmTitle: String = "대국 화면을 나갈까요?"
    const val leaveConfirmMessage: String = "나가도 체스 시계는 계속 흘러요. 시간이 다 되면 져요."
    const val leaveConfirm: String = "나가기"
    const val leaveCancel: String = "계속 두기"
}
