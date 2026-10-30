// 원본: Sources/check/CheckMenuView.swift @ db93317f — 421-429(본문 + 레일) · 540-880(한 화면만: … 콕 > 울트라 > 미션 > … > 홈)
// 결정: W-9 #2(페이지 갈래는 화면까지 — 배선은 통합) · W-13 #1·#4·#5·#6·#8·#9 · 갈래 notes(xplat-w4/w3-notes.md W3-c2·c3·c4)
//
// int-w2 배선(pages) — 3차 페이지(홈 · 콕 목록 · 울트라 · AI 토큰 · AI 리밋 · 기기 · PC 설정)와 첫 실행 화면을 지어 공용 호스트에 넘길 묶음
// ([routePages] · [firstRun])을 낸다. 스토어는 만들지 않는다(조립 AppGraph 가 넘긴다). 깃발 판정은 페이지 쪽 함수(SocialPageFlags) 하나만
// 읽는다 — 꺼진 기능의 페이지는 **짓지도 않는다**(라우트·레일도 SharedRouter 가 같은 함수로 숨긴다 → 그 서버 경로 요청 0).
// 공용 18(울트라 가격)·19(회고 배너)는 조립 때 잇는다 — 여기는 공급자 매개만(기본 null).
package com.yehsung.aingcheck.desktop.wiring

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsActions
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsFlyoutPage
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsRouteRule
import com.yehsung.aingcheck.desktop.pages.aitokens.AiTokensFlyoutPage
import com.yehsung.aingcheck.desktop.pages.aitokens.AiTokensPageDeps
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsDeps
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsFlyoutPage
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.pages.devices.DevicesFlyoutPage
import com.yehsung.aingcheck.desktop.pages.onboarding.FirstRunOnboarding
import com.yehsung.aingcheck.desktop.pages.poke.PokeListDeps
import com.yehsung.aingcheck.desktop.pages.poke.PokeListPage
import com.yehsung.aingcheck.desktop.pages.poke.SocialPageFlags
import com.yehsung.aingcheck.desktop.pages.shared.RoutePages
import com.yehsung.aingcheck.desktop.pages.shared.RuntimeRouteRules
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPage
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPageDeps
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPurchaseModel
import com.yehsung.aingcheck.desktop.pages.work.HomeAiEntryRow
import com.yehsung.aingcheck.desktop.pages.work.HomePage
import com.yehsung.aingcheck.desktop.pages.work.HomePageDeps
import com.yehsung.aingcheck.desktop.pages.work.HomeRetroBanner
import com.yehsung.aingcheck.desktop.pages.work.assembled
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitStore
import com.yehsung.aingcheck.feature.desktop.ultra.UltraPurchase
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore

/** 울트라 화면 재료(SocialWiring.wallet·purchase + 상점과 **같은** 루비 칸). */
class UltraPageInputs(
    val wallet: UltraWalletStore,
    /** SocialWiring.purchase(ultra=false → null). */
    val purchase: UltraPurchase?,
    val ruby: RubyBalanceMirror,
    /** 상점 다시 읽기(조립: { uiScope.launch { me.loadShop() } }). */
    val reloadShop: () -> Unit = {},
    val rubyArt: () -> ImageBitmap? = { null },
)

/** AI 리밋·기기·PC 설정의 리밋 절(TokensWiring.aiLimits + aiLimitSync.asActions(wallNow)). */
class AiLimitsInputs(val store: AILimitStore, val actions: AiLimitsActions)

class PagesWiringDeps(
    val desktopConfig: DesktopAppConfig,
    /** c4 설정 저장소(파일 kv 위 — AppGraph 가 하나 만든다). */
    val settings: DesktopSettingsStore,
    val wallNow: () -> SwiftDate,
    /** 홈 의존(nav 를 받아 짓는다 — 배너 [보기]가 nav 로 간다 · 업데이트 상태는 껍데기가 지은 뒤라 늦게 읽는다). null = 홈 '준비 중'. */
    val home: ((FlyoutNavigator) -> HomePageDeps)? = null,
    /** 공용 19 회고 배너(조립 때 잇는다). null = 회고 배너 없음(HomeBannerFeed.retroDue 기본 거짓 그대로). */
    val retroBanner: HomeRetroBanner? = null,
    val pokeList: PokeListDeps? = null,
    val ultra: UltraPageInputs? = null,
    /** 공용 18 울트라 가격(MeStore.ultraPrice — Compose 상태를 읽는 람다, 조립 때 잇는다). null = 값 모름(구매 단추는 상점을 다시 읽기만). */
    val ultraPrice: (() -> Long?)? = null,
    val aiTokens: AiTokensPageDeps? = null,
    val aiLimits: AiLimitsInputs? = null,
    /** 동의를 막 켰다(첫 실행 · PC 설정 · AI 토큰 화면 공통 — 조립: tokens.scan.refreshNow()). */
    val onConsentGranted: suspend () -> Unit = {},
    val openUrl: (String) -> Unit = {},
    /** W4-f 상점·미션(이제 레일 옆 본문 폭 — RoutePages 주석). */
    val shop: FlyoutPageHost? = null,
    val missions: FlyoutPageHost? = null,
)

