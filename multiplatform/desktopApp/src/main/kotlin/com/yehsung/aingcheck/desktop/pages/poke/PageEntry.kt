// 원본: Sources/check/WorkTimerStore.swift 290-315(setMenuPresented — 팝오버를 다시 열 때 하는 일) · 2839-2857(togglePokePanel — 패널 진입)
//       · 3008-3022(toggleShopPanel — 상점 진입 = loadShopState) @ 35649bee
// W3-c3 수정(반박 검증 P2): 맥은 패널에 **들어오는 순간**과 팝오버를 **닫았다 다시 연 순간**에 하는 일이 다르다.
// 콕 패널: 진입 = 디렉터리 + 지갑 panelOpen(적립 쓰기) · 다시 열기 = 디렉터리만. 울트라: 다시 열기도 지갑(:310), 상점 읽기는 진입만.
package com.yehsung.aingcheck.desktop.pages.poke

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute

/**
 * 한 페이지의 진입. route 가 그 페이지가 되면 시작되고, route 가 **다른 페이지로 바뀌면** 끝난다.
 * 플라이아웃을 숨겼다 다시 여는 것(route 그대로)은 같은 진입이다 — 창이 컴포지션을 버렸다 다시 만들어도 같다.
 */
class PageEntry {
    private var entered = false

    /** 이번 진입의 첫 보임이면 true(진입마다 한 번). */
    fun firstShow(): Boolean {
        if (entered) return false
        entered = true
        return true
    }

    fun leave() {
        entered = false
    }
}

/** 페이지 활성 = `visible && route 가 그 페이지`(FlyoutContracts). route 가 떠나면(값이 바뀌거나 페이지가 컴포지션을 떠날 때) [entry] 를 끝낸다. */
@Composable
fun pageActive(nav: FlyoutNavigator, page: FlyoutRoute, entry: PageEntry): Boolean {
    val visible by nav.visible.collectAsState()
    val route by nav.route.collectAsState()
    LaunchedEffect(route) { if (route != page) entry.leave() }
    DisposableEffect(entry) { onDispose { if (nav.route.value != page) entry.leave() } }
    return visible && route == page
}
