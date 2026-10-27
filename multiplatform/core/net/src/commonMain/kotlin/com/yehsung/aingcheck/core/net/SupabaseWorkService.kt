// 원본: Sources/CheckCore/SupabaseWorkService.swift(맥 블록 밖 전부) · SupabaseWorkHTTP.swift · DuelRPC.swift @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.swiftTry
import io.ktor.client.HttpClient
import io.ktor.client.HttpClientConfig
import io.ktor.client.call.body
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.URLBuilder
import io.ktor.http.content.ByteArrayContent
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlin.concurrent.Volatile

/**
 * Supabase 와이어 서비스(Swift `actor SupabaseWorkService` 의 맥 블록 밖 몫 — C§3.2 C-2). supabase-kt 는 쓰지 않는다(§8-1 #14).
 *
 * - HTTP 클라이언트는 **주입**받는다: 앱은 단일 팩토리(`HttpEngineFactory.ktorClient(SupabaseWorkService.clientConfig)` — 재전송 끔,
 *   G §8-12)가 만든 것을, 시험은 MockEngine 을 넘긴다. 이 모듈은 엔진을 만들지 않는다(구조 시험 R3·R3c).
 * - 전 호출을 직렬화하지 않는다(Swift actor 재진입과 같다 — 팀 상태 GET 들은 병렬). 작은 상태(상점 번호 깃발)만 `@Volatile`.
 * - 오류 분류는 [ServiceErrorClassifier](23505 → 5xx → 429 → 본문). 2xx 가 아니면 던진다.
 * - 벽시계·uuid 는 주입(구조 시험 R2 — 조립 지점 밖에서 `Clock.System` 금지). 글자 규칙(NFC·보이는 글자)은 [WireTextRules].
 */
