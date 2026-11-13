// 원본: Sources/CheckCore/MahjongStorePractice.swift @ e4995a3a(혼자 연습판 — 혼자 + 봇 셋) — Android 판 8
//
// 연습판은 `practice` 칸 안에서만 돈다. 판 권위는 엔진, 화면이 보는 것은 엔진 payload(사람 자리)를 옮긴 `practice.payload` 뿐이다.
// 서버 `match` 를 건드리지 않고 루비 · 기록 · 미션 · 네트워크는 0. 루비 판이 서면 연습판을 버린다.
// 봇은 메인 밖에서([MahjongStore.botContext]) — 입력은 그 자리 시야 사본, 결과는 세대 · 판 id · 국 · seq · 대기 자리가 그대로일 때만 반영.
// 멈춤: 화면이 탁자를 안 보이거나 · 방을 보는 중 · 방장 + 넷째 착석이면 판 전체가 멈춘다(봇도 안 둔다). 시계는 멈춘 만큼 뒤로 민다.
// 시간: '실전처럼 5+20'일 때만 사람 결정 마감을 잰다. '넉넉히'는 론 아닌 울기 프롬프트만 5초 뒤 안내 · 30초 뒤 저절로 넘김.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.ai.SeededSwiftRandom
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClock
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.stores.alkkagi.randomUUIDString
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import kotlin.time.TimeSource

// MARK: 동작(표면)

/** 연습판을 연다. 루비 판이 진행 중이면 열지 않는다. */
fun MahjongStore.startPractice(format: MahjongFormat, timed: Boolean) {
    if (match?.match?.matchStatus == MahjongMatchStatus.active) return
    beginPractice(format, timed)
}

/** 같은 설정으로 새 연습판. */
fun MahjongStore.restartPractice() {
    val current = practice ?: return
    startPractice(current.format, current.timed)
}

/** 연습판을 닫는다. 서버 방이 있으면 방이 선다. */
fun MahjongStore.endPractice() {
    discardPracticeGame()
    if (showsPractice) showsPractice = false
    recomputePhase()
}

/** 띠의 [방 보기] — 연습은 그대로 두고(멈춘 채) 방을 본다. */
fun MahjongStore.showRoom() {
    if (showsPractice) showsPractice = false
    syncPracticePause()
    recomputePhase()
}

/** 연습으로 돌아가기. */
fun MahjongStore.showPractice() {
    if (practice == null) return
    if (!showsPractice) showsPractice = true
    syncPracticePause()
    recomputePhase()
}

/** 사람 시계가 다 됐으면 대신 둔다 · '넉넉히' 울기 안내/저절로 넘김 · 보조 쯔모기리(시험은 now 를 넣어 직접 부른다). */
fun MahjongStore.handlePracticeClock(now: SwiftDate) {
    val session = practice?.duplicate() ?: return
    val engine = session.engine ?: return
    if (session.isPaused || engine.isFinished) return
    val decision = engine.decision(session.humanSeat) ?: return
    val human = session.humanSeat
    val started = session.humanStartedAt
    if (session.timed && started != null &&
        now >= MahjongClock.deadline(started, session.bankMs).addingTimeInterval(MahjongClock.graceMs.toDouble() / 1_000)
    ) {
        engine.nowMs = practiceServerMs(now)
        val events = engine.timeout(human)
        session.bankMs = 0
        foldTwoStageInputs()
        when {
            events.any { it.kind == "win" } -> setNotice(null)
            decision is MahjongDecision.Turn -> setNotice(MahjongNoticeText.timeoutDiscarded)
            else -> setNotice(MahjongNoticeText.timeoutPassed)
        }
        commitPractice(session)
        return
    }
    val prompt = session.callPromptAt
    if (!session.timed && decision is MahjongDecision.Call && !decision.ron && prompt != null) {
        if (now >= prompt.addingTimeInterval(MahjongStore.practiceIdleCallPassSeconds)) {
            engine.nowMs = practiceServerMs(now)
            engine.call(human, MahjongCallAnswer.Pass)
            foldTwoStageInputs()
            if (notice == MahjongNoticeText.practiceIdleCallHint) setNotice(null)
            commitPractice(session)
            return
        }
        if (now >= prompt.addingTimeInterval(MahjongStore.practiceIdleCallHintSeconds) && !session.hintShown) {
            session.hintShown = true
            practice = session
            setNotice(MahjongNoticeText.practiceIdleCallHint)
        }
    }
    val due = session.aidDueAt
    if (due != null && now >= due) {
        session.aidDueAt = null
        practice = session
        val drawn = session.payload.myDrawn
        if (decision is MahjongDecision.Turn && drawn != null && drawn in decision.discard) {
            practiceAct(MahjongTurnAction.Discard(drawn))
            return
        }
    }
    schedulePracticeClock()
}

