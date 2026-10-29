// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift @ 3bd04bd
//
// 1:1 오목 화면 — 코어 `GomokuStore` 의 단계(로비 · 대국 · 결과)를 **한 화면에서** 갈아 끼운다(E§3.2 "한 화면 안 탭").
// 관전(0.3.41)은 로비 자리에 서고, 순위표는 로비 맨 아래 절이며, 규칙·판돈·AI 돌 색·기권 확인은 화면 안 덮개다 — 새 목적지(자식 화면)를
// 밀면 이 화면이 컴포지션에서 빠져 `gomokuScreenDidDisappear` → `windowDidHide()` 로 폴링이 죽는다(Swift 머리말 · E§4.4).
//
// 수명: 나타나면 `GamesStore.gomokuScreenDidAppear`(로비·인박스·진행 판 + 폴링), 사라지면 `gomokuScreenDidDisappear`. 화면 꺼짐 방지는 이 화면이
// 쓰지 않는다 — 주인은 `GamesStore`(판이 도는 동안은 화면을 떠나도 유지, 끝나면 푼다 — Android 조립이 FLAG_KEEP_SCREEN_ON 싱크를 단다).
//
// 판돈 대결 진입(§8-17 #1): `appConfig.duelsEnabled` 가 꺼진 빌드는 [도전] · 결과의 [같은 판돈으로 다시 신청] · 로비의 "신청하고 받을 수 있어요"
// 캡션을 **숨기고**, 받은 신청은 카드 통째([거절]·[수락] 둘 다)가 스토어의 접힌 한 줄(`incomingFoldedNotice`)로 바뀐다(스토어 `duelsLocked` 한 문 —
// 스토어도 짝으로 신청·수락 RPC 를 막는다). AI 대국 · 관전 · 순위는 그대로다.
//
// Android 몫(iOS 에 없는 것): 뒤로가기 계획([GomokuBackPlan]) — 덮개 닫기 → (사람과의 판이 흐르면) "대국은 계속 흘러요" 확인 → (관전 중이면) 관전 나가기 →
// 화면 떠나기(E:56 · G §2-3 W4-a ③).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.stores.games.GamesLobbyRoster
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhase
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuTapPreview
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.isAIMatch
import com.yehsung.aingcheck.core.stores.gomoku.leaveWatch
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 시험·조립이 잡는 표지(testTag). 글자는 바꾸지 않는다 — 시험이 이 값으로 찾는다. */
object GomokuScreenTags {
    const val screen = "gomoku-screen"
    const val lobby = "gomoku-lobby"
    const val lobbyRefresh = "gomoku-lobby-refresh"
    const val match = "gomoku-match"
    const val result = "gomoku-result"
    const val watch = "gomoku-watch"
    const val board = "gomoku-board"
    const val back = "gomoku-back"
    const val rules = "gomoku-rules"
    const val more = "gomoku-more"
    const val resign = "gomoku-resign"
    const val stakeSheet = "gomoku-stake-sheet"
    const val rulesSheet = "gomoku-rules-sheet"
    const val aiSheet = "gomoku-ai-sheet"
    const val leaveConfirm = "gomoku-leave-confirm"
    const val resignConfirm = "gomoku-resign-confirm"
    const val aiEntry = "gomoku-ai-entry"
    const val rankingToggle = "gomoku-ranking-toggle"
    const val incomingNotice = "gomoku-incoming-folded"
    const val rematch = "gomoku-rematch"
    const val backToLobby = "gomoku-back-to-lobby"
    const val leaveWatch = "gomoku-leave-watch"
    fun opponent(userID: String): String = "gomoku-opponent-$userID"
    fun challenge(userID: String): String = "gomoku-challenge-$userID"
    fun accept(inviteID: String): String = "gomoku-accept-$inviteID"
    fun decline(inviteID: String): String = "gomoku-decline-$inviteID"
    fun watch(matchID: String): String = "gomoku-watch-$matchID"
    fun stakeOption(stake: Long): String = "gomoku-stake-$stake"
    const val stakeSend = "gomoku-stake-send"
}

