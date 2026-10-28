// 원본: Sources/CheckCore/GomokuStoreWatch.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.net.gomokuWatch
import com.yehsung.aingcheck.core.net.gomokuWatchLive
import com.yehsung.aingcheck.core.rules.ai.GomokuAIGame
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.GomokuRPCStatus
import com.yehsung.aingcheck.core.wire.games.GomokuWatchResponse
import kotlinx.coroutines.launch
import kotlin.math.abs

// 오목 스토어의 **관전** 갈래(0.3.41) — 남의 진행 중인 판을 읽기 전용으로 본다.
//
// ── 관전은 판만이다 ── 서버 `gomoku_watch` 는 판·수순·남은 시간·두 사람·판돈만 준다(채팅 키 자체가 없다). 이 파일은 `gomoku_state` 를
// **절대 부르지 않는다**. 관전 응답을 `applyState` 로도 넣지 않는다 — 적용 경로는 아래 [applyWatch] 하나다.
// ── 주 스위치(C11) ── `spectatorFeaturesEnabled` 가 꺼져 있으면 진입·조회·폴링이 한 번도 안 돈다. **판돈 깃발(§8-17 #1)과는 무관하다.**
// ── 세대(C13) ── `watchRuntime.watchGeneration` 이 관전 세대다. 세대가 같아도 응답의 `match.id` 가 다르면 버린다(이중 자물쇠).
// ── 창이 안 보이면 요청이 없다(C14) ── 진행 중인 관전은 창을 닫거나 최소화해도 남고 **폴링만** 멈춘다.
// ── 흑·백은 서버만 안다(C15) ── 씨앗은 `faces` 두 얼굴뿐이고 `black`/`white` 는 첫 ok 응답으로만 선다.
// ── 실패 경로(C17) ── PGRST202 는 관전을 내리고 "곧 열려요"; 그 밖은 연속 [GomokuStore.watchFailureLimit] 회까지 씨앗 화면을 유지하다 내린다.
// ── 관전자 수(0.3.65) ── `gomoku_watch_live` 를 먼저 부르고 없으면(PGRST202) 이 로그인 동안 옛 `gomoku_watch` 로 접는다(깃발 겸업 금지).

/** 내 user id(소문자). 세션이 없으면 null. */
val GomokuStore.myUserID: String? get() = host?.session?.userID?.lowercase()

/** 로비 "지금 대결 중" 카드가 내 판인가([관전] 칩 대신 "내 판" 캡션). */
fun GomokuStore.isMine(live: GomokuLiveMatch): Boolean {
    val mine = myUserID ?: return false
    return live.a.id == mine || live.b.id == mine
}

/** 지금 관전 폴링이 돌아야 하는가: 관전 중 + 안 끝남 + 로비 화면 + 주 스위치·창·세션. */
val GomokuStore.shouldPollWatch: Boolean
    get() {
        val watch = spectating ?: return false
        if (watch.isFinished) return false
        return phase == GomokuPhase.lobby && canPollSpectatorFeatures
    }

// MARK: 진입 · 이탈

/**
 * [관전] — 로비 카드의 두 얼굴을 씨앗으로 관전 상태를 세우고, 창이 보이면 곧바로 한 번 읽는다. 내 판이 진행 중(1:1·AI)이거나 결과 화면이면
 * 아무것도 하지 않는다 — 관전 화면은 로비 자리에 선다.
 */
fun GomokuStore.startWatching(matchID: String) {
    val id = matchID.lowercase()
    if (!spectatorFeaturesEnabled || id.isEmpty() || GomokuAIGame.isAIMatchID(id) || host?.session == null) return
    val current = match
    if (current != null && !current.isFinished) return
    if (phase != GomokuPhase.lobby) return
    if (spectating?.id == id) return
    // INV-GomokuStoreWatch-937ab6bc 이식: **문 앞에서 막는다.** 404 뒤 `stopWatching()` 이 `spectating` 을 비우므로 위 재진입 가드가
    // 다시 통과한다 — 화면의 칩만 잠그면 스토어를 직접 부르는 길(딥링크·다른 호출부)이 404 를 무한히 낸다. 잠금은 폴링 주기가 한 번씩 풀어 준다.
    if (watchUnavailable) {
        setNotice(GomokuNoticeText.watchUnavailable)
        return
    }
    val live = liveMatches.firstOrNull { it.id == id }
    // 로비 30초 사이 목록에서 빠진 판을 눌렀다 — 얼굴 없는 같은 로딩 상태로 들어가고 응답이 채운다.
    val seed = if (live != null) GomokuSpectateState(id, faces = listOf(live.a, live.b), stake = live.stake.rawValue) else GomokuSpectateState(id)
    resetWatchRuntime()
    clearWatchNotice()
    spectating = seed
    if (canPollSpectatorFeatures) scope.launch { refreshWatch() }
}