// MARK: 사람 동작

internal fun MahjongStore.practiceDiscard(tile: MahjongTile) {
    val session = practice ?: return
    val engine = session.engine ?: return
    if (engine.isAway(session.humanSeat)) {
        practiceComeBack()
        return
    }
    val turn = session.payload.myDecision as? MahjongDecision.Turn ?: return
    if (riichiArmed) {
        if (tile !in turn.riichi) return
        practiceAct(MahjongTurnAction.Riichi(tile))
    } else {
        if (tile !in turn.discard) return
        practiceAct(MahjongTurnAction.Discard(tile))
    }
}

internal fun MahjongStore.practiceCall(kind: MahjongClaimKind, tiles: List<MahjongTile>) {
    val call = practice?.payload?.myDecision as? MahjongDecision.Call ?: return
    if (call.answered != null) return
    val chosen = chooseCallTiles(kind, tiles, call) ?: return
    // 엔진에는 엔진이 준 조합 그대로(순서 포함)를 돌려준다.
    val option = MahjongStore.options(kind, call).firstOrNull { it.sorted() == chosen } ?: chosen
    when (kind) {
        MahjongClaimKind.ron -> practiceAnswer(MahjongCallAnswer.Ron)
        MahjongClaimKind.pon -> practiceAnswer(MahjongCallAnswer.Pon(option))
        MahjongClaimKind.minkan -> practiceAnswer(MahjongCallAnswer.Minkan(option))
        MahjongClaimKind.chi -> practiceAnswer(MahjongCallAnswer.Chi(option))
    }
}

internal fun MahjongStore.practiceAct(action: MahjongTurnAction) = practiceHumanStep { MahjongEngineStep.Act(it, action) }

internal fun MahjongStore.practiceAnswer(answer: MahjongCallAnswer) = practiceHumanStep { MahjongEngineStep.Call(it, answer) }

/** [돌아왔어요] — 자리 비움(실전처럼에서 시간 초과 연속 3)에서 돌아온다. */
internal fun MahjongStore.practiceComeBack() {
    val session = practice ?: return
    val engine = session.engine ?: return
    if (!engine.isAway(session.humanSeat)) return
    practiceHumanStep { MahjongEngineStep.Back(it) }
}

/** 사람 걸음 하나 — 멈춘 동안은 받지 않는다. 실패한 걸음도 따라잡기는 남으므로 늘 옮겨 적는다. */
private fun MahjongStore.practiceHumanStep(make: (Int) -> MahjongEngineStep) {
    val session = practice?.duplicate() ?: return
    val engine = session.engine ?: return
    if (session.isPaused || engine.isFinished) return
    val now = clock()
    val started = session.humanStartedAt
    if (session.timed && started != null) session.bankMs = MahjongClock.charge(started, now, session.bankMs).bankLeft
    engine.nowMs = practiceServerMs(now)
    when (engine.step(make(session.humanSeat))) {
        is MahjongStepResult.Success -> {
            foldTwoStageInputs()
            if (notice != null) setNotice(null)
        }
        is MahjongStepResult.Failure -> setNotice(MahjongNoticeText.notAnOption)
    }
    commitPractice(session)
}

