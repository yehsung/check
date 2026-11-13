// 원본: Sources/CheckCore/MahjongTableEngineHand.swift @ e4995a3a(한 국의 흐름 — 배패 · 선택지 · 따라잡기 · 버림 · 깡 · 창 · 국 끝) — Android 판 8
//
// 흐름 약속(table_ref · SQL · Swift 가 같은 문장을 옮긴다):
//  · 창(버림 · 가깡 · 암깡)은 열 때 선택지를 한 번 계산하고, 자리 비움 자리의 선택지는 곧바로 pass.
//  · 창이 론 없이 닫히면: ① 놓친 화료패 → 동순(리치면 리치) 후리텐 ② 리치 선언패면 리치 성립(−1000 · 공탁 +1) → 사가리치면 유국
//    ③ 사깡유국(울기보다 먼저) ④ 넘김/울기 적용.
//  · 깡도라: 앞 깡의 미뤄 둔 표시패는 타패 순간 또는 새 깡 선언 직전에. 암깡은 선언 때, 대명깡 · 가깡은 그 사람 타패 때.
//  · 일발은 리치 성립 때 켜고, 그 사람의 다음 타패 · 누구의 울기 · 깡 성립에 끈다.
//  · 시간 초과: 차례 — 쯔모 > 뽑은 패 > 허용 패 중 최대 id. 울기 — 론 > 넘김. 자리 비움 자리는 화료하지 않는다.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimAnswer
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimResolution
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFuriten
import com.yehsung.aingcheck.core.rules.mahjong.MahjongHand
import com.yehsung.aingcheck.core.rules.mahjong.MahjongHandOutcome
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeld
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeldType
import com.yehsung.aingcheck.core.rules.mahjong.MahjongPao
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRonWin
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongScore
import com.yehsung.aingcheck.core.rules.mahjong.MahjongScoring
import com.yehsung.aingcheck.core.rules.mahjong.MahjongEvaluation
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTimeoutAction
import com.yehsung.aingcheck.core.rules.mahjong.MahjongWind
import com.yehsung.aingcheck.core.rules.mahjong.MahjongWinContext
import com.yehsung.aingcheck.core.rules.mahjong.MahjongYaku
import com.yehsung.aingcheck.core.stores.mahjong.MahjongTableEngine.Companion.tile
import com.yehsung.aingcheck.core.stores.mahjong.MahjongTableEngine.Companion.tiles

// MARK: - 안쪽 타입

internal enum class Stage { idle, turn, claim, draw, handEnd, finished }

internal enum class WindowKind(val rawValue: String) { discard("discard"), kakan("kakan"), ankan("ankan") }

internal data class EngineMeld(val type: MahjongMeldType, val tiles: List<Int>, val called: Int?, val fromSeat: Int?) {
    val meld: MahjongMeld get() = MahjongMeld(type, tiles(tiles), called?.let(::tile), fromSeat)
}

internal data class DiscardRow(val tile: Int, val tsumogiri: Boolean, val riichi: Boolean, var taken: Boolean)

internal class Seat(val no: Int) {
    var away = false
    var awayReason: MahjongAwayReason? = null
    var awaySinceMs: Double? = null
    var streak = 0
    /** 손 안 패 id(쯔모패 제외), 오름차순. */
    var hand: MutableList<Int> = mutableListOf()
    var drawn: Int? = null
    val melds: MutableList<EngineMeld> = mutableListOf()
    val discards: MutableList<DiscardRow> = mutableListOf()
    /** 리치 성립. */
    var riichi = false
    /** 선언패를 버렸고 그 창이 아직 안 닫힘. */
    var declared = false
    var doublePending = false
    var doubleRiichi = false
    var ippatsu = false
    var furiten = MahjongFuriten()
    /** 대기 종류(자기 버림 때 다시 잰다). */
    var waits: List<Int> = emptyList()
    var discardedOnce = false
    /** 쿠이카에 금지 종류(치 · 퐁 직후). */
    var kuikae: List<Int> = emptyList()
    var pao: MahjongPao? = null

    fun resetHand() {
        hand = mutableListOf()
        drawn = null
        melds.clear()
        discards.clear()
        riichi = false
        declared = false
        doublePending = false
        doubleRiichi = false
        ippatsu = false
        furiten = MahjongFuriten()
        waits = emptyList()
        discardedOnce = false
        kuikae = emptyList()
        pao = null
    }

    val closed14: List<Int> get() = hand + listOfNotNull(drawn)
    val menzen: Boolean get() = melds.all { it.type == MahjongMeldType.ankan }
}

internal data class CallOptions(
    var ron: Boolean = false,
    var pon: MutableList<List<Int>> = mutableListOf(),
    var minkan: List<List<Int>> = emptyList(),
    var chi: MutableList<List<Int>> = mutableListOf(),
) {
    /** resolveClaims 에 넘길 고를 수 있는 것. */
    val kinds: List<MahjongClaimKind>
        get() = buildList {
            if (ron) add(MahjongClaimKind.ron)
            if (pon.isNotEmpty()) add(MahjongClaimKind.pon)
            if (minkan.isNotEmpty()) add(MahjongClaimKind.minkan)
            if (chi.isNotEmpty()) add(MahjongClaimKind.chi)
        }
}

