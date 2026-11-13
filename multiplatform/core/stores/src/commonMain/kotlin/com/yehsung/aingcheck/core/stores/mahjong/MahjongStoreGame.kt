// 원본: Sources/CheckCore/MahjongStoreGame.swift @ e4995a3a(판 state 적용 · 내 차례 동작 · 깨우기 · 폴링 걸음) — Android 판 8
//
// 늦은 응답 가드: (a) 접은 판 (b) 끝난 판 뒤 진행 응답 (c) 같은 판은 hand_index → seq → 요청 표 순 (d) 다른 판은 표
// (e) 울기 답 뒤 내 창 번호가 다르면 조용히 내린다 (f) 결정 키가 바뀌거나 결정이 없어지면 2단 입력을 접는다
// (g) 서버 경로 응답은 연습 칸을 안 건드린다 (h) 울기 답은 한 창 안에서 단조 (i) ⓓ · ⓔ.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimAnswer
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.random.Random

/** applyState 결과. needsFull = 사건 꼬리에 구멍 — 부르는 쪽이 p_since 0 으로 다시 읽는다. */
enum class MahjongStateApplyOutcome { applied, needsFull, ignored }

/** 서버 state 하나를 넣는다(픽스처 문). 서버 전용 — 연습 칸을 안 건드린다. */
fun MahjongStore.applyState(payload: MahjongStatePayload, requestedSince: Int = 0): MahjongStateApplyOutcome =
    applyState(payload, requestedSince, null, false)

internal fun MahjongStore.applyState(payload: MahjongStatePayload, requestedSince: Int, rawTicket: Int?, predatesWrite: Boolean): MahjongStateApplyOutcome {
    val incoming = payload.match ?: return MahjongStateApplyOutcome.ignored
    if (incoming.isPractice) return MahjongStateApplyOutcome.ignored
    // (a) 접은 판.
    if (incoming.id in dismissedMatchIDs) return MahjongStateApplyOutcome.ignored
    val ticket = rawTicket ?: issueTicket()

    var next = payload
    val current = match?.match
    if (current != null && current.id == incoming.id) {
        val held = current.matchStatus
        val arriving = incoming.matchStatus
        // (b) 끝난 판 뒤의 진행 응답.
        if (held.isTerminal && !arriving.isTerminal) return MahjongStateApplyOutcome.ignored
        // ⓔ 판으로 든 id 에 늦게 온 방 단계 응답.
        if ((held == MahjongMatchStatus.active || held == MahjongMatchStatus.finished) &&
            (arriving == MahjongMatchStatus.forming || arriving == MahjongMatchStatus.cancelled || arriving == MahjongMatchStatus.expired)
        ) return MahjongStateApplyOutcome.ignored
        // (c) 같은 판은 hand_index → seq 순.
        val heldHand = current.handIndex ?: -1
        val arrivingHand = incoming.handIndex ?: -1
        if (arrivingHand < heldHand) return MahjongStateApplyOutcome.ignored
        if (arrivingHand == heldHand && (incoming.seq ?: 0) < (current.seq ?: 0)) return MahjongStateApplyOutcome.ignored
        if (arrivingHand == heldHand && (incoming.seq ?: 0) == (current.seq ?: 0) && ticket < appliedTicket) return MahjongStateApplyOutcome.ignored
        if (requestedSince > 0) {
            val first = payload.events?.firstOrNull()?.seq
            if (first != null && first > requestedSince + 1) return MahjongStateApplyOutcome.needsFull
            next = next.copy(events = MahjongStore.mergedEvents(match?.events ?: emptyList(), payload.events ?: emptyList()))
        }
    } else {
        // (d) 다른 판은 요청 표.
        if (match?.match != null && ticket < appliedTicket) return MahjongStateApplyOutcome.ignored
        if (requestedSince > 0) return MahjongStateApplyOutcome.needsFull
    }
    noteServerClock(payload.serverNowMs)

    // 닫힌 방(취소 · 만료).
    if (incoming.matchStatus == MahjongMatchStatus.cancelled || incoming.matchStatus == MahjongMatchStatus.expired) {
        appliedTicket = maxOf(appliedTicket, ticket)
        if (match?.match?.id == incoming.id) {
            leaveHeldRoom(incoming.id)
            setNotice(MahjongNoticeText.roomClosed)
        } else {
            dropOwnership(incoming.id)
        }
        if (activeMatchID == incoming.id) activeMatchID = null
        return MahjongStateApplyOutcome.applied
    }
    // 내 자리가 아닌 state(초대만 받은 방 · 빠진 방)는 들지 않는다.
    val me = myUserID
    if (me != null && !MahjongStore.isParticipant(payload, me)) {
        if (match?.match?.id == incoming.id) {
            appliedTicket = maxOf(appliedTicket, ticket)
            val droppedHere = incoming.matchStatus == MahjongMatchStatus.forming &&
                (payload.members?.any { it.user?.id?.lowercase() == me && it.state == "dropped" } ?: false)
            leaveHeldRoom(incoming.id)
            setNotice(if (droppedHere) MahjongNoticeText.droppedAtStart else MahjongNoticeText.roomClosed)
        }
        return MahjongStateApplyOutcome.ignored
    }

    // (h) 울기 답 단조: 답한 창의 answered == null 은 프롬프트를 되살리지 않는다.
    val call = next.myDecision as? MahjongDecision.Call
    if (call != null && call.answered == null && MahjongStore.windowKey(incoming.id, call.windowId) in answeredWindowIDs) {
        val held = match?.myDecision as? MahjongDecision.Call
        val answer = if (held != null && held.windowId == call.windowId && held.answered != null) held.answered
        else answeredWindowAnswers[MahjongStore.windowKey(incoming.id, call.windowId)] ?: MahjongClaimAnswer.pass.rawValue
        next = next.copy(myDecision = call.copy(answered = answer))
    }

    appliedTicket = maxOf(appliedTicket, ticket)
    val previous = match
    if (incoming.matchStatus == MahjongMatchStatus.forming) lastRoomCheckAt = clock()
    noteTimeouts(previous, next)
    if (previous != next) match = next
    if (!predatesWrite) applyRuby(next.rubyBalance)
    afterMatchApplied(previous)
    return MahjongStateApplyOutcome.applied
}

