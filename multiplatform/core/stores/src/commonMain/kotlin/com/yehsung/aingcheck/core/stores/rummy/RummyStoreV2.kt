// 원본: Sources/CheckCore/RummyStoreV2.swift:1 @ 1a5eeca6 · 뒤로 가기 판단은 Sources/check/CheckRummyWindow.swift:252(requestClose · confirmClose)
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.net.rummyHeartbeat
import com.yehsung.aingcheck.core.net.rummyLeave
import com.yehsung.aingcheck.core.net.rummyReact
import com.yehsung.aingcheck.core.net.rummyState
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyExitPolicy
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.rules.rummy.RummyRackEntry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummyRPCStatus
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray

// 아잉 큐브 스토어 — v2 자리: 판 배치 읽기 · 묶음 위치 이동 · 하트비트 · 의도적 이탈 · 이모티콘 반응 · 뽑기 사건 · 받침대 자리 로컬 저장.
// 규약은 RummyStore.kt 머리말 ⑪~⑮.

/**
 * 의도적 이탈의 계기(기록용 — 서버엔 같은 `rummy_leave` 다). 앞 넷은 맥 글자 그대로, 뒤 둘은 폰 몫(맥엔 뒤로 가기가 없고 계정 삭제는 이탈을 안 보낸다).
 */
enum class RummyExitReason(val rawValue: String) {
    windowClosed("window_closed"),
    appQuit("app_quit"),
    signOut("sign_out"),

    /** 판·방 중에 앱 업데이트를 골랐다. */
    appUpdate("app_update"),

    /** 폰 뒤로 가기(판 중 기권 확인 · 방 손님은 묻지 않고). */
    back("back"),

    /** 폰 계정 삭제(재인증을 지난 뒤 삭제 RPC 앞). */
    accountDeletion("account_deletion"),
}

/** 내 랙에 새로 들어온 타일 한 장(편집기 로컬 id · 면 · 받침대 자리). */
data class RummyDrawnTile(val tileID: Int, val face: RummyFace, val slot: RummyRackSlot)

/** 뽑기 사건(모션 계기). [serial] 은 스토어 안에서 1 부터 오른다. */
data class RummyDrawEvent(val serial: Int, val tiles: List<RummyDrawnTile>)

/** 반응 하나. [id] 는 스토어 안에서 오르는 번호, [receivedAt] 은 기기 시계(말풍선 2.5초 기준). */
data class RummyReactionEvent(val id: Int, val seatNo: Long, val sticker: AingSticker, val isMine: Boolean, val receivedAt: SwiftDate)

// MARK: - 판 배치 읽기

/** 확정 판(`match.table`)의 배치. 빈 자리는 결정적 자동 배치로 채운다(모든 기기가 같다). 판이 없으면 빈 배치. */
val RummyStore.confirmedLayout: RummyTableLayout
    get() {
        val current = match ?: return RummyTableLayout.empty
        return RummyTableLayout(sets = current.table ?: emptyList(), layout = current.tableLayout)
    }

/** 남의 차례면 그 사람 작업 판의 배치([RummyStore.otherDraft] 의 짝). 없으면 null(→ [confirmedLayout]). */
val RummyStore.otherDraftLayout: RummyTableLayout?
    get() {
        val sets = otherDraft ?: return null
        return RummyTableLayout(sets = sets, layout = match?.draft?.layout)
    }

/** v2 묶음 통째 위치 이동(내 차례만 — 배치도 작업 상태라 서버로 간다). 판 좌표 왼쪽 위, 가장 가까운 빈자리로 스냅. */
fun RummyStore.moveSet(setIndex: Int, point: RummyPoint) {
    if (!isMyTurn) return
    val working = editor?.copy() ?: return
    if (!working.moveSet(setIndex, point) || editor == working) return
    editor = working
    setNotice(null)
    scheduleDraft()
}

// MARK: - 하트비트(머리말 ⑫)

