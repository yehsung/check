// 원본: Sources/CheckCore/GomokuAIEngine.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuRenjuProbe
import kotlin.time.Duration
import kotlin.time.TimeMark
import kotlin.time.TimeSource

// 오목 AI 탐색 엔진 본체. 공개 입구는 GomokuAI.kt 의 `GomokuAI.bestMove` 하나다. 설계: docs/plan/gomoku-ai.md §2.
//
// 판 표현: 15×15 판을 사방 5칸씩 벽(3)으로 두른 25×25 배열. 칸 값 0 빈칸 · 1 흑 · 2 백 · 3 벽. 방향: 가로(+1) · 세로(+25) · /(+26) · \(−24).
// 줄 모양 표(증분 평가의 핵심): 빈칸 p 에 색 c 가 **둔다면** 방향 d 에서 어떤 모양인가를 p 양옆 5칸씩(3^10)으로 미리 계산한다.
// 흑의 5목은 **정확히 5**(장목은 5목이 아니다). 흑 후보의 금수 여부는 [GomokuRenjuProbe](= GomokuRules 판정기 그대로)로 묻는다.
// 탐색: 즉결(5목 · 상대 4 막기 · 열린 4) → 내 VCF → 상대 VCF 끊기 → 반복 심화 네가맥스 알파베타. 루트에서 점수가 **정확히 같은**
// 최선의 수들을 모아 씨앗 무작위로 하나 고른다(SwiftRandom — Swift randomElement 와 같은 알고리즘).
//
// Kotlin 이식 메모:
//  · Swift UInt64 해시·Zobrist 는 Long 비트로 든다(XOR·감김 곱셈은 부호와 무관하게 같은 비트, 슬롯은 아래 비트만 쓴다).
//  · 시간은 주입한 [TimeSource](기본 단조 시계 — 벽시계가 아니다)로 잰다. 시험은 넉넉한 예산 + 깊이 한도로 결정적으로 돈다.
//  · Swift 의 `sort`/`sorted` 는 안정 정렬이다 — Kotlin `sortedWith`(TimSort)도 안정이라 동점의 순서가 같다(골든 `renju/ai-trace` 가 잰다).

internal object GomokuAIShape {
    const val none = 0
    const val two = 1
    const val openTwo = 2
    const val three = 3
    const val openThree = 4
    const val four = 5
    const val openFour = 6
    const val five = 7
}

/** 네 방향 모양을 합친 칸의 위협 등급. */
internal object GomokuAICategory {
    const val none = 0
    const val weak = 1
    const val building = 2
    const val openThree = 3
    const val four = 4
    const val doubleThree = 5
    const val fourThree = 6
    /** 열린 4 또는 4-4(흑이면 금수일 수 있다 — 합법 확인은 따로). */
    const val openFour = 7
    const val five = 8
}

internal object GomokuAITables {
    const val keyCount = 59_049 // 3^10

    /** 흑(정확히 5) · 백(5 이상) 줄 모양 표. 읽기 전용으로 엔진들이 나눠 쓴다. */
    val blackShapes: ByteArray = buildShapes(exactFive = true)
    val whiteShapes: ByteArray = buildShapes(exactFive = false)

    /** 네 방향 모양(각 3비트) → 등급 · 칸 점수. */
    val comboCategories: ByteArray
    val comboValues: IntArray

    init {
        val built = buildCombos()
        comboCategories = built.first
        comboValues = built.second
    }

    /** Zobrist 키: [패딩 칸 625 × 색 2] + 백 차례 키. 고정 씨앗이라 실행마다 같다(Swift UInt64 → Long 비트). */
    val zobrist: LongArray = run {
        val rng = SplitMix64(0x6F6D_6F6B_7541_4921uL)
        LongArray(625 * 2 + 1) { rng.next().toLong() }
    }

    private fun isFive(line: IntArray, exact: Boolean): Boolean {
        var run = 1
        var j = 4
        while (j >= 0 && line[j] == 1) { run += 1; j -= 1 }
        j = 6
        while (j <= 10 && line[j] == 1) { run += 1; j += 1 }
        return if (exact) run == 5 else run >= 5
    }

