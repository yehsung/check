// 원본: Sources/check/MiniGamePanel.swift:146-240(MiniGameSpaceKey — GameKey·Stroke.key·hopDirection·strokeBelongsToGame)
//       · CheckTetrisDuelWindow.swift ★433(뗌 먼저) (W4-d 창 공통 부품 — games.md §4)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame

/** 판이 도는 동안만 쓰는 조작 키(맥 MiniGameSpaceKey.GameKey). */
enum class GameKey { MoveLeft, MoveRight, SoftDrop, RotateCW, RotateCCW, Hold }

/** 한 번의 키 사건. `down == false` 는 뗌이다. */
data class GameStroke(val key: GameKey, val down: Boolean)

/**
 * 가상 키 코드(Win32 VK = AWT KeyEvent.VK_* 와 같은 값) → 조작 키.
 *
 * ★1 **물리 키 자리로만 받는다** — 글자로 받으면 한글 입력 상태에서 Z·X·C 가 'ㅋ'·'ㅌ'·'ㅊ' 로 와서 통째로 빗나간다
 *    (MiniGamePanel.swift:153-156). Windows 에선 IME 가 켜져 있으면 VK_PROCESSKEY(0xE5)로 오므로 미니게임·테트리스 창은
 *    [ImeGate.detach] 로 IME 를 뗀다.
 * ★2 길건너 뛰기 표([hop])는 테트리스 표([tetrisKey])와 **따로** 둔다 — W·A·S·D 는 테트리스 표에서 반드시 null
 *    (아무 글자나 삼키면 다른 창의 타이핑을 훔친다 — MiniGamePanel.swift:194-198).
 * ⚠️3 뗌은 게이트보다 먼저 무조건 전달한다(안 그러면 키가 굳는다 — CheckTetrisDuelWindow.swift ★433).
 * ★4 수정키(Ctrl·Alt·Win·Shift)가 눌린 누름은 무시한다 · 자동 반복(isARepeat)은 무시한다(DAS·ARR 은 게임 시계가 만든다).
 */
object GameKeyMap {
    const val VK_LEFT = 0x25
    const val VK_UP = 0x26
    const val VK_RIGHT = 0x27
    const val VK_DOWN = 0x28
    const val VK_A = 0x41
    const val VK_C = 0x43
    const val VK_D = 0x44
    const val VK_S = 0x53
    const val VK_W = 0x57
    const val VK_X = 0x58
    const val VK_Z = 0x5A
    const val VK_SPACE = 0x20
    const val VK_ESCAPE = 0x1B

    /** ← · → · ↓ · ↑/X 시계 · Z 반시계 · C 홀드(맥 Stroke.key(forKeyCode:) 123·124·125·126/7·6·8). */
    fun tetrisKey(vk: Int): GameKey? = when (vk) {
        VK_LEFT -> GameKey.MoveLeft
        VK_RIGHT -> GameKey.MoveRight
        VK_DOWN -> GameKey.SoftDrop
        VK_UP, VK_X -> GameKey.RotateCW
        VK_Z -> GameKey.RotateCCW
        VK_C -> GameKey.Hold
        else -> null
    }

    /** 길건너 뛰기(맥 hopDirection(forKeyCode:) — ↑·W 앞 · ↓·S 뒤 · ←·A 왼 · →·D 오른). Windows 1차는 길건너를 숨긴다(W-3 #1). */
    fun hop(vk: Int): CrossyGame.Direction? = when (vk) {
        VK_UP, VK_W -> CrossyGame.Direction.forward
        VK_DOWN, VK_S -> CrossyGame.Direction.back
        VK_LEFT, VK_A -> CrossyGame.Direction.left
        VK_RIGHT, VK_D -> CrossyGame.Direction.right
        else -> null
    }

    /** 누름/뗌 짝으로 오는 키인가(맥 GameKey.isLevel). 회전·홀드는 누름만 뜻이 있다. */
    fun isHeld(k: GameKey): Boolean = k == GameKey.MoveLeft || k == GameKey.MoveRight || k == GameKey.SoftDrop

    /**
     * 키 사건 하나를 판정한다. null = 게임이 받지 않는다(이벤트를 그대로 흘린다).
     * [gameOwnsKeys] = 키가 실제로 향한 창이 이 게임 창과 같은 객체이고 판이 얼어 있지 않다(맥 strokeBelongsToGame ∧ ¬isFrozen).
     */
    fun stroke(vk: Int, down: Boolean, hasModifiers: Boolean, isRepeat: Boolean, gameOwnsKeys: Boolean): GameStroke? {
        val key = tetrisKey(vk) ?: return null
        if (!down) return GameStroke(key, down = false)           // ⚠️3 뗌은 게이트보다 먼저
        if (isRepeat || hasModifiers) return null                 // ★4
        if (!gameOwnsKeys) return null
        return GameStroke(key, down = true)
    }
}
