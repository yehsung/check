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
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.desktop.pages.poke.SocialPageFlags
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
    /** 잔디 상세(폰 MeDestination.Grass 짝 — 공용 GrassDetailScreen). */
    data class Grass(val axis: MeGrassAxis) : SharedPage
    data object Missions : SharedPage
    data object Settings : SharedPage
    data object Profile : SharedPage
    data object Characters : SharedPage
    data object Feedback : SharedPage
    data object Blocked : SharedPage
    data object AccountDeletion : SharedPage
    /** int-w2 배선(3차 페이지 — RoutePages 가 그린다): 홈(W3-c2) · 콕 목록·울트라(W3-c3) · AI 토큰·AI 리밋·기기·PC 설정(W3-c4). */
    data object Home : SharedPage
    data object PokeList : SharedPage
    data object Ultra : SharedPage
    data object AiTokens : SharedPage
    data object AiLimits : SharedPage
    data object Devices : SharedPage
    data object DesktopSettings : SharedPage
    /** 공용 호스트가 스스로 그리지 않는 라우트(상점 = W4-f 덮개 · 고정 안내 = c1). RoutePages 에 그 페이지가 없으면 '준비 중'. */
    data class Pending(val route: FlyoutRoute) : SharedPage
}

/** 수명(tabDidAppear/Disappear) 비교 열쇠 — 같은 열쇠면 같은 페이지로 본다(판만 바뀐 순위·상대만 바뀐 대화는 재진입이 아니다). */
enum class SharedPageKey {
    LAUNCHING, NEEDS_UPDATE, SIGNED_OUT, ANOTHER_INSTANCE, TEAMLESS, MESSAGES, CONVERSATION, RANKINGS, RECORDS, GRASS, MISSIONS,
    SETTINGS, PROFILE, CHARACTERS, FEEDBACK, BLOCKED, ACCOUNT_DELETION, HOME, POKE_LIST, ULTRA, AI_TOKENS, AI_LIMITS, DEVICES,
    DESKTOP_SETTINGS, PENDING,
}

object SharedRouter {
    /** 무소속일 때도 갈 수 있는 라우트(로그아웃·계정 삭제·차단 목록 — 맥 무소속 화면의 푸터 몫). */
    private fun allowedWhileTeamless(route: FlyoutRoute): Boolean =
        route == FlyoutRoute.Settings || route == FlyoutRoute.AccountDeletion || route == FlyoutRoute.Blocked

    /**
     * W-3 #17: 깃발이 꺼진 기능의 라우트인가. 빠짐없는 when(라우트를 더하면 여기가 컴파일로 막는다 — else 금지).
     * 콕·울트라는 **페이지 쪽 판정**(SocialPageFlags.visibleRoutes — W-9 #2) 하나를 읽는다(여기서 깃발을 다시 해석하지 않는다).
     */
    fun isEnabled(route: FlyoutRoute, config: DesktopAppConfig): Boolean = when (route) {
        FlyoutRoute.PokeList, FlyoutRoute.Ultra -> route in SocialPageFlags.visibleRoutes(config)
        FlyoutRoute.Home, FlyoutRoute.Messages, is FlyoutRoute.Conversation, is FlyoutRoute.Rankings, FlyoutRoute.Records,
        is FlyoutRoute.Grass, FlyoutRoute.Missions, FlyoutRoute.Settings, FlyoutRoute.Profile, FlyoutRoute.Characters, FlyoutRoute.Feedback,
        FlyoutRoute.Blocked, FlyoutRoute.AccountDeletion, FlyoutRoute.PinToTaskbar, FlyoutRoute.Shop, FlyoutRoute.AiTokens,
        FlyoutRoute.AiLimits, FlyoutRoute.Devices, FlyoutRoute.DesktopSettings -> true
    }

