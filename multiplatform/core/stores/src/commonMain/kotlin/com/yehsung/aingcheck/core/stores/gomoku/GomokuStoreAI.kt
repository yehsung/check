// 원본: Sources/CheckCore/GomokuStoreAI.swift · Sources/CheckCore/GomokuAIGame.swift:212-222·294-304(matchState · GomokuUser.gomokuAI — W1-b 가 스토어 값이라 남긴 몫) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.ai.GomokuAI
import com.yehsung.aingcheck.core.rules.ai.GomokuAIGame
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuTapRefusal
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.random.Random

// 오목 스토어의 **AI 대국** 갈래 — 설계: docs/plan/gomoku-ai.md §4.
//
// ── 서버와 섞이지 않는다 ──
// AI 판은 `GomokuAIGame`(로컬 판)이 권위이고 `match` 는 그 값을 옮겨 적은 화면 값이다. 서버 경로는 id 머리말("ai-")로 막는다:
// `refreshMatch(id)`·`leaveMatch`·채팅 두 문이 맨 앞에서 거르고, 동기화·폴링은 AI 판을 진행 중 판으로 보지 않는다.
// 1:1 판이 서버에서 열리면(`applyState` 가 `match` 를 다른 id 로 바꾸면) `match` 대입이 AI 판을 **조용히 버린다** — 1:1 이 언제나 이긴다.
//
// ── 늦게 끝난 AI 수는 버린다 ──
// 계산을 시작할 때 세대(`aiRuntime.generation`)·판 id·기록 수·차례를 잡고, 끝났을 때 하나라도 다르면 결과를 버린다.
//
// ── 사람 시계는 창이 보일 때만 돈다 ── 기다리는 상대가 없기 때문이다.
//
// Kotlin 몫: W1-b `GomokuAIGame` 은 가변 참조다(Swift 는 값). 스토어는 들고 있는 판을 **고치지 않고** `copy()` 에 고친 뒤 통째로 바꿔 넣는다
// (Swift `var game = aiGame; game.…; commitAIGame(game)` 과 같은 뜻). 시각은 1970 기준 초 Double(W1-b 규약)로 넘긴다.
// "최소 생각 시간"은 벽시계를 읽지 않고 같은 범위의 `delay` 와 선택기를 함께 기다려 낸다(Swift `Date()` 차이 셈과 같은 결과 — 구조 시험 R2).

/** AI 수 선택기. 판과 둘 색을 받아 한 수(없으면 null)를 돌려준다. 시험이 결정적 가짜로 갈아 끼운다. */
typealias GomokuAIMoveChooser = suspend (GomokuBoard, GomokuColor) -> GomokuPoint?

/** AI 갈래의 관찰 대상이 아닌 장부. */
class GomokuAIRuntime {
    companion object {
        /** 기본 선택기: 엔진을 백그라운드(Default)에서 돌리고, 기다리던 쪽이 취소되면 엔진에도 취소를 전한다. */
        val engineChooser: GomokuAIMoveChooser = { board, color ->
            withContext(Dispatchers.Default) {
                val job = coroutineContext[Job]
                GomokuAI.bestMove(board = board, toMove = color, isCancelled = { job?.isActive == false })
            }
        }
    }

