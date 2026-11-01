// 원본: Sources/CheckCore/RummyStoreGame.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.net.rummyDraft
import com.yehsung.aingcheck.core.net.rummyDraw
import com.yehsung.aingcheck.core.net.rummyPlay
import com.yehsung.aingcheck.core.net.rummyState
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummyRules
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyActionResponse
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyRPCStatus
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 아잉 큐브 스토어 — state 깔때기 · 편집기 재구성 · 차례 동작(끌기·되돌리기·정렬·완료·뽑기) · 작업 상태 전송 · 마감.
// 규약은 RummyStore.kt 머리말 ①~⑩.

// MARK: - 판 조회

/**
 * 한 방·판의 state 를 읽는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다.
 * 도는 중에 **다른 판** id 가 들어오면 기억했다가 지금 것을 끝낸 뒤 그 판을 한 번 읽는다.
 * 비행 깃발은 finally 로 내린다 — 폴링 잡이 취소되면 `perform` 이 취소를 다시 던져 끝줄에 닿지 못한다.
 */
suspend fun RummyStore.refreshMatch(id: SwiftUUID?) {
    if (id == null || host?.session == null) return
    if (stateInFlight) {
        if (id == stateInFlightID) stateAgain = true else pendingStateID = id
        return
    }
    stateInFlight = true
    val generation = resetGeneration
    try {
        var nextID: SwiftUUID? = id
        while (nextID != null) {
            val current: SwiftUUID = nextID
            nextID = null
            stateInFlightID = current
            do {
                stateAgain = false
                lastStateRequestAt = clock()
                val ticket = issueTicket()
                val result = perform("refreshMatch") { service, token -> service.rummyState(token, current) }
                if (generation != resetGeneration) return
                when (result) {
                    is DuelCall.Success -> {
                        val response = result.value
                        noteServerNow(response.serverNowMs)
                        when (response.status) {
                            RummyRPCStatus.ok -> response.state?.let { applyState(it, ticket) }
                            RummyRPCStatus.notFound -> {
                                // 내 자리가 없는 방·판(지워졌거나 정리됐다).
                                val held = match
                                if (held != null && held.id == current && held.status != RummyMatchStatus.finished) {
                                    clearMatch()
                                    setNotice(RummyNoticeText.roomClosed)
                                }
                                if (activeMatchID == current) activeMatchID = null
                            }
                            RummyRPCStatus.unsupportedClient -> noteUpdateRequired()
                            RummyRPCStatus.unauthorized -> setNotice(RummyNoticeText.signInAgain)
                            else -> logNotice("state refused status=${response.status.rawValue}")
                        }
                    }
                    is DuelCall.Failure -> if (isSchemaMissing(result.error)) noteServerMissing()
                    null -> Unit
                }
            } while (stateAgain)
            val pending = pendingStateID
            if (pending != null) {
                pendingStateID = null
                nextID = pending
            }
        }
    } finally {
        if (generation == resetGeneration) {
            stateInFlightID = null
            stateInFlight = false
            stateAgain = false
        }
    }
}

/**
 * 서버 state 를 화면 상태로 옮기는 **유일한 깔때기**(조회 · 참가 · 시작 · 완료 · 뽑기 · 거절에 실린 state 전부).
 *
 * 늦은 응답 가드(머리말 ④):
 *  (a) 접은 판([RummyStore.dismissedMatchIDs])의 state 는 무시한다.
 *  (b) 이미 끝남으로 든 판에 끝나지 않은 응답이 오면 무시한다(끝나기 전에 읽힌 옛 스냅숏).
 *  (c) 같은 판이면 `seq` → `draft_seq` → 요청 표 순으로 대어 **더 옛것이면** 무시한다(forming 방은 seq 가 안 오른다).
 *  (d) 다른 판이면 요청 표가 더 옛것일 때 무시한다(방을 옮긴 뒤 늦게 온 옛 방의 응답).
 * @param ticket 그 요청을 **보낼 때** 뗀 표. null 이면 지금 새로 뗀다(가장 새것으로 친다).
 */
