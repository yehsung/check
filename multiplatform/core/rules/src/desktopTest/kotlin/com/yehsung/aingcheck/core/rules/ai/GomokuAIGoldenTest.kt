// 원본: Tests/checkTests/V0332GomokuAIEngineTests.swift · Tests/checkTests/GoldenExport/games-board/GoldenExportGamesBoardAI.swift(renju/ai-*) @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuRenjuProbe
import com.yehsung.aingcheck.core.rules.renju.GomokuRules
import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.core.rules.renju.optString
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFnv1a64
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlin.time.Duration.Companion.seconds

/**
 * 오목 AI. C§5.1 은 집합 동등(renju/ai-puzzles)을 요구하고, 이 이식은 Swift randomElement 알고리즘까지 옮겨 **비트**로도 대조한다
 * (renju/ai-trace: 표 지문 · 국면별 고른 수 · 노드 수 · 마친 깊이). 시간 예산은 600초라 깊이가 먼저 끊는다(벽시계 무관).
 * 데스크톱 JVM 에서만 돈다 — 엔진 대 엔진 수순이 Android 호스트(Robolectric)에서 두 번 돌 값어치가 없다(같은 JVM 바이트코드).
 */
class GomokuAIGoldenTest {
    private fun board(black: List<String>, white: List<String>): GomokuBoard {
        val board = GomokuBoard()
        for (n in black) board[GomokuPoint.fromNotation(n)!!] = GomokuColor.black
        for (n in white) board[GomokuPoint.fromNotation(n)!!] = GomokuColor.white
        return board
    }

    private fun playable(judgement: GomokuJudgement) = judgement == GomokuJudgement.Legal || judgement == GomokuJudgement.Win

    /** 엔진 대 엔진으로 `plies` 수. 모든 수가 합법이어야 하고, 5목을 만든 색을 돌려준다. */
    private fun playOut(start: GomokuBoard, toMove: GomokuColor, plies: Int, limits: GomokuAISearchLimits): Pair<GomokuColor?, List<String>> {
        val board = start.copy()
        var color = toMove
        val moves = ArrayList<String>()
        repeat(plies) {
            val move = GomokuAI.bestMove(board, color, limits)
            if (move == null) {
                moves.add("pass")
                color = color.opponent
                return@repeat
            }
            val verdict = GomokuRules.judge(board, move, color)
            assertTrue(playable(verdict), "$color 가 둘 수 없는 ${move.notation}($verdict)에 뒀다 — 수순 $moves")
            board[move] = color
            moves.add(move.notation)
            if (verdict == GomokuJudgement.Win) return color to moves
            color = color.opponent
        }
        return null to moves
    }

    @Test
    fun puzzlesAreSolvedWithinTheAnswerSets() {
        val golden = Golden.load("renju/ai-puzzles")
        var sameAsSwift = 0
        for (case in golden.cases) {
            val id = case.string("id")
            val start = board(case.array("black").strings(), case.array("white").strings())
            val toMove = GomokuColor.fromRawValue(case.string("toMove"))!!
            val limits = GomokuAISearchLimits(600.seconds, case.int("maxDepth"), case.hex64("seed"))
            val move = GomokuAI.bestMove(start, toMove, limits) ?: fail(golden.failure(id, "둘 곳이 없다고 했다"))
            assertTrue(playable(GomokuRules.judge(start, move, toMove)), golden.failure(id, "둘 수 없는 ${move.notation}"))
            if (case["expect"] !is JsonNull) assertTrue(move.notation in case.array("expect").strings(), golden.failure(id, "${move.notation} ∉ expect"))
            if (case["reject"] !is JsonNull) assertFalse(move.notation in case.array("reject").strings(), golden.failure(id, "${move.notation} ∈ reject"))
            case.optInt("winWithin")?.let { n ->
                assertEquals(toMove, playOut(start, toMove, 2 * n - 1, limits).first, golden.failure(id, "${n}수 안에 못 이겼다"))
            }
            case.optInt("holdFor")?.let { n ->
                val after = start.copy().also { it[move] = toMove }
                assertTrue(playOut(after, toMove.opponent, 2 * n - 1, limits).first != toMove.opponent, golden.failure(id, "${move.notation} 뒤 상대가 이겼다"))
                case.optString("loseAfter")?.let { bad ->
                    val wrong = start.copy().also { it[GomokuPoint.fromNotation(bad)!!] = toMove }
                    assertEquals(toMove.opponent, playOut(wrong, toMove.opponent, 2 * n - 1, limits).first, golden.failure(id, "대조군 $bad 뒤에도 상대가 못 이겼다"))
                }
            }
            if (move.notation == case.string("swiftMove")) sameAsSwift++
        }
        assertEquals(16, golden.cases.size)
        // 집합 동등이 계약이지만, 알고리즘을 그대로 옮겼으므로 Swift 와 같은 수를 골라야 한다(trace 가 그 단언을 맡는다 — 여기선 보고만).
        println("AINGCHECK-GOMOKU-AI-PUZZLES| same-as-swift=$sameAsSwift/${golden.cases.size}")
    }

