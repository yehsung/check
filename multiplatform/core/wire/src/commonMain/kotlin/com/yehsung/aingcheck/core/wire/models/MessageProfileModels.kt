// 원본: Sources/CheckCore/SupabaseWorkModels.swift:1417-1616(콕 디렉터리·공개 설정)·1757-1913(PokeSendResponse·TakenPokeRow)·2347-2805(메시지·이력·프로필 칸·릴리스·공지·별명) · CheckCore/StatusMessage.swift:95-170(전선 모양) @ 1b8260d
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
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

// ---------------------------------------------------------------- 콕 디렉터리(app_user_directory)

/**
 * Swift `PokeDirectoryRow` — 메시지 가능 여부는 새 칸 `message_capable` 을 먼저, 없으면 옛 `can_receive_message`.
 */
// INV-SupabaseWorkModels-27bf4155 이식: 직접 짠 디코더 — 칸을 더하면 CodingKey 와 디코드 줄을 함께(여기선 Serializer 한 곳).
@Serializable(with = PokeDirectoryRow.Serializer::class)
data class PokeDirectoryRow(
    val userId: String,
    val displayName: String,
    val avatarUrl: String? = null,
    val isWorking: Boolean,
    val canReceiveMessage: Boolean? = null,
    val center: String? = null,
    val statusMessage: String? = null,
) {
    object Serializer : SwiftDecodableSerializer<PokeDirectoryRow>("PokeDirectoryRow") {
        override fun deserialize(decoder: Decoder): PokeDirectoryRow {
            val c = SwiftDecoding.keyed(decoder)
            return PokeDirectoryRow(
                userId = c.string("user_id"),
                displayName = c.string("display_name"),
                avatarUrl = c.stringIfPresent("avatar_url"),
                isWorking = c.bool("is_working"),
                canReceiveMessage = c.boolIfPresent("message_capable") ?: c.boolIfPresent("can_receive_message"),
                center = c.stringIfPresent("center"),
                statusMessage = c.stringIfPresent("status_message"),
            )
        }
    }
}

// INV-SupabaseWorkModels-306d1d36 이식: center 는 서버값이 아니라 이미 변환된 화면 글자(toPokeDirectoryEntries 한 곳에서 CenterLabel.display).
/** Swift `PokeDirectoryEntry`(표시). 메시지 가능 칸을 모르면(옛 서버) 받을 수 있다고 본다. */
data class PokeDirectoryEntry(
    val userID: String,
    val name: String,
    val avatarURL: String?,
    val isWorking: Boolean,
    val canReceiveMessage: Boolean = true,
    val center: String? = null,
    val statusMessage: String? = null,
) {
    val id: String get() = userID
}

/** 행 → 표시(센터는 화면 글자로, 상태메시지는 보이는 글자가 있을 때만). */
fun List<PokeDirectoryRow>.toPokeDirectoryEntries(text: WireTextRules): List<PokeDirectoryEntry> = map { row ->
    PokeDirectoryEntry(
        userID = row.userId,
        name = row.displayName,
        avatarURL = row.avatarUrl,
        isWorking = row.isWorking,
        canReceiveMessage = row.canReceiveMessage ?: true,
        center = CenterLabel.display(row.center),
        statusMessage = text.statusMessageDisplay(row.statusMessage),
    )
}

/**
 * 콕 목록 네 무리 정렬(v0.3.65): 안 읽음 → 근무 중(`workKnown` 일 때만) → 이름(`localizedStandardCompare` = [Collation]) → userID.
 * 규칙이지만 와이어 파일에 있다(hasVisibleContent 와 같은 처리). 정렬 표 골든은 W2-b `messages` 가 낸다(배정표).
 */
// INV-SupabaseWorkModels-ff1fcccd 이식: 두 인자(unreadPeerIDs · workKnown) 모두 기본값을 두지 않는다.
fun List<PokeDirectoryEntry>.sortedForPokeDisplay(
    unreadPeerIDs: Set<String>,
    workKnown: Boolean,
    collation: Collation,
): List<PokeDirectoryEntry> = sortedWith { l, r ->
    val lu = l.userID in unreadPeerIDs
    val ru = r.userID in unreadPeerIDs
    when {
        lu != ru -> if (lu) -1 else 1
        workKnown && l.isWorking != r.isWorking -> if (l.isWorking) -1 else 1
        else -> {
            val byName = collation.compare(l.name, r.name)
            if (byName != 0) byName else l.userID.compareTo(r.userID)
        }
    }
}

