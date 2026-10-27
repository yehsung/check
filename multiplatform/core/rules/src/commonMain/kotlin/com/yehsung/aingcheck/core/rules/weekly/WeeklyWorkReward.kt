// 원본: Sources/CheckCore/WeeklyWorkReward.swift @ 1b8260d (서비스 래퍼 `extension SupabaseWorkService` 는 net(W1-d) 몫)
package com.yehsung.aingcheck.core.rules.weekly

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.abs

// 주간 누적 근무 보상(v0.3.55 · 사장님 확정: 20h 20 · 40h 50 · 60h 200 — 단계마다 따로). 단계 표는 **응답이 말한다**(클라에 숫자를
// 적지 않는다). 주 = KST 월요일 0시 → 다음 월요일 0시. 이 파일이 지키는 것:
// ① 디코드가 통째로 죽지 않는다 ② "방금 받았다"는 서버가 넣은 행으로만 ③ v0.3.58 받기 버튼(pending · claimable_ruby 가 있으면 받기 서버).

/**
 * `weekly_work_status()` · `weekly_work_claim()` 응답.
 * INV-WeeklyWorkReward-1621c9d5 이식: **칸 하나 때문에 throw 하지 않는다** — 최상위가 객체가 아닐 때만 [SwiftDecodingError].
 * 생성은 [of] — 단계 표는 시간 오름차순 · 같은 시간은 앞의 것만, claimableRuby 는 음수 → 0.
 */
