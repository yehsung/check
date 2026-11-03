// 원본: Tests/checkTests/V03xxReversiFlipAnimationTests.swift:38-128(순수 값 몫) @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기 뒤집기 그림([ReversiFlipAnimation]) — 순수 값 계약. 어떤 프레임이든 `now` 하나로 결정되는 값이라 시각을 넣어 프레임을 직접 잰다.
 * 지키는 것: t=0 옛 색 · 반을 지나면 새 색 · 투명도 불변(언제나 두 극단색 중 하나) · 지연은 2차원 고리 거리 · 돌 한 수(+ 패스)만 그림 ·
 * 두 수 건너뜀·패스만·기록 구멍은 그림 없음. 스토어가 창이 보일 때만 세우는 몫(Swift V03xxReversiFlipStoreTests)은 스토어 단계가 옮긴다.
 * [ReversiTurnWarning] 판정식도 여기서 잰다.
 */
class ReversiFlipAnimationTest {
    private val t0 = 1_793_660_908.0

    private fun stone(seq: Int, color: ReversiColor, idx: Int, flipped: List<Int>) = ReversiPly(seq, color, ReversiPly.Kind.stone, idx, flipped, false)

    private fun pass(seq: Int, color: ReversiColor) = ReversiPly(seq, color, ReversiPly.Kind.pass, null, emptyList(), false)

    /** Swift `make(from: rvMatch("m", count: 4), to: rvMatch(id, count:, plies:))` — 프로덕션 짝 [ReversiFlipAnimation.make](previousMatchID, …) 를 그대로 부른다(판 id 가드는 그 안에 있다). */
    private fun make(previousID: String?, nextID: String, count: Int, plies: List<ReversiPly>): ReversiFlipAnimation? =
        ReversiFlipAnimation.make(previousID, 4, nextID, count, plies, t0)

    @Test
    fun startsWithOldColorAndSwitchesAtHalf() {
        // 없으면: 첫 프레임부터 새 색이거나(뒤집힘이 안 보인다) 끝까지 옛 색이어도(판과 그림이 어긋난다) 초록이다.
        val anim = ReversiFlipAnimation("m", t0, 19, ReversiColor.black, listOf(27))
        assertEquals(ReversiColor.white, anim.displayedColor(27, t0))
        assertEquals(1.0, anim.xScale(27, t0))
        val half = t0 + ReversiFlipAnimation.flipDuration / 2
        assertEquals(ReversiColor.white, anim.displayedColor(27, half - 0.01))
        assertEquals(ReversiColor.black, anim.displayedColor(27, half + 0.001))
        assertTrue(anim.xScale(27, half + 0.001) < 0.02)
        val end = t0 + ReversiFlipAnimation.flipDuration + 0.001
        assertEquals(ReversiColor.black, anim.displayedColor(27, end))
        assertTrue(abs(anim.xScale(27, end) - 1) < 0.000_001)
        assertTrue(anim.isFinished(end))
        assertFalse(anim.isFinished(end - 0.02))
        // 놓은 칸·무관한 칸은 그림이 없다(판 그대로).
        assertNull(anim.displayedColor(19, half))
        assertNull(anim.progress(0, half))
        assertEquals(1.0, anim.xScale(0, half))
    }

    @Test
    fun delayIsTwoDimensionalRingDistance() {
        // 없으면: 1차원 idx 차로 거리를 재서 h1(7)과 a2(8)를 이웃으로 보는(행 끝 넘김, V-01) 구현도 초록이다.
        val wrap = ReversiFlipAnimation("m", t0, 7, ReversiColor.white, listOf(8))
        assertTrue(abs((wrap.delays[8] ?: -1.0) - 6 * ReversiFlipAnimation.ringDelay) < 0.000_001)
        val diagonal = ReversiFlipAnimation("m", t0, 0, ReversiColor.black, listOf(9, 18, 27))
        assertEquals(0.0, diagonal.delays[9])
        assertTrue(abs((diagonal.delays[18] ?: -1.0) - ReversiFlipAnimation.ringDelay) < 0.000_001)
        assertTrue(abs((diagonal.delays[27] ?: -1.0) - 2 * ReversiFlipAnimation.ringDelay) < 0.000_001)
        assertTrue(abs(diagonal.duration - (2 * ReversiFlipAnimation.ringDelay + ReversiFlipAnimation.flipDuration)) < 0.000_001)
        // 늦게 시작하는 칸은 앞 칸이 반을 넘었을 때도 아직 옛 색이다.
        val t = t0 + ReversiFlipAnimation.flipDuration / 2 + 0.01
        assertEquals(ReversiColor.black, diagonal.displayedColor(9, t))
        assertEquals(ReversiColor.white, diagonal.displayedColor(27, t))
        // 박자 값 고정(맥과 같은 숫자 — 화면 갈래가 이 값으로 그린다).
        assertEquals(0.32, ReversiFlipAnimation.flipDuration)
        assertEquals(0.06, ReversiFlipAnimation.ringDelay)
    }

