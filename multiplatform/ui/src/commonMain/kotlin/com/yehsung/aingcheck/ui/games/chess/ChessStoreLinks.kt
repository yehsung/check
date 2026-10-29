// 원본: 없음 — 체스 스토어(W2-d)를 게임 탭 스토어 문(GamesBoardGameLink · GamesLobbyRoster · GamesChessGateFacts)에 잇는 얇은 어댑터.
//
// 오목 짝(ui/games/gomoku/GomokuStoreLinks.kt)과 같은 까닭이다: 코어 스토어 파일은 닫힌 갈래(조정자) 자리라 고치지 않고 문을 화면 갈래 패키지에 둔다.
// 판정은 하나도 없다 — 값을 문 이름으로 옮기기만 한다. 조립(AppContainer)이 이 어댑터를 GamesContext 에 넣는다(assembly.md).
package com.yehsung.aingcheck.ui.games.chess

import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.core.stores.chess.stopWatching
import com.yehsung.aingcheck.core.stores.games.GamesBoardGameLink
import com.yehsung.aingcheck.core.stores.games.GamesChessGateFacts
import com.yehsung.aingcheck.core.stores.games.GamesLobbyRoster

/**
 * 체스 로비의 상대 목록 문 — 코어 `visibleUsers`(스토어가 쥔 `hiddenPeerIDs` 까지 거른 값, 서버와 같은 규칙으로 이미 정렬). 화면은 이 값을 직접 읽지 않고
 * `games.chessLobbyUsers(roster)` 로 메시지 탭 차단 목록을 한 번 더 겹친 값을 읽는다.
 */
class ChessLobbyRoster(private val store: ChessStore) : GamesLobbyRoster<ChessUser> {
    override val lobbyUsers: List<ChessUser> get() = store.visibleUsers
    override fun lobbyUserID(user: ChessUser): String = user.id.lowercase()
}

/** 게임 탭 스토어가 체스 스토어에 거는 문(Swift `GamesStore` 가 `context.chess` 에서 읽고 부르는 것). */
class ChessGamesLink(private val store: ChessStore) : GamesBoardGameLink {
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
    override fun refreshLobbyIfStale() = store.refreshLobbyIfStale()
}

/** 체스 입구 판정이 읽는 스토어 사실(Swift `GamesChessChallengeGate` 가 읽는 칸 그대로). */
class ChessGateFacts(private val store: ChessStore) : GamesChessGateFacts {
    override val hasOutgoing: Boolean get() = store.outgoing != null
    override val hasMatch: Boolean get() = store.match != null
    override val isBusy: Boolean get() = store.isBusy
}
