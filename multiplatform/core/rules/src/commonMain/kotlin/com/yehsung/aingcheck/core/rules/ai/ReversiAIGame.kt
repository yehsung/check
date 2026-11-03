// 원본: Sources/CheckCore/ReversiAIGame.swift @ 12624739
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.renju.swiftMax
import com.yehsung.aingcheck.core.rules.reversi.ReversiPlay
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiResult
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

// AI 와 두는 아잉 뒤집기 한 판의 **로컬 상태** — 시계·무작위는 밖에서 넣는다. 설계: flip/SPEC.md §4.2. 오목 `GomokuAIGame` 과 같은 모양이다.
//
// ── 규칙은 서버 1:1 과 한 벌이다 ──
// 판정은 `ReversiRules.play` 그대로(두 벌 만들지 않는다) · 흑 선 · 상대가 둘 곳이 없으면 자동 패스(기록에 pass 한 줄) ·
// 둘 다 없으면 자연 종료(WOF 점수). 사람 차례 30초가 지나면 **사람 합법 수 가운데 균등 무작위** 자동 착수(서버 `reversi__autoplace`),
// 연속 3회 자동 착수면 사람 패(abandoned) — 단 그 세 번째 수로 판이 자연히 끝나면 자연 결과가 우선한다(V-14, 서버 `reversi__play` 순서).
// 사람 직접 착수는 연속 횟수를 0 으로 되돌리고, **자동 패스는 시계·연속 횟수 어디에도 넣지 않는다**(사용자 결정).
//
// ── 서버와 다른 점 ──
// 루비·전적·순위가 없다(사용자 결정). AI 차례에는 시계가 없다. 창(화면)이 안 보이면 사람 시계를 멈춘다(`pause`/`resume` —
// 기다리는 상대가 없다). 이 타입은 화면을 모른다 — 멈출지는 스토어가 정한다.
// 사람이 패스하면 AI 차례가 연달아 온다. 오목과 달리 이것이 **정상 경로**다 — 스토어는 AI 수를 반영한 뒤 차례가 여전히 AI 면 다시 부른다.
//
// Kotlin 이식 메모: 시각은 Swift `Date` → **1970 기준 초 Double**(오목 AI 판과 같은 눈금). Swift 값 타입(Equatable) → Kotlin 은
// 바꿀 수 있는 클래스 + [copy] + 모든 칸을 견주는 [equals]. 옮기지 않은 것: `matchState(…)` 류(ReversiMatchState — 스토어 값, 다음 단계).

