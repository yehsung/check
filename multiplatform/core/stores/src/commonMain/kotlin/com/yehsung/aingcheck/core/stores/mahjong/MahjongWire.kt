// 원본: Sources/CheckCore/MahjongWire.swift @ e4995a3a(아잉 마작 4인 RPC 와이어 — 요청 · 응답 · 서비스 13) — Android 판 8
//
// 규칙 타입(MahjongTile · MahjongDecision · MahjongFormat …)을 쓰므로 core:wire 가 아니라 이 모듈에 둔다(core:wire 는 rules 를 모른다).
// 규약(리버시 · 큐브 와이어와 같다): ① status 만 필수, 나머지는 전부 nullable ② 모르는 status 는 unknown ③ 시각은 epoch ms Double
// ④ 요청은 늘 p_protocol 을 싣는다 ⑤ 상태는 `{status, state}` 봉투. 열린 어휘 칸은 원문 String — 엔진 값은 계산 속성.
// 디코딩은 Swift 합성 Codable 그대로: 필수 칸이 없으면 던지고, Optional 칸은 키가 없거나 null 이면 null(있는데 틀리면 던진다).
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeld
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeldType
import com.yehsung.aingcheck.core.rules.mahjong.MahjongPao
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.rules.mahjong.MahjongYaku
import com.yehsung.aingcheck.core.rules.mahjong.MahjongYakuHan
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftKeyed
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encoding.Decoder

/** 아잉 마작 RPC 프로토콜과 이름 묶음. */
object MahjongWire {
    /** 서버 `mahjong_protocol()` 이 1 이고, 이보다 작으면 `unsupported_client` 다. */
    const val protocolVersion = 1

    /** 클라가 부르는 RPC 이름 전부(13). */
    enum class RPC(val rawValue: String) {
        lobby("mahjong_lobby"), create("mahjong_create"), invite("mahjong_invite"), join("mahjong_join"), decline("mahjong_decline"),
        leave("mahjong_leave"), start("mahjong_start"), state("mahjong_state"), act("mahjong_act"), call("mahjong_call"),
        back("mahjong_back"), react("mahjong_react"), ranking("mahjong_ranking");

        /** 교착(40P01) 한 번 재시도 여부. 쓰기 전부 + state. 로비 · 반응 · 순위는 끈다. */
        val retriesDeadlockOnce: Boolean
            get() = when (this) {
                create, invite, join, decline, leave, start, state, act, call, back -> true
                lobby, react, ranking -> false
            }

        companion object {
            val all: List<String> get() = entries.map { it.rawValue }
        }
    }
}

/** 패 한 장 = id(0~135) 정수 하나. 범위 밖은 디코드 실패. */
object MahjongTileWire : SwiftDecodableSerializer<MahjongTile>("MahjongTile") {
    override fun deserialize(decoder: Decoder): MahjongTile {
        val raw = Int.serializer().deserialize(decoder)
        return MahjongTile.of(raw) ?: throw IllegalArgumentException("패 id 범위 밖(0~135): $raw")
    }
}

private val tileList = ListSerializer(MahjongTileWire)
private val tileListList = ListSerializer(tileList)
private val intList = ListSerializer(Int.serializer())
private val stringList = ListSerializer(String.serializer())

/** RPC status 어휘. 모르는 값은 unknown. */
enum class MahjongRPCStatus(val rawValue: String) {
    ok("ok"), unauthorized("unauthorized"), unsupportedClient("unsupported_client"), invalid("invalid"), blackout("blackout"),
    targetFocused("target_focused"), targetOutdated("target_outdated"), outdated("outdated"), busy("busy"), targetBusy("target_busy"),
    alreadyInRoom("already_in_room"), alreadyInvited("already_invited"), roomFull("room_full"), tooManyInvites("too_many_invites"),
    roomClosed("room_closed"), notInvited("not_invited"), notHost("not_host"), notEnoughPlayers("not_enough_players"),
    seatsDropped("seats_dropped"), insufficient("insufficient"), notFound("not_found"), notActive("not_active"),
    notYourTurn("not_your_turn"), stale("stale"), illegal("illegal"), windowClosed("window_closed"), tooFast("too_fast"),
    tooEarly("too_early"), unknown("unknown");

    companion object {
        fun of(raw: String): MahjongRPCStatus = entries.firstOrNull { it.rawValue == raw } ?: unknown
    }

    object Serializer : SwiftDecodableSerializer<MahjongRPCStatus>("MahjongRPCStatus") {
        override fun deserialize(decoder: Decoder): MahjongRPCStatus = of(String.serializer().deserialize(decoder))
    }
}

// MARK: - 요청 본문

@Serializable
data class MahjongProtocolRequest(@SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion)

@Serializable
data class MahjongCreateRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_stake") val pStake: Int,
    @SerialName("p_public") val pPublic: Boolean,
    @SerialName("p_format") val pFormat: String,
)

@Serializable
data class MahjongMatchRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
)

@Serializable
data class MahjongInviteRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_user_id") val pUserId: String,
)

@Serializable
data class MahjongStateRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_since_seq") val pSinceSeq: Int,
)

/** `p_tiles` 는 패 id 배열(쯔모 · 구종구패는 []) — 서버는 null 인자를 invalid 로 받으므로 늘 배열을 싣는다. */
@Serializable
data class MahjongActRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_expected_seq") val pExpectedSeq: Int,
    @SerialName("p_action") val pAction: String,
    @SerialName("p_tiles") val pTiles: List<Int> = emptyList(),
)

