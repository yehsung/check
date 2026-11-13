// 원본: Sources/CheckCore/MahjongBot.swift @ e4995a3a(혼자 연습판 봇 — 결정 · 샹텐 셈) — Android 판 8
//
// 계약: 입력은 그 자리 시야(payload)뿐 · 고르는 것은 myDecision 안에서만 · 계산 상한 200ms(1샹텐 2단 보기는 마감을 넘기면 멈추고 1단 결과)
// · 같은 점수끼리만 주입 난수로 고른다(일부러 틀리는 수는 없다). 난수는 Swift 표준 알고리즘 그대로(SwiftRandomSource) — 같은 씨앗이면 같은 수.
// 정책: 화료는 늘 · 리치 중이면 쯔모기리(대기 불변 안깡만) · 구종구패(요구패 10종 이상이면 국사) · 안깡(샹텐 불변) · 가깡(위협 없고 샹텐 불변)
// · 대명깡 안 함 · 위협 표에 따라 밀기/접기 · 멘젠 텐파이면 리치(가라텐 · 만관 다마 · 후리텐 저장수 제외) · 역 확보형 울기만.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.ai.SwiftRandomSource
import com.yehsung.aingcheck.core.rules.ai.nextBounded
import com.yehsung.aingcheck.core.rules.ai.nextIndex
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongEvaluation
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeld
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeldType
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongScore
import com.yehsung.aingcheck.core.rules.mahjong.MahjongScoring
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTiles
import com.yehsung.aingcheck.core.rules.mahjong.MahjongWind
import com.yehsung.aingcheck.core.rules.mahjong.MahjongWinContext
import com.yehsung.aingcheck.core.rules.mahjong.MahjongYaku
import com.yehsung.aingcheck.core.rules.mahjong.ShantenTable
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/** 봇이 고른 것. 차례면 Act, 울기 창이면 Call(창 번호를 함께), 내 몫 결정이 없으면 None. */
sealed interface MahjongBotMove {
    data class Act(val action: MahjongTurnAction) : MahjongBotMove
    data class Call(val windowId: Int, val answer: MahjongCallAnswer) : MahjongBotMove
    data object None : MahjongBotMove
}

/** 봇 정책 스위치 — 앱은 늘 standard. */
data class MahjongBotPolicy(val defends: Boolean, val calls: Boolean = true) {
    companion object {
        val standard = MahjongBotPolicy(defends = true)
        val efficiencyOnly = MahjongBotPolicy(defends = false)
    }
}

object MahjongBot {
    /** 계산 상한. */
    val computeBudget: Duration = 200.milliseconds
    /** 보여 주는 생각 시간(초) — 버림 0.6~1.2 균등 · 리치 뒤 쯔모기리 0.4 · 최대 1.5. */
    val thinkRange: ClosedFloatingPointRange<Double> = 0.6..1.2
    const val riichiTsumogiriThink = 0.4
    const val maxThink = 1.5
    const val pushValue = 7_700
    const val weakTenpaiValue = 2_000
    const val weakTenpaiWaits = 3
    const val pushUkeire = 16
    /** 1샹텐으로 밀 때 버릴 수 있는 패의 위험 상한('스지' 급). */
    const val pushDangerCap = MahjongBotRisk.sujiMiddle
    /** 구종구패를 선언하지 않고 국사를 노리는 요구패 종류 수. */
    const val kokushiAim = 10

    /** 그 자리 시야에서 한 수를 고른다. pastDeadline = 마감이 지났는가(시계 주입). */
    fun decide(
        view: MahjongStatePayload,
        rng: SwiftRandomSource,
        pastDeadline: () -> Boolean,
        policy: MahjongBotPolicy = MahjongBotPolicy.standard,
    ): MahjongBotMove {
        val decision = view.myDecision ?: return MahjongBotMove.None
        val me = view.mySeat ?: return MahjongBotMove.None
        val mind = MahjongBotMind(view, me, policy, pastDeadline)
        return when (decision) {
            is MahjongDecision.Turn -> MahjongBotMove.Act(mind.turn(decision, rng))
            is MahjongDecision.Call -> MahjongBotMove.Call(decision.windowId, mind.call(decision, rng))
        }
    }

    /** 보여 주는 생각 시간(버림 0.6~1.2초 · 리치 뒤 쯔모기리 0.4초 · 울기 답은 0 · 최대 1.5초). */
    fun thinkSeconds(move: MahjongBotMove, view: MahjongStatePayload, rng: SwiftRandomSource): Double = when (move) {
        MahjongBotMove.None, is MahjongBotMove.Call -> 0.0
        is MahjongBotMove.Act -> {
            if (view.mySeatRow?.riichi == true && move.action is MahjongTurnAction.Discard) riichiTsumogiriThink
            else minOf(maxThink, swiftRandomDouble(thinkRange, rng))
        }
    }

    /** Swift `Double.random(in: ClosedRange, using:)` — next(upperBound: 2^53 + 1) × ulpOfOne/2. */
    internal fun swiftRandomDouble(range: ClosedFloatingPointRange<Double>, rng: SwiftRandomSource): Double {
        val delta = range.endInclusive - range.start
        val maxSignificand = 1uL shl 53
        val rand = rng.nextBounded(maxSignificand + 1uL)
        if (rand == maxSignificand) return range.endInclusive
        val unit = rand.toDouble() * (Math_ulpOfOneHalf)
        return delta * unit + range.start
    }

