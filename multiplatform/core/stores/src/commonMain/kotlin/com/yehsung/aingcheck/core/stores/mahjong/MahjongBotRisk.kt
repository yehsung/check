// 원본: Sources/CheckCore/MahjongBotRisk.swift · MahjongVisibleTiles.swift @ e4995a3a(연습 봇 위협 · 현물 · 패별 위험도 / 보이는 장수 한 곳) — Android 판 8
//
// 입력은 그 자리 시야(payload)뿐이다. 보이는 장수는 [MahjongVisibleTiles.counts] 한 곳만 쓴다(울린 패를 강에서 두 번 세지 않는다).
// 위험도 표(비율만 뜻이 있는 설계 상수)와 현물 규칙은 Swift 머리말 그대로.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeldType
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTiles

/** '보이는 장수' 한 곳 — 상태 줄 · 버림 미리보기 · 역 시트 · 봇 유효패가 모두 이것 하나만 부른다. */
object MahjongVisibleTiles {
    /** 종류별 보이는 장수(34칸). 강은 taken == false 만 · 부로 전부 · 열린 도라 표시패 · 내 손 · 내가 뽑은 패. */
    fun counts(payload: MahjongStatePayload): IntArray {
        val counts = IntArray(34)
        fun add(t: MahjongTile) { counts[t.kind] += 1 }
        for (seat in payload.seats ?: emptyList()) {
            for (d in seat.discards ?: emptyList()) if (d.taken != true) add(d.tile)
            for (m in seat.melds ?: emptyList()) m.tiles.forEach(::add)
        }
        (payload.match?.doraIndicators ?: emptyList()).forEach(::add)
        (payload.myHand ?: emptyList()).forEach(::add)
        payload.myDrawn?.let(::add)
        return counts
    }

    /** 아직 안 보인 장수(0 아래로 내려가지 않는다). */
    fun unseen(kind: Int, payload: MahjongStatePayload): Int {
        if (kind !in 0..33) return 0
        return maxOf(0, 4 - counts(payload)[kind])
    }
}

/** 위협 하나. 리치 = 완전 위협(1.0), 울음 셋 · 울음 둘 + 역패/도라 = 반 위협(0.4). */
data class MahjongBotThreat(val seat: Int, val riichi: Boolean, val weight: Double, val safeKinds: Set<Int>) {
    companion object {
        const val riichiWeight = 1.0
        const val openWeight = 0.4
    }
}

object MahjongBotRisk {
    const val genbutsu = 0.0
    const val noChanceTerminal = 1.0
    const val honorThreeSeen = 1.0
    const val sujiTerminal = 3.0
    const val honorTwoSeen = 3.0
    const val noChanceMiddle = 5.0
    const val sujiTwoEight = 5.0
    const val honorOneSeen = 6.0
    const val oneChance = 7.0
    const val sujiThreeSeven = 7.0
    const val honorUnseen = 8.0
    const val sujiMiddle = 8.0
    const val musujiTerminal = 10.0
    const val halfSujiMiddle = 11.0
    const val musujiTwoEight = 13.0
    const val musujiThreeSeven = 15.0
    const val musujiMiddle = 18.0
    const val doraMiddleFactor = 1.5
    const val doraEdgeFactor = 1.8
    const val redFactor = 1.5
    /** '위험 높은 패' 문턱 — 무스지 2 · 8 이상. */
    const val highDanger = 13.0

    /** 시야에서 위협 목록(나는 빼고, 자리 번호 순). */
    fun threats(view: MahjongStatePayload): List<MahjongBotThreat> {
        val me = view.mySeat ?: return emptyList()
        val doraKinds = (view.match?.doraIndicators ?: emptyList()).map { MahjongTiles.doraKind(it.kind) }.toSet()
        val roundWind = 27 + (view.match?.round ?: 0) % 4
        val tail = currentHandEvents(view)
        val out = mutableListOf<MahjongBotThreat>()
        for (seat in view.seats ?: emptyList()) {
            if (seat.seatNo == me) continue
            val melds = (seat.melds ?: emptyList()).mapNotNull { it.meld }
            val isRiichi = seat.riichi == true
            val open = melds.filter { it.type != MahjongMeldType.ankan }
            var weight = 0.0
            if (isRiichi) {
                weight = MahjongBotThreat.riichiWeight
            } else if (open.size >= 3) {
                weight = MahjongBotThreat.openWeight
            } else if (open.size >= 2) {
                val seatWind = windKind(seat.wind)
                val yakuhaiShown = melds.any { m -> m.type != MahjongMeldType.chi && isYakuhai(m.tiles[0].kind, seatWind, roundWind) }
                val doraShown = melds.any { m -> m.tiles.any { it.kind in doraKinds || it.isRed } }
                if (yakuhaiShown || doraShown) weight = MahjongBotThreat.openWeight
            }
            if (weight <= 0) continue
            out += MahjongBotThreat(seat.seatNo, isRiichi, weight, safeKinds(seat.seatNo, view, tail))
        }
        return out
    }

    /** 그 자리에게 현물인 종류 — 강 전부 · 리치 선언 뒤 나온 패 · 마지막 버림/쯔모 뒤 나온 패(동순 후리텐). */
    fun safeKinds(seat: Int, view: MahjongStatePayload): Set<Int> = safeKinds(seat, view, currentHandEvents(view))

