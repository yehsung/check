// 원본: Sources/CheckCore/CrossyDuelStoreGame.swift @ e4995a3a(판 갈래) — Android 판 8
//
// 판 구동기 수명 · 판 루프 · 입력 문 · 보고 루프 · 한 판 한 기기 · 경주 스냅숏(SPEC v1.3 §8.3 · §3.1 · §3.4 B4 · §8.4).
//   판 루프(창과 무관, 0.05초) ─┐
//   화면 프레임 루프(보일 때) ───┼→ tick(now) → duel.advance → 흐름 → considerFrame → considerReport
//   입력 문(hop · forward) ──────┘
// ★ 판정 · 루비는 **서버 값만**. 3분 얼림 · 100 도달 뒤에도 결과가 올 때까지 하트비트를 멈추지 않는다(`waitingForResult`).
// ★ 구동기는 **이 기기가 두는 판**에서만 선다(`playsMatch`).
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.net.CrossyDuelLockNotAvailable
import com.yehsung.aingcheck.core.net.crossyDuelReport
import com.yehsung.aingcheck.core.rules.crossy.CrossyDuelSession
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.clampedInt
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.games.CrossyDuelActionResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRPCStatus
import com.yehsung.aingcheck.core.wire.games.CrossyDuelReportBody
import com.yehsung.aingcheck.core.wire.games.CrossyDuelSideRow
import com.yehsung.aingcheck.core.wire.games.CrossyDuelStatePayload
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// MARK: - 판 구동기 수명

/** 재개 출발점(순수). */
data class CrossyDuelResumePoint(val score: Int, val deaths: Int, val seq: Int)

/**
 * 진행 중 판의 구동기를 준비한다(같은 판이면 그대로 둔다). 씨앗이 없으면 만들지 않는다. 서버가 **판 중에 받은 내 보고**를 이미 들고
 * 있으면(앱을 다시 열었다) 그 값에서 이어 선다(`resume`).
 */
internal fun CrossyDuelStore.prepareDuel(matchID: String, payload: CrossyDuelStatePayload) {
    if (duel != null && duelMatchID == matchID) return
    discardDuel()
    val seed = payload.seed
    if (seed == null) {
        logNotice("duel not prepared — active match without seed")
        return
    }
    val session = CrossyDuelSession(
        seed = seed,
        goal = payload.goal?.clampedInt() ?: CrossyDuelSession.EXPECTED_GOAL,
        maxDurationSeconds = payload.maxDurationSeconds?.clampedInt() ?: CrossyDuelSession.EXPECTED_MAX_DURATION_SECONDS,
        startingSeq = (payload.me?.seq ?: 0).clampedInt(),
    )
    resumePoint(payload.me, payload.startAtMs)?.let { point ->
        session.resume(point.score, point.deaths, point.seq)
        logNotice("duel resumed from server row seq=${point.seq} score=${point.score}")
    }
    duel = session
    duelMatchID = matchID
}

/** 서버의 내 행이 **판이 시작된 뒤에** 받아 적은 보고면 재개 출발점(순수). 아니면 null(새 판으로 연다). */
fun resumePoint(me: CrossyDuelSideRow?, startAtMs: Double?): CrossyDuelResumePoint? {
    me ?: return null
    val seq = me.seq ?: return null
    if (seq <= 0 || me.ready != true) return null
    val start = startAtMs ?: return null
    val lastSeen = me.lastSeenMs ?: return null
    if (!start.isFinite() || !lastSeen.isFinite() || lastSeen <= start) return null
    return CrossyDuelResumePoint(maxOf(0, (me.score ?: 0).clampedInt()), maxOf(0, (me.deaths ?: 0).clampedInt()), seq.clampedInt())
}

/** 구동기를 버린다(판 루프 · 프레임 소켓까지 — 나가 있는 보고의 응답은 세대로 버려진다). */
fun CrossyDuelStore.discardDuel() {
    stopGameLoop()
    discardFrames()
    duelGeneration += 1
    reportInFlight = false
    reportSentAt = null
    reportInFlightKind = null
    reportFailureStreak = 0
    duel = null
    duelMatchID = null
    if (connectionTrouble) connectionTrouble = false
}

// MARK: - 판 루프 (창과 무관하게 흐른다)

internal fun CrossyDuelStore.startGameLoop() {
    if (gameLoopJob != null || duel == null) return
    gameLoopToken += 1
    val token = gameLoopToken
    gameLoopJob = scope.launch {
        while (true) {
            delay(delayMillis(gameLoopStepSeconds))
            if (token != gameLoopToken) return@launch
            if (duel == null || match?.isFinished != false) {
                gameLoopJob = null
                return@launch
            }
            tick()
        }
    }
}

