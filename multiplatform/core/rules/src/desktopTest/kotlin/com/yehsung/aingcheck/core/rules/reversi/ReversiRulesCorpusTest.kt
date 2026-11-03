// 원본: Tests/checkTests/ReversiRulesTests.swift:189-434 @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 아잉 뒤집기 규칙([ReversiRules]) — **판정 코퍼스 hand 48 의 합격선**(맥 `ReversiRulesTests` 의 Kotlin 판).
 * 기대값은 이 파일에 없다 — cases.json 한 곳에 있고 서버 판정 함수·맥 Swift·파이썬 참조 구현이 같은 파일을 정답으로 쓴다.
 * 재는 것: hand 의 kind 셋(legal 6 · move 33 · score 9)을 전부 · 판 끝 1차원 넘김(C04~C07)을 넘김 구현과 갈라서 ·
 * 시작 흑 네 수의 불변식 · 비트보드 = 2차원 걷기(무작위 대국 차분) · 좌표 표기.
 */
class ReversiRulesCorpusTest {
    // 없으면: 누가 코퍼스에서 사례를 지우거나 kind 를 바꿔도 아래 반복 시험들은 남은 것만 돌고 초록이다.
    @Test
    fun corpusShapeIsIntact() {
        val corpus = ReversiCorpusFile.load()
        assertEquals("reversi-cases/1", corpus.str("schema"))
        val hand = ReversiCorpusFile.hand(corpus)
        assertEquals(48, hand.size)
        assertEquals(48, hand.map { it.str("id") }.toSet().size, "사례 id 가 겹친다")
        assertEquals(6, hand.count { it.str("kind") == "legal" })
        assertEquals(33, hand.count { it.str("kind") == "move" })
        assertEquals(9, hand.count { it.str("kind") == "score" })
        assertEquals(listOf("S01", "S02", "S03", "S04", "S05"), corpus.objects("streak").map { it.str("id") })
        assertEquals(200, corpus.objects("wthor_sample").size)
        val perft = corpus.obj("perft")!!
        assertEquals((1..10).map(Int::toString).toSet(), perft.obj("values")!!.keys)
        assertEquals(ReversiBoard.start.string, perft.str("start"))
        assertEquals("black", perft.str("to_move"))
    }

    // 없으면: 합법 수 목록이 색을 뒤바꾸거나(A02) 빈 목록을 잘못 내도(E02·E05 의 패스·끝 판단) 착수 시험만으로는 안 드러난다.
    @Test
    fun legalCasesMatch() {
        val cases = ReversiCorpusFile.hand().filter { it.str("kind") == "legal" }
        assertEquals(6, cases.size)
        for (item in cases) {
            val id = item.str("id")!!
            val board = ReversiCorpusFile.board(item.str("board"), id)
            val color = ReversiCorpusFile.color(item.str("color"), id)
            val expected = item.obj("expected")!!
            val mine = ReversiRules.legalMoves(board, color)
            val theirs = ReversiRules.legalMoves(board, color.opponent)
            assertEquals(expected.ints("legal_moves"), mine, "$id ${item.str("title")}")
            assertEquals(expected.ints("opponent_legal_moves"), theirs, "$id 상대 합법 수")
            assertEquals(mine.isNotEmpty(), ReversiRules.hasLegalMove(board, color), id)
            val resolution = if (mine.isNotEmpty()) "move" else if (theirs.isNotEmpty()) "pass" else "over"
            assertEquals(expected.str("resolution"), resolution, "$id 차례 판단")
            assertEquals(resolution == "over", ReversiRules.endKind(board) != null, "$id 끝 판단")
        }
    }