internal data class TurnOptions(
    var discard: List<Int> = emptyList(),
    var riichi: List<Int> = emptyList(),
    var tsumo: Boolean = false,
    var ankan: List<List<Int>> = emptyList(),
    var kakan: List<Int> = emptyList(),
    var kyuushu: Boolean = false,
)

internal class Window(
    val id: Int,
    val kind: WindowKind,
    val from: Int,
    val tile: Int,
    val houtei: Boolean,
    val order: List<Int>,
    /** 가깡 창이면 더해질 퐁의 자리(melds 안 번호). */
    val kakanMeld: Int?,
) {
    val options: MutableMap<Int, CallOptions> = linkedMapOf()
    val answers: MutableMap<Int, MahjongClaimAnswer> = linkedMapOf()
    val chosen: MutableMap<Int, List<Int>> = linkedMapOf()
}

internal data class PendingDraw(val seat: Int, val rinshan: Boolean, val born: Int)

internal data class HandRecord(val result: MahjongHandResult, val advance: com.yehsung.aingcheck.core.rules.mahjong.MahjongAdvance, val kyotakuAfter: Int)

internal data class FinalRecord(val endReason: String, val order: List<Int>, val ranks: List<Int>, val finalScores: List<Int>, val kyotaku: Int)

internal data class WinFlags(
    var rinshan: Boolean = false, var haitei: Boolean = false, var houtei: Boolean = false,
    var chankan: Boolean = false, var heavenly: Boolean = false, var earthly: Boolean = false,
)

/** 판 진행이 되풀이해 묻는 순수 판정(대기 · 리치 선언 종류)의 기억 — 엔진마다 하나(잠금 없는 공용 기억은 두지 않는다). */
internal class MahjongEngineMemo {
    private val store = HashMap<String, List<Int>>()

    fun value(table: Int, counts: IntArray, melds: Int, compute: () -> List<Int>): List<Int> {
        val key = buildString {
            append(table); append(':'); append(melds); append(':')
            for (c in counts) append(c.coerceIn(0, 9))
        }
        store[key]?.let { return it }
        val v = compute()
        if (store.size >= CAPACITY) store.clear()
        store[key] = v
        return v
    }

    companion object {
        const val CAPACITY = 200_000
    }
}

internal val redIDs: Set<Int> = setOf(16, 52, 88)

internal fun engineCounts(ids: List<Int>): IntArray = IntArray(34).also { c -> ids.forEach { c[it / 4] += 1 } }

/** 같은 종류 id 묶음에서 n 장 고르기 — 적5 여부가 같은 고르기는 하나만(작은 id 먼저, 사전순 조합 순서). */
internal fun uniqueCombos(ids: List<Int>, n: Int): List<List<Int>> {
    val s = ids.sorted()
    val out = mutableListOf<List<Int>>()
    val seen = mutableListOf<List<Boolean>>()
    fun walk(start: Int, pick: List<Int>) {
        if (pick.size == n) {
            val key = pick.map { it in redIDs }
            if (key !in seen) {
                seen += key
                out += pick
            }
            return
        }
        if (start >= s.size) return
        for (i in start until s.size) walk(i + 1, pick + s[i])
    }
    walk(0, emptyList())
    return out
}

// MARK: - 작은 도우미

internal val MahjongTableEngine.dealer: Int get() = handNo

/** 살아 있는 산 남은 장수(마지막 = 121 − 깡 수). */
internal val MahjongTableEngine.liveLeft: Int get() = (121 - kans) - ptr + 1

internal val MahjongTableEngine.indicators: List<Int> get() = (0 until timer.open).map { wall[126 + it] }

internal val MahjongTableEngine.uraIndicators: List<Int> get() = (0 until timer.open).map { wall[131 + it] }

internal val MahjongTableEngine.allAway: Boolean get() = seatState.all { it.away }

/** 대기 종류 — 같은 꼴은 기억해 둔 값. */
internal fun MahjongTableEngine.engineWaits(ids: List<Int>, melds: Int): List<Int> {
    val c = engineCounts(ids)
    return memo.value(0, c, melds) { MahjongHand.waits(c, melds) }
}

/** 버려서 텐파이가 되는 종류. 14장 샹텐이 1 이상이면 [] — 대기 14번을 매 차례 돌지 않게. */
internal fun MahjongTableEngine.riichiKinds(c14: List<Int>, ankans: Int): List<Int> {
    val c = engineCounts(c14)
    return memo.value(1, c, ankans) {
        if (MahjongHand.shanten(c, ankans) > 0) emptyList()
        else MahjongRules.riichiDiscards(tiles(c14), ankans, 1000, 4, menzen = true, already = false)
    }
}

internal fun MahjongTableEngine.emit(kind: String, seat: Int? = null, fill: (MahjongEvent) -> MahjongEvent = { it }) {
    seqValue += 1
    log += fill(MahjongEvent(seq = seqValue, kind = kind, seat = seat, atMs = nowMs))
}

internal fun MahjongTableEngine.flushDora() {
    val old = timer.open
    timer = timer.discard()
    for (i in old until maxOf(old, timer.open)) {
        val t = wall[126 + i]
        emit("dora") { it.copy(indicator = tile(t)) }
    }
}

internal fun MahjongTableEngine.timerKan(type: MahjongMeldType) {
    val old = timer.open
    timer = timer.kan(type)
    for (i in old until maxOf(old, timer.open)) {
        val t = wall[126 + i]
        emit("dora") { it.copy(indicator = tile(t)) }
    }
}

