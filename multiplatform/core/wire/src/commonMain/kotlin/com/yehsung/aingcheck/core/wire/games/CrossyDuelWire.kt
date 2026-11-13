// 원본: Sources/CheckCore/CrossyDuelWire.swift @ e4995a3a(1:1 길건너 — 맥 0.3.78 · 폰 1.0.18 · Android 판 8) · CrossyDuelReportBody @ CrossyDuelSession.swift
//
// 1:1 길건너 RPC 의 와이어 타입(요청·응답) — `/rest/v1/rpc/crossy_duel_*`. 계약 정본은 설계서 crossy-duel/SPEC.md v1.3 §6.3~6.5 · §3.4 B5.
// **키 이름을 바꾸지 마라.** 테트리스 와이어(TetrisWire.kt)의 규약을 그대로 베낀다:
//  ① status 만 필수이고 나머지는 전부 null 가능 — 서버가 키를 늘리기 전 창에서 디코드가 통째로 죽지 않게.
//  ② 모르는 status 는 [CrossyDuelRPCStatus.unknown] 으로 접는다.
//  ③ 시각은 전부 epoch **밀리초**(Double). 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 빈 `{}` 가 아니다 — `p_protocol` 을 언제나 싣는다.
//  ⑤ 상태는 `{status, state}` 봉투의 `state` 키에 들어온다.
// 정수 칸은 Swift Int(64비트)라 Long 이다(골든 'big' 변형 — 판 8 리버시 교훈).
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder

object CrossyDuelWire {
    const val protocolVersion: Long = 1

    object RPC {
        const val lobby = "crossy_duel_lobby"
        const val challenge = "crossy_duel_challenge"
        const val cancel = "crossy_duel_cancel"
        const val respond = "crossy_duel_respond"
        const val report = "crossy_duel_report"
        const val state = "crossy_duel_state"
        const val resign = "crossy_duel_resign"
        const val ranking = "crossy_duel_ranking"
        val all = listOf(lobby, challenge, cancel, respond, report, state, resign, ranking)
    }
}

@Serializable(with = CrossyDuelRPCStatus.Serializer::class)
enum class CrossyDuelRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"), notSignedIn("not_signed_in"), unsupportedClient("unsupported_client"), invalid("invalid"), blackout("blackout"),
    targetFocused("target_focused"), targetOutdated("target_outdated"), busy("busy"), targetBusy("target_busy"),
    alreadyPending("already_pending"), insufficient("insufficient"), notFound("not_found"), notPending("not_pending"),
    expired("expired"), notActive("not_active"), stale("stale"), otherDevice("other_device"),
    unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<CrossyDuelRPCStatus>("CrossyDuelRPCStatus", entries, unknown)
}

// MARK: 요청 본문

@Serializable
data class CrossyDuelProtocolRequest(@SerialName("p_protocol") val pProtocol: Long = CrossyDuelWire.protocolVersion)

@Serializable
data class CrossyDuelLobbyRequest(
    @SerialName("p_protocol") val pProtocol: Long = CrossyDuelWire.protocolVersion,
    /** false 면 서버가 `me` 만 채우고 `users` 는 빈 배열 · 전적은 null(가벼운 로비). */
    @SerialName("p_users") val pUsers: Boolean,
)

@Serializable
data class CrossyDuelChallengeRequest(
    @SerialName("p_protocol") val pProtocol: Long = CrossyDuelWire.protocolVersion,
    @SerialName("p_opponent") val pOpponent: String,
    @SerialName("p_stake") val pStake: Long,
)

@Serializable
data class CrossyDuelMatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = CrossyDuelWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
)

@Serializable
data class CrossyDuelRespondRequest(
    @SerialName("p_protocol") val pProtocol: Long = CrossyDuelWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_accept") val pAccept: Boolean,
)

/** 보고 한 번의 몸통(누계 — 순번 · 점수 · 넘어진 수). */
data class CrossyDuelReportBody(val seq: Long, val score: Long, val deaths: Long)

@Serializable
data class CrossyDuelReportRequest(
    @SerialName("p_protocol") val pProtocol: Long = CrossyDuelWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_seq") val pSeq: Long,
    @SerialName("p_score") val pScore: Long,
    @SerialName("p_deaths") val pDeaths: Long,
) {
    companion object {
        fun of(matchID: String, report: CrossyDuelReportBody): CrossyDuelReportRequest =
            CrossyDuelReportRequest(pMatchId = matchID, pSeq = report.seq, pScore = report.score, pDeaths = report.deaths)
    }
}

// MARK: 응답 행

@Serializable
data class CrossyDuelPeerRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
)

@Serializable
data class CrossyDuelUserRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("is_working") val isWorking: Boolean? = null,
    @SerialName("in_match") val inMatch: Boolean? = null,
    @SerialName("capable") val capable: Boolean? = null,
    @SerialName("focus_mode") val focusMode: Boolean? = null,
)

@Serializable
data class CrossyDuelInviteRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("from") val from: CrossyDuelPeerRow? = null,
    @SerialName("to") val to: CrossyDuelPeerRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
)

