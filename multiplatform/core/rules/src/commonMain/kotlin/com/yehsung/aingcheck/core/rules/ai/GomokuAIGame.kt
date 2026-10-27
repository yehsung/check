// 원본: Sources/CheckCore/GomokuAIGame.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuRules
import com.yehsung.aingcheck.core.rules.renju.GomokuTapRefusal
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

// AI 와 두는 1:1 오목 한 판의 **로컬 상태** — 순수 값(시계·무작위는 밖에서 넣는다). 설계: docs/plan/gomoku-ai.md §1·§3.
//
// 규칙은 서버 1:1 과 한 벌이다: 판정은 `GomokuRules.judge` 그대로 · 흑 선공 · 흑만 금수 · 판이 차면 무승부 · 백이 둔 뒤 흑이 둘 곳이
// 없으면 규칙 패스 · 사람 차례 30초가 지나면 **빈칸 중 균등 무작위** 대리 착수(흑이면 금수 제외) · 연속 N회 대리 착수면 사람 패
// (abandoned), 단 그 수로 5목·무승부가 되면 자연 종료가 이긴다(서버 `gomoku__autoplace` 순서 그대로).
// 서버와 다른 점: 루비·전적·순위가 없다. AI 차례에는 시계가 없다. 창이 안 보이면 사람 시계를 멈춘다(pause/resume).
//
// 시각: Swift `Date` → **1970 기준 초 Double**(C§2.5). 골든 `renju/ai-game` 은 시작 시각에서 잰 상대 초(정수·반 초)로 대조한다.
// 옮기지 않은 것: `matchState(opponent:)`(GomokuMatchState — 스토어 값, W2-d) · `GomokuUser.gomokuAI`/`isGomokuAI`(스토어 값, W2-d).
// Swift 값 타입 → Kotlin 은 [copy] 로 복사한다.

