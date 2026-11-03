// 원본: Sources/CheckMobileKit/Games/GamesReversiScreen.swift:135-459(GamesReversiScreen — 루트 · 시트 넷의 주인 · 로비 스크롤) @ ios-1017-int 879c9952
//
// 폰 아잉 뒤집기 **화면 하나**(판 7 — 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)") — 로비 · 판 · AI 연습 · 결과 · 관전 · 순위를 코어 `phase`·`spectating`
// 으로 갈아 끼운다(체스와 같은 구조). 판정은 전부 core/stores(`GamesReversi*` · `ReversiPhoneText`)이고 이 파일은 배치만 한다.
//
// ── 수명은 직접 코어를 부르지 않는다 ── 나타나면 `GamesStore.reversiScreenDidAppear()`, 사라지면 `…DidDisappear()` 뿐이다. 그 둘이 `openWindow`·`windowDidShow`·
//   `stopWatching`·`windowDidHide`·`windowDidClose` 의 순서와 끝난 판 접기를 쥔다(배선 갈래). 순위·관전은 **자식 목적지가 아니라 이 화면 안의 절**이다 —
//   목적지를 밀면 이 화면이 컴포지션에서 빠져 `windowDidHide()` 로 폴링이 죽는다. 시트(돌 색 · 판돈 · 규칙 · 로봇 판 확인 · 기권 확인)도 전부 **화면 안 덮개**다.
// ── 시트의 주인은 이 루트 하나다 ── 행·카드가 시트를 직접 띄우면 판이 서는 순간(로비가 판 화면으로 바뀌며) 그 행이 사라져 시트가 고아가 된다. 판 id 가 바뀌면
//   판돈·돌 색·로봇 확인·기권 확인을 접는다(규칙 시트는 판 중에도 읽을 수 있어 둔다).
// ── 사람 절(받은·보낸 신청 · 상대 · 관전 · 순위)은 이 기기·서버가 아잉 뒤집기를 할 수 있을 때만 선다 ── 업데이트가 필요하거나 서버가 준비 중이면 안내 한 줄 +
//   로봇 연습만 선다(로봇 연습은 서버를 안 탄다). 서버 `reversi_android_min_build` 가 닫혀 있는 동안에도 화면은 깨지지 않는다 — 상대 줄은 `capable=false` 로
//   [업데이트 필요] 가 서고, 신청 거절(`target_outdated`)은 코어 문구로 선다.
// ── 판돈 대결 깃발(§8-17 #1) ── 꺼진 빌드는 [도전]과 "신청하고 받을 수 있어요" 캡션을 숨기고, 받은 신청은 스토어의 접힌 한 줄로 선다(체스와 같다).
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiInviteBanner
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiLobbyPlan
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiRespond
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiUnavailable
import com.yehsung.aingcheck.core.stores.reversi.ReversiInvite
import com.yehsung.aingcheck.core.stores.reversi.ReversiMatchOutcome
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhase
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.isAIMatch
import com.yehsung.aingcheck.core.stores.reversi.leaveWatch
import com.yehsung.aingcheck.core.stores.reversi.refreshRanking
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.chess.ChessScreenText
import com.yehsung.aingcheck.ui.games.gomoku.BarIcon
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardCaption
import com.yehsung.aingcheck.ui.games.gomoku.BoardConfirmOverlay
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoadFailure
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoading
import com.yehsung.aingcheck.ui.games.gomoku.BoardMatchFeedback
import com.yehsung.aingcheck.ui.games.gomoku.BoardNotice
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardRuby
import com.yehsung.aingcheck.ui.games.gomoku.BoardScreenPresence
import com.yehsung.aingcheck.ui.games.gomoku.BoardSectionHeader
import com.yehsung.aingcheck.ui.games.gomoku.BoardStakeLine
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.WatcherBadge
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