fun RummyStore.applyState(state: RummyMatchState, ticket: Int? = null): RummyStateApplyOutcome {
    val id = state.id
    if (id in dismissedMatchIDs) return RummyStateApplyOutcome.ignored
    val stamp = ticket ?: issueTicket()
    val seq = state.seq ?: 0L
    val draftSeq = state.draft?.draftSeq ?: 0L
    val held = match
    if (held != null) {
        if (held.id == id) {
            if (held.status == RummyMatchStatus.finished && state.status != RummyMatchStatus.finished) return RummyStateApplyOutcome.ignored
            val heldSeq = held.seq ?: 0L
            if (seq < heldSeq) return RummyStateApplyOutcome.ignored
            if (seq == heldSeq) {
                val heldDraft = held.draft?.draftSeq ?: 0L
                if (draftSeq < heldDraft) return RummyStateApplyOutcome.ignored
                if (draftSeq == heldDraft && stamp < appliedTicket) return RummyStateApplyOutcome.ignored
            }
        } else if (stamp < appliedTicket) {
            return RummyStateApplyOutcome.ignored
        }
    }
    noteServerNow(state.serverNowMs)

    // 닫힌 방(취소·만료) — 들고 있던 방이면 내리고 한 줄.
    if (state.status == RummyMatchStatus.cancelled || state.status == RummyMatchStatus.expired) {
        forgetEngaged(id)
        if (match?.id == id) {
            appliedTicket = maxOf(appliedTicket, stamp)
            clearMatch()
            setNotice(RummyNoticeText.roomClosed)
        }
        if (activeMatchID == id) activeMatchID = null
        return RummyStateApplyOutcome.applied
    }
    // 내 자리가 아닌 state(초대만 받은 방 · 시작 검사에서 빠진 방 · 시작 때 declined 로 접힌 자리)는 들지 않는다.
    if (!isParticipant(state)) {
        forgetEngaged(id)
        if (match?.id == id) {
            appliedTicket = maxOf(appliedTicket, stamp)
            val dropped = mySeat(state)?.state == RummySeatState.dropped
            clearMatch()
            setNotice(if (dropped) RummyNoticeText.droppedFromRoom else RummyNoticeText.roomClosed)
        }
        return RummyStateApplyOutcome.ignored
    }

    appliedTicket = maxOf(appliedTicket, stamp)
    val previous = match
    if (previous != state) match = state
    reconcileEditor(state)
    noteReactions(state)
    if (state.status == RummyMatchStatus.finished) {
        forgetRack(id)
        forgetEngaged(id)
    }
    refreshPhase()
    // 판돈 차감(시작)·정산(끝)을 **처음** 본다 — 판 state 엔 잔액이 없어 로비로 맞춘다(머리말 ⑯). 알림과 같은 장부로 가른다.
    val rubyMoved = if (state.status == RummyMatchStatus.finished) {
        id !in finishAnnouncedIDs
    } else {
        state.status == RummyMatchStatus.active && id !in startAnnouncedIDs
    }
    announce(state)
    if (rubyMoved) refreshRubyAfterSettlement()
    scheduleDeadlineWake()
    if (previous?.id != id) pumpInviteQueue()
    return RummyStateApplyOutcome.applied
}

/** 이 state 에서 내 자리(내 id 로, 호스트가 없으면 `my_seat_no` 로). */
internal fun RummyStore.mySeat(state: RummyMatchState): RummyMatchSeat? = RummyStore.mySeat(state, myUserID)

fun RummyStore.Companion.mySeat(state: RummyMatchState, me: String?): RummyMatchSeat? {
    if (me != null) state.seats?.firstOrNull { it.userId.lowercased == me }?.let { return it }
    val mine = state.mySeatNo ?: return null
    return state.seats?.firstOrNull { it.seatNo == mine }
}

/** 내가 이 방·판의 사람인가 — 방이면 joined, 판이면 playing·forfeit·done. */
internal fun RummyStore.isParticipant(state: RummyMatchState): Boolean {
    val seat = mySeat(state)
    // 자리 줄을 못 찾았다(옛 모양·미리보기) — 서버가 내 자리 번호를 줬으면 믿는다.
        ?: return state.mySeatNo != null
    return when (state.status) {
        RummyMatchStatus.forming -> seat.state == RummySeatState.joined || seat.state == null
        else -> {
            val seatState = seat.state ?: return true
            seatState == RummySeatState.playing || seatState == RummySeatState.forfeit ||
                seatState == RummySeatState.done || seatState == RummySeatState.unknown
        }
    }
}

