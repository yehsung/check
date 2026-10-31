// 원본: Sources/CheckCore/RummyRules.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason

// 아잉 큐브(내부 이름 rummy) 규칙 코어. 규칙 정본은 `rummy/research/rules.md` v1.1(R-01~R-24)이고, Swift 는 파이썬 참조 구현을 줄 단위로 옮겼으며
// 이 파일은 그 Swift 를 다시 줄 단위로 옮겼다. 기대값의 집은 `Tests/checkTests/Fixtures/rummy/cases.json`(154건)과 설계서 §2.1 P01~P10 표다 —
// 골든 `rummy/rules` 가 이 파일의 계약이다. 숫자를 고치면 서버와 갈린다.
//
// 다중집합(M·K)은 `Map<원소, 개수>` 다. 빼기는 0 아래로 내려가지 않는다(R-16) — [minus] 가 0 이하 항목을 지운다.
// 면 타입 [RummyFace]·판정 이유 [RummyTurnReason] 는 core/wire 한 벌을 쓴다(R-01 판정은 `RummyFace.of` 와 디코드가 맡는다). 그래서 [judgeTurn] 의
// malformed 는 "빈 세트"만 본다.
//
// Swift 와 다른 점: 면의 `color`·`number` 는 와이어가 `Long` 으로 들지만 1…13·0…3 이라 판정은 `Int` 로 한다.

/** 조커인가. */
val RummyFace.isJoker: Boolean get() = color == null

/** 랙에 남았을 때 값(R-22): 숫자 또는 조커 30. */
val RummyFace.rackValue: Int get() = number?.toInt() ?: 30

/** 숫자 타일. 범위 밖 값은 부르는 쪽 실수다. Swift `RummyFace(color:number:)`. */
fun RummyFace.Companion.numbered(color: Int, number: Int): RummyFace {
    require(color in 0..3 && number in 1..13) { "RummyFace 범위 밖: $color $number" }
    return RummyFace(color.toLong(), number.toLong())
}

/** R-09 비교 키 순서: 색 A < B < C < D, 같은 색은 숫자 오름차순, 조커 맨 뒤. Swift `RummyFace.<`. */
object RummyFaceOrder : Comparator<RummyFace> {
    override fun compare(a: RummyFace, b: RummyFace): Int {
        val l = a.color
        val r = b.color
        return when {
            l == null && r == null -> 0
            l == null -> 1
            r == null -> -1
            l != r -> l.compareTo(r)
            else -> (a.number ?: 0L).compareTo(b.number ?: 0L)
        }
    }
}

// MARK: - 판정 값

enum class RummyMeldKind(val rawValue: String) { run("run"), group("group") }

data class RummyMeldAnalysis(val valid: Boolean, val kind: RummyMeldKind?, val points: Int?) {
    companion object {
        val invalid = RummyMeldAnalysis(valid = false, kind = null, points = null)
    }
}

/** payouts 입력 한 자리(§2.1). */
data class RummyPayoutSeat(
    val active: Boolean,
    val score: Int,
    val tiles: Int,
    val seat: Int,
    val forfeitOrder: Int? = null,
)

/** [RummyRules.finalScores] 의 답 — 끝 점수와 승자(0-기반 자리, 오름차순). */
data class RummyFinalScores(val scores: List<Int>, val winners: List<Int>)

/** [RummyRules.payouts] 의 답. */
data class RummyPayouts(val payouts: List<Int>, val ranks: List<Int>)

// MARK: - 규칙

object RummyRules {
    /** R-11 첫 등록 최소 점수. 30 정확히는 통과, 29 는 실패. */
    const val initialMinimum: Int = 30

