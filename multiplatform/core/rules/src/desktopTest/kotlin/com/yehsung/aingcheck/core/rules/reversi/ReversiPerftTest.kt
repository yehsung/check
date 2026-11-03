// 원본: Tests/checkTests/ReversiPerftTests.swift:101-227 @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기 수 세기(perft) — **ReversiRules 의 합격선**. 기대값은 `Tests/checkTests/Fixtures/reversi-perft.json` 한 곳에 있다
 * (맥 시험 · SQL 마이그레이션이 같은 파일을 베낀다). ① 시작 판 depth 1~7 과 잎 다섯은 기본, depth 8~10 은 `REVERSI_PERFT_DEEP=1` 에서만.
 */
class ReversiPerftTest {
    // 없으면: depth 0 을 0 으로 세는 구현(재귀 바닥이 틀림)이 잎 depth 1 에서야 이상하게 드러난다.
    @Test
    fun depthZeroCountsThePositionItself() {
        assertEquals(1L, ReversiRules.perft(ReversiBoard.start, ReversiColor.black, 0))
        assertEquals(0L, ReversiRules.perft(ReversiBoard.start, ReversiColor.black, -1))
        val ended = ReversiCorpusFile.board(ReversiPerftFixture.item("ⓑ").board, "ⓑ")
        assertEquals(1L, ReversiRules.perft(ended, ReversiColor.black, 0))
        assertTrue(ReversiRules.perftDivide(ReversiBoard.start, ReversiColor.black, 0).isEmpty())
    }

    // 없으면: 누가 픽스처에서 잎 하나를 지워도 아래 반복 시험은 남은 것만 돌고 초록이다. cases.json 의 perft 값과 픽스처가 따로 놀아도 모른다.
    @Test
    fun fixtureShapeIsIntact() {
        val positions = ReversiPerftFixture.positions()
        val leaves = ReversiPerftFixture.leaves()
        assertEquals(listOf("①"), positions.map { it.marker })
        assertEquals(listOf("ⓐ", "ⓑ", "ⓒ", "ⓓ", "ⓔ"), leaves.map { it.marker })
        val start = positions.first()
        assertTrue(start.board == ReversiBoard.start.string && start.color == "black")
        val values = ReversiCorpusFile.load().obj("perft")!!.obj("values")!!
        val published = (1..10).map { values.obj("$it")?.intOrNull("ply_pass")?.toLong() ?: -1L }
        assertEquals(published, start.counts, "픽스처 ① 과 cases.json perft.values.ply_pass 가 갈렸다")
        assertEquals((1..10).map { values.obj("$it")?.intOrNull("known")?.toLong() ?: -1L }, start.counts, "공표값(known)과 갈렸다")
        assertEquals(24_571_056L, start.counts[9], "depth 10 은 ply_pass 관례 값이다(24,571,284 는 ply_pass_ended)")
        for (item in leaves) {
            assertEquals(2, item.counts.size, item.label)
            assertNotNull(ReversiBoard.fromString(item.board), "${item.label}: 판을 못 읽었다")
            assertTrue('-' !in item.board, "${item.label}: 빈칸은 '.' 이다")
        }
        // 0 짜리 잎과 0 아닌 잎이 둘 다 있어야 한다 — 전부 0 이면 "0 을 특별 취급"하는 구현이 통과한다.
        assertTrue(leaves.any { it.counts[0] == 0L })
        assertTrue(leaves.any { it.counts[0] > 0L })
        val raw = ReversiPerftFixture.raw()
        for (key in listOf("about", "positions_source", "leaves_source", "leaves_why", "counts_note", "sql_contract")) {
            assertNotNull(raw.str(key), "머리 키 $key 가 없다")
        }
    }

    @Test
    fun startShallow() {
        val item = ReversiPerftFixture.item("①")
        for (depth in 1..4) expectReversiPerft(item, depth)
    }

    @Test
    fun startDepthFive() = expectReversiPerft(ReversiPerftFixture.item("①"), 5)

    @Test
    fun startDepthSix() = expectReversiPerft(ReversiPerftFixture.item("①"), 6)

