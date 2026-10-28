// 원본: Sources/CheckCore/SupabaseWorkServiceBlocks.swift · SupabaseWorkServiceCharacter.swift · SupabaseWorkServiceMessageReads.swift · SupabaseWorkServiceTodoSync.swift · AppUserCharacters.swift:44-76 · CharacterGift.swift:218-268 · MessagePokeLog.swift:209-312 · Gacha.swift:330-370 · Achievements.swift:275-309 · DailyMissions.swift:194-213 · WeeklyWorkReward.swift:323-360 · Megaphone.swift:203-241 · CheckMobileKit/Session/MobileDeviceService.swift:86-165 · Session/MobilePhoneWorkService.swift:109-145 · Me/MeProfileService.swift · Me/MeAILimitsService.swift:91-139 @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.EmptyBody
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftClaimRequest
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftClaimResponse
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftPendingRequest
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftPendingResponse
import com.yehsung.aingcheck.core.wire.models.AILimitPrefsServerRow
import com.yehsung.aingcheck.core.wire.models.AILimitServerRow
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterRow
import com.yehsung.aingcheck.core.wire.models.BlockUserRequest
import com.yehsung.aingcheck.core.wire.models.BlockedUser
import com.yehsung.aingcheck.core.wire.models.BlockedUserRow
import com.yehsung.aingcheck.core.wire.models.CharacterSyncFetchError
import com.yehsung.aingcheck.core.wire.models.CharacterSyncProfileRow
import com.yehsung.aingcheck.core.wire.models.ClientReleaseRequest
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import com.yehsung.aingcheck.core.wire.models.ContentReportRequest
import com.yehsung.aingcheck.core.wire.models.GachaExchangeRequest
import com.yehsung.aingcheck.core.wire.models.GachaExchangeResponse
import com.yehsung.aingcheck.core.wire.models.GachaPullRequest
import com.yehsung.aingcheck.core.wire.models.GachaPullResponse
import com.yehsung.aingcheck.core.wire.models.InstallationRequest
import com.yehsung.aingcheck.core.wire.models.MeProfileCardRow
import com.yehsung.aingcheck.core.wire.models.MessageConversationReadMarkRequest
import com.yehsung.aingcheck.core.wire.models.MessageConversationReadMarkResponse
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessageHistoryReadsRow
import com.yehsung.aingcheck.core.wire.models.MessageHistoryRequest
import com.yehsung.aingcheck.core.wire.models.MessageHistoryWithPokes
import com.yehsung.aingcheck.core.wire.models.MessageHistoryWithPokesRow
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogEntry
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogKind
import com.yehsung.aingcheck.core.wire.models.MessagePokeLossyRow
import com.yehsung.aingcheck.core.wire.models.MessageReadMarkRequest
import com.yehsung.aingcheck.core.wire.models.MessageReadMarkResponse
import com.yehsung.aingcheck.core.wire.models.MessageUnreadSummaryResponse
import com.yehsung.aingcheck.core.wire.models.PhoneWorkResponse
import com.yehsung.aingcheck.core.wire.models.PhoneWorkStopRequest
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.core.wire.models.RegisterDeviceRequest
import com.yehsung.aingcheck.core.wire.models.RegisterDeviceResponse
import com.yehsung.aingcheck.core.wire.models.SendMegaphoneRequest
import com.yehsung.aingcheck.core.wire.models.SetPushPrefsRequest
import com.yehsung.aingcheck.core.wire.models.SetPushPrefsResponse
import com.yehsung.aingcheck.core.wire.models.TodoSyncRequest
import com.yehsung.aingcheck.core.wire.models.TodoSyncResponse
import com.yehsung.aingcheck.core.wire.models.UnregisterDeviceResponse
import com.yehsung.aingcheck.core.wire.models.achievementClaimBody
import com.yehsung.aingcheck.core.wire.models.microsecondsSinceEpoch
import com.yehsung.aingcheck.core.wire.models.swiftTrim
import com.yehsung.aingcheck.core.wire.models.swiftTrimSpaces
import com.yehsung.aingcheck.core.wire.models.weeklyWorkClaimBody
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement

