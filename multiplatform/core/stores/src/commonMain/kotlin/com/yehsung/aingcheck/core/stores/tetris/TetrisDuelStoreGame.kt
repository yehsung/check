// 원본: Sources/CheckCore/TetrisDuelStoreGame.swift @ 1b8260d · 한 판 한 기기 절 @ 75c31cd2
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.net.tetrisRanking
import com.yehsung.aingcheck.core.net.tetrisReport
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelBoard
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelReport
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelReportReason
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelResumePoint
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisActionResponse
import com.yehsung.aingcheck.core.wire.games.TetrisPlayerRow
import com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus
import com.yehsung.aingcheck.core.wire.games.TetrisRankingResponse
import com.yehsung.aingcheck.core.wire.games.TetrisReportRequest
import com.yehsung.aingcheck.core.wire.games.TetrisUserRow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject

// 테트리스 대결 스토어의 **판 갈래** — 판 구동기 수명 · 판 루프(D10) · 입력 문 · 보고 루프(§4.1) · 순위.
// 저장 프로퍼티는 본문(TetrisDuelStore.kt)에 있고 여기는 로직만 둔다(Swift extension 그대로 — 같은 모듈 internal 로 닿는다).
//
// ── 보고 루프 한눈에 ──
//   판 루프(창과 무관, 0.05초) ─┐
//   화면 프레임 루프(창이 보일 때) ─┼→ tick(now) → duel.advance → 상대 공격 차분 반영 → 숫자·흐름 → considerReport
//   입력 문(하드드롭)       ─────┘                                                        │
//                         reportReason: 준비 · 탑아웃 · 공격 증가(0.25초 바닥) · 1초 하트비트  │
//                         한 번에 하나(reportInFlight) — 응답이 오면 곧바로 한 번 더 묻는다 ←──┘
//                         3초 넘게 답이 없으면 그 보고를 버리고 새로 낸다(reportStallSeconds · reportTicket)
//   응답(ok/stale) → applyState: 시작 시각(단조 시계로) · 서버 seq 따라잡기 · 상대 판 · 상대 공격 누계 · 정산
//
// INV-TetrisDuelStoreGame-ae16a897 이식: 보고 값은 전부 **누계**다(지운 줄 · 보낸 공격 · 받아들인 공격). 그래서 보고 하나가 사라져도
//   (오프라인 · 멎어서 버림) 다음 보고가 같은 사실을 다시 싣고, 서버 seq 가 늦게 온 옛 보고를 `stale` 로 버린다 — 재전송 큐가 필요 없다.
// INV-TetrisDuelStoreGame-6bd5749a 이식: 앱을 다시 열면 판은 서버가 들고 있는 내 마지막 보고에서 다시 선다(`prepareDuel` ·
//   `resumePoint`) — 빈 판이 아니다. 골든 `duel/resume` 이 Swift 스토어와 같은 재개 판정·판 상태를 잰다.
// ★ 구동기는 **이 기기가 두는 판**에서만 선다(`playsMatch` — 본문 머리말 ⑩ · 아래 '한 판 한 기기' 절). 구동기가 없으면 판 루프 ·
//   준비/보고 · 입력 문이 전부 서지 않는다 — 같은 계정의 다른 기기가 두는 판을 이 기기가 덮어쓰지 않게 하는 한 자리다.

// MARK: - 판 구동기 수명

/**
 * 진행 중 판의 구동기를 준비한다(같은 판이면 그대로 둔다). 시드가 없으면 만들지 않는다 — 서버 계약상 진행 중 판에는
 * 언제나 있지만, 없으면 지어낸 시드로 두 사람의 조각 순서가 갈리는 것보다 판을 못 여는 편이 낫다.
 *
 * 이 프로세스가 이 판을 처음 보는데 서버가 **판 중에 받은 내 보고**를 이미 들고 있으면(앱을 다시 열었다 · 다시 로그인했다)
 * 그 보고에서 판을 다시 세운다(`resumePoint` — 리뷰 RV1). 빈 판에서 다시 시작하면 침묵 판정(15초) 안에 앱을 껐다 켜는 것만으로
 * 거의 찬 판이 비워지고, 받아들인 누계를 0 으로 두면 상대의 공격 이력이 통째로 한 번 더 들어온다.
 */