class PagesWiring(private val deps: PagesWiringDeps) {
    private val surfaces = SocialPageFlags.surfaces(deps.desktopConfig)

    /** 실행 중 라우트 판정(AI 리밋 = 연동 있음 · 기기 = 두 대 이상). 리밋 재료가 없으면 둘 다 숨김. */
    val runtimeShown: (FlyoutRoute) -> Boolean = { route ->
        val limits = deps.aiLimits?.store
        RuntimeRouteRules.shown(route, aiLimitsAvailable = limits?.let { AiLimitsRouteRule.showsRoute(it) } ?: false, deviceCount = limits?.state?.value?.devices?.size ?: 0)
    }

    /** 콕 목록(poke=false → 짓지 않는다). 로그아웃 때 `pokeListPage?.model?.directory?.reset()`(c3 notes). */
    val pokeListPage: PokeListPage? = if (surfaces.pokeList) deps.pokeList?.let { PokeListPage(it) } else null

    /** 울트라 화면(ultra=false → 짓지 않는다 — 지갑 PanelOpen sync·상점 읽기 0). */
    val ultraPage: UltraPage? = if (surfaces.ultraPage) deps.ultra?.let(::ultraPageOf) else null

    val homePage: FlyoutPageHost? = deps.home?.let { build ->
        NavBoundPage { nav ->
            HomePage(
                build(nav).assembled(deps.retroBanner, middle = homeMiddle(nav)),
            )
        }
    }

    val firstRun = FirstRunOnboarding(deps.settings) { result -> if (result.consent) deps.onConsentGranted() }

    val routePages = RoutePages(
        home = homePage,
        pokeList = pokeListPage,
        ultra = ultraPage,
        aiTokens = deps.aiTokens?.let { AiTokensFlyoutPage(it) },
        aiLimits = deps.aiLimits?.let { AiLimitsFlyoutPage(it.store, it.actions, deps.wallNow) },
        devices = deps.aiLimits?.let { DevicesFlyoutPage(it.store, it.actions) },
        desktopSettings = DesktopSettingsFlyoutPage(
            DesktopSettingsDeps(deps.settings, deps.aiLimits?.store, deps.aiLimits?.actions, deps.onConsentGranted, deps.openUrl),
        ),
        shop = deps.shop,
        missions = deps.missions,
        runtimeShown = runtimeShown,
    )

    private fun ultraPageOf(u: UltraPageInputs): UltraPage {
        val price: () -> Long? = deps.ultraPrice ?: { null }
        val purchase = if (surfaces.ultraPurchase) u.purchase?.let { UltraPurchaseModel(it, u.ruby, price, u.reloadShop) } else null
        return UltraPage(UltraPageDeps(wallet = u.wallet, purchase = purchase, ruby = u.ruby, ultraPrice = price, rubyArt = u.rubyArt))
    }

    /** 헤더 아래 AI 입구(AI 토큰 · AI 리밋). 둘 다 없으면 자리 없음. */
    private fun homeMiddle(nav: FlyoutNavigator): (@Composable () -> Unit)? {
        if (deps.aiTokens == null && deps.aiLimits == null) return null
        return {
            HomeAiEntryRow(
                showsLimits = runtimeShown(FlyoutRoute.AiLimits),
                onTokens = { nav.navigate(FlyoutRoute.AiTokens) },
                onLimits = { nav.navigate(FlyoutRoute.AiLimits) },
            )
        }
    }
}

/** nav 를 받아 한 번 짓는 페이지(같은 nav 면 같은 페이지 — 모델 상태를 잃지 않는다). */
internal class NavBoundPage(private val build: (FlyoutNavigator) -> FlyoutPageHost) : FlyoutPageHost {
    private var built: Pair<FlyoutNavigator, FlyoutPageHost>? = null

    fun pageFor(nav: FlyoutNavigator): FlyoutPageHost =
        built?.takeIf { it.first === nav }?.second ?: build(nav).also { built = nav to it }

    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        pageFor(nav).Content(nav, widthDip)
    }
}