    /** 칸(가운데, 이미 내 돌)을 지나는 한 줄의 모양. 자식(빈칸 하나에 내 돌을 더한 줄)은 내 돌이 하나 더 많아 먼저 계산돼 있다. */
    private fun buildShapes(exactFive: Boolean): ByteArray {
        val pow3 = IntArray(10) { 1 }
        for (i in 1 until 10) pow3[i] = pow3[i - 1] * 3
        val buckets = Array(11) { ArrayList<Int>() }
        for (key in 0 until keyCount) {
            var k = key
            var ones = 0
            repeat(10) {
                if (k % 3 == 1) ones += 1
                k /= 3
            }
            buckets[ones].add(key)
        }
        val table = ByteArray(keyCount)
        val line = IntArray(11)
        for (ones in 10 downTo 0) {
            for (key in buckets[ones]) {
                var k = key
                for (i in 0 until 10) {
                    line[if (i < 5) i else i + 1] = k % 3
                    k /= 3
                }
                line[5] = 1
                if (isFive(line, exactFive)) {
                    table[key] = GomokuAIShape.five.toByte()
                    continue
                }
                // 5목 자리: 가운데를 포함하는 5목은 ±4 안에 있다.
                var winPoints = 0
                for (q in 1..9) {
                    if (q == 5 || line[q] != 0) continue
                    line[q] = 1
                    if (isFive(line, exactFive)) winPoints += 1
                    line[q] = 0
                }
                if (winPoints >= 2) { table[key] = GomokuAIShape.openFour.toByte(); continue }
                if (winPoints == 1) { table[key] = GomokuAIShape.four.toByte(); continue }
                var best = GomokuAIShape.none
                for (q in 1..9) {
                    if (q == 5 || line[q] != 0) continue
                    when (table[key + pow3[if (q < 5) q else q - 1]].toInt()) {
                        GomokuAIShape.openFour -> best = maxOf(best, GomokuAIShape.openThree)
                        GomokuAIShape.four -> best = maxOf(best, GomokuAIShape.three)
                        GomokuAIShape.openThree -> best = maxOf(best, GomokuAIShape.openTwo)
                        GomokuAIShape.three -> best = maxOf(best, GomokuAIShape.two)
                        else -> Unit
                    }
                }
                table[key] = best.toByte()
            }
        }
        return table
    }

    private fun buildCombos(): Pair<ByteArray, IntArray> {
        // 방향 하나의 모양 점수(내가 거기 두면 얻는 잠재력).
        val dirValue = intArrayOf(0, 8, 40, 50, 450, 520, 6_000, 60_000)
        val categories = ByteArray(4096)
        val values = IntArray(4096)
        for (index in 0 until 4096) {
            val shapes = intArrayOf((index shr 9) and 7, (index shr 6) and 7, (index shr 3) and 7, index and 7)
            val n = IntArray(8)
            var value = 0
            for (s in shapes) {
                n[s] += 1
                value += dirValue[s]
            }
            val category: Int
            if (n[7] > 0) {
                category = GomokuAICategory.five
            } else if (n[6] > 0 || n[5] >= 2) {
                category = GomokuAICategory.openFour
                value += 5_000
            } else if (n[5] == 1 && n[4] >= 1) {
                category = GomokuAICategory.fourThree
                value += 4_000
            } else if (n[4] >= 2) {
                category = GomokuAICategory.doubleThree
                value += 2_000
            } else if (n[5] == 1) {
                category = GomokuAICategory.four
                if (n[3] + n[2] >= 1) value += 150
            } else if (n[4] == 1) {
                category = GomokuAICategory.openThree
                if (n[3] + n[2] >= 1) value += 300
            } else if (n[3] + n[2] >= 1) {
                category = GomokuAICategory.building
                if (n[3] + n[2] >= 2) value += 120
            } else if (n[1] >= 1) {
                category = GomokuAICategory.weak
            } else {
                category = GomokuAICategory.none
            }
            categories[index] = category.toByte()
            values[index] = value
        }
        return categories to values
    }
}

/** [GomokuAIEngine.generate] 의 결과(Swift 튜플 `(count, forced, immediate)`). */
internal class GomokuAIGenerated(val count: Int, val forced: Boolean, val immediate: Int?)

/** 공격자 주변 5목 자리 셈(Swift 튜플 `(count, first)`). */
private class GomokuFivePoints(val count: Int, val first: Int)

