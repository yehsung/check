// 원본: Sources/CheckCore/AlkkagiOnlineWire.swift @ e4995a3a(1:1 알까기 와이어 v2 — 맥 0.3.82 · 폰 1.0.18) — Android 판 8
//
// 요청 본문 · 응답 디코딩(SPEC v1.1 §1 · §3.5~3.7 · §4.1). 키 이름은 알까기 v1 것을 지키고 덧붙이기만 한다. 서명은 v1 순서(p_protocol 맨 뒤).
// 디코딩은 Swift 의 직접 짠 init(from:) 그대로다 — 필수 칸이 없으면 던지고(그 응답은 버린다), 선택 칸은 없으면 null.
// 돌(Stone)은 Swift 합성 Codable 이라 칸 여섯이 전부 필수다(`id` · `owner` · `position` · `velocity` · `isOut` · `isPlaced` — 서버가 camel 로 싣는다).
// 정수 칸은 Swift Int(64비트)라 Long 이다.
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftKeyed
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import com.yehsung.aingcheck.core.wire.json.lossyList
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.json.JsonNull

object AlkkagiWire {
    /** 모든 요청의 `p_protocol` 이자 응답이 넘어야 하는 문턱(낮으면 서버가 옛판 — '곧 열려요'). */
    const val protocolVersion: Long = 2

    enum class RPC(val rawValue: String) {
        lobby("alkkagi_lobby"), challenge("alkkagi_challenge"), cancel("alkkagi_cancel"), respond("alkkagi_respond"),
        state("alkkagi_state"), place("alkkagi_place"), ready("alkkagi_ready"), shoot("alkkagi_shoot"), resign("alkkagi_resign"),
        leave("alkkagi_leave"), chatSend("alkkagi_chat_send"), chatMute("alkkagi_chat_mute"), ranking("alkkagi_ranking"),
        watch("alkkagi_watch"), watchLive("alkkagi_watch_live");

        companion object {
            val all: List<String> get() = entries.map { it.rawValue }
        }
    }
}

/** 요청 본문 하나(쓰지 않는 칸은 키째 빠진다 — SwiftJson `explicitNulls = false`). `p_protocol` 은 언제나 싣는다. */
@Serializable
data class AlkkagiParameters(
    @SerialName("p_protocol") val pProtocol: Long = AlkkagiWire.protocolVersion,
    @SerialName("p_users") val pUsers: Boolean? = null,
    @SerialName("p_opponent") val pOpponent: String? = null,
    @SerialName("p_stake") val pStake: Long? = null,
    @SerialName("p_match_id") val pMatchID: String? = null,
    @SerialName("p_action_id") val pActionID: String? = null,
    @SerialName("p_expected_revision") val pExpectedRevision: Long? = null,
    @SerialName("p_expected_placement_revision") val pExpectedPlacementRevision: Long? = null,
    @SerialName("p_accept") val pAccept: Boolean? = null,
    @SerialName("p_since_chat_seq") val pSinceChatSeq: Long? = null,
    @SerialName("p_stone_id") val pStoneID: Long? = null,
    @SerialName("p_x") val pX: Double? = null,
    @SerialName("p_y") val pY: Double? = null,
    @SerialName("p_pull_x") val pPullX: Double? = null,
    @SerialName("p_pull_y") val pPullY: Double? = null,
    @SerialName("p_body") val pBody: String? = null,
    @SerialName("p_muted") val pMuted: Boolean? = null,
)

