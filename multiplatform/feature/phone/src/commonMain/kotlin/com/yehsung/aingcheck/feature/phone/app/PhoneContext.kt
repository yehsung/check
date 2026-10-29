// 원본: Sources/CheckMobileKit/App/MobileContext.swift(MobileContext · MobileStoreLinks · MobileGomokuHost) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeLinks
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.core.stores.me.missionClaimableCount
import com.yehsung.aingcheck.core.stores.me.refreshAchievementsAfterGameResult
import com.yehsung.aingcheck.core.stores.messages.MegaphoneHost
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameContext
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.feature.phone.push.PhonePushCoordinator
import com.yehsung.aingcheck.feature.phone.realtime.PhoneRealtimeRunner
import com.yehsung.aingcheck.feature.phone.routing.PhoneBadges
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouter
import com.yehsung.aingcheck.feature.phone.routing.PhoneTab
import com.yehsung.aingcheck.feature.phone.widget.NowWidgetSnapshotSink
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotWriter
import com.yehsung.aingcheck.feature.phone.work.PhoneWorkController
import kotlinx.coroutines.CoroutineScope

/**
 * 스토어끼리의 고리 묶음(Swift `MobileStoreLinks`). 앱 모델이 스토어를 모두 만든 **뒤** 채운다 — 스토어 생성 중에 읽으면 null 이다.
 * Swift 는 순환 참조를 피하려고 weak 였다. Kotlin 은 수명이 앱과 같아 그냥 든다(앱 모델이 주인).
 */
class PhoneStoreLinks {
    var now: NowStore? = null
    var messages: MessagesStore? = null
    var rankings: RankingsStore? = null
    var games: GamesStore? = null
    var me: MeStore? = null
    var push: PhonePushCoordinator? = null

    /** 폰 근무 왕복(지금 탭에 붙는 문 — Swift 는 NowStore 확장이었다). */
    var work: PhoneWorkController? = null

    /** 위젯 스냅숏을 쓰는 유일한 자리(지금 탭 몫). */
    var widgetSink: NowWidgetSnapshotSink? = null

    /**
     * **딥링크 대상 해석** 한 문(앱 모델의 `PhoneAppModel.openRoute` — 탭 스토어 규칙: 게임 탭 `routeStep`·체스 입구 막기·제보 초점·순위 판).
     * Swift 는 `router.open` 이 탭의 `consumePendingRoute` 를 지나 그 규칙을 탔다. Android 는 셸이 탭 백스택을 쥐어 라우터가 규칙을 모르므로,
     * 화면을 여는 쪽(푸시 조정자)은 라우터를 바로 부르지 않고 이 문을 지난다(W2-f 검증 7차 지적 — 알림 탭·[수락] 대체 길이 규칙을 건너뛰었다).
     */
    var routeResolver: ((PhoneRouteTarget) -> Unit)? = null

    /** 탭 배지 합성(메시지 · 게임 · 나 = 받을 보상). 앱 아이콘 배지는 메시지 + 게임만이다([PhoneBadges.appBadgeTotal]). */
    val badges: PhoneBadges
        get() = PhoneBadges(
            messages = messages?.badgeCount ?: 0,
            games = games?.badgeCount ?: 0,
            missions = me?.missionClaimableCount ?: 0,
        )
}

/**
 * 탭 스토어 · 푸시 조정자가 받는 **기반 묶음**(Swift `MobileContext` · SPEC-ios-build §1-5). W2-a [SessionContext] 를 넓혀 라우터 · 실시간 ·
 * 위젯 · 스토어 고리를 붙인다(SessionContext 머리말의 약속). 나 탭 문맥([MeContext])과 미니게임 허브 문맥([GamesMiniGameContext])을 한 객체가
 * 구현한다 — 루비 칸([ruby])이 **하나**여야 탭마다 잔액이 갈리지 않는다(W2-c · W2-d 계약).
 *
 * 오목·체스·테트리스 스토어는 [gomoku] · [chess] · [tetris] 에 둔다(Swift 와 같은 자리 — 셋이 같은 호스트·같은 루비 칸을 빌린다).
 * 게임 탭 스토어가 기대는 문맥(W2-e `GamesContext`)은 [PhoneGamesContext] 가 이 문맥으로 구현한다(이름이 같은 칸 `gomoku` 의 타입이 달라 따로 둔다).
 *
 * 쓰는 법(Swift 머리말 그대로): 서버 호출은 세션 가드 → 세대 캡처 → `withSessionRetry { s -> service.…(s.accessToken) }` → 세대 가드.
 * 시각은 [clock] 만. 딥링크로 화면을 여는 것은 [openRoute](탭 스토어 규칙을 지난다), 스토어가 내는 이동 요청은 [router]. 실시간은 [onMessageActivity] · [onMessageRead](1초 합치기).
 */