@Serializable
data class MahjongCallRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_window_id") val pWindowId: Int,
    @SerialName("p_action") val pAction: String,
    @SerialName("p_tiles") val pTiles: List<Int> = emptyList(),
)

@Serializable
data class MahjongReactRequest(
    @SerialName("p_protocol") val pProtocol: Int = MahjongWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_key") val pKey: String,
)

// MARK: - 응답 — 로비

/** 이름 정도만 실린 사람(PEER). id 키는 `id`. */
data class MahjongPeer(val id: String? = null, val displayName: String? = null, val avatarUrl: String? = null, val character: String? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongPeer>("MahjongPeer") {
        override fun deserialize(decoder: Decoder): MahjongPeer {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongPeer(c.stringIfPresent("id"), c.stringIfPresent("display_name"), c.stringIfPresent("avatar_url"), c.stringIfPresent("character"))
        }
    }
}

/** 방 자리 한 줄 `{user, state: "invited"|"joined"}`. */
data class MahjongRoomSeat(val user: MahjongPeer? = null, val state: String? = null) {
    val isJoined: Boolean get() = state == "joined"

    object Serializer : SwiftDecodableSerializer<MahjongRoomSeat>("MahjongRoomSeat") {
        override fun deserialize(decoder: Decoder): MahjongRoomSeat {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongRoomSeat(c.decodeIfPresent("user", MahjongPeer.Serializer), c.stringIfPresent("state"))
        }
    }
}

/** ROOM — 받은 초대 · 공개 방 · 내 방. id 는 서버 uuid. */
data class MahjongRoom(
    val id: SwiftUUID,
    val host: MahjongPeer? = null,
    val stake: Int? = null,
    val format: String? = null,
    val isPublic: Boolean? = null,
    val expiresAtMs: Double? = null,
    val maxSeats: Int? = null,
    val seats: List<MahjongRoomSeat>? = null,
) {
    val formatKind: MahjongFormat? get() = format?.let(MahjongFormat::of)
    /** 앉은(joined) 사람 수. */
    val joinedCount: Int get() = seats?.count { it.isJoined } ?: 0

    object Serializer : SwiftDecodableSerializer<MahjongRoom>("MahjongRoom") {
        override fun deserialize(decoder: Decoder): MahjongRoom {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongRoom(
                c.decode("id", SwiftUUID.Serializer), c.decodeIfPresent("host", MahjongPeer.Serializer), c.intIfPresent("stake"),
                c.stringIfPresent("format"), c.boolIfPresent("is_public"), c.doubleIfPresent("expires_at_ms"), c.intIfPresent("max_seats"),
                c.decodeIfPresent("seats", ListSerializer(MahjongRoomSeat.Serializer)),
            )
        }
    }
}

/** 로비 `users[]` 한 줄. `capable` 이 null 이면 불가로 읽는다. */
data class MahjongLobbyUser(
    val id: SwiftUUID,
    val displayName: String? = null,
    val avatarUrl: String? = null,
    val character: String? = null,
    val isWorking: Boolean? = null,
    val inMatch: Boolean? = null,
    val capable: Boolean? = null,
    val focusMode: Boolean? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongLobbyUser>("MahjongLobbyUser") {
        override fun deserialize(decoder: Decoder): MahjongLobbyUser {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongLobbyUser(
                c.decode("id", SwiftUUID.Serializer), c.stringIfPresent("display_name"), c.stringIfPresent("avatar_url"), c.stringIfPresent("character"),
                c.boolIfPresent("is_working"), c.boolIfPresent("in_match"), c.boolIfPresent("capable"), c.boolIfPresent("focus_mode"),
            )
        }
    }
}

/** 내 전적. `avg_rank` 는 0판이면 null. */
data class MahjongRecord(
    val games: Int? = null, val firsts: Int? = null, val seconds: Int? = null, val thirds: Int? = null, val fourths: Int? = null, val avgRank: Double? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongRecord>("MahjongRecord") {
        override fun deserialize(decoder: Decoder): MahjongRecord {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongRecord(c.intIfPresent("games"), c.intIfPresent("firsts"), c.intIfPresent("seconds"), c.intIfPresent("thirds"), c.intIfPresent("fourths"), c.doubleIfPresent("avg_rank"))
        }
    }
}

/** 로비 `me`. */
data class MahjongLobbyMe(val rubyBalance: Int? = null, val record: MahjongRecord? = null, val room: MahjongRoom? = null, val activeMatchId: String? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongLobbyMe>("MahjongLobbyMe") {
        override fun deserialize(decoder: Decoder): MahjongLobbyMe {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongLobbyMe(
                c.intIfPresent("ruby_balance"), c.decodeIfPresent("record", MahjongRecord.Serializer), c.decodeIfPresent("room", MahjongRoom.Serializer),
                c.stringIfPresent("active_match_id"),
            )
        }
    }
}

