// 원본: Sources/CheckCore/ChessStoreAI.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.ai.ChessAI
import com.yehsung.aingcheck.core.rules.chess.ChessClock
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessOutcome
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessRepetitionLedger
import com.yehsung.aingcheck.core.rules.chess.ChessRules
import com.yehsung.aingcheck.core.rules.chess.ChessTimeoutRuling
import com.yehsung.aingcheck.core.rules.chess.fen
import com.yehsung.aingcheck.core.rules.chess.san
import com.yehsung.aingcheck.core.stores.gomoku.roundHalfAwayFromZero
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

// 체스 스토어의 **AI 대국** 갈래 — 기기 혼자 두는 한 판(A1·A5: 단일 난이도).
//
// ── 서버와 섞이지 않는다 ── AI 판은 [ChessAIGame] 이 권위이고 `match` 는 그 값을 옮겨 적은 화면 값이다. 서버 경로는 id 머리말("ai-")로 막는다.
// ── 합법 수의 주인이 뒤집힌다(ChessStore 머리말 ⑦) ── AI 판에는 서버가 없으므로 로컬 `ChessRules.legalMoves` 가 그 자리를 채운다 —
//    그래도 **사람 차례일 때만** 채운다(서버가 그러하므로 화면이 두 경로에서 같은 코드를 쓴다).
// ── 늦게 끝난 AI 수는 버린다 ── 세대·판 id·수 번호·차례가 하나라도 다르면 결과를 버린다.
// ── 시계는 창이 보일 때만 돈다 ── 창이 안 보이면 **쓴 시간을 그 자리에서 빼고** 멈춘다(1:1 은 반대다 — 서버에서 시간이 흐른다).
// **판돈 깃발(§8-17 #1)과는 무관하다**(루비·전적·순위가 없다 — 사용자 결정).
//
// Kotlin 몫: Swift `ChessAIGame` 은 값 타입이다. W1-b 의 `ChessPosition`·`ChessRepetitionLedger` 가 가변 참조라 [ChessAIGame] 은 가변 클래스 +
// [ChessAIGame.copy] 로 옮겼고, 스토어는 들고 있는 판을 고치지 않고 사본에 고쳐 통째로 바꿔 넣는다.

/** AI 수 선택기. 국면과 반복 장부를 받아 한 수(없으면 null)를 돌려준다. 시험이 결정적 가짜로 갈아 끼운다. */
typealias ChessAIMoveChooser = suspend (ChessPosition, Map<String, Int>) -> ChessMove?

/** AI 갈래의 관찰 대상이 아닌 장부. */
class ChessAIRuntime {
    companion object {
        /** 기본 선택기: 엔진을 백그라운드에서 돌리고, 기다리던 쪽이 취소되면 **엔진에도 취소를 전한다**. */
        val engineChooser: ChessAIMoveChooser = { position, repetitionCounts ->
            withContext(Dispatchers.Default) {
                val job = coroutineContext[Job]
                ChessAI.bestMove(position = position, repetitionCounts = repetitionCounts, isCancelled = { job?.isActive == false })
            }
        }
    }

    var chooser: ChessAIMoveChooser = engineChooser
    /** AI 가 즉답해도 화면에 "생각 중" 을 이만큼은 보여 준다(초). 시험은 0. */
    var minimumThinkSeconds: Double = 0.6

    /** 판이 바뀔 때마다 오른다. 늦게 끝난 계산을 버리는 기준이다. */
    var generation: Int = 0
        private set
    /** 선택기를 부른 횟수(진단·시험 지점). */
    var chooserCalls: Int = 0
        private set
    internal var moveTask: Job? = null
    internal var clockTask: Job? = null

    internal fun bump(): Int {
        generation += 1
        return generation
    }

    internal fun noteChooserCall() {
        chooserCalls += 1
    }

    internal fun cancelTasks() {
        moveTask?.cancel()
        moveTask = null
        clockTask?.cancel()
        clockTask = null
    }
}