private fun SupabaseWorkService.emptyBody(): ByteArray = encode(EmptyBody.serializer(), EmptyBody())

// ======================================================================== 차단 · 신고

suspend fun SupabaseWorkService.blockUser(accessToken: String, userID: String) {
    sendNoBody(SupabaseWorkService.blockUserPath, "POST", emptyList(), encode(BlockUserRequest.serializer(), BlockUserRequest(userID)), accessToken, null)
}

suspend fun SupabaseWorkService.unblockUser(accessToken: String, userID: String) {
    sendNoBody(SupabaseWorkService.unblockUserPath, "POST", emptyList(), encode(BlockUserRequest.serializer(), BlockUserRequest(userID)), accessToken, null)
}

/** 차단 목록 — id 없는 행은 버리고, 이름 폴백 '사용자', 시각은 epoch 우선. */
suspend fun SupabaseWorkService.fetchBlocks(accessToken: String): List<BlockedUser> {
    val data = send(SupabaseWorkService.listBlocksPath, "POST", emptyList(), emptyBody(), accessToken, null)
    return decode(ListSerializer(BlockedUserRow.serializer()), data).mapNotNull { r ->
        val id = r.userID
        if (id.isNullOrEmpty()) return@mapNotNull null
        BlockedUser(
            userID = id,
            name = r.displayName?.ifEmpty { null } ?: "사용자",
            avatarURL = SwiftURL.parse(r.avatarUrl),
            blockedAt = r.createdEpoch?.let { SwiftDate(it.toDouble()) } ?: r.createdAt?.let(::parseDate),
        )
    }
}

/** 신고 — 다섯 키 언제나(빈 상세·메시지 id 는 null 로). */
suspend fun SupabaseWorkService.reportContent(
    accessToken: String,
    targetUserID: String,
    reason: ContentReportReason,
    detail: String?,
    messageID: String?,
    alsoBlock: Boolean,
) {
    sendNoBody(
        SupabaseWorkService.reportContentPath, "POST", emptyList(),
        encode(
            ContentReportRequest.serializer(),
            ContentReportRequest(targetUserID, reason.rawValue, detail?.ifEmpty { null }, messageID?.ifEmpty { null }, alsoBlock),
        ),
        accessToken, null,
    )
}

// ======================================================================== 캐릭터

/** 내 장착 캐릭터(profiles?select=character). 행이 없으면 [CharacterSyncFetchError.NoProfileRow]. */
suspend fun SupabaseWorkService.fetchEquippedCharacter(accessToken: String, userID: String): String? {
    val data = send("/rest/v1/profiles", "GET", listOf("select" to "character", "id" to "eq.$userID"), null, accessToken, null)
    val row = decode(ListSerializer(CharacterSyncProfileRow.serializer()), data).firstOrNull() ?: throw CharacterSyncFetchError.NoProfileRow
    return row.character
}

/** 모두의 장착 캐릭터. 함수가 없으면(PGRST202 · 404) 빈 표 — user_id 없는 행은 버린다. */
suspend fun SupabaseWorkService.fetchAppUserCharacters(accessToken: String): List<AppUserCharacterRow> {
    val data = try {
        send(SupabaseWorkService.appUserCharactersPath, "POST", emptyList(), emptyBody(), accessToken, null)
    } catch (e: SupabaseWorkServiceError) {
        if (e == SupabaseWorkServiceError.DatabaseSchemaMissing || e == SupabaseWorkServiceError.InvalidResponse(404)) return emptyList()
        throw e
    }
    return decode(ListSerializer(AppUserCharacterRow.serializer()), data).filter { it.userId != null }
}

// ======================================================================== 케이크 선물(v0.3.66)