/** 내 차례인가(판 active · 차례 자리 = 내 자리 · 내 자리가 아직 playing). */
fun RummyStore.Companion.isMyTurn(state: RummyMatchState?, me: String?): Boolean {
    if (state == null || state.status != RummyMatchStatus.active) return false
    val mine = state.mySeatNo ?: return false
    if (state.turnSeatNo != mine) return false
    val seat = mySeat(state, me)
    return seat?.state == null || seat.state == RummySeatState.playing
}

// MARK: - 편집기

/**
 * 편집기를 state 에 맞춘다(머리말 ⑩): 판이 active 이고 내가 playing 이면 **차례**가 바뀔 때마다 다시 세우고(랙 배치 보존),
 * 같은 차례면 그대로 둔다(작업 보존 — 남의 기권으로 seq 만 오른 state 도). 아니면 내린다.
 */
internal fun RummyStore.reconcileEditor(state: RummyMatchState) {
    val seat = mySeat(state)
    val rack = state.myRack
    if (state.status != RummyMatchStatus.active || rack == null || !(seat?.state == null || seat.state == RummySeatState.playing)) {
        if (editor != null) editor = null
        if (rackSortMode != null) rackSortMode = null
        editorKey = null
        lastSentDraft = null
        cancelDraft()
        return
    }
    val key = RummyEditorKey.of(state)
    val seq = state.seq ?: 0L
    val table = state.table ?: emptyList()
    val current = editor
    if (current != null && editorKey == key) {
        // 같은 차례. seq 가 그대로면 메아리·폴링이고, 올랐으면 남의 기권이다(차례·마감·작업 판은 그대로) —
        // 확정 판·내 랙이 그대로인 한 작업을 덮지 않는다.
        if (editorSeq == seq || current.standsOn(table, rack)) {
            editorSeq = seq
            return
        }
    }
    // 랙 자리 승계: 같은 판의 앞 편집기(판에 나갔던 타일은 나간 자리로 돌린 모양) → 없으면(앱 재실행) 로컬 저장 → 면 순서.
    val previous = if (editorKey?.matchID == state.id) editor else null
    val order = previous?.rackFaces
    val entries = previous?.restoredRackEntries ?: loadRackEntries(state.id)
    val fresh = RummyTurnEditor(
        table = table, rack = rack, initialDone = state.myInitialDone ?: false, rackOrder = order,
        tableLayout = state.tableLayout, rackEntries = entries, rackHalfColumns = rackHalfColumns,
    )
    var drawn = if (previous != null) RummyStore.drawnTiles(previous, fresh, entries ?: emptyList()) else emptyList()
    val mode = rackSortMode
    if (previous == null) {
        if (rackSortMode != null) rackSortMode = null
    } else if (mode != null && drawn.isNotEmpty()) {
        // 0.3.70(감사 #10): 정렬한 뒤 손대지 않았으면 뽑은 타일을 그 정렬 자리에 끼운다(단위 사이 반 칸 그대로).
        fresh.sortRack(mode)
        drawn = drawn.map { RummyDrawnTile(it.tileID, it.face, fresh.rackLayout.slot(it.tileID) ?: it.slot) }
    }
    editor = fresh
    editorKey = key
    editorSeq = seq
    cancelDraft()
    draftRetryCount = 0
    // 서버가 들고 있는 작업 판. 새 차례면 null(= 시작 판)이다.
    val serverDraft = state.draft?.table
    lastSentDraft = serverDraft ?: table
    lastSentLayout = if (serverDraft != null) state.draft?.layout else state.tableLayout
    saveRack()
    if (drawn.isNotEmpty()) noteDrawn(drawn)
    // 차례 중간에 편집기를 새로 세웠는데(앱 재실행) 서버 작업 판이 내 화면과 다르면 맞춘다 — 시간 초과 때 서버는 그 작업 판을 판정한다(R-19).
    // 비교는 K(다중집합) — 서버가 판정하는 기준과 같고, 편집기가 세트 안 순서를 표시 순서로 바꿔도 헛보내지 않는다.
    // **이 기기가 손댄 판에서만**(머리말 ⑮). 놀던 기기가 판을 처음 읽은 순간 보이는 작업 판은 같은 계정의 다른 기기가 지금 만드는 것이다 —
    // 되돌려 보내면 그 작업을 지우고, 보내는 순간 이 기기가 engaged 가 되어 이 기기를 내리면 판이 기권된다.
    if (RummyStore.isMyTurn(state, myUserID) && isEngaged(state.id) && serverDraft != null &&
        !RummyRules.sameTable(serverDraft, fresh.submissionTable)
    ) {
        scheduleDraft()
    }
}