    private const val Math_ulpOfOneHalf = 1.1102230246251565E-16 // 2^-53
}

/** 버림 후보 하나의 평가. */
internal class MahjongBotDiscard(
    val tile: MahjongTile,
    /** 버린 뒤 샹텐. */
    val shanten: Int,
    var score: Double,
    /** 낮을수록 먼저 버린다(동률 깨기). */
    val keep: Int,
    val danger: Double,
    val worst: Double,
) {
    val kind: Int get() = tile.kind
    var ukeire = 0
    var kinds: List<Int> = emptyList()
    var value = 0
    var valueRiichi = 0
    var damaMangan = false
    var furiten = false
    var hasYakuDama = false

    /** 순위용 샹텐 — 날 수 없는 텐파이(가라텐 · 울은 손 역 없음)는 1샹텐으로 친다. */
    val rankShanten: Int get() = if (shanten == 0 && score <= 0) 1 else shanten
}

/** 짧은 수명의 결정 상태. */
internal class MahjongBotMind(val view: MahjongStatePayload, val me: Int, val policy: MahjongBotPolicy, val pastDeadlineFn: () -> Boolean) {
    private val row = view.mySeatRow
    val drawn: MahjongTile? = view.myDrawn
    val hand: List<MahjongTile> = ((view.myHand ?: emptyList()) + listOfNotNull(view.myDrawn)).sorted()
    val counts: IntArray = MahjongTiles.counts34(hand)
    val melds: List<MahjongMeld> = (row?.melds ?: emptyList()).mapNotNull { it.meld }
    val visible: IntArray = MahjongVisibleTiles.counts(view)
    val unseen: IntArray = IntArray(34) { maxOf(0, 4 - visible[it]) }
    val doraIndicators: List<MahjongTile> = view.match?.doraIndicators ?: emptyList()
    val doraKinds: Set<Int> = doraIndicators.map { MahjongTiles.doraKind(it.kind) }.toSet()
    private val dealerSeat = view.match?.dealerSeat ?: view.match?.handNo ?: 0
    val seatWind: MahjongWind = row?.wind?.let(MahjongWind::of) ?: MahjongWind.entries[(me - dealerSeat + 4) % 4]
    val roundWind: MahjongWind = MahjongWind.entries[(view.match?.round ?: 0) % 4]
    val seatWindKind = 27 + seatWind.ordinal
    val roundWindKind = 27 + roundWind.ordinal
    val isDealer: Boolean = row?.isDealer ?: (me == dealerSeat)
    val wallLeft: Int = view.match?.wallRemaining ?: 70
    val ownDiscardKinds: Set<Int> = (row?.discards ?: emptyList()).map { it.tile.kind }.toSet()
    val menzen: Boolean = melds.all { it.type == MahjongMeldType.ankan }
    val inRiichi: Boolean = row?.riichi == true
    val threats: List<MahjongBotThreat> = if (policy.defends) MahjongBotRisk.threats(view) else emptyList()
    val calc = MahjongBotShanten()
    private val waitMemo = HashMap<MahjongBotKey, Int>()
    /** 2단 보기를 마감 때문에 멈췄는가. */
    var lookaheadCut = false

    companion object {
        /** 2단 보기를 하는 1샹텐 버림 수. */
        const val lookaheadWidth = 4

        /** 같은 종류 여러 id 가운데 버릴 한 장: 뽑은 패(쯔모기리) → 적5 아닌 패 → 아무거나. */
        fun representative(ids: List<MahjongTile>, drawn: MahjongTile?): MahjongTile? {
            if (drawn != null && drawn in ids && !drawn.isRed) return drawn
            return ids.filter { !it.isRed }.maxOrNull() ?: ids.maxOrNull()
        }

        fun redCount(tiles: List<MahjongTile>): Int = tiles.count { it.isRed }
    }

    fun shanten(c: IntArray, m: Int): Int = calc.base(c, m).shanten

    val pastDeadline: Boolean get() = pastDeadlineFn()

    // MARK: - 차례

