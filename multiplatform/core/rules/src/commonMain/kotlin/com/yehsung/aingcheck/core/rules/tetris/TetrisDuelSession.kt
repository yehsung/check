// 원본: Sources/CheckCore/TetrisDuelSession.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.swiftMax
import com.yehsung.aingcheck.core.rules.minigame.swiftMin
import kotlin.math.floor

/** 서버 `tetris_report` 한 번에 실을 값(인자 이름은 서버 계약 `p_*` 와 한 짝). */
data class TetrisDuelReport(
    val seq: Int,
    /** 보이는 판 200글자([TetrisDuelBoard]). */
    val board: String,
    val lines: Int,
    /** 보낸 공격 누계(단조 증가). */
    val garbageSent: Int,
    /** 상대 공격 중 내 대기열에 받아들인 누계. */
    val garbageApplied: Int,
    /** 아직 판에 안 들어온 대기 방해 줄. */
    val pending: Int,
    /** 내가 꼭대기에 닿았다(= 내 패배 신고, D9). */
    val toppedOut: Boolean,
)

/** 앱을 다시 열어 판으로 돌아올 때의 출발점 — 서버가 들고 있는 **내** 판 행(마지막 보고). */
data class TetrisDuelResumePoint(
    val seq: Int,
    val board: String,
    val lines: Int,
    val garbageSent: Int,
    /** 서버가 '받아들였다'고 적어 둔 상대 공격 누계 — 이만큼은 다시 넣지 않는다. */
    val garbageApplied: Int,
    val pending: Int,
    /** 그 보고가 서버에 닿은 판 경과초(`last_seen_ms − start_at_ms`). */
    val elapsedSeconds: Double,
)

/** 지금 보고해야 하는 까닭. */
enum class TetrisDuelReportReason {
    /** 첫 보고 = 준비 완료. */
    ready,
    /** 탑아웃 — 곧바로(최소 간격만). */
    toppedOut,
    /** 공격 누계가 늘었다 — 곧바로(최소 간격만). */
    attack,
    /** 1초 하트비트. */
    heartbeat,
}

/**
 * 테트리스 1:1 — 한 사람 몫의 판 구동기(v0.3.60, 순수 · 맥·폰 공용). 엔진 하나에 ① 판 시계(단조 시계, 최대 30초 따라잡기)
 * ② 가속(D7: t < 120 → 1, 그 뒤 min(28, 10 + (t−120)/10)) ③ 보고 차분(준비 · 탑아웃 · 공격은 곧바로, 최소 간격 0.25초, 1초 하트비트)
 * 을 묶는다. **시계를 읽지 않는다** — 시각은 전부 `now`(로컬 단조 시계 초)로 받는다.
 *
 * Swift 는 값 타입이다. Kotlin 은 참조라 복제가 필요하면 [copy] 를 부른다.
 */
