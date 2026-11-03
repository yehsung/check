// 원본: Tests/CheckMobileKitTests/GamesTetrisScreenTests.swift(TabBarPolicy.tetrisMatch) @ 1b8260d · BaseComponentTests.swift(목록 아홉 — reversiMatch) @ ios-1017-int 467aec40
package com.yehsung.aingcheck.core.stores.rankings

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TabBarPolicyTest {
    /** INV-MobileComponentModels-d28152c7: 값으로 되묻는 자리 — 목록의 모든 화면이 숨긴다(테트리스 판 포함). */
    @Test
    fun everyListedScreenHidesTheTabBarIncludingTetrisMatch() {
        for (screen in TabBarPolicy.Screen.entries) assertTrue(TabBarPolicy.hidesTabBar(screen), "$screen 이 탭 막대를 안 숨긴다")
        assertEquals(
            listOf("conversation", "gomokuMatch", "chessMatch", "tetrisMatch", "rummyMatch", "reversiMatch", "shop", "miniGamePlay", "grassDetail"),
            TabBarPolicy.Screen.entries.map { it.rawValue },
        )
    }
}
