// 원본: Sources/CheckCore/ReversiAI.swift · Sources/CheckCore/ReversiAIEngine.swift:35-76(ReversiAIDecision · ReversiAI.decide) @ 12624739
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.reversi.ReversiBits
import com.yehsung.aingcheck.core.rules.reversi.sides
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource

// 아잉 뒤집기 AI(단일 난이도 — 일부러 틀리는 수 없음). 설계: flip/SPEC.md §4.2.
// 직접 작성, 외부 엔진 코드 없음(GPL 엔진의 소스·평가표·정석 책을 보지도 베끼지도 않는다) — 맥 Swift 엔진을 줄 그대로 옮겼다.
//
// 공개 서명(`ReversiAISearchLimits` · `ReversiAI.bestMove`)은 스토어·화면 갈래와의 계약이다(맥과 같은 이름·기본값).
// 오목 `GomokuAI` · 체스 `ChessAI` 와 같은 꼴: 시간 예산 · 깊이 상한 · 동점 씨앗 · 취소 문 · 주입한 단조 시계.
// 동점 고르기는 [SwiftRandomSource](Swift `randomElement(using:)` 와 같은 알고리즘)라 같은 씨앗이면 맥과 같은 수를 고른다.

/** Swift `ReversiAISearchLimits` — 한 수를 고를 때의 한도. 기본값까지 계약이다. */
data class ReversiAISearchLimits(
    /** 생각 시간 상한(사용자 결정 1.5초). 반복 심화가 이 시간에 끊긴다. */
    val timeBudget: Duration = 1500.milliseconds,
    /** 탐색 깊이 상한. 앱은 넉넉히 두고 시간이 먼저 끊게 한다 — 시험은 이 값으로 결정적으로 돌린다. */
    val maxDepth: Int = 60,
    /** 점수가 완전히 같은 최선의 수끼리 고를 때 쓰는 씨앗. null 이면 시스템 무작위(앱), 시험은 고정한다. */
    val tieBreakSeed: ULong? = null,
) {
    companion object {
        /** 앱 기본값(1.5초 · 깊이 60 · 시스템 무작위). */
        val standard: ReversiAISearchLimits = ReversiAISearchLimits()
    }
}

/** Swift `ReversiAIDecision` — 한 번의 탐색 결과(측정·시험용). 앱은 [ReversiAI.bestMove] 로 수만 받는다. */
data class ReversiAIDecision(
    /** 고른 칸(idx). */
    val move: Int,
    /** 두는 쪽 시점 값. [exact] 면 최종 WOF 점수 차(−64…64), 아니면 평가 단위(끝난 판은 ±win + 점수 차). */
    val score: Int,
    /** 판 끝까지 읽은 값인가(종반 완전 탐색을 끝까지 마쳤다). */
    val exact: Boolean,
    /** 끝까지 마친 가장 깊은 반복(완전 탐색이면 빈칸 수). 수가 하나뿐이라 탐색하지 않았으면 0. */
    val depth: Int,
    /** 마지막으로 마친 반복에서 최선 값과 똑같은 수(오름차순). [move] 는 이 가운데 하나다. */
    val tiedMoves: List<Int>,
    val nodes: Int,
    val elapsed: Duration,
    /** 마감·취소로 어떤 반복을 도중에 버렸는가. */
    val aborted: Boolean,
)

/** Swift `ReversiAI`. 탐색 본체는 ReversiAIEngine.kt(반복 심화 negamax + 알파베타 · 종반 완전 탐색 · 최선 동점끼리만 무작위). */
object ReversiAI {
    /**
     * `toMove` 가 둘 최선의 수(idx). 둘 곳이 없을 때만 null.
     * `isCancelled` 가 true 가 되면 지금까지 찾은 최선(없으면 첫 합법 수)을 곧바로 돌려준다.
     * `timeSource` 는 시간 예산을 재는 단조 시계다(벽시계가 아니다).
     */
    fun bestMove(
        board: ReversiBoard,
        toMove: ReversiColor,
        limits: ReversiAISearchLimits = ReversiAISearchLimits.standard,
        isCancelled: () -> Boolean = { false },
        timeSource: TimeSource = TimeSource.Monotonic,
    ): Int? = decide(board, toMove, limits, isCancelled, timeSource)?.move

    /** [bestMove] 와 같은 탐색이지만 값·깊이·동점 후보·노드·걸린 시간까지 낸다. 둘 곳이 없으면 null. */
    fun decide(
        board: ReversiBoard,
        toMove: ReversiColor,
        limits: ReversiAISearchLimits = ReversiAISearchLimits.standard,
        isCancelled: () -> Boolean = { false },
        timeSource: TimeSource = TimeSource.Monotonic,
    ): ReversiAIDecision? {
        val (own, opp) = board.sides(toMove)
        if (ReversiBits.moves(own, opp) == 0uL) return null
        // 엔진은 이 호출 안에서만 산다 — 취소 문을 들고 있어도 호출 밖으로 새지 않는다.
        val engine = ReversiAIEngine(limits.timeBudget, isCancelled, timeSource)
        val depth = maxOf(1, limits.maxDepth)
        val seed = limits.tieBreakSeed
        val rng: SwiftRandomSource = if (seed != null) SeededSwiftRandom(seed) else SystemSwiftRandom
        return engine.decide(own, opp, depth, rng)
    }
}