private fun MahjongStore.beginPractice(format: MahjongFormat, timed: Boolean) {
    val runtime = practiceRuntime
    runtime.cancelTasks()
    val generation = runtime.bump()
    val human = runtime.pickHumanSeat().coerceIn(0, 3)
    var bot = 0
    val seats = (0 until 4).map { seat ->
        if (seat == human) {
            MahjongStateUser(userId = myUserID ?: MahjongStore.practiceHumanID, displayName = MahjongNoticeText.practiceMe)
        } else {
            bot += 1
            MahjongStateUser(
                userId = "${MahjongStatePayload.practiceIDPrefix}bot-$bot", displayName = MahjongNoticeText.practiceBotName(bot),
                character = ShopWire.robotCharacterID,
            )
        }
    }
    val id = MahjongStatePayload.practiceIDPrefix + randomUUIDString()
    val engine = MahjongTableEngine(format, seats)
    engine.matchID = id
    val now = clock()
    engine.nowMs = practiceServerMs(now)
    engine.deal(runtime.makeWall())
    if (engine.phase == MahjongEnginePhase.Idle) return // 패산이 순열이 아니다 — 판을 세우지 않는다
    val session = MahjongPracticeSession(id, format, timed, human, generation, engine.payload(human, 0, practiceServerMs(now)))
    session.engine = engine
    if (!isWindowShowingTable) {
        session.isPaused = true
        session.pausedAt = now
    }
    practice = session
    foldTwoStageInputs()
    setNotice(null)
    if (!showsPractice) showsPractice = true
    commitPractice(session)
}

/** 연습판을 버린다(루비 판이 섰다 · 연습 끝내기 · 리셋). showsPractice 는 부르는 쪽이 정한다. */
internal fun MahjongStore.discardPracticeGame() {
    practiceRuntime.cancelTasks()
    practiceRuntime.bump()
    if (practice != null) practice = null
}

/** 연습판의 ms 칸은 서버 ms 공간에 둔다(화면은 serverClockOffset 한 길로 기기 시각을 얻는다). */
internal fun MahjongStore.practiceServerMs(date: SwiftDate): Double = (date.timeIntervalSince1970 - serverClockOffset) * 1_000

/** 엔진 값을 화면 값으로 옮기고 다음 일을 예약한다. 새 사람 결정이면 시계 · 안내 · 2단 입력을 새로 잡는다. */
internal fun MahjongStore.commitPractice(value: MahjongPracticeSession) {
    val session = value.duplicate()
    val engine = session.engine ?: return
    val now = clock()
    if (session.bankHandIndex != engine.handIndex) {
        session.bankHandIndex = engine.handIndex
        session.bankMs = MahjongClock.bankFullMs
    }
    val decision = engine.decision(session.humanSeat)
    val anchor = MahjongStore.practiceAnchor(decision, engine.handIndex)
    val isNewDecision = anchor != session.humanAnchor
    if (isNewDecision) {
        session.humanAnchor = anchor
        session.humanStartedAt = if (decision == null) null else (session.pausedAt ?: now)
        session.callPromptAt = if (decision is MahjongDecision.Call && !decision.ron) (session.pausedAt ?: now) else null
        session.hintShown = false
        session.aidDueAt = null
        foldTwoStageInputs()
        if (notice == MahjongNoticeText.practiceIdleCallHint) setNotice(null)
    }
    val phase = engine.phase
    if (phase is MahjongEnginePhase.Claim) {
        if (session.windowID != phase.windowId) {
            session.windowID = phase.windowId
            session.claimReadyAt = (session.pausedAt ?: now).addingTimeInterval(practiceRuntime.pauseSeconds() * practiceRuntime.delayScale)
        }
    } else {
        session.windowID = null
        session.claimReadyAt = null
    }
    session.payload = practicePayload(session, engine, now)
    practice = session
    recomputePhase()
    if (isNewDecision) runPracticeAids()
    schedulePracticeTurnIfNeeded()
}

/** 엔진 투영 + 연습 시계(실전처럼일 때만 사람 결정에 시작 · 마감 · 예비를 싣는다). */
internal fun MahjongStore.practicePayload(session: MahjongPracticeSession, engine: MahjongTableEngine, now: SwiftDate): MahjongStatePayload {
    val payload = engine.payload(session.humanSeat, 0, practiceServerMs(now))
    val started = session.humanStartedAt
    val decision = payload.myDecision
    if (!session.timed || started == null || decision == null) return payload
    val startedMs = practiceServerMs(started)
    val bank = session.bankMs
    val deadlineMs = startedMs + (MahjongClock.baseMs + bank).toDouble()
    val timedDecision: MahjongDecision = when (decision) {
        is MahjongDecision.Turn -> decision.copy(startedMs = startedMs, deadlineMs = deadlineMs, bankMs = bank)
        is MahjongDecision.Call -> decision.copy(startedMs = startedMs, deadlineMs = deadlineMs, bankMs = bank)
    }
    return payload.copy(myDecision = timedDecision)
}