/**
 * 화면 상태(Swift `@State` 묶음). 화면 **루트**가 든다 — 관전이 로비 자리에 서는 순간 로비 컴포저블이 빠져도 순위표 펼침이 남아야 한다
 * (Swift `rankingExpanded` 머리말: 로비가 들면 관전 한 번에 펼침이 되돌아갔다).
 */
@Stable
class GomokuScreenState {
    var stakeTarget: GomokuUser? by mutableStateOf(null)
    var showsAIPicker: Boolean by mutableStateOf(false)
    var showsResignConfirm: Boolean by mutableStateOf(false)
    var rankingExpanded: Boolean by mutableStateOf(false)
    /** Android: 사람과의 판이 흐르는 중 뒤로가기 → "대국은 계속 흘러요" 확인(E:56). */
    var confirmingLeave: Boolean by mutableStateOf(false)
    var chatExpanded: Boolean by mutableStateOf(false)
    var focusedForbidden: GomokuForbiddenReason? by mutableStateOf(null)
    /** 대국 채팅 ⋯ [신고하기] — 신고 시트(조립이 넣는 메시지 탭 시트)를 화면 안 덮개로 띄운 대상. */
    var reportTarget: BoardReportTarget? by mutableStateOf(null)
    /** 대국 채팅 ⋯ [차단하기] — 차단 확인 덮개의 대상. **차단은 확인을 지나야만 나간다**(Swift `showsBlockConfirm`). */
    var blockTarget: BoardReportTarget? by mutableStateOf(null)
    var previewVersion: Int by mutableStateOf(0)
    val preview: GomokuTapPreview = GomokuTapPreview()
    val forbiddenMemo: GomokuForbiddenMemo = GomokuForbiddenMemo()
    /** 이 판이 나타난 시각 — [기권] 누름 가드의 기준(GomokuPhoneResignGuard). */
    var shownAt: SwiftDate? = null

    val hasOverlay: Boolean get() = stakeTarget != null || showsAIPicker || showsResignConfirm || confirmingLeave || reportTarget != null || blockTarget != null

    private var observedMatch = false
    private var lastMatchID: String? = null

    /**
     * 화면이 본 판 id 를 적는다. **처음 본 값은 변화가 아니다**(Swift `onChange(of:)` 는 나타날 때 안 불린다) — 진입 섹션이 세운 덮개(AI 시트 ·
     * 순위 펼침)를 첫 조성에서 걷지 않는다. 그다음부터 id 가 바뀌면 [matchChanged].
     */
    fun observeMatch(id: String?) {
        if (observedMatch && id != lastMatchID) matchChanged()
        observedMatch = true
        lastMatchID = id
    }

    /** 판이 갈렸다 — 판에 매인 덮개를 접는다(Swift `onChange(of: match?.id)`). */
    fun matchChanged() {
        stakeTarget = null
        showsResignConfirm = false
        showsAIPicker = false
        focusedForbidden = null
        // 신고·차단 대상은 그 판의 상대다 — 판이 갈리면 대상도 갈린다(Swift: 서랍과 함께 그 시트가 내려간다).
        reportTarget = null
        blockTarget = null
        preview.clear()
    }

    fun closeOverlay() {
        when {
            confirmingLeave -> confirmingLeave = false
            blockTarget != null -> blockTarget = null
            reportTarget != null -> reportTarget = null
            showsResignConfirm -> showsResignConfirm = false
            stakeTarget != null -> stakeTarget = null
            showsAIPicker -> showsAIPicker = false
        }
    }
}

/** 탭 막대를 숨기는 단계인가 — 대국·결과(판이 있을 때). */
object GomokuTabBarPolicy {
    fun hidesTabBar(phase: GomokuPhase, hasMatch: Boolean): Boolean = hasMatch && phase != GomokuPhase.lobby
}