class TetrisDuelSession private constructor(
    /** 서버가 수락 때 뽑은 판 시드(0…2147483647). Swift `Int`(64비트) → Long. */
    val seed: Long,
    private var engine: TetrisGame,
    startAt: Double?,
    simulated: Double,
    started: Boolean,
    finished: Boolean,
    droppedSeconds: Double,
    garbageApplied: Int,
    seq: Int,
    lastReportAt: Double?,
    reportedAttackSent: Int,
    reportedToppedOut: Boolean,
) {
    /**
     * 엔진 상태. Swift 는 값 타입이라 읽은 쪽이 판을 못 바꾼다 — Kotlin 도 **읽을 때마다 사본**을 준다(세션의 입력 문지기 isLive 를
     * 건너뛰어 판을 움직이지 못하게). 한 프레임에 여러 칸을 읽으면 한 번 받아 두고 쓴다.
     */
    val game: TetrisGame get() = engine.copy()
    /** 판 시계 0 의 로컬 단조 시각. null = 서버가 아직 시작을 안 정했다. */
    var startAt: Double? = startAt
        private set
    /** 엔진에 흘려 준 판 시간(초). */
    var simulated: Double = simulated
        private set
    var started: Boolean = started
        private set
    var finished: Boolean = finished
        private set
    /** 따라잡기 상한을 넘어 버린 판 시간 합(진단용). */
    var droppedSeconds: Double = droppedSeconds
        private set
    var garbageApplied: Int = garbageApplied
        private set
    var seq: Int = seq
        private set
    var lastReportAt: Double? = lastReportAt
        private set
    var reportedAttackSent: Int = reportedAttackSent
        private set
    var reportedToppedOut: Boolean = reportedToppedOut
        private set

    /**
     * @param startingSeq 서버에 이미 저장된 seq(다음 보고는 +1).
     * @param garbageApplied 서버가 이미 받아들였다고 적은 상대 공격 누계(리뷰 RV1 — 0 에서 출발하면 공격 이력을 다시 맞는다).
     */
    constructor(seed: Long, startingSeq: Int = 0, garbageApplied: Int = 0) : this(
        seed = seed,
        engine = TetrisGame(clampedSeed(seed)),
        startAt = null,
        simulated = 0.0,
        started = false,
        finished = false,
        droppedSeconds = 0.0,
        garbageApplied = maxOf(0, garbageApplied),
        seq = maxOf(0, startingSeq),
        lastReportAt = null,
        reportedAttackSent = 0,
        reportedToppedOut = false,
    )

    /** 테스트 픽스처 — 이미 시작한 판에서 출발한다(판 시계 0 = [startAt]). */
    constructor(seed: Long, startedGame: TetrisGame, startAt: Double, simulated: Double = 0.0) : this(seed) {
        this.engine = startedGame.copy()
        this.startAt = startAt
        this.simulated = swiftMax(0.0, simulated)
        this.started = true
    }

    /** Swift 값 복사와 같은 뜻의 깊은 복제. */
    fun copy(): TetrisDuelSession = TetrisDuelSession(
        seed, engine.copy(), startAt, simulated, started, finished, droppedSeconds, garbageApplied, seq,
        lastReportAt, reportedAttackSent, reportedToppedOut,
    )

    // MARK: - 읽기

    /** 내가 꼭대기에 닿았다(판이 시작된 뒤의 게임 오버만). */
    val toppedOut: Boolean get() = started && engine.isGameOver

    /** 입력을 받는 상태(시작했고 · 안 끝났고 · 탑아웃 전). */
    val isLive: Boolean get() = started && !finished && !engine.isGameOver

    /** 판 경과초. 시작 시각을 모르면 null, 카운트다운 중이면 음수. */
    fun matchElapsed(at: Double): Double? = startAt?.let { at - it }

    /** 카운트다운 남은 초(모르면 null, 시작했으면 0). */
    fun countdownRemaining(at: Double): Double? = startAt?.let { swiftMax(0.0, it - at) }

    val currentLevelFloor: Int get() = engine.levelFloor

    // MARK: - 시계

    /** 서버 판 시작을 로컬 단조 시계로 옮겨 둔다. 가장 이른 추정을 남긴다(판 시계가 뒤로 가지 않게). */
    fun syncStart(startAtMs: Double, serverNowMs: Double, localNow: Double) {
        if (!startAtMs.isFinite() || !serverNowMs.isFinite() || !localNow.isFinite()) return
        val estimate = localStart(startAtMs, serverNowMs, localNow)
        startAt = swiftMin(startAt ?: estimate, estimate)
    }

    /** 판 시계를 [now] 까지 민다(따라잡기 · 시작 시각을 처음 넘는 순간 엔진을 연다). */
    fun advance(now: Double) {
        if (finished) return
        val start = startAt ?: return
        if (!now.isFinite()) return
        val target = now - start
        if (!(target >= 0)) return
        if (!started) {
            started = true
            simulated = 0.0
            engine.action()
        }
        var remaining = target - simulated
        if (!(remaining > 0)) return
        if (remaining > maxCatchUpSeconds) {
            val skip = remaining - maxCatchUpSeconds
            droppedSeconds += skip
            simulated += skip
            remaining = maxCatchUpSeconds
        }
        while (remaining > 1e-9) {
            if (engine.phase == TetrisGame.Phase.Result) {
                simulated += remaining
                return
            }
            engine.setLevelFloor(rampLevelFloor(simulated))
            val dt = swiftMin(remaining, TetrisGame.maxStep)
            engine.step(dt)
            simulated += dt
            remaining -= dt
        }
    }

    /** 서버가 판을 닫았다. 눌린 키를 풀고 이후로는 멎는다. */
    fun finish() {
        finished = true
        engine.releaseAllKeys()
    }

    // MARK: - 입력(살아 있을 때만 · 뗌은 언제나)

    fun setLeftHeld(held: Boolean) {
        if (!(isLive || !held)) return
        engine.setLeftHeld(held)
    }

    fun setRightHeld(held: Boolean) {
        if (!(isLive || !held)) return
        engine.setRightHeld(held)
    }

    fun setSoftDropHeld(held: Boolean) {
        if (!(isLive || !held)) return
        engine.setSoftDropHeld(held)
    }

    fun rotate(clockwise: Boolean) {
        if (!isLive) return
        engine.rotate(clockwise)
    }

    /**
     * 가로 **한 칸**(폰 끌기). 누름과 뗌을 같은 호출 안에서 연달아 준다 — 쌍 사이에 시간이 안 흘러 DAS 가 만기될 수 없다.
     *
     * INV-TetrisDuelSession-de855c1d 이식: **쌍 사이에 [advance]·step 을 끼우지 마라** — 그 순간 자동 반복이 살아나 한 걸음이
     * 여러 칸이 된다. 이 함수 안에서 끝나므로 호출자는 끼울 수 없다(대본 골든 `tetris/duel` 의 ML·MR 연산이 이 함수다).
     */
    fun moveLeftOneCell() {
        if (!isLive) return
        engine.setLeftHeld(true)
        engine.setLeftHeld(false)
    }

    fun moveRightOneCell() {
        if (!isLive) return
        engine.setRightHeld(true)
        engine.setRightHeld(false)
    }

    /** 세로 한 칸(엔진 softDropOneCell). */
    fun softDropOneCell(): Boolean {
        if (!isLive) return false
        return engine.softDropOneCell()
    }

    fun hold() {
        if (!isLive) return
        engine.holdCurrentPiece()
    }

    /** 하드드롭. 엔진 action() 은 ready/result 에서 새 판이라 조각이 있을 때만 부른다. */
    fun hardDrop() {
        if (!isLive || engine.phase != TetrisGame.Phase.Running) return
        engine.action()
    }

    fun releaseAllKeys() {
        engine.releaseAllKeys()
    }

    // MARK: - 상대 공격

    /** 상대 공격 누계를 받아 지난번과의 **차분만** 대기열에 넣는다. 받을 수 없는 때는 누계를 올리지 않는다. */
    fun absorbOpponentAttack(total: Int): Int {
        if (finished || !started) return 0
        val diff = total - garbageApplied
        if (diff <= 0) return 0
        if (!engine.receiveGarbage(diff)) return 0
        garbageApplied = total
        return diff
    }

    // MARK: - 보고

    /** 지금 보고할 때인가. 첫 보고는 준비, 그 뒤 탑아웃·공격은 최소 간격만, 그 밖엔 1초 하트비트. */
    fun reportReason(at: Double): TetrisDuelReportReason? {
        if (finished) return null
        val last = lastReportAt ?: return TetrisDuelReportReason.ready
        val since = at - last
        if (since >= minReportGapSeconds) {
            if (toppedOut && !reportedToppedOut) return TetrisDuelReportReason.toppedOut
            if (engine.attackSentTotal > reportedAttackSent) return TetrisDuelReportReason.attack
        }
        if (since >= heartbeatSeconds) return TetrisDuelReportReason.heartbeat
        return null
    }

    /** 보고 한 벌을 만들고 장부(번호 · 시각 · 실은 누계)를 넘긴다. */
    fun makeReport(at: Double): TetrisDuelReport {
        seq += 1
        lastReportAt = at
        reportedAttackSent = engine.attackSentTotal
        reportedToppedOut = toppedOut
        return TetrisDuelReport(
            seq = seq, board = TetrisDuelBoard.encode(engine), lines = engine.lines,
            garbageSent = engine.attackSentTotal, garbageApplied = garbageApplied,
            pending = engine.pendingGarbageLines, toppedOut = toppedOut,
        )
    }

    /** 서버가 `stale` 로 돌려준 저장 seq 를 따라잡는다. */
    fun adoptServerSeq(serverSeq: Int) {
        seq = maxOf(seq, serverSeq)
    }

    companion object {
        const val rampStartSeconds: Int = 120
        const val rampStartLevel: Int = 10
        const val rampSecondsPerLevel: Int = 10
        const val rampMaxLevel: Int = 28
        const val maxCatchUpSeconds: Double = 30.0
        const val heartbeatSeconds: Double = 1.0
        const val minReportGapSeconds: Double = 0.25

        /** Swift `UInt64(clamping: seed)`. */
        private fun clampedSeed(seed: Long): ULong = if (seed < 0) 0uL else seed.toULong()

        /** 판 경과초 → 레벨 바닥(D7). 초는 내림한 정수(서버 식과 같은 정수 나눗셈). */
        fun rampLevelFloor(elapsedSeconds: Double): Int {
            val t = elapsedSeconds
            if (!(t.isFinite() && t >= rampStartSeconds.toDouble())) return 1
            if (!(t < 1_000_000)) return rampMaxLevel
            val seconds = floor(t).toInt()
            return minOf(rampMaxLevel, rampStartLevel + (seconds - rampStartSeconds) / rampSecondsPerLevel)
        }

        /** 서버 시각 → 로컬 단조 시계의 판 시작(받은 지연만큼 늦다 — 이르지는 않다). */
        fun localStart(startAtMs: Double, serverNowMs: Double, localNow: Double): Double =
            localNow + (startAtMs - serverNowMs) / 1000

        /**
         * 앱을 다시 열어 **이미 시작한** 판으로 돌아온다(리뷰 RV1 — 빈 판에서 다시 시작하면 거의 찬 판이 공짜로 비워진다).
         * 판은 서버 마지막 보고 그대로(방해 줄 `G` 는 표시까지), 누계도 그 값에서 잇는다. 판 시계는 그 보고가 닿은 판 시각에 서 있다.
         * 판 글자가 서버 CHECK 모양이 아니면 null — 깨진 판을 지어내지 않는다.
         */
        fun resuming(seed: Long, point: TetrisDuelResumePoint): TetrisDuelSession? {
            val decoded = TetrisDuelBoard.decode(point.board) ?: return null
            val board = MutableList(TetrisGame.totalRows) { MutableList<TetrisGame.Piece?>(TetrisGame.columns) { null } }
            val mask = IntArray(TetrisGame.totalRows)
            for ((offset, row) in decoded.withIndex()) {
                val boardRow = TetrisGame.firstVisibleRow + offset
                for ((column, cell) in row.withIndex()) {
                    when (cell) {
                        TetrisDuelCell.Empty -> continue
                        is TetrisDuelCell.Piece -> board[boardRow][column] = cell.piece
                        TetrisDuelCell.Garbage -> {
                            board[boardRow][column] = TetrisGame.Piece.i
                            mask[boardRow] = mask[boardRow] or (1 shl column)
                        }
                    }
                }
            }
            val session = TetrisDuelSession(seed, startingSeq = point.seq, garbageApplied = point.garbageApplied)
            session.engine = TetrisGame(
                seed = clampedSeed(seed), board = board, active = null,
                phase = TetrisGame.Phase.Are(TetrisGame.areSeconds),
                lines = maxOf(0, point.lines),
                pendingGarbage = if (point.pending > 0) listOf(point.pending) else emptyList(),
                attackSentTotal = maxOf(0, point.garbageSent),
                garbageMask = mask.toList(),
            )
            session.started = true
            session.simulated = if (point.elapsedSeconds.isFinite()) swiftMax(0.0, point.elapsedSeconds) else 0.0
            session.reportedAttackSent = session.engine.attackSentTotal
            return session
        }
    }
}
