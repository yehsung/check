// 원본: Sources/CheckCore/RummyStoreLobby.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.net.rummyCreate
import com.yehsung.aingcheck.core.net.rummyDecline
import com.yehsung.aingcheck.core.net.rummyInvite
import com.yehsung.aingcheck.core.net.rummyJoin
import com.yehsung.aingcheck.core.net.rummyLeave
import com.yehsung.aingcheck.core.net.rummyLobby
import com.yehsung.aingcheck.core.net.rummyRanking
import com.yehsung.aingcheck.core.net.rummyStart
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyActionResponse
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyPeer
import com.yehsung.aingcheck.core.wire.games.RummyRPCStatus
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyRoomSeat
import kotlinx.coroutines.launch

// 아잉 큐브 스토어 — 로비 · 초대 · 방 동작(만들기·초대·참가·거절·나가기·시작) · 순위 · 차단 거울.
// 규약은 RummyStore.kt 머리말 ①~⑩.

// MARK: - 로비

/** 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다 — 앞 조회는 그 뒤에 생긴 초대를 모르므로 그 사이 온 초인종을 버리면 다음 계기까지 안 뜬다. */
suspend fun RummyStore.refreshLobby() {
    if (host?.session == null) return
    if (lobbyInFlight) {
        lobbyAgain = true
        return
    }
    lobbyInFlight = true
    val generation = resetGeneration
    try {
        do {
            lobbyAgain = false
            lastLobbyRequestAt = clock()
            val revision = matchRevision
            val result = perform("refreshLobby") { service, token -> service.rummyLobby(token) } ?: return
            when (result) {
                is DuelCall.Success -> applyLobby(result.value, revision)
                is DuelCall.Failure ->
                    if (isSchemaMissing(result.error)) {
                        logNotice("lobby unavailable — rummy functions missing on server")
                        noteServerMissing()
                    } else {
                        logNotice("lobby request failed")
                        if (!lobbyLoadFailed) lobbyLoadFailed = true
                    }
            }
        } while (lobbyAgain && generation == resetGeneration)
    } finally {
        if (generation == resetGeneration) lobbyInFlight = false
    }
}

/** 화면이 다시 읽어 달라고 했다([다시 시도]). */
fun RummyStore.reloadLobby() {
    scope.launch { refreshLobby() }
}

/** 로비 응답을 옮긴다. [revision] 은 그 요청을 낼 때의 `matchRevision` 이다(null = 지금 것). */
suspend fun RummyStore.applyLobby(response: RummyLobby, revision: Int? = null) {
    if (response.status != RummyRPCStatus.ok) {
        logNotice("lobby refused status=${response.status.rawValue}")
        when (response.status) {
            RummyRPCStatus.unsupportedClient -> noteUpdateRequired()
            RummyRPCStatus.unauthorized -> setNotice(RummyNoticeText.signInAgain)
            else -> if (!lobbyLoadFailed) lobbyLoadFailed = true
        }
        return
    }
    noteServerNow(response.serverNowMs)
    if (availability != RummyAvailability.available) availability = RummyAvailability.available
    if (lobbyLoadFailed) lobbyLoadFailed = false
    rawLobby = response
    publishLobby()
    applyRuby(response.me?.rubyBalance)
    val stakes = response.stakes
    if (!stakes.isNullOrEmpty() && selectedStake !in stakes) selectedStake = stakes.first()
    // 새 초대 — 방 id 마다 **한 번**. 차단한 방장의 초대·잠긴 빌드는 알리지 않는다(본 것으로는 적는다).
    for (room in response.invites ?: emptyList()) {
        if (room.id in seenInviteIDs) continue
        seenInviteIDs = seenInviteIDs + room.id
        if (isHidden(room) || duelsLocked) continue
        onInviteArrived?.invoke(room)
    }
    // 내 방·판.
    val mine = response.me?.activeMatchId ?: response.me?.room?.id
    activeMatchID = mine
    if (mine != null) {
        if (mine in dismissedMatchIDs) return
        // 같은 id 면 신호·폴링·따라잡기가 이미 그 판을 읽는다 — 단, 모르는 status 로 든 판은 여기서도 다시 읽는다.
        val held = match
        if (held == null || held.id != mine || held.status == RummyMatchStatus.finished || held.status == RummyMatchStatus.unknown) {
            refreshMatch(mine)
        }
    } else {
        val current = match
        if (current != null && RummyStore.isUnsettled(current.status) && (revision ?: matchRevision) == matchRevision) {
            // 서버는 내 방·판이 없다고 한다 — 그 판을 직접 읽어 사정(닫힘·끝남·기권)을 안다. 지우지 않는다.
            refreshMatch(current.id)
        }
    }
}

