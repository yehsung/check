// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift:133·174 @ 3bd04bd (fullScreenCover + .ignoresSafeArea())
//
// 8c 스토어 07 결함: 뽑기 기계 화면 위아래(상태 바 · 내비 막대 자리)에 셸 면 색 띠가 남았다. 셸 여백을 걷는 목적지 표(ShellSystemBarRules)에
// 뽑기 기계가 있는지, 그 밖의 목적지(상점 · 로비 · 나 탭)는 여백을 그대로 받는지, 막대 뒤까지 그리는 화면은 탭 막대도 숨는지 잰다.
package com.yehsung.aingcheck.android.nav

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShellSystemBarRulesTest {
    @Test
    fun gachaMachineDrawsBehindTheSystemBarsAndNothingElseDoes() {
        assertTrue("뽑기 기계가 셸 여백을 받는다 — 상태 바 · 내비 막대 자리에 띠가 남는다", ShellSystemBarRules.drawsBehindSystemBars(Dest.GachaMachine::class))
        for (route in listOf(Dest.Shop::class, Dest.MeHome::class, Dest.Gomoku::class, Dest.CharacterPicker::class)) {
            assertFalse("$route 가 셸 여백을 잃는다(내용이 상태 바 밑으로 들어간다)", ShellSystemBarRules.drawsBehindSystemBars(route))
        }
        assertFalse(ShellSystemBarRules.drawsBehindSystemBars(null as kotlin.reflect.KClass<*>?))
        for (route in ShellSystemBarRules.edgeToEdge) {
            assertTrue("$route 는 막대 뒤까지 그리는데 탭 막대가 남는다", ShellTabBarRules.hidesTabBar(route, ShellTabBarRules.Play()))
        }
    }
}
