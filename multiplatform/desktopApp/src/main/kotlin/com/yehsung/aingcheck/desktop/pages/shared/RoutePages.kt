// 원본: Sources/check/CheckMenuView.swift @ db93317f — 421-429(본문 열 316 + 레일 64 의 HStack: 레일은 본문 옆에 늘 선다)
//       · 762-799(미션 화면 = 본문 열 안의 if-else 한 가지) · 820-(상점 화면도 본문 열 안) · 1002-1010(레일 [미션] isActive = 미션 화면이 떠 있음)
//
// int-w2 배선(pages) — 3차 페이지(W3-c2 홈 · W3-c3 콕 목록·울트라 · W3-c4 AI 토큰·AI 리밋·기기·PC 설정)와 W4-f 상점·미션을
// 공용 호스트(SharedFlyoutPageHost)의 **본문 자리**에 꽂는 묶음. 조립은 PagesWiring 이 만든다(없으면 '준비 중').
//
// W-9 #7 · W-13 #9 미션 덮개 자리: 맥은 미션·상점 화면을 본문 열(316) 안에 그리고 레일(64)은 그 옆에 그대로 선다(위 원본 줄).
// 그래서 여기도 상점·미션을 **레일 옆 본문 폭**으로 그린다(W4-f 의 전체 폭 덮개 ShellPageHost 가 레일을 가리던 것과 다르다 — 걷는 줄은 notes).
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute

/** 라우트 → 페이지 호스트. null 이면 그 라우트는 공용 호스트의 기본(공용 화면 또는 '준비 중'). */
class RoutePages(
    val home: FlyoutPageHost? = null,
    val pokeList: FlyoutPageHost? = null,
    val ultra: FlyoutPageHost? = null,
    val aiTokens: FlyoutPageHost? = null,
    val aiLimits: FlyoutPageHost? = null,
    val devices: FlyoutPageHost? = null,
    val desktopSettings: FlyoutPageHost? = null,
    /** W4-f ShopFlyoutPage. */
    val shop: FlyoutPageHost? = null,
    /** W4-f MissionsFlyoutPage(없으면 공용 MeMissionsScreen). */
    val missions: FlyoutPageHost? = null,
    /** 실행 중 상태로 정해지는 라우트 판정(RuntimeRouteRules). 기본 늘 보임. */
    val runtimeShown: (FlyoutRoute) -> Boolean = { true },
) {
    /** 이 페이지를 그릴 호스트. 공용 화면 페이지(메시지·순위…)는 null — 공용 호스트가 그린다. */
    fun hostFor(page: SharedPage): FlyoutPageHost? = when (page) {
        SharedPage.Home -> home
        SharedPage.PokeList -> pokeList
        SharedPage.Ultra -> ultra
        SharedPage.AiTokens -> aiTokens
        SharedPage.AiLimits -> aiLimits
        SharedPage.Devices -> devices
        SharedPage.DesktopSettings -> desktopSettings
        SharedPage.Missions -> missions
        is SharedPage.Pending -> if (page.route == FlyoutRoute.Shop) shop else null
        else -> null
    }

    companion object {
        val NONE = RoutePages()
    }
}

/**
 * 실행 중 상태로 정하는 라우트(W-9 #2 — c4 판정 함수를 그대로 읽는다): AI 리밋 = AiLimitsRouteRule.showsRoute(연동 도구 있음),
 * 기기 = DevicePickerModel.showsPicker(두 대 이상). AI 토큰·PC 설정은 늘 보인다. 숨은 라우트로 오면 홈으로 접힌다(SharedRouter).
 */
object RuntimeRouteRules {
    fun shown(route: FlyoutRoute, aiLimitsAvailable: Boolean, deviceCount: Int): Boolean = when (route) {
        FlyoutRoute.AiLimits -> aiLimitsAvailable
        FlyoutRoute.Devices -> deviceCount >= 2
        else -> true
    }
}

/** 본문 폭(DIP) — 레일이 서면 그 몫을 뺀다(맥 contentColumnWidth 316 = 창 폭 − 레일 − 간격). 페이지 호스트에 넘기는 폭. */
object RouteBodyWidth {
    fun of(widthDip: Double, railShown: Boolean): Double =
        if (railShown) (widthDip - SharedFlyoutPageHost.RAIL_WIDTH).coerceAtLeast(0.0) else widthDip
}
