// 원본: Sources/CheckCore/ChessStoreWatch.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.net.chessWatch
import com.yehsung.aingcheck.core.net.chessWatchLive
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.fromFen
import com.yehsung.aingcheck.core.stores.gomoku.CallResult
import com.yehsung.aingcheck.core.stores.gomoku.distantPast
import com.yehsung.aingcheck.core.stores.gomoku.isSchemaMissing
import com.yehsung.aingcheck.core.stores.gomoku.nonNegative
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ChessRPCStatus
import com.yehsung.aingcheck.core.wire.games.ChessWatchResponse
import kotlinx.coroutines.launch

// 체스 스토어의 **관전** 갈래 — 남의 진행 중인 판을 읽기 전용으로 본다.
// ── 관전은 판만이다 ── `chess_watch` 는 판(FEN)·수순·남은 시간·두 사람·판돈만 준다. 이 파일은 `chess_state` 를 **절대 부르지 않는다**.
// ── 관전자는 깃발을 떨어뜨리지 않는다 ── "남은 시간이 0 인데 아직 진행 중" 인 판을 볼 수 있다 — 결과를 지어내지 마라.
// ── 주 스위치 ── `spectatorFeaturesEnabled` 가 꺼져 있으면 진입·조회·폴링이 한 번도 안 돈다. **판돈 깃발(§8-17 #1)과는 무관하다.**
// ── 세대 ── `watchRuntime.watchGeneration` 이 관전 세대다. 세대가 같아도 응답의 `match.id` 가 다르면 버린다(이중 자물쇠).
// ── 흑·백은 서버만 안다 ── 씨앗은 `faces` 두 얼굴뿐이고 `black`/`white` 는 첫 ok 응답으로만 선다.

/** 관전·순위 갈래의 관찰 대상이 아닌 장부(이름이 `reset` 이 아니라 `clear` 인 까닭은 Swift 소스 계약 시험 — 원문 그대로 둔다). */
class ChessWatchRuntime {
    var lastWatchRequestAt: SwiftDate = distantPast
    var watchInFlight: Boolean = false
    /** 조회 중에 또 조회할 이유가 생겼다 — 끝나면 한 번 더 돈다. */
    var watchAgain: Boolean = false
    /** 다음 조회 한 번을 `p_since_seq = 0` 으로 띄운다. 내리는 것은 **그 전체를 실어 온 응답**이다. */
    var watchWantsFull: Boolean = false
    var watchGeneration: Int = 0
        private set
    /** 연속 실패 횟수(throw 경로 — 5xx·오프라인). */
    var watchFailureStreak: Int = 0
    var lastRankingRequestAt: SwiftDate = distantPast
    var rankingInFlight: Boolean = false

    fun bumpWatchGeneration(): Int {
        watchGeneration += 1
        return watchGeneration
    }