/** mahjong_lobby 응답. 숫자 상수(판돈 · 형식 · 방 TTL · 초대 상한 · 생각 시간)도 서버가 말한다. */
data class MahjongLobbyResponse(
    val status: MahjongRPCStatus,
    val serverNowMs: Double? = null,
    val stakes: List<Int>? = null,
    val formats: List<String>? = null,
    val roomTtlSeconds: Int? = null,
    val maxInvites: Int? = null,
    val baseMs: Int? = null,
    val bankMs: Int? = null,
    val me: MahjongLobbyMe? = null,
    val invites: List<MahjongRoom>? = null,
    val publicRooms: List<MahjongRoom>? = null,
    val users: List<MahjongLobbyUser>? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongLobbyResponse>("MahjongLobbyResponse") {
        override fun deserialize(decoder: Decoder): MahjongLobbyResponse {
            val c = SwiftDecoding.keyed(decoder)
            val rooms = ListSerializer(MahjongRoom.Serializer)
            return MahjongLobbyResponse(
                c.decode("status", MahjongRPCStatus.Serializer), c.doubleIfPresent("server_now_ms"), c.decodeIfPresent("stakes", intList),
                c.decodeIfPresent("formats", stringList), c.intIfPresent("room_ttl_seconds"), c.intIfPresent("max_invites"), c.intIfPresent("base_ms"),
                c.intIfPresent("bank_ms"), c.decodeIfPresent("me", MahjongLobbyMe.Serializer), c.decodeIfPresent("invites", rooms),
                c.decodeIfPresent("public_rooms", rooms), c.decodeIfPresent("users", ListSerializer(MahjongLobbyUser.Serializer)),
            )
        }
    }
}

// MARK: - 응답 — state

/** 판(방) status. 모르는 값은 unknown. */
enum class MahjongMatchStatus(val rawValue: String) {
    forming("forming"), active("active"), finished("finished"), cancelled("cancelled"), expired("expired"), unknown("unknown");

    /** 다시 안 바뀌는 끝 상태. */
    val isTerminal: Boolean get() = this == finished || this == cancelled || this == expired

    companion object {
        fun wire(raw: String?): MahjongMatchStatus = raw?.let { r -> entries.firstOrNull { it.rawValue == r } } ?: unknown
    }
}

/** state 의 자리 사람(USER). */
data class MahjongStateUser(val userId: String? = null, val displayName: String? = null, val avatarUrl: String? = null, val character: String? = null, val center: String? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongStateUser>("MahjongStateUser") {
        override fun deserialize(decoder: Decoder): MahjongStateUser {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongStateUser(c.stringIfPresent("user_id"), c.stringIfPresent("display_name"), c.stringIfPresent("avatar_url"), c.stringIfPresent("character"), c.stringIfPresent("center"))
        }
    }
}

/** forming 방의 멤버 한 줄. */
data class MahjongStateMember(val user: MahjongPeer? = null, val state: String? = null, val isHost: Boolean? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongStateMember>("MahjongStateMember") {
        override fun deserialize(decoder: Decoder): MahjongStateMember {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongStateMember(c.decodeIfPresent("user", MahjongPeer.Serializer), c.stringIfPresent("state"), c.boolIfPresent("is_host"))
        }
    }
}

/** 강의 한 장(DISC). */
data class MahjongDiscard(val tile: MahjongTile, val tsumogiri: Boolean? = null, val riichi: Boolean? = null, val taken: Boolean? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongDiscard>("MahjongDiscard") {
        override fun deserialize(decoder: Decoder): MahjongDiscard {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongDiscard(c.decode("tile", MahjongTileWire), c.boolIfPresent("tsumogiri"), c.boolIfPresent("riichi"), c.boolIfPresent("taken"))
        }
    }
}

/** 부로 원문(MELD). 엔진 값은 [meld](모르는 type 이면 null). */
data class MahjongWireMeld(val type: String, val tiles: List<MahjongTile>, val called: MahjongTile? = null, val fromSeat: Int? = null) {
    constructor(meld: MahjongMeld) : this(meld.type.rawValue, meld.tiles, meld.called, meld.fromSeat)

    val meld: MahjongMeld? get() = MahjongMeldType.of(type)?.let { MahjongMeld(it, tiles, called, fromSeat) }

    object Serializer : SwiftDecodableSerializer<MahjongWireMeld>("MahjongWireMeld") {
        override fun deserialize(decoder: Decoder): MahjongWireMeld {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongWireMeld(c.string("type"), c.decode("tiles", tileList), c.decodeIfPresent("called", MahjongTileWire), c.intIfPresent("from_seat"))
        }
    }
}

/** 자리 한 줄(SEAT). 남의 손은 `hand_count` 만. */
data class MahjongStateSeat(
    val seatNo: Int,
    val user: MahjongStateUser? = null,
    val wind: String? = null,
    val isDealer: Boolean? = null,
    val score: Int? = null,
    val handCount: Int? = null,
    val melds: List<MahjongWireMeld>? = null,
    val discards: List<MahjongDiscard>? = null,
    val riichi: Boolean? = null,
    val away: Boolean? = null,
    val deleted: Boolean? = null,
    val finalRank: Int? = null,
    val finalScore: Int? = null,
    val payout: Int? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongStateSeat>("MahjongStateSeat") {
        override fun deserialize(decoder: Decoder): MahjongStateSeat {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongStateSeat(
                c.int("seat_no"), c.decodeIfPresent("user", MahjongStateUser.Serializer), c.stringIfPresent("wind"), c.boolIfPresent("is_dealer"),
                c.intIfPresent("score"), c.intIfPresent("hand_count"), c.decodeIfPresent("melds", ListSerializer(MahjongWireMeld.Serializer)),
                c.decodeIfPresent("discards", ListSerializer(MahjongDiscard.Serializer)), c.boolIfPresent("riichi"), c.boolIfPresent("away"),
                c.boolIfPresent("deleted"), c.intIfPresent("final_rank"), c.intIfPresent("final_score"), c.intIfPresent("payout"),
            )
        }
    }
}