    /** R-04~R-08 세트 판정(reference.py `meld_valid`). 무효면 kind·points 가 null. */
    fun analyze(meld: List<RummyFace>): RummyMeldAnalysis {
        val n = meld.size
        val colorsOfNumbered = ArrayList<Int>(n)
        val values = ArrayList<Int>(n)
        for (face in meld) {
            val color = face.color
            val number = face.number
            if (color != null && number != null) {
                colorsOfNumbered.add(color.toInt())
                values.add(number.toInt())
            }
        }
        val jokers = n - values.size
        // R-06: 3~13장 · 숫자 타일 1장 이상 · 조커 2장까지.
        if (n !in 3..13 || values.isEmpty() || jokers > 2) return RummyMeldAnalysis.invalid
        val colors = colorsOfNumbered.toSet()
        val distinctValues = values.toSet()

        var group: Int? = null
        // 그룹(R-04·R-06): n ∈ {3,4}, 숫자 하나, 색 모두 다름.
        if (n <= 4 && distinctValues.size == 1 && colors.size == values.size) {
            group = values[0] * n
        }
        var run: Int? = null
        // 런(R-05·R-06): 색 하나, 숫자 모두 다름, hi − lo + 1 ≤ n. 순환(12-13-1) 없음.
        if (colors.size == 1 && distinctValues.size == values.size) {
            val lo = values.min()
            val hi = values.max()
            if (hi - lo + 1 <= n) {
                val start = runStart(lo, n)
                run = n * start + n * (n - 1) / 2 // R-08
            }
        }
        // R-07: 점수 큰 쪽, 같으면 그룹.
        return when {
            group != null && run != null ->
                if (run > group) RummyMeldAnalysis(true, RummyMeldKind.run, run) else RummyMeldAnalysis(true, RummyMeldKind.group, group)
            group != null -> RummyMeldAnalysis(true, RummyMeldKind.group, group)
            run != null -> RummyMeldAnalysis(true, RummyMeldKind.run, run)
            else -> RummyMeldAnalysis.invalid
        }
    }

    /** R-07 런 시작 숫자 s = min(lo, 14 − n): 조커는 안쪽 빈칸 → 위쪽(13 까지) → 아래쪽 순으로 붙는다. */
    private fun runStart(lowest: Int, count: Int): Int = minOf(lowest, 14 - count)

    /** R-09 비교 키: (색 A<B<C<D, 숫자 오름, J 맨 뒤) 정렬. */
    fun compareKey(meld: List<RummyFace>): List<RummyFace> = meld.sortedWith(RummyFaceOrder)

    /**
     * R-09 표시 순서. 런 = R-07 구간 s … s+n−1 을 왼쪽부터(빈 자리에 조커), 그룹 = 색 A → D 뒤 조커.
     * 무효 세트는 받은 순서 그대로 돌려준다 — 작업 중인 조각은 플레이어가 놓은 순서가 곧 뜻이다(R-09 "작업 중에는 놓은 순서").
     */
    fun displayOrder(meld: List<RummyFace>): List<RummyFace> {
        val analysis = analyze(meld)
        val kind = analysis.kind
        if (!analysis.valid || kind == null) return meld
        return when (kind) {
            RummyMeldKind.group -> compareKey(meld)
            RummyMeldKind.run -> {
                val lo = meld.mapNotNull { it.number?.toInt() }.minOrNull() ?: return meld
                val start = runStart(lo, meld.size)
                val byNumber = HashMap<Int, RummyFace>()
                for (face in meld) {
                    val number = face.number
                    if (number != null) byNumber[number.toInt()] = face
                }
                (start until start + meld.size).map { byNumber[it] ?: RummyFace.joker }
            }
        }
    }

    /** K 다중집합 같음 — 판 위 세트 순서·세트 안 순서는 의미 없다(R-09). */
    fun sameTable(a: List<List<RummyFace>>, b: List<List<RummyFace>>): Boolean =
        a.size == b.size && keyBag(a) == keyBag(b)

