// 원본: Tests/checkTests/ReversiAIEngineTests.swift @ 12624739
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.rules.reversi.ReversiBits
import com.yehsung.aingcheck.core.rules.reversi.ReversiCorpusFile
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.rules.reversi.sides
import com.yehsung.aingcheck.core.rules.reversi.str
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiResult
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeMark
import kotlin.time.TimeSource
import kotlin.time.measureTime

/** Swift `ReversiAIEndgameFixture` — 고정 종반 국면(두는 쪽 · 판 · 수마다 판 끝까지 읽은 최종 WOF 점수 차). 값은 맥 Swift 전수 탐색과 파이썬 참조 구현이 둘 다 낸 것. */
internal class ReversiAIEndgameFixture(val label: String, val color: ReversiColor, val board: String, val values: Map<Int, Int>) {
    val best: Int get() = values.values.max()
    val bestMoves: List<Int> get() = values.filter { it.value == best }.keys.sorted()

    override fun toString(): String = label
}

internal val reversiAIEndgameFixtures: List<ReversiAIEndgameFixture> = listOf(
    ReversiAIEndgameFixture(
        "흑 빈칸8 동점 둘", ReversiColor.black,
        "wwwwwbw.wbbbbb..wbbbwb.bwbwwwwwwwwwwwbwbwwwwww.b.wwbwwbb..wwwwwb",
        mapOf(7 to -6, 48 to -8, 56 to -8, 57 to -6),
    ),
    ReversiAIEndgameFixture(
        "흑 빈칸8 동점 둘(진 판)", ReversiColor.black,
        "..bwwwwbbbbbwwwwbbbwwwwwbbbbwwbbbwbbbbbbbwwwwwbbbwww..wbww..w..w",
        mapOf(52 to -28, 53 to -26, 58 to -20, 59 to -26, 61 to -22, 62 to -20),
    ),
    ReversiAIEndgameFixture(
        "흑 빈칸8 동점 둘(이긴 판)", ReversiColor.black,
        "wwwwwww...wwwwwwwwwbwww..wwwwww.wwwwwbwbwwwwwbwbbbbbb.wwwwwwwww.",
        mapOf(7 to 8, 9 to 0, 23 to 8, 24 to 16, 31 to 12, 53 to 14, 63 to 16),
    ),
    ReversiAIEndgameFixture(
        "흑 빈칸10 동점 둘", ReversiColor.black,
        "wwb.bwwwwwbwbwwwwwbwbbwbwwbwbbb.wbbwbb..bbb.wb..bbwbbw..bbbwwww.",
        mapOf(31 to -6, 43 to -6, 54 to -22, 63 to -8),
    ),
    ReversiAIEndgameFixture(
        "흑 빈칸10 동점 셋", ReversiColor.black,
        "b.b.wwbbbb..wwbbb.wwwwbbbwwwwbwbbwwbww.wbww.bbw.bwwbbb.ww.bwwwww",
        mapOf(3 to 8, 10 to -2, 11 to 0, 17 to 6, 38 to 8, 43 to 8, 47 to 6),
    ),
    ReversiAIEndgameFixture(
        "백 빈칸9 동점 넷", ReversiColor.white,
        "wwb.bwwwwwbwbbwwwwbwbbbbwwbwbbbbwbbwbb..bbb.wb..bbwbbw..bbbwwww.",
        mapOf(3 to 6, 38 to 6, 39 to 6, 43 to 6, 46 to 4, 54 to 4),
    ),
    ReversiAIEndgameFixture(
        "백 빈칸9 하나뿐(+8, 다음 +6)", ReversiColor.white,
        "wwwwwbw.wbbbbb..wbbbwb.bwbwwbbb.wwwwwbbbwwwwwb.b.wwbbwbb..wwwwwb",
        mapOf(14 to 8, 22 to -12, 31 to 6, 46 to 4),
    ),
    ReversiAIEndgameFixture(
        "백 빈칸9 하나뿐(+16, 다음 +14 둘)", ReversiColor.white,
        "...w..bwbw.wbbbwwwwbbbw.wwbwbwbbwwwbwbwww.bwbbwwwwwwbww.wwwwwwww",
        mapOf(0 to 14, 4 to 8, 5 to 4, 10 to 2, 23 to 16, 41 to 14),
    ),
)