    @Test
    fun startDepthSeven() = expectReversiPerft(ReversiPerftFixture.item("①"), 7)

    // 깊은 자리: 셋이 합쳐 2,797만 잎이다. depth 9 는 시작 판에서 첫 패스가 나오는 깊이다(ply_pass 와 move_only 가 처음 갈린다).
    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_PERFT_DEEP", matches = "1")
    fun deepStartDepthEight() = expectReversiPerft(ReversiPerftFixture.item("①"), 8)

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_PERFT_DEEP", matches = "1")
    fun deepStartDepthNine() = expectReversiPerft(ReversiPerftFixture.item("①"), 9)

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_PERFT_DEEP", matches = "1")
    fun deepStartDepthTen() = expectReversiPerft(ReversiPerftFixture.item("①"), 10)

    // 없으면: 패스를 깊이 없이 넘기거나(move_only) 끝난 판을 잎 1 로 세는 관례 혼동, 빈 합법 수 목록 경계 결함이 depth 9 에야 우연히 드러난다.
    @Test
    fun leavesDepthOneAndTwo() {
        val leaves = ReversiPerftFixture.leaves()
        assertEquals(5, leaves.size)
        for (item in leaves) {
            expectReversiPerft(item, 1)
            expectReversiPerft(item, 2)
        }
    }

    // 없으면: 픽스처의 outcome·score 가 말하는 국면 판단과 규칙이 갈려도 노드 수만으로는 모른다(ⓑⓒⓓ 는 셋 다 [0, 0]).
    @Test
    fun leafOutcomesMatchRules() {
        for (item in ReversiPerftFixture.leaves()) {
            val board = ReversiCorpusFile.board(item.board, item.label)
            val color = ReversiCorpusFile.color(item.color, item.label)
            val mine = ReversiRules.hasLegalMove(board, color)
            val theirs = ReversiRules.hasLegalMove(board, color.opponent)
            val actual: String? = if (mine) null else if (theirs) "pass" else ReversiRules.endKind(board)?.rawValue
            assertEquals(item.outcome, actual, "${item.label}: 국면 판단")
            assertEquals(item.json.obj("score")?.scoreTriple(), ReversiRules.score(board)?.triple(), "${item.label}: 점수")
            item.json.obj("discs")?.let { assertEquals(it.counts(), board.counts, "${item.label}: 돌 수") }
        }
    }

    // 없으면: divide 가 합계와 어긋나거나(진단 도구가 거짓말) 패스 뿌리를 빼먹어도, 실패할 때만 찍히는 도구라 아무도 모른다.
    @Test
    fun divideIsConsistent() {
        for (item in ReversiPerftFixture.all()) {
            val board = ReversiCorpusFile.board(item.board, item.label)
            val color = ReversiCorpusFile.color(item.color, item.label)
            val depth = if (item.marker == "①") 4 else 2
            val divide = ReversiRules.perftDivide(board, color, depth)
            assertEquals(ReversiRules.perft(board, color, depth), divide.sumOf { it.nodes }, item.label)
            for (child in item.terminalChildren ?: emptyList()) {
                assertEquals(0L, divide.firstOrNull { it.idx == child }?.nodes, "${item.label}: $child 는 판을 끝내는 수다")
            }
        }
        val pass = ReversiPerftFixture.item("ⓐ")
        val passDivide = ReversiRules.perftDivide(ReversiCorpusFile.board(pass.board, "ⓐ"), ReversiColor.black, 2)
        assertEquals(1, passDivide.size, "ⓐ 패스 뿌리")
        assertNull(passDivide[0].idx)
        assertEquals(1L, passDivide[0].nodes)
        val over = ReversiPerftFixture.item("ⓑ")
        assertTrue(ReversiRules.perftDivide(ReversiCorpusFile.board(over.board, "ⓑ"), ReversiColor.black, 2).isEmpty(), "ⓑ 끝난 판")
        assertEquals(listOf(36), ReversiPerftFixture.item("ⓔ").terminalChildren, "ⓔ 의 유일한 수 e5 는 백을 전멸시킨다")
    }
}