    /** 전부 초기값 + 세대 한 번 올림(로그아웃·계정 전환). */
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

/**
 * 관전 중인 남의 판 하나. `phase` 는 `lobby` 그대로이고 **이 값이 null 이 아닌 것**이 관전 중이다. **흑·백을 추측하지 않는다**.
 * 판은 `match.fen` 이 권위이고 `moves` 는 기보·마지막 수용이다.
 */
data class ChessSpectateState(
    /** match id 소문자. */
    val id: String,
    /** 로비 카드에서 빌린 두 얼굴(a·b 순서, **색 모름**). */
    val faces: List<ChessUser> = emptyList(),
    /** 판돈. 씨앗이 없으면 null 이고 응답의 `match.stake` 가 채운다. */
    val stake: Long? = null,
    /** 서버가 말한 흑·백. **첫 ok 응답 전에는 null**. */
    val black: ChessUser? = null,
    val white: ChessUser? = null,
    val fen: String = "",
    /** [fen] 을 읽은 국면. null 이면 판을 그릴 수 없다. */
    val position: ChessPosition? = null,
    val plyCount: Int = 0,
    /** 내가 반영한 마지막 수 번호. 다음 요청의 `p_since_seq` 다. */
    val appliedSeq: Int = 0,
    val moves: List<ChessMoveRecord> = emptyList(),
    val lastMove: ChessMove? = null,
    /** 끝나면 null. */
    val turn: ChessColor? = null,
    val clock: ChessServerClock = ChessServerClock.initial,
    val isInCheck: Boolean = false,
    val startedAt: SwiftDate? = null,
    val isFinished: Boolean = false,
    /** 이긴 색. 끝났는데 null 이면 무승부다. */
    val winner: ChessColor? = null,
    val endReason: ChessEndReason? = null,
) {
    /** 서버 응답을 한 번이라도 반영했는가(= 흑·백이 확정됐는가). */
    val hasServerState: Boolean get() = black != null && white != null
}

/** 내 user id(소문자). 세션이 없으면 null. */
val ChessStore.myUserID: String? get() = host?.session?.userID?.lowercase()

/** 로비 "지금 대결 중" 카드가 내 판인가. */
fun ChessStore.isMine(live: ChessLiveMatch): Boolean {
    val mine = myUserID ?: return false
    return live.a.id == mine || live.b.id == mine
}

/** 지금 관전 폴링이 돌아야 하는가: 관전 중 + 안 끝남 + 로비 화면 + 주 스위치·창·세션. */
val ChessStore.shouldPollWatch: Boolean
    get() {
        val watch = spectating ?: return false
        if (watch.isFinished) return false
        return phase == ChessPhase.lobby && canPollSpectatorFeatures
    }

// MARK: 진입 · 이탈

/** [관전] — 로비 카드의 두 얼굴을 씨앗으로 관전 상태를 세우고, 창이 보이면 곧바로 한 번 읽는다. */
fun ChessStore.startWatching(matchID: String) {
    val id = matchID.lowercase()
    if (!spectatorFeaturesEnabled || id.isEmpty() || ChessAIGame.isAIMatchID(id) || host?.session == null) return
    val current = match
    if (current != null && !current.isFinished) return
    if (phase != ChessPhase.lobby) return
    if (spectating?.id == id) return
    // INV-ChessStoreWatch-fde7c1f1 이식: **문 앞에서 막는다.** 404 뒤 `stopWatching()` 이 `spectating` 을 비우므로 위 재진입 가드가 다시
    // 통과한다 — 화면의 칩만 잠그면 스토어를 직접 부르는 길이 404 를 무한히 낸다. 잠금은 폴링 주기가 한 번씩 풀어 준다.
    if (watchUnavailable) {
        setNotice(ChessNoticeText.unavailable)
        return
    }
    val live = liveMatches.firstOrNull { it.id == id }
    val seed = if (live != null) ChessSpectateState(id, faces = listOf(live.a, live.b), stake = live.stake.rawValue) else ChessSpectateState(id)
    resetWatchRuntime()
    clearWatchNotice()
    spectating = seed
    if (canPollSpectatorFeatures) scope.launch { refreshWatch() }
}

/** 사용자 [나가기]. 관전을 내리고 로비 자리로 돌아오며 목록·순위를 새로 읽는다. */
fun ChessStore.leaveWatch() {
    stopWatching()
    if (host?.session == null) return
    scope.launch {
        refreshLobby()
        loadRanking()
    }
}

/** 조용히 내린다(요청 없음): 세대를 올려 나가 있던 응답을 버리고 장부를 비운다. */
fun ChessStore.stopWatching() {
    resetWatchRuntime()
    if (spectating != null) spectating = null
    if (spectatorCount != 0L) spectatorCount = 0
}

private fun ChessStore.resetWatchRuntime() {
    val runtime = watchRuntime
    runtime.bumpWatchGeneration()
    runtime.watchInFlight = false
    runtime.watchAgain = false
    runtime.watchWantsFull = false
    runtime.watchFailureStreak = 0
    runtime.lastWatchRequestAt = distantPast
}

/** 관전이 남긴 안내(못 보는 판·준비 중·연결)는 새 관전에 들어갈 때 걷는다. 그 밖의 안내는 건드리지 않는다. */
private fun ChessStore.clearWatchNotice() {
    val mine = setOf(ChessNoticeText.watchGone, ChessNoticeText.unavailable, ChessNoticeText.checkConnection)
    val current = notice
    if (current != null && current in mine) setNotice(null)
}

// MARK: 조회

/** 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 창 규칙(보일 때만)은 **부르는 쪽**이 본다. */
suspend fun ChessStore.refreshWatch() {
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
        val since = if (runtime.watchWantsFull) 0 else (spectating?.appliedSeq ?: 0)
        runtime.lastWatchRequestAt = clock()
        val result = watchFetch(id, since)
        if (generation != runtime.watchGeneration || resetMark != resetGeneration) return
        when (result) {
            is CallResult.Success -> applyWatch(result.value, since)
            is CallResult.Failure -> noteWatchFailure(result.error)
            null -> Unit
        }
        if (generation != runtime.watchGeneration) return
    } while (runtime.watchAgain && spectating != null)
    runtime.watchInFlight = false
}

/**
 * 관전 한 번 — `chess_watch_live` 를 먼저 부르고, 서버에 그 함수가 아직 없으면 옛 `chess_watch` 로 **한 번 접어** 같은 바퀴 안에서 다시 부른다.
 * INV-ChessStoreWatch-cd8533c4 이식: 이 실패는 `watchUnavailable` 도 `watchFailureStreak` 도 **건드리지 않는다** — 관전은 옛 길로 멀쩡히
 * 돌고 잃는 것은 숫자 한 칸뿐이다(두 사실을 한 깃발에 겸업시키면 관전 입구가 통째로 잠긴다).
 */