object ReversiScreenTags {
    const val screen = "reversi-screen"
    const val lobby = "reversi-lobby"
    const val lobbyRefresh = "reversi-lobby-refresh"
    const val match = "reversi-match"
    const val board = "reversi-board"
    const val watchBoard = "reversi-watch-board"
    const val back = "reversi-back"
    const val rules = "reversi-rules"
    const val rulesSheet = "reversi-rules-sheet"
    const val stakeSheet = "reversi-stake-sheet"
    const val stakeSend = "reversi-stake-send"
    const val aiEntry = "reversi-ai-entry"
    const val aiColorSheet = "reversi-ai-color-sheet"
    const val robotConfirm = "reversi-robot-confirm"
    const val resignConfirm = "reversi-resign-confirm"
    const val leaveConfirm = "reversi-leave-confirm"
    const val resign = "reversi-resign"
    const val backToLobby = "reversi-back-to-lobby"
    const val rematch = "reversi-rematch"
    const val banner = "reversi-invite-banner"
    const val unavailable = "reversi-unavailable"
    const val blockedNotice = "reversi-blocked-notice"
    const val incomingNotice = "reversi-incoming-folded"
    const val rankingToggle = "reversi-ranking-toggle"
    const val ranking = "reversi-ranking"
    const val watch = "reversi-watch"
    const val leaveWatch = "reversi-leave-watch"
    const val turnLine = "reversi-turn-line"
    const val result = "reversi-result"
    fun challenge(userID: String): String = "reversi-challenge-$userID"
    fun accept(inviteID: String): String = "reversi-accept-$inviteID"
    fun decline(inviteID: String): String = "reversi-decline-$inviteID"
    fun watchChip(matchID: String): String = "reversi-watch-$matchID"
    fun stakeOption(stake: Int): String = "reversi-stake-$stake"
    fun aiColor(name: String): String = "reversi-ai-color-$name"
    fun cell(idx: Int): String = "reversi-cell-$idx"
}

/** 화면 상태(Swift `@State` 묶음). 시트의 주인은 루트 하나다. */
@Stable
class ReversiScreenState {
    /** [로봇과 연습하기] → 돌 색 시트. */
    var showsAIColorSheet: Boolean by mutableStateOf(false)

    /** [도전] → 판돈 시트의 대상. */
    var stakeTarget: ReversiUser? by mutableStateOf(null)

    /** 로봇 판을 두는 중에 누른 [수락] — 확인을 거쳐야 보낸다(`GamesReversiRespond.AcceptRoute.confirmRobot`). */
    var acceptNeedsRobotConfirm: ReversiInvite? by mutableStateOf(null)
    var confirmsResign: Boolean by mutableStateOf(false)
    var confirmingLeave: Boolean by mutableStateOf(false)
    var rankingExpanded: Boolean by mutableStateOf(false)

    /** 이 판이 나타난 시각 — [기권] 누름 가드의 기준(로비 [수락] 두 번 누름의 두 번째가 막 열린 판에 떨어지는 길). */
    var shownAt: SwiftDate? = null

    fun hasOverlay(reversi: ReversiStore): Boolean =
        showsAIColorSheet || stakeTarget != null || acceptNeedsRobotConfirm != null || confirmsResign || confirmingLeave || reversi.isRulesVisible

    private var observedMatch = false
    private var lastMatchID: String? = null

    /** 화면이 본 판 id 를 적는다 — 처음 본 값은 변화가 아니다(Swift `onChange(of:)` 는 나타날 때 안 불린다). 그다음 바뀌면 [matchChanged]. */
    fun observeMatch(id: String?) {
        if (observedMatch && id != lastMatchID) matchChanged()
        observedMatch = true
        lastMatchID = id
    }

    /** 판이 섰다(신청 수락 · 다른 기기에서 연 판을 읽음) — 들고 있던 시트가 로비로 돌아올 때 되살아나지 않게 접는다. */
    fun matchChanged() {
        showsAIColorSheet = false
        stakeTarget = null
        acceptNeedsRobotConfirm = null
        confirmsResign = false
    }
}

@Composable
fun rememberReversiScreenState(): ReversiScreenState = remember { ReversiScreenState() }

/** 탭 막대를 숨기는 화면인가(Swift `TabBarPolicy.Screen.reversiMatch`) — 대국·결과(1:1 · 로봇 연습 모두 · 몰입 화면 + 자체 동작 줄). 로비·관전은 거짓. */
object ReversiTabBarPolicy {
    fun hidesTabBar(phase: ReversiPhase, hasMatch: Boolean): Boolean = hasMatch && phase != ReversiPhase.lobby
}

