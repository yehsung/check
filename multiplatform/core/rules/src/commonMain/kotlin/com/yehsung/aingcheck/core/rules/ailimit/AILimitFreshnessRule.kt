// 원본: Sources/CheckCore/AILimitFreshnessRule.swift @ 1b8260d (+ SupabaseWorkModels.swift:3651-3658 FeedbackText.ageText — 나이 문구)
package com.yehsung.aingcheck.core.rules.ailimit

import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero

/** 신선도 등급. */
enum class AILimitFreshness(val rawValue: String) {
    fresh("fresh"),
    recent("recent"),
    stale("stale"),
    ancient("ancient"),
    reset("reset"),
    resetUnverified("resetUnverified"),
    unknown("unknown"),
    ;

    /**
     * 하한만 말하는 등급(stale · ancient — "이상").
     * INV-AILimitFreshnessRule-e3181122 이식: **등급의 성질**이다 — 실제로 "이상"이 글자에 붙는지는 [AILimitFreshnessRule.value] 가 정한다(0% 에는 안 붙는다).
     */
    val isFloorOnly: Boolean get() = this == stale || this == ancient
    val isResetClaim: Boolean get() = this == reset || this == resetUnverified
}

data class AILimitValue(val percent: Double, val text: String, val floorOnly: Boolean)

/** 카드 한 줄이 그리는 것 — 값 · 캡션 · 표시 여부가 **한 함수**에서 나온다. */
data class AILimitDisplay(
    val isVisible: Boolean,
    val valueText: String,
    val captionText: String,
    val percent: Double?,
    val floorOnly: Boolean,
    val freshness: AILimitFreshness,
    val claimAge: Double?,
    val provider: AILimitProvider?,
    val window: AILimitWindow?,
    val source: AILimitSource?,
    val resetsAt: Double?,
) {
    internal fun withProvider(provider: AILimitProvider): AILimitDisplay = copy(provider = provider)
}

object AILimitFreshnessRule {
    const val clockSkewTolerance = 120.0
    const val freshWithin = 60.0
    const val recentWithin = 1_800.0
    const val staleWithin = 86_400.0
    const val sameWindowTolerance = 600.0
    const val unknownValueText = "—"

    fun display(snapshot: AILimitWindowSnapshot?, now: Double): AILimitDisplay {
        if (snapshot == null) return unknownDisplay(false, null, null, null)
        // 시계가 앞선 관측 · 리셋이 관측보다 앞 · 리셋이 그 창의 것이 아니다 → 알 수 없음(보이되 값은 —).
        if (snapshot.observedAt - now > clockSkewTolerance) return unknownDisplay(true, null, snapshot.window, snapshot.source)
        val resetsAt = snapshot.resetsAt
        if (resetsAt != null) {
            if (resetsAt < snapshot.observedAt) return unknownDisplay(true, null, snapshot.window, snapshot.source)
            if (resetsAt - snapshot.observedAt > snapshot.window.lengthSeconds + sameWindowTolerance) {
                return unknownDisplay(true, null, snapshot.window, snapshot.source)
            }
        }
        val resetClaimed = snapshot.usedPercent > 0 && resetsAt != null && now >= resetsAt + clockSkewTolerance
        val rawFloor: Double
        val reference: Double
        if (resetClaimed && resetsAt != null) {
            rawFloor = 0.0
            reference = resetsAt   // 다음 경계를 추정하지 않는다 — 나이는 이 시각으로만.
        } else {
            rawFloor = snapshot.usedPercent
            reference = snapshot.observedAt
        }
        val age = maxOf(0.0, now - reference)
        val freshness = grade(age, resetClaimed)
        val caption = captionText(freshness, reference, now)
        val value = value(rawFloor, freshness.isFloorOnly, freshness.isResetClaim)
        return AILimitDisplay(true, value.text, caption, value.percent, value.floorOnly, freshness, age, null, snapshot.window, snapshot.source,
            snapshot.resetsAt)
    }

    fun display(provider: AILimitProviderSnapshot?, window: AILimitWindow, now: Double): AILimitDisplay {
        if (provider == null) return unknownDisplay(false, null, window, null)
        val row = provider.window(window) ?: return unknownDisplay(false, provider.provider, window, null)
        return display(row, now).withProvider(provider.provider)
    }

    fun displays(provider: AILimitProviderSnapshot, now: Double): List<AILimitDisplay> =
        provider.orderedWindows.map { display(it, now).withProvider(provider.provider) }

