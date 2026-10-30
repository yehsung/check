// 원본: Sources/check/CheckMenuView.swift @ a90d8623 — 535-560(로그인 → 무소속 패널 · 아니면 메인) · 540-880(한 화면만 보인다: 메시지 > 제보 > 팀 현황 >
//       토큰판 > 콕 > 울트라 > 미션 > 내 기록 > 상점 > 캐릭터 > 홈) · 965-1085(오른쪽 레일: 미니게임 · 상점 · 미션 · 팀 현황 · 내 기록 · 제보 · 설정)
// 원본: multiplatform/androidApp/…/screens/session/SessionEntries.kt(루트 단계 분기: 실행 중 → 업데이트 필요 → 로그인 → 탭)
//
// W3-c0(공용 화면 감싸기) — 플라이아웃 라우터·레일의 **순수 판정**. 화면 그리기는 SharedFlyoutPageHost, 라우트 값·뒤로 판정은 조정자 핀
// (shellapi/FlyoutContracts.kt — FlyoutRoute·FlyoutRoutes)을 그대로 쓴다(다시 만들지 않는다).
//
// 규약(shell.md §2 ★·⚠️ 번호):
//  ③ 대화로 가는 길은 FlyoutRoutes.forMessageArrival 하나 — 목록에서 연 대화는 Entry.MESSAGES(뒤로 = 목록).
//  ⑤ 배너를 공용 화면 위에 겹쳐 쌓지 않는다(배너는 W3-c2 — 여기는 자리조차 두지 않는다).
//  W-3 #17 깃발 꺼진 기능(찌르기·울트라)은 레일 칸과 라우트 진입 둘 다 숨긴다 — 라우트로 와도 홈으로 접는다.
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig

/** 플라이아웃 안에 지금 그릴 것 한 장(세션 단계 + 라우트 + 깃발로 정해진다). */
sealed interface SharedPage {
    data object Launching : SharedPage
    data class NeedsUpdate(val minBuild: Long) : SharedPage
    data object SignedOut : SharedPage
    /** 다른 실행이 단일 실행 가드를 쥐었다 — 세션을 시작하지 않는다(SessionPhase.AnotherInstanceRunning). */
    data object AnotherInstance : SharedPage
    /** 로그인했지만 소속 팀이 없다(맥 TeamlessPanel). */
    data object Teamless : SharedPage
    data object Messages : SharedPage
    data class Conversation(val peerId: String, val from: Entry) : SharedPage
    data class Rankings(val board: String) : SharedPage
    data object Records : SharedPage
    data object Missions : SharedPage
    data object Settings : SharedPage
    data object Profile : SharedPage
    data object Characters : SharedPage
    data object Feedback : SharedPage
    data object Blocked : SharedPage
    data object AccountDeletion : SharedPage
    /** 이번 웨이브에 없는 페이지(홈·콕·울트라·토큰·리밋·기기·데스크톱 설정 = W3-c2~c4, 상점 = W4-f, 고정 안내 = c1) — '준비 중' 자리표시. */
    data class Pending(val route: FlyoutRoute) : SharedPage
}

/** 수명(tabDidAppear/Disappear) 비교 열쇠 — 같은 열쇠면 같은 페이지로 본다(판만 바뀐 순위·상대만 바뀐 대화는 재진입이 아니다). */
enum class SharedPageKey {
    LAUNCHING, NEEDS_UPDATE, SIGNED_OUT, ANOTHER_INSTANCE, TEAMLESS, MESSAGES, CONVERSATION, RANKINGS, RECORDS, MISSIONS,
    SETTINGS, PROFILE, CHARACTERS, FEEDBACK, BLOCKED, ACCOUNT_DELETION, PENDING,
}

object SharedRouter {
    /** 무소속일 때도 갈 수 있는 라우트(로그아웃·계정 삭제·차단 목록 — 맥 무소속 화면의 푸터 몫). */
    private fun allowedWhileTeamless(route: FlyoutRoute): Boolean =
        route == FlyoutRoute.Settings || route == FlyoutRoute.AccountDeletion || route == FlyoutRoute.Blocked

    /** W-3 #17: 깃발이 꺼진 기능의 라우트인가. 빠짐없는 when(라우트를 더하면 여기가 컴파일로 막는다 — else 금지). */
    fun isEnabled(route: FlyoutRoute, config: DesktopAppConfig): Boolean = when (route) {
        FlyoutRoute.PokeList -> config.poke
        FlyoutRoute.Ultra -> config.ultra
        FlyoutRoute.Home, FlyoutRoute.Messages, is FlyoutRoute.Conversation, is FlyoutRoute.Rankings, FlyoutRoute.Records,
        FlyoutRoute.Missions, FlyoutRoute.Settings, FlyoutRoute.Profile, FlyoutRoute.Characters, FlyoutRoute.Feedback,
        FlyoutRoute.Blocked, FlyoutRoute.AccountDeletion, FlyoutRoute.PinToTaskbar, FlyoutRoute.Shop, FlyoutRoute.AiTokens,
        FlyoutRoute.AiLimits, FlyoutRoute.Devices, FlyoutRoute.DesktopSettings -> true
    }