/** 판 행(`state.match`). 공개 칸만. */
data class MahjongStateMatch(
    /** 서버 uuid · 연습판은 "ai-…". */
    val id: String,
    val status: String? = null,
    val stake: Int? = null,
    val format: String? = null,
    val isPublic: Boolean? = null,
    val host: MahjongPeer? = null,
    val seq: Int? = null,
    val createdMs: Double? = null,
    val roomExpiresMs: Double? = null,
    val startedMs: Double? = null,
    val finishedMs: Double? = null,
    val endReason: String? = null,
    /** 원문 "room"|"turn"|"wait"|"hand_end"|"finished". */
    val phase: String? = null,
    val handIndex: Int? = null,
    val round: Int? = null,
    val handNo: Int? = null,
    val honba: Int? = null,
    val kyotaku: Int? = null,
    val dealerSeat: Int? = null,
    val extension: Boolean? = null,
    val wallRemaining: Int? = null,
    val doraIndicators: List<MahjongTile>? = null,
    val kanCount: Int? = null,
    val turnSeat: Int? = null,
    val wakeAtMs: Double? = null,
    val wakeSeat: Int? = null,
    val backupAtMs: Double? = null,
    val nextHandMs: Double? = null,
    val baseMs: Int? = null,
    val bankFullMs: Int? = null,
    val graceMs: Int? = null,
) {
    val matchStatus: MahjongMatchStatus get() = MahjongMatchStatus.wire(status)
    val formatKind: MahjongFormat? get() = format?.let(MahjongFormat::of)
    /** 무효 판(루비 환불 — 순위 · 미션 · 판 끝 콜백에서 뺀다). */
    val isVoid: Boolean get() = endReason == "void"
    /** 연습판(기기 안 엔진) id 인가. */
    val isPractice: Boolean get() = id.startsWith(MahjongStatePayload.practiceIDPrefix)

    object Serializer : SwiftDecodableSerializer<MahjongStateMatch>("MahjongStateMatch") {
        override fun deserialize(decoder: Decoder): MahjongStateMatch {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongStateMatch(
                id = c.string("id"), status = c.stringIfPresent("status"), stake = c.intIfPresent("stake"), format = c.stringIfPresent("format"),
                isPublic = c.boolIfPresent("is_public"), host = c.decodeIfPresent("host", MahjongPeer.Serializer), seq = c.intIfPresent("seq"),
                createdMs = c.doubleIfPresent("created_ms"), roomExpiresMs = c.doubleIfPresent("room_expires_ms"), startedMs = c.doubleIfPresent("started_ms"),
                finishedMs = c.doubleIfPresent("finished_ms"), endReason = c.stringIfPresent("end_reason"), phase = c.stringIfPresent("phase"),
                handIndex = c.intIfPresent("hand_index"), round = c.intIfPresent("round"), handNo = c.intIfPresent("hand_no"), honba = c.intIfPresent("honba"),
                kyotaku = c.intIfPresent("kyotaku"), dealerSeat = c.intIfPresent("dealer_seat"), extension = c.boolIfPresent("extension"),
                wallRemaining = c.intIfPresent("wall_remaining"), doraIndicators = c.decodeIfPresent("dora_indicators", tileList),
                kanCount = c.intIfPresent("kan_count"), turnSeat = c.intIfPresent("turn_seat"), wakeAtMs = c.doubleIfPresent("wake_at_ms"),
                wakeSeat = c.intIfPresent("wake_seat"), backupAtMs = c.doubleIfPresent("backup_at_ms"), nextHandMs = c.doubleIfPresent("next_hand_ms"),
                baseMs = c.intIfPresent("base_ms"), bankFullMs = c.intIfPresent("bank_full_ms"), graceMs = c.intIfPresent("grace_ms"),
            )
        }
    }
}

/** 내 자리 비움(`my_away` — 나만). */
data class MahjongAwayState(val reason: String? = null, val sinceMs: Double? = null, val backReadyMs: Double? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongAwayState>("MahjongAwayState") {
        override fun deserialize(decoder: Decoder): MahjongAwayState {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongAwayState(c.stringIfPresent("reason"), c.doubleIfPresent("since_ms"), c.doubleIfPresent("back_ready_ms"))
        }
    }
}

/** 사건의 주인 전용 칸(`priv`). */
data class MahjongEventPriv(val auto: Boolean? = null, val tile: MahjongTile? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongEventPriv>("MahjongEventPriv") {
        override fun deserialize(decoder: Decoder): MahjongEventPriv {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongEventPriv(c.boolIfPresent("auto"), c.decodeIfPresent("tile", MahjongTileWire))
        }
    }
}

