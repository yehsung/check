// 원본: Sources/CheckCore/Achievements.swift @ 1b8260d (서비스 래퍼 `extension SupabaseWorkService` 는 net(W1-d) 몫)
package com.yehsung.aingcheck.core.rules.achievements

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import com.yehsung.aingcheck.core.rules.text.TextScalars
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// 도전 미션(일회성 업적) — v0.3.58. 값(보상·목표·제목·순서)은 **응답이 말한다** — 이 파일에 50/20/10 … 을 적지 않는다.
// INV-Achievements-d802c464 이식: **받기 버튼으로 받는다** — 달성(achieved)과 지급(claimed)이 갈린다. 달성은 서버가 적고 루비는 사람이
// [받기]를 누를 때만 움직인다. 달성한 보상은 사라지지 않는다(받을 때까지 기다린다). 3시간 루비만 자동 지급(이 파일 밖).
// 이 파일이 지키는 것: ① 디코드가 통째로 죽지 않는다 ② "받았다"는 서버가 넣은 행(claimed_now)으로만 ③ 한 줄은 한 계열(seriesRows).

/**
 * `achievements_status()` · `achievement_claim(p_key)` · `daily_mission_claim(p_key)` 응답(같은 모양 — 받기 응답에만 claimed_now 가 찬다).
 * INV-Achievements-1621c9d5 이식: **칸 하나 때문에 throw 하지 않는다** — 최상위가 객체가 아닐 때만 [SwiftDecodingError].
 */