/**
 * phase 가 room·playing 이고 **이 기기가 손댄 판**(머리말 ⑮)이면 그 판의 하트비트를 돌리고, 아니면 멈춘다.
 * 같은 조건으로 [RummyStore.isHoldingMatch] 도 쥐고 놓는다. `refreshPhase` 와 engaged 장부 · 앱 수명이 늘 부른다.
 */
internal fun RummyStore.updateHeartbeat() {
    val current = match
    val holding = host?.session != null && (phase == RummyPhase.room || phase == RummyPhase.playing) && current != null && isEngaged(current.id)
    // 기권(forfeit)·끝(done)한 뒤 남의 판을 지켜보는 동안은 쥐지 않는다. 하트비트는 그대로 둔다(서버가 joined·playing 자리만 갱신한다).
    val seatState = current?.let { mySeat(it) }?.state
    setHoldingMatch(holding && seatState != RummySeatState.forfeit && seatState != RummySeatState.done)
    val wanted = if (heartbeatEnabled && holding && !isAppInBackground) current?.id else null
    if (wanted == heartbeatMatchID) return
    heartbeatJob?.cancel()
    heartbeatJob = null
    heartbeatMatchID = wanted
    val matchID = wanted ?: return
    val generation = resetGeneration
    heartbeatJob = scope.launch {
        while (true) {
            delay(delayMillis(heartbeatSeconds))
            if (generation != resetGeneration || heartbeatMatchID != matchID) return@launch
            heartbeatTick(matchID)
        }
    }
}

/** 하트비트 한 번. 자리가 없어졌으면(`not_found`) 따라잡기 조회를 건다. 이 기기가 손대지 않은 판엔 보내지 않는다(⑮). */
suspend fun RummyStore.heartbeatTick(matchID: SwiftUUID) {
    if (host?.session == null || !isEngaged(matchID)) return
    val result = perform("heartbeatTick") { service, token -> service.rummyHeartbeat(token, matchID) } ?: return
    when (result) {
        is DuelCall.Success -> {
            val response = result.value
            noteServerNow(response.serverNowMs)
            when (response.status) {
                RummyRPCStatus.ok -> Unit
                RummyRPCStatus.notFound -> requestSync()
                RummyRPCStatus.unsupportedClient -> noteUpdateRequired()
                else -> logNotice("heartbeat refused status=${response.status.rawValue}")
            }
        }
        is DuelCall.Failure -> if (isSchemaMissing(result.error)) logNotice("heartbeat missing on server")
    }
}

// MARK: - 앱 수명(폰 몫 — 정책은 이 두 함수 한 곳)

/**
 * 앱이 뒤로 갔다. **기권하지 않는다**(결정 10-31): 잠깐 알림을 보고 돌아온 사람의 판돈을 잃게 하지 않는다. 하트비트만 멈춰 서버 90초 끊김 규칙에 맡긴다 —
 * 프로세스가 살아 있는 동안 하트비트를 계속 내면 그 규칙이 안 돌아 자리를 비운 사람 때문에 남들이 매 차례 시간 초과를 기다린다.
 * 사용자 답이 달라지면 **여기 한 곳**만 고친다(즉시 기권이면 `scope.launch { leaveForExit(...) }` 한 줄).
 */
fun RummyStore.appDidEnterBackground() {
    isAppInBackground = true
    updateHeartbeat()
}

/** 앱이 앞으로 왔다. 다음 10초를 기다리지 않고 **바로 한 번** 보낸다(뒤에 있던 공백을 90초 판정 전에 메운다 — 맥 didWake 와 같은 뜻). */
fun RummyStore.appDidBecomeActive() {
    isAppInBackground = false
    updateHeartbeat()
    val matchID = heartbeatMatchID ?: return
    scope.launch { heartbeatTick(matchID) }
}

// MARK: - 의도적 이탈(머리말 ⑫)

