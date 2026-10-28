// 원본: 없음 — 화면 게이트 시험(G §8-17 1 · §8-18 7). 판정은 core 이고, 이 시험은 **화면이 그 판정대로 그리는가**를 잰다(기억 client-gates-come-in-pairs —
// 스토어만 막고 화면이 버튼을 세우면 눌러도 아무 일 없는 버튼이 된다 · 화면만 막고 스토어가 열려 있으면 다른 입구로 샌다. 스토어 쪽 짝은 W2-e 시험).
//  ① 게임 탭에 **길건너 아잉이가 없다**(iOS 1.0.14 바닥 — phoneCases 가 거르고 표시 깃발이 좁힌다): 타일 · 오늘 내 순위 줄 둘 다.
//  ② 1:1 테트리스 판돈 **신청·수락 진입은 duelsEnabled 가 켜진 빌드에서만** 그린다. [거절]은 판돈이 움직이지 않아 늘 있다(§8-18 5).
// 로비 값은 폰 데모 픽스처(Sources/CheckMobileKit/Demo/Fixtures/games — 복사 0, 저장소 경로에서 읽는다)를 스토어 applyLobby 로 넣는다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubTags
import com.yehsung.aingcheck.ui.games.minigame.hub.hubMiniGames
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelScreen
import com.yehsung.aingcheck.ui.games.tetris.TetrisDuelTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalTestApi::class)
class GamesScreensGateTest {
    /** 데모 고정 시계(픽스처의 server_now_ms 1789621500000)에 맞춘 문맥. 망 0 — 이 시험은 로그인하지 않는다(스토어 일은 시험 디스패처에서 멈춰 있다). */
    private fun harness(duelsEnabled: Boolean): UiGamesHarness =
        UiGamesHarness(TestScope(), AppConfig(duelsEnabled = duelsEnabled)) { null }.also { h ->
            h.tetris.clock = { SwiftDate(1_789_621_500.0) }
        }

    /** 와이어 타입은 앱과 같은 디코더(SwiftJson — Swift JSONDecoder 의 꼴)로만 읽는다. */
    private fun lobby(path: String): TetrisLobbyResponse = SwiftJson.decode(TetrisLobbyResponse.serializer(), RepoFiles.readText(path))

    @Test
    fun theHubHasNoCrossyTileOrRankRow() = runComposeUiTest {
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.tetris), hubMiniGames, "게임 탭 미니게임 = iOS 1.0.14 셋")
        val h = harness(duelsEnabled = false)
        val store = GamesStore(h.context)
        setContent {
            AingTheme(dark = false) {
                GamesHubScreen(store, GamesHubBoardFactsSnapshot(), MiniGameArt.empty, { SwiftDate(1_789_621_500.0) }, {}, {}, {})
            }
        }
        onNodeWithTag(GamesHubTags.tile(MiniGameKind.crossy)).assertDoesNotExist()
        onNodeWithTag(GamesHubTags.rankRow(MiniGameKind.crossy), useUnmergedTree = true).assertDoesNotExist()
        for (kind in hubMiniGames) {
            onNodeWithTag(GamesHubTags.tile(kind)).assertExists()
            onNodeWithTag(GamesHubTags.rankRow(kind), useUnmergedTree = true).assertExists()
        }
        onNodeWithTag(GamesHubTags.TETRIS_DUEL).assertExists()
        h.close()
    }

    private fun lobbyScreen(duelsEnabled: Boolean, fixture: String, check: androidx.compose.ui.test.ComposeUiTest.() -> Unit) = runComposeUiTest {
        val h = harness(duelsEnabled)
        runBlocking { h.tetris.applyLobby(lobby(fixture)) }
        val store = GamesStore(h.context)
        setContent { AingTheme(dark = false) { GamesTetrisDuelScreen(store, myUserID = null, refreshHz = 60) } }
        check()
        h.close()
    }

    private val plainLobby = "Sources/CheckMobileKit/Demo/Fixtures/games/rpc.tetris_lobby.json"
    private val invitesLobby = "Sources/CheckMobileKit/Demo/Fixtures/games/_games-tetris-lobby-invites/rpc.tetris_lobby.json"

    /** 픽스처의 '근무 중·가능' 상대(구름빵) — 신청 게이트가 열린다(보낸 신청이 없을 때). */
    private val cloudBread = "d0000000-0000-4000-8000-0000000000b1"

    @Test
    fun challengeIsDrawnOnlyWhenDuelsAreEnabled() {
        lobbyScreen(duelsEnabled = true, fixture = plainLobby) {
            onNodeWithTag(TetrisDuelTags.challenge(cloudBread), useUnmergedTree = true).assertExists().assertIsEnabled()
        }
        lobbyScreen(duelsEnabled = false, fixture = plainLobby) {
            onNodeWithTag(TetrisDuelTags.LOBBY).assertExists()
            onNodeWithTag(TetrisDuelTags.challenge(cloudBread), useUnmergedTree = true).assertDoesNotExist()
        }
    }

    @Test
    fun acceptIsDrawnOnlyWhenDuelsAreEnabledButDeclineAlways() {
        val invite = "demo-tetris-ready"
        lobbyScreen(duelsEnabled = true, fixture = invitesLobby) {
            onNodeWithTag(TetrisDuelTags.accept(invite), useUnmergedTree = true).assertExists().assertIsEnabled()
            onNodeWithTag(TetrisDuelTags.decline(invite), useUnmergedTree = true).assertExists()
            // 보낸 신청이 있으면 신청 게이트가 닫힌다 — 버튼은 서되(깃발 켬) 눌리지 않는다.
            onNodeWithTag(TetrisDuelTags.challenge(cloudBread), useUnmergedTree = true).assertExists().assertIsNotEnabled()
        }
        lobbyScreen(duelsEnabled = false, fixture = invitesLobby) {
            onNodeWithTag(TetrisDuelTags.accept(invite), useUnmergedTree = true).assertDoesNotExist()
            onNodeWithTag(TetrisDuelTags.decline(invite), useUnmergedTree = true).assertExists()
        }
    }
}