/** `match` 가 바뀐 뒤 한 곳. 단계 · 결정 키 접기(f) · 판 끝 · 연습판 버림. */
internal fun MahjongStore.matchDidChange(old: MahjongStatePayload?) {
    if (!showsPractice) {
        val oldKey = MahjongDecisionKey.of(old)
        val newKey = MahjongDecisionKey.of(match)
        if (oldKey != newKey || newKey == null) {
            foldTwoStageInputs()
            if (oldKey != newKey) {
                if (isWorking) isWorking = false
                if (isAnsweringCall) isAnsweringCall = false
            }
        }
    }
    val previous = old?.match
    val current = match?.match
    val sameMatch = previous?.id != null && previous.id == current?.id

    // 루비 판이 서면 연습판을 버린다.
    if (current != null && current.matchStatus == MahjongMatchStatus.active &&
        !(sameMatch && previous?.matchStatus == MahjongMatchStatus.active) && practice != null
    ) {
        discardPracticeGame()
        showsPractice = false
        setNotice(MahjongNoticeText.practiceClosed)
    }
    syncPracticeRoomHold(old)

    // 끝난 판을 처음 본 순간 한 번.
    if (current != null && current.matchStatus.isTerminal && !(sameMatch && previous?.matchStatus?.isTerminal == true)) {
        dropOwnership(current.id)
        if (current.matchStatus == MahjongMatchStatus.finished && !current.isVoid) onMatchFinished?.invoke()
        if (host?.session != null) {
            scope.launch {
                refreshLobby()
                refreshRanking()
            }
        }
    }
    // 판이 선 순간(판돈 차감) 로비 다시 읽기.
    if (current != null && current.matchStatus == MahjongMatchStatus.active && !(sameMatch && previous?.matchStatus == MahjongMatchStatus.active) &&
        host?.session != null
    ) {
        scope.launch { refreshLobby() }
    }
    // 넷째가 앉은 순간(같은 방에서 3 → 4).
    if (current != null && current.matchStatus == MahjongMatchStatus.forming && sameMatch && previous?.matchStatus == MahjongMatchStatus.forming &&
        MahjongStore.joinedCount(old) < 4 && MahjongStore.joinedCount(match) == 4
    ) {
        setNotice(MahjongNoticeText.fourGathered)
    }
    recomputePhase()
    scheduleWake()
    syncHoldingActivity()
}

