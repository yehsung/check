// 원본: Sources/CheckCore/SupabaseWorkServiceBlocks.swift:105-255 · SupabaseWorkServiceMessageReads.swift:107-196 · SupabaseWorkServiceCharacter.swift:33-42 · AppUserCharacters.swift:77-111 · MessagePokeLog.swift:1-207·314-336(전선 · microsecondsSinceEpoch — 배정표 W1-d 몫 1–313 + 서비스가 부르는 한 함수) @ 1b8260d
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// ---------------------------------------------------------------- 차단 · 신고

@Serializable
data class BlockUserRequest(@SerialName("p_user") val pUser: String)

/** Swift `ContentReportRequest` — 다섯 키를 **언제나** 싣는다(nil 은 null — 서버 오버로드가 키 집합으로 갈린다). */
@Serializable(with = ContentReportRequest.Serializer::class)
data class ContentReportRequest(
    val pTarget: String,
    val pReason: String,
    val pDetail: String?,
    val pMessageID: String?,
    val pBlock: Boolean,
) {
    object Serializer : KSerializer<ContentReportRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("ContentReportRequest")
        override fun serialize(encoder: Encoder, value: ContentReportRequest) {
            (encoder as JsonEncoder).encodeJsonElement(
                JsonObject(
                    mapOf(
                        "p_target" to JsonPrimitive(value.pTarget),
                        "p_reason" to JsonPrimitive(value.pReason),
                        "p_detail" to (value.pDetail?.let { JsonPrimitive(it) } ?: JsonNull),
                        "p_message_id" to (value.pMessageID?.let { JsonPrimitive(it) } ?: JsonNull),
                        "p_block" to JsonPrimitive(value.pBlock),
                    ),
                ),
            )
        }
        override fun deserialize(decoder: Decoder): ContentReportRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** Swift `BlockedUserRow`(list_blocks 행) — id·시각 칸 이름이 서버 판마다 달라 둘 이상을 차례로 본다. */
@Serializable(with = BlockedUserRow.Serializer::class)
data class BlockedUserRow(
    val userID: String?,
    val displayName: String?,
    val avatarUrl: String?,
    val createdAt: String?,
    val createdEpoch: Long?,
) {
    object Serializer : SwiftDecodableSerializer<BlockedUserRow>("BlockedUserRow") {
        override fun deserialize(decoder: Decoder): BlockedUserRow {
            val c = SwiftDecoding.keyed(decoder)
            return BlockedUserRow(
                userID = c.stringIfPresent("user_id") ?: c.stringIfPresent("blocked") ?: c.stringIfPresent("id"),
                displayName = c.stringIfPresent("display_name"),
                avatarUrl = c.stringIfPresent("avatar_url"),
                createdAt = c.stringIfPresent("created_at") ?: c.stringIfPresent("blocked_at"),
                createdEpoch = c.longIfPresent("created_epoch") ?: c.longIfPresent("blocked_epoch"),
            )
        }
    }
}

/** Swift `BlockedUser`(표시). */
data class BlockedUser(val userID: String, val name: String, val avatarURL: String?, val blockedAt: SwiftDate?) {
    val id: String get() = userID
}

/** Swift `ContentReportReason`. */
enum class ContentReportReason(val rawValue: String) {
    spam("spam"), harassment("harassment"), inappropriate("inappropriate"), other("other");

    val id: String get() = rawValue
    val label: String
        get() = when (this) {
            spam -> "스팸"; harassment -> "욕설·괴롭힘"; inappropriate -> "부적절한 내용"; other -> "기타"
        }
}

// ---------------------------------------------------------------- 내 캐릭터 · 모두의 캐릭터

/** Swift `CharacterSyncProfileRow`(profiles?select=character). */
@Serializable
data class CharacterSyncProfileRow(@SerialName("character") val character: String? = null)

/** Swift `CharacterSyncFetchError`. */
sealed class CharacterSyncFetchError(message: String) : Exception(message) {
    data object NoProfileRow : CharacterSyncFetchError("noProfileRow")
}

/**
 * Swift `AppUserCharacterRow`(app_user_characters 행) — 객체가 아니면 빈 행, 칸마다 lossy. user_id 는 앞뒤 공백을 자르고
 * 소문자로(비면 null). 접기·경합 규약(INV-AppUserCharacters-*)은 디렉터리(W2-b `AppUserCharacterStore`)의 몫이다.
 */
@Serializable(with = AppUserCharacterRow.Serializer::class)
data class AppUserCharacterRow(val userId: String?, val character: String?) {
    object Serializer : SwiftDecodableSerializer<AppUserCharacterRow>("AppUserCharacterRow") {
        override fun deserialize(decoder: Decoder): AppUserCharacterRow {
            val c = swiftTry { SwiftDecoding.keyed(decoder) } ?: return AppUserCharacterRow(null, null)
            return AppUserCharacterRow(userId = normalizedUserID(c.lossyString("user_id")), character = c.lossyString("character"))
        }
    }

    companion object {
        /** Swift `AppUserCharacterDirectory.normalizedUserID` — 공백을 자르고 비면 null, 소문자. */
        fun normalizedUserID(raw: String?): String? {
            val trimmed = raw?.let(::swiftTrim) ?: return null
            if (trimmed.isEmpty()) return null
            return trimmed.lowercase()
        }
    }
}

// ---------------------------------------------------------------- 읽음 표시(message_history_with_reads · 요약 · mark)

@Serializable
data class MessageHistoryReadsRow(
    @SerialName("id") val id: String? = null,
    @SerialName("from_user") val fromUser: String? = null,
    @SerialName("to_user") val toUser: String? = null,
    @SerialName("body") val body: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("is_mine") val isMine: Boolean? = null,
    @SerialName("peer_user_id") val peerUserId: String? = null,
    @SerialName("peer_display_name") val peerDisplayName: String? = null,
    @SerialName("peer_avatar_url") val peerAvatarUrl: String? = null,
    @SerialName("created_epoch") val createdEpoch: Long? = null,
    @SerialName("read_by_peer") val readByPeer: Boolean? = null,
    @SerialName("unread") val unread: Boolean? = null,
)

/** mark_messages_read 본문 — `p_through` 가 null 이면 키째 뺀다(합성 인코더). */
@Serializable
data class MessageReadMarkRequest(
    @SerialName("p_peer") val pPeer: String,
    @SerialName("p_through") val pThrough: String? = null,
)

@Serializable
data class MessageReadMarkResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("advanced") val advanced: Boolean? = null,
    @SerialName("unread") val unread: Long? = null,
) {
    val isOK: Boolean get() = status == "ok"
}