/** Swift `PokeKind` — 서버 원시값 → 갈래(모르면 normal). */
enum class PokeKind(val rawValue: String) {
    normal("normal"), ultra("ultra"), message("message");

    companion object {
        fun of(rawServerValue: String?): PokeKind = when (rawServerValue) {
            "ultra" -> ultra
            "message" -> message
            else -> normal
        }
    }
}

/** Swift `PokeSendResponse`(콕·메시지 보내기 응답 — status 만 필수). */
@Serializable(with = PokeSendResponse.Serializer::class)
data class PokeSendResponse(
    val status: String,
    val retryAfterSeconds: Long? = null,
    val resetAfterSeconds: Long? = null,
    val ultraRemaining: Long? = null,
    val ultraBalance: Long? = null,
    val ring: String? = null,
    val maxLength: Long? = null,
) {
    val ultraRemainingForDisplay: Long? get() = ultraRemaining?.let { maxOf(0L, it) }
    val ultraBalanceForDisplay: Long? get() = (ultraBalance ?: ultraRemaining)?.let { maxOf(0L, it) }

    object Serializer : SwiftDecodableSerializer<PokeSendResponse>("PokeSendResponse") {
        override fun deserialize(decoder: Decoder): PokeSendResponse {
            val c = SwiftDecoding.keyed(decoder)
            return PokeSendResponse(
                status = c.string("status"),
                retryAfterSeconds = c.longIfPresent("retry_after_seconds"),
                resetAfterSeconds = c.longIfPresent("reset_after_seconds"),
                ultraRemaining = c.longIfPresent("ultra_remaining"),
                ultraBalance = c.longIfPresent("ultra_balance"),
                ring = c.stringIfPresent("ring"),
                // INV-SupabaseWorkModels-0f970b7f 이식: 이 줄을 빼고 키만 더하면 값은 영원히 null 이다.
                maxLength = c.longIfPresent("max_length"),
            )
        }
    }
}

/** Swift `PokeSendOutcome`. */
sealed interface PokeSendOutcome {
    data object Ok : PokeSendOutcome
    data class Cooldown(val retryAfterSeconds: Long) : PokeSendOutcome
    data object NotWorking : PokeSendOutcome
    data object TargetNotWorking : PokeSendOutcome
    data class UltraUsedToday(val resetAfterSeconds: Long) : PokeSendOutcome
    data object TargetFocused : PokeSendOutcome
    data object TargetOnPhone : PokeSendOutcome
    data object Invalid : PokeSendOutcome

    companion object {
        fun of(response: PokeSendResponse): PokeSendOutcome = when (response.status) {
            "ok" -> Ok
            "cooldown" -> Cooldown(maxOf(1L, response.retryAfterSeconds ?: 60))
            "not_working" -> NotWorking
            "target_not_working" -> TargetNotWorking
            "ultra_used_today" -> UltraUsedToday(maxOf(1L, response.resetAfterSeconds ?: 3600))
            "target_focused" -> TargetFocused
            "target_on_phone" -> TargetOnPhone
            else -> Invalid
        }
    }
}

/** Swift `TakenPokeRow`(take_pokes 응답 행 — 데스크톱 drain 이 받는다). */
@Serializable
data class TakenPokeRow(
    @SerialName("id") val id: String,
    @SerialName("from_user") val fromUser: String,
    @SerialName("from_display_name") val fromDisplayName: String,
    @SerialName("from_avatar_url") val fromAvatarUrl: String? = null,
    @SerialName("created_epoch") val createdEpoch: Long,
    @SerialName("kind") val kind: String? = null,
    @SerialName("body") val body: String? = null,
    @SerialName("from_character") val fromCharacter: String? = null,
)

// ---------------------------------------------------------------- 메시지

@Serializable
data class SendMessageRequest(
    @SerialName("p_to") val pTo: String,
    @SerialName("p_body") val pBody: String,
)

// INV-SupabaseWorkModels-7b2172c0 이식: cooldown · target_outdated 갈래는 없다(죽은 가지 — 되살리면 화면에 카운트다운이 돌아온다).
/** Swift `MessageSendOutcome`. */
sealed interface MessageSendOutcome {
    data object Ok : MessageSendOutcome
    data object Invalid : MessageSendOutcome
    data object Blackout : MessageSendOutcome
    data object NotWorking : MessageSendOutcome
    data object NotText : MessageSendOutcome
    data object TooLong : MessageSendOutcome
    data object TargetFocused : MessageSendOutcome
    data object TargetNotWorking : MessageSendOutcome
    data object Flood : MessageSendOutcome