/** 마감·취소 시험 국면(빈칸 14, 흑 차례). 맥 실측으로 무작위 대국 30국면 가운데 완전 탐색이 가장 무거운 자리다(556만 노드). */
internal const val reversiAIHeavyBoard = "wb..w..bbbbwwwww..wbbbb..wbbbbb.wbwwbbbbb.wbbwb..wbbbbbb.b.wbwww"

/**
 * 아잉 뒤집기 AI 엔진 — **고르는 수**와 **돌아오는 시간**을 못 박는다(맥 `ReversiAIEngineTests` 의 Kotlin 판).
 * "엔진이 수를 돌려준다"는 아무것도 재지 않는다. 여기서 재는 건 "이 국면의 최선 값은 이 값이고 · 최선과 똑같은 수는 이 집합이며 ·
 * 이 시간 안에 돌아온다"다. 종반 정답은 [bruteValues](규칙 공개 함수만 쓰는 전수 탐색)와 박아 둔 값(맥·파이썬 둘이 낸 값)이다.
 * 값을 재는 시험은 `maxDepth` 로 끊고 시간 예산은 넉넉히 둔다. 마감·취소는 **세는 시계**(읽을 때마다 1ms 가는 가짜 시계 · 몇 번째에 열리는
 * 취소 문)로 결정적으로 재고, 벽시계 확인은 넉넉한 상한 하나만 둔다(병렬 게이트에서 흔들리지 않게 — 맥은 Debug 벽시계 0.3초).
 * 느린 것(1.5초 상한 실측 · 승률 200판 둘 · 빈칸 9~10 전수 대조 · 박아 둔 값 재확인 · 동점 덮기 전부)은 `REVERSI_AI_SLOW=1` 에서만.
 */
class ReversiAIEngineTest {
    private fun board(text: String): ReversiBoard = ReversiBoard.fromString(text) ?: fail("판 문자열을 못 읽었다: $text")

    /** 깊이로 못 박은 한도. 시간은 넉넉히 둬서 **깊이가 먼저** 끊는다. */
    private fun limits(depth: Int, seed: ULong = 0x5EEDuL, budget: Duration = 120.seconds) = ReversiAISearchLimits(budget, depth, seed)

    // MARK: 언제나 합법 수 · 둘 곳 없으면 null

    // 없으면: 엔진이 비트 → 칸 번호를 잘못 옮기거나(전치·뒤집기) 상대 쪽 합법 수를 고르는 결함이 초록으로 지나간다.
    @Test
    fun alwaysLegal() {
        var checked = 0
        var seed = 0xA1_0000uL
        for (empties in 56 downTo 4 step 4) {
            var found = 0
            while (found < 3) {
                seed += 1uL
                val (board, color) = randomPosition(empties, seed) ?: continue
                found += 1
                val legal = ReversiRules.legalMoves(board, color)
                val decision = assertNotNull(ReversiAI.decide(board, color, limits(2, seed)))
                assertTrue(decision.move in legal, "빈칸 $empties $color: ${decision.move} ∉ $legal / ${board.string}")
                assertTrue(legal.containsAll(decision.tiedMoves), "동점 후보 ${decision.tiedMoves} ⊄ $legal")
                assertTrue(decision.move in decision.tiedMoves)
                // 공개 입구도 같은 수를 낸다(같은 씨앗).
                assertEquals(decision.move, ReversiAI.bestMove(board, color, limits(2, seed)))
                checked += 1
            }
        }
        assertEquals(42, checked)
    }

    // 없으면: 둘 곳이 없는 차례에 아무 칸(상대의 합법 수 등)을 내서 스토어가 불법 수를 보내는 결함이 지나간다.
    @Test
    fun noMoveMeansNull() {
        val corpus = ReversiCorpusFile.load()
        val passBoard = ReversiCorpusFile.board(ReversiCorpusFile.hand("E02", corpus).str("board"), "E02")
        assertNull(ReversiAI.bestMove(passBoard, ReversiColor.black, limits(4)))
        // 기준선: 같은 판 백은 c1(2) 하나뿐이라 그 수다.
        assertEquals(2, ReversiAI.bestMove(passBoard, ReversiColor.white, limits(4)))
        val overBoard = ReversiCorpusFile.board(ReversiCorpusFile.hand("E05", corpus).str("board"), "E05")
        assertNull(ReversiAI.bestMove(overBoard, ReversiColor.black, limits(4)))
        assertNull(ReversiAI.bestMove(overBoard, ReversiColor.white, limits(4)))
        assertNull(ReversiAI.bestMove(board("b".repeat(64)), ReversiColor.white))
    }