/** 공개 사건 한 줄(EVENT). kind 밖 칸은 모두 nullable. */
data class MahjongEvent(
    val seq: Int,
    /** 원문 deal · draw · discard · call · kan · dora · riichi · win · hand_draw · scores · away · end. */
    val kind: String,
    val seat: Int? = null,
    val atMs: Double? = null,
    val handIndex: Int? = null,
    val round: Int? = null,
    val handNo: Int? = null,
    val honba: Int? = null,
    val kyotaku: Int? = null,
    val dealerSeat: Int? = null,
    val dora: List<MahjongTile>? = null,
    val rinshan: Boolean? = null,
    val tile: MahjongTile? = null,
    val tsumogiri: Boolean? = null,
    val riichi: Boolean? = null,
    val priv: MahjongEventPriv? = null,
    val type: String? = null,
    val tiles: List<MahjongTile>? = null,
    val called: MahjongTile? = null,
    val fromSeat: Int? = null,
    val indicator: MahjongTile? = null,
    val seats: List<Int>? = null,
    val reason: String? = null,
    val deltas: List<Int>? = null,
    val scoresAfter: List<Int>? = null,
    val on: Boolean? = null,
    val endReason: String? = null,
) {
    /** 주인에게 온 '시간이 지나 자동으로 버렸다' 표지. */
    val isAutoDiscard: Boolean get() = kind == "discard" && priv?.auto == true

    object Serializer : SwiftDecodableSerializer<MahjongEvent>("MahjongEvent") {
        override fun deserialize(decoder: Decoder): MahjongEvent {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongEvent(
                seq = c.int("seq"), kind = c.string("kind"), seat = c.intIfPresent("seat"), atMs = c.doubleIfPresent("at_ms"),
                handIndex = c.intIfPresent("hand_index"), round = c.intIfPresent("round"), handNo = c.intIfPresent("hand_no"), honba = c.intIfPresent("honba"),
                kyotaku = c.intIfPresent("kyotaku"), dealerSeat = c.intIfPresent("dealer_seat"), dora = c.decodeIfPresent("dora", tileList),
                rinshan = c.boolIfPresent("rinshan"), tile = c.decodeIfPresent("tile", MahjongTileWire), tsumogiri = c.boolIfPresent("tsumogiri"),
                riichi = c.boolIfPresent("riichi"), priv = c.decodeIfPresent("priv", MahjongEventPriv.Serializer), type = c.stringIfPresent("type"),
                tiles = c.decodeIfPresent("tiles", tileList), called = c.decodeIfPresent("called", MahjongTileWire), fromSeat = c.intIfPresent("from_seat"),
                indicator = c.decodeIfPresent("indicator", MahjongTileWire), seats = c.decodeIfPresent("seats", intList), reason = c.stringIfPresent("reason"),
                deltas = c.decodeIfPresent("deltas", intList), scoresAfter = c.decodeIfPresent("scores_after", intList), on = c.boolIfPresent("on"),
                endReason = c.stringIfPresent("end_reason"),
            )
        }
    }
}

/** 결과의 역 한 칸 `[id, 판]` 원문. 엔진 값은 [yakuKind](모르는 역이면 null). */
data class MahjongWireYaku(val id: String, val han: Int) {
    constructor(yakuHan: MahjongYakuHan) : this(yakuHan.yaku.rawValue, yakuHan.han)

    val yakuKind: MahjongYaku? get() = MahjongYaku.of(id)

    object Serializer : SwiftDecodableSerializer<MahjongWireYaku>("MahjongWireYaku") {
        override fun deserialize(decoder: Decoder): MahjongWireYaku {
            val items = SwiftDecoding.unkeyed(decoder)
            if (items.size < 2) throw IllegalArgumentException("역 칸은 [id, 판]")
            return MahjongWireYaku(String.serializer().deserialize(items[0]), Int.serializer().deserialize(items[1]))
        }
    }
}

/** 화료 한 건(`last_hand.wins[]`). */
data class MahjongWinResult(
    val seat: Int,
    val fromSeat: Int? = null,
    val hand: List<MahjongTile>? = null,
    val melds: List<MahjongWireMeld>? = null,
    val winTile: MahjongTile? = null,
    val yaku: List<MahjongWireYaku>? = null,
    val yakuman: Int? = null,
    val han: Int? = null,
    val fu: Int? = null,
    val limit: String? = null,
    val dora: Int? = null,
    val aka: Int? = null,
    val ura: Int? = null,
    val uraIndicators: List<MahjongTile>? = null,
    val total: Int? = null,
    val pao: Pao? = null,
) {
    /** 책임 지불(파오) — `{seat, yaku}` 원문. */
    data class Pao(val seat: Int? = null, val yaku: String? = null) {
        val pao: MahjongPao?
            get() {
                val s = seat ?: return null
                val kind = yaku?.let(MahjongYaku::of) ?: return null
                return MahjongPao(s, kind)
            }

        object Serializer : SwiftDecodableSerializer<Pao>("MahjongWinResult.Pao") {
            override fun deserialize(decoder: Decoder): Pao {
                val c = SwiftDecoding.keyed(decoder)
                return Pao(c.intIfPresent("seat"), c.stringIfPresent("yaku"))
            }
        }
    }

    object Serializer : SwiftDecodableSerializer<MahjongWinResult>("MahjongWinResult") {
        override fun deserialize(decoder: Decoder): MahjongWinResult {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongWinResult(
                seat = c.int("seat"), fromSeat = c.intIfPresent("from_seat"), hand = c.decodeIfPresent("hand", tileList),
                melds = c.decodeIfPresent("melds", ListSerializer(MahjongWireMeld.Serializer)), winTile = c.decodeIfPresent("win_tile", MahjongTileWire),
                yaku = c.decodeIfPresent("yaku", ListSerializer(MahjongWireYaku.Serializer)), yakuman = c.intIfPresent("yakuman"), han = c.intIfPresent("han"),
                fu = c.intIfPresent("fu"), limit = c.stringIfPresent("limit"), dora = c.intIfPresent("dora"), aka = c.intIfPresent("aka"), ura = c.intIfPresent("ura"),
                uraIndicators = c.decodeIfPresent("ura_indicators", tileList), total = c.intIfPresent("total"), pao = c.decodeIfPresent("pao", Pao.Serializer),
            )
        }
    }
}