internal fun CrossyDuelStore.stopGameLoop() {
    gameLoopToken += 1
    gameLoopJob?.cancel()
    gameLoopJob = null
}

/** 판 루프 한 걸음 + 보고 판단(창과 무관). 인자가 없으면 [CrossyDuelStore.uptime]. 같은 시각이면 아무 일도 안 한다. */
fun CrossyDuelStore.tick(now: Double? = null) {
    val d = duel ?: return
    val instant = now ?: uptime()
    d.advance(instant)
    refreshPhase()
    // 프레임은 보고보다 **먼저**, 따로 묻는다 — 나가 있는 보고가 프레임을 막지 않는다.
    considerFrame(instant)
    considerReport(instant)
}

/** 화면 흐름을 판 상태에서 다시 내고, 끝에서 활동 붙들기 신호를 맞춘다. */
fun CrossyDuelStore.refreshPhase() {
    val m = match
    val d = duel
    val next = when {
        m == null -> CrossyDuelPhase.lobby
        m.isFinished -> CrossyDuelPhase.finished
        d != null && duelMatchID == m.id && d.startAt != null -> if (d.started) CrossyDuelPhase.playing else CrossyDuelPhase.countdown
        else -> CrossyDuelPhase.ready
    }
    if (phase != next) phase = next
    syncHoldingActivity()
}

/** [CrossyDuelStore.holdsActivity] 가 바뀌었으면 한 번 알린다. */
internal fun CrossyDuelStore.syncHoldingActivity() {
    val holding = holdsActivity
    if (holding == lastHoldingActivity) return
    lastHoldingActivity = holding
    onHoldingActivityChange?.invoke(holding)
}

// MARK: - 입력 문

/** 방향 입력(판 중에만). 넣기 **전에** 판을 지금까지 민다. */
fun CrossyDuelStore.hop(direction: CrossyGame.Direction) {
    if (phase != CrossyDuelPhase.playing || playingElsewhere) return
    val d = duel ?: return
    d.advance(uptime())
    d.input(direction)
}

/** 앞으로 한 칸(탭). */
fun CrossyDuelStore.forward() = hop(CrossyGame.Direction.forward)

// MARK: - 경주 스냅숏

/**
 * 경주 트랙 값 하나(단조 시계). 판이 없으면 null.
 *  · 내 점수 = 로컬 엔진(끝난 판은 [finishedMyScore]) · 상대 점수 = 끝나지 않은 판에서 max(프레임 sc, DB), 끝난 판은 final.opponent
 *  · opponentQuiet = 상대의 마지막 증거 뒤 8초 넘음 · waitingForResult = 얼었거나 100 에 닿았는데 결과가 아직 없다
 */
fun CrossyDuelStore.raceSnapshot(now: Double? = null): CrossyDuelRaceSnapshot? {
    val m = match ?: return null
    val t = now ?: uptime()
    val ownDuel = if (duelMatchID == null || duelMatchID == m.id) duel else null
    val game = ownDuel?.game
    val goal = game?.rules?.goalScore ?: CrossyDuelSession.EXPECTED_GOAL
    val localScore = game?.score ?: m.myServerScore
    val myScore = if (m.isFinished) finishedMyScore(m, game?.score) else localScore
    val link = if (frameLinkMatchID == null || frameLinkMatchID == m.id) frameLink else null
    val opponentScore = if (m.isFinished) (m.finalOpponentScore ?: m.opponentScore) else (link?.mergedOpponentScore(m.opponentScore) ?: m.opponentScore)
    var respawnIn: Double? = null
    val phase = game?.phase
    if (game != null && !m.isFinished && game.rules.respawnDelay != null && phase is CrossyGame.Phase.Over) respawnIn = maxOf(0.0, phase.hold)
    val shielded = game?.let { g -> g.respawnShield?.let { g.elapsed < it.until } ?: false } ?: false
    val countdown = if (m.isFinished) null else ownDuel?.countdownRemaining(t)?.takeIf { it > 0 }
    val reachedGoal = (game?.score ?: 0) >= goal
    val frozen = m.isFinished || (ownDuel?.finished ?: false) || reachedGoal
    val waiting = !m.isFinished && ((ownDuel?.finished ?: false) || reachedGoal)
    // 판 구동기 시계가 없을 때: 끝 시각을 알면 기기 시계로 센 남은 시간, 모르면 판 상한(3:00). "0:00" 은 끝난 판의 굳힌 글자다.
    val cap = CrossyDuelSession.EXPECTED_MAX_DURATION_SECONDS.toDouble()
    val remaining: Double = if (m.isFinished) {
        0.0
    } else {
        ownDuel?.remaining(t) ?: m.endAt?.let { maxOf(0.0, minOf(cap, it.timeIntervalSince(clock()))) } ?: cap
    }
    return CrossyDuelRaceSnapshot(
        myScore = myScore, opponentScore = opponentScore, goal = goal,
        myDeaths = game?.deaths ?: 0, opponentDeaths = m.opponentDeaths,
        countdown = countdown, remaining = remaining, respawnIn = respawnIn,
        shielded = shielded && !m.isFinished, frozen = frozen, waitingForResult = waiting,
        opponentQuiet = !m.isFinished && opponentQuiet(t),
    )
}

