// 원본: 없음 — 검토 F3(판 7 뒤집기 코어). 맥 Swift 엔진의 중반 결정 240건(ReversiAISwiftTrace.kt)을 Kotlin 엔진이 그대로 내는지 잰다.
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlin.time.Duration.Companion.seconds

/**
 * ReversiAI.kt 머리말의 약속 "같은 씨앗이면 맥과 같은 수를 고른다"를 **중반**(완전 탐색이 아닌 반복 심화)에서 잰다.
 * 수 · 값 · 마친 깊이 · 동점 후보 · 노드 수까지 줄마다 맞아야 한다 — 노드 수는 수 정렬 열쇠 · 치환표 해시 · 가지치기 한 글자에도 바뀐다.
 * 오목 renju/ai-trace · 체스 chess/ai-trace 골든에 해당하는 것이 리버시엔 아직 없어(contract/golden 에 reversi 폴더 없음) 갈래 시험으로 먼저 둔다.
 */
class ReversiAISwiftTraceTest {
    private class Row(
        val line: Int, val board: String, val color: ReversiColor, val seed: ULong, val maxDepth: Int,
        val move: Int, val score: Int, val exact: Boolean, val depth: Int, val tied: List<Int>, val nodes: Int, val aborted: Boolean,
    )

    private val pattern = Regex(
        """^([.bw]{64}) (black|white) s=(\d+) d=(\d+) -> move=(\d+) score=(-?\d+) exact=(true|false) depth=(\d+) tied=\[([\d, ]*)] nodes=(\d+) aborted=(true|false)$""",
    )

    private fun rows(): List<Row> = REVERSI_AI_SWIFT_TRACE.lines().filter { it.isNotBlank() }.mapIndexed { i, text ->
        val g = pattern.matchEntire(text)?.groupValues ?: fail("표 ${i + 1}행을 못 읽었다: $text")
        Row(
            line = i + 1, board = g[1], color = if (g[2] == "black") ReversiColor.black else ReversiColor.white,
            seed = g[3].toULong(), maxDepth = g[4].toInt(), move = g[5].toInt(), score = g[6].toInt(), exact = g[7] == "true",
            depth = g[8].toInt(), tied = if (g[9].isBlank()) emptyList() else g[9].split(", ").map { it.toInt() },
            nodes = g[10].toInt(), aborted = g[11] == "true",
        )
    }

    // 없으면: Kotlin 쪽 수 정렬 열쇠(2_000 + 이동성×256 − 칸 가중치)나 치환표 해시 상수가 한 글자 틀어져 중반 수가 맥과 갈려도
    // 합법 수 · 시작 판 대칭 · 손으로 센 평가 · 종반 전수 대조는 모두 초록이다(앱 세기가 조용히 바뀐다).
    @Test
    fun midgameDecisionsMatchTheMacEngineNodeForNode() {
        val rows = rows()
        // 표가 잘려 몇 줄만 남아도 초록이 되지 않게 — 줄 수 · 깊이 0…7 · 동점 줄(씨앗이 고르는 자리)이 다 있어야 한다.
        assertTrue(rows.size == 240, "표 줄 수가 240 이 아니다(${rows.size})")
        assertTrue(rows.map { it.maxDepth }.toSet() == (0..7).toSet(), "깊이 상한 0…7 이 다 있어야 한다: ${rows.map { it.maxDepth }.toSet()}")
        assertTrue(rows.count { it.tied.size > 1 } >= 10, "동점 줄이 적다(${rows.count { it.tied.size > 1 }})")
        assertTrue(rows.none { it.exact || it.aborted }, "이 표는 중반(완전 탐색 아님 · 끊김 없음) 결정만 담는다")
        val problems = mutableListOf<String>()
        for (row in rows) {
            val board = ReversiBoard.fromString(row.board) ?: fail("${row.line}행 판을 못 읽었다")
            val limits = ReversiAISearchLimits(timeBudget = 600.seconds, maxDepth = row.maxDepth, tieBreakSeed = row.seed)
            val d = ReversiAI.decide(board, row.color, limits) ?: fail("${row.line}행: 둘 곳이 없다고 했다")
            val want = "move=${row.move} score=${row.score} exact=${row.exact} depth=${row.depth} tied=${row.tied} nodes=${row.nodes} aborted=${row.aborted}"
            val got = "move=${d.move} score=${d.score} exact=${d.exact} depth=${d.depth} tied=${d.tiedMoves} nodes=${d.nodes} aborted=${d.aborted}"
            if (want != got) problems += "${row.line}행 ${row.board} ${row.color} s=${row.seed} d=${row.maxDepth}\n  Swift : $want\n  Kotlin: $got"
        }
        if (problems.isNotEmpty()) fail("맥과 다른 결정 ${problems.size}건(처음 8):\n" + problems.take(8).joinToString("\n"))
    }
}
