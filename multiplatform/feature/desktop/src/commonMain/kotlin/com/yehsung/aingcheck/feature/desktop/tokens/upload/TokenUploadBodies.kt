// W2-h3 토큰 업로드 본문 · 일별 순수 계산.
// 원본: Sources/CheckCore/SupabaseWorkModels.swift:613-900(TokenUsageUpsertRequest · TokenScanHeartbeatRequest · TokenUsageDailyUpsertRow)
//       Sources/CheckCore/SupabaseWorkServiceMacOnly.swift:630-641(계정 칸 조립) · Sources/check/WorkTimerStoreSync.swift:2425-2518(일별 순수 계산)
// 옛 표(token_usage_monthly) 본문 TokenUsageLegacyUpsertRequest 는 옮기지 않는다(W-3 #11 — Windows 는 읽지도 쓰지도 않는다).
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountUsage
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import com.yehsung.aingcheck.feature.desktop.tokens.scan.TokenMonthKeys
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * token_usage_device_monthly upsert 본문(Swift TokenUsageUpsertRequest, convertToSnakeCase).
 * ★ null 칸은 **키째 빠진다**(SwiftJson.encoder explicitNulls=false = 합성 Encodable 의 encodeIfPresent). 0 을 싣지 마라 —
 *   merge-duplicates upsert 는 본문에 온 칸만 SET 하므로 0 은 서버의 다른 값(계정·진단)을 민다(SupabaseWorkModels.swift 주석).
 */