/**
 * AI 와 두는 체스 한 판의 **로컬 상태**(시계는 밖에서 `now` 로 넣는다). 규칙은 서버 1:1 과 **한 벌**이다: `ChessRules` 하나가 합법 수·체크·종국을
 * 판정하고, 3회 반복은 `ChessRepetitionLedger` 가 센다. 시계는 10분 + 한 수 3초 가산이고 **다 쓰면 패배**다(B4).
 */
class ChessAIGame private constructor(
    val id: String,
    val humanColor: ChessColor,
    val incrementMs: Long,
    position: ChessPosition,
    ledger: ChessRepetitionLedger,
    whiteMsLeft: Long,
    blackMsLeft: Long,
    turnStartedAt: SwiftDate?,
) {
    val aiColor: ChessColor get() = humanColor.opponent

    var position: ChessPosition = position
        private set
    /** 3회 반복 장부. **시작 국면도 한 번 적는다**(서버 `chess__rep_count` 와 같은 눈금). */
    var ledger: ChessRepetitionLedger = ledger
        private set
    private val movesStorage = ArrayList<ChessMoveRecord>()
    val moves: List<ChessMoveRecord> get() = movesStorage.toList()
    var whiteMsLeft: Long = whiteMsLeft
        private set
    var blackMsLeft: Long = blackMsLeft
        private set
    /** 차례가 시작된 시각. **null 이면 시계가 멈춰 있다**(창이 안 보인다 · 판이 끝났다). */
    var turnStartedAt: SwiftDate? = turnStartedAt
        private set
    var isFinished: Boolean = false
        private set
    /** **사람 기준** 결과. */
    var outcome: ChessMatchOutcome? = null
        private set
    var endReason: ChessEndReason? = null
        private set

    /** 끝나면 null(1:1 과 같은 규약). */
    val turn: ChessColor? get() = if (isFinished) null else position.sideToMove
    val plyCount: Int get() = movesStorage.size
    val lastMove: ChessMove? get() = movesStorage.lastOrNull()?.move

    fun msLeft(color: ChessColor): Long = if (color == ChessColor.white) whiteMsLeft else blackMsLeft

    fun copy(): ChessAIGame {
        val other = ChessAIGame(id, humanColor, incrementMs, position.copy(), ledger.copy(), whiteMsLeft, blackMsLeft, turnStartedAt)
        other.movesStorage.addAll(movesStorage)
        other.isFinished = isFinished
        other.outcome = outcome
        other.endReason = endReason
        return other
    }

    /** 차례인 쪽의 남은 초. **음수가 될 수 있다**. */
    fun rawRemainingSeconds(color: ChessColor, now: SwiftDate): Double {
        val stored = msLeft(color).toDouble() / 1000
        val started = turnStartedAt
        if (isFinished || started == null || position.sideToMove != color) return stored
        return stored - now.timeIntervalSince(started)
    }

    /** 차례인 쪽의 깃발이 떨어졌는가(시계가 돌고 있을 때만). */
    fun isFlagged(now: SwiftDate): Boolean {
        if (isFinished || turnStartedAt == null) return false
        return rawRemainingSeconds(position.sideToMove, now) <= 0
    }

    /** 깃발이 떨어진 판을 닫는다 — 판정은 **FIDE 6.9**(`ChessRules.timeoutRuling`)다. 상대가 메이트할 기물이 없으면 무승부(`timeout_insufficient`). */
    fun applyFlag(now: SwiftDate) {
        if (!isFlagged(now)) return
        val flagged = position.sideToMove
        when (val ruling = ChessRules.timeoutRuling(position, flagged)) {
            ChessTimeoutRuling.DrawByInsufficientMaterial -> finish(null, ChessEndReason.timeoutInsufficient)
            is ChessTimeoutRuling.Loss -> finish(ruling.flagged.opponent, ChessEndReason.timeout)
        }
        // 깃발이 떨어진 쪽의 시계는 0 이다(화면이 "1초 남음" 으로 멈추지 않게).
        if (flagged == ChessColor.white) whiteMsLeft = 0 else blackMsLeft = 0
    }

    /** 창이 안 보이게 됐다 — **쓴 시간을 그 자리에서 빼고** 멈춘다. */
    fun pause(now: SwiftDate) {
        val started = turnStartedAt
        if (isFinished || started == null) return
        val spent = maxOf(0L, roundHalfAwayFromZero(now.timeIntervalSince(started) * 1000))
        val side = position.sideToMove
        val left = maxOf(0L, msLeft(side) - spent)
        if (side == ChessColor.white) whiteMsLeft = left else blackMsLeft = left
        turnStartedAt = null
    }

    /** 창이 다시 보인다 — 멈춘 시계를 이어 간다. */
    fun resume(now: SwiftDate) {
        if (isFinished || turnStartedAt != null) return
        turnStartedAt = now
    }

    /**
     * 한 수를 둔다(사람·AI 공용). 거절이면 그 사유를 돌려준다(null = 받아들였다). 순서가 서버 `chess_move` 와 같다: ① 깃발 먼저 ② 합법성
     * ③ 시계 차감(가산은 **둔 뒤에** 붙는다) ④ 기록 ⑤ 판 갱신 ⑥ 종국 판정.
     */
    fun play(move: ChessMove, now: SwiftDate): ChessTapRefusal? {
        if (isFinished) return ChessTapRefusal.finished
        if (isFlagged(now)) {
            applyFlag(now)
            return null // 판이 끝났다 — 거절이 아니라 결과다
        }
        val legal = ChessRules.legalMoves(position)
        if (move !in legal) return ChessTapRefusal.illegalTarget
        val san = ChessRules.san(move, position, legal) ?: return ChessTapRefusal.illegalTarget
        val after = ChessRules.apply(move, position) ?: return ChessTapRefusal.illegalTarget

        val side = position.sideToMove
        val started = turnStartedAt
        val spent = if (started != null) maxOf(0L, roundHalfAwayFromZero(now.timeIntervalSince(started) * 1000)) else 0L
        val left = maxOf(0L, msLeft(side) - spent) + incrementMs
        if (side == ChessColor.white) whiteMsLeft = left else blackMsLeft = left

        movesStorage.add(ChessMoveRecord(movesStorage.size + 1, side, move, san, after.fen, left, spent))
        position = after
        ledger.record(after)
        if (turnStartedAt != null) turnStartedAt = now
        settleIfOver()
        return null
    }

    /** 사람이 기권했다. */
    fun resign() {
        if (isFinished) return
        finish(aiColor, ChessEndReason.resign)
    }

    /** 화면 값으로 옮긴다. `legalMoves` 는 **사람 차례일 때만** 채운다. */
    fun matchState(opponent: ChessUser = ChessUser.chessAI): ChessMatchState = ChessMatchState(
        id = id, stake = 0, myColor = humanColor, opponent = opponent, fen = position.fen,
        position = position.copy(), plyCount = plyCount, turn = turn, lastMove = lastMove, moves = moves,
        clock = ChessServerClock(
            whiteMsLeft = whiteMsLeft, blackMsLeft = blackMsLeft, incrementMs = incrementMs,
            turnStartedAt = if (isFinished) null else turnStartedAt,
            running = if (turnStartedAt == null) null else turn,
        ),
        isInCheck = if (isFinished) false else ChessRules.isInCheck(position),
        legalMoves = if (turn == humanColor) ChessRules.legalMoves(position) else emptyList(),
        isFinished = isFinished, outcome = outcome, endReason = endReason,
        rubyDelta = if (isFinished) 0 else null, drawOfferBy = null, drawOfferedByMe = false,
    )

    /** 지금 국면이 끝난 판인가 — **`ChessRules.outcome` 하나가 판정한다**(3회 반복은 장부로 센다). */
    private fun settleIfOver() {
        if (isFinished) return
        when (val result = ChessRules.outcome(position, ledger.repetitionCounts) ?: return) {
            is ChessOutcome.Checkmate -> finish(result.winner, ChessEndReason.checkmate)
            ChessOutcome.Stalemate -> finish(null, ChessEndReason.stalemate)
            ChessOutcome.InsufficientMaterial -> finish(null, ChessEndReason.insufficientMaterial)
            ChessOutcome.FiftyMoveRule -> finish(null, ChessEndReason.fiftyMove)
            ChessOutcome.ThreefoldRepetition -> finish(null, ChessEndReason.threefold)
        }
    }

    private fun finish(winner: ChessColor?, reason: ChessEndReason) {
        isFinished = true
        endReason = reason
        turnStartedAt = null
        outcome = when (winner) {
            humanColor -> ChessMatchOutcome.won
            null -> ChessMatchOutcome.draw
            else -> ChessMatchOutcome.lost
        }
    }

    override fun equals(other: Any?): Boolean =
        other is ChessAIGame && other.id == id && other.humanColor == humanColor && other.incrementMs == incrementMs &&
            other.position == position && other.ledger == ledger && other.movesStorage == movesStorage &&
            other.whiteMsLeft == whiteMsLeft && other.blackMsLeft == blackMsLeft && other.turnStartedAt == turnStartedAt &&
            other.isFinished == isFinished && other.outcome == outcome && other.endReason == endReason

    override fun hashCode(): Int = id.hashCode() * 31 + movesStorage.size

    companion object {
        /** 판 id 머리말. 서버 판 id 는 uuid 라 이 머리말로 시작할 수 없다 — **이 한 줄이 서버 경로 차단의 근거다.** */
        const val idPrefix: String = "ai-"

        /** 이 id 가 AI 판인가. 스토어의 서버 경로(조회·착수·무승부)가 이 판정으로 요청을 막는다. */
        fun isAIMatchID(id: String?): Boolean = id?.startsWith(idPrefix) ?: false

        @OptIn(ExperimentalUuidApi::class)
        private fun newID(): String = idPrefix + Uuid.random().toString().lowercase()

        /** 새 판. 백이 먼저 두므로 사람이 백이면 곧바로 사람 시계가 돈다(멈출지는 스토어가 곧이어 정한다). */
        fun start(
            humanColor: ChessColor,
            now: SwiftDate,
            id: String = newID(),
            position: ChessPosition = ChessPosition.standard,
            initialMs: Long = ChessClock.initialMs.toLong(),
            incrementMs: Long = 3_000,
        ): ChessAIGame {
            val ledger = ChessRepetitionLedger()
            ledger.record(position)
            val game = ChessAIGame(
                id, humanColor, maxOf(0L, incrementMs), position.copy(), ledger,
                maxOf(0L, initialMs), maxOf(0L, initialMs), now,
            )
            // 손으로 짠 시작 국면이 이미 끝난 판일 수 있다(검증·시험 경로) — 새 판도 같은 문으로 판정한다.
            game.settleIfOver()
            return game
        }
    }
}

