// 원본: Sources/CheckCore/TetrisWire.swift @ 1b8260d · 한 판 한 기기(otherDevice · myDevice) @ 75c31cd2 · 판 표시 프레임 칸(state.frames) @ 12624739
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder

/**
 * 테트리스 와이어 상수(Swift `TetrisWire`). `p_protocol` 을 **언제나** 싣는다(C§4 #10 — `TetrisWire.swift:15`).
 * 응답 규약(C§4 #19 · `TetrisWire.swift:7-10`): status 만 필수, 나머지는 Optional, 모르는 status 는 `.unknown`.
 */
object TetrisWire {
    const val protocolVersion: Long = 1
}

/** Swift `TetrisRPCStatus`. */
@Serializable(with = TetrisRPCStatus.Serializer::class)
enum class TetrisRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"), notSignedIn("not_signed_in"), unsupportedClient("unsupported_client"), invalid("invalid"), blackout("blackout"),
    targetFocused("target_focused"), targetOutdated("target_outdated"), busy("busy"), targetBusy("target_busy"),
    alreadyPending("already_pending"), insufficient("insufficient"), notFound("not_found"), notPending("not_pending"),
    expired("expired"), notActive("not_active"), stale("stale"),

    /**
     * 보고·기권이 **이 판을 연 기기의 것이 아니다**(서버 20261103124000 — 한 판 한 기기). 같은 계정의 다른 기기가 신청·수락한
     * 판이거나, 보낸 누계(지운 줄·공격)가 서버 값보다 뒤로 갔다. 서버는 **쓰지도 정산하지도 않았고** `state` 는 실려 온다.
     * 클라는 판 루프를 멈추고 그 판에서 물러난다(`yieldMatchToOtherDevice`). 옛 코어(≤ 0.3.68)는 [unknown] 으로 접는다.
     */
    otherDevice("other_device"),
    unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<TetrisRPCStatus>("TetrisRPCStatus", entries, unknown)
}

/** Swift `TetrisProtocolRequest`: Encodable. */
@Serializable
data class TetrisProtocolRequest(
    @SerialName("p_protocol") val pProtocol: Long = TetrisWire.protocolVersion,
)

/** Swift `TetrisChallengeRequest`: Encodable. */
@Serializable
data class TetrisChallengeRequest(
    @SerialName("p_protocol") val pProtocol: Long = TetrisWire.protocolVersion,
    @SerialName("p_opponent") val pOpponent: String,
    @SerialName("p_stake") val pStake: Long,
)

/** Swift `TetrisMatchRequest`: Encodable. */
@Serializable
data class TetrisMatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = TetrisWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
)

/** Swift `TetrisRespondRequest`: Encodable. */
@Serializable
data class TetrisRespondRequest(
    @SerialName("p_protocol") val pProtocol: Long = TetrisWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_accept") val pAccept: Boolean,
)

/** Swift `TetrisReportRequest`(Swift 는 `TetrisDuelReport`(W1-a)에서 칸을 옮겨 담는다 — 여기선 칸을 직접 받는다). */
@Serializable
data class TetrisReportRequest(
    @SerialName("p_protocol") val pProtocol: Long = TetrisWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_seq") val pSeq: Long,
    @SerialName("p_board") val pBoard: String,
    @SerialName("p_lines") val pLines: Long,
    @SerialName("p_garbage_sent") val pGarbageSent: Long,
    @SerialName("p_garbage_applied") val pGarbageApplied: Long,
    @SerialName("p_pending") val pPending: Long,
    @SerialName("p_topped_out") val pToppedOut: Boolean,
)