/** 판돈 차감(판 시작)·정산(판 끝)을 **처음 본** 순간 로비를 한 번 다시 읽어 잔액을 맞춘다(머리말 ⑯). 판 state 에는 잔액이 없다. */
internal fun RummyStore.refreshRubyAfterSettlement() {
    if (host?.session == null) return
    scope.launch { refreshLobby() }
}

/** 차단 거울을 거친 로비를 낸다(관찰자를 헛되게 깨우지 않게 같으면 대입하지 않는다). */
internal fun RummyStore.publishLobby() {
    val raw = rawLobby
    if (raw == null) {
        if (lobby != null) lobby = null
        return
    }
    var shown: RummyLobby = raw
    if (hiddenPeerIDs.isNotEmpty()) {
        shown = shown.copy(
            users = shown.users?.filter { it.id !in hiddenPeerIDs },
            invites = shown.invites?.filter { !isHidden(it) },
            publicRooms = shown.publicRooms?.filter { !isHidden(it) },
        )
    }
    // 나가기로 접은 방을 늦게 온 로비 응답이 다시 '내 방' 카드로 세우지 않게(나가기 전에 나간 조회).
    val room = shown.me?.room
    if (room != null && room.id in dismissedMatchIDs) shown = shown.copy(me = shown.me?.copy(room = null))
    if (lobby != shown) lobby = shown
}

// MARK: - 내 방(방 카드의 원천)

/** 방 카드에 그릴 내 방 — [shownRummyRoom] 을 지금 값으로. */
val RummyStore.myRoom: RummyRoom? get() = shownRummyRoom(match, lobby)

/**
 * 방 카드에 그릴 내 방. **들고 있는 forming 판 state 가 먼저**고, 없을 때만 로비 `me.room` 이다.
 *
 * 왜(10-30 운영 결함 — 방 만들기 뒤 방 화면이 20~30초 안 떴다): 만들기·참가 응답과 초인종·5초 폴링은 `match` 만 갈고, 로비 `me.room` 은
 * **30초 로비 폴링**만 간다. 방 카드가 로비만 보면 phase 는 이미 방인데 화면은 '방 만들기' 카드에 머물고, 들어온 사람·[시작] 단추도 30초씩 늦는다.
 */
fun shownRummyRoom(match: RummyMatchState?, lobby: RummyLobby?): RummyRoom? {
    val listed = lobby?.me?.room
    if (match == null || match.status != RummyMatchStatus.forming) return listed
    val sameListed = if (listed?.id == match.id) listed else null
    val hostSeat = match.hostId?.let { hostID -> match.seats?.firstOrNull { it.userId == hostID } }
    val host: RummyPeer? = hostSeat?.let { RummyPeer(it.userId, it.displayName, it.avatarUrl, it.character) }
        ?: sameListed?.host
        ?: match.hostId?.let { RummyPeer(it) }
    val seats: List<RummyRoomSeat>? = match.seats?.map {
        RummyRoomSeat(userId = it.userId, displayName = it.displayName, avatarUrl = it.avatarUrl, character = it.character, state = it.state, seatNo = it.seatNo)
    } ?: sameListed?.seats
    return RummyRoom(
        id = match.id,
        host = host,
        stake = match.stake ?: sameListed?.stake,
        isPublic = match.isPublic ?: sameListed?.isPublic,
        expiresAtMs = match.expiresAtMs ?: sameListed?.expiresAtMs,
        maxSeats = match.maxSeats ?: sameListed?.maxSeats,
        seats = seats,
    )
}

/** 차단한 사람이 방장이거나 자리에 낀 방인가. */
internal fun RummyStore.isHidden(room: RummyRoom): Boolean {
    if (hiddenPeerIDs.isEmpty()) return false
    val hostID = room.host?.id
    if (hostID != null && hostID in hiddenPeerIDs) return true
    return room.seats?.any { it.userId in hiddenPeerIDs } ?: false
}

// MARK: - 초대

