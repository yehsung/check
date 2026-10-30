// 원본: Sources/check/CheckApp.swift:344-440(★ "전부 빠져도 컴파일·시험은 초록" — 옵셔널 문 다섯) · CheckMiniGameWindow.swift:247(③ 닫기 = 판 끝) ·
//       :267(④ 키 상실 = 일시정지만, 0.3.62) · MiniGameExposure(길건너 숨김 — W-3 #1)
//       (W4-e 완료 기준 — WindowWiringContractTest · MiniGameFocusPauseTest · ExposureTest · 반박 수정: 순위 스위치 ①·닫기 정산·kind 없는 열기 멱등)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.ui.games.minigame.UiFixtures
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.games.gomoku.boardClock
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

private val NOW = SwiftDate(1_789_621_500.0)
private val ART by lazy { MiniGameArt(DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_SIDE_SOURCE), DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_NEGATIVE_SOURCE)) }
private val NO_FACTS = GamesHubBoardFactsSnapshot(gomokuRecord = null, chessRecord = null, chessHasIncoming = false)

class WindowWiringContractTest {
    private class Rig(config: DesktopAppConfig, onInvite: (GameWindowKind) -> Unit = {}) {
        val board = BoardGameRig(me = null, duelsEnabled = config.toAppConfig().duelsEnabled)
        val games = UiGamesHarness(TestScope(), config.toAppConfig()) { null }
        val shells = GamesWindowsHost.OWN_KINDS.associateWith { FakeGameWindowShell() }
        val host = GameWindowScenes.host(shells)
        init { GameWindowWiring.wire(board.gomoku, board.chess, games.tetris, host, config, onInvite = onInvite) }
    }

    /** ★CheckApp.swift:344-440 — 문 다섯 × 스토어 셋 = 15 칸이 전부 차야 한다(빠져도 컴파일은 초록이라 시험이 그물이다). */
    @Test
    fun allFiveDoorsOfTheThreeBoardStoresAreWired() {
        // 음성 대조: 배선 전 대결 스토어는 순위가 꺼져 있다(폰과 공용 — 기본 false). 아래 단언이 배선을 재는지 확인.
        assertFalse(UiGamesHarness(TestScope(), AppConfig()) { null }.tetris.rankingEnabled, "대결 스토어 기본이 켜져 있다 — 순위 단언이 헛돈다")
        val r = Rig(DesktopAppConfig())
        val g = r.board.gomoku
        val c = r.board.chess
        val t = r.games.tetris
        val doors = mapOf(
            "gomoku.presentWindow" to g.presentWindow, "gomoku.dismissWindow" to g.dismissWindow, "gomoku.requestAttention" to g.requestAttention,
            "gomoku.onInviteArrived" to g.onInviteArrived, "gomoku.onAttention" to g.onAttention,
            "chess.presentWindow" to c.presentWindow, "chess.dismissWindow" to c.dismissWindow, "chess.requestAttention" to c.requestAttention,
            "chess.onInviteArrived" to c.onInviteArrived, "chess.onAttention" to c.onAttention,
            "tetris.presentWindow" to t.presentWindow, "tetris.dismissWindow" to t.dismissWindow, "tetris.requestAttention" to t.requestAttention,
            "tetris.onInviteArrived" to t.onInviteArrived, "tetris.onAttention" to t.onAttention,
        )
        doors.forEach { (name, door) -> assertNotNull(door, "$name 이 비었다 — 배선이 빠졌다") }
        // W-3 #4 — Windows 는 관전·순위를 켠다(맥과 같게).
        assertTrue(g.spectatorFeaturesEnabled && c.spectatorFeaturesEnabled && t.spectatorFeaturesEnabled, "관전 스위치가 꺼져 있다")
        // ①CheckApp.swift:409·430 — 순위의 주 스위치. 없으면 대결 순위 탭은 영영 로딩(GamesTetrisDuelRankingPlan.shouldRefresh 가 요구).
        assertTrue(t.rankingEnabled, "테트리스 대결 rankingEnabled 가 꺼져 있다 — 순위 탭이 영영 로딩")
    }