@Serializable
data class MessageUnreadSummaryResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("total") val total: Long? = null,
    @SerialName("peers") val peers: List<Peer>? = null,
) {
    @Serializable
    data class Peer(
        @SerialName("peer_user_id") val peerUserId: String? = null,
        @SerialName("count") val count: Long? = null,
        @SerialName("last_epoch_ms") val lastEpochMs: Double? = null,
    )

    /** ok 일 때만. 빈 id·0 이하 count 는 버리고, total 이 없으면 행 합. */
    val summary: MessageUnreadSummary?
        get() {
            if (status != "ok") return null
            val rows = (peers ?: emptyList()).mapNotNull { peer ->
                val id = peer.peerUserId
                val count = peer.count
                if (id.isNullOrEmpty() || count == null || count <= 0) return@mapNotNull null
                MessageUnreadPeer(peerUserID = id, count = count, lastMessageAt = peer.lastEpochMs?.let { SwiftDate(it / 1000) })
            }
            return MessageUnreadSummary(total = maxOf(0L, total ?: rows.sumOf { it.count }), peers = rows)
        }
}

data class MessageUnreadSummary(val total: Long, val peers: List<MessageUnreadPeer>) {
    val unreadPeerIDs: Set<String> get() = peers.map { it.peerUserID }.toSet()

