// 원본: Sources/CheckCore/ReversiAIEngine.swift:78-562(평가표 · 엔진) @ 12624739
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.reversi.ReversiBits
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeMark
import kotlin.time.TimeSource

// 아잉 뒤집기 AI 탐색 엔진 본체. 공개 입구는 ReversiAI.kt 의 `ReversiAI.bestMove` 하나다(측정·시험용 `ReversiAI.decide`).
// 설계: flip/SPEC.md §4.2. 직접 작성 — 평가의 숫자는 이 파일이 정하고 ReversiAIEngineTest 가 고정한다. 정석 책은 없다(v1).
//
// ── 규칙은 다시 적지 않는다 ──
// 합법 수·뒤집기는 규칙 코어의 비트보드(`ReversiBits.moves` · `ReversiBits.flips`)를 그대로 부른다. 두 벌을 두면 그 어긋남은
// 수 세기(perft)가 아니라 **대국 중 불법 수**로 드러난다. 판은 늘 "두는 쪽(own) · 상대(opp)" 두 비트로 들고 다닌다(negamax).
//
// ── 탐색 ──
// 반복 심화 negamax + 알파베타(fail-soft). 수 정렬은 **모서리 → 직전 최선(앞 깊이가 이 국면에서 고른 수) → 상대 이동성이
// 적은 순**이다(같은 이동성이면 칸 가중치가 높은 칸 먼저). 패스는 한 수(마디)로 다루되 깊이를 쓰지 않는다 — 패스는 연달아
// 두 번 올 수 없으므로(둘 다 못 두면 끝) 깊이를 안 써도 탐색이 끝난다.
//
// ── 종반 완전 탐색 ──
// 빈칸이 `endgameEmpties` 이하이고 깊이 상한이 빈칸 수 이상이면, 몸풀기 반복 심화(`endgameWarmupDepth` 까지) 뒤 판 끝까지
// 읽어 **최종 WOF 점수 차**(빈칸은 이긴 쪽에 — rules.md V-11)를 최대로 하는 수를 고른다. 예산 안에 못 끝나면 그 반복은 버리고
// 마친 반복 심화 결과를 쓴다.
//
// ── 시간 ──
// 마감은 예산보다 조금 앞(틱 사이 간격 + 뿌리 마무리). 탐색 **안에서 256 노드마다** 마감·취소를 본다 — 깊이 사이에서만 보면
// 종반 완전 탐색 한 번(= 한 반복)이 1.5초 상한을 넘기고 취소도 늦는다. 예산 절반을 넘겨 쓴 뒤에는 다음 깊이를 시작하지 않는다.
// 끊긴 반복의 값은 버린다.
//
// ── 동점 ──
// 끝까지 마친 마지막 반복에서 **값이 최선과 똑같은 수끼리만** 고른다. 뿌리의 둘째 수부터는 창을 (최선−1, +∞) 로 연다 —
// 정수 점수라 최선 이상인 값은 창 안에서 정확하고, 최선 미만은 "최선보다 작다"는 경계만 나온다(동점 후보가 아니다).
//
// Kotlin 이식 메모: Swift UnsafeMutablePointer 버퍼 → 원시 배열(비트는 Long 칸에 ULong 비트 그대로) · `ContinuousClock` → 주입한
// [TimeSource] · 해시 곱셈은 ULong 감김 곱셈(Swift `&*`) · 뿌리 재정렬은 Swift 비교식(값 내림차순, 같으면 앞 순서)과 같은 전순서.

/** Swift `ReversiAIEval` — 평가의 숫자. 전부 이 파일이 정한 값이다(외부 평가표 없음). 표는 **보이는 대로**(1행이 위, a열이 왼쪽 — idx 순서) 적는다. */
object ReversiAIEval {
    /**
     * 칸 가중치. 판의 8대칭(가로·세로·대각 뒤집기)에 대해 대칭이어야 한다 — 대칭 국면의 동점이 동점으로 남는다(시험이 잰다).
     * X(b2 등)·C(b1·a2 등) 칸은 여기서는 가볍게만 깎고, 모서리가 **비었을 때**의 큰 벌점은 [xPenalty]·[cPenalty] 가 따로 준다.
     */
    val squareWeights: List<Int> = listOf(
        100, -10, 20, 8, 8, 20, -10, 100,
        -10, -15, -4, -3, -3, -4, -15, -10,
        20, -4, 6, 3, 3, 6, -4, 20,
        8, -3, 3, 0, 0, 3, -3, 8,
        8, -3, 3, 0, 0, 3, -3, 8,
        20, -4, 6, 3, 3, 6, -4, 20,
        -10, -15, -4, -3, -3, -4, -15, -10,
        100, -10, 20, 8, 8, 20, -10, 100,
    )