// MARK: - 알림(판 시작 · 내 차례 · 끝남)

internal fun RummyStore.announce(state: RummyMatchState) {
    val id = state.id
    if (state.status == RummyMatchStatus.finished) {
        if (id !in finishAnnouncedIDs) {
            finishAnnouncedIDs = finishAnnouncedIDs + id
            onMatchFinished?.invoke()
        }
        return
    }
    if (state.status != RummyMatchStatus.active) return
    val myTurn = RummyStore.isMyTurn(state, myUserID)
    // 같은 차례(남의 기권으로 seq 만 올랐다)에 알림을 또 울리지 않게 차례 정체성으로 가른다.
    val turnKey = RummyEditorKey.of(state).text
    val windowShown = isWindowVisible && !isWindowOccluded
    if (id !in startAnnouncedIDs) {
        // 판으로 **처음** 넘어갔다 — 창을 띄우고 주의를 끈다(테트리스 noteMatchStarted 와 같은 길).
        startAnnouncedIDs = startAnnouncedIDs + id
        if (myTurn) turnAnnouncedKeys = turnAnnouncedKeys + turnKey
        presentWindow?.invoke()
        if (windowShown) return
        requestAttention?.invoke()
        onAttention?.invoke(if (myTurn) RummyNoticeText.myTurnAttention else RummyNoticeText.matchStartedAttention)
        return
    }
    if (!myTurn || turnKey in turnAnnouncedKeys) return
    turnAnnouncedKeys = turnAnnouncedKeys + turnKey
    if (windowShown) return
    requestAttention?.invoke()
    onAttention?.invoke(RummyNoticeText.myTurnAttention)
}

// MARK: - 차례 동작

/** 끌어 놓기. 내 차례면 작업 판을 바꾸고 작업 상태를 보낸다(디바운스). 내 차례가 아니면 **랙 안 재배치만** 받는다. */
fun RummyStore.moveTile(tileID: Int, target: RummyDropTarget) = moveTiles(listOf(tileID), target)

/**
 * v2 묶음째 끌어 놓기(전부 아니면 전무 — `RummyTurnEditor.moveBlock`). 가드는 [moveTile] 과 같다: 내 차례가 아니면
 * **랙 안 재배치만**(Rack·RackSlot, 전부 랙 타일). 작업 상태 전송은 한 번(디바운스).
 */
fun RummyStore.moveTiles(tileIDs: List<Int>, target: RummyDropTarget) {
    val working = editor?.copy() ?: return
    val myTurn = isMyTurn
    if (!myTurn) {
        if (!RummyStore.isRackTarget(target)) return
        if (!tileIDs.all { id -> working.rack.any { it.id == id } }) return
    }
    if (!working.moveBlock(tileIDs, target)) return
    if (editor != working) editor = working
    // 받침대를 손으로 정리했다 — 정렬이 풀린다(판으로 내는 것은 정렬을 안 깬다: 못 내면 그 자리로 돌아온다).
    if (RummyStore.isRackTarget(target) && rackSortMode != null) rackSortMode = null
    saveRack()
    if (!myTurn) return
    setNotice(null)
    scheduleDraft()
}

fun RummyStore.Companion.isRackTarget(target: RummyDropTarget): Boolean = when (target) {
    is RummyDropTarget.Rack, is RummyDropTarget.RackSlot -> true
    is RummyDropTarget.Meld, RummyDropTarget.NewMeld, is RummyDropTarget.NewMeldAt -> false
}