// MARK: 판 조회

/** 한 판(방)의 state 를 읽는다. 같은 판이면 p_since_seq = 내 seq, 구멍이면 처음부터 한 번 더. 같은 판 중복은 합치고 다른 판은 끝난 뒤 한 번. */
internal suspend fun MahjongStore.refreshMatch(rawID: String?) {
    val requested = rawID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return
    if (requested.startsWith(MahjongStatePayload.practiceIDPrefix) || host?.session == null) return
    if (stateInFlight) {
        if (requested == stateInFlightID) stateAgain = true else pendingStateID = requested
        return
    }
    stateInFlight = true
    val generation = resetGeneration
    var nextID: String? = requested
    while (nextID != null) {
        val id: String = nextID
        nextID = null
        stateInFlightID = id
        var forceFull = false
        do {
            stateAgain = false
            val since = if (!forceFull && match?.match?.id == id) (match?.match?.seq ?: 0) else 0
            forceFull = false
            lastStateRequestAt = clock()
            val ticket = issueTicket()
            val writes = writeRevision
            val result = perform { s, t -> s.mahjongState(t, id, since) }
            if (generation != resetGeneration) return
            when (result) {
                is DuelCall.Success -> {
                    val response = result.value
                    noteServerClock(response.serverNowMs)
                    when (response.status) {
                        MahjongRPCStatus.ok -> {
                            val state = response.state
                            if (state != null && applyState(state, since, ticket, writes != writeRevision) == MahjongStateApplyOutcome.needsFull && since > 0) {
                                forceFull = true
                                stateAgain = true
                            }
                        }
                        MahjongRPCStatus.notFound -> matchNotFound(id)
                        MahjongRPCStatus.unsupportedClient -> noteUpdateRequired()
                        MahjongRPCStatus.unauthorized -> setNotice(MahjongNoticeText.signInAgain)
                        else -> response.state?.let { applyState(it, 0, ticket, writes != writeRevision) }
                    }
                }
                is DuelCall.Failure -> {
                    if (isSchemaMissing(result.error)) noteServerMissing()
                    scheduleWake()
                }
                null -> Unit
            }
        } while (stateAgain && generation == resetGeneration)
        pendingStateID?.let {
            pendingStateID = null
            nextID = it
        }
    }
    stateInFlightID = null
    stateInFlight = false
}

/** 판 · 방 조회가 not_found — 들고 있던 것이면 내리고 한 줄. */
internal fun MahjongStore.matchNotFound(id: String) {
    if (activeMatchID == id) activeMatchID = null
    val held = match?.match
    if (held == null || held.id != id) {
        dropOwnership(id)
        return
    }
    when (held.matchStatus) {
        MahjongMatchStatus.forming -> {
            val wasFull = MahjongStore.joinedCount(match) == 4 && !isHost
            setNotice(if (wasFull) MahjongNoticeText.droppedAtStart else MahjongNoticeText.roomClosed)
        }
        MahjongMatchStatus.active -> setNotice(MahjongNoticeText.finishedMatch)
        else -> Unit
    }
    leaveHeldRoom(id)
}

// MARK: 적용 뒤 — 알림 · 보조 · 깨우기

internal fun MahjongStore.afterMatchApplied(previous: MahjongStatePayload?) {
    announce(previous)
    runAids()
    scheduleWake()
}