    /** 이동성(내 합법 수 − 상대 합법 수) 한 칸당. */
    const val mobility: Int = 10

    /** 모서리가 비었을 때 그 X 칸(대각 이웃)에 내 돌이 있으면 깎는 값(상대 돌이면 그만큼 더한다). */
    const val xPenalty: Int = 40

    /** 모서리가 비었을 때 그 C 칸(변 위 이웃 둘)에 내 돌이 있으면 깎는 값. */
    const val cPenalty: Int = 15

    /** 경계 돌(빈칸에 닿은 돌) 하나당 — 적을수록 좋다(상대의 둘 곳이 된다). */
    const val frontier: Int = 4

    /** 변 위 안정 돌(모서리에서 이어진 돌 · 꽉 찬 변의 돌) 하나당. */
    const val stable: Int = 12

    /** 모서리 a1·h1·a8·h8. */
    val corners: IntArray = intArrayOf(0, 7, 56, 63)

    /** 모서리마다 X 칸. */
    val xSquares: IntArray = intArrayOf(9, 14, 49, 54)

    /** 모서리마다 C 칸 둘. */
    val cSquares: Array<IntArray> = arrayOf(intArrayOf(1, 8), intArrayOf(6, 15), intArrayOf(48, 57), intArrayOf(55, 62))
    val cornerMask: ULong = (1uL shl 0) or (1uL shl 7) or (1uL shl 56) or (1uL shl 63)

    /** 네 변(모서리에서 모서리로 가는 순서). 안정 돌 셈에 쓴다. */
    val edges: Array<IntArray> = arrayOf(
        intArrayOf(0, 1, 2, 3, 4, 5, 6, 7),
        intArrayOf(56, 57, 58, 59, 60, 61, 62, 63),
        intArrayOf(0, 8, 16, 24, 32, 40, 48, 56),
        intArrayOf(7, 15, 23, 31, 39, 47, 55, 63),
    )
    /** 변마다 가면(비트는 Long 칸에 ULong 비트 그대로 — 노드마다 부르므로 상자 없는 배열). */
    internal val edgeMasks: LongArray = LongArray(edges.size) { e -> edges[e].fold(0uL) { acc, idx -> acc or (1uL shl idx) }.toLong() }

    internal val weightArray: IntArray = squareWeights.toIntArray()

    /** 같은 가중치 칸끼리 묶은 가면(평가가 칸마다 돌지 않고 묶음마다 popcount 로 센다). 가중치 0 칸은 뺀다. 순서는 합에 영향이 없다. */
    internal val weightClassWeights: IntArray = squareWeights.filter { it != 0 }.distinct().sorted().toIntArray()
    internal val weightClassMasks: LongArray = LongArray(weightClassWeights.size) { i ->
        var mask = 0uL
        for ((idx, weight) in squareWeights.withIndex()) if (weight == weightClassWeights[i]) mask = mask or (1uL shl idx)
        mask.toLong()
    }
}