internal fun MahjongTableEngine.clearIppatsu() {
    for (s in seatState) s.ippatsu = false
}

// MARK: - 배패(MJ-08)

internal fun MahjongTableEngine.dealHand(w: List<Int>) {
    wall = w
    ptr = 53
    kans = 0
    kanSeats.clear()
    rinshanUsed = 0
    timer = com.yehsung.aingcheck.core.rules.mahjong.MahjongDoraTimer()
    firstUninterrupted = true
    firstDiscards.clear()
    window = null
    pendingDraw = null
    for (s in seatState) s.resetHand()
    for (j in 0 until 4) {
        val n = (dealer + j) % 4
        seatState[n].hand = w.subList(13 * j, 13 * j + 13).sorted().toMutableList()
    }
    seatState[dealer].drawn = w[52]
    for (n in 0 until 4) if (n != dealer) seatState[n].waits = engineWaits(seatState[n].hand, 0)
    val hi = handIndexValue
    val r = round
    val hn = handNo
    val hb = honba
    val kt = kyotaku
    val d = dealer
    emit("deal") { it.copy(handIndex = hi, round = r, handNo = hn, honba = hb, kyotaku = kt, dealerSeat = d, dora = listOf(tile(w[126]))) }
    turnSeat = dealer
    turnRinshan = false
    stage = Stage.turn
    decisionSeqValue = seqValue
}

internal fun MahjongTableEngine.startNext(w: List<Int>) {
    val n = nextHand
    if (stage != Stage.handEnd || n == null) return
    round = n.round
    handNo = n.hand
    honba = n.honba
    handIndexValue += 1
    dealHand(w)
}

// MARK: - 손 계산

internal fun MahjongTableEngine.evaluate(seat: Int, win: Int, tsumo: Boolean, f: WinFlags): MahjongScore? {
    val s = seatState[seat]
    val ctx = MahjongWinContext(
        closed = tiles(s.hand), melds = s.melds.map { it.meld }, win = tile(win), tsumo = tsumo,
        seatWind = MahjongWind.entries[(seat - dealer + 4) % 4], roundWind = MahjongWind.entries[round % 4],
        riichi = s.riichi, doubleRiichi = s.doubleRiichi, ippatsu = s.ippatsu, rinshan = f.rinshan, chankan = f.chankan,
        haitei = f.haitei, houtei = f.houtei, heavenly = f.heavenly, earthly = f.earthly,
        doraIndicators = tiles(indicators), uraIndicators = if (s.riichi) tiles(uraIndicators) else emptyList(),
        honba = honba, kyoutaku = kyotaku,
    )
    return (MahjongScoring.evaluate(ctx) as? MahjongEvaluation.Success)?.score
}

internal fun MahjongTableEngine.tsumoFlags(seat: Int): WinFlags {
    val f = WinFlags()
    if (turnRinshan) f.rinshan = true else if (liveLeft == 0) f.haitei = true
    if (firstUninterrupted && !seatState[seat].discardedOnce && !turnRinshan) {
        if (seat == dealer) f.heavenly = true else f.earthly = true
    }
    return f
}

internal fun ronFlags(kind: WindowKind, houtei: Boolean): WinFlags {
    val f = WinFlags()
    if (kind == WindowKind.kakan || kind == WindowKind.ankan) f.chankan = true else if (houtei) f.houtei = true
    return f
}

// MARK: - 차례 선택지

/** 버릴 수 있는 패. 치 · 퐁 직후는 쿠이카에 금지 종류를 뺀 손패, 리치 중이면 뽑은 패만. */
internal fun MahjongTableEngine.discardOptions(seat: Int): List<Int> {
    val s = seatState[seat]
    val drawn = s.drawn ?: return s.hand.filter { (it / 4) !in s.kuikae }.sorted()
    return if (s.riichi) listOf(drawn) else s.closed14.sorted()
}

internal fun MahjongTableEngine.tsumoOption(seat: Int): Boolean {
    val s = seatState[seat]
    val drawn = s.drawn ?: return false
    if ((drawn / 4) !in engineWaits(s.hand, s.melds.size)) return false
    return evaluate(seat, drawn, true, tsumoFlags(seat))?.agari ?: false
}

internal fun MahjongTableEngine.riichiOptions(seat: Int): List<Int> {
    val s = seatState[seat]
    if (s.drawn == null || s.riichi || !s.menzen || points[seat] < 1000 || liveLeft < 4) return emptyList()
    val c14 = s.closed14
    val ks = riichiKinds(c14, s.melds.size).toSet()
    return c14.filter { (it / 4) in ks }.sorted()
}

internal fun MahjongTableEngine.ankanOptions(seat: Int): List<List<Int>> {
    val s = seatState[seat]
    val drawn = s.drawn ?: return emptyList()
    if (liveLeft < 1 || kans >= 4) return emptyList()
    val c14 = s.closed14
    val cnt = engineCounts(c14)
    val out = mutableListOf<List<Int>>()
    for (k in 0 until 34) {
        if (cnt[k] != 4) continue
        if (s.riichi) {
            if (k != drawn / 4) continue
            if (!MahjongRules.riichiAnkanOK(tiles(s.hand), tile(drawn), drawn / 4, s.melds.size)) continue
        }
        out += c14.filter { it / 4 == k }.sorted()
    }
    return out
}

