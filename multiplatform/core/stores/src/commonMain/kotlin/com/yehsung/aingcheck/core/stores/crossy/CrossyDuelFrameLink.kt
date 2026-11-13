// 원본: Sources/CheckCore/CrossyDuelFrameLink.swift @ e4995a3a(1:1 길건너 판 표시 프레임 장부 — 맥 0.3.78·0.3.82 · 폰 1.0.18 · Android 판 8)
//
// 1:1 길건너 판 표시 프레임의 **순수 장부**(SPEC v1.3 §3.4 B0~B4 · §8.4 — `TetrisFrameLink` 틀). 소켓·스토어·화면을 모른다.
// 판 중 상대 점수(와 반투명 그림자)만 판 전용 비공개 채널(`crossy_duel:<match>`)의 Broadcast 로 받고, DB 보고는 "판정용 체크포인트(3초)
// + 100 도달·3분 즉시"로 둔다. **양쪽 프레임이 실제로 오가는 것이 확인될 때만** 체크포인트로 줄이고, 어긋나면 곧바로 대체 길(DB `report_ms`)이다.
// 불변식: 프레임은 **표시 전용**이다 — 승패·루비·판정·재개 어느 것도 프레임 값을 근거로 삼지 않는다.
// Swift 는 값 타입(struct)이다 — Kotlin 은 스토어 하나가 혼자 들고 고치는 가변 객체다(복사해 견주는 자리가 없다).
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.net.realtime.BackoffPolicy
import com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.wire.games.CrossyDuelFramesRow
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.abs
import kotlin.math.roundToLong

/** 상대 반투명 그림자 한 점(11-10 대표 "부하 엄청 심하지 않다면 구현하자"). 두 사람은 같은 씨앗의 같은 길을 달려 내 판에 그대로 겹쳐 그린다. */
data class CrossyDuelGhost(
    /** 가로 자리(칸 단위, 통나무 위면 소수 — 0.01 칸으로 실어 보낸다). */
    val x: Double,
    /** 몇째 줄(앞이 +). */
    val row: Int,
    val facing: CrossyGame.Direction,
    /** 죽어 있는 동안(부활 전) — 그림자를 숨긴다. */
    val dead: Boolean,
) {
    /** 보낼 만큼 움직였는가(0.05 칸 · 줄 · 방향 · 생사). */
    fun moved(from: CrossyDuelGhost?): Boolean {
        val other = from ?: return true
        return other.row != row || other.facing != facing || other.dead != dead || abs(other.x - x) >= 0.05
    }

    companion object {
        /** 판 값에서 지금 내 그림자(뛰는 중이면 그 순간의 자리). Swift `rounded()` = 0.5 는 0 에서 먼 쪽. */
        fun of(game: CrossyGame): CrossyDuelGhost {
            val visual = game.playerVisual
            return CrossyDuelGhost(visual.x, swiftRound(visual.row).toInt(), game.player.facing, game.death != null)
        }
    }
}

/** Swift `Double.rounded()`(.toNearestOrAwayFromZero). */
internal fun swiftRound(value: Double): Double = if (value < 0) -kotlin.math.floor(-value + 0.5) else kotlin.math.floor(value + 0.5)

/** 받은 프레임을 버린 까닭. 버린 프레임은 아무것도 바꾸지 않는다. */
enum class CrossyDuelFrameRejection { malformed, unknownVersion, outOfRange, notOpponent, stale, matchFinished }

