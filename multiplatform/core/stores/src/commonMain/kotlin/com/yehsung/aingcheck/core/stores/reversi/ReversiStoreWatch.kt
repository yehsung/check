// 원본: Sources/CheckCore/ReversiStoreWatch.swift:80-457(관전 장부 · 진입·이탈 · 조회 · 폴링 훅 · 순수 매퍼) ·
//       Sources/CheckCore/ReversiStoreRanking.swift:59-141(순위 조회 · 매퍼) @ 12624739
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.net.reversiRanking
import com.yehsung.aingcheck.core.net.reversiWatch
import com.yehsung.aingcheck.core.net.reversiWatchLive
import com.yehsung.aingcheck.core.rules.ai.ReversiAIGame
import com.yehsung.aingcheck.core.rules.reversi.ReversiFlipAnimation
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.stores.gomoku.CallResult
import com.yehsung.aingcheck.core.stores.gomoku.distantPast
import com.yehsung.aingcheck.core.stores.gomoku.isSchemaMissing
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiRPCStatus
import com.yehsung.aingcheck.core.wire.games.ReversiRankingResponse
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload

// 아잉 뒤집기 관전 · 순위 — 스토어 확장. 틀은 체스 `ChessStoreWatch`·`ChessStoreRanking`: 관전 2초 폴링 · 관전 세대 · watch_live 가 없으면
// watch 로 한 번 접기(`spectatorCountUnavailable`) · watch 도 없으면 `watchUnavailable`(관전 잠금은 이 깃발 하나로만) · 순위 60초 주기 ·
// 창 보일 때 한 번 · 내 판 끝난 순간 한 번. 관전은 phase 가 아니라 로비 안의 `spectating != null` 로 갈린다. 내 판이 서면 관전은 내려간다.
// **관전·순위는 부르는 사람의 능력을 보지 않는다**(서버 사실 ⑤) — 서버 `reversi_android_min_build` 가 닫혀 있어도 이 갈래는 돈다.

/**
 * 관전·순위 갈래의 관찰 대상이 아닌 장부. 이름이 `reset` 이 아니라 [clear] 인 까닭: 소스 계약 시험이 한 파일에서 `fun reset()` 의 **첫 등장**을
 * 스토어 것으로 잡는다(Swift 머리말 그대로).
 */
class ReversiWatchRuntime {
    var lastWatchRequestAt: SwiftDate = distantPast
    var watchInFlight: Boolean = false
    /** 조회 중에 또 조회할 이유가 생겼다 — 끝나면 한 번 더 돈다. */
    var watchAgain: Boolean = false
    /** 다음 조회 한 번을 `p_since_seq = 0` 으로 띄운다(수 번호에 구멍이 났다). 내리는 것은 **그 전체를 실어 온 응답**이다. */
    var watchWantsFull: Boolean = false
    var watchGeneration: Int = 0
        private set
    /** 연속 실패 횟수(throw 경로 — 5xx·오프라인). 문턱을 넘으면 관전을 내리고 안내 한 줄을 남긴다. */
    var watchFailureStreak: Int = 0
    var lastRankingRequestAt: SwiftDate = distantPast
    var rankingInFlight: Boolean = false

    fun bumpWatchGeneration(): Int {
        watchGeneration += 1
        return watchGeneration
    }

    /** 전부 초기값 + 세대 한 번 올림(로그아웃·계정 전환 — 앞 계정의 늦은 응답을 버린다). */
    fun clear() {
        lastWatchRequestAt = distantPast
        watchInFlight = false
        watchAgain = false
        watchWantsFull = false
        watchFailureStreak = 0
        lastRankingRequestAt = distantPast
        rankingInFlight = false
        bumpWatchGeneration()
    }
}

// MARK: 읽기

/** 내 user id(소문자). 세션이 없으면 null. */
val ReversiStore.myUserID: String? get() = host?.session?.userID?.lowercase()

/** 로비 "지금 대결 중" 카드가 내 판인가([관전] 칩 대신 "내 판" 캡션). */
fun ReversiStore.isMine(live: ReversiLiveMatch): Boolean {
    val mine = myUserID ?: return false
    return live.a.id == mine || live.b.id == mine
}

/** 관전 조회가 **지금** 나가도 되는가 — 관전 스위치 + 창이 보이고 안 가려짐 + 세션. */
val ReversiStore.canPollSpectatorFeatures: Boolean
    get() = spectatorFeaturesEnabled && isWindowVisible && !isWindowOccluded && host?.session != null