    fun turn(t: MahjongDecision.Turn, rng: SwiftRandomSource): MahjongTurnAction {
        if (t.tsumo) return MahjongTurnAction.Tsumo
        val fallback: MahjongTurnAction = t.discard.firstOrNull()?.let { MahjongTurnAction.Discard(it) } ?: MahjongTurnAction.Tsumo
        if (inRiichi) {
            t.ankan.firstOrNull()?.let { return MahjongTurnAction.Ankan(it) }
            if (drawn != null && drawn in t.discard) return MahjongTurnAction.Discard(drawn)
            return fallback
        }
        if (t.kyuushu) {
            val yaochuKinds = MahjongTiles.yaochu.count { counts[it] > 0 }
            if (yaochuKinds < MahjongBot.kokushiAim) return MahjongTurnAction.Kyuushu
        }
        val cands = evaluateDiscards(t.discard)
        if (cands.isEmpty()) return fallback
        val bestShanten = cands.minOf { it.rankShanten }

        for (four in t.ankan) {
            val k = four.firstOrNull()?.kind ?: continue
            val c = counts.copyOf()
            c[k] -= 4
            if (c[k] >= 0 && shanten(c, melds.size + 1) <= bestShanten) return MahjongTurnAction.Ankan(four)
        }
        if (threats.isEmpty()) {
            for (tile in t.kakan) {
                val c = counts.copyOf()
                c[tile.kind] -= 1
                if (c[tile.kind] >= 0 && shanten(c, melds.size) <= bestShanten) return MahjongTurnAction.Kakan(tile)
            }
        }

        val riichiKinds = t.riichi.map { it.kind }.toSet()
        when (val s = stance(cands, bestShanten)) {
            Stance.Fold -> return MahjongTurnAction.Discard(pickSafest(cands, rng).tile)
            is Stance.WeakTenpai -> {
                val safe = s.safe
                if (safe.kind in riichiKinds && riichiAllowed(safe)) riichiTile(t.riichi, safe.kind)?.let { return MahjongTurnAction.Riichi(it) }
                return MahjongTurnAction.Discard(safe.tile)
            }
            is Stance.Attack -> {
                var pool = cands
                val cap = s.capWorst
                if (cap != null) {
                    val capped = cands.filter { it.rankShanten == bestShanten && it.worst <= cap }
                    if (capped.isNotEmpty()) pool = capped
                }
                val choice = pickAttack(pool, rng)
                if (choice.shanten == 0 && choice.kind in riichiKinds && riichiAllowed(choice)) {
                    riichiTile(t.riichi, choice.kind)?.let { return MahjongTurnAction.Riichi(it) }
                }
                return MahjongTurnAction.Discard(choice.tile)
            }
        }
    }

    /** 리치할 수 있는 텐파이 버림인가: 가라텐 · 만관 다마 · 후리텐이고 남은 장수 4 미만이면 안 한다. */
    fun riichiAllowed(d: MahjongBotDiscard): Boolean {
        if (d.shanten != 0 || d.ukeire <= 0) return false
        if (d.damaMangan) return false
        if (d.furiten && d.ukeire < 4) return false
        return true
    }

    fun riichiTile(options: List<MahjongTile>, kind: Int): MahjongTile? = representative(options.filter { it.kind == kind }, drawn)

    // MARK: 버림 평가

    fun evaluateDiscards(options: List<MahjongTile>): List<MahjongBotDiscard> {
        val m = melds.size
        val byKind = linkedMapOf<Int, MutableList<MahjongTile>>()
        for (t in options) byKind.getOrPut(t.kind) { mutableListOf() } += t
        val c = counts.copyOf()
        val b14 = calc.base(c, m)
        val out = mutableListOf<MahjongBotDiscard>()
        for (kind in byKind.keys.sorted()) {
            if (c[kind] <= 0) continue
            val tile = representative(byKind[kind] ?: emptyList(), drawn) ?: continue
            val sh = calc.shanten(b14, c, kind, -1)
            val (sum, worst) = MahjongBotRisk.weighted(tile, threats, visible, doraKinds)
            out += MahjongBotDiscard(tile, sh, 0.0, keepValue(tile), sum, worst)
        }
        val low = out.minOfOrNull { it.shanten } ?: 8
        val pr = calc.pairs(b14)
        fillUkeire(out, low, b14, pr)
        if (low == 0 && out.none { it.shanten == 0 && it.score > 0 }) fillUkeire(out, 1, b14, pr)
        lookahead(out)
        return out
    }

    fun fillUkeire(out: List<MahjongBotDiscard>, tier: Int, b14: MahjongBotShanten.Base, pr: MahjongBotShanten.Pairs) {
        val c = counts.copyOf()
        for (d in out) {
            if (d.shanten != tier) continue
            val b = calc.removing(b14, pr, c, d.kind)
            c[d.kind] -= 1
            val (uke, kinds) = calc.ukeire(b, c, unseen)
            d.ukeire = uke
            d.kinds = kinds
            d.score = uke.toDouble()
            if (tier == 0) scoreTenpai(d, b)
            c[d.kind] += 1
        }
    }

    /** 텐파이 버림: 후리텐이면 감점 · 울은 손은 역 있는 대기만 센다 · 손 값. */
    fun scoreTenpai(d: MahjongBotDiscard, b: MahjongBotShanten.Base) {
        val closed = removing(d.tile, hand)
        val rivers = ownDiscardKinds + d.kind
        val c = counts.copyOf()
        c[d.kind] -= 1
        d.furiten = (0 until 34).any { w -> w in rivers && c[w] < 4 && calc.shanten(b, c, w, 1) < 0 }
        val dama = mutableListOf<Pair<Int, String>>()
        val withRiichi = mutableListOf<Int>()
        var winnable = 0
        for (w in d.kinds) {
            val win = syntheticTile(w, closed) ?: continue
            val s = evaluate(closed, win, menzen) ?: continue
            if (!s.agari) continue
            val full = s.total - s.honbaBonus - s.kyoutakuBonus
            if (!menzen) {
                dama += full to s.limit
                winnable += unseen[w]
                continue
            }
            withRiichi += full
            if (s.yakuman > 0) {
                dama += full to s.limit
            } else {
                val r = s.yaku.firstOrNull { it.yaku == MahjongYaku.riichi }
                if (r != null && s.yaku.size > 1) {
                    val sc = MahjongScoring.scoreOf(s.han - r.han, s.fu, isDealer, tsumo = false)
                    dama += sc.total to sc.limit
                }
            }
        }
        d.hasYakuDama = dama.isNotEmpty() && dama.size == d.kinds.size
        d.damaMangan = d.hasYakuDama && dama.all { it.second.isNotEmpty() }
        d.value = if (dama.isEmpty()) 0 else dama.sumOf { it.first } / dama.size
        d.valueRiichi = if (withRiichi.isEmpty()) d.value else withRiichi.sum() / withRiichi.size
        if (!menzen) d.score = winnable.toDouble()
        if (d.furiten) d.score *= 0.3
    }