data class AchievementStatus(
    /** 서버가 도전 미션을 연 시각(epoch ms). 진단용. */
    val launchAtMs: Long? = null,
    /** 미션 전부(서버 순서 그대로). 같은 키가 둘이면 앞의 것만 — [of] 가 거른다. */
    val missions: List<Mission> = emptyList(),
    val reportedClaimableCount: Long? = null,
    val reportedClaimableRuby: Long? = null,
    /** 이 호출이 장부에 **실제로 넣은** 지급(받기 응답만). */
    val claimedNow: List<Claim> = emptyList(),
    /** 정산 뒤 루비 잔량. null = 안 알려 줬다(스토어는 잔량을 건드리지 않는다). */
    val rubyBalance: Long? = null,
    val serverNowMs: Long? = null,
    /** 일일 미션(v0.3.64 — 최상위 `daily`). **null = 이 서버엔 일일 미션이 없다**(옛 서버 · 칸이 객체가 아님). */
    val daily: DailyMissionStatus? = null,
) {
    /** 줄 하나가 그리는 상태 — 미달성 → [받기] → 받음, 이 순서로만. */
    enum class RowState { inProgress, claimable, claimed }

    /** 미션 하나(한 단계). 생성은 [Mission.of] 로만 — 값을 자르는 규칙이 거기 있다. */
    data class Mission(
        val key: String,
        val series: String,
        val tier: Long,
        val title: String,
        val detail: String,
        val reward: Long,
        val target: Long,
        val progress: Long,
        val achieved: Boolean,
        val claimed: Boolean,
        val achievedAtMs: Long?,
        val claimedAtMs: Long?,
        val sort: Long,
    ) {
        val id: String get() = key

        /** 채웠고 아직 안 받았다 — [받기] 버튼이 서는 줄. */
        val isClaimable: Boolean get() = achieved && !claimed

        val state: RowState
            get() = when {
                claimed -> RowState.claimed
                achieved -> RowState.claimable
                else -> RowState.inProgress
            }

        /** 진행 막대 0…1. 채웠으면 1(달성은 끈적하다). */
        val fraction: Double get() = if (achieved) 1.0 else minOf(1.0, maxOf(0.0, progress.toDouble() / target.toDouble()))

        /** 받은 것으로 굳힌 사본(늦게 온 옛 응답이 받은 줄을 [받기]로 되돌리지 않게). */
        internal fun markedClaimed(previous: Mission): Mission = of(
            key = key, series = series, tier = tier, title = title, detail = detail, reward = reward, target = target,
            progress = progress, achieved = true, claimed = true,
            achievedAtMs = achievedAtMs ?: previous.achievedAtMs, claimedAtMs = claimedAtMs ?: previous.claimedAtMs, sort = sort,
        )

        companion object {
            /** Swift 생성자 규칙: 계열이 비면 키 · 보상 음수 → 0 · 목표 최소 1 · 진행은 0…목표 · 받았으면 채운 것이다. */
            fun of(
                key: String, series: String? = null, tier: Long = 1, title: String, detail: String = "", reward: Long = 0,
                target: Long = 1, progress: Long = 0, achieved: Boolean = false, claimed: Boolean = false,
                achievedAtMs: Long? = null, claimedAtMs: Long? = null, sort: Long = Long.MAX_VALUE,
            ): Mission {
                val clampedTarget = maxOf(1L, target)
                return Mission(
                    key = key,
                    series = series?.takeIf { it.isNotEmpty() } ?: key,
                    tier = tier,
                    title = title,
                    detail = detail,
                    reward = maxOf(0L, reward),
                    target = clampedTarget,
                    progress = minOf(maxOf(0L, progress), clampedTarget),
                    achieved = achieved || claimed,
                    claimed = claimed,
                    achievedAtMs = achievedAtMs,
                    claimedAtMs = claimedAtMs,
                    sort = sort,
                )
            }
        }
    }

    /** 이 호출이 넣은 지급 한 건(`claimed_now`). 보상 음수 → 0. */
    data class Claim(val key: String, val title: String, val reward: Long) {
        companion object {
            fun of(key: String, title: String, reward: Long): Claim = Claim(key, title, maxOf(0L, reward))
        }
    }

    // MARK: 파생(순수)

    /** 받을 수 있는 미션 — 계열로 접기 **전**이다. */
    val claimable: List<Mission> get() = missions.filter { it.isClaimable }

    /** 배지 · 절 머리의 "받을 보상 N개" — 줄에서 센다(서버 숫자와 갈리면 줄이 이긴다). */
    val claimableCount: Int get() = claimable.size

    val claimableRuby: Long get() = claimable.sumOf { it.reward }

    /**
     * 화면의 줄 — **계열마다 한 줄**: ① [받기]가 있는 가장 낮은 단계 → ② 아직 안 받은 가장 낮은 단계 → ③ 가장 높은 단계(받음).
     * 받을 수 있는 보상이 위 단계에 **가려지면 안 된다**. 줄 순서는 계열의 가장 작은 sort · 같으면 키.
     */
    val seriesRows: List<Mission>
        get() {
            val groups = LinkedHashMap<String, MutableList<Mission>>()
            for (mission in missions) groups.getOrPut(mission.series) { ArrayList() } += mission
            val rows = groups.values.mapNotNull { group ->
                val tiers = group.sortedWith(compareBy<Mission>({ it.tier }, { it.sort }).thenBy(SWIFT_STRING) { it.key })
                val shown = tiers.firstOrNull { it.isClaimable } ?: tiers.firstOrNull { !it.claimed } ?: tiers.lastOrNull() ?: return@mapNotNull null
                Triple(tiers.minOf { it.sort }, shown.key, shown)
            }
            return rows.sortedWith(compareBy<Triple<Long, String, Mission>> { it.first }.thenBy(SWIFT_STRING) { it.second }).map { it.third }
        }

    fun series(ofKey: String): String? = missions.firstOrNull { it.key == ofKey }?.series

    val claimedNowRuby: Long get() = claimedNow.sumOf { it.reward }

    /**
     * `previous`(같은 사람의 지난 응답) 위에 이 응답을 얹는다 — **받음은 되돌아가지 않는다**(받기 두 건의 답이 순서를 바꿔 와도
     * 방금 받은 줄에 [받기]가 다시 서지 않게). 일일은 같은 kst_day 안에서만([DailyMissionStatus.merged]).
     */
    fun merged(previous: AchievementStatus?): AchievementStatus {
        if (previous == null) return this
        val mergedDaily = daily?.merged(previous.daily)
        val claimedBefore = LinkedHashMap<String, Mission>()
        for (mission in previous.missions) if (mission.claimed && mission.key !in claimedBefore) claimedBefore[mission.key] = mission
        if (claimedBefore.isEmpty()) return copy(daily = mergedDaily)
        return copy(
            daily = mergedDaily,
            missions = missions.map { mission ->
                val before = claimedBefore[mission.key]
                if (mission.claimed || before == null) mission else mission.markedClaimed(before)
            },
        )
    }

    companion object {
        /** Swift 문자열 비교(키는 ASCII 라 UTF-16 순서와 같다). */
        internal val SWIFT_STRING: Comparator<String> = Comparator { a, b -> a.compareTo(b) }

        /** Swift `init(...)` — 같은 키는 앞의 것만. */
        fun of(
            launchAtMs: Long? = null, missions: List<Mission> = emptyList(), reportedClaimableCount: Long? = null,
            reportedClaimableRuby: Long? = null, claimedNow: List<Claim> = emptyList(), rubyBalance: Long? = null,
            serverNowMs: Long? = null, daily: DailyMissionStatus? = null,
        ): AchievementStatus {
            val seen = HashSet<String>()
            return AchievementStatus(launchAtMs, missions.filter { seen.add(it.key) }, reportedClaimableCount, reportedClaimableRuby,
                claimedNow, rubyBalance, serverNowMs, daily)
        }

        /** 관대한 디코드(서비스 디코더 — 키는 convertFromSnakeCase). 최상위가 객체가 아니면 [SwiftDecodingError]. */
        fun decode(element: JsonElement): AchievementStatus {
            val c = SwiftKeyed(SwiftValue.obj(element))
            return of(
                launchAtMs = AchievementLossy.int(c, "launchAtMs"),
                missions = AchievementLossy.list(c, "missions")?.mapNotNull(::lossyMission) ?: emptyList(),
                reportedClaimableCount = AchievementLossy.int(c, "claimableCount"),
                reportedClaimableRuby = AchievementLossy.int(c, "claimableRuby"),
                claimedNow = AchievementLossy.list(c, "claimedNow")?.mapNotNull(::lossyClaim) ?: emptyList(),
                rubyBalance = AchievementLossy.int(c, "rubyBalance"),
                serverNowMs = AchievementLossy.int(c, "serverNowMs"),
                // 일일 칸 하나가 깨져도 누적 미션은 산다(객체가 아니면 null = 일일 없음).
                daily = c.element("daily")?.takeIf { it !is JsonNull }?.let { DailyMissionStatus.decodeOrNull(it) },
            )
        }

        /** 키나 제목이 없는(또는 빈) 미션은 null — 그 행만 버린다. 받음/달성 칸이 없거나 틀리면 시각으로, 둘 다 없으면 **아니다**. */
        private fun lossyMission(element: JsonElement): Mission? {
            val obj = element as? JsonObject ?: return null
            val c = SwiftKeyed(obj)
            val key = c.lossyString("key")?.takeIf { it.isNotEmpty() } ?: return null
            val title = c.lossyString("title")?.let(TextScalars::trimmingWhitespacesAndNewlines)?.takeIf { it.isNotEmpty() } ?: return null
            val achievedAtMs = AchievementLossy.int(c, "achievedAtMs")
            val claimedAtMs = AchievementLossy.int(c, "claimedAtMs")
            val claimed = c.lossyBool("claimed") ?: (claimedAtMs != null)
            return Mission.of(
                key = key,
                series = c.lossyString("series"),
                tier = AchievementLossy.int(c, "tier") ?: 1,
                title = title,
                detail = c.lossyString("detail") ?: "",
                reward = AchievementLossy.int(c, "reward") ?: 0,
                target = AchievementLossy.int(c, "target") ?: 1,
                progress = AchievementLossy.int(c, "progress") ?: 0,
                achieved = c.lossyBool("achieved") ?: (achievedAtMs != null),
                claimed = claimed,
                achievedAtMs = achievedAtMs,
                claimedAtMs = claimedAtMs,
                sort = AchievementLossy.int(c, "sort") ?: Long.MAX_VALUE,
            )
        }

        private fun lossyClaim(element: JsonElement): Claim? {
            val obj = element as? JsonObject ?: return null
            val c = SwiftKeyed(obj)
            val key = c.lossyString("key")?.takeIf { it.isNotEmpty() } ?: return null
            return Claim.of(key, c.lossyString("title") ?: "", AchievementLossy.int(c, "reward") ?: 0)
        }
    }
}