/** 받은 초대(최근 순, 서버 순서 그대로). 차단한 방장의 초대·지금 앉은 방은 뺀다. 잠긴 빌드에서도 비우지 않는다 — 접힌 한 줄이 이 값을 본다. */
val RummyStore.incomingInvites: List<RummyRoom>
    get() {
        val rooms = lobby?.invites ?: emptyList()
        val current = match?.id ?: return rooms
        return rooms.filter { it.id != current }
    }

/** 배너·점. 잠긴 빌드에서는 수락할 수 없는 초대로 서지 않는다(§8-17 #1). */
val RummyStore.hasIncomingInvite: Boolean get() = !duelsLocked && incomingInvites.isNotEmpty()

/**
 * 게임 탭 배지에 더하는 수. 잠긴 빌드는 0. 방 수명(10분)이 지난 초대는 세지 않는다 — 폴링이 창이 보일 때만 돌아 로비가 오래됐을 수 있다
 * (없는 초대를 가리키는 배지가 되지 않게).
 */
val RummyStore.pendingIncomingInviteCount: Int
    get() {
        if (duelsLocked) return 0
        val now = clock()
        return incomingInvites.count { room -> deviceDate(room.expiresAtMs)?.let { it > now } ?: true }
    }

// MARK: - 방 동작

/** [RummyStore.selectedStake]·[RummyStore.createPublic] 으로 방을 만든다. 잠긴 빌드는 요청을 내지 않는다. */
fun RummyStore.createRoom() {
    if (host?.session == null) return
    if (duelsLocked) {
        setNotice(RummyNoticeText.updateRequired)
        return
    }
    val stake = selectedStake
    val isPublic = createPublic
    runAction { store ->
        val ticket = store.issueTicket()
        val result = store.perform("createRoom") { service, token -> service.rummyCreate(token, stake, isPublic) } ?: return@runAction
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                store.noteServerNow(response.serverNowMs)
                val id = response.matchId ?: response.state?.id
                if (response.status != RummyRPCStatus.ok || id == null) {
                    store.noteRefusal(response, RummyNoticeText.Action.create)
                    return@runAction
                }
                store.setNotice(null)
                // 이 기기가 세운 방(머리말 ⑮) — 만들기는 id 를 응답에서야 안다.
                store.markEngaged(id)
                store.matchRevision += 1
                store.activeMatchID = id
                store.dismissedMatchIDs = store.dismissedMatchIDs - id
                val state = response.state
                if (state != null) store.applyState(state, ticket) else store.refreshMatch(id)
            }
            is DuelCall.Failure -> store.noteActionFailure(result.error)
        }
    }
}

/** 방장이 사람을 골라 초대한다. 성공이면 방 state 를 다시 읽는다(초대 자리가 보인다). */
fun RummyStore.invite(userID: SwiftUUID) {
    val room = match
    if (room == null || room.status != RummyMatchStatus.forming) return
    if (duelsLocked) {
        setNotice(RummyNoticeText.updateRequired)
        return
    }
    val roomID = room.id
    runAction { store ->
        val ticket = store.issueTicket()
        val result = store.perform("invite") { service, token -> service.rummyInvite(token, roomID, userID) } ?: return@runAction
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                store.noteServerNow(response.serverNowMs)
                if (response.status != RummyRPCStatus.ok) {
                    store.noteRefusal(response, RummyNoticeText.Action.invite)
                    return@runAction
                }
                store.setNotice(RummyNoticeText.invited)
                val state = response.state
                if (state != null) store.applyState(state, ticket) else store.refreshMatch(roomID)
            }
            is DuelCall.Failure -> store.noteActionFailure(result.error)
        }
    }
}