    /** 꺼진 라우트는 홈으로 접는다(진입 자체를 숨긴다 — 레일에도 칸이 없다). */
    fun effectiveRoute(route: FlyoutRoute, config: DesktopAppConfig): FlyoutRoute =
        if (isEnabled(route, config)) route else FlyoutRoute.Home

    /**
     * 무소속 판정. [teamKnown] = 로그인 직후 소속 읽기(SessionStore.pendingProfileRefresh)가 끝났다 — 끝나기 전의 teamID null 은
     * "아직 모른다"이지 "팀이 없다"가 아니다(세션은 소속을 읽기 전에 teamID 없는 프로필을 먼저 싣는다 — SessionStore.enterSignedIn).
     */
    fun isTeamless(profile: SessionProfile?, teamKnown: Boolean): Boolean =
        teamKnown && profile != null && profile.teamID == null

    /** 실행 중 → 업데이트 필요 → 로그아웃 → (다른 실행) → 무소속 → 라우트. */
    fun resolve(
        phase: SessionPhase,
        profile: SessionProfile?,
        teamKnown: Boolean,
        route: FlyoutRoute,
        config: DesktopAppConfig,
    ): SharedPage = when (phase) {
        SessionPhase.Launching -> SharedPage.Launching
        is SessionPhase.NeedsUpdate -> SharedPage.NeedsUpdate(phase.minBuild)
        SessionPhase.SignedOut -> SharedPage.SignedOut
        SessionPhase.AnotherInstanceRunning -> SharedPage.AnotherInstance
        SessionPhase.SignedIn -> {
            val effective = effectiveRoute(route, config)
            if (isTeamless(profile, teamKnown) && !allowedWhileTeamless(effective)) SharedPage.Teamless else pageOf(effective)
        }
    }

    /** 로그인·소속이 끝난 뒤 라우트 → 페이지. 빠짐없는 when(else 금지). */
    fun pageOf(route: FlyoutRoute): SharedPage = when (route) {
        FlyoutRoute.Messages -> SharedPage.Messages
        is FlyoutRoute.Conversation -> SharedPage.Conversation(route.peerId, route.from)
        is FlyoutRoute.Rankings -> SharedPage.Rankings(route.board)
        FlyoutRoute.Records -> SharedPage.Records
        FlyoutRoute.Missions -> SharedPage.Missions
        FlyoutRoute.Settings -> SharedPage.Settings
        FlyoutRoute.Profile -> SharedPage.Profile
        FlyoutRoute.Characters -> SharedPage.Characters
        FlyoutRoute.Feedback -> SharedPage.Feedback
        FlyoutRoute.Blocked -> SharedPage.Blocked
        FlyoutRoute.AccountDeletion -> SharedPage.AccountDeletion
        FlyoutRoute.Home, FlyoutRoute.PinToTaskbar, FlyoutRoute.Shop, FlyoutRoute.PokeList, FlyoutRoute.Ultra,
        FlyoutRoute.AiTokens, FlyoutRoute.AiLimits, FlyoutRoute.Devices, FlyoutRoute.DesktopSettings -> SharedPage.Pending(route)
    }

    fun keyOf(page: SharedPage): SharedPageKey = when (page) {
        SharedPage.Launching -> SharedPageKey.LAUNCHING
        is SharedPage.NeedsUpdate -> SharedPageKey.NEEDS_UPDATE
        SharedPage.SignedOut -> SharedPageKey.SIGNED_OUT
        SharedPage.AnotherInstance -> SharedPageKey.ANOTHER_INSTANCE
        SharedPage.Teamless -> SharedPageKey.TEAMLESS
        SharedPage.Messages -> SharedPageKey.MESSAGES
        is SharedPage.Conversation -> SharedPageKey.CONVERSATION
        is SharedPage.Rankings -> SharedPageKey.RANKINGS
        SharedPage.Records -> SharedPageKey.RECORDS
        SharedPage.Missions -> SharedPageKey.MISSIONS
        SharedPage.Settings -> SharedPageKey.SETTINGS
        SharedPage.Profile -> SharedPageKey.PROFILE
        SharedPage.Characters -> SharedPageKey.CHARACTERS
        SharedPage.Feedback -> SharedPageKey.FEEDBACK
        SharedPage.Blocked -> SharedPageKey.BLOCKED
        SharedPage.AccountDeletion -> SharedPageKey.ACCOUNT_DELETION
        is SharedPage.Pending -> SharedPageKey.PENDING
    }
}