    // MARK: 최선 동점끼리만 무작위

    // 없으면: 동점 판정이 "모든 수"나 "최선 근처"를 고르는 결함, 같은 씨앗에 다른 수가 나오는 결함이 지나간다.
    @Test
    fun symmetricOpeningTies() {
        val picked = HashSet<Int>()
        for (seed in 1uL..32uL) {
            val decision = assertNotNull(ReversiAI.decide(ReversiBoard.start, ReversiColor.black, limits(3, seed)))
            assertEquals(listOf(19, 26, 37, 44), decision.tiedMoves, "씨앗 $seed")
            picked.add(decision.move)
            assertEquals(decision.move, ReversiAI.bestMove(ReversiBoard.start, ReversiColor.black, limits(3, seed)), "씨앗 $seed: 같은 씨앗인데 다른 수")
        }
        assertEquals(setOf(19, 26, 37, 44), picked, "씨앗 32개가 고른 수 ${picked.sorted()}")
    }

    // 없으면: ① 최선보다 2 낮은 수를 동점에 넣는 결함 ② 뿌리를 좁은 창으로 보고 경계값을 동점으로 세는 결함 ③ 최선이 하나뿐인데 다른 수를 내는 결함.
    @Test
    fun endgameFixtureTies() {
        for (fixture in reversiAIEndgameFixtures) {
            val board = board(fixture.board)
            assertEquals(fixture.values.keys.sorted(), ReversiRules.legalMoves(board, fixture.color), "${fixture.label}: 합법 수가 박아 둔 값의 칸과 다르다")
            for (seed in 1uL..2uL) {
                val decision = assertNotNull(ReversiAI.decide(board, fixture.color, limits(60, seed)))
                assertTrue(decision.exact, "${fixture.label}: 판 끝까지 못 읽었다(깊이 ${decision.depth})")
                assertEquals(fixture.best, decision.score, "${fixture.label}: 값")
                assertEquals(fixture.bestMoves, decision.tiedMoves, "${fixture.label}: 동점")
                assertTrue(decision.move in fixture.bestMoves, "${fixture.label}: 고른 수 ${decision.move} ∉ 최선 ${fixture.bestMoves}")
            }
        }
    }

    // 없으면: 동점 후보는 맞게 세고도 늘 첫 후보만 내는 결함(앱에서 매판 같은 기보)이 지나간다.
    @Test
    fun endgameTieCoverage() = checkTieCoverage(reversiAIEndgameFixtures.filter { f -> f.board.count { it == '.' } == 8 }, seeds = 8uL, expectFixtures = 3)

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_AI_SLOW", matches = "1")
    fun endgameTieCoverageAll() = checkTieCoverage(reversiAIEndgameFixtures, seeds = 24uL, expectFixtures = 8)

    private fun checkTieCoverage(fixtures: List<ReversiAIEndgameFixture>, seeds: ULong, expectFixtures: Int) {
        assertEquals(expectFixtures, fixtures.size)
        for (fixture in fixtures) {
            val board = board(fixture.board)
            val picked = (1uL..seeds).map { seed -> assertNotNull(ReversiAI.bestMove(board, fixture.color, limits(60, seed))) }.toSet()
            assertEquals(fixture.bestMoves.toSet(), picked, "${fixture.label}: 고른 수 ${picked.sorted()} ≠ 최선 ${fixture.bestMoves}")
        }
    }

    // 없으면: 규칙이 바뀌었는데 박아 둔 값이 옛 규칙의 정답으로 남아 위 시험이 엉뚱한 정답지로 재는 일이 지나간다.
    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_AI_SLOW", matches = "1")
    fun endgameFixtureValuesMatchRules() {
        for (fixture in reversiAIEndgameFixtures) {
            assertEquals(fixture.values, bruteValues(board(fixture.board), fixture.color), "${fixture.label}: 박아 둔 값과 전수 탐색이 다르다")
        }
    }

