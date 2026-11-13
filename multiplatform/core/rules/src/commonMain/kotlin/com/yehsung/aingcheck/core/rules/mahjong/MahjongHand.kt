// 원본: Sources/CheckCore/MahjongHand.swift @ e4995a3a(화료 꼴 · 대기 · 샹텐 — MJ-22 · MJ-26 · X-03) — Android 판 8
//
// 입력은 **종류 34칸 장수 배열**([MahjongTiles.counts34])과 손 밖 몸통 수(울기 · 깡 수)다. 손 안 패만 센다.
// 대기 정의는 X-03 판: 1장을 더해 화료 꼴이 되는 종류 가운데 **순수 손패에 이미 4장 쥔 종류는 뺀다**(MJ-26).
// 샹텐은 색마다 최선 하나로 합치지 않는다(색마다 파레토 후보를 들고 배낭 합으로 합친다).
package com.yehsung.aingcheck.core.rules.mahjong

import kotlin.math.max
import kotlin.math.min

object MahjongHand {
    /** MJ-22 화료 꼴인가(역 무관). 표준형(몸통 4−melds + 머리) · 울기 없을 때 치또이(서로 다른 7쌍) · 국사. */
    fun isComplete(counts: IntArray, melds: Int): Boolean {
        if (counts.size != 34 || melds !in 0..4 || counts.any { it < 0 }) return false
        if (melds == 0 && (isChiitoi(counts) || isKokushi(counts))) return true
        val c = counts.copyOf()
        return decomposes(c, 4 - melds, false, 0)
    }

    /** MJ-26 대기 종류(오름차순). 손에 그 종류를 이미 4장 쥐었으면 뺀다(X-03). 가라텐은 대기로 친다. */
    fun waits(counts: IntArray, melds: Int): List<Int> {
        if (counts.size != 34) return emptyList()
        val c = counts.copyOf()
        val out = mutableListOf<Int>()
        for (x in 0 until 34) {
            if (c[x] >= 4) continue
            c[x] += 1
            if (isComplete(c, melds)) out += x
            c[x] -= 1
        }
        return out
    }

    /**
     * 샹텐. −1 = 화료 꼴, 0 = 텐파이. 표준형 · 치또이 · 국사 중 작은 값(치또이 · 국사는 울기 없을 때만).
     * counts 가 34칸이 아니거나 melds 가 0~4 밖이면 8.
     */
    fun shanten(counts: IntArray, melds: Int): Int {
        if (counts.size != 34 || melds !in 0..4) return 8
        var acc = ShantenTable.identity
        for (s in 0 until 3) acc = ShantenTable.knap(acc, ShantenTable.suitCost(counts, s * 9))
        for (k in 27 until 34) acc = ShantenTable.knap(acc, ShantenTable.honorCost(counts[k]))
        var best = acc[(4 - melds) * 2 + 1] - 1
        if (melds == 0) {
            var pairs = 0
            var kinds = 0
            for (x in counts) {
                if (x >= 2) pairs += 1
                if (x >= 1) kinds += 1
            }
            val chiitoi = 6 - pairs + max(0, 7 - kinds)
            var yaochuKinds = 0
            var yaochuPair = false
            for (k in MahjongTiles.yaochu) {
                if (counts[k] >= 1) yaochuKinds += 1
                if (counts[k] >= 2) yaochuPair = true
            }
            val kokushi = 13 - yaochuKinds - (if (yaochuPair) 1 else 0)
            best = min(best, min(chiitoi, kokushi))
        }
        return best
    }

    /** MJ-22-2 서로 다른 7쌍(4장을 2쌍으로 치지 않음). */
    fun isChiitoi(c: IntArray): Boolean = c.sum() == 14 && c.count { it == 2 } == 7

    /** MJ-22-3 요구패 13종 1장씩 + 그중 하나 1장 더. */
    fun isKokushi(c: IntArray): Boolean {
        if (c.sum() != 14) return false
        val y = MahjongTiles.yaochu
        return y.all { c[it] >= 1 } && y.sumOf { c[it] } == 14
    }