data class WeeklyWorkStatus(
    val weekStart: String? = null,
    val nextWeekStart: String? = null,
    /** 이번 주 누적 근무초. **null = 모른다**(0 이 아니다). */
    val workedSeconds: Long? = null,
    val tiers: List<Tier> = emptyList(),
    val grantedNow: List<Grant> = emptyList(),
    val rubyBalance: Long? = null,
    val serverNowMs: Long? = null,
    /** v0.3.58 받을 것 전부(어느 주든). **null = 옛 서버**. */
    val pending: List<Pending>? = null,
    val claimableRuby: Long? = null,
    val claimedNow: List<Grant> = emptyList(),
) {
    /** 한 단계. `claimed` = 이 주 · 이 단계의 장부 행이 있다. */
    data class Tier(val hours: Long, val ruby: Long, val claimed: Boolean, val achieved: Boolean? = null, val claimable: Boolean? = null) {
        val thresholdSeconds: Long get() = hours * 3_600
    }

    /** 지급 한 건. weekStart null = 이번 주(서버는 지난주 소급분에만 싣는다). */
    data class Grant(val hours: Long, val ruby: Long, val weekStart: String? = null)

    /** v0.3.58 채웠고 아직 안 받은 단계(어느 주든). ruby 음수 → 0. */
    data class Pending(val weekStart: String, val hours: Long, val ruby: Long) {
        companion object {
            fun of(weekStart: String, hours: Long, ruby: Long): Pending = Pending(weekStart, hours, maxOf(0L, ruby))
        }
    }

    // MARK: 파생(순수)

    /** 줄을 그릴 만큼 아는가(누적초 + 단계 표 한 행 이상). 모르는 값을 0 으로 그리지 않는다. */
    val isUsable: Boolean get() = workedSeconds != null && tiers.isNotEmpty()

    val displayWorkedSeconds: Long get() = maxOf(0L, workedSeconds ?: 0L)

    val totalRuby: Long get() = tiers.sumOf { maxOf(0L, it.ruby) }

    /** 받기 서버의 응답인가(pending 이나 claimable_ruby 가 실려 왔다). */
    val supportsClaim: Boolean get() = pending != null || claimableRuby != null

    val pendingRuby: Long
        get() {
            if (!supportsClaim) return 0
            return maxOf(0L, claimableRuby ?: (pending ?: emptyList()).sumOf { it.ruby })
        }

    val pendingCount: Int
        get() {
            if (pendingRuby <= 0) return 0
            return maxOf(1, pending?.size ?: 1)
        }

    val hasClaimable: Boolean get() = pendingRuby > 0

    val claimedNowRuby: Long get() = claimedNow.sumOf { maxOf(0L, it.ruby) }

    /** 다음 주 월요일 0시(KST, Double 초). 못 읽으면 null. */
    val nextWeekStartDate: Double? get() = KstCalendar.midnight(nextWeekStart)

    fun hasEnded(now: Double): Boolean {
        val end = nextWeekStartDate ?: return false
        return now >= end
    }

    /** 주 경계가 `last` 뒤 · `now` 이전에 있었는가(맥 1분 창을 건너뛰는 조건). */
    fun weekEnded(last: Double, now: Double): Boolean {
        val end = nextWeekStartDate ?: return false
        return last < end && end <= now
    }

    val gauge: WeeklyWorkGauge?
        get() = if (!isUsable) null else WeeklyWorkGauge.make(displayWorkedSeconds, tiers)

    /**
     * `previous` 다음에 **새로 들어온** 지급: ① granted_now(이번 주 행은 weekStart 를 비운다) ∪ ② (받기 서버가 아니고 같은 주면)
     * claimed 거짓 → 참 단계. (주, 시간)당 한 번, 루비 > 0 만.
     */
    fun newlyGranted(previous: WeeklyWorkStatus?): List<Grant> {
        val result = ArrayList<Grant>()
        val seen = HashSet<String>()
        fun add(grant: Grant) {
            val week = grant.weekStart ?: weekStart ?: ""
            if (grant.ruby <= 0 || !seen.add("$week|${grant.hours}")) return
            result += grant
        }
        for (grant in grantedNow) {
            val isThisWeek = grant.weekStart == null || grant.weekStart == weekStart
            add(Grant(grant.hours, grant.ruby, if (isThisWeek) null else grant.weekStart))
        }
        if (!supportsClaim && previous != null && previous.weekStart != null && previous.weekStart == weekStart) {
            val wasClaimed = LinkedHashMap<Long, Boolean>()
            for (tier in previous.tiers) if (tier.hours !in wasClaimed) wasClaimed[tier.hours] = tier.claimed
            for (tier in tiers) if (tier.claimed && wasClaimed[tier.hours] == false) add(Grant(tier.hours, tier.ruby))
        }
        return result
    }

    companion object {
        internal fun normalized(tiers: List<Tier>): List<Tier> {
            val seen = HashSet<Long>()
            return tiers.sortedBy { it.hours }.filter { seen.add(it.hours) }
        }

        fun of(
            weekStart: String? = null, nextWeekStart: String? = null, workedSeconds: Long? = null, tiers: List<Tier> = emptyList(),
            grantedNow: List<Grant> = emptyList(), rubyBalance: Long? = null, serverNowMs: Long? = null, pending: List<Pending>? = null,
            claimableRuby: Long? = null, claimedNow: List<Grant> = emptyList(),
        ): WeeklyWorkStatus = WeeklyWorkStatus(weekStart, nextWeekStart, workedSeconds, normalized(tiers), grantedNow, rubyBalance, serverNowMs,
            pending, claimableRuby?.let { maxOf(0L, it) }, claimedNow)

        /** 관대한 디코드(서비스 디코더 — convertFromSnakeCase). */
        fun decode(element: JsonElement): WeeklyWorkStatus {
            val c = SwiftKeyed(SwiftValue.obj(element))
            return of(
                weekStart = c.lossyString("weekStart"),
                nextWeekStart = c.lossyString("nextWeekStart"),
                workedSeconds = lossyInt(c, "workedSeconds"),
                tiers = lossyList(c, "tiers")?.mapNotNull(::lossyTier) ?: emptyList(),
                grantedNow = lossyList(c, "grantedNow")?.mapNotNull(::lossyGrant) ?: emptyList(),
                rubyBalance = lossyInt(c, "rubyBalance"),
                serverNowMs = lossyInt(c, "serverNowMs"),
                pending = lossyList(c, "pending")?.mapNotNull(::lossyPending),
                claimableRuby = lossyInt(c, "claimableRuby"),
                claimedNow = lossyList(c, "claimedNow")?.mapNotNull(::lossyGrant) ?: emptyList(),
            )
        }

        /** Swift `WeeklyLossyNumber`: 정수, 아니면 유한 소수(|v| < 9e15)를 0 쪽으로 버림. **글자 숫자는 받지 않는다.** */
        internal fun lossyNumber(value: JsonElement): Long? {
            try {
                return SwiftValue.int(value)
            } catch (e: SwiftDecodingError) {
                // 소수로.
            }
            return try {
                val d = SwiftValue.double(value)
                if (d.isFinite() && abs(d) < 9.0e15) d.toLong() else null
            } catch (e: SwiftDecodingError) {
                null
            }
        }

        private fun lossyInt(c: SwiftKeyed, key: String): Long? {
            val value = c.element(key) ?: return null
            if (value is JsonNull) return null
            return lossyNumber(value)
        }

        private fun lossyList(c: SwiftKeyed, key: String): List<JsonElement>? {
            if (!c.contains(key)) return null
            return c.element(key) as? JsonArray
        }

        private fun lossyTier(element: JsonElement): Tier? {
            val c = SwiftKeyed(element as? JsonObject ?: return null)
            val hours = lossyInt(c, "hours")?.takeIf { it > 0 } ?: return null
            val ruby = lossyInt(c, "ruby") ?: return null
            // claimed 가 없거나 틀리면 **안 받은 것** — 받았다고 그리면 안 준 루비를 준 것처럼 말한다.
            return Tier(hours, ruby, c.lossyBool("claimed") ?: false, c.lossyBool("achieved"), c.lossyBool("claimable"))
        }

        private fun lossyPending(element: JsonElement): Pending? {
            val c = SwiftKeyed(element as? JsonObject ?: return null)
            val hours = lossyInt(c, "hours")?.takeIf { it > 0 } ?: return null
            val ruby = lossyInt(c, "ruby") ?: return null
            return Pending.of(c.lossyString("weekStart") ?: "", hours, ruby)
        }

        private fun lossyGrant(element: JsonElement): Grant? {
            val c = SwiftKeyed(element as? JsonObject ?: return null)
            val hours = lossyInt(c, "hours") ?: return null
            val ruby = lossyInt(c, "ruby") ?: return null
            return Grant(hours, ruby, c.lossyString("weekStart"))
        }
    }
}

