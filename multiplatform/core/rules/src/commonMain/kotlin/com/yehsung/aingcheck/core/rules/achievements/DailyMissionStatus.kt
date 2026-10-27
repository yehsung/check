// 원본: Sources/CheckCore/DailyMissions.swift:1-193 @ 1b8260d (194– `daily_mission_claim` 서비스 래퍼는 W1-d net — 배정표 round5)
package com.yehsung.aingcheck.core.rules.achievements

import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.text.TextScalars
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// 일일 미션(v0.3.64). 사용자 결정: 미니게임 일반·멀티 여섯 각각 하루 1회 플레이 = 루비 5(값은 응답이 말한다), **자정(KST)까지 [받기]를
// 안 누르면 사라진다**. 서버 정본은 daily_missions 마이그레이션. 이 파일이 지키는 것:
// ① 디코드가 통째로 죽지 않는다(daily 가 객체가 아니면 null — 일일 줄만 감춘다) ② 날을 넘긴 줄은 [받기]를 세우지 않는다
// ③ "받음은 되돌아가지 않는다"는 **같은 kst_day 안에서만**이다.

/** `daily` 묶음(조회 · 받기 응답 공통). 생성은 [of] — 같은 키는 앞의 것만, 줄은 sort 순(같으면 키). */
data class DailyMissionStatus(
    /** 이 응답의 하루(KST, "2026-10-22"). 비면 null — 그때는 같은 날인지 모르므로 받음을 이어 붙이지 않는다. */
    val kstDay: String? = null,
    /** 다음 KST 자정(epoch ms). 서버 시각이 이 값에 닿으면 이 응답의 줄은 어제의 것이다. */
    val resetAtMs: Long? = null,
    val missions: List<Mission> = emptyList(),
    val reportedClaimableCount: Long? = null,
    val reportedClaimableRuby: Long? = null,
) {
    /** 일일 미션 한 줄. 화면 부품은 누적 미션 줄과 같다([row]). */
    data class Mission(
        /** 세는 게임(`timing_bar` · `flappy` · `tetris` · `gomoku` · `chess` · `tetris_duel` · `crossy` …). 모르는 값이면 화면이 기본 아이콘. */
        val game: String,
        val row: AchievementStatus.Mission,
    ) {
        val id: String get() = row.key
        val key: String get() = row.key

        /** 새 날의 모양 — 진행 0 · 안 채움 · 안 받음. */
        val freshForNewDay: Mission
            get() = Mission(game, AchievementStatus.Mission.of(
                key = row.key, series = row.series, tier = row.tier, title = row.title, detail = row.detail, reward = row.reward,
                target = row.target, progress = 0, achieved = false, claimed = false, achievedAtMs = null, claimedAtMs = null, sort = row.sort,
            ))

        /** 받은 것으로 굳힌 사본(같은 날 늦게 온 옛 응답이 받은 줄을 [받기]로 되돌리지 않게). 진행은 목표로 채운다. */
        internal fun markedClaimed(previous: Mission): Mission = Mission(game, AchievementStatus.Mission.of(
            key = row.key, series = row.series, tier = row.tier, title = row.title, detail = row.detail, reward = row.reward,
            target = row.target, progress = row.target, achieved = true, claimed = true,
            achievedAtMs = row.achievedAtMs ?: previous.row.achievedAtMs, claimedAtMs = row.claimedAtMs ?: previous.row.claimedAtMs,
            sort = row.sort,
        ))
    }

    /** 서버 시각에서 이 응답의 하루가 이미 끝났는가. 리셋 시각이나 지금을 모르면 **아니다**. */
    fun hasRolledOver(serverNowMs: Long?): Boolean {
        val reset = resetAtMs ?: return false
        val now = serverNowMs ?: return false
        return now >= reset
    }

    /** 화면의 줄 — 하루가 끝났으면 새 날의 모양. */
    fun rows(serverNowMs: Long?): List<Mission> = if (hasRolledOver(serverNowMs)) missions.map { it.freshForNewDay } else missions

    fun claimable(serverNowMs: Long?): List<Mission> = rows(serverNowMs).filter { it.row.isClaimable }

    fun claimableCount(serverNowMs: Long?): Int = claimable(serverNowMs).size

    fun claimableRuby(serverNowMs: Long?): Long = claimable(serverNowMs).sumOf { it.row.reward }

    fun mission(key: String): Mission? = missions.firstOrNull { it.key == key }

    /** `previous` 위에 얹기 — **같은 kst_day 안에서만** 받음이 되돌아가지 않는다. 날이 바뀌었거나 어느 쪽이든 날을 모르면 이 응답 그대로. */
    fun merged(previous: DailyMissionStatus?): DailyMissionStatus {
        if (previous == null) return this
        val day = kstDay ?: return this
        if (previous.kstDay != day) return this
        val claimedBefore = LinkedHashMap<String, Mission>()
        for (mission in previous.missions) if (mission.row.claimed && mission.key !in claimedBefore) claimedBefore[mission.key] = mission
        if (claimedBefore.isEmpty()) return this
        return copy(missions = missions.map { mission ->
            val before = claimedBefore[mission.key]
            if (mission.row.claimed || before == null) mission else mission.markedClaimed(before)
        })
    }

    companion object {
        /** 일일 미션 키의 머리(`daily_`) — 서버 `daily_mission_defs()` 의 규칙. */
        const val keyPrefix = "daily_"

        /** 게임 → 일일 미션 키(판이 끝난 쪽은 게임 이름만 안다). */
        fun key(game: String): String = keyPrefix + game

        /** Swift `init(...)`: 빈 kstDay → null · 같은 키는 앞의 것만 · (sort, key) 순. */
        fun of(
            kstDay: String? = null, resetAtMs: Long? = null, missions: List<Mission> = emptyList(),
            reportedClaimableCount: Long? = null, reportedClaimableRuby: Long? = null,
        ): DailyMissionStatus {
            val seen = HashSet<String>()
            val unique = missions.filter { seen.add(it.key) }
                .sortedWith(compareBy<Mission> { it.row.sort }.thenBy(AchievementStatus.SWIFT_STRING) { it.key })
            return DailyMissionStatus(kstDay?.takeIf { it.isNotEmpty() }, resetAtMs, unique, reportedClaimableCount, reportedClaimableRuby)
        }

        /** 관대한 디코드 — 최상위가 객체가 아니면 null(부르는 쪽이 "일일 없음"으로 접는다). */
        fun decodeOrNull(element: JsonElement): DailyMissionStatus? {
            val obj = element as? JsonObject ?: return null
            val c = SwiftKeyed(obj)
            return of(
                kstDay = c.lossyString("kstDay")?.let(TextScalars::trimmingWhitespaces),
                resetAtMs = AchievementLossy.int(c, "resetAtMs"),
                missions = AchievementLossy.list(c, "missions")?.mapNotNull(::lossyMission) ?: emptyList(),
                reportedClaimableCount = AchievementLossy.int(c, "claimableCount"),
                reportedClaimableRuby = AchievementLossy.int(c, "claimableRuby"),
            )
        }

        /** 키나 제목이 없는 줄은 null. 게임 칸이 없거나 비면 키에서 읽는다(`daily_<게임>`), 그것도 아니면 빈 글. */
        private fun lossyMission(element: JsonElement): Mission? {
            val obj = element as? JsonObject ?: return null
            val c = SwiftKeyed(obj)
            val key = c.lossyString("key")?.takeIf { it.isNotEmpty() } ?: return null
            val title = c.lossyString("title")?.let(TextScalars::trimmingWhitespacesAndNewlines)?.takeIf { it.isNotEmpty() } ?: return null
            val achievedAtMs = AchievementLossy.int(c, "achievedAtMs")
            val claimedAtMs = AchievementLossy.int(c, "claimedAtMs")
            val claimed = c.lossyBool("claimed") ?: (claimedAtMs != null)
            val game = c.lossyString("game")?.takeIf { it.isNotEmpty() }
                ?: if (key.startsWith(keyPrefix)) key.substring(keyPrefix.length) else ""
            return Mission(game, AchievementStatus.Mission.of(
                key = key,
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
            ))
        }
    }
}