internal fun TetrisDuelStore.prepareDuel(matchID: String, seed: Long?, me: TetrisPlayerRow?, startAtMs: Double?) {
    if (duel != null && duelMatchID == matchID) return
    discardDuel()
    if (seed == null) {
        logNotice("duel not prepared — active match without seed")
        return
    }
    val point = TetrisDuelStore.resumePoint(me, startAtMs)
    val resumed = point?.let { TetrisDuelSession.resuming(seed, it) }
    if (point != null && resumed != null) {
        logNotice("duel resumed from server row seq=${point.seq} applied=${point.garbageApplied}")
        duel = resumed
    } else {
        // 판 시작 전(준비 · 카운트다운)이거나 판 중 보고가 없다 — 새 판. 받아들인 누계는 그래도 서버 값에서 잇는다.
        duel = TetrisDuelSession(seed, startingSeq = me?.seq?.clampedInt() ?: 0, garbageApplied = me?.garbageApplied?.clampedInt() ?: 0)
    }
    duelMatchID = matchID
}

/**
 * 서버의 내 행이 **판이 시작된 뒤에** 받아 적은 보고면 그 보고를 재개 출발점으로(순수). 아니면 null(새 판으로 연다).
 * 시작 전 보고(준비 · 카운트다운 하트비트)는 빈 판이고 엔진도 아직 안 열렸으므로 이어 받을 것이 없다.
 */
fun TetrisDuelStore.Companion.resumePoint(me: TetrisPlayerRow?, startAtMs: Double?): TetrisDuelResumePoint? {
    if (me == null) return null
    val seq = me.seq?.clampedInt() ?: return null
    if (seq <= 0) return null
    val board = me.board ?: return null
    if (!TetrisDuelBoard.isValid(board)) return null
    if (startAtMs == null) return null
    val lastSeenMs = me.lastSeenMs ?: return null
    if (!startAtMs.isFinite() || !lastSeenMs.isFinite() || !(lastSeenMs > startAtMs)) return null
    return TetrisDuelResumePoint(
        seq = seq, board = board, lines = me.lines?.clampedInt() ?: 0, garbageSent = me.garbageSent?.clampedInt() ?: 0,
        garbageApplied = me.garbageApplied?.clampedInt() ?: 0, pending = me.pending?.clampedInt() ?: 0,
        elapsedSeconds = (lastSeenMs - startAtMs) / 1000,
    )
}

/** 구동기를 버린다(판 루프를 멈추고, 나가 있는 보고의 응답은 세대로 버려진다 — 요청 자체는 끊지 않는다). */
internal fun TetrisDuelStore.discardDuel() {
    stopGameLoop()
    duelGeneration += 1
    reportInFlight = false
    reportSentAt = null
    reportFailureStreak = 0
    duel = null
    duelMatchID = null
    if (connectionTrouble) connectionTrouble = false
}

// MARK: - 판 루프 (D10 — 창과 무관하게 흐른다)