internal fun MahjongTableEngine.kakanOptions(seat: Int): List<Int> {
    val s = seatState[seat]
    if (s.drawn == null || liveLeft < 1 || kans >= 4 || s.riichi) return emptyList()
    val c14 = s.closed14
    val out = mutableListOf<Int>()
    for (m in s.melds) {
        if (m.type != MahjongMeldType.pon) continue
        val k = m.tiles[0] / 4
        out += c14.filter { it / 4 == k }
    }
    return out.sorted()
}

internal fun MahjongTableEngine.kyuushuOption(seat: Int): Boolean {
    val s = seatState[seat]
    if (s.drawn == null || !firstUninterrupted || s.discardedOnce || turnRinshan) return false
    return MahjongRules.kyuushuOK(tiles(s.closed14), firstTurnUninterrupted = true)
}

internal fun MahjongTableEngine.turnOptions(seat: Int): TurnOptions {
    val o = TurnOptions(discard = discardOptions(seat))
    if (seatState[seat].drawn == null) return o
    o.tsumo = tsumoOption(seat)
    o.riichi = riichiOptions(seat)
    o.ankan = ankanOptions(seat)
    o.kakan = kakanOptions(seat)
    o.kyuushu = kyuushuOption(seat)
    return o
}

// MARK: - 울기 선택지

internal fun MahjongTableEngine.callOptions(seat: Int, kind: WindowKind, d: Int, tileId: Int, houtei: Boolean): CallOptions {
    val s = seatState[seat]
    val k = tileId / 4
    val res = CallOptions()
    if (kind == WindowKind.ankan) {
        if (s.melds.isEmpty() && kokushiOn(seat, k) && s.furiten.canRon(s.waits)) {
            res.ron = evaluate(seat, tileId, false, WinFlags(chankan = true))?.agari ?: false
        }
        return res
    }
    if (k in s.waits && s.furiten.canRon(s.waits)) {
        res.ron = evaluate(seat, tileId, false, ronFlags(kind, houtei))?.agari ?: false
    }
    if (kind != WindowKind.discard || houtei || s.riichi) return res
    val same = s.hand.filter { it / 4 == k }
    fun rest(used: List<Int>): List<Int> = s.hand.filter { it !in used }
    val called = tile(tileId)
    if (same.size >= 2) {
        for (c in uniqueCombos(same, 2)) {
            if (MahjongRules.callAllowed(MahjongMeldType.pon, called, tiles(c), tiles(rest(c)))) res.pon += c
        }
    }
    if (same.size >= 3 && kans < 4) res.minkan = uniqueCombos(same, 3)
    if (seat == (d + 1) % 4 && k < 27) {
        val suit = k / 9
        for ((a, b) in listOf((k - 2) to (k - 1), (k - 1) to (k + 1), (k + 1) to (k + 2))) {
            if (!(suit * 9 <= a && a < suit * 9 + 9 && suit * 9 <= b && b < suit * 9 + 9)) continue
            val ia = s.hand.filter { it / 4 == a }
            val ib = s.hand.filter { it / 4 == b }
            for (x in uniqueCombos(ia, 1)) {
                for (y in uniqueCombos(ib, 1)) {
                    val c = (x + y).sorted()
                    if (MahjongRules.callAllowed(MahjongMeldType.chi, called, tiles(c), tiles(rest(c)))) res.chi += c
                }
            }
        }
    }
    return res
}

internal fun MahjongTableEngine.kokushiOn(seat: Int, k: Int): Boolean {
    val c = engineCounts(seatState[seat].hand)
    c[k] += 1
    return MahjongHand.isKokushi(c)
}

// MARK: - 따라잡기

/** 미뤄 둔 일 가운데 '때가 된' 것만 한다. 네 자리가 모두 비면 바로 한다. */
internal fun MahjongTableEngine.catchup() {
    while (true) {
        val aa = allAway
        when {
            stage == Stage.draw -> {
                val p = pendingDraw ?: return
                if (!(p.born < stepNo || aa)) return
                pendingDraw = null
                draw(p.seat, p.rinshan)
            }
            stage == Stage.turn && seatState[turnSeat].away -> autoTurn(turnSeat, allowWin = false)
            stage == Stage.handEnd && (handEndStep < stepNo || aa) -> {
                if (wallQueue.isEmpty()) return
                startNext(wallQueue.removeAt(0))
            }
            else -> return
        }
    }
}

/** 창이 닫힌 뒤 쯔모: 여는 걸음 안에서 닫혔으면 다음 걸음으로 미루고, 답으로 닫혔으면 바로. */
internal fun MahjongTableEngine.afterClose(seat: Int, rinshan: Boolean) {
    if (opening) {
        pendingDraw = PendingDraw(seat, rinshan, stepNo)
        stage = Stage.draw
    } else {
        draw(seat, rinshan)
    }
}