/** 초대 수락 또는 공개 방 참가. 잠긴 빌드는 요청을 내지 않는다. */
fun RummyStore.join(roomID: SwiftUUID) {
    if (host?.session == null) return
    if (duelsLocked) {
        setNotice(RummyNoticeText.updateRequired)
        return
    }
    runAction { store ->
        val ticket = store.issueTicket()
        // 보내기 직전에 적는다(머리말 ⑮) — 답이 안 와도 서버엔 앉았을 수 있다.
        store.markEngaged(roomID)
        val result = store.perform("join") { service, token -> service.rummyJoin(token, roomID) } ?: return@runAction
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                store.noteServerNow(response.serverNowMs)
                if (response.status != RummyRPCStatus.ok) {
                    // 못 앉았다 — 들고 있는 방이 아니면 장부에서 걷는다.
                    if (store.match?.id != roomID) store.forgetEngaged(roomID)
                    store.noteRefusal(response, RummyNoticeText.Action.join)
                    // 닫혔거나 초대가 없어진 방 — 로비를 다시 읽어 그 카드를 걷는다.
                    if (response.status == RummyRPCStatus.roomClosed || response.status == RummyRPCStatus.notInvited ||
                        response.status == RummyRPCStatus.roomFull || response.status == RummyRPCStatus.notFound
                    ) {
                        store.refreshLobby()
                    }
                    return@runAction
                }
                store.setNotice(null)
                store.matchRevision += 1
                store.activeMatchID = roomID
                store.dismissedMatchIDs = store.dismissedMatchIDs - roomID
                val state = response.state
                if (state != null) store.applyState(state, ticket) else store.refreshMatch(roomID)
            }
            is DuelCall.Failure -> store.noteActionFailure(result.error)
        }
    }
}

/** 받은 초대를 거절한다. 성공이면 그 카드를 곧바로 걷는다(다음 로비가 확인한다). 판돈이 움직이지 않아 깃발과 무관하다. */
fun RummyStore.decline(roomID: SwiftUUID) {
    runAction { store ->
        val result = store.perform("decline") { service, token -> service.rummyDecline(token, roomID) } ?: return@runAction
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                store.noteServerNow(response.serverNowMs)
                if (response.status == RummyRPCStatus.ok) {
                    store.setNotice(null)
                    store.dropInvite(roomID)
                } else {
                    store.noteRefusal(response, RummyNoticeText.Action.decline)
                    store.refreshLobby()
                }
            }
            is DuelCall.Failure -> store.noteActionFailure(result.error)
        }
    }
}

/** 방 나가기(방장이면 방이 닫힌다) / 판 기권. 끝난 판이면 결과 접기와 같다. */
fun RummyStore.leave() {
    val current = match ?: return
    if (current.status == RummyMatchStatus.finished) {
        dismissResult()
        return
    }
    val matchID = current.id
    runAction { store ->
        val ticket = store.issueTicket()
        val result = store.perform("leave") { service, token -> service.rummyLeave(token, matchID) } ?: return@runAction
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                store.noteServerNow(response.serverNowMs)
                if (response.status != RummyRPCStatus.ok) {
                    store.noteRefusal(response, RummyNoticeText.Action.leave)
                    response.state?.let { store.applyState(it, ticket) }
                    return@runAction
                }
                store.setNotice(null)
                store.dismissedMatchIDs = store.dismissedMatchIDs + matchID
                store.matchRevision += 1
                if (store.activeMatchID == matchID) store.activeMatchID = null
                if (store.match?.id == matchID) store.clearMatch()
                store.refreshLobby()
            }
            is DuelCall.Failure -> store.noteActionFailure(result.error)
        }
    }
}

/** 방장이 판을 시작한다. 빠진 자리가 있으면 시작하지 않고 방 state 를 다시 읽는다. 잠긴 빌드는 요청을 내지 않는다(판돈이 움직이는 순간이다). */
fun RummyStore.startGame() {
    val room = match
    if (room == null || room.status != RummyMatchStatus.forming) return
    if (duelsLocked) {
        setNotice(RummyNoticeText.updateRequired)
        return
    }
    val roomID = room.id
    runAction { store ->
        val ticket = store.issueTicket()
        store.markEngaged(roomID)
        val result = store.perform("startGame") { service, token -> service.rummyStart(token, roomID) } ?: return@runAction
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                store.noteServerNow(response.serverNowMs)
                val state = response.state
                if (response.status == RummyRPCStatus.ok) {
                    store.setNotice(null)
                    if (state != null) store.applyState(state, ticket) else store.refreshMatch(roomID)
                    return@runAction
                }
                store.noteRefusal(response, RummyNoticeText.Action.start)
                if (state != null) {
                    store.applyState(state, ticket)
                } else if (response.status == RummyRPCStatus.seatsDropped) {
                    store.refreshMatch(roomID)
                }
            }
            is DuelCall.Failure -> store.noteActionFailure(result.error)
        }
    }
}