/** 뒤로가기 한 번이 무엇이 되는가(Android 몫 — 순수 판정). */
enum class BoardBackStep { CloseOverlay, ConfirmLeave, LeaveWatch, Leave }

object GomokuBackPlan {
    /**
     * 순서: 덮개 → **사람과의 판이 흐른다**(확인 — 나가도 서버 시계는 흐르고 자동 착수 셋이면 진다) → 관전 중(관전만 나간다 — 로비로) → 떠난다.
     * AI 판은 확인하지 않는다 — 화면을 떠나면 AI 시계가 멈춘다(`aiClockPauses`, 잃을 것이 없다). 끝난 판(결과)도 그냥 떠난다(결과는 접힌다).
     */
    fun step(hasOverlay: Boolean, hasLiveHumanMatch: Boolean, isSpectating: Boolean): BoardBackStep = when {
        hasOverlay -> BoardBackStep.CloseOverlay
        hasLiveHumanMatch -> BoardBackStep.ConfirmLeave
        isSpectating -> BoardBackStep.LeaveWatch
        else -> BoardBackStep.Leave
    }

    fun step(state: GomokuScreenState, gomoku: GomokuStore): BoardBackStep = step(
        hasOverlay = state.hasOverlay,
        hasLiveHumanMatch = gomoku.match?.let { !it.isFinished } == true && !gomoku.isAIMatch,
        isSpectating = gomoku.spectating != null,
    )
}

@Composable
fun rememberGomokuScreenState(): GomokuScreenState = remember { GomokuScreenState() }

/**
 * 뒤로가기 한 번을 처리한다. 화면이 소비했으면 true(Android `BackHandler` 가 그대로 막는다), 떠나야 하면 false(부르는 쪽이 pop).
 */
fun GomokuScreenState.handleBack(gomoku: GomokuStore): Boolean = when (GomokuBackPlan.step(this, gomoku)) {
    BoardBackStep.CloseOverlay -> { closeOverlay(); true }
    BoardBackStep.ConfirmLeave -> { confirmingLeave = true; true }
    BoardBackStep.LeaveWatch -> { gomoku.leaveWatch(); true }
    BoardBackStep.Leave -> false
}

/**
 * 오목 화면 루트. [games] 는 게임 탭 스토어(수명 훅 · 차단 거른 로비 목록 · 루비 미러), [gomoku] 는 코어 오목 스토어.
 * [roster] 는 로비 상대 목록 문 — **화면은 `games.gomokuLobbyUsers(roster)` 만 읽는다**(6차 int-h '[조립 K11]' 차단 약속).
 * [onLeave] 는 화면을 떠나는 길(Android NavController.popBackStack) — 확인을 지난 뒤에만 부른다.
 */