object ReversiBackPlan {
    /**
     * Android 뒤로가기(체스 E:56 과 같은 서열): 덮개 → 사람과의 판이 흐른다(확인 — 나가도 서버 시계가 흐른다) → 관전 중(관전만 나간다) → 떠난다.
     * 로봇 판은 확인하지 않는다(떠나면 로봇 판 사람 시계가 멈춘다 — 잃을 것이 없다).
     */
    fun step(hasOverlay: Boolean, hasLiveHumanMatch: Boolean, isSpectating: Boolean): BoardBackStep = when {
        hasOverlay -> BoardBackStep.CloseOverlay
        hasLiveHumanMatch -> BoardBackStep.ConfirmLeave
        isSpectating -> BoardBackStep.LeaveWatch
        else -> BoardBackStep.Leave
    }

    fun step(state: ReversiScreenState, reversi: ReversiStore): BoardBackStep = step(
        hasOverlay = state.hasOverlay(reversi),
        hasLiveHumanMatch = reversi.match?.let { !it.isFinished && !it.isAI } == true,
        isSpectating = reversi.spectating != null,
    )
}

/** 뒤로가기 한 번. 소비했으면 true, 떠나야 하면 false. */
fun ReversiScreenState.handleBack(reversi: ReversiStore): Boolean = when (ReversiBackPlan.step(this, reversi)) {
    BoardBackStep.CloseOverlay -> {
        when {
            confirmingLeave -> confirmingLeave = false
            confirmsResign -> confirmsResign = false
            acceptNeedsRobotConfirm != null -> acceptNeedsRobotConfirm = null
            stakeTarget != null -> stakeTarget = null
            showsAIColorSheet -> showsAIColorSheet = false
            reversi.isRulesVisible -> reversi.isRulesVisible = false
        }
        true
    }
    BoardBackStep.ConfirmLeave -> { confirmingLeave = true; true }
    BoardBackStep.LeaveWatch -> { reversi.leaveWatch(); true }
    BoardBackStep.Leave -> false
}

/**
 * 아잉 뒤집기 화면 루트. **로비 상대 목록은 `games.reversiLobbyUsers` 만 읽는다**(차단 거울을 거친 값). [games] 의 `reversi` 가 null 이면(떼어 내기 깃발 끔 ·
 * Windows) 아무것도 그리지 않는다 — 입구가 없으니 닿지 않는 자리지만, 닿아도 빈 화면 대신 [onLeave] 로 물러난다.
 */
