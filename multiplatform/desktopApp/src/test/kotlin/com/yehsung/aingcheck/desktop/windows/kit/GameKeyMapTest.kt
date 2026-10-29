// 원본: Sources/check/MiniGamePanel.swift:159-205(GameKey.isLevel · Stroke.key(forKeyCode:) · hopDirection(forKeyCode:)) ·
//       CheckTetrisDuelWindow.swift ★433(뗌 먼저) (W4-d)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import java.awt.event.KeyEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

class GameKeyMapTest {
    /** 맥 ANSI keyCode(Carbon Events.h) → Windows VK(= AWT KeyEvent.VK_*). 같은 물리 키 자리. */
    private val macToVk = mapOf(
        123 to KeyEvent.VK_LEFT, 124 to KeyEvent.VK_RIGHT, 125 to KeyEvent.VK_DOWN, 126 to KeyEvent.VK_UP,
        6 to KeyEvent.VK_Z, 7 to KeyEvent.VK_X, 8 to KeyEvent.VK_C,
        13 to KeyEvent.VK_W, 0 to KeyEvent.VK_A, 1 to KeyEvent.VK_S, 2 to KeyEvent.VK_D,
        49 to KeyEvent.VK_SPACE, 53 to KeyEvent.VK_ESCAPE,
    )

    /** MiniGamePanel.swift:180-190 Stroke.key(forKeyCode:) 그대로. */
    private val macTetris = mapOf(
        123 to GameKey.MoveLeft, 124 to GameKey.MoveRight, 125 to GameKey.SoftDrop,
        126 to GameKey.RotateCW, 7 to GameKey.RotateCW, 6 to GameKey.RotateCCW, 8 to GameKey.Hold,
    )

    /** MiniGamePanel.swift:199-205 hopDirection(forKeyCode:) 그대로. */
    private val macHop = mapOf(
        126 to CrossyGame.Direction.forward, 13 to CrossyGame.Direction.forward,
        125 to CrossyGame.Direction.back, 1 to CrossyGame.Direction.back,
        123 to CrossyGame.Direction.left, 0 to CrossyGame.Direction.left,
        124 to CrossyGame.Direction.right, 2 to CrossyGame.Direction.right,
    )

    @Test
    fun vkConstantsAreAwtAndWin32Values() {
        assertEquals(KeyEvent.VK_SPACE, GameKeyMap.VK_SPACE)
        assertEquals(KeyEvent.VK_ESCAPE, GameKeyMap.VK_ESCAPE)
        assertEquals(0x20, GameKeyMap.VK_SPACE)
        assertEquals(0x1B, GameKeyMap.VK_ESCAPE)
    }

    /** ★1 테트리스 표 1:1 — 맥 표의 모든 칸이 같은 물리 키 자리에서 같은 조작으로, 표 밖 키(0..255)는 전부 null. */
    @Test
    fun star1_tetrisTableMatchesMacOneToOne() {
        for ((mac, vk) in macToVk) assertEquals(macTetris[mac], GameKeyMap.tetrisKey(vk), "mac $mac → vk 0x${vk.toString(16)}")
        val expectedVks = macTetris.keys.map { macToVk.getValue(it) }.toSet()
        for (vk in 0..255) if (vk !in expectedVks) assertNull(GameKeyMap.tetrisKey(vk), "vk 0x${vk.toString(16)}")
    }

    /** ★2 WASD 는 테트리스 표에서 반드시 null(남의 타이핑을 훔치지 않는다) — 길건너 표에만 있다. 스페이스·ESC 도 표 밖. */
    @Test
    fun star2_wasdNeverInTetrisTable() {
        for (vk in listOf(KeyEvent.VK_W, KeyEvent.VK_A, KeyEvent.VK_S, KeyEvent.VK_D, KeyEvent.VK_SPACE, KeyEvent.VK_ESCAPE)) {
            assertNull(GameKeyMap.tetrisKey(vk), "vk 0x${vk.toString(16)}")
        }
    }

    @Test
    fun hopTableMatchesMacOneToOne() {
        for ((mac, vk) in macToVk) assertEquals(macHop[mac], GameKeyMap.hop(vk), "mac $mac")
        val expectedVks = macHop.keys.map { macToVk.getValue(it) }.toSet()
        for (vk in 0..255) if (vk !in expectedVks) assertNull(GameKeyMap.hop(vk), "vk 0x${vk.toString(16)}")
    }

    /** 맥 GameKey.isLevel: ←·→·↓ 만 누름/뗌 짝. */
    @Test
    fun heldKeysAreMoveAndSoftDropOnly() {
        val held = GameKey.entries.filter { GameKeyMap.isHeld(it) }.toSet()
        assertEquals(setOf(GameKey.MoveLeft, GameKey.MoveRight, GameKey.SoftDrop), held)
    }

    /** ⚠️3 뗌은 게이트·수정키·반복과 상관없이 언제나 전달(안 그러면 키가 굳는다). */
    @Test
    fun warn3_releaseAlwaysDelivered() {
        for (gate in listOf(true, false)) for (mods in listOf(true, false)) for (rep in listOf(true, false)) {
            assertEquals(GameStroke(GameKey.MoveLeft, down = false),
                GameKeyMap.stroke(KeyEvent.VK_LEFT, down = false, hasModifiers = mods, isRepeat = rep, gameOwnsKeys = gate))
        }
    }

    /** ★4 누름: 수정키·자동 반복·게이트 닫힘이면 흘린다. 표 밖 키는 언제나 흘린다. */
    @Test
    fun star4_pressFilteredByModifiersRepeatAndGate() {
        assertEquals(GameStroke(GameKey.Hold, true), GameKeyMap.stroke(KeyEvent.VK_C, true, false, false, true))
        assertNull(GameKeyMap.stroke(KeyEvent.VK_C, true, hasModifiers = true, isRepeat = false, gameOwnsKeys = true))
        assertNull(GameKeyMap.stroke(KeyEvent.VK_LEFT, true, hasModifiers = false, isRepeat = true, gameOwnsKeys = true))
        assertNull(GameKeyMap.stroke(KeyEvent.VK_Z, true, hasModifiers = false, isRepeat = false, gameOwnsKeys = false))
        assertNull(GameKeyMap.stroke(KeyEvent.VK_W, false, false, false, true))
        assertFalse(GameKeyMap.stroke(KeyEvent.VK_UP, true, false, false, true)?.key != GameKey.RotateCW)
    }
}