/**
 * 뒤로 가기 · 로그아웃 · 계정 삭제. 방(forming)이면 방 나가기(방장이면 방 닫기), 판(active)이면 **즉시 기권**(`rummy_leave`).
 * 서버 답을 최대 [RummyStore.exitLeaveLimitSeconds](2초) 기다린다. 답과 무관하게 이 기기에선 판을 접는다(하트비트도 멈춘다) —
 * 서버에 못 닿았으면 90초 끊김 기권이 마무리한다. 반환: 서버가 나감을 확인했는가(끝난 판·판 없음은 true).
 * [RummyStore.isWorking] 과 무관하게 돈다. **이 기기가 손대지 않은 판이면 아무것도 보내지 않고 true**(머리말 ⑮).
 */
suspend fun RummyStore.leaveForExit(reason: RummyExitReason): Boolean {
    val current = match
    if (current == null || !RummyStore.isUnsettled(current.status) || host?.session == null) return true
    if (!isEngaged(current.id)) {
        logNotice("exit leave skipped: not engaged on this device reason=${reason.rawValue}")
        return true
    }
    val matchID = current.id
    logNotice("exit leave reason=${reason.rawValue}")
    val answer = CompletableDeferred<Boolean>()
    scope.launch {
        val result = perform("leaveForExit") { service, token -> service.rummyLeave(token, matchID) }
        if (result is DuelCall.Success) {
            noteServerNow(result.value.serverNowMs)
            // not_found = 이미 자리가 없다(나간 것과 같다).
            answer.complete(result.value.status == RummyRPCStatus.ok || result.value.status == RummyRPCStatus.notFound)
        } else {
            answer.complete(false)
        }
    }
    val confirmed = withTimeoutOrNull(delayMillis(RummyStore.exitLeaveLimitSeconds)) { answer.await() } ?: false
    dismissedMatchIDs = dismissedMatchIDs + matchID
    matchRevision += 1
    if (activeMatchID == matchID) activeMatchID = null
    if (match?.id == matchID) clearMatch()
    return confirmed
}

/**
 * 방 손님의 **묻지 않는** 이탈. 들고 있는 것은 방(forming)이어도 그새 방장이 시작했으면(시작 신호가 이 기기에 닿기 전) `rummy_leave` 는 **판 기권**이다 —
 * 묻지도 않고 판돈을 잃게 된다. 그래서 먼저 그 방 state 를 한 번 읽는다(상한 2초). 판이 시작돼 내 자리가 playing 이면 나가지 않고 그 state 를 든다.
 * 아직 방이거나 못 읽었으면 나간다. 반환: 나갔으면 [leaveForExit] 의 답, 시작된 판을 들고 남았으면 false.
 */
suspend fun RummyStore.leaveRoomForExit(reason: RummyExitReason): Boolean {
    val current = match
    if (current == null || current.status != RummyMatchStatus.forming || host?.session == null || !isEngaged(current.id)) {
        return leaveForExit(reason)
    }
    val roomID = current.id
    val ticket = issueTicket()
    val answer = CompletableDeferred<RummyMatchState?>()
    scope.launch {
        val result = perform("leaveRoomForExit") { service, token -> service.rummyState(token, roomID) }
        if (result is DuelCall.Success && result.value.status == RummyRPCStatus.ok) {
            noteServerNow(result.value.serverNowMs)
            answer.complete(result.value.state)
        } else {
            answer.complete(null)
        }
    }
    val fetched = withTimeoutOrNull(delayMillis(RummyStore.exitLeaveLimitSeconds)) { answer.await() }
    if (fetched != null && fetched.id == roomID && fetched.status == RummyMatchStatus.active && match?.id == roomID &&
        mySeat(fetched)?.state == RummySeatState.playing
    ) {
        logNotice("exit leave skipped: room already started")
        applyState(fetched, ticket)
        return false
    }
    return leaveForExit(reason)
}

// MARK: - 뒤로 가기(폰 — 맥 창 닫기 판단을 그대로)

/** 지금 뒤로 가면 어떻게 되는가(순수 판단은 [RummyExitPolicy]). 놀던 기기는 언제나 그냥 닫힌다. */
val RummyStore.closeDecision: RummyCloseDecision
    get() = RummyExitPolicy.closeDecision(phase, RummyExitPolicy.mySeat(match)?.state, RummyExitPolicy.amHost(match), isEngagedInCurrentMatch)