    @Test
    fun neverTouchesOpacity() {
        // 없으면: 이징으로 투명도를 깎는 구현(밀려나기 전에 사라진다 — 렌더 감지기가 돌을 못 센다)도 초록이다.
        val anim = ReversiFlipAnimation("m", t0, 0, ReversiColor.black, listOf(1, 2, 3, 9, 18))
        var t = t0
        while (t <= t0 + anim.duration) {
            for (idx in anim.flipped) {
                val color = anim.displayedColor(idx, t)
                assertTrue(color == ReversiColor.black || color == ReversiColor.white, "칸 $idx 가 ${t - t0}초에 색이 없다")
            }
            t += 0.01
        }
        val source = RepoFiles.readText(SOURCE).lines().joinToString("\n") { line -> line.substringBefore("//") }.lowercase()
        assertFalse("opacity" in source)
        assertFalse("alpha" in source)
    }

    @Test
    fun onlyOneStonePlusPassAnimates() {
        // 없으면: 두 수를 한 장으로 미끄러뜨리거나 · 패스만 온 응답에도 그림이 서거나 · 다른 판으로 바뀐 화면 전환이 애니메이션으로 둔갑해도 초록이다.
        val made = make("m", "m", 5, listOf(stone(5, ReversiColor.black, 19, listOf(27))))
        assertEquals(19, made?.placedIdx)
        assertEquals(listOf(27), made?.flipped)
        assertEquals(ReversiColor.black, made?.color)
        assertEquals("m", made?.matchID)
        assertEquals(listOf(1), make("m", "m", 6, listOf(stone(5, ReversiColor.black, 2, listOf(1)), pass(6, ReversiColor.white)))?.flipped)
        assertNull(make("m", "m", 6, listOf(stone(5, ReversiColor.black, 19, listOf(27)), stone(6, ReversiColor.white, 18, listOf(27)))))
        assertNull(make("m", "m", 5, listOf(pass(5, ReversiColor.black))))
        assertNull(make("m", "other", 5, listOf(stone(5, ReversiColor.black, 19, listOf(27)))))
        assertNull(make(null, "m", 5, listOf(stone(5, ReversiColor.black, 19, listOf(27)))))
        assertNull(make("m", "m", 3, emptyList()))
        assertNull(make("m", "m", 5, emptyList()), "수 번호는 올랐는데 기록이 없다")
        assertNull(make("m", "m", 7, listOf(stone(5, ReversiColor.black, 19, listOf(27)), pass(6, ReversiColor.white), pass(7, ReversiColor.black))))
    }

    @Test
    fun turnWarningWatchesOnlyMyRunningClock() {
        // 없으면: 상대 차례·끝난 판·마감 없는 AI 차례에도 테두리가 빨개지거나, 내 차례에 안 서도 초록이다.
        val deadline = t0 + 30
        assertTrue(ReversiTurnWarning.watchesMyClock(false, deadline, ReversiColor.black, ReversiColor.black))
        assertFalse(ReversiTurnWarning.watchesMyClock(false, deadline, ReversiColor.white, ReversiColor.black), "상대 차례")
        assertFalse(ReversiTurnWarning.watchesMyClock(true, deadline, ReversiColor.black, ReversiColor.black), "끝난 판")
        assertFalse(ReversiTurnWarning.watchesMyClock(false, null, ReversiColor.black, ReversiColor.black), "마감 없음(AI 차례 · 멈춘 시계)")
        assertFalse(ReversiTurnWarning.watchesMyClock(false, deadline, null, ReversiColor.black), "차례 없음")
        // 숫자는 오목 한 벌을 그대로 쓴다(3초 문턱 · 세기).
        assertTrue(GomokuTurnWarning.isActive(3.0) && !GomokuTurnWarning.isActive(3.01))
    }

    private companion object {
        const val SOURCE = "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/reversi/ReversiFlipAnimation.kt"
    }
}