internal fun TetrisDuelStore.startGameLoop() {
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

internal fun TetrisDuelStore.stopGameLoop() {
    gameLoopToken += 1
    gameLoopJob?.cancel()
    gameLoopJob = null
}

/**
 * 판을 지금(단조 시계)까지 밀고, 숫자·흐름을 맞추고, 보고할 때면 보고한다.
 * 판 루프와 화면 프레임 루프가 함께 부른다 — 같은 시각이면 아무 일도 안 한다(따라잡기라 부르는 간격과 무관하게 같은 판이다).
 */
fun TetrisDuelStore.tick(now: Double? = null) {
    val session = duel ?: return
    val instant = now ?: uptime()
    session.advance(instant)
    // 판 시작 전에 온 상대 공격은 구동기가 받지 않는다 — 시작한 뒤 첫 걸음에서 누계 차분으로 들어간다(멱등).
    session.absorbOpponentAttack(opponentAttackTotal)
    syncStats()
    refreshPhase()
    considerReport(instant)
}

/** 화면 흐름을 판 상태에서 다시 낸다(값이 같으면 쓰지 않는다 — 관찰자를 헛되게 깨우지 않게). */
fun TetrisDuelStore.refreshPhase() {
    val current = match
    val session = duel
    val next = when {
        current == null -> TetrisDuelPhase.lobby
        current.isFinished -> TetrisDuelPhase.finished
        session != null && duelMatchID == current.id && session.startAt != null ->
            if (session.started) TetrisDuelPhase.playing else TetrisDuelPhase.countdown
        else -> TetrisDuelPhase.ready
    }
    if (phase != next) phase = next
}

/** 관찰 가능한 숫자를 구동기에서 다시 낸다(조각이 굳을 때만 실제로 바뀐다). */
fun TetrisDuelStore.syncStats() {
    val next = duel?.let { session ->
        val game = session.game
        TetrisDuelMyStats(
            lines = game.lines, attackSent = game.attackSentTotal, pendingGarbage = game.pendingGarbageLines,
            levelFloor = session.currentLevelFloor, toppedOut = session.toppedOut,
        )
    }
    if (myStats != next) myStats = next
}

// MARK: - 시각 (화면 프레임 루프가 부르는 순수 조회)

/** 판 경과초(단조 시계). 시작 시각을 모르면 null, 카운트다운 중이면 음수. */
fun TetrisDuelStore.matchElapsedSeconds(now: Double? = null): Double? = duel?.matchElapsed(now ?: uptime())

/** 카운트다운 남은 초(시작 시각을 모르면 null, 시작했으면 0). */
fun TetrisDuelStore.countdownSeconds(now: Double? = null): Double? = duel?.countdownRemaining(now ?: uptime())

/** 상대의 마지막 보고 뒤 흐른 초(서버 시각 보정). 모르면 null. */
fun TetrisDuelStore.opponentSilenceSeconds(now: SwiftDate? = null): Double? =
    opponentLastSeenAt?.let { maxOf(0.0, (now ?: clock()).timeIntervalSince(it)) }

// MARK: - 입력 문 (제스처·버튼이 부른다)
//
// 넣기 **전에** 판을 지금까지 민다 — 판 루프가 0.05초마다 돌므로 그 사이에 누른 키가 한 걸음 앞 시각의 판에
// 들어가지 않게 한다. 살아 있지 않은 판(시작 전·탑아웃 뒤·정산 뒤)에서는 구동기가 누름을 버리고 뗌만 받는다.

fun TetrisDuelStore.setLeftHeld(held: Boolean) {
    advanceToNow()
    duel?.setLeftHeld(held)
}

fun TetrisDuelStore.setRightHeld(held: Boolean) {
    advanceToNow()
    duel?.setRightHeld(held)
}

fun TetrisDuelStore.setSoftDropHeld(held: Boolean) {
    advanceToNow()
    duel?.setSoftDropHeld(held)
}

fun TetrisDuelStore.rotate(clockwise: Boolean) {
    advanceToNow()
    duel?.rotate(clockwise)
}

/**
 * 가로·세로 **한 칸**(폰 제스처·보이스오버). 굳힘이 없으므로 보고를 재촉하지 않는다 — 다음 하트비트(1초)나
 * 하드드롭이 싣는다. 보고 값은 전부 누계라 한 칸 이동이 따로 실릴 필요가 없다.
 */
fun TetrisDuelStore.moveLeftOneCell() {
    advanceToNow()
    duel?.moveLeftOneCell()
}

fun TetrisDuelStore.moveRightOneCell() {
    advanceToNow()
    duel?.moveRightOneCell()
}

fun TetrisDuelStore.softDropOneCell(): Boolean {
    advanceToNow()
    return duel?.softDropOneCell() ?: false
}

fun TetrisDuelStore.hold() {
    advanceToNow()
    duel?.hold()
}

/** 하드드롭 — 굳힘이 곧 줄 지우기·공격이므로 보고를 곧바로 묻는다(최소 간격 0.25초는 구동기가 지킨다). */
fun TetrisDuelStore.hardDrop() {
    advanceToNow()
    duel?.hardDrop()
    syncStats()
    considerReport(uptime())
}

/** 눌린 키를 전부 놓는다(창 숨김·가림·닫힘 · 앱이 내려갔을 때). */
fun TetrisDuelStore.releaseAllKeys() {
    duel?.releaseAllKeys()
}

private fun TetrisDuelStore.advanceToNow() {
    val session = duel ?: return
    session.advance(uptime())
}

// MARK: - 보고 루프

/**
 * 보고할 때면 한 벌을 만들어 보낸다. 한 번에 하나만 나간다(응답이 오면 곧바로 다시 묻는다).
 * 나가 있는 보고가 [TetrisDuelStore.reportStallSeconds] 넘게 답이 없으면 버리고 새로 낸다(리뷰 RV2 — 멎은 요청 하나가 하트비트를
 * 15초 막으면 서버가 연결 끊김 패로 닫는다).
 */
internal fun TetrisDuelStore.considerReport(now: Double) {
    val sentAt = reportSentAt
    if (reportInFlight && sentAt != null && now - sentAt >= TetrisDuelStore.reportStallSeconds) {
        abandonStalledReport(sentAt, now)
    }
    val current = match ?: return
    val session = duel ?: return
    if (reportInFlight || current.isFinished || duelMatchID != current.id || host?.session == null) return
    // 준비(첫 보고)는 창이 화면에 떠 있을 때만(머리말 ⑨). 서버가 이미 준비를 받았으면(앱을 다시 열었다) 묻지 않는다.
    if (session.lastReportAt == null && !current.meReady && !isWindowVisible) return
    val reason = session.reportReason(now) ?: return
    val report = session.makeReport(now)
    sendReport(report, reason, current.id, now)
}

/**
 * 멎은 보고를 놓는다. 요청은 끊지 않는다(세션 재시도·토큰 갱신 경로를 취소로 건드리지 않게) — 그 답은 표가 바뀌어 버려지고,
 * 서버에 늦게 닿아도 seq 가 더 큰 다음 보고 앞에서 stale 이다. 실패 한 번으로 세어 두 번 연달아면 "연결 확인 중" 이 뜬다.
 */
private fun TetrisDuelStore.abandonStalledReport(sentAt: Double, now: Double) {
    reportTicket += 1
    reportInFlight = false
    reportSentAt = null
    reportFailureStreak += 1
    if (reportFailureStreak >= TetrisDuelStore.reportFailureLimit && !connectionTrouble) connectionTrouble = true
    logNotice("report stalled ${now - sentAt}s — abandoned streak=$reportFailureStreak")
}

private fun TetrisDuelStore.sendReport(report: TetrisDuelReport, reason: TetrisDuelReportReason, matchID: String, now: Double) {
    reportInFlight = true
    reportSentAt = now
    reportTicket += 1
    val ticket = reportTicket
    val token = duelGeneration
    if (reason != TetrisDuelReportReason.heartbeat) logNotice("report reason=$reason seq=${report.seq}")
    val request = TetrisReportRequest(
        pMatchId = matchID, pSeq = report.seq.toLong(), pBoard = report.board, pLines = report.lines.toLong(),
        pGarbageSent = report.garbageSent.toLong(), pGarbageApplied = report.garbageApplied.toLong(),
        pPending = report.pending.toLong(), pToppedOut = report.toppedOut,
    )
    reportJob = scope.launch {
        val result = perform { service, accessToken -> service.tetrisReport(accessToken, request) }
        val receivedAt = uptime()
        // 판이 바뀌었다(접기 · 로그아웃 · 다른 판) — 이 응답은 지금 판의 것이 아니다.
        if (token != duelGeneration) return@launch
        // 멎어서 버린 보고의 늦은 답이다 — 그 뒤에 낸 보고가 자리를 쥐고 있다(그 답이 같은 사실을 더 새로 싣는다).
        if (ticket != reportTicket) return@launch
        reportInFlight = false
        reportSentAt = null
        if (result == null) return@launch
        applyReportResult(result, matchID, receivedAt)
        // 왕복 사이에 공격이 늘었거나 탑아웃했다 — 다음 판 루프 걸음을 기다리지 않는다.
        considerReport(uptime())
    }
}

/** 보고 응답 하나를 옮긴다. `ok`·`stale` 둘 다 상태를 싣는다 — stale 은 "쓰지 않았다" 일 뿐 상태는 사실이다. */
fun TetrisDuelStore.applyReportResult(result: DuelCall<TetrisActionResponse>, matchID: String, receivedAt: Double) {
    when (result) {
        is DuelCall.Failure -> {
            reportFailureStreak += 1
            if (reportFailureStreak >= TetrisDuelStore.reportFailureLimit && !connectionTrouble) connectionTrouble = true
            if (isSchemaMissing(result.error)) noteServerMissing()
            logNotice("report failed streak=$reportFailureStreak")
        }
        is DuelCall.Success -> {
            val response = result.value
            reportFailureStreak = 0
            if (connectionTrouble) connectionTrouble = false
            noteServerNow(response.serverNowMs)
            when (response.status) {
                TetrisRPCStatus.ok, TetrisRPCStatus.stale -> response.state?.let { applyState(it, receivedAt) }
                TetrisRPCStatus.otherDevice -> {
                    // 이 판은 같은 계정의 다른 기기가 둔다(서버가 쓰지도 정산하지도 않았다 — 머리말 ⑩). 곧바로 물러난다:
                    // 판 루프를 멈추고 구동기를 버리고 '이 기기가 연 판' 기록을 지운다. 실려 온 상태는 그다음에 옮긴다
                    // (물러난 판이라 그 상태가 my_device 'this' 를 말해도 구동기를 다시 세우지 않는다).
                    logNotice("report refused — another device plays this match")
                    yieldMatchToOtherDevice(matchID)
                    response.state?.let { applyState(it, receivedAt) }
                }
                TetrisRPCStatus.notFound -> {
                    // 판이 사라졌다(계정 삭제의 cascade 등) — 그 판을 내린다.
                    if (match?.id == matchID) {
                        clearMatch()
                        setNotice(TetrisDuelNoticeText.finishedMatch)
                    }
                }
                TetrisRPCStatus.unsupportedClient -> noteUpdateRequired()
                TetrisRPCStatus.notSignedIn -> setNotice(TetrisDuelNoticeText.signInAgain)
                else -> logNotice("report refused status=${response.status.rawValue}")
            }
        }
    }
}

// MARK: - 한 판 한 기기 (머리말 ⑩ · 서버 20261103124000)
//
// 초인종은 사람의 모든 기기로 간다. 판을 두는 기기는 **하나**다 — 그 판을 연 기기(신청을 보냈다 · 수락했다).
// 서버가 `my_device` 로 말하면 그 말이 권위이고, 옛 서버(말이 없다)에서는 이 기기의 기록이 가른다.

/**
 * 이 기기가 이 판을 **두는가**(순수 판정 — 기록을 맞추는 일은 `applyState` 가 한다).
 *  · 서버가 `other_device` 로 돌려보내 물러난 판이면 아니다(서버가 다시 'this' 라 해도 — [TetrisDuelStore.yieldedMatchIDs]).
 *  · 서버 `my_device` 가 'this' 면 둔다 · 'other' 면 안 둔다.
 *  · 말이 없으면(옛 서버 · 기록 없는 판 · 세션 없는 토큰) 이 기기가 그 판을 열었는가([ownsMatch]).
 */
fun TetrisDuelStore.playsMatch(matchID: String, myDevice: String?): Boolean {
    val id = matchID.lowercase()
    if (id in yieldedMatchIDs) return false
    return when (myDevice) {
        "this" -> true
        "other" -> false
        else -> ownsMatch(id)
    }
}

/** 이 기기가 이 판을 열었다는 기록이 있는가(지금 로그인한 사람의 기록만 — 로그인 전이면 언제나 아니다). */
fun TetrisDuelStore.ownsMatch(matchID: String): Boolean = ownedMatches()[matchID.lowercase()] != null

/** 이 기기가 이 판을 열었다(신청 ok · 수락 ok · 서버가 'this' 라 했다). 이미 있으면 그대로 둔다(처음 시각 유지). */
internal fun TetrisDuelStore.noteOwnsMatch(matchID: String) {
    val id = matchID.lowercase()
    val owned = ownedMatches().toMutableMap()
    if (owned[id] != null) return
    owned[id] = clock().timeIntervalSince1970
    storeOwnedMatches(owned)
}

/** 이 판의 기록을 지운다(끝났다 · 거절·만료 · 서버가 'other' 라 했다 · 물러났다). 없으면 아무것도 안 쓴다. */
internal fun TetrisDuelStore.dropOwnership(matchID: String) {
    val owned = ownedMatches().toMutableMap()
    if (owned.remove(matchID.lowercase()) == null) return
    storeOwnedMatches(owned)
}

/**
 * 서버가 이 판의 보고·기권을 다른 기기의 것으로 돌려보냈다(`other_device`). 판 루프를 **곧바로** 멈추고 구동기를 버리고
 * 기록을 지우고, 같은 판은 다시 두지 않는다. 판 상태는 남겨 화면이 안내 한 줄을 그린다.
 */
internal fun TetrisDuelStore.yieldMatchToOtherDevice(matchID: String) {
    val id = matchID.lowercase()
    yieldedMatchIDs = yieldedMatchIDs + id
    dropOwnership(id)
    if (duelMatchID == id || match?.id == id) discardDuel()
    val current = match
    if (current != null && current.id == id && !current.isFinished) {
        if (!playingElsewhere) playingElsewhere = true
        setNotice(TetrisDuelNoticeText.otherDevice)
    }
    refreshPhase()
    syncStats()
}

/**
 * 지금 로그인한 사람의 기록(유효 기간 안의 것만). 로그인 전이면 빈 표.
 * Kotlin 이식: [KeyValueStore] 에는 사전 칸이 없어 `{판 id: epoch 초}` JSON 글자 한 칸으로 둔다(깨진 글자는 빈 표 — 기록이 없는 것과 같다).
 */
private fun TetrisDuelStore.ownedMatches(): Map<String, Double> {
    val user = host?.session?.userID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return emptyMap()
    val store = defaults
    val raw: Map<String, Double> = if (store != null) decodeOwnedMatches(store.getString(TetrisDuelStore.ownedMatchesKey(user))) else ownedMatchesInMemory[user] ?: emptyMap()
    val cutoff = clock().timeIntervalSince1970 - TetrisDuelStore.ownedMatchTTLSeconds
    return raw.filterValues { it >= cutoff }
}

/** 기록을 쓴다 — 새것부터 [TetrisDuelStore.ownedMatchLimit] 개만(유효 기간이 지난 것은 [ownedMatches] 가 이미 걸렀다). */
private fun TetrisDuelStore.storeOwnedMatches(owned: Map<String, Double>) {
    val user = host?.session?.userID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return
    val kept = owned.entries.sortedByDescending { it.value }.take(TetrisDuelStore.ownedMatchLimit).associate { it.key to it.value }
    val store = defaults
    if (store != null) {
        val key = TetrisDuelStore.ownedMatchesKey(user)
        if (kept.isEmpty()) store.remove(key) else store.putString(key, JsonObject(kept.mapValues { JsonPrimitive(it.value) }).toString())
    } else {
        if (kept.isEmpty()) ownedMatchesInMemory.remove(user) else ownedMatchesInMemory[user] = kept
    }
}

private fun decodeOwnedMatches(text: String?): Map<String, Double> {
    if (text.isNullOrEmpty()) return emptyMap()
    val obj = try {
        Json.parseToJsonElement(text).jsonObject
    } catch (e: IllegalArgumentException) {
        return emptyMap()
    }
    return obj.entries.mapNotNull { (key, value) ->
        val seconds = (value as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null
        key to seconds
    }.toMap()
}

// MARK: - 순위

/**
 * 순위표 한 번. 도는 중이면 **합치지 않고 버린다**(60초 주기 목록이라 뒤따르는 한 번이 필요 없다).
 * 실패는 안내줄로 새지 않는다 — 판 상태줄을 가린다. 깃발만 세우고 들고 있던 목록은 지우지 않는다.
 */
suspend fun TetrisDuelStore.loadRanking() {
    if (!rankingEnabled || host?.session == null || rankingInFlight) return
    rankingInFlight = true
    val generation = resetGeneration
    try {
        lastRankingRequestAt = clock()
        val result = perform { service, token -> service.tetrisRanking(token) } ?: return
        when (result) {
            is DuelCall.Success -> applyRanking(result.value)
            is DuelCall.Failure -> {
                if (isSchemaMissing(result.error)) {
                    if (!rankingUnavailable) rankingUnavailable = true
                    if (rankingLoadFailed) rankingLoadFailed = false
                    if (!hasLoadedRanking) hasLoadedRanking = true
                } else if (!rankingLoadFailed) {
                    rankingLoadFailed = true
                }
            }
        }
    } finally {
        if (generation == resetGeneration) rankingInFlight = false
    }
}

fun TetrisDuelStore.applyRanking(response: TetrisRankingResponse) {
    if (response.status != TetrisRPCStatus.ok) {
        logNotice("ranking refused status=${response.status.rawValue}")
        if (!rankingLoadFailed) rankingLoadFailed = true
        return
    }
    noteServerNow(response.serverNowMs)
    if (rankingLoadFailed) rankingLoadFailed = false
    if (rankingUnavailable) rankingUnavailable = false
    if (!hasLoadedRanking) hasLoadedRanking = true
    val board = TetrisDuelStore.rankingBoard(response)
    if (ranking != board) ranking = board
}

/** 순위 탭을 열었다 등(60초 스로틀). */
fun TetrisDuelStore.refreshRankingIfStale() {
    if (!rankingEnabled || host?.session == null) return
    if (clock().timeIntervalSince(lastRankingRequestAt) < TetrisDuelStore.rankingPollSeconds) return
    scope.launch { loadRanking() }
}

/** 내 판이 끝났다 — 전적이 바뀐 순간 순위도 다시 읽는다(창이 안 보여도 사건에 대한 한 번). */
internal fun TetrisDuelStore.noteOwnMatchFinishedForRanking() {
    lastRankingRequestAt = DISTANT_PAST
    if (!rankingEnabled || host?.session == null) return
    scope.launch { loadRanking() }
}

/** 응답 → 순위표(순수). **행 순서는 입력 그대로**. id 나 rank 가 빠진 행은 싣지 않는다. */
fun TetrisDuelStore.Companion.rankingBoard(response: TetrisRankingResponse): TetrisDuelRankingBoard {
    val entries = (response.rows ?: emptyList()).mapNotNull { row ->
        val rank = row.rank?.clampedInt() ?: return@mapNotNull null
        val user = user(TetrisUserRow(id = row.id, displayName = row.displayName, avatarUrl = row.avatarUrl, character = row.character))
            ?: return@mapNotNull null
        val wins = row.wins?.clampedInt() ?: 0
        val losses = row.losses?.clampedInt() ?: 0
        TetrisDuelRankEntry(
            id = user.id, rank = rank, user = user, wins = wins, losses = losses,
            draws = row.draws?.clampedInt() ?: 0, points = row.points?.clampedInt() ?: (wins - losses),
        )
    }
    val mine = response.me?.let { me ->
        val wins = me.wins?.clampedInt() ?: 0
        val losses = me.losses?.clampedInt() ?: 0
        TetrisDuelMyRank(
            rank = me.rank?.clampedInt(), wins = wins, losses = losses, draws = me.draws?.clampedInt() ?: 0,
            points = me.points?.clampedInt() ?: (wins - losses),
        )
    }
    val since = response.recordSinceMs?.let { if (it > 0) SwiftDate(it / 1000) else null }
    return TetrisDuelRankingBoard(entries = entries, me = mine, recordSince = since)
}
