// 원본: 없음 — Swift 값 타입(struct) 의미를 Kotlin 참조 타입으로 옮긴 자리의 시험(복사 = 갈라짐 · 읽기 = 사본). 골든이 못 재는 Kotlin 몫이다.
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Swift 에서 `var b = a` 는 판을 둘로 가른다(난수 상태까지). Kotlin 은 [TetrisGame.copy] 등을 불러야 같은 뜻이 된다.
 * 그리고 Swift 의 `package private(set) var game` 처럼 **읽은 값을 고쳐도 주인이 안 바뀌어야** 하는 자리(대결 세션의 엔진 · 길건너 줄 난수)는
 * 읽을 때마다 사본을 준다. 기준선: 복사 직후에는 같고(equals), 한쪽만 움직이면 달라진다.
 */
class ValueSemanticsTest {
    @Test
    fun tetrisCopyForksBoardAndRandomStream() {
        val a = TetrisGame(42uL)
        a.action()
        val b = a.copy()
        assertEquals(a, b, "복사 직후는 같은 판")
        b.action()                                   // 하드드롭
        assertNotEquals(a.advance, b.advance, "복사본을 움직였는데 원본도 움직였다")
        // 봉지를 두 번 넘게 비우도록(7조각 × 2) 더 떨어뜨린다 — 난수를 나눠 쓰면 여기서 두 판의 조각열이 갈린다.
        fun drop(g: TetrisGame) = repeat(16) { g.step(0.05); g.step(0.05); g.action() }
        drop(b)
        a.action()
        drop(a)
        assertEquals(a.advance, b.advance)
        assertEquals(a.next, b.next, "같은 상태에서 갈라진 두 판은 같은 조각열을 낸다(난수 상태도 복사됐다)")
        assertEquals(TetrisGoldenSupport.boardText(a), TetrisGoldenSupport.boardText(b))
    }

    @Test
    fun duelSessionGameIsAReadOnlyCopy() {
        val s = TetrisDuelSession(7L)
        s.syncStart(0.0, 0.0, 0.0)
        s.advance(0.5)
        assertTrue(s.isLive)
        val before = s.game.advance
        val leaked = s.game
        leaked.action()                              // 바깥에서 받은 사본을 하드드롭
        assertEquals(before, s.game.advance, "세션 밖에서 엔진을 움직였다(입력 문지기 isLive 를 건너뜀)")
        s.hardDrop()
        assertEquals(before + 1, s.game.advance, "세션 문으로는 움직여야 한다(기준선)")
        val fork = s.copy()
        fork.advance(0.7)                            // ARE(0.1초)를 지나 다음 조각을 띄우고
        fork.hardDrop()
        assertNotEquals(fork.game.advance, s.game.advance, "세션 복사본이 원본과 엔진을 나눈다")
    }

    @Test
    fun otherGamesCopyIndependently() {
        val flappy = FlappyGame(3uL).also { it.flap() }
        val flappyFork = flappy.copy()
        flappyFork.step(1.0 / 30.0)
        assertNotEquals(flappy.elapsed, flappyFork.elapsed)
        val timing = TimingBarGame(3uL).also { it.tap() }
        val timingFork = timing.copy()
        timingFork.tap()
        assertNotEquals(timing.phase, timingFork.phase)
        val crossy = CrossyGame(5uL)
        val crossyFork = crossy.copy()
        assertEquals(crossy, crossyFork)
        crossyFork.action()
        repeat(30) { crossyFork.step(1.0 / 30.0) }
        assertNotEquals(crossy, crossyFork)
        assertEquals(CrossyGame(5uL), crossy, "복사본을 돌렸는데 원본 판이 바뀌었다(줄 객체를 나눠 썼다)")
    }

    @Test
    fun crossyTrainRandomReadIsACopy() {
        val lane = CrossyGame.Lane(20, CrossyGame.LaneKind.rail, direction = 1, speed = 24.0, trainCountdown = 2.0, trainSeed = 9uL)
        val state = lane.trainRandom.state
        lane.trainRandom.next()                      // 읽은 사본을 굴려도
        assertEquals(state, lane.trainRandom.state, "줄의 기차 난수가 바깥에서 굴렀다")
        assertEquals(lane, lane.copy())
    }
}
