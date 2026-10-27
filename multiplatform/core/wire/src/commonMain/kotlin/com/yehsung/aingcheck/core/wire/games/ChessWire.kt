// 원본: Sources/CheckCore/ChessWire.swift @ 1b8260d
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encoding.Decoder

/** 체스 와이어 상수(Swift `ChessWire`). `p_protocol` 은 **언제나** 싣는다(C§4 #10 — 빠지면 서버가 다른 오버로드를 고른다). */
object ChessWire {
    const val protocolVersion: Long = 1
}

/** Swift `ChessRPCStatus` — 모르는 status 는 `.unknown`(C§4 #19). 상수 이름 = Swift case 이름. */
@Serializable(with = ChessRPCStatus.Serializer::class)
enum class ChessRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"), unauthorized("unauthorized"), unsupportedClient("unsupported_client"), invalid("invalid"), blackout("blackout"),
    targetFocused("target_focused"), targetOutdated("target_outdated"), busy("busy"), targetBusy("target_busy"),
    alreadyPending("already_pending"), insufficient("insufficient"), notFound("not_found"), notPending("not_pending"),
    expired("expired"), notActive("not_active"), stale("stale"), notYourTurn("not_your_turn"), illegal("illegal"),
    retry("retry"), offerPending("offer_pending"), noOffer("no_offer"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<ChessRPCStatus>("ChessRPCStatus", entries, unknown)
}

/** Swift `ChessProtocolRequest`: Encodable. */
@Serializable
data class ChessProtocolRequest(
    @SerialName("p_protocol") val pProtocol: Long = ChessWire.protocolVersion,
)

/** Swift `ChessChallengeRequest`: Encodable. */
@Serializable
data class ChessChallengeRequest(
    @SerialName("p_protocol") val pProtocol: Long = ChessWire.protocolVersion,
    @SerialName("p_opponent") val pOpponent: String,
    @SerialName("p_stake") val pStake: Long,
)

/** Swift `ChessMatchRequest`: Encodable. */
@Serializable
data class ChessMatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = ChessWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
)

/** Swift `ChessRespondRequest`: Encodable. */
@Serializable
data class ChessRespondRequest(
    @SerialName("p_protocol") val pProtocol: Long = ChessWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_accept") val pAccept: Boolean,
)

/** Swift `ChessMoveRequest`: Encodable. */
@Serializable
data class ChessMoveRequest(
    @SerialName("p_protocol") val pProtocol: Long = ChessWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_expected_ply") val pExpectedPly: Long,
    @SerialName("p_uci") val pUci: String,
)

/** Swift `ChessSinceRequest`: Encodable. */
@Serializable
data class ChessSinceRequest(
    @SerialName("p_protocol") val pProtocol: Long = ChessWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_since_seq") val pSinceSeq: Long,
)

/** Swift `ChessUserRow`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessUserRow(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
    @SerialName("is_working") val isWorking: Boolean? = null,
    @SerialName("capable") val capable: Boolean? = null,
    @SerialName("in_match") val inMatch: Boolean? = null,
)

/** Swift `ChessLobbyMe`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessLobbyMe(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("active_match_id") val activeMatchId: String? = null,
    @SerialName("outgoing_match_id") val outgoingMatchId: String? = null,
    @SerialName("incoming_match_id") val incomingMatchId: String? = null,
)

/** Swift `ChessLobbyMatchRow`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessLobbyMatchRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("a") val a: ChessUserRow? = null,
    @SerialName("b") val b: ChessUserRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("started_ms") val startedMs: Double? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `ChessLobbyResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessLobbyResponse(
    @SerialName("status") val status: ChessRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("initial_ms") val initialMs: Long? = null,
    @SerialName("increment_ms") val incrementMs: Long? = null,
    @SerialName("grace_ms") val graceMs: Long? = null,
    @SerialName("invite_ttl_seconds") val inviteTtlSeconds: Long? = null,
    @SerialName("me") val me: ChessLobbyMe? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("users") val users: List<ChessUserRow>? = null,
    @SerialName("matches") val matches: List<ChessLobbyMatchRow>? = null,
)

/** Swift `ChessMatchRow`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessMatchRow(
    @SerialName("id") val id: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("white") val white: String? = null,
    @SerialName("black") val black: String? = null,
    @SerialName("challenger") val challenger: String? = null,
    @SerialName("opponent") val opponent: String? = null,
    @SerialName("ply_count") val plyCount: Long? = null,
    @SerialName("fen") val fen: String? = null,
    @SerialName("turn") val turn: String? = null,
    @SerialName("white_ms_left") val whiteMsLeft: Long? = null,
    @SerialName("black_ms_left") val blackMsLeft: Long? = null,
    @SerialName("white_grace_ms") val whiteGraceMs: Long? = null,
    @SerialName("black_grace_ms") val blackGraceMs: Long? = null,
    @SerialName("increment_ms") val incrementMs: Long? = null,
    @SerialName("deadline_ms") val deadlineMs: Double? = null,
    @SerialName("turn_started_ms") val turnStartedMs: Double? = null,
    @SerialName("draw_offer_by") val drawOfferBy: String? = null,
    @SerialName("result") val result: String? = null,
    @SerialName("end_reason") val endReason: String? = null,
    @SerialName("winner") val winner: String? = null,
    @SerialName("invite_expires_ms") val inviteExpiresMs: Double? = null,
    @SerialName("started_ms") val startedMs: Double? = null,
    @SerialName("finished_ms") val finishedMs: Double? = null,
)

/** Swift `ChessMoveRow`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessMoveRow(
    @SerialName("seq") val seq: Long? = null,
    @SerialName("color") val color: String? = null,
    @SerialName("from") val from: Long? = null,
    @SerialName("to") val to: Long? = null,
    @SerialName("promo") val promo: String? = null,
    @SerialName("san") val san: String? = null,
    @SerialName("fen") val fen: String? = null,
    @SerialName("ms_left") val msLeft: Long? = null,
    @SerialName("ms_spent") val msSpent: Long? = null,
)

/** Swift `ChessStatePayload`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessStatePayload(
    @SerialName("match") val match: ChessMatchRow? = null,
    @SerialName("moves") val moves: List<ChessMoveRow>? = null,
    @SerialName("my_color") val myColor: String? = null,
    @SerialName("opponent") val opponent: ChessUserRow? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("in_check") val inCheck: Boolean? = null,
    @SerialName("legal_moves") val legalMoves: List<String>? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `ChessRankRow`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessRankRow(
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

/** Swift `ChessRankingMe`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessRankingMe(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

/** Swift `ChessRankingResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessRankingResponse(
    @SerialName("status") val status: ChessRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("record_since_ms") val recordSinceMs: Double? = null,
    @SerialName("me") val me: ChessRankingMe? = null,
    @SerialName("rows") val rows: List<ChessRankRow>? = null,
)

/** Swift `ChessWatchResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class ChessWatchResponse(
    @SerialName("status") val status: ChessRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("match") val match: ChessMatchRow? = null,
    @SerialName("moves") val moves: List<ChessMoveRow>? = null,
    @SerialName("in_check") val inCheck: Boolean? = null,
    @SerialName("black_user") val blackUser: ChessUserRow? = null,
    @SerialName("white_user") val whiteUser: ChessUserRow? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `ChessStateResponse` — status 와 **같은 객체**에서 `ChessStatePayload` 를 읽는다(평평한 응답). */