    /** 차단한 사람 등을 빼고 다시 센다(뺄 것이 없으면 그대로). */
    fun excluding(userIDs: Set<String>): MessageUnreadSummary {
        if (userIDs.isEmpty()) return this
        val kept = peers.filter { it.peerUserID !in userIDs }
        if (kept.size == peers.size) return this
        return MessageUnreadSummary(total = kept.sumOf { it.count }, peers = kept)
    }
}

data class MessageUnreadPeer(val peerUserID: String, val count: Long, val lastMessageAt: SwiftDate?)

// ---------------------------------------------------------------- 찌르기 기록(v0.3.65 — message_history_with_pokes · mark_conversation_read)

/** Swift `MessagePokeLogKind` — 서버 kind(poke·normal → poke, ultra → ultra). 모르면 null. */
enum class MessagePokeLogKind(val rawValue: String) {
    poke("poke"), ultra("ultra");

    companion object {
        fun of(serverKind: String?): MessagePokeLogKind? = when (serverKind?.let(::swiftTrimSpaces)) {
            "poke", "normal" -> poke
            "ultra" -> ultra
            else -> null
        }
    }
}

/** Swift `trimmingCharacters(in: .whitespaces)`(줄바꿈은 자르지 않는다 — Z* + 탭). */
fun swiftTrimSpaces(s: String): String {
    fun ws(c: Char) = when (c.code) {
        0x09, 0x20, 0xA0, 0x1680, in 0x2000..0x200A, 0x202F, 0x205F, 0x3000 -> true
        else -> false
    }
    var start = 0
    var end = s.length
    while (start < end && ws(s[start])) start++
    while (end > start && ws(s[end - 1])) end--
    return s.substring(start, end)
}

/** Swift `MessagePokeLogEntry`(대화 안 찌르기 한 줄). */
data class MessagePokeLogEntry(
    val id: String,
    val peerUserID: String,
    val peerName: String,
    val peerAvatarURL: String? = null,
    val createdAt: SwiftDate,
    val isMine: Boolean,
    val kind: MessagePokeLogKind,
    val isUnread: Boolean? = null,
)

/**
 * Swift `MessageHistoryWithPokesRow` — 칸마다 lossy. `created_epoch` 는 정수 → 실수(반올림) → 글자 순으로 읽는다.
 */
@Serializable(with = MessageHistoryWithPokesRow.Serializer::class)
data class MessageHistoryWithPokesRow(
    val id: String? = null,
    val fromUser: String? = null,
    val toUser: String? = null,
    val body: String? = null,
    val createdAt: String? = null,
    val isMine: Boolean? = null,
    val peerUserId: String? = null,
    val peerDisplayName: String? = null,
    val peerAvatarUrl: String? = null,
    val createdEpoch: Long? = null,
    val readByPeer: Boolean? = null,
    val unread: Boolean? = null,
    val kind: String? = null,
) {
    object Serializer : SwiftDecodableSerializer<MessageHistoryWithPokesRow>("MessageHistoryWithPokesRow") {
        override fun deserialize(decoder: Decoder): MessageHistoryWithPokesRow {
            val c = SwiftDecoding.keyed(decoder)
            val epoch = c.lossyLong("created_epoch")
                ?: c.lossyDouble("created_epoch")?.takeIf { it.isFinite() }?.let { swiftRoundedToLong(it) }
                ?: c.lossyString("created_epoch")?.let { swiftIntParse(it) }
            return MessageHistoryWithPokesRow(
                id = c.lossyString("id"),
                fromUser = c.lossyString("from_user"),
                toUser = c.lossyString("to_user"),
                body = c.lossyString("body"),
                createdAt = c.lossyString("created_at"),
                isMine = c.lossyBool("is_mine"),
                peerUserId = c.lossyString("peer_user_id"),
                peerDisplayName = c.lossyString("peer_display_name"),
                peerAvatarUrl = c.lossyString("peer_avatar_url"),
                createdEpoch = epoch,
                readByPeer = c.lossyBool("read_by_peer"),
                unread = c.lossyBool("unread"),
                kind = c.lossyString("kind"),
            )
        }
    }
}