@Composable
fun ReversiScreen(
    games: GamesStore,
    me: BoardGameMe,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    state: ReversiScreenState = rememberReversiScreenState(),
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val reversi = games.reversi
    if (reversi == null) {
        LaunchedEffect(Unit) { onLeave() }
        return
    }
    val colors = AingTheme.colors
    DisposableEffect(games) {
        // 같은 목적지가 겹쳐 쌓여도 마지막 하나가 내려갈 때만 창을 내린다(오목·체스와 같은 셈).
        BoardScreenPresence.enter(games, "reversi")
        games.reversiScreenDidAppear()
        onDispose {
            if (BoardScreenPresence.leave(games, "reversi")) {
                games.reversiScreenDidDisappear()
                onTabBarHidden(false)
            }
        }
    }
    val hidesTabBar = ReversiTabBarPolicy.hidesTabBar(reversi.phase, reversi.match != null)
    LaunchedEffect(hidesTabBar) { onTabBarHidden(hidesTabBar) }
    LaunchedEffect(reversi.match?.id) {
        state.observeMatch(reversi.match?.id)
        state.shownAt = reversi.clock()
    }
    // 확인을 띄운 채 판이 끝났다(상대 기권 · 자동 착수 3번) — 끝난 판에 '기권하기'가 남지 않게 접는다.
    LaunchedEffect(reversi.match?.isFinished) { if (reversi.match?.isFinished == true) state.confirmsResign = false }
    // 햅틱(Swift `.sensoryFeedback(won ? .success : .warning, trigger: match.isFinished)` · 판 `.impact(.medium, trigger: moveCount)`).
    val haptics = LocalHapticFeedback.current
    val feedback = remember { BoardMatchFeedback() }
    val match = reversi.match
    LaunchedEffect(match?.id, match?.isFinished) {
        if (feedback.ended(match?.id, match?.isFinished)) {
            haptics.performHapticFeedback(if (reversi.match?.outcome == ReversiMatchOutcome.won) HapticFeedbackType.Confirm else HapticFeedbackType.Reject)
        }
    }
    LaunchedEffect(match?.id, match?.moveCount) {
        if (feedback.moved(match?.id, match?.moveCount, playing = reversi.phase == ReversiPhase.playing)) {
            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        }
    }
    val accept: (ReversiInvite) -> Unit = { invite ->
        when (GamesReversiRespond.acceptRoute(games)) {
            GamesReversiRespond.AcceptRoute.send -> reversi.scope.launch { GamesReversiRespond.accept(games, invite.id) }
            GamesReversiRespond.AcceptRoute.confirmRobot -> state.acceptNeedsRobotConfirm = invite
            GamesReversiRespond.AcceptRoute.blocked -> Unit
        }
    }
    Box(modifier.fillMaxSize().background(colors.background).testTag(ReversiScreenTags.screen)) {
        Column(Modifier.fillMaxSize()) {
            ReversiTopBar(reversi, onBack = { if (!state.handleBack(reversi)) onLeave() })
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (reversi.phase) {
                    // 판이 없으면 로비가 선다 — 늦게 온 응답이 단계만 올려 놓고 판을 못 세운 틈이다(체스·오목과 같은 대체 갈래).
                    ReversiPhase.playing, ReversiPhase.result ->
                        if (reversi.match != null) {
                            Column(Modifier.fillMaxSize()) {
                                // 로봇 연습·끝난 판이 로비를 덮는 동안 온 60초 신청 — 판 위 띠(판정 `GamesReversiInviteBanner`).
                                ReversiInviteBannerView(games, reversi, accept)
                                Box(Modifier.weight(1f).fillMaxWidth()) { ReversiMatchView(reversi, me, state) }
                            }
                        } else {
                            ReversiLobby(games, reversi, state, accept)
                        }
                    ReversiPhase.lobby -> ReversiLobby(games, reversi, state, accept)
                }
            }
        }
        // ★ 숫자 셋은 **로비 응답이 말한 값**이다(응답 전에는 코어 기본값 30 · 3 · 60) — 상수를 베끼면 서버가 바꾼 날 규칙 시트만 옛 숫자다.
        if (reversi.isRulesVisible) {
            ReversiRulesSheet(reversi.turnSeconds, reversi.autoAbandonStreak, reversi.inviteTTLSeconds.toInt(), onClose = { reversi.isRulesVisible = false })
        }
        if (state.showsAIColorSheet) ReversiAIColorSheet(reversi, onClose = { state.showsAIColorSheet = false })
        state.stakeTarget?.let { target -> ReversiStakeSheet(games, reversi, target, onClose = { state.stakeTarget = null }) }
        state.acceptNeedsRobotConfirm?.let { invite ->
            // 로봇 판을 두는 중에 1:1 을 수락하려 한다 — **먼저 묻는다**. 확인 뒤에는 코어가 알아서 로봇 판을 버린다(1:1 판이 서는 순간 `match` 관찰자).
            BoardConfirmOverlay(
                title = ReversiPhoneText.acceptEndsRobotTitle, message = ReversiPhoneText.acceptEndsRobotMessage,
                confirmTitle = ReversiPhoneText.acceptEndsRobotConfirm, cancelTitle = ReversiPhoneText.acceptEndsRobotCancel,
                onConfirm = {
                    state.acceptNeedsRobotConfirm = null
                    reversi.scope.launch { GamesReversiRespond.accept(games, invite.id) }
                },
                onCancel = { state.acceptNeedsRobotConfirm = null },
                testTag = ReversiScreenTags.robotConfirm,
            )
        }
        val current = reversi.match
        if (state.confirmsResign && current != null && !current.isFinished) {
            val robot = current.isAI
            BoardConfirmOverlay(
                title = if (robot) ReversiPhoneText.aiResignConfirmTitle else ReversiPhoneText.resignConfirmTitle,
                message = if (robot) ReversiPhoneText.aiNoRecord else ReversiPhoneText.resignConfirmMessage,
                confirmTitle = ReversiPhoneText.resignNow, cancelTitle = ReversiPhoneText.keepPlaying,
                onConfirm = {
                    state.confirmsResign = false
                    reversi.scope.launch { reversi.resign() }
                },
                onCancel = { state.confirmsResign = false },
                testTag = ReversiScreenTags.resignConfirm,
            )
        }
        if (state.confirmingLeave) {
            // 뒤로가기 확인(Android 몫 — 체스와 같은 제목·단추 글자). 몸글은 **새 글자 없이** 이 판의 시계 규칙 한 줄(iOS `clockLine` — "앱을 나가도 차례 시간은 흘러요 · …")이다.
            BoardConfirmOverlay(
                title = ChessScreenText.leaveConfirmTitle,
                message = ReversiPhoneText.clockLine(isAI = false, turnSeconds = maxOf(1, reversi.turnSeconds), lossStreak = maxOf(1, current?.autoAbandonStreak ?: reversi.autoAbandonStreak)),
                confirmTitle = ChessScreenText.leaveConfirm, cancelTitle = ChessScreenText.leaveCancel,
                onConfirm = { state.confirmingLeave = false; onLeave() },
                onCancel = { state.confirmingLeave = false },
                testTag = ReversiScreenTags.leaveConfirm,
            )
        }
    }
}

