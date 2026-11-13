// 원본: Sources/CheckCore/CrossyDuelStoreFrames.swift @ e4995a3a(판 표시 프레임 갈래) — Android 판 8
//
//   응답(applyState) ─ noteServerFrames → 장부 → 소켓 열기·닫기 · 끝난 판 → finishFrames(곧바로 닫기)
//   판 루프(tick)     ─ considerFrame: ① 소켓 명령 ② 토큰 밀어 넣기 ③ 프레임 보내기(playing 이고 join 됐을 때만)
//   보고              ─ frameChangeReportsSuppressed(확인됨 = 체크포인트 · 변화 보고 0)
//   소켓 사건         ─ handleFrameChannelEvent → 장부 apply · receive
// ★ 프레임은 **표시 전용**이다 — 승패 · 루비 · 판정 · 재개 · heldOpponentSeq · match 를 바꾸는 줄이 이 파일에 없다(B0 불변식).
// ★ 서버가 `frames` 키를 안 주면 장부의 조건 ① 이 거짓이라 언제나 대체 길(DB `report_ms`)이다.
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.wire.games.CrossyDuelFramesRow
import kotlinx.coroutines.launch
import kotlin.math.floor

/** 이 기기가 프레임을 실제로 열 수 있는가 — 소켓이 만들어지고(킬스위치 · 시험 프로세스 아님) 키가 있다. */
val CrossyDuelStore.framesCapable: Boolean
    get() {
        val h = host ?: return false
        if (h.service.anonKey == null) return false
        return resolvedFrameChannel() != null
    }

/** 프레임 소켓을 처음 필요할 때 **한 번만** 만든다(킬스위치도 그때 한 번 읽는다 — 실행 중에 뒤집히지 않게). */
internal fun CrossyDuelStore.resolvedFrameChannel(): CrossyDuelFrameChannel? {
    if (!frameChannelResolved) {
        frameChannelResolved = true
        val channel = makeFrameChannel()
        channel?.onEvent = { event -> handleFrameChannelEvent(event) }
        frameChannel = channel
    }
    return frameChannel
}

/** 지금 보고 간격(초) — 장부가 있으면 그 판정(확인됨 = 체크포인트), 없으면 판의 `report_ms`(대체 길). */
fun CrossyDuelStore.frameReportInterval(now: Double): Double {
    val link = frameLink
    if (link != null && (frameLinkMatchID == null || frameLinkMatchID == match?.id)) return link.reportInterval(now)
    return (match?.reportMs ?: CrossyDuelFrameLink.defaultReportMs).toDouble() / 1000
}

/** 프레임이 확인돼 점수·죽음 변화 보고를 내지 않는가. 장부가 없으면 false(대체 길). 바뀔 때만 로그 한 줄. */
fun CrossyDuelStore.frameChangeReportsSuppressed(now: Double): Boolean {
    val link = frameLink ?: return false
    if (frameLinkMatchID != null && frameLinkMatchID != match?.id) return false
    val confirmed = link.changeReportsSuppressed(now)
    if (loggedFramesConfirmed != confirmed) {
        loggedFramesConfirmed = confirmed
        val c = link.conditions(now)
        logNotice(
            "frames confirmed=$confirmed server=${c.serverOn} joined=${c.joined} heard=${c.heardRecently} " +
                "hears=${c.opponentHearsMe} healthy=${c.reportsHealthy} steady=${c.steady}",
        )
    }
    return confirmed
}

// MARK: - 응답에서

/** 진행 중이고 **이 기기가 두는** 판의 응답마다: 서버 켬/끔 · 간격 · 실패 streak 를 장부에 넣고, 켜졌으면 열고 꺼졌으면 닫는다. */
internal fun CrossyDuelStore.noteServerFrames(
    frames: CrossyDuelFramesRow?,
    reportMs: Int,
    checkpointMs: Int?,
    matchID: String,
    opponentID: String,
    now: Double,
) {
    if (!framesCapable) {
        if (frameLink != null) discardFrames()
        return
    }
    if (frameLink == null || frameLinkMatchID != matchID) {
        val me = host?.session?.userID
        if (me.isNullOrEmpty() || opponentID.isEmpty()) return
        discardFrames()
        frameLink = CrossyDuelFrameLink(me, opponentID, frameBaseNow())
        frameLinkMatchID = matchID
    }
    val link = frameLink ?: return
    val wasOn = link.topic != null
    link.noteServerFrames(frames, reportMs, checkpointMs)
    link.noteReportFailureStreak(reportFailureStreak)
    val isOn = link.topic != null
    if (wasOn != isOn) logNotice("frames ${if (isOn) "on" else "off"} by server")
    driveFrameSocket(now)
}

