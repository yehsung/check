// 원본: Sources/CheckCore/ReversiStoreAI.swift @ 12624739
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.ai.ReversiAI
import com.yehsung.aingcheck.core.rules.ai.ReversiAIGame
import com.yehsung.aingcheck.core.rules.reversi.ReversiPlay
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.random.Random

// 아잉 뒤집기 AI 연습 판(로컬) — 스토어 확장. 계약은 설계서 FLIP/SPEC.md §4.4 · DEC:20.
//
// ── 서버와 섞이지 않는다 ── 루비·기록 없음 · 단일 난이도 · 생각 상한 1.5초. AI 판은 [ReversiAIGame](로컬 값)이 권위이고 `match` 는 그 값을 옮겨 적은
//    화면 값이다(`isAI`). 서버 경로는 `"ai-"` id 머리말과 `isAI` 로 막는다 — `refreshMatch` 가 맨 앞에서 거르고, `syncOnce`·`pollTick`·`windowDidShow`
//    는 AI 판을 진행 중 1:1 판으로 보지 않으며, `onMatchFinished` 는 AI 판에 안 운다(서버 `daily_reversi` 도 AI 판을 안 센다).
//    1:1 판이 서면(`applyState` 가 `match` 를 다른 id 로 바꾸면) `match` 대입이 AI 판을 **조용히 버린다** — 1:1 이 언제나 이긴다.
// ── 늦게 끝난 AI 수는 버린다 ── 계산을 시작할 때 세대·판 id·기록 수·차례를 잡고, 끝났을 때 하나라도 다르면 결과를 버린다.
// ── 사람 시계는 창(폰은 화면)이 보일 때만 돈다 ── 안 보이거나 가려지면(앱이 background) 멈추고(남은 초 보존), 다시 보이면 이어 간다.
//    30초가 지나면 사람 합법 수 가운데 무작위 자동 착수 · 연속 3회면 패(자연 종료 우선) — [ReversiAIGame] 이 판정한다.
// ── 사람이 패스하면 AI 차례가 이어진다 ── 오목과 달리 이것이 **정상 경로**다 — AI 수를 반영한 뒤 차례가 여전히 AI 면 다시 부른다.
// 시각 눈금: [ReversiAIGame] 은 1970 기준 초 Double, 스토어는 [SwiftDate] 다 — 두 문(`nowSeconds` · `SwiftDate(초)`)에서만 바꾼다.

/** AI 갈래의 관찰 대상이 아닌 장부. */
class ReversiAIRuntime {
    companion object {
        /** 기본 선택기: 엔진을 백그라운드에서 돌리고, 기다리던 쪽이 취소되면 **엔진에도 취소를 전한다**(체스 `engineChooser` 와 같은 꼴). */
        val engineChooser: ReversiAIMoveChooser = { board, color ->
            withContext(Dispatchers.Default) {
                val job = coroutineContext[Job]
                ReversiAI.bestMove(board = board, toMove = color, isCancelled = { job?.isActive == false })
            }
        }
    }

    var chooser: ReversiAIMoveChooser = engineChooser
    /** AI 가 즉답해도 화면에 "생각 중"을 이만큼은 보여 준다(초). 시험은 0. */
    var minimumThinkSeconds: Double = 0.6
    /** 0 until n 중 하나. 사람 자동 착수·엔진 대타·무작위 색이 쓴다(시험은 고정한다). */
    var randomIndex: (Int) -> Int = { n -> Random.nextInt(maxOf(1, n)) }