    companion object {
        fun of(response: PokeSendResponse): MessageSendOutcome = when (response.status) {
            "ok" -> Ok
            "blackout" -> Blackout
            "not_working" -> NotWorking
            "not_text" -> NotText
            "too_long" -> TooLong
            "target_not_working" -> TargetNotWorking
            "target_focused" -> TargetFocused
            "flood" -> Flood
            else -> Invalid
        }
    }
}

@Serializable
data class MessageHistoryRequest(
    @SerialName("p_hours") val pHours: Long,
    @SerialName("p_limit") val pLimit: Long,
)

/** Swift `MessageHistoryRow`: Decodable, Equatable. */
@Serializable
data class MessageHistoryRow(
    @SerialName("id") val id: String,
    @SerialName("from_user") val fromUser: String? = null,
    @SerialName("to_user") val toUser: String? = null,
    @SerialName("body") val body: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("is_mine") val isMine: Boolean? = null,
    @SerialName("peer_user_id") val peerUserId: String? = null,
    @SerialName("peer_display_name") val peerDisplayName: String? = null,
    @SerialName("peer_avatar_url") val peerAvatarUrl: String? = null,
    @SerialName("created_epoch") val createdEpoch: Long? = null,
)

// INV-SupabaseWorkModels-3666309f 이식: body 는 사람이 쓴 문장 — 로그·진단 글자로 흘리지 않는다(이 모듈엔 로그가 없다).
/** Swift `MessageHistoryEntry`(표시 한 줄). readByPeer 는 내 메시지에만, isUnread 는 받은 메시지에만. */
data class MessageHistoryEntry(
    val id: String,
    val peerUserID: String,
    val peerName: String,
    val peerAvatarURL: String?,
    val body: String,
    val createdAt: SwiftDate,
    val isMine: Boolean,
    val readByPeer: Boolean? = null,
    val isUnread: Boolean? = null,
)

// ---------------------------------------------------------------- 프로필 칸

/** Swift `ProfilePrivacyRow`: Decodable, Equatable. */
@Serializable
data class ProfilePrivacyRow(
    @SerialName("token_usage_public") val tokenUsagePublic: Boolean? = null,
    @SerialName("token_usage_collect") val tokenUsageCollect: Boolean? = null,
    @SerialName("focus_mode") val focusMode: Boolean? = null,
    @SerialName("minigame_public") val minigamePublic: Boolean? = null,
)

/** Swift `ProfilePrivacyUpdateRequest`: Encodable. */
@Serializable
data class ProfilePrivacyUpdateRequest(
    @SerialName("token_usage_public") val tokenUsagePublic: Boolean,
)

/** Swift `ProfileMiniGamePublicUpdateRequest`: Encodable. */
@Serializable
data class ProfileMiniGamePublicUpdateRequest(
    @SerialName("minigame_public") val minigamePublic: Boolean,
)

/** Swift `ProfileCenterRow`: Decodable, Equatable. */
@Serializable
data class ProfileCenterRow(
    @SerialName("center") val center: String? = null,
)

/** Swift `AppLatestRelease`: Decodable, Equatable, Sendable. */
@Serializable
data class AppLatestRelease(
    @SerialName("v") val v: Long? = null,
    @SerialName("version") val version: String? = null,
    @SerialName("build") val build: Long? = null,
    @SerialName("notes") val notes: List<String>? = null,
    @SerialName("published_at") val publishedAt: String? = null,
)

// INV-SupabaseWorkModels-0a4ac1a5 이식: profiles.center 의 갱신 요청 모델은 일부러 없다(읽기 ProfileCenterRow 만).
/** Swift `ProfileStatusMessageRow`(내 상태메시지 GET — 별도 GET 이다, 칸이 없는 서버에서 다른 요청을 죽이지 않게). */
@Serializable
data class ProfileStatusMessageRow(@SerialName("status_message") val statusMessage: String? = null)

/** Swift `SetStatusMessageRequest` — nil 이어도 키를 싣는다(`{"p_text": null}` = 지우기). */
@Serializable(with = SetStatusMessageRequest.Serializer::class)
data class SetStatusMessageRequest(val pText: String?) {
    object Serializer : KSerializer<SetStatusMessageRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("SetStatusMessageRequest")
        override fun serialize(encoder: Encoder, value: SetStatusMessageRequest) {
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(mapOf("p_text" to (value.pText?.let { JsonPrimitive(it) } ?: JsonNull))))
        }
        override fun deserialize(decoder: Decoder): SetStatusMessageRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

