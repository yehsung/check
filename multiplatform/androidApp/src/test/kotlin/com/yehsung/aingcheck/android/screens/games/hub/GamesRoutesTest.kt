// 원본: Sources/CheckMobileKit/Games/GamesTab.swift:48-76 @ 3bd04bd (navigationDestination — 쌓는 목적지 넷) · G §8-18 7(길건너 숨김)
//
// 게임 목적지 → 셸 목적지 옮김(GamesRoutes). 길건너 아잉이는 라우트 글자도 목적지도 없다(허브가 숨기고, 셸에 와도 쌓지 않는다).
// 보이는 세 종류는 글자 ↔ 종류가 왕복한다(기준선 — 길건너가 null 인 것이 '모두 null' 이 아님을 같은 표가 보인다).
package com.yehsung.aingcheck.android.screens.games.hub

import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.GameSection
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GamesRoutesTest {
    @Test
    fun visibleMiniGamesRoundTripAndCrossyHasNoRoute() {
        for (kind in MiniGameKind.entries) {
            val raw = GamesRoutes.miniGameRaw(kind)
            if (kind == MiniGameKind.crossy) {
                assertNull("길건너는 라우트 글자가 없다", raw)
                assertNull("길건너는 셸 목적지가 없다", GamesRoutes.destination(GamesDestination.MiniGame(kind)))
            } else {
                assertEquals("$kind 왕복", kind, GamesRoutes.miniGameKind(requireNotNull(raw)))
                assertEquals(Dest.MiniGame(raw), GamesRoutes.destination(GamesDestination.MiniGame(kind)))
            }
        }
        assertEquals("허브가 보이는 종류 = 라우트가 있는 종류", MiniGameExposure.visible.toSet(), MiniGameKind.entries.filter { GamesRoutes.miniGameRaw(it) != null }.toSet())
        assertNull("모르는 글자", GamesRoutes.miniGameKind("crossy"))
    }

    @Test
    fun boardGamesOpenTheirLobbies() {
        assertEquals(Dest.Gomoku(GameSection.LOBBY.raw), GamesRoutes.destination(GamesDestination.Gomoku))
        assertEquals(Dest.Chess(GameSection.LOBBY.raw), GamesRoutes.destination(GamesDestination.Chess))
        assertEquals(Dest.TetrisDuel, GamesRoutes.destination(GamesDestination.TetrisDuel))
    }
}