/** 순위 조회가 **지금** 나가도 되는가 — 순위 스위치(관전과 **따로**) + 창 + 세션. */
val ReversiStore.canPollRanking: Boolean
    get() = rankingEnabled && isWindowVisible && !isWindowOccluded && host?.session != null

/** 지금 관전 폴링이 돌아야 하는가: 관전 중 + 안 끝남 + 로비 화면 + 스위치·창·세션. */
val ReversiStore.shouldPollWatch: Boolean
    get() {
        val watch = spectating ?: return false
        if (watch.isFinished) return false
        return phase == ReversiPhase.lobby && canPollSpectatorFeatures
    }

val ReversiStore.isSpectating: Boolean get() = spectating != null

// MARK: 진입 · 이탈

/**
 * 로비 "지금 대결 중" 줄의 [관전]. 로비 카드의 두 얼굴을 씨앗으로 관전 상태를 세우고, 창이 보이면 곧바로 한 번 읽는다. 내 판이 진행 중(1:1·AI)이거나
 * 결과 화면이면 아무것도 하지 않는다. 누른 줄이 **내 판**(진행 판 id · 줄에 내가 있다)이면 관전 대신 그 판을 읽어 연다.
 */
fun ReversiStore.startWatching(matchID: String) {
    val id = matchID.lowercase()
    if (!spectatorFeaturesEnabled || id.isEmpty() || ReversiAIGame.isAIMatchID(id) || host?.session == null) return
    val current = match
    if (current != null && !current.isFinished) return
    if (phase != ReversiPhase.lobby) return
    // ★ 내 판이다 — 입력 없는 관전 화면이 아니라 **내 판**을 다시 읽어 연다(관전 생존 신호도 안 보낸다).
    val listedAsMine = liveMatches.firstOrNull { it.id == id }?.let { isMine(it) } ?: false
    if (id == activeMatchID || listedAsMine) {
        launch { refreshMatch(id) }
        return
    }
    if (spectating?.id == id) return
    // ★ 문 앞에서 막는다 — 404 뒤 `stopWatching()` 이 비우므로 재진입 가드가 다시 통과한다. 잠금은 순위 주기가 풀어 준다.
    if (watchUnavailable) {
        setNotice(ReversiNoticeText.unavailable)
        return
    }
    val live = liveMatches.firstOrNull { it.id == id }
    // 로비 30초 사이 목록에서 빠진 판을 눌렀다 — 얼굴 없는 같은 로딩 상태로 들어가고 응답이 채운다.
    val seed = if (live != null) ReversiSpectating(id = id, faces = listOf(live.a, live.b), stake = live.stake, startedAt = live.startedAt) else ReversiSpectating(id = id)
    resetWatchRuntime()
    clearWatchNotice()
    spectating = seed
    if (canPollSpectatorFeatures) launch { refreshWatch() }
}

/** 관전 화면의 [나가기](로비로). 관전을 내리고 목록·순위를 새로 읽는다. */
fun ReversiStore.leaveWatch() {
    stopWatching()
    if (host?.session == null) return
    launch {
        refreshLobby()
        refreshRanking()
    }
}

/** 화면 떠남·초기화로 관전을 조용히 내린다(문구·요청 없음). 세대를 올려 나가 있던 응답을 버린다. */
fun ReversiStore.stopWatching() {
    resetWatchRuntime()
    if (spectating != null) spectating = null
    if (spectatorCount != 0) spectatorCount = 0
    val current = flip
    if (current != null && current.matchID != match?.id) clearFlip()
}

/** 세대 올림 + 장부 초기값. 앞 판의 in-flight 깃발이 남으면 새 판의 첫 조회가 "도는 중" 으로 합쳐져 영영 안 나간다. */
private fun ReversiStore.resetWatchRuntime() {
    val runtime = watchRuntime
    runtime.bumpWatchGeneration()
    runtime.watchInFlight = false
    runtime.watchAgain = false
    runtime.watchWantsFull = false
    runtime.watchFailureStreak = 0
    runtime.lastWatchRequestAt = distantPast
}

/** 관전이 남긴 안내(못 보는 판·준비 중·연결)는 새 관전에 들어갈 때 걷는다. */
private fun ReversiStore.clearWatchNotice() {
    val mine = setOf(ReversiNoticeText.watchGone, ReversiNoticeText.unavailable, ReversiNoticeText.checkConnection)
    if (notice in mine) setNotice(null)
}