/** 관대한 디코드 부품(Swift `AchievementLossyNumber` · `achievementLossyList` — DailyMissions 도 같은 부품을 쓴다). */
internal object AchievementLossy {
    /**
     * 숫자면 정수로(소수는 0 쪽으로 버림 — |v| < 9e15 일 때만), 글자 숫자("23")도 받는다(앞뒤 `.whitespaces` 를 지우고 Swift `Int(글자)`).
     * 칸이 없거나 null 이거나 아무것도 아니면 null.
     */
    fun int(c: SwiftKeyed, key: String): Long? {
        val value = c.element(key) ?: return null
        if (value is JsonNull) return null
        return number(value)
    }

    fun number(value: JsonElement): Long? {
        try {
            return SwiftValue.int(value)
        } catch (e: SwiftDecodingError) {
            // 다음 꼴로.
        }
        try {
            val d = SwiftValue.double(value)
            if (d.isFinite() && kotlin.math.abs(d) < 9.0e15) return d.toLong()
        } catch (e: SwiftDecodingError) {
            // 다음 꼴로.
        }
        val text = (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        return swiftIntParse(TextScalars.trimmingWhitespaces(text))
    }

    /** Swift `Int(String)` — 부호 한 글자(+/-) 다음 ASCII 숫자만, 범위 밖이면 null. */
    fun swiftIntParse(text: String): Long? {
        if (text.isEmpty()) return null
        val body = if (text[0] == '+' || text[0] == '-') text.substring(1) else text
        if (body.isEmpty() || body.any { it !in '0'..'9' }) return null
        return if (text[0] == '+') body.toLongOrNull() else text.toLongOrNull()
    }

    /** 배열이 아니면 null, 배열이면 원소들(원소마다 따로 읽는 것은 부르는 쪽). */
    fun list(c: SwiftKeyed, key: String): List<JsonElement>? {
        if (!c.contains(key)) return null
        return c.element(key) as? JsonArray
    }
}

/** 받기 실패 문구(맥 · 폰 · Android 한 벌). */
object AchievementNoticeText {
    const val claimFailed = "받지 못했어요. 잠시 후 다시 시도해 주세요"
    /** 실패한 **그 줄** 안의 문장(버튼 옆 보조 문장 자리 — 버튼이 남으니 다시 누르는 것이 재시도다). */
    const val claimFailedRow = "받지 못했어요 · 다시 눌러 주세요"
}

/** `achievement_claim(p_key)` · `daily_mission_claim(p_key)` 본문 — **키를 언제나 싣는다**(null = 받을 것 전부). */
data class AchievementClaimRequest(val pKey: String?) {
    fun body(): JsonObject = JsonObject(mapOf("p_key" to (pKey?.let { JsonPrimitive(it) } ?: JsonNull)))
}