/** 결과 화면 [로비로]. 그 판은 다시 끌려오지 않는다. */
fun RummyStore.dismissResult() {
    if (!foldMatch()) return
    if (host?.session == null) return
    scope.launch { refreshLobby() }
}

/** 화면을 정말 떠났다(폰 — Tetris `windowDidClose` 선례). **끝난 판만** 접는다 — 요청 0건. 진행 중인 판·방은 그대로 남는다(이탈은 `requestBack` 이 정했다). */
fun RummyStore.windowDidClose() {
    if (match?.status == RummyMatchStatus.finished) foldMatch()
}

private fun RummyStore.foldMatch(): Boolean {
    val current = match ?: return false
    dismissedMatchIDs = dismissedMatchIDs + current.id
    if (activeMatchID == current.id) activeMatchID = null
    clearMatch()
    setNotice(null)
    return true
}

// MARK: - 순위

fun RummyStore.refreshRanking() {
    if (!rankingEnabled || host?.session == null) return
    scope.launch { loadRanking() }
}

suspend fun RummyStore.loadRanking() {
    if (!rankingEnabled || host?.session == null || rankingInFlight) return
    rankingInFlight = true
    val generation = resetGeneration
    try {
        lastRankingRequestAt = clock()
        val result = perform("loadRanking") { service, token -> service.rummyRanking(token) } ?: return
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                noteServerNow(response.serverNowMs)
                when (response.status) {
                    RummyRPCStatus.ok -> if (ranking != response) ranking = response
                    RummyRPCStatus.unsupportedClient -> noteUpdateRequired()
                    else -> logNotice("ranking refused status=${response.status.rawValue}")
                }
            }
            is DuelCall.Failure -> if (isSchemaMissing(result.error)) noteServerMissing()
        }
    } finally {
        if (generation == resetGeneration) rankingInFlight = false
    }
}

// MARK: - 차단 거울

fun RummyStore.setHiddenPeers(ids: Set<SwiftUUID>) {
    if (hiddenPeerIDs == ids) return
    hiddenPeerIDs = ids
    publishLobby()
}

// MARK: - 내부

/** 거절 응답 한 줄(문구는 `RummyNoticeText` 표). 버전 거절은 화면 전체를 '업데이트 필요' 로 바꾼다. */
internal fun RummyStore.noteRefusal(response: RummyActionResponse, action: RummyNoticeText.Action) {
    logNotice("${action.rawValue} refused status=${response.status.rawValue}")
    applyRuby(response.rubyBalance)
    if (response.status == RummyRPCStatus.unsupportedClient) {
        noteUpdateRequired()
        return
    }
    setNotice(RummyNoticeText.status(response.status, action))
}

/** 받은 초대 카드 하나를 걷는다(원본과 거울 둘 다). */
internal fun RummyStore.dropInvite(roomID: SwiftUUID) {
    val raw = rawLobby ?: return
    val invites = raw.invites ?: return
    if (invites.none { it.id == roomID }) return
    rawLobby = raw.copy(invites = invites.filter { it.id != roomID })
    publishLobby()
}

/**
 * 방·판을 내린다(편집기·작업 전송·마감 깨우기까지). 로비 `me.room` 이 그 방이면 같이 걷는다 — 닫힘·나가기·빠짐을 안 순간 방 카드가
 * 내려가야 한다(다음 30초 로비 폴링까지 닫힌 방의 [시작]·[나가기] 가 남지 않게). 다음 로비 응답이 확인한다.
 */
fun RummyStore.clearMatch() {
    val cleared = match?.id
    if (cleared != null) {
        forgetRack(cleared)
        forgetEngaged(cleared)
    }
    pendingOwnReactions = mutableListOf()
    seenReactionKeys = mutableSetOf()
    if (reactionFeed.isNotEmpty()) reactionFeed = emptyList()
    lastSentLayout = null
    val raw = rawLobby
    if (cleared != null && raw != null && raw.me?.room?.id == cleared) {
        rawLobby = raw.copy(me = raw.me?.copy(room = null))
        publishLobby()
    }
    if (match != null) match = null
    if (editor != null) editor = null
    editorKey = null
    editorSeq = null
    lastSentDraft = null
    cancelDraft()
    deadlineJob?.cancel()
    deadlineJob = null
    deadlineWakeKey = null
    refreshPhase()
    pumpInviteQueue()
}