/** Swift `Double.rounded()`(0.5 는 0 에서 먼 쪽) → Int. Kotlin `roundToLong` 은 +∞ 쪽이라 다르다(C§2.5). */
fun swiftRoundedToLong(x: Double): Long {
    val t = kotlin.math.truncate(x)
    // x − trunc(x) 는 유한 Double 에서 정확하다 → 0.5 경계를 정확히 가른다(0.49999999999999994 는 내림).
    val frac = kotlin.math.abs(x - t)
    return (if (frac >= 0.5) t + kotlin.math.sign(x) else t).toLong()
}

/** Swift `Int(String)` — 부호 하나 + ASCII 숫자만, 범위 밖이면 null. */
fun swiftIntParse(s: String): Long? {
    if (s.isEmpty()) return null
    val body = if (s[0] == '+' || s[0] == '-') s.substring(1) else s
    if (body.isEmpty() || !body.all { it in '0'..'9' }) return null
    return s.toLongOrNull()
}

/** Swift `MessagePokeLossyRow` — 행 하나가 깨지면 그 행만 버린다(배열은 산다). */
@Serializable(with = MessagePokeLossyRow.Serializer::class)
data class MessagePokeLossyRow(val row: MessageHistoryWithPokesRow?) {
    object Serializer : SwiftDecodableSerializer<MessagePokeLossyRow>("MessagePokeLossyRow") {
        override fun deserialize(decoder: Decoder): MessagePokeLossyRow =
            MessagePokeLossyRow(swiftTry { MessageHistoryWithPokesRow.serializer().deserialize(decoder) })
    }
}

/** Swift `MessageHistoryWithPokes` — 메시지 · 찌르기 · 서버 순서표(id → 순위). */
data class MessageHistoryWithPokes(
    val messages: List<MessageHistoryEntry>,
    val pokes: List<MessagePokeLogEntry>,
    val chronology: Map<String, Long>,
)

/** mark_conversation_read 본문 — 둘 다 null 이면 키를 뺀다(합성 인코더). */
@Serializable
data class MessageConversationReadMarkRequest(
    @SerialName("p_peer") val pPeer: String,
    @SerialName("p_through_message") val pThroughMessage: String? = null,
    @SerialName("p_through_poke") val pThroughPoke: String? = null,
)

@Serializable
data class MessageConversationReadMarkResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("advanced") val advanced: Boolean? = null,
    @SerialName("unread") val unread: Long? = null,
    @SerialName("poke_advanced") val pokeAdvanced: Boolean? = null,
    @SerialName("poke_unread") val pokeUnread: Long? = null,
) {
    val isOK: Boolean get() = status == "ok"
}

/**
 * Swift `MessagePokeLogRules.microsecondsSinceEpoch` — `"…T01:02:03.123456+00:00"` → 마이크로초 epoch. 소수부는 **직접** 읽는다
 * (ISO 포매터는 밀리초에서 자른다). 초 부분은 주입한 파서가 읽는다. 서비스의 순서표가 부르므로 와이어에 둔다(배정표 W2-b 규칙의 한 함수).
 */
fun microsecondsSinceEpoch(text: String, wholeSeconds: (String) -> SwiftDate?): Long? {
    val tee = text.indexOf('T')
    if (tee < 0) return null
    var base = text
    var fraction = ""
    val dot = text.indexOf('.', tee)
    if (dot >= 0) {
        val afterDot = dot + 1
        var digitsEnd = afterDot
        while (digitsEnd < text.length && text[digitsEnd] in '0'..'9') digitsEnd++
        fraction = text.substring(afterDot, digitsEnd)
        base = text.substring(0, dot) + text.substring(digitsEnd)
    }
    val date = wholeSeconds(base) ?: return null
    val padded = (fraction + "000000").take(6)
    val micros = padded.toLongOrNull() ?: 0
    return swiftRoundedToLong(date.timeIntervalSince1970) * 1_000_000 + micros
}