/**
 * 맥 줄 · 폰 카드가 그리는 게이지(지금 퀘스트 하나 — 사장님 늦은 변경 2026-10-16). 지금 퀘스트 = 누적초가 **아직 못 넘은** 첫 단계
 * (claimed 로 고르지 않는다 — cron 이 1분 늦게 따라온다). 채움 = 이번 주 누적 ÷ 퀘스트 초. 마지막을 넘으면 완료.
 */
data class WeeklyWorkGauge(val questHours: Long, val fill: Double, val isComplete: Boolean, val reward: Long, val claimedTotal: Long) {
    fun hasPassed(tier: WeeklyWorkStatus.Tier): Boolean = isComplete || tier.hours < questHours

    companion object {
        /** 표가 비면 null. 표 순서 · 중복은 여기서 다시 정리한다(시간 > 0 만). */
        fun make(workedSeconds: Long, tiers: List<WeeklyWorkStatus.Tier>): WeeklyWorkGauge? {
            val table = WeeklyWorkStatus.normalized(tiers.filter { it.hours > 0 })
            val last = table.lastOrNull() ?: return null
            val worked = maxOf(0L, workedSeconds)
            val claimedTotal = table.sumOf { if (it.claimed) maxOf(0L, it.ruby) else 0L }
            val quest = table.firstOrNull { worked < it.thresholdSeconds }
                ?: return WeeklyWorkGauge(last.hours, 1.0, true, maxOf(0L, last.ruby), claimedTotal)
            val fill = minOf(1.0, maxOf(0.0, worked.toDouble() / quest.thresholdSeconds.toDouble()))
            return WeeklyWorkGauge(quest.hours, fill, false, maxOf(0L, quest.ruby), claimedTotal)
        }
    }
}

/** `weekly_work_claim(p_week_start, p_hours)` 본문 — **키 둘을 언제나 싣는다**(null 은 JSON null). */
data class WeeklyWorkClaimRequest(val pWeekStart: String?, val pHours: Long?) {
    fun body(): JsonObject = JsonObject(linkedMapOf(
        "p_week_start" to (pWeekStart?.let { JsonPrimitive(it) } ?: JsonNull),
        "p_hours" to (pHours?.let { JsonPrimitive(it) } ?: JsonNull),
    ))
}