/** 알림 정책 — 모두 이 기기가 연 판에서만. matchStarted(판이 처음 active) · myTurn(국마다 첫 내 결정, 화면이 안 보일 때) · away. */
internal fun MahjongStore.announce(previous: MahjongStatePayload?) {
    val payload = match ?: return
    val current = payload.match ?: return
    if (current.matchStatus != MahjongMatchStatus.active || !ownsMatch(current.id)) return
    val showing = isWindowShowingTable
    val prior = previous?.match
    if (!(prior?.id == current.id && prior.matchStatus == MahjongMatchStatus.active) && current.id !in deliveredAttentionKeys) {
        presentWindow?.invoke()
        if (showing) {
            deliveredAttentionKeys.add(current.id)
        } else {
            requestAttention?.invoke()
            deliverAttention(MahjongAttention(MahjongAttention.Kind.matchStarted, current.id, current.handIndex ?: 0, current.id))
        }
    }
    val away = payload.myAway
    if (away != null) {
        deliverAttention(MahjongAttention(MahjongAttention.Kind.away, current.id, current.handIndex ?: 0, "${current.id}#away#${(away.sinceMs ?: 0.0).toLong()}"))
    } else if (!showing) {
        val qualifies = when (val d = payload.myDecision) {
            is MahjongDecision.Turn -> true
            is MahjongDecision.Call -> d.ron && d.answered == null
            null -> false
        }
        if (qualifies) {
            deliverAttention(MahjongAttention(MahjongAttention.Kind.myTurn, current.id, current.handIndex ?: 0, "${current.id}#${current.handIndex ?: 0}"))
        }
    }
}

/** 시간 초과 문구: 내 자동 버림 표지가 새로 왔거나, 답하지 않은 내 울기 창이 마감 + 유예 뒤에 닫혔다. */
internal fun MahjongStore.noteTimeouts(previous: MahjongStatePayload?, next: MahjongStatePayload) {
    val current = next.match ?: return
    val held = previous?.match ?: return
    if (current.matchStatus != MahjongMatchStatus.active || next.myAway != null || held.id != current.id) return
    val heldSeq = held.seq ?: 0
    val mySeat = next.mySeat
    if (mySeat != null) {
        val auto = next.events?.lastOrNull { it.seq > heldSeq && it.isAutoDiscard && it.seat == mySeat }
        if (auto != null && timeoutNoticeKeys.add("${current.id}#auto#${auto.seq}")) {
            setNotice(MahjongNoticeText.timeoutDiscarded)
            return
        }
    }
    val call = previous.myDecision as? MahjongDecision.Call ?: return
    if (call.answered != null) return
    val still = next.myDecision as? MahjongDecision.Call
    if (still != null && still.windowId == call.windowId) return
    val grace = (current.graceMs ?: held.graceMs ?: MahjongStore.defaultGraceMs.toInt()).toDouble()
    val due = localDate(call.deadlineMs + grace) ?: return
    if (clock() >= due && timeoutNoticeKeys.add("${current.id}#window#${call.windowId}")) setNotice(MahjongNoticeText.timeoutPassed)
}

// MARK: 보조 — 이 기기가 연 판에서만 자동으로 보낸다

internal fun MahjongStore.tsumogiriAidDate(turn: MahjongDecision.Turn): SwiftDate? {
    turn.notBeforeMs?.let { return localDate(it) }
    return localDate(turn.startedMs)?.addingTimeInterval(aidJitter())
}

/** 결정 키마다 한 번: 자동 화료 · 울지 않음(국마다 꺼짐) · 쯔모기리. */
internal fun MahjongStore.runAids() {
    if (showsPractice) return
    val payload = match ?: return
    val current = payload.match ?: return
    if (current.matchStatus != MahjongMatchStatus.active || payload.myAway != null || payload.mySeatRow?.away == true || !ownsMatch(current.id)) return
    val handKey = "${current.id}#${current.handIndex ?: 0}"
    if (aids.noCalls) {
        val marked = noCallsHandKey
        if (marked != null && marked != handKey) {
            noCallsHandKey = null
            aids = aids.copy(noCalls = false)
        } else if (marked == null) {
            noCallsHandKey = handKey
        }
    }
    val key = MahjongDecisionKey.of(payload) ?: return
    if (key in aidHandledKeys) return
    when (val decision = payload.myDecision ?: return) {
        is MahjongDecision.Turn -> {
            if (aids.autoWin && decision.tsumo) {
                aidHandledKeys.add(key)
                scope.launch { declareTsumo() }
                return
            }
            val drawn = payload.myDrawn
            if (!aids.tsumogiri || decision.tsumo || decision.ankan.isNotEmpty() || decision.kakan.isNotEmpty() || decision.riichi.isNotEmpty() ||
                drawn == null || drawn !in decision.discard
            ) return
            val due = tsumogiriAidDate(decision) ?: return
            aidHandledKeys.add(key)
            val id = current.id
            val expected = current.seq ?: decision.seq
            val generation = resetGeneration
            aidJob?.cancel()
            aidJob = scope.launch {
                val wait = due.timeIntervalSince(clock())
                if (wait > 0) delay(delayMillis(wait))
                if (!isActive || generation != resetGeneration || decisionKey != key) return@launch
                sendAct("discard", listOf(drawn), decision, id, expected)
            }
        }
        is MahjongDecision.Call -> {
            if (decision.answered != null) return
            if (aids.autoWin && decision.ron) {
                aidHandledKeys.add(key)
                scope.launch { call(com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind.ron, emptyList()) }
            } else if (aids.noCalls && !decision.ron) {
                aidHandledKeys.add(key)
                scope.launch { passCall() }
            }
        }
    }
}

