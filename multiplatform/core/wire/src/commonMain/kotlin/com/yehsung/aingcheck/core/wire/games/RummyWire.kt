// 원본: Sources/CheckCore/RummyWire.swift · RummyRules.swift(RummyFace · RummyTurnReason) · RummyTableLayout.swift(RummyPoint · RummyLayout) @ 1a5eeca6
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonNull

/**
 * 아잉 큐브(rummy) RPC 의 와이어 타입(요청·응답)과 RPC 이름 — `/rest/v1/rpc/rummy_*`. **화면·스토어·규칙은 아직 없다**(이 파일과 core/net RpcGames 의
 * 호출 14개까지가 G5·G6 골든이 재는 몫이다).
 *
 * 규약(Swift 파일 머리와 같다): status 와 행의 id 만 필수, 나머지는 Optional · 모르는 status·상태 글자는 `unknown` · 시각은 epoch 밀리초 Double ·
 * 요청 본문은 빈 `{}` 가 아니라 `p_protocol` 을 언제나 싣는다 · 면은 문자열(`"A7"`·`"J"`) · 비로그인 어휘는 `unauthorized` · uuid 는 소문자 문자열로 싣는다.
 */
object RummyWire {
    const val protocolVersion: Long = 1

    /** RPC 이름(서버 함수 이름 그대로). */
    object RPC {
        const val lobby = "rummy_lobby"
        const val create = "rummy_create"
        const val invite = "rummy_invite"
        const val join = "rummy_join"
        const val decline = "rummy_decline"
        const val leave = "rummy_leave"
        const val start = "rummy_start"
        const val state = "rummy_state"
        const val draft = "rummy_draft"
        const val play = "rummy_play"
        const val draw = "rummy_draw"
        const val ranking = "rummy_ranking"
        const val heartbeat = "rummy_heartbeat"
        const val react = "rummy_react"
    }
}

/** Swift `RummyRPCStatus`. 모르는 값은 [unknown]. */
@Serializable(with = RummyRPCStatus.Serializer::class)
enum class RummyRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"), unauthorized("unauthorized"), unsupportedClient("unsupported_client"), invalid("invalid"), busy("busy"),
    alreadyInRoom("already_in_room"), insufficient("insufficient"), notHost("not_host"), blackout("blackout"),
    targetFocused("target_focused"), targetOutdated("target_outdated"), targetBusy("target_busy"), roomFull("room_full"),
    tooManyInvites("too_many_invites"), alreadyInvited("already_invited"), roomClosed("room_closed"), notInvited("not_invited"),
    notEnoughPlayers("not_enough_players"), seatsDropped("seats_dropped"), notFound("not_found"), notYourTurn("not_your_turn"),
    stale("stale"), malformed("malformed"), tooFast("too_fast"), rejected("rejected"), notActive("not_active"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<RummyRPCStatus>("RummyRPCStatus", entries, unknown)
}

/** Swift `RummyMatchStatus`. */
@Serializable(with = RummyMatchStatus.Serializer::class)
enum class RummyMatchStatus(override val rawValue: String) : SwiftRawValued {
    forming("forming"), active("active"), finished("finished"), cancelled("cancelled"), expired("expired"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<RummyMatchStatus>("RummyMatchStatus", entries, unknown)
}

/** Swift `RummySeatState`. */
@Serializable(with = RummySeatState.Serializer::class)
enum class RummySeatState(override val rawValue: String) : SwiftRawValued {
    invited("invited"), joined("joined"), declined("declined"), left("left"), dropped("dropped"), playing("playing"),
    forfeit("forfeit"), done("done"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<RummySeatState>("RummySeatState", entries, unknown)
}

/** Swift `RummyEndReason`. */
@Serializable(with = RummyEndReason.Serializer::class)
enum class RummyEndReason(override val rawValue: String) : SwiftRawValued {
    rackEmpty("rack_empty"), blocked("blocked"), lastStanding("last_standing"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<RummyEndReason>("RummyEndReason", entries, unknown)
}

/** Swift `RummyTurnReason`(RummyRules.swift — play 거절 이유). */
@Serializable(with = RummyTurnReason.Serializer::class)
enum class RummyTurnReason(override val rawValue: String) : SwiftRawValued {
    ok("ok"), malformed("malformed"), jokerNotReused("joker_not_reused"), tableTileRemoved("table_tile_removed"),
    tileNotOwned("tile_not_owned"), noTilePlayed("no_tile_played"), invalidMeld("invalid_meld"),
    initialTableTouched("initial_table_touched"), initialUnder30("initial_under_30"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<RummyTurnReason>("RummyTurnReason", entries, unknown)
}

/**
 * Swift `RummyFace`(RummyRules.swift). 전선 값은 면 문자열 하나다. R-01 정규식(`^([ABCD](1[0-3]|[1-9])|J)$`)에 맞지 않으면 디코드가 던진다
 * — 응답 전체가 throw 하는 것까지 Swift 와 같다.
 */
@Serializable(with = RummyFace.Serializer::class)
data class RummyFace(
    /** 0…3 = A…D. 조커는 null. */
    val color: Long?,
    /** 1…13. 조커는 null. */
    val number: Long?,
) {
    /** "A7" / "J". */
    val text: String get() = if (color == null || number == null) "J" else "${COLOR_LETTERS[color.toInt()]}$number"

    object Serializer : KSerializer<RummyFace> {
        override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("RummyFace", PrimitiveKind.STRING)

        override fun deserialize(decoder: Decoder): RummyFace {
            val d = SwiftDecoding.single(decoder)
            val raw = d.decodeString()
            return of(raw) ?: throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, d.path, "R-01 면 표기가 아니다: $raw")
        }

        override fun serialize(encoder: Encoder, value: RummyFace) = encoder.encodeString(value.text)
    }