    /** 1샹텐에서만 2단 보기(유효패 많은 넷까지). 마감을 넘기면 멈추고 1단 결과로 되돌린다. */
    fun lookahead(cands: List<MahjongBotDiscard>) {
        val m = melds.size
        val ones = cands.indices.filter { cands[it].shanten == 1 && cands[it].ukeire > 0 }
            .sortedWith { x, y ->
                // Swift: (ukeire[x], kind[y]) > (ukeire[y], kind[x]) — 유효패 큰 쪽, 같으면 종류 작은 쪽 먼저.
                val ux = cands[x].ukeire
                val uy = cands[y].ukeire
                if (ux != uy) uy.compareTo(ux) else cands[x].kind.compareTo(cands[y].kind)
            }
            .take(lookaheadWidth)
        val extra = mutableListOf<Pair<Int, Double>>()
        for (i in ones) {
            val c = counts.copyOf()
            c[cands[i].kind] -= 1
            var sum = 0.0
            for (k in cands[i].kinds) {
                if (pastDeadline) {
                    lookaheadCut = true
                    return
                }
                c[k] += 1
                val b14 = calc.base(c, m)
                var best = 0
                for (e in 0 until 34) {
                    if (c[e] <= 0 || calc.shanten(b14, c, e, -1) != 0) continue
                    c[e] -= 1
                    best = maxOf(best, waitCount(c, m))
                    c[e] += 1
                }
                c[k] -= 1
                sum += (unseen[k] * best).toDouble()
            }
            extra += i to sum / 10
        }
        for ((i, x) in extra) cands[i].score += x
    }

    /** 텐파이 13장 꼴의 대기 남은 장수(기억). */
    fun waitCount(c: IntArray, m: Int): Int {
        val key = MahjongBotKey.of(c, m)
        waitMemo[key]?.let { return it }
        val cc = c.copyOf()
        val b = calc.base(cc, m)
        val v = calc.ukeire(b, cc, unseen).first
        waitMemo[key] = v
        return v
    }

    /** 동률 깨기 가치(낮을수록 먼저 버린다). */
    fun keepValue(tile: MahjongTile): Int {
        val k = tile.kind
        var v: Int
        if (k >= 27) {
            val yakuhai = MahjongBotRisk.isYakuhai(k, seatWindKind, roundWindKind)
            v = if (counts[k] >= 2) 6 else if (yakuhai) 1 else 0
        } else {
            val n = k % 9 + 1
            v = if (n == 1 || n == 9) 2 else if (n == 2 || n == 8) 3 else 4
        }
        if (k in doraKinds) v += 5
        if (tile.isRed) v += 5
        return v
    }

    // MARK: 밀기 · 접기

    sealed interface Stance {
        data class Attack(val capWorst: Double?) : Stance
        data class WeakTenpai(val safe: MahjongBotDiscard) : Stance
        data object Fold : Stance
    }

    fun stance(cands: List<MahjongBotDiscard>, bestShanten: Int): Stance {
        if (!policy.defends || threats.isEmpty()) return Stance.Attack(null)
        val riichiCount = threats.count { it.riichi }
        val tenpai = cands.filter { it.rankShanten == 0 }
        val bestTenpai = tenpai.maxWithOrNull(compareBy<MahjongBotDiscard>({ it.ukeire }, { it.valueRiichi }))
        val value = bestTenpai?.let { if (menzen) it.valueRiichi else it.value } ?: estimateValue()
        val bestUke = cands.filter { it.rankShanten == bestShanten }.maxOfOrNull { it.ukeire } ?: 0
        if (riichiCount >= 2) return if (bestShanten == 0 && value >= MahjongBot.pushValue) Stance.Attack(null) else Stance.Fold
        if (riichiCount == 1) {
            return when (bestShanten) {
                0 -> {
                    if (bestTenpai != null && bestTenpai.ukeire <= MahjongBot.weakTenpaiWaits && value < MahjongBot.weakTenpaiValue) {
                        val safe = tenpai.filter { it.danger == 0.0 }.maxByOrNull { it.ukeire }
                        if (safe != null) Stance.WeakTenpai(safe) else Stance.Fold
                    } else Stance.Attack(null)
                }
                1 -> {
                    if (value >= MahjongBot.pushValue && bestUke >= MahjongBot.pushUkeire &&
                        cands.any { it.rankShanten == 1 && it.worst <= MahjongBot.pushDangerCap }
                    ) Stance.Attack(MahjongBot.pushDangerCap) else Stance.Fold
                }
                else -> Stance.Fold
            }
        }
        if (bestShanten == 0) return Stance.Attack(null)
        return Stance.Attack(MahjongBotRisk.highDanger - 0.5)
    }