// MARK: 조회

/**
 * 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 세대·판 id 두 자물쇠를 지난 응답만 [applyWatch] 로.
 * ★ `watchInFlight` 는 **finally 에서** 내린다(판 7 검토 S-F2). 폴링 한 걸음([pollSpectatorFeatures])은 이 함수를 폴링 작업 안에서 부르므로, 앱이 뒤로 가는
 *   순간 `stopPolling` 의 취소가 날던 조회에 닿으면 `performDuelCall` 이 취소를 다시 던진다 — 그때 깃발이 참으로 남으면 앞으로 돌아와도 모든 관전 조회가
 *   '도는 중'으로 합쳐져 영영 안 나간다(Swift 는 취소가 `perform` 에서 nil 로 접혀 루프 끝에서 내려간다). 세대가 밀렸으면 장부는 그쪽이 이미 비웠고 새 관전의
 *   깃발일 수 있으니 건드리지 않는다.
 */
suspend fun ReversiStore.refreshWatch() {
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
    try {
        do {
            runtime.watchAgain = false
            val since = if (runtime.watchWantsFull) 0 else (spectating?.appliedSeq ?: 0)
            runtime.lastWatchRequestAt = clock()
            val result = watchFetch(id, since)
            // 세대가 밀렸으면(나가기·판 전환·내 판·로그아웃) 장부는 그쪽이 이미 비웠다 — 아무것도 건드리지 않는다.
            if (generation != runtime.watchGeneration || resetMark != resetGeneration) return
            when (result) {
                is CallResult.Success -> applyWatch(result.value, since)
                is CallResult.Failure -> noteWatchFailure(result.error)
                null -> Unit
            }
            if (generation != runtime.watchGeneration) return
        } while (runtime.watchAgain && spectating != null)
    } finally {
        if (generation == runtime.watchGeneration && resetMark == resetGeneration) runtime.watchInFlight = false
    }
}

/**
 * 관전 한 번 — `reversi_watch_live`(관전 + 관전자 수)를 먼저 부르고, 서버에 그 함수가 아직 없으면 `reversi_watch` 로 **한 번 접어** 같은 바퀴 안에서
 * 다시 부른다. ★ 이 실패는 `watchUnavailable`(관전 입구 잠금)도 연속 실패도 **건드리지 않는다** — 잃는 것은 숫자 한 칸뿐이다.
 */
private suspend fun ReversiStore.watchFetch(matchID: String, sinceSeq: Int): CallResult<ReversiActionResponse>? {
    if (!spectatorCountUnavailable) {
        val live = perform { service, token -> service.reversiWatchLive(token, matchID, sinceSeq.toLong()) }
        if (live !is CallResult.Failure || !isSchemaMissing(live.error)) return live
        log("reversi_watch_live missing — folding to reversi_watch")
        spectatorCountUnavailable = true
    }
    return perform { service, token -> service.reversiWatch(token, matchID, sinceSeq.toLong()) }
}

