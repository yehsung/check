// 원본: Sources/CheckCore/DuelRooms.swift @ main 341eb4e3(맥 0.3.83 · 아이폰 1.0.19 9774e23b 가 같은 코어) — 판 9 1:1 대기방의 전선
//
// 방 = **상대를 정하지 않은 신청**. 방장이 게임 · 판돈을 골라 열면 그 게임 로비 '기다리는 방'에 뜨고, 누구든 [참가]하면 서버가 한 트랜잭션에서
// 그 게임의 신청(방장) + 수락(참가자)으로 판을 세운다 — 판돈 · 정산 · 전적 · 대국 중 판정은 각 게임 것 그대로다.
// 응답 상태는 모르는 값이 와도 죽지 않는다(unknown). 방 줄 하나가 깨져도 나머지는 산다. 문(서버 duel__capable)이 닫혀 있으면 unsupported_client.
package com.yehsung.aingcheck.core.wire.rooms

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.SwiftKeyed
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** 방을 열 수 있는 게임(서버 duel_rooms_games() 와 같은 글자). */
enum class DuelRoomGame(val rawValue: String, val title: String) {
    gomoku("gomoku", "오목"),
    chess("chess", "체스"),
    tetris("tetris", "테트리스"),
    reversi("reversi", "아잉 뒤집기"),
    crossyDuel("crossy_duel", "1:1 길건너"),
    alkkagi("alkkagi", "1:1 알까기");

    companion object {
        fun of(raw: String?): DuelRoomGame? = entries.firstOrNull { it.rawValue == raw }
    }
}

data class DuelRoomHost(val userID: String, val displayName: String, val avatarURL: String? = null, val character: String? = null) {
    companion object {
        fun decode(c: SwiftKeyed): DuelRoomHost = DuelRoomHost(c.string("user_id"), c.string("display_name"), c.stringIfPresent("avatar_url"), c.stringIfPresent("character"))
    }
}

@Serializable(with = DuelRoom.Serializer::class)
data class DuelRoom(
    val id: String,
    val gameRaw: String,
    val stake: Long,
    val status: String = "open",
    val createdMs: Double,
    val seenMs: Double? = null,
    val expiresMs: Double? = null,
    val matchID: String? = null,
    val closeReason: String? = null,
    val host: DuelRoomHost? = null,
) {
    val game: DuelRoomGame? get() = DuelRoomGame.of(gameRaw)
    val isOpen: Boolean get() = status == "open"
    val isStarted: Boolean get() = status == "started" && !matchID.isNullOrEmpty()

    /** 서버 duel__room_json 의 키. */
    object Serializer : SwiftDecodableSerializer<DuelRoom>("DuelRoom") {
        override fun deserialize(decoder: Decoder): DuelRoom {
            val c = SwiftDecoding.keyed(decoder)
            return DuelRoom(
                id = c.string("id"), gameRaw = c.string("game"), stake = c.long("stake"), status = c.string("status"),
                createdMs = c.double("created_ms"), seenMs = c.doubleIfPresent("seen_ms"), expiresMs = c.doubleIfPresent("expires_ms"),
                matchID = c.stringIfPresent("match_id"), closeReason = c.stringIfPresent("close_reason"),
                host = c.decodeIfPresent("host", HostSerializer),
            )
        }
    }

    private object HostSerializer : SwiftDecodableSerializer<DuelRoomHost>("DuelRoomHost") {
        override fun deserialize(decoder: Decoder): DuelRoomHost = DuelRoomHost.decode(SwiftDecoding.keyed(decoder))
    }
}

/** 서버 응답 상태(모르는 값은 unknown — 디코드가 죽지 않는다). */
enum class DuelRoomStatus(val rawValue: String) {
    ok("ok"), unauthorized("unauthorized"), invalid("invalid"), insufficient("insufficient"), busy("busy"), stale("stale"),
    focused("focused"), blackout("blackout"), unsupportedClient("unsupported_client"), unsupportedGame("unsupported_game"),
    notFound("not_found"), roomGone("room_gone"), ownRoom("own_room"), updateRequired("update_required"), hostBusy("host_busy"),
    unknown("");

    companion object {
        fun of(raw: String?): DuelRoomStatus = entries.firstOrNull { it != unknown && it.rawValue == raw } ?: unknown
    }
}

@Serializable(with = DuelRoomsResponse.Serializer::class)
data class DuelRoomsResponse(
    val status: DuelRoomStatus,
    val serverNowMs: Double? = null,
    val stakes: List<Long>? = null,
    val doorOpen: Boolean? = null,
    val rooms: List<DuelRoom>? = null,
    val myRoom: DuelRoom? = null,
    val room: DuelRoom? = null,
    val need: Long? = null,
    val have: Long? = null,
    val reason: String? = null,
    val matchID: String? = null,
    val gameRaw: String? = null,
    val rubyBalance: Long? = null,
) {
    object Serializer : SwiftDecodableSerializer<DuelRoomsResponse>("DuelRoomsResponse") {
        override fun deserialize(decoder: Decoder): DuelRoomsResponse {
            val c = SwiftDecoding.keyed(decoder)
            // 방 줄 하나가 깨져도 나머지는 산다.
            val rooms = (c.raw("rooms") as? JsonArray)?.mapNotNull { element -> swiftTry { SwiftJson.decode(DuelRoom.serializer(), element) } }
            return DuelRoomsResponse(
                status = DuelRoomStatus.of(swiftTry { c.string("status") }),
                serverNowMs = swiftTry { c.doubleIfPresent("server_now_ms") },
                stakes = c.lossy("stakes", ListSerializer(Long.serializer())),
                doorOpen = c.lossyBool("door_open"),
                rooms = rooms,
                myRoom = c.lossy("my_room", DuelRoom.serializer()),
                room = c.lossy("room", DuelRoom.serializer()),
                need = c.lossyLong("need"),
                have = c.lossyLong("have"),
                reason = c.lossyString("reason"),
                matchID = c.lossyString("match_id"),
                gameRaw = c.lossyString("game"),
                rubyBalance = c.lossyLong("ruby_balance"),
            )
        }
    }
}