/** `f` 시작값 = 장부를 만드는 순간의 벽시계 ms(다시 연 프로세스·다시 만든 장부의 첫 장이 옛 장보다 크다). */
internal fun CrossyDuelStore.frameBaseNow(): Long {
    val ms = clock().timeIntervalSince1970 * 1000
    return if (ms.isFinite() && ms > 0) floor(ms).toLong() else 0L
}

/** 서버가 판을 닫았다(끝난 판 가지). 소켓을 **곧바로** 닫고 장부는 남긴다. */
internal fun CrossyDuelStore.finishFrames() {
    val link = frameLink ?: return
    val command = link.finish()
    if (command == CrossyDuelFrameSocketCommand.Disconnect || frameSocketOpen) {
        closeFrameSocket()
        logNotice("frames closed — match finished")
    }
}

/** 판이 끝났거나 로비로 간다 — 채널을 닫고 장부를 버린다. */
fun CrossyDuelStore.discardFrames() {
    closeFrameSocket()
    frameLink = null
    frameLinkMatchID = null
    frameSocketToken = null
    loggedFramesConfirmed = null
}

/** 보고 실패 streak 가 바뀐 세 자리(멎음 버림 · 실패 · 성공)에서 부른다 — 조건 ⑤. */
internal fun CrossyDuelStore.noteFrameReportStreak() {
    frameLink?.noteReportFailureStreak(reportFailureStreak)
}

/** 판 화면이 그릴 상대 반투명 그림자 — 프레임이 켜진 판에서 최근에 받은 위치만. 표시 전용이다(B0). */
val CrossyDuelStore.opponentGhost: CrossyDuelGhost?
    get() {
        val link = frameLink ?: return null
        val current = match ?: return null
        if (current.isFinished || frameLinkMatchID != current.id || phase != CrossyDuelPhase.playing) return null
        return link.opponentGhost(uptime())
    }

// MARK: - 판 루프에서

/** 판 루프 한 걸음: ① 소켓 열기·닫기 ② 바뀐 세션 토큰 밀어 넣기 ③ 프레임 보내기. **보고와 따로 돈다.** */
internal fun CrossyDuelStore.considerFrame(now: Double) {
    if (frameLink == null) return
    val current = match ?: return
    if (current.isFinished || frameLinkMatchID != current.id) return
    val d = duel ?: return
    if (duelMatchID != current.id || host?.session == null) return
    driveFrameSocket(now)
    pushFrameTokenIfChanged()
    if (!frameSocketOpen || phase != CrossyDuelPhase.playing) return
    val channel = frameChannel ?: return
    val link = frameLink ?: return
    val score = d.game.score
    val deaths = d.game.deaths
    val ghost = CrossyDuelGhost.of(d.game)
    if (!link.frameDue(now, d.isLive, link.changedSinceLastFrame(score, deaths), link.movedSinceLastFrame(ghost))) return
    val frame = link.makeFrame(now, d.seq, score, deaths, ghost)
    channel.send(CrossyDuelFrame.EVENT, frame.payload)
}

private fun CrossyDuelStore.driveFrameSocket(now: Double) {
    val link = frameLink ?: return
    val command = link.socketCommand(now, duel?.startAt, frameJitter)
    performFrameSocket(command)
}

private fun CrossyDuelStore.performFrameSocket(command: CrossyDuelFrameSocketCommand) {
    when (command) {
        CrossyDuelFrameSocketCommand.None -> Unit
        CrossyDuelFrameSocketCommand.Disconnect -> {
            closeFrameSocket()
            logNotice("frames closed socket=${frameLink?.socket}")
        }
        is CrossyDuelFrameSocketCommand.Connect -> openFrameSocket(command.topic, command.refreshToken)
    }
}

