// 원본: Sources/CheckCore/MahjongTableEngine.swift @ e4995a3a(아잉 마작 판 진행 엔진 — 공개 표면 · state 투영) — Android 판 8
//
// 연습판은 서버 없이 한 판 전체를 기기 안에서 돌린다. SQL 결정 엔진 · 파이썬 참조(table_ref.py)와 같은 판 흐름 · 같은 사건 순서를 내고,
// 사람 자리 화면 · 봇은 `payload(for:)` 투영만 받는다. 판정은 MahjongScoring · MahjongRules 를 그대로 부른다.
// 걸음(= 서버 RPC 하나): begin(걸음 번호 +1 → back 이면 비움 먼저 풀기 → 따라잡기) + apply(동작).
// 시간: 엔진은 시계를 읽지 않는다 — 사건 at_ms 는 [nowMs], state 의 server_now_ms 는 payload 인자.
// Swift 는 값 타입(struct)이다 — Kotlin 은 한 객체를 고쳐 쓴다(엔진을 복사해 쓰는 곳이 없다 — onReady 는 읽기만).
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongAdvance
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimAnswer
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClock
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDoraTimer
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile

/** 엔진 판 단계. */
sealed interface MahjongEnginePhase {
    data object Idle : MahjongEnginePhase
    data class Turn(val seat: Int) : MahjongEnginePhase
    data class Claim(val windowId: Int) : MahjongEnginePhase
    data class DrawWait(val seat: Int) : MahjongEnginePhase
    data class HandEnd(val result: MahjongHandResult) : MahjongEnginePhase
    data object Finished : MahjongEnginePhase

    /** state 의 공개 phase 이름(claim · draw_wait 는 둘 다 "wait"). */
    val wireName: String
        get() = when (this) {
            Idle -> "room"
            is Turn -> "turn"
            is Claim, is DrawWait -> "wait"
            is HandEnd -> "hand_end"
            Finished -> "finished"
        }
}

/** 차례 동작(= `mahjong_act` 의 p_action · p_tiles). */
sealed interface MahjongTurnAction {
    data class Discard(val tile: MahjongTile) : MahjongTurnAction
    /** 리치 선언패를 버린다. */
    data class Riichi(val tile: MahjongTile) : MahjongTurnAction
    data object Tsumo : MahjongTurnAction
    /** 네 장. */
    data class Ankan(val tilesOut: List<MahjongTile>) : MahjongTurnAction
    /** 퐁에 더하는 한 장. */
    data class Kakan(val tile: MahjongTile) : MahjongTurnAction
    data object Kyuushu : MahjongTurnAction

    val wireAction: String
        get() = when (this) {
            is Discard -> "discard"
            is Riichi -> "riichi"
            Tsumo -> "tsumo"
            is Ankan -> "ankan"
            is Kakan -> "kakan"
            Kyuushu -> "kyuushu"
        }

    val tiles: List<MahjongTile>
        get() = when (this) {
            is Discard -> listOf(tile)
            is Riichi -> listOf(tile)
            is Kakan -> listOf(tile)
            is Ankan -> tilesOut
            Tsumo, Kyuushu -> emptyList()
        }
}

/** 울기 창 답(= `mahjong_call` 의 p_action · p_tiles — 손에서 내는 패). */
sealed interface MahjongCallAnswer {
    data object Ron : MahjongCallAnswer
    data object Pass : MahjongCallAnswer
    data class Pon(val tilesOut: List<MahjongTile>) : MahjongCallAnswer
    data class Minkan(val tilesOut: List<MahjongTile>) : MahjongCallAnswer
    data class Chi(val tilesOut: List<MahjongTile>) : MahjongCallAnswer

    val wireAction: String
        get() = when (this) {
            Ron -> "ron"
            Pass -> "pass"
            is Pon -> "pon"
            is Minkan -> "minkan"
            is Chi -> "chi"
        }

    val tiles: List<MahjongTile>
        get() = when (this) {
            Ron, Pass -> emptyList()
            is Pon -> tilesOut
            is Minkan -> tilesOut
            is Chi -> tilesOut
        }
}