/** RPC 다섯. 서명은 서버와 같다(p_protocol 은 맨 뒤 · 없는 칸은 싣지 않는다). */
sealed interface DuelRoomCall {
    data class list(val game: DuelRoomGame) : DuelRoomCall
    data class open(val game: DuelRoomGame, val stake: Long) : DuelRoomCall
    data class close(val roomID: String) : DuelRoomCall
    data object ping : DuelRoomCall
    data class join(val roomID: String) : DuelRoomCall

    val rpcName: String
        get() = when (this) {
            is list -> "duel_rooms_list"
            is open -> "duel_room_open"
            is close -> "duel_room_close"
            ping -> "duel_room_ping"
            is join -> "duel_room_join"
        }

    val body: DuelRoomBody
        get() = when (this) {
            is list -> DuelRoomBody(game = game.rawValue)
            is open -> DuelRoomBody(game = game.rawValue, stake = stake)
            is close -> DuelRoomBody(room = roomID)
            ping -> DuelRoomBody()
            is join -> DuelRoomBody(room = roomID)
        }
}

@Serializable(with = DuelRoomBody.Serializer::class)
data class DuelRoomBody(val game: String? = null, val stake: Long? = null, val room: String? = null, val protocolVersion: Int = PROTOCOL_VERSION) {
    companion object {
        const val PROTOCOL_VERSION = 1
    }

    object Serializer : KSerializer<DuelRoomBody> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("DuelRoomBody")
        override fun serialize(encoder: Encoder, value: DuelRoomBody) {
            val map = LinkedHashMap<String, kotlinx.serialization.json.JsonElement>()
            value.game?.let { map["p_game"] = JsonPrimitive(it) }
            value.stake?.let { map["p_stake"] = JsonPrimitive(it) }
            value.room?.let { map["p_room"] = JsonPrimitive(it) }
            map["p_protocol"] = JsonPrimitive(value.protocolVersion)
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(map))
        }
        override fun deserialize(decoder: Decoder): DuelRoomBody = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** 사용자 문구(서버 · 시험 같은 내부 어휘 없음 — 맥 · 아이폰과 같은 글). */
object DuelRoomText {
    const val roomsTitle = "기다리는 방"
    const val create = "방 만들기"
    const val createTitle = "방 만들기"
    const val createHint = "판돈을 정해 방을 열어 두면, 누가 들어오는 순간 바로 대결이 시작돼요."
    const val createButton = "만들기"
    const val createClose = "방 만들기 닫기"
    const val join = "참가"
    const val notEnough = "루비 부족"
    const val myRoomTitle = "내 방"
    const val myRoomHint = "누가 들어오면 바로 시작해요 · 창을 닫아도 방은 30분 남아요"
    const val closeRoom = "닫기"
    const val emptyRooms = "기다리는 방이 없어요 · 방을 만들어 두고 일하세요"
    const val loading = "방을 불러오는 중…"
    const val stakeLabel = "판돈"
    fun otherGameRoom(game: DuelRoomGame): String = "${game.title} 방을 열어 두었어요"
    fun waiting(seconds: Long): String = if (seconds < 60) "방금" else "${seconds / 60}분째 기다림"
    fun stakeLine(stake: Long): String = "$stake · 이기면 +$stake"

    /** 상태별 안내(열기 · 참가 · 닫기의 실패). */
    fun notice(status: DuelRoomStatus, need: Long? = null): String? = when (status) {
        DuelRoomStatus.ok -> null
        DuelRoomStatus.insufficient -> need?.let { "루비가 모자라요 · 판돈 $it" } ?: "루비가 모자라요"
        DuelRoomStatus.busy -> "대결 중에는 방을 열거나 들어갈 수 없어요"
        DuelRoomStatus.roomGone -> "방이 닫혔어요"
        DuelRoomStatus.ownRoom -> "내가 연 방이에요"
        DuelRoomStatus.focused -> "집중 모드를 끄면 들어갈 수 있어요"
        DuelRoomStatus.updateRequired, DuelRoomStatus.unsupportedGame, DuelRoomStatus.unsupportedClient -> "앱을 업데이트하면 방을 쓸 수 있어요"
        DuelRoomStatus.blackout -> "지금은 대결 신청을 받지 않는 시간이에요"
        DuelRoomStatus.hostBusy -> "방장이 다른 신청을 기다리는 중이에요 · 잠시 뒤에 다시"
        DuelRoomStatus.notFound, DuelRoomStatus.stale -> "방이 바뀌었어요 · 다시 불러올게요"
        DuelRoomStatus.invalid, DuelRoomStatus.unauthorized, DuelRoomStatus.unknown -> "잠시 뒤에 다시 해 주세요"
    }
}