/** 한 번의 동작(Swift `AlkkagiCall`). 동작마다 한 번 만든 값이 세션 · 교착 재시도에 그대로 다시 쓰인다(action_id 멱등). uuid 는 소문자 글자. */
sealed interface AlkkagiCall {
    data class Lobby(val users: Boolean = true) : AlkkagiCall
    data class Challenge(val opponentID: String, val stake: Long, val actionID: String) : AlkkagiCall
    data class Cancel(val matchID: String, val actionID: String) : AlkkagiCall
    data class Respond(val matchID: String, val accept: Boolean, val actionID: String) : AlkkagiCall
    data class State(val matchID: String, val sinceChatSeq: Long = 0) : AlkkagiCall
    data class Place(val matchID: String, val expectedPlacementRevision: Long, val stoneID: Long, val x: Double, val y: Double, val actionID: String) : AlkkagiCall
    data class Ready(val matchID: String, val expectedPlacementRevision: Long, val actionID: String) : AlkkagiCall
    data class Shoot(val matchID: String, val expectedRevision: Long, val stoneID: Long, val pullX: Double, val pullY: Double, val actionID: String) : AlkkagiCall
    data class Resign(val matchID: String, val expectedRevision: Long, val actionID: String) : AlkkagiCall
    data class ChatSend(val matchID: String, val body: String, val actionID: String) : AlkkagiCall
    data class ChatMute(val matchID: String, val muted: Boolean, val actionID: String) : AlkkagiCall
    data class Leave(val matchID: String, val expectedRevision: Long, val actionID: String) : AlkkagiCall
    data object Ranking : AlkkagiCall
    data class Watch(val matchID: String?) : AlkkagiCall
    data class WatchLive(val matchID: String?) : AlkkagiCall

    val rpc: AlkkagiWire.RPC
        get() = when (this) {
            is Lobby -> AlkkagiWire.RPC.lobby
            is Challenge -> AlkkagiWire.RPC.challenge
            is Cancel -> AlkkagiWire.RPC.cancel
            is Respond -> AlkkagiWire.RPC.respond
            is State -> AlkkagiWire.RPC.state
            is Place -> AlkkagiWire.RPC.place
            is Ready -> AlkkagiWire.RPC.ready
            is Shoot -> AlkkagiWire.RPC.shoot
            is Resign -> AlkkagiWire.RPC.resign
            is ChatSend -> AlkkagiWire.RPC.chatSend
            is ChatMute -> AlkkagiWire.RPC.chatMute
            is Leave -> AlkkagiWire.RPC.leave
            Ranking -> AlkkagiWire.RPC.ranking
            is Watch -> AlkkagiWire.RPC.watch
            is WatchLive -> AlkkagiWire.RPC.watchLive
        }

    val rpcName: String get() = rpc.rawValue

    val parameters: AlkkagiParameters
        get() = when (this) {
            is Lobby -> AlkkagiParameters(pUsers = users)
            is Challenge -> AlkkagiParameters(pOpponent = opponentID, pActionID = actionID, pStake = stake)
            is Cancel -> AlkkagiParameters(pMatchID = matchID, pActionID = actionID)
            is Respond -> AlkkagiParameters(pMatchID = matchID, pAccept = accept, pActionID = actionID)
            is State -> AlkkagiParameters(pMatchID = matchID, pSinceChatSeq = sinceChatSeq)
            is Place -> AlkkagiParameters(pMatchID = matchID, pExpectedPlacementRevision = expectedPlacementRevision, pStoneID = stoneID, pX = x, pY = y, pActionID = actionID)
            is Ready -> AlkkagiParameters(pMatchID = matchID, pExpectedPlacementRevision = expectedPlacementRevision, pActionID = actionID)
            is Resign -> AlkkagiParameters(pMatchID = matchID, pExpectedRevision = expectedRevision, pActionID = actionID)
            is Leave -> AlkkagiParameters(pMatchID = matchID, pExpectedRevision = expectedRevision, pActionID = actionID)
            is Shoot -> AlkkagiParameters(pMatchID = matchID, pExpectedRevision = expectedRevision, pStoneID = stoneID, pPullX = pullX, pPullY = pullY, pActionID = actionID)
            is ChatSend -> AlkkagiParameters(pMatchID = matchID, pBody = body, pActionID = actionID)
            is ChatMute -> AlkkagiParameters(pMatchID = matchID, pMuted = muted, pActionID = actionID)
            Ranking -> AlkkagiParameters()
            is Watch -> AlkkagiParameters(pMatchID = matchID)
            is WatchLive -> AlkkagiParameters(pMatchID = matchID)
        }
}

/** 서버 status 어휘. 모르는 값은 unknown 으로 접는다. */
@Serializable(with = AlkkagiRPCStatus.Serializer::class)
enum class AlkkagiRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"), stale("stale"), invalid("invalid"), busy("busy"), expired("expired"), forbidden("forbidden"), blackout("blackout"),
    insufficient("insufficient"), notSignedIn("not_signed_in"), unsupportedClient("unsupported_client"), notFound("not_found"),
    notPending("not_pending"), notActive("not_active"), alreadyPending("already_pending"), targetBusy("target_busy"),
    targetFocused("target_focused"), targetOutdated("target_outdated"), rateLimited("rate_limited"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<AlkkagiRPCStatus>("AlkkagiRPCStatus", entries, unknown)
}

