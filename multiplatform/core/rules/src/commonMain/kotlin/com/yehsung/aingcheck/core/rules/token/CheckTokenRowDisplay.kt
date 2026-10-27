// 원본: Sources/CheckCore/CheckTokenRowDisplay.swift @ 1b8260d (폰 몫 — `resolve` 는 맥 로컬 스캐너(TokenUsageMonthly · CodexAccountUsage)가 재료라 W2-h(Windows 보류))
package com.yehsung.aingcheck.core.rules.token

import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.format.parseSwiftInt
import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.insights.KstCalendar

/**
 * 순위판 보드 RPC 가 내려준 **내 행**의 표시값(서버가 나눈 내 몫을 그대로 그린다 — 비율로 다시 계산하는 길은 닫혀 있다).
 * INV-CheckTokenRowDisplay-b253ba3b 이식: 서버가 `codex_effective` 를 안 준 행(옛 RPC)은 **만들지 않는다**([of] 가 null) —
 * 그 행의 값은 폐기한 `max(로컬, 계정)` 미러다.
 */
data class TokenRowServerValue(
    val userID: String,
    /** 'YYYY-MM'(KST) — 다른 달이면 쓰지 않는다. */
    val month: String,
    val total: Long,
    val claudeTotal: Long,
    val codexEffective: Long,
    val antigravityEffective: Long,
    /** 보드 14번 칸 `codex_account_month` — 이미 나눈 내 몫. 옛 표가 이긴 행이면 null. */
    val codexAccountShare: Long?,
    val fetchedAt: Double,
) {
    /** 순위판 카드 툴팁과 **같은 조립**(0 인 종류는 줄을 만들지 않는다). */
    val detailTooltip: String
        get() {
            val parts = ArrayList<String>()
            if (claudeTotal > 0) parts += "Claude ${TokenNumberFormatter.grouped(claudeTotal)}"
            if (codexEffective > 0) parts += "Codex ${TokenNumberFormatter.grouped(codexEffective)}"
            if (antigravityEffective > 0) parts += "안티그래비티 ${TokenNumberFormatter.grouped(antigravityEffective)}"
            return parts.joinToString(" · ")
        }

    /** 'YYYY-MM' 뒤 두 자리(선행 0 제거, 못 읽으면 0). */
    val monthNumber: Int get() = parseSwiftInt(month.split('-').lastOrNull { it.isNotEmpty() } ?: "")?.toInt() ?: 0

    companion object {
        /** 보드 엔트리의 사실(와이어 `TokenBoardEntry` 는 W1-d — W2-b 가 이 칸들로 넘긴다). `hasServerCodexEffective` 가 거짓이면 null. */
        fun of(
            userID: String, month: String, total: Long, claudeTotal: Long, codexEffective: Long, antigravityEffective: Long,
            codexAccountMonth: Long?, hasServerCodexEffective: Boolean, fetchedAt: Double,
        ): TokenRowServerValue? {
            if (!hasServerCodexEffective) return null
            return TokenRowServerValue(userID, month, total, claudeTotal, codexEffective, antigravityEffective, codexAccountMonth, fetchedAt)
        }
    }
}

/** 팝오버(Windows 플라이아웃) 행이 그릴 것. */
data class TokenRowDisplay(val total: Long, val tooltip: String, val monthNumber: Int, val isFromServer: Boolean)

/** 보드 응답 한 번이 내 행에 시키는 일 — 세 갈래뿐이다(`keep` 은 "판단하지 않는다" — 실패와 '내 행 없음'은 반대 사실). */
sealed interface MyTokenRowOutcome {
    data class adopt(val value: TokenRowServerValue) : MyTokenRowOutcome
    data object clear : MyTokenRowOutcome
    data object keep : MyTokenRowOutcome
}

/** 보드 엔트리 한 줄 중 [TokenRowDisplayRule.outcomeForMyRow] 가 읽는 칸. */
data class TokenBoardEntryFacts(
    val userID: String, val total: Long, val claudeTotal: Long, val codexEffective: Long, val antigravityEffective: Long,
    val codexAccountMonth: Long?, val hasServerCodexEffective: Boolean,
)

object TokenRowDisplayRule {
    /** 서버 행이 내 것 · 이번 달 · total > 0 이면 그것(낡음을 이유로 로컬로 되돌아가지 않는다). 로컬 산식 갈래는 W2-h. */
    fun resolveServer(server: TokenRowServerValue?, userID: String?, currentMonth: String): TokenRowDisplay? {
        if (server == null || userID == null || server.userID != userID || server.month != currentMonth || server.total <= 0) return null
        return TokenRowDisplay(server.total, server.detailTooltip, server.monthNumber, true)
    }

    /** 공유 비율(관측 분모 판): share 없음 · 분모 ≤ 0 → 1.0, 그 외 clamp(share/bucketSum, 0, 1). share 0 은 null 과 다르다. */
    fun accountShareRatio(share: Long?, bucketSum: Long): Double {
        if (share == null || bucketSum <= 0) return 1.0
        return minOf(1.0, maxOf(0.0, share.toDouble() / bucketSum.toDouble()))
    }

    /** 새 달의 비율을 아직 재지 않는 유예 일수(KST 월초). */
    const val shareRatioGraceDays = 3

    /**
     * 지금이 새 달 지분비가 아직 표본이 아닌 구간(KST 월초 3일)인가.
     * INV-CheckTokenRowDisplay-7174e35b 이식: 이 유예는 **폰 전용**이다(맥 호출부는 그대로 — Android 는 폰 쪽 규칙을 쓴다).
     */
    fun shareRatioMonthIsYoung(now: Double): Boolean = KstCalendar.localDate(now).day <= shareRatioGraceDays

    /** 보드 응답 한 번 → 내 행: 내 행 없음 = clear, 값을 못 만듦(옛 RPC) = keep, 그 외 adopt. */
    fun outcomeForMyRow(entries: List<TokenBoardEntryFacts>, userID: String, month: String, fetchedAt: Double): MyTokenRowOutcome {
        val mine = entries.firstOrNull { it.userID == userID } ?: return MyTokenRowOutcome.clear
        val value = TokenRowServerValue.of(mine.userID, month, mine.total, mine.claudeTotal, mine.codexEffective, mine.antigravityEffective,
            mine.codexAccountMonth, mine.hasServerCodexEffective, fetchedAt) ?: return MyTokenRowOutcome.keep
        return MyTokenRowOutcome.adopt(value)
    }

    /** 계정 버킷 하나를 비율로 줄인다(서버 round — 0.5 는 0 에서 먼 쪽). 비율 ≥ 1 이면 항등. */
    fun scaledAccountBucket(value: Long, ratio: Double): Long {
        if (!(ratio < 1.0)) return value
        return roundedHalfAwayFromZero(value.toDouble() * ratio).toLong()
    }
}