/** AI 대국 한 판. */
class GomokuAIGame private constructor(
    val id: String,
    val humanColor: GomokuColor,
    /** 사람 한 수 제한(초). */
    val turnSeconds: Double,
    /** 연속 대리 착수 몇 번에 사람이 지는가. */
    val autoLossStreak: Int,
    board: GomokuBoard,
    moveCount: Int,
    humanAutoStreak: Int,
) {
    /** 판을 막 둔 결과의 거절(사람 착수). */
    data class Refusal(val kind: GomokuTapRefusal, val reason: GomokuForbiddenReason?)

    val aiColor: GomokuColor get() = humanColor.opponent

    private var boardStorage: GomokuBoard = board

    /** 판(사본 — 고쳐도 이 판에는 안 닿는다. Swift 값 의미). */
    val board: GomokuBoard get() = boardStorage.copy()

    /** 기록 수(규칙 패스 포함 — 서버 move_count 와 같은 눈금). */
    var moveCount: Int = moveCount
        private set
    var lastMove: GomokuPoint? = null
        private set
    /** 끝나면 null. */
    var turn: GomokuColor? = GomokuColor.black
        private set
    /** 사람 차례이고 시계가 돌 때만 값이 있다(1970 기준 초). */
    var deadline: Double? = null
        private set
    /** 사람 차례인데 시계가 멈춰 있을 때 남은 초. */
    var pausedRemaining: Double? = null
        private set
    var isFinished: Boolean = false
        private set
    /** **사람 기준** 결과. */
    var outcome: GomokuOutcome? = null
        private set
    var endReason: GomokuEndReason? = null
        private set
    private val autoPointsStorage = LinkedHashSet<GomokuPoint>()
    /** 시간이 지나 대신 놓인 사람 돌. */
    val autoPoints: Set<GomokuPoint> get() = LinkedHashSet(autoPointsStorage)
    var lastMoveWasAuto: Boolean = false
        private set
    /** 직전 기록이 흑 규칙 패스다(백이 두면 내린다). */
    var blackPassed: Boolean = false
        private set
    /** 사람이 **연속으로** 대리 착수당한 횟수. 직접 한 수 두면 0. */
    var humanAutoStreak: Int = humanAutoStreak
        private set

    fun copy(): GomokuAIGame {
        val other = GomokuAIGame(id, humanColor, turnSeconds, autoLossStreak, boardStorage.copy(), moveCount, humanAutoStreak)
        other.lastMove = lastMove
        other.turn = turn
        other.deadline = deadline
        other.pausedRemaining = pausedRemaining
        other.isFinished = isFinished
        other.outcome = outcome
        other.endReason = endReason
        other.autoPointsStorage.addAll(autoPointsStorage)
        other.lastMoveWasAuto = lastMoveWasAuto
        other.blackPassed = blackPassed
        return other
    }

    // MARK: 사람

    /** 사람 한 수. 거절이면 판은 그대로다. */
    fun humanPlace(point: GomokuPoint, now: Double): Refusal? {
        if (isFinished) return Refusal(GomokuTapRefusal.finished, null)
        if (turn != humanColor) return Refusal(GomokuTapRefusal.notYourTurn, null)
        when (val verdict = GomokuRules.judge(boardStorage, point, humanColor)) {
            GomokuJudgement.Occupied -> return Refusal(GomokuTapRefusal.occupied, null)
            is GomokuJudgement.Forbidden -> return Refusal(GomokuTapRefusal.forbidden, verdict.reason)
            GomokuJudgement.OutOfRange -> return Refusal(GomokuTapRefusal.occupied, null)
            GomokuJudgement.Win -> {
                humanAutoStreak = 0
                placeStone(point, humanColor, auto = false)
                finish(humanColor, GomokuEndReason.five)
            }
            GomokuJudgement.Legal -> {
                humanAutoStreak = 0
                placeStone(point, humanColor, auto = false)
                advance(humanColor, now)
            }
        }
        return null
    }

    /** 사람 시계가 다 됐는가(멈춰 있으면 절대 아니다). */
    fun isHumanClockExpired(now: Double): Boolean {
        val deadline = deadline
        if (isFinished || turn != humanColor || deadline == null) return false
        return now >= deadline
    }

    /**
     * 시간이 지난 사람 차례를 대신 둔다. `randomIndex(n)` 은 0..<n 중 하나(시험은 고정한다).
     * 사람 차례가 아니거나 끝난 판이면 아무것도 안 한다(false).
     */
    fun autoPlaceHuman(now: Double, randomIndex: (Int) -> Int): Boolean {
        if (isFinished || turn != humanColor) return false
        humanAutoStreak += 1
        val candidates = legalPoints(boardStorage, humanColor)
        if (candidates.isEmpty()) {
            // 둘 곳이 하나도 없다(흑 금수뿐) — 서버처럼 대리 패스, 연속 횟수는 올린다.
            recordPass(humanColor)
            startTurn(aiColor, now)
        } else {
            val index = minOf(maxOf(randomIndex(candidates.size), 0), candidates.size - 1)
            val point = candidates[index]
            val verdict = GomokuRules.judge(boardStorage, point, humanColor)
            placeStone(point, humanColor, auto = true)
            if (verdict == GomokuJudgement.Win) finish(humanColor, GomokuEndReason.five) else advance(humanColor, now)
        }
        // 자연 종료(5목·무승부)가 아니었을 때만 — 이긴 수를 빼앗지 않는다(서버 순서).
        if (!isFinished && humanAutoStreak >= autoLossStreak) finish(aiColor, GomokuEndReason.abandoned)
        return true
    }

    /** 기권 — 사람 패. */
    fun resign() {
        if (isFinished) return
        finish(aiColor, GomokuEndReason.resign)
    }

    // MARK: AI

    /**
     * AI 한 수. null 은 "둘 곳 없음"이다. 규칙에 맞지 않는 수(이미 돌 · 흑 금수 · 차례 아님)면 **판을 안 바꾸고** false —
     * 스토어가 무작위 합법 수로 대신 둔다(엔진 결함 하나로 판이 멈추지 않게).
     */
    fun applyAIMove(point: GomokuPoint?, now: Double): Boolean {
        if (isFinished || turn != aiColor) return false
        if (point == null) {
            // 흑이 둘 곳이 정말 없을 때만 패스가 성립한다.
            if (legalPoints(boardStorage, aiColor, stopAtFirst = true).isNotEmpty()) return false
            recordPass(aiColor)
            startTurn(humanColor, now)
            return true
        }
        return when (GomokuRules.judge(boardStorage, point, aiColor)) {
            GomokuJudgement.Win -> {
                placeStone(point, aiColor, auto = false)
                finish(aiColor, GomokuEndReason.five)
                true
            }
            GomokuJudgement.Legal -> {
                placeStone(point, aiColor, auto = false)
                advance(aiColor, now)
                true
            }
            GomokuJudgement.Occupied, is GomokuJudgement.Forbidden, GomokuJudgement.OutOfRange -> false
        }
    }

    /** AI 가 둘 수 있는 무작위 합법 수(엔진이 규칙 밖의 수를 냈을 때의 대타). 없으면 null. */
    fun randomAIFallback(randomIndex: (Int) -> Int): GomokuPoint? {
        val candidates = legalPoints(boardStorage, aiColor)
        if (candidates.isEmpty()) return null
        return candidates[minOf(maxOf(randomIndex(candidates.size), 0), candidates.size - 1)]
    }

    // MARK: 시계 일시정지

    /** 사람 시계를 멈춘다(남은 초 보존). 돌고 있지 않으면 아무것도 안 한다. Swift `max(0, deadline − now)`. */
    fun pause(now: Double) {
        val deadline = deadline ?: return
        val left = deadline - now
        pausedRemaining = if (left >= 0.0) left else 0.0
        this.deadline = null
    }

    /** 멈춘 시계를 이어 간다. */
    fun resume(now: Double) {
        val remaining = pausedRemaining ?: return
        deadline = now + remaining
        pausedRemaining = null
    }

    // MARK: 내부

    private fun placeStone(point: GomokuPoint, color: GomokuColor, auto: Boolean) {
        boardStorage[point] = color
        moveCount += 1
        lastMove = point
        lastMoveWasAuto = auto
        blackPassed = false
        if (auto) autoPointsStorage.add(point) else autoPointsStorage.remove(point)
    }

    private fun recordPass(color: GomokuColor) {
        moveCount += 1
        lastMoveWasAuto = false
        blackPassed = color == GomokuColor.black
    }

    /** 돌을 놓은 뒤(끝나지 않았을 때) 다음 차례를 세운다: 판이 차면 무승부, 다음이 흑인데 둘 곳이 없으면 규칙 패스. */
    private fun advance(color: GomokuColor, now: Double) {
        if (boardStorage.stoneCount >= GomokuBoard.cellCount) {
            finish(null, GomokuEndReason.boardFull)
            return
        }
        val next = color.opponent
        if (next == GomokuColor.black && legalPoints(boardStorage, GomokuColor.black, stopAtFirst = true).isEmpty()) {
            recordPass(GomokuColor.black)
            startTurn(GomokuColor.white, now)
            return
        }
        startTurn(next, now)
    }

    private fun startTurn(color: GomokuColor, now: Double) {
        turn = color
        pausedRemaining = null
        deadline = if (color == humanColor) now + turnSeconds else null
    }

    private fun finish(winner: GomokuColor?, reason: GomokuEndReason) {
        isFinished = true
        turn = null
        deadline = null
        pausedRemaining = null
        endReason = reason
        outcome = when (winner) {
            humanColor -> GomokuOutcome.won
            null -> GomokuOutcome.draw
            else -> GomokuOutcome.lost
        }
    }

    override fun equals(other: Any?): Boolean =
        other is GomokuAIGame && other.id == id && other.humanColor == humanColor && other.turnSeconds == turnSeconds &&
            other.autoLossStreak == autoLossStreak && other.boardStorage == boardStorage && other.moveCount == moveCount &&
            other.lastMove == lastMove && other.turn == turn && other.deadline == deadline &&
            other.pausedRemaining == pausedRemaining && other.isFinished == isFinished && other.outcome == outcome &&
            other.endReason == endReason && other.autoPointsStorage == autoPointsStorage &&
            other.lastMoveWasAuto == lastMoveWasAuto && other.blackPassed == blackPassed && other.humanAutoStreak == humanAutoStreak

    override fun hashCode(): Int = id.hashCode() * 31 + boardStorage.hashCode()

    companion object {
        /** 판 id 머리말. 서버 판 id 는 uuid 라 이 머리말로 시작할 수 없다 — **이 한 줄이 서버 경로 차단의 근거다**. */
        const val idPrefix: String = "ai-"

        /** 이 id 가 AI 판인가. 스토어의 서버 경로(조회·나가기·채팅)가 이 판정으로 요청을 막는다. */
        fun isAIMatchID(id: String?): Boolean = id?.startsWith(idPrefix) ?: false

        @OptIn(ExperimentalUuidApi::class)
        private fun newID(): String = idPrefix + Uuid.random().toString().lowercase()

        /** 새 판. 흑이 먼저 두므로 사람이 흑이면 곧바로 사람 시계가 돈다. Swift `init(id:humanColor:turnSeconds:autoLossStreak:now:)`. */
        fun start(
            humanColor: GomokuColor,
            now: Double,
            id: String = newID(),
            turnSeconds: Double = 30.0,
            autoLossStreak: Int = 3,
        ): GomokuAIGame {
            val game = GomokuAIGame(id, humanColor, turnSeconds, maxOf(1, autoLossStreak), GomokuBoard(), 0, 0)
            game.startTurn(GomokuColor.black, now)
            return game
        }

        /**
         * 검증·렌더용: 주어진 판에서 `turn` 차례로 시작한다(기록 수 = 판 위 돌 수). Swift `init(id:humanColor:board:turn:humanAutoStreak:…:now:)`.
         * 판은 복사해서 든다.
         */
        fun fromBoard(
            humanColor: GomokuColor,
            board: GomokuBoard,
            turn: GomokuColor,
            now: Double,
            id: String = newID(),
            humanAutoStreak: Int = 0,
            turnSeconds: Double = 30.0,
            autoLossStreak: Int = 3,
        ): GomokuAIGame {
            val game = GomokuAIGame(id, humanColor, turnSeconds, maxOf(1, autoLossStreak), board.copy(), board.stoneCount, humanAutoStreak)
            game.startTurn(turn, now)
            return game
        }

        /** 빈칸 중 `color` 가 둘 수 있는 칸(행 → 열 순서). 흑은 금수(예산 초과 포함)를 뺀다. */
        fun legalPoints(board: GomokuBoard, color: GomokuColor, stopAtFirst: Boolean = false): List<GomokuPoint> {
            val result = ArrayList<GomokuPoint>()
            for (y in 0 until GomokuBoard.size) {
                for (x in 0 until GomokuBoard.size) {
                    val point = GomokuPoint.at(x, y) ?: continue
                    if (board[point] != null) continue
                    if (color == GomokuColor.black) {
                        when (GomokuRules.judge(board, point, GomokuColor.black)) {
                            GomokuJudgement.Legal, GomokuJudgement.Win -> Unit
                            else -> continue
                        }
                    }
                    result.add(point)
                    if (stopAtFirst) return result
                }
            }
            return result
        }
    }
}