/** Swift `ReversiAIEngine` — 한 번의 탐색 안에서만 산다(스레드를 넘나들지 않는다). */
internal class ReversiAIEngine(
    private val budget: Duration,
    private val isCancelled: () -> Boolean,
    timeSource: TimeSource = TimeSource.Monotonic,
) {
    companion object {
        /** 탐색 경로 길이 상한(수 60 + 패스 — 패스는 연달아 오지 않으므로 120 을 넘지 않는다). */
        const val maxPly = 128

        /** 한 국면의 수 목록 칸(실제 최대 합법 수는 이보다 훨씬 적다). */
        const val slots = 64
        const val ttBits = 16
        const val infinity = 1 shl 28

        /** 끝난 판 점수의 바탕. 평가가 닿지 못하는 크기라 "이긴 판"은 어떤 평가보다 높다. */
        const val win = 1 shl 20

        /**
         * 종반 완전 탐색 문턱(빈칸 수). 맥 Release 실측(초당 약 1,900만 노드): 빈칸 14 는 0.3초 안 · 16 은 1.13초 안(중앙 0.18초) ·
         * 18 은 중앙 4.3초라 1.5초 예산으로는 대부분 못 끝낸다. 못 끝나면 그 시간을 통째로 버리므로 16 으로 둔다(맥과 같은 값).
         */
        const val endgameEmpties = 16

        /** 완전 탐색 전에 마칠 반복 심화 깊이 — 완전 탐색이 끊겼을 때 쓸 수와 뿌리 정렬을 만든다. */
        const val endgameWarmupDepth = 4

        /** 완전 탐색에서 빈칸이 이 수 이하면 정렬하지 않는다(정렬 비용이 줄인 마디보다 크다). */
        const val solveSortEmpties = 7

        /** 끝난 판의 최종 WOF 점수 차(두는 쪽 − 상대, 빈칸은 이긴 쪽에 — rules.md V-11). 같으면 0(32:32). */
        fun finalDiff(own: ULong, opp: ULong): Int {
            val mine = own.countOneBits()
            val theirs = opp.countOneBits()
            val empty = 64 - mine - theirs
            if (mine > theirs) return mine - theirs + empty
            if (mine < theirs) return mine - theirs - empty
            return 0
        }

        /** 중반 탐색에서 만난 끝난 판: 이기면 `win` + 점수 차, 지면 −`win` + 점수 차, 비기면 0. */
        fun terminal(own: ULong, opp: ULong): Int {
            val diff = finalDiff(own, opp)
            if (diff > 0) return win + diff
            if (diff < 0) return -win + diff
            return 0
        }

        /** 중반 평가(두는 쪽 시점): 칸 가중치 + 이동성 + 모서리 빈 X·C 벌점 + 경계 + 변 안정 돌. 모서리 가치는 칸 가중치(100)에 있다. */
        fun evaluate(own: ULong, opp: ULong, moves: ULong): Int {
            val replies = ReversiBits.moves(opp, own)
            var score = 0
            val masks = ReversiAIEval.weightClassMasks
            val weights = ReversiAIEval.weightClassWeights
            for (i in masks.indices) {
                val mask = masks[i].toULong()
                score += weights[i] * ((own and mask).countOneBits() - (opp and mask).countOneBits())
            }
            score += ReversiAIEval.mobility * (moves.countOneBits() - replies.countOneBits())
            val occupied = own or opp
            for (corner in 0 until 4) {
                if (occupied and (1uL shl ReversiAIEval.corners[corner]) != 0uL) continue
                val x = 1uL shl ReversiAIEval.xSquares[corner]
                if (own and x != 0uL) score -= ReversiAIEval.xPenalty
                if (opp and x != 0uL) score += ReversiAIEval.xPenalty
                val pair = ReversiAIEval.cSquares[corner]
                val cs = (1uL shl pair[0]) or (1uL shl pair[1])
                score -= ReversiAIEval.cPenalty * ((own and cs).countOneBits() - (opp and cs).countOneBits())
            }
            val empty = occupied.inv()
            var touching = 0uL
            for (direction in 0 until 8) touching = touching or ReversiBits.shift(empty, direction)
            score += ReversiAIEval.frontier * ((opp and touching).countOneBits() - (own and touching).countOneBits())
            score += ReversiAIEval.stable * (stableEdgeDiscs(own, opp) - stableEdgeDiscs(opp, own))
            return score
        }

        /**
         * 변 위에서 다시 뒤집힐 수 없는 내 돌 수. 변의 돌은 **변 방향으로만** 끼일 수 있다(다른 방향은 한쪽이 판 밖) — 그래서
         * ① 꽉 찬 변의 돌 ② 모서리에서 끊김 없이 이어진 내 돌은 끝까지 내 돌이다.
         */
        fun stableEdgeDiscs(own: ULong, opp: ULong): Int {
            val occupied = own or opp
            var stable = 0uL
            for (edge in 0 until 4) {
                val mask = ReversiAIEval.edgeMasks[edge].toULong()
                if (occupied and mask == mask) {
                    stable = stable or (own and mask)
                    continue
                }
                val line = ReversiAIEval.edges[edge]
                var forward = 0
                while (forward < 8 && own and (1uL shl line[forward]) != 0uL) {
                    stable = stable or (1uL shl line[forward])
                    forward += 1
                }
                var backward = 7
                while (backward >= 0 && own and (1uL shl line[backward]) != 0uL) {
                    stable = stable or (1uL shl line[backward])
                    backward -= 1
                }
            }
            return stable.countOneBits()
        }
    }

    private val started: TimeMark = timeSource.markNow()

    /** 마감(시작에서 잰 거리). 틱은 256 노드마다라 그 사이 간격과 뿌리 마무리가 남는다 — 예산에 딱 맞추면 재 보면 넘는다. */
    private val deadline: Duration = budget - minOf(budget / 50, 20.milliseconds)

    var nodes: Int = 0
        private set
    var aborted: Boolean = false
        private set

    /** 이번 반복에서 평가(깊이 끝)에 닿은 마디가 있었나. 없으면 그 반복은 모든 갈래가 판 끝까지 읽힌 것이다. */
    private var horizonHit = false

    // 국면마다 수 목록(ply * slots 부터): 칸 · 정렬 열쇠 · 뒤집힐 돌 · 둔 뒤 상대의 합법 수(비트는 Long 칸에 ULong 비트 그대로).
    private val moveSquare = IntArray(maxPly * slots)
    private val moveKey = IntArray(maxPly * slots)
    private val moveFlips = LongArray(maxPly * slots)
    private val moveReply = LongArray(maxPly * slots)

    // 직전 최선 표(국면 → 그 국면에서 마지막으로 고른 수). 값이 아니라 **정렬에만** 쓴다.
    private val ttOwn = LongArray(1 shl ttBits)
    private val ttOpp = LongArray(1 shl ttBits)
    private val ttMove = ByteArray(1 shl ttBits) { -1 }
    private val ttMask: ULong = ((1 shl ttBits) - 1).toULong()

    // MARK: 시간

    private fun tick() {
        nodes += 1
        if (nodes and 255 == 0 && !aborted) {
            if (started.elapsedNow() >= deadline || isCancelled()) aborted = true
        }
    }

    private fun checkAbortNow(): Boolean {
        if (!aborted && (started.elapsedNow() >= deadline || isCancelled())) aborted = true
        return aborted
    }

    private val elapsed: Duration get() = started.elapsedNow()

    // MARK: 뿌리

    fun decide(own: ULong, opp: ULong, maxDepth: Int, rng: SwiftRandomSource): ReversiAIDecision? {
        val rootBits = ReversiBits.moves(own, opp)
        if (rootBits == 0uL) return null
        val legal = ReversiBits.indices(rootBits)
        if (legal.size == 1) {
            // 고를 여지가 없다 — 탐색하지 않는다.
            return ReversiAIDecision(legal[0], 0, false, 0, legal, 0, elapsed, false)
        }
        val empties = 64 - (own or opp).countOneBits()
        // 뿌리 정렬: 안쪽 마디와 같은 열쇠로 시작하고, 반복마다 앞 반복의 값 순으로 다시 세운다(직전 최선이 맨 앞).
        val generated = generate(own, opp, rootBits, 0)
        var order: List<Int> = List(generated) { moveSquare[it] }

        var bestMoves: List<Int> = emptyList()
        var bestScore = 0
        var completedDepth = 0
        var exact = false
        var abortedIteration = false
        val canSolve = empties <= endgameEmpties && empties <= maxDepth
        var depth = 1
        while (true) {
            val solving = depth >= empties || (canSolve && depth > endgameWarmupDepth)
            var iterationBest = -infinity
            val iterationMoves = ArrayList<Int>()
            val scores = IntArray(order.size) { -infinity }
            horizonHit = false
            for ((index, square) in order.withIndex()) {
                val placed = 1uL shl square
                val flipped = ReversiBits.flips(own, opp, square)
                val newOwn = own or flipped or placed
                val newOpp = opp and flipped.inv()
                val reply = ReversiBits.moves(newOpp, newOwn)
                // 첫 수는 전 창, 둘째부터는 (최선−1, +∞): 최선 이상이면 정확한 값, 미만이면 경계뿐(동점 후보 아님).
                val alpha = if (iterationMoves.isEmpty()) -infinity else iterationBest - 1
                val value = if (solving) {
                    -solve(newOpp, newOwn, reply, -infinity, -alpha, 1)
                } else {
                    -search(newOpp, newOwn, reply, depth - 1, -infinity, -alpha, 1)
                }
                if (aborted) break
                scores[index] = value
                if (value > iterationBest) {
                    iterationBest = value
                    iterationMoves.clear()
                    iterationMoves.add(square)
                } else if (value == iterationBest) {
                    iterationMoves.add(square)
                }
            }
            if (aborted || iterationMoves.isEmpty()) {
                abortedIteration = true
                break
            }
            completedDepth = if (solving) empties else depth
            bestScore = iterationBest
            bestMoves = iterationMoves.toList()
            exact = solving
            if (solving) break
            if (!horizonHit) {
                // 평가에 한 번도 닿지 않았다 = 모든 갈래가 판 끝까지 읽혔다(일찍 끝나는 판). 값은 끝난 판 점수뿐이므로
                // ±win 을 걷어 최종 점수 차로 바꾼다(단조 변환이라 동점 집합은 그대로다). 더 깊이 볼 것이 없다.
                exact = true
                bestScore = if (bestScore > 0) bestScore - win else if (bestScore < 0) bestScore + win else 0
                break
            }
            // 다음 깊이는 직전 최선부터(값이 같으면 앞 순서 유지 — 정렬이 결정적이어야 씨앗 시험이 결정적이다).
            val ranked = order.indices.sortedWith { a, b ->
                when {
                    scores[a] > scores[b] -> -1
                    scores[a] < scores[b] -> 1
                    else -> a.compareTo(b)
                }
            }
            order = ranked.map { order[it] }
            if (depth >= maxDepth) break
            if (checkAbortNow()) {
                abortedIteration = true
                break
            }
            if (elapsed > budget / 2) break
            depth += 1
        }

        if (bestMoves.isEmpty()) {
            // 한 반복도 못 마쳤다(곧바로 취소) — 계약대로 첫 합법 수.
            return ReversiAIDecision(legal[0], 0, false, 0, listOf(legal[0]), nodes, elapsed, true)
        }
        val tied = bestMoves.sorted()
        val chosen = tied.randomElement(rng) ?: tied[0]
        return ReversiAIDecision(chosen, bestScore, exact, completedDepth, tied, nodes, elapsed, abortedIteration)
    }

    // MARK: 중반 탐색

    /** negamax 알파베타(fail-soft). `moves` = 두는 쪽(own)의 합법 수(부르는 쪽이 이미 셌다). */
    private fun search(own: ULong, opp: ULong, moves: ULong, depth: Int, alpha: Int, beta: Int, ply: Int): Int {
        tick()
        if (aborted) return 0
        if (moves == 0uL) {
            val replies = ReversiBits.moves(opp, own)
            if (replies == 0uL) return terminal(own, opp)
            // 패스 — 한 마디지만 깊이는 쓰지 않는다.
            return -search(opp, own, replies, depth, -beta, -alpha, ply + 1)
        }
        if (depth <= 0) {
            horizonHit = true
            return evaluate(own, opp, moves)
        }
        val count = generate(own, opp, moves, ply)
        val base = ply * slots
        var best = -infinity
        var bestSquare = -1
        var floor = alpha
        for (offset in 0 until count) {
            val slot = base + offset
            val square = moveSquare[slot]
            val flipped = moveFlips[slot].toULong()
            val newOwn = own or flipped or (1uL shl square)
            val newOpp = opp and flipped.inv()
            val value = -search(newOpp, newOwn, moveReply[slot].toULong(), depth - 1, -beta, -floor, ply + 1)
            if (aborted) return 0
            if (value > best) {
                best = value
                bestSquare = square
                if (value > floor) {
                    floor = value
                    if (floor >= beta) break
                }
            }
        }
        remember(own, opp, bestSquare)
        return best
    }

    // MARK: 종반 완전 탐색

    /** 판 끝까지 읽은 최종 WOF 점수 차(두는 쪽 시점). fail-soft 알파베타. */
    private fun solve(own: ULong, opp: ULong, moves: ULong, alpha: Int, beta: Int, ply: Int): Int {
        tick()
        if (aborted) return 0
        if (moves == 0uL) {
            val replies = ReversiBits.moves(opp, own)
            if (replies == 0uL) return finalDiff(own, opp)
            return -solve(opp, own, replies, -beta, -alpha, ply + 1)
        }
        val empties = 64 - (own or opp).countOneBits()
        if (empties == 1) {
            // 마지막 빈칸에 둔다 — 판이 가득 차 끝난다.
            val square = moves.countTrailingZeroBits()
            val flipped = ReversiBits.flips(own, opp, square)
            return finalDiff(own or flipped or (1uL shl square), opp and flipped.inv())
        }
        var best = -infinity
        var floor = alpha
        if (empties > solveSortEmpties) {
            val count = generate(own, opp, moves, ply)
            val base = ply * slots
            var bestSquare = -1
            for (offset in 0 until count) {
                val slot = base + offset
                val square = moveSquare[slot]
                val flipped = moveFlips[slot].toULong()
                val value = -solve(opp and flipped.inv(), own or flipped or (1uL shl square), moveReply[slot].toULong(), -beta, -floor, ply + 1)
                if (aborted) return 0
                if (value > best) {
                    best = value
                    bestSquare = square
                    if (value > floor) {
                        floor = value
                        if (floor >= beta) break
                    }
                }
            }
            remember(own, opp, bestSquare)
            return best
        }
        var rest = moves
        while (rest != 0uL) {
            val square = rest.countTrailingZeroBits()
            rest = rest and (rest - 1uL)
            val flipped = ReversiBits.flips(own, opp, square)
            val newOwn = own or flipped or (1uL shl square)
            val newOpp = opp and flipped.inv()
            val value = -solve(newOpp, newOwn, ReversiBits.moves(newOpp, newOwn), -beta, -floor, ply + 1)
            if (aborted) return 0
            if (value > best) {
                best = value
                if (value > floor) {
                    floor = value
                    if (floor >= beta) break
                }
            }
        }
        return best
    }

    // MARK: 수 정렬

    /**
     * `ply` 칸에 수 목록을 정렬해 채우고 개수를 낸다. 열쇠가 작을수록 먼저:
     * 모서리(상대 이동성) → 직전 최선 → 그 밖(상대 이동성 × 256 − 칸 가중치).
     */
    private fun generate(own: ULong, opp: ULong, moves: ULong, ply: Int): Int {
        val base = ply * slots
        val hint = recalled(own, opp)
        var count = 0
        var rest = moves
        while (rest != 0uL) {
            val square = rest.countTrailingZeroBits()
            rest = rest and (rest - 1uL)
            val placed = 1uL shl square
            val flipped = ReversiBits.flips(own, opp, square)
            val newOwn = own or flipped or placed
            val newOpp = opp and flipped.inv()
            val reply = ReversiBits.moves(newOpp, newOwn)
            val mobility = reply.countOneBits()
            val key = when {
                placed and ReversiAIEval.cornerMask != 0uL -> mobility
                square == hint -> 1_000
                else -> 2_000 + mobility * 256 - ReversiAIEval.weightArray[square]
            }
            // 넣으면서 정렬(삽입 정렬 — 목록이 짧다). 같은 열쇠는 들어온 순서(idx 오름차순)를 지킨다.
            var position = base + count
            while (position > base && moveKey[position - 1] > key) {
                moveSquare[position] = moveSquare[position - 1]
                moveKey[position] = moveKey[position - 1]
                moveFlips[position] = moveFlips[position - 1]
                moveReply[position] = moveReply[position - 1]
                position -= 1
            }
            moveSquare[position] = square
            moveKey[position] = key
            moveFlips[position] = flipped.toLong()
            moveReply[position] = reply.toLong()
            count += 1
        }
        return count
    }

    private fun slotIndex(own: ULong, opp: ULong): Int {
        var hash = (own * 0x9E37_79B9_7F4A_7C15uL) xor (opp * 0xC2B2_AE3D_27D4_EB4FuL)
        hash = hash xor (hash shr 31)
        return (hash and ttMask).toInt()
    }

    private fun remember(own: ULong, opp: ULong, square: Int) {
        if (square < 0) return
        val slot = slotIndex(own, opp)
        ttOwn[slot] = own.toLong()
        ttOpp[slot] = opp.toLong()
        ttMove[slot] = square.toByte()
    }

    private fun recalled(own: ULong, opp: ULong): Int {
        val slot = slotIndex(own, opp)
        if (ttOwn[slot] != own.toLong() || ttOpp[slot] != opp.toLong()) return -1
        return ttMove[slot].toInt()
    }
}