@Serializable
data class SetStatusMessageResponse(
    @SerialName("status") val status: String,
    @SerialName("status_message") val statusMessage: String? = null,
    @SerialName("max_length") val maxLength: Long? = null,
)

/**
 * Swift `AppNotice`(app_current_notice) — id·title·body 를 앞뒤 공백 잘라 비면 디코드 실패, 링크 둘은 비면 null.
 * Swift CodingKey `linkURL = "linkUrl"` 은 convertFromSnakeCase 뒤 `link_url` 과 같은 칸이다.
 */
@Serializable(with = AppNotice.Serializer::class)
data class AppNotice(
    val id: String,
    val title: String,
    val body: String,
    val linkURL: String? = null,
    val linkLabel: String? = null,
) {
    object Serializer : SwiftDecodableSerializer<AppNotice>("AppNotice") {
        override fun deserialize(decoder: Decoder): AppNotice {
            val c = SwiftDecoding.keyed(decoder)
            val id = swiftTrim(c.string("id"))
            val title = swiftTrim(c.string("title"))
            val body = swiftTrim(c.string("body"))
            if (id.isEmpty() || title.isEmpty() || body.isEmpty()) {
                throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "${c.path}.id", "공지의 id·title·body 는 비면 안 된다")
            }
            return AppNotice(
                id = id, title = title, body = body,
                linkURL = c.stringIfPresent("link_url")?.let(::swiftTrim)?.ifEmpty { null },
                linkLabel = c.stringIfPresent("link_label")?.let(::swiftTrim)?.ifEmpty { null },
            )
        }
    }
}

/**
 * Swift `trimmingCharacters(in: .whitespacesAndNewlines)` 의 **명시 집합**(C§2.5 — Kotlin `trim()` 과 집합이 다를 수 있다):
 * Unicode White_Space 25자 + U+0085(NEL). Foundation `whitespacesAndNewlines` = Z* 범주 + 탭·줄바꿈 류.
 */
fun swiftTrim(s: String): String {
    var start = 0
    var end = s.length
    while (start < end && isSwiftWhitespaceOrNewline(s[start])) start++
    while (end > start && isSwiftWhitespaceOrNewline(s[end - 1])) end--
    return s.substring(start, end)
}

private fun isSwiftWhitespaceOrNewline(c: Char): Boolean = when (c.code) {
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 -> true
    else -> false
}

// ---------------------------------------------------------------- 별명

@Serializable
data class SetDisplayNameRequest(@SerialName("p_name") val pName: String)

@Serializable
data class DisplayNameChangeResponse(
    @SerialName("status") val status: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("retry_after_seconds") val retryAfterSeconds: Long? = null,
    @SerialName("max_length") val maxLength: Long? = null,
)

/** Swift `DisplayNameChangeOutcome`. 쿨다운 기본 7일, 길이 기본 `displayNameMaxLength`(12). */
sealed interface DisplayNameChangeOutcome {
    data class Ok(val name: String) : DisplayNameChangeOutcome
    data object Unchanged : DisplayNameChangeOutcome
    data object Taken : DisplayNameChangeOutcome
    data class Cooldown(val retryAfterSeconds: Long) : DisplayNameChangeOutcome
    data class TooLong(val maxLength: Long) : DisplayNameChangeOutcome
    data object Empty : DisplayNameChangeOutcome
    data object Invalid : DisplayNameChangeOutcome

    companion object {
        /** Swift `CheckCoreShared.displayNameMaxLength`(서버 set_display_name 의 max_len 과 같은 값). */
        const val displayNameMaxLength: Long = 12

        fun of(response: DisplayNameChangeResponse): DisplayNameChangeOutcome = when (response.status) {
            "ok" -> Ok(response.displayName ?: "")
            "unchanged" -> Unchanged
            "taken" -> Taken
            "cooldown" -> Cooldown(maxOf(1L, response.retryAfterSeconds ?: 604_800))
            "invalid_long" -> TooLong(maxOf(1L, response.maxLength ?: displayNameMaxLength))
            "invalid_empty" -> Empty
            else -> Invalid
        }
    }
}

@Serializable
data class DisplayNameChangedAtRow(@SerialName("display_name_changed_at") val displayNameChangedAt: String? = null)