// MARK: 읽기

/** 지금 들고 있는 판이 AI 판인가. */
val ChessStore.isAIMatch: Boolean
    get() {
        val game = aiGame ?: return false
        val current = match ?: return false
        return current.id == game.id
    }

/** AI 가 둘 차례인가(화면의 "생각 중"). */
val ChessStore.isAIThinking: Boolean
    get() {
        if (!isAIMatch) return false
        val game = aiGame ?: return false
        return !game.isFinished && game.turn == game.aiColor
    }

/** 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나 보낸 신청이 떠 있으면 안 된다. **판돈 깃발과는 무관하다.** */
val ChessStore.canStartAIMatch: Boolean
    get() = phase == ChessPhase.lobby && match == null && outgoing == null && activeMatchID == null && !isBusy

/** 시험 주입점: AI 수 선택기. */
var ChessStore.aiMoveChooser: ChessAIMoveChooser
    get() = aiRuntime.chooser
    set(value) {
        aiRuntime.chooser = value
    }

// MARK: 동작

/** 로비에서 AI 대국을 시작한다. 사람이 고른 색으로 두고, AI 가 백이면 곧바로 AI 가 생각한다. */
fun ChessStore.startAIMatch(humanColor: ChessColor) {
    if (!canStartAIMatch) {
        if (match != null || activeMatchID != null) setNotice(ChessNoticeText.busy)
        return
    }
    beginAIGame(humanColor)
}