@Composable
fun GomokuScreen(
    games: GamesStore,
    gomoku: GomokuStore,
    me: BoardGameMe,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    roster: GamesLobbyRoster<GomokuUser> = remember(gomoku) { GomokuLobbyRoster(gomoku) },
    state: GomokuScreenState = rememberGomokuScreenState(),
    safety: BoardGameSafety? = null,
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val colors = AingTheme.colors
    DisposableEffect(games) {
        // 같은 목적지가 겹쳐 쌓이면(알림·딥링크) 새 화면이 선 뒤에 옛 화면이 내려간다 — 마지막 하나가 내려갈 때만 창을 내린다([BoardScreenPresence]).
        BoardScreenPresence.enter(games, "gomoku")
        games.gomokuScreenDidAppear()
        onDispose {
            if (BoardScreenPresence.leave(games, "gomoku")) {
                games.gomokuScreenDidDisappear()
                onTabBarHidden(false)
            }
        }
    }
    // 대국·결과는 탭 막대를 숨긴다(Swift `.hidesTabBar(for: .gomokuMatch)` — 몰입 화면 + 대화 서랍). 로비·관전은 보인다. 셸이 그린다(assembly.md).
    val hidesTabBar = GomokuTabBarPolicy.hidesTabBar(gomoku.phase, gomoku.match != null)
    LaunchedEffect(hidesTabBar) { onTabBarHidden(hidesTabBar) }
    val matchID = gomoku.match?.id
    LaunchedEffect(matchID) {
        state.observeMatch(matchID)
        state.shownAt = gomoku.clock()
    }
    // 수가 바뀌면 금수 초점을 지운다(Swift `onChange(of: match.moveCount)`) — 시간 초과 자동 착수·상대 수가 와도 빨간 금수 줄이 1순위로 남아
    // '상대 차례'·'내 차례' 줄을 가리지 않게.
    val moveCount = gomoku.match?.moveCount
    LaunchedEffect(moveCount) { state.focusedForbidden = null }
    // 햅틱(Swift `sensoryFeedback`): 보는 동안 수가 놓이면 착수 한 번(대국 단계만 — 판 캔버스가 선 자리) · 보는 동안 판이 끝나면 이김/그 밖.
    val haptics = LocalHapticFeedback.current
    val feedback = remember { BoardMatchFeedback() }
    val isFinished = gomoku.match?.isFinished
    LaunchedEffect(matchID, moveCount, isFinished) {
        val current = gomoku.match
        val moved = feedback.moved(matchID, moveCount, playing = gomoku.phase == GomokuPhase.playing)
        val ended = feedback.ended(matchID, isFinished)
        if (ended) haptics.performHapticFeedback(if (current?.outcome == GomokuOutcome.won) HapticFeedbackType.Confirm else HapticFeedbackType.Reject)
        else if (moved) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    Box(modifier.fillMaxSize().background(colors.background).testTag(GomokuScreenTags.screen)) {
        Column(Modifier.fillMaxSize()) {
            GomokuTopBar(gomoku, state, onBack = { if (!state.handleBack(gomoku)) onLeave() })
            Box(Modifier.weight(1f).fillMaxWidth()) {
                val match = gomoku.match
                val watch = gomoku.spectating
                when (gomoku.phase) {
                    GomokuPhase.playing -> if (match != null) GomokuMatchView(games, gomoku, match, me, state, safety) else GomokuLobby(games, gomoku, roster, state)
                    GomokuPhase.result -> if (match != null) GomokuResultView(games, gomoku, match, me, state, safety) else GomokuLobby(games, gomoku, roster, state)
                    // 관전(0.3.41)은 **로비 자리**에 선다 — 새 목적지가 아니다(머리말). 대국·결과 갈래에는 두지 않는다: 스토어가 내 판이 진행 중이면
                    // 관전에 들어가지 않고, 내 판이 서면 관전을 내린다(있을 수 없는 상태를 그리는 코드를 두 벌 두지 않는다).
                    GomokuPhase.lobby -> if (watch != null) GomokuWatchView(games, gomoku, watch, state) else GomokuLobby(games, gomoku, roster, state)
                }
            }
        }
        // 덮개(시트·확인)는 루트만 띄운다(Swift 관례: 시트는 화면 루트만).
        if (gomoku.isRulesVisible) GomokuRulesSheet(onClose = { gomoku.isRulesVisible = false })
        state.stakeTarget?.let { target -> GomokuStakeSheet(gomoku, target, onClose = { state.stakeTarget = null }) }
        if (state.showsAIPicker) GomokuAIColorSheet(gomoku, onClose = { state.showsAIPicker = false })
        if (state.showsResignConfirm) {
            val chrome = gomoku.match?.let { com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneMatchChrome(it) }
            if (chrome != null) {
                BoardConfirmOverlay(
                    title = GomokuScreenText.resignConfirmTitle(chrome),
                    message = GomokuScreenText.resignConfirmMessage(chrome),
                    confirmTitle = GomokuPhoneText.resignNow,
                    cancelTitle = GomokuPhoneText.keepPlaying,
                    onConfirm = {
                        state.showsResignConfirm = false
                        gomoku.scope.launch { gomoku.resign() }
                    },
                    onCancel = { state.showsResignConfirm = false },
                    testTag = GomokuScreenTags.resignConfirm,
                )
            }
        }
        // 대국 채팅 ⋯ 의 신고·차단(Swift `GamesGomokuChatDrawer` 의 두 시트) — **화면 안 덮개**다. 목적지(Dest.ReportSheet · Dest.BlockConfirm)로 밀면
        // 대국 화면이 컴포지션에서 빠져 폴링·관전이 죽는다(E§4.4 · G ②). 차단은 확인을 지나야만 나가고, 뒤에는 이 판의 채팅을 끈다(판은 그대로 — 판돈).
        if (safety != null) {
            state.blockTarget?.let { target ->
                BoardSheetFrame(onDismiss = { state.blockTarget = null }, testTag = BoardSafetyTags.blockSheet) {
                    safety.blockConfirmSheet(
                        target.peerName,
                        {
                            state.blockTarget = null
                            safety.block(target.peerID)
                            gomoku.muteChatAfterBlock()
                        },
                        { state.blockTarget = null },
                    )
                }
            }
            state.reportTarget?.let { target ->
                BoardSheetFrame(onDismiss = null, testTag = BoardSafetyTags.reportSheet) {
                    safety.reportSheet(
                        target,
                        { blocked ->
                            state.reportTarget = null
                            // '신고하면서 차단'은 서버가 이미 차단했다 — 화면도 같은 순간에 상대 말을 덮는다(Swift `onSent(blocked)` → muteAfterBlock).
                            if (blocked) gomoku.muteChatAfterBlock()
                        },
                        { state.reportTarget = null },
                    )
                }
            }
        }
        if (state.confirmingLeave) {
            BoardConfirmOverlay(
                title = GomokuScreenText.leaveConfirmTitle,
                message = GomokuScreenText.leaveConfirmMessage,
                confirmTitle = GomokuScreenText.leaveConfirm,
                cancelTitle = GomokuScreenText.leaveCancel,
                onConfirm = {
                    state.confirmingLeave = false
                    onLeave()
                },
                onCancel = { state.confirmingLeave = false },
                testTag = GomokuScreenTags.leaveConfirm,
            )
        }
    }
}

/**
 * 머리 줄(Swift 내비 막대 자리): 뒤로 · 가운데 제목(+ 대국·결과면 판돈 부제와 관전자 수) · 규칙 책 · (대국 중) 더보기[기권].
 * 대국 중 내 판을 보는 사람 수(0.3.65 — 명세 §3 '대국자 본인 화면: 판돈 칩 줄에 같이')는 부제 줄에 선다 — 0 이면 서지 않는다.
 */
@Composable
private fun GomokuTopBar(gomoku: GomokuStore, state: GomokuScreenState, onBack: () -> Unit) {
    val colors = AingTheme.colors
    val match = gomoku.match
    val inMatch = match != null && gomoku.phase != GomokuPhase.lobby
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BarIcon(AppIcon.ChevronLeft, "뒤로", GomokuScreenTags.back, onClick = onBack)
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(GomokuPhoneText.title, style = BoardText.headline(), color = colors.label, maxLines = 1, modifier = Modifier.semantics { heading() })
            if (inMatch && match != null) {
                val chrome = com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneMatchChrome(match)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (chrome.showsStake) {
                        BoardStakeLine(match.stake, prefix = GomokuPhoneText.stakeTitle, suffix = GomokuPhoneText.stakeGainSuffix(match.stake.toInt()), gemSize = 13.dp, style = BoardText.caption())
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                            AingIcon(AppIcon.Memory, contentDescription = null, size = 13.dp, tint = colors.label2)
                            Text(GomokuPhoneText.aiStakeChip, style = BoardText.caption(), color = colors.label2)
                        }
                    }
                    if (gomoku.phase == GomokuPhase.playing) WatcherBadge(gomoku.spectatorCount, style = BoardText.caption())
                }
            }
        }
        BarIcon(AppIcon.MenuBook, GomokuPhoneText.rulesTitle, GomokuScreenTags.rules) { gomoku.isRulesVisible = true }
        if (gomoku.phase == GomokuPhase.playing && match != null) {
            // Swift: 머리 오른쪽 ⋯ 메뉴 안의 [기권](위험 동작을 머리에 바로 두지 않는다). 메뉴는 늘 열리고, 항목만 끝난 판·처리 중에 흐려진다.
            var menuOpen by remember { mutableStateOf(false) }
            Box {
                BarIcon(AppIcon.MoreHoriz, GomokuPhoneText.moreMenu, GomokuScreenTags.more) { menuOpen = true }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(GomokuPhoneText.resign, color = if (!match.isFinished && !gomoku.isBusy) colors.danger else colors.label3Text) },
                        leadingIcon = { AingIcon(AppIcon.Flag, contentDescription = null, size = 20.dp, tint = if (!match.isFinished && !gomoku.isBusy) colors.danger else colors.label3Text) },
                        enabled = !match.isFinished && !gomoku.isBusy,
                        modifier = Modifier.testTag(GomokuScreenTags.resign),
                        onClick = {
                            menuOpen = false
                            // [기권]을 화면이 뜬 직후에는 받지 않는다(로비 [수락] 두 번 누름의 둘째가 떨어지는 경로 — GomokuPhoneResignGuard).
                            if (com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneResignGuard.acceptsTap(state.shownAt, gomoku.clock())) state.showsResignConfirm = true
                        },
                    )
                }
            }
        } else {
            Spacer(Modifier.size(AingDimens.minimumTarget))
        }
    }
}

