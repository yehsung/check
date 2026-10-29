// 원본: Sources/CheckMobileShared/AingRoute.swift:3-36·165-190(라우트 값 · tab) · Sources/CheckMobileKit/Push/PushPayload.swift:116-124(route) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.routing

import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard

/**
 * 딥링크(푸시 · 위젯 · `aingcheck://`)가 여는 **스토어 쪽 대상**. URL 문법(`AingRoute` — Android 셸 W1-g, androidApp 의 routing 패키지)은 셸이
 * 풀고, 조립의 빠짐없는 when 이 이 값으로 옮긴다(feature/phone 은 앱 모듈을 볼 수 없다 — 의존 방향 app → feature).
 *
 * 탭마다 그 탭 스토어가 이미 가진 요청 모양을 그대로 싣는다: 게임 = W2-e [GamesRouteRequest], 나 = W2-c [MeRoute], 순위 = W2-b [RankingsBoard].
 * 체스 셋은 Android 에만 있다(E§6.1 — 체스 신청 푸시를 처리한다). iOS 열거를 넓힐 때 같은 글자를 쓴다.
 */
sealed interface PhoneRouteTarget {
    data object Now : PhoneRouteTarget

    /** 메시지 탭 목록. */
    data object Messages : PhoneRouteTarget

    /** 그 상대와의 대화. */
    data class Message(val peerID: String) : PhoneRouteTarget

    data class Rankings(val board: RankingsBoard) : PhoneRouteTarget

    /** 게임 탭(첫 화면 · 미니게임 · 오목 셋). */
    data class Games(val request: GamesRouteRequest) : PhoneRouteTarget

    data object ChessLobby : PhoneRouteTarget
    data class ChessInvite(val matchID: String) : PhoneRouteTarget

    /** null = 지금 진행 중인 판. */
    data class ChessMatch(val matchID: String?) : PhoneRouteTarget

    /** 나 탭(나 · 상점 · 설정 · 제보). */
    data class Me(val route: MeRoute) : PhoneRouteTarget

    /** 이 대상이 속한 탭. */
    val tab: PhoneTab
        get() = when (this) {
            Now -> PhoneTab.now
            Messages, is Message -> PhoneTab.messages
            is Rankings -> PhoneTab.rankings
            is Games, ChessLobby, is ChessInvite, is ChessMatch -> PhoneTab.games
            is Me -> PhoneTab.me
        }
}