/** 사용자 [나가기]. 관전을 내리고 로비 자리로 돌아오며 목록·받은함·순위를 새로 읽는다. */
fun GomokuStore.leaveWatch() {
    stopWatching()
    if (host?.session == null) return
    scope.launch {
        refreshLobby()
        loadInbox()
        loadRanking()
    }
}

/** 조용히 내린다(요청 없음): 세대를 올려 나가 있던 응답을 버리고 장부를 비운다. */
fun GomokuStore.stopWatching() {
    resetWatchRuntime()
    if (spectating != null) spectating = null
    // 보던 판이 내려갔다 — 남의 관전자 수가 로비·다음 판으로 따라가지 않게 여기서 0 으로 돌린다.
    if (spectatorCount != 0L) spectatorCount = 0
}

/** 세대 올림 + 장부 초기값. 진입·나가기 둘 다 여기를 지난다 — 앞 판의 in-flight 깃발이 남으면 새 판의 첫 조회가 영영 안 나간다. */
private fun GomokuStore.resetWatchRuntime() {
    val runtime = watchRuntime
    runtime.bumpWatchGeneration()
    runtime.watchInFlight = false
    runtime.watchAgain = false
    runtime.watchWantsFull = false
    runtime.watchFailureStreak = 0
    runtime.lastWatchRequestAt = distantPast
}

/** 관전이 남긴 안내(못 보는 판·준비 중·연결)는 새 관전에 들어갈 때 걷는다. 그 밖의 안내(신청 거절·만료)는 건드리지 않는다(C12). */
private fun GomokuStore.clearWatchNotice() {
    val mine = setOf(GomokuNoticeText.watchGone, GomokuNoticeText.watchUnavailable, GomokuNoticeText.checkConnection)
    val current = notice
    if (current != null && current in mine) setNotice(null)
}

// MARK: 조회

/**
 * 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 세대·판 id 두 자물쇠를 지난 응답만 [applyWatch] 로 간다.
 * 창 규칙(보일 때만)은 부르는 쪽이 본다.
 */
suspend fun GomokuStore.refreshWatch() {
    if (!spectatorFeaturesEnabled || host?.session == null) return
    val watched = spectating ?: return
    val runtime = watchRuntime
    if (runtime.watchInFlight) {
        runtime.watchAgain = true
        return
    }
    runtime.watchInFlight = true
    val generation = runtime.watchGeneration
    val resetMark = resetGeneration
    val id = watched.id
    do {
        runtime.watchAgain = false
        // 전체 재요청 표시는 **요청을 띄울 때 본다**(내리는 것은 그것을 실어 온 응답이다).
        val since = if (runtime.watchWantsFull) 0 else (spectating?.appliedSeq ?: 0)
        runtime.lastWatchRequestAt = clock()
        val result = watchFetch(id, since)
        // 세대가 밀렸으면(나가기·판 전환·내 판·로그아웃) 장부는 그쪽이 이미 비웠다 — 여기서는 아무것도 건드리지 않는다.
        if (generation != runtime.watchGeneration || resetMark != resetGeneration) return
        when (result) {
            // 연속 실패는 **판을 실은 ok** 만 끊는다(applyWatch 안에서). 여기서 지우면 status 거절이 매번 0 → 1 로 되돌아간다(W5 실측).
            is CallResult.Success -> applyWatch(result.value, since)
            is CallResult.Failure -> noteWatchFailure(result.error)
            null -> Unit
        }
        // applyWatch·noteWatchFailure 가 관전을 내렸으면 세대가 올랐다 — 그것으로 끝이다.
        if (generation != runtime.watchGeneration) return
    } while (runtime.watchAgain && spectating != null)
    runtime.watchInFlight = false
}

/**
 * 관전 한 번 — `gomoku_watch_live`(관전 + 관전자 수)를 먼저 부르고, 서버에 그 함수가 아직 없으면 옛 `gomoku_watch` 로 **한 번 접어** 같은 바퀴
 * 안에서 다시 부른다. 접힘은 이 로그인 동안 한 번만 판정한다(`spectatorCountUnavailable`).
 * INV-GomokuStoreWatch-3213c61d 이식: 이 실패는 `watchUnavailable`(관전 입구 잠금)도 `watchFailureStreak`(연결 끊김)도 **건드리지 않는다** —
 * 관전은 옛 길로 멀쩡히 돌고 잃는 것은 숫자 한 칸뿐이다(두 사실을 한 깃발에 겸업시키면 [관전] 칩이 통째로 잠긴다).
 */