    internal fun safeKinds(seat: Int, view: MahjongStatePayload, tail: List<MahjongEvent>): Set<Int> {
        val row = view.seats?.firstOrNull { it.seatNo == seat }
        val safe = (row?.discards ?: emptyList()).map { it.tile.kind }.toMutableSet()
        val discards = tail.filter { it.kind == "discard" && it.tile != null }
        if (row?.riichi == true) {
            val declared = tail.indexOfLast { it.kind == "discard" && it.seat == seat && it.riichi == true }
            if (declared >= 0) {
                for (e in tail.drop(declared + 1)) if (e.kind == "discard") e.tile?.let { safe += it.kind }
            } else {
                // 선언이 꼬리보다 옛날이다 — 꼬리의 버림은 모두 선언 뒤다.
                for (e in discards) e.tile?.let { safe += it.kind }
            }
        }
        val mark = tail.indexOfLast { (it.kind == "discard" || it.kind == "draw") && it.seat == seat }
        if (mark >= 0) for (e in tail.drop(mark + 1)) if (e.kind == "discard") e.tile?.let { safe += it.kind }
        return safe
    }

    /** 사건 꼬리 가운데 이 국 것만(마지막 deal 뒤). */
    internal fun currentHandEvents(view: MahjongStatePayload): List<MahjongEvent> {
        val events = (view.events ?: emptyList()).sortedBy { it.seq }
        val deal = events.indexOfLast { it.kind == "deal" }
        return if (deal < 0) events else events.drop(deal + 1)
    }

    private enum class Side { none, wall, suji, oneChance, open }

    /** 한 상대에 대한 종류 k 의 위험도(도라 · 적5 배율 전). visible = 34칸 보이는 장수(내 손 포함). */
    fun baseDanger(k: Int, safe: Set<Int>, visible: IntArray): Double {
        if (k in safe) return genbutsu
        if (k >= 27) {
            return when (maxOf(0, 4 - visible[k])) {
                0 -> genbutsu
                1 -> honorThreeSeen
                2 -> honorTwoSeen
                3 -> honorOneSeen
                else -> honorUnseen
            }
        }
        val base = k - k % 9
        val n = k % 9 + 1
        fun seen(m: Int): Int = if (m in 1..9) visible[base + m - 1] else 0
        fun gen(m: Int): Boolean = m in 1..9 && (base + m - 1) in safe
        fun side(exists: Boolean, a: Int, b: Int, suji: Int): Side {
            if (!exists) return Side.none
            if (seen(a) >= 4 || seen(b) >= 4) return Side.wall
            if (gen(suji)) return Side.suji
            if (seen(a) == 3 || seen(b) == 3) return Side.oneChance
            return Side.open
        }
        val low = side(n >= 4, n - 2, n - 1, n - 3)
        val high = side(n <= 6, n + 1, n + 2, n + 3)
        val sides = listOf(low, high).filter { it != Side.none }
        val edge = n == 1 || n == 9
        val twoEight = n == 2 || n == 8
        val threeSeven = n == 3 || n == 7
        if (sides.all { it == Side.wall }) return if (edge) noChanceTerminal else noChanceMiddle
        var best = when {
            edge -> musujiTerminal
            twoEight -> musujiTwoEight
            threeSeven -> musujiThreeSeven
            else -> musujiMiddle
        }
        if (sides.all { it == Side.wall || it == Side.suji }) {
            val suji = if (edge) sujiTerminal else if (twoEight) sujiTwoEight else if (threeSeven) sujiThreeSeven else sujiMiddle
            best = minOf(best, suji)
        } else if (sides.size == 2 && sides.any { it == Side.wall || it == Side.suji } && Side.oneChance !in sides) {
            best = minOf(best, halfSujiMiddle)
        }
        if (sides.all { it != Side.open }) best = minOf(best, oneChance)
        return best
    }

    /** 도라 · 적5 배율을 곱한 한 상대 위험도. */
    fun danger(tile: MahjongTile, safe: Set<Int>, visible: IntArray, doraKinds: Set<Int>): Double {
        val k = tile.kind
        var d = baseDanger(k, safe, visible)
        if (k in doraKinds) {
            val n = k % 9 + 1
            d *= if (k >= 27 || n == 1 || n == 9) doraEdgeFactor else doraMiddleFactor
        }
        if (tile.isRed) d *= redFactor
        return d
    }

    /** 위협들에 대한 가중 합과 가장 큰 날 값. */
    fun weighted(tile: MahjongTile, threats: List<MahjongBotThreat>, visible: IntArray, doraKinds: Set<Int>): Pair<Double, Double> {
        var sum = 0.0
        var worst = 0.0
        for (t in threats) {
            val d = danger(tile, t.safeKinds, visible, doraKinds)
            sum += t.weight * d
            worst = maxOf(worst, d)
        }
        return sum to worst
    }

    /** 와이어 바람 글자 → 바람패 종류(27~30). 모르면 null. */
    internal fun windKind(letter: String?): Int? = when (letter) {
        "E" -> 27
        "S" -> 28
        "W" -> 29
        "N" -> 30
        else -> null
    }

    /** 역패 종류인가 — 삼원패 · 그 자리 바람 · 장풍. */
    internal fun isYakuhai(kind: Int, seatWind: Int?, roundWind: Int): Boolean = kind >= 31 || kind == seatWind || kind == roundWind
}