/** 이번 차례 처음 상태로(랙 순서는 유지). 되돌린 판도 보낸다(남들이 보는 작업 판을 되돌린다). */
fun RummyStore.resetTurn() {
    if (!isMyTurn) return
    val working = editor?.copy() ?: return
    working.reset()
    // 0.3.70 검증: 정렬이 살아 있으면 돌아온 타일도 정렬 자리로 — 판에 낸 채 정렬했으면 나간 자리는 정렬 전 자리라, 그대로
    // 돌리면 받침대는 정렬이 아닌데 정렬 버튼은 '선택됨'이고 다음 뽑기 때 받침대 전체가 갑자기 다시 정렬된다.
    rackSortMode?.let { working.sortRack(it) }
    if (editor != working) editor = working
    saveRack()
    setNotice(null)
    scheduleDraft()
}

/** 랙 정렬(777 · 789). 차례와 무관하고 서버로 가지 않는다. */
fun RummyStore.sortRack(mode: RummyRackSort) {
    val working = editor?.copy() ?: return
    working.sortRack(mode)
    if (editor != working) editor = working
    if (rackSortMode != mode) rackSortMode = mode
    saveRack()
}

/** [완료]. 편집기가 이미 거절을 아는 판은 보내지 않고 이유 한 줄만 낸다(서버가 같은 판정을 다시 한다). */
fun RummyStore.submitTurn() {
    val current = match ?: return
    val working = editor ?: return
    if (!isMyTurn) return
    val reason = working.reason
    if (reason != RummyTurnReason.ok && reason != RummyTurnReason.unknown) {
        setNotice(RummyNoticeText.reason(reason, working.initialPoints))
        return
    }
    val matchID = current.id
    val seq = current.seq ?: 0L
    val table = working.submissionTable
    val layout = working.submissionLayout
    // 확정이 작업 상태를 대신한다 — 기다리던 디바운스는 걷는다(나가 있는 것은 서버가 stale 로 버린다).
    draftDebounceJob?.cancel()
    draftDebounceJob = null
    runAction { store ->
        val ticket = store.issueTicket()
        store.markEngaged(matchID)
        val result = store.perform("submitTurn") { service, token -> service.rummyPlay(token, matchID, seq, table, layout) } ?: return@runAction
        store.handleTurnResult(result, matchID, ticket, RummyNoticeText.Action.play)
    }
}

/** [뽑기|넘기기]. 더미가 비었으면 서버가 패스로 바꾼다. */
fun RummyStore.drawTile() {
    val current = match ?: return
    if (!isMyTurn) return
    val matchID = current.id
    val seq = current.seq ?: 0L
    draftDebounceJob?.cancel()
    draftDebounceJob = null
    runAction { store ->
        val ticket = store.issueTicket()
        store.markEngaged(matchID)
        val result = store.perform("drawTile") { service, token -> service.rummyDraw(token, matchID, seq) } ?: return@runAction
        store.handleTurnResult(result, matchID, ticket, RummyNoticeText.Action.draw)
    }
}

/**
 * 완료·뽑기 응답. 거절에도 state 가 실려 오면 그대로 맞춘다(같은 차례면 편집기는 남는다 — 고쳐서 다시 낼 수 있게).
 * 확정되지 않았으면(거절·stale·실패) 걷었던 작업 상태 전송을 다시 건다 — 서버 작업 판이 내 화면에 머물게(R-19).
 */
internal fun RummyStore.handleTurnResult(
    result: DuelCall<RummyActionResponse>, matchID: SwiftUUID, ticket: Int, action: RummyNoticeText.Action,
) {
    when (result) {
        is DuelCall.Success -> {
            val response = result.value
            noteServerNow(response.serverNowMs)
            when (response.status) {
                RummyRPCStatus.ok -> {
                    setNotice(null)
                    response.state?.let { applyState(it, ticket) }
                    return
                }
                RummyRPCStatus.rejected -> {
                    val reason = response.reason ?: RummyTurnReason.unknown
                    setNotice(RummyNoticeText.reason(reason, editor?.initialPoints) ?: RummyNoticeText.tryAgain)
                }
                RummyRPCStatus.stale, RummyRPCStatus.notYourTurn -> {
                    // stale 은 "판이 바뀌었다" 일 뿐이다 — 실린 state 를 먼저 맞추고, 그래도 내 차례면 차례를 잃었다고 말하지 않는다.
                    logNotice("${action.rawValue} refused status=${response.status.rawValue}")
                    val state = response.state
                    if (state != null) {
                        applyState(state, ticket)
                        noteTurnRefusal()
                    } else {
                        scope.launch {
                            refreshMatch(matchID)
                            noteTurnRefusal()
                        }
                    }
                    scheduleDraft()
                    return
                }
                else -> noteRefusal(response, action)
            }
            val state = response.state
            if (state != null) applyState(state, ticket) else scope.launch { refreshMatch(matchID) }
        }
        is DuelCall.Failure -> noteActionFailure(result.error)
    }
    // 내 차례가 아니면(넘어갔다) scheduleDraft 가 스스로 거른다.
    scheduleDraft()
}