@Serializable
data class TokenUsageUpsertRequest(
    @SerialName("user_id") val userId: String,
    @SerialName("month") val month: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("claude_input") val claudeInput: Long,
    @SerialName("claude_output") val claudeOutput: Long,
    @SerialName("claude_cache_read") val claudeCacheRead: Long,
    @SerialName("claude_cache_creation") val claudeCacheCreation: Long,
    @SerialName("codex_input") val codexInput: Long,
    @SerialName("codex_output") val codexOutput: Long,
    @SerialName("total") val total: Long,
    @SerialName("today_total") val todayTotal: Long,
    @SerialName("today_date") val todayDate: String,
    @SerialName("codex_cache_read") val codexCacheRead: Long,
    // INV-SupabaseWorkModels-4eaa032e 이식: 계정·진단 칸은 서버 마이그레이션이 클라 배포 **전에** 있어야 한다(없으면 400) — Windows 는 tokenUpload 깃발로 닫혀 있다.
    @SerialName("codex_account_month") val codexAccountMonth: Long? = null,
    @SerialName("codex_account_lifetime") val codexAccountLifetime: Long? = null,
    @SerialName("codex_account_at") val codexAccountAt: String? = null,
    @SerialName("codex_account_last_day") val codexAccountLastDay: String? = null,
    @SerialName("codex_account_status") val codexAccountStatus: Int? = null,
    @SerialName("codex_diag_files_total") val codexDiagFilesTotal: Long? = null,
    @SerialName("codex_diag_files_month") val codexDiagFilesMonth: Long? = null,
    @SerialName("codex_diag_events_month") val codexDiagEventsMonth: Long? = null,
    @SerialName("codex_diag_max_delta") val codexDiagMaxDelta: Long? = null,
    @SerialName("codex_diag_carry_files") val codexDiagCarryFiles: Long? = null,
    @SerialName("codex_diag_carry_total") val codexDiagCarryTotal: Long? = null,
    @SerialName("codex_diag_dup_events") val codexDiagDupEvents: Long? = null,
    @SerialName("codex_diag_dup_tokens") val codexDiagDupTokens: Long? = null,
    @SerialName("codex_diag_final_sum") val codexDiagFinalSum: Long? = null,
    @SerialName("codex_diag_dedup_total") val codexDiagDedupTotal: Long? = null,
    @SerialName("codex_diag_drops") val codexDiagDrops: Long? = null,
    @SerialName("codex_diag_top_file") val codexDiagTopFile: Long? = null,
    /** = 진단의 appBuild — Windows 는 version.properties windowsBuild(tokens.md §2 ⑤). */
    @SerialName("codex_diag_build") val codexDiagBuild: Long? = null,
    @SerialName("codex_diag_legacy_total") val codexDiagLegacyTotal: Long? = null,
    @SerialName("codex_diag_big_delta_count") val codexDiagBigDeltaCount: Long? = null,
    @SerialName("codex_diag_big_delta_total") val codexDiagBigDeltaTotal: Long? = null,
    @SerialName("codex_diag_max_delta_gap_s") val codexDiagMaxDeltaGapS: Long? = null,
    @SerialName("codex_diag_big_gap_median_s") val codexDiagBigGapMedianS: Long? = null,
    @SerialName("codex_diag_input_at_scan") val codexDiagInputAtScan: Long? = null,
    @SerialName("codex_diag_fork_files") val codexDiagForkFiles: Long? = null,
    @SerialName("codex_diag_fork_tokens") val codexDiagForkTokens: Long? = null,
    // INV-SupabaseWorkModels-69603d7a 이식: 안티그래비티 넷은 total 에 절대 더하지 않는다(total = TokenUsageMonthly.total).
    @SerialName("antigravity_input") val antigravityInput: Long? = null,
    @SerialName("antigravity_output") val antigravityOutput: Long? = null,
    @SerialName("antigravity_thinking") val antigravityThinking: Long? = null,
    @SerialName("antigravity_cache_read") val antigravityCacheRead: Long? = null,
) {
    companion object {
        /**
         * Swift `upsertTokenUsage` 의 본문 조립(SupabaseWorkServiceMacOnly.swift:630-667).
         * ★ 미로그인(3)이면 스냅샷 네 값(month·lifetime·at·last_day)을 **싣지 않는다** — 서버 가드(스냅샷 없는 status 3 만 계정 밖)의 짝.
         * 계정도 상태도 없으면 계정 칸 다섯이 통째로 빠진다. 안티그래비티는 합 > 0 일 때만 네 키(Windows 는 집계 0 이라 늘 빠진다).
         */
        fun of(
            userId: String,
            usage: TokenUsageMonthly,
            deviceId: String,
            account: CodexAccountUsage?,
            accountStatus: CodexAccountProbeStatus?,
            diagnostics: CodexUsageDiagnostics?,
        ): TokenUsageUpsertRequest {
            val snapshot = if (accountStatus == CodexAccountProbeStatus.NOT_LOGGED_IN) null else account
            val hasAccountFields = !(account == null && accountStatus == null)
            val antigravity = usage.antigravityTotal > 0
            return TokenUsageUpsertRequest(
                userId = userId, month = usage.month, deviceId = deviceId,
                claudeInput = usage.claudeInput, claudeOutput = usage.claudeOutput,
                claudeCacheRead = usage.claudeCacheRead, claudeCacheCreation = usage.claudeCacheCreation,
                codexInput = usage.codexInput, codexOutput = usage.codexOutput,
                total = usage.total, todayTotal = usage.todayTotal, todayDate = usage.todayDate,
                codexCacheRead = usage.codexCacheRead,
                codexAccountMonth = if (hasAccountFields) snapshot?.monthTotal(usage.month) else null,
                codexAccountLifetime = if (hasAccountFields) snapshot?.lifetimeTokens else null,
                codexAccountAt = if (hasAccountFields) snapshot?.let { SwiftISO8601.format(it.fetchedAt) } else null,
                codexAccountLastDay = if (hasAccountFields) snapshot?.latestBucketDate(usage.month) else null,
                codexAccountStatus = if (hasAccountFields) accountStatus?.raw else null,
                codexDiagFilesTotal = diagnostics?.filesTotal,
                codexDiagFilesMonth = diagnostics?.filesMonth,
                codexDiagEventsMonth = diagnostics?.eventsMonth,
                codexDiagMaxDelta = diagnostics?.maxDelta,
                codexDiagCarryFiles = diagnostics?.carryFiles,
                codexDiagCarryTotal = diagnostics?.carryTotal,
                codexDiagDupEvents = diagnostics?.dupEvents,
                codexDiagDupTokens = diagnostics?.dupTokens,
                codexDiagFinalSum = diagnostics?.finalSum,
                codexDiagDedupTotal = diagnostics?.dedupTotal,
                codexDiagDrops = diagnostics?.drops,
                codexDiagTopFile = diagnostics?.topFile,
                codexDiagBuild = diagnostics?.appBuild,
                codexDiagLegacyTotal = diagnostics?.legacyTotal,
                codexDiagBigDeltaCount = diagnostics?.bigDeltaCount,
                codexDiagBigDeltaTotal = diagnostics?.bigDeltaTotal,
                codexDiagMaxDeltaGapS = diagnostics?.maxDeltaGapSeconds,
                codexDiagBigGapMedianS = diagnostics?.bigGapMedianSeconds,
                codexDiagInputAtScan = diagnostics?.let { usage.codexInput + usage.codexOutput },
                codexDiagForkFiles = diagnostics?.forkFiles,
                codexDiagForkTokens = diagnostics?.forkCopyTokens,
                antigravityInput = if (antigravity) usage.antigravityInput else null,
                antigravityOutput = if (antigravity) usage.antigravityOutput else null,
                antigravityThinking = if (antigravity) usage.antigravityThinking else null,
                antigravityCacheRead = if (antigravity) usage.antigravityCacheRead else null,
            )
        }
    }
}