/** 유국 텐파이 한 줄. */
data class MahjongTenpaiResult(val seat: Int, val hand: List<MahjongTile>? = null, val melds: List<MahjongWireMeld>? = null) {
    object Serializer : SwiftDecodableSerializer<MahjongTenpaiResult>("MahjongTenpaiResult") {
        override fun deserialize(decoder: Decoder): MahjongTenpaiResult {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongTenpaiResult(c.int("seat"), c.decodeIfPresent("hand", tileList), c.decodeIfPresent("melds", ListSerializer(MahjongWireMeld.Serializer)))
        }
    }
}

/** 가장 최근 끝난 국(HAND_RESULT). */
data class MahjongHandResult(
    val handIndex: Int,
    /** 원문 "win"|"exhaustive"|"abortive". */
    val kind: String,
    val reason: String? = null,
    val wins: List<MahjongWinResult>? = null,
    val tenpai: List<MahjongTenpaiResult>? = null,
    val nagashi: List<Int>? = null,
    val deltas: List<Int>? = null,
    val scoresAfter: List<Int>? = null,
    val bonusTo: Int? = null,
    val renchan: Boolean? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongHandResult>("MahjongHandResult") {
        override fun deserialize(decoder: Decoder): MahjongHandResult {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongHandResult(
                c.int("hand_index"), c.string("kind"), c.stringIfPresent("reason"), c.decodeIfPresent("wins", ListSerializer(MahjongWinResult.Serializer)),
                c.decodeIfPresent("tenpai", ListSerializer(MahjongTenpaiResult.Serializer)), c.decodeIfPresent("nagashi", intList),
                c.decodeIfPresent("deltas", intList), c.decodeIfPresent("scores_after", intList), c.intIfPresent("bonus_to"), c.boolIfPresent("renchan"),
            )
        }
    }
}

/** 반응 한 줄. */
data class MahjongReaction(val seatNo: Int? = null, val userId: String? = null, val key: String? = null, val atMs: Double? = null) {
    val sticker: AingSticker? get() = key?.let { k -> AingSticker.entries.firstOrNull { it.rawValue == k } }

    object Serializer : SwiftDecodableSerializer<MahjongReaction>("MahjongReaction") {
        override fun deserialize(decoder: Decoder): MahjongReaction {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongReaction(c.intIfPresent("seat_no"), c.stringIfPresent("user_id"), c.stringIfPresent("key"), c.doubleIfPresent("at_ms"))
        }
    }
}

/** `my_decision` 디코드 — `kind` 칸("turn"|"call") + 그 갈래의 칸들. 모르는 kind 는 던진다(감싸기는 state 몫). */
object MahjongDecisionWire : SwiftDecodableSerializer<MahjongDecision>("MahjongDecision") {
    override fun deserialize(decoder: Decoder): MahjongDecision {
        val c = SwiftDecoding.keyed(decoder)
        return when (val kind = c.string("kind")) {
            "turn" -> MahjongDecision.Turn(
                seq = c.int("seq"), decisionSeq = c.int("decision_seq"), startedMs = c.double("started_ms"), deadlineMs = c.double("deadline_ms"),
                notBeforeMs = c.doubleIfPresent("not_before_ms"), bankMs = c.int("bank_ms"), discard = c.decode("discard", tileList),
                riichi = c.decode("riichi", tileList), tsumo = c.bool("tsumo"), ankan = c.decode("ankan", tileListList),
                kakan = c.decode("kakan", tileList), kyuushu = c.bool("kyuushu"),
            )
            "call" -> MahjongDecision.Call(
                windowId = c.int("window_id"), windowKind = c.string("window_kind"), tile = c.decode("tile", MahjongTileWire), fromSeat = c.int("from_seat"),
                startedMs = c.double("started_ms"), deadlineMs = c.double("deadline_ms"), bankMs = c.int("bank_ms"), ron = c.bool("ron"),
                pon = c.decode("pon", tileListList), minkan = c.decode("minkan", tileListList), chi = c.decode("chi", tileListList),
                answered = c.stringIfPresent("answered"),
            )
            else -> throw IllegalArgumentException("모르는 결정 kind $kind")
        }
    }
}