internal fun MahjongTableEngine.draw(seat: Int, rinshan: Boolean) {
    val t: Int
    if (rinshan) {
        t = wall[122 + rinshanUsed]
        rinshanUsed += 1
    } else {
        if (liveLeft <= 0) {
            // 하저 창이 닫히면 황패 유국으로 이미 끝난다 — 여기 오면 흐름 결함이다. 판을 세우지 않고 황패로 닫는다.
            exhaustive()
            return
        }
        t = wall[ptr]
        ptr += 1
        seatState[seat].furiten = seatState[seat].furiten.drawLive()
    }
    seatState[seat].drawn = t
    emit("draw", seat) { it.copy(tile = tile(t), rinshan = rinshan) }
    turnSeat = seat
    turnRinshan = rinshan
    stage = Stage.turn
    decisionSeqValue = seqValue
}

// MARK: - 차례 동작

/** 성공이면 null. */
internal fun MahjongTableEngine.doAct(seat: Int, action: MahjongTurnAction): MahjongActError? {
    when (action) {
        is MahjongTurnAction.Discard -> {
            if (action.tile.id !in discardOptions(seat)) return MahjongActError.illegal
            discard(seat, action.tile.id, riichi = false, auto = false)
        }
        is MahjongTurnAction.Riichi -> {
            if (action.tile.id !in riichiOptions(seat)) return MahjongActError.illegal
            discard(seat, action.tile.id, riichi = true, auto = false)
        }
        MahjongTurnAction.Tsumo -> {
            if (!tsumoOption(seat)) return MahjongActError.illegal
            tsumoWin(seat)
        }
        is MahjongTurnAction.Ankan -> {
            val ids = action.tilesOut.map { it.id }.sorted()
            if (ids !in ankanOptions(seat)) return MahjongActError.illegal
            ankan(seat, ids)
        }
        is MahjongTurnAction.Kakan -> {
            if (action.tile.id !in kakanOptions(seat)) return MahjongActError.illegal
            kakan(seat, action.tile.id)
        }
        MahjongTurnAction.Kyuushu -> {
            if (!kyuushuOption(seat)) return MahjongActError.illegal
            abortive("kyuushu")
        }
    }
    return null
}

/** 시간 초과 · 자리 비움의 차례 동작 — `MahjongRules.timeoutAction`. */
internal fun MahjongTableEngine.autoTurn(seat: Int, allowWin: Boolean) {
    val s = seatState[seat]
    val light = MahjongDecision.Turn(
        seq = seqValue, decisionSeq = decisionSeqValue, startedMs = 0.0, deadlineMs = 0.0, bankMs = 0,
        discard = tiles(discardOptions(seat)), tsumo = allowWin && tsumoOption(seat),
    )
    when (val a = MahjongRules.timeoutAction(light, s.drawn?.let(::tile))) {
        MahjongTimeoutAction.Tsumo -> tsumoWin(seat)
        is MahjongTimeoutAction.Discard -> discard(seat, a.tile.id, riichi = false, auto = true)
        MahjongTimeoutAction.Ron, MahjongTimeoutAction.Pass -> s.closed14.maxOrNull()?.let { discard(seat, it, riichi = false, auto = true) }
    }
}

internal fun MahjongTableEngine.doTimeout(seat: Int): MahjongActError? {
    if (seatState[seat].away) return MahjongActError.awayState
    if (stage == Stage.turn && turnSeat == seat) {
        autoTurn(seat, MahjongRules.timeoutAutoWin)
        seatState[seat].streak += 1
        if (seatState[seat].streak >= MahjongTableEngine.awayAfterTimeouts && stage != Stage.finished) markAway(seat, MahjongAwayReason.timeouts)
        catchup()
        return null
    }
    val w = window
    val o = w?.options?.get(seat)
    if (stage == Stage.claim && w != null && o != null && w.answers[seat] == null) {
        val d = MahjongDecision.Call(
            windowId = w.id, windowKind = w.kind.rawValue, tile = tile(w.tile), fromSeat = w.from,
            startedMs = 0.0, deadlineMs = 0.0, bankMs = 0, ron = o.ron,
        )
        val ron = MahjongRules.timeoutAction(d, null) == MahjongTimeoutAction.Ron
        answer(seat, if (ron) MahjongCallAnswer.Ron else MahjongCallAnswer.Pass)
        catchup()
        return null
    }
    return MahjongActError.notYourTurn
}

internal fun MahjongTableEngine.markAway(seat: Int, reason: MahjongAwayReason) {
    val s = seatState[seat]
    s.away = true
    s.awayReason = reason
    s.awaySinceMs = nowMs
    emit("away", seat) { it.copy(on = true, reason = reason.rawValue) }
    val w = window
    if (stage == Stage.claim && w != null && w.options[seat] != null && w.answers[seat] == null) {
        w.answers[seat] = MahjongClaimAnswer.pass
        tryResolve()
    }
}

// MARK: - 버림