/** 멈춤을 다시 잰다. 멈추면 봇 · 시계 작업을 모두 거두고, 이어 가면 시계들을 멈춘 만큼 뒤로 민다. */
internal fun MahjongStore.syncPracticePause() {
    val session = practice?.duplicate() ?: return
    val shouldPause = !(isWindowShowingTable && showsPractice) || session.roomHold
    if (shouldPause == session.isPaused) return
    val now = clock()
    if (shouldPause) {
        session.isPaused = true
        session.pausedAt = now
        practice = session
        practiceRuntime.cancelTasks()
        practiceRuntime.bump()
        return
    }
    val paused = session.pausedAt?.let { maxOf(0.0, now.timeIntervalSince(it)) } ?: 0.0
    session.humanStartedAt = session.humanStartedAt?.addingTimeInterval(paused)
    session.callPromptAt = session.callPromptAt?.addingTimeInterval(paused)
    session.claimReadyAt = session.claimReadyAt?.addingTimeInterval(paused)
    session.aidDueAt = session.aidDueAt?.addingTimeInterval(paused)
    session.isPaused = false
    session.pausedAt = null
    commitPractice(session)
}

/** 연습 중 서버 방: 방장이 보는 방에 넷째가 앉은 순간 연습을 멈춘다. 방이 넷이 아니게 되면 풀린다. */
internal fun MahjongStore.syncPracticeRoomHold(old: MahjongStatePayload?) {
    val session = practice?.duplicate() ?: return
    val room = match?.match
    val gathered = room?.matchStatus == MahjongMatchStatus.forming && MahjongStore.joinedCount(match) >= 4
    var hold = session.roomHold
    if (!gathered) {
        hold = false
    } else if (!hold && isHost && room != null && old?.match?.id == room.id && old.match?.matchStatus == MahjongMatchStatus.forming &&
        MahjongStore.joinedCount(old) < 4
    ) {
        hold = true
    }
    if (hold == session.roomHold) return
    session.roomHold = hold
    practice = session
    syncPracticePause()
}

/** 사람 보조(결정마다 한 번 — 연습판은 늘 이 기기 판): 자동 화료 · 울지 않음(국마다 꺼짐) · 쯔모기리. */
private fun MahjongStore.runPracticeAids() {
    val session = practice?.duplicate() ?: return
    if (session.isPaused) return
    val engine = session.engine ?: return
    val decision = session.payload.myDecision ?: return
    val anchor = session.humanAnchor ?: return
    val handKey = "${session.matchID}#${engine.handIndex}"
    if (aids.noCalls) {
        val marked = noCallsHandKey
        if (marked != null && marked != handKey) {
            noCallsHandKey = null
            aids = aids.copy(noCalls = false)
        } else if (marked == null) {
            noCallsHandKey = handKey
        }
    }
    when (decision) {
        is MahjongDecision.Turn -> {
            if (aids.autoWin && decision.tsumo) {
                practiceAidHop(anchor) { it.practiceAct(MahjongTurnAction.Tsumo) }
                return
            }
            val drawn = session.payload.myDrawn
            if (!aids.tsumogiri || decision.tsumo || decision.ankan.isNotEmpty() || decision.kakan.isNotEmpty() || decision.riichi.isNotEmpty() ||
                drawn == null || drawn !in decision.discard
            ) return
            session.aidDueAt = clock().addingTimeInterval(aidJitter() * practiceRuntime.delayScale)
            practice = session
        }
        is MahjongDecision.Call -> {
            if (aids.autoWin && decision.ron) practiceAidHop(anchor) { it.practiceAnswer(MahjongCallAnswer.Ron) }
            else if (aids.noCalls && !decision.ron) practiceAidHop(anchor) { it.practiceAnswer(MahjongCallAnswer.Pass) }
        }
    }
}

