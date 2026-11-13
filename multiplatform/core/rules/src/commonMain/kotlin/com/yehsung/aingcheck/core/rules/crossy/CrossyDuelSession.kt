// 원본: Sources/CheckCore/CrossyDuelSession.swift @ e4995a3a(1:1 길건너 판 구동기 — 맥 0.3.78 · 폰 1.0.18 · Android 판 8)
//
// 1:1 길건너 판 구동기(순수 값 — 테트리스 TetrisDuelSession 틀, SPEC v1.3 §8.1 · §3.1 · §3.4 B4).
// 판 시계는 로컬 **단조** 시계의 초(스토어의 uptime())다. 서버 start_at_ms 를 [syncStart] 로 옮겨 두고, 그 전엔 판을 Ready 에 둔다 →
// startAt 에 game.begin() → 1/30초 조각으로 step(따라잡기 상한 1초) → endAt 에서 얼림. 보고 판단([reportDue])은 간격을 인자로 받는다.
// 보고 한 건의 수명: reportDue 가 종류를 말한다 → 스토어가 [makeReport] 로 본문을 만든다(seq +1 · 직전 값 · 비행 중) → 응답이 오면
// [reportSettled](또는 3초 멎음이면 같은 자리에서 버린다). **goal · cap 은 비행 중이어도 낸다**(v1.1 CC-3).
// Swift 는 값 타입이다 — Kotlin 은 [copy] 로 복제한다(판 값까지 깊이).
// 와이어 본문을 들이므로 minigame/ 밖(규칙 결정성 구조 시험의 들여오기 잠금 — TetrisDuelSession 과 같은 자리)에 둔다.
package com.yehsung.aingcheck.core.rules.crossy

import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.wire.games.CrossyDuelReportBody