internal fun MahjongTableEngine.discard(seat: Int, tileId: Int, riichi: Boolean, auto: Boolean) {
    val s = seatState[seat]
    val tsumogiri = tileId == s.drawn
    if (tsumogiri) {
        s.drawn = null
    } else {
        val i = s.hand.indexOf(tileId)
        if (i >= 0) s.hand.removeAt(i)
        s.drawn?.let {
            s.hand.add(it)
            s.drawn = null
        }
        s.hand.sort()
    }
    s.discards += DiscardRow(tileId, tsumogiri, riichi, false)
    s.furiten = s.furiten.ownDiscard(tileId / 4)
    val first = !s.discardedOnce
    if (riichi) {
        s.declared = true
        s.doublePending = first && firstUninterrupted
        s.furiten = s.furiten.declareRiichi()
    } else {
        s.ippatsu = false
    }
    s.discardedOnce = true
    s.kuikae = emptyList()
    emit("discard", seat) { it.copy(tile = tile(tileId), tsumogiri = tsumogiri, riichi = riichi, priv = if (auto) MahjongEventPriv(auto = true) else null) }
    showsLastHand = false
    flushDora()
    if (first && firstUninterrupted) firstDiscards += tileId / 4
    s.waits = engineWaits(s.hand, s.melds.size)
    if (firstUninterrupted && firstDiscards.size == 4 && MahjongRules.suufonRenda(firstDiscards, anyCall = false)) {
        abortive("suufon")
        return
    }
    openWindow(WindowKind.discard, seat, tileId, houtei = liveLeft == 0)
}

// MARK: - 깡 선언

internal fun MahjongTableEngine.ankan(seat: Int, tilesIn: List<Int>) {
    val s = seatState[seat]
    val hold = s.closed14
    s.drawn = null
    s.hand = hold.filter { it !in tilesIn }.sorted().toMutableList()
    flushDora()
    emit("kan", seat) { it.copy(type = MahjongMeldType.ankan.rawValue, tiles = tiles(tilesIn)) }
    s.melds += EngineMeld(MahjongMeldType.ankan, tilesIn, null, null)
    timerKan(MahjongMeldType.ankan)
    openWindow(WindowKind.ankan, seat, tilesIn.maxOrNull() ?: tilesIn[0], houtei = false)
}

internal fun MahjongTableEngine.kakan(seat: Int, tileId: Int) {
    val s = seatState[seat]
    val hold = s.closed14.toMutableList()
    s.drawn = null
    val i = hold.indexOf(tileId)
    if (i >= 0) hold.removeAt(i)
    s.hand = hold.sorted().toMutableList()
    val mi = s.melds.indexOfFirst { it.type == MahjongMeldType.pon && it.tiles[0] / 4 == tileId / 4 }
    if (mi < 0) return
    flushDora()
    val all = (s.melds[mi].tiles + tileId).sorted()
    emit("kan", seat) { it.copy(type = MahjongMeldType.kakan.rawValue, tiles = tiles(all)) }
    openWindow(WindowKind.kakan, seat, tileId, houtei = false, kakanMeld = mi)
}

// MARK: - 창

internal fun MahjongTableEngine.openWindow(kind: WindowKind, d: Int, tileId: Int, houtei: Boolean, kakanMeld: Int? = null) {
    windowSerial += 1
    val order = listOf(1, 2, 3).map { (d + it) % 4 }
    val w = Window(windowSerial, kind, d, tileId, houtei, order, kakanMeld)
    for (x in order) {
        val o = callOptions(x, kind, d, tileId, houtei)
        if (o.kinds.isNotEmpty()) w.options[x] = o
    }
    stage = Stage.claim
    decisionSeqValue = seqValue
    for (x in order) if (w.options[x] != null && seatState[x].away) w.answers[x] = MahjongClaimAnswer.pass
    window = w
    opening = true
    tryResolve()
    opening = false
}

/** 성공이면 null. */
internal fun MahjongTableEngine.answer(seat: Int, a: MahjongCallAnswer): MahjongActError? {
    val w = window ?: return MahjongActError.notYourTurn
    val o = w.options[seat] ?: return MahjongActError.notYourTurn
    when (a) {
        MahjongCallAnswer.Pass -> w.answers[seat] = MahjongClaimAnswer.pass
        MahjongCallAnswer.Ron -> {
            if (!o.ron) return MahjongActError.illegal
            w.answers[seat] = MahjongClaimAnswer.ron
        }
        is MahjongCallAnswer.Pon, is MahjongCallAnswer.Minkan, is MahjongCallAnswer.Chi -> {
            val ids = a.tiles.map { it.id }.sorted()
            val (list, ans) = when (a) {
                is MahjongCallAnswer.Pon -> o.pon to MahjongClaimAnswer.pon
                is MahjongCallAnswer.Minkan -> o.minkan to MahjongClaimAnswer.minkan
                else -> o.chi to MahjongClaimAnswer.chi
            }
            if (!callTilesOK(seat, ids, list)) return MahjongActError.illegal
            w.answers[seat] = ans
            w.chosen[seat] = ids
        }
    }
    tryResolve()
    return null
}

/** 선택지 목록은 적5 여부로 하나씩만 보이지만, 같은 꼴(종류 · 적5 여부)의 다른 물리 패도 받는다. */
internal fun MahjongTableEngine.callTilesOK(seat: Int, ids: List<Int>, list: List<List<Int>>): Boolean {
    val hand = seatState[seat].hand
    if (ids.toSet().size != ids.size || !ids.all { it in hand }) return false
    fun sig(c: List<Int>): List<Int> = c.map { it / 4 * 2 + (if (it in redIDs) 1 else 0) }
    return list.any { sig(it) == sig(ids) }
}

internal fun MahjongTableEngine.tryResolve() {
    val w = window ?: return
    val r = MahjongRules.resolveClaims(w.from, w.options.mapValues { it.value.kinds }, w.answers)
    if (r == MahjongClaimResolution.Wait) return
    closeWindow(r)
}