/** 결과 화면 [다시 두기] — 같은 색으로 새 판. */
fun ChessStore.restartAIMatch() {
    val game = aiGame ?: return
    if (!isAIMatch || !game.isFinished) return
    beginAIGame(game.humanColor)
}

/** 시계가 다 됐으면 판을 닫는다(시계 작업이 깨어나 부른다 — 시험은 `now` 를 넣어 직접 부른다). */
fun ChessStore.handleAIClock(now: SwiftDate) {
    if (!isAIMatch) return
    val game = aiGame?.copy() ?: return
    if (!game.isFlagged(now)) {
        scheduleAIClock()
        return
    }
    game.applyFlag(now)
    commitAIGame(game)
}

/** 스토어 본문 `send` 의 AI 분기. 거절이면 그 사유를 돌려준다(본문이 문구·진단 줄로 흘린다). */
internal fun ChessStore.moveInAIMatch(move: ChessMove): ChessTapRefusal? {
    val game = aiGame?.copy() ?: return ChessTapRefusal.noMatch
    if (game.turn != game.humanColor) return ChessTapRefusal.notYourTurn
    game.play(move, clock())?.let { return it }
    setNotice(null)
    commitAIGame(game)
    scheduleAITurnIfNeeded()
    return null
}

/** 기권(본문 `resign` 의 앞머리). */
internal fun ChessStore.resignAIMatch() {
    val game = aiGame?.copy() ?: return
    if (game.isFinished) return
    game.resign()
    setNotice(null)
    commitAIGame(game)
}