// MARK: 깨우기 — 창과 무관, 장부 판에서만

internal data class MahjongWakeTarget(val kind: Kind, val at: SwiftDate, val key: String, val matchID: String) {
    enum class Kind { decision, beat, backup, room }
}

/** 지금 판에서 다음으로 깨울 때. 같은 열쇠로 이미 쏘았으면 1초 뒤 재시도, 2번까지. */
internal fun MahjongStore.wakeTarget(now: SwiftDate): MahjongWakeTarget? {
    val payload = match ?: return null
    val current = payload.match ?: return null
    if (!ownsMatch(current.id)) return null
    val target: MahjongWakeTarget
    when (current.matchStatus) {
        MahjongMatchStatus.forming -> {
            val me = myUserID ?: return null
            if (!MahjongStore.isParticipant(payload, me)) return null
            return MahjongWakeTarget(
                MahjongWakeTarget.Kind.room, lastRoomCheckAt.addingTimeInterval(MahjongStore.roomCheckSeconds),
                "room#${current.id}#${lastRoomCheckAt.timeIntervalSince1970}", current.id,
            )
        }
        MahjongMatchStatus.active -> {
            val signature = "${current.id}#${current.seq ?: 0}#${current.phase ?: ""}#${(current.wakeAtMs ?: -1.0).toLong()}"
            val grace = (current.graceMs ?: MahjongStore.defaultGraceMs.toInt()).toDouble()
            val decision = payload.myDecision
            val wakeSeat = current.wakeSeat
            val wakeAt = current.wakeAtMs
            val backup = current.backupAtMs
            target = if (decision != null) {
                var atMs: Double
                when (decision) {
                    is MahjongDecision.Turn -> {
                        atMs = decision.deadlineMs + grace + MahjongStore.wakeSlackMs
                        val nb = decision.notBeforeMs?.let { localDate(it) }
                        if (nb != null && now < nb) atMs = decision.notBeforeMs!!
                    }
                    is MahjongDecision.Call -> atMs = decision.deadlineMs + grace + MahjongStore.wakeSlackMs
                }
                val at = localDate(atMs) ?: return null
                MahjongWakeTarget(MahjongWakeTarget.Kind.decision, at, "decision#$signature#${atMs.toLong()}", current.id)
            } else if (wakeSeat != null && wakeSeat == payload.mySeat && wakeAt != null) {
                MahjongWakeTarget(MahjongWakeTarget.Kind.beat, localDate(wakeAt)!!, "beat#$signature", current.id)
            } else if (backup != null) {
                MahjongWakeTarget(MahjongWakeTarget.Kind.backup, localDate(backup)!!, "backup#$signature#${backup.toLong()}", current.id)
            } else {
                return null
            }
        }
        else -> return null
    }
    if (target.key != wakeFiredKey) return target
    if (wakeFiredCount > MahjongStore.wakeRetryLimit) return null
    val retry = maxOf(target.at, wakeFiredAt.addingTimeInterval(MahjongStore.wakeRetrySeconds))
    return target.copy(at = retry)
}