/** 걸음이 받아지지 않은 까닭(서버 status 어휘와 짝). */
enum class MahjongActError { notDealt, over, notYourTurn, illegal, awayState, badWall }

/** 자리 비움 이유(= 서버 away_reason). */
enum class MahjongAwayReason(val rawValue: String) {
    timeouts("timeouts"), leave("leave"), accountDeleted("account_deleted");

    companion object {
        fun of(raw: String): MahjongAwayReason? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 걸음 하나(= 서버 RPC 하나, replay 대본 op 하나). */
sealed interface MahjongEngineStep {
    data class Act(val seat: Int, val action: MahjongTurnAction) : MahjongEngineStep
    data class Call(val seat: Int, val answer: MahjongCallAnswer) : MahjongEngineStep
    data class Timeout(val seat: Int) : MahjongEngineStep
    data class Away(val seat: Int, val reason: MahjongAwayReason) : MahjongEngineStep
    data class Back(val seat: Int) : MahjongEngineStep
    data object Wait : MahjongEngineStep
}

/** 걸음 결과(Swift `Result<[MahjongEvent], MahjongActError>`). */
sealed interface MahjongStepResult {
    data class Success(val events: List<MahjongEvent>) : MahjongStepResult
    data class Failure(val error: MahjongActError) : MahjongStepResult

    val eventsOrEmpty: List<MahjongEvent> get() = (this as? Success)?.events ?: emptyList()
}

/** 연습판 · replay 판 진행 엔진. 시계 · 멈춤은 바깥이 쥔다. */
class MahjongTableEngine(
    val format: MahjongFormat,
    seats: List<MahjongStateUser?>,
    startScores: List<Int> = listOf(25000, 25000, 25000, 25000),
    round: Int = 0,
    handNo: Int = 0,
    honba: Int = 0,
    kyotaku: Int = 0,
) {
    companion object {
        /** 자기 차례 시간 초과가 이만큼 이어지면 자리 비움. */
        const val awayAfterTimeouts = 3
        /** [나가기] 뒤 [돌아왔어요]가 받아지기까지. */
        const val backCooldownMs: Double = 10_000.0
        /** state 사건 꼬리 상한. */
        const val eventPageLimit = 80

        val windLetters = listOf("E", "S", "W", "N")

        /** 엔진 안 패 id 는 늘 0~135(패산을 순열로 확인한 뒤에만 배패한다). */
        fun tile(id: Int): MahjongTile = MahjongTile.of(id)!!

        fun tiles(ids: List<Int>): List<MahjongTile> = ids.map(::tile)

        fun isPermutation(wall: List<Int>): Boolean = wall.size == 136 && wall.sorted() == (0 until 136).toList()

        /** 사건 한 줄을 보는 자리에 맞게 거른다 — 뽑은 패 · 자동 버림 표지(priv)는 그 자리 주인에게만. */
        fun visible(event: MahjongEvent, viewer: Int?): MahjongEvent {
            val owner = viewer != null && event.seat == viewer
            if (owner) return event
            return event.copy(tile = if (event.kind == "draw") null else event.tile, priv = null)
        }
    }

    /** state `match.id`(연습판은 "ai-" 머리). */
    var matchID: String = MahjongStatePayload.practiceIDPrefix + "practice"
    /** 판돈(연습판 0). */
    var stake: Int = 0
    /** 시간 주입 — 이 뒤에 나는 사건의 at_ms. */
    var nowMs: Double = 0.0
    /** 자리마다 사람(봇 포함, 없으면 null). */
    val users: MutableList<MahjongStateUser?> = seats.take(4).toMutableList().also { while (it.size < 4) it.add(null) }

    // 판 상태(숨은 정보)
    internal var stage: Stage = Stage.idle
    internal var round: Int = round
    internal var handNo: Int = handNo
    internal var honba: Int = honba
    internal var kyotaku: Int = kyotaku
    internal var points: MutableList<Int> = (if (startScores.size == 4) startScores else listOf(25000, 25000, 25000, 25000)).toMutableList()
    internal val seatState: List<Seat> = (0 until 4).map { Seat(it) }
    internal var handIndexValue = 0
    internal var seqValue = 0
    internal val log: MutableList<MahjongEvent> = mutableListOf()
    internal val hands: MutableList<HandRecord> = mutableListOf()
    internal var finalRecord: FinalRecord? = null
    internal val wallQueue: MutableList<List<Int>> = mutableListOf()
    internal var stepNo = 0
    internal var handEndStep = 0
    internal var opening = false
    internal var nextHand: MahjongAdvance.Next? = null
    internal var showsLastHand = false
    internal var windowSerial = 0
    internal var decisionSeqValue = 0

    // 국 상태
    internal var wall: List<Int> = emptyList()
    internal var ptr = 53
    internal var kans = 0
    internal val kanSeats: MutableList<Int> = mutableListOf()
    internal var rinshanUsed = 0
    internal var timer = MahjongDoraTimer()
    internal var firstUninterrupted = true
    internal val firstDiscards: MutableList<Int> = mutableListOf()
    internal var window: Window? = null
    internal var pendingDraw: PendingDraw? = null
    internal var turnSeat = 0
    internal var turnRinshan = false
    internal val memo = MahjongEngineMemo()

    // MARK: - 공개 표면

    /** 첫 국 배패(MJ-08). wall = 136 id 순열. 배패 전에만 받는다. */
    fun deal(wall: List<Int>): List<MahjongEvent> {
        if (stage != Stage.idle || !isPermutation(wall)) return emptyList()
        val start = log.size
        dealHand(wall)
        return log.subList(start, log.size).toList()
    }

    /** 다음 국 패산을 줄 세운다 — 국이 끝난 다음 걸음의 따라잡기가 꺼내 배패한다. */
    fun enqueueWalls(walls: List<List<Int>>) {
        wallQueue.addAll(walls.filter(::isPermutation))
    }

    val phase: MahjongEnginePhase
        get() = when (stage) {
            Stage.idle -> MahjongEnginePhase.Idle
            Stage.turn -> MahjongEnginePhase.Turn(turnSeat)
            Stage.claim -> MahjongEnginePhase.Claim(window?.id ?: windowSerial)
            Stage.draw -> MahjongEnginePhase.DrawWait(pendingDraw?.seat ?: turnSeat)
            Stage.handEnd -> MahjongEnginePhase.HandEnd(hands.lastOrNull()?.result ?: MahjongHandResult(handIndexValue, "abortive"))
            Stage.finished -> MahjongEnginePhase.Finished
        }

    /** = 서버 my_decision(시계 칸은 0/null). 자리 비움 자리 · 답한 울기 창은 null. */
    fun decision(seat: Int): MahjongDecision? {
        if (seat !in 0..3 || seatState[seat].away) return null
        return when {
            stage == Stage.turn && turnSeat == seat -> {
                val o = turnOptions(seat)
                MahjongDecision.Turn(
                    seq = seqValue, decisionSeq = decisionSeqValue, startedMs = 0.0, deadlineMs = 0.0, bankMs = 0,
                    discard = tiles(o.discard), riichi = tiles(o.riichi), tsumo = o.tsumo,
                    ankan = o.ankan.map(::tiles), kakan = tiles(o.kakan), kyuushu = o.kyuushu,
                )
            }
            stage == Stage.claim -> {
                val w = window ?: return null
                val o = w.options[seat] ?: return null
                if (w.answers[seat] != null) return null
                MahjongDecision.Call(
                    windowId = w.id, windowKind = w.kind.rawValue, tile = tile(w.tile), fromSeat = w.from,
                    startedMs = 0.0, deadlineMs = 0.0, bankMs = 0, ron = o.ron, pon = o.pon.map(::tiles),
                    minkan = o.minkan.map(::tiles), chi = o.chi.map(::tiles),
                )
            }
            else -> null
        }
    }

    fun act(seat: Int, action: MahjongTurnAction): MahjongStepResult = step(MahjongEngineStep.Act(seat, action))

    fun call(seat: Int, answer: MahjongCallAnswer): MahjongStepResult = step(MahjongEngineStep.Call(seat, answer))

    /** 그 자리 결정의 시간 초과. 그 자리 결정이 없으면 []. */
    fun timeout(seat: Int): List<MahjongEvent> = step(MahjongEngineStep.Timeout(seat)).eventsOrEmpty

    /** 다음 국 배패(국 끝에서만). */
    fun startNextHand(wall: List<Int>): List<MahjongEvent> {
        if (stage != Stage.handEnd || !isPermutation(wall)) return emptyList()
        val start = log.size
        startNext(wall)
        return log.subList(start, log.size).toList()
    }

    /** 걸음 하나(begin + apply). onReady 는 따라잡기 뒤 · 동작 전의 엔진을 본다(읽기만). */
    fun step(op: MahjongEngineStep, onReady: ((MahjongTableEngine) -> Unit)? = null): MahjongStepResult {
        if (stage == Stage.idle) return MahjongStepResult.Failure(MahjongActError.notDealt)
        if (stage == Stage.finished) return MahjongStepResult.Failure(MahjongActError.over)
        val seat: Int? = when (op) {
            is MahjongEngineStep.Act -> op.seat
            is MahjongEngineStep.Call -> op.seat
            is MahjongEngineStep.Timeout -> op.seat
            is MahjongEngineStep.Away -> op.seat
            is MahjongEngineStep.Back -> op.seat
            MahjongEngineStep.Wait -> null
        }
        if (seat != null && seat !in 0..3) return MahjongStepResult.Failure(MahjongActError.notYourTurn)
        if (op is MahjongEngineStep.Back && !seatState[op.seat].away) return MahjongStepResult.Failure(MahjongActError.awayState)
        val start = log.size
        stepNo += 1
        if (op is MahjongEngineStep.Back) {
            val s = seatState[op.seat]
            s.away = false
            s.awayReason = null
            s.awaySinceMs = null
            s.streak = 0
            emit("away", op.seat) { it.copy(on = false) }
        }
        catchup()
        if (op is MahjongEngineStep.Back || op == MahjongEngineStep.Wait) return MahjongStepResult.Success(log.subList(start, log.size).toList())
        if (stage == Stage.handEnd || stage == Stage.finished) return MahjongStepResult.Failure(MahjongActError.over)
        onReady?.invoke(this)
        val applied: MahjongActError? = when (op) {
            is MahjongEngineStep.Act -> {
                if (stage != Stage.turn || turnSeat != op.seat) return MahjongStepResult.Failure(MahjongActError.notYourTurn)
                if (seatState[op.seat].away) return MahjongStepResult.Failure(MahjongActError.awayState)
                doAct(op.seat, op.action).also { if (it == null) seatState[op.seat].streak = 0 }
            }
            is MahjongEngineStep.Call -> {
                val w = window
                if (stage != Stage.claim || w == null || w.options[op.seat] == null || w.answers[op.seat] != null) {
                    return MahjongStepResult.Failure(MahjongActError.notYourTurn)
                }
                if (seatState[op.seat].away) return MahjongStepResult.Failure(MahjongActError.awayState)
                answer(op.seat, op.answer).also { if (it == null) seatState[op.seat].streak = 0 }
            }
            is MahjongEngineStep.Timeout -> doTimeout(op.seat)
            is MahjongEngineStep.Away -> {
                if (seatState[op.seat].away) return MahjongStepResult.Failure(MahjongActError.awayState)
                markAway(op.seat, op.reason)
                null
            }
            else -> null
        }
        return if (applied == null) MahjongStepResult.Success(log.subList(start, log.size).toList()) else MahjongStepResult.Failure(applied)
    }

    /** 사람 결정을 기다리는 자리(자리 비움 자리는 따라잡기가 처리한다). */
    val pendingSeats: List<Int>
        get() = when (stage) {
            Stage.turn -> if (seatState[turnSeat].away) emptyList() else listOf(turnSeat)
            Stage.claim -> window?.let { w -> w.order.filter { w.options[it] != null && w.answers[it] == null } } ?: emptyList()
            else -> emptyList()
        }

    val scores: List<Int> get() = points.toList()
    val seq: Int get() = seqValue
    val handIndex: Int get() = handIndexValue
    val isFinished: Boolean get() = stage == Stage.finished

    /** 자리 비움 칩(공개). */
    fun isAway(seat: Int): Boolean = seat in 0..3 && seatState[seat].away

    // MARK: - state 투영

    /** §3.6 모양 그대로. seat = 보는 자리(null = 공개 칸만). since = 이 seq 뒤 사건만(최대 80). serverNowMs = 지금(epoch ms). */
    fun payload(seat: Int?, since: Int, serverNowMs: Double): MahjongStatePayload {
        val viewer = seat?.takeIf { it in 0..3 }
        val dealt = stage != Stage.idle
        val m = MahjongStateMatch(
            id = matchID,
            status = if (stage == Stage.finished) "finished" else "active",
            stake = stake,
            format = format.rawValue,
            isPublic = false,
            seq = seqValue,
            endReason = finalRecord?.endReason,
            phase = phase.wireName,
            handIndex = if (dealt) handIndexValue else null,
            round = if (dealt) round else null,
            handNo = if (dealt) handNo else null,
            honba = if (dealt) honba else null,
            kyotaku = if (dealt) kyotaku else null,
            dealerSeat = if (dealt) handNo else null,
            extension = if (dealt) round > (if (format == MahjongFormat.tonpuu) 0 else 1) else null,
            wallRemaining = if (dealt) liveLeft else null,
            doraIndicators = if (dealt) tiles(indicators) else null,
            kanCount = if (dealt) kans else null,
            turnSeat = if (stage == Stage.turn) turnSeat else null,
            baseMs = MahjongClock.baseMs,
            bankFullMs = MahjongClock.bankFullMs,
            graceMs = MahjongClock.graceMs,
        )
        val pay = MahjongRules.payouts(stake)
        val rows = (0 until 4).map { n ->
            val s = seatState[n]
            val fin = finalRecord
            MahjongStateSeat(
                seatNo = n,
                user = users[n],
                wind = windLetters[(n - handNo + 4) % 4],
                isDealer = n == handNo,
                score = points[n],
                handCount = s.hand.size + (if (s.drawn == null) 0 else 1),
                melds = wireMelds(n),
                discards = s.discards.map { MahjongDiscard(tile(it.tile), it.tsumogiri, it.riichi, it.taken) },
                riichi = s.riichi,
                away = s.away,
                deleted = false,
                finalRank = fin?.ranks?.get(n),
                finalScore = fin?.finalScores?.get(n),
                payout = fin?.let { pay[(it.ranks[n] - 1).coerceIn(0, 3)] },
            )
        }
        var p = MahjongStatePayload(match = m, members = emptyList(), seats = if (dealt) rows else emptyList())
        if (viewer != null) {
            val s = seatState[viewer]
            p = p.copy(
                mySeat = viewer,
                myHand = tiles(s.hand.sorted()),
                myDrawn = s.drawn?.let(::tile),
                myWaits = s.waits,
                myFuriten = s.furiten.kinds(s.waits).map { it.rawValue },
                myDecision = decision(viewer),
                myAway = if (s.away) {
                    MahjongAwayState(
                        reason = s.awayReason?.rawValue, sinceMs = s.awaySinceMs,
                        backReadyMs = (s.awaySinceMs ?: nowMs) + (if (s.awayReason == MahjongAwayReason.leave) backCooldownMs else 0.0),
                    )
                } else null,
            )
        }
        val fresh = log.filter { it.seq > since }
        return p.copy(
            events = fresh.takeLast(eventPageLimit).map { visible(it, viewer) },
            lastHand = if (showsLastHand) hands.lastOrNull()?.result else null,
            reactions = emptyList(),
            serverNowMs = serverNowMs,
        )
    }

    /** 부로(원문 꼴). 가깡 창이 열린 동안의 그 퐁은 더한 패까지 가깡으로 보인다. */
    internal fun wireMelds(n: Int): List<MahjongWireMeld> {
        val melds = seatState[n].melds.map { it.copy() }.toMutableList()
        val w = window
        val i = w?.kakanMeld
        if (w != null && w.kind == WindowKind.kakan && w.from == n && i != null && i in melds.indices) {
            melds[i] = melds[i].copy(type = com.yehsung.aingcheck.core.rules.mahjong.MahjongMeldType.kakan, tiles = (melds[i].tiles + w.tile).sorted())
        }
        return melds.map { MahjongWireMeld(it.meld) }
    }
}