    var chooser: GomokuAIMoveChooser = engineChooser
    /** AI 가 즉답해도 화면에 "생각 중"을 이만큼은 보여 준다(초). 시험은 0. */
    var minimumThinkSeconds: Double = 0.6
    /** 0..<n 중 하나. 대리 착수·엔진 대타가 쓴다(시험은 고정한다). */
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

/** 화면 값으로 옮긴다(Swift `GomokuAIGame.matchState(opponent:)`). 판돈·루비는 없다(끝났으면 rubyDelta 0). */
fun GomokuAIGame.matchState(opponent: GomokuUser = GomokuUser.gomokuAI): GomokuMatchState = GomokuMatchState(
    id = id, stake = 0, myColor = humanColor, opponent = opponent, board = board, lastMove = lastMove,
    moveCount = moveCount, turn = turn, deadline = deadline?.let { SwiftDate(it) }, isFinished = isFinished, outcome = outcome,
    endReason = endReason, rubyDelta = if (isFinished) 0 else null, blackPassed = blackPassed,
    autoPoints = autoPoints, lastMoveWasAuto = lastMoveWasAuto,
)

// MARK: 읽기

/** 지금 들고 있는 판이 AI 판인가. */
val GomokuStore.isAIMatch: Boolean
    get() {
        val game = aiGame ?: return false
        val current = match ?: return false
        return current.id == game.id
    }

/** AI 가 둘 차례인가(화면의 "생각 중"). */
val GomokuStore.isAIThinking: Boolean
    get() {
        if (!isAIMatch) return false
        val game = aiGame ?: return false
        return !game.isFinished && game.turn == game.aiColor
    }

/**
 * 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나(서버가 진행 중이라 말함 포함) 보낸 신청이 떠 있으면 안 된다 —
 * 신청이 수락되는 순간 1:1 이 AI 판을 이기므로 두던 판이 사라진다. **판돈 깃발(§8-17 #1)과는 무관하다.**
 */
val GomokuStore.canStartAIMatch: Boolean
    get() = phase == GomokuPhase.lobby && match == null && outgoing == null && activeMatchID == null && !isBusy

/** 시험 주입점: AI 수 선택기. */
var GomokuStore.aiMoveChooser: GomokuAIMoveChooser
    get() = aiRuntime.chooser
    set(value) {
        aiRuntime.chooser = value
    }

// MARK: 동작

/** 로비에서 AI 대국을 시작한다. 사람이 고른 색으로 두고, AI 가 흑이면 곧바로 AI 가 생각한다. */
fun GomokuStore.startAIMatch(humanColor: GomokuColor) {
    if (!canStartAIMatch) {
        if (match != null || activeMatchID != null) setAINotice(GomokuNoticeText.busy)
        return
    }
    beginAIGame(humanColor)
}

/** 결과 화면 [다시 두기] — 같은 색으로 새 판. */
fun GomokuStore.restartAIMatch() {
    val game = aiGame ?: return
    if (!isAIMatch || !game.isFinished) return
    beginAIGame(game.humanColor)
}

/** 사람 시계가 다 됐으면 대신 둔다(시계 작업이 깨어나 부른다 — 시험은 `now` 를 넣어 직접 부른다). */
fun GomokuStore.handleAIClock(now: SwiftDate) {
    if (!isAIMatch) return
    val game = aiGame?.copy() ?: return
    if (!game.isHumanClockExpired(now.timeIntervalSince1970)) {
        scheduleAIClock()
        return
    }
    game.autoPlaceHuman(now.timeIntervalSince1970, aiRuntime.randomIndex)
    commitAIGame(game)
    setAINotice(GomokuNoticeText.autoPlaced)
    scheduleAITurnIfNeeded()
}

// MARK: 스토어 본문의 앞머리 분기가 부르는 문

/** 사람 착수(본문 `place` 의 거절 가드를 **다 지난 뒤**). 거절이면 그 사유를 돌려준다. */
internal fun GomokuStore.placeInAIMatch(point: GomokuPoint): GomokuAIGame.Refusal? {
    val game = aiGame?.copy() ?: return GomokuAIGame.Refusal(GomokuTapRefusal.noMatch, null)
    val refusal = game.humanPlace(point, clock().timeIntervalSince1970)
    if (refusal != null) return refusal
    setAINotice(null)
    commitAIGame(game)
    scheduleAITurnIfNeeded()
    return null
}

/** 기권(본문 `resign` 의 앞머리). */
internal fun GomokuStore.resignAIMatch() {
    val game = aiGame?.copy() ?: return
    if (game.isFinished) return
    game.resign()
    setAINotice(null)
    commitAIGame(game)
}

/**
 * 결과 화면 [로비로](본문 `backToLobby` 의 앞머리). 끝난 AI 판만 내린다 — 나머지는 본문이 1:1 과 같은 길로 이어서 한다.
 * **진행 중인 판이면 아무것도 안 한다**(빠져나가는 길은 기권뿐, 1:1 과 같다).
 */
internal fun GomokuStore.backToLobbyFromAIMatch() {
    val game = aiGame ?: return
    if (!game.isFinished) return
    match = null // 대입이 AI 판을 버린다
}

/** 창이 안 보이게 됐다 — 사람 시계를 멈춘다. */
internal fun GomokuStore.pauseAIClock() {
    if (!isAIMatch) return
    val game = aiGame?.copy() ?: return
    if (game.deadline == null) return
    game.pause(clock().timeIntervalSince1970)
    commitAIGame(game)
}

/** 창이 다시 보인다 — 멈춘 시계를 이어 간다(보이지 않으면 그대로 둔다). */
internal fun GomokuStore.resumeAIClockIfVisible() {
    if (!isAIMatch || !isWindowVisible || isWindowOccluded) return
    val game = aiGame?.copy() ?: return
    if (game.pausedRemaining == null) return
    game.resume(clock().timeIntervalSince1970)
    commitAIGame(game)
}

/** AI 판을 버린다(1:1 판이 열렸다 · 로비로 · 로그아웃). `match` 는 건드리지 않는다 — 부르는 쪽이 이미 바꿨다. */
internal fun GomokuStore.discardAIGame() {
    aiRuntime.cancelTasks()
    aiRuntime.bump()
    if (aiGame != null) aiGame = null
}

// MARK: 내부

private fun GomokuStore.beginAIGame(humanColor: GomokuColor) {
    aiRuntime.cancelTasks()
    aiRuntime.bump()
    val game = GomokuAIGame.start(
        humanColor = humanColor, now = clock().timeIntervalSince1970,
        turnSeconds = turnSeconds.toDouble(), autoLossStreak = autoAbandonStreak,
    )
    // 순서가 계약이다: 판을 먼저 세우고 화면 값을 옮긴다(`match` 대입은 id 가 같으면 버리지 않는다).
    aiGame = game.copy()
    setAINotice(null)
    commitAIGame(game)
    scheduleAITurnIfNeeded()
}

/** 로컬 판을 화면 값으로 옮긴다. 창이 안 보이면 사람 시계를 곧바로 멈춘 채로 옮긴다(시작 순간·AI 수 직후 포함). */
private fun GomokuStore.commitAIGame(game: GomokuAIGame) {
    if (!(isWindowVisible && !isWindowOccluded) && game.deadline != null) game.pause(clock().timeIntervalSince1970)
    if (aiGame != game) aiGame = game
    val next = game.matchState()
    if (match != next) match = next
    val nextPhase = if (game.isFinished) GomokuPhase.result else GomokuPhase.playing
    if (phase != nextPhase) phase = nextPhase
    if (myAutoStreak != game.humanAutoStreak) myAutoStreak = game.humanAutoStreak
    scheduleAIClock()
}

private fun GomokuStore.setAINotice(text: String?) {
    if (notice != text) notice = text
}

/** AI 차례면 한 번 생각을 맡긴다. 끝나면 세대·판 id·기록 수·차례가 그대로일 때만 반영한다. */
private fun GomokuStore.scheduleAITurnIfNeeded() {
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
        // 선택기와 최소 표시 시간을 함께 기다린다 = Swift 의 "즉답이면 남은 시간만큼 더 잔다".
        val move = coroutineScope {
            val floor = async { if (minimumMillis > 0) delay(minimumMillis) }
            val chosen = chooser(board, color)
            floor.await()
            chosen
        }
        val current = aiGame
        if (aiRuntime.generation != generation || current == null || current.id != id ||
            current.moveCount != expectedCount || current.turn != color || current.isFinished
        ) {
            host.notice(GomokuStore.LOG_TAG, "ai move dropped (stale)")
            return@launch
        }
        aiRuntime.moveTask = null
        applyAIMove(move)
    }
}

private fun GomokuStore.applyAIMove(move: GomokuPoint?) {
    val game = aiGame?.copy() ?: return
    val now = clock().timeIntervalSince1970
    if (!game.applyAIMove(move, now)) {
        // 엔진이 규칙 밖의 수를 냈다 — 판이 멈추지 않게 무작위 합법 수로 대신 둔다(진단 줄 하나).
        host.notice(GomokuStore.LOG_TAG, "ai move rejected, using fallback")
        val fallback = game.randomAIFallback(aiRuntime.randomIndex)
        if (!game.applyAIMove(fallback, now)) return
    }
    commitAIGame(game)
    // AI 수 뒤에 흑 규칙 패스로 다시 AI 차례가 올 수는 없지만, 판이 한 수라도 AI 차례에 멈추지 않도록 한 번 더 본다.
    scheduleAITurnIfNeeded()
}

/** 사람 시계 작업을 (다시) 건다. 시계가 돌 때만 마감에 깨어난다. */
private fun GomokuStore.scheduleAIClock() {
    aiRuntime.clockTask?.cancel()
    aiRuntime.clockTask = null
    if (!isAIMatch) return
    val game = aiGame ?: return
    val deadline = game.deadline ?: return
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