/** 머리 줄: 뒤로 · 가운데 제목(대국 중이면 판돈 부제 또는 '로봇과 연습' 칩 + 관전자 수) · 규칙 책(로비와 판 화면 **둘 다** — 판 중에도 규칙을 읽는다). */
@Composable
private fun ReversiTopBar(reversi: ReversiStore, onBack: () -> Unit) {
    val colors = AingTheme.colors
    val match = reversi.match
    val inMatch = match != null && reversi.phase != ReversiPhase.lobby
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        BarIcon(AppIcon.ChevronLeft, "뒤로", ReversiScreenTags.back, onClick = onBack)
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(ReversiPhoneText.title, style = BoardText.headline(), color = colors.label, maxLines = 1, modifier = Modifier.semantics { heading() })
            if (inMatch && match != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (!match.isAI) {
                        BoardStakeLine(match.stake.toLong(), prefix = ReversiPhoneText.stakeTitle, suffix = ReversiPhoneText.stakeGainSuffix(match.stake), gemSize = 13.dp, style = BoardText.caption())
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                            AingIcon(AppIcon.Memory, contentDescription = null, size = 13.dp, tint = colors.label2)
                            Text(ReversiPhoneText.aiStakeChip, style = BoardText.caption(), color = colors.label2, maxLines = 1)
                        }
                    }
                    // 내 판을 보고 있는 사람 수. 0 이면 서지 않으므로 로봇 판에서도 모양이 그대로다.
                    WatcherBadge(reversi.spectatorCount.toLong(), style = BoardText.caption())
                }
            }
        }
        BarIcon(AppIcon.MenuBook, ReversiPhoneText.rulesTitle, ReversiScreenTags.rules) { reversi.isRulesVisible = true }
        Spacer(Modifier.size(AingDimens.minimumTarget))
    }
}

// MARK: - 로비