    // 없으면: 뒤집기·다음 차례·자동 패스·끝 사유·WOF 점수 가운데 하나가 틀려도 다른 갈래(서버·화면)가 먼저 밟을 때까지 모른다.
    @Test
    fun moveCasesMatch() {
        val cases = ReversiCorpusFile.hand().filter { it.str("kind") == "move" }
        var legalCount = 0
        var illegalCount = 0
        for (item in cases) {
            val id = item.str("id")!!
            val board = ReversiCorpusFile.board(item.str("board"), id)
            val color = ReversiCorpusFile.color(item.str("color"), id)
            val idx = item.intOrNull("idx") ?: fail("$id: idx 가 없다")
            val expected = item.obj("expected")!!
            when (val verdict = ReversiRules.play(board, color, idx)) {
                is ReversiPlay.Played -> {
                    legalCount += 1
                    val outcome = verdict.outcome
                    assertEquals(true, expected.boolOrNull("legal"), "$id ${item.str("title")}: 코퍼스는 불법(${expected.str("reason")})인데 두어졌다")
                    assertEquals(expected.ints("flipped"), outcome.flipped, "$id 뒤집힌 칸")
                    assertEquals(expected.ints("flipped"), ReversiRules.flips(board, color, idx), "$id flips")
                    assertEquals(expected.str("board_after"), outcome.board.string, "$id 둔 뒤 판")
                    assertEquals(expected.str("next"), outcome.next?.rawValue, "$id 다음 차례")
                    assertEquals(expected.boolOrNull("passed"), outcome.passed, "$id 자동 패스")
                    assertEquals(expected.boolOrNull("over"), outcome.isOver, "$id 끝")
                    assertEquals(expected.obj("discs")?.counts(), outcome.counts, "$id 돌 수")
                    assertEquals(expected.obj("score")?.scoreTriple(), outcome.score?.triple(), "$id 점수")
                    assertEquals(expected.str("end"), outcome.end?.rawValue, "$id 끝 사유")
                    // 같은 판정을 낱개 함수로 다시 — play 안에서만 맞고 낱개가 갈리면 서버 쌍둥이와 대조할 때 어긋난다.
                    assertEquals(ReversiNextTurn(outcome.next, outcome.passed), ReversiRules.nextTurn(outcome.board, color), "$id nextTurn")
                    assertEquals(outcome.end, ReversiRules.endKind(outcome.board), "$id endKind")
                    assertEquals(outcome.score, ReversiRules.score(outcome.board), "$id score")
                }
                is ReversiPlay.Illegal -> {
                    illegalCount += 1
                    assertEquals(false, expected.boolOrNull("legal"), "$id ${item.str("title")}: 코퍼스는 합법인데 ${verdict.reason.rawValue} 로 막혔다")
                    assertEquals(expected.str("reason"), verdict.reason.rawValue, "$id 불법 까닭")
                    assertEquals(item.str("board"), expected.str("board_after"), "$id: 코퍼스가 불법 수의 판을 바꿔 적었다")
                    assertTrue(ReversiRules.flips(board, color, idx).isEmpty(), "$id 불법 칸에 뒤집힘이 있다")
                    assertTrue(idx !in ReversiRules.legalMoves(board, color), "$id 불법 칸이 합법 수 목록에 있다")
                }
            }
        }
        // 갈래 수까지 못 박는다 — 한쪽이 통째로 비면(예: 전부 불법) 위 단언 절반이 안 돈다.
        assertEquals(21, legalCount)
        assertEquals(12, illegalCount)
    }

    // 없으면: 끝 분류 순서(전멸 → 판 가득 → no_moves)나 빈칸 몫(이긴 쪽에 전부, 같으면 32:32)이 틀려도 착수 사례가 다 못 잡는다.
    @Test
    fun scoreCasesMatch() {
        val cases = ReversiCorpusFile.hand().filter { it.str("kind") == "score" }
        assertEquals(9, cases.size)
        for (item in cases) {
            val id = item.str("id")!!
            val board = ReversiCorpusFile.board(item.str("board"), id)
            val expected = item.obj("expected")!!
            assertEquals(expected.boolOrNull("over"), ReversiRules.endKind(board) != null, "$id ${item.str("title")}")
            assertEquals(expected.str("end"), ReversiRules.endKind(board)?.rawValue, "$id 끝 사유")
            assertEquals(expected.obj("score")?.scoreTriple(), ReversiRules.score(board)?.triple(), "$id 점수")
            assertEquals(expected.obj("discs")?.counts(), board.counts, "$id 돌 수")
            ReversiRules.score(board)?.let { assertEquals(64, it.black + it.white, "$id 점수 합") }
        }
    }