private suspend fun ChessStore.watchFetch(matchID: String, sinceSeq: Int): CallResult<ChessWatchResponse>? {
    if (!spectatorCountUnavailable) {
        val live = perform { service, token -> service.chessWatchLive(token, matchID, sinceSeq.toLong()) }
        if (live !is CallResult.Failure || !isSchemaMissing(live.error)) return live
        log("chess_watch_live missing — folding to chess_watch")
        spectatorCountUnavailable = true
    }
    return perform { service, token -> service.chessWatch(token, matchID, sinceSeq.toLong()) }
}

/** 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다. */
fun ChessStore.applyWatch(response: ChessWatchResponse, requestedSince: Int = 0) {
    val current = spectating ?: return
    when (response.status) {
        ChessRPCStatus.ok -> {
            val row = response.match
            if (row == null) {
                noteWatchFailure(null)
                return
            }
            if (row.id?.lowercase() != current.id) return
            noteServerNow(response.serverNowMs)
            if (watchUnavailable) watchUnavailable = false
            val status = row.status ?: ""
            if (status != "active" && status != "finished") {
                stopWatching()
                setNotice(ChessNoticeText.watchGone)
                return
            }
            val inMatch = status == "active"
            val watchers = nonNegative(response.watchers)
            if (spectatorCount != watchers) spectatorCount = watchers
            // 흑·백은 **여기서만** 선다. 서버 행이 없으면 씨앗 얼굴·로비 목록에서 id 로 빌리고, 그래도 없으면 앞 값이다.
            val black = peerUser(response.blackUser, inMatch) ?: knownUser(row.black, current) ?: current.black
            val white = peerUser(response.whiteUser, inMatch) ?: knownUser(row.white, current) ?: current.white
            val turnStartedAt = deviceDate(row.turnStartedMs)
            val startedAt = deviceDate(row.startedMs) ?: current.startedAt
            val mapped = chessSpectateState(response, current, requestedSince, black, white, turnStartedAt, startedAt) ?: return
            val runtime = watchRuntime
            runtime.watchFailureStreak = 0
            if (mapped.second) {
                // 수 번호에 구멍 — 판은 `fen` 이 권위라 멀쩡하지만 **기보**가 구멍 난 채로는 그리지 않는다.
                runtime.watchWantsFull = true
                runtime.watchAgain = true
                return
            }
            if (requestedSince == 0) runtime.watchWantsFull = false
            if (spectating != mapped.first) spectating = mapped.first
            // (Swift 는 여기서 관전 판 애니메이션을 띄운다 — 그림 갈래 몫이라 옮기지 않았다. ChessStore.kt 머리말.)
        }
        ChessRPCStatus.notFound -> {
            stopWatching()
            setNotice(ChessNoticeText.watchGone)
        }
        ChessRPCStatus.unsupportedClient -> {
            stopWatching()
            setNotice(ChessNoticeText.updateMine)
        }
        else -> {
            log("watch refused status=${response.status.rawValue}")
            noteWatchFailure(null)
        }
    }
}

private fun ChessStore.knownUser(rawID: String?, current: ChessSpectateState): ChessUser? {
    val id = rawID?.lowercase()
    if (id.isNullOrEmpty()) return null
    return current.faces.firstOrNull { it.id == id } ?: users.firstOrNull { it.id == id }
}

private fun ChessStore.noteWatchFailure(error: Throwable?) {
    if (error != null && isSchemaMissing(error)) {
        stopWatching()
        setNotice(ChessNoticeText.unavailable)
        // INV-ChessStoreWatch-d083b0c6 이식: 관전 입구를 잠그는 신호는 **조건 없이** 세운다 — `chess_watch` 가 없다는 직접 증거이고 순위를
        // 들고 있든 없든 관전은 못 한다. 이 한 줄이 없으면 [관전] 칩이 활성인 채로 남아 누를 때마다 404 를 반복한다.
        if (!watchUnavailable) watchUnavailable = true
        // 순위표까지 함께 접는 것은 **순위를 한 번도 못 받았을 때만**이다.
        if (ranking == null) {
            if (!rankingUnavailable) rankingUnavailable = true
            if (!hasLoadedRanking) hasLoadedRanking = true
        }
        return
    }
    log("watch request failed")
    val runtime = watchRuntime
    runtime.watchFailureStreak += 1
    if (runtime.watchFailureStreak < ChessStore.watchFailureLimit) return
    stopWatching()
    setNotice(ChessNoticeText.checkConnection)
}

