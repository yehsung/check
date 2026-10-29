// 원본: Sources/CheckMobileShared/AingRoute.swift:37-48(미니게임 열거 짝) · Sources/CheckMobileKit/Push/PushPayload.swift:116-131(route · messagePeerID) @ 3bd04bd
// 조립(K11) 변환 한 자리: 셸의 URL 문법 값(AingRoute — W1-g)과 폰 로직(feature/phone — W2-f)의 대상 값 사이. feature/phone 은 앱 모듈을 볼 수
// 없어(의존 방향 app → feature) 두 값을 잇는 빠짐없는 when 이 여기 있다. `else ->` 를 두지 않는다 — 한쪽에 갈래가 생기면 컴파일이 막는다.
package com.yehsung.aingcheck.android.routing

import com.yehsung.aingcheck.android.push.AingChannel
import com.yehsung.aingcheck.android.push.PushDecision
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.feature.phone.push.PhonePushContent
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.feature.phone.routing.PhoneTab
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard as StoreRankingsBoard

object RouteTargets {
    /** 딥링크 → 폰 로직의 대상(`PhoneAppModel.handleOpenRoute` 에 넘긴다 — 탭 스토어 규칙으로 거른 뒤 라우터 요청이 된다). */
    fun target(route: AingRoute): PhoneRouteTarget = when (route) {
        AingRoute.Now -> PhoneRouteTarget.Now
        AingRoute.Messages -> PhoneRouteTarget.Messages
        is AingRoute.Message -> PhoneRouteTarget.Message(route.peerId)
        is AingRoute.Rankings -> PhoneRouteTarget.Rankings(board(route.board))
        AingRoute.Games -> PhoneRouteTarget.Games(GamesRouteRequest.Games)
        is AingRoute.MiniGame -> PhoneRouteTarget.Games(GamesRouteRequest.MiniGame(miniGame(route.game)))
        AingRoute.GomokuLobby -> PhoneRouteTarget.Games(GamesRouteRequest.GomokuLobby)
        is AingRoute.GomokuInvite -> PhoneRouteTarget.Games(GamesRouteRequest.GomokuInvite(route.matchId))
        is AingRoute.GomokuMatch -> PhoneRouteTarget.Games(GamesRouteRequest.GomokuMatch(route.matchId))
        AingRoute.ChessLobby -> PhoneRouteTarget.ChessLobby
        is AingRoute.ChessInvite -> PhoneRouteTarget.ChessInvite(route.matchId)
        is AingRoute.ChessMatch -> PhoneRouteTarget.ChessMatch(route.matchId)
        AingRoute.Me -> PhoneRouteTarget.Me(MeRoute.Me)
        AingRoute.Shop -> PhoneRouteTarget.Me(MeRoute.Shop)
        is AingRoute.Feedback -> PhoneRouteTarget.Me(MeRoute.Feedback(route.reportId))
        AingRoute.Settings -> PhoneRouteTarget.Me(MeRoute.Settings)
    }

    /**
     * 폰 로직의 대상 → 셸이 그릴 라우트(NavGraph 가 `RoutePlans.plan` 으로 목적지를 쌓는다). 라우트로 나타낼 수 없는 대상
     * (게임 탭 밖 요청 · 이 빌드에 링크가 없는 미니게임)은 null — 셸은 아무것도 바꾸지 않는다.
     */
    fun route(target: PhoneRouteTarget): AingRoute? = when (target) {
        PhoneRouteTarget.Now -> AingRoute.Now
        PhoneRouteTarget.Messages -> AingRoute.Messages
        is PhoneRouteTarget.Message -> AingRoute.safeId(target.peerID)?.let { AingRoute.Message(it) }
        is PhoneRouteTarget.Rankings -> AingRoute.Rankings(board(target.board))
        is PhoneRouteTarget.Games -> when (val request = target.request) {
            GamesRouteRequest.Games -> AingRoute.Games
            is GamesRouteRequest.MiniGame -> miniGame(request.kind)?.let { AingRoute.MiniGame(it) }
            GamesRouteRequest.GomokuLobby -> AingRoute.GomokuLobby
            is GamesRouteRequest.GomokuInvite -> AingRoute.safeId(request.inviteID)?.let { AingRoute.GomokuInvite(it) }
            is GamesRouteRequest.GomokuMatch -> request.matchID?.let { id -> AingRoute.safeId(id)?.let { AingRoute.GomokuMatch(it) } } ?: AingRoute.GomokuMatch(null)
            GamesRouteRequest.Other -> null
        }
        PhoneRouteTarget.ChessLobby -> AingRoute.ChessLobby
        is PhoneRouteTarget.ChessInvite -> AingRoute.safeId(target.matchID)?.let { AingRoute.ChessInvite(it) }
        is PhoneRouteTarget.ChessMatch -> target.matchID?.let { id -> AingRoute.safeId(id)?.let { AingRoute.ChessMatch(it) } } ?: AingRoute.ChessMatch(null)
        is PhoneRouteTarget.Me -> when (val route = target.route) {
            MeRoute.Me -> AingRoute.Me
            MeRoute.Shop -> AingRoute.Shop
            MeRoute.Settings -> AingRoute.Settings
            is MeRoute.Feedback -> AingRoute.Feedback(route.reportID?.let(AingRoute::safeId))
        }
    }

