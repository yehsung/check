// 원본: Sources/CheckMobileKit/App/MobileContext.swift(게임 탭이 읽는 칸 — gomoku · chess · tetris · router · links.messages · gomokuHost) ·
//       Sources/CheckMobileKit/Games/GamesStore.swift:153-180(aiThinker 를 코어에 끼우는 자리) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.core.stores.chess.stopWatching
import com.yehsung.aingcheck.core.stores.games.GamesBoardGameLink
import com.yehsung.aingcheck.core.stores.games.GamesChessGateFacts
import com.yehsung.aingcheck.core.stores.games.GamesContext
import com.yehsung.aingcheck.core.stores.games.GamesGomokuLink
import com.yehsung.aingcheck.core.stores.games.GamesLobbyRoster
import com.yehsung.aingcheck.core.stores.games.GamesRouter
import com.yehsung.aingcheck.core.stores.gomoku.GamesGomokuAIThinker
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.aiMoveChooser
import com.yehsung.aingcheck.core.stores.gomoku.isAIMatch
import com.yehsung.aingcheck.core.stores.gomoku.isAIThinking
import com.yehsung.aingcheck.core.stores.gomoku.stopWatching
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import kotlinx.coroutines.CoroutineScope

/**
 * 게임 탭 스토어(W2-e `GamesStore`)가 기대는 문맥([GamesContext])의 폰 구현 — Swift `MobileContext` 중 게임 탭이 읽는 칸. 세션·시계·앱 구성·
 * 미니게임 허브 몫은 [PhoneContext] 를 그대로 빌린다(같은 루비 칸 · 같은 범위).
 */
class PhoneGamesContext(private val phone: PhoneContext, override val gomoku: PhoneGomokuLink, override val chess: PhoneChessLink) : GamesContext {
    override val sessionStore: SessionStore get() = phone.sessionStore
    override val appConfig: AppConfig get() = phone.appConfig
    override val scope: CoroutineScope get() = phone.scope
    override val collation: Collation get() = phone.collation
    override val tetris: TetrisDuelStore get() = phone.tetris
    override val router: GamesRouter get() = phone.router

    /** 메시지 탭이 차단해 숨긴 상대(Swift `context.links.messages?.hiddenBlockedPeerIDs`). 메시지 스토어가 없으면 빈 집합. */
    override val hiddenBlockedPeerIDs: Set<String> get() = phone.links.messages?.hiddenBlockedPeerIDs ?: emptySet()

    /**
     * 루비 **공유 미러**(Swift `context.gomokuHost.rubyBalance`). 칸은 Long 하나(G §8-18 #4) — 자르지 않고 그대로 넘긴다.
     */
    override val sharedRubyBalance: Long?
        get() = phone.ruby.rubyBalance

    override fun refreshAchievementsAfterGameResult(game: String) = phone.refreshAchievementsAfterGameResult(game)
}

/**
 * 오목 스토어(W2-d [GomokuStore]) → 게임 탭 문(W2-e [GamesGomokuLink]) + 로비 상대 목록([GamesLobbyRoster]).
 *
 * AI 대국 선택기(Swift `GamesStore.aiThinker`)는 여기서 만들어 코어 `aiMoveChooser` 에 끼운다 — 코어 기본 선택기는 창을 몰라 화면을 떠나도
 * 계속 생각한다(맥 동작). 폰 선택기는 "오목 화면이 보이고 앱이 active"일 때만 생각한다([setAIThinkerAllowed] — 게임 탭 스토어가 화면 수명마다 적는다).
 */