    /** R-16 차례 판정(reference.py `turn_valid`). 위에서부터 처음 걸리는 reason 하나. */
    fun judgeTurn(
        initialDone: Boolean,
        tableBefore: List<List<RummyFace>>,
        rackBefore: List<RummyFace>,
        tableAfter: List<List<RummyFace>>,
    ): RummyTurnReason {
        // 0. 형식 — 면 정규식은 RummyFace 가 이미 보증했다. 남은 것은 빈 세트.
        if (tableAfter.any { it.isEmpty() }) return RummyTurnReason.malformed

        // 1. 판 보존 — 판에 있던 면이 사라지면 안 된다. 조커가 빠졌으면 따로 알린다(R-15).
        val before = bag(tableBefore.flatten())
        val after = bag(tableAfter.flatten())
        val missing = minus(before, after)
        if ((missing[RummyFace.joker] ?: 0) > 0) return RummyTurnReason.jokerNotReused
        if (missing.isNotEmpty()) return RummyTurnReason.tableTileRemoved

        // 2. 출처 — 새로 생긴 면은 모두 내 랙에서.
        val played = minus(after, before)
        if (!isSubset(played, bag(rackBefore))) return RummyTurnReason.tileNotOwned

        // 3. 최소 — 1장 이상.
        if (played.isEmpty()) return RummyTurnReason.noTilePlayed

        // 4. 세트 — 낱장·2장 조각 포함 하나라도 무효면 거절.
        if (tableAfter.any { !analyze(it).valid }) return RummyTurnReason.invalidMeld

        // 5. 첫 등록(R-11·R-12) — 판 기존 세트는 그대로(K 부분집합), 새 세트 점수 합 ≥ 30.
        if (!initialDone) {
            if (!isSubset(keyBag(tableBefore), keyBag(tableAfter))) return RummyTurnReason.initialTableTouched
            if (newMeldPoints(tableBefore, tableAfter) < initialMinimum) return RummyTurnReason.initialUnder30
        }
        return RummyTurnReason.ok
    }

    /** 랙 값 합(R-22, 조커 30). */
    fun rackValue(rack: List<RummyFace>): Int = rack.sumOf { it.rackValue }

    /**
     * R-22~R-24 끝 점수와 승자(0-기반 자리, 오름차순). reference.py `score` 를 옮겼다.
     *  · 빈 랙이 있으면 R-22: 처음 빈 랙이 승자, 나머지 랙 값의 합을 가져간다.
     *  · 없으면 R-23·R-24: 최소 집단 T 가 감점 합 P 를 똑같이 나눈다(⌊P/m⌋, 나머지는 장수 적은 → 자리 앞 순으로 1점씩),
     *    승자는 T 중 장수 최소(공동 가능).
     */
    fun finalScores(racks: List<List<RummyFace>>): RummyFinalScores {
        if (racks.isEmpty()) return RummyFinalScores(emptyList(), emptyList())
        val values = racks.map { rackValue(it) }

        val emptied = racks.indexOfFirst { it.isEmpty() }
        if (emptied >= 0) {
            val scores = values.map { -it }.toMutableList()
            scores[emptied] = values.filterIndexed { i, _ -> i != emptied }.sum()
            return RummyFinalScores(scores, listOf(emptied))
        }

        val lowest = values.min()
        val tied = racks.indices.filter { values[it] == lowest }
        val fewest = tied.minOf { racks[it].size }
        val winners = tied.filter { racks[it].size == fewest }
        val scores = values.map { -(it - lowest) }.toMutableList()
        val pot = -scores.filterIndexed { i, _ -> i !in tied }.sum()
        val order = tied.sortedWith(compareBy({ racks[it].size }, { it }))
        val base = pot / tied.size
        val remainder = pot % tied.size
        order.forEachIndexed { rank, seat -> scores[seat] = base + if (rank < remainder) 1 else 0 }
        return RummyFinalScores(scores, winners)
    }

    /**
     * §2.1 0번: 정산이 [payouts] 에 넘기는 점수(서버 `rummy__settle` 과 같다). [racks] 는 끝까지 남은 자리 순.
     * [finalScores] 그대로이되, 막힘 끝(빈 랙 없음)의 최소 집단 T(m ≥ 2)는 모두 ⌊P/m⌋ 로 같게 넘긴다 —
     * 화면 점수의 나머지 1점이 §2.1 묶음을 갈라 값이 같은 공동 최소 집단이 다른 상금·등수를 받지 않게(설계서 P11).
     */
    fun payoutScores(racks: List<List<RummyFace>>): List<Int> {
        val scores = finalScores(racks).scores.toMutableList()
        if (racks.isEmpty() || racks.any { it.isEmpty() }) return scores
        val values = racks.map { rackValue(it) }
        val lowest = values.min()
        val tied = racks.indices.filter { values[it] == lowest }
        if (tied.size < 2) return scores
        val pot = values.sumOf { it - lowest }
        for (seat in tied) scores[seat] = pot / tied.size
        return scores
    }