@Composable
internal fun BarIcon(icon: AppIcon, label: String, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    val colors = AingTheme.colors
    Box(
        Modifier.size(AingDimens.minimumTarget).testTag(tag)
            .let { if (enabled) it.clickable(onClick = onClick) else it }
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        AingIcon(icon, contentDescription = null, size = 22.dp, tint = if (enabled) colors.accent else colors.label3)
    }
}

/** 신고·차단 대상 — **사람**이다(대국 채팅 줄은 1:1 메시지와 다른 표라 그 id 로는 운영자가 못 찾는다 — 메시지 id 를 싣지 않는다). */
data class BoardReportTarget(val peerID: String, val peerName: String)

/**
 * 대국 채팅 서랍의 신고·차단 문(메시지 탭 스토어·시트 — 조립이 넣는다). 없으면 ⋯ 메뉴를 세우지 않는다(Swift `messages == nil`).
 * 두 시트는 **화면 안 덮개**로 그린다 — 조립은 목적지로 밀지 않고 시트 컴포저블을 이 칸에 넣는다(assembly.md).
 *  - [block]: 확인을 지난 차단만 부른다(메시지 스토어 block). 화면이 확인 덮개를 먼저 띄운다.
 *  - [reportSheet]: 메시지 탭과 같은 신고 시트(W3-a `MessagesReportSheet(store, MessagesReportTarget(peerID, peerName), onSent, onClose)`).
 *    `onSent(blocked)` — '신고하면서 차단'이었으면 true(화면이 이 판의 채팅을 끈다).
 *  - [blockConfirmSheet]: 차단 확인 시트(기본은 같은 문구의 [BoardBlockConfirmSheet] — W3-a `MessagesBlockConfirmSheet` 를 넣으면 세 입구가 한 시트를 쓴다).
 */
class BoardGameSafety(
    val block: (peerID: String) -> Unit,
    val reportSheet: @Composable (target: BoardReportTarget, onSent: (blocked: Boolean) -> Unit, onClose: () -> Unit) -> Unit,
    val blockConfirmSheet: @Composable (peerName: String, onConfirm: () -> Unit, onClose: () -> Unit) -> Unit =
        { peerName, onConfirm, onClose -> BoardBlockConfirmSheet(peerName, onConfirm, onClose) },
)