    /**
     * 딥링크 미니게임 ↔ 엔진 종류.
     * INV-AingRoute-67c8ae7d 이식: **이 열거([AingMiniGame])와 `MiniGameKind.phoneCases` 는 언제나 같이 넓힌다.** 한쪽만 넓히면 게임 탭의
     *   `routeStep` 이 모르는 값을 엉뚱한 게임으로 오배달하거나 링크가 조용히 사라진다. 빠짐없는 when 두 개가 컴파일로 막고,
     *   `RouteTargetsTest.miniGameLinksAndPhoneCasesWidenTogether` 가 두 집합이 1:1 인지 잰다(길건너는 폰에 아직 없어 양쪽 다 없다 — §8-18 #7).
     */
    fun miniGame(game: AingMiniGame): MiniGameKind = when (game) {
        AingMiniGame.TIMING -> MiniGameKind.timingBar
        AingMiniGame.FLAPPY -> MiniGameKind.flappy
        AingMiniGame.TETRIS -> MiniGameKind.tetris
    }

    fun miniGame(kind: MiniGameKind): AingMiniGame? = when (kind) {
        MiniGameKind.timingBar -> AingMiniGame.TIMING
        MiniGameKind.flappy -> AingMiniGame.FLAPPY
        MiniGameKind.tetris -> AingMiniGame.TETRIS
        MiniGameKind.crossy -> null
    }

    fun board(board: RankingsBoard): StoreRankingsBoard = when (board) {
        RankingsBoard.LEAGUE -> StoreRankingsBoard.league
        RankingsBoard.TOKENS -> StoreRankingsBoard.tokens
        RankingsBoard.MINIGAME -> StoreRankingsBoard.minigame
    }

    fun board(board: StoreRankingsBoard): RankingsBoard = when (board) {
        StoreRankingsBoard.league -> RankingsBoard.LEAGUE
        StoreRankingsBoard.tokens -> RankingsBoard.TOKENS
        StoreRankingsBoard.minigame -> RankingsBoard.MINIGAME
    }

    fun tab(tab: AingTab): PhoneTab = when (tab) {
        AingTab.NOW -> PhoneTab.now
        AingTab.MESSAGES -> PhoneTab.messages
        AingTab.RANKINGS -> PhoneTab.rankings
        AingTab.GAMES -> PhoneTab.games
        AingTab.ME -> PhoneTab.me
    }

    fun tab(tab: PhoneTab): AingTab = when (tab) {
        PhoneTab.now -> AingTab.NOW
        PhoneTab.messages -> AingTab.MESSAGES
        PhoneTab.rankings -> AingTab.RANKINGS
        PhoneTab.games -> AingTab.GAMES
        PhoneTab.me -> AingTab.ME
    }

    /**
     * FCM 판정(W1-g `NotificationSpecs.decide`) → 푸시 조정자가 받는 내용(`PhonePushCoordinator.didReceive`). 페이로드를 두 번 풀지 않는다 —
     * 판정이 이미 고른 라우트에서 id 를 꺼낸다. 버린 메시지(Drop)는 null.
     */
    fun content(decision: PushDecision): PhonePushContent? = when (decision) {
        is PushDecision.Post -> content(decision.spec.tap.route, decision.refresh)
        is PushDecision.Hide -> content(decision.route, decision.refresh)
        is PushDecision.Drop -> null
    }

    /** 알림 [수락]으로 연 신청(셸이 증표를 확인한 라우트) → 조정자의 수락 대상. 신청 라우트가 아니면 null. */
    fun acceptContent(route: AingRoute): PhonePushContent? = when (route) {
        is AingRoute.GomokuInvite -> PhonePushContent.GomokuInvite(route.matchId)
        is AingRoute.ChessInvite -> PhonePushContent.ChessInvite(route.matchId)
        else -> null
    }

    private fun content(route: AingRoute, channel: AingChannel): PhonePushContent? = when (channel) {
        AingChannel.MESSAGE -> (route as? AingRoute.Message)?.let { PhonePushContent.Message(it.peerId) }
        AingChannel.GOMOKU_INVITE -> (route as? AingRoute.GomokuInvite)?.let { PhonePushContent.GomokuInvite(it.matchId) }
        AingChannel.CHESS_INVITE -> (route as? AingRoute.ChessInvite)?.let { PhonePushContent.ChessInvite(it.matchId) }
        AingChannel.FEEDBACK_REPLY -> (route as? AingRoute.Feedback)?.let { PhonePushContent.FeedbackReply(it.reportId) }
        // session_id 는 참고값이다 — 판정이 라우트(지금 탭)에 싣지 않으므로 여기서도 없다(조정자는 쓰지 않는다).
        AingChannel.WORK_CHECK -> PhonePushContent.WorkCheck(null)
    }
}