    /** 텐파이 전 손 값 어림: 확정 역 + 도라(적5 포함) + 멘젠이면 리치 1판, 30부 론. 울은 손에 확정 역이 없으면 0. */
    fun estimateValue(): Int {
        var han = 0
        val all = hand + melds.flatMap { it.tiles }
        han += all.count { it.kind in doraKinds }
        han += all.count { it.isRed }
        var yaku = 0
        for (k in 27 until 34) {
            if (!MahjongBotRisk.isYakuhai(k, seatWindKind, roundWindKind)) continue
            val inMeld = melds.any { it.type != MahjongMeldType.chi && it.tiles[0].kind == k }
            if (inMeld || counts[k] >= 3) yaku += if (k == seatWindKind && k == roundWindKind) 2 else 1
        }
        han += yaku
        if (menzen) han += 1 else if (yaku == 0) return 0
        return MahjongScoring.scoreOf(maxOf(1, han), 30, isDealer, tsumo = false).total
    }

    // MARK: 고르기

    /** Swift max(by:) 꼴 — 앞에서부터 보며 더 큰 것이 나올 때만 바꾼다(같은 값이면 앞의 것). */
    private fun <T> List<T>.maxWithOrNull(cmp: Comparator<T>): T? {
        if (isEmpty()) return null
        var best = this[0]
        for (i in 1 until size) if (cmp.compare(best, this[i]) < 0) best = this[i]
        return best
    }

    private fun List<MahjongBotDiscard>.maxByOrNull(sel: (MahjongBotDiscard) -> Int): MahjongBotDiscard? =
        maxWithOrNull(compareBy(sel))

    fun pickAttack(cands: List<MahjongBotDiscard>, rng: SwiftRandomSource): MahjongBotDiscard {
        val sh = cands.minOfOrNull { it.rankShanten } ?: 0
        val tier = cands.filter { it.rankShanten == sh }
        val top = tier.maxOfOrNull { it.score } ?: 0.0
        var near = tier.filter { it.score >= top - 1 }
        if (sh == 0) {
            val bestValue = near.maxOfOrNull { if (menzen) it.valueRiichi else it.value } ?: 0
            near = near.filter { (if (menzen) it.valueRiichi else it.value) >= bestValue }
        }
        val low = near.minOfOrNull { it.keep } ?: 0
        val pool = near.filter { it.keep == low }.sortedBy { it.tile.id }
        return pool[if (pool.size == 1) 0 else rng.nextIndex(pool.size)]
    }

    fun pickSafest(cands: List<MahjongBotDiscard>, rng: SwiftRandomSource): MahjongBotDiscard {
        val low = cands.minOfOrNull { it.danger } ?: 0.0
        return pickAttack(cands.filter { it.danger <= low + 1e-9 }, rng)
    }

    // MARK: - 울기 창

    private class CallOption(val answer: MahjongCallAnswer, val shanten: Int, val ukeire: Int, val red: Int)

    fun call(c: MahjongDecision.Call, rng: SwiftRandomSource): MahjongCallAnswer {
        if (c.ron) return MahjongCallAnswer.Ron
        if (inRiichi || !policy.calls || (c.pon.isEmpty() && c.chi.isEmpty())) return MahjongCallAnswer.Pass
        val m = melds.size
        val cur = shanten(counts, m)
        val calledKind = c.tile.kind
        if (menzen && cur == 0) return MahjongCallAnswer.Pass
        if (threats.any { it.riichi } && cur >= 2) return MahjongCallAnswer.Pass
        if (threats.isEmpty() && MahjongBotRisk.isYakuhai(calledKind, seatWindKind, roundWindKind)) {
            // Swift min(by:) 는 같은 값이면 앞의 것.
            val pair = c.pon.minByOrNull { redCount(it) }
            if (pair != null) return MahjongCallAnswer.Pon(pair)
        }
        val best = mutableListOf<CallOption>()
        fun consider(type: MahjongMeldType, fromHand: List<MahjongTile>) {
            val after = counts.copyOf()
            for (t in fromHand) after[t.kind] -= 1
            if (!after.all { it >= 0 }) return
            val newMeld = MahjongMeld(type, (fromHand + c.tile).sorted(), c.tile, c.fromSeat)
            if (!confirmedYaku(after, melds + newMeld, calledKind)) return
            val banned = MahjongRules.kuikaeForbidden(type, c.tile, fromHand).toSet()
            val b = calc.base(after, m + 1)
            var bestSh = 9
            val bestDiscards = mutableListOf<Int>()
            for (d in 0 until 34) {
                if (after[d] <= 0 || d in banned) continue
                val sh = calc.shanten(b, after, d, -1)
                if (sh < bestSh) {
                    bestSh = sh
                    bestDiscards.clear()
                    bestDiscards += d
                } else if (sh == bestSh) {
                    bestDiscards += d
                }
            }
            if (bestSh >= cur) return
            var bestUke = 0
            for (d in bestDiscards) {
                after[d] -= 1
                val b2 = calc.base(after, m + 1)
                bestUke = maxOf(bestUke, calc.ukeire(b2, after, unseen).first)
                after[d] += 1
            }
            best += CallOption(
                if (type == MahjongMeldType.pon) MahjongCallAnswer.Pon(fromHand) else MahjongCallAnswer.Chi(fromHand),
                bestSh, bestUke, redCount(fromHand),
            )
        }
        for (pair in c.pon) consider(MahjongMeldType.pon, pair)
        for (pair in c.chi) consider(MahjongMeldType.chi, pair)
        if (best.isEmpty()) return MahjongCallAnswer.Pass
        val sh = best.minOf { it.shanten }
        val tier = best.filter { it.shanten == sh }
        val top = tier.maxOf { it.ukeire }
        val near = tier.filter { it.ukeire >= top - 1 }
        val fewRed = near.minOf { it.red }
        val pool = near.filter { it.red == fewRed }
        return pool[if (pool.size == 1) 0 else rng.nextIndex(pool.size)].answer
    }