    /** 등수 상금표(× 판돈, 설계서 §2.1 ①). 2인 [2,0] · 3인 [2,1,0] · 4인 [3,1,0,0]. */
    fun prizeTable(seatCount: Int): List<Int> = when (seatCount) {
        2 -> listOf(2, 0)
        3 -> listOf(2, 1, 0)
        4 -> listOf(3, 1, 0, 0)
        else -> emptyList()
    }

    /**
     * §2.1 등수별 분배(제로섬)와 표시 등수. [seats] 는 자리 순(p1..pn).
     * 시작 인원이 2~4 밖이거나 active 가 하나도 없으면 분배할 수 없다 — 0 배열(등수는 그대로 센다).
     * Swift 의 제로섬 `assert` 는 릴리스에서 빠지는 디버그 단언이라 여기선 시험(payoutTable · 골든)이 잰다.
     */
    fun payouts(seatCount: Int, stake: Int, seats: List<RummyPayoutSeat>): RummyPayouts {
        val prizes = prizeTable(seatCount).map { it * stake }
        val payouts = MutableList(seats.size) { 0 }

        // ② active 를 score 내림차순으로 줄 세우고 같은 score 끼리 묶는다.
        val active = seats.indices.filter { seats[it].active }.sortedByDescending { seats[it].score }
        val groups = ArrayList<MutableList<Int>>()
        for (index in active) {
            val last = groups.lastOrNull()?.first()
            if (last != null && seats[last].score == seats[index].score) {
                groups.last().add(index)
            } else {
                groups.add(mutableListOf(index))
            }
        }

        // 묶음 m명이 합을 나눈다: ⌊합/m⌋, 나머지는 (tiles 오름 → seat 오름) 앞사람부터 1씩.
        fun split(total: Int, group: List<Int>) {
            val order = group.sortedWith(compareBy({ seats[it].tiles }, { seats[it].seat }))
            val base = total / group.size
            val remainder = total % group.size
            order.forEachIndexed { rank, index -> payouts[index] += base + if (rank < remainder) 1 else 0 }
        }

        if (prizes.isNotEmpty() && groups.isNotEmpty()) {
            var position = 0
            for (group in groups) {
                val total = (position until position + group.size).sumOf { if (it < prizes.size) prizes[it] else 0 }
                split(total, group)
                position += group.size
            }
            // ③ 기권자가 차지한 자리의 몫은 1위 묶음에 더 나눈다.
            val leftover = seatCount * stake - payouts.sum()
            if (leftover > 0) split(leftover, groups[0])
        }

        // ⑤ 표시 등수: active = 1 + (score 가 더 큰 active 수), 기권 = k + (기권자 수 − forfeitOrder + 1).
        val activeCount = active.size
        val forfeitCount = seats.size - activeCount
        val ranks = seats.map { seat ->
            if (seat.active) {
                1 + active.count { seats[it].score > seat.score }
            } else {
                activeCount + (forfeitCount - (seat.forfeitOrder ?: 1) + 1)
            }
        }
        return RummyPayouts(payouts, ranks)
    }

    /** 첫 등록 진행 표시("18/30")용: 새로 생긴 세트(K(after) − K(before))의 R-08 점수 합. 무효 세트는 0점. */
    fun newMeldPoints(tableBefore: List<List<RummyFace>>, tableAfter: List<List<RummyFace>>): Int =
        minus(keyBag(tableAfter), keyBag(tableBefore)).entries.sumOf { (key, count) -> (analyze(key).points ?: 0) * count }

    // MARK: 다중집합

    private fun <E> bag(items: Iterable<E>): Map<E, Int> {
        val out = HashMap<E, Int>()
        for (item in items) out[item] = (out[item] ?: 0) + 1
        return out
    }

    /** 판의 비교 키 다중집합 K(R-09). */
    private fun keyBag(table: List<List<RummyFace>>): Map<List<RummyFace>, Int> = bag(table.map { compareKey(it) })

    /** a − b, 0 이하는 지운다(Counter 의 `-` 와 같다). */
    private fun <E> minus(a: Map<E, Int>, b: Map<E, Int>): Map<E, Int> {
        val out = HashMap<E, Int>()
        for ((key, value) in a) {
            val left = value - (b[key] ?: 0)
            if (left > 0) out[key] = left
        }
        return out
    }

    private fun <E> isSubset(a: Map<E, Int>, b: Map<E, Int>): Boolean = a.all { (b[it.key] ?: 0) >= it.value }
}