internal fun MahjongTableEngine.closeWindow(r: MahjongClaimResolution) {
    val w = window ?: return
    window = null
    val d = w.from
    val tileId = w.tile
    val k = tileId / 4
    if (r is MahjongClaimResolution.Ron) {
        ronWin(r.seats, w)
        return
    }
    // ① 놓친 화료패 → 동순(리치면 리치) 후리텐
    for (x in w.order) {
        if (w.kind == WindowKind.ankan) {
            if (seatState[x].melds.isEmpty() && kokushiOn(x, k)) seatState[x].furiten = seatState[x].furiten.missed()
        } else if (k in seatState[x].waits) {
            seatState[x].furiten = seatState[x].furiten.missed()
        }
    }
    // ② 리치 성립 — 론 없이 닫힘 넷 모두
    if (w.kind == WindowKind.discard && seatState[d].declared) {
        val sd = seatState[d]
        sd.declared = false
        sd.riichi = true
        sd.ippatsu = true
        sd.doubleRiichi = sd.doublePending
        points[d] -= 1000
        kyotaku += 1
        emit("riichi", d)
        if (seatState.all { it.riichi }) {
            abortive("suucha_riichi")
            return
        }
    }
    // ③ 사깡유국 — 울기 적용 전
    if (w.kind == WindowKind.discard && MahjongRules.suukaikan(kanSeats)) {
        abortive("suukaikan")
        return
    }
    if (r !is MahjongClaimResolution.Claim) {
        // 넘김
        if (w.kind == WindowKind.discard) {
            if (w.houtei) {
                exhaustive()
                return
            }
            afterClose((d + 1) % 4, rinshan = false)
        } else { // 가깡 · 암깡 성립
            val mi = w.kakanMeld
            if (w.kind == WindowKind.kakan && mi != null) {
                val m = seatState[d].melds[mi]
                seatState[d].melds[mi] = m.copy(type = MahjongMeldType.kakan, tiles = (m.tiles + tileId).sorted())
                timerKan(MahjongMeldType.kakan)
            }
            kans += 1
            kanSeats += d
            firstUninterrupted = false
            clearIppatsu()
            afterClose(d, rinshan = true)
        }
        return
    }
    // ④ 퐁 · 대명깡 · 치
    val caller = r.seat
    val typ = when (r.kind) {
        MahjongClaimKind.pon -> MahjongMeldType.pon
        MahjongClaimKind.minkan -> MahjongMeldType.minkan
        else -> MahjongMeldType.chi
    }
    val chosen = w.chosen[caller] ?: emptyList()
    seatState[d].discards.lastOrNull()?.taken = true
    for (t in chosen) {
        val i = seatState[caller].hand.indexOf(t)
        if (i >= 0) seatState[caller].hand.removeAt(i)
    }
    val meldTiles = (chosen + tileId).sorted()
    seatState[caller].melds += EngineMeld(typ, meldTiles, tileId, d)
    firstUninterrupted = false
    clearIppatsu()
    emit("call", caller) { it.copy(type = typ.rawValue, tiles = tiles(meldTiles), called = tile(tileId), fromSeat = d) }
    checkPao(caller, k, d)
    if (typ == MahjongMeldType.minkan) {
        timerKan(MahjongMeldType.minkan)
        kans += 1
        kanSeats += caller
        draw(caller, rinshan = true) // 대명깡은 영상 쯔모 뒤 차례 — 울기 확정 걸음 안에서 바로
        return
    }
    seatState[caller].kuikae = MahjongRules.kuikaeForbidden(typ, tile(tileId), tiles(chosen))
    turnSeat = caller
    turnRinshan = false
    stage = Stage.turn
    decisionSeqValue = seqValue
}

/** MJ-42: 삼원 몸통 2개를 드러낸 사람에게 셋째 삼원을, 바람 3개에게 넷째 바람을 준 사람(암깡 포함). */
internal fun MahjongTableEngine.checkPao(caller: Int, k: Int, from: Int) {
    val melds = seatState[caller].melds
    val kinds = setOf(MahjongMeldType.pon, MahjongMeldType.minkan, MahjongMeldType.kakan, MahjongMeldType.ankan)
    val prev = melds.dropLast(1).filter { it.type in kinds }.map { it.tiles[0] / 4 }
    if (k in 31..33 && prev.count { it in 31..33 } == 2) seatState[caller].pao = MahjongPao(from, MahjongYaku.daisangen)
    if (k in 27..30 && prev.count { it in 27..30 } == 3) seatState[caller].pao = MahjongPao(from, MahjongYaku.daisuushii)
}

// MARK: - 국 끝

internal fun MahjongTableEngine.winSummary(seat: Int, res: MahjongScore, from: Int?, winTile: Int): MahjongWinResult {
    val s = seatState[seat]
    val pao = s.pao
    return MahjongWinResult(
        seat = seat, fromSeat = from, hand = tiles(s.hand.sorted()), melds = s.melds.map { MahjongWireMeld(it.meld) },
        winTile = tile(winTile), yaku = res.yaku.map { MahjongWireYaku(it) }, yakuman = res.yakuman, han = res.han, fu = res.fu,
        limit = res.limit, dora = res.dora, aka = res.aka, ura = res.ura, uraIndicators = if (s.riichi) tiles(uraIndicators) else null,
        total = res.total,
        pao = if (pao != null && res.yakuman > 0 && res.yaku.any { it.yaku == pao.yaku }) MahjongWinResult.Pao(pao.seat, pao.yaku.rawValue) else null,
    )
}

