// 원본: Tests/checkTests/ChessAIEngineTests.swift · Tests/checkTests/GoldenExport/games-board/GoldenExportGamesBoardAI.swift(chess/ai-*) @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.chess.ChessEngine
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessRules
import com.yehsung.aingcheck.core.rules.chess.fen
import com.yehsung.aingcheck.core.rules.chess.fromFen
import com.yehsung.aingcheck.core.rules.chess.fromUci
import com.yehsung.aingcheck.core.rules.chess.uci
import com.yehsung.aingcheck.core.rules.renju.asArray
import com.yehsung.aingcheck.core.rules.renju.intValue
import com.yehsung.aingcheck.core.rules.renju.optBool
import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.core.rules.renju.optString
import com.yehsung.aingcheck.core.rules.renju.optStringValue
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFnv1a64
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlin.time.Duration.Companion.seconds

/**
 * 체스 AI. 집합 동등(chess/ai-puzzles: 메이트 거리 · 공짜 퀸 · 정지 탐색 · 스테일메이트 · 3회 반복)과 비트 대조(chess/ai-trace: 표 지문 ·
 * 국면별 수·점수·마친 깊이·노드 수 · 증분 Zobrist). 시간 예산 600초라 깊이가 먼저 끊는다. 데스크톱 JVM 에서만 돈다.
 */
class ChessAIGoldenTest {
    private fun repetition(case: JsonObject): Map<String, Int> =
        case.array("repetition").associate { it.asArray().let { row -> row[0].optStringValue()!! to row[1].intValue() } }

    private fun limits(case: JsonObject) = ChessAISearchLimits(600.seconds, case.int("depth"), case.hex64("seed"))

    @Test
    fun puzzlesAreSolvedWithinTheAnswerSets() {
        val golden = Golden.load("chess/ai-puzzles")
        var checked = 0
        for (case in golden.cases) {
            val id = case.string("id")
            val position = ChessPosition.fromFen(case.string("fen")) ?: fail(golden.failure(id, "FEN"))
            val decision = ChessAI.decide(position, repetition(case), limits(case))
            if (case.optBool("expectNone") == true) {
                assertNull(decision, golden.failure(id, "둘 수가 없는 국면인데 수를 냈다"))
                continue
            }
            assertNotNull(decision, golden.failure(id, "수가 없다"))
            val uci = decision.move.uci
            assertTrue(decision.move in ChessRules.legalMoves(position), golden.failure(id, "불법 수 $uci"))
            if (case["expect"] !is JsonNull) assertTrue(uci in case.array("expect").strings(), golden.failure(id, "$uci ∉ expect"))
            if (case["reject"] !is JsonNull) assertFalse(uci in case.array("reject").strings(), golden.failure(id, "$uci ∈ reject"))
            case.optInt("mateInPlies")?.let { assertEquals(it, decision.mateInPlies, golden.failure(id, "메이트 거리(점수 ${decision.score})")) }
            case.optInt("scoreAbove")?.let { assertTrue(decision.score > it, golden.failure(id, "점수 ${decision.score} ≤ $it")) }
            case.optInt("scoreBelow")?.let { assertTrue(decision.score < it, golden.failure(id, "점수 ${decision.score} ≥ $it")) }
            case.optInt("scoreEquals")?.let { assertEquals(it, decision.score, golden.failure(id, "점수")) }
            checked++
        }
        assertTrue(checked >= 19, "과제 $checked 개")
    }