    @Test
    fun tracesMatchSwiftBitForBit() {
        val golden = Golden.load("renju/ai-trace")
        val budgets = HashSet<String>()
        var choices = 0
        var shortcuts = 0
        for (case in golden.cases) {
            val id = case.string("id")
            if (id == "tables") {
                fun fnv(values: IntArray): String = GoldenFnv1a64().also { h -> values.forEach { h.add(it.toLong().toULong()) } }.value.let(Golden::hex64Text)
                assertEquals(case.string("blackShapes"), fnv(IntArray(GomokuAITables.keyCount) { GomokuAITables.blackShapes[it].toInt() }), "흑 줄 모양 표")
                assertEquals(case.string("whiteShapes"), fnv(IntArray(GomokuAITables.keyCount) { GomokuAITables.whiteShapes[it].toInt() }), "백 줄 모양 표")
                assertEquals(case.string("comboCategories"), fnv(IntArray(4096) { GomokuAITables.comboCategories[it].toInt() }), "조합 등급 표")
                val values = GoldenFnv1a64().also { h -> GomokuAITables.comboValues.forEach { h.add(it) } }
                assertEquals(case.string("comboValues"), Golden.hex64Text(values.value), "조합 점수 표")
                val zobrist = GoldenFnv1a64().also { h -> GomokuAITables.zobrist.forEach { h.add(it.toULong()) } }
                assertEquals(case.string("zobrist"), Golden.hex64Text(zobrist.value), "Zobrist")
                assertEquals(case.array("zobristHead").map { Golden.hex64(it.stringValue()) }, GomokuAITables.zobrist.take(4).map { it.toULong() })
                // 이름 붙은 탐색 상수(Swift static let). 이름 없는 VCF 예산은 budget-* 국면의 노드 수가 잰다.
                val engine = case["engine"] as? JsonObject ?: fail(golden.failure(id, "engine 칸이 없다"))
                val want = listOf("width", "cellCount", "win", "infinity", "maxPly", "ttBits", "centralityWeight", "keyCount").map { engine.int(it) }
                val got = listOf(GomokuAIEngine.width, GomokuAIEngine.cellCount, GomokuAIEngine.win, GomokuAIEngine.infinity, GomokuAIEngine.maxPly,
                    GomokuAIEngine.ttBits, GomokuAIEngine.centralityWeight, GomokuAITables.keyCount)
                assertEquals(want, got, golden.failure(id, "탐색 상수 [폭, 칸, 승, 무한, 최대 반수, TT 비트, 중앙 가중치, 키 수]"))
                continue
            }
            val start = GomokuBoard.fromServerString(case.string("board"))!!
            val color = GomokuColor.fromRawValue(case.string("toMove"))!!
            val depth = case.int("maxDepth")
            val seed = case.hex64("seed")
            if (id.startsWith("shortcut-")) {
                val move = GomokuAI.bestMove(start, color, GomokuAISearchLimits(600.seconds, depth, seed))
                assertEquals(case.optString("bestMove"), move?.notation, golden.failure(id, "bestMove 지름길"))
                shortcuts++
                continue
            }
            val engine = GomokuAIEngine(start, 600.seconds, { false })
            val raw = engine.chooseMove(if (color == GomokuColor.black) 1 else 2, depth, SeededSwiftRandom(seed))
            val point = raw?.let { GomokuAIEngine.coordinates(it) }?.let { GomokuPoint.at(it.first, it.second) }
            val side = if (color == GomokuColor.black) 1 else 2
            val eval0 = GomokuAIEngine(start, 600.seconds, { false }).negamax(0, -GomokuAIEngine.infinity, GomokuAIEngine.infinity, 0, side)
            val eval1 = GomokuAIEngine(start, 600.seconds, { false }).negamax(1, -GomokuAIEngine.infinity, GomokuAIEngine.infinity, 0, side)
            val want = listOf(case.optString("move"), case.int("nodes"), case.int("completedDepth"), case.int("eval0"), case.int("eval1"))
            val got = listOf(point?.notation, engine.nodes, engine.completedDepth, eval0, eval1)
            if (want != got) fail(golden.failure(id, "[수, 노드, 마친 깊이, 평가0, 평가1] Swift $want · Kotlin $got"))
            assertFalse(engine.aborted, "$id: 시간 예산에 끊겼다")
            assertEquals(point, GomokuAI.bestMove(start, color, GomokuAISearchLimits(600.seconds, depth, seed)), golden.failure(id, "bestMove = chooseMove"))
            choices++
            if (id.startsWith("budget-")) budgets.add(id)
        }
        assertTrue(choices > 60 && shortcuts == 6, "고른 수 $choices · 지름길 $shortcuts")
        // VCF 예산 국면 셋(루트 30,000 · 상대 20,000 · 방어 확인 4,000)이 빠지면 예산 숫자를 아무것도 안 잰다.
        assertEquals(setOf("budget-root", "budget-opponent", "budget-defense"), budgets, "VCF 예산 국면")
    }