internal fun MahjongTableEngine.tsumoWin(seat: Int) {
    val drawn = seatState[seat].drawn ?: return
    val res = evaluate(seat, drawn, true, tsumoFlags(seat)) ?: return
    if (!res.agari) return
    val deltas = MahjongRules.settleWin(seat, dealer, res, null, honba, kyotaku, seatState[seat].pao, getsBonus = true)
    val result = MahjongHandResult(
        handIndex = handIndexValue, kind = "win", wins = listOf(winSummary(seat, res, null, drawn)), tenpai = emptyList(), nagashi = emptyList(), bonusTo = seat,
    )
    emit("win") { it.copy(seats = listOf(seat), fromSeat = null) }
    finishHand(result, deltas, if (seat == dealer) MahjongHandOutcome.dealerWin else MahjongHandOutcome.childWin, renchan = seat == dealer, clearKyotaku = true)
}

internal fun MahjongTableEngine.ronWin(winners: List<Int>, w: Window) {
    val d = w.from
    val tileId = w.tile
    val wins = mutableListOf<MahjongRonWin>()
    val summaries = mutableListOf<MahjongWinResult>()
    for (x in winners) {
        val res = evaluate(x, tileId, false, ronFlags(w.kind, w.houtei)) ?: continue
        if (!res.agari) continue
        wins += MahjongRonWin(x, res, seatState[x].pao)
        summaries += winSummary(x, res, d, tileId)
    }
    seatState[d].declared = false // 선언패가 론되면 리치 불성립(MJ-28)
    val deltas: List<Int>
    val bonusTo: Int
    val renchan: Boolean
    if (wins.size == 1) {
        val x = wins[0]
        deltas = MahjongRules.settleWin(x.seat, dealer, x.score, d, honba, kyotaku, x.pao, getsBonus = true)
        bonusTo = x.seat
        renchan = x.seat == dealer
    } else {
        val m = MahjongRules.settleRonMulti(d, dealer, wins, honba, kyotaku)
        deltas = m.deltas
        bonusTo = m.bonusTo
        renchan = m.renchan
    }
    val result = MahjongHandResult(handIndex = handIndexValue, kind = "win", wins = summaries, tenpai = emptyList(), nagashi = emptyList(), bonusTo = bonusTo)
    emit("win") { it.copy(seats = winners, fromSeat = d) }
    finishHand(result, deltas, if (renchan) MahjongHandOutcome.dealerWin else MahjongHandOutcome.childWin, renchan, clearKyotaku = true)
}

internal fun MahjongTableEngine.exhaustive() {
    val tenpai = seatState.map { engineWaits(it.hand, it.melds.size).isNotEmpty() }
    val nagashi = seatState.map { s -> MahjongRules.nagashiOK(s.discards.map { it.tile / 4 }, s.discards.any { it.taken }) }
    val st = MahjongRules.settleExhaustive(dealer, tenpai, nagashi)
    val result = MahjongHandResult(
        handIndex = handIndexValue, kind = "exhaustive", wins = emptyList(),
        tenpai = (0 until 4).filter { tenpai[it] }.map { n ->
            MahjongTenpaiResult(n, tiles(seatState[n].hand.sorted()), seatState[n].melds.map { MahjongWireMeld(it.meld) })
        },
        nagashi = (0 until 4).filter { nagashi[it] },
    )
    emit("hand_draw") { it.copy(reason = "exhaustive") }
    finishHand(result, st.deltas, if (st.renchan) MahjongHandOutcome.drawDealerTenpai else MahjongHandOutcome.drawDealerNoten, st.renchan, clearKyotaku = false)
}

internal fun MahjongTableEngine.abortive(reason: String) {
    val result = MahjongHandResult(handIndex = handIndexValue, kind = "abortive", reason = reason, wins = emptyList(), tenpai = emptyList(), nagashi = emptyList())
    emit("hand_draw") { it.copy(reason = reason) }
    finishHand(result, listOf(0, 0, 0, 0), MahjongHandOutcome.abortive, renchan = true, clearKyotaku = false)
}

internal fun MahjongTableEngine.finishHand(partial: MahjongHandResult, deltas: List<Int>, outcome: MahjongHandOutcome, renchan: Boolean, clearKyotaku: Boolean) {
    window = null
    pendingDraw = null
    for (i in 0 until 4) points[i] += deltas[i]
    if (clearKyotaku) kyotaku = 0
    val after = points.toList()
    emit("scores") { it.copy(deltas = deltas, scoresAfter = after) }
    val adv = MahjongRules.advance(format, round, handNo, honba, points.toList(), outcome)
    val result = partial.copy(deltas = deltas, scoresAfter = after, renchan = renchan)
    hands += HandRecord(result, adv, kyotaku)
    handEndStep = stepNo
    showsLastHand = true
    if (adv.end) {
        val fr = MahjongRules.finalResult(points.toList(), kyotaku)
        val reason = adv.reason ?: "max_round"
        finalRecord = FinalRecord(reason, fr.order, fr.ranks, fr.finalScores, kyotaku)
        emit("end") { it.copy(endReason = reason) }
        stage = Stage.finished
    } else {
        nextHand = adv.next
        stage = Stage.handEnd
    }
}