/** 깨우기 판정(시험이 직접 밟는다). 때가 됐으면 그 판 state 를 한 번 읽는다. */
fun MahjongStore.checkWake(now: SwiftDate) {
    val target = wakeTarget(now) ?: return
    if (now < target.at) {
        scheduleWake()
        return
    }
    if (target.key == wakeFiredKey) {
        wakeFiredCount += 1
    } else {
        wakeFiredKey = target.key
        wakeFiredCount = 1
    }
    wakeFiredAt = now
    if (target.kind == MahjongWakeTarget.Kind.room) lastRoomCheckAt = now
    val id = target.matchID
    scope.launch { refreshMatch(id) }
}

/** 실제 타이머로 다음 깨우기를 잡는다(같은 깨우기 시각이면 한 번만). 박자 기기는 0~150ms 흔든다. */
internal fun MahjongStore.scheduleWake() {
    val target = if (timersEnabled && host?.session != null) wakeTarget(clock()) else null
    if (target == null) {
        if (wakeJob != null) {
            wakeJob?.cancel()
            wakeJob = null
        }
        wakeScheduledKey = null
        return
    }
    val scheduled = "${target.key}@${target.at.timeIntervalSince1970}"
    if (scheduled == wakeScheduledKey) return
    wakeScheduledKey = scheduled
    wakeJob?.cancel()
    var wait = maxOf(0.0, target.at.timeIntervalSince(clock()))
    if (target.kind == MahjongWakeTarget.Kind.beat) wait += Random.nextDouble(0.0, MahjongStore.beatJitterMs / 1_000)
    val generation = resetGeneration
    wakeJob = scope.launch {
        delay(delayMillis(wait))
        if (generation != resetGeneration) return@launch
        wakeJob = null
        wakeScheduledKey = null
        checkWake(clock())
    }
}

// MARK: 폴링 걸음

/** 안전망 한 걸음(화면이 탁자를 보일 때만). 방 10초 · 판 구독 중 5초 / 미구독 1.5초 · 판이 없으면 로비 30초 · 순위 60초. */
suspend fun MahjongStore.pollTick(now: SwiftDate) {
    if (!isWindowShowingTable || host?.session == null) return
    val current = match?.match
    if (current != null && !current.matchStatus.isTerminal) {
        val interval = if (current.matchStatus == MahjongMatchStatus.forming) MahjongStore.roomPollSeconds
        else MahjongStore.statePollSeconds(host?.realtimeState?.isSubscribed ?: false)
        if (now.timeIntervalSince(lastStateRequestAt) >= interval) {
            val id = current.id
            outsidePolling { it.refreshMatch(id) }
        }
    } else if (!showsPractice && now.timeIntervalSince(lastLobbyRequestAt) >= MahjongStore.lobbyPollSeconds) {
        outsidePolling { it.refreshLobby() }
    }
    if (!isWindowShowingTable) return
    val terminal = match?.match?.matchStatus?.isTerminal ?: true
    if (rankingEnabled && terminal && now.timeIntervalSince(lastRankingRequestAt) >= MahjongStore.rankingPollSeconds) {
        outsidePolling { it.refreshRanking() }
    }
}

// MARK: 내 차례 동작(act)

internal data class MahjongServerTurn(val payload: MahjongStatePayload, val match: MahjongStateMatch, val turn: MahjongDecision.Turn)

internal val MahjongStore.serverTurn: MahjongServerTurn?
    get() {
        if (showsPractice) return null
        val payload = match ?: return null
        val current = payload.match ?: return null
        if (current.matchStatus != MahjongMatchStatus.active) return null
        val turn = payload.myDecision as? MahjongDecision.Turn ?: return null
        return MahjongServerTurn(payload, current, turn)
    }

/** 내 자리가 비움인가(서버 판). */
val MahjongStore.isAwayHere: Boolean
    get() {
        val payload = match ?: return false
        if (payload.match?.matchStatus != MahjongMatchStatus.active) return false
        return payload.myAway != null || payload.mySeatRow?.away == true
    }