    /** 울고 난 손에 확정 역이 있는가: 역패 커쯔 · 쿠이탄(요구패 1장 이하) · 혼일색(한 색 + 자패 11장 이상). */
    fun confirmedYaku(after: IntArray, all: List<MahjongMeld>, calledKind: Int): Boolean {
        fun yakuhai(k: Int) = MahjongBotRisk.isYakuhai(k, seatWindKind, roundWindKind)
        if (all.any { it.type != MahjongMeldType.chi && yakuhai(it.tiles[0].kind) }) return true
        if ((27 until 34).any { yakuhai(it) && after[it] >= 3 }) return true
        val yaochu = MahjongTiles.yaochu.toSet()
        val meldKinds = all.flatMap { m -> m.tiles.map { it.kind } }
        if (meldKinds.none { it in yaochu }) {
            val left = yaochu.sumOf { after[it] }
            if (left <= 1) return true
        }
        for (s in 0 until 3) {
            fun inColor(k: Int) = k >= 27 || k / 9 == s
            if (!inColor(calledKind) || !meldKinds.all(::inColor)) continue
            val handIn = (0 until 34).filter(::inColor).sumOf { after[it] }
            val meldIn = all.size * 3
            if (handIn + meldIn >= 11) return true
        }
        return false
    }

    // MARK: - 손 계산 도우미

    fun removing(tile: MahjongTile, tiles: List<MahjongTile>): List<MahjongTile> {
        val out = tiles.toMutableList()
        val i = out.indexOf(tile)
        if (i >= 0) out.removeAt(i)
        return out
    }

    /** 대기 종류 w 의 가상 화료패 — 내 손 · 부로에 없는 id(적5 를 피해 c 3 · 2 · 1 · 0 순). */
    fun syntheticTile(w: Int, closed: List<MahjongTile>): MahjongTile? {
        val taken = (closed + melds.flatMap { it.tiles }).map { it.id }.toSet()
        for (c in listOf(3, 2, 1, 0)) if ((w * 4 + c) !in taken) return MahjongTile.of(w * 4 + c)
        return null
    }

    fun evaluate(closed: List<MahjongTile>, win: MahjongTile, riichi: Boolean): MahjongScore? {
        val ctx = MahjongWinContext(
            closed = closed, melds = melds, win = win, tsumo = false, seatWind = seatWind, roundWind = roundWind,
            riichi = riichi, doraIndicators = doraIndicators,
        )
        return (MahjongScoring.evaluate(ctx) as? MahjongEvaluation.Success)?.score
    }
}

/** 34칸 장수 + 손 밖 몸통 수를 두 낱말로 접은 기억 열쇠. */
internal data class MahjongBotKey(val a: ULong, val b: ULong) {
    companion object {
        fun of(c: IntArray, melds: Int): MahjongBotKey {
            var a = 0uL
            var b = (melds and 7).toULong()
            for (i in 0 until 20) a = (a shl 3) or (c[i] and 7).toULong()
            for (i in 20 until 34) b = (b shl 3) or (c[i] and 7).toULong()
            return MahjongBotKey(a, b)
        }
    }
}

/** 봇 전용 샹텐 셈. 값은 MahjongHand.shanten 과 같다 — 색 비용 표를 그대로 쓰고 합치는 길만 다르다(표 10칸을 6비트씩 ULong 하나에). */
internal class MahjongBotShanten {
    private val suits = HashMap<Int, ULong>()
    private val honors = HashMap<Int, ULong>()