    companion object {
        private const val COLOR_LETTERS = "ABCD"
        private val FACE = Regex("[ABCD](1[0-3]|[1-9])|J")

        val joker = RummyFace(null, null)

        /** Swift `RummyFace(text:)`. */
        fun of(text: String): RummyFace? = when {
            !FACE.matches(text) -> null
            text == "J" -> joker
            else -> RummyFace(COLOR_LETTERS.indexOf(text[0]).toLong(), text.substring(1).toLong())
        }
    }
}

/** Swift `RummyPoint`(판 위 논리 좌표). 전선 값은 `[x, y]` 이고 서버 정리 범위(0…1000 · 0…640) 안일 때만 읽는다. */
@Serializable(with = RummyPoint.Serializer::class)
data class RummyPoint(val x: Long, val y: Long) {
    object Serializer : KSerializer<RummyPoint> {
        private val pair = ListSerializer(Long.serializer())
        override val descriptor: SerialDescriptor = pair.descriptor

        override fun deserialize(decoder: Decoder): RummyPoint {
            val d = SwiftDecoding.single(decoder)
            val items = SwiftDecoding.unkeyed(decoder)
            // Swift 는 x, y 차례로 읽고 isAtEnd 를 본다 — 모자라거나 남으면 던진다.
            if (items.size != 2) throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, d.path, "rummy point")
            val x = items[0].decodeLong()
            val y = items[1].decodeLong()
            if (x !in 0..CANVAS_WIDTH || y !in 0..CANVAS_HEIGHT) throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, d.path, "rummy point")
            return RummyPoint(x, y)
        }

        override fun serialize(encoder: Encoder, value: RummyPoint) = pair.serialize(encoder, listOf(value.x, value.y))
    }

    companion object {
        /** Swift `RummyTableLayout.canvasWidth` · `canvasHeight`. */
        const val CANVAS_WIDTH: Long = 1000
        const val CANVAS_HEIGHT: Long = 640
    }
}

/**
 * Swift `RummyLayout` — 전선 값 `[[x,y]|null]`. **디코드는 던지지 않는다**: 배열이 아니면 빈 목록, 원소가 범위 안의 `[int,int]` 가 아니면 그 칸만 null.
 */
@Serializable(with = RummyLayout.Serializer::class)
data class RummyLayout(val points: List<RummyPoint?>) {
    object Serializer : KSerializer<RummyLayout> {
        private val list = ListSerializer(RummyPoint.serializer().nullable)
        override val descriptor: SerialDescriptor = list.descriptor

        override fun deserialize(decoder: Decoder): RummyLayout {
            val items = swiftTry { SwiftDecoding.unkeyed(decoder) } ?: return RummyLayout(emptyList())
            return RummyLayout(items.map { item -> if (item.element is JsonNull) null else swiftTry { RummyPoint.Serializer.deserialize(item) } })
        }

        override fun serialize(encoder: Encoder, value: RummyLayout) = list.serialize(encoder, value.points)
    }
}

// ---------- 요청 본문(키 = 서버 인자 이름) ----------

/** rummy_lobby / rummy_ranking 본문. */
@Serializable
data class RummyProtocolRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
)