/** 패를 버린다. 리치 무장이면 리치 선언 버림, 자리 비움이면 돌아오기(손패를 한 번 누르면 복귀). */
suspend fun MahjongStore.discard(tile: MahjongTile) {
    if (showsPractice) {
        practiceDiscard(tile)
        return
    }
    if (isAwayHere) {
        comeBack()
        return
    }
    if (isWorking) return
    val st = serverTurn ?: return
    val action: String
    if (riichiArmed) {
        if (tile !in st.turn.riichi) return
        action = "riichi"
    } else {
        if (tile !in st.turn.discard) return
        action = "discard"
    }
    sendAct(action, listOf(tile), st.turn, st.match.id, st.match.seq ?: st.turn.seq)
}

/** 리치 무장 — 이 결정의 riichi 선택지가 있을 때만. */
fun MahjongStore.armRiichi() {
    val turn = myDecision as? MahjongDecision.Turn ?: return
    if (turn.riichi.isEmpty()) return
    if (chiChoicesOpen) chiChoicesOpen = false
    if (kanChoicesOpen) kanChoicesOpen = false
    if (!riichiArmed) riichiArmed = true
}

fun MahjongStore.cancelRiichi() {
    if (riichiArmed) riichiArmed = false
}

suspend fun MahjongStore.declareTsumo() {
    if (showsPractice) {
        if (practiceTurn?.tsumo == true) practiceAct(MahjongTurnAction.Tsumo)
        return
    }
    if (isWorking) return
    val st = serverTurn ?: return
    if (!st.turn.tsumo) return
    sendAct("tsumo", emptyList(), st.turn, st.match.id, st.match.seq ?: st.turn.seq)
}

suspend fun MahjongStore.declareKyuushu() {
    if (showsPractice) {
        if (practiceTurn?.kyuushu == true) practiceAct(MahjongTurnAction.Kyuushu)
        return
    }
    if (isWorking) return
    val st = serverTurn ?: return
    if (!st.turn.kyuushu) return
    sendAct("kyuushu", emptyList(), st.turn, st.match.id, st.match.seq ?: st.turn.seq)
}

/** 암깡(4장 묶음). 빈 목록이면: 후보가 하나뿐이면 그것을, 깡 후보(암깡 + 가깡)가 둘 이상이면 고르기를 펼친다. */
suspend fun MahjongStore.ankan(tiles: List<MahjongTile>) {
    if (showsPractice) {
        val turn = practiceTurn ?: return
        val chosen = chooseAnkan(tiles, turn) ?: return
        practiceAct(MahjongTurnAction.Ankan(turn.ankan.firstOrNull { it.sorted() == chosen } ?: chosen))
        return
    }
    if (isWorking) return
    val st = serverTurn ?: return
    val chosen = chooseAnkan(tiles, st.turn) ?: return
    sendAct("ankan", chosen, st.turn, st.match.id, st.match.seq ?: st.turn.seq)
}

internal fun MahjongStore.chooseAnkan(tiles: List<MahjongTile>, turn: MahjongDecision.Turn): List<MahjongTile>? {
    var chosen = tiles.sorted()
    if (chosen.isEmpty()) {
        if (turn.ankan.size + turn.kakan.size > 1) {
            if (riichiArmed) riichiArmed = false
            if (!kanChoicesOpen) kanChoicesOpen = true
            return null
        }
        if (turn.ankan.size != 1) return null
        chosen = turn.ankan[0].sorted()
    }
    if (turn.ankan.none { it.sorted() == chosen }) return null
    return chosen
}

internal val MahjongStore.practiceTurn: MahjongDecision.Turn?
    get() = if (showsPractice) practice?.payload?.myDecision as? MahjongDecision.Turn else null

/** 가깡(더할 패). */
suspend fun MahjongStore.kakan(tile: MahjongTile) {
    if (showsPractice) {
        if (kanChoicesOpen) kanChoicesOpen = false
        if (practiceTurn?.kakan?.contains(tile) == true) practiceAct(MahjongTurnAction.Kakan(tile))
        return
    }
    if (isWorking) return
    val st = serverTurn ?: return
    if (tile !in st.turn.kakan) return
    sendAct("kakan", listOf(tile), st.turn, st.match.id, st.match.seq ?: st.turn.seq)
}

