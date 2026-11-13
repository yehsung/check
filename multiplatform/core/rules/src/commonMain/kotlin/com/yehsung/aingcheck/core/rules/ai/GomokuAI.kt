// 원본: Sources/CheckCore/GomokuAI.swift @ 1b8260d · e4995a3a(난이도 — 몇 수 앞까지 · 맥 0.3.82 · 폰 1.0.18)
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource

// 오목 AI(렌주룰). 설계: docs/plan/gomoku-ai.md §2.
// 난이도(11-10 대표: "늘 최선의 수를 못두게 하는 방식이 아니라 몇수앞까지 계산할지에 제한") — 어느 단계든 **자기 수평선 안에서는
// 언제나 최선**을 둔다. 단계는 '몇 수 앞까지 보는가' 하나로 갈린다(알파베타 깊이 · 4 로 몰기(VCF) 깊이 · 상대 몰기 끊기 깊이).
// 공개 서명(`GomokuAISearchLimits` · `GomokuAI.bestMove`)은 대국·화면 갈래와의 계약이다. 몸통은 GomokuAIEngine.kt.

/** 한 수를 고를 때의 한도. 기본값까지 계약이다(Swift `publicSignatureAndDefaultsStayPut`). */
data class GomokuAISearchLimits(
    /** 생각 시간 상한. 반복 심화가 이 시간에 끊긴다. */
    val timeBudget: Duration = 1500.milliseconds,
    /** 탐색 깊이 상한. 앱은 넉넉히 두고 시간이 먼저 끊게 한다 — 시험은 이 값으로 결정적으로 돌린다. */
    val maxDepth: Int = 64,
    /** 점수가 완전히 같은 최선의 수끼리 고를 때 쓰는 씨앗. null 이면 시스템 무작위(앱), 시험은 고정한다. */
    val tieBreakSeed: ULong? = null,
    /** 몇 수 앞까지(반수 · ply). null = 제한 없음(어려움 — 판 7 까지의 단일 난이도 그대로). */
    val lookahead: Int? = null,
    /** 내 4 로 몰기(VCF) 깊이 · 상대 몰기 끊기 깊이 · 잎 평가의 VCF 깊이(0 = 안 본다). 기본값 = 어려움(16 · 16 · 8). */
    val vcfDepth: Int = 16,
    val defenseVcfDepth: Int = 16,
    val leafVcfDepth: Int = 8,
)

/** 오목 AI 연습 난이도(맥 0.3.82 · 폰 1.0.18 — 대표 11-10). 원문 = 상수 이름(기억 저장 값). */
enum class GomokuAIDifficulty {
    easy, normal, hard;

    /** 몇 수 앞까지. 어려움은 null(제한 없음). */
    val lookahead: Int?
        get() = when (this) {
            easy -> GomokuAIDifficultyTuning.easyLookahead
            normal -> GomokuAIDifficultyTuning.normalLookahead
            hard -> null
        }

    val limits: GomokuAISearchLimits get() = lookahead?.let { limits(it) } ?: GomokuAISearchLimits()

    companion object {
        /** 몇 수 앞까지 → 한도(4 로 몰기 깊이는 절반, 잎 VCF 는 끈다 — 맥과 같은 식). */
        fun limits(lookahead: Int): GomokuAISearchLimits {
            val fours = maxOf(1, lookahead / 2)
            return GomokuAISearchLimits(maxDepth = lookahead, lookahead = lookahead, vcfDepth = fours, defenseVcfDepth = fours, leafVcfDepth = 0)
        }

        fun fromRaw(raw: String?): GomokuAIDifficulty? = entries.firstOrNull { it.name == raw }
    }
}

/** 난이도 값(맥 측정: 2v6 0:16 · 6v어려움 2:14 · 4수는 2수에 짐 — 쉬움 2 · 보통 6). */
object GomokuAIDifficultyTuning {
    const val easyLookahead = 2
    const val normalLookahead = 6
}

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
        val engine = GomokuAIEngine(board, limits.timeBudget, isCancelled, timeSource, limits)
        val seed = limits.tieBreakSeed
        val rng: SwiftRandomSource = if (seed != null) SeededSwiftRandom(seed) else SystemSwiftRandom
        val move = engine.chooseMove(side, depth, rng) ?: return null
        val (x, y) = GomokuAIEngine.coordinates(move)
        return GomokuPoint.at(x, y)
    }
}
