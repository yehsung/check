// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift:133·174 @ 3bd04bd (뽑기 기계 = fullScreenCover + .ignoresSafeArea() — 배경이 상태 바 · 홈 막대 뒤까지 깔린다)
//
// 셸(AingShell)이 목적지 내용에 시스템 막대 몫(상태 바 · 내비 막대 · 탭 막대) 여백을 주지 않는 표 — 그 화면이 **배경을 막대 뒤까지 깔고**
// 내용만 스스로 inset 을 단다(MachineChrome 의 statusBarsPadding). 8c 스토어 07 결함: 셸 여백 때문에 상태 바 · 내비 막대 자리가 남색(셸 면) 띠로 남아
// 보라 배경과 위아래 이음매가 보였다.
package com.yehsung.aingcheck.android.nav

import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hasRoute
import kotlin.reflect.KClass

object ShellSystemBarRules {
    /** 막대 뒤까지 그리는 목적지. 탭 막대도 숨겨야 한다(ShellTabBarRules — 탭 막대 위에 겹쳐 그리지 않게). */
    val edgeToEdge: List<KClass<*>> = listOf(Dest.GachaMachine::class)

    fun drawsBehindSystemBars(route: KClass<*>?): Boolean = route != null && route in edgeToEdge

    /** 셸이 부르는 쪽 — 지금 백스택 꼭대기 목적지. */
    fun drawsBehindSystemBars(destination: NavDestination?): Boolean =
        destination != null && edgeToEdge.any { destination.hasRoute(it) }
}
