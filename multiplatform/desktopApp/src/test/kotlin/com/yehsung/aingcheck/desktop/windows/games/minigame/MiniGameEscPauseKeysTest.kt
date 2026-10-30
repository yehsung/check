// 원본: Sources/check/MiniGamePanel.swift:316-333(스페이스·ESC 게이트 — ESC 는 정지·재개를 실제로 했을 때만 삼킨다) · :962-990(정지 중 스페이스는 아무 일도 ·
//       onEscape → PauseState.escaped) · :994(wantsStrokes `!pauseState.isFrozen`)
// W4-e 배선(공용 패치 11 뒤): 미니게임 창 키 라우터의 ESC = 정지 토글(MiniGameWindowState.togglePause → ui pauseToggleSerial),
// 정지 카드 · 3-2-1 동안(state.frozen — 화면 onFrozenChanged)은 판 키를 받지 않는다(W4-e unresolved ② "정지 카드 동안 키가 조각을 움직인다" 수리).
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.UiGamesHarness
import com.yehsung.aingcheck.desktop.windows.kit.GameKeyMap
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class MiniGameEscPauseKeysTest {
    private class Board(val state: MiniGameWindowState, val controller: GamesPlayController, val keys: GameKeyRouter) {
        fun press(vk: Int, owns: Boolean = true, repeat: Boolean = false) = keys.route(vk, down = true, hasModifiers = false, isRepeat = repeat, ownsKeys = owns)
        fun release(vk: Int, owns: Boolean = true) = keys.route(vk, down = false, hasModifiers = false, isRepeat = false, ownsKeys = owns)

        /** 판 모양 지문(조각 자리 · 점수) — 키가 판을 움직였는가. */
        fun print(): String = controller.tetris.let { "${it.score}|${it.active}|${it.board}" }
    }

    private fun tetrisBoard(): Board {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        state.show(MiniGameKind.tetris)
        store.miniGames.openScreen(MiniGameKind.tetris)
        val controller = requireNotNull(store.miniGames.controller) { "테트리스 판이 안 열렸다" }
        return Board(state, controller, ComposeGamesWindows.miniGameKeys(store, state))
    }

    @Test
    fun escapeTogglesOnlyWhenThereIsARoundToPause() {
        val b = tetrisBoard()
        // 시작 전: 정지할 판이 없다 — 흘린다(남의 취소 키를 훔치지 않는다).
        assertFalse(b.controller.isPlaying)
        assertFalse(b.press(GameKeyMap.VK_ESCAPE), "시작 전 ESC 를 삼켰다")
        assertEquals(0, b.state.pauseToggleSerial)

        b.controller.tap() // 시작
        assertTrue(b.controller.isPlaying)
        assertFalse(b.press(GameKeyMap.VK_ESCAPE, owns = false), "남의 창으로 간 ESC 를 삼켰다(맥 v0.3.62 — 팝오버 닫는 ESC 가 판을 재개했다)")
        assertEquals(0, b.state.pauseToggleSerial)
        assertTrue(b.press(GameKeyMap.VK_ESCAPE), "판 중 ESC 를 흘렸다")
        assertEquals(1, b.state.pauseToggleSerial, "판 중 ESC 가 정지 토글을 안 올렸다")
        assertTrue(b.press(GameKeyMap.VK_ESCAPE, repeat = true), "ESC 반복은 삼키기만")
        assertEquals(1, b.state.pauseToggleSerial, "ESC 반복이 또 토글했다")
        assertFalse(b.release(GameKeyMap.VK_ESCAPE), "ESC 뗌은 뜻이 없다")

        // 얼어 있는 동안에도 ESC 는 토글(정지 → 3-2-1 · 3-2-1 → 다시 정지).
        b.state.frozen = true
        assertTrue(b.press(GameKeyMap.VK_ESCAPE))
        assertEquals(2, b.state.pauseToggleSerial)
    }

    @Test
    fun frozenRoundTakesNoGameKeys() {
        val b = tetrisBoard()
        b.controller.tap()
        assertTrue(b.controller.isPlaying)

        // 기준선: 얼지 않았으면 ← 가 조각을 움직인다 — 아래 '안 움직임'이 헛것이 아니다(스페이스 하드드롭은 조각을 내려놓아 뒤 대조를 비우므로 마지막에).
        val before = b.print()
        assertTrue(b.press(GameKeyMap.VK_LEFT))
        assertTrue(b.release(GameKeyMap.VK_LEFT))
        assertNotEquals(before, b.print(), "기준선: 키가 판을 안 움직인다")

        b.state.frozen = true
        val frozen = b.print()
        assertFalse(b.press(GameKeyMap.VK_LEFT), "정지 중 ← 를 삼켰다(맥 wantsStrokes 거짓 — 흘린다)")
        assertFalse(b.release(GameKeyMap.VK_LEFT), "정지 중 ← 뗌을 삼켰다")
        assertTrue(b.press(GameKeyMap.VK_SPACE), "정지 중 스페이스는 삼키기만(맥 shouldConsume)")
        assertTrue(b.press(GameKeyMap.VK_UP).not(), "정지 중 회전을 삼켰다")
        assertEquals(frozen, b.print(), "정지 카드 동안 키가 판을 움직였다")

        b.state.frozen = false
        assertTrue(b.press(GameKeyMap.VK_SPACE))
        assertNotEquals(frozen, b.print(), "풀린 뒤에도 키가 안 먹는다(하드드롭 점수)")
    }
}