@Serializable(with = AlkkagiMatchPhase.Serializer::class)
enum class AlkkagiMatchPhase(override val rawValue: String) : SwiftRawValued {
    placing("placing"), aiming("aiming"), rolling("rolling"), finished("finished"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<AlkkagiMatchPhase>("AlkkagiMatchPhase", entries, unknown)
}

@Serializable(with = AlkkagiMatchResult.Serializer::class)
enum class AlkkagiMatchResult(override val rawValue: String) : SwiftRawValued {
    black("black"), white("white"), draw("draw"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<AlkkagiMatchResult>("AlkkagiMatchResult", entries, unknown)
}

/** 돌 색(와이어 글자 그대로 — 모르는 글자는 디코드 실패). */
@Serializable(with = AlkkagiPlayerWire.Serializer::class)
enum class AlkkagiPlayerWire(val rawValue: String) {
    black("black"), white("white");

    object Serializer : SwiftDecodableSerializer<AlkkagiPlayerWire>("AlkkagiPlayerWire") {
        override fun deserialize(decoder: Decoder): AlkkagiPlayerWire {
            val raw = String.serializer().deserialize(decoder)
            return entries.firstOrNull { it.rawValue == raw } ?: throw IllegalArgumentException("모르는 돌 색 $raw")
        }
    }
}

@Serializable(with = AlkkagiVectorWire.Serializer::class)
data class AlkkagiVectorWire(val x: Double, val y: Double) {
    object Serializer : SwiftDecodableSerializer<AlkkagiVectorWire>("AlkkagiVectorWire") {
        override fun deserialize(decoder: Decoder): AlkkagiVectorWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiVectorWire(c.double("x"), c.double("y"))
        }
    }
}

@Serializable(with = AlkkagiStoneWire.Serializer::class)
data class AlkkagiStoneWire(
    val id: Long,
    val owner: AlkkagiPlayerWire,
    val position: AlkkagiVectorWire,
    val velocity: AlkkagiVectorWire,
    val isOut: Boolean,
    val isPlaced: Boolean,
) {
    object Serializer : SwiftDecodableSerializer<AlkkagiStoneWire>("AlkkagiStoneWire") {
        override fun deserialize(decoder: Decoder): AlkkagiStoneWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiStoneWire(
                c.long("id"), c.decode("owner", AlkkagiPlayerWire.serializer()), c.decode("position", AlkkagiVectorWire.serializer()),
                c.decode("velocity", AlkkagiVectorWire.serializer()), c.bool("is_out"), c.bool("is_placed"),
            )
        }
    }
}

@Serializable(with = AlkkagiPeer.Serializer::class)
data class AlkkagiPeer(val id: String, val displayName: String, val avatarURL: String? = null, val characterID: String? = null, val busy: Boolean? = null) {
    object Serializer : SwiftDecodableSerializer<AlkkagiPeer>("AlkkagiPeer") {
        override fun deserialize(decoder: Decoder): AlkkagiPeer {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiPeer(c.string("id"), c.string("display_name"), c.stringIfPresent("avatar_url"), c.stringIfPresent("character_id"), c.boolIfPresent("busy"))
        }
    }
}

/** INVITE = v1 + `stake`. v2 신청은 늘 판돈이 있다 — null 은 v1 옛 신청뿐이다. */
@Serializable(with = AlkkagiInviteWire.Serializer::class)
data class AlkkagiInviteWire(val id: String, val opponent: AlkkagiPeer, val expiresAtMs: Double, val stake: Long? = null) {
    object Serializer : SwiftDecodableSerializer<AlkkagiInviteWire>("AlkkagiInvite") {
        override fun deserialize(decoder: Decoder): AlkkagiInviteWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiInviteWire(c.string("id"), c.decode("opponent", AlkkagiPeer.serializer()), c.double("expires_at_ms"), c.longIfPresent("stake"))
        }
    }
}