/** rummy_create 본문. */
@Serializable
data class RummyCreateRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
    @SerialName("p_stake") val pStake: Long,
    @SerialName("p_public") val pPublic: Boolean,
)

/** rummy_invite 본문. */
@Serializable
data class RummyInviteRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: SwiftUUID,
    @SerialName("p_user") val pUser: SwiftUUID,
)

/** rummy_join / decline / leave / start / state / heartbeat 본문. */
@Serializable
data class RummyMatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: SwiftUUID,
)

/** rummy_draw 본문. */
@Serializable
data class RummySeqRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: SwiftUUID,
    @SerialName("p_expected_seq") val pExpectedSeq: Long,
)

/** rummy_draft / rummy_play 본문. `p_layout` 이 null 이면 **키를 싣지 않는다**(서버 `default null` — v1 본문과 같은 키 집합). */
@Serializable
data class RummyTableRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: SwiftUUID,
    @SerialName("p_expected_seq") val pExpectedSeq: Long,
    @SerialName("p_table") val pTable: List<List<RummyFace>>,
    @SerialName("p_layout") val pLayout: RummyLayout? = null,
)

/** rummy_react 본문. `p_key` = 이모티콘 키. */
@Serializable
data class RummyReactRequest(
    @SerialName("p_protocol") val pProtocol: Long = RummyWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: SwiftUUID,
    @SerialName("p_key") val pKey: String,
)

// ---------- 로비 ----------

/** Swift `RummyPeer`. */
@Serializable
data class RummyPeer(
    @SerialName("id") val id: SwiftUUID,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
)

/** Swift `RummyRoomSeat`. 초대받은 자리는 `seat_no` 가 null 이다. */
@Serializable
data class RummyRoomSeat(
    @SerialName("user_id") val userId: SwiftUUID,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("state") val state: RummySeatState? = null,
    @SerialName("seat_no") val seatNo: Long? = null,
)

/** Swift `RummyRoom` — 받은 초대 · 공개 방 · 내 방이 같은 모양이다. */
@Serializable
data class RummyRoom(
    @SerialName("id") val id: SwiftUUID,
    @SerialName("host") val host: RummyPeer? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("is_public") val isPublic: Boolean? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
    @SerialName("max_seats") val maxSeats: Long? = null,
    @SerialName("seats") val seats: List<RummyRoomSeat>? = null,
)

/** Swift `RummyLobbyUser`. `capable` 이 null 이면 **불가**로 읽는다. */
@Serializable
data class RummyLobbyUser(
    @SerialName("id") val id: SwiftUUID,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("is_working") val isWorking: Boolean? = null,
    @SerialName("in_match") val inMatch: Boolean? = null,
    @SerialName("capable") val capable: Boolean? = null,
    @SerialName("focus_mode") val focusMode: Boolean? = null,
)

/** Swift `RummyLobbyMe`. */
@Serializable
data class RummyLobbyMe(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("games") val games: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("room") val room: RummyRoom? = null,
    @SerialName("active_match_id") val activeMatchId: SwiftUUID? = null,
)

/** rummy_lobby 응답. */
@Serializable
data class RummyLobby(
    @SerialName("status") val status: RummyRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("turn_seconds") val turnSeconds: Long? = null,
    @SerialName("room_ttl_seconds") val roomTtlSeconds: Long? = null,
    @SerialName("me") val me: RummyLobbyMe? = null,
    @SerialName("invites") val invites: List<RummyRoom>? = null,
    @SerialName("public_rooms") val publicRooms: List<RummyRoom>? = null,
    @SerialName("users") val users: List<RummyLobbyUser>? = null,
)

// ---------- 판 상태 ----------

/** Swift `RummyMatchSeat`. `final_*` 은 finished 에서만 찬다. */
@Serializable
data class RummyMatchSeat(
    @SerialName("seat_no") val seatNo: Long? = null,
    @SerialName("user_id") val userId: SwiftUUID,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("state") val state: RummySeatState? = null,
    @SerialName("rack_count") val rackCount: Long? = null,
    @SerialName("initial_done") val initialDone: Boolean? = null,
    @SerialName("timeout_streak") val timeoutStreak: Long? = null,
    @SerialName("forfeit_order") val forfeitOrder: Long? = null,
    @SerialName("final_rank") val finalRank: Long? = null,
    @SerialName("final_score") val finalScore: Long? = null,
    @SerialName("payout") val payout: Long? = null,
    @SerialName("is_winner") val isWinner: Boolean? = null,
    @SerialName("final_rack") val finalRack: List<RummyFace>? = null,
)

