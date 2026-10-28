// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift(진입 · 데모 씨앗 자리) · Sources/CheckMobileKit/Games/GamesStore.swift(routeStep 의 오목 갈래) @ 3bd04bd
//
// 오목 목적지(Dest.Gomoku)의 **진입 함수와 라우트 상수** — 화면 본문은 ui 모듈의 [GomokuScreen](한 화면 안 탭). 내비 배선(NavGraph 의 한 줄)은 조립(K11 —
// 조정자)이 이 함수로 바꾼다(assembly.md). 여기서 하는 일은 셋뿐이다:
//  ① 섹션 인자 → 화면 진입 동작([GomokuEntry.action] — 순수): 판·신청 초점은 화면이 나타나기 **전에** 게임 탭 스토어에 심는다(`gomokuScreenDidAppear` 가 꺼내 쓴다).
//  ② Android 뒤로가기(예측 뒤로가기 포함)를 화면의 뒤로가기 계획([GomokuBackPlan])에 잇는다 — 사람과의 판이 흐르면 "대국은 계속 흘러요" 확인(E:56).
//  ③ 떠나는 길([onLeave] = NavController.popBackStack)은 계획이 '떠난다'일 때만 시스템에 넘긴다.
package com.yehsung.aingcheck.android.screens.games.gomoku

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.GameSection
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.startWatching
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameSafety
import com.yehsung.aingcheck.ui.games.gomoku.GomokuBackPlan
import com.yehsung.aingcheck.ui.games.gomoku.GomokuLobbyRoster
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreen
import com.yehsung.aingcheck.ui.games.gomoku.handleBack
import com.yehsung.aingcheck.ui.games.gomoku.rememberGomokuScreenState

/** 오목 목적지 라우트 상수 — 허브 카드·딥링크·알림이 [Dest.Gomoku] 를 만드는 한 자리(섹션 글자는 [GameSection.raw]). */
object GomokuRoute {
    fun lobby(): Dest.Gomoku = Dest.Gomoku(GameSection.LOBBY.raw)
    fun match(matchID: String?): Dest.Gomoku = Dest.Gomoku(GameSection.MATCH.raw, matchID)
    fun invite(inviteID: String): Dest.Gomoku = Dest.Gomoku(GameSection.INVITE.raw, inviteID)
    fun watch(matchID: String): Dest.Gomoku = Dest.Gomoku(GameSection.WATCH.raw, matchID)
    fun ranking(): Dest.Gomoku = Dest.Gomoku(GameSection.RANKING.raw)
    fun ai(): Dest.Gomoku = Dest.Gomoku(GameSection.AI.raw)
}

/** 섹션 인자 → 진입 동작(순수). 모르는 섹션 글자는 로비로 접는다(오배달 금지 — 빈 화면 대신 로비). */
object GomokuEntry {
    sealed interface Action {
        data object Lobby : Action
        /** 신청·판 초점(`games.pendingGomokuFocusID` — 화면이 나타날 때 `openWindow(focus)` 로 넘어간다). */
        data class Focus(val id: String) : Action
        /** 남의 판 관전(로비 자리에 선다 — 화면이 나타난 뒤 `startWatching`). */
        data class Watch(val matchID: String) : Action
        /** 순위표 절을 펼친 채로. */
        data object Ranking : Action
        /** AI 돌 색 시트를 띄운 채로. */
        data object AIPicker : Action
    }

    fun action(section: String, matchId: String?): Action = when (GameSection.entries.firstOrNull { it.raw == section }) {
        GameSection.INVITE, GameSection.MATCH -> matchId?.let { Action.Focus(it) } ?: Action.Lobby
        GameSection.WATCH -> matchId?.let { Action.Watch(it) } ?: Action.Lobby
        GameSection.RANKING -> Action.Ranking
        GameSection.AI -> Action.AIPicker
        GameSection.LOBBY, null -> Action.Lobby
    }
}

/**
 * 오목 목적지 진입 함수. [games]·[gomoku] 는 조립(AppContainer)이 만든 스토어, [me] 는 게임 화면이 그리는 '나'(나 탭·지금 탭이 이미 아는 값),
 * [safety] 는 대국 채팅의 신고·차단 문(메시지 스토어), [onTabBarHidden] 은 셸의 탭 막대 숨김 문.
 */
@Composable
fun GomokuDestination(
    dest: Dest.Gomoku,
    games: GamesStore,
    gomoku: GomokuStore,
    me: BoardGameMe,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    safety: BoardGameSafety? = null,
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val state = rememberGomokuScreenState()
    val roster = remember(gomoku) { GomokuLobbyRoster(gomoku) }
    val action = remember(dest) { GomokuEntry.action(dest.section, dest.matchId) }
    // 초점은 **나타나기 전에** 심는다(조성 단계 — 효과보다 먼저). 화면이 이미 보이면 게임 탭 스토어의 routeStep 이 코어에 바로 넘긴다.
    remember(dest) {
        when (action) {
            is GomokuEntry.Action.Focus -> if (!games.isGomokuScreenVisible) games.pendingGomokuFocusID = action.id
            GomokuEntry.Action.Ranking -> state.rankingExpanded = true
            GomokuEntry.Action.AIPicker -> state.showsAIPicker = true
            else -> Unit
        }
        true
    }
    LaunchedEffect(dest) {
        if (action is GomokuEntry.Action.Watch) gomoku.startWatching(action.matchID)
    }
    // 뒤로가기: 계획이 '떠난다'가 아니면 화면이 소비한다(덮개 닫기 · 대국 확인 · 관전 나가기). '떠난다'면 시스템(NavController)이 pop 한다.
    BackHandler(enabled = GomokuBackPlan.step(state, gomoku) != BoardBackStep.Leave) { state.handleBack(gomoku) }
    GomokuScreen(games, gomoku, me, onLeave, modifier, roster = roster, state = state, safety = safety, onTabBarHidden = onTabBarHidden)
}
