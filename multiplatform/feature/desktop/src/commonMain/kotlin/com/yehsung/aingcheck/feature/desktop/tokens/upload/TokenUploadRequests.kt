// W2-h3 토큰 업로드 요청 — core/net SupabaseWorkService.sendNoBody 위의 갈래 확장 함수(tokens.md §3: core/wire 에 없다).
// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift:621-735(upsertTokenUsage · sendTokenScanHeartbeat · upsertTokenUsageDaily)
// 옛 표 요청(upsertLegacyTokenUsage · fetchLegacyTokenUsageTotal :736-775)은 옮기지 않는다(W-3 #11).
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountUsage
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import kotlinx.serialization.builtins.ListSerializer

/** Windows 가 쓰는 표 둘(월·하트비트 = 기기 월 표, 일별 = 기기 일 표). 옛 (user, month) 한 줄 표는 여기 없다. */
object TokenUploadPaths {
    const val DEVICE_MONTHLY = "/rest/v1/token_usage_device_monthly"
    const val DEVICE_DAILY = "/rest/v1/token_usage_device_daily"
    const val MONTHLY_CONFLICT = "user_id,month,device_id"
    const val DAILY_CONFLICT = "user_id,day,device_id"
    /** merge-duplicates + return=minimal(수집 거부자의 0행도 성공). */
    const val PREFER = "resolution=merge-duplicates,return=minimal"
}

/** Swift `upsertTokenUsage` — 기기 월 표에 한 행. 본문 조립은 [TokenUsageUpsertRequest.of]. */
suspend fun SupabaseWorkService.upsertTokenUsage(
    accessToken: String,
    userID: String,
    usage: TokenUsageMonthly,
    deviceID: String,
    account: CodexAccountUsage? = null,
    accountStatus: CodexAccountProbeStatus? = null,
    diagnostics: CodexUsageDiagnostics? = null,
) {
    val body = TokenUsageUpsertRequest.of(userID, usage, deviceID, account, accountStatus, diagnostics)
    sendNoBody(
        path = TokenUploadPaths.DEVICE_MONTHLY,
        method = "POST",
        query = listOf("on_conflict" to TokenUploadPaths.MONTHLY_CONFLICT),
        body = encode(TokenUsageUpsertRequest.serializer(), body),
        accessToken = accessToken,
        prefer = TokenUploadPaths.PREFER,
    )
}

/** Swift `sendTokenScanHeartbeat` — 토큰 값과 무관하게 "스캔이 돌았고 파일을 N개 봤다"만. 본문 다섯 칸. */
suspend fun SupabaseWorkService.sendTokenScanHeartbeat(
    accessToken: String,
    userID: String,
    month: String,
    deviceID: String,
    files: Int,
    scannedAt: SwiftDate,
) {
    sendNoBody(
        path = TokenUploadPaths.DEVICE_MONTHLY,
        method = "POST",
        query = listOf("on_conflict" to TokenUploadPaths.MONTHLY_CONFLICT),
        body = encode(TokenScanHeartbeatRequest.serializer(), TokenScanHeartbeatRequest.of(userID, month, deviceID, files, scannedAt)),
        accessToken = accessToken,
        prefer = TokenUploadPaths.PREFER,
    )
}

/**
 * Swift `upsertTokenUsageDaily` — 배열 본문. ★ 키 집합이 **같은 행끼리만** 한 요청에 담는다(PGRST102). 묶음은 [TokenUsageDailyUpsertRow.shape]
 * 내림차순, 묶음 안 순서는 받은 순서 그대로. 빈 배열이면 요청 0. 첫 실패는 그대로 던진다(장부 갱신 없음 — 다음 주기가 전부 다시 보낸다).
 */
// INV-SupabaseWorkServiceMacOnly-283ea0c9 이식: 키 집합이 같은 행끼리만 한 요청(PGRST102) — 골든 requests/daily-shapes.
suspend fun SupabaseWorkService.upsertTokenUsageDaily(accessToken: String, rows: List<TokenUsageDailyUpsertRow>) {
    if (rows.isEmpty()) return
    val grouped = LinkedHashMap<Int, MutableList<TokenUsageDailyUpsertRow>>()
    for (row in rows) grouped.getOrPut(row.shape) { ArrayList() }.add(row)
    for (shape in grouped.keys.sortedDescending()) {
        val group = grouped[shape].orEmpty()
        if (group.isEmpty()) continue
        sendNoBody(
            path = TokenUploadPaths.DEVICE_DAILY,
            method = "POST",
            query = listOf("on_conflict" to TokenUploadPaths.DAILY_CONFLICT),
            body = encode(ListSerializer(TokenUsageDailyUpsertRow.serializer()), group),
            accessToken = accessToken,
            prefer = TokenUploadPaths.PREFER,
        )
    }
}