/** Swift `ReversiAIGame` — AI 대국 한 판. */
class ReversiAIGame private constructor(
    val id: String,
    val humanColor: ReversiColor,
    board: ReversiBoard,
    humanAutoStreak: Int,
) {
    val aiColor: ReversiColor get() = humanColor.opponent

    var board: ReversiBoard = board
        private set

    /** 지금 둘 차례. 끝나면 null. 진행 중이면 이 색은 늘 합법 수가 하나 이상 있다(V-09 불변식). */
    var turn: ReversiColor? = null
        private set

    private val pliesStorage = ArrayList<ReversiPly>()

    /** 수 기록(돌·패스, seq 1 부터). 사본이다(고쳐도 판에는 안 닿는다 — Swift 값 의미). */
    val plies: List<ReversiPly> get() = pliesStorage.toList()

    /** 지금 차례의 시계 기준 시각(1970 기준 초). 사람 차례의 마감은 `turnStartedAt + 30초`다 — 멈췄다 이으면 멈춘 만큼 뒤로 민다. 끝나면 null. */
    var turnStartedAt: Double? = null
        private set

    /** 사람이 **연속으로** 자동 착수당한 횟수. 직접 한 수 두면 0, 자동 패스는 그대로. */
    var humanAutoStreak: Int = humanAutoStreak
        private set
    var isFinished: Boolean = false
        private set

    /** 결과(색 기준). 끝나야 값이 있다. */
    var result: ReversiResult? = null
        private set
    var endReason: ReversiEndReason? = null
        private set

    /** WOF 점수 — 자연 종료일 때만. 기권·abandoned 는 점수 없이 승패만(V-15). */
    var score: ReversiScore? = null
        private set

    /** 끝난 시각. */
    var finishedAt: Double? = null
        private set

    /** 사람 시계가 멈춰 있다(화면이 안 보임). 멈춘 동안 새로 오는 사람 차례도 멈춘 채 30초를 들고 시작한다. */
    var isClockPaused: Boolean = false
        private set

    /** 멈춘 동안 사람 차례의 남은 초. */
    private var pausedRemaining: Double? = null

    /** 새 판. 흑이 먼저 두므로 사람이 흑이면 곧바로 사람 시계가 돈다(멈출지는 스토어가 곧이어 정한다). */
    constructor(humanColor: ReversiColor, startedAt: Double, id: String = newID()) : this(id, humanColor, ReversiBoard.start, 0) {
        startTurn(ReversiColor.black, startedAt)
    }

    /**
     * 검증·렌더용: 주어진 판에서 `turn` 차례로 시작한다(기록은 빈 채로). `turn` 이 둘 곳이 없으면 V-09 대로 바로잡는다 —
     * 상대에게 수가 있으면 `turn` 의 패스 한 줄을 남기고 상대 차례, 둘 다 없으면 자연 종료.
     */
    constructor(
        humanColor: ReversiColor,
        board: ReversiBoard,
        turn: ReversiColor,
        startedAt: Double,
        humanAutoStreak: Int = 0,
        id: String = newID(),
    ) : this(id, humanColor, board, maxOf(0, humanAutoStreak)) {
        if (ReversiRules.hasLegalMove(board, turn)) startTurn(turn, startedAt) else foldStuckTurn(turn, startedAt)
    }

    /** Swift 값 복사와 같은 뜻 — 고쳐도 서로에 안 닿는 사본. */
    fun copy(): ReversiAIGame {
        val other = ReversiAIGame(id, humanColor, board, humanAutoStreak)
        other.turn = turn
        other.pliesStorage.addAll(pliesStorage)
        other.turnStartedAt = turnStartedAt
        other.isFinished = isFinished
        other.result = result
        other.endReason = endReason
        other.score = score
        other.finishedAt = finishedAt
        other.isClockPaused = isClockPaused
        other.pausedRemaining = pausedRemaining
        return other
    }

    // MARK: 화면 값

    /** 기록 수(패스 포함) — 서버 move_count 와 같은 눈금. */
    val moveCount: Int get() = pliesStorage.size
    val counts: ReversiCounts get() = board.counts

    /** 이긴 색. 진행 중·무승부면 null. */
    val winner: ReversiColor? get() = result?.winner

    /** 마지막으로 놓인 돌의 칸(패스는 건너뛴다). */
    val lastStoneIdx: Int? get() = pliesStorage.lastOrNull { it.kind == ReversiPly.Kind.stone }?.idx

    /** 시간 초과로 대신 놓인 돌의 칸들. */
    val autoStones: Set<Int> get() = pliesStorage.mapNotNullTo(LinkedHashSet()) { if (it.auto) it.idx else null }

    /** 지금 차례의 합법 수(오름차순). 끝났으면 []. */
    val legalMoves: List<Int> get() = turn?.let { ReversiRules.legalMoves(board, it) } ?: emptyList()

    /** 사람 차례의 마감. 사람 차례가 아니거나 · 끝났거나 · 시계가 멈춰 있으면 null. */
    fun humanDeadline(): Double? {
        val started = turnStartedAt
        if (isFinished || turn != humanColor || isClockPaused || started == null) return null
        return started + turnSeconds
    }

    /** 사람 차례의 남은 초(멈춰 있으면 멈춘 값). 사람 차례가 아니거나 끝났으면 null. */
    fun humanRemaining(now: Double): Double? {
        if (isFinished || turn != humanColor) return null
        if (isClockPaused) return pausedRemaining ?: turnSeconds
        val deadline = humanDeadline() ?: return null
        return swiftMax(0.0, deadline - now)
    }

    /** 사람 시계가 다 됐는가(멈춰 있으면 절대 아니다). 스토어가 이것을 보고 [autoPlaceHuman] 을 부른다. */
    fun isHumanClockExpired(now: Double): Boolean {
        val deadline = humanDeadline() ?: return false
        return now >= deadline
    }

    // MARK: 사람

    /** 사람 한 수. 불법이면 까닭만 돌려주고 판은 그대로다. 끝났거나 사람 차례가 아니면 `outOfRange`(둘 수 없는 칸). */
    fun playHuman(idx: Int, now: Double): ReversiPlay {
        if (isFinished || turn != humanColor) return ReversiPlay.Illegal(ReversiIllegalReason.outOfRange)
        val verdict = ReversiRules.play(board, humanColor, idx)
        if (verdict is ReversiPlay.Played) {
            humanAutoStreak = 0
            record(verdict, humanColor, idx, auto = false, now = now)
        }
        return verdict
    }

    /**
     * 시간이 지난 사람 차례를 대신 둔다(사람 합법 수 가운데 `randomIndex(n)` 번째, 0..<n — 시험은 고정한다).
     * 연속 횟수 +1, 3 이 되면 사람 패(abandoned) — 단 그 수로 판이 자연히 끝나면 자연 결과가 우선한다.
     * 놓인 칸을 돌려준다. 사람 차례가 아니거나 끝난 판이면 아무것도 안 하고 null. 마감이 지났는지는 부르는 쪽이 본다.
     */
    fun autoPlaceHuman(now: Double, randomIndex: (Int) -> Int): Int? {
        if (isFinished || turn != humanColor) return null
        val candidates = ReversiRules.legalMoves(board, humanColor)
        if (candidates.isEmpty()) {
            // 불변식(차례 주인은 늘 합법 수 ≥ 1)이 깨졌다 — 판을 죽이지 않고 V-09 로 접는다(SPEC §2.2).
            foldStuckTurn(humanColor, now)
            return null
        }
        val idx = candidates[minOf(maxOf(randomIndex(candidates.size), 0), candidates.size - 1)]
        val verdict = ReversiRules.play(board, humanColor, idx) as? ReversiPlay.Played ?: return null
        humanAutoStreak += 1
        record(verdict, humanColor, idx, auto = true, now = now)
        // 자연 종료가 아니었을 때만 — 판을 끝낸 수를 빼앗지 않는다(서버 순서).
        if (!isFinished && humanAutoStreak >= autoLossStreak) finish(aiColor, ReversiEndReason.abandoned, now)
        return idx
    }

    /** 기권 — 사람 패(점수 없음). */
    fun resign(now: Double) {
        if (isFinished) return
        finish(aiColor, ReversiEndReason.resign, now)
    }

    // MARK: AI

    /**
     * AI 한 수. 규칙 밖의 수(범위 밖·이미 돌·못 뒤집음·AI 차례 아님)면 **판을 안 바꾸고** false —
     * 부르는 쪽이 [randomAIFallback] 으로 대신 둔다(엔진 결함 하나로 판이 멈추지 않게).
     */
    fun playAI(idx: Int, now: Double): Boolean {
        if (isFinished || turn != aiColor) return false
        val verdict = ReversiRules.play(board, aiColor, idx) as? ReversiPlay.Played ?: return false
        record(verdict, aiColor, idx, auto = false, now = now)
        return true
    }

    /** AI 차례의 무작위 합법 수(엔진이 규칙 밖의 수를 냈을 때의 대타). AI 차례가 아니면 null. */
    fun randomAIFallback(randomIndex: (Int) -> Int): Int? {
        if (isFinished || turn != aiColor) return null
        val candidates = ReversiRules.legalMoves(board, aiColor)
        if (candidates.isEmpty()) return null
        return candidates[minOf(maxOf(randomIndex(candidates.size), 0), candidates.size - 1)]
    }

    // MARK: 시계 일시정지

    /** 사람 시계를 멈춘다(남은 초 보존). 이미 멈췄거나 끝났으면 아무것도 안 한다. AI 차례에 멈춰도 깃발은 선다 — 그 뒤 사람 차례가 오면 멈춘 채(30초) 시작한다. */
    fun pause(now: Double) {
        if (isFinished || isClockPaused) return
        isClockPaused = true
        val started = turnStartedAt
        pausedRemaining = if (turn == humanColor && started != null) swiftMax(0.0, (started + turnSeconds) - now) else null
    }

    /** 멈춘 시계를 이어 간다: 사람 차례면 마감 = 지금 + 남은 초(`turnStartedAt` 을 그만큼 뒤로 민다). */
    fun resume(now: Double) {
        if (!isClockPaused) return
        isClockPaused = false
        if (!isFinished && turn == humanColor) {
            val remaining = pausedRemaining ?: turnSeconds
            turnStartedAt = now + (remaining - turnSeconds)
        }
        pausedRemaining = null
    }

    // MARK: 내부

    /**
     * 합법 수 하나를 기록하고 다음 차례를 세운다. 상대 자동 패스면 그 사람의 pass 줄(auto=false)을 남기고 둔 사람이 이어 둔다 —
     * 패스는 시계·연속 횟수를 건드리지 않는다(이어 두는 사람의 새 차례가 지금부터 시작할 뿐이다).
     */
    private fun record(played: ReversiPlay.Played, color: ReversiColor, idx: Int, auto: Boolean, now: Double) {
        val outcome = played.outcome
        board = outcome.board
        pliesStorage.add(ReversiPly(pliesStorage.size + 1, color, ReversiPly.Kind.stone, idx, outcome.flipped, auto))
        if (outcome.passed) {
            pliesStorage.add(ReversiPly(pliesStorage.size + 1, color.opponent, ReversiPly.Kind.pass, null, emptyList(), false))
        }
        val next = outcome.next
        if (next != null) startTurn(next, now) else finishNaturally(now)
    }

    /** 차례 주인이 둘 곳이 없을 때(불변식 위반·검증용 시작 판)의 V-09 복구: 상대에게 수가 있으면 패스 한 줄 + 상대 차례, 둘 다 없으면 자연 종료. */
    private fun foldStuckTurn(color: ReversiColor, now: Double) {
        if (ReversiRules.hasLegalMove(board, color.opponent)) {
            pliesStorage.add(ReversiPly(pliesStorage.size + 1, color, ReversiPly.Kind.pass, null, emptyList(), false))
            startTurn(color.opponent, now)
        } else {
            finishNaturally(now)
        }
    }

    private fun startTurn(color: ReversiColor, now: Double) {
        turn = color
        turnStartedAt = now
        pausedRemaining = if (isClockPaused && color == humanColor) turnSeconds else null
    }

    private fun finishNaturally(now: Double) {
        val natural = ReversiRules.wofScore(board)
        score = natural
        result = natural.result
        endReason = ReversiEndReason.of(ReversiRules.endKindOfFinished(board))
        close(now)
    }

    private fun finish(winner: ReversiColor, reason: ReversiEndReason, now: Double) {
        score = null
        result = ReversiResult.of(winner)
        endReason = reason
        close(now)
    }

    private fun close(now: Double) {
        isFinished = true
        turn = null
        turnStartedAt = null
        pausedRemaining = null
        finishedAt = now
    }

    /** Swift 합성 Equatable — 저장 칸 전부(멈춘 남은 초 포함). */
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ReversiAIGame) return false
        return id == other.id && humanColor == other.humanColor && board == other.board && turn == other.turn &&
            pliesStorage == other.pliesStorage && turnStartedAt == other.turnStartedAt && humanAutoStreak == other.humanAutoStreak &&
            isFinished == other.isFinished && result == other.result && endReason == other.endReason && score == other.score &&
            finishedAt == other.finishedAt && isClockPaused == other.isClockPaused && pausedRemaining == other.pausedRemaining
    }

    override fun hashCode(): Int = id.hashCode() * 31 + pliesStorage.size

    companion object {
        /** 판 id 머리말. 서버 판 id 는 uuid 라 이 머리말로 시작할 수 없다 — **이 한 줄이 서버 경로 차단의 근거다**. */
        const val idPrefix: String = "ai-"

        /** 사람 한 수 제한(초) — 1:1 과 같은 30초(유예 2초는 서버 왕복 몫이라 로컬 판엔 없다). */
        const val turnSeconds: Double = 30.0

        /** 연속 자동 착수 몇 번에 사람이 지는가(V-14). */
        const val autoLossStreak: Int = 3

        /** 이 id 가 AI 판인가. 스토어의 서버 경로(조회·착수·기권)가 이 판정으로 요청을 막는다(대소문자 구분 — "AI-1" 은 아니다). */
        fun isAIMatchID(id: String?): Boolean = id?.startsWith(idPrefix) ?: false

        @OptIn(ExperimentalUuidApi::class)
        private fun newID(): String = idPrefix + Uuid.random().toString().lowercase()
    }
}