/**
 * 스캐너 하트비트 본문(Swift TokenScanHeartbeatRequest).
 * ★ 다섯 칸뿐이다 — 토큰 칸을 절대 싣지 마라(합계 0 일 때도 나가므로 0 을 실으면 그 기기의 이번 달 누적치를 민다).
 */
// INV-SupabaseWorkServiceMacOnly-81c10cad 이식: 본문 다섯 칸뿐 — 시험 TokenUploadGateTest · 골든 requests/heartbeat 가 키 집합을 잠근다.
@Serializable
data class TokenScanHeartbeatRequest(
    @SerialName("user_id") val userId: String,
    @SerialName("month") val month: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("last_scan_at") val lastScanAt: String,
    @SerialName("scan_files") val scanFiles: Int,
) {
    companion object {
        fun of(userId: String, month: String, deviceId: String, files: Int, scannedAt: SwiftDate): TokenScanHeartbeatRequest =
            TokenScanHeartbeatRequest(userId, month, deviceId, SwiftISO8601.format(scannedAt), files)
    }
}

/** token_usage_device_daily 본문 한 줄(Swift TokenUsageDailyUpsertRow). null = 키 생략 = 서버 값 보존(0 을 싣지 마라). */
@Serializable
data class TokenUsageDailyUpsertRow(
    @SerialName("user_id") val userId: String,
    @SerialName("day") val day: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("claude_total") val claudeTotal: Long? = null,
    @SerialName("codex_total") val codexTotal: Long? = null,
    @SerialName("codex_utc_total") val codexUtcTotal: Long? = null,
    @SerialName("codex_account") val codexAccount: Long? = null,
    @SerialName("antigravity_total") val antigravityTotal: Long? = null,
) {
    /**
     * 묶음 키 = 옵셔널 **다섯**의 유무 비트(claude 16 · codex 8 · utc 4 · account 2 · antigravity 1).
     * ★ 새 옵셔널을 더하면 **반드시 여기에 비트를 더해라** — 키 집합이 다른 행이 한 요청에 섞이면 PostgREST 가 본문 전체를
     *   400 PGRST102 로 거절하고 장부가 갱신되지 않아 영구 고착된다(v0.2.41 리뷰 P0).
     */
    // INV-SupabaseWorkServiceMacOnly-ea2163b7 이식: 새 옵셔널을 더하면 비트도 더한다(음성 대조: codex 비트를 빼면 골든 daily-shapes 빨강).
    val shape: Int
        get() = (if (claudeTotal != null) 16 else 0) + (if (codexTotal != null) 8 else 0) + (if (codexUtcTotal != null) 4 else 0) +
            (if (codexAccount != null) 2 else 0) + (if (antigravityTotal != null) 1 else 0)
}

