// W2-g2 찌르기 전선 — Swift Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 808-835(sendPoke·sendUltraPoke) · 864-904(takePokes)
// · SupabaseWorkModels.swift 1584(PokeSendRequest) · 1764(TakePokesRequest). 데스크톱 전용이라 core 를 고치지 않고 확장 함수로 둔다.
// 골든: contract/golden/desktop-poke/requests.json(경로·본문 바이트·PGRST202 재호출).
package com.yehsung.aingcheck.feature.desktop.poke.net

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.EmptyBody
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.models.PokeSendResponse
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** poke_user · ultra_poke_user 본문 `{p_to}`(두 RPC 가 같은 본문을 쓴다). */
@Serializable
data class PokeSendRequest(@SerialName("p_to") val pTo: String)

/** take_pokes 본문. 이 앱은 **언제나 true** 를 싣는다(P12 — 빼면 메시지를 못 받는다). */
@Serializable
data class TakePokesRequest(@SerialName("p_message_capable") val pMessageCapable: Boolean)

object PokeRpcPaths {
    const val POKE_USER: String = "/rest/v1/rpc/poke_user"
    /** poke_user 의 오버로드가 아니라 다른 이름의 함수다(PostgREST 모호성). */
    const val ULTRA_POKE_USER: String = "/rest/v1/rpc/ultra_poke_user"
    const val TAKE_POKES: String = "/rest/v1/rpc/take_pokes"
}

/** Swift `sendPoke(accessToken:to:)` — 응답은 jsonb 단일 객체. */
suspend fun SupabaseWorkService.sendPoke(accessToken: String, to: String): PokeSendResponse =
    decode(
        PokeSendResponse.serializer(),
        send(PokeRpcPaths.POKE_USER, "POST", body = encode(PokeSendRequest.serializer(), PokeSendRequest(to)), accessToken = accessToken, prefer = null),
    )

/** Swift `sendUltraPoke(accessToken:to:)` — 발신 몫만(지갑 호출은 UltraWalletTrigger 로, W2-g4). */
suspend fun SupabaseWorkService.sendUltraPoke(accessToken: String, to: String): PokeSendResponse =
    decode(
        PokeSendResponse.serializer(),
        send(PokeRpcPaths.ULTRA_POKE_USER, "POST", body = encode(PokeSendRequest.serializer(), PokeSendRequest(to)), accessToken = accessToken, prefer = null),
    )

/**
 * Swift `takePokes(accessToken:)` — P12: `p_message_capable:true` 를 언제나 싣는다. PGRST202(`DatabaseSchemaMissing`)일 때만
 * 같은 경로에 `{}` 로 한 번 더 부른다(그 시점엔 아무것도 소비되지 않았다). 그 판정을 **캐시하지 않는다** — 상주 앱이라
 * db push 가 끝난 뒤에도 옛 모양에 눌러앉으면 재시작 전까지 메시지를 영영 못 받는다.
 */
suspend fun SupabaseWorkService.takePokes(accessToken: String): List<TakenPokeRow> {
    val data = try {
        send(PokeRpcPaths.TAKE_POKES, "POST", body = encode(TakePokesRequest.serializer(), TakePokesRequest(true)), accessToken = accessToken, prefer = null)
    } catch (e: SupabaseWorkServiceError) {
        if (e != SupabaseWorkServiceError.DatabaseSchemaMissing) throw e
        send(PokeRpcPaths.TAKE_POKES, "POST", body = encode(EmptyBody.serializer(), EmptyBody()), accessToken = accessToken, prefer = null)
    }
    return decode(ListSerializer(TakenPokeRow.serializer()), data)
}
