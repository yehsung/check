// 원본: 없음 — 오목 스토어(W2-d)를 게임 탭 스토어 문(GamesContext 의 GamesGomokuLink · GamesLobbyRoster)에 잇는 얇은 어댑터.
//
// 6차 통합(int-h) 미결 '[조립 K11] GomokuStore·ChessStore 가 아직 GamesLobbyRoster 를 구현하지 않는다'의 화면 갈래 몫이다. 코어 스토어 파일은
// 닫힌 갈래(조정자) 자리라 고치지 않고, 문을 **화면 갈래 패키지**에 둔다 — 조립(AppContainer)은 이 어댑터를 [GamesContext] 에 넣는다
// (assembly.md). 판정은 하나도 없다: 스토어 값을 문 이름으로 옮기기만 한다(Swift `GomokuStore` 가 같은 이름을 직접 내주던 자리).
package com.yehsung.aingcheck.ui.games.gomoku

import com.yehsung.aingcheck.core.stores.games.GamesGomokuLink
import com.yehsung.aingcheck.core.stores.games.GamesLobbyRoster
import com.yehsung.aingcheck.core.stores.gomoku.GamesGomokuAIThinker
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.isAIMatch
import com.yehsung.aingcheck.core.stores.gomoku.stopWatching

/**
 * 오목 로비의 상대 목록 문. 내주는 것은 코어 `users`(서버 로비 응답 그대로 — 폰은 `hiddenPeerIDs` 를 채우지 않는다, Swift GomokuStore.swift:787).
 * **화면은 이 값을 직접 읽지 않는다** — 게임 탭 스토어의 [com.yehsung.aingcheck.core.stores.games.GamesStore.gomokuLobbyUsers] 를 거쳐
 * 메시지 탭 차단 목록이 걸러진 값을 읽는다(차단 확인 시트의 약속 "오목 신청에서 서로 보이지 않아요").
 */
class GomokuLobbyRoster(private val store: GomokuStore) : GamesLobbyRoster<GomokuUser> {
    override val lobbyUsers: List<GomokuUser> get() = store.users
    override fun lobbyUserID(user: GomokuUser): String = user.id.lowercase()
}

/**
 * 게임 탭 스토어가 오목 스토어에 거는 문(Swift `GamesStore` 가 `context.gomoku` 에서 읽고 부르는 것). [thinker] 는 폰 AI 수 선택기 —
 * 조립 지점이 `store.aiMoveChooser = thinker.chooser` 로 끼운 그 인스턴스를 넘긴다(없으면 허락 문이 아무 일도 안 한다).
 */
class GomokuGamesLink(
    private val store: GomokuStore,
    private val thinker: GamesGomokuAIThinker? = null,
) : GamesGomokuLink {
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

    /** 오목은 받은함(60초 스로틀)으로 신선도를 맞춘다 — 로비 스로틀 조회는 체스 문이다(GamesBoardGameLink 머리말). */
    override fun refreshLobbyIfStale() = Unit

    override val pendingIncomingInviteCount: Int get() = store.pendingIncomingInvites.size
    override fun refreshInboxIfStale() = store.refreshInboxIfStale()
    override fun setAIThinkerAllowed(allowed: Boolean) {
        thinker?.setAllowed(allowed)
    }
}