    /** 표준형 분해가 하나라도 있는가. c 는 호출 뒤 원래대로 돌아온다. */
    internal fun decomposes(c: IntArray, need: Int, havePair: Boolean, start: Int): Boolean {
        var i = start
        while (i < 34 && c[i] == 0) i += 1
        if (i == 34) return need == 0 && havePair
        if (!havePair && c[i] >= 2) {
            c[i] -= 2
            val ok = decomposes(c, need, true, i)
            c[i] += 2
            if (ok) return true
        }
        if (need > 0 && c[i] >= 3) {
            c[i] -= 3
            val ok = decomposes(c, need - 1, havePair, i)
            c[i] += 3
            if (ok) return true
        }
        if (need > 0 && i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
            c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
            val ok = decomposes(c, need - 1, havePair, i)
            c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
            if (ok) return true
        }
        return false
    }
}

/** 샹텐 비용 표. 표 = 10칸 [몸통 수 m × 2 + 머리 수 p] → 더 들일 최소 장수(없으면 inf). */
object ShantenTable {
    const val inf = 99
    val identity: IntArray = intArrayOf(0, inf, inf, inf, inf, inf, inf, inf, inf, inf)

    /** 두 표의 배낭 합 — m1 + m2 ≤ 4, p1 + p2 ≤ 1 에서 비용의 최소. */
    fun knap(a: IntArray, b: IntArray): IntArray {
        val out = IntArray(10) { inf }
        for (m1 in 0..4) for (p1 in 0..1) {
            val x = a[m1 * 2 + p1]
            if (x >= inf) continue
            for (m2 in 0..(4 - m1)) for (p2 in 0..(1 - p1)) {
                val v = x + b[m2 * 2 + p2]
                val i = (m1 + m2) * 2 + p1 + p2
                if (v < out[i]) out[i] = v
            }
        }
        return out
    }

    /** 자패 한 종류: 커쯔 하나(3 − h) 또는 머리 하나(2 − h). */
    fun honorCost(h: Int): IntArray {
        val t = IntArray(10) { inf }
        t[0] = 0
        t[2] = max(0, 3 - h)
        t[1] = max(0, 2 - h)
        return t
    }

    /**
     * 한 색(9칸)의 비용 표. Swift 는 같은 9칸 장수를 잠금 걸린 표로 기억해 둔다 — 공용 Kotlin 에는 잠금이 없어(여러 줄기에서 봇이 부를 수 있다)
     * 기억하지 않고 매번 센다(250 상태 × 9칸 — 한 번에 수 마이크로초).
     */
    fun suitCost(counts: IntArray, start: Int): IntArray {
        val have = IntArray(9) { i -> min(max(counts[start + i], 0), 4) }
        return suitCostUncached(have)
    }

    /** 상태 (s1, s2, m, p) → 최소 비용을 9칸 앞으로 민다. 끝에서 s1 = s2 = 0 인 상태(앞 10칸)만 센다. */
    fun suitCostUncached(have: IntArray): IntArray {
        var cur = IntArray(250) { inf }
        var nxt = IntArray(250)
        cur[0] = 0
        for (i in 0 until 9) {
            val e = if (i <= 6) edgesWithSeq else edgesNoSeq
            val h = have[i]
            nxt.fill(inf)
            for (from in 0 until 250) {
                val c = cur[from]
                if (c >= inf) continue
                for (k in e.start[from] until e.start[from + 1]) {
                    val d = e.need[k] - h
                    val nc = if (d > 0) c + d else c
                    val t = e.to[k]
                    if (nc < nxt[t]) nxt[t] = nc
                }
            }
            val tmp = cur
            cur = nxt
            nxt = tmp
        }
        return cur.copyOfRange(0, 10)
    }

    class Edges(val start: IntArray, val to: IntArray, val need: IntArray)

    val edgesWithSeq: Edges = makeEdges(4)
    val edgesNoSeq: Edges = makeEdges(0)

    fun makeEdges(stMax: Int): Edges {
        val start = ArrayList<Int>()
        val to = ArrayList<Int>()
        val need = ArrayList<Int>()
        for (from in 0 until 250) {
            start += to.size
            val p = from % 2
            val m = (from / 2) % 5
            val s2 = (from / 10) % 5
            val s1 = from / 50
            if (s1 + s2 > 4) continue
            for (st in 0..stMax) {
                if (st + s1 + s2 > 4 || m + st > 4) continue
                for (tr in 0..1) {
                    if (m + st + tr > 4) continue
                    for (pr in 0..(1 - p)) {
                        val n = st + s1 + s2 + 3 * tr + 2 * pr
                        if (n > 4) continue
                        to += ((st * 5 + s1) * 5 + m + st + tr) * 2 + p + pr
                        need += n
                    }
                }
            }
        }
        start += to.size
        return Edges(start.toIntArray(), to.toIntArray(), need.toIntArray())
    }
}