    @Test
    fun doorsReachTheirOwnWindow() {
        val r = Rig(DesktopAppConfig())
        requireNotNull(r.board.gomoku.presentWindow).invoke()
        requireNotNull(r.board.chess.presentWindow).invoke()
        requireNotNull(r.games.tetris.presentWindow).invoke()
        for (kind in listOf(GameWindowKind.Gomoku, GameWindowKind.Chess, GameWindowKind.TetrisDuel)) {
            assertEquals(1, r.shells.getValue(kind).handles.size, "$kind 창이 하나 생기지 않았다")
            assertEquals(1, r.shells.getValue(kind).handles.single().shown, "$kind 창이 앞으로 오지 않았다")
        }
        assertEquals(0, r.shells.getValue(GameWindowKind.MiniGame).handles.size, "판 게임 문이 미니게임 창을 만들었다")
        // dismissWindow = 앱이 닫는다(로그아웃 reset) → 숨기고 DidHide 뒤 DidClose(★CheckGomokuWindow.swift:314 순서).
        requireNotNull(r.games.tetris.dismissWindow).invoke()
        val duel = r.shells.getValue(GameWindowKind.TetrisDuel)
        assertEquals(1, duel.handles.single().hidden)
        assertEquals(listOf(StoreNotice.DidShow, StoreNotice.ReadRefreshRate, StoreNotice.DidHide, StoreNotice.DidClose), duel.notices)
        requireNotNull(r.board.gomoku.requestAttention).invoke()
        assertEquals(1, r.shells.getValue(GameWindowKind.Gomoku).attention)
        assertEquals(0, r.shells.getValue(GameWindowKind.Chess).attention)
    }

    /** W-3 #7 — 대결 깃발이 꺼진 빌드는 신청 안내를 띄우지 않는다. 음성: 깃발을 켜면 안내가 간다. */
    @Test
    fun inviteDoorIsSilentWhileDuelsAreOff() {
        val invite = GomokuInvite("11111111-0000-4000-8000-0000000000a1", GameWindowScenes.SEED_USERS[0], 5, boardClock)
        var off = 0
        requireNotNull(Rig(DesktopAppConfig()) { off++ }.board.gomoku.onInviteArrived).invoke(invite)
        assertEquals(0, off, "깃발 꺼진 빌드가 신청 안내를 냈다")
        var on = 0
        requireNotNull(Rig(DesktopAppConfig(duels = true)) { on++ }.board.gomoku.onInviteArrived).invoke(invite)
        assertEquals(1, on, "깃발 켠 빌드인데 안내가 안 갔다 — 시험이 문을 못 본다")
    }
}

@OptIn(ExperimentalTestApi::class)
class MiniGameFocusPauseTest {
    private class Rig(route: (com.yehsung.aingcheck.testkit.mock.RecordedRequest) -> Pair<String, Int>? = { null }) {
        val scope = TestScope()
        val harness = UiGamesHarness(scope, AppConfig(), route)
        val store = GamesStore(harness.context)
        val state = MiniGameWindowState(store.miniGames)
        val shell = FakeGameWindowShell(sink = state::apply, local = state::onWindowEvent)
        val host = GameWindowScenes.host(GameWindowScenes.fakeShells(GameWindowKind.MiniGame to shell), miniGame = state)
    }

