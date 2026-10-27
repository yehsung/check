// 원본: Sources/CheckCore/GomokuAI.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource

// 오목 AI(렌주룰, 단일 난이도 — 항상 최선의 수). 설계: docs/plan/gomoku-ai.md §2.
// 공개 서명(`GomokuAISearchLimits` · `GomokuAI.bestMove`)은 대국·화면 갈래와의 계약이다. 몸통은 GomokuAIEngine.kt.

/** 한 수를 고를 때의 한도. 기본값까지 계약이다(Swift `publicSignatureAndDefaultsStayPut`). */
data class GomokuAISearchLimits(
    /** 생각 시간 상한. 반복 심화가 이 시간에 끊긴다. */
    val timeBudget: Duration = 1500.milliseconds,
    /** 탐색 깊이 상한. 앱은 넉넉히 두고 시간이 먼저 끊게 한다 — 시험은 이 값으로 결정적으로 돌린다. */
    val maxDepth: Int = 64,
    /** 점수가 완전히 같은 최선의 수끼리 고를 때 쓰는 씨앗. null 이면 시스템 무작위(앱), 시험은 고정한다. */
    val tieBreakSeed: ULong? = null,
)

object GomokuAI {
    /**
     * `toMove` 가 둘 최선의 수. 둘 곳이 없으면(흑의 빈칸이 전부 금수 · 판 가득) null.
     * `isCancelled` 가 true 가 되면 지금까지 찾은 최선(없으면 첫 합법 수)을 곧바로 돌려준다.
     * `timeSource` 는 시간 예산을 재는 단조 시계다(벽시계가 아니다 — 구조 규칙 R2 와 무관).
     */
    fun bestMove(
        board: GomokuBoard,
        toMove: GomokuColor,
        limits: GomokuAISearchLimits = GomokuAISearchLimits(),
        isCancelled: () -> Boolean = { false },
        timeSource: TimeSource = TimeSource.Monotonic,
    ): GomokuPoint? {
        // 빈 판: 천원(H8). 흑 첫 수 자리이고 백이어도 가장 좋은 자리다.
        if (board.stoneCount <= 0) return GomokuPoint.at(GomokuBoard.size / 2, GomokuBoard.size / 2)
        if (board.stoneCount >= GomokuBoard.cellCount) return null
        val side = if (toMove == GomokuColor.black) 1 else 2
        val depth = maxOf(1, limits.maxDepth)
        val engine = GomokuAIEngine(board, limits.timeBudget, isCancelled, timeSource)
        val seed = limits.tieBreakSeed
        val rng: SwiftRandomSource = if (seed != null) SeededSwiftRandom(seed) else SystemSwiftRandom
        val move = engine.chooseMove(side, depth, rng) ?: return null
        val (x, y) = GomokuAIEngine.coordinates(move)
        return GomokuPoint.at(x, y)
    }
}
