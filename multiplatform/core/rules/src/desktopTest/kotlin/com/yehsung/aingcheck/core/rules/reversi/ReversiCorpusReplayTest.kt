// 원본: Tests/checkTests/ReversiCorpusTests.swift @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 아잉 뒤집기 실전 기보 재생 — cases.json `wthor_sample` 200판(공개 대회 기보 표본)과 가장 짧은 판.
 * 판 하나를 처음부터 끝까지 둔다: 자동 패스 자리(passes_before) · 마지막 판 · 실제 돌 수 · WOF 점수 · 결과 · 끝 사유 · 기보 파일의 흑 점수.
 */
class ReversiCorpusReplayTest {
    private class Replay(var board: ReversiBoard = ReversiBoard.start, var turn: ReversiColor? = ReversiColor.black) {
        val passesBefore = ArrayList<Int>()
        var played = 0
    }

    /** 수 목록을 시작 판부터 둔다(둘 곳 없는 쪽은 자동 패스). 불법이거나 끝난 뒤에 수가 남으면 실패. */
    private fun replay(moves: List<Int>, label: String): Replay {
        val state = Replay()
        for ((k, idx) in moves.withIndex()) {
            val color = state.turn ?: fail("$label: $k 번째 수($idx) 전에 판이 끝났다")
            when (val verdict = ReversiRules.play(state.board, color, idx)) {
                is ReversiPlay.Illegal ->
                    fail("$label: $k 번째 수 ${ReversiPoint.of(idx)?.coord ?: "$idx"} ($color) 가 불법 — ${verdict.reason.rawValue}\n${state.board.string}")
                is ReversiPlay.Played -> {
                    state.board = verdict.outcome.board
                    state.turn = verdict.outcome.next
                    state.played += 1
                    // passes_before = k+1: 다음 수(k+1 번째)를 두기 직전에 자동 패스가 있었다.
                    if (verdict.outcome.passed) state.passesBefore.add(k + 1)
                }
            }
        }
        return state
    }

    private fun samples(): List<JsonObject> = ReversiCorpusFile.load().objects("wthor_sample")

    // 없으면: 표본에서 패스·무승부·전멸·no_moves 판이 빠져도 아래 재생은 판 가득 판만 돌고 초록이다.
    @Test
    fun sampleCoversEveryEnding() {
        val games = samples()
        assertEquals(200, games.size)
        assertEquals(200, games.map { it.str("id") }.toSet().size)
        assertEquals(setOf("board_full", "no_moves", "wipeout"), games.map { it.str("end") }.toSet())
        assertTrue(games.any { it.str("result") == "draw" })
        assertTrue(games.any { it.str("result") == "black_win" } && games.any { it.str("result") == "white_win" })
        assertTrue(games.count { it.ints("passes_before")!!.isNotEmpty() } >= 15)
    }

    // 없으면: 자동 패스 시점(V-09)·끝 판정(V-10)·WOF 점수(V-11)가 손 사례 밖의 실전 판에서 갈려도 모른다.
    @Test
    fun wthorSampleReplays() {
        var replayed = 0
        for (game in samples()) {
            val label = "${game.str("id")}(${game.str("picked_for")})"
            val moves = ReversiCorpusFile.indices(game.str("moves")!!, label)
            val state = replay(moves, label)
            assertEquals(game.intOrNull("plies"), moves.size, "$label 수 수")
            assertNull(state.turn, "$label: 기보가 끝났는데 판이 안 끝났다")
            assertEquals(game.ints("passes_before"), state.passesBefore, "$label 패스 자리")
            assertEquals(game.str("final_board"), state.board.string, "$label 마지막 판")
            assertEquals(game.obj("discs")!!.counts(), state.board.counts, "$label 돌 수")
            val score = ReversiRules.score(state.board)
            val pair = game.obj("score")!!
            assertEquals<Pair<Int?, Int?>?>(pair.intOrNull("black") to pair.intOrNull("white"), score?.let { it.black to it.white }, "$label WOF 점수")
            assertEquals(game.str("result"), score?.result?.rawValue, "$label 결과")
            assertEquals(game.str("end"), ReversiRules.endKind(state.board)?.rawValue, "$label 끝 사유")
            assertEquals(game.intOrNull("official_black_score"), score?.black, "$label: 기보 파일의 흑 점수와 다르다")
            replayed += 1
        }
        assertEquals(200, replayed)
    }

    // 없으면: 판 가득 전에 전멸로 끝나는 판(9수)이 "끝난 뒤 수가 남음"·"전멸 대신 no_moves" 로 갈려도 표본만으로는 드물게만 밟힌다.
    @Test
    fun shortestGameReplays() {
        val shortest = ReversiCorpusFile.load().obj("perft")!!.obj("shortest_game")!!
        val moves = ReversiCorpusFile.indices(shortest.str("moves")!!, "shortest_game")
        assertEquals(9, moves.size)
        val state = replay(moves, "shortest_game")
        assertNull(state.turn)
        assertEquals(shortest.str("final_board"), state.board.string)
        assertEquals(shortest.obj("discs")!!.counts(), state.board.counts)
        val score = assertNotNull(ReversiRules.score(state.board))
        assertEquals<Pair<Int?, Int?>>(shortest.obj("score")!!.intOrNull("black") to shortest.obj("score")!!.intOrNull("white"), score.black to score.white)
        assertEquals(shortest.str("result"), score.result.rawValue)
        assertEquals(shortest.str("end"), ReversiRules.endKind(state.board)?.rawValue)
        // 기준선: 마지막 수 하나를 빼면 판은 아직 안 끝났다 — "끝"이 수 수와 상관없이 늘 참인 구현을 가른다.
        val before = replay(moves.dropLast(1), "shortest_game −1")
        assertNotNull(before.turn)
        assertNull(ReversiRules.endKind(before.board))
    }
}
