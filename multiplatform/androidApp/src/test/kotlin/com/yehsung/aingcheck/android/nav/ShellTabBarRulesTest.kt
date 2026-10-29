// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift:445-477(TabBarPolicy — 숨기는 화면 목록) @ 3bd04bd
//
// 판 중 라우트 목록은 한 자리(ShellTabBarRules)다 — iOS 가 탭 막대를 숨기는 화면 전부가 Android 목적지에 걸려 있는지,
// 판 중(오목·체스·1:1 테트리스·미니게임)엔 숨고 로비·관전·목록 화면엔 보이는지 잰다. 7차 e2e: 1:1 테트리스 판에서만 탭 막대가 보였다.
package com.yehsung.aingcheck.android.nav

import com.yehsung.aingcheck.core.stores.rankings.TabBarPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShellTabBarRulesTest {
    private val idle = ShellTabBarRules.Play()
    private val inPlay = ShellTabBarRules.Play(tetrisMatch = true, boardScreenHides = true)

    @Test
    fun everyScreenIosHidesHasAnAndroidRoute() {
        val covered = ShellTabBarRules.rows.mapNotNull { it.screen }.toSet()
        assertEquals("iOS 가 탭 막대를 숨기는데 Android 목적지가 없는 화면", emptySet<TabBarPolicy.Screen>(), TabBarPolicy.Screen.entries.toSet() - covered)
        val routes = ShellTabBarRules.rows.map { it.route }
        assertEquals("같은 목적지가 표에 두 번", routes.size, routes.toSet().size)
    }

    @Test
    fun inPlayRoutesHideTheTabBar() {
        for (route in listOf(Dest.Gomoku::class, Dest.Chess::class, Dest.TetrisDuel::class, Dest.MiniGame::class)) {
            assertTrue("$route: 판 중인데 탭 막대가 보인다", ShellTabBarRules.hidesTabBar(route, inPlay))
        }
        // 1:1 테트리스 — 판만 들고 있으면 숨는다(오목·체스 화면 알림과 무관).
        assertTrue(ShellTabBarRules.hidesTabBar(Dest.TetrisDuel::class, ShellTabBarRules.Play(tetrisMatch = true)))
    }

    @Test
    fun lobbyAndSpectatingKeepTheTabBar() {
        // 오목·체스 로비·관전은 화면이 숨김을 알리지 않는다(iOS: 로비·관전 화면엔 `.hidesTabBar` 가 없다). 테트리스 로비도 보인다.
        for (route in listOf(Dest.Gomoku::class, Dest.Chess::class, Dest.TetrisDuel::class)) {
            assertFalse("$route: 로비·관전인데 탭 막대가 숨었다", ShellTabBarRules.hidesTabBar(route, idle))
        }
    }

    @Test
    fun screensWithTheirOwnBottomChromeAlwaysHide() {
        for (route in listOf(Dest.Conversation::class, Dest.Shop::class, Dest.GrassDetail::class, Dest.GachaMachine::class, Dest.MiniGame::class)) {
            assertTrue("$route: 탭 막대가 보인다", ShellTabBarRules.hidesTabBar(route, idle))
        }
    }

    @Test
    fun listScreensKeepTheTabBarEvenDuringPlay() {
        val lists = listOf(
            Dest.NowHome::class, Dest.MessagesList::class, Dest.RankingsHome::class, Dest.GamesHome::class,
            Dest.MeHome::class, Dest.Settings::class, Dest.Missions::class, Dest.Profile::class,
        )
        for (route in lists) assertFalse("$route: 목록 화면에서 탭 막대가 숨었다", ShellTabBarRules.hidesTabBar(route, inPlay))
        assertFalse("목적지를 모르면 숨기지 않는다", ShellTabBarRules.hidesTabBar(null as kotlin.reflect.KClass<*>?, inPlay))
    }
}
