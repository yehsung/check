// 원본: Sources/CheckCore/SupabaseWorkModels.swift:3677-4186(MARK 1:1 오목 · 순위표·관전) @ 1b8260d
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder

/** 오목 와이어 상수(Swift `GomokuWire`). `p_protocol` 2 를 **언제나** 싣는다(C§4 #10). */
object GomokuWire {
    const val protocolVersion: Long = 2
}

/** Swift `GomokuRPCStatus` — 모르는 status 는 `.unknown`(C§4 #19). */
@Serializable(with = GomokuRPCStatus.Serializer::class)
enum class GomokuRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"), unauthorized("unauthorized"), unsupportedClient("unsupported_client"), invalid("invalid"), blackout("blackout"),
    notWorking("not_working"), targetNotWorking("target_not_working"), targetFocused("target_focused"),
    targetOutdated("target_outdated"), busy("busy"), targetBusy("target_busy"), alreadyPending("already_pending"),
    insufficient("insufficient"), notFound("not_found"), notPending("not_pending"), expired("expired"), notActive("not_active"),
    notFinished("not_finished"), timeout("timeout"), autoPlaced("auto_placed"), notYourTurn("not_your_turn"), stale("stale"),
    forbidden("forbidden"), flood("flood"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<GomokuRPCStatus>("GomokuRPCStatus", entries, unknown)
}

/** Swift `GomokuChatKind`(요청에 원시값으로만 실린다). */
enum class GomokuChatKind(override val rawValue: String) : SwiftRawValued { text("text"), quick("quick") }

/** Swift `GomokuLobbyRequest`: Encodable. */
@Serializable
data class GomokuLobbyRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
)

/** Swift `GomokuInboxRequest`: Encodable. */
@Serializable
data class GomokuInboxRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
)

/** Swift `GomokuChallengeRequest`: Encodable. */
@Serializable
data class GomokuChallengeRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_opponent") val pOpponent: String,
    @SerialName("p_stake") val pStake: Long,
)

/** Swift `GomokuMatchRequest`: Encodable. */
@Serializable
data class GomokuMatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
)

/** Swift `GomokuRespondRequest`: Encodable. */
@Serializable
data class GomokuRespondRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_accept") val pAccept: Boolean,
)

/** Swift `GomokuMoveRequest`: Encodable. */
@Serializable
data class GomokuMoveRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_expected_seq") val pExpectedSeq: Long,
    @SerialName("p_x") val pX: Long,
    @SerialName("p_y") val pY: Long,
)

/** Swift `GomokuStateRequest`: Encodable. */
@Serializable
data class GomokuStateRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_since_seq") val pSinceSeq: Long,
    @SerialName("p_since_chat_seq") val pSinceChatSeq: Long,
)

/** Swift `GomokuChatSendRequest`: Encodable. */
@Serializable
data class GomokuChatSendRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_kind") val pKind: String,
    @SerialName("p_body") val pBody: String,
)

/** Swift `GomokuChatMuteRequest`: Encodable. */
@Serializable
data class GomokuChatMuteRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_muted") val pMuted: Boolean,
)

/** Swift `GomokuRankingRequest`: Encodable. */
@Serializable
data class GomokuRankingRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
)

/** Swift `GomokuWatchRequest`: Encodable. */
@Serializable
data class GomokuWatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = GomokuWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_since_seq") val pSinceSeq: Long,
)