/** Swift `RummyDraft` — 이번 차례 작업 판(공개). */
@Serializable
data class RummyDraft(
    @SerialName("table") val table: List<List<RummyFace>>? = null,
    @SerialName("layout") val layout: RummyLayout? = null,
    @SerialName("draft_seq") val draftSeq: Long? = null,
    @SerialName("at_ms") val atMs: Double? = null,
)

/** Swift `RummyReaction` — 최근 10초 이모티콘 반응. */
@Serializable
data class RummyReaction(
    @SerialName("seat_no") val seatNo: Long? = null,
    @SerialName("key") val key: String? = null,
    @SerialName("at_ms") val atMs: Double? = null,
)

/** Swift `RummyLastEvent` — 마지막 확정 사건. `kind` 는 서버 글자 그대로. */
@Serializable
data class RummyLastEvent(
    @SerialName("kind") val kind: String? = null,
    @SerialName("seat_no") val seatNo: Long? = null,
    @SerialName("count") val count: Long? = null,
    @SerialName("at_ms") val atMs: Double? = null,
)

/** Swift `RummyMatchState`. forming 방도 같은 모양. **남의 랙·pool 내용은 실리지 않는다.** */
@Serializable
data class RummyMatchState(
    @SerialName("id") val id: SwiftUUID,
    @SerialName("status") val status: RummyMatchStatus? = null,
    @SerialName("host_id") val hostId: SwiftUUID? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("is_public") val isPublic: Boolean? = null,
    @SerialName("seat_count") val seatCount: Long? = null,
    @SerialName("max_seats") val maxSeats: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("seq") val seq: Long? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
    @SerialName("seats") val seats: List<RummyMatchSeat>? = null,
    @SerialName("my_seat_no") val mySeatNo: Long? = null,
    @SerialName("my_rack") val myRack: List<RummyFace>? = null,
    @SerialName("my_initial_done") val myInitialDone: Boolean? = null,
    @SerialName("table") val table: List<List<RummyFace>>? = null,
    @SerialName("table_layout") val tableLayout: RummyLayout? = null,
    @SerialName("pool_count") val poolCount: Long? = null,
    @SerialName("turn_seat_no") val turnSeatNo: Long? = null,
    @SerialName("turn_started_ms") val turnStartedMs: Double? = null,
    @SerialName("turn_deadline_ms") val turnDeadlineMs: Double? = null,
    @SerialName("grace_ms") val graceMs: Double? = null,
    @SerialName("draft") val draft: RummyDraft? = null,
    @SerialName("consecutive_passes") val consecutivePasses: Long? = null,
    @SerialName("last_event") val lastEvent: RummyLastEvent? = null,
    @SerialName("end_reason") val endReason: RummyEndReason? = null,
    @SerialName("finished_at_ms") val finishedAtMs: Double? = null,
    @SerialName("reactions") val reactions: List<RummyReaction>? = null,
)

/** 쓰기·조회 공용 응답. 상태는 **`state` 키**에 실려 온다. 거절 응답에도 가능하면 실린다. */
@Serializable
data class RummyActionResponse(
    @SerialName("status") val status: RummyRPCStatus,
    @SerialName("state") val state: RummyMatchState? = null,
    @SerialName("match_id") val matchId: SwiftUUID? = null,
    @SerialName("draft_seq") val draftSeq: Long? = null,
    @SerialName("reason") val reason: RummyTurnReason? = null,
    @SerialName("dropped") val dropped: List<SwiftUUID>? = null,
    @SerialName("side") val side: String? = null,
    @SerialName("need") val need: Long? = null,
    @SerialName("have") val have: Long? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

// ---------- 순위 ----------

/** Swift `RummyRankRow`. 순위·배열 순서 모두 서버 것이다. */
@Serializable
data class RummyRankRow(
    @SerialName("id") val id: SwiftUUID,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("games") val games: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("rank") val rank: Long? = null,
)

/** Swift `RummyRankingMe`. 0판이면 rank null. */
@Serializable
data class RummyRankingMe(
    @SerialName("games") val games: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("rank") val rank: Long? = null,
)

/** rummy_ranking 응답. */
@Serializable
data class RummyRanking(
    @SerialName("status") val status: RummyRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("rows") val rows: List<RummyRankRow>? = null,
    @SerialName("me") val me: RummyRankingMe? = null,
)