    // MARK: 종반 완전 탐색 = 전수 탐색

    // 없으면: 완전 탐색의 패스 처리·끝 점수(빈칸을 이긴 쪽에)·마지막 빈칸 지름길 결함이 지나간다.
    @Test
    fun endgameMatchesBruteForceSmall() = compareWithBruteForce(listOf(6, 7, 8), perEmpties = 2, start = 0xE0_0000uL)

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_AI_SLOW", matches = "1")
    fun endgameMatchesBruteForceLarge() = compareWithBruteForce(listOf(9, 10), perEmpties = 10, start = 0xE1_0000uL)

    private fun compareWithBruteForce(list: List<Int>, perEmpties: Int, start: ULong) {
        var seed = start
        val colors = HashSet<ReversiColor>()
        var compared = 0
        for (empties in list) {
            var found = 0
            while (found < perEmpties) {
                seed += 1uL
                val (board, color) = randomPosition(empties, seed) ?: continue
                if (ReversiRules.legalMoves(board, color).size < 2) continue // 하나뿐이면 탐색하지 않는다
                found += 1
                val values = bruteValues(board, color)
                val best = values.values.max()
                val bestMoves = values.filter { it.value == best }.keys.sorted()
                val decision = assertNotNull(ReversiAI.decide(board, color, limits(60, seed)))
                assertTrue(decision.exact, "${board.string} $color: 판 끝까지 못 읽었다")
                assertEquals(empties, decision.depth)
                assertEquals(best, decision.score, "${board.string} $color: 값 / $values")
                assertEquals(bestMoves, decision.tiedMoves, "${board.string} $color: 동점 / $values")
                colors.add(color)
                compared += 1
            }
        }
        assertEquals(list.size * perEmpties, compared)
        assertEquals(2, colors.size, "흑·백이 섞이지 않았다: $colors")
    }

    // 없으면: 깊이 상한이 빈칸보다 작은데도 완전 탐색으로 뛰어 시험의 결정적 한도(`maxDepth`)를 넘는 결함이 지나간다.
    @Test
    fun maxDepthBoundsSolve() {
        val fixture = reversiAIEndgameFixtures[0]
        val board = board(fixture.board)
        val shallow = assertNotNull(ReversiAI.decide(board, fixture.color, limits(6)))
        assertFalse(shallow.exact)
        assertEquals(6, shallow.depth)
        val full = assertNotNull(ReversiAI.decide(board, fixture.color, limits(8)))
        assertTrue(full.exact)
        assertEquals(8, full.depth)
    }

    // 없으면: 끝 점수에서 남은 빈칸을 이긴 쪽에 안 더하는 결함(V-11)이 지나간다 — 여기는 전멸로 빈칸 59 를 남기고 끝난다.
    @Test
    fun earlyEndScoresEmptiesToWinner() {
        // 흑 a1, 백 b1·a2. 흑 c1·a3 어느 쪽을 먼저 둬도 백은 둘 곳이 없고(자동 패스) 흑이 나머지로 백을 전멸시킨다 → 64:0.
        val cells = CharArray(64) { '.' }
        cells[0] = 'b'
        cells[1] = 'w'
        cells[8] = 'w'
        val board = board(cells.concatToString())
        assertEquals(mapOf(2 to 64, 16 to 64), bruteValues(board, ReversiColor.black)) // 기준선(규칙만으로 센 값)
        val decision = assertNotNull(ReversiAI.decide(board, ReversiColor.black, limits(60)))
        assertTrue(decision.exact)
        assertEquals(64, decision.score)
        assertEquals(listOf(2, 16), decision.tiedMoves)
        // 끝난 코퍼스 판마다 엔진 점수 차 = 규칙 WOF 점수 차, 두 색 시점 모두.
        var ended = 0
        for (hand in ReversiCorpusFile.hand()) {
            val handBoard = ReversiBoard.fromString(hand.str("board") ?: continue) ?: continue
            val score = ReversiRules.score(handBoard) ?: continue
            val (black, white) = handBoard.sides(ReversiColor.black)
            assertEquals(score.black - score.white, ReversiAIEngine.finalDiff(black, white), hand.str("id"))
            assertEquals(score.white - score.black, ReversiAIEngine.finalDiff(white, black), hand.str("id"))
            if (handBoard.counts.empty > 0) ended += 1
        }
        assertTrue(ended >= 1, "빈칸이 남은 끝난 판이 코퍼스에 없다 — 이 줄이 아무것도 안 잰다")
    }

