// 원본: 없음 — 솔로 컨트롤러의 키보드 누름/뗌(setLeftHeld·setRightHeld·setSoftDropHeld·releaseAllKeys)이 대결 쪽(TetrisDuelSession)과
//   같은 엔진 문을 지나는지 **이 컨트롤러를 실제로 지나며** 잰다(엔진 계약 시험은 이 배선을 대신하지 못한다 — 같은 파일의 끌기 시험 주석).
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelSession
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GamesPlayControllerHeldKeysTest {
    private val t0 = SwiftDate(1_000_000.0)
    private fun at(seconds: Double) = t0.addingTimeInterval(seconds)

    /** 판을 켜고 첫 조각이 나올 때까지 민다. 마지막 틱 시각을 함께 준다. */
    private fun startedTetris(seed: ULong = 7u): Pair<GamesPlayController, Double> {
        val c = GamesPlayController(MiniGameKind.tetris, seed)
        c.tap()
        c.tick(at(0.0))
        var s = 0.0
        while (c.tetris.active == null && s < 2) {
            s += 1.0 / 60
            c.tick(at(s))
        }
        check(c.tetris.phase == TetrisGame.Phase.Running && c.tetris.active != null) { "판이 안 섰다: ${c.tetris.phase}" }
        return c to s
    }

    /** 컨트롤러와 대결 세션을 **같은 판 상태**에서 같은 시각표로 민다. [steps] 개의 0.01초 틱. */
    private class Pair2(val c: GamesPlayController, var s: Double, val duel: TetrisDuelSession, var d: Double) {
        fun tick(steps: Int) = repeat(steps) {
            s += 0.01
            c.tick(SwiftDate(1_000_000.0).addingTimeInterval(s))
            d += 0.01
            duel.advance(d)
        }
        val controllerColumn get() = c.tetris.active!!.column
        val duelColumn get() = duel.game.active!!.column
    }

    private fun pair(seed: ULong = 7u): Pair2 {
        val (c, s) = startedTetris(seed)
        return Pair2(c, s, TetrisDuelSession(seed.toLong(), startedGame = c.tetris, startAt = 0.0), 0.0)
    }

    /**
     * 누름 → 0.22초 틱 → 뗌: 즉시 1칸 + DAS(0.167) 1칸 + ARR(0.200) 1칸 = **3칸**, 대결 세션과 같은 칸 수.
     * 뗀 뒤 0.3초를 더 밀어도 그대로다(눌린 채 남지 않는다). 왼쪽·오른쪽 둘 다.
     */
    @Test
    fun heldKeysRepeatExactlyLikeTheDuel() {
        for ((dir, sign) in listOf("left" to -1, "right" to 1)) {
            for (seed in listOf<ULong>(7u, 11u, 23u)) {
                val p = pair(seed)
                val col0 = p.controllerColumn
                assertEquals(col0, p.duelColumn, "같은 판에서 출발")
                if (sign < 0) { p.c.setLeftHeld(true); p.duel.setLeftHeld(true) } else { p.c.setRightHeld(true); p.duel.setRightHeld(true) }
                assertEquals(col0 + sign, p.controllerColumn, "$dir/$seed: 누르는 순간 한 칸")
                p.tick(22)
                val moved = p.controllerColumn - col0
                if (sign < 0) { p.c.setLeftHeld(false); p.duel.setLeftHeld(false) } else { p.c.setRightHeld(false); p.duel.setRightHeld(false) }
                assertEquals(p.duelColumn - col0, moved, "$dir/$seed: 대결 세션과 같은 칸 수")
                assertEquals(3 * sign, moved, "$dir/$seed: 즉시 + DAS + ARR 한 번")
                p.tick(30)
                assertEquals(col0 + moved, p.controllerColumn, "$dir/$seed: 뗀 뒤 움직이지 않는다")
                assertEquals(p.duelColumn, p.controllerColumn, "$dir/$seed: 뗀 뒤도 대결과 같다")
            }
        }
    }

    /** 소프트드롭 누름: 같은 시간 동안 대결 세션과 같은 줄 수만큼 내려가고, 누르지 않은 판보다 빨리 내려간다. */
    @Test
    fun softDropHeldFallsLikeTheDuel() {
        val p = pair()
        val idle = pair()
        val row0 = p.c.tetris.active!!.row
        p.c.setSoftDropHeld(true)
        p.duel.setSoftDropHeld(true)
        p.tick(15)
        idle.tick(15)
        assertEquals(p.duel.game.active!!.row, p.c.tetris.active!!.row, "대결 세션과 같은 줄")
        assertTrue(p.c.tetris.active!!.row - row0 > idle.c.tetris.active!!.row - row0, "누른 판이 더 내려간다")
        assertEquals(p.duel.game.score, p.c.tetris.score, "소프트드롭 점수도 같다")
    }

    /** releaseAllKeys: 눌린 키가 모두 풀려 **더는 옆으로 가지 않는다**. 대결 세션의 releaseAllKeys 와 같다. */
    @Test
    fun releaseAllKeysStopsAllMovement() {
        val p = pair()
        p.c.setLeftHeld(true)
        p.duel.setLeftHeld(true)
        p.tick(5)
        p.c.releaseAllKeys()
        p.duel.releaseAllKeys()
        val col = p.controllerColumn
        p.tick(40)
        assertEquals(col, p.controllerColumn, "풀린 뒤 이동 0")
        assertEquals(p.duelColumn, p.controllerColumn)
        p.c.releaseAllKeys()                                // 멱등
        p.tick(5)
        assertEquals(col, p.controllerColumn)
    }

    /** 다른 게임은 아무 일도 없다 — 테트리스 판을 억지로 넣어 둬도(replaceForTesting) 그 판을 건드리지 않는다. */
    @Test
    fun otherGamesIgnoreHeldKeys() {
        val running = startedTetris().first.tetris
        for (kind in listOf(MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.crossy)) {
            val c = GamesPlayController(kind, 3u)
            c.replaceForTesting(tetris = running.copy())
            val timing = c.timing
            val flappy = c.flappy
            val column = c.tetris.active!!.column
            c.setLeftHeld(true)
            c.setRightHeld(true)
            c.setSoftDropHeld(true)
            c.releaseAllKeys()
            c.setLeftHeld(true)
            assertEquals(column, c.tetris.active!!.column, "${kind.rawValue}: 테트리스 판을 건드리지 않는다")
            assertEquals(timing, c.timing, kind.rawValue)
            assertEquals(flappy, c.flappy, kind.rawValue)
        }
    }

    /** 살아 있지 않은 판(시작 전·결과 카드)에서는 누름을 버리고 판을 켜지 않는다. 뗌은 언제나 받는다. */
    @Test
    fun pressesOutsideALiveRoundAreDropped() {
        val c = GamesPlayController(MiniGameKind.tetris, 7u)
        c.setLeftHeld(true)
        c.setSoftDropHeld(true)
        assertFalse(c.isPlaying, "누름이 판을 켜지 않는다(켜는 것은 tap)")
        assertEquals(TetrisGame.Phase.Ready, c.tetris.phase)
        val (live, _) = startedTetris()
        live.endRound()
        assertEquals(TetrisGame.Phase.Result, live.tetris.phase)
        val before = live.tetris
        live.setRightHeld(true)
        assertEquals(before, live.tetris, "결과 카드에서는 누름을 버린다")
        live.setRightHeld(false)
        live.releaseAllKeys()
        assertFalse(live.isPlaying)
    }
}