@Serializable
data class CrossyDuelLobbyMe(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("active_match_id") val activeMatchId: String? = null,
    @SerialName("incoming") val incoming: List<CrossyDuelInviteRow>? = null,
    @SerialName("outgoing") val outgoing: CrossyDuelInviteRow? = null,
)

@Serializable
data class CrossyDuelLobbyResponse(
    @SerialName("status") val status: CrossyDuelRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("goal") val goal: Long? = null,
    @SerialName("max_duration_seconds") val maxDurationSeconds: Long? = null,
    @SerialName("me") val me: CrossyDuelLobbyMe? = null,
    @SerialName("users") val users: List<CrossyDuelUserRow>? = null,
)

/** 한 사람 칸(판 — 경주 칸 `score` · `deaths` · `goal_at_ms`). */
@Serializable
data class CrossyDuelSideRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("ready") val ready: Boolean? = null,
    @SerialName("seq") val seq: Long? = null,
    @SerialName("score") val score: Long? = null,
    @SerialName("deaths") val deaths: Long? = null,
    @SerialName("goal_at_ms") val goalAtMs: Double? = null,
    @SerialName("last_seen_ms") val lastSeenMs: Double? = null,
)

/** 끝난 판의 굳은 점수(내 관점). */
@Serializable
data class CrossyDuelFinalRow(
    @SerialName("me") val me: Long? = null,
    @SerialName("opponent") val opponent: Long? = null,
)

/**
 * 판 그림 방송 칸(B5 — 능력 협상 없음, 모든 맥이 방송한다). 칸 하나가 틀려도 통째로 버리지 않는다(Swift 의 try? 디코드와 같다).
 * [activeTopic] = 켜져 있고 주제가 `crossy_duel:` 로 시작할 때만.
 */
@Serializable(with = CrossyDuelFramesRow.Serializer::class)
data class CrossyDuelFramesRow(val on: Boolean? = null, val topic: String? = null) {
    val activeTopic: String?
        get() {
            val t = topic ?: return null
            return if (on == true && t.startsWith(TOPIC_PREFIX) && t.length > TOPIC_PREFIX.length) t else null
        }

    companion object {
        const val TOPIC_PREFIX = "crossy_duel:"
    }

    object Serializer : SwiftDecodableSerializer<CrossyDuelFramesRow>("CrossyDuelFramesRow") {
        override fun deserialize(decoder: Decoder): CrossyDuelFramesRow {
            val c = swiftTry { SwiftDecoding.keyed(decoder) } ?: return CrossyDuelFramesRow()
            return CrossyDuelFramesRow(on = swiftTry { c.boolIfPresent("on") }, topic = swiftTry { c.stringIfPresent("topic") })
        }
    }
}

@Serializable
data class CrossyDuelStatePayload(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("seed") val seed: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("accepted_at_ms") val acceptedAtMs: Double? = null,
    @SerialName("ready_deadline_ms") val readyDeadlineMs: Double? = null,
    @SerialName("start_at_ms") val startAtMs: Double? = null,
    @SerialName("end_at_ms") val endAtMs: Double? = null,
    @SerialName("grace_end_ms") val graceEndMs: Double? = null,
    @SerialName("finished_at_ms") val finishedAtMs: Double? = null,
    @SerialName("goal") val goal: Long? = null,
    @SerialName("max_duration_seconds") val maxDurationSeconds: Long? = null,
    @SerialName("report_ms") val reportMs: Long? = null,
    @SerialName("heartbeat_ms") val heartbeatMs: Long? = null,
    @SerialName("silence_ms") val silenceMs: Long? = null,
    @SerialName("countdown_ms") val countdownMs: Long? = null,
    @SerialName("checkpoint_ms") val checkpointMs: Long? = null,
    @SerialName("me") val me: CrossyDuelSideRow? = null,
    @SerialName("opponent") val opponent: CrossyDuelSideRow? = null,
    @SerialName("result") val result: String? = null,
    @SerialName("winner") val winner: String? = null,
    @SerialName("end_reason") val endReason: String? = null,
    @SerialName("final") val final: CrossyDuelFinalRow? = null,
    @SerialName("my_device") val myDevice: String? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("frames") val frames: CrossyDuelFramesRow? = null,
)

/** 쓰기 · 조회 공용 응답(challenge · cancel · respond · report · state · resign). */
@Serializable
data class CrossyDuelActionResponse(
    @SerialName("status") val status: CrossyDuelRPCStatus,
    @SerialName("state") val state: CrossyDuelStatePayload? = null,
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
    @SerialName("need") val need: Long? = null,
    @SerialName("have") val have: Long? = null,
    @SerialName("side") val side: String? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("accepted") val accepted: Boolean? = null,
    @SerialName("match_status") val matchStatus: String? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

@Serializable
data class CrossyDuelRankRow(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

@Serializable
data class CrossyDuelRankingMe(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

@Serializable
data class CrossyDuelRankingResponse(
    @SerialName("status") val status: CrossyDuelRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("record_since_ms") val recordSinceMs: Double? = null,
    @SerialName("me") val me: CrossyDuelRankingMe? = null,
    @SerialName("rows") val rows: List<CrossyDuelRankRow>? = null,
)