    // MARK: 마감 · 취소

    /** 읽을 때마다 [step] 씩 가는 가짜 단조 시계 — 마감이 **탐색 안에서** 몇 번째 읽기에 걸리는지 결정적으로 잰다. */
    private class SteppingTimeSource(private val step: Duration) : TimeSource {
        var reads = 0
            private set

        override fun markNow(): TimeMark = object : TimeMark {
            override fun elapsedNow(): Duration {
                reads += 1
                return step * reads
            }
        }
    }

    // 없으면(SPEC v1.1 CCT I10): 마감을 깊이 사이에서만 보는 엔진이 통과한다 — 그 엔진은 이 국면에서 완전 탐색 한 반복이 끝날 때까지 돌아오지 않는다.
    // 가짜 시계: 읽을 때마다 1ms. 예산 200ms → 마감 196ms(예산 − min(예산/50, 20ms)) → 시계를 197번째 읽을 때 끊긴다. 탐색 안의 시계는 256 노드마다 읽히므로
    // 노드는 약 5만 안쪽이어야 한다(이 국면의 완전 탐색은 556만 노드 — 깊이 사이에서만 보면 수백만까지 간다).
    @Test
    fun deadlineInsideSearch() {
        val board = board(reversiAIHeavyBoard)
        assertEquals(14, board.counts.empty)
        val clock = SteppingTimeSource(1.milliseconds)
        val found = assertNotNull(ReversiAI.decide(board, ReversiColor.black, ReversiAISearchLimits(200.milliseconds, 60, 3uL), timeSource = clock))
        assertTrue(found.aborted, "예산 안에 다 읽었다 — 마감 시험으로 쓸 만큼 무겁지 않다")
        assertFalse(found.exact)
        assertTrue(found.move in ReversiRules.legalMoves(board, ReversiColor.black))
        assertTrue(found.nodes <= 200 * 256, "마감 뒤에도 ${found.nodes} 노드를 더 돌았다(시계 ${clock.reads}번)")
        // 벽시계 확인(넉넉한 상한 — 병렬 게이트에서도 흔들리지 않게): 진짜 단조 시계로 예산 0.2초면 1초 안에 돌아온다.
        var real: ReversiAIDecision? = null
        val spent = measureTime { real = ReversiAI.decide(board, ReversiColor.black, ReversiAISearchLimits(200.milliseconds, 60, 3uL)) }
        assertTrue(spent <= 1.seconds, "벽시계 $spent")
        assertTrue(assertNotNull(real).move in ReversiRules.legalMoves(board, ReversiColor.black))
    }

    // 없으면: 탐색 안의 틱이 시계만 보고 취소 문을 안 보는 결함이 지나간다(창을 닫아도 1.5초 동안 계속 돈다).
    // 취소 문은 40번째 물음에 열린다. 시계(예산 60초)는 안 걸리므로 취소만으로 끊겨야 하고, 물음은 256 노드마다라 노드는 41 × 256 안쪽이다.
    @Test
    fun cancelInsideSearch() {
        val board = board(reversiAIHeavyBoard)
        var asked = 0
        val found = assertNotNull(
            ReversiAI.decide(board, ReversiColor.black, ReversiAISearchLimits(60.seconds, 60, 3uL), isCancelled = { asked += 1; asked >= 40 }),
        )
        assertTrue(found.aborted)
        assertTrue(found.move in ReversiRules.legalMoves(board, ReversiColor.black))
        assertTrue(found.nodes <= 41 * 256, "취소 뒤에도 ${found.nodes} 노드를 더 돌았다(물음 $asked 번)")
    }

    // 없으면: 처음부터 취소된 호출이 null 을 내거나(스토어가 둘 곳 없음으로 오해) 불법 수를 내는 결함이 지나간다.
    @Test
    fun cancelledFromStart() {
        val board = board(reversiAIHeavyBoard)
        var move: Int? = null
        val spent = measureTime { move = ReversiAI.bestMove(board, ReversiColor.black, limits(60, budget = 60.seconds), isCancelled = { true }) }
        assertTrue(assertNotNull(move) in ReversiRules.legalMoves(board, ReversiColor.black))
        assertTrue(spent <= 1.seconds, "벽시계 $spent")
    }