@Serializable(with = AlkkagiChatMessage.Serializer::class)
data class AlkkagiChatMessage(val seq: Long, val senderID: String, val body: String, val sentAtMs: Double) {
    object Serializer : SwiftDecodableSerializer<AlkkagiChatMessage>("AlkkagiChatMessage") {
        override fun deserialize(decoder: Decoder): AlkkagiChatMessage {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiChatMessage(c.long("seq"), c.string("sender_id"), c.string("body"), c.double("sent_at_ms"))
        }
    }
}

@Serializable(with = AlkkagiShotWire.Serializer::class)
data class AlkkagiShotWire(val id: String, val stoneID: Long, val pull: AlkkagiVectorWire, val startedAtMs: Double, val steps: Long, val initialStones: List<AlkkagiStoneWire>) {
    /** 굴림 길이(초) = 걸음 / 240. */
    val duration: Double get() = maxOf(0L, steps).toDouble() / 240

    object Serializer : SwiftDecodableSerializer<AlkkagiShotWire>("AlkkagiShot") {
        override fun deserialize(decoder: Decoder): AlkkagiShotWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiShotWire(
                c.string("id"), c.long("stone_id"), c.decode("pull", AlkkagiVectorWire.serializer()), c.double("started_at_ms"), c.long("steps"),
                c.decode("initial_stones", ListSerializer(AlkkagiStoneWire.serializer())),
            )
        }
    }
}

/** STATE(내 판 — `my_color` 있음). 놓기(placing) 판은 놓기 세 칸이 필수다. v2 덧붙임은 없으면 null(옛 판). */
@Serializable(with = AlkkagiMatchWire.Serializer::class)
data class AlkkagiMatchWire(
    val id: String,
    val revision: Long,
    val phase: AlkkagiMatchPhase,
    val currentPlayer: AlkkagiPlayerWire,
    val myColor: AlkkagiPlayerWire,
    val black: AlkkagiPeer,
    val white: AlkkagiPeer,
    val stones: List<AlkkagiStoneWire>,
    val deadlineMs: Double? = null,
    val shotCount: Long = 0,
    val result: AlkkagiMatchResult? = null,
    val finishReason: String? = null,
    val shot: AlkkagiShotWire? = null,
    val chatSeq: Long = 0,
    val chat: List<AlkkagiChatMessage> = emptyList(),
    val muted: Boolean = false,
    val placementRevision: Long = 1,
    val myReady: Boolean = false,
    val opponentReady: Boolean = false,
    val stake: Long? = null,
    val acceptedAtMs: Double? = null,
    val myMissedTurns: Long? = null,
    val opponentMissedTurns: Long? = null,
    val forfeitAfter: Long? = null,
    val settled: Boolean? = null,
    val rubyBalance: Long? = null,
    val watchers: Long? = null,
    val graceMs: Double? = null,
) {
    object Serializer : SwiftDecodableSerializer<AlkkagiMatchWire>("AlkkagiMatch") {
        override fun deserialize(decoder: Decoder): AlkkagiMatchWire {
            val c = SwiftDecoding.keyed(decoder)
            val phase = c.decode("phase", AlkkagiMatchPhase.serializer())
            val placing = phase == AlkkagiMatchPhase.placing
            return AlkkagiMatchWire(
                id = c.string("id"),
                revision = c.long("revision"),
                phase = phase,
                currentPlayer = c.decode("current_player", AlkkagiPlayerWire.serializer()),
                myColor = c.decode("my_color", AlkkagiPlayerWire.serializer()),
                black = c.decode("black", AlkkagiPeer.serializer()),
                white = c.decode("white", AlkkagiPeer.serializer()),
                stones = c.decode("stones", ListSerializer(AlkkagiStoneWire.serializer())),
                deadlineMs = c.doubleIfPresent("deadline_ms"),
                shotCount = c.long("shot_count"),
                result = c.decodeIfPresent("result", AlkkagiMatchResult.serializer()),
                finishReason = c.stringIfPresent("finish_reason"),
                shot = c.decodeIfPresent("shot", AlkkagiShotWire.serializer()),
                chatSeq = c.long("chat_seq"),
                chat = c.decode("chat", ListSerializer(AlkkagiChatMessage.serializer())),
                muted = c.bool("muted"),
                placementRevision = if (placing) c.long("placement_revision") else c.longIfPresent("placement_revision") ?: 1,
                myReady = if (placing) c.bool("my_ready") else c.boolIfPresent("my_ready") ?: false,
                opponentReady = if (placing) c.bool("opponent_ready") else c.boolIfPresent("opponent_ready") ?: false,
                stake = c.longIfPresent("stake"),
                acceptedAtMs = c.doubleIfPresent("accepted_at_ms"),
                myMissedTurns = c.longIfPresent("my_missed_turns"),
                opponentMissedTurns = c.longIfPresent("opponent_missed_turns"),
                forfeitAfter = c.longIfPresent("forfeit_after"),
                settled = c.boolIfPresent("settled"),
                rubyBalance = c.longIfPresent("ruby_balance"),
                watchers = c.longIfPresent("watchers"),
                graceMs = c.doubleIfPresent("grace_ms"),
            )
        }
    }
}