    /** 여러 줄을 하나로: 알 수 없음만이면 알 수 없음. 리셋 주장은 전부 주장일 때만 말한다. 값은 말하는 줄의 최대, 캡션은 가장 오래된 줄. */
    fun combine(displays: List<AILimitDisplay>): AILimitDisplay {
        val known = displays.filter { it.freshness != AILimitFreshness.unknown }
        if (known.isEmpty()) {
            return unknownDisplay(displays.any { it.isVisible }, common(displays.map { it.provider }), common(displays.map { it.window }),
                common(displays.map { it.source }))
        }
        val claiming = known.filter { it.freshness.isResetClaim }
        val speaking = if (claiming.size == known.size) claiming else known.filter { !it.freshness.isResetClaim }
        val floor = speaking.mapNotNull { it.percent }.maxOrNull() ?: 0.0
        // Swift max(by:) — 같으면 앞의 것.
        var lead: AILimitDisplay? = null
        for (candidate in speaking) {
            val current = lead
            if (current == null || isLessLead(current, candidate)) lead = candidate
        }
        val caption = lead?.captionText ?: ""
        val freshness = lead?.freshness ?: AILimitFreshness.unknown
        val value = value(floor, speaking.any { it.floorOnly } || freshness.isFloorOnly, freshness.isResetClaim)
        return AILimitDisplay(true, value.text, caption, value.percent, value.floorOnly, freshness, lead?.claimAge,
            common(known.map { it.provider }), common(known.map { it.window }), common(known.map { it.source }), null)
    }

    private fun isLessLead(lhs: AILimitDisplay, rhs: AILimitDisplay): Boolean {
        val left = lhs.claimAge ?: 0.0
        val right = rhs.claimAge ?: 0.0
        if (left != right) return left < right
        return !lhs.floorOnly && rhs.floorOnly
    }

    fun grade(age: Double, resetClaimed: Boolean): AILimitFreshness {
        if (resetClaimed) return if (age <= recentWithin) AILimitFreshness.reset else AILimitFreshness.resetUnverified
        if (age <= freshWithin) return AILimitFreshness.fresh
        if (age <= recentWithin) return AILimitFreshness.recent
        if (age <= staleWithin) return AILimitFreshness.stale
        return AILimitFreshness.ancient
    }

    fun captionText(freshness: AILimitFreshness, reference: Double, now: Double): String = when (freshness) {
        AILimitFreshness.unknown -> "알 수 없음"
        AILimitFreshness.reset -> "초기화됨"
        AILimitFreshness.resetUnverified -> "초기화됨 · 확인 못 함"
        else -> ageText(reference, now)
    }

    /** 나이 문구(FeedbackText.ageText): 60초 미만 '방금' · 분 · 시간 · 일(정수 초 — Swift Int(차) 0 쪽 자름, 음수 0). */
    fun ageText(date: Double?, now: Double): String {
        if (date == null) return ""
        val diff = now - date
        val seconds = maxOf(0L, if (diff.isFinite()) diff.toLong() else 0L)
        if (seconds < 60) return "방금"
        if (seconds < 3600) return "${seconds / 60}분 전"
        if (seconds < 86_400) return "${seconds / 3600}시간 전"
        return "${seconds / 86_400}일 전"
    }

    /**
     * 값과 글자. 리셋 주장은 언제나 0%(이상 없음).
     * INV-AILimitFreshnessRule-ad2aa296 이식: **0% 에는 "이상"을 붙이지 않는다** — 하한이 0 이면 아무것도 말하지 않는 것과 같다.
     */
    fun value(percent: Double, floorOnly: Boolean, isResetClaim: Boolean): AILimitValue {
        if (isResetClaim) return AILimitValue(0.0, "0%", false)
        val clamped = clampedPercent(percent)
        val whole = wholePercent(clamped)
        val isFloor = floorOnly && whole > 0
        return AILimitValue(clamped, if (isFloor) "$whole% 이상" else "$whole%", isFloor)
    }

    fun valueText(percent: Double, freshness: AILimitFreshness): String {
        if (freshness == AILimitFreshness.unknown) return unknownValueText
        return value(percent, freshness.isFloorOnly, freshness.isResetClaim).text
    }

    /** 반올림(0.5 → 0 에서 먼 쪽) — 0 초과면 최소 1, 100 미만이면 최대 99(0% · 100% 는 정말 그럴 때만). */
    fun wholePercent(value: Double): Int {
        val clamped = clampedPercent(value)
        var whole = roundedHalfAwayFromZero(clamped).toInt()
        if (clamped > 0 && whole == 0) whole = 1
        if (clamped < 100 && whole == 100) whole = 99
        return whole
    }

    fun clampedPercent(value: Double): Double {
        if (!value.isFinite()) return 0.0
        return minOf(maxOf(value, 0.0), 100.0)
    }

    private fun unknownDisplay(isVisible: Boolean, provider: AILimitProvider?, window: AILimitWindow?, source: AILimitSource?) =
        AILimitDisplay(isVisible, unknownValueText, "알 수 없음", null, false, AILimitFreshness.unknown, null, provider, window, source, null)

    private fun <T> common(values: List<T?>): T? {
        val present = values.filterNotNull()
        val first = present.firstOrNull() ?: return null
        if (present.size != values.size) return null
        return if (present.all { it == first }) first else null
    }
}