/** 완료·뽑기의 stale·not_your_turn 한 줄 — 맞춘 state 에서 여전히 내 차례면 "판이 바뀌었어요", 아니면 "차례가 넘어갔어요". */
internal fun RummyStore.noteTurnRefusal() {
    setNotice(if (isMyTurn) RummyNoticeText.tableChanged else RummyNoticeText.turnPassed)
}

// MARK: - 작업 상태 전송(머리말 ⑨)

/** 디바운스(250ms)를 다시 건다. 끝나면 [flushDraft]. */
fun RummyStore.scheduleDraft(after: Double? = null) {
    if (!isMyTurn || editor == null) return
    draftDebounceJob?.cancel()
    val generation = resetGeneration
    val wait = after ?: draftDebounceSeconds
    draftDebounceJob = scope.launch {
        delay(delayMillis(wait))
        if (generation != resetGeneration) return@launch
        draftDebounceJob = null
        flushDraft()
    }
}

/** 지금 작업 판을 보낸다. 나가 있는 게 있으면 **끝난 뒤 최신 것 한 번**(합치기). 서버가 이미 든 판과 같으면 안 보낸다. */
fun RummyStore.flushDraft() {
    if (draftInFlight) {
        draftDirty = true
        return
    }
    draftDirty = false
    val current = match ?: return
    val working = editor ?: return
    val key = editorKey ?: return
    if (key.matchID != current.id || !RummyStore.isMyTurn(current, myUserID)) return
    val table = working.submissionTable
    val layout = working.submissionLayout
    if (table == lastSentDraft && layout == lastSentLayout) return
    draftInFlight = true
    lastSentDraft = table
    lastSentLayout = layout
    val matchID = current.id
    // 편집기가 선 seq 가 아니라 지금 든 판의 seq — 같은 차례에 남의 기권으로 오를 수 있다.
    val seq = current.seq ?: 0L
    val generation = resetGeneration
    markEngaged(matchID)
    draftFlushJob = scope.launch {
        val ticket = issueTicket()
        val result = perform("flushDraft") { service, token -> service.rummyDraft(token, matchID, seq, table, layout) }
        if (generation != resetGeneration) return@launch
        draftInFlight = false
        val sameTurn = editorKey == key
        var retryAfter: Double? = null
        when (result) {
            is DuelCall.Success -> {
                val response = result.value
                noteServerNow(response.serverNowMs)
                when (response.status) {
                    RummyRPCStatus.ok -> draftRetryCount = 0
                    RummyRPCStatus.stale, RummyRPCStatus.notYourTurn, RummyRPCStatus.notActive -> {
                        // 실려 온 state 로 맞춘다 — 차례가 넘어갔으면 편집기는 새 차례로 다시 선다.
                        val state = response.state
                        if (state != null) applyState(state, ticket) else refreshMatch(matchID)
                        // 같은 차례인데 seq 만 올랐다(남의 기권) — 서버가 이 판을 버렸으니 새 seq 로 한 번 더 보낸다.
                        if (editorKey == key && isMyTurn && (match?.seq ?: 0L) != seq) retryAfter = draftDebounceSeconds
                    }
                    RummyRPCStatus.malformed -> if (sameTurn) setNotice(RummyNoticeText.reason(RummyTurnReason.malformed, null))
                    RummyRPCStatus.unsupportedClient -> noteUpdateRequired()
                    else -> if (sameTurn) retryAfter = RummyStore.draftRetrySeconds
                }
            }
            is DuelCall.Failure -> {
                if (isSchemaMissing(result.error)) noteServerMissing()
                if (sameTurn) retryAfter = RummyStore.draftRetrySeconds
            }
            null -> if (sameTurn) retryAfter = RummyStore.draftRetrySeconds
        }
        val retry = retryAfter
        if (retry != null && editorKey == key) {
            // 서버가 이 판을 못 받았다 — 다음 보내기가 같은 판이라고 건너뛰지 않게 기억을 지운다.
            lastSentDraft = null
            lastSentLayout = null
            if (!draftDirty && draftRetryCount < RummyStore.draftRetryLimit) {
                draftRetryCount += 1
                scheduleDraft(retry)
            }
        }
        if (draftDirty && editorKey == key) {
            flushDraft()
        } else {
            draftDirty = false
        }
    }
}