/** 로그아웃 앞에 `rummy_leave` 를 보낼 판·방이 있는가. 이미 기권한 관전자는 보낼 것이 없다. */
val RummyStore.needsExitLeave: Boolean
    get() = RummyExitPolicy.needsExitLeave(phase, RummyExitPolicy.mySeat(match)?.state, isEngagedInCurrentMatch)

/**
 * 뒤로 가기를 눌렀다. 돌려준 값이 `confirmForfeit`·`confirmCloseRoom` 이면 화면이 확인을 띄우고 [confirmBack] 을 부른다. 그 밖이면 바로 떠나도 된다
 * (`leaveRoom` 은 여기서 이미 나가기를 띄웠다 — 그새 판이 시작됐으면 기권을 보내지 않고 판을 든다).
 */
fun RummyStore.requestBack(): RummyCloseDecision {
    val decision = closeDecision
    if (decision == RummyCloseDecision.leaveRoom) scope.launch { leaveThenSettle { leaveRoomForExit(RummyExitReason.back) } }
    return decision
}

/**
 * 확인을 골랐다. 묻던 사이 판단이 바뀌었으면(방장 확인 중 판이 시작됐다 · 판이 끝났다) **지금 판단**으로 간다 —
 * "루비는 그대로예요" 를 읽고 고른 버튼이 판돈을 잃는 기권이 되면 안 된다.
 * 반환: null = 떠나도 된다(이탈은 뒤에서 돈다) · 값 = 그 새 문구로 **다시 묻는다**.
 */
fun RummyStore.confirmBack(asked: RummyCloseDecision): RummyCloseDecision? {
    val now = closeDecision
    when {
        now == asked && asked == RummyCloseDecision.confirmCloseRoom -> scope.launch { leaveThenSettle { leaveRoomForExit(RummyExitReason.back) } }
        now == asked -> scope.launch { leaveThenSettle { leaveForExit(RummyExitReason.back) } }
        now == RummyCloseDecision.close -> Unit
        now == RummyCloseDecision.leaveRoom -> scope.launch { leaveThenSettle { leaveRoomForExit(RummyExitReason.back) } }
        else -> return now
    }
    return null
}

/**
 * 뒤로 나간 뒤 안내줄을 지우고 로비를 다시 읽는다(코어 `dismissResult` 처럼 — Swift `GamesRummyExit.settleAfterLeaving` @ c9f6976f). 안 읽으면 낡은 `activeMatchId` 로 게임 탭 카드가 최대 30초
 * '판 진행 중'이고, 닫힌 방이 공개 목록에 남는다. 시작된 판을 들고 남았으면(`leaveRoomForExit`) 아무것도 안 한다. 로그아웃 길은 부르지 않는다 — 세션이 곧 끝난다.
 */
private suspend fun RummyStore.leaveThenSettle(leave: suspend () -> Unit) {
    leave()
    if (match != null) return
    setNotice(null)
    refreshLobby()
}

// MARK: - 이모티콘 반응(머리말 ⑬)

/** 지금 반응을 보낼 수 있는가(판·방이 있고 쿨다운이 지났다). 버튼 흐리기용. */
fun RummyStore.canReact(date: SwiftDate): Boolean =
    match != null && date.timeIntervalSince(lastReactionSentAt) >= RummyStore.reactionCooldownSeconds

