// 원본: Tests/checkTests/V03xxMahjongPanelRenderTests.swift · V03xxMahjongWindowTests.swift 의 뜻(화면 고르기 · 가로 판 · 손패 누름) — 픽셀 대신 값 · 상호작용으로 잰다. Android 판 8.
package com.yehsung.aingcheck.ui.games.mahjong

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.ai.SeededSwiftRandom
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongPhoneText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStore
import com.yehsung.aingcheck.core.stores.mahjong.startPractice
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class GamesMahjongScreenTest {
    private class Rig(val h: UiGamesHarness, val mahjong: MahjongStore, val games: GamesStore)

    /** 호스트 없는 스토어 — 네트워크 0. 연습판 봇은 시험 디스패처에서 바로 둔다(보여 주는 시간 0). */
    private fun rig(): Rig {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val mahjong = MahjongStore(null, h.storeScope, clock = { SwiftDate(1_800_000_000.0) }, botContext = h.storeScope.coroutineContext.minusKey(Job))
        mahjong.timersEnabled = false
        mahjong.practiceRuntime.delayScale = 0.0
        mahjong.practiceRuntime.pickHumanSeat = { 0 }
        mahjong.practiceRuntime.makeWall = { (0 until 136).shuffled(kotlin.random.Random(7)) }
        mahjong.practiceRuntime.nextSeed = { 3uL }
        // 폰 기본(PhoneAppModel 이 처음 한 번 심는다) — 두 번 눌러 버리기.
        mahjong.aids = mahjong.aids.copy(twoClickDiscard = true)
        h.mahjong = mahjong
        return Rig(h, mahjong, GamesStore(h.context))
    }

    // 없으면: 연습판을 열어도 판이 안 서거나(가로 화면이 깨짐 · 패 그리기에서 죽음) 방향이 세로로 남아 판이 잘린다.
    @Test
    fun practiceTableIsLandscapeAndTwoTapDiscards() = runDesktopComposeUiTest(852, 393) {
        val x = rig()
        x.games.appDidBecomeActive() // 앱이 앞에 있어야 화면이 '창 보임'이 된다(아니면 연습판이 멈춘 채 선다)
        setContent { AingTheme(dark = true) { GamesMahjongScreen(x.games, x.mahjong, "나", null) } }
        waitForIdle()
        onNodeWithTag(MahjongLobbyTags.LOBBY).assertExists()
        assertEquals(GamesRummyInterfaceOrientation.portrait, x.games.rummyInterfaceOrientation, "로비가 가로다")
        x.mahjong.startPractice(MahjongFormat.tonpuu, timed = false)
        x.h.testScope.advanceUntilIdle()
        waitForIdle()
        onNodeWithTag(MahjongTableTags.TABLE).assertExists()
        assertEquals(false, x.mahjong.practice?.isPaused, "화면이 보이는데 연습판이 멈췄다")
        assertEquals(GamesRummyInterfaceOrientation.landscape, x.games.rummyInterfaceOrientation, "판이 가로가 아니다")
        // 친(내 자리 0)이 먼저 둔다 — 버릴 패 목록이 결정에서 온다.
        val turn = assertNotNull(x.mahjong.myDecision as? MahjongDecision.Turn)
        val tile = x.mahjong.table?.myDrawn ?: turn.discard.last()
        val before = x.mahjong.table?.match?.seq
        onNodeWithTag(MahjongTableTags.handTile(tile.id)).performClick() // 한 번 = 들기
        waitForIdle()
        x.h.testScope.advanceUntilIdle()
        assertEquals(before, x.mahjong.table?.match?.seq, "한 번 눌렀는데 버렸다(두 번 눌러 버리기)")
        onNodeWithTag(MahjongTableTags.handTile(tile.id)).performClick() // 한 번 더 = 버리기
        waitForIdle()
        x.h.testScope.advanceUntilIdle()
        waitForIdle()
        assertNotEquals(before, x.mahjong.table?.match?.seq, "두 번 눌러도 안 버렸다")
        assertTrue(x.mahjong.table?.seats?.firstOrNull { it.seatNo == 0 }?.discards?.any { it.tile == tile } == true)
        // 봇 셋이 돌고 다시 내 차례(또는 울기 창)가 온다 — 판이 멎지 않는다.
        assertTrue(x.mahjong.practiceRuntime.botCalls > 0)
        assertTrue(onAllNodesWithTag(MahjongTableTags.HAND).fetchSemanticsNodes().isNotEmpty())
        x.h.close()
    }

    // 없으면: 세로로 든 폰에서 판이 잘린 채 그려지거나(손패가 화면 밖) 아무것도 안 보인다.
    @Test
    fun portraitShowsRotateHint() = runDesktopComposeUiTest(393, 852) {
        val x = rig()
        x.mahjong.startPractice(MahjongFormat.tonpuu, timed = false)
        setContent { AingTheme(dark = true) { GamesMahjongScreen(x.games, x.mahjong, "나", null) } }
        waitForIdle()
        onNodeWithText(GamesMahjongPhoneText.rotating).assertExists()
        onNodeWithTag(MahjongTableTags.HAND).assertDoesNotExist()
        x.h.close()
    }
}