/** 보조 동작은 다음 차례로 미뤄 보낸다(옮겨 적기 도중에 다시 들어가지 않게) — 그 사이 결정이 바뀌었으면 안 보낸다. */
private fun MahjongStore.practiceAidHop(anchor: String, body: (MahjongStore) -> Unit) {
    scope.launch {
        if (practice?.humanAnchor != anchor || practice?.isPaused != false) return@launch
        body(this@practiceAidHop)
    }
}

/** 지금 판에서 다음 일을 맡긴다: 봇 차례 · 봇 울기 답(창 멈춤 뒤) · 미룬 쯔모 · 자리 비움 차례 · 다음 국. 사람 차례면 시계만 건다. */
internal fun MahjongStore.schedulePracticeTurnIfNeeded() {
    val runtime = practiceRuntime
    runtime.botJob?.cancel()
    runtime.botJob = null
    runtime.stepJob?.cancel()
    runtime.stepJob = null
    val generation = runtime.bump()
    try {
        val session = practice ?: return
        val engine = session.engine ?: return
        if (session.isPaused) return
        val human = session.humanSeat
        val scale = runtime.delayScale
        when (val phase = engine.phase) {
            MahjongEnginePhase.Idle, MahjongEnginePhase.Finished -> return
            is MahjongEnginePhase.HandEnd -> schedulePracticeStep(PracticeStep.nextHand, MahjongStore.practiceHandRestSeconds(phase.result.wins?.size ?: 0) * scale, generation)
            is MahjongEnginePhase.DrawWait -> schedulePracticeStep(PracticeStep.wait, runtime.pauseSeconds() * scale, generation)
            is MahjongEnginePhase.Turn -> {
                if (engine.isAway(phase.seat)) schedulePracticeStep(PracticeStep.wait, runtime.pauseSeconds() * scale, generation)
                else if (phase.seat != human) schedulePracticeBot(phase.seat, null, generation)
            }
            is MahjongEnginePhase.Claim -> {
                val pending = engine.pendingSeats
                val seat = pending.firstOrNull { it != human }
                if (seat != null) schedulePracticeBot(seat, session.claimReadyAt, generation)
                else if (pending.isEmpty()) schedulePracticeStep(PracticeStep.wait, 0.0, generation)
            }
        }
    } finally {
        schedulePracticeClock()
    }
}

internal enum class PracticeStep { wait, nextHand }

private fun MahjongStore.schedulePracticeStep(kind: PracticeStep, seconds: Double, generation: Int) {
    practiceRuntime.stepJob = scope.launch {
        if (seconds > 0) delay(delayMillis(seconds))
        if (practiceRuntime.generation != generation) return@launch
        val session = practice?.duplicate() ?: return@launch
        val engine = session.engine ?: return@launch
        if (session.isPaused) return@launch
        practiceRuntime.stepJob = null
        val beforeSeq = engine.seq
        val beforePhase = engine.phase
        engine.nowMs = practiceServerMs(clock())
        when (kind) {
            PracticeStep.wait -> engine.step(MahjongEngineStep.Wait)
            PracticeStep.nextHand -> engine.startNextHand(practiceRuntime.makeWall())
        }
        // 아무 일도 안 일어났으면 다시 맡기지 않는다(0초 걸음이 제자리를 도는 일을 막는다).
        if (engine.seq == beforeSeq && engine.phase == beforePhase) {
            practice = session
            return@launch
        }
        commitPractice(session)
    }
}