/**
 * 로비 스크롤. 순서(iOS 그대로): 받은 신청(60초 — 스크롤해야 보이는 자리에 두면 그 사이 만료된다) → 내 전적·루비 → 규칙 한 줄 → 안내 → 다른 게임 판 막힘 →
 * 보낸 신청 → 로봇 연습 → 상대 고르기 → 지금 대결 중(↔ 관전 판) → 순위. 이 기기·서버가 아잉 뒤집기를 못 하면 안내 + 로봇 연습만 선다.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReversiLobby(games: GamesStore, reversi: ReversiStore, state: ReversiScreenState, accept: (ReversiInvite) -> Unit) {
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            refreshing = true
            reversi.scope.launch {
                try {
                    reversi.refreshLobby()
                    reversi.refreshRanking()
                } finally {
                    refreshing = false
                }
            }
        },
        modifier = Modifier.fillMaxSize().testTag(ReversiScreenTags.lobbyRefresh),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val viewportHeight = maxHeight
            val columnWidth = maxWidth - AingDimens.sideMargin * 2
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag(ReversiScreenTags.lobby)
                    .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space6),
            ) {
                if (GamesReversiLobbyPlan.showsPeopleSections(reversi)) {
                    ReversiIncoming(games, reversi, accept)
                    ReversiSummary(games, reversi)
                    // 규칙 한 줄 — 한 수 시간은 **서버가 말한 값**.
                    BoardCaption(ReversiPhoneText.lobbySubtitle(reversi.turnSeconds))
                    ReversiNoticeLine(reversi)
                    reversi.incomingFoldedNotice?.let { folded ->
                        Spacer(Modifier.height(AingDimens.rowSpacing))
                        BoardNotice(folded, Modifier.testTag(ReversiScreenTags.incomingNotice))
                    }
                    ReversiBlockedByOtherGame(games)
                    ReversiOutgoing(reversi)
                    Spacer(Modifier.height(AingDimens.rowSpacing))
                    ReversiAIEntryCard(reversi, onPlay = { state.showsAIColorSheet = true })
                    ReversiOpponents(games, reversi, onChallenge = { state.stakeTarget = it })
                    ReversiWatchSection(reversi, viewportHeight, columnWidth)
                    ReversiRankingSection(reversi, state)
                } else {
                    // 할 수 없는 기기·서버 상태다 — 사람에게 신청하는 길은 서지 않는다. **로봇 연습은 서버를 안 타므로 그대로 연다**.
                    BoardNotice(GamesReversiUnavailable.title(reversi.availability) ?: "", Modifier.testTag(ReversiScreenTags.unavailable))
                    ReversiNoticeLine(reversi)
                    Spacer(Modifier.height(AingDimens.rowSpacing))
                    ReversiAIEntryCard(reversi, onPlay = { state.showsAIColorSheet = true })
                }
            }
        }
    }
}

/** 머리 두 칸 — 내 전적 · 내 루비(공유 미러 먼저 — `GamesStore.rubyBalance` 와 같은 순서). */
@Composable
private fun ReversiSummary(games: GamesStore, reversi: ReversiStore) {
    val colors = AingTheme.colors
    Spacer(Modifier.height(AingDimens.rowSpacing))
    BoardGroup {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Column(
                Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp)
                    .clearAndSetSemantics { contentDescription = ReversiPhoneText.myRecordAccessibility(reversi.record) },
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(ReversiPhoneText.recordTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                Text(ReversiPhoneText.record(reversi.record), style = BoardText.digits(BoardText.headline()), color = colors.label)
            }
            Box(Modifier.width(AingDimens.hairline).fillMaxHeight().background(colors.separator))
            Column(
                Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp).semantics(mergeDescendants = true) {},
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(ReversiPhoneText.myRubyTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                val balance = games.rubyBalance
                if (balance != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                        BoardRuby(20.dp)
                        Text("$balance", style = BoardText.digits(BoardText.headline()), color = colors.label)
                    }
                } else {
                    Text(ReversiPhoneText.unknownNumber, style = BoardText.headline(), color = colors.label)
                }
            }
        }
    }
}

/** 코어 안내(신청·수락·취소 응답 · 관전 못 봄 · 연결) — 거절 까닭(바쁨 · 상대 대국 중 · 상대 앱 모름 · 집중 · 루비 모자람)이 여기 선다. */
@Composable
private fun ReversiNoticeLine(reversi: ReversiStore) {
    val text = reversi.notice ?: return
    Spacer(Modifier.height(AingDimens.rowSpacing))
    BoardNotice(text)
}