/** 기다리던 디바운스를 걷는다(나가 있는 전송은 끝까지 간다 — 그 답은 `editorKey` 로 가린다). */
fun RummyStore.cancelDraft() {
    draftDebounceJob?.cancel()
    draftDebounceJob = null
    draftDirty = false
}

// MARK: - 마감

/** 마감 + 유예가 지났으면 state 를 다시 읽는다(서버 `rummy__catchup` 이 시간 초과를 판정한다). 같은 차례면 3초 간격으로 세 번까지. */
suspend fun RummyStore.checkDeadline(now: SwiftDate) {
    val current = match ?: return
    if (current.status != RummyMatchStatus.active) return
    val deadline = deviceDate(current.turnDeadlineMs) ?: return
    val grace = current.graceMs?.let { it / 1000 } ?: RummyStore.defaultGraceSeconds
    if (now < deadline.addingTimeInterval(grace + RummyStore.deadlineSlackSeconds)) return
    val key = RummyEditorKey.of(current).text
    if (deadlineFetchKey == key) {
        if (deadlineFetchCount >= RummyStore.deadlineRetryLimit || now.timeIntervalSince(lastDeadlineFetchAt) < RummyStore.deadlineRetrySeconds) return
        deadlineFetchCount += 1
    } else {
        deadlineFetchKey = key
        deadlineFetchCount = 1
    }
    lastDeadlineFetchAt = now
    refreshMatch(current.id)
    // 여전히 같은 차례(서버가 아직 안 따라잡았다) — 한 번 더 깨운다.
    val after = match
    if (after != null && RummyEditorKey.of(after).text == key) {
        deadlineWakeKey = null
        scheduleDeadlineWake()
    }
}

/** 창이 안 보여도 마감 + 유예 뒤 한 번 깨어나 state 를 다시 읽는다(차례 · 마감이 바뀔 때만 다시 건다). */
internal fun RummyStore.scheduleDeadlineWake() {
    val current = match
    val deadline = if (deadlineWakeEnabled && current != null && current.status == RummyMatchStatus.active) deviceDate(current.turnDeadlineMs) else null
    if (current == null || deadline == null) {
        if (deadlineJob != null) {
            deadlineJob?.cancel()
            deadlineJob = null
            deadlineWakeKey = null
        }
        return
    }
    val wakeKey = "${RummyEditorKey.of(current).text}#${current.turnDeadlineMs ?: 0.0}"
    if (deadlineWakeKey == wakeKey) return
    deadlineWakeKey = wakeKey
    deadlineJob?.cancel()
    val grace = current.graceMs?.let { it / 1000 } ?: RummyStore.defaultGraceSeconds
    var wake = deadline.addingTimeInterval(grace + RummyStore.deadlineSlackSeconds)
    if (deadlineFetchKey?.let { wakeKey.startsWith("$it#") } == true) {
        wake = maxOf(wake, lastDeadlineFetchAt.addingTimeInterval(RummyStore.deadlineRetrySeconds))
    }
    val wait = maxOf(0.0, wake.timeIntervalSince(clock()))
    val generation = resetGeneration
    deadlineJob = scope.launch {
        // 지연 0 이면 Main.immediate 에서 그 자리에 돌아 applyState 안으로 다시 들어온다 — 한 틱은 쉰다(머리말 Kotlin 이식).
        delay(maxOf(1L, delayMillis(wait)))
        if (generation != resetGeneration) return@launch
        deadlineJob = null
        checkDeadline(clock())
    }
}