/** Swift `GomokuUserRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuUserRow(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
    @SerialName("is_working") val isWorking: Boolean? = null,
    @SerialName("capable") val capable: Boolean? = null,
    @SerialName("in_match") val inMatch: Boolean? = null,
)

/** Swift `GomokuLobbyMe`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuLobbyMe(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("active_match_id") val activeMatchId: String? = null,
    @SerialName("outgoing_match_id") val outgoingMatchId: String? = null,
)

/** Swift `GomokuLobbyMatchRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuLobbyMatchRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("a") val a: GomokuUserRow? = null,
    @SerialName("b") val b: GomokuUserRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("started_ms") val startedMs: Double? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `GomokuLobbyResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuLobbyResponse(
    @SerialName("status") val status: GomokuRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("turn_seconds") val turnSeconds: Long? = null,
    @SerialName("invite_ttl_seconds") val inviteTtlSeconds: Long? = null,
    @SerialName("me") val me: GomokuLobbyMe? = null,
    @SerialName("users") val users: List<GomokuUserRow>? = null,
    @SerialName("matches") val matches: List<GomokuLobbyMatchRow>? = null,
    @SerialName("auto_abandon_streak") val autoAbandonStreak: Long? = null,
)

/** Swift `GomokuMatchRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuMatchRow(
    @SerialName("id") val id: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("black") val black: String? = null,
    @SerialName("white") val white: String? = null,
    @SerialName("challenger") val challenger: String? = null,
    @SerialName("opponent") val opponent: String? = null,
    @SerialName("move_count") val moveCount: Long? = null,
    @SerialName("turn") val turn: String? = null,
    @SerialName("deadline_ms") val deadlineMs: Double? = null,
    @SerialName("result") val result: String? = null,
    @SerialName("end_reason") val endReason: String? = null,
    @SerialName("winner") val winner: String? = null,
    @SerialName("invite_expires_ms") val inviteExpiresMs: Double? = null,
    @SerialName("board") val board: String? = null,
    @SerialName("turn_started_ms") val turnStartedMs: Double? = null,
    @SerialName("started_ms") val startedMs: Double? = null,
    @SerialName("finished_ms") val finishedMs: Double? = null,
)

/** Swift `GomokuMoveRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuMoveRow(
    @SerialName("seq") val seq: Long? = null,
    @SerialName("color") val color: String? = null,
    @SerialName("kind") val kind: String? = null,
    @SerialName("x") val x: Long? = null,
    @SerialName("y") val y: Long? = null,
    @SerialName("auto") val auto: Boolean? = null,
)

/** Swift `GomokuChatRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuChatRow(
    @SerialName("seq") val seq: Long? = null,
    @SerialName("kind") val kind: String? = null,
    @SerialName("body") val body: String? = null,
    @SerialName("mine") val mine: Boolean? = null,
    @SerialName("created_ms") val createdMs: Double? = null,
)

/** Swift `GomokuStatePayload`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuStatePayload(
    @SerialName("match") val match: GomokuMatchRow? = null,
    @SerialName("moves") val moves: List<GomokuMoveRow>? = null,
    @SerialName("my_color") val myColor: String? = null,
    @SerialName("opponent") val opponent: GomokuUserRow? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("chat") val chat: List<GomokuChatRow>? = null,
    @SerialName("chat_seq") val chatSeq: Long? = null,
    @SerialName("my_muted") val myMuted: Boolean? = null,
    @SerialName("opponent_muted") val opponentMuted: Boolean? = null,
    @SerialName("chat_capable") val chatCapable: Boolean? = null,
    @SerialName("chat_max_len") val chatMaxLen: Long? = null,
    @SerialName("my_auto_streak") val myAutoStreak: Long? = null,
    @SerialName("opponent_auto_streak") val opponentAutoStreak: Long? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `GomokuInviteRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuInviteRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("challenger") val challenger: GomokuUserRow? = null,
    @SerialName("opponent") val opponent: GomokuUserRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("invite_expires_ms") val inviteExpiresMs: Double? = null,
)

/** Swift `GomokuLastFinishedRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuLastFinishedRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("result") val result: String? = null,
    @SerialName("end_reason") val endReason: String? = null,
    @SerialName("winner") val winner: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("finished_ms") val finishedMs: Double? = null,
)

/** Swift `GomokuInboxResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuInboxResponse(
    @SerialName("status") val status: GomokuRPCStatus,
    @SerialName("incoming") val incoming: List<GomokuInviteRow>? = null,
    @SerialName("outgoing") val outgoing: GomokuInviteRow? = null,
    @SerialName("active_match_id") val activeMatchId: String? = null,
    @SerialName("last_finished") val lastFinished: GomokuLastFinishedRow? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

// INV-SupabaseWorkModels-2a2b5957 이식: retry_after_seconds 를 두지 않는다(flood 에 숫자를 읽는 순간 화면이 카운트다운을 그린다).
/** Swift `GomokuChatResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuChatResponse(
    @SerialName("status") val status: GomokuRPCStatus,
    @SerialName("chat_seq") val chatSeq: Long? = null,
    @SerialName("opponent_muted") val opponentMuted: Boolean? = null,
    @SerialName("chat_capable") val chatCapable: Boolean? = null,
    @SerialName("chat_max_len") val chatMaxLen: Long? = null,
    @SerialName("muted") val muted: Boolean? = null,
    @SerialName("match_status") val matchStatus: String? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

/** Swift `GomokuLeaveResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuLeaveResponse(
    @SerialName("status") val status: GomokuRPCStatus,
    @SerialName("both_left") val bothLeft: Boolean? = null,
    @SerialName("match_status") val matchStatus: String? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

/** Swift `GomokuRankRow`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuRankRow(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

/** Swift `GomokuRankingMe`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuRankingMe(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

/** Swift `GomokuRankingResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuRankingResponse(
    @SerialName("status") val status: GomokuRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("record_since_ms") val recordSinceMs: Double? = null,
    @SerialName("me") val me: GomokuRankingMe? = null,
    @SerialName("rows") val rows: List<GomokuRankRow>? = null,
)

/** Swift `GomokuWatchResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class GomokuWatchResponse(
    @SerialName("status") val status: GomokuRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("match") val match: GomokuMatchRow? = null,
    @SerialName("moves") val moves: List<GomokuMoveRow>? = null,
    @SerialName("black_user") val blackUser: GomokuUserRow? = null,
    @SerialName("white_user") val whiteUser: GomokuUserRow? = null,
    @SerialName("black_auto_streak") val blackAutoStreak: Long? = null,
    @SerialName("white_auto_streak") val whiteAutoStreak: Long? = null,
    @SerialName("auto_abandon_streak") val autoAbandonStreak: Long? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `GomokuStateResponse` — status 와 같은 객체에서 `GomokuStatePayload` 를 읽는다(평평한 응답). */