/** state 묶음 — state 와 쓰기 RPC 응답 공통, 연습판 엔진의 `payload(for:)` 도 이 타입을 낸다. */
data class MahjongStatePayload(
    val match: MahjongStateMatch? = null,
    val members: List<MahjongStateMember>? = null,
    val seats: List<MahjongStateSeat>? = null,
    val mySeat: Int? = null,
    /** id 오름차순, 쯔모패 제외. */
    val myHand: List<MahjongTile>? = null,
    val myDrawn: MahjongTile? = null,
    /** 대기 종류(0~33). */
    val myWaits: List<Int>? = null,
    /** 원문 "discard"|"temporary"|"riichi". */
    val myFuriten: List<String>? = null,
    val myDecision: MahjongDecision? = null,
    val myAway: MahjongAwayState? = null,
    val events: List<MahjongEvent>? = null,
    val lastHand: MahjongHandResult? = null,
    val reactions: List<MahjongReaction>? = null,
    val rubyBalance: Int? = null,
    val serverNowMs: Double? = null,
) {
    /** 내 자리 줄(자리 전이면 null). */
    val mySeatRow: MahjongStateSeat? get() = mySeat?.let { s -> seats?.firstOrNull { it.seatNo == s } }

    /** 마지막 사건 seq(사건이 없으면 판 seq). */
    val lastEventSeq: Int? get() = events?.lastOrNull()?.seq ?: match?.seq

    companion object {
        /** 연습판 id 머리(서버 uuid 와 겹치지 않는다). */
        const val practiceIDPrefix = "ai-"
    }

    object Serializer : SwiftDecodableSerializer<MahjongStatePayload>("MahjongStatePayload") {
        override fun deserialize(decoder: Decoder): MahjongStatePayload {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongStatePayload(
                match = c.decodeIfPresent("match", MahjongStateMatch.Serializer),
                members = c.decodeIfPresent("members", ListSerializer(MahjongStateMember.Serializer)),
                seats = c.decodeIfPresent("seats", ListSerializer(MahjongStateSeat.Serializer)),
                mySeat = c.intIfPresent("my_seat"), myHand = c.decodeIfPresent("my_hand", tileList), myDrawn = c.decodeIfPresent("my_drawn", MahjongTileWire),
                myWaits = c.decodeIfPresent("my_waits", intList), myFuriten = c.decodeIfPresent("my_furiten", stringList),
                // 모르는 결정 kind 는 state 전체를 죽이지 않고 '내 몫 결정 없음'으로 접는다(CC-07).
                myDecision = swiftTry { c.decodeIfPresent("my_decision", MahjongDecisionWire) },
                myAway = c.decodeIfPresent("my_away", MahjongAwayState.Serializer), events = c.decodeIfPresent("events", ListSerializer(MahjongEvent.Serializer)),
                lastHand = c.decodeIfPresent("last_hand", MahjongHandResult.Serializer),
                reactions = c.decodeIfPresent("reactions", ListSerializer(MahjongReaction.Serializer)),
                rubyBalance = c.intIfPresent("ruby_balance"), serverNowMs = c.doubleIfPresent("server_now_ms"),
            )
        }
    }
}

// MARK: - 응답 — 쓰기 · 조회 공용

data class MahjongActionResponse(
    val status: MahjongRPCStatus,
    val state: MahjongStatePayload? = null,
    val matchId: String? = null,
    val need: Int? = null,
    val have: Int? = null,
    val side: String? = null,
    val dropped: List<String>? = null,
    val reasons: Map<String, String>? = null,
    val retryMs: Double? = null,
    val reason: String? = null,
    val stakes: List<Int>? = null,
    val formats: List<String>? = null,
    val serverNowMs: Double? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongActionResponse>("MahjongActionResponse") {
        override fun deserialize(decoder: Decoder): MahjongActionResponse {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongActionResponse(
                status = c.decode("status", MahjongRPCStatus.Serializer), state = c.decodeIfPresent("state", MahjongStatePayload.Serializer),
                matchId = c.stringIfPresent("match_id"), need = c.intIfPresent("need"), have = c.intIfPresent("have"), side = c.stringIfPresent("side"),
                dropped = c.decodeIfPresent("dropped", stringList), reasons = reasons(c), retryMs = c.doubleIfPresent("retry_ms"),
                reason = c.stringIfPresent("reason"), stakes = c.decodeIfPresent("stakes", intList), formats = c.decodeIfPresent("formats", stringList),
                serverNowMs = c.doubleIfPresent("server_now_ms"),
            )
        }

        /** Swift `[String: String]` — 사전 키(uuid)는 snake→camel 변환을 받지 않는다(Foundation 은 키 변환을 사전 키에 걸지 않는다). */
        private fun reasons(c: SwiftKeyed): Map<String, String>? {
            if (!c.contains("reasons")) return null
            val raw = c.raw("reasons")
            if (raw == null || raw is kotlinx.serialization.json.JsonNull) return null
            return SwiftDecoding.keyedPlain(c.decoder("reasons")).let { k ->
                k.obj.keys.associateWith { key -> k.string(key) }
            }
        }
    }
}

// MARK: - 응답 — 순위

data class MahjongRankRow(
    val rank: Int? = null, val userId: String? = null, val displayName: String? = null, val avatarUrl: String? = null, val character: String? = null,
    val center: String? = null, val games: Int? = null, val firsts: Int? = null, val avgRank: Double? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongRankRow>("MahjongRankRow") {
        override fun deserialize(decoder: Decoder): MahjongRankRow {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongRankRow(
                c.intIfPresent("rank"), c.stringIfPresent("user_id"), c.stringIfPresent("display_name"), c.stringIfPresent("avatar_url"),
                c.stringIfPresent("character"), c.stringIfPresent("center"), c.intIfPresent("games"), c.intIfPresent("firsts"), c.doubleIfPresent("avg_rank"),
            )
        }
    }
}

data class MahjongRankingMe(
    val rank: Int? = null, val games: Int? = null, val firsts: Int? = null, val seconds: Int? = null, val thirds: Int? = null, val fourths: Int? = null,
    val avgRank: Double? = null,
) {
    /** 순위에 오르기까지 남은 판 수(이미 올랐거나 모르면 0). */
    val gamesUntilRanked: Int get() = maxOf(0, MahjongRules.rankingMinGames - (games ?: 0))

    object Serializer : SwiftDecodableSerializer<MahjongRankingMe>("MahjongRankingMe") {
        override fun deserialize(decoder: Decoder): MahjongRankingMe {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongRankingMe(
                c.intIfPresent("rank"), c.intIfPresent("games"), c.intIfPresent("firsts"), c.intIfPresent("seconds"), c.intIfPresent("thirds"),
                c.intIfPresent("fourths"), c.doubleIfPresent("avg_rank"),
            )
        }
    }
}