    /** ④ 키 상실 = 일시정지만(0.3.62) — 창 사건 FocusLost 가 표를 거쳐 화면의 정지 카드까지 닿는다. 판은 끝나지 않는다. */
    @Test
    fun focusLostPausesTheRoundWithoutEndingIt() = runDesktopComposeUiTest(440, 720) {
        val r = Rig()
        r.host.openGames(MiniGameKind.tetris)
        setContent { MiniGameWindowContent(r.store, r.state, NO_FACTS, ART, null, { NOW }, false, true, {}, {}, {}) }
        waitForIdle()
        val c = requireNotNull(r.store.miniGames.controller) { "화면이 판을 열지 않았다" }
        // 시험 시계를 손으로 한 장씩 민다(자동 진행이면 쉬는 동안 판 시계가 멀리 흘러 판이 저절로 끝난다 — 화면 몫과 무관한 시험 잡음).
        mainClock.autoAdvance = false
        Snapshot.withMutableSnapshot { c.tap() }
        mainClock.advanceTimeByFrame()
        assertTrue(c.isPlaying, "판이 시작되지 않았다")
        // 음성 대조: 초점이 있는 동안엔 정지 카드가 없다.
        assertEquals(0, onAllNodesWithText("일시정지", useUnmergedTree = true).fetchSemanticsNodes().size, "초점이 있는데 정지 카드가 있다")
        // 창 사건은 EDT 에서 온다 — 시험에선 변경 스냅숏으로 적어 바로 알린다.
        Snapshot.withMutableSnapshot { r.shell.emit(WindowEvent.FocusLost) }
        repeat(3) { mainClock.advanceTimeByFrame() }
        assertEquals(listOf(StoreNotice.ReadRefreshRate, StoreNotice.PauseIfPlaying), r.shell.notices)
        assertFalse(r.state.windowFocused, "키 상실이 화면의 '초점 있음'을 내리지 않았다")
        assertTrue(onAllNodesWithText("일시정지", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty(), "키 상실인데 정지 카드가 없다")
        val frozen = c.tetris.copy()
        repeat(30) { mainClock.advanceTimeByFrame() }
        assertEquals(frozen, c.tetris, "정지인데 판 시계가 흐른다")
        assertTrue(c.isPlaying, "키 상실이 판을 끝냈다 — 일시정지만 해야 한다")
        assertTrue(r.store.miniGames.controller === c, "키 상실이 판을 버렸다")
    }

    /** ③ 닫기 = 판 끝. 기록이 남는 게임(quittingKeepsTheScore)만 제출 1회, 타이밍 바는 0회. */
    @Test
    fun userCloseEndsTheRoundAndOnlyScoreKeepingGamesSubmitOnce() {
        for (kind in listOf(MiniGameKind.tetris, MiniGameKind.timingBar, MiniGameKind.flappy)) {
            var tokens = 0
            val r = Rig { req -> UiFixtures.miniGameRoute(req) { ++tokens } }
            runBlocking { r.harness.signIn() }
            r.host.openGames(kind)
            r.store.miniGames.openScreen(kind) // 화면 수명(GamesMiniGameScreen 의 DisposableEffect)을 대신한다 — 창 0
            r.scope.advanceUntilIdle()
            val c = requireNotNull(r.store.miniGames.controller)
            c.tap()
            r.scope.advanceUntilIdle()
            if (kind == MiniGameKind.tetris) repeat(3) { SoloTetrisKeys.action(c) }
            assertTrue(c.isPlaying, "$kind: 판이 시작되지 않았다")
            val score = c.score
            if (kind == MiniGameKind.tetris) assertTrue(score > 0, "테트리스 판에 점수가 없다 — 제출 1회 단언이 헛돈다")
            r.shell.emit(WindowEvent.UserClosed)
            r.scope.advanceUntilIdle()
            assertTrue(StoreNotice.EndRound in r.shell.notices, "$kind: 닫기가 판 끝 통지를 안 냈다")
            assertEquals(MiniGameWindowRoute.Closed(kind), r.state.route)
            assertEquals(null, r.store.miniGames.controller, "$kind: 닫았는데 판이 살아 있다")
            // 맥 endRound(closing:) → settleMiniGameLiveRound → quittingKeepsTheScore(CheckMiniGameWindow.swift:303 · MiniGamePanel.swift:567-570):
            // 테트리스·플래피는 그 점수로 1회, 타이밍 바는 0회(core endRound 는 플래피를 버린다 — 공용 패치 1 전 임시 어댑터가 MiniGameWindowState 에 있다).
            assertEquals(kind != MiniGameKind.timingBar, MiniGameWindowState.quittingKeepsTheScore(kind))
            val expected = if (kind == MiniGameKind.timingBar) 0 else 1
            assertEquals(expected, r.harness.server.count("minigame_submit_score"), "$kind: 제출 수")
            assertEquals(1, r.shell.handles.single().hidden, "$kind: 닫기가 창을 숨기지 않았다(파괴 금지)")
            assertFalse(r.shell.handles.single().disposed)
            r.harness.close()
        }
    }
}

@OptIn(ExperimentalTestApi::class)
class ExposureTest {
    /** W-3 #1 — 길건너는 Windows 1차에서 숨긴다(MiniGameExposure 그대로). 양성 대조: 같은 허브에 테트리스는 있다. */
    @Test
    fun hubShowsNoCrossy() = runDesktopComposeUiTest(440, 2400) {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        setContent { MiniGameWindowContent(store, state, NO_FACTS, ART, null, { NOW }, false, true, {}, {}, {}) }
        waitForIdle()
        assertTrue(onAllNodesWithText("테트리스", substring = true).fetchSemanticsNodes().isNotEmpty(), "허브에 테트리스가 없다 — 노드를 못 읽는다")
        assertEquals(0, onAllNodesWithText("길건너", substring = true).fetchSemanticsNodes().size, "허브에 길건너가 있다")
        assertFalse(MiniGameKind.crossy in MiniGameExposure.visible)
    }