internal class GomokuAIEngine(
    board: GomokuBoard,
    private val budget: Duration,
    private val isCancelled: () -> Boolean,
    timeSource: TimeSource = TimeSource.Monotonic,
) {
    // 판 상태
    private val cells = ByteArray(cellCount) { 3 }
    private val shapes = ByteArray(cellCount * 8) // p*8 + c*4 + d
    private val categories = ByteArray(cellCount * 2) // p*2 + c
    private val values = IntArray(cellCount * 2) // p*2 + c
    private val neighbors = IntArray(cellCount) // 반경 2 안 돌 수
    private val blackTable = GomokuAITables.blackShapes
    private val whiteTable = GomokuAITables.whiteShapes
    private val comboCategories = GomokuAITables.comboCategories
    private val comboValues = GomokuAITables.comboValues
    private val zobrist = GomokuAITables.zobrist
    private var sums0 = 0
    private var sums1 = 0
    /** 색별 돌의 중앙 가까움 합(고리 0…7). 줄 모양 점수가 같은 수끼리를 가르는 작은 항. */
    private var centrality0 = 0
    private var centrality1 = 0
    var hash: Long = 0L
        private set
    var stones = 0
        private set
    private var minX = 15
    private var maxX = -1
    private var minY = 15
    private var maxY = -1
    private val boxStack = IntArray(226 * 4) // stones*4
    private val probe: GomokuRenjuProbe = GomokuRenjuProbe(board)
    private val legalCache = HashMap<Long, Boolean>()

    // 탐색 상태
    private val started: TimeMark = timeSource.markNow()
    var aborted = false
        private set
    var nodes = 0
        private set
    private val ttKey = LongArray(1 shl ttBits)
    private val ttScore = IntArray(1 shl ttBits)
    private val ttDepth = IntArray(1 shl ttBits) { -1 }
    private val ttFlag = ByteArray(1 shl ttBits)
    private val ttMove = IntArray(1 shl ttBits) { -1 }
    private val ttMask = (1 shl ttBits) - 1
    private val moveBuffer = IntArray(maxPly * 225) // ply*225
    private val priorityBuffer = IntArray(maxPly * 225)
    /** VCF 실패 기억: 국면(+공격자) → 실패가 확정된 최대 깊이. 예산에 걸려 끊긴 실패는 적지 않는다. */
    private val vcfFailures = HashMap<Long, Int>()
    private var vcfBudget = 0
    private var vcfBudgetHit = false
    /** 탐색이 끝까지 마친 가장 깊은 반복 심화 깊이(측정·보고용). */
    var completedDepth = 0
        private set

    init {
        for (y in 0 until 15) for (x in 0 until 15) cells[index(x, y)] = 0
        for (y in 0 until 15) {
            for (x in 0 until 15) {
                val point = GomokuPoint.at(x, y) ?: continue
                val color = board[point] ?: continue
                val p = index(x, y)
                val value = if (color == GomokuColor.black) 1 else 2
                cells[p] = value.toByte()
                hash = hash xor zobrist[p * 2 + value - 1]
                stones += 1
                if (value == 1) centrality0 += ring(x, y) else centrality1 += ring(x, y)
                minX = minOf(minX, x); maxX = maxOf(maxX, x); minY = minOf(minY, y); maxY = maxOf(maxY, y)
                for (dy in -2..2) for (dx in -2..2) neighbors[p + dy * width + dx] += 1
            }
        }
        for (y in 0 until 15) {
            for (x in 0 until 15) {
                val p = index(x, y)
                if (cells[p].toInt() != 0) continue
                for (d in 0 until 4) refreshDirection(p, d)
                refreshCombo(p)
            }
        }
    }

    private fun delta(d: Int): Int = when (d) {
        0 -> 1
        1 -> 25
        2 -> 26
        else -> -24
    }

    // MARK: 증분 갱신

    private fun refreshDirection(p: Int, d: Int) {
        val step = delta(d)
        var blackKey = 0
        var whiteKey = 0
        var multiplier = 1
        var q = p - 5 * step
        for (i in 0 until 11) {
            if (i != 5) {
                when (cells[q].toInt()) {
                    1 -> { blackKey += multiplier; whiteKey += 2 * multiplier }
                    2 -> { blackKey += 2 * multiplier; whiteKey += multiplier }
                    3 -> { blackKey += 2 * multiplier; whiteKey += 2 * multiplier }
                    else -> Unit
                }
                multiplier *= 3
            }
            q += step
        }
        shapes[p * 8 + d] = blackTable[blackKey]
        shapes[p * 8 + 4 + d] = whiteTable[whiteKey]
    }

    private fun refreshCombo(p: Int) {
        for (c in 0 until 2) {
            val base = p * 8 + c * 4
            val combo = (shapes[base].toInt() shl 9) or (shapes[base + 1].toInt() shl 6) or
                (shapes[base + 2].toInt() shl 3) or shapes[base + 3].toInt()
            val newValue = comboValues[combo]
            val delta = newValue - values[p * 2 + c]
            if (c == 0) sums0 += delta else sums1 += delta
            values[p * 2 + c] = newValue
            categories[p * 2 + c] = comboCategories[combo]
        }
    }

    fun make(p: Int, color: Int) {
        val base = stones * 4
        boxStack[base] = minX; boxStack[base + 1] = maxX
        boxStack[base + 2] = minY; boxStack[base + 3] = maxY
        cells[p] = color.toByte()
        hash = hash xor zobrist[p * 2 + color - 1]
        val x = p % width - 5
        val y = p / width - 5
        probe.setCell(x, y, if (color == 1) GomokuColor.black else GomokuColor.white)
        stones += 1
        if (color == 1) centrality0 += ring(x, y) else centrality1 += ring(x, y)
        minX = minOf(minX, x); maxX = maxOf(maxX, x); minY = minOf(minY, y); maxY = maxOf(maxY, y)
        sums0 -= values[p * 2]; sums1 -= values[p * 2 + 1]
        values[p * 2] = 0; values[p * 2 + 1] = 0
        categories[p * 2] = 0; categories[p * 2 + 1] = 0
        for (dy in -2..2) for (dx in -2..2) neighbors[p + dy * width + dx] += 1
        for (d in 0 until 4) {
            val step = delta(d)
            var q = p - 5 * step
            for (k in -5..5) {
                if (k != 0 && cells[q].toInt() == 0) {
                    refreshDirection(q, d)
                    refreshCombo(q)
                }
                q += step
            }
        }
    }

    fun unmake(p: Int) {
        val color = cells[p].toInt()
        cells[p] = 0
        hash = hash xor zobrist[p * 2 + color - 1]
        val x = p % width - 5
        val y = p / width - 5
        probe.setCell(x, y, null)
        stones -= 1
        if (color == 1) centrality0 -= ring(x, y) else centrality1 -= ring(x, y)
        val base = stones * 4
        minX = boxStack[base]; maxX = boxStack[base + 1]
        minY = boxStack[base + 2]; maxY = boxStack[base + 3]
        for (dy in -2..2) for (dx in -2..2) neighbors[p + dy * width + dx] -= 1
        for (d in 0 until 4) refreshDirection(p, d)
        refreshCombo(p)
        for (d in 0 until 4) {
            val step = delta(d)
            var q = p - 5 * step
            for (k in -5..5) {
                if (k != 0 && cells[q].toInt() == 0) {
                    refreshDirection(q, d)
                    refreshCombo(q)
                }
                q += step
            }
        }
    }

    // MARK: 조회

    fun category(p: Int, color: Int): Int = categories[p * 2 + color - 1].toInt()
    fun value(p: Int, color: Int): Int = values[p * 2 + color - 1]
    fun isEmpty(p: Int): Boolean = cells[p].toInt() == 0

    /** 이 칸에 두면 어느 방향이든 4(또는 열린 4·5목)가 되는가. */
    fun makesFour(p: Int, color: Int): Boolean {
        val base = p * 8 + (color - 1) * 4
        return shapes[base] >= GomokuAIShape.four || shapes[base + 1] >= GomokuAIShape.four ||
            shapes[base + 2] >= GomokuAIShape.four || shapes[base + 3] >= GomokuAIShape.four
    }

    /** 색 `color` 가 빈칸 p 에 둘 수 있는가. 백은 언제나. 흑은 렌주 판정(5목은 합법, 금수·예산 초과는 불법). */
    fun isLegal(p: Int, color: Int): Boolean {
        if (color != 1) return true
        if (categories[p * 2].toInt() == GomokuAICategory.five) return true
        // 걸러내기: 금수는 적어도 두 방향에 흑이 둘 이상이거나, 한 방향에 셋 이상이거나, ±5 안에 흑이 다섯 이상일 때만 생긴다.
        var directionsWithTwo = 0
        var needsJudge = false
        for (d in 0 until 4) {
            val step = delta(d)
            var near = 0
            var wide = 0
            for (k in 1..5) {
                if (cells[p + k * step].toInt() == 1) { wide += 1; if (k <= 4) near += 1 }
                if (cells[p - k * step].toInt() == 1) { wide += 1; if (k <= 4) near += 1 }
            }
            if (near >= 3 || wide >= 5) { needsJudge = true; break }
            if (near >= 2) directionsWithTwo += 1
        }
        if (!needsJudge && directionsWithTwo < 2) return true
        val key = hash xor (p.toLong() * GOLDEN_GAMMA)
        legalCache[key]?.let { return it }
        val legal = when (probe.blackJudgement(p % width - 5, p / width - 5)) {
            GomokuJudgement.Legal, GomokuJudgement.Win -> true
            else -> false
        }
        if (legalCache.size > 200_000) legalCache.clear()
        legalCache[key] = legal
        return legal
    }

    /** 탐색할 만한 빈칸(돌 반경 2 안). `body` 가 false 를 내면 멈춘다. */
    private inline fun forEachCandidate(body: (Int) -> Boolean) {
        if (stones <= 0) return
        val x0 = maxOf(0, minX - 2)
        val x1 = minOf(14, maxX + 2)
        val y0 = maxOf(0, minY - 2)
        val y1 = minOf(14, maxY + 2)
        for (y in y0..y1) {
            var p = index(x0, y)
            repeat(x1 - x0 + 1) {
                if (cells[p].toInt() == 0 && neighbors[p] > 0) {
                    if (!body(p)) return
                }
                p += 1
            }
        }
    }

    /** 판 전체 빈칸 중 합법인 첫 칸(돌 반경 밖 포함). 둘 곳이 하나도 없으면 null. */
    fun anyLegalCell(color: Int): Int? {
        for (y in 0 until 15) {
            for (x in 0 until 15) {
                val p = index(x, y)
                if (cells[p].toInt() == 0 && isLegal(p, color)) return p
            }
        }
        return null
    }

    // MARK: 시간

    private fun tick() {
        nodes += 1
        if (nodes and 255 == 0) {
            if (started.elapsedNow() >= budget || isCancelled()) aborted = true
        }
    }

    fun checkAbortNow(): Boolean {
        if (!aborted && (started.elapsedNow() >= budget || isCancelled())) aborted = true
        return aborted
    }

    val elapsedFraction: Double
        get() {
            val total = budget.inWholeNanoseconds.toDouble()
            val used = started.elapsedNow().inWholeNanoseconds.toDouble()
            return if (total > 0) used / total else 1.0
        }

    // MARK: VCF

    /** 공격자가 두면 막 생긴 5목 자리들(착수 m 을 지나는 네 줄에서만 찾는다). 최대 2개까지 센다. */
    private fun fivePoints(m: Int, color: Int): GomokuFivePoints {
        var count = 0
        var first = -1
        for (d in 0 until 4) {
            val step = delta(d)
            var q = m - 4 * step
            for (k in -4..4) {
                if (k != 0 && cells[q].toInt() == 0 && categories[q * 2 + color - 1].toInt() == GomokuAICategory.five && q != first) {
                    if (first < 0) first = q
                    count += 1
                    if (count >= 2) return GomokuFivePoints(count, first)
                }
                q += step
            }
        }
        return GomokuFivePoints(count, first)
    }

    /** 판 전체에서 색 `color` 의 5목 자리(최대 2개). */
    private fun globalFivePoints(color: Int): GomokuFivePoints {
        var count = 0
        var first = -1
        forEachCandidate { p ->
            if (categories[p * 2 + color - 1].toInt() == GomokuAICategory.five) {
                if (first < 0) first = p
                count += 1
            }
            count < 2
        }
        return GomokuFivePoints(count, first)
    }

    /** 공격자 차례에서 4만 연달아 두어 이기는 수순이 있는가. 있으면 첫 수(패딩 인덱스)를 돌려준다. */
    fun vcfMove(attacker: Int, depth: Int, lastDefenderMove: Int?): Int? {
        tick()
        if (aborted || vcfBudget <= 0) { vcfBudgetHit = true; return null }
        vcfBudget -= 1
        val defender = 3 - attacker
        val memoKey = hash xor (if (attacker == 2) zobrist[625 * 2] else 0L) xor VCF_SALT
        val failedDepth = vcfFailures[memoKey]
        if (failedDepth != null && failedDepth >= depth) return null

        if (lastDefenderMove == null) {
            val own = globalFivePoints(attacker)
            if (own.count > 0) return own.first
        }
        val defenderFives = if (lastDefenderMove != null) fivePoints(lastDefenderMove, defender) else globalFivePoints(defender)
        if (defenderFives.count >= 2) return null

        val candidates = ArrayList<Int>()
        if (defenderFives.count == 1) {
            val block = defenderFives.first
            if (!(makesFour(block, attacker) && isLegal(block, attacker))) return null
            candidates.add(block)
        } else {
            forEachCandidate { p ->
                if (makesFour(p, attacker)) candidates.add(p)
                true
            }
            for (p in candidates) {
                if (categories[p * 2 + attacker - 1].toInt() == GomokuAICategory.openFour && isLegal(p, attacker)) return p
            }
        }
        if (depth <= 0) return null
        val sorted = candidates.sortedWith { a, b -> compareDescending(value(a, attacker), value(b, attacker)) }
        val hitBefore = vcfBudgetHit
        vcfBudgetHit = false
        for (m in sorted) {
            if (!isLegal(m, attacker)) continue
            if (defenderFives.count == 0 && categories[m * 2 + attacker - 1].toInt() == GomokuAICategory.openFour) return m
            make(m, attacker)
            val points = fivePoints(m, attacker)
            if (points.count >= 2) { unmake(m); vcfBudgetHit = hitBefore || vcfBudgetHit; return m }
            if (points.count == 0) { unmake(m); continue }
            val block = points.first
            if (defender == 1 && !isLegal(block, 1)) { unmake(m); vcfBudgetHit = hitBefore || vcfBudgetHit; return m }
            make(block, defender)
            val found = vcfMove(attacker, depth - 1, block) != null
            unmake(block)
            unmake(m)
            if (found) { vcfBudgetHit = hitBefore || vcfBudgetHit; return m }
            if (aborted) break
        }
        if (!vcfBudgetHit && !aborted) {
            if (vcfFailures.size > 300_000) vcfFailures.clear()
            vcfFailures[memoKey] = maxOf(depth, vcfFailures[memoKey] ?: -1)
        }
        vcfBudgetHit = hitBefore || vcfBudgetHit
        return null
    }

    fun hasVCF(attacker: Int, depth: Int = 12, budget: Int): Boolean {
        vcfBudget = budget
        vcfBudgetHit = false
        return vcfMove(attacker, depth, null) != null
    }

    // MARK: 알파베타

    private fun evaluate(side: Int, ply: Int): Int {
        val opponent = 3 - side
        // 잎 VCF: 두는 쪽이 4 로 몰아 이길 수 있으면 이긴 국면으로 본다(작은 예산).
        var hasFour = false
        forEachCandidate { p ->
            if (makesFour(p, side)) { hasFour = true; false } else true
        }
        if (hasFour) {
            vcfBudget = 120
            vcfBudgetHit = false
            if (vcfMove(side, 8, null) != null) return win - (ply + 20)
        }
        val mine = (if (side == 1) sums0 else sums1) + centralityWeight * (if (side == 1) centrality0 else centrality1)
        val theirs = (if (opponent == 1) sums0 else sums1) + centralityWeight * (if (opponent == 1) centrality0 else centrality1)
        return mine - theirs
    }

    private fun toTT(score: Int, ply: Int): Int = when {
        score > win - 1000 -> score + ply
        score < -(win - 1000) -> score - ply
        else -> score
    }

    private fun fromTT(score: Int, ply: Int): Int = when {
        score > win - 1000 -> score - ply
        score < -(win - 1000) -> score + ply
        else -> score
    }

    /** 위협 규칙으로 후보를 모은다. 후보는 moveBuffer[ply*225 …] 에 우선순위 내림차순으로 들어간다. */
    fun generate(side: Int, ply: Int, @Suppress("UNUSED_PARAMETER") depth: Int, limit: Int): GomokuAIGenerated {
        val opponent = 3 - side
        val so = side - 1
        val oo = opponent - 1
        var oppFiveCount = 0
        var oppFive = -1
        var ownFive = false
        val ownOpenFour = ArrayList<Int>()
        val oppOpenFour = ArrayList<Int>()
        forEachCandidate { p ->
            val mine = categories[p * 2 + so].toInt()
            val theirs = categories[p * 2 + oo].toInt()
            if (mine == GomokuAICategory.five) {
                ownFive = true
                return@forEachCandidate false
            }
            if (theirs == GomokuAICategory.five) {
                if (oppFive != p) oppFiveCount += 1
                if (oppFive < 0) oppFive = p
            }
            if (mine == GomokuAICategory.openFour) ownOpenFour.add(p)
            if (theirs == GomokuAICategory.openFour) oppOpenFour.add(p)
            true
        }
        val base = ply * 225
        if (ownFive) return GomokuAIGenerated(0, false, win - (ply + 1))
        if (oppFiveCount >= 2) return GomokuAIGenerated(0, false, -(win - (ply + 2)))
        if (oppFiveCount == 1) {
            if (side == 1 && !isLegal(oppFive, 1)) return GomokuAIGenerated(0, false, -(win - (ply + 2)))
            moveBuffer[base] = oppFive
            return GomokuAIGenerated(1, true, null)
        }
        for (p in ownOpenFour) if (isLegal(p, side)) return GomokuAIGenerated(0, false, win - (ply + 3))

        val threatened = oppOpenFour.any { isLegal(it, opponent) }
        var count = 0
        val cap = if (threatened) 225 else limit
        forEachCandidate { p ->
            if (threatened) {
                val theirs = categories[p * 2 + oo].toInt()
                if (!(makesFour(p, side) || makesFour(p, opponent) || theirs >= GomokuAICategory.doubleThree)) {
                    return@forEachCandidate true
                }
            }
            val priority = values[p * 2 + so] + values[p * 2 + oo]
            // 상위 cap 개만 우선순위 내림차순으로 유지(삽입 정렬).
            var i = count
            if (count < cap) {
                count += 1
            } else if (priority <= priorityBuffer[base + cap - 1]) {
                return@forEachCandidate true
            } else {
                i = cap - 1
            }
            while (i > 0 && priorityBuffer[base + i - 1] < priority) {
                moveBuffer[base + i] = moveBuffer[base + i - 1]
                priorityBuffer[base + i] = priorityBuffer[base + i - 1]
                i -= 1
            }
            moveBuffer[base + i] = p
            priorityBuffer[base + i] = priority
            true
        }
        return GomokuAIGenerated(count, false, null)
    }

    private fun branching(depth: Int): Int = when {
        depth >= 6 -> 7
        depth >= 4 -> 9
        depth >= 2 -> 12
        else -> 16
    }

    fun negamax(depth: Int, alphaIn: Int, betaIn: Int, ply: Int, side: Int): Int {
        tick()
        if (aborted) return 0
        if (ply >= maxPly - 1) return evaluate(side, ply)
        var alpha = alphaIn
        var beta = betaIn
        val key = hash xor (if (side == 2) zobrist[625 * 2] else 0L)
        val slot = key.toInt() and ttMask
        var ttMoveHere = -1
        if (ttKey[slot] == key) {
            ttMoveHere = ttMove[slot]
            if (ttDepth[slot] >= depth) {
                val score = fromTT(ttScore[slot], ply)
                when (ttFlag[slot].toInt()) {
                    1 -> return score
                    2 -> alpha = maxOf(alpha, score)
                    3 -> beta = minOf(beta, score)
                    else -> Unit
                }
                if (alpha >= beta) return score
            }
        }

        val generated = generate(side, ply, depth, branching(depth))
        generated.immediate?.let { return it }
        if (!generated.forced && depth <= 0) return evaluate(side, ply)
        val base = ply * 225
        val count = generated.count
        if (count == 0) return evaluate(side, ply)
        if (ttMoveHere >= 0) {
            for (i in 0 until count) {
                if (moveBuffer[base + i] != ttMoveHere) continue
                if (i > 0) {
                    val moved = moveBuffer[base + i]
                    var j = i
                    while (j > 0) { moveBuffer[base + j] = moveBuffer[base + j - 1]; j -= 1 }
                    moveBuffer[base] = moved
                }
                break
            }
        }
        val opponent = 3 - side
        val childDepth = if (generated.forced) depth else depth - 1
        var best = -infinity
        var bestMove = -1
        for (i in 0 until count) {
            val m = moveBuffer[base + i]
            if (!isLegal(m, side)) continue
            make(m, side)
            val score = -negamax(childDepth, -beta, -alpha, ply + 1, opponent)
            unmake(m)
            if (aborted) return 0
            if (score > best) {
                best = score
                bestMove = m
                if (score > alpha) {
                    alpha = score
                    if (alpha >= beta) break
                }
            }
        }
        if (bestMove < 0) return evaluate(side, ply)
        val flag = if (best <= alphaIn) 3 else if (best >= betaIn) 2 else 1
        if (ttKey[slot] != key || ttDepth[slot] <= depth) {
            ttKey[slot] = key
            ttScore[slot] = toTT(best, ply)
            ttDepth[slot] = depth.toShort().toInt()
            ttFlag[slot] = flag.toByte()
            ttMove[slot] = bestMove.toShort().toInt()
        }
        return best
    }

    // MARK: 루트

    /** 루트 결정. 반환은 패딩 인덱스(null = 둘 곳 없음). */
    fun chooseMove(side: Int, maxDepth: Int, rng: SwiftRandomSource): Int? {
        val opponent = 3 - side
        val near = ArrayList<Int>()
        forEachCandidate { p -> near.add(p); true }

        // 1) 내 5목.
        val ownFives = near.filter { category(it, side) == GomokuAICategory.five }
        if (ownFives.isNotEmpty()) return ownFives.randomElement(rng)
        // 2) 상대 5목 자리 막기(둘 이상이면 이미 진 판 — 합법인 하나라도 막는다).
        val opponentFives = near.filter { category(it, opponent) == GomokuAICategory.five }
        if (opponentFives.isNotEmpty()) {
            val blocks = opponentFives.filter { isLegal(it, side) }
            val block = pickBest(blocks, side, rng)
            if (block != null) return block
        }
        // 3) 내 열린 4 · 4-4(합법).
        if (opponentFives.isEmpty()) {
            val openFours = near.filter { category(it, side) == GomokuAICategory.openFour && isLegal(it, side) }
            if (openFours.isNotEmpty()) return openFours.randomElement(rng)
        }
        val legalNear = near.filter { isLegal(it, side) }
        if (legalNear.isEmpty()) return anyLegalCell(side)
        val fallback = pickBest(legalNear, side, rng)
        if (checkAbortNow()) return fallback

        // 4) 내 VCF.
        if (opponentFives.isEmpty()) {
            vcfBudget = 30_000
            vcfBudgetHit = false
            val move = vcfMove(side, 16, null)
            if (move != null && isLegal(move, side)) return move
            if (checkAbortNow()) return fallback
        }

        // 5) 상대 VCF 가 있으면 그것을 끊는 수로 좁힌다.
        var rootMoves: List<Int> = emptyList()
        if (opponentFives.isEmpty() && hasVCF(opponent, 16, 20_000)) {
            var defenses = ArrayList<Int>()
            var pool: List<Int> = legalNear.sortedWith { a, b ->
                compareDescending(value(a, side) + value(a, opponent), value(b, side) + value(b, opponent))
            }
            if (pool.size > 40) {
                val fours = pool.subList(40, pool.size).filter { makesFour(it, side) }
                pool = pool.subList(0, 40) + fours
            }
            // 예산에 걸려 "모른다"로 끝난 수는 확인된 방어가 아니다 — 확인된 방어가 하나도 없을 때만 후보로 되살린다.
            val uncertain = ArrayList<Int>()
            for (m in pool) {
                make(m, side)
                val stillLost = hasVCF(opponent, 16, 4_000)
                val unknown = vcfBudgetHit
                unmake(m)
                if (checkAbortNow()) break
                if (!stillLost) { if (unknown) uncertain.add(m) else defenses.add(m) }
            }
            if (defenses.isEmpty()) defenses = uncertain
            if (defenses.isNotEmpty()) rootMoves = defenses
            if (aborted) return defenses.firstOrNull() ?: fallback
        }

        // 6) 반복 심화.
        if (rootMoves.isEmpty()) {
            val generated = generate(side, 0, maxDepth, 24)
            val immediate = generated.immediate
            if (immediate != null && immediate > 0) return fallback
            val collected = ArrayList<Int>()
            for (i in 0 until generated.count) {
                val m = moveBuffer[i]
                if (isLegal(m, side)) collected.add(m)
            }
            rootMoves = if (collected.isEmpty()) legalNear else collected
        } else {
            rootMoves = rootMoves.sortedWith { a, b ->
                compareDescending(value(a, side) + value(a, opponent), value(b, side) + value(b, opponent))
            }
        }
        if (rootMoves.size == 1) return rootMoves[0]

        var chosen: List<Int> = emptyList()
        var scores = IntArray(rootMoves.size) { -infinity }
        var depth = 1
        while (depth <= maxDepth) {
            var best = -infinity
            var bests = ArrayList<Int>()
            val iterationScores = IntArray(rootMoves.size) { -infinity }
            for ((i, m) in rootMoves.withIndex()) {
                make(m, side)
                var score: Int
                if (best == -infinity) {
                    score = -negamax(depth - 1, -infinity, infinity, 1, opponent)
                } else {
                    score = -negamax(depth - 1, -(best + 1), -(best - 1), 1, opponent)
                    if (!aborted && score > best) {
                        score = -negamax(depth - 1, -infinity, -best, 1, opponent)
                    }
                }
                unmake(m)
                if (aborted) break
                iterationScores[i] = score
                if (score > best) {
                    best = score
                    bests = arrayListOf(m)
                } else if (score == best) {
                    bests.add(m)
                }
            }
            if (aborted) break
            completedDepth = depth
            chosen = bests
            scores = iterationScores
            // 다음 반복은 좋은 수부터(안정 정렬).
            val order = rootMoves.indices.sortedWith { a, b -> compareDescending(scores[a], scores[b]) }
            rootMoves = order.map { rootMoves[it] }
            scores = IntArray(order.size) { scores[order[it]] }
            if (best > win - 1000 || best < -(win - 1000)) break
            if (elapsedFraction > 0.45) break
            depth += 1
        }
        if (chosen.isEmpty()) return rootMoves.firstOrNull() ?: fallback
        return chosen.randomElement(rng)
    }

    /** 우선순위(두 색 칸 점수 합) 최고인 칸, 동점이면 무작위. */
    private fun pickBest(moves: List<Int>, side: Int, rng: SwiftRandomSource): Int? {
        if (moves.isEmpty()) return null
        val opponent = 3 - side
        val top = moves.maxOf { value(it, side) + value(it, opponent) }
        return moves.filter { value(it, side) + value(it, opponent) == top }.randomElement(rng)
    }

    companion object {
        const val width = 25
        const val cellCount = 625
        const val win = 1_000_000
        const val infinity = 10_000_000
        const val maxPly = 96
        const val ttBits = 17
        const val centralityWeight = 2
        /** Swift `0x9E37_79B9_7F4A_7C15`(UInt64) 의 비트. */
        private val GOLDEN_GAMMA: Long = 0x9E3779B97F4A7C15uL.toLong()
        private const val VCF_SALT: Long = 0x5646_4346_0000_0001L

        fun index(x: Int, y: Int): Int = (y + 5) * width + x + 5

        /** 중앙(H8)에서 몇 번째 고리 안쪽인가: 7 − 체비셰프 거리. */
        fun ring(x: Int, y: Int): Int = 7 - maxOf(kotlin.math.abs(x - 7), kotlin.math.abs(y - 7))

        fun coordinates(p: Int): Pair<Int, Int> = (p % width - 5) to (p / width - 5)
    }
}

/** Swift `{ a > b }` 비교를 안정 정렬 비교자로(큰 것 먼저, 같으면 원래 순서). */
internal fun compareDescending(a: Int, b: Int): Int = b.compareTo(a)