/** 끝난 판의 '나' 숫자 — goal 로 **진** 판만 max(final.me, 로컬), 그 밖은 final.me(없으면 로컬 · 서버 값 순). */
fun finishedMyScore(match: CrossyDuelMatchState, localScore: Int?): Int {
    val settled = match.finalMyScore ?: localScore ?: match.myServerScore
    if (match.endReason != CrossyDuelEndReason.goal || match.outcome != CrossyDuelOutcome.loss || localScore == null) return settled
    return maxOf(settled, localScore)
}

/** 상대가 조용한가(8초). DB 재료와 프레임 수신 중 **최근 증거**를 쓴다. 둘 다 없으면 거짓. */
fun CrossyDuelStore.opponentQuiet(now: Double): Boolean {
    var silence: Double? = null
    val atReceipt = opponentSilenceAtReceipt
    val received = opponentSilenceReceivedAt
    if (atReceipt != null && received != null) silence = atReceipt + maxOf(0.0, now - received)
    val heard = frameLink?.opponentHeardAt
    if (heard != null && frameLinkMatchID == match?.id) {
        val framed = maxOf(0.0, now - heard)
        silence = silence?.let { minOf(it, framed) } ?: framed
    }
    val s = silence ?: return false
    return s > CrossyDuelStore.opponentQuietSeconds
}

// MARK: - 보고 루프

/** 보고할 때면 한 벌을 만들어 보낸다. 나가 있는 보고가 3초 넘게 답이 없으면 버리고 새로 낸다. */
internal fun CrossyDuelStore.considerReport(now: Double) {
    val sentAt = reportSentAt
    if (reportInFlight && sentAt != null && now - sentAt >= CrossyDuelSession.REPORT_STALL_SECONDS) abandonStalledReport(sentAt, now)
    val current = match ?: return
    if (current.isFinished) return
    val d = duel ?: return
    if (duelMatchID != current.id || host?.session == null) return
    // 준비(첫 보고)는 창이 보일 때만 — 서버가 이미 준비를 받았으면 문이 열려 있다.
    val windowOpen = isWindowVisible || current.meReady
    val confirmed = frameChangeReportsSuppressed(now)
    val heartbeat = if (confirmed) (frameLink?.checkpointMs ?: current.heartbeatMs) else current.heartbeatMs
    val kind = d.reportDue(now, current.reportMs, heartbeat, windowOpen, confirmed) ?: return
    val body = d.makeReport(kind, now)
    sendReport(body, kind, current.id, now)
}

/** 멎은 보고를 놓는다(그 답은 표가 바뀌어 버려진다). 실패 한 번으로 센다. 결승 보고였으면 다음 걸음에 같은 종류로 다시 낸다. */
private fun CrossyDuelStore.abandonStalledReport(sentAt: Double, now: Double) {
    reportTicket += 1
    reportInFlight = false
    reportSentAt = null
    duel?.reportSettled()
    val kind = reportInFlightKind
    if (kind == CrossyDuelSession.ReportKind.goal || kind == CrossyDuelSession.ReportKind.cap || kind == CrossyDuelSession.ReportKind.postGrace) {
        duel?.reportNeedsRetry(kind)
    }
    reportInFlightKind = null
    reportFailureStreak += 1
    noteFrameReportStreak()
    if (reportFailureStreak >= CrossyDuelStore.reportFailureLimit && !connectionTrouble) connectionTrouble = true
    logNotice("report stalled ${((now - sentAt) * 10).toLong() / 10.0}s — abandoned streak=$reportFailureStreak")
}

private fun CrossyDuelStore.sendReport(report: CrossyDuelReportBody, kind: CrossyDuelSession.ReportKind, matchID: String, now: Double) {
    reportInFlight = true
    reportSentAt = now
    reportInFlightKind = kind
    reportTicket += 1
    val ticket = reportTicket
    val token = duelGeneration
    if (kind != CrossyDuelSession.ReportKind.heartbeat) logNotice("report kind=$kind seq=${report.seq} score=${report.score}")
    reportJob = scope.launch {
        val result = perform { service, accessToken -> service.crossyDuelReport(accessToken, matchID, report) }
        val receivedAt = uptime()
        if (token != duelGeneration) return@launch
        // 버렸거나 goal·cap 이 앞지른 보고의 늦은 답 — 그 뒤에 낸 보고가 자리를 쥐고 있다.
        if (ticket != reportTicket) return@launch
        reportInFlight = false
        reportSentAt = null
        reportInFlightKind = null
        duel?.reportSettled()
        result ?: return@launch
        applyReportResult(result, matchID, receivedAt, kind)
        considerReport(uptime())
    }
}