    // MARK: 평가 고정

    // 없으면: 가중치 숫자를 바꾸거나(엔진 세기가 조용히 변한다) 평가 항 하나를 빼는 결함이 지나간다. 값은 손으로 셌다(맥 시험과 같은 두 국면).
    @Test
    fun evaluationPinned() {
        assertEquals(
            listOf(
                100, -10, 20, 8, 8, 20, -10, 100,
                -10, -15, -4, -3, -3, -4, -15, -10,
                20, -4, 6, 3, 3, 6, -4, 20,
                8, -3, 3, 0, 0, 3, -3, 8,
                8, -3, 3, 0, 0, 3, -3, 8,
                20, -4, 6, 3, 3, 6, -4, 20,
                -10, -15, -4, -3, -3, -4, -15, -10,
                100, -10, 20, 8, 8, 20, -10, 100,
            ),
            ReversiAIEval.squareWeights,
        )
        assertEquals(
            listOf(10, 40, 15, 4, 12),
            listOf(ReversiAIEval.mobility, ReversiAIEval.xPenalty, ReversiAIEval.cPenalty, ReversiAIEval.frontier, ReversiAIEval.stable),
        )
        // ① 내 돌 a1·b1, 상대 c1 → 가중치 70 · 이동성 10 · X/C 0 · 경계 −4 · 안정 24 → 100.
        val own1 = (1uL shl 0) or (1uL shl 1)
        val opp1 = 1uL shl 2
        assertEquals(100, ReversiAIEngine.evaluate(own1, opp1, ReversiBits.moves(own1, opp1)))
        // ② 내 돌 b2(X), 상대 c3 → 가중치 −21 · 이동성 0 · a1 이 빈 채 X 에 내 돌 −40 · 경계 0 · 안정 0 → −61.
        val own2 = 1uL shl 9
        val opp2 = 1uL shl 18
        assertEquals(-61, ReversiAIEngine.evaluate(own2, opp2, ReversiBits.moves(own2, opp2)))
        // 기준선: ② 에서 a1 을 내 돌로 채우면 X 벌점이 사라진다(값이 갈린다).
        val own3 = own2 or 1uL
        assertTrue(ReversiAIEngine.evaluate(own3, opp2, ReversiBits.moves(own3, opp2)) != -61)
    }

    // 없으면: 가중치 표의 한 칸 오타(대칭 깨짐)가 지나간다 — 그러면 시작 판 같은 대칭 국면의 동점이 동점이 아니게 된다.
    @Test
    fun evaluationSymmetric() {
        var seed = 0xC0_0000uL
        var checked = 0
        while (checked < 24) {
            seed += 1uL
            val (board, color) = randomPosition(20 + (seed % 30uL).toInt(), seed) ?: continue
            val (own, opp) = board.sides(color)
            val base = ReversiAIEngine.evaluate(own, opp, ReversiBits.moves(own, opp))
            for (kind in 1 until 8) {
                val tOwn = transform(own, kind)
                val tOpp = transform(opp, kind)
                assertEquals(base, ReversiAIEngine.evaluate(tOwn, tOpp, ReversiBits.moves(tOwn, tOpp)), "대칭 $kind / ${board.string}")
            }
            checked += 1
        }
    }

    // 없으면: 꽉 찬 변 규칙이나 모서리에서 이어진 줄 규칙이 빠진 결함이 지나간다.
    @Test
    fun stableEdges() {
        val own = 0b0111uL
        val opp = 0b1000uL
        assertEquals(3, ReversiAIEngine.stableEdgeDiscs(own, opp))
        assertEquals(0, ReversiAIEngine.stableEdgeDiscs(opp, own))
        val fullOwn = (1uL shl 1) or (1uL shl 3) or (1uL shl 5) or (1uL shl 7)
        val fullOpp = (1uL shl 0) or (1uL shl 2) or (1uL shl 4) or (1uL shl 6)
        assertEquals(4, ReversiAIEngine.stableEdgeDiscs(fullOwn, fullOpp))
        assertEquals(4, ReversiAIEngine.stableEdgeDiscs(fullOpp, fullOwn))
        assertEquals(0, ReversiAIEngine.stableEdgeDiscs(0b0111_1110uL, 0uL))
    }