/** 창이 안 보이게 됐다 — 시계를 멈춘다. */
internal fun ChessStore.pauseAIClock() {
    if (!isAIMatch) return
    val game = aiGame?.copy() ?: return
    if (game.turnStartedAt == null) return
    game.pause(clock())
    commitAIGame(game)
}

/** 창이 다시 보인다 — 멈춘 시계를 이어 간다(보이지 않으면 그대로 둔다). */
internal fun ChessStore.resumeAIClockIfVisible() {
    if (!isAIMatch || !isWindowVisible || isWindowOccluded) return
    val game = aiGame?.copy() ?: return
    if (game.isFinished || game.turnStartedAt != null) return
    game.resume(clock())
    commitAIGame(game)
}

/** AI 판을 버린다(1:1 판이 열렸다 · 로비로 · 로그아웃). `match` 는 건드리지 않는다. */
internal fun ChessStore.discardAIGame() {
    aiRuntime.cancelTasks()
    aiRuntime.bump()
    if (aiGame != null) aiGame = null
}

// MARK: 내부

private fun ChessStore.beginAIGame(humanColor: ChessColor) {
    aiRuntime.cancelTasks()
    aiRuntime.bump()
    val game = ChessAIGame.start(humanColor = humanColor, now = clock(), initialMs = initialMs, incrementMs = incrementMs)
    // 순서가 계약이다: 판을 먼저 세우고 화면 값을 옮긴다(`match` 대입은 id 가 같으면 버리지 않는다).
    aiGame = game.copy()
    setNotice(null)
    commitAIGame(game)
    scheduleAITurnIfNeeded()
}