private suspend fun GomokuStore.watchFetch(matchID: String, sinceSeq: Int): CallResult<GomokuWatchResponse>? {
    if (!spectatorCountUnavailable) {
        val live = perform { service, token -> service.gomokuWatchLive(token, matchID, sinceSeq.toLong()) }
        // null(세대 밀림·세션 없음)과 그 밖의 실패는 **그대로 돌려준다** — 5xx 한 번에 숫자를 영영 끄면 안 된다.
        if (live !is CallResult.Failure || !isSchemaMissing(live.error)) return live
        host.notice(GomokuStore.LOG_TAG, "gomoku_watch_live missing — folding to gomoku_watch")
        spectatorCountUnavailable = true
    }
    return perform { service, token -> service.gomokuWatch(token, matchID, sinceSeq.toLong()) }
}

/** 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다(C13 의 둘째 자물쇠). */
fun GomokuStore.applyWatch(response: GomokuWatchResponse, requestedSince: Int = 0) {
    val current = spectating ?: return
    when (response.status) {
        GomokuRPCStatus.ok -> {
            val row = response.match
            if (row == null) {
                noteWatchFailure(null) // ok 인데 판이 없다 — 모르는 모양은 실패로 센다(연속되면 내린다)
                return
            }
            if (row.id?.lowercase() != current.id) return
            noteServerNow(response.serverNowMs)
            // 관전이 실제로 왔다 — 서버에 함수가 있다. 잠겼던 칩을 여기서 연다(세우는 곳과 내리는 곳을 한 갈래씩만 둔다).
            if (watchUnavailable) watchUnavailable = false
            val status = row.status ?: ""
            if (status != "active" && status != "finished") {
                // 서버 계약상 여기로 못 온다(pending·declined 은 not_found 다). 와도 판이 아니다 — not_found 와 같은 길.
                stopWatching()
                setNotice(GomokuNoticeText.watchGone)
                return
            }
            val inMatch = status == "active"
            // 나 말고 몇 명이 이 판을 보고 있는가. 옛 길로 접힌 세션에는 키가 없어 0. **판이 아닌 응답(위 가드)에는 세우지 않는다.**
            val watchers = nonNegative(response.watchers)
            if (spectatorCount != watchers) spectatorCount = watchers
            // 흑·백은 **여기서만** 선다(C15). 서버 행이 없으면 씨앗 얼굴·로비 목록에서 id 로 빌리고, 그래도 없으면 앞 값.
            val black = peerUser(response.blackUser, working = true, capable = true, inMatch = inMatch)
                ?: knownUser(row.black, current) ?: current.black
            val white = peerUser(response.whiteUser, working = true, capable = true, inMatch = inMatch)
                ?: knownUser(row.white, current) ?: current.white
            val deadline = if (inMatch) deviceDate(row.deadlineMs) else null
            val startedAt = deviceDate(row.startedMs) ?: current.startedAt
            val mapped = gomokuSpectateState(response, current, requestedSince, black, white, deadline, startedAt) ?: return
            val runtime = watchRuntime
            runtime.watchFailureStreak = 0 // 판을 실은 응답 = 연결이 살아 있다(구멍 재요청도 마찬가지)
            if (mapped.second) {
                // 수 번호에 구멍 — 마지막 수·자동 착수 점은 기록에서만 온다. 다음 한 번을 처음부터 받는다.
                runtime.watchWantsFull = true
                runtime.watchAgain = true
                return
            }
            if (requestedSince == 0) runtime.watchWantsFull = false
            if (spectating != mapped.first) spectating = mapped.first
            // 1 이하는 받지 않는다(applyLobby 와 같은 이유).
            val streak = response.autoAbandonStreak
            if (streak != null && streak > 1 && autoAbandonStreak.toLong() != streak) autoAbandonStreak = streak.toInt()
        }
        GomokuRPCStatus.notFound -> {
            // 끝난 지 오래된 판·없는 판·숨김 격리 — 서버는 있다/없다를 가르지 않는다.
            stopWatching()
            setNotice(GomokuNoticeText.watchGone)
        }
        GomokuRPCStatus.unsupportedClient -> {
            // 매 조회가 같은 답이라 폴링을 이어 갈 이유가 없다 — 내리고 업데이트 안내.
            stopWatching()
            setNotice(GomokuNoticeText.updateMine)
        }
        else -> {
            host.notice(GomokuStore.LOG_TAG, "watch refused status=${response.status.rawValue}")
            noteWatchFailure(null) // unauthorized·모르는 status 도 연속이면 내린다 — 빈 판이 영영 돌지 않게
        }
    }
}

