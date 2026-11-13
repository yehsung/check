// 원본: Sources/CheckCore/MahjongStoreLobby.swift @ e4995a3a(로비 · 방(forming) · 초인종 · 순위) — Android 판 8
//
// 초인종 합치기: 도는 중에 온 신호는 끝난 뒤 정확히 한 번 더. 서버 `match`(방 포함)가 있으면 그 판 state, 없으면 로비.
// ⓓ writeRevision: 쓰기 응답보다 먼저 나간 로비는 잔액 · active_match_id 를 덮지 않는다(방이 판이 됐다는 판정에는 쓴다).
// Android: 판돈 대결 스위치(`AppConfig.duelsEnabled`)가 꺼지면 만들기 · 참가 · 초대 · 시작을 보내지 않는다(G §8-17 #1).
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.wire.SwiftUUID
import kotlinx.coroutines.launch

/** 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 한 번 더. 로비가 내 진행 판 · 방을 말하는데 들고 있지 않으면 그 판을 읽어 세운다. */
internal suspend fun MahjongStore.refreshLobby() {
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
            val writes = writeRevision
            val result = perform { s, t -> s.mahjongLobby(t) } ?: return
            when (result) {
                is DuelCall.Success -> {
                    val response = result.value
                    applyLobby(response, predatesWrite = writes != writeRevision)
                    if (response.status != MahjongRPCStatus.ok) continue
                    val active = response.me?.activeMatchId?.lowercase()
                    val held = match?.match
                    val roomID = response.me?.room?.id?.lowercased
                    if (active != null && (held?.id != active || held.matchStatus != MahjongMatchStatus.active)) {
                        dismissedMatchIDs.remove(active)
                        refreshMatch(active)
                    } else if (active == null && (held == null || held.matchStatus.isTerminal) && roomID != null && held?.id != roomID) {
                        // 다른 기기에서 만든 · 참가한 방 — 그 방을 세운다(장부엔 안 적는다).
                        refreshMatch(roomID)
                    }
                }
                is DuelCall.Failure -> if (isSchemaMissing(result.error)) noteServerMissing()
            }
        } while (lobbyAgain && generation == resetGeneration)
    } finally {
        if (generation == resetGeneration) lobbyInFlight = false
    }
}

/** 로비 응답 하나를 넣는다(픽스처 문 — 쓰기 뒤 판정 없이 지금 것으로 친다). */
fun MahjongStore.applyLobby(response: MahjongLobbyResponse) = applyLobby(response, predatesWrite = false)

internal fun MahjongStore.applyLobby(response: MahjongLobbyResponse, predatesWrite: Boolean) {
    noteServerClock(response.serverNowMs)
    when (response.status) {
        MahjongRPCStatus.ok -> if (availability != MahjongAvailability.available) availability = MahjongAvailability.available
        MahjongRPCStatus.unsupportedClient -> {
            noteUpdateRequired()
            return
        }
        MahjongRPCStatus.unauthorized -> {
            setNotice(MahjongNoticeText.signInAgain)
            return
        }
        else -> return
    }
    val u = response.users ?: emptyList()
    if (users != u) users = u
    val pr = response.publicRooms ?: emptyList()
    if (publicRooms != pr) publicRooms = pr
    val arriving = response.invites ?: emptyList()
    if (invites != arriving) invites = arriving
    val stakes = response.stakes
    val first = stakes?.firstOrNull()
    if (stakes != null && first != null && selectedStake.rawValue !in stakes) selectedStake = MahjongStake.of(first) ?: selectedStake
    response.me?.let { me ->
        me.record?.let { if (record != it) record = it }
        lobbyRoom = me.room
        if (!predatesWrite) {
            applyRuby(me.rubyBalance)
            activeMatchID = me.activeMatchId?.lowercase()
        }
    }
    // 처음 본 초대만 알린다(장부와 무관 — 모든 기기). 차단한 방장의 초대는 본 것으로만 적는다.
    for (room in invites) {
        if (!seenInviteIDs.add(room.id)) continue
        if (visibleInvites.any { it.id == room.id }) onInviteArrived?.invoke(room)
    }
    recomputePhase()
}

// MARK: 방 동작

/** 방 만들기(selectedStake · selectedPublic · selectedFormat). ok 면 장부에 적는다. */
suspend fun MahjongStore.createRoom() {
    if (isWorking || host?.session == null || !duelsEnabled) return
    val stake = selectedStake.rawValue
    val isPublic = selectedPublic
    val format = selectedFormat.rawValue
    runRoomAction(MahjongNoticeText.Action.create) { s, t -> s.mahjongCreate(t, stake, isPublic, format) }
}