    companion object {
        const val none = 63
        val allNone: ULong = (0 until 10).fold(0uL) { acc, i -> acc or (none.toULong() shl (6 * i)) }
        val pow5 = intArrayOf(390_625, 78_125, 15_625, 3_125, 625, 125, 25, 5, 1)
        val pow5h = intArrayOf(15_625, 3_125, 625, 125, 25, 5, 1)
        val isYaochu: BooleanArray = BooleanArray(34) { it in MahjongTiles.yaochu }

        fun pack(t: IntArray): ULong {
            var out = 0uL
            for (i in 0 until 10) out = out or (minOf(t[i], none).toULong() shl (6 * i))
            return out
        }

        fun cell(a: ULong, i: Int): Int = ((a shr (6 * i)) and 63uL).toInt()

        fun knap(a: ULong, b: ULong): ULong {
            var out = allNone
            var i1 = 0
            while (i1 < 10) {
                val x = cell(a, i1)
                if (x < none) {
                    var i2 = 0
                    while (i1 + i2 < 10) {
                        if (i1 and i2 and 1 == 0) {
                            val y = cell(b, i2)
                            if (y < none) {
                                val shift = 6 * (i1 + i2)
                                if (x + y < ((out shr shift) and 63uL).toInt()) {
                                    out = (out and (63uL shl shift).inv()) or ((x + y).toULong() shl shift)
                                }
                            }
                        }
                        i2 += 1
                    }
                }
                i1 += 1
            }
            return out
        }

        fun pick(a: ULong, b: ULong, target: Int): Int {
            var best = 2 * none
            var i1 = 0
            while (i1 <= target) {
                val x = cell(a, i1)
                val y = cell(b, target - i1)
                if (x < none && y < none && x + y < best) best = x + y
                i1 += 1
            }
            return best
        }

        fun code(c: IntArray, s: Int): Int {
            var code = 0
            for (i in s * 9 until s * 9 + 9) code = code * 5 + c[i].coerceIn(0, 4)
            return code
        }

        fun honorCode(c: IntArray): Int {
            var code = 0
            for (k in 27 until 34) code = code * 5 + c[k].coerceIn(0, 4)
            return code
        }

        data class Forms(val pairs: Int, val kinds: Int, val yk: Int, val yp: Int)

        fun forms(c: IntArray): Forms {
            var pairs = 0
            var kinds = 0
            var yk = 0
            var yp = 0
            for (k in 0 until 34) {
                val n = c[k]
                if (n >= 2) pairs += 1
                if (n >= 1) kinds += 1
                if (isYaochu[k]) {
                    if (n >= 1) yk += 1
                    if (n >= 2) yp += 1
                }
            }
            return Forms(pairs, kinds, yk, yp)
        }

        fun other(pairs: Int, kinds: Int, yk: Int, yp: Int): Int = minOf(6 - pairs + maxOf(0, 7 - kinds), 13 - yk - (if (yp > 0) 1 else 0))

        fun near(c: IntArray, k: Int): Boolean {
            if (c[k] > 0) return true
            if (k >= 27) return false
            val n = k % 9
            var i = k - minOf(n, 2)
            val hi = k + minOf(8 - n, 2)
            while (i <= hi) {
                if (c[i] > 0) return true
                i += 1
            }
            return false
        }
    }

    /** 한 손의 부분 합. */
    data class Base(
        val melds: Int, val target: Int,
        val t0: ULong, val t1: ULong, val t2: ULong, val th: ULong,
        val code0: Int, val code1: Int, val code2: Int, val codeH: Int,
        val rest0: ULong, val rest1: ULong, val rest2: ULong, val restH: ULong,
        val pairs: Int, val kinds: Int, val yaochuKinds: Int, val yaochuPairs: Int,
        val shanten: Int, val wide: Boolean, val valid: Boolean,
    ) {
        companion object {
            val invalid = Base(0, 1, 0uL, 0uL, 0uL, 0uL, 0, 0, 0, 0, 0uL, 0uL, 0uL, 0uL, 0, 0, 0, 0, 8, false, false)
        }
    }

    data class Pairs(val k01: ULong, val k02: ULong, val k12: ULong, val k0h: ULong, val k1h: ULong, val k2h: ULong)

    fun suitTable(c: IntArray, s: Int, code: Int): ULong = suits.getOrPut(code) { pack(ShantenTable.suitCost(c, s * 9)) }

    fun honorTable(c: IntArray, code: Int): ULong = honors.getOrPut(code) {
        var acc = ShantenTable.identity
        for (k in 27 until 34) acc = ShantenTable.knap(acc, ShantenTable.honorCost(c[k]))
        pack(acc)
    }

    fun base(c: IntArray, m: Int): Base {
        if (c.size != 34 || m !in 0..4) return Base.invalid
        val c0 = code(c, 0)
        val c1 = code(c, 1)
        val c2 = code(c, 2)
        val ch = honorCode(c)
        val t0 = suitTable(c, 0, c0)
        val t1 = suitTable(c, 1, c1)
        val t2 = suitTable(c, 2, c2)
        val h = honorTable(c, ch)
        val k01 = knap(t0, t1)
        val restH = knap(k01, t2)
        val target = (4 - m) * 2 + 1
        val f = forms(c)
        var sh = pick(restH, h, target) - 1
        var wide = false
        if (m == 0) {
            val o = other(f.pairs, f.kinds, f.yk, f.yp)
            wide = o <= sh
            sh = minOf(sh, o)
        }
        return Base(
            m, target, t0, t1, t2, h, c0, c1, c2, ch,
            knap(knap(t1, t2), h), knap(knap(t0, t2), h), knap(k01, h), restH,
            f.pairs, f.kinds, f.yk, f.yp, sh, wide, true,
        )
    }