/** 받을 선물(status ok 일 때만). 함수가 없으면 null(서버 준비 전 — 선물 없음과 같다). */
suspend fun SupabaseWorkService.fetchCharacterGiftPending(accessToken: String, protocolVersion: Long): CharacterGiftOffer? {
    val data = try {
        send(
            SupabaseWorkService.characterGiftPendingPath, "POST", emptyList(),
            encode(CharacterGiftPendingRequest.serializer(), CharacterGiftPendingRequest(protocolVersion)), accessToken, null,
        )
    } catch (e: SupabaseWorkServiceError) {
        if (ServiceErrorClassifier.isMissingFunction(e)) return null
        throw e
    }
    return decode(CharacterGiftPendingResponse.serializer(), data).offer
}

suspend fun SupabaseWorkService.claimCharacterGift(accessToken: String, giftID: String, characterID: String, protocolVersion: Long): CharacterGiftClaimResponse {
    val data = send(
        SupabaseWorkService.claimCharacterGiftPath, "POST", emptyList(),
        encode(CharacterGiftClaimRequest.serializer(), CharacterGiftClaimRequest(giftID, characterID, protocolVersion)), accessToken, null,
    )
    return decode(CharacterGiftClaimResponse.serializer(), data)
}

// ======================================================================== 뽑기(request_id 는 결과를 모르는 실패면 쥔 채 재시도 — 호출부)

suspend fun SupabaseWorkService.gachaPull(accessToken: String, protocolVersion: Long, requestID: String): GachaPullResponse {
    val data = send(
        SupabaseWorkService.gachaPullPath, "POST", emptyList(),
        encode(GachaPullRequest.serializer(), GachaPullRequest(protocolVersion, requestID.lowercase())), accessToken, null,
    )
    return decode(GachaPullResponse.serializer(), data)
}

suspend fun SupabaseWorkService.gachaExchange(accessToken: String, characterID: String, protocolVersion: Long, requestID: String): GachaExchangeResponse {
    val data = send(
        SupabaseWorkService.gachaExchangePath, "POST", emptyList(),
        encode(GachaExchangeRequest.serializer(), GachaExchangeRequest(characterID, protocolVersion, requestID.lowercase())), accessToken, null,
    )
    return decode(GachaExchangeResponse.serializer(), data)
}

// ======================================================================== 메시지 읽음 · 찌르기 기록

suspend fun SupabaseWorkService.fetchMessageHistoryWithReads(accessToken: String, hours: Long, limit: Long): List<MessageHistoryEntry> {
    val data = send(
        SupabaseWorkService.messageHistoryWithReadsPath, "POST", emptyList(),
        encode(MessageHistoryRequest.serializer(), MessageHistoryRequest(minOf(24L, maxOf(1L, hours)), minOf(500L, maxOf(1L, limit)))),
        accessToken, null,
    )
    return decode(ListSerializer(MessageHistoryReadsRow.serializer()), data).mapNotNull { messageHistoryEntry(it) }
}

/**
 * 읽음 행 → 표시. INV-SupabaseWorkServiceMessageReads-728fdae2 이식: 옮김 규칙은 `fetchMessageHistory` 와 **같다**(본문 정규화 ·
 * 상대 없음 버림 · epoch 우선 · 이름 폴백) + readByPeer 는 내 메시지에만, unread 는 받은 메시지에만.
 */
fun SupabaseWorkService.messageHistoryEntry(row: MessageHistoryReadsRow): MessageHistoryEntry? {
    val id = row.id
    if (id.isNullOrEmpty()) return null
    val body = text.sanitized(row.body ?: "")
    if (!text.hasVisibleContent(body)) return null
    val peer = row.peerUserId
    if (peer.isNullOrEmpty()) return null
    val createdAt = row.createdEpoch?.let { SwiftDate(it.toDouble()) } ?: row.createdAt?.let(::parseDate) ?: return null
    val isMine = row.isMine ?: false
    return MessageHistoryEntry(
        id = id, peerUserID = peer, peerName = row.peerDisplayName?.ifEmpty { null } ?: "사용자", peerAvatarURL = SwiftURL.parse(row.peerAvatarUrl),
        body = body, createdAt = createdAt, isMine = isMine,
        readByPeer = if (isMine) row.readByPeer else null,
        isUnread = if (isMine) null else row.unread,
    )
}