/** 방에 초대(방장만). */
suspend fun MahjongStore.invite(userID: SwiftUUID) {
    val room = match?.match ?: return
    if (isWorking || room.matchStatus != MahjongMatchStatus.forming || !duelsEnabled) return
    val roomID = room.id
    val target = userID.lowercased
    runRoomAction(MahjongNoticeText.Action.invite) { s, t -> s.mahjongInvite(t, roomID, target) }
}

/** 초대 · 공개 방 참가. ok 면 장부에 적는다. */
suspend fun MahjongStore.join(roomID: SwiftUUID) {
    if (isWorking || !duelsEnabled) return
    val id = roomID.lowercased
    runRoomAction(MahjongNoticeText.Action.join) { s, t -> s.mahjongJoin(t, id) }
}

suspend fun MahjongStore.decline(roomID: SwiftUUID) {
    if (isWorking) return
    val id = roomID.lowercased
    // 이 기기에서 답했다 — 카드를 걷는다(응답이 늦어도 다시 안 뜬다).
    invites = invites.filter { it.id != roomID }
    runRoomAction(MahjongNoticeText.Action.decline) { s, t -> s.mahjongDecline(t, id) }
}

/** 방에서 나가기(방장이면 방 닫기). 판 중 [나가기]는 leaveTable(). */
suspend fun MahjongStore.leaveRoom() {
    val room = match?.match ?: return
    if (isWorking || room.matchStatus != MahjongMatchStatus.forming) return
    val id = room.id
    runRoomAction(MahjongNoticeText.Action.leave) { s, t -> s.mahjongLeave(t, id) }
}

/** 방장 [시작](넷이 모였을 때). */
suspend fun MahjongStore.start() {
    val room = match?.match ?: return
    if (isWorking || !canStart || !duelsEnabled) return
    val id = room.id
    runRoomAction(MahjongNoticeText.Action.start) { s, t -> s.mahjongStart(t, id) }
}

/** 방 동작 하나 — 잠금 · 요청 표 · ⓓ · 장부(만들기 · 참가 · 시작 ok) · 문구 · 실린 state 적용. */
internal suspend fun MahjongStore.runRoomAction(action: MahjongNoticeText.Action, operation: suspend (SupabaseWorkService, String) -> MahjongActionResponse) {
    if (host?.session == null) return
    actionToken += 1
    val token = actionToken
    isWorking = true
    setNotice(null)
    val generation = resetGeneration
    try {
        val ticket = issueTicket()
        when (val result = perform(operation) ?: return) {
            is DuelCall.Failure -> noteActionFailure(result.error)
            is DuelCall.Success -> {
                writeRevision += 1
                noteServerClock(result.value.serverNowMs)
                handleRoomResponse(result.value, action, ticket)
            }
        }
    } finally {
        if (generation == resetGeneration && token == actionToken && isWorking) isWorking = false
    }
}

