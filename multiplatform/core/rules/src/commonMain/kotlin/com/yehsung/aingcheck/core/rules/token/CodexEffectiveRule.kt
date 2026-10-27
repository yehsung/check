// 원본: Sources/CheckCore/CodexEffectiveRule.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.token

/**
 * Codex 토큰 **표시값**의 단 하나의 규칙 — 계정 우선 · 미반영 꼬리만 로컬(`max(로컬, 계정)` 은 포크 복사본으로 부푼 쪽을 고르는 증폭기라 폐기).
 * 날짜 키는 고정폭 'YYYY-MM-DD' 라 사전식 비교가 곧 날짜 비교다.
 */
object CodexEffectiveRule {
    /** 로컬이 계정보다 이 배수 넘게 크면 포크 복사본 의심(서버 token_scan_health 와 같은 문턱). */
    const val overcountRatio = 1.2

    fun localExceedsAccount(local: Long, account: Long?): Boolean {
        if (account == null || account <= 0) return false
        return local.toDouble() > account.toDouble() * overcountRatio
    }

    /** 월 단위: 계정 없음 → 로컬, 이 달 버킷 없음 → 로컬, 그 외 = 계정 + 마지막 버킷 뒤 로컬 + max(0, 로컬[last] − 버킷[last]). */
    fun month(localMonth: Long, localDaily: Map<String, Long>, accountMonth: Long?, accountLastDay: String?, accountBucketOnLastDay: Long?): Long {
        val local = maxOf(0L, localMonth)
        if (accountMonth == null || accountLastDay == null) return local
        var effective = maxOf(0L, accountMonth)
        for ((day, tokens) in localDaily) if (day > accountLastDay) effective += maxOf(0L, tokens)
        effective += maxOf(0L, maxOf(0L, localDaily[accountLastDay] ?: 0L) - maxOf(0L, accountBucketOnLastDay ?: 0L))
        return effective
    }

    /** 하루 단위(잔디 칸): lastDay 앞은 버킷(없으면 0) · lastDay 는 max(버킷, 로컬) · 뒤는 로컬. 계정 없음 → 로컬. */
    fun day(day: String, local: Long, accountBucket: Long?, accountLastDay: String?): Long {
        val safeLocal = maxOf(0L, local)
        if (accountLastDay == null) return safeLocal
        val bucket = maxOf(0L, accountBucket ?: 0L)
        if (day < accountLastDay) return bucket
        if (day == accountLastDay) return maxOf(bucket, safeLocal)
        return safeLocal
    }
}
