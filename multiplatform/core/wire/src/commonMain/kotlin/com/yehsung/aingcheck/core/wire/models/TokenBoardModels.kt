// 원본: Sources/CheckCore/SupabaseWorkModels.swift:344-1059(MARK 팀원 이번 달 AI 토큰 보드 — 폰이 읽는 몫) @ 1b8260d
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder

/**
 * Swift `TokenBoardRow`(token_usage_board 응답 행). 직접 짠 디코드: 마이그레이션 전 옛 RPC 의 빠진 칸을 0/""/nil 로 접는다
 * (합성 디코더는 기본값을 무시하고 필수로 요구한다 — Swift 주석 그대로).
 */
@Serializable(with = TokenBoardRow.Serializer::class)
data class TokenBoardRow(
    val userId: String,
    val displayName: String,
    val avatarUrl: String?,
    val claudeInput: Long,
    val claudeOutput: Long,
    val claudeCacheRead: Long,
    val claudeCacheCreation: Long,
    val codexInput: Long,
    val codexOutput: Long,
    val total: Long,
    val todayTotal: Long = 0,
    val todayDate: String = "",
    val codexCacheRead: Long = 0,
    val codexAccountMonth: Long? = null,
    val codexEffective: Long? = null,
    val center: String? = null,
) {
    object Serializer : SwiftDecodableSerializer<TokenBoardRow>("TokenBoardRow") {
        override fun deserialize(decoder: Decoder): TokenBoardRow {
            val c = SwiftDecoding.keyed(decoder)
            return TokenBoardRow(
                userId = c.string("user_id"),
                displayName = c.string("display_name"),
                avatarUrl = c.stringIfPresent("avatar_url"),
                claudeInput = c.long("claude_input"),
                claudeOutput = c.long("claude_output"),
                claudeCacheRead = c.long("claude_cache_read"),
                claudeCacheCreation = c.long("claude_cache_creation"),
                codexInput = c.long("codex_input"),
                codexOutput = c.long("codex_output"),
                total = c.long("total"),
                todayTotal = c.longIfPresent("today_total") ?: 0,
                todayDate = c.stringIfPresent("today_date") ?: "",
                codexCacheRead = c.longIfPresent("codex_cache_read") ?: 0,
                codexAccountMonth = c.longIfPresent("codex_account_month"),
                codexEffective = c.longIfPresent("codex_effective"),
                center = c.stringIfPresent("center"),
            )
        }
    }
}

/**
 * Swift `TokenBoardEntry`(표시용 한 행). 캡션·툴팁 글자(`toolUsageLabel`·`detailTooltip`)는 숫자 표기
 * `TokenNumberFormatter`(W1-c rules/format)에 기대므로 그쪽(스토어·화면)에서 만든다 — 여기엔 숫자 판정만 둔다.
 */
data class TokenBoardEntry(
    val userID: String,
    val name: String,
    val avatarURL: String?,
    val total: Long,
    val claudeInput: Long,
    val claudeOutput: Long,
    val claudeCacheRead: Long,
    val claudeCacheCreation: Long,
    val codexInput: Long,
    val codexOutput: Long,
    val todayTotal: Long = 0,
    val todayDate: String = "",
    val codexCacheRead: Long = 0,
    val codexAccountMonth: Long? = null,
    val codexEffectiveFromServer: Long? = null,
    val center: String? = null,
) {
    val id: String get() = userID
    val claudeTotal: Long get() = claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation
    val codexLocalTotal: Long get() = codexInput + codexOutput

    /**
     * 순위에 쓰인 Codex 몫: 서버 `codex_effective` 가 있으면 그것, 옛 RPC 면 `max(로컬, 계정)` 미러.
     * ⚠️ 이 max 폴백은 **순위판 캡션 전용**이다 — 개인 표시에 쓰지 마라(`hasServerCodexEffective` 가 참일 때만 서버 행).
     */
    // INV-SupabaseWorkModels-e849cbbf 이식: max 폴백은 순위판 캡션 전용 — 개인 표시는 hasServerCodexEffective 일 때만 서버 행.
    val codexEffective: Long get() = codexEffectiveFromServer ?: maxOf(codexLocalTotal, codexAccountMonth ?: 0)
    val hasServerCodexEffective: Boolean get() = codexEffectiveFromServer != null

    /** 안티그래비티 몫 = total − claude − codexEffective 의 잔차(음수는 0). */
    val antigravityEffective: Long get() = maxOf(0L, total - claudeTotal - codexEffective)

    val totalIsAccountDriven: Boolean
        get() {
            val account = codexAccountMonth ?: return false
            if (account <= 0) return false
            return codexEffectiveFromServer != null || account > codexLocalTotal
        }

    /** todayDate 가 오늘(KST 키)일 때만 todayTotal, 아니면 0. */
    fun todayDelta(currentDate: String): Long = if (todayDate == currentDate) todayTotal else 0
}

/** 행 → 표시 엔트리(결합 불필요 — 행 자체가 완결). 정렬은 [sortedByTotalDescending]. */
fun List<TokenBoardRow>.toTokenBoardEntries(): List<TokenBoardEntry> = map { row ->
    TokenBoardEntry(
        userID = row.userId,
        name = row.displayName,
        avatarURL = row.avatarUrl,
        total = row.total,
        claudeInput = row.claudeInput,
        claudeOutput = row.claudeOutput,
        claudeCacheRead = row.claudeCacheRead,
        claudeCacheCreation = row.claudeCacheCreation,
        codexInput = row.codexInput,
        codexOutput = row.codexOutput,
        todayTotal = row.todayTotal,
        todayDate = row.todayDate,
        codexCacheRead = row.codexCacheRead,
        codexAccountMonth = row.codexAccountMonth,
        codexEffectiveFromServer = row.codexEffective,
        center = CenterLabel.display(row.center),
    )
}

/** 토큰 보드 정렬: 총합 내림차순, 동률이면 이름 오름차순(`localizedStandardCompare` = [Collation]). */
fun List<TokenBoardEntry>.sortedByTotalDescending(collation: Collation): List<TokenBoardEntry> =
    sortedWith { l, r -> if (l.total != r.total) r.total.compareTo(l.total) else collation.compare(l.name, r.name) }

/** token_usage_board(p_month) 본문. */
@Serializable
data class TokenBoardRequest(@SerialName("p_month") val pMonth: String)

/** Swift `TokenUsageDailyRow`(token_usage_device_daily GET — 폰 '나'의 기록이 읽는다). */
@Serializable
data class TokenUsageDailyRow(
    @SerialName("day") val day: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("claude_total") val claudeTotal: Long,
    @SerialName("codex_total") val codexTotal: Long,
    @SerialName("codex_account") val codexAccount: Long? = null,
    @SerialName("codex_utc_total") val codexUtcTotal: Long? = null,
)