/** USER = {id, display_name, avatar_url, character_id, is_working, in_match, capable, focus_mode}. `capable` 이 없으면 불가. */
@Serializable(with = AlkkagiLobbyUserWire.Serializer::class)
data class AlkkagiLobbyUserWire(
    val id: String, val displayName: String, val avatarURL: String?, val characterID: String?,
    val isWorking: Boolean, val inMatch: Boolean, val isCapable: Boolean, val isFocused: Boolean,
) {
    object Serializer : SwiftDecodableSerializer<AlkkagiLobbyUserWire>("AlkkagiLobbyUser") {
        override fun deserialize(decoder: Decoder): AlkkagiLobbyUserWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiLobbyUserWire(
                c.string("id"), c.string("display_name"), c.stringIfPresent("avatar_url"), c.stringIfPresent("character_id"),
                c.boolIfPresent("is_working") ?: false, c.boolIfPresent("in_match") ?: false, c.boolIfPresent("capable") ?: false,
                c.boolIfPresent("focus_mode") ?: false,
            )
        }
    }
}

@Serializable(with = AlkkagiRecordWire.Serializer::class)
data class AlkkagiRecordWire(val wins: Long, val losses: Long, val draws: Long) {
    object Serializer : SwiftDecodableSerializer<AlkkagiRecordWire>("AlkkagiRecord") {
        override fun deserialize(decoder: Decoder): AlkkagiRecordWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiRecordWire(c.longIfPresent("wins") ?: 0, c.longIfPresent("losses") ?: 0, c.longIfPresent("draws") ?: 0)
        }
    }
}

/** LIVE = {id, black, white, stake, shot_count, watchers, accepted_at_ms}. */
@Serializable(with = AlkkagiLiveMatchWire.Serializer::class)
data class AlkkagiLiveMatchWire(val id: String, val black: AlkkagiPeer, val white: AlkkagiPeer, val stake: Long?, val shotCount: Long, val watchers: Long, val acceptedAtMs: Double?) {
    object Serializer : SwiftDecodableSerializer<AlkkagiLiveMatchWire>("AlkkagiLiveMatch") {
        override fun deserialize(decoder: Decoder): AlkkagiLiveMatchWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiLiveMatchWire(
                c.string("id"), c.decode("black", AlkkagiPeer.serializer()), c.decode("white", AlkkagiPeer.serializer()), c.longIfPresent("stake"),
                c.longIfPresent("shot_count") ?: 0, c.longIfPresent("watchers") ?: 0, c.doubleIfPresent("accepted_at_ms"),
            )
        }
    }
}

@Serializable(with = AlkkagiRankEntryWire.Serializer::class)
data class AlkkagiRankEntryWire(
    val rank: Long, val id: String, val displayName: String, val avatarURL: String?, val characterID: String?,
    val wins: Long, val losses: Long, val draws: Long, val points: Long,
) {
    object Serializer : SwiftDecodableSerializer<AlkkagiRankEntryWire>("AlkkagiRankEntry") {
        override fun deserialize(decoder: Decoder): AlkkagiRankEntryWire {
            val c = SwiftDecoding.keyed(decoder)
            val wins = c.longIfPresent("wins") ?: 0
            val losses = c.longIfPresent("losses") ?: 0
            return AlkkagiRankEntryWire(
                c.long("rank"), c.string("id").lowercase(), c.stringIfPresent("display_name") ?: "", c.stringIfPresent("avatar_url"),
                c.stringIfPresent("character_id"), wins, losses, c.longIfPresent("draws") ?: 0, c.longIfPresent("points") ?: (wins - losses),
            )
        }
    }
}