/**
 * 보고 응답 하나를 옮긴다. ok·stale 둘 다 상태를 싣는다. 실패면 55P03 은 무엇이든 · 그 밖의 실패는 결승 보고(goal · cap · postGrace)만
 * 다음 걸음에 다시 낸다.
 */
fun CrossyDuelStore.applyReportResult(
    result: DuelCall<CrossyDuelActionResponse>,
    matchID: String,
    receivedAt: Double,
    kind: CrossyDuelSession.ReportKind? = null,
) {
    when (result) {
        is DuelCall.Failure -> {
            val error = result.error
            if (error is CrossyDuelLockNotAvailable) {
                // 55P03 — 정산 경합의 순간이 바로 결승선이다. 실패로 세지 않고 다음 걸음에 다시 보낸다(CC-21).
                logNotice("report lock timeout — retry next step")
                if (kind != null) duel?.reportNeedsRetry(kind)
                return
            }
            if (kind == CrossyDuelSession.ReportKind.goal || kind == CrossyDuelSession.ReportKind.cap || kind == CrossyDuelSession.ReportKind.postGrace) {
                duel?.reportNeedsRetry(kind)
            }
            reportFailureStreak += 1
            noteFrameReportStreak()
            if (reportFailureStreak >= CrossyDuelStore.reportFailureLimit && !connectionTrouble) connectionTrouble = true
            if (isSchemaMissing(error)) noteServerMissing()
            logNotice("report failed streak=$reportFailureStreak")
        }
        is DuelCall.Success -> {
            val response = result.value
            reportFailureStreak = 0
            noteFrameReportStreak()
            if (connectionTrouble) connectionTrouble = false
            noteServerNow(response.serverNowMs)
            when (response.status) {
                CrossyDuelRPCStatus.ok, CrossyDuelRPCStatus.stale -> response.state?.let { applyState(it, receivedAt) }
                CrossyDuelRPCStatus.otherDevice -> {
                    logNotice("report refused — another device plays this match")
                    yieldMatchToOtherDevice(matchID)
                    response.state?.let { applyState(it, receivedAt) }
                }
                CrossyDuelRPCStatus.notFound -> if (match?.id == matchID) {
                    clearMatch()
                    setNotice(CrossyDuelNoticeText.finishedMatch)
                }
                CrossyDuelRPCStatus.unsupportedClient -> noteUpdateRequired()
                CrossyDuelRPCStatus.notSignedIn -> setNotice(CrossyDuelNoticeText.signInAgain)
                else -> logNotice("report refused status=${response.status.rawValue}")
            }
        }
    }
}

// MARK: - 한 판 한 기기 (서버 `my_device` → 없으면 장부)

/** 이 기기가 이 판을 **두는가**. 물러난 판이면 아니다 · 'this' 면 둔다 · 'other' 면 안 둔다 · 말이 없으면 장부. */
fun CrossyDuelStore.playsMatch(matchID: String, myDevice: String?): Boolean {
    val id = matchID.lowercase()
    if (id in yieldedMatchIDs) return false
    return when (myDevice) {
        "this" -> true
        "other" -> false
        else -> ownsMatch(id)
    }
}

fun CrossyDuelStore.ownsMatch(matchID: String): Boolean =
    deviceLedger.owns(matchID, host?.session?.userID, clock().timeIntervalSince1970)

internal fun CrossyDuelStore.noteOwnsMatch(matchID: String) =
    deviceLedger.note(matchID, host?.session?.userID, clock().timeIntervalSince1970)

internal fun CrossyDuelStore.dropOwnership(matchID: String) =
    deviceLedger.drop(matchID, host?.session?.userID, clock().timeIntervalSince1970)

/** 서버가 이 판의 보고·기권을 다른 기기의 것으로 돌려보냈다. 판 루프를 **곧바로** 멈추고, 같은 판은 다시 두지 않는다. */
internal fun CrossyDuelStore.yieldMatchToOtherDevice(matchID: String) {
    val id = matchID.lowercase()
    yieldedMatchIDs = yieldedMatchIDs + id
    dropOwnership(id)
    if (duelMatchID == id || match?.id == id) discardDuel()
    val current = match
    if (current != null && current.id == id && !current.isFinished) {
        if (!playingElsewhere) playingElsewhere = true
        setNotice(CrossyDuelNoticeText.otherDevice)
    }
    refreshPhase()
}