@Serializable(with = ChessStateResponse.Serializer::class)
data class ChessStateResponse(
    val status: ChessRPCStatus,
    val state: ChessStatePayload,
) {
    object Serializer : SwiftDecodableSerializer<ChessStateResponse>("ChessStateResponse") {
        override fun deserialize(decoder: Decoder): ChessStateResponse {
            val c = SwiftDecoding.keyed(decoder)
            return ChessStateResponse(
                status = c.decode("status", ChessRPCStatus.serializer()),
                state = c.decodeSelf(ChessStatePayload.serializer()),
            )
        }
    }
}

/**
 * Swift `ChessActionResponse` — `match` 칸이 있으면(갱신된 판이 실려 왔으면) 같은 객체를 `ChessStatePayload` 로도 읽는다.
 * 나머지 칸은 합성 `decodeIfPresent`(없음·null → null, 타입이 다르면 던진다).
 */
@Serializable(with = ChessActionResponse.Serializer::class)
data class ChessActionResponse(
    val status: ChessRPCStatus,
    val state: ChessStatePayload? = null,
    val accepted: Boolean? = null,
    val san: String? = null,
    val outcome: String? = null,
    val repetition: Long? = null,
    val uci: String? = null,
    val reason: String? = null,
    val matchId: String? = null,
    val inviteExpiresMs: Double? = null,
    val side: String? = null,
    val need: Long? = null,
    val have: Long? = null,
    val stakes: List<Long>? = null,
    val matchStatus: String? = null,
    val rubyBalance: Long? = null,
    val serverNowMs: Double? = null,
) {
    object Serializer : SwiftDecodableSerializer<ChessActionResponse>("ChessActionResponse") {
        override fun deserialize(decoder: Decoder): ChessActionResponse {
            val c = SwiftDecoding.keyed(decoder)
            return ChessActionResponse(
                status = c.decode("status", ChessRPCStatus.serializer()),
                state = if (c.contains("match")) c.decodeSelf(ChessStatePayload.serializer()) else null,
                accepted = c.boolIfPresent("accepted"),
                san = c.stringIfPresent("san"),
                outcome = c.stringIfPresent("outcome"),
                repetition = c.longIfPresent("repetition"),
                uci = c.stringIfPresent("uci"),
                reason = c.stringIfPresent("reason"),
                matchId = c.stringIfPresent("match_id"),
                inviteExpiresMs = c.doubleIfPresent("invite_expires_ms"),
                side = c.stringIfPresent("side"),
                need = c.longIfPresent("need"),
                have = c.longIfPresent("have"),
                stakes = c.decodeIfPresent("stakes", ListSerializer(Long.serializer())),
                matchStatus = c.stringIfPresent("match_status"),
                rubyBalance = c.longIfPresent("ruby_balance"),
                serverNowMs = c.doubleIfPresent("server_now_ms"),
            )
        }
    }
}