internal fun MahjongStore.handleRoomResponse(response: MahjongActionResponse, action: MahjongNoticeText.Action, ticket: Int) {
    when (response.status) {
        MahjongRPCStatus.unsupportedClient -> {
            noteUpdateRequired()
            return
        }
        MahjongRPCStatus.seatsDropped -> {
            val me = myUserID
            if (response.reasons?.keys?.any { it.lowercase() == me } == true || response.dropped?.any { it.lowercase() == me } == true) {
                setNotice(MahjongNoticeText.droppedAtStart)
                match?.match?.id?.let(::leaveHeldRoom)
                return
            }
            setNotice(MahjongNoticeText.droppedOthers(response.reasons?.values?.toList() ?: emptyList()))
        }
        MahjongRPCStatus.ok -> setNotice(if (action == MahjongNoticeText.Action.invite) MahjongNoticeText.invited else null)
        else -> setNotice(MahjongNoticeText.status(response.status, action, response.need, response.have))
    }
    val state = response.state
    val id = state?.match?.id ?: response.matchId?.lowercase()
    if (response.status == MahjongRPCStatus.ok && id != null) {
        when (action) {
            MahjongNoticeText.Action.create, MahjongNoticeText.Action.join, MahjongNoticeText.Action.start -> noteOwnsMatch(id)
            MahjongNoticeText.Action.leave -> if (state?.match?.matchStatus != MahjongMatchStatus.active) dropOwnership(id)
            else -> Unit
        }
    }
    // 나갔던 방에 다시 참가했다 — 그 방의 접은 기록을 지운다.
    if (response.status == MahjongRPCStatus.ok && (action == MahjongNoticeText.Action.create || action == MahjongNoticeText.Action.join) && id != null) {
        dismissedMatchIDs.remove(id)
    }
    if (state != null) {
        applyState(state, requestedSince = 0, rawTicket = ticket, predatesWrite = false)
        if (response.status == MahjongRPCStatus.ok && action == MahjongNoticeText.Action.leave &&
            state.match?.matchStatus != MahjongMatchStatus.active && id != null
        ) leaveHeldRoom(id)
    } else if (response.status == MahjongRPCStatus.ok && action == MahjongNoticeText.Action.leave) {
        match?.match?.id?.let(::leaveHeldRoom)
    } else if ((response.status == MahjongRPCStatus.roomClosed || response.status == MahjongRPCStatus.notFound) &&
        action != MahjongNoticeText.Action.invite && action != MahjongNoticeText.Action.create
    ) {
        val held = match?.match
        if (held != null && held.matchStatus == MahjongMatchStatus.forming) leaveHeldRoom(held.id)
    }
    val refreshes = action == MahjongNoticeText.Action.create || action == MahjongNoticeText.Action.join ||
        action == MahjongNoticeText.Action.leave || action == MahjongNoticeText.Action.decline
    if (response.status == MahjongRPCStatus.ok && refreshes) {
        scope.launch { refreshLobby() }
    } else if (action == MahjongNoticeText.Action.leave && (response.status == MahjongRPCStatus.notFound || response.status == MahjongRPCStatus.roomClosed)) {
        scope.launch { refreshLobby() }
    }
}

/** 들고 있던 방을 내린다(나가기 ok · 닫힌 방). 그 방의 늦은 응답은 버린다(가드 (a)). */
internal fun MahjongStore.leaveHeldRoom(id: String) {
    dismissedMatchIDs.add(id)
    dropOwnership(id)
    if (match?.match?.id == id) match = null
    if (lobbyRoom?.id?.lowercased == id) lobbyRoom = null
    recomputePhase()
}

// MARK: 계기

/** 실시간 초인종 'mahjong'. */
fun MahjongStore.handleSignal() = requestSync()

/** 실시간 채널이 (다시) 붙었다. */
fun MahjongStore.realtimeDidJoin() = requestSync()

/** 기기가 깨어났다(앱이 앞으로) — 판 · 방 · 로비를 한 번 읽는다. */
fun MahjongStore.systemDidWake() {
    if (host?.session == null) return
    scope.launch {
        syncOnce()
        if (match != null) refreshLobby()
    }
}

/** 화면이 열렸다 — 로비가 오래됐으면 읽는다(30초 스로틀). */
fun MahjongStore.refreshLobbyIfStale() {
    if (host?.session == null) return
    val now = clock()
    if (now.timeIntervalSince(lastMenuLobbyAt) < MahjongStore.menuLobbyThrottleSeconds) return
    lastMenuLobbyAt = now
    scope.launch { refreshLobby() }
}

/** 로비를 지금 읽는다(화면 진입 · 당겨서 새로고침). */
fun MahjongStore.loadLobby() {
    scope.launch { refreshLobby() }
}

/** 순위(rankingEnabled 일 때만). 10판 미만이면 me.rank 는 null(서버 것 그대로). */
internal suspend fun MahjongStore.refreshRanking() {
    if (!rankingEnabled || host?.session == null) return
    lastRankingRequestAt = clock()
    when (val result = perform { s, t -> s.mahjongRanking(t) } ?: return) {
        is DuelCall.Success -> {
            val response = result.value
            noteServerClock(response.serverNowMs)
            if (response.status == MahjongRPCStatus.ok) {
                if (ranking != response) ranking = response
                if (rankingUnavailable) rankingUnavailable = false
            } else {
                if (response.status == MahjongRPCStatus.unsupportedClient) noteUpdateRequired()
                if (!rankingUnavailable) rankingUnavailable = true
            }
        }
        is DuelCall.Failure -> {
            if (isSchemaMissing(result.error)) noteServerMissing()
            if (!rankingUnavailable) rankingUnavailable = true
        }
    }
}

/** 순위를 지금 읽는다(순위 칸을 열 때). */
fun MahjongStore.loadRanking() {
    scope.launch { refreshRanking() }
}