/** 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다(둘째 자물쇠). */
fun ReversiStore.applyWatch(response: ReversiActionResponse, requestedSince: Int = 0) {
    val current = spectating ?: return
    when (response.status) {
        ReversiRPCStatus.ok -> {
            val payload = response.state
            val row = payload?.match
            if (payload == null || row == null) {
                noteWatchFailure(null) // ok 인데 판이 없다 — 모르는 모양은 실패로 센다(연속되면 내린다)
                return
            }
            if (row.id?.lowercase() != current.id) return
            noteServerNow(payload.serverNowMs)
            // 관전이 실제로 왔다 — 서버에 함수가 있다. 잠겼던 칩을 여기서 연다.
            if (watchUnavailable) watchUnavailable = false
            val status = row.matchStatus
            if (status != ReversiMatchStatus.active && status != ReversiMatchStatus.finished) {
                // 서버 계약상 여기로 못 온다(pending 은 not_found 다). 와도 판이 아니다 — not_found 와 같은 길.
                stopWatching()
                setNotice(ReversiNoticeText.watchGone)
                return
            }
            val inMatch = status == ReversiMatchStatus.active
            val black = playerUser(payload.blackUser, inMatch) ?: knownUser(row.black, current) ?: current.blackUser
            val white = playerUser(payload.whiteUser, inMatch) ?: knownUser(row.white, current) ?: current.whiteUser
            val turnStartedAt = deviceDate(row.turnStartedMs)
            val deadline = deviceDate(row.deadlineMs) ?: turnStartedAt?.addingTimeInterval(turnSeconds.toDouble())
            val startedAt = deviceDate(row.startedMs) ?: current.startedAt
            val mapped = spectateState(payload, current, requestedSince, black, white, turnStartedAt, deadline, startedAt) ?: return
            val runtime = watchRuntime
            runtime.watchFailureStreak = 0 // 판을 실은 응답 = 연결이 살아 있다
            if (mapped.second) {
                // 수 번호에 구멍 — 판은 문자열이 권위라 멀쩡하지만 **기록**이 구멍 난 채로는 그리지 않는다.
                runtime.watchWantsFull = true
                runtime.watchAgain = true
                return
            }
            if (requestedSince == 0) runtime.watchWantsFull = false
            val state = mapped.first
            // 나 말고 몇 명이 이 판을 보고 있는가(watch_live 만 채운다 — 옛 길로 접히면 0 이고 화면은 아무것도 안 그린다).
            if (spectatorCount != state.watchers) spectatorCount = state.watchers
            if (spectating != state) spectating = state
            // 관전도 같은 뒤집기 그림을 쓴다 — 창이 보일 때 · 돌 한 수(+ 패스)만 나아갔을 때만.
            if (state.moveCount != current.moveCount) {
                val made = if (isWindowVisible && !isWindowOccluded) {
                    ReversiFlipAnimation.make(current.id, current.moveCount, state.moveCount, state.plies, clock().timeIntervalSince1970)
                } else {
                    null
                }
                if (made != null) beginFlip(made) else if (flip?.matchID == current.id) clearFlip()
            }
        }
        ReversiRPCStatus.notFound -> {
            // 끝난 지 오래된 판·없는 판·숨김 격리 — 서버는 있다/없다를 가르지 않는다.
            stopWatching()
            setNotice(ReversiNoticeText.watchGone)
        }
        ReversiRPCStatus.unsupportedClient -> {
            stopWatching()
            noteUpdateRequired()
        }
        else -> {
            log("watch refused status=${response.status.rawValue}")
            noteWatchFailure(null) // unauthorized·모르는 status 도 연속이면 내린다
        }
    }
}

/** 판의 두 사람 중 서버 행이 빠진 쪽을 id 로 찾는다: 씨앗 얼굴(로비 카드) → 로비 목록. */
private fun ReversiStore.knownUser(rawID: String?, current: ReversiSpectating): ReversiUser? {
    val id = rawID?.lowercase()
    if (id.isNullOrEmpty()) return null
    return current.faces.firstOrNull { it.id == id } ?: users.firstOrNull { it.id == id }
}

/** 예외 실패 경로. status 가 아니라 **throw 로 온** 실패(PGRST202·5xx·오프라인)와 모르는 응답 모양을 접는다. */
private fun ReversiStore.noteWatchFailure(error: Throwable?) {
    if (error != null && isSchemaMissing(error)) {
        // 서버에 reversi_watch 가 아직 없다. 관전 입구를 잠그는 신호는 **조건 없이** 세운다(게이트와 신호는 짝).
        // 순위 깃발(`rankingUnavailable`)은 건드리지 않는다 — 서로 다른 사실이다.
        stopWatching()
        setNotice(ReversiNoticeText.unavailable)
        if (!watchUnavailable) watchUnavailable = true
        return
    }
    log("watch request failed")
    val runtime = watchRuntime
    runtime.watchFailureStreak += 1
    if (runtime.watchFailureStreak < ReversiStore.watchFailureLimit) return
    stopWatching()
    setNotice(ReversiNoticeText.checkConnection)
}

// MARK: 폴링 훅 — `pollTick` · `windowDidShow` 가 부른다

/** 안전망 한 걸음: 관전 중이면 2초마다 판, 아니면 로비에서 60초마다 순위. 관전 중엔 순위를 돌리지 않는다. */
suspend fun ReversiStore.pollSpectatorFeatures(now: SwiftDate) {
    if (phase != ReversiPhase.lobby || !isWindowVisible || isWindowOccluded || host?.session == null) return
    if (spectating != null) {
        if (shouldPollWatch && now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= ReversiStore.watchPollSeconds) refreshWatch()
        return
    }
    if (now.timeIntervalSince(watchRuntime.lastRankingRequestAt) < ReversiStore.rankingPollSeconds) return
    // ★ 관전 잠금을 이 주기에 한 번 풀어 준다(`startWatching` 이 문 앞에서 막아 자기가 자기를 못 연다).
    if (watchUnavailable) watchUnavailable = false
    if (canPollRanking) refreshRanking() else watchRuntime.lastRankingRequestAt = now
}

