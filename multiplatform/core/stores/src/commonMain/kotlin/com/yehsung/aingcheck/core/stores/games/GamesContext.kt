// 원본: Sources/CheckMobileKit/App/MobileContext.swift(게임 탭이 읽는 칸 — gomoku · chess · tetris · router · links · gomokuHost) @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameContext
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore

/**
 * 오목·체스 스토어(W2-d)가 게임 탭 스토어에 내주는 **문** — Swift `GamesStore` 가 `context.gomoku`·`context.chess` 에서 실제로 읽고
 * 부르는 것만 모았다(멤버를 더하면 W2-d 쪽 적합성도 같이 늘린다 — Swift `GomokuStoreHost` 머리말과 같은 규약).
 *
 * 왜 인터페이스인가: 오목·체스 스토어는 같은 웨이브의 W2-d 가 만든다(병렬 갈래). 게임 탭 스토어가 그 타입을 직접 보면 이 갈래가
 * W2-d 보다 먼저 서지 못한다. 병합 뒤 W2-d 의 `GomokuStore`·`ChessStore` 가 이 문을 구현하고(또는 조립 지점이 얇은 어댑터를 두고)
 * 폰 문맥(W2-f)이 [GamesContext] 에 넣는다. 게임 판정(한 사람 한 판 · 화면 수명 순서 · 화면 꺼짐)은 이 갈래에 남는다.
 */
interface GamesBoardGameLink {
    /** 서버가 말한 내 진행 중 대국 id(로비·받은함). 들고 있는 판이 없어도 참일 수 있다. */
    val activeMatchID: String?

    /** 판을 들고 있다(끝난 판 포함 — Swift `match != nil`). */
    val hasMatch: Boolean

    /** 들고 있는 판이 끝나지 않았다(Swift `match != nil && !match.isFinished`). */
    val hasUnfinishedMatch: Boolean

    /** 들고 있는 판이 AI·로봇 판이다(루비·순위가 없고 화면을 떠나면 시계가 멈춘다). */
    val isAIMatch: Boolean

    /** 코어 창 깃발(Swift `isWindowVisible`). */
    val isWindowVisible: Boolean

    /** 판이 막 시작됐을 때 화면을 여는 문(코어가 부른다 — 게임 탭 스토어가 단다). */
    var presentWindow: (() -> Unit)?

    fun openWindow(focusMatchID: String?)
    fun windowDidShow()
    fun windowDidHide()
    fun windowDidClose()
    fun windowOcclusionDidChange(visible: Boolean)

    /** 관전을 조용히 내린다(요청 0건 — Swift `stopWatching()`). */
    fun stopWatching()
    suspend fun catchUp()

    /** 로비 30초 스로틀 조회(체스 — 받은함 RPC 가 없다). 오목은 받은함([GamesGomokuLink.refreshInboxIfStale])을 쓴다. */
    fun refreshLobbyIfStale()
}

/** 오목 쪽에만 있는 문(받은함 · 탭 배지 · AI 선택기). */
interface GamesGomokuLink : GamesBoardGameLink {
    /** 만료 안 된 받은 오목 신청 수(탭 배지). */
    val pendingIncomingInviteCount: Int

    /** 받은함 60초 스로틀 조회. */
    fun refreshInboxIfStale()

    /** AI 대국 수 선택기의 허락(Swift `aiThinker.setAllowed`) — 오목 화면이 보이고 앱이 active 일 때만 생각한다. 선택기는 W2-d 몫. */
    fun setAIThinkerAllowed(allowed: Boolean)
}

/**
 * 오목·체스 로비의 **상대 목록** 문 — 오목·체스 스토어(W2-d)가 자기 사용자 타입 [U](`GomokuUser`·`ChessUser`)로 구현한다.
 * 게임 탭 스토어는 그 타입을 모르므로(병렬 갈래) 목록과 id 꺼내기만 받는다. 차단 거르기는 [GamesStore.gomokuLobbyUsers]·
 * [GamesStore.chessLobbyUsers] 한 자리에서 한다(Swift `GamesStore.gomokuLobbyUsers`·`chessLobbyUsers` — 화면이 읽는 자리도 거기 하나다).
 *
 * 무엇을 내주는가(Swift 가 읽는 칸 그대로):
 *  · 오목 — 코어 `users`(서버 로비 응답 그대로. 폰은 코어 `hiddenPeerIDs` 를 채우지 않는다 — GomokuStore.swift:787).
 *  · 체스 — 코어 `visibleUsers`(스토어가 쥔 `hiddenPeerIDs` 까지 거른 값).
 * 둘 다 **서버와 같은 규칙으로 이미 정렬된** 순서다 — 받는 쪽이 다시 정렬하지 않는다.
 */