@Serializable(with = AlkkagiMyRankWire.Serializer::class)
data class AlkkagiMyRankWire(val rank: Long?, val wins: Long, val losses: Long, val draws: Long, val points: Long) {
    object Serializer : SwiftDecodableSerializer<AlkkagiMyRankWire>("AlkkagiMyRank") {
        override fun deserialize(decoder: Decoder): AlkkagiMyRankWire {
            val c = SwiftDecoding.keyed(decoder)
            val wins = c.longIfPresent("wins") ?: 0
            val losses = c.longIfPresent("losses") ?: 0
            return AlkkagiMyRankWire(c.longIfPresent("rank"), wins, losses, c.longIfPresent("draws") ?: 0, c.longIfPresent("points") ?: (wins - losses))
        }
    }
}

/** 순위 응답 한 벌(행은 깨진 줄만 버린다). */
data class AlkkagiRankingWire(val entries: List<AlkkagiRankEntryWire>, val me: AlkkagiMyRankWire?, val recordSinceMs: Double?)

/** WATCH(관전 — `my_color` 없음). 둘 다 준비 전이면 `stones` 가 [] 다. `watchers` 는 watch_live 만 싣는다. */
@Serializable(with = AlkkagiWatchStateWire.Serializer::class)
data class AlkkagiWatchStateWire(
    val id: String,
    val revision: Long,
    val phase: AlkkagiMatchPhase,
    val currentPlayer: AlkkagiPlayerWire,
    val black: AlkkagiPeer,
    val white: AlkkagiPeer,
    val blackReady: Boolean,
    val whiteReady: Boolean,
    val stones: List<AlkkagiStoneWire>,
    val deadlineMs: Double?,
    val shotCount: Long,
    val result: AlkkagiMatchResult?,
    val finishReason: String?,
    val shot: AlkkagiShotWire?,
    val stake: Long?,
    val blackMissedTurns: Long,
    val whiteMissedTurns: Long,
    val forfeitAfter: Long,
    val finishedAtMs: Double?,
    val watchers: Long?,
) {
    object Serializer : SwiftDecodableSerializer<AlkkagiWatchStateWire>("AlkkagiWatchState") {
        override fun deserialize(decoder: Decoder): AlkkagiWatchStateWire {
            val c = SwiftDecoding.keyed(decoder)
            return AlkkagiWatchStateWire(
                id = c.string("id"),
                revision = c.long("revision"),
                phase = c.decode("phase", AlkkagiMatchPhase.serializer()),
                currentPlayer = c.decodeIfPresent("current_player", AlkkagiPlayerWire.serializer()) ?: AlkkagiPlayerWire.black,
                black = c.decode("black", AlkkagiPeer.serializer()),
                white = c.decode("white", AlkkagiPeer.serializer()),
                blackReady = c.boolIfPresent("black_ready") ?: false,
                whiteReady = c.boolIfPresent("white_ready") ?: false,
                stones = c.decodeIfPresent("stones", ListSerializer(AlkkagiStoneWire.serializer())) ?: emptyList(),
                deadlineMs = c.doubleIfPresent("deadline_ms"),
                shotCount = c.longIfPresent("shot_count") ?: 0,
                result = c.decodeIfPresent("result", AlkkagiMatchResult.serializer()),
                finishReason = c.stringIfPresent("finish_reason"),
                shot = c.decodeIfPresent("shot", AlkkagiShotWire.serializer()),
                stake = c.longIfPresent("stake"),
                blackMissedTurns = c.longIfPresent("black_missed_turns") ?: 0,
                whiteMissedTurns = c.longIfPresent("white_missed_turns") ?: 0,
                forfeitAfter = c.longIfPresent("forfeit_after") ?: 3,
                finishedAtMs = c.doubleIfPresent("finished_at_ms"),
                watchers = c.longIfPresent("watchers"),
            )
        }
    }
}