/** 창이 다시 보였다: 관전 중이면 즉시 한 번, 로비면 순위 한 번 — 둘 다 1초 dedupe. */
fun ReversiStore.spectatorWindowDidShow(now: SwiftDate) {
    if (phase != ReversiPhase.lobby || !isWindowVisible || isWindowOccluded || host?.session == null) return
    if (spectating != null) {
        if (shouldPollWatch && now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= ReversiStore.reloadDedupeSeconds) launch { refreshWatch() }
        return
    }
    if (canPollRanking && now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= ReversiStore.reloadDedupeSeconds) launch { refreshRanking() }
}

// MARK: 순수 매퍼

/**
 * 응답 → 다음 관전 상태(순수). 사람·시각은 호출부가 스토어 경계(playerUser·deviceDate)로 만들어 넘긴다. null = 이 판 응답이 아니다.
 * 둘째 값 true = 수 번호에 구멍이 있어 처음부터 다시 받아야 한다(그때 첫째 값은 이전 값).
 */
fun spectateState(
    payload: ReversiStatePayload,
    previous: ReversiSpectating,
    requestedSince: Int,
    black: ReversiUser?,
    white: ReversiUser?,
    turnStartedAt: SwiftDate?,
    deadline: SwiftDate?,
    startedAt: SwiftDate?,
): Pair<ReversiSpectating, Boolean>? {
    val row = payload.match ?: return null
    if (row.id?.lowercase() != previous.id) return null
    val status = row.matchStatus
    if (status != ReversiMatchStatus.active && status != ReversiMatchStatus.finished) return null
    val isFinished = status == ReversiMatchStatus.finished
    val records = (payload.moves ?: emptyList()).filter { it.seq >= 1 }.sortedBy { it.seq }
    val rebuild = requestedSince == 0 || records.firstOrNull()?.seq == 1

    val merged = if (rebuild) ArrayList() else ArrayList(previous.plies)
    var applied = if (rebuild) 0 else previous.appliedSeq
    for (record in records) {
        if (record.seq <= applied) continue
        if (record.seq != applied + 1 && !rebuild) return previous to true
        merged += record
        applied = record.seq
    }
    val moveCount = row.moveCount ?: applied
    if (moveCount != applied && !rebuild) return previous to true

    val board = row.board ?: previous.board
    val result = if (isFinished) row.result else null
    val scoreRow = row.score
    val score = if (scoreRow?.black != null && scoreRow.white != null && result != null) ReversiScore(scoreRow.black!!, scoreRow.white!!, result) else null
    val next = previous.copy(
        blackUser = black,
        whiteUser = white,
        stake = row.stake?.toInt() ?: previous.stake,
        board = board,
        moveCount = moveCount,
        appliedSeq = moveCount,
        plies = merged.toList(),
        lastStoneIdx = merged.lastOrNull { it.kind == ReversiPly.Kind.stone }?.idx,
        autoStones = merged.mapNotNullTo(LinkedHashSet()) { if (it.kind == ReversiPly.Kind.stone && it.auto) it.idx else null },
        turn = if (isFinished) null else row.turn,
        turnStartedAt = if (isFinished) null else turnStartedAt,
        deadline = if (isFinished) null else deadline,
        counts = row.discs ?: board.counts,
        result = result,
        score = score,
        endReason = if (isFinished) row.endReason else null,
        winner = result?.winner,
        blackAutoStreak = payload.blackAutoStreak?.toInt() ?: previous.blackAutoStreak,
        whiteAutoStreak = payload.whiteAutoStreak?.toInt() ?: previous.whiteAutoStreak,
        startedAt = startedAt,
        isFinished = isFinished,
        watchers = maxOf(0L, payload.watchers ?: 0L).toInt(),
    )
    return next to false
}

// MARK: - 순위

/**
 * 순위표 한 번([ReversiStore.rankingEnabled] 이 꺼져 있으면 나가지 않는다). 도는 중이면 **합치지 않고 버린다**(60초 주기 목록이라 뒤따르는 한 번이
 * 필요 없다). 실패는 안내줄을 만들지 않는다 — 대국 안내를 가리지 않게.
 */