suspend fun SupabaseWorkService.fetchMessageUnreadSummary(accessToken: String): MessageUnreadSummaryResponse {
    val data = send(SupabaseWorkService.messageUnreadSummaryPath, "POST", emptyList(), emptyBody(), accessToken, null)
    return decode(MessageUnreadSummaryResponse.serializer(), data)
}

suspend fun SupabaseWorkService.markMessagesRead(accessToken: String, peerUserID: String, throughMessageID: String?): MessageReadMarkResponse {
    val data = send(
        SupabaseWorkService.markMessagesReadPath, "POST", emptyList(),
        encode(MessageReadMarkRequest.serializer(), MessageReadMarkRequest(peerUserID, throughMessageID)), accessToken, null,
    )
    return decode(MessageReadMarkResponse.serializer(), data)
}

/** 찌르기를 끼운 대화(v0.3.65). 행 하나가 깨지면 그 행만 버린다(lossy 행). */
suspend fun SupabaseWorkService.fetchMessageHistoryWithPokes(accessToken: String, hours: Long, limit: Long): MessageHistoryWithPokes {
    val data = send(
        SupabaseWorkService.messageHistoryWithPokesPath, "POST", emptyList(),
        encode(MessageHistoryRequest.serializer(), MessageHistoryRequest(minOf(24L, maxOf(1L, hours)), minOf(500L, maxOf(1L, limit)))),
        accessToken, null,
    )
    val rows = decode(ListSerializer(MessagePokeLossyRow.serializer()), data).mapNotNull { it.row }
    return messageHistoryWithPokes(rows)
}

/**
 * 행 → 메시지·찌르기·순서표. kind 가 없거나 message 면 메시지(읽음 행 규칙 그대로), poke·normal·ultra 면 찌르기, 그 밖은 버린다.
 * 순서표: 서버 시각(마이크로초)이 다르면 그 순서, 같거나 모르면 응답 자리 순(같은 id 는 처음 것).
 */
fun SupabaseWorkService.messageHistoryWithPokes(rows: List<MessageHistoryWithPokesRow>): MessageHistoryWithPokes {
    val messages = mutableListOf<MessageHistoryEntry>()
    val pokes = mutableListOf<MessagePokeLogEntry>()
    data class Stamp(val id: String, val micros: Long?, val index: Int)
    val stamps = mutableListOf<Stamp>()
    rows.forEachIndexed { index, row ->
        val kind = row.kind?.let(::swiftTrimSpaces)
        if (kind == null || kind == "message") {
            val readsRow = MessageHistoryReadsRow(
                id = row.id, fromUser = row.fromUser, toUser = row.toUser, body = row.body, createdAt = row.createdAt,
                isMine = row.isMine, peerUserId = row.peerUserId, peerDisplayName = row.peerDisplayName,
                peerAvatarUrl = row.peerAvatarUrl, createdEpoch = row.createdEpoch, readByPeer = row.readByPeer, unread = row.unread,
            )
            val entry = messageHistoryEntry(readsRow) ?: return@forEachIndexed
            messages += entry
            stamps += Stamp(entry.id, serverMicros(row), index)
        } else {
            val pokeKind = MessagePokeLogKind.of(kind) ?: return@forEachIndexed
            val entry = pokeLogEntry(row, pokeKind) ?: return@forEachIndexed
            pokes += entry
            stamps += Stamp(entry.id, serverMicros(row), index)
        }
    }
    val ranked = stamps.sortedWith { l, r ->
        val lm = l.micros
        val rm = r.micros
        if (lm != null && rm != null && lm != rm) lm.compareTo(rm) else l.index.compareTo(r.index)
    }
    val chronology = LinkedHashMap<String, Long>()
    ranked.forEachIndexed { rank, stamp -> if (stamp.id !in chronology) chronology[stamp.id] = rank.toLong() }
    return MessageHistoryWithPokes(messages, pokes, chronology)
}