/** Swift `TetrisPeerRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisPeerRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
)

/** Swift `TetrisUserRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisUserRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("is_working") val isWorking: Boolean? = null,
    @SerialName("in_match") val inMatch: Boolean? = null,
    @SerialName("capable") val capable: Boolean? = null,
    @SerialName("focus_mode") val focusMode: Boolean? = null,
)

/** Swift `TetrisInviteRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisInviteRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("from") val from: TetrisPeerRow? = null,
    @SerialName("to") val to: TetrisPeerRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
)

/** Swift `TetrisLobbyMe`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisLobbyMe(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("active_match_id") val activeMatchId: String? = null,
    @SerialName("incoming") val incoming: List<TetrisInviteRow>? = null,
    @SerialName("outgoing") val outgoing: TetrisInviteRow? = null,
)

/** Swift `TetrisLobbyMatchRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisLobbyMatchRow(
    @SerialName("id") val id: String? = null,
    @SerialName("a") val a: TetrisPeerRow? = null,
    @SerialName("b") val b: TetrisPeerRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("started_at_ms") val startedAtMs: Double? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `TetrisLobbyResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisLobbyResponse(
    @SerialName("status") val status: TetrisRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("me") val me: TetrisLobbyMe? = null,
    @SerialName("users") val users: List<TetrisUserRow>? = null,
    @SerialName("matches") val matches: List<TetrisLobbyMatchRow>? = null,
)

/** Swift `TetrisPlayerRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisPlayerRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("ready") val ready: Boolean? = null,
    @SerialName("seq") val seq: Long? = null,
    @SerialName("board") val board: String? = null,
    @SerialName("lines") val lines: Long? = null,
    @SerialName("garbage_sent") val garbageSent: Long? = null,
    @SerialName("garbage_applied") val garbageApplied: Long? = null,
    @SerialName("pending") val pending: Long? = null,
    @SerialName("last_seen_ms") val lastSeenMs: Double? = null,
    @SerialName("topped_out") val toppedOut: Boolean? = null,
)

/** Swift `TetrisStatePayload`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisStatePayload(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("seed") val seed: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("accepted_at_ms") val acceptedAtMs: Double? = null,
    @SerialName("start_at_ms") val startAtMs: Double? = null,
    @SerialName("ready_deadline_ms") val readyDeadlineMs: Double? = null,
    @SerialName("max_end_ms") val maxEndMs: Double? = null,
    @SerialName("finished_at_ms") val finishedAtMs: Double? = null,
    @SerialName("me") val me: TetrisPlayerRow? = null,
    @SerialName("opponent") val opponent: TetrisPlayerRow? = null,
    @SerialName("result") val result: String? = null,
    @SerialName("winner") val winner: String? = null,
    @SerialName("end_reason") val endReason: String? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("watchers") val watchers: Long? = null,
    /**
     * 이 판의 내 자리를 **이 기기가** 두는가(서버 20261103124000 — 부르는 토큰의 로그인 세션을 그 자리를 연 세션과 견준다).
     * 'this' | 'other' | null. null 은 "모른다" 다(옛 서버 · 기록 없는 판 · 세션 없는 토큰) — 스토어가 '이 기기가 연 판' 기록으로 가른다.
     */
    @SerialName("my_device") val myDevice: String? = null,
    /**
     * 판 표시 프레임(맥 main 0.3.74 — `TetrisWire.swift` `TetrisStatePayload.frames`). 진행 중 판에서 서버 스위치가 켜져 있고 두 자리 모두
     * 프레임을 아는 기기(`p_protocol` 2)가 보고했으면 `{on:true, topic:"tetris:<match>"}`, 아니면 null. 옛 서버엔 없다 → null.
     * ★ 이 판(안드로이드 판 7)은 프레임 소켓을 열지 않는다 — `tetris_report` 는 언제나 `p_protocol` 1 이라 서버가 켤 일이 없다.
     *   디코드 모양만 맥과 맞춘다(골든 wire/decode-demo-games 의 덤프 칸).
     */
    @SerialName("frames") val frames: TetrisFramesRow? = null,
)

/**
 * Swift `TetrisFramesRow` — **전 칸 Optional 이고 디코드가 절대 throw 하지 않는다**(칸이 깨져 와도 판 상태 전체가 죽지 않게).
 * 객체가 아니면 두 칸 모두 null 인 값, 칸마다 모양이 틀리면 그 칸만 null(Swift `try? container?.decodeIfPresent`).
 */
@Serializable(with = TetrisFramesRow.Serializer::class)
data class TetrisFramesRow(
    val on: Boolean? = null,
    /** 조인할 토픽(접두사 `realtime:` 없음). 서버가 조립한 글자 그대로. */
    val topic: String? = null,
) {
    object Serializer : SwiftDecodableSerializer<TetrisFramesRow>("TetrisFramesRow") {
        override fun deserialize(decoder: Decoder): TetrisFramesRow {
            val c = swiftTry { SwiftDecoding.keyed(decoder) } ?: return TetrisFramesRow()
            return TetrisFramesRow(on = c.lossyBool("on"), topic = c.lossyString("topic"))
        }
    }
}

/** Swift `TetrisActionResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisActionResponse(
    @SerialName("status") val status: TetrisRPCStatus,
    @SerialName("state") val state: TetrisStatePayload? = null,
    @SerialName("accepted") val accepted: Boolean? = null,
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
    @SerialName("side") val side: String? = null,
    @SerialName("need") val need: Long? = null,
    @SerialName("have") val have: Long? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("match_status") val matchStatus: String? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

/** Swift `TetrisWatchUserRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisWatchUserRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
)

/** Swift `TetrisWatchMatchRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisWatchMatchRow(
    @SerialName("id") val id: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("started_ms") val startedMs: Double? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("result") val result: String? = null,
    @SerialName("winner") val winner: String? = null,
    @SerialName("reason") val reason: String? = null,
    @SerialName("finished_ms") val finishedMs: Double? = null,
)

/** Swift `TetrisWatchSideRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisWatchSideRow(
    @SerialName("user") val user: TetrisWatchUserRow? = null,
    @SerialName("board") val board: String? = null,
    @SerialName("lines") val lines: Long? = null,
    @SerialName("pending") val pending: Long? = null,
    @SerialName("garbage_sent") val garbageSent: Long? = null,
    @SerialName("topped_out") val toppedOut: Boolean? = null,
    @SerialName("last_seen_ms") val lastSeenMs: Double? = null,
)

/** Swift `TetrisWatchResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisWatchResponse(
    @SerialName("status") val status: TetrisRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("match") val match: TetrisWatchMatchRow? = null,
    @SerialName("a") val a: TetrisWatchSideRow? = null,
    @SerialName("b") val b: TetrisWatchSideRow? = null,
    @SerialName("watchers") val watchers: Long? = null,
)

/** Swift `TetrisRankRow`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisRankRow(
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

/** Swift `TetrisRankingMe`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisRankingMe(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

/** Swift `TetrisRankingResponse`: Decodable, Equatable, Sendable. */
@Serializable
data class TetrisRankingResponse(
    @SerialName("status") val status: TetrisRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("record_since_ms") val recordSinceMs: Double? = null,
    @SerialName("me") val me: TetrisRankingMe? = null,
    @SerialName("rows") val rows: List<TetrisRankRow>? = null,
)