class PhoneContext(
    override val sessionStore: SessionStore,
    override val appConfig: AppConfig,
    /** 루비 잔액 미러 — 오목·체스·테트리스·확성기·나 탭·폰 근무 지갑이 **한 칸**을 읽고 쓴다. */
    override val ruby: RubyBalanceMirror,
    val router: PhoneRouter,
    val realtime: PhoneRealtimeRunner,
    val widgets: WidgetSnapshotWriter,
    val links: PhoneStoreLinks,
    /** 스토어 일이 도는 자리(앱 = 메인 디스패처 한 줄기, 시험 = 시험 디스패처). */
    override val scope: CoroutineScope,
    /** 이름 정렬(Swift `localizedStandardCompare`). */
    override val collation: Collation,
    val logger: Logger? = null,
) : MeContext, GamesMiniGameContext {
    /** 코어 오목 스토어. 조립이 채운다(게임 탭이 화면을, 실시간 러너가 신호를 맡는다). */
    lateinit var gomoku: GomokuStore

    /** 코어 체스 스토어(호스트는 오목과 **같은** 하나 — `ChessStoreHost` 는 `GomokuStoreHost` 의 별명). */
    lateinit var chess: ChessStore

    /** 코어 1:1 테트리스 스토어(루비 칸을 같이 쓴다). */
    lateinit var tetris: TetrisDuelStore

    /** 캐릭터 한 표(사람 아바타 = 사진 → 착용 캐릭터 → 이니셜). */
    lateinit var characters: AppUserCharacterStore

    /** 캐릭터 한 표가 이어졌는가(조립 전 · 시험 문맥에서는 거짓). */
    val hasCharacters: Boolean get() = ::characters.isInitialized

    override val meLinks: MeLinks = PhoneMeLinks(this)

    /** 판이 서버에 남은 직후 일일 미션 재조회(Swift `context.links.me?.refreshAchievementsAfterGameResult`). 고리가 없으면 아무 일도 안 한다. */
    override fun refreshAchievementsAfterGameResult(game: String) {
        links.me?.refreshAchievementsAfterGameResult(game)
    }

    /**
     * 대상을 탭 스토어 규칙으로 걸러 연다([PhoneStoreLinks.routeResolver]). 고리가 비면(앱 모델 밖 문맥) **아무것도 열지 않는다** — 규칙을 건너뛴
     * 열기(`router.open` 직행)로 떨어지지 않게.
     */
    fun openRoute(target: PhoneRouteTarget) {
        links.routeResolver?.invoke(target)
    }

    /** 새 메시지 신호(`.drain`) · 조인 따라잡기(`.catchUp`) 핸들러. */
    fun onMessageActivity(handler: () -> Unit) = realtime.onMessageActivity(handler)

    /** 읽음 신호(`message_read`) 핸들러. */
    fun onMessageRead(handler: () -> Unit) = realtime.onMessageRead(handler)
}

/** 나 탭이 부르는 바깥 고리(W2-c [MeLinks]) — 라우터 · 위젯 · 다른 탭 스토어로 잇는다. 고리가 비면 아무것도 안 한다(Swift 약참조 nil). */
class PhoneMeLinks(private val context: PhoneContext) : MeLinks {
    override fun noteMyEquipped(serverID: String?) {
        if (context.hasCharacters) context.characters.noteMyEquipped(serverID)
    }

    override val isAnyMatchScreenVisible: Boolean
        get() = context.links.games?.isAnyMatchScreenVisible ?: false

    /** 위젯 리밋 패널 — 쓰는 주체는 지금 탭 하나라 그 자리로 넘긴다(Swift `context.links.now?.noteAILimitPanel`). */
    override fun noteAILimitPanel(panel: MeAILimitWidgetPanel) {
        context.links.widgetSink?.noteAILimitPanel(panel)
    }

    override fun noteTokenUsagePublic(isPublic: Boolean) {
        context.links.rankings?.noteTokenUsagePublic(isPublic)
    }

    override fun clearPushPrefsNotice() {
        context.links.push?.prefsNotice = null
    }

    override fun popMeToRoot() {
        context.router.popToRoot(PhoneTab.me)
    }

    override fun pushMe(destination: MeDestination) {
        context.router.pushMe(destination)
    }
}

/**
 * 테트리스 스토어의 호스트(Swift `MobileGomokuHost` 의 테트리스 몫 — Kotlin 은 W2-e 가 루비 칸을 `Int?` 로 두어 오목 호스트(`Long?`)와 한 객체로
 * 구현할 수 없다). **칸은 빌린다** — 같은 [RubyBalanceMirror] 를 읽고 쓴다(§8-18 #4: 루비 칸 타입은 Long 하나, 테트리스 Int? 는 8차 접기).
 * Long → Int 는 Int 범위로 자른다(잔액이 21억을 넘을 일은 없지만 넘으면 조용히 감기지 않게).
 */
class PhoneTetrisHost(private val context: SessionContext, private val ruby: RubyBalanceMirror) : TetrisDuelStoreHost {
    override var rubyBalance: Int?
        get() = ruby.rubyBalance?.let { it.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt() }
        set(value) {
            ruby.rubyBalance = value?.toLong()
        }
    override val appConfig: AppConfig get() = context.appConfig
    override val session: SupabaseSession? get() = context.sessionStore.session
    override val sessionGeneration: Int get() = context.sessionStore.sessionGeneration
    override val service: SupabaseWorkService get() = context.service

    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = context.withSessionRetry(operation)
}

/** 확성기 호스트(W2-b [MegaphoneHost] — Swift `context.gomokuHost` 를 빌린다). 같은 루비 칸이다. */
class PhoneMegaphoneHost(private val context: SessionContext, private val ruby: RubyBalanceMirror) : MegaphoneHost {
    override var rubyBalance: Long?
        get() = ruby.rubyBalance
        set(value) {
            ruby.rubyBalance = value
        }
    override val session: SupabaseSession? get() = context.sessionStore.session
    override val sessionGeneration: Int get() = context.sessionStore.sessionGeneration
    override val service: SupabaseWorkService get() = context.service

    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = context.withSessionRetry(operation)
}