/** 일별 변경 게이트의 하루치 값(Swift TokenUsageDailyValue). null = 이 기기가 그 날의 그 값을 모른다 → 본문에서 키가 빠진다. */
data class TokenUsageDailyValue(
    val claude: Long?,
    val codex: Long?,
    val codexUTC: Long? = null,
    val codexAccount: Long?,
    val antigravity: Long? = null,
)

/** Swift `TokenUsageDailyUpload`(WorkTimerStoreSync.swift:2453-2518) — 월간 사용량 + 계정 스냅샷 → 일별 값. */
object TokenUsageDailyUpload {
    /**
     * 창(windowStartDay) 안 날짜별 값. 키 = claudeDaily ∪ codexDaily ∪ codexDailyUTC ∪ antigravityDaily ∪ 계정 버킷.
     * ① claude 는 claudeCompleteFrom 이후만 ② codex(KST) 는 현재 월만 ③ codexUTC 는 이 빌드 스냅샷 + UTC 보존 하한 **다음 날**부터
     * ④ 계정 버킷은 있는 날만(창 앞은 보내지 않는다) ⑤ 안티그래비티는 그 날 맵에 값이 있을 때만. 다섯 다 0/null 인 날은 뺀다.
     */
    fun values(usage: TokenUsageMonthly, account: CodexAccountUsage?): Map<String, TokenUsageDailyValue> {
        val windowStart = usage.windowStartDay
        val completeFrom = usage.claudeCompleteFrom
        val monthPrefix = usage.month + "-"
        val utcRetainFrom = TokenMonthKeys.utcRetainFromKey(usage.month) // W-6 #4: h1 공용 규칙
        val utcMapIsFromThisBuild = usage.windowStart.isNotEmpty()
        val buckets = account?.buckets ?: emptyMap()
        val keys = LinkedHashSet<String>().apply {
            addAll(usage.claudeDaily.keys); addAll(usage.codexDaily.keys); addAll(usage.codexDailyUTC.keys)
            addAll(usage.antigravityDaily.keys); addAll(buckets.keys)
        }
        val result = HashMap<String, TokenUsageDailyValue>()
        for (day in keys) {
            if (day < windowStart) continue
            val claudeKnown = completeFrom.isEmpty() || day >= completeFrom
            val codexKnown = day.startsWith(monthPrefix)
            val utcKnown = utcMapIsFromThisBuild && day > utcRetainFrom
            val antigravityKnown = day.startsWith(monthPrefix) && usage.antigravityDaily[day] != null
            val value = TokenUsageDailyValue(
                claude = if (claudeKnown) maxOf(0L, usage.claudeDaily[day] ?: 0L) else null,
                codex = if (codexKnown) maxOf(0L, usage.codexDaily[day] ?: 0L) else null,
                codexUTC = if (utcKnown) maxOf(0L, usage.codexDailyUTC[day] ?: 0L) else null,
                codexAccount = buckets[day]?.let { maxOf(0L, it) },
                antigravity = if (antigravityKnown) maxOf(0L, usage.antigravityDaily[day] ?: 0L) else null,
            )
            if ((value.claude ?: 0) > 0 || (value.codex ?: 0) > 0 || (value.codexUTC ?: 0) > 0 ||
                value.codexAccount != null || (value.antigravity ?: 0) > 0
            ) {
                result[day] = value
            }
        }
        return result
    }

    /** 마지막 성공 업로드와 값이 다른 날만(날짜 오름차순). 장부가 비어 있으면 전부. */
    fun changedDays(current: Map<String, TokenUsageDailyValue>, lastUploaded: Map<String, TokenUsageDailyValue>): List<String> =
        current.filter { (day, value) -> lastUploaded[day] != value }.keys.sorted()

    /** 요청 행(days 순서 그대로). values 에 없는 날은 건너뛴다. */
    fun rows(userID: String, deviceID: String, days: List<String>, values: Map<String, TokenUsageDailyValue>): List<TokenUsageDailyUpsertRow> =
        days.mapNotNull { day ->
            val v = values[day] ?: return@mapNotNull null
            TokenUsageDailyUpsertRow(userID, day, deviceID, v.claude, v.codex, v.codexUTC, v.codexAccount, v.antigravity)
        }
}