class CrossyDuelSession private constructor(
    val seed: Long,
    game: CrossyGame,
    val maxDuration: Double,
    startAt: Double?,
    seq: Int,
    lastSent: LastSent?,
    inFlight: Boolean,
    started: Boolean,
    finished: Boolean,
    goalReported: Boolean,
    capReported: Boolean,
    postGraceReported: Boolean,
    advancedTo: Double?,
    droppedSeconds: Double,
    serverClosed: Boolean,
    retryPending: ReportKind?,
) {
    enum class ReportKind { ready, goal, cap, postGrace, change, heartbeat }

    data class LastSent(val score: Int, val deaths: Int, val at: Double)

    var game: CrossyGame = game
        private set
    var startAt: Double? = startAt
        private set
    var seq: Int = seq
        private set
    var lastSent: LastSent? = lastSent
        private set
    var inFlight: Boolean = inFlight
        private set
    var started: Boolean = started
        private set
    var finished: Boolean = finished
        private set
    var goalReported: Boolean = goalReported
        private set
    var capReported: Boolean = capReported
        private set
    var postGraceReported: Boolean = postGraceReported
        private set
    var advancedTo: Double? = advancedTo
        private set
    var droppedSeconds: Double = droppedSeconds
        private set
    var serverClosed: Boolean = serverClosed
        private set
    var retryPending: ReportKind? = retryPending
        private set

    /** 새 판(카운트다운 전) — 1:1 규칙에 목표만 서버 값으로. */
    constructor(seed: Long, goal: Int = EXPECTED_GOAL, maxDurationSeconds: Int = EXPECTED_MAX_DURATION_SECONDS, startingSeq: Int = 0) : this(
        seed = seed,
        game = CrossyGame(maxOf(0L, seed).toULong(), CrossyGame.Rules.duel.copy(goalScore = goal)),
        maxDuration = maxDurationSeconds.toDouble(),
        startAt = null, seq = maxOf(0, startingSeq), lastSent = null, inFlight = false, started = false, finished = false,
        goalReported = false, capReported = false, postGraceReported = false, advancedTo = null, droppedSeconds = 0.0,
        serverClosed = false, retryPending = null,
    )

    companion object {
        const val EXPECTED_GOAL = 100
        const val EXPECTED_MAX_DURATION_SECONDS = 180
        const val GRACE_SECONDS: Double = 2.0
        val STEP_SECONDS: Double get() = CrossyGame.maxStep
        const val MAX_CATCH_UP_SECONDS: Double = 1.0
        const val MIN_REPORT_GAP_SECONDS: Double = 0.25
        const val UNSTARTED_HEARTBEAT_SECONDS: Double = 1.0
        const val DEFAULT_REPORT_MS = 2_000
        const val DEFAULT_HEARTBEAT_MS = 3_000
        const val REPORT_STALL_SECONDS: Double = 3.0

        fun localStart(startAtMs: Double, serverNowMs: Double, localNow: Double): Double = localNow + (startAtMs - serverNowMs) / 1000

        /** 이미 시작한 판(시험 · 이어 하기 재료). */
        fun started(seed: Long, game: CrossyGame, startAt: Double, maxDurationSeconds: Int = EXPECTED_MAX_DURATION_SECONDS, seq: Int = 0): CrossyDuelSession =
            CrossyDuelSession(
                seed, game.copy(), maxDurationSeconds.toDouble(), startAt, maxOf(0, seq), null, false, true, false,
                false, false, false, startAt, 0.0, false, null,
            )

        /** 보고 · 심장 박동 간격(서버 값을 1~5초로 자르고 심장은 보고 이상). */
        fun clampedIntervals(reportMs: Int?, heartbeatMs: Int?): Pair<Int, Int> {
            val report = minOf(maxOf(reportMs ?: DEFAULT_REPORT_MS, 1_000), 5_000)
            val heartbeat = minOf(maxOf(heartbeatMs ?: DEFAULT_HEARTBEAT_MS, report), 5_000)
            return report to heartbeat
        }
    }

    fun copy(): CrossyDuelSession = CrossyDuelSession(
        seed, game.copy(), maxDuration, startAt, seq, lastSent, inFlight, started, finished, goalReported, capReported,
        postGraceReported, advancedTo, droppedSeconds, serverClosed, retryPending,
    )

    override fun equals(other: Any?): Boolean = other is CrossyDuelSession && other.seed == seed && other.game == game &&
        other.maxDuration == maxDuration && other.startAt == startAt && other.seq == seq && other.lastSent == lastSent &&
        other.inFlight == inFlight && other.started == started && other.finished == finished && other.goalReported == goalReported &&
        other.capReported == capReported && other.postGraceReported == postGraceReported && other.advancedTo == advancedTo &&
        other.droppedSeconds == droppedSeconds && other.serverClosed == serverClosed && other.retryPending == retryPending

    override fun hashCode(): Int = seed.hashCode() * 31 + seq

    // MARK: 시계

    val endAt: Double? get() = startAt?.let { it + maxDuration }
    val graceEndAt: Double? get() = endAt?.let { it + GRACE_SECONDS }

    /** 서버 시작 시각을 로컬 단조 시계로 옮긴다. 이미 있으면 더 이른 쪽(늦게 온 응답이 판을 뒤로 밀지 않게). */
    fun syncStart(startAtMs: Double, serverNowMs: Double, localNow: Double) {
        if (!startAtMs.isFinite() || !serverNowMs.isFinite() || !localNow.isFinite()) return
        val estimate = localStart(startAtMs, serverNowMs, localNow)
        startAt = minOf(startAt ?: estimate, estimate)
    }

    fun countdownRemaining(now: Double): Double? = startAt?.let { maxOf(0.0, it - now) }

    fun remaining(now: Double): Double? = endAt?.let { maxOf(0.0, it - maxOf(now, startAt ?: now)) }

    // MARK: 판

    fun advance(now: Double) {
        val start = startAt ?: return
        val end = endAt ?: return
        if (!now.isFinite() || finished || serverClosed || now < start) return
        if (!started) {
            game.begin()
            started = true
            advancedTo = start
        }
        val target = minOf(now, end)
        val from = advancedTo ?: target
        if (target > from) {
            var span = target - from
            if (span > MAX_CATCH_UP_SECONDS) {
                droppedSeconds += span - MAX_CATCH_UP_SECONDS
                span = MAX_CATCH_UP_SECONDS
            }
            while (span > 1e-9) {
                val dt = minOf(STEP_SECONDS, span)
                game.step(dt)
                span -= dt
            }
        }
        advancedTo = maxOf(from, target)
        if (now >= end) finished = true
    }

    fun freeze() {
        serverClosed = true
        finished = true
        inFlight = false
    }

    val isLive: Boolean get() = started && !finished && !serverClosed
    val goal: Int get() = game.rules.goalScore ?: EXPECTED_GOAL

    fun input(direction: CrossyGame.Direction) {
        if (!started || finished || serverClosed) return
        game.input(direction)
    }

    fun forward() = input(CrossyGame.Direction.forward)

    // MARK: 보고

    fun reportDue(now: Double, reportMs: Int, heartbeatMs: Int, windowVisible: Boolean, changeReportsSuppressed: Boolean = false): ReportKind? {
        if (!now.isFinite() || serverClosed) return null
        val last = lastSent ?: return if (windowVisible) ReportKind.ready else null
        val gap = now - last.at
        if (gap < MIN_REPORT_GAP_SECONDS) return null
        if (!goalReported && started && game.score >= goal) return ReportKind.goal
        val end = endAt
        if (!capReported && end != null && now >= end) return ReportKind.cap
        if (inFlight) return null
        retryPending?.let { return it }
        val graceEnd = graceEndAt
        if (!postGraceReported && graceEnd != null && now >= graceEnd + MIN_REPORT_GAP_SECONDS) return ReportKind.postGrace
        if (startAt == null) return if (gap >= UNSTARTED_HEARTBEAT_SECONDS) ReportKind.heartbeat else null
        val (report, heartbeat) = clampedIntervals(reportMs, heartbeatMs)
        if (!changeReportsSuppressed && (game.score != last.score || game.deaths != last.deaths) && gap >= report.toDouble() / 1000) {
            return ReportKind.change
        }
        if (gap >= heartbeat.toDouble() / 1000) return ReportKind.heartbeat
        return null
    }

    fun makeReport(kind: ReportKind, now: Double): CrossyDuelReportBody {
        val body = makeReport()
        lastSent = LastSent(body.score.toInt(), body.deaths.toInt(), now)
        inFlight = true
        retryPending = null
        when (kind) {
            ReportKind.goal -> goalReported = true
            ReportKind.cap -> capReported = true
            ReportKind.postGrace -> postGraceReported = true
            ReportKind.ready, ReportKind.change, ReportKind.heartbeat -> Unit
        }
        return body
    }

    fun reportNeedsRetry(kind: ReportKind) {
        if (serverClosed) return
        when (kind) {
            ReportKind.goal -> goalReported = false
            ReportKind.cap -> capReported = false
            ReportKind.postGrace -> postGraceReported = false
            ReportKind.ready, ReportKind.change, ReportKind.heartbeat -> Unit
        }
        if (lastSent == null) return
        retryPending = kind
    }

    fun reportSettled() {
        inFlight = false
    }

    fun reportStalled(now: Double): Boolean {
        val at = lastSent?.at ?: return false
        return inFlight && now - at >= REPORT_STALL_SECONDS
    }

    fun adoptServerSeq(serverSeq: Int) {
        seq = maxOf(seq, serverSeq)
    }

    /** 서버 점수가 로컬보다 크면 그 줄로 다시 세운다(CC-22). 목표 이상 · 결과면 안 한다. */
    fun catchUp(serverScore: Int, serverDeaths: Int): Boolean {
        if (!isLive || serverScore <= game.score || serverScore >= goal || game.phase == CrossyGame.Phase.Result) return false
        game.restore(serverScore, serverScore, maxOf(serverDeaths, game.deaths))
        return true
    }

    fun makeReport(): CrossyDuelReportBody {
        seq += 1
        return CrossyDuelReportBody(seq.toLong(), game.score.toLong(), game.deaths.toLong())
    }

    /** 앱 재실행 이어 하기 — 서버가 아는 점수 · 넘어짐 · 순번에서 다시 연다(목표 바로 아래까지). */
    fun resume(score: Int, deaths: Int, seq: Int) {
        if (started || serverClosed) return
        val clamped = minOf(maxOf(0, score), maxOf(0, goal - 1))
        game.restore(clamped, clamped, maxOf(0, deaths))
        started = true
        advancedTo = null
        this.seq = maxOf(this.seq, seq)
    }
}