    // 없으면: 비트 이동의 행 끝 가면을 빠뜨린 구현(h4 +1 = a5)이 C04~C07 에서 뒤집어도 "그 사례들이 정말 그 결함을 밟는지"를 모른다.
    // 기준선: 1차원 idx 에 ±1·±7·±8·±9 를 더하고 64 로 감아 읽는 넘김 구현은 네 사례 모두에서 뭔가를 뒤집는다 — 결과가 갈린다.
    @Test
    fun edgeWrapCasesDiscriminate() {
        val corpus = ReversiCorpusFile.load()
        for (id in listOf("C04", "C05", "C06", "C07")) {
            val item = ReversiCorpusFile.hand(id, corpus)
            val board = ReversiCorpusFile.board(item.str("board"), id)
            val color = ReversiCorpusFile.color(item.str("color"), id)
            val idx = item.intOrNull("idx")!!
            assertEquals("no_flip", item.obj("expected")!!.str("reason"), "$id: 코퍼스 기대가 바뀌었다")
            assertTrue(ReversiRules.flips(board, color, idx).isEmpty(), "$id ${item.str("title")}")
            assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.noFlip), ReversiRules.play(board, color, idx), id)
            assertTrue(wrappingFlips(item.str("board")!!, color, idx).isNotEmpty(), "$id: 넘김 구현도 못 뒤집는다 — 이 사례는 판 끝 결함을 가르지 못한다")
        }
    }

    // 없으면: 시작 배치(V-04)나 첫 수 판정이 어긋나도 perft 1 = 4 만으로는 "네 수가 대칭인지"까지 못 본다.
    @Test
    fun startPositionFourMovesInvariant() {
        val start = ReversiBoard.start
        assertEquals("...........................wb......bw...........................", start.string)
        assertEquals(ReversiCounts(2, 2, 60), start.counts)
        assertEquals(listOf(19, 26, 37, 44), ReversiRules.legalMoves(start, ReversiColor.black))
        assertEquals(listOf(20, 29, 34, 43), ReversiRules.legalMoves(start, ReversiColor.white))
        assertNull(ReversiRules.endKind(start))
        assertNull(ReversiRules.score(start))
        for (idx in listOf(19, 26, 37, 44)) {
            val outcome = assertNotNull(ReversiRules.play(start, ReversiColor.black, idx).outcomeOrNull, "흑 $idx")
            assertEquals(1, outcome.flipped.size, "흑 $idx")
            assertEquals(ReversiCounts(4, 1, 59), outcome.counts, "흑 $idx")
            assertTrue(outcome.next == ReversiColor.white && !outcome.passed && !outcome.isOver, "흑 $idx")
            assertEquals(3, ReversiRules.legalMoves(outcome.board, ReversiColor.white).size, "흑 $idx 뒤 백의 응수")
        }
    }

    // 없으면: 비트보드 가면·밀기에 코퍼스 손 사례가 안 덮는 자리(긴 줄·여러 방향·판 끝 근처)의 결함이 남는다.
    // 무작위 대국의 모든 국면에서 두 색 × 64칸의 뒤집힘과 합법 수를 행·열 2차원 걷기(reference.py 를 옮긴 것)와 맞세운다.
    @Test
    fun bitboardMatchesTwoDimensionalWalk() = compareWithWalk(games = 6, seed = 0x5245_5645_5253_4931uL)

    @Test
    @EnabledIfEnvironmentVariable(named = "REVERSI_PERFT_DEEP", matches = "1")
    fun deepBitboardMatchesTwoDimensionalWalk() = compareWithWalk(games = 200, seed = 0x5245_5645_5253_4932uL)

    private fun compareWithWalk(games: Int, seed: ULong) {
        val rng = SplitMix64(seed)
        var positions = 0
        repeat(games) {
            var board = ReversiBoard.start
            var turn: ReversiColor? = ReversiColor.black
            while (turn != null) {
                val color: ReversiColor = turn
                val text = board.string
                for (side in ReversiColor.entries) {
                    val walked = (0 until 64).map { walkedFlips(text, side, it) }
                    val ours = (0 until 64).map { ReversiRules.flips(board, side, it) }
                    assertEquals(walked, ours, "$text $side")
                    assertEquals((0 until 64).filter { walked[it].isNotEmpty() }, ReversiRules.legalMoves(board, side), "$text $side")
                }
                positions += 1
                val moves = ReversiRules.legalMoves(board, color)
                val pick = moves[(rng.next() % moves.size.toULong()).toInt()]
                val outcome = ReversiRules.play(board, color, pick).outcomeOrNull ?: fail("$text: $pick 가 불법")
                board = outcome.board
                turn = outcome.next
            }
        }
        assertTrue(positions > games * 50, "대국이 너무 짧다($positions 국면) — 무작위가 고장 났다")
    }

    // 없으면: 화면 표기(d3)와 와이어 idx 가 행·열을 뒤바꿔도(V-01 한계) 코퍼스의 coord·idx 쌍이 그것을 못 잡는다.
    @Test
    fun coordinatesMatchCorpus() {
        assertEquals(19, ReversiPoint.fromCoord("d3")?.idx)
        assertEquals(19, ReversiPoint.fromCoord("D3")?.idx)
        assertEquals(0, ReversiPoint.fromCoord("a1")?.idx)
        assertEquals(7, ReversiPoint.fromCoord("h1")?.idx)
        assertEquals(56, ReversiPoint.fromCoord("a8")?.idx)
        assertEquals(63, ReversiPoint.fromCoord("h8")?.idx)
        assertEquals("d3", ReversiPoint.of(19)?.coord)
        assertEquals(ReversiPoint.of(col = 3, row = 2), ReversiPoint.of(19))
        for (idx in 0 until 64) {
            val point = assertNotNull(ReversiPoint.of(idx))
            assertEquals(point, ReversiPoint.fromCoord(point.coord), "$idx")
            assertEquals(point, ReversiPoint.fromCoord(point.coord.uppercase()), "$idx 대문자")
            assertEquals(idx, point.idx)
        }
        var paired = 0
        for (item in ReversiCorpusFile.hand()) {
            val coord = item.str("coord") ?: continue
            val idx = item.intOrNull("idx") ?: continue
            assertEquals(idx, ReversiPoint.fromCoord(coord)?.idx, "${item.str("id")} $coord")
            paired += 1
        }
        assertEquals(32, paired, "coord·idx 쌍이 있는 move 사례 수(A10 은 판 밖이라 coord 가 없다)")
    }

    companion object {
        private val directions = listOf(-1 to -1, -1 to 0, -1 to 1, 0 to -1, 0 to 1, 1 to -1, 1 to 0, 1 to 1)

        /** reference.py `flips` 를 옮긴 행·열 2차원 걷기 — 비트보드와 맞세우는 정답. */
        fun walkedFlips(cells: String, color: ReversiColor, idx: Int): List<Int> {
            if (idx !in 0 until 64 || cells[idx] != '.') return emptyList()
            val me = color.cell
            val op = color.opponent.cell
            val out = ArrayList<Int>()
            for ((dr, dc) in directions) {
                var r = idx / 8 + dr
                var c = idx % 8 + dc
                val line = ArrayList<Int>()
                while (r in 0 until 8 && c in 0 until 8 && cells[r * 8 + c] == op) {
                    line.add(r * 8 + c)
                    r += dr
                    c += dc
                }
                if (line.isNotEmpty() && r in 0 until 8 && c in 0 until 8 && cells[r * 8 + c] == me) out.addAll(line)
            }
            return out.sorted()
        }

        /** **틀린** 구현(기준선): 1차원 idx 에 방향 차를 더하고 64 로 감아 읽는다(행 끝·판 끝을 모른다). C04~C07 이 이것을 가른다. */
        fun wrappingFlips(cells: String, color: ReversiColor, idx: Int): List<Int> {
            if (idx !in 0 until 64 || cells[idx] != '.') return emptyList()
            val me = color.cell
            val op = color.opponent.cell
            fun cell(i: Int): Char = cells[((i % 64) + 64) % 64]
            val out = ArrayList<Int>()
            for (step in listOf(-9, -8, -7, -1, 1, 7, 8, 9)) {
                var i = idx + step
                val line = ArrayList<Int>()
                while (line.size < 7 && cell(i) == op) {
                    line.add(((i % 64) + 64) % 64)
                    i += step
                }
                if (line.isNotEmpty() && cell(i) == me) out.addAll(line)
            }
            return out.sorted()
        }
    }
}