suspend fun ReversiStore.refreshRanking() {
    if (!rankingEnabled || host?.session == null) return
    val runtime = watchRuntime
    if (runtime.rankingInFlight) return
    runtime.rankingInFlight = true
    val generation = resetGeneration
    try {
        runtime.lastRankingRequestAt = clock()
        when (val result = perform { service, token -> service.reversiRanking(token) }) {
            null -> Unit
            is CallResult.Success -> applyRanking(result.value)
            is CallResult.Failure -> {
                if (isSchemaMissing(result.error)) {
                    // 서버에 reversi_ranking 이 아직 없다. 60초 폴링은 그대로라 서버가 올라오면 저절로 회복한다.
                    log("ranking unavailable — function missing on server")
                    if (!rankingUnavailable) rankingUnavailable = true
                    if (rankingLoadFailed) rankingLoadFailed = false
                    if (!hasLoadedRanking) hasLoadedRanking = true
                } else {
                    log("ranking request failed")
                    if (!rankingLoadFailed) rankingLoadFailed = true
                }
            }
        }
    } finally {
        if (generation == resetGeneration) runtime.rankingInFlight = false
    }
}

/** 순위 응답을 화면 값으로 옮긴다. status ok 만 — 거절은 로그만 남긴다(같은 순간 나가는 로비가 같은 status 로 말한다). */
fun ReversiStore.applyRanking(response: ReversiRankingResponse) {
    if (response.status != ReversiRPCStatus.ok) {
        log("ranking refused status=${response.status.rawValue}")
        if (!rankingLoadFailed) rankingLoadFailed = true
        return
    }
    noteServerNow(response.serverNowMs)
    if (rankingUnavailable) rankingUnavailable = false
    if (rankingLoadFailed) rankingLoadFailed = false
    if (!hasLoadedRanking) hasLoadedRanking = true
    val board = rankingBoard(response)
    if (ranking != board) ranking = board
}

/** 머리글용 내 순위. 순위 응답의 전적이 로비 전적(`record`)과 같을 때만 — 다르면 한쪽이 늦은 것이라 null. 로비를 아직 못 받았으면 그대로 낸다. */
val ReversiStore.myRankConsistentWithRecord: ReversiMyRank?
    get() {
        val mine = ranking?.me ?: return null
        val known = record
        if (known != null && known != ReversiRecord(mine.wins, mine.losses, mine.draws)) return null
        return mine
    }

/** 내 판이 끝났다(`applyState` 의 justFinished) — 전적이 바뀐 순간 순위도 다시 읽는다. 화면이 안 보여도 한 번은 낸다(사건에 대한 한 번). */
fun ReversiStore.noteOwnMatchFinishedForRanking() {
    watchRuntime.lastRankingRequestAt = distantPast // 지금 못 나가도(도는 중) 다음 틱이 바로 읽게
    if (!rankingEnabled || host?.session == null) return
    launch { refreshRanking() }
}

/** 응답 → 순위표(순수). **행 순서는 입력 그대로**. user_id 나 rank 가 빠진 행은 싣지 않는다. */
fun rankingBoard(response: ReversiRankingResponse): ReversiRanking {
    val entries = (response.rows ?: emptyList()).mapNotNull { row ->
        val rank = row.rank?.toInt() ?: return@mapNotNull null
        val id = row.userId?.lowercase()
        if (id.isNullOrEmpty()) return@mapNotNull null
        val user = ReversiUser(
            id = id, displayName = row.displayName ?: "", avatarURL = row.avatarUrl, characterID = row.character,
            center = CenterLabel.display(row.center), isWorking = false, isCapable = false, inMatch = false,
        )
        val wins = (row.wins ?: 0).toInt()
        val losses = (row.losses ?: 0).toInt()
        ReversiRankEntry(id, rank, user, wins, losses, (row.draws ?: 0).toInt(), row.points?.toInt() ?: (wins - losses))
    }
    val mine = response.me?.let { me ->
        val wins = (me.wins ?: 0).toInt()
        val losses = (me.losses ?: 0).toInt()
        ReversiMyRank(me.rank?.toInt(), wins, losses, (me.draws ?: 0).toInt(), me.points?.toInt() ?: (wins - losses))
    }
    val since = response.recordSinceMs?.let { if (it > 0) SwiftDate(it / 1000) else null }
    return ReversiRanking(entries, mine, since)
}