data class MahjongRankingResponse(
    val status: MahjongRPCStatus,
    val serverNowMs: Double? = null,
    val recordSinceMs: Double? = null,
    val me: MahjongRankingMe? = null,
    val rows: List<MahjongRankRow>? = null,
) {
    object Serializer : SwiftDecodableSerializer<MahjongRankingResponse>("MahjongRankingResponse") {
        override fun deserialize(decoder: Decoder): MahjongRankingResponse {
            val c = SwiftDecoding.keyed(decoder)
            return MahjongRankingResponse(
                c.decode("status", MahjongRPCStatus.Serializer), c.doubleIfPresent("server_now_ms"), c.doubleIfPresent("record_since_ms"),
                c.decodeIfPresent("me", MahjongRankingMe.Serializer), c.decodeIfPresent("rows", ListSerializer(MahjongRankRow.Serializer)),
            )
        }
    }
}

// MARK: - 서비스 호출(13) — 몸통은 공용 duelRPC. 요청 마감(act · call · back)은 스토어가 감싼다.

private suspend fun <B, R> SupabaseWorkService.mahjongCall(
    rpc: MahjongWire.RPC, serializer: kotlinx.serialization.SerializationStrategy<B>, body: B, accessToken: String, response: DeserializationStrategy<R>,
): R = duelRPC(rpc.rawValue, encode(serializer, body), accessToken, response, rpc.retriesDeadlockOnce)

suspend fun SupabaseWorkService.mahjongLobby(accessToken: String): MahjongLobbyResponse =
    mahjongCall(MahjongWire.RPC.lobby, MahjongProtocolRequest.serializer(), MahjongProtocolRequest(), accessToken, MahjongLobbyResponse.Serializer)

suspend fun SupabaseWorkService.mahjongCreate(accessToken: String, stake: Int, isPublic: Boolean, format: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.create, MahjongCreateRequest.serializer(), MahjongCreateRequest(pStake = stake, pPublic = isPublic, pFormat = format), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongInvite(accessToken: String, matchID: String, userID: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.invite, MahjongInviteRequest.serializer(), MahjongInviteRequest(pMatchId = matchID, pUserId = userID), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongJoin(accessToken: String, matchID: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.join, MahjongMatchRequest.serializer(), MahjongMatchRequest(pMatchId = matchID), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongDecline(accessToken: String, matchID: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.decline, MahjongMatchRequest.serializer(), MahjongMatchRequest(pMatchId = matchID), accessToken, MahjongActionResponse.Serializer)

/** forming 이면 방에서 나가기(방장이면 방 닫기) · active 면 자리 비움(기권 아님). */
suspend fun SupabaseWorkService.mahjongLeave(accessToken: String, matchID: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.leave, MahjongMatchRequest.serializer(), MahjongMatchRequest(pMatchId = matchID), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongStart(accessToken: String, matchID: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.start, MahjongMatchRequest.serializer(), MahjongMatchRequest(pMatchId = matchID), accessToken, MahjongActionResponse.Serializer)

/** 상태. 읽기처럼 보이지만 마감이 지났으면 서버가 따라잡기로 판을 바꾼다. */
suspend fun SupabaseWorkService.mahjongState(accessToken: String, matchID: String, sinceSeq: Int = 0): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.state, MahjongStateRequest.serializer(), MahjongStateRequest(pMatchId = matchID, pSinceSeq = sinceSeq), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongAct(accessToken: String, matchID: String, expectedSeq: Int, action: String, tiles: List<MahjongTile>): MahjongActionResponse =
    mahjongCall(
        MahjongWire.RPC.act, MahjongActRequest.serializer(),
        MahjongActRequest(pMatchId = matchID, pExpectedSeq = expectedSeq, pAction = action, pTiles = tiles.map { it.id }), accessToken, MahjongActionResponse.Serializer,
    )

suspend fun SupabaseWorkService.mahjongCallAnswer(accessToken: String, matchID: String, windowID: Int, action: String, tiles: List<MahjongTile>): MahjongActionResponse =
    mahjongCall(
        MahjongWire.RPC.call, MahjongCallRequest.serializer(),
        MahjongCallRequest(pMatchId = matchID, pWindowId = windowID, pAction = action, pTiles = tiles.map { it.id }), accessToken, MahjongActionResponse.Serializer,
    )

/** [돌아왔어요] — 자리 비움 풀기. */
suspend fun SupabaseWorkService.mahjongBack(accessToken: String, matchID: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.back, MahjongMatchRequest.serializer(), MahjongMatchRequest(pMatchId = matchID), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongReact(accessToken: String, matchID: String, key: String): MahjongActionResponse =
    mahjongCall(MahjongWire.RPC.react, MahjongReactRequest.serializer(), MahjongReactRequest(pMatchId = matchID, pKey = key), accessToken, MahjongActionResponse.Serializer)

suspend fun SupabaseWorkService.mahjongRanking(accessToken: String): MahjongRankingResponse =
    mahjongCall(MahjongWire.RPC.ranking, MahjongProtocolRequest.serializer(), MahjongProtocolRequest(), accessToken, MahjongRankingResponse.Serializer)