private fun SupabaseWorkService.pokeLogEntry(row: MessageHistoryWithPokesRow, kind: MessagePokeLogKind): MessagePokeLogEntry? {
    val id = row.id
    val peer = row.peerUserId
    if (id.isNullOrEmpty() || peer.isNullOrEmpty()) return null
    val createdAt = row.createdEpoch?.let { SwiftDate(it.toDouble()) } ?: row.createdAt?.let(::parseDate) ?: return null
    val isMine = row.isMine ?: false
    return MessagePokeLogEntry(
        id = id, peerUserID = peer, peerName = row.peerDisplayName?.ifEmpty { null } ?: "사용자", peerAvatarURL = SwiftURL.parse(row.peerAvatarUrl),
        createdAt = createdAt, isMine = isMine, kind = kind, isUnread = if (isMine) null else row.unread,
    )
}

private fun SupabaseWorkService.serverMicros(row: MessageHistoryWithPokesRow): Long? {
    val text = row.createdAt
    if (text != null) microsecondsSinceEpoch(text) { parseDate(it) }?.let { return it }
    return row.createdEpoch?.let { it * 1_000_000 }
}

/** 대화 읽음 표시(메시지·찌르기를 한 번에 — v0.3.65). null 인 쪽은 키를 뺀다. */
suspend fun SupabaseWorkService.markConversationRead(
    accessToken: String,
    peerUserID: String,
    throughMessageID: String?,
    throughPokeID: String?,
): MessageConversationReadMarkResponse {
    val data = send(
        SupabaseWorkService.markConversationReadPath, "POST", emptyList(),
        encode(MessageConversationReadMarkRequest.serializer(), MessageConversationReadMarkRequest(peerUserID, throughMessageID, throughPokeID)),
        accessToken, null,
    )
    return decode(MessageConversationReadMarkResponse.serializer(), data)
}

// ======================================================================== 할 일 동기화(본문 바이트 그대로 — C§4 #10: p_since_ms 는 null 이어도 싣는다)

suspend fun SupabaseWorkService.todoSync(accessToken: String, request: TodoSyncRequest): TodoSyncResponse {
    val data = sendData("/rest/v1/rpc/todo_sync", "POST", emptyList(), encode(request.rpcBody()), "application/json", accessToken)
    return decode(TodoSyncResponse.serializer(), data)
}

// ======================================================================== W1-c 응답 타입을 받는 RPC — 요청은 여기서, 읽기는 W1-c(rules 의 lossy 디코드)

/** achievements_status — 응답(AchievementStatus · daily 포함)은 W1-c `achievements`·`missions` 가 읽는다. */
suspend fun SupabaseWorkService.achievementsStatusRaw(accessToken: String): JsonElement =
    decodeRaw(send(SupabaseWorkService.achievementsStatusPath, "POST", emptyList(), emptyBody(), accessToken, null))

/** achievement_claim — key 가 null 이면 `{"p_key": null}`(받을 수 있는 것 전부). */
suspend fun SupabaseWorkService.achievementClaimRaw(accessToken: String, key: String?): JsonElement =
    decodeRaw(send(SupabaseWorkService.achievementClaimPath, "POST", emptyList(), encode(achievementClaimBody(key)), accessToken, null))

/** daily_mission_claim(v0.3.64) — 같은 본문 모양, 응답은 AchievementStatus(W1-c). */
suspend fun SupabaseWorkService.dailyMissionClaimRaw(accessToken: String, key: String?): JsonElement =
    decodeRaw(send(SupabaseWorkService.dailyMissionClaimPath, "POST", emptyList(), encode(achievementClaimBody(key)), accessToken, null))

suspend fun SupabaseWorkService.weeklyWorkStatusRaw(accessToken: String): JsonElement =
    decodeRaw(send(SupabaseWorkService.weeklyWorkStatusPath, "POST", emptyList(), emptyBody(), accessToken, null))