    /** AI 가 금수를 묻는 판정기(GomokuRenjuProbe)는 GomokuRules.judge 와 같은 판정이어야 한다(V0332 renjuProbeAgreesWithRulesOnRandomPositions). */
    @Test
    fun renjuProbeAgreesWithRulesOnRandomPositions() {
        val rng = SplitMix64(0x0332_0001uL)
        var checked = 0
        var forbiddenSeen = 0
        repeat(16) {
            val board = GomokuBoard()
            var color = GomokuColor.black
            val stones = 20 + (rng.next() % 51uL).toInt()
            for (n in 0 until stones) {
                val candidates = (0 until 225).mapNotNull { GomokuPoint.at(it % 15, it / 15) }.filter { board[it] == null }
                val move = candidates[(rng.next() % candidates.size.toULong()).toInt()]
                val verdict = GomokuRules.judge(board, move, color)
                if (verdict == GomokuJudgement.Win) break
                if (!playable(verdict)) continue
                board[move] = color
                color = color.opponent
            }
            val probe = GomokuRenjuProbe(board)
            for (index in 0 until 225) {
                val point = GomokuPoint.at(index % 15, index / 15)!!
                val expected = if (board[point] == null) GomokuRules.judge(board, point, GomokuColor.black) else GomokuJudgement.Occupied
                assertEquals(expected, probe.blackJudgement(point.x, point.y), "${point.notation}")
                if (expected is GomokuJudgement.Forbidden) forbiddenSeen++
                checked++
            }
            // 제자리 고치기(setCell)도 복사본과 같은 판을 만든다.
            val empty = (0 until 225).mapNotNull { GomokuPoint.at(it % 15, it / 15) }.firstOrNull { board[it] == null } ?: return@repeat
            probe.setCell(empty.x, empty.y, GomokuColor.white)
            val fresh = GomokuRenjuProbe(board.copy().also { it[empty] = GomokuColor.white })
            for (index in 0 until 225) assertEquals(fresh.blackJudgement(index % 15, index / 15), probe.blackJudgement(index % 15, index / 15))
        }
        assertEquals(16 * 225, checked)
        assertTrue(forbiddenSeen > 0, "무작위 국면에 금수가 하나도 없었다 — 이 시험은 금수를 한 번도 대조하지 않았다")
    }

    /** 취소 문이 열리면 곧바로 합법 수를 들고 돌아온다(벽시계 상한은 느슨하게 — 기계가 바빠도 결과가 같아야 한다). */
    @Test
    fun cancellationReturnsALegalMove() {
        val golden = Golden.load("renju/ai-puzzles")
        val case = golden.cases.first { it.string("id") == "white-vcf" }
        val start = board(case.array("black").strings(), case.array("white").strings())
        val move = GomokuAI.bestMove(start, GomokuColor.white, GomokuAISearchLimits(30.seconds, 64, 1uL), isCancelled = { true })
        assertNotNull(move)
        assertTrue(playable(GomokuRules.judge(start, move, GomokuColor.white)))
        val full = GomokuBoard()
        for (i in 0 until 225) full[GomokuPoint.at(i % 15, i / 15)!!] = if ((i / 15 + i % 15) % 2 == 0) GomokuColor.black else GomokuColor.white
        assertEquals(null, GomokuAI.bestMove(full, GomokuColor.black))
        assertEquals("H8", GomokuAI.bestMove(GomokuBoard(), GomokuColor.white)?.notation)
        val limits = GomokuAISearchLimits()
        assertEquals(listOf(1500L, 64L), listOf(limits.timeBudget.inWholeMilliseconds, limits.maxDepth.toLong()))
        assertEquals(null, limits.tieBreakSeed)
    }

    /** 집합에 쓰인 배열이 비지 않았다(빈 대조가 초록이 되지 않게). */
    @Test
    fun puzzleGoldenIsNotHollow() {
        val golden = Golden.load("renju/ai-puzzles")
        val withSets = golden.cases.count { it["expect"] is JsonArray || it["reject"] is JsonArray }
        val withPlayouts = golden.cases.count { it.optInt("winWithin") != null || it.optInt("holdFor") != null }
        assertTrue(withSets >= 12 && withPlayouts >= 6, "집합 $withSets · 수순 $withPlayouts")
    }
}