/** 판의 두 사람 중 서버 행이 빠진 쪽을 id 로 찾는다: 씨앗 얼굴(로비 카드) → 로비 목록. */
private fun GomokuStore.knownUser(rawID: String?, current: GomokuSpectateState): GomokuUser? {
    val id = rawID?.lowercase()
    if (id.isNullOrEmpty()) return null
    return current.faces.firstOrNull { it.id == id } ?: users.firstOrNull { it.id == id }
}

/** 예외 실패 경로(C17). throw 로 온 실패(PGRST202·5xx·오프라인)와 모르는 응답 모양을 여기서 접는다. */
private fun GomokuStore.noteWatchFailure(error: Throwable?) {
    if (error != null && isSchemaMissing(error)) {
        // 서버에 gomoku_watch 가 아직 없다(앱이 db push 보다 먼저 나간 창).
        stopWatching()
        setNotice(GomokuNoticeText.watchUnavailable)
        // INV-GomokuStoreWatch-059c263c 이식: 관전 입구를 잠그는 신호는 **조건 없이** 세운다 — `gomoku_watch` 가 없다는 직접 증거이고,
        // 순위를 들고 있든 없든 관전은 못 한다. 이 한 줄이 없으면 [관전] 칩이 활성인 채로 남아 누를 때마다 404 를 반복한다(게이트와 신호는 짝).
        if (!watchUnavailable) watchUnavailable = true
        // 순위표까지 함께 접는 것은 **순위를 한 번도 못 받았을 때만**이다 — 순위를 이미 들고 있으면 서버에 gomoku_ranking 이 있다는 증거다.
        if (ranking == null) {
            if (!rankingUnavailable) rankingUnavailable = true
            if (!hasLoadedRanking) hasLoadedRanking = true
        }
        return
    }
    host.notice(GomokuStore.LOG_TAG, "watch request failed")
    val runtime = watchRuntime
    runtime.watchFailureStreak += 1
    if (runtime.watchFailureStreak < GomokuStore.watchFailureLimit) return
    stopWatching()
    setNotice(GomokuNoticeText.checkConnection)
}

// MARK: 폴링 훅 — GomokuStore.pollTick · windowDidShow 가 부른다

/** 안전망 한 걸음: 관전 중이면 2초마다 판, 아니면 로비에서 60초마다 순위. 관전 중엔 순위를 돌리지 않는다. */
suspend fun GomokuStore.pollSpectatorFeatures(now: SwiftDate) {
    if (!canPollSpectatorFeatures || phase != GomokuPhase.lobby) return
    val watch = spectating
    if (watch != null) {
        if (!watch.isFinished && now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= GomokuStore.watchPollSeconds) refreshWatch()
        return
    }
    if (now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= GomokuStore.rankingPollSeconds) {
        // INV-GomokuStoreWatch-b46c13fc 이식: 관전 잠금을 이 주기에 **한 번 풀어 준다.** `watchUnavailable` 은 `startWatching` 을 문 앞에서
        // 막으므로 자기가 자기를 열 수 없다 — 안 풀면 서버가 올라와도 로그아웃까지 잠긴 채 남는다(최악이 "60초에 404 한 번").
        if (watchUnavailable) watchUnavailable = false
        loadRanking()
    }
}

/** 창이 다시 보였다: 관전 중이면 즉시 한 번(C14), 로비면 순위 한 번 — 둘 다 로비 목록과 같은 1초 dedupe. */
fun GomokuStore.spectatorWindowDidShow(now: SwiftDate) {
    if (!canPollSpectatorFeatures || phase != GomokuPhase.lobby) return
    val watch = spectating
    if (watch != null) {
        if (!watch.isFinished && now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= GomokuStore.reloadDedupeSeconds) {
            scope.launch { refreshWatch() }
        }
        return
    }
    if (now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= GomokuStore.reloadDedupeSeconds) scope.launch { loadRanking() }
}

// MARK: 순수 매퍼

private class WatchRecord(val seq: Int, val color: GomokuColor, val point: GomokuPoint?, val auto: Boolean)

