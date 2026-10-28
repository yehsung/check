// 원본: Sources/CheckMobileKit/Me/MeWeeklyWork.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus
import com.yehsung.aingcheck.core.wire.SwiftDate

// 이번 주 누적 근무 보상(v0.3.55 — 서버 20261016120000_weekly_work_reward.sql). 사장님 결정: 20h 💎20 · 40h 💎50 · 60h 💎200(칸마다 따로).
// 폰이 하는 일은 **읽기**다(+ v0.3.58 [받기]): 시간 계산 · 칸 판정 · 지급은 전부 서버 몫이고 폰은 숫자를 옮겨 적는다.
// 응답 모델 · 디코더 · 게이지는 코어(rules weekly) 한 벌이다. 여기 남은 것은 폰에만 있는 규칙(이 기기가 본 칸 · 알림 합치기 · 주 넘김 · 루비 미러).

/** 한 번의 '받았어요' 알림(+N). 여러 칸이 한꺼번에 들어오면 합쳐서 한 번. */
data class WeeklyWorkGrantNotice(val ruby: Long, val hours: List<Long>)

/** 이 기기가 마지막으로 **본** 이번 주 받은 칸(계정별 저장 — [WeeklyWorkRules.newGrants]). */
data class WeeklyWorkSeen(val weekStart: String, val claimedHours: Set<Long>) {
    /** 저장 글자 "2026-10-12|20,40"(빈 칸이면 "2026-10-12|"). */
    val encoded: String get() = "$weekStart|" + claimedHours.sorted().joinToString(",")

    companion object {
        /** Swift `init?(encoded:)` — 모양이 틀리면 null, 숫자가 아닌 조각은 버린다. */
        fun decode(encoded: String?): WeeklyWorkSeen? {
            if (encoded == null) return null
            val bar = encoded.indexOf('|')
            if (bar < 0) return null
            val week = encoded.substring(0, bar)
            if (week.isEmpty()) return null
            val hours = encoded.substring(bar + 1).split(',').filter { it.isNotEmpty() }.mapNotNull(::swiftInt).toSet()
            return WeeklyWorkSeen(week, hours)
        }

        /** Swift `Int(Substring)` — 앞 부호 하나 + 숫자만(공백 · 소수점 · 빈 글자는 null). */
        private fun swiftInt(text: String): Long? {
            if (text.isEmpty()) return null
            val body = if (text[0] == '+' || text[0] == '-') text.substring(1) else text
            if (body.isEmpty() || body.any { it !in '0'..'9' }) return null
            return text.toLongOrNull()
        }
    }
}

object WeeklyWorkRules {
    /**
     * '받았어요' 알림에 올릴 지급. 서버 `granted_now` 만 보면 cron 이 1분마다 먼저 지급해 알림이 거의 영영 안 뜬다 — 그래서 '이 기기가
     * 마지막으로 본 상태'와 비교해 새로 받은 칸도 알린다. `previous` 가 없으면(첫 조회) 기준만 잡고 알리지 않는다. 같은 (주, 칸)은 한 번만.
     *
     * INV-MeWeeklyWork-0bc1ecd4 이식: **v0.3.58 받기 서버에서는 '본 기록과 비교' 갈래를 보지 않는다**(`status.supportsClaim`) — 그 서버에서
     *   claimed 가 거짓 → 참이 되는 길은 사람이 [받기]를 누른 것뿐이고(받기 연출이 이미 말했다), 그걸 "N시간 채웠어요"로 또 말하면 같은 일을
     *   두 번 알린다. `granted_now` 는 그대로 둔다 — 서버가 자동 지급으로 돌아가는 날 이 갈래가 저절로 산다.
     */
    fun newGrants(previous: WeeklyWorkSeen?, status: WeeklyWorkStatus): List<WeeklyWorkStatus.Grant> {
        val result = ArrayList<WeeklyWorkStatus.Grant>()
        val keys = HashSet<String>()
        fun add(grant: WeeklyWorkStatus.Grant) {
            val week = grant.weekStart ?: status.weekStart ?: ""
            if (!keys.add("$week#${grant.hours}")) return
            result += grant
        }
        status.grantedNow.forEach(::add)
        val week = status.weekStart
        if (!status.supportsClaim && previous != null && week != null) {
            val already = if (previous.weekStart == week) previous.claimedHours else emptySet()
            for (tier in status.tiers) {
                if (tier.claimed && tier.hours !in already) add(WeeklyWorkStatus.Grant(tier.hours, tier.ruby))
            }
        }
        return result
    }

    /** 이번 응답을 본 뒤 저장할 기준(이번 주 받은 칸). 주를 모르면 null. */
    fun seen(after: WeeklyWorkStatus): WeeklyWorkSeen? {
        val week = after.weekStart
        if (week.isNullOrEmpty()) return null
        return WeeklyWorkSeen(week, after.tiers.filter { it.claimed }.map { it.hours }.toSet())
    }

    /** 알림 하나로 합친다(빈 목록이거나 합이 0 이하면 null). */
    fun notice(grants: List<WeeklyWorkStatus.Grant>): WeeklyWorkGrantNotice? {
        if (grants.isEmpty()) return null
        val ruby = grants.sumOf { it.ruby }
        if (ruby <= 0) return null
        return WeeklyWorkGrantNotice(ruby, grants.map { it.hours }.sorted())
    }

    /** "2026-10-19" → 그 날 0시(KST). 못 읽으면 null. */
    fun kstMidnight(day: String?): SwiftDate? = KstCalendar.midnight(day)?.let { SwiftDate(it) }

    /** 이 응답의 주가 끝났는가(지금이 다음 주 월요일 0시 이후). 끝났으면 화면 값은 지난주 것이다 — 스로틀 없이 다시 읽는다. */
    fun weekHasRolled(status: WeeklyWorkStatus?, now: SwiftDate): Boolean = status?.hasEnded(now.timeIntervalSince1970) ?: false

    /**
     * 루비 미러에 서버 잔량을 쓸 것인가 — **더 새 값을 되돌리지 않는다**. 미러는 상점 · 뽑기 · 오목 · 체스가 다 쓰는 한 칸이라, 이 조회가
     * 떠 있는 사이 다른 응답이 미러에 썼으면(뽑기 −50) 이 응답의 잔량을 쓰면 깎인 루비가 되살아난다. **떠난 뒤 쓴 횟수가 0 일 때만** 쓴다
     * (값으로 비교하면 ABA — 40시간 보상 50 = 뽑기 값 50 — 에서 옛 잔량이 이긴다).
     */
    fun shouldApplyRuby(server: Long?, writeSerialAtDeparture: Int, currentWriteSerial: Int): Boolean {
        if (server == null) return false
        return writeSerialAtDeparture == currentWriteSerial
    }
}
