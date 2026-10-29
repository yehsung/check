// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 835-847(buyUltra) · 906-921(syncUltraWallet) @ a90d8623
// SupabaseWorkService 확장 함수(poke.md §3 — 데스크톱 전용 호출은 갈래 안에 둔다. core/net 은 고치지 않는다).
package com.yehsung.aingcheck.feature.desktop.ultra.net

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError

object UltraRpcPaths {
    const val WALLET_SYNC: String = "/rest/v1/rpc/ultra_wallet_sync"
    const val BUY_ULTRA: String = "/rest/v1/rpc/buy_ultra"
}

/**
 * 지갑 동기(★U1 — **읽기가 아니다**: 밑바닥 보정·미션 적립이 이 호출 안에서 일어난다).
 * 기본 p_days_back=1(어제 몫 소급). 함수가 없는 서버(PGRST202 = databaseSchemaMissing)는 [SupabaseWorkServiceError.UltraWalletUnavailable] 로
 * 따로 던진다(U2).
 */
suspend fun SupabaseWorkService.syncUltraWallet(accessToken: String, daysBack: Int = 1): UltraWalletResponse {
    val data = try {
        send(
            UltraRpcPaths.WALLET_SYNC, "POST", emptyList(),
            encode(UltraWalletSyncRequest.serializer(), UltraWalletSyncRequest(daysBack)), accessToken, null,
        )
    } catch (e: SupabaseWorkServiceError) {
        if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) throw SupabaseWorkServiceError.UltraWalletUnavailable
        throw e
    }
    return decode(UltraWalletResponse.Serializer, data)
}

/** 울트라 찌르기를 산다(루비 → 울트라). 결과 판정은 서버 status 그대로(U5). */
suspend fun SupabaseWorkService.buyUltra(accessToken: String, count: Int): BuyUltraResponse {
    val data = send(
        UltraRpcPaths.BUY_ULTRA, "POST", emptyList(),
        encode(BuyUltraRequest.serializer(), BuyUltraRequest(count)), accessToken, null,
    )
    return decode(BuyUltraResponse.serializer(), data)
}