/**
 * 연다. 토큰이 만료돼 거절된 뒤의 한 번(`refreshToken`)이면 판 상태를 한 번 읽어 토큰을 새로 받는다(세션 재시도가 갱신한다).
 * 읽은 뒤에도 토큰이 거절된 그대로면 다시 붙지 않는다.
 */
private fun CrossyDuelStore.openFrameSocket(topic: String, refreshToken: Boolean) {
    val h = host
    val session = h?.session
    val matchID = frameLinkMatchID
    if (!CrossyDuelFrameWire.isFrameTopic(topic) || h == null || session == null || h.service.anonKey == null ||
        resolvedFrameChannel() == null || matchID == null
    ) {
        frameLink?.apply(RealtimeTransportEvent.Closed(null), uptime(), frameJitter)
        return
    }
    if (!refreshToken || session.accessToken != frameSocketToken) {
        connectFrameChannel(topic)
        return
    }
    frameConnectTicket += 1
    val ticket = frameConnectTicket
    val generation = duelGeneration
    val rejectedToken = session.accessToken
    val merged = stateInFlight
    logNotice("frames token expired — refreshing session before the one retry merged=$merged")
    scope.launch {
        refreshMatch(matchID)
        if (ticket != frameConnectTicket || generation != duelGeneration || frameLink?.socket != CrossyDuelFrameSocketPhase.Connecting) return@launch
        val fresh = host?.session?.accessToken
        if (fresh == null || fresh == rejectedToken) {
            val event: RealtimeTransportEvent =
                if (merged) RealtimeTransportEvent.Closed(null) else RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.ExpiredToken)
            frameLink?.apply(event, uptime(), frameJitter)?.let { performFrameSocket(it) }
            return@launch
        }
        connectFrameChannel(topic)
    }
}

private fun CrossyDuelStore.connectFrameChannel(topic: String) {
    val h = host ?: return
    val session = h.session ?: return
    val apiKey = h.service.anonKey ?: return
    val channel = resolvedFrameChannel() ?: return
    frameConnectTicket += 1
    frameSocketOpen = true
    frameSocketTopic = topic
    frameSocketToken = session.accessToken
    logNotice("frames connect retries=${frameLink?.retriesUsed ?: 0}")
    channel.connect(h.service.projectURL, apiKey, session.accessToken, topic)
}

/** 닫는다(열려 있을 때만 소켓에 시킨다 — 몇 번을 불러도 같다). */
internal fun CrossyDuelStore.closeFrameSocket() {
    frameConnectTicket += 1
    if (frameSocketOpen) frameChannel?.disconnect()
    frameSocketOpen = false
    frameSocketTopic = null
}

/** 판 중 세션 토큰이 바뀌었으면 열린 채널에 밀어 넣는다. join 된 뒤에만. */
private fun CrossyDuelStore.pushFrameTokenIfChanged() {
    if (!frameSocketOpen || frameLink?.socket != CrossyDuelFrameSocketPhase.Joined) return
    val token = host?.session?.accessToken ?: return
    val used = frameSocketToken ?: return
    if (token == used) return
    frameSocketToken = token
    frameChannel?.pushAccessToken(token)
}

// MARK: - 소켓 사건

/** 소켓 사건 하나. 닫힌 소켓의 늦은 사건은 버린다. 받아들인 상대 프레임은 장부에만 남는다(표시 전용). */
fun CrossyDuelStore.handleFrameChannelEvent(event: CrossyDuelFrameChannelEvent) {
    if (!frameSocketOpen) return
    val link = frameLink ?: return
    val now = uptime()
    when (event) {
        is CrossyDuelFrameChannelEvent.Transport -> {
            val command = link.apply(event.event, now, frameJitter)
            if (event.event == RealtimeTransportEvent.Joined && link.socket == CrossyDuelFrameSocketPhase.Joined) logNotice("frames joined")
            if (command == CrossyDuelFrameSocketCommand.Disconnect) {
                closeFrameSocket()
                logNotice("frames closed by ${event.event} socket=${link.socket}")
            }
        }
        is CrossyDuelFrameChannelEvent.Frame -> link.receive(event.frame, now)
        is CrossyDuelFrameChannelEvent.Rejected -> Unit
    }
}