class SupabaseWorkService(
    /** 끝 `/` 없는 프로젝트 주소(시험은 `https://golden.invalid`). */
    val projectURL: String,
    val anonKey: String?,
    private val client: HttpClient,
    /** Swift `clock` — 상점 번호 깃발 만료와 캐시 무력화 값에 쓴다. */
    val clock: () -> SwiftDate,
    val text: WireTextRules,
    /** Swift `UUID().uuidString`(대문자) — 아바타 캐시 무력화 꼬리에만 쓴다. */
    private val newUUIDString: () -> String,
) {
    companion object {
        /**
         * 클라이언트 설정(C§4 #39 · `SupabaseWorkService.swift:19-33`): 요청 15초 · 리소스 30초. 캐시는 붙이지 않는다(Ktor 기본 = 캐시 없음).
         * 2xx 가 아니어도 예외로 바꾸지 않는다(분류는 [ServiceErrorClassifier] 가 한다).
         */
        val clientConfig: HttpClientConfig<*>.() -> Unit = {
            expectSuccess = false
            install(HttpTimeout) {
                socketTimeoutMillis = 15_000
                requestTimeoutMillis = 30_000
            }
        }

        const val gomokuDeadlockCode = "40P01"
        const val teamWeeklyLeaderboardPath = "/rest/v1/rpc/team_weekly_leaderboard"
        const val miniGameAllTimeBoardPath = "/rest/v1/rpc/minigame_alltime_board"
        const val blockUserPath = "/rest/v1/rpc/block_user"
        const val unblockUserPath = "/rest/v1/rpc/unblock_user"
        const val listBlocksPath = "/rest/v1/rpc/list_blocks"
        const val reportContentPath = "/rest/v1/rpc/report_content"
        const val messageHistoryWithReadsPath = "/rest/v1/rpc/message_history_with_reads"
        const val messageUnreadSummaryPath = "/rest/v1/rpc/message_unread_summary"
        const val markMessagesReadPath = "/rest/v1/rpc/mark_messages_read"
        const val messageHistoryWithPokesPath = "/rest/v1/rpc/message_history_with_pokes"
        const val markConversationReadPath = "/rest/v1/rpc/mark_conversation_read"
        const val appUserCharactersPath = "/rest/v1/rpc/app_user_characters"
        const val characterGiftPendingPath = "/rest/v1/rpc/character_gift_pending"
        const val claimCharacterGiftPath = "/rest/v1/rpc/claim_character_gift"
        const val gachaPullPath = "/rest/v1/rpc/gacha_pull"
        const val gachaExchangePath = "/rest/v1/rpc/gacha_exchange"
        const val achievementsStatusPath = "/rest/v1/rpc/achievements_status"
        const val achievementClaimPath = "/rest/v1/rpc/achievement_claim"
        const val dailyMissionClaimPath = "/rest/v1/rpc/daily_mission_claim"
        const val weeklyWorkStatusPath = "/rest/v1/rpc/weekly_work_status"
        const val weeklyWorkClaimPath = "/rest/v1/rpc/weekly_work_claim"
        const val sendMegaphonePath = "/rest/v1/rpc/send_megaphone"
        const val megaphoneInfoPath = "/rest/v1/rpc/megaphone_info"
        const val aiLimitsPath = "/rest/v1/ai_limits"
    }

    // ------------------------------------------------------------------ HTTP 바탕(SupabaseWorkHTTP.swift)

    /** 응답 한 건(상태코드 + 본문 바이트). */
    class RawResponse(val statusCode: Int, val body: ByteArray)

    /** 요청 본문 인코딩(Swift `encoder.encode(body)` — 키는 @SerialName, nil Optional 은 뺀다). */
    fun <B> encode(serializer: SerializationStrategy<B>, body: B): ByteArray = SwiftJson.encode(serializer, body).encodeToByteArray()

    fun encode(element: JsonElement): ByteArray = element.toString().encodeToByteArray()

    /** 응답 디코드(Swift `decoder.decode` — convertFromSnakeCase 규칙, C-X3). */
    fun <T> decode(deserializer: DeserializationStrategy<T>, data: ByteArray): T = SwiftJson.decode(deserializer, data.decodeToString())

    /** 응답 원문 JSON(타입이 W1-c rules 쪽에 있는 RPC — 그쪽이 읽는다). */
    fun decodeRaw(data: ByteArray): JsonElement = SwiftJson.parse(data.decodeToString())

    /** Swift `url(path:queryItems:)`. 쿼리는 이름·값 쌍 순서 그대로(같은 이름 둘 — `ended_at` — 도 그대로). */
    fun url(path: String, query: List<Pair<String, String>>): String {
        val builder = URLBuilder(projectURL + path)
        for ((k, v) in query) builder.parameters.append(k, v)
        return builder.buildString()
    }

    /**
     * Swift `send` — 헤더 다섯(apikey · Authorization(access 또는 anon) · Accept · Prefer · 본문 있을 때 Content-Type).
     * anon 키가 없으면 [SupabaseWorkServiceError.MissingAnonKey](시험 빌드에는 키가 없다 — C§6 세 겹 잠금 ①).
     */
    suspend fun send(
        path: String,
        method: String,
        query: List<Pair<String, String>> = emptyList(),
        body: ByteArray?,
        accessToken: String?,
        prefer: String?,
    ): ByteArray {
        val response = rawRequest(path, method, query, body, "application/json", accessToken, prefer, emptyMap())
        if (response.statusCode !in 200..299) throw serviceError(response.statusCode, response.body)
        return response.body
    }

    /** Swift `sendNoBody` — 응답 본문을 버린다. */
    suspend fun sendNoBody(
        path: String,
        method: String,
        query: List<Pair<String, String>> = emptyList(),
        body: ByteArray?,
        accessToken: String,
        prefer: String?,
    ) {
        send(path, method, query, body, accessToken, prefer)
    }

    /** Swift `sendData` — 본문 바이트와 Content-Type 을 그대로(사진·todo_sync). 토큰은 언제나 사용자 것. */
    suspend fun sendData(
        path: String,
        method: String,
        query: List<Pair<String, String>> = emptyList(),
        body: ByteArray,
        contentType: String,
        accessToken: String,
        extraHeaders: Map<String, String> = emptyMap(),
    ): ByteArray {
        val response = rawRequest(path, method, query, body, contentType, accessToken, null, extraHeaders)
        if (response.statusCode !in 200..299) throw serviceError(response.statusCode, response.body)
        return response.body
    }

    /** 상태코드를 보고 직접 가르는 자리(대결 RPC 의 40P01 재시도 · 사진 지우기). */
    suspend fun rawRequest(
        path: String,
        method: String,
        query: List<Pair<String, String>>,
        body: ByteArray?,
        contentType: String,
        accessToken: String?,
        prefer: String?,
        extraHeaders: Map<String, String>,
    ): RawResponse {
        val key = anonKey ?: throw SupabaseWorkServiceError.MissingAnonKey
        val response = client.request(url(path, query)) {
            this.method = HttpMethod.parse(method)
            header("apikey", key)
            header("Authorization", "Bearer ${accessToken ?: key}")
            header("Accept", "application/json")
            if (prefer != null) header("Prefer", prefer)
            for ((name, value) in extraHeaders) header(name, value)
            if (body != null) setBody(ByteArrayContent(body, ContentType.parse(contentType)))
        }
        return RawResponse(response.status.value, response.body<ByteArray>())
    }

    fun serviceError(statusCode: Int, data: ByteArray): SupabaseWorkServiceError = ServiceErrorClassifier.classify(statusCode, data)

    /** Swift `parseDate` — 소수초 포매터 먼저, 실패하면 기본 포매터(C§4 #30). */
    fun parseDate(value: String): SwiftDate? = SwiftISO8601.parse(value)

    /** Swift `dateFormatter.string(from:)`(초 단위 UTC). */
    fun formatDate(date: SwiftDate): String = SwiftISO8601.format(date)

    /** PostgREST 오류 본문의 `code`(40P01 판정). 못 읽으면 null. */
    fun postgrestErrorCode(data: ByteArray): String? =
        swiftTry { decode(PostgrestCodeEnvelope.serializer(), data).code }

    @Serializable
    internal data class PostgrestCodeEnvelope(@kotlinx.serialization.SerialName("code") val code: String? = null)

    /**
     * 1:1 대결 RPC 공용 몸통(DuelRPC.swift · 오목 `gomokuRPC` · 체스 `chessRPC` 가 같은 모양): POST 한 번 + 교착(40P01)이면
     * **정확히 한 번** 다시(C§4 #25). 두 번째도 교착이면 그 오류를 던진다.
     */
    suspend fun <T> duelRPC(
        name: String,
        body: ByteArray,
        accessToken: String,
        response: DeserializationStrategy<T>,
        retriesDeadlockOnce: Boolean = false,
    ): T {
        var attempt = 0
        while (true) {
            attempt += 1
            val r = rawRequest("/rest/v1/rpc/$name", "POST", emptyList(), body, "application/json", accessToken, null, emptyMap())
            if (r.statusCode in 200..299) return decode(response, r.body)
            if (retriesDeadlockOnce && attempt == 1 && postgrestErrorCode(r.body) == gomokuDeadlockCode) continue
            throw serviceError(r.statusCode, r.body)
        }
    }

    // ------------------------------------------------------------------ 상점 능력 번호 깃발(C§4 #9)

    /**
     * 상점 RPC 의 `p_protocol` 서명을 서버가 모른다는 사실을 **증명한 시각**(null = 모른다/다시 물을 때).
     * INV-SupabaseWorkService-56894129 이식: Bool 이 아니라 시각이다 — 영구 깃발은 db push 뒤에도 그 실행 동안 옛 모양만 보낸다.
     * INV-SupabaseWorkService-d052ad8a 이식: 5분([com.yehsung.aingcheck.core.wire.models.ShopWire.shopProtocolRecheckInterval])이 지나면 새 모양을 다시 묻는다.
     * INV-SupabaseWorkService-76edd6c3 이식: "404 당 되묻기 한 번"은 순차 호출 이야기다 — 동시 첫 호출은 각자 404 를 맞아도 둔다
     *   (첫 질문을 직렬화하면 그 자리를 잘못 풀 때 상점이 영구 정지한다). 그래서 잠금 없이 `@Volatile` 하나다.
     */
    @Volatile
    internal var shopProtocolUnsupportedAt: SwiftDate? = null

    /** Swift `UUID().uuidString.prefix(8)`(대문자 16진 8자). */
    internal fun newUUIDStringPrefix8(): String = newUUIDString().take(8)
}