/**
 * 모든 RPC 의 응답 한 모양(봉투 + 덧붙임). 갈리는 곳 둘: `state` 는 `my_color` 가 있으면 내 판([state]), 없으면 관전([watch]) ·
 * 최상위 `rows` 가 있으면 순위 응답이고 그때 `me` 는 내 순위 줄([ranking]).
 */
@Serializable(with = AlkkagiResponse.Serializer::class)
data class AlkkagiResponse(
    val status: AlkkagiRPCStatus,
    val protocolVersion: Long = AlkkagiWire.protocolVersion,
    val serverNowMs: Double,
    val me: AlkkagiPeer? = null,
    val users: List<AlkkagiLobbyUserWire>? = null,
    val incoming: List<AlkkagiInviteWire>? = null,
    val outgoing: AlkkagiInviteWire? = null,
    val state: AlkkagiMatchWire? = null,
    val rubyBalance: Long? = null,
    val stakes: List<Long>? = null,
    /** 문이 열렸거나 내가 capable. false 면 '곧 열려요'. protocol 1 응답에는 없다. */
    val doorOpen: Boolean? = null,
    /** null = 가벼운 로비(덮지 않는다). */
    val record: AlkkagiRecordWire? = null,
    val matches: List<AlkkagiLiveMatchWire>? = null,
    val need: Long? = null,
    val have: Long? = null,
    val side: String? = null,
    val matchID: String? = null,
    val ranking: AlkkagiRankingWire? = null,
    val watch: AlkkagiWatchStateWire? = null,
) {
    object Serializer : SwiftDecodableSerializer<AlkkagiResponse>("AlkkagiResponse") {
        override fun deserialize(decoder: Decoder): AlkkagiResponse {
            val c = SwiftDecoding.keyed(decoder)
            var me: AlkkagiPeer? = null
            var ranking: AlkkagiRankingWire? = null
            if (c.contains("rows")) {
                val mine = c.decodeIfPresent("me", AlkkagiMyRankWire.serializer())
                val rows = if (c.raw("rows") == null || c.raw("rows") is JsonNull) emptyList() else c.decoder("rows").lossyList(AlkkagiRankEntryWire.serializer())
                ranking = AlkkagiRankingWire(rows, mine, c.doubleIfPresent("record_since_ms"))
            } else {
                me = c.decodeIfPresent("me", AlkkagiPeer.serializer())
            }
            var state: AlkkagiMatchWire? = null
            var watch: AlkkagiWatchStateWire? = null
            val rawState = c.raw("state")
            if (rawState != null && rawState !is JsonNull) {
                if (c.nested("state").contains("my_color")) state = c.decode("state", AlkkagiMatchWire.serializer())
                else watch = c.decode("state", AlkkagiWatchStateWire.serializer())
            }
            return AlkkagiResponse(
                status = c.decode("status", AlkkagiRPCStatus.serializer()),
                protocolVersion = c.longIfPresent("protocol") ?: 1,
                serverNowMs = c.double("server_now_ms"),
                me = me,
                users = c.decodeIfPresent("users", ListSerializer(AlkkagiLobbyUserWire.serializer())),
                incoming = c.decodeIfPresent("incoming", ListSerializer(AlkkagiInviteWire.serializer())),
                outgoing = c.decodeIfPresent("outgoing", AlkkagiInviteWire.serializer()),
                state = state,
                rubyBalance = c.longIfPresent("ruby_balance"),
                stakes = c.decodeIfPresent("stakes", ListSerializer(Long.serializer())),
                doorOpen = c.boolIfPresent("door_open"),
                record = c.decodeIfPresent("record", AlkkagiRecordWire.serializer()),
                matches = c.decodeIfPresent("matches", ListSerializer(AlkkagiLiveMatchWire.serializer())),
                need = c.longIfPresent("need"),
                have = c.longIfPresent("have"),
                side = c.stringIfPresent("side"),
                matchID = c.stringIfPresent("match_id"),
                ranking = ranking,
                watch = watch,
            )
        }
    }
}

/** 시험 · 도우미: 칸 이름이 이 파일 밖으로 새지 않게 쓰는 키 묶음(사용처 없음 — Swift `SwiftKeyed` 도우미 자리). */
internal fun SwiftKeyed.hasValue(key: String): Boolean = raw(key).let { it != null && it !is JsonNull }