/**
 * 로컬 판을 화면 값으로 옮긴다. 창이 안 보이면 시계를 곧바로 멈춘 채로 옮긴다. 이전 판은 **대입 전에** 잡는다 — 사람 수와 로봇 수가 둘 다
 * 이 문을 지나므로 여기 한 자리만 붙여도 두 길의 놓은 말 꼬리표가 거둬진다([ChessStore.notePlyAdvanced]).
 */
private fun ChessStore.commitAIGame(game: ChessAIGame) {
    if (!(isWindowVisible && !isWindowOccluded) && game.turnStartedAt != null) game.pause(clock())
    if (aiGame != game) aiGame = game
    val next = game.matchState()
    val previous = match
    if (match != next) match = next
    notePlyAdvanced(next.id, previous?.id, previous?.plyCount, next.plyCount, next.lastMove)
    val nextPhase = if (game.isFinished) ChessPhase.result else ChessPhase.playing
    if (phase != nextPhase) phase = nextPhase
    scheduleAIClock()
}

/** AI 차례면 한 번 생각을 맡긴다. 끝나면 세대·판 id·수 번호·차례가 그대로일 때만 반영한다. */
private fun ChessStore.scheduleAITurnIfNeeded() {
    if (!isAIMatch) return
    val game = aiGame ?: return
    if (game.isFinished || game.turn != game.aiColor) return
    aiRuntime.moveTask?.cancel()
    val generation = aiRuntime.bump()
    val id = game.id
    val expectedPly = game.plyCount
    val color = game.aiColor
    val position = game.position.copy()
    val counts = game.ledger.repetitionCounts
    val chooser = aiRuntime.chooser
    val minimumMillis = (aiRuntime.minimumThinkSeconds * 1000).toLong()
    aiRuntime.noteChooserCall()
    aiRuntime.moveTask = scope.launch {
        val move = coroutineScope {
            val floor = async { if (minimumMillis > 0) delay(minimumMillis) }
            val chosen = chooser(position, counts)
            floor.await()
            chosen
        }
        val current = aiGame
        if (aiRuntime.generation != generation || current == null || current.id != id || current.plyCount != expectedPly ||
            current.turn != color || current.isFinished
        ) {
            log("ai move dropped (stale)")
            return@launch
        }
        aiRuntime.moveTask = null
        applyAIMove(move)
    }
}

/**
 * AI 가 낸 수를 로컬 판에 둔다. 엔진이 수를 못 내거나 규칙 밖의 수를 내면 판이 멈추지 않게 **결정적인 첫 합법 수**로 대신 둔다
 * (`ChessRules.legalMoves` 의 순서는 결정적이다 — 무작위를 쓰면 같은 판이 실행마다 달라진다).
 */
private fun ChessStore.applyAIMove(move: ChessMove?) {
    val game = aiGame?.copy() ?: return
    val now = clock()
    var advanced = false
    if (move != null) {
        if (game.play(move, now) == null) advanced = true else log("ai move rejected, using fallback")
    }
    if (!advanced && !game.isFinished) {
        val fallback = ChessRules.legalMoves(game.position).firstOrNull()
        if (fallback != null) advanced = game.play(fallback, now) == null
    }
    commitAIGame(game)
    if (advanced) scheduleAITurnIfNeeded()
}

/** 시계 작업을 (다시) 건다. 시계가 돌 때만 깃발 시각에 깨어난다. */
private fun ChessStore.scheduleAIClock() {
    aiRuntime.clockTask?.cancel()
    aiRuntime.clockTask = null
    if (!isAIMatch) return
    val game = aiGame ?: return
    if (game.isFinished || game.turnStartedAt == null) return
    val left = game.rawRemainingSeconds(game.position.sideToMove, clock())
    val delaySeconds = (if (left > 0.0) left else 0.0) + 0.05
    val generation = aiRuntime.generation
    aiRuntime.clockTask = scope.launch {
        delay((delaySeconds * 1000).toLong())
        if (aiRuntime.generation != generation) return@launch
        aiRuntime.clockTask = null
        handleAIClock(clock())
    }
}