    // 없으면: 앱 기본값(1.5초 · 깊이 60 · 시스템 무작위)이 바뀌어도 시험이 모른다(서명·기본값은 스토어 갈래와의 계약).
    @Test
    fun defaultsArePinned() {
        val defaults = ReversiAISearchLimits()
        assertEquals(1500L, defaults.timeBudget.inWholeMilliseconds)
        assertEquals(60, defaults.maxDepth)
        assertNull(defaults.tieBreakSeed)
        assertEquals(defaults, ReversiAISearchLimits.standard)
        assertEquals(16, ReversiAIEngine.endgameEmpties)
        assertEquals(4, ReversiAIEngine.endgameWarmupDepth)
    }

    // MARK: 느린 것(REVERSI_AI_SLOW=1)

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_AI_SLOW", matches = "1")
    fun respectsOneAndAHalfSeconds() {
        val positions = mutableListOf(Triple("시작 판", ReversiBoard.start, ReversiColor.black))
        for ((empties, start) in listOf(44 to 0x51uL, 30 to 0x52uL, 20 to 0x53uL, 16 to 0x54uL)) {
            var s = start
            while (true) {
                s += 1uL
                val found = randomPosition(empties, s) ?: continue
                positions.add(Triple("빈칸 $empties", found.first, found.second))
                break
            }
        }
        positions.add(Triple("빈칸 14 무거운 자리", board(reversiAIHeavyBoard), ReversiColor.black))
        for ((label, board, color) in positions) {
            var decision: ReversiAIDecision? = null
            val spent = measureTime { decision = ReversiAI.decide(board, color, ReversiAISearchLimits(tieBreakSeed = 7uL)) }
            val found = assertNotNull(decision)
            assertTrue(spent <= 1500.milliseconds, "$label: 벽시계 $spent")
            assertTrue(found.depth >= 2, "$label: 깊이 ${found.depth}")
            println("[1.5초] $label → ${found.move} 깊이 ${found.depth} exact ${found.exact} 노드 ${found.nodes} $spent 끊김 ${found.aborted}")
        }
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_AI_SLOW", matches = "1")
    fun beatsRandomOpponent() {
        val rng = SplitMix64(0x00AB_CDEFuL)
        var wins = 0
        for (game in 0 until 200) {
            val engine = if (game % 2 == 0) ReversiColor.black else ReversiColor.white
            val (result, _) = playGame(engine, limits(MATCH_DEPTH, game.toULong() + 1uL)) { board, color ->
                val moves = ReversiRules.legalMoves(board, color)
                moves[(rng.next() % moves.size.toULong()).toInt()]
            }
            if (result.winner == engine) wins += 1
        }
        println("[무작위 200판] 깊이 $MATCH_DEPTH: 승 $wins")
        assertTrue(wins >= 190, "승 $wins/200")
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_AI_SLOW", matches = "1")
    fun beatsGreedyOpponent() {
        val rng = SplitMix64(0x0067_4EEDuL)
        var wins = 0
        for (game in 0 until 200) {
            val engine = if (game % 2 == 0) ReversiColor.black else ReversiColor.white
            val (result, _) = playGame(engine, limits(MATCH_DEPTH, game.toULong() + 1uL)) { board, color ->
                val moves = ReversiRules.legalMoves(board, color)
                val counts = moves.map { ReversiRules.flips(board, color, it).size }
                val most = counts.max()
                val greedy = moves.filterIndexed { i, _ -> counts[i] == most }
                greedy[(rng.next() % greedy.size.toULong()).toInt()]
            }
            if (result.winner == engine) wins += 1
        }
        println("[탐욕 200판] 깊이 $MATCH_DEPTH: 승 $wins")
        assertTrue(wins >= 160, "승 $wins/200")
    }

    companion object {
        /** 승률 시험의 엔진 한도(깊이로 묶어 결정적). 앱(1.5초)보다 약하다. */
        private const val MATCH_DEPTH = 4

        /** 시작 판에서 씨앗 무작위 대국으로 빈칸 `empties` 국면을 만든다. 그 자리의 두는 쪽이 둘 곳이 없거나 판이 먼저 끝나면 null. */
        internal fun randomPosition(empties: Int, seed: ULong): Pair<ReversiBoard, ReversiColor>? {
            val rng = SplitMix64(seed)
            var board = ReversiBoard.start
            var turn = ReversiColor.black
            while (board.counts.empty > empties) {
                val moves = ReversiRules.legalMoves(board, turn)
                if (moves.isEmpty()) return null // play 의 next 가 패스를 접어 주므로 여기 오면 끝난 판이다
                val idx = moves[(rng.next() % moves.size.toULong()).toInt()]
                val outcome = ReversiRules.play(board, turn, idx).outcomeOrNull ?: return null
                val next = outcome.next ?: return null
                board = outcome.board
                turn = next
            }
            if (!ReversiRules.hasLegalMove(board, turn)) return null
            return board to turn
        }

        private fun scoreDiff(score: ReversiScore, color: ReversiColor): Int =
            if (color == ReversiColor.black) score.black - score.white else score.white - score.black

        /** 전수 탐색 — `ReversiRules` 공개 함수만 쓴다(엔진 코드를 한 줄도 부르지 않는다). 두는 쪽 시점 최종 WOF 점수 차. */
        private fun bruteValue(board: ReversiBoard, color: ReversiColor): Int {
            val moves = ReversiRules.legalMoves(board, color)
            if (moves.isEmpty()) {
                if (!ReversiRules.hasLegalMove(board, color.opponent)) return scoreDiff(ReversiRules.score(board)!!, color)
                return -bruteValue(board, color.opponent)
            }
            return moves.maxOf { bruteChild(board, color, it) }
        }

        private fun bruteChild(board: ReversiBoard, color: ReversiColor, idx: Int): Int {
            val outcome = ReversiRules.play(board, color, idx).outcomeOrNull ?: return Int.MIN_VALUE
            if (outcome.isOver) return scoreDiff(outcome.score!!, color)
            if (outcome.next == color) return bruteValue(outcome.board, color) // 상대 자동 패스 — 내가 또 둔다
            return -bruteValue(outcome.board, color.opponent)
        }

        /** 뿌리의 수마다 전수 탐색 값. */
        internal fun bruteValues(board: ReversiBoard, color: ReversiColor): Map<Int, Int> =
            ReversiRules.legalMoves(board, color).associateWith { bruteChild(board, color, it) }

        /** 판의 8대칭(가로·세로 뒤집기 · 전치)으로 칸을 옮긴다. `kind` 0…7. */
        private fun transform(idx: Int, kind: Int): Int {
            var row = idx / 8
            var col = idx % 8
            if (kind and 1 != 0) col = 7 - col
            if (kind and 2 != 0) row = 7 - row
            if (kind and 4 != 0) row = col.also { col = row }
            return row * 8 + col
        }

        private fun transform(bits: ULong, kind: Int): ULong =
            ReversiBits.indices(bits).fold(0uL) { acc, idx -> acc or (1uL shl transform(idx, kind)) }

        /** 대국 한 판. 엔진의 수는 매번 규칙의 합법 수 안인지 본다. 결과(흑 기준)와 엔진 시점 최종 점수 차를 낸다. */
        private fun playGame(engine: ReversiColor, limits: ReversiAISearchLimits, opponent: (ReversiBoard, ReversiColor) -> Int): Pair<ReversiResult, Int> {
            var board = ReversiBoard.start
            var turn: ReversiColor? = ReversiColor.black
            var plies = 0
            while (turn != null) {
                val color: ReversiColor = turn
                val legal = ReversiRules.legalMoves(board, color)
                val idx = if (color == engine) {
                    val move = assertNotNull(ReversiAI.bestMove(board, color, limits))
                    assertTrue(move in legal, "${plies}수: 엔진이 불법 수 $move / ${board.string}")
                    move
                } else {
                    opponent(board, color)
                }
                val outcome = ReversiRules.play(board, color, idx).outcomeOrNull ?: fail("${plies}수: 둘 수 없는 칸 $idx")
                board = outcome.board
                turn = outcome.next
                plies += 1
            }
            val score = assertNotNull(ReversiRules.score(board))
            return score.result to scoreDiff(score, engine)
        }
    }
}