/**
 * 오른쪽 레일 칸. 맥 8칸(미니게임 · 콕 · 상점 · 미션 · 팀 현황 · 내 기록 · 제보 · 설정) 앞에 **홈 · 메시지** 두 칸을 더 둔다 — 맥은 둘을
 * 헤더 카드(W3-c2)에서 연다. 헤더 카드가 들어오면 이 두 칸을 걷을지 다시 정한다(보고 unresolved).
 */
enum class RailSlot(val label: String, val sfName: String) {
    HOME("홈", "house.fill"),
    MESSAGES("메시지", "bubble.left.and.bubble.right.fill"),
    MINIGAME("미니게임", "gamecontroller.fill"),
    POKE("콕", "hand.point.right.fill"),
    SHOP("상점", "bag.fill"),
    MISSIONS("미션", "checklist"),
    TEAM("팀 현황", "chart.bar.xaxis"),
    RECORDS("내 기록", "chart.xyaxis.line"),
    FEEDBACK("제보", "exclamationmark.bubble.fill"),
    SETTINGS("설정", "gearshape.fill"),
}

object SharedRail {
    /** 팀 현황 칸이 여는 판(맥 LeaderboardPanel = 팀 리그). RankingsBoard.league.rawValue 와 같은 글자. */
    const val TEAM_BOARD = "league"

    /**
     * 보일 칸(위 → 아래). 로그인 전·다른 실행·업데이트 필요엔 레일이 없다. 무소속은 설정 한 칸(맥 무소속 화면의 푸터).
     * 미니게임은 별도 창(W4-e)이라 [miniGameAvailable] 이 거짓이면(창이 아직 없다) 숨긴다. 콕은 W-3 #17 poke 깃발.
     */
    fun slots(page: SharedPage, config: DesktopAppConfig, miniGameAvailable: Boolean): List<RailSlot> = when (page) {
        SharedPage.Launching, is SharedPage.NeedsUpdate, SharedPage.SignedOut, SharedPage.AnotherInstance -> emptyList()
        SharedPage.Teamless -> listOf(RailSlot.SETTINGS)
        else -> RailSlot.entries.filter { slot ->
            when (slot) {
                RailSlot.MINIGAME -> miniGameAvailable
                RailSlot.POKE -> config.poke
                else -> true
            }
        }
    }

    /** 칸 → 라우트. 미니게임은 라우트가 아니라 창(null — 부르는 쪽이 창을 연다). */
    fun route(slot: RailSlot): FlyoutRoute? = when (slot) {
        RailSlot.HOME -> FlyoutRoute.Home
        RailSlot.MESSAGES -> FlyoutRoute.Messages
        RailSlot.MINIGAME -> null
        RailSlot.POKE -> FlyoutRoute.PokeList
        RailSlot.SHOP -> FlyoutRoute.Shop
        RailSlot.MISSIONS -> FlyoutRoute.Missions
        RailSlot.TEAM -> FlyoutRoute.Rankings(TEAM_BOARD)
        RailSlot.RECORDS -> FlyoutRoute.Records
        RailSlot.FEEDBACK -> FlyoutRoute.Feedback
        RailSlot.SETTINGS -> FlyoutRoute.Settings
    }

    /** 칸이 켜져 보이는가(맥 isActive — 그 패널이 떠 있다). 대화는 메시지 칸, 하위 설정(차단·계정 삭제)은 설정 칸. */
    fun isActive(slot: RailSlot, page: SharedPage): Boolean = when (slot) {
        RailSlot.HOME -> page is SharedPage.Pending && page.route == FlyoutRoute.Home
        RailSlot.MESSAGES -> page == SharedPage.Messages || page is SharedPage.Conversation
        RailSlot.MINIGAME -> false
        RailSlot.POKE -> page is SharedPage.Pending && page.route == FlyoutRoute.PokeList
        RailSlot.SHOP -> page is SharedPage.Pending && page.route == FlyoutRoute.Shop
        RailSlot.MISSIONS -> page == SharedPage.Missions
        RailSlot.TEAM -> page is SharedPage.Rankings
        RailSlot.RECORDS -> page == SharedPage.Records || page == SharedPage.Profile || page == SharedPage.Characters
        RailSlot.FEEDBACK -> page == SharedPage.Feedback
        RailSlot.SETTINGS -> page == SharedPage.Settings || page == SharedPage.Blocked || page == SharedPage.AccountDeletion
    }
}
