// W2-h3 로컬 표시 산식 — 서버 행이 없을 때의 폴백(팝오버 행·툴팁).
// 원본: Sources/CheckCore/CheckTokenUsage.swift:142-178(detailTooltip · displayTotal) · Sources/CheckCore/CheckCodexAccountUsage.swift:872-904(TokenUsageDisplay)
package com.yehsung.aingcheck.feature.desktop.tokens.account

import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.token.CodexEffectiveRule
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly

/**
 * INV-CheckCodexAccountUsage-8c00c4e7 이식: 이 산식은 **이 기기가 아는 것만으로** 계산한 값이라 지분 개념이 없다 — 공유 Codex 계정에선
 * 서버 codex_effective 와 다르다. 서버 행이 있으면 그 total 을 그린다(core/rules TokenRowDisplayRule.resolveServer). 이것은 폴백뿐.
 */
object TokenUsageDisplay {
    fun codexEffective(local: TokenUsageMonthly, account: CodexAccountUsage?): Long {
        val lastDay = account?.latestBucketDate(local.month)
        return CodexEffectiveRule.month(
            localMonth = local.codexTotal,
            localDaily = local.codexDailyOnAccountAxis,
            accountMonth = account?.monthTotal(local.month),
            accountLastDay = lastDay,
            accountBucketOnLastDay = lastDay?.let { account.buckets[it] },
        )
    }

    fun effectiveTotal(local: TokenUsageMonthly, account: CodexAccountUsage?): Long = local.claudeTotal + codexEffective(local, account)
}

/** 굵게 뜨는 표시 총합(클로드 + Codex 유효값 + 안티그래비티 — Windows 는 안티그래비티 0). */
fun TokenUsageMonthly.displayTotal(account: CodexAccountUsage?): Long = TokenUsageDisplay.effectiveTotal(this, account) + antigravityTotal

/** 툴팁 — 0 인 종류는 줄을 만들지 않는다. */
fun TokenUsageMonthly.detailTooltip(account: CodexAccountUsage?): String {
    val parts = ArrayList<String>()
    if (claudeTotal > 0) parts += "Claude ${TokenNumberFormatter.grouped(claudeTotal)}"
    val codex = TokenUsageDisplay.codexEffective(this, account)
    if (codex > 0) parts += "Codex ${TokenNumberFormatter.grouped(codex)}"
    if (antigravityTotal > 0) parts += "안티그래비티 ${TokenNumberFormatter.grouped(antigravityTotal)}"
    return parts.joinToString(" · ")
}