    /** 데스크톱 목록(허브 visibleKinds = desktopVisible): 허브에 길건너 칸이 서고, 창 문으로 열면 길건너 판(구동기)이 선다. 음성 짝은 위 hubShowsNoCrossy(기본 = 폰 노출). */
    @Test
    fun desktopListShowsAndOpensCrossy() = runDesktopComposeUiTest(440, 2400) {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        store.miniGames.visibleKinds = MiniGameExposure.desktopVisible
        val state = MiniGameWindowState(store.miniGames, visibleKinds = store.miniGames.visibleKinds)
        setContent { MiniGameWindowContent(store, state, NO_FACTS, ART, null, { NOW }, false, true, {}, {}, {}) }
        waitForIdle()
        assertTrue(onAllNodesWithText("길건너", substring = true).fetchSemanticsNodes().isNotEmpty(), "데스크톱 허브에 길건너가 없다")
        Snapshot.withMutableSnapshot { state.show(MiniGameKind.crossy) }
        waitForIdle()
        assertEquals(MiniGameWindowRoute.Game(MiniGameKind.crossy), state.route)
        assertEquals(MiniGameKind.crossy, store.miniGames.controller?.kind, "허브가 길건너 판을 열지 않았다(빈 판)")
    }

    /**
     * kind 없는 열기(플라이아웃 게임 레일 · 두 번째 실행)는 멱등 — 판 도중이면 그 판 그대로(맥 show(), CheckMiniGameWindow.swift:213-235).
     * 실제 화면을 띄워(화면 수명의 closeScreen 까지) 판이 살아 있는지 잰다. 음성 짝: kind 를 주면 그 게임으로 간다 · 허브·닫힘은 그대로.
     */
    @Test
    fun reopeningWithoutAKindKeepsTheRoundInPlay() = runDesktopComposeUiTest(440, 720) {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        val host = GameWindowScenes.host(GameWindowScenes.fakeShells(), miniGame = state)
        host.openGames(null)
        assertEquals(MiniGameWindowRoute.Hub, state.route, "허브에서 kind 없이 열면 허브")
        host.openGames(MiniGameKind.tetris)
        setContent { MiniGameWindowContent(store, state, NO_FACTS, ART, null, { NOW }, false, true, {}, {}, {}) }
        waitForIdle()
        val c = requireNotNull(store.miniGames.controller) { "화면이 판을 열지 않았다" }
        mainClock.autoAdvance = false
        Snapshot.withMutableSnapshot { c.tap() }
        mainClock.advanceTimeByFrame()
        assertTrue(c.isPlaying, "판이 시작되지 않았다")
        Snapshot.withMutableSnapshot { host.openGames(null) }
        repeat(3) { mainClock.advanceTimeByFrame() }
        assertEquals(MiniGameWindowRoute.Game(MiniGameKind.tetris), state.route, "kind 없는 다시 열기가 판 화면을 허브로 돌렸다")
        assertTrue(store.miniGames.controller === c, "kind 없는 다시 열기가 판을 갈아 끼웠다")
        assertTrue(c.isPlaying, "kind 없는 다시 열기가 진행 중인 판을 끝냈다")
        // 양성 짝: kind 를 주면 그 게임으로 간다(판 바꾸기는 사람이 고른 것).
        Snapshot.withMutableSnapshot { host.openGames(MiniGameKind.flappy) }
        repeat(3) { mainClock.advanceTimeByFrame() }
        assertEquals(MiniGameWindowRoute.Game(MiniGameKind.flappy), state.route)
    }

    /** 창 문으로 길건너를 열어도 허브에 남는다. 음성 짝: 테트리스는 바로 게임 화면으로 간다. */
    @Test
    fun openingCrossyThroughTheWindowDoorStaysOnTheHub() {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        val host = GameWindowScenes.host(GameWindowScenes.fakeShells(), miniGame = state)
        host.openGames(MiniGameKind.crossy)
        assertEquals(MiniGameWindowRoute.Hub, state.route)
        host.openGames(MiniGameKind.tetris)
        assertEquals(MiniGameWindowRoute.Game(MiniGameKind.tetris), state.route)
    }
}