/** 반응 보내기. 쿨다운(2초) 안이거나 판이 없으면 false(아무것도 안 한다). 내 말풍선은 바로 낸다. */
fun RummyStore.sendReaction(sticker: AingSticker): Boolean {
    val current = match ?: return false
    if (host?.session == null) return false
    val now = clock()
    if (!canReact(now)) return false
    lastReactionSentAt = now
    val matchID = current.id
    val key = sticker.rawValue
    markEngaged(matchID)
    val seat = RummyStore.mySeat(current, myUserID)?.seatNo ?: current.mySeatNo
    if (seat != null) {
        pendingOwnReactions.add(key to now)
        emitReaction(seat, sticker, isMine = true)
    }
    scope.launch {
        val result = perform("sendReaction") { service, token -> service.rummyReact(token, matchID, key) }
        if (result !is DuelCall.Success) return@launch
        noteServerNow(result.value.serverNowMs)
        if (result.value.status != RummyRPCStatus.ok) {
            // 메아리가 안 온다 — 기다리던 것을 걷는다.
            val index = pendingOwnReactions.indexOfFirst { it.first == key }
            if (index >= 0) pendingOwnReactions.removeAt(index)
            logNotice("react refused status=${result.value.status.rawValue}")
        }
    }
    return true
}

/** state 의 `reactions` 에서 처음 보는 것만 낸다(오래된 것부터). 모르는 키는 버린다. 내 것의 메아리는 한 번 삼킨다. */
internal fun RummyStore.noteReactions(state: RummyMatchState) {
    val now = clock()
    pendingOwnReactions.removeAll { now.timeIntervalSince(it.second) > RummyStore.reactionEchoSeconds }
    val reactions = state.reactions
    if (reactions.isNullOrEmpty()) return
    val mine = RummyStore.mySeat(state, myUserID)?.seatNo ?: state.mySeatNo
    val prefix = state.id.lowercased
    for (reaction in reactions.asReversed()) {
        val seat = reaction.seatNo ?: continue
        // Swift `RummyReaction.sticker` = `AingSticker(rawValue:)` — 와이어 모듈은 이모티콘 표를 모른다.
        val sticker = AingSticker.entries.firstOrNull { it.rawValue == reaction.key } ?: continue
        val key = "$prefix#$seat#${sticker.rawValue}#${(reaction.atMs ?: 0.0).toLong()}"
        if (!seenReactionKeys.add(key)) continue
        if (seat == mine) {
            val index = pendingOwnReactions.indexOfFirst { it.first == sticker.rawValue }
            if (index >= 0) {
                pendingOwnReactions.removeAt(index)
                continue
            }
        }
        emitReaction(seat, sticker, isMine = seat == mine)
    }
}

internal fun RummyStore.emitReaction(seatNo: Long, sticker: AingSticker, isMine: Boolean) {
    reactionSerial += 1
    val event = RummyReactionEvent(reactionSerial, seatNo, sticker, isMine, clock())
    reactionFeed = (reactionFeed + event).takeLast(RummyStore.reactionFeedLimit)
    onReaction?.invoke(event)
}

// MARK: - 뽑기 사건(머리말 ⑬)

/**
 * 같은 판의 앞 편집기와 새 편집기를 대어 새로 들어온 면(다중집합 차)을 찾는다 — 그 타일(앞 자리 목록에 없던 자리).
 * 0.3.70: 찾기와 알리기를 나눴다 — 정렬이 살아 있으면 그 사이에 받침대를 다시 정렬한다(`reconcileEditor`).
 */
internal fun RummyStore.Companion.drawnTiles(previous: RummyTurnEditor, fresh: RummyTurnEditor, entries: List<RummyRackEntry>): List<RummyDrawnTile> {
    val gained = HashMap<RummyFace, Int>()
    for (face in fresh.startRackFaces) gained[face] = (gained[face] ?: 0) + 1
    for (face in previous.startRackFaces) gained[face] = (gained[face] ?: 0) - 1
    if (gained.values.none { it > 0 }) return emptyList()
    val known = entries.toSet()
    val tiles = ArrayList<RummyDrawnTile>()
    // 새 타일은 마지막 빈자리로 갔다 — 뒤에서부터 고른다(같은 면이 둘이면 앞 자리 목록에 없는 쪽).
    val layout = fresh.rackLayout
    for (tile in fresh.rack.asReversed()) {
        if ((gained[tile.face] ?: 0) <= 0) continue
        val slot = layout.slot(tile.id) ?: continue
        if (RummyRackEntry(tile.face, slot) in known) continue
        gained[tile.face] = (gained[tile.face] ?: 0) - 1
        tiles.add(0, RummyDrawnTile(tile.id, tile.face, slot))
    }
    return tiles
}

