// 원본: Sources/check/MiniGamePanel.swift:302-311(★★ 뗌은 게이트보다 먼저, 무조건 — 삼킴은 `belongs && wantsStrokes()`) ·
//       CheckTetrisDuelWindow.swift:428-445(★433 뗌 먼저 — 삼킴은 `belongs && live`) · :535-539(isLive = 카운트다운·판 중)
//       (W4-e 반박 수정 — 창마다 전역 KeyEventDispatcher 가 생성 순서로 붙고 앞이 true 면 뒤는 못 본다: 남의 창 뗌을 삼키면 그 창 키가 굳는다)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelPhase
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelInput
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelKeys
import com.yehsung.aingcheck.desktop.windows.kit.GameKey
import com.yehsung.aingcheck.desktop.windows.kit.GameKeyMap
import com.yehsung.aingcheck.desktop.windows.kit.GameStroke
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GameKeyRoutingTest {
    /** 대결 입력 기록기 — 스토어 대신 무엇이 닿았는지 적는다. */
    private class DuelRecorder(live: Boolean) : TetrisDuelInput {
        val strokes = mutableListOf<GameStroke>()
        var drops = 0
        private var liveNow = live
        override val live: Boolean get() = liveNow
        fun setLive(v: Boolean) { liveNow = v }
        override fun stroke(stroke: GameStroke) { strokes += stroke }
        override fun hardDrop() { drops++ }
    }

    /** 솔로 쪽 기록 라우터 — 받은 (키, 누름, 반복)을 적고 owns 만큼 삼킨다. */
    private class Seen(val vk: Int, val down: Boolean, val repeat: Boolean)

    private fun recordingRouter(into: MutableList<Seen>) = GameKeyRouter { vk, down, _, repeat, owns ->
        into += Seen(vk, down, repeat)
        owns
    }

    /** AWT DefaultKeyboardFocusManager 그대로: 붙은 순서로 묻고, 앞이 true 면 뒤는 못 본다. [owner] = 키가 향한 창의 자리. */
    private fun chain(dispatchers: List<GameKeyDispatch>, owner: Int, vk: Int, down: Boolean) {
        for ((i, d) in dispatchers.withIndex()) {
            if (d.dispatch(vk, down, hasModifiers = false, ownsKeys = i == owner)) return
        }
    }

    /** 테트리스 판이 열린 미니게임 창의 키 라우터(창 0 — 화면 수명은 openScreen 이 대신한다). */
    private fun miniGameWithTetrisBoard(): GameKeyRouter {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        state.show(MiniGameKind.tetris)
        store.miniGames.openScreen(MiniGameKind.tetris)
        assertEquals(MiniGameKind.tetris, store.miniGames.controller?.kind, "테트리스 판이 안 열렸다 — 라우터가 일찍 빠진다")
        return ComposeGamesWindows.miniGameKeys(store, state)
    }

    /**
     * ① 미니게임 창(테트리스 판)이 먼저 생긴 세션: 대결 창의 ←뗌이 미니게임 디스패처를 지나 대결까지 가야 한다(★433 ⚠️뗌 먼저).
     * 못 가면 대결 스토어 setLeftHeld(true) 가 남고(판돈 판에서 조각이 계속 밀림), 대결 창 눌린 키 표에 ← 가 남아 다음 누름이 반복(★4)으로 버려진다.
     */
    @Test
    fun duelReleasePassesTheMiniGameDispatcherAhead() {
        val duel = DuelRecorder(live = true)
        val dispatchers = listOf(GameKeyDispatch(miniGameWithTetrisBoard()), GameKeyDispatch(ComposeGamesWindows.duelKeys(duel)))
        chain(dispatchers, owner = 1, vk = GameKeyMap.VK_LEFT, down = true)
        chain(dispatchers, owner = 1, vk = GameKeyMap.VK_LEFT, down = false)
        chain(dispatchers, owner = 1, vk = GameKeyMap.VK_LEFT, down = true)
        assertEquals(
            listOf(GameStroke(GameKey.MoveLeft, true), GameStroke(GameKey.MoveLeft, false), GameStroke(GameKey.MoveLeft, true)),
            duel.strokes, "대결 창 ←뗌이 앞 디스패처에 삼켜졌다(키 굳음) 또는 다음 누름이 반복으로 버려졌다",
        )
    }

    /** ② 대결 창이 먼저 생긴 세션: 솔로 창 뗌을 대결 디스패처가 삼키면 솔로 ← 는 초점을 잃기 전까지 한 번만 먹는다. */
    @Test
    fun soloReleasePassesTheDuelDispatcherAhead() {
        val games = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        games.tetris.phase = TetrisDuelPhase.playing // 대결 판 중에도 남의 창 뗌은 삼키지 않는다
        val solo = mutableListOf<Seen>()
        val dispatchers = listOf(GameKeyDispatch(ComposeGamesWindows.duelKeys(games)), GameKeyDispatch(recordingRouter(solo)))
        repeat(2) {
            chain(dispatchers, owner = 1, vk = GameKeyMap.VK_LEFT, down = true)
            chain(dispatchers, owner = 1, vk = GameKeyMap.VK_LEFT, down = false)
        }
        assertEquals(listOf(true, false, true, false), solo.map { it.down }, "솔로 창 뗌이 대결 디스패처에 삼켜졌다")
        assertFalse(solo.any { it.repeat }, "솔로 창 두 번째 ← 누름이 반복으로 읽혔다(눌린 키 표에 뗌이 안 닿음)")
    }

    /** ★433 ⚠️뗌은 게이트보다 먼저, 무조건 적용 — 삼킴만 owns ∧ 판 흐름(CheckTetrisDuelWindow.swift:433-436). */
    @Test
    fun duelReleaseIsAppliedAlwaysButSwallowedOnlyByItsOwnLiveWindow() {
        val duel = DuelRecorder(live = true)
        val keys = ComposeGamesWindows.duelKeys(duel)
        assertFalse(keys.route(GameKeyMap.VK_LEFT, down = false, hasModifiers = false, isRepeat = false, ownsKeys = false), "남의 창 뗌을 삼켰다")
        assertEquals(listOf(GameStroke(GameKey.MoveLeft, false)), duel.strokes, "남의 창으로 간 뗌을 적용하지 않았다(키 굳음)")
        assertTrue(keys.route(GameKeyMap.VK_LEFT, down = false, hasModifiers = true, isRepeat = false, ownsKeys = true), "제 창 뗌을 흘렸다")
        assertEquals(2, duel.strokes.size, "수정키 단 뗌을 버렸다(←를 잡은 채 Ctrl — 뗌엔 수정키 가드를 안 건다)")
        duel.setLive(false)
        assertFalse(keys.route(GameKeyMap.VK_LEFT, down = false, hasModifiers = false, isRepeat = false, ownsKeys = true), "판 흐름 밖인데 뗌을 삼켰다")
        assertEquals(3, duel.strokes.size, "판 흐름 밖 뗌을 적용하지 않았다")
    }

    /** 대결 누름은 판 흐름(카운트다운·판 중)에서만 — 로비에선 스페이스가 초점 단추로 간다(:535-539). ★4 반복은 삼키기만. */
    @Test
    fun duelPressesOnlyLandWhileTheRoundIsLive() {
        val duel = DuelRecorder(live = false)
        val keys = ComposeGamesWindows.duelKeys(duel)
        assertFalse(keys.route(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, isRepeat = false, ownsKeys = true), "판 흐름 밖 ← 누름을 삼켰다")
        assertFalse(keys.route(GameKeyMap.VK_SPACE, down = true, hasModifiers = false, isRepeat = false, ownsKeys = true), "로비에서 스페이스를 삼켰다")
        assertEquals(0, duel.strokes.size + duel.drops, "판 흐름 밖 누름이 스토어에 갔다")
        duel.setLive(true)
        assertTrue(keys.route(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, isRepeat = false, ownsKeys = true))
        assertTrue(keys.route(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, isRepeat = true, ownsKeys = true), "★4 반복을 흘렸다")
        assertTrue(keys.route(GameKeyMap.VK_SPACE, down = true, hasModifiers = false, isRepeat = false, ownsKeys = true))
        assertFalse(keys.route(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, isRepeat = false, ownsKeys = false), "남의 창 누름을 받았다")
        assertEquals(listOf(GameStroke(GameKey.MoveLeft, true)), duel.strokes, "반복·남의 창 누름이 스토어에 갔다")
        assertEquals(1, duel.drops)

        // 실제 스토어의 판 흐름: 카운트다운·판 중만.
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context).tetris
        val live = TetrisDuelPhase.entries.filter { store.phase = it; TetrisDuelKeys.isLive(store) }
        assertEquals(listOf(TetrisDuelPhase.countdown, TetrisDuelPhase.playing), live)
        store.phase = TetrisDuelPhase.playing
        assertTrue(TetrisDuelKeys.input(store).live)
    }

    /** ★4 반복 판정은 이 창이 받은 누름만 센다 — 남의 창 누름의 뗌을 다른 디스패처가 가져가도 이 창 첫 누름이 반복으로 버려지지 않는다. */
    @Test
    fun repeatDetectionCountsOnlyPressesThisWindowOwned() {
        val seen = mutableListOf<Seen>()
        val d = GameKeyDispatch(recordingRouter(seen))
        d.dispatch(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, ownsKeys = false) // 남의 창 누름 — 그 뗌은 여기 안 온다
        d.dispatch(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, ownsKeys = true)
        d.dispatch(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, ownsKeys = true) // 진짜 자동 반복
        assertEquals(listOf(false, false, true), seen.map { it.repeat }, "남의 창 누름이 이 창 반복 판정을 흐렸다 또는 자동 반복을 못 가렸다")
    }

    /** 솔로 창: 남의 창 뗌은 삼키지 않고(⚠️), 제 판 키 뗌은 삼킨다(짝 잃은 뗌이 남의 손에 가지 않게). */
    @Test
    fun soloReleaseIsSwallowedOnlyByItsOwnBoard() {
        val keys = miniGameWithTetrisBoard()
        assertFalse(keys.route(GameKeyMap.VK_LEFT, down = false, hasModifiers = false, isRepeat = false, ownsKeys = false), "남의 창 뗌을 삼켰다")
        assertTrue(keys.route(GameKeyMap.VK_LEFT, down = false, hasModifiers = false, isRepeat = false, ownsKeys = true), "제 판 뗌을 흘렸다")
        assertTrue(keys.route(GameKeyMap.VK_LEFT, down = true, hasModifiers = false, isRepeat = true, ownsKeys = true), "★4 반복을 흘렸다")
    }
}