/** 봇 한 자리의 결정을 메인 밖에 맡긴다. 끝나면 세대 · 판 id · 국 · seq · 대기 자리가 그대로일 때만 반영한다. */
private fun MahjongStore.schedulePracticeBot(seat: Int, notBefore: SwiftDate?, generation: Int) {
    val session = practice ?: return
    val engine = session.engine ?: return
    val runtime = practiceRuntime
    val now = clock()
    val view = engine.payload(seat, 0, practiceServerMs(now)) // 메인에서 만든 그 자리 시야 사본(값)
    val matchID = session.matchID
    val seq = engine.seq
    val hand = engine.handIndex
    val decide = runtime.decide
    val seed = runtime.nextSeed()
    val scale = runtime.delayScale
    val hold = maxOf(0.0, notBefore?.timeIntervalSince(now) ?: 0.0)
    runtime.noteBotCall()
    runtime.botJob = scope.launch {
        val started = TimeSource.Monotonic.markNow()
        val move = withContext(botContext) {
            val job: Job? = coroutineContext[Job]
            decide.decide(view, seed) { job?.isActive == false }
        }
        val think = MahjongBot.thinkSeconds(move, view, SeededSwiftRandom(seed xor 0x9E37_79B9_7F4A_7C15uL)) * scale
        val spent = started.elapsedNow().inWholeMilliseconds / 1000.0
        val remaining = maxOf(think, hold) - spent
        if (remaining > 0) delay(delayMillis(remaining))
        val current = practice
        val live = current?.engine
        if (!isActive || practiceRuntime.generation != generation || current == null || current.matchID != matchID || current.isPaused ||
            live == null || live.seq != seq || live.handIndex != hand || seat !in live.pendingSeats
        ) {
            practiceRuntime.droppedBotMoves += 1
            return@launch
        }
        practiceRuntime.botJob = null
        applyPracticeBotMove(move, seat)
    }
}

/** 봇 수를 엔진에 넣는다. 규칙 밖이면(엔진 거절) 판이 멈추지 않게 버림(마지막 후보) · 넘김으로 대신 둔다. */
private fun MahjongStore.applyPracticeBotMove(move: MahjongBotMove, seat: Int) {
    val session = practice?.duplicate() ?: return
    val engine = session.engine ?: return
    engine.nowMs = practiceServerMs(clock())
    var applied = false
    when (move) {
        is MahjongBotMove.Act -> if (engine.act(seat, move.action) is MahjongStepResult.Success) applied = true
        is MahjongBotMove.Call -> {
            val phase = engine.phase
            if (phase is MahjongEnginePhase.Claim && phase.windowId == move.windowId && engine.call(seat, move.answer) is MahjongStepResult.Success) applied = true
        }
        MahjongBotMove.None -> Unit
    }
    if (!applied) {
        when (val decision = engine.decision(seat)) {
            is MahjongDecision.Turn -> decision.discard.lastOrNull()?.let { engine.act(seat, MahjongTurnAction.Discard(it)) }
            is MahjongDecision.Call -> engine.call(seat, MahjongCallAnswer.Pass)
            null -> Unit
        }
    }
    commitPractice(session)
}

/** 사람 시계 작업을 (다시) 건다. 실제 타이머는 timersEnabled 일 때만. */
internal fun MahjongStore.schedulePracticeClock() {
    val runtime = practiceRuntime
    runtime.clockJob?.cancel()
    runtime.clockJob = null
    if (!timersEnabled) return
    val due = nextPracticeClockDate() ?: return
    val generation = runtime.generation
    val wait = maxOf(0.0, due.timeIntervalSince(clock())) + 0.02
    runtime.clockJob = scope.launch {
        delay(delayMillis(wait))
        if (practiceRuntime.generation != generation) return@launch
        practiceRuntime.clockJob = null
        handlePracticeClock(clock())
    }
}

/** 다음으로 사람 시계가 깨어날 때. */
internal fun MahjongStore.nextPracticeClockDate(): SwiftDate? {
    val session = practice ?: return null
    val engine = session.engine ?: return null
    if (session.isPaused || engine.decision(session.humanSeat) == null) return null
    val dates = mutableListOf<SwiftDate>()
    session.aidDueAt?.let { dates += it }
    val started = session.humanStartedAt
    val prompt = session.callPromptAt
    if (session.timed && started != null) {
        dates += MahjongClock.deadline(started, session.bankMs).addingTimeInterval(MahjongClock.graceMs.toDouble() / 1_000)
    } else if (prompt != null) {
        dates += prompt.addingTimeInterval(if (session.hintShown) MahjongStore.practiceIdleCallPassSeconds else MahjongStore.practiceIdleCallHintSeconds)
    }
    return dates.minOrNull()
}
