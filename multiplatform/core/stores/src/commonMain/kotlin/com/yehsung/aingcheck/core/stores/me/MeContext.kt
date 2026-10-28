// 원본: Sources/CheckMobileKit/App/MobileContext.swift:118-157(MobileStoreLinks · MobileGomokuHost.rubyBalance/rubyWriteSerial) · Sources/CheckMobileKit/Me/MeStore.swift:6-25(MeDestination · MeLoadState) · Sources/CheckMobileKit/Rankings/RankingsStore.swift:8-18(RankingsLoadState) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * 나 탭 스토어가 세션 문([SessionContext]) **밖에서** 기대는 것 — Swift `MobileContext` 중 나 탭이 읽는 칸(루비 미러 · 스토어 사이 고리 ·
 * 라우터). 의존 방향(session ← stores ← feature) 때문에 이 셋의 **구현**은 위층(W2-d 오목 호스트 · W2-f 폰 문맥 · 조립 K11)이 준다.
 * 시험은 [RubyBalanceCell] · [MeLinks] 기본 구현으로 돈다.
 */
interface MeContext : SessionContext {
    /** 루비 잔액 미러(Swift `context.gomokuHost.rubyBalance` — 오목·체스·테트리스·나 탭이 **한 칸**을 읽고 쓴다). */
    val ruby: RubyBalanceMirror

    /** 다른 스토어·라우터로 가는 고리(Swift `context.links` · `context.router` · `context.characters`). 비면 아무 일도 안 한다. */
    val meLinks: MeLinks

    companion object {
        operator fun invoke(
            sessionStore: SessionStore,
            appConfig: AppConfig = AppConfig(),
            ruby: RubyBalanceMirror = RubyBalanceCell(),
            meLinks: MeLinks = MeLinks.None,
        ): MeContext = DefaultMeContext(sessionStore, appConfig, ruby, meLinks)
    }
}

private class DefaultMeContext(
    override val sessionStore: SessionStore,
    override val appConfig: AppConfig,
    override val ruby: RubyBalanceMirror,
    override val meLinks: MeLinks,
) : MeContext

/**
 * 루비 잔액 미러. **대입마다 [rubyWriteSerial] 이 오른다**(같은 값을 써도 센다 — Swift `didSet { rubyWriteSerial &+= 1 }`).
 * 늦게 도착한 응답은 "떠난 뒤 다른 쓰기가 있었나"를 **값이 아니라 횟수로** 묻는다(값으로 물으면 ABA — 주간 보상 50 = 뽑기 값 50 — 를 못 가른다).
 * 오목·체스·테트리스 호스트(W2-d·W2-e)가 이 문을 구현하거나 조립(K11)이 같은 칸을 건네야 한다 — 칸이 둘이면 탭마다 잔액이 갈린다.
 */
interface RubyBalanceMirror {
    /** null = 모른다(막지 않는다 — 맥 0.3.29 규칙). */
    var rubyBalance: Long?
    val rubyWriteSerial: Int
}

/** 기본 미러(시험 · 조립 지점이 하나를 만들어 모든 게임 호스트와 나 탭에 같이 건넨다). */
class RubyBalanceCell(initial: Long? = null) : RubyBalanceMirror {
    private var value by mutableStateOf(initial)
    override var rubyWriteSerial: Int = 0
        private set

    override var rubyBalance: Long?
        get() = value
        set(new) {
            value = new
            rubyWriteSerial += 1
        }
}

/**
 * 나 탭이 부르는 바깥 고리 — 전부 기본은 아무것도 안 한다(Swift 약참조가 nil 인 것과 같다). 조립(K11)이 채운다.
 */
interface MeLinks {
    /** 캐릭터 한 표의 내 칸(Swift `context.characters.noteMyEquipped`, W2-b `characters`). */
    fun noteMyEquipped(serverID: String?) {}

    /** 오목·체스·테트리스 화면(로비·대국·관전)이 떠 있나(Swift `context.links.games?.isAnyMatchScreenVisible`, W2-e). */
    val isAnyMatchScreenVisible: Boolean get() = false

    /** 위젯 리밋 패널을 지금 탭에 넘긴다(Swift `context.links.now?.noteAILimitPanel`, 쓰는 주체는 지금 탭 하나 — W2-b·W2-f). */
    fun noteAILimitPanel(panel: MeAILimitWidgetPanel) {}

    /** 순위 탭에 토큰 공개 설정이 바뀌었음을 알린다(Swift `context.links.rankings?.noteTokenUsagePublic`, W2-b). */
    fun noteTokenUsagePublic(isPublic: Boolean) {}

    /** 설정 화면을 떠날 때 푸시 저장 안내를 걷는다(Swift `context.links.push?.prefsNotice = nil`, W2-f). */
    fun clearPushPrefsNotice() {}

    /** 나 탭 경로를 루트로(Swift `context.router.popToRoot(.me)`, W2-f). */
    fun popMeToRoot() {}

    /** 나 탭에 하위 화면을 한 칸 쌓는다(Swift `context.router.push(_:on: .me)`, W2-f). */
    fun pushMe(destination: MeDestination) {}

    object None : MeLinks
}

/** 나 탭이 쌓는 하위 화면(Swift `MeDestination`). 딥링크는 `.shop` · `.settings` · `.feedback` 만(나머지는 push 만 하는 화면). */
sealed interface MeDestination {
    data object Shop : MeDestination
    data object Characters : MeDestination
    data object Profile : MeDestination
    data object Feedback : MeDestination
    data object Settings : MeDestination

    /** 설정 → 차단한 사람(목록·해제는 메시지 스토어가 쥔다). */
    data object Blocked : MeDestination

    /** 잔디 상세 — 처음 색으로 볼 축(`work` · `token`). */
    data class Grass(val axis: MeGrassAxis) : MeDestination

    /** v1.0.13 「미션」 화면(이번 주 근무 + 일일 · 누적 미션). 딥링크는 두지 않는다. */
    data object Missions : MeDestination
}

/** 잔디 축(Swift `ContributionAxis` 의 나 탭 몫). */
enum class MeGrassAxis { work, token }

/** 나 탭이 받는 딥링크(Swift `AingRoute` 중 나 탭 몫 — 라우터가 경로를 비운 뒤 넘긴다). */
sealed interface MeRoute {
    data object Me : MeRoute
    data object Shop : MeRoute
    data object Settings : MeRoute
    data class Feedback(val reportID: String?) : MeRoute
}

/**
 * 한 덩어리(머리·기록·상점…)의 불러오기 상태 — 순위 탭과 같은 뜻의 세 깃발 + 마지막 성공 시각(Swift `RankingsLoadState`).
 * 칸마다 스냅숏 상태라 화면이 칸 단위로 다시 그린다.
 */
class MeLoadState {
    /** 한 번이라도 성공했다(빈 목록이어도). */
    var hasLoaded by mutableStateOf(false)
    var isLoading by mutableStateOf(false)

    /** 마지막 조회가 실패로 끝났다. */
    var hasFailed by mutableStateOf(false)

    /** 마지막 성공 시각(스토어 시계). 신선도 판정에 쓴다. */
    var loadedAt by mutableStateOf<SwiftDate?>(null)

    /** Swift `state = MeLoadState()`. */
    fun reset() {
        hasLoaded = false
        isLoading = false
        hasFailed = false
        loadedAt = null
    }
}