interface GamesLobbyRoster<U> {
    val lobbyUsers: List<U>

    /** 그 사람의 user id(소문자 — 메시지 탭 차단 목록 [GamesContext.hiddenBlockedPeerIDs] 와 같은 표기). */
    fun lobbyUserID(user: U): String
}

/**
 * 게임 탭 라우터 문(Swift `context.router` 중 게임 탭이 쓰는 조각 — 탭 고르기 · 쌓인 화면 비우기 · 쌓기). 폰 문맥(W2-f)이 구현한다.
 * Swift `router.open(.gomokuMatch(matchID: nil))` 도 같은 세 조각이라 한 문([present])으로 모았다.
 */
interface GamesRouter {
    /** 게임 탭을 고르고 · 쌓인 화면을 비우고 · [destination] 을 쌓는다. */
    fun present(destination: GamesDestination)

    /**
     * 떠나는 문을 단다(폰 라우터만 — Windows 조립 · 시험 가짜는 큐브가 없어 기본값 그대로다). 라우터가 화면을 옮기기 전에 이 답을 묻는다:
     * true = 지금 간다 · false = 확인을 띄웠다, 수락하면 받은 resume 이 원래 가려던 곳으로 간다.
     */
    fun installDepartureGuard(guard: (resume: () -> Unit) -> Boolean) {}
}

/**
 * 게임 탭 스토어가 기대는 문맥 — Swift `MobileContext` 중 게임 탭이 읽는 칸(W2-a 세션 문맥을 [GamesMiniGameContext] 로 넓힌 위에).
 * 폰 조립(K11 — 조정자)·폰 문맥(W2-f)이 구현한다. 시험은 가짜 문을 넣는다.
 */
interface GamesContext : GamesMiniGameContext {
    val tetris: TetrisDuelStore

    /**
     * 아잉 큐브 스토어(폰 조립이 넣는다). **기본이 null 인 까닭**: 이 문맥을 구현하는 곳에 Windows 조립(desktopApp `AppGraph` — v1 기능 동결)과 시험 조립이
     * 여럿 있다 — 필수로 두면 큐브를 쓰지 않는 그 자리가 전부 깨진다. null 이면 게임 탭은 큐브가 없는 것처럼 돈다(입구 막기·배지·화면 꺼짐 모두 건너뛴다).
     */
    val rummy: RummyStore? get() = null

    /**
     * 아잉 뒤집기 스토어(폰 조립이 넣는다 — 판 7). **기본이 null 인 까닭은 큐브와 같다**(Windows 조립 · 시험 조립이 여럿). 또 하나: 폰 조립도 떼어 내기
     * 깃발(`AppConfig.reversiEnabled`)이 꺼지면 null 을 넣는다 — null 이면 게임 탭은 리버시가 없는 것처럼 돈다(카드 · 배지 · 입구 막기 · 화면 꺼짐 ·
     * 허브 조회 · 화면 문 모두 건너뛴다). 그래서 이 칸 하나가 리버시 입구의 유일한 스위치다.
     */
    val reversi: ReversiStore? get() = null

    /** 1:1 길건너(판 8). 떼어 내기 깃발(`AppConfig.crossyDuelEnabled`)이 꺼지면 null — 게임 탭은 1:1 길건너가 없는 것처럼 돈다. */
    val crossyDuel: com.yehsung.aingcheck.core.stores.crossy.CrossyDuelStore? get() = null
    val gomoku: GamesGomokuLink
    val chess: GamesBoardGameLink
    val router: GamesRouter

    /** 메시지 탭이 차단해 숨긴 상대(Swift `context.links.messages?.hiddenBlockedPeerIDs` — W2-b). 메시지 스토어가 없으면 빈 집합. */
    val hiddenBlockedPeerIDs: Set<String>

    /** 루비 **공유 미러**(Swift `context.gomokuHost.rubyBalance`) — 오목·체스·테트리스·상점이 한 칸에 쓴다. 모르면 null. */
    val sharedRubyBalance: Long?
}