/** weekly_work_claim — 두 키를 언제나(nil 은 null). */
suspend fun SupabaseWorkService.weeklyWorkClaimRaw(accessToken: String, weekStart: String? = null, hours: Long? = null): JsonElement =
    decodeRaw(send(SupabaseWorkService.weeklyWorkClaimPath, "POST", emptyList(), encode(weeklyWorkClaimBody(weekStart, hours)), accessToken, null))

/** send_megaphone — 본문 검증(`MegaphoneBody.validate`)은 W1-c 가 먼저 한다. 여기엔 정규화한 글자가 온다. */
suspend fun SupabaseWorkService.sendMegaphoneRaw(accessToken: String, normalizedBody: String, requestID: String): JsonElement =
    decodeRaw(
        send(SupabaseWorkService.sendMegaphonePath, "POST", emptyList(), encode(SendMegaphoneRequest.serializer(), SendMegaphoneRequest(normalizedBody, requestID)), accessToken, null),
    )

suspend fun SupabaseWorkService.megaphoneInfoRaw(accessToken: String): JsonElement =
    decodeRaw(send(SupabaseWorkService.megaphoneInfoPath, "POST", emptyList(), emptyBody(), accessToken, null))

// ======================================================================== 기기 등록 · 릴리스(폰)

/** Swift `MobileDeviceRPC.isMissingFunction`(PGRST202 · 404). */
fun isMissingDeviceFunction(error: Throwable): Boolean =
    error == SupabaseWorkServiceError.DatabaseSchemaMissing || error == SupabaseWorkServiceError.InvalidResponse(404)

/** client_release(anon). `platform` 은 앱 정보에서 주입(C§3.2 C-2 — iOS 는 "ios"). */
suspend fun SupabaseWorkService.fetchClientRelease(platform: String): ClientReleaseResponse {
    val data = send("/rest/v1/rpc/client_release", "POST", emptyList(), encode(ClientReleaseRequest.serializer(), ClientReleaseRequest(platform)), null, null)
    return decode(ClientReleaseResponse.serializer(), data)
}

/** register_device(iOS 모양 — 토큰과 환경을 **짝으로**: 하나만 있으면 둘 다 뺀다, C§4 #33). */
suspend fun SupabaseWorkService.registerDevice(
    accessToken: String,
    platform: String,
    installationID: String,
    appBuild: Long,
    appVersion: String?,
    apnsToken: String?,
    apnsEnvironment: String?,
): RegisterDeviceResponse {
    val body = RegisterDeviceRequest(
        pInstallationId = installationID,
        pPlatform = platform,
        pAppBuild = appBuild,
        pAppVersion = appVersion,
        pApnsToken = if (apnsEnvironment == null) null else apnsToken,
        pApnsEnv = if (apnsToken == null) null else apnsEnvironment,
    )
    val data = send("/rest/v1/rpc/register_device", "POST", emptyList(), encode(RegisterDeviceRequest.serializer(), body), accessToken, null)
    return decode(RegisterDeviceResponse.serializer(), data)
}

suspend fun SupabaseWorkService.unregisterDevice(accessToken: String, installationID: String): UnregisterDeviceResponse {
    val data = send("/rest/v1/rpc/unregister_device", "POST", emptyList(), encode(InstallationRequest.serializer(), InstallationRequest(installationID)), accessToken, null)
    return decode(UnregisterDeviceResponse.serializer(), data)
}

suspend fun SupabaseWorkService.setPushPrefs(accessToken: String, installationID: String, prefs: PushPrefs): SetPushPrefsResponse {
    val data = send(
        "/rest/v1/rpc/set_push_prefs", "POST", emptyList(),
        encode(SetPushPrefsRequest.serializer(), SetPushPrefsRequest(installationID, prefs)), accessToken, null,
    )
    return decode(SetPushPrefsResponse.serializer(), data)
}

// ======================================================================== 폰 근무(본문에 시각·길이 0 — C§4 #12)

suspend fun SupabaseWorkService.startPhoneWork(accessToken: String): PhoneWorkResponse =
    decode(PhoneWorkResponse.serializer(), send("/rest/v1/rpc/work_phone_start", "POST", emptyList(), emptyBody(), accessToken, null))