/** act 한 번 — 장부(보낼 때) · 잠금 · 요청 표 · 요청 마감 · 응답 처리. */
internal suspend fun MahjongStore.sendAct(action: String, tiles: List<MahjongTile>, turn: MahjongDecision.Turn, matchID: String, expectedSeq: Int) {
    if (host?.session == null) return
    noteOwnsMatch(matchID)
    actionToken += 1
    val token = actionToken
    isWorking = true
    if (kanChoicesOpen) kanChoicesOpen = false
    val generation = resetGeneration
    try {
        val ticket = issueTicket()
        val seconds = requestDeadlineSeconds(turn.deadlineMs)
        val result = performWithin(seconds) { s, t -> s.mahjongAct(t, matchID, expectedSeq, action, tiles) }
        handleDecisionResponse(result, MahjongNoticeText.Action.act, ticket, matchID)
    } finally {
        if (generation == resetGeneration && token == actionToken && isWorking) isWorking = false
    }
}

/** 결정 동작(act · call · back) 응답 한 곳. null(마감 · 취소)이면 아무것도 바꾸지 않는다. */
internal suspend fun MahjongStore.handleDecisionResponse(result: DuelCall<MahjongActionResponse>?, action: MahjongNoticeText.Action, ticket: Int, matchID: String) {
    when (val r = result ?: return) {
        is DuelCall.Failure -> noteActionFailure(r.error)
        is DuelCall.Success -> {
            val response = r.value
            writeRevision += 1
            noteServerClock(response.serverNowMs)
            if (response.status == MahjongRPCStatus.unsupportedClient) {
                noteUpdateRequired()
                return
            }
            setNotice(MahjongNoticeText.status(response.status, action, response.need, response.have))
            if (response.status == MahjongRPCStatus.notFound) {
                matchNotFound(matchID)
                return
            }
            val state = response.state
            if (state != null) {
                if (applyState(state, 0, ticket, false) == MahjongStateApplyOutcome.needsFull) refreshMatch(matchID)
            } else if (response.status != MahjongRPCStatus.ok) {
                refreshMatch(matchID)
            }
        }
    }
}

/** 판 중 [나가기] = 자리 비움(기권 아님). 판은 자동으로 끝까지, 장부는 그대로 둔다. */
suspend fun MahjongStore.leaveTable() {
    if (showsPractice || isAwayHere) return
    val current = match?.match ?: return
    if (current.matchStatus != MahjongMatchStatus.active) return
    val id = current.id
    runRoomAction(MahjongNoticeText.Action.leave) { s, t -> s.mahjongLeave(t, id) }
}

/** [돌아왔어요]. 나가기 뒤 10초 안이면 too_fast → "잠시 뒤에 다시 눌러 주세요". */
suspend fun MahjongStore.comeBack() {
    if (showsPractice) {
        practiceComeBack()
        return
    }
    if (isWorking || host?.session == null) return
    val payload = match ?: return
    val current = payload.match ?: return
    if (current.matchStatus != MahjongMatchStatus.active) return
    val id = current.id
    noteOwnsMatch(id)
    actionToken += 1
    val token = actionToken
    isWorking = true
    val generation = resetGeneration
    try {
        val ticket = issueTicket()
        val deadline = when (val d = payload.myDecision) {
            is MahjongDecision.Turn -> d.deadlineMs
            is MahjongDecision.Call -> d.deadlineMs
            null -> null
        }
        val result = performWithin(requestDeadlineSeconds(deadline)) { s, t -> s.mahjongBack(t, id) }
        handleDecisionResponse(result, MahjongNoticeText.Action.back, ticket, id)
    } finally {
        if (generation == resetGeneration && token == actionToken && isWorking) isWorking = false
    }
}

/** 반응(2초 쿨다운 too_fast 는 조용히 버린다). */
suspend fun MahjongStore.sendReaction(key: String) {
    if (showsPractice || host?.session == null) return
    val current = match?.match ?: return
    if (current.matchStatus != MahjongMatchStatus.active) return
    val id = current.id
    noteOwnsMatch(id)
    val ticket = issueTicket()
    val result = perform { s, t -> s.mahjongReact(t, id, key) } as? DuelCall.Success ?: return
    noteServerClock(result.value.serverNowMs)
    result.value.state?.let { applyState(it, 0, ticket, false) }
}
