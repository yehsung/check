// 원본: Sources/CheckCore/MahjongRules.swift @ e4995a3a(울기 · 리치 · 유국 · 정산 · 국 끝 · 등수 · 루비 · 시간 초과 — MJ-14~MJ-55) — Android 판 8
//
// `MahjongFormat` · `MahjongDecision` 은 판 진행(엔진) · 와이어 · 스토어가 같이 쓴다. Swift 의 값 타입(struct + mutating)은
// 값 의미를 지키려고 바꾼 새 값을 돌려주는 불변 data class 로 옮겼다(엔진이 상태를 복사해도 서로 새지 않는다).
package com.yehsung.aingcheck.core.rules.mahjong

/** 판 길이. 와이어 `format` 값 그대로. 둘 다 남입 · 서입 연장 포함. */
enum class MahjongFormat(val rawValue: String) {
    tonpuu("tonpuu"), hanchan("hanchan");

    companion object {
        fun of(raw: String): MahjongFormat? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 울기 창에서 고를 수 있는 것. 대명깡은 `minkan`. */
enum class MahjongClaimKind(val rawValue: String) {
    ron("ron"), pon("pon"), minkan("minkan"), chi("chi");

    companion object {
        fun of(raw: String): MahjongClaimKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 울기 창에서 한 자리의 답(와이어 `answered` 값). */
enum class MahjongClaimAnswer(val rawValue: String) {
    ron("ron"), pon("pon"), minkan("minkan"), chi("chi"), pass("pass");

    companion object {
        fun of(raw: String): MahjongClaimAnswer? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 울기 창 해결(reference `resolve_claims`). 우선순위 론 > 퐁 · 대명깡 > 치(MJ-17), 론은 모두 화료(MJ-25), 치는 하가만(MJ-14). */
sealed interface MahjongClaimResolution {
    /** 더 높은 우선순위의 답을 아직 기다린다. */
    data object Wait : MahjongClaimResolution
    /** 아무도 울지 않고 닫힘(reference action 'none'). */
    data object None : MahjongClaimResolution
    /** 론 — 화료 자리들, 방총자 다음 차례부터의 순서. */
    data class Ron(val seats: List<Int>) : MahjongClaimResolution
    /** 퐁 · 대명깡 · 치 — 한 자리. */
    data class Claim(val kind: MahjongClaimKind, val seat: Int) : MahjongClaimResolution
}

/** 책임 지불(MJ-42) — 대삼원 · 대사희를 확정시킨 자리. 와이어 `pao{seat, yaku}`. */
data class MahjongPao(val seat: Int, val yaku: MahjongYaku)

/** 국 끝 모양(reference `advance` 의 outcome 값 그대로). */
enum class MahjongHandOutcome(val rawValue: String) {
    dealerWin("dealer_win"), childWin("child_win"),
    drawDealerTenpai("draw_dealer_tenpai"), drawDealerNoten("draw_dealer_noten"),
    abortive("abortive");

    companion object {
        fun of(raw: String): MahjongHandOutcome? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 국 끝 처리 결과 = reference `advance` 반환 `{end, reason, next{round, hand, honba}, extension}`. */
data class MahjongAdvance(
    /** 판이 끝났는가. */
    val end: Boolean,
    /** 끝난 까닭: tobi · agari_yame · tenpai_yame · target_reached · max_round. 계속이면 null. */
    val reason: String? = null,
    /** 다음 국. 끝이면 null. */
    val next: Next? = null,
    /** 다음 국이 연장(남입 · 서입)의 첫 국으로 들어가는가. */
    val isExtension: Boolean = false,
) {
    /** round 0 = 동 · 1 = 남 · 2 = 서. hand 0~3(친 자리 = hand). */
    data class Next(val round: Int, val hand: Int, val honba: Int)
}

/** 지금 내 몫 결정 = 와이어 `my_decision` — 차례 · 울기 두 갈래. 시각은 epoch ms Double, 패는 id. */
sealed interface MahjongDecision {
    /** 와이어 kind 글자 "turn" | "call". */
    val kind: String

    /** DECISION(차례) — 쯔모 뒤 · 울기 뒤 · 영상 뒤 내 차례. */
    data class Turn(
        val seq: Int,
        /** 결정 정체성 · 낡음 판정 눈금(CS-02). */
        val decisionSeq: Int,
        val startedMs: Double,
        val deadlineMs: Double,
        /** 리치 중일 때 시작 + 멈춤(그 전 버림은 too_early). 아니면 null. */
        val notBeforeMs: Double? = null,
        val bankMs: Int,
        /** 버릴 수 있는 패 id. */
        val discard: List<MahjongTile>,
        /** 리치 선언패 id(같은 종류 id 모두 — CS-24). 못 하면 []. */
        val riichi: List<MahjongTile> = emptyList(),
        val tsumo: Boolean = false,
        /** 암깡 후보(4장 id 묶음). */
        val ankan: List<List<MahjongTile>> = emptyList(),
        /** 가깡 후보(더할 패 id). */
        val kakan: List<MahjongTile> = emptyList(),
        val kyuushu: Boolean = false,
    ) : MahjongDecision {
        override val kind: String get() = "turn"
    }

    /** DECISION(울기) — 남의 버림 · 가깡 · 암깡에 대한 창. */
    data class Call(
        val windowId: Int,
        /** "discard" | "kakan" | "ankan"(원문 문자열, CC-07). */
        val windowKind: String,
        val tile: MahjongTile,
        val fromSeat: Int,
        val startedMs: Double,
        val deadlineMs: Double,
        val bankMs: Int,
        val ron: Boolean = false,
        /** 퐁 후보(손에서 낼 2장 id). */
        val pon: List<List<MahjongTile>> = emptyList(),
        /** 대명깡 후보(손에서 낼 3장 id). */
        val minkan: List<List<MahjongTile>> = emptyList(),
        /** 치 후보(손에서 낼 2장 id). */
        val chi: List<List<MahjongTile>> = emptyList(),
        /** 이미 낸 답 "ron"|"pon"|"minkan"|"chi"|"pass"(원문 문자열). 아직이면 null. */
        val answered: String? = null,
    ) : MahjongDecision {
        override val kind: String get() = "call"
    }
}

/** 시간 초과 때 대신 둘 것(MJ-54, SPEC §2.3 K-1). */
sealed interface MahjongTimeoutAction {
    /** 쯔모기리(방금 뽑은 패) 또는 허용 패 가운데 id 가 가장 큰 것. */
    data class Discard(val tile: MahjongTile) : MahjongTimeoutAction
    /** 쯔모 화료. */
    data object Tsumo : MahjongTimeoutAction
    /** 론. */
    data object Ron : MahjongTimeoutAction
    /** 넘김 — 치 · 퐁 · 깡은 하지 않는다. */
    data object Pass : MahjongTimeoutAction
}

/** 후리텐 세 가지(MJ-24) — 한 사람 몫. 종류(0~33)로 판정한다. 바꾸는 함수는 새 값을 돌려준다. */
data class MahjongFuriten(
    /** 내가 버린 패 종류(남이 울어 가도 남긴다). */
    val discards: Set<Int> = emptySet(),
    /** 동순 후리텐. */
    val temporary: Boolean = false,
    /** 리치했는가. */
    val riichi: Boolean = false,
    /** 리치 후 후리텐(국 끝까지). */
    val riichiFuriten: Boolean = false,
) {
    /** 와이어 `my_furiten` 값. */
    enum class Kind(val rawValue: String) {
        discard("discard"), temporary("temporary"), riichi("riichi");

        companion object {
            fun of(raw: String): Kind? = entries.firstOrNull { it.rawValue == raw }
        }
    }

    /** 내가 버린 패 종류. 가깡 패는 부르지 않는다. */
    fun ownDiscard(kind: Int): MahjongFuriten = copy(discards = discards + kind)

    fun declareRiichi(): MahjongFuriten = copy(riichi = true)

    /** 살아 있는 산에서 쯔모 → 동순 후리텐 풀림. 영상 쯔모 · 치 · 퐁 · 깡으로는 안 풀린다(MJ-24-2). */
    fun drawLive(): MahjongFuriten = copy(temporary = false)

    /** 내 화료패가 나왔는데 론하지 않음. */
    fun missed(): MahjongFuriten = copy(temporary = true, riichiFuriten = riichiFuriten || riichi)

    /** 지금 걸린 후리텐(와이어 순서 discard → temporary → riichi). */
    fun kinds(waitKinds: List<Int>): List<Kind> = buildList {
        if (waitKinds.any { it in discards }) add(Kind.discard)
        if (temporary) add(Kind.temporary)
        if (riichiFuriten) add(Kind.riichi)
    }

    /** 론할 수 있는가(후리텐 없음). */
    fun canRon(waitKinds: List<Int>): Boolean = kinds(waitKinds).isEmpty()
}

/** 깡도라 여는 때(MJ-11) — 암깡 = 즉시, 대명깡 · 가깡 = 그 사람 타패 때(또는 다음 깡 선언 직전). */
data class MahjongDoraTimer(
    /** 지금 열린 표시패 수(표 도라 포함). */
    val open: Int = 1,
    /** 타패 때 열 표시패 수. */
    val pending: Int = 0,
) {
    /** 깡 성립. 앞 명깡 · 가깡의 표시패는 새 깡 선언 직전에 연다. */
    fun kan(type: MahjongMeldType): MahjongDoraTimer {
        val f = flush()
        return if (type == MahjongMeldType.ankan) f.copy(open = f.open + 1) else f.copy(pending = f.pending + 1)
    }

    /** 타패. */
    fun discard(): MahjongDoraTimer = flush()

    private fun flush(): MahjongDoraTimer = MahjongDoraTimer(open + pending, 0)
}

/** 동시 론 한 자리. */
data class MahjongRonWin(val seat: Int, val score: MahjongScore, val pao: MahjongPao?)

data class MahjongExhaustiveSettlement(val deltas: List<Int>, val renchan: Boolean)

data class MahjongRonMultiSettlement(val deltas: List<Int>, val bonusTo: Int, val renchan: Boolean)

data class MahjongFinalResult(val order: List<Int>, val ranks: List<Int>, val finalScores: List<Int>)

/** 울기 · 리치 · 유국 · 정산 · 국 끝 · 등수 · 루비 · 시간 초과 판정(SQL `mahjong_*` 쌍둥이). */
object MahjongRules {
    /** = SQL `mahjong_timeout_auto_win()` — 시간 초과 때 론 · 쯔모 선택지가 있으면 자동 화료. */
    const val timeoutAutoWin = true

    /** = SQL `mahjong_ranking_min_games()` — 이 판 수 이상이어야 순위에 선다. */
    const val rankingMinGames = 10

    /** MJ-18 쿠이카에 금지: 울고 그 차례에 버릴 수 없는 종류(현물 + 치 양끝 스지). 종류 오름차순. */
    fun kuikaeForbidden(call: MahjongMeldType, called: MahjongTile, fromHand: List<MahjongTile>): List<Int> {
        val t = called.kind
        val out = mutableSetOf(t)
        if (call == MahjongMeldType.chi && t < 27) {
            val lo = (fromHand.map { it.kind } + t).minOrNull() ?: t
            val number = t % 9 + 1
            if (t == lo && number + 3 <= 9) {
                out += t + 3
            } else if (t == lo + 2 && number - 3 >= 1) {
                out += t - 3
            }
        }
        return out.sorted()
    }

    /** MJ-18 울고 나서 버릴 수 있는 패가 하나도 없으면 그 울기는 선택지가 아니다. */
    fun callAllowed(call: MahjongMeldType, called: MahjongTile, fromHand: List<MahjongTile>, closedAfter: List<MahjongTile>): Boolean {
        val bad = kuikaeForbidden(call, called, fromHand).toSet()
        return closedAfter.any { it.kind !in bad }
    }

    /** MJ-17 울기 창 해결. eligible = 자리 → 고를 수 있는 것, answers = 자리 → 낸 답(아직 답 없으면 빠짐). 하가가 아닌 자리의 치는 무시. */
    fun resolveClaims(discarder: Int, eligible: Map<Int, List<MahjongClaimKind>>, answers: Map<Int, MahjongClaimAnswer>): MahjongClaimResolution {
        val order = listOf(1, 2, 3).map { (discarder + it) % 4 }
        val next = (discarder + 1) % 4
        fun level(kind: MahjongClaimKind): Int = when (kind) {
            MahjongClaimKind.ron -> 3
            MahjongClaimKind.pon, MahjongClaimKind.minkan -> 2
            MahjongClaimKind.chi -> 1
        }
        fun answerLevel(answer: MahjongClaimAnswer): Int = when (answer) {
            MahjongClaimAnswer.ron -> 3
            MahjongClaimAnswer.pon, MahjongClaimAnswer.minkan -> 2
            MahjongClaimAnswer.chi -> 1
            MahjongClaimAnswer.pass -> 0
        }
        fun kinds(seat: Int): List<MahjongClaimKind> = (eligible[seat] ?: emptyList()).filter { it != MahjongClaimKind.chi || seat == next }
        for (lv in listOf(3, 2, 1)) {
            val cands = order.filter { seat -> kinds(seat).any { level(it) == lv } }
            if (cands.isEmpty()) continue
            if (lv == 3) {
                if (cands.any { answers[it] == null }) return MahjongClaimResolution.Wait
                val rons = order.filter { answers[it] == MahjongClaimAnswer.ron }
                if (rons.isNotEmpty()) return MahjongClaimResolution.Ron(rons)
                continue
            }
            val seat = cands.firstOrNull { s -> answers[s]?.let(::answerLevel) == lv }
            val answer = seat?.let { answers[it] }
            if (seat != null && answer != null) {
                val kind = when (answer) {
                    MahjongClaimAnswer.pon -> MahjongClaimKind.pon
                    MahjongClaimAnswer.minkan -> MahjongClaimKind.minkan
                    else -> MahjongClaimKind.chi
                }
                return MahjongClaimResolution.Claim(kind, seat)
            }
            if (cands.any { answers[it] == null }) return MahjongClaimResolution.Wait
        }
        return MahjongClaimResolution.None
    }

    /** MJ-27 리치할 수 있으면 버려서 텐파이가 되는 패 **종류** 목록(오름차순). 못 하면 []. */
    fun riichiDiscards(closed14: List<MahjongTile>, ankans: Int, score: Int, liveLeft: Int, menzen: Boolean, already: Boolean): List<Int> {
        if (already || !menzen || score < 1000 || liveLeft < 4) return emptyList()
        val counts = MahjongTiles.counts34(closed14)
        val out = mutableListOf<Int>()
        for (k in 0 until 34) {
            if (counts[k] <= 0) continue
            counts[k] -= 1
            if (MahjongHand.waits(counts, ankans).isNotEmpty()) out += k
            counts[k] += 1
        }
        return out
    }

    /** MJ-29 리치 뒤 암깡: 방금 쯔모한 패가 4번째 + 깡 전후 대기 종류 집합이 같음. */
    fun riichiAnkanOK(closed13: List<MahjongTile>, drawn: MahjongTile, kanKind: Int?, melds: Int): Boolean {
        val k = kanKind ?: drawn.kind
        if (k != drawn.kind) return false
        val counts = MahjongTiles.counts34(closed13)
        if (counts[k] != 3) return false
        val before = MahjongHand.waits(counts, melds)
        counts[k] = 0
        val after = MahjongHand.waits(counts, melds + 1)
        return before.isNotEmpty() && before.toSet() == after.toSet()
    }

    /** MJ-45-1 구종구패: 첫 차례 · 울기 없음 · 요구패 종류 9 이상. */
    fun kyuushuOK(hand14: List<MahjongTile>, firstTurnUninterrupted: Boolean): Boolean {
        val kinds = hand14.map { it.kind }.toSet()
        return firstTurnUninterrupted && MahjongTiles.yaochu.count { it in kinds } >= 9
    }

    /** MJ-45-2 사풍연타: 첫 순 네 사람의 첫 타패가 같은 바람패, 울기 없음. */
    fun suufonRenda(firstDiscardKinds: List<Int>, anyCall: Boolean): Boolean {
        if (anyCall || firstDiscardKinds.size != 4) return false
        val kinds = firstDiscardKinds.toSet()
        if (kinds.size != 1) return false
        return kinds.first() in MahjongTiles.winds
    }

    /** MJ-45-3 사깡유국: 합계 4번 깡이 2명 이상에게서(한 사람 4번은 계속). */
    fun suukaikan(kanSeats: List<Int>): Boolean = kanSeats.size >= 4 && kanSeats.toSet().size >= 2

    /** MJ-44 유국만관: 버림패 전부 요구패 + 한 장도 불려 가지 않음. */
    fun nagashiOK(discardKinds: List<Int>, calledAway: Boolean): Boolean =
        discardKinds.isNotEmpty() && !calledAway && discardKinds.all { it in MahjongTiles.yaochu }

    /** MJ-43 · MJ-44 황패 유국 정산. 유국만관이 하나라도 있으면 노텐벌 대신 만관 쯔모 정산(본장 · 공탁 없음). */
    fun settleExhaustive(dealer: Int, tenpai: List<Boolean>, nagashi: List<Boolean>): MahjongExhaustiveSettlement {
        if (tenpai.size != 4 || nagashi.size != 4 || dealer !in 0..3) return MahjongExhaustiveSettlement(listOf(0, 0, 0, 0), false)
        val d = IntArray(4)
        if (nagashi.any { it }) {
            for (s in 0 until 4) {
                if (!nagashi[s]) continue
                for (o in 0 until 4) {
                    if (o == s) continue
                    val pay = if (s == dealer || o == dealer) 4000 else 2000
                    d[o] -= pay
                    d[s] += pay
                }
            }
        } else {
            val n = tenpai.count { it }
            if (n in 1..3) for (s in 0 until 4) d[s] = if (tenpai[s]) 3000 / n else -(3000 / (4 - n))
        }
        return MahjongExhaustiveSettlement(d.toList(), tenpai[dealer])
    }

    /** MJ-41 · MJ-42 화료 하나의 자리별 점수 변화. discarder null = 쯔모. getsBonus = 본장 · 공탁을 받는가(MJ-25). */
    fun settleWin(winner: Int, dealer: Int, score: MahjongScore, discarder: Int?, honba: Int, kyoutaku: Int, pao: MahjongPao?, getsBonus: Boolean): List<Int> {
        val d = IntArray(4)
        if (winner !in 0..3) return d.toList()
        val isDealer = winner == dealer
        val hb = if (getsBonus) honba else 0
        var paoMult = 0
        if (pao != null && score.yakuman > 0 && score.yaku.any { it.yaku == pao.yaku }) paoMult = pao.yaku.yakumanMultiple
        val restMult = score.yakuman - paoMult
        fun value(mult: Int): Int = (if (isDealer) 48000 else 32000) * mult
        if (discarder != null) {
            if (pao != null && paoMult > 0) {
                val pv = value(paoMult)
                if (pao.seat == discarder) {
                    d[discarder] -= pv
                } else {
                    d[discarder] -= pv / 2
                    d[pao.seat] -= pv / 2
                }
                d[winner] += pv
                if (restMult > 0) {
                    val rv = value(restMult)
                    d[discarder] -= rv
                    d[winner] += rv
                }
                d[pao.seat] -= 300 * hb
                d[winner] += 300 * hb
            } else {
                val v = (score.points.ron ?: 0) + 300 * hb
                d[discarder] -= v
                d[winner] += v
            }
        } else if (pao != null && paoMult > 0) {
            val pv = value(paoMult)
            d[pao.seat] -= pv
            d[winner] += pv
            if (restMult > 0) {
                for (o in 0 until 4) {
                    if (o == winner) continue
                    val v = if (isDealer || o == dealer) 16000 * restMult else 8000 * restMult
                    d[o] -= v
                    d[winner] += v
                }
            }
            d[pao.seat] -= 300 * hb
            d[winner] += 300 * hb
        } else {
            for (o in 0 until 4) {
                if (o == winner) continue
                var v = score.points.fromEach ?: ((if (o == dealer) score.points.fromDealer else score.points.fromChild) ?: 0)
                v += 100 * hb
                d[o] -= v
                d[winner] += v
            }
        }
        if (getsBonus) d[winner] += 1000 * kyoutaku
        return d.toList()
    }

    /** MJ-25 동시 론. 본장 · 공탁은 방총자 다음 차례부터 처음 화료자 한 명만. 친이 화료자에 있으면 연장. */
    fun settleRonMulti(discarder: Int, dealer: Int, wins: List<MahjongRonWin>, honba: Int, kyoutaku: Int): MahjongRonMultiSettlement {
        val order = listOf(1, 2, 3).map { (discarder + it) % 4 }
        val seats = wins.map { it.seat }
        val first = order.firstOrNull { it in seats } ?: (seats.firstOrNull() ?: discarder)
        val total = IntArray(4)
        for (win in wins) {
            val d = settleWin(win.seat, dealer, win.score, discarder, honba, kyoutaku, win.pao, win.seat == first)
            for (i in 0 until 4) total[i] += d[i]
        }
        return MahjongRonMultiSettlement(total.toList(), first, dealer in seats)
    }

    /** MJ-46~MJ-50 국 끝 처리 = reference `advance`. scores = 이 국 정산 뒤 점수(공탁 제외). */
    fun advance(format: MahjongFormat, round: Int, handNo: Int, honba: Int, scores: List<Int>, outcome: MahjongHandOutcome): MahjongAdvance {
        val target = 30000
        if (scores.any { it < 0 }) return MahjongAdvance(end = true, reason = "tobi")
        val renchan = outcome == MahjongHandOutcome.dealerWin || outcome == MahjongHandOutcome.drawDealerTenpai || outcome == MahjongHandOutcome.abortive
        val nextHonba = if (outcome == MahjongHandOutcome.childWin) 0 else honba + 1
        val lastRound = if (format == MahjongFormat.tonpuu) 0 else 1
        val maxRound = lastRound + 1
        val dealer = handNo
        val stay = MahjongAdvance(end = false, next = MahjongAdvance.Next(round, handNo, nextHonba))
        val (nr, nh) = if (handNo == 3) (round + 1) to 0 else round to (handNo + 1)
        if ((round == lastRound && handNo == 3) || round > lastRound) {
            if (renchan && outcome != MahjongHandOutcome.abortive) {
                if (scores.size == 4 && rankOrder(scores).first() == dealer && scores[dealer] >= target) {
                    return MahjongAdvance(end = true, reason = if (outcome == MahjongHandOutcome.dealerWin) "agari_yame" else "tenpai_yame")
                }
                return stay
            }
            if (renchan) return stay
            if ((scores.maxOrNull() ?: 0) >= target) return MahjongAdvance(end = true, reason = "target_reached")
            if (round == maxRound && handNo == 3) return MahjongAdvance(end = true, reason = "max_round")
            return MahjongAdvance(end = false, next = MahjongAdvance.Next(nr, nh, nextHonba), isExtension = nr > lastRound && handNo == 3)
        }
        if (renchan) return stay
        return MahjongAdvance(end = false, next = MahjongAdvance.Next(nr, nh, nextHonba))
    }

    /** MJ-51 등수와 남은 공탁(1위에게). 같은 점수는 기가(0번)에 가까운 자리가 위. */
    fun finalResult(scores: List<Int>, kyoutaku: Int): MahjongFinalResult {
        if (scores.size != 4) return MahjongFinalResult(emptyList(), emptyList(), scores)
        val order = rankOrder(scores)
        val final = scores.toMutableList()
        final[order[0]] += 1000 * kyoutaku
        val ranks = IntArray(4)
        order.forEachIndexed { i, seat -> ranks[seat] = i + 1 }
        return MahjongFinalResult(order, ranks.toList(), final)
    }

    /** 루비 분배 = SQL `mahjong_payouts(stake)` — 등수 1~4 의 지급 `[3N, N, 0, 0]`. */
    fun payouts(stake: Int): List<Int> = listOf(3 * stake, stake, 0, 0)

    /** MJ-54 시간 초과 동작: 차례 — 쯔모 > 방금 뽑은 패 > 허용 패 중 id 최대. 울기 — 론 > 넘김. */
    fun timeoutAction(decision: MahjongDecision, drawn: MahjongTile?): MahjongTimeoutAction = when (decision) {
        is MahjongDecision.Turn -> when {
            timeoutAutoWin && decision.tsumo -> MahjongTimeoutAction.Tsumo
            drawn != null && drawn in decision.discard -> MahjongTimeoutAction.Discard(drawn)
            else -> decision.discard.maxOrNull()?.let { MahjongTimeoutAction.Discard(it) } ?: MahjongTimeoutAction.Pass
        }
        is MahjongDecision.Call -> if (timeoutAutoWin && decision.ron) MahjongTimeoutAction.Ron else MahjongTimeoutAction.Pass
    }

    /** MJ-51 점수 높은 순, 같으면 기가(0번)에 가까운 자리 먼저. reference `rank_order`. */
    fun rankOrder(scores: List<Int>): List<Int> =
        scores.indices.sortedWith { a, b -> if (scores[a] != scores[b]) scores[b].compareTo(scores[a]) else a.compareTo(b) }
}