/** 프레임 한 장(이벤트 `frame`, 형식 버전 1). 한 장이 그 순간의 전체 표시 상태다(누계). */
data class CrossyDuelFrame(
    val sender: String,
    val seq: Long,
    val frame: Long,
    val score: Int,
    val deaths: Int,
    val heardAgoMs: Long,
    val version: Int = FORMAT_VERSION,
    val ghost: CrossyDuelGhost? = null,
) {
    /** 송신 본문. **키 이름을 바꾸지 마라** — 받는 쪽 [decode] 와 한 짝이다. */
    val payload: JsonObject
        get() {
            val body = linkedMapOf<String, JsonElement>(
                "v" to JsonPrimitive(version), "u" to JsonPrimitive(sender), "s" to JsonPrimitive(seq), "f" to JsonPrimitive(frame),
                "sc" to JsonPrimitive(score), "d" to JsonPrimitive(deaths), "h" to JsonPrimitive(heardAgoMs),
            )
            ghost?.let {
                body["gx"] = JsonPrimitive(swiftRound(it.x * 100).roundToLong())
                body["gr"] = JsonPrimitive(it.row)
                body["gf"] = JsonPrimitive(it.facing.rawValue)
                body["gd"] = JsonPrimitive(if (it.dead) 1 else 0)
            }
            return JsonObject(body)
        }

    /** 결과: 프레임 또는 버린 까닭(Swift `Result<CrossyDuelFrame, CrossyDuelFrameRejection>`). */
    sealed interface Decoded {
        data class Ok(val frame: CrossyDuelFrame) : Decoded
        data class Rejected(val rejection: CrossyDuelFrameRejection) : Decoded
    }

    companion object {
        const val EVENT = "frame"
        const val FORMAT_VERSION = 1
        const val MAX_SCORE = 100

        /** 받은 본문 → 프레임. 모양만 본다. 모르는 키는 무시한다(운영 realtime 이 `id` 를 덧붙인다). */
        fun decode(payload: JsonObject): Decoded {
            val version = integer(payload["v"]) ?: return Decoded.Rejected(CrossyDuelFrameRejection.malformed)
            if (version != FORMAT_VERSION.toLong()) return Decoded.Rejected(CrossyDuelFrameRejection.unknownVersion)
            val senderEl = payload["u"] as? JsonPrimitive
            val sender = senderEl?.takeIf { it.isString }?.content
            val seq = integer(payload["s"])
            val frame = integer(payload["f"])
            val score = integer(payload["sc"])
            val deaths = integer(payload["d"])
            val heard = integer(payload["h"])
            if (sender.isNullOrEmpty() || seq == null || seq < 0 || frame == null || frame < 0 || score == null || deaths == null ||
                heard == null || heard < -1
            ) return Decoded.Rejected(CrossyDuelFrameRejection.malformed)
            if (score !in 0..MAX_SCORE.toLong() || deaths < 0) return Decoded.Rejected(CrossyDuelFrameRejection.outOfRange)
            // 그림자는 선택 칸 — 모양이 어긋나면 그림자만 버리고 프레임(점수 표시)은 받는다.
            var ghost: CrossyDuelGhost? = null
            val gx = integer(payload["gx"])
            val gr = integer(payload["gr"])
            val gf = (payload["gf"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                ?.let { raw -> CrossyGame.Direction.entries.firstOrNull { it.rawValue == raw } }
            if (gx != null && gr != null && abs(gx) <= 100_000 && abs(gr) <= 100_000 && gf != null) {
                ghost = CrossyDuelGhost(gx.toDouble() / 100, gr.toInt(), gf, integer(payload["gd"]) == 1L)
            }
            return Decoded.Ok(CrossyDuelFrame(sender, seq, frame, score.toInt(), deaths.toInt(), heard, version.toInt(), ghost))
        }

        /** JSON **정수**만 읽는다(불리언 · 소수 · 문자열은 null — Swift NSNumber 판정과 같다). */
        internal fun integer(value: JsonElement?): Long? {
            val p = value as? JsonPrimitive ?: return null
            if (p.isString) return null
            val c = p.content
            if (c == "true" || c == "false" || c == "null") return null
            if (c.contains('.') || c.contains('e') || c.contains('E')) return null
            return c.toLongOrNull()
        }
    }
}

/** 프레임 확인 조건(B4 ①~⑤ + 3장 연속). **하나라도 거짓이면 대체 길이다.** */
data class CrossyDuelFrameConditions(
    val serverOn: Boolean = false,
    val joined: Boolean = false,
    val heardRecently: Boolean = false,
    val opponentHearsMe: Boolean = false,
    val reportsHealthy: Boolean = false,
    val steady: Boolean = false,
) {
    val allHold: Boolean get() = serverOn && joined && heardRecently && opponentHearsMe && reportsHealthy && steady
}

/** 이 판에서 프레임 소켓을 다시 열지 않는 까닭. */
enum class CrossyDuelFrameStopReason { unauthorized, rateLimited, exhausted, finished }

/** 프레임 소켓의 상태. */
sealed interface CrossyDuelFrameSocketPhase {
    data object Idle : CrossyDuelFrameSocketPhase
    data object Connecting : CrossyDuelFrameSocketPhase
    data object Joined : CrossyDuelFrameSocketPhase
    /** 닫혔고 이 시각(로컬 단조 초)에 다시 연다. */
    data class Retrying(val at: Double) : CrossyDuelFrameSocketPhase
    /** 이 판에서는 다시 열지 않는다(남은 판은 대체 길). */
    data class Stopped(val reason: CrossyDuelFrameStopReason) : CrossyDuelFrameSocketPhase
}

/** 프레임 소켓이 닫힌 까닭(사유마다 재시도가 다르다). */
enum class CrossyDuelFrameCloseCause {
    unauthorized, expiredToken, rateLimited, noEvidence, lost;

    companion object {
        /** 전송자 사건 → 닫힘 사유. 닫힘이 아닌 사건은 null. */
        fun classify(event: RealtimeTransportEvent): CrossyDuelFrameCloseCause? = when (event) {
            RealtimeTransportEvent.Opened, RealtimeTransportEvent.Joined, is RealtimeTransportEvent.Broadcast, RealtimeTransportEvent.HeartbeatAck -> null
            is RealtimeTransportEvent.JoinRejected -> when (val r = event.rejection) {
                RealtimeJoinRejection.Unauthorized -> unauthorized
                RealtimeJoinRejection.ExpiredToken -> expiredToken
                is RealtimeJoinRejection.Unknown -> {
                    val lowered = r.reason.lowercase()
                    if (lowered.contains("too many") || lowered.contains("toomany")) rateLimited else lost
                }
            }
            is RealtimeTransportEvent.Closed, RealtimeTransportEvent.HeartbeatTimedOut -> lost
        }
    }
}

/** 판 루프가 소켓에게 시킬 일. 장부는 스스로 아무것도 하지 않는다. */
sealed interface CrossyDuelFrameSocketCommand {
    data object None : CrossyDuelFrameSocketCommand
    /** 이 토픽(`state.frames.topic` 글자 그대로)으로 private join 을 연다. [refreshToken] 이면 토큰을 새로 받은 뒤. */
    data class Connect(val topic: String, val refreshToken: Boolean) : CrossyDuelFrameSocketCommand
    data object Disconnect : CrossyDuelFrameSocketCommand
}

/**
 * 한 판의 프레임 장부(판마다 새로 만든다). 동기 · 순수 — I/O 0, 시계 읽기 0, 난수 0. `at` 인자는 전부 로컬 **단조** 시계의 초.
 * @param frameBase `f` 시작값 — 프로세스 시작 벽시계 ms(프로세스당 한 번 정한 값, 스토어가 넘긴다).
 */
class CrossyDuelFrameLink(me: String, opponent: String, frameBase: Long) {
    companion object {
        const val heardWithinSeconds: Double = 2.5
        const val heardWithinMs: Long = 2_500
        const val steadyFrameCount = 3
        const val frameIntervalSeconds: Double = 1.0
        const val minFrameGapSeconds: Double = 0.5
        /** 내 그림자가 움직였을 때 직전 프레임과의 최소 틈(초당 5장 상한 — 반투명 상대, 11-10). */
        const val ghostFrameGapSeconds: Double = 0.2
        const val evidenceTimeoutSeconds: Double = 10.0
        const val maxRetries = 3
        const val checkpointMinMs = 2_000
        const val checkpointMaxMs = 5_000
        const val defaultReportMs = 2_000
        const val defaultCheckpointMs = 3_000
        /** 재시도 지연 — full jitter, 천장 1·2·4초, 바닥 0.25초. */
        val retryPolicy = BackoffPolicy(base = 1.0, factor = 2.0, cap = 4.0, floor = 0.25)
    }

    val me: String = me.lowercase()
    val opponent: String = opponent.lowercase()
    var topic: String? = null
        private set
    var reportMs: Int = defaultReportMs
        private set
    var checkpointMs: Int = defaultCheckpointMs
        private set
    var reportFailureStreak: Int = 0
        private set
    var finished: Boolean = false
        private set
    var socket: CrossyDuelFrameSocketPhase = CrossyDuelFrameSocketPhase.Idle
        private set
    var retriesUsed: Int = 0
        private set
    var expiredRetryUsed: Boolean = false
        private set
    var needsFreshToken: Boolean = false
        private set
    var attemptStartedAt: Double? = null
        private set
    var lastEvidenceAt: Double? = null
        private set
    var lastFrame: CrossyDuelFrame? = null
        private set
    var opponentHeardAt: Double? = null
        private set
    var steadyStreak: Int = 0
        private set
    var nextFrameNumber: Long = maxOf(0L, frameBase)
        private set
    var lastSentAt: Double? = null
        private set
    var lastSentScore: Int? = null
        private set
    var lastSentDeaths: Int? = null
        private set
    var lastSentGhost: CrossyDuelGhost? = null
        private set

    /** 서버 state 의 `frames` · `report_ms` · `checkpoint_ms` 를 응답마다 넣는다. 꺼지면 조건 ① 이 곧바로 거짓이고 다음 [socketCommand] 가 닫는다. */
    fun noteServerFrames(frames: CrossyDuelFramesRow?, reportMs: Int? = null, checkpointMs: Int? = null) {
        val next = frames?.activeTopic
        if (next == null) steadyStreak = 0
        topic = next
        if (reportMs != null) this.reportMs = reportMs
        val checkpoint = checkpointMs ?: defaultCheckpointMs
        this.checkpointMs = minOf(maxOf(checkpoint, checkpointMinMs), checkpointMaxMs)
    }

    /** 보고 실패 streak 가 바뀔 때마다 넣는다. 0 이 아니면 곧바로 대체 길이고, 0 으로 돌아와도 프레임 3장을 다시 모아야 확인이다. */
    fun noteReportFailureStreak(streak: Int) {
        reportFailureStreak = maxOf(0, streak)
        if (reportFailureStreak > 0) steadyStreak = 0
    }

    /** 판이 끝났다 — 소켓을 닫고 다시 열지 않는다(닫기 누락 = 연결 누수). */
    fun finish(): CrossyDuelFrameSocketCommand {
        val wasOpen = isOpen
        finished = true
        steadyStreak = 0
        socket = CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.finished)
        return if (wasOpen) CrossyDuelFrameSocketCommand.Disconnect else CrossyDuelFrameSocketCommand.None
    }

    /** 판 루프가 걸음마다 묻는다: 지금 소켓을 열까 · 닫을까. [matchStartedAt] 이 null(카운트다운 전)이면 멈춤 시계가 돌지 않는다. */
    fun socketCommand(now: Double, matchStartedAt: Double?, jitter: (Double) -> Double): CrossyDuelFrameSocketCommand {
        if (finished) return finish()
        val topic = this.topic
        if (topic == null) {
            val wasOpen = isOpen
            when (socket) {
                CrossyDuelFrameSocketPhase.Connecting, CrossyDuelFrameSocketPhase.Joined, is CrossyDuelFrameSocketPhase.Retrying ->
                    socket = CrossyDuelFrameSocketPhase.Idle
                else -> Unit
            }
            steadyStreak = 0
            return if (wasOpen) CrossyDuelFrameSocketCommand.Disconnect else CrossyDuelFrameSocketCommand.None
        }
        return when (val s = socket) {
            CrossyDuelFrameSocketPhase.Idle -> startAttempt(topic, now)
            is CrossyDuelFrameSocketPhase.Retrying -> if (now >= s.at) startAttempt(topic, now) else CrossyDuelFrameSocketCommand.None
            CrossyDuelFrameSocketPhase.Connecting, CrossyDuelFrameSocketPhase.Joined -> {
                if (!evidenceTimedOut(now, matchStartedAt)) return CrossyDuelFrameSocketCommand.None
                close(CrossyDuelFrameCloseCause.noEvidence, now, jitter)
                CrossyDuelFrameSocketCommand.Disconnect
            }
            is CrossyDuelFrameSocketPhase.Stopped -> CrossyDuelFrameSocketCommand.None
        }
    }

    /** 소켓 사건. 닫힘이면 사유별로 재시도를 정하고 Disconnect 를 돌려준다(이미 처리한 닫힘은 두 번 세지 않는다). */
    fun apply(event: RealtimeTransportEvent, now: Double, jitter: (Double) -> Double): CrossyDuelFrameSocketCommand {
        if (event == RealtimeTransportEvent.Joined) {
            if (socket == CrossyDuelFrameSocketPhase.Connecting) socket = CrossyDuelFrameSocketPhase.Joined
            return CrossyDuelFrameSocketCommand.None
        }
        val cause = CrossyDuelFrameCloseCause.classify(event) ?: return CrossyDuelFrameSocketCommand.None
        if (!isOpen) return CrossyDuelFrameSocketCommand.None
        close(cause, now, jitter)
        return CrossyDuelFrameSocketCommand.Disconnect
    }

    private val isOpen: Boolean get() = socket == CrossyDuelFrameSocketPhase.Connecting || socket == CrossyDuelFrameSocketPhase.Joined

    private fun startAttempt(topic: String, now: Double): CrossyDuelFrameSocketCommand {
        socket = CrossyDuelFrameSocketPhase.Connecting
        attemptStartedAt = now
        steadyStreak = 0
        val refresh = needsFreshToken
        needsFreshToken = false
        return CrossyDuelFrameSocketCommand.Connect(topic, refresh)
    }

    /** 멈춤 조건(B4): 기준 = max(판 시작, 이 연결 시도 시작, 마지막 증거). 기준에서 10초 동안 증거가 없으면 닫는다. */
    private fun evidenceTimedOut(now: Double, matchStartedAt: Double?): Boolean {
        val start = matchStartedAt ?: return false
        if (!start.isFinite()) return false
        var reference = start
        attemptStartedAt?.let { reference = maxOf(reference, it) }
        lastEvidenceAt?.let { reference = maxOf(reference, it) }
        return now - reference >= evidenceTimeoutSeconds
    }

    private fun close(cause: CrossyDuelFrameCloseCause, now: Double, jitter: (Double) -> Double) {
        steadyStreak = 0
        when (cause) {
            CrossyDuelFrameCloseCause.unauthorized -> {
                socket = CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.unauthorized)
                return
            }
            CrossyDuelFrameCloseCause.rateLimited -> {
                socket = CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.rateLimited)
                return
            }
            CrossyDuelFrameCloseCause.expiredToken -> {
                if (expiredRetryUsed) {
                    socket = CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.exhausted)
                    return
                }
                expiredRetryUsed = true
                needsFreshToken = true
            }
            CrossyDuelFrameCloseCause.noEvidence, CrossyDuelFrameCloseCause.lost -> Unit
        }
        if (retriesUsed >= maxRetries) {
            socket = CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.exhausted)
            return
        }
        retriesUsed += 1
        socket = CrossyDuelFrameSocketPhase.Retrying(now + retryPolicy.delay(retriesUsed.toLong(), jitter))
    }

    /**
     * 상대 프레임 한 장. null = 받아들였다(표시 · 증거 · 히스테리시스가 바뀐다). 버린 프레임은 아무것도 바꾸지 않는다.
     * 순서(B2): `f` 가 마지막보다 크거나 **`s` 가 더 크면** 받는다.
     */
    fun receive(frame: CrossyDuelFrame, now: Double): CrossyDuelFrameRejection? {
        if (finished) return CrossyDuelFrameRejection.matchFinished
        if (frame.sender.lowercase() != opponent) return CrossyDuelFrameRejection.notOpponent
        if (frame.score !in 0..CrossyDuelFrame.MAX_SCORE || frame.deaths < 0) return CrossyDuelFrameRejection.outOfRange
        lastFrame?.let { last -> if (!(frame.frame > last.frame || frame.seq > last.seq)) return CrossyDuelFrameRejection.stale }
        val continuous = opponentHeardAt?.let { now - it <= heardWithinSeconds } ?: false
        lastFrame = frame
        opponentHeardAt = now
        val hearsMe = frame.heardAgoMs in 0..heardWithinMs
        if (hearsMe) lastEvidenceAt = now
        steadyStreak = if (hearsMe && topic != null && socket == CrossyDuelFrameSocketPhase.Joined && reportFailureStreak == 0) {
            if (continuous) steadyStreak + 1 else 1
        } else {
            0
        }
        return null
    }

    /** 지금 조건(B4 ①~⑤ + 3장). 순수 판정. */
    fun conditions(now: Double): CrossyDuelFrameConditions = CrossyDuelFrameConditions(
        serverOn = topic != null && !finished,
        joined = socket == CrossyDuelFrameSocketPhase.Joined,
        heardRecently = opponentHeardAt?.let { now - it <= heardWithinSeconds } ?: false,
        opponentHearsMe = lastFrame?.let { it.heardAgoMs in 0..heardWithinMs } ?: false,
        reportsHealthy = reportFailureStreak == 0,
        steady = steadyStreak >= steadyFrameCount,
    )

    /** 보고 간격(초) — 확인됨 = [checkpointMs], 아니면 [reportMs]. */
    fun reportInterval(now: Double): Double = (if (conditions(now).allHold) checkpointMs else reportMs).toDouble() / 1000

    /** 확인됨이면 점수·죽음 변화 보고를 내지 않는다(체크포인트가 싣는다). */
    fun changeReportsSuppressed(now: Double): Boolean = conditions(now).allHold

    /** 지금 프레임을 보낼 때인가(B3). 바뀌었으면 0.5초 틈, 그림자가 움직였으면 0.2초 틈, 아니면 1초. */
    fun frameDue(now: Double, live: Boolean, changed: Boolean, moved: Boolean = false): Boolean {
        if (!live || finished || topic == null || socket != CrossyDuelFrameSocketPhase.Joined) return false
        val last = lastSentAt ?: return true
        val since = now - last
        if (changed && since >= minFrameGapSeconds) return true
        if (moved && since >= ghostFrameGapSeconds) return true
        return since >= frameIntervalSeconds
    }

    fun movedSinceLastFrame(ghost: CrossyDuelGhost): Boolean = ghost.moved(lastSentGhost)

    /** 지금 그릴 상대 그림자 — 끝나지 않은 판에서 최근(2.5초 안) 받은 프레임에 실렸을 때만. 죽어 있으면 null. */
    fun opponentGhost(now: Double): CrossyDuelGhost? {
        if (finished) return null
        val ghost = lastFrame?.ghost ?: return null
        if (ghost.dead) return null
        val heard = opponentHeardAt ?: return null
        return if (now - heard <= heardWithinSeconds) ghost else null
    }

    fun changedSinceLastFrame(score: Int, deaths: Int): Boolean = lastSentScore != score || lastSentDeaths != deaths

    /** 보낼 프레임을 만든다(`f` +1 · 보낸 시각 · 값 기록). */
    fun makeFrame(now: Double, seq: Int, score: Int, deaths: Int, ghost: CrossyDuelGhost? = null): CrossyDuelFrame {
        val frame = CrossyDuelFrame(
            sender = me, seq = maxOf(0, seq).toLong(), frame = nextFrameNumber,
            score = minOf(maxOf(0, score), CrossyDuelFrame.MAX_SCORE), deaths = maxOf(0, deaths),
            heardAgoMs = heardAgoMs(now), ghost = ghost,
        )
        nextFrameNumber += 1
        lastSentAt = now
        lastSentScore = score
        lastSentDeaths = deaths
        if (ghost != null) lastSentGhost = ghost
        return frame
    }

    private fun heardAgoMs(now: Double): Long {
        val at = opponentHeardAt ?: return -1
        val ms = (now - at) * 1000
        if (!ms.isFinite()) return -1
        return minOf(maxOf(0.0, swiftRound(ms)), Int.MAX_VALUE.toDouble()).toLong()
    }

    /** 상대 트랙 점수 — **끝나지 않은 판에서** max(프레임 sc, DB opponent.score). 끝난 판은 DB 값. */
    fun mergedOpponentScore(db: Int): Int {
        if (finished) return db
        val last = lastFrame ?: return db
        return maxOf(last.score, db)
    }
}