/**
 * 한 사람 한 판 — 다른 1:1 판(오목·체스·테트리스·큐브)이 흐르는 동안은 신청·수락을 못 한다. 버튼만 흐려 두면 **왜**인지 모른다(툴팁이 없다).
 * ★ **두 줄**이다: 왜(두는 판의 이름) + 언제 풀리는지. 조립은 문구 표가 쥔다(`GamesBusyText.entryBlockNotice`).
 */
@Composable
private fun ReversiBlockedByOtherGame(games: GamesStore) {
    val text = GamesBusyText.entryBlockNotice(games.reversiEntryBlock, GamesBusyGame.reversi) ?: return
    Spacer(Modifier.height(AingDimens.rowSpacing))
    BoardNotice(text, Modifier.testTag(ReversiScreenTags.blockedNotice))
}

/** 받은 신청 — 서버가 **여럿**을 준다(최신이 앞). 다 세운다: 60초가 각자 흐르므로 안 보이는 사이 만료된다. */
@Composable
private fun ReversiIncoming(games: GamesStore, reversi: ReversiStore, accept: (ReversiInvite) -> Unit) {
    val invites = reversi.visibleIncomingInvites
    if (invites.isEmpty()) return
    BoardSectionHeader(ReversiPhoneText.incomingTitle, trailing = ReversiPhoneText.inviteTtlHint(reversi.inviteTTLSeconds.toInt()))
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing)) {
        for (invite in invites) {
            BoardGroup { ReversiInviteCard(games, reversi, invite, onAccept = accept) }
        }
    }
}

@Composable
private fun ReversiOutgoing(reversi: ReversiStore) {
    val invite = reversi.outgoing ?: return
    BoardSectionHeader(ReversiPhoneText.outgoingTitle)
    BoardGroup { ReversiOutgoingRow(reversi, invite) }
    BoardCaption(ReversiPhoneText.stakeNotHeldYet(reversi.inviteTTLSeconds.toInt()))
}

/** 상대 고르기 — 근무 중 먼저(코어 정렬 그대로) · 막힌 까닭 버튼 · 풀이 줄. 목록은 `games.reversiLobbyUsers` 만(차단 거울). */
@Composable
private fun ReversiOpponents(games: GamesStore, reversi: ReversiStore, onChallenge: (ReversiUser) -> Unit) {
    val colors = AingTheme.colors
    val users = games.reversiLobbyUsers
    BoardSectionHeader(ReversiPhoneText.lobbyTitle, trailing = if (users.isEmpty()) null else ReversiPhoneText.peopleCount(users.size))
    BoardGroup {
        when (GamesReversiLobbyPlan.users(games)) {
            // ★ **정렬하지 않는다** — 코어가 서버와 같은 규칙으로 이미 맞췄다(`sortedForLobby`).
            GamesReversiLobbyPlan.Users.rows -> users.forEachIndexed { index, user ->
                ReversiOpponentRow(games, reversi, user, isLast = index == users.size - 1, onChallenge = onChallenge)
            }
            GamesReversiLobbyPlan.Users.empty -> BoardRow { Text(ReversiPhoneText.emptyUsers, style = BoardText.subheadline(), color = colors.label2) }
            // 불러오기 실패(Android 스토어만 아는 깃발) — 체스 표의 같은 문장 + 공용 [다시 시도].
            GamesReversiLobbyPlan.Users.failed -> BoardRow { BoardLoadFailure(ChessPhoneText.usersLoadFailed) { reversi.scope.launch { reversi.refreshLobby() } } }
            GamesReversiLobbyPlan.Users.loading -> BoardRow { BoardLoading(ReversiPhoneText.loadingUsers) }
        }
    }
    Column(Modifier.semantics(mergeDescendants = true) {}) {
        // 깃발이 꺼진 빌드엔 신청 입구가 없다 — "신청하고 받을 수 있어요"도 세우지 않는다.
        if (!reversi.duelsLocked) BoardCaption(ReversiPhoneText.lobbyCaption)
        // 막힌 [도전]의 뜻 — 목록에 그 까닭이 **있을 때만**(왜 · 언제 풀리는지).
        for (line in GamesReversiLobbyPlan.lockLegends(games)) BoardCaption(line)
    }
}