/**
 * 응답 → 다음 관전 상태(순수, Swift `GomokuStore.spectateState(applying:to:…)`). `black`/`white`/`deadline`/`startedAt` 은 호출부가 스토어 경계로 만든다.
 * null = 이 판 응답이 아니다. 두 번째 값 = 수 번호에 구멍이 있어 처음부터 다시 받아야 한다(그때 첫 값은 이전 값 그대로).
 */
fun gomokuSpectateState(
    response: GomokuWatchResponse,
    previous: GomokuSpectateState,
    requestedSince: Int,
    black: GomokuUser?,
    white: GomokuUser?,
    deadline: SwiftDate?,
    startedAt: SwiftDate?,
): Pair<GomokuSpectateState, Boolean>? {
    val row = response.match ?: return null
    if (row.id?.lowercase() != previous.id) return null
    val status = row.status ?: ""
    if (status != "active" && status != "finished") return null
    val isFinished = status == "finished"
    val tolerateGaps = requestedSince == 0
    // `auto` 가 없는 응답(옛 서버)은 사람이 둔 수로 읽는다.
    val records = (response.moves ?: emptyList()).mapNotNull { move ->
        val seq = move.seq?.toInt() ?: return@mapNotNull null
        val color = GomokuColor.fromRawValue(move.color ?: "") ?: return@mapNotNull null
        val auto = move.auto ?: false
        if (move.kind == "pass" || move.x == null || move.y == null) return@mapNotNull WatchRecord(seq, color, null, auto)
        val point = GomokuPoint.at(move.x?.toInt() ?: -1, move.y?.toInt() ?: -1) ?: return@mapNotNull null
        WatchRecord(seq, color, point, auto)
    }.sortedBy { it.seq }

    val rebuild = tolerateGaps || records.firstOrNull()?.seq == 1
    var board = if (rebuild) GomokuBoard() else previous.board.copy()
    var lastMove = if (rebuild) null else previous.lastMove
    var applied = if (rebuild) 0 else previous.appliedSeq
    val autoPoints: MutableSet<GomokuPoint> = if (rebuild) LinkedHashSet() else LinkedHashSet(previous.autoPoints)
    var lastMoveWasAuto = if (rebuild) false else previous.lastMoveWasAuto
    for (record in records) {
        if (record.seq <= applied) continue
        if (record.seq != applied + 1 && !tolerateGaps) return previous to true
        val point = record.point
        if (point != null) {
            board[point] = record.color
            lastMove = point
            if (record.auto) autoPoints.add(point) else autoPoints.remove(point)
        }
        lastMoveWasAuto = record.auto
        applied = record.seq
    }
    val serverCount = row.moveCount?.toInt()
    val serverBoard = row.board?.let { GomokuBoard.fromServerString(it) }
    if (serverBoard != null) {
        board = serverBoard // 판 문자열은 서버가 권위다
        if (serverCount != null) applied = serverCount
    } else if (serverCount != null && serverCount != applied) {
        if (!tolerateGaps) return previous to true
        applied = serverCount
    }

    val moveCount = serverCount ?: applied
    val turn = if (isFinished) null else GomokuColor.fromRawValue(row.turn ?: "")
    var nextDeadline = if (isFinished) null else deadline
    val kept = previous.deadline
    val fresh = nextDeadline
    if (kept != null && fresh != null && previous.moveCount == moveCount && previous.turn == turn &&
        abs(fresh.timeIntervalSince(kept)) < GomokuStore.deadlineToleranceSeconds
    ) {
        // 같은 차례를 다시 읽었다 — 보정 오차만큼 다른 마감으로 갈면 창 루트가 2초마다 다시 그려진다.
        nextDeadline = kept
    }
    val winner = when (row.result) {
        "black_win" -> GomokuColor.black
        "white_win" -> GomokuColor.white
        else -> null // 무승부 또는 아직 진행 중
    }
    val next = previous.copy(
        black = black,
        white = white,
        stake = row.stake ?: previous.stake,
        board = board,
        lastMove = lastMove,
        moveCount = moveCount,
        appliedSeq = applied,
        autoPoints = autoPoints.toSet(),
        lastMoveWasAuto = lastMoveWasAuto,
        turn = turn,
        deadline = nextDeadline,
        startedAt = startedAt,
        isFinished = isFinished,
        winner = winner,
        endReason = row.endReason?.let { GomokuEndReason.fromRawValue(it) },
        blackAutoStreak = response.blackAutoStreak?.toInt() ?: previous.blackAutoStreak,
        whiteAutoStreak = response.whiteAutoStreak?.toInt() ?: previous.whiteAutoStreak,
    )
    return next to false
}