    @Test
    fun tracesMatchSwiftBitForBit() {
        val golden = Golden.load("chess/ai-trace")
        var decisions = 0
        var lines = 0
        for (case in golden.cases) {
            val id = case.string("id")
            when {
                id == "tables" -> {
                    val pieces = GoldenFnv1a64().also { h -> ChessAITables.zobristPieces.forEach { h.add(it.toULong()) } }
                    assertEquals(case.string("zobristPieces"), Golden.hex64Text(pieces.value), "Zobrist 말·칸")
                    val rest = GoldenFnv1a64().also { h ->
                        ChessAITables.zobristCastling.forEach { h.add(it.toULong()) }
                        ChessAITables.zobristEnPassant.forEach { h.add(it.toULong()) }
                        h.add(ChessAITables.zobristSide.toULong())
                    }
                    assertEquals(case.string("zobristRest"), Golden.hex64Text(rest.value), "Zobrist 캐슬링·앙파상·차례")
                    assertEquals(case.hex64("zobristSide"), ChessAITables.zobristSide.toULong())
                    val squares = GoldenFnv1a64().also { h -> (ChessAITables.midgame + ChessAITables.endgame).forEach { t -> t.forEach { h.add(it) } } }
                    assertEquals(case.string("squareTables"), Golden.hex64Text(squares.value), "칸 가치표")
                    assertEquals(case.array("pieceValues").map { it.intValue() }, ChessAIScore.piece.toList())
                    assertEquals(case.int("mate"), ChessAIScore.mate)
                    assertEquals(case.int("infinity"), ChessAIScore.infinity)
                }
                id.startsWith("hash-") -> {
                    val position = ChessPosition.fromFen(case.string("fen"))!!
                    val search = ChessAISearch(ChessEngine.create(position)!!, 600.seconds, { false })
                    val hashes = case.array("hashes").map { Golden.hex64(it.stringValue()) }
                    assertEquals(hashes[0], search.hash.toULong(), "$id 시작 해시")
                    assertEquals(ChessAISearch.fullHash(search.engine), search.hash)
                    val states = ArrayList<ChessAIMoveState>()
                    for ((index, text) in case.array("uci").strings().withIndex()) {
                        val raw = search.engine.matchingLegalMove(ChessMove.fromUci(text)!!) ?: fail("$id: $text 불법")
                        states.add(search.makeMove(raw))
                        assertEquals(hashes[index + 1], search.hash.toULong(), golden.failure(id, "$text 뒤 증분 해시"))
                        assertEquals(ChessAISearch.fullHash(search.engine), search.hash, "$id: $text 뒤 증분 ≠ 전체 재계산")
                    }
                    for (state in states.asReversed()) search.undoMove(state)
                    assertEquals(hashes[0], search.hash.toULong(), "$id: 되돌린 뒤 해시")
                    assertEquals(position.fen, search.engine.position.fen)
                    lines++
                }
                else -> {
                    val position = ChessPosition.fromFen(case.string("fen")) ?: fail(golden.failure(id, "FEN"))
                    val decision = ChessAI.decide(position, repetition(case), limits(case))
                    val staticEval = ChessAISearch(ChessEngine.create(position)!!, 600.seconds, { false }).evaluate()
                    val want = listOf(case.optString("move"), case.optInt("score"), case.optInt("completedDepth"), case.optInt("nodes"),
                        case.optInt("mateInPlies"), case.optInt("eval"))
                    val got = listOf(decision?.move?.uci, decision?.score, decision?.depth, decision?.nodes, decision?.mateInPlies, staticEval)
                    if (want != got) fail(golden.failure(id, "[수, 점수, 깊이, 노드, 메이트 거리, 정적 평가] Swift $want · Kotlin $got"))
                    decisions++
                }
            }
        }
        assertTrue(decisions > 35 && lines == 3, "결정 $decisions · 해시 수순 $lines")
    }

    /** 기본 한도 · 취소: 취소 문이 열려 있으면 곧바로 합법 수, 수가 없으면 null(서명·기본값은 계약). */
    @Test
    fun cancellationAndDefaults() {
        val position = ChessPosition.fromFen("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")!!
        val move = ChessAI.bestMove(position, limits = ChessAISearchLimits(30.seconds, 64), isCancelled = { true })
        assertNotNull(move)
        assertTrue(move in ChessRules.legalMoves(position))
        val defaults = ChessAISearchLimits()
        assertEquals(listOf(1500L, 64L), listOf(defaults.timeBudget.inWholeMilliseconds, defaults.maxDepth.toLong()))
        assertNull(defaults.tieBreakSeed)
        assertNull(ChessAI.bestMove(ChessPosition.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!!))
        assertNull(ChessAI.decide(ChessPosition.empty), "왕 없는 판은 결정이 없다")
    }
}