// MARK: 폴링 훅

/** 안전망 한 걸음: 관전 중이면 2초마다 판, 아니면 로비에서 60초마다 순위. 관전 중엔 순위를 돌리지 않는다. */
suspend fun ChessStore.pollSpectatorFeatures(now: SwiftDate) {
    if (!canPollSpectatorFeatures || phase != ChessPhase.lobby) return
    // INV-ChessStoreWatch-81bb3632 이식: 같은 사실을 두 곳에 적지 않는다 — "관전 중 + 안 끝남"은 [shouldPollWatch] 한 술어다
    // (옛 코드는 여기에 다시 써서 그 술어를 죽은 게이트로 만들었고, 지워도 전부 초록이었다 — 뮤테이션 M12).
    if (spectating != null) {
        if (shouldPollWatch && now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= ChessStore.watchPollSeconds) refreshWatch()
        return
    }
    if (now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= ChessStore.rankingPollSeconds) {
        // INV-ChessStoreWatch-576c0edc 이식: 관전 잠금을 이 주기에 **한 번 풀어 준다** — `watchUnavailable` 은 `startWatching` 을 문 앞에서
        // 막으므로 자기가 자기를 열 수 없다. 풀어 두면 최악이 "60초에 404 한 번"이다.
        if (watchUnavailable) watchUnavailable = false
        loadRanking()
    }
}

/** 창이 다시 보였다: 관전 중이면 즉시 한 번, 로비면 순위 한 번 — 둘 다 1초 dedupe. */
fun ChessStore.spectatorWindowDidShow(now: SwiftDate) {
    if (!canPollSpectatorFeatures || phase != ChessPhase.lobby) return
    if (spectating != null) {
        if (shouldPollWatch && now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= ChessStore.reloadDedupeSeconds) {
            scope.launch { refreshWatch() }
        }
        return
    }
    if (now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= ChessStore.reloadDedupeSeconds) scope.launch { loadRanking() }
}

// MARK: 순수 매퍼

/**
 * 응답 → 다음 관전 상태(순수, Swift `ChessStore.spectateState(applying:to:…)`). null = 이 판 응답이 아니다.
 * 두 번째 값 = 수 번호에 구멍이 있어 처음부터 다시 받아야 한다(그때 첫 값은 이전 값 그대로 — 구멍 난 기보를 그리면 기보가 거짓말을 한다).
 */
fun chessSpectateState(
    response: ChessWatchResponse,
    previous: ChessSpectateState,
    requestedSince: Int,
    black: ChessUser?,
    white: ChessUser?,
    turnStartedAt: SwiftDate?,
    startedAt: SwiftDate?,
): Pair<ChessSpectateState, Boolean>? {
    val row = response.match ?: return null
    if (row.id?.lowercase() != previous.id) return null
    val status = row.status ?: ""
    if (status != "active" && status != "finished") return null
    val isFinished = status == "finished"
    val rebuild = requestedSince == 0 || response.moves?.firstOrNull()?.seq == 1L

    val merged = if (rebuild) ArrayList() else ArrayList(previous.moves)
    var applied = if (rebuild) 0 else previous.appliedSeq
    for (record in ChessStore.moveRecords(response.moves)) {
        if (record.seq <= applied) continue
        if (record.seq != applied + 1 && !rebuild) return previous to true
        merged.add(record)
        applied = record.seq
    }
    val serverPly = row.plyCount?.toInt() ?: applied
    if (serverPly != applied && !rebuild) return previous to true

    val fen = row.fen ?: previous.fen
    val turn = if (isFinished) null else ChessColor.fromRawValue(row.turn ?: "")
    val winner = when (row.result) {
        "white_win" -> ChessColor.white
        "black_win" -> ChessColor.black
        else -> null // 무승부 또는 아직 진행 중
    }
    val next = previous.copy(
        black = black,
        white = white,
        stake = row.stake ?: previous.stake,
        fen = fen,
        position = ChessPosition.fromFen(fen),
        plyCount = serverPly,
        appliedSeq = applied,
        moves = merged.toList(),
        lastMove = merged.lastOrNull()?.move,
        turn = turn,
        clock = ChessServerClock(
            whiteMsLeft = row.whiteMsLeft ?: previous.clock.whiteMsLeft,
            blackMsLeft = row.blackMsLeft ?: previous.clock.blackMsLeft,
            incrementMs = row.incrementMs ?: previous.clock.incrementMs,
            turnStartedAt = if (isFinished) null else turnStartedAt,
            running = turn,
        ),
        isInCheck = response.inCheck ?: false,
        startedAt = startedAt,
        isFinished = isFinished,
        winner = winner,
        endReason = ChessEndReason.fromRawValue(row.endReason),
    )
    return next to false
}