    fun pairs(b: Base): Pairs = Pairs(knap(b.t0, b.t1), knap(b.t0, b.t2), knap(b.t1, b.t2), knap(b.t0, b.th), knap(b.t1, b.th), knap(b.t2, b.th))

    /** 종류 k 를 delta 만큼 바꾼 그 부분의 (표, 열쇠). c 는 바뀌지 않은 손(잠시 바꿨다 되돌린다). */
    fun changedTable(b: Base, c: IntArray, k: Int, delta: Int): Pair<ULong, Int> {
        if (k < 27) {
            val s = k / 9
            val code = (if (s == 0) b.code0 else if (s == 1) b.code1 else b.code2) + delta * pow5[k - s * 9]
            suits[code]?.let { return it to code }
            c[k] += delta
            val t = suitTable(c, s, code)
            c[k] -= delta
            return t to code
        }
        val code = b.codeH + delta * pow5h[k - 27]
        honors[code]?.let { return it to code }
        c[k] += delta
        val t = honorTable(c, code)
        c[k] -= delta
        return t to code
    }

    /** base 의 손 c 에서 종류 k 를 delta(±1)만큼 바꾼 손의 샹텐. c 는 그대로 둔다. */
    fun shanten(b: Base, c: IntArray, k: Int, delta: Int): Int {
        if (!b.valid) return 8
        val old = c[k]
        val new = old + delta
        if (new < 0 || new > 4) return 8
        val (table, _) = changedTable(b, c, k, delta)
        val rest = if (k < 9) b.rest0 else if (k < 18) b.rest1 else if (k < 27) b.rest2 else b.restH
        var v = pick(rest, table, b.target) - 1
        if (b.melds == 0) {
            val pairs = b.pairs + (if (new >= 2) 1 else 0) - (if (old >= 2) 1 else 0)
            val kinds = b.kinds + (if (new >= 1) 1 else 0) - (if (old >= 1) 1 else 0)
            var yk = b.yaochuKinds
            var yp = b.yaochuPairs
            if (isYaochu[k]) {
                yk += (if (new >= 1) 1 else 0) - (if (old >= 1) 1 else 0)
                yp += (if (new >= 2) 1 else 0) - (if (old >= 2) 1 else 0)
            }
            v = minOf(v, other(pairs, kinds, yk, yp))
        }
        return v
    }

    /** 14장 꼴 b(부분 합 pr)에서 종류 d 한 장을 뺀 13장 꼴의 Base. */
    fun removing(b: Base, pr: Pairs, c: IntArray, d: Int): Base {
        if (!b.valid || c[d] <= 0) return Base.invalid
        val (t, code) = changedTable(b, c, d, -1)
        var t0 = b.t0
        var t1 = b.t1
        var t2 = b.t2
        var th = b.th
        var c0 = b.code0
        var c1 = b.code1
        var c2 = b.code2
        var ch = b.codeH
        var r0 = b.rest0
        var r1 = b.rest1
        var r2 = b.rest2
        var rh = b.restH
        when (d) {
            in 0 until 9 -> { t0 = t; c0 = code; r1 = knap(t, pr.k2h); r2 = knap(t, pr.k1h); rh = knap(t, pr.k12) }
            in 9 until 18 -> { t1 = t; c1 = code; r0 = knap(t, pr.k2h); r2 = knap(t, pr.k0h); rh = knap(t, pr.k02) }
            in 18 until 27 -> { t2 = t; c2 = code; r0 = knap(t, pr.k1h); r1 = knap(t, pr.k0h); rh = knap(t, pr.k01) }
            else -> { th = t; ch = code; r0 = knap(t, pr.k12); r1 = knap(t, pr.k02); r2 = knap(t, pr.k01) }
        }
        val old = c[d]
        val new = old - 1
        val pairs = b.pairs + (if (new >= 2) 1 else 0) - (if (old >= 2) 1 else 0)
        val kinds = b.kinds + (if (new >= 1) 1 else 0) - (if (old >= 1) 1 else 0)
        var yk = b.yaochuKinds
        var yp = b.yaochuPairs
        if (isYaochu[d]) {
            yk += (if (new >= 1) 1 else 0) - (if (old >= 1) 1 else 0)
            yp += (if (new >= 2) 1 else 0) - (if (old >= 2) 1 else 0)
        }
        var sh = pick(rh, th, b.target) - 1
        var wide = false
        if (b.melds == 0) {
            val o = other(pairs, kinds, yk, yp)
            wide = o <= sh
            sh = minOf(sh, o)
        }
        return Base(b.melds, b.target, t0, t1, t2, th, c0, c1, c2, ch, r0, r1, r2, rh, pairs, kinds, yk, yp, sh, wide, true)
    }

    /** 13장 꼴(base 의 손 c)의 유효패 — 샹텐을 줄이는 종류마다 남은 장수 u. (장수 합, 종류 목록). */
    fun ukeire(b: Base, c: IntArray, u: IntArray): Pair<Int, List<Int>> {
        var total = 0
        val kinds = mutableListOf<Int>()
        for (k in 0 until 34) {
            if (c[k] < 4 && u[k] > 0 && (b.wide || near(c, k)) && shanten(b, c, k, 1) < b.shanten) {
                total += u[k]
                kinds += k
            }
        }
        return total to kinds
    }
}