/** 뽑기 사건을 알린다(모션 · 3초 빛남 계기). */
internal fun RummyStore.noteDrawn(tiles: List<RummyDrawnTile>) {
    if (tiles.isEmpty()) return
    drawSerial += 1
    val event = RummyDrawEvent(drawSerial, tiles)
    lastDraw = event
    onTileDrawn?.invoke(event)
}

// MARK: - 한 계정 기기 여럿(머리말 ⑮)

/**
 * 확성기 배너를 미뤄야 하는 판인가(맥 `MegaphoneBannerDeferral` · 폰 `MegaphoneBannerPhoneRules.isDeferred` 가 읽는다).
 * 이 기기가 손댄 판이 진행 중이고 내 자리가 아직 playing 일 때만 참. 놀던 기기 · 기권 뒤 구경은 미루지 않는다.
 */
val RummyStore.defersMegaphoneBanner: Boolean
    get() {
        val current = match
        if (phase != RummyPhase.playing || current == null || !isEngaged(current.id)) return false
        val seat = RummyStore.mySeat(current, myUserID)
        return seat?.state == null || seat.state == RummySeatState.playing
    }

/**
 * 한 사람 한 판(B8)의 재료: 들고 있는 방·판에 내 자리가 아직 있는가. 서버 `chess__busy` 와 같은 술어다 — 모으는 방에 앉았거나(joined) 판 중(playing).
 * 기권·끝난 자리는 구경일 뿐 바쁘지 않다.
 */
val RummyStore.holdsLiveSeat: Boolean
    get() {
        val current = match ?: return false
        if (!RummyStore.isUnsettled(current.status)) return false
        val state = RummyStore.mySeat(current, myUserID)?.state
        return state != RummySeatState.forfeit && state != RummySeatState.done
    }

/** 이 기기가 이 판에 손댄 적이 있는가(create·join·start·draft·play·draw·react 를 보냈다). **지금 계정의 장부일 때만.** */
fun RummyStore.isEngaged(matchID: SwiftUUID): Boolean = matchID in engagedMatchIDs && engagedLedgerIsMine

/** 장부 주인이 지금 계정인가. 주인을 모르거나(세션 전에 적었다) 세션이 없으면 믿는다(세션 없는 문은 따로 막혀 있다). */
internal val RummyStore.engagedLedgerIsMine: Boolean
    get() {
        val owner = engagedOwnerUserID ?: return true
        val me = myUserID ?: return true
        return owner == me
    }

/** 들고 있는 판이 이 기기가 손댄 판인가 — 뒤로 가기·로그아웃 판단이 읽는다. */
val RummyStore.isEngagedInCurrentMatch: Boolean get() = match?.let { isEngaged(it.id) } ?: false

/** 판에 쓰기를 **보내기 직전에** 부른다. 처음이면 장부에 적고(저장소가 있으면 남긴다) 하트비트를 다시 맞춘다. */
fun RummyStore.markEngaged(matchID: SwiftUUID) {
    var changed = false
    val me = myUserID
    if (me != null && engagedOwnerUserID != me) {
        // 다른 계정의 장부(강제 로그아웃으로 남았다) — 버리고 이 계정 것으로 연다. 주인을 몰랐으면 지금 계정으로 적는다.
        if (engagedOwnerUserID != null) engagedMatchIDs = emptyList()
        engagedOwnerUserID = me
        changed = true
    }
    if (matchID !in engagedMatchIDs) {
        engagedMatchIDs = (engagedMatchIDs + matchID).takeLast(RummyStore.engagedLimit)
        changed = true
    }
    if (!changed) return
    saveEngaged()
    updateHeartbeat()
}