class PhoneGomokuLink(val store: GomokuStore, val aiThinker: GamesGomokuAIThinker = GamesGomokuAIThinker()) :
    GamesGomokuLink, GamesLobbyRoster<GomokuUser> {
    init {
        store.aiMoveChooser = aiThinker.chooser
        aiThinker.isStillNeeded = { board, color ->
            val game = store.aiGame
            store.isAIThinking && game != null && game.board == board && game.aiColor == color
        }
    }

    override val activeMatchID: String? get() = store.activeMatchID
    override val hasMatch: Boolean get() = store.match != null
    override val hasUnfinishedMatch: Boolean get() = store.match?.let { !it.isFinished } ?: false
    override val isAIMatch: Boolean get() = store.isAIMatch
    override val isWindowVisible: Boolean get() = store.isWindowVisible
    override var presentWindow: (() -> Unit)?
        get() = store.presentWindow
        set(value) {
            store.presentWindow = value
        }

    override fun openWindow(focusMatchID: String?) = store.openWindow(focusMatchID)
    override fun windowDidShow() = store.windowDidShow()
    override fun windowDidHide() = store.windowDidHide()
    override fun windowDidClose() = store.windowDidClose()
    override fun windowOcclusionDidChange(visible: Boolean) = store.windowOcclusionDidChange(visible)
    override fun stopWatching() = store.stopWatching()
    override suspend fun catchUp() = store.catchUp()

    /** 오목은 받은함(60초 스로틀)을 쓴다 — 로비 스로틀 문은 체스 몫이라 여기서는 받은함으로 잇는다. */
    override fun refreshLobbyIfStale() = store.refreshInboxIfStale()

    /** 만료 안 된 받은 오목 신청 수(탭 배지). 판돈 깃발이 꺼진 빌드에서는 0(코어가 비운다 — §8-17 #1). */
    override val pendingIncomingInviteCount: Int get() = store.pendingIncomingInvites.size

    override fun refreshInboxIfStale() = store.refreshInboxIfStale()
    override fun setAIThinkerAllowed(allowed: Boolean) = aiThinker.setAllowed(allowed)

    /** 오목 로비는 코어 `users` 그대로(폰은 코어 `hiddenPeerIDs` 를 채우지 않는다 — 차단 거르기는 게임 탭 한 자리). */
    override val lobbyUsers: List<GomokuUser> get() = store.users
    override fun lobbyUserID(user: GomokuUser): String = user.id.lowercase()
}

/** 체스 스토어(W2-d [ChessStore]) → 게임 탭 문(W2-e [GamesBoardGameLink]) + 입구 판정 사실([GamesChessGateFacts]) + 로비 상대 목록. */
class PhoneChessLink(val store: ChessStore) : GamesBoardGameLink, GamesChessGateFacts, GamesLobbyRoster<ChessUser> {
    override val activeMatchID: String? get() = store.activeMatchID
    override val hasMatch: Boolean get() = store.match != null
    override val hasUnfinishedMatch: Boolean get() = store.match?.let { !it.isFinished } ?: false
    override val isAIMatch: Boolean get() = store.isAIMatch
    override val isWindowVisible: Boolean get() = store.isWindowVisible
    override var presentWindow: (() -> Unit)?
        get() = store.presentWindow
        set(value) {
            store.presentWindow = value
        }
    override val hasOutgoing: Boolean get() = store.outgoing != null
    override val isBusy: Boolean get() = store.isBusy

    override fun openWindow(focusMatchID: String?) = store.openWindow(focusMatchID)
    override fun windowDidShow() = store.windowDidShow()
    override fun windowDidHide() = store.windowDidHide()
    override fun windowDidClose() = store.windowDidClose()
    override fun windowOcclusionDidChange(visible: Boolean) = store.windowOcclusionDidChange(visible)
    override fun stopWatching() = store.stopWatching()
    override suspend fun catchUp() = store.catchUp()
    override fun refreshLobbyIfStale() = store.refreshLobbyIfStale()

    /** 체스 로비는 코어 `visibleUsers`(스토어가 쥔 hiddenPeerIDs 까지 거른 값). */
    override val lobbyUsers: List<ChessUser> get() = store.visibleUsers
    override fun lobbyUserID(user: ChessUser): String = user.id.lowercase()
}