    /** 판이 바뀔 때마다(시작·버림·새 AI 차례) 오른다. 늦게 끝난 계산을 버리는 기준. */
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

// MARK: 읽기

/** 지금 들고 있는 판이 AI 판인가(로컬 판과 화면 값이 같은 id). */
val ReversiStore.isAIMatch: Boolean
    get() {
        val game = aiGame ?: return false
        return match?.id == game.id
    }

/** AI 가 지금 생각 중인가(AI 판 · 안 끝남 · AI 차례). 선수 카드가 "생각 중"을 그린다. */
val ReversiStore.isAIThinking: Boolean
    get() {
        val current = match ?: return false
        if (!current.isAI || current.isFinished) return false
        val turn = current.turn ?: return false
        return turn == current.myColor.opponent
    }

/**
 * 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나(서버가 진행 중이라 말함 포함) 보낸 신청이 떠 있으면 안 된다 — 신청이 수락되는
 * 순간 1:1 이 AI 판을 이기므로 두던 판이 사라진다.
 */
val ReversiStore.canStartAIMatch: Boolean
    get() = phase == ReversiPhase.lobby && match == null && outgoing == null && activeMatchID == null && !isBusy

/** 시험 주입점: AI 수 선택기. */
var ReversiStore.aiMoveChooser: ReversiAIMoveChooser
    get() = aiRuntime.chooser
    set(value) {
        aiRuntime.chooser = value
    }

// MARK: 동작

/** AI 판을 연다. [humanColor] null = 무작위. AI 가 흑이면 곧바로 AI 가 생각한다. */
fun ReversiStore.startAIMatch(humanColor: ReversiColor?) {
    if (!canStartAIMatch) {
        if (match != null || activeMatchID != null) setNotice(ReversiNoticeText.busy)
        return
    }
    val color = humanColor ?: if (aiRuntime.randomIndex(2) == 0) ReversiColor.black else ReversiColor.white
    beginAIGame(color)
}

/** 같은 색으로 새 AI 판(결과 카드 [다시 두기]). */
fun ReversiStore.restartAIMatch() {
    if (!isAIMatch) return
    val game = aiGame ?: return
    if (!game.isFinished) return
    beginAIGame(game.humanColor)
}

/** 사람 시계가 다 됐으면 대신 둔다(시계 작업이 깨어나 부른다 — 시험은 `now` 를 넣어 직접 부른다). */
fun ReversiStore.handleAIClock(now: SwiftDate) {
    if (!isAIMatch) return
    val game = aiGame?.copy() ?: return
    if (!game.isHumanClockExpired(now.timeIntervalSince1970)) {
        scheduleAIClock()
        return
    }
    game.autoPlaceHuman(now.timeIntervalSince1970, aiRuntime.randomIndex)
    commitAIGame(game)
    setNotice(ReversiNoticeText.autoPlaced)
    scheduleAITurnIfNeeded()
}

// MARK: 스토어 본문의 앞머리 분기가 부르는 문

/** 사람 착수(본문 `place` 의 거절 가드를 **다 지난 뒤**). 규칙 밖이면 그 까닭을 문구로 남긴다. */
internal fun ReversiStore.placeInAIMatch(idx: Int) {
    val game = aiGame?.copy() ?: return
    when (val verdict = game.playHuman(idx, clock().timeIntervalSince1970)) {
        is ReversiPlay.Illegal -> setNotice(ReversiNoticeText.illegal(verdict.reason))
        is ReversiPlay.Played -> {
            setNotice(null)
            commitAIGame(game)
            scheduleAITurnIfNeeded()
        }
    }
}

/** 기권(본문 `resign` 의 앞머리). */
internal fun ReversiStore.resignAIMatch() {
    val game = aiGame?.copy() ?: return
    if (game.isFinished) return
    game.resign(clock().timeIntervalSince1970)
    setNotice(null)
    commitAIGame(game)
}

/** 창이 안 보이게 됐다 — 사람 시계를 멈춘다(AI 차례여도 깃발을 세워 다음 사람 차례가 멈춘 채 시작한다). */
internal fun ReversiStore.pauseAIClock() {
    if (!isAIMatch) return
    val game = aiGame?.copy() ?: return
    if (game.isFinished || game.isClockPaused) return
    game.pause(clock().timeIntervalSince1970)
    commitAIGame(game)
}

/** 창이 다시 보인다 — 멈춘 시계를 이어 간다(보이지 않거나 가려져 있으면 그대로 둔다). */
internal fun ReversiStore.resumeAIClockIfVisible() {
    if (!isAIMatch || !isWindowVisible || isWindowOccluded) return
    val game = aiGame?.copy() ?: return
    if (!game.isClockPaused) return
    game.resume(clock().timeIntervalSince1970)
    commitAIGame(game)
}

/** AI 판을 버린다(1:1 판이 열렸다 · 로비로 · 로그아웃). `match` 는 건드리지 않는다 — 부르는 쪽이 이미 바꿨다. */
internal fun ReversiStore.discardAIGame() {
    aiRuntime.cancelTasks()
    aiRuntime.bump()
    if (aiGame != null) aiGame = null
}

// MARK: 내부

private fun ReversiStore.beginAIGame(humanColor: ReversiColor) {
    aiRuntime.cancelTasks()
    aiRuntime.bump()
    val game = ReversiAIGame(humanColor = humanColor, startedAt = clock().timeIntervalSince1970)
    // 순서가 계약이다: 판을 먼저 세우고 화면 값을 옮긴다(`match` 대입은 id 가 같으면 버리지 않는다).
    aiGame = game.copy()
    setNotice(null)
    commitAIGame(game)
    scheduleAITurnIfNeeded()
}

/** 로컬 판을 화면 값으로 옮긴다. 창이 안 보이면 사람 시계를 곧바로 멈춘 채로 옮긴다(시작 순간·AI 수 직후 포함). */
private fun ReversiStore.commitAIGame(value: ReversiAIGame) {
    val game = value.copy()
    if (!(isWindowVisible && !isWindowOccluded) && !game.isFinished && !game.isClockPaused) game.pause(clock().timeIntervalSince1970)
    if (aiGame != game) aiGame = game.copy()
    val previous = match
    val next = aiMatchState(game)
    if (match != next) match = next
    noteBoardProgress(previous, next)
    val nextPhase = if (game.isFinished) ReversiPhase.result else ReversiPhase.playing
    if (phase != nextPhase) phase = nextPhase
    scheduleAIClock()
}

/** AI 판 → 화면 값(순수). 루비·관전자 없음, 상대는 로봇. 마감은 사람 차례에 시계가 돌 때만 선다. */
fun aiMatchState(game: ReversiAIGame): ReversiMatchState {
    val ai = ReversiUser.reversiAI
    return ReversiMatchState(
        id = game.id, isAI = true, status = if (game.isFinished) ReversiMatchStatus.finished else ReversiMatchStatus.active, stake = 0,
        myColor = game.humanColor, opponent = ai,
        blackUser = if (game.aiColor == ReversiColor.black) ai else null, whiteUser = if (game.aiColor == ReversiColor.white) ai else null,
        board = game.board, moveCount = game.moveCount, turn = game.turn, turnStartedAt = game.turnStartedAt?.let(::SwiftDate),
        deadline = game.humanDeadline()?.let(::SwiftDate),
        legalMoves = if (game.turn == game.humanColor) game.legalMoves else emptyList(),
        plies = game.plies, lastStoneIdx = game.lastStoneIdx, autoStones = game.autoStones, counts = game.counts,
        score = game.score, result = game.result, endReason = game.endReason, winner = game.winner,
        myAutoStreak = game.humanAutoStreak, opponentAutoStreak = 0,
        autoAbandonStreak = ReversiAIGame.autoLossStreak, watchers = 0,
    )
}

/** AI 차례면 한 번 생각을 맡긴다. 끝나면 세대·판 id·기록 수·차례가 그대로일 때만 반영한다. */
private fun ReversiStore.scheduleAITurnIfNeeded() {
    if (!isAIMatch) return
    val game = aiGame ?: return
    if (game.isFinished || game.turn != game.aiColor) return
    aiRuntime.moveTask?.cancel()
    val generation = aiRuntime.bump()
    val id = game.id
    val expectedCount = game.moveCount
    val color = game.aiColor
    val board = game.board
    val chooser = aiRuntime.chooser
    val minimumMillis = (aiRuntime.minimumThinkSeconds * 1000).toLong()
    aiRuntime.noteChooserCall()
    aiRuntime.moveTask = scope.launch {
        val move = coroutineScope {
            val floor = async { if (minimumMillis > 0) delay(minimumMillis) }
            val chosen = chooser(board, color)
            floor.await()
            chosen
        }
        val current = aiGame
        if (aiRuntime.generation != generation || current == null || current.id != id || current.moveCount != expectedCount ||
            current.turn != color || current.isFinished
        ) {
            log("ai move dropped (stale)")
            return@launch
        }
        aiRuntime.moveTask = null
        applyAIMove(move)
    }
}

private fun ReversiStore.applyAIMove(move: Int?) {
    val game = aiGame?.copy() ?: return
    val now = clock().timeIntervalSince1970
    var placed = false
    if (move != null) placed = game.playAI(move, now)
    if (!placed) {
        // 엔진이 규칙 밖의 수를 냈다(또는 null) — 판이 멈추지 않게 무작위 합법 수로 대신 둔다(진단 줄 하나).
        log("ai move rejected, using fallback")
        val fallback = game.randomAIFallback(aiRuntime.randomIndex) ?: return
        if (!game.playAI(fallback, now)) return
    }
    commitAIGame(game)
    // 사람이 둘 곳이 없으면(자동 패스) AI 차례가 이어진다 — 정상 경로다.
    scheduleAITurnIfNeeded()
}

/** 사람 시계 작업을 (다시) 건다. 시계가 돌 때만 마감에 깨어난다. */
private fun ReversiStore.scheduleAIClock() {
    aiRuntime.clockTask?.cancel()
    aiRuntime.clockTask = null
    if (!isAIMatch) return
    val game = aiGame ?: return
    val deadline = game.humanDeadline() ?: return
    val left = deadline - clock().timeIntervalSince1970
    val delaySeconds = (if (left > 0.0) left else 0.0) + 0.05
    val generation = aiRuntime.generation
    aiRuntime.clockTask = scope.launch {
        delay((delaySeconds * 1000).toLong())
        if (aiRuntime.generation != generation) return@launch
        aiRuntime.clockTask = null
        handleAIClock(clock())
    }
}