/** 판이 끝났다·접혔다·닫혔다 — 장부에서 지운다. */
fun RummyStore.forgetEngaged(matchID: SwiftUUID) {
    if (matchID !in engagedMatchIDs) return
    engagedMatchIDs = engagedMatchIDs - matchID
    saveEngaged()
    updateHeartbeat()
}

internal fun RummyStore.setHoldingMatch(holding: Boolean) {
    if (holding == isHoldingMatch) return
    isHoldingMatch = holding
    logNotice("holding match $holding")
    onHoldingMatchChange?.invoke(holding)
}

/** [KeyValueStore][com.yehsung.aingcheck.core.foundation.platform.KeyValueStore] 에는 목록 칸이 없어 JSON 글자 한 칸으로 둔다(Tetris '이 기기가 연 판' 선례). */
internal fun RummyStore.saveEngaged() {
    val defaults = engagedDefaults ?: return
    defaults.putString(RummyStore.engagedDefaultsKey, JsonArray(engagedMatchIDs.map { JsonPrimitive(it.lowercased) }).toString())
    val owner = engagedOwnerUserID
    if (owner != null) defaults.putString(RummyStore.engagedOwnerDefaultsKey, owner) else defaults.remove(RummyStore.engagedOwnerDefaultsKey)
}

/**
 * 저장소를 넣은 순간 저장된 목록을 앞에 합친다(앱을 다시 켜도 쥐던 판의 하트비트·이탈이 이어진다).
 * 저장된 주인이 메모리 장부의 주인과 다르면 저장된 것은 남의 장부라 합치지 않는다.
 */
internal fun RummyStore.loadEngaged() {
    val defaults = engagedDefaults ?: return
    val text = defaults.getString(RummyStore.engagedDefaultsKey) ?: return
    val stored: List<SwiftUUID> = try {
        Json.parseToJsonElement(text).jsonArray.mapNotNull { (it as? JsonPrimitive)?.content?.let { raw -> SwiftUUID.parse(raw) } }
    } catch (ignored: IllegalArgumentException) {
        return // 깨진 글자는 기록이 없는 것과 같다(SerializationException 도 여기로 온다)
    }
    val storedOwner = defaults.getString(RummyStore.engagedOwnerDefaultsKey)
    var merged = stored
    val current = engagedOwnerUserID
    if (current != null) {
        if (storedOwner != null && storedOwner != current) merged = emptyList()
    } else {
        engagedOwnerUserID = storedOwner
    }
    merged = merged + engagedMatchIDs.filter { it !in merged }
    engagedMatchIDs = merged.takeLast(RummyStore.engagedLimit)
    updateHeartbeat()
}

// MARK: - 받침대 자리 로컬 저장(머리말 ⑭)

private val rackEntriesSerializer = ListSerializer(RummyRackEntry.serializer())

/** 지금 편집기의 받침대 자리(판에 나간 타일은 나간 자리로 돌린 모양)를 판 id 키로 저장한다. 면이 와이어 타입이라 **SwiftJson 으로만** 쓴다. */
internal fun RummyStore.saveRack() {
    val defaults = rackDefaults ?: return
    val working = editor ?: return
    val matchID = editorKey?.matchID ?: return
    defaults.putString(RummyStore.rackDefaultsKey(matchID), SwiftJson.encode(rackEntriesSerializer, working.restoredRackEntries))
}

/** 저장된 받침대 자리. 깨졌으면 null(면 순서로 돌아간다 — Swift `try?`). 일반 Json 디코더는 면 타입을 거절한다. */
internal fun RummyStore.loadRackEntries(matchID: SwiftUUID): List<RummyRackEntry>? {
    val text = rackDefaults?.getString(RummyStore.rackDefaultsKey(matchID)) ?: return null
    return try {
        SwiftJson.decode(rackEntriesSerializer, text)
    } catch (ignored: IllegalArgumentException) {
        null // SwiftDecodingException · SerializationException 도 여기로 온다
    }
}

internal fun RummyStore.forgetRack(matchID: SwiftUUID) {
    rackDefaults?.remove(RummyStore.rackDefaultsKey(matchID))
}