suspend fun SupabaseWorkService.stopPhoneWork(accessToken: String, sessionID: String?): PhoneWorkResponse =
    decode(
        PhoneWorkResponse.serializer(),
        send("/rest/v1/rpc/work_phone_stop", "POST", emptyList(), encode(PhoneWorkStopRequest.serializer(), PhoneWorkStopRequest(sessionID?.lowercase())), accessToken, null),
    )

suspend fun SupabaseWorkService.touchPhoneWork(accessToken: String): PhoneWorkResponse =
    decode(PhoneWorkResponse.serializer(), send("/rest/v1/rpc/work_phone_touch", "POST", emptyList(), emptyBody(), accessToken, null))

// ======================================================================== 나

suspend fun SupabaseWorkService.fetchMyProfileCard(accessToken: String, userID: String): MeProfileCardRow? {
    val data = send("/rest/v1/profiles", "GET", listOf("select" to "display_name,avatar_url", "id" to "eq.$userID"), null, accessToken, null)
    return decode(ListSerializer(MeProfileCardRow.serializer()), data).firstOrNull()
}

/**
 * 내 AI 리밋(ai_limits 읽기 — 폰은 쓰지 않는다) — 요청과 행 디코드까지. **행을 거르지 않는다**: 관측 시각을 못 읽거나 기기 id 가 빈 행을
 * 버리는 일과 값 정규화(날짜 · 라벨 `AILimit*Contract`)는 core/stores me `AILimitFetchedRow.fromRows` **한 자리**다(Swift `fetchMyAILimits` 의
 * `compactMap` 하나 — 여기서도 거르면 그쪽 거름이 한 번도 돌지 않아 시험이 못 본다, 6차 c-fold 검증 지적). 앱은 core/stores
 * `service.fetchMyAILimits` 를 부른다.
 */
suspend fun SupabaseWorkService.fetchMyAILimitRows(accessToken: String, userID: String): List<AILimitServerRow> {
    // INV-MeAILimitsService-e8b002fa 이식: 이 select 는 device_label 칸이 있는 서버(20261008120000_ai_limits_devices)를 요구한다 — 없는 칸을 적으면
    // PostgREST 가 400 으로 응답 전체를 거절해 리밋 카드가 통째로 빈다. 그 마이그레이션이 올라간 서버에서만 나가는 빌드라 그대로 적는다.
    val data = send(
        SupabaseWorkService.aiLimitsPath, "GET",
        listOf(
            "select" to "device_id,device_label,provider,five_hour_percent,five_hour_resets_at,weekly_percent,weekly_resets_at,plan_label,observed_at",
            "user_id" to "eq.$userID",
            "order" to "observed_at.desc",
            "limit" to "60",
        ),
        null, accessToken, null,
    )
    return decode(ListSerializer(AILimitServerRow.serializer()), data)
}

/**
 * 계정이 고른 메인 맥(`ai_limits_prefs?select=main_device_id` — 폰 MeAILimitsStore 가 부르는 **읽기**). null = 아직 안 골랐다(행 0 개는 정상 —
 * 가입 트리거가 이 행을 만들지 않는다, throw 하지 않는다). 칸은 앞뒤 공백·줄바꿈을 걷고 비면 null.
 * 원본: Sources/CheckCore/SupabaseWorkServiceAILimits.swift:327-343(파일은 I 몫이지만 이 메서드는 폰이 부른다 — G5 태그는 메서드 단위).
 */
suspend fun SupabaseWorkService.fetchAILimitMainDeviceID(accessToken: String, userID: String): String? {
    val data = send(
        SupabaseWorkService.aiLimitsPrefsPath, "GET",
        listOf("select" to "main_device_id", "user_id" to "eq.$userID"),
        null, accessToken, null,
    )
    val raw = decode(ListSerializer(AILimitPrefsServerRow.serializer()), data).firstOrNull()?.mainDeviceId ?: return null
    return swiftTrim(raw).ifEmpty { null }
}