@Serializable(with = GomokuStateResponse.Serializer::class)
data class GomokuStateResponse(
    val status: GomokuRPCStatus,
    val state: GomokuStatePayload,
) {
    object Serializer : SwiftDecodableSerializer<GomokuStateResponse>("GomokuStateResponse") {
        override fun deserialize(decoder: Decoder): GomokuStateResponse {
            val c = SwiftDecoding.keyed(decoder)
            return GomokuStateResponse(
                status = c.decode("status", GomokuRPCStatus.serializer()),
                state = c.decodeSelf(GomokuStatePayload.serializer()),
            )
        }
    }
}

/**
 * Swift `GomokuActionResponse` — 판은 `state` 칸(중첩)이 먼저, 없으면 `match` 칸이 있을 때 **같은 객체**를 판으로 읽는다.
 */
@Serializable(with = GomokuActionResponse.Serializer::class)
data class GomokuActionResponse(
    val status: GomokuRPCStatus,
    val state: GomokuStatePayload? = null,
    val blackPassed: Boolean? = null,
    val reason: String? = null,
    val side: String? = null,
    val need: Long? = null,
    val have: Long? = null,
    val rubyBalance: Long? = null,
    val serverNowMs: Double? = null,
    val matchId: String? = null,
    val inviteExpiresMs: Double? = null,
) {
    object Serializer : SwiftDecodableSerializer<GomokuActionResponse>("GomokuActionResponse") {
        override fun deserialize(decoder: Decoder): GomokuActionResponse {
            val c = SwiftDecoding.keyed(decoder)
            val status = c.decode("status", GomokuRPCStatus.serializer())
            val nested = c.decodeIfPresent("state", GomokuStatePayload.serializer())
            val state = nested ?: if (c.contains("match")) c.decodeSelf(GomokuStatePayload.serializer()) else null
            return GomokuActionResponse(
                status = status,
                state = state,
                blackPassed = c.boolIfPresent("black_passed"),
                reason = c.stringIfPresent("reason"),
                side = c.stringIfPresent("side"),
                need = c.longIfPresent("need"),
                have = c.longIfPresent("have"),
                rubyBalance = c.longIfPresent("ruby_balance"),
                serverNowMs = c.doubleIfPresent("server_now_ms"),
                matchId = c.stringIfPresent("match_id"),
                inviteExpiresMs = c.doubleIfPresent("invite_expires_ms"),
            )
        }
    }
}