    /**
     * 꺼진 라우트는 홈으로 접는다(진입 자체를 숨긴다 — 레일에도 칸이 없다). [runtimeShown] = 실행 중 상태로 정해지는 라우트
     * (AI 리밋 = 연동 있음 · 기기 = 두 대 이상 — RuntimeRouteRules). 기본은 늘 보임.
     */
    fun effectiveRoute(route: FlyoutRoute, config: DesktopAppConfig, runtimeShown: (FlyoutRoute) -> Boolean = { true }): FlyoutRoute =
        if (isEnabled(route, config) && runtimeShown(route)) route else FlyoutRoute.Home

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
        runtimeShown: (FlyoutRoute) -> Boolean = { true },
    ): SharedPage = when (phase) {
        SessionPhase.Launching -> SharedPage.Launching
        is SessionPhase.NeedsUpdate -> SharedPage.NeedsUpdate(phase.minBuild)
        SessionPhase.SignedOut -> SharedPage.SignedOut
        SessionPhase.AnotherInstanceRunning -> SharedPage.AnotherInstance
        SessionPhase.SignedIn -> {
            val effective = effectiveRoute(route, config, runtimeShown)
            if (isTeamless(profile, teamKnown) && !allowedWhileTeamless(effective)) SharedPage.Teamless else pageOf(effective)
        }
    }

    /**
     * 첫 실행 화면(pages/onboarding)을 지금 페이지 대신 그리나. 실행 중·다른 실행·업데이트 필요는 그 화면이 먼저다(동의는 그 뒤에 물어도 늦지 않다 —
     * 동의 전엔 스캔·자격 읽기가 0). 로그인 전에도 묻는다(자동 실행은 로그인과 무관 · 동의는 로그인 뒤 첫 스캔 전에 정해져 있어야 한다).
     */
    fun showsFirstRun(pending: Boolean, page: SharedPage): Boolean =
        pending && page != SharedPage.Launching && page != SharedPage.AnotherInstance && page !is SharedPage.NeedsUpdate

    /** 로그인·소속이 끝난 뒤 라우트 → 페이지. 빠짐없는 when(else 금지). */
    fun pageOf(route: FlyoutRoute): SharedPage = when (route) {
        FlyoutRoute.Messages -> SharedPage.Messages
        is FlyoutRoute.Conversation -> SharedPage.Conversation(route.peerId, route.from)
        is FlyoutRoute.Rankings -> SharedPage.Rankings(route.board)
        FlyoutRoute.Records -> SharedPage.Records
        is FlyoutRoute.Grass -> SharedPage.Grass(grassAxisOf(route.axis))
        FlyoutRoute.Missions -> SharedPage.Missions
        FlyoutRoute.Settings -> SharedPage.Settings
        FlyoutRoute.Profile -> SharedPage.Profile
        FlyoutRoute.Characters -> SharedPage.Characters
        FlyoutRoute.Feedback -> SharedPage.Feedback
        FlyoutRoute.Blocked -> SharedPage.Blocked
        FlyoutRoute.AccountDeletion -> SharedPage.AccountDeletion
        FlyoutRoute.Home -> SharedPage.Home
        FlyoutRoute.PokeList -> SharedPage.PokeList
        FlyoutRoute.Ultra -> SharedPage.Ultra
        FlyoutRoute.AiTokens -> SharedPage.AiTokens
        FlyoutRoute.AiLimits -> SharedPage.AiLimits
        FlyoutRoute.Devices -> SharedPage.Devices
        FlyoutRoute.DesktopSettings -> SharedPage.DesktopSettings
        FlyoutRoute.PinToTaskbar, FlyoutRoute.Shop -> SharedPage.Pending(route)
    }

    /** 라우트의 축 문자열 → 축. 모르는 값(옛 저장·오타)은 근무 잔디. */
    fun grassAxisOf(raw: String): MeGrassAxis = MeGrassAxis.entries.firstOrNull { it.name == raw } ?: MeGrassAxis.work

    /** 나(내 기록) 하위 화면 → 플라이아웃 라우트. 빠짐없는 when(else 금지) — 잔디 상세는 W-6 #3 의 FlyoutRoute.Grass. */
    fun routeOf(destination: MeDestination): FlyoutRoute = when (destination) {
        MeDestination.Shop -> FlyoutRoute.Shop
        MeDestination.Characters -> FlyoutRoute.Characters
        MeDestination.Profile -> FlyoutRoute.Profile
        MeDestination.Feedback -> FlyoutRoute.Feedback
        MeDestination.Settings -> FlyoutRoute.Settings
        MeDestination.Blocked -> FlyoutRoute.Blocked
        is MeDestination.Grass -> FlyoutRoute.Grass(destination.axis.name)
        MeDestination.Missions -> FlyoutRoute.Missions
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
        is SharedPage.Grass -> SharedPageKey.GRASS
        SharedPage.Missions -> SharedPageKey.MISSIONS
        SharedPage.Settings -> SharedPageKey.SETTINGS
        SharedPage.Profile -> SharedPageKey.PROFILE
        SharedPage.Characters -> SharedPageKey.CHARACTERS
        SharedPage.Feedback -> SharedPageKey.FEEDBACK
        SharedPage.Blocked -> SharedPageKey.BLOCKED
        SharedPage.AccountDeletion -> SharedPageKey.ACCOUNT_DELETION
        SharedPage.Home -> SharedPageKey.HOME
        SharedPage.PokeList -> SharedPageKey.POKE_LIST
        SharedPage.Ultra -> SharedPageKey.ULTRA
        SharedPage.AiTokens -> SharedPageKey.AI_TOKENS
        SharedPage.AiLimits -> SharedPageKey.AI_LIMITS
        SharedPage.Devices -> SharedPageKey.DEVICES
        SharedPage.DesktopSettings -> SharedPageKey.DESKTOP_SETTINGS
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
                // 콕 칸 = 페이지 쪽 표면 판정(SocialPageFlags.surfaces.pokeList — 라우트 판정 visibleRoutes 와 같은 답, 시험이 견준다).
                RailSlot.POKE -> SocialPageFlags.surfaces(config).pokeList
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
        RailSlot.HOME -> page == SharedPage.Home
        RailSlot.MESSAGES -> page == SharedPage.Messages || page is SharedPage.Conversation
        RailSlot.MINIGAME -> false
        // 울트라 화면은 콕 제목 배지에서 들어간다(맥 openUltraPanel(from: .poke)) — 레일 칸이 따로 없으니 콕 칸이 켜진다.
        RailSlot.POKE -> page == SharedPage.PokeList || page == SharedPage.Ultra
        RailSlot.SHOP -> page is SharedPage.Pending && page.route == FlyoutRoute.Shop
        RailSlot.MISSIONS -> page == SharedPage.Missions
        RailSlot.TEAM -> page is SharedPage.Rankings
        RailSlot.RECORDS -> page == SharedPage.Records || page == SharedPage.Profile || page == SharedPage.Characters
        RailSlot.FEEDBACK -> page == SharedPage.Feedback
        RailSlot.SETTINGS -> page == SharedPage.Settings || page == SharedPage.Blocked || page == SharedPage.AccountDeletion ||
            page == SharedPage.DesktopSettings
    }
}
