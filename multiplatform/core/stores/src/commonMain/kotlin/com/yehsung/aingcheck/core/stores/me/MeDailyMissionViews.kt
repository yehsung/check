// 원본: Sources/CheckMobileKit/Me/MeDailyMissionViews.swift:1-121 @ 1b8260d (122– 는 `#if os(iOS)` 화면 — W4-c)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.achievements.DailyMissionStatus

// 「일일 미션」 절(폰 1.0.13 — 서버 v0.3.64 `daily` · 맥 MissionPanel 의 일일 묶음 미러). 사용자 결정(2026-10-22): 미니게임·멀티 6개 각각
// 하루 1회 플레이 = 루비 5, **자정(KST)까지 안 받으면 사라진다**. 자리: 「이번 주 근무」 카드 **위**.
//  ① 제목 · 보상 · 순서는 서버 글자. ② 버튼 · 연출은 누적과 같은 부품(화면 갈래). ③ 그리는 값은 **순수 값**(이 파일) — 화면은 배치만.
//  ④ 날을 넘긴 줄에는 [받기]가 없다(코어 rows(serverNowMs)). ⑤ 일일의 떠 있음 · 실패는 누적과 따로 센다(장부가 두 벌).

/**
 * 일일 미션 절의 상태 — **갈래는 둘뿐**이다. 일일은 누적과 **같은 응답**으로 오고 그 전에는 이 서버에 일일이 있는지조차 모른다 —
 * 자리를 미리 잡으면 옛 서버에서 빈 카드가 섰다가 사라진다.
 */
sealed interface MeDailyMissionSection {
    data object Hidden : MeDailyMissionSection

    /** 줄(sort 순 — 코어가 정렬) + 지금 받을 수 있는 줄의 수 · 루비 합(**날을 넘긴 줄은 빠진 뒤**). */
    data class Loaded(
        override val rows: List<DailyMissionStatus.Mission>,
        override val claimableCount: Int,
        override val claimableRuby: Long,
    ) : MeDailyMissionSection

    /** 그려지는 줄(안 그리면 빈 목록). */
    val rows: List<DailyMissionStatus.Mission> get() = emptyList()

    /** 머리 오른쪽 "받을 보상 N개" · 탭 배지가 세는 수. */
    val claimableCount: Int get() = 0
    val claimableRuby: Long get() = 0

    companion object {
        /** 응답의 `daily` 와 **서버 시각 추정값**에서 고른다(날이 끝났으면 코어가 줄을 새 날의 모양으로 바꿔 준다). */
        fun make(daily: DailyMissionStatus?, serverNowMs: Long?): MeDailyMissionSection {
            if (daily == null) return Hidden
            val rows = daily.rows(serverNowMs)
            if (rows.isEmpty()) return Hidden
            val claimable = rows.filter { it.row.isClaimable }
            return Loaded(rows, claimable.size, claimable.sumOf { it.row.reward })
        }
    }
}

/**
 * 일일 줄 하나에 **실제로 그려지는 것**(순수). 세 상태: 진행 중 → 보상 칩 "+5" + 진행 "0/1" · 받을 수 있음 → [받기 +5](칩은 감춘다) ·
 * 받음 → 보상 칩 + "받음".
 */
data class MeDailyMissionRowContent(
    /** SF Symbol 이름(`MeText.dailyMissionIcon` — Android 는 ui SfSymbols 표가 잇는다). */
    val icon: String,
    val title: String,
    /** 보상 칩 글자("+5"). [받기] 가 서는 줄에서는 null. */
    val rewardChip: String?,
    /** [받기] 금액. null 이면 버튼이 없다(미달성 · 받음 · 날을 넘긴 줄). */
    val claimAmount: Long?,
    /** 진행 숫자("0/1"). 받을 수 있거나 받은 줄에서는 null. */
    val progress: String?,
    val claimedMark: String?,
    /** 보조 문장 — 서버 글자, 받기가 실패했으면 그 줄 안의 실패 문장. */
    val caption: String,
    val showsFailure: Boolean,
    val fraction: Double,
    val isClaimed: Boolean,
    val accessibilityLabel: String,
) {
    companion object {
        /** [failed] = 이 줄의 마지막 받기가 실패했는가. **[받기] 가 선 줄에서만** 실패를 말한다. */
        fun make(mission: DailyMissionStatus.Mission, failed: Boolean = false): MeDailyMissionRowContent {
            val row = mission.row
            val state = row.state
            val showsFailure = state == AchievementStatus.RowState.claimable && failed
            return MeDailyMissionRowContent(
                icon = MeText.dailyMissionIcon(mission.game),
                title = row.title,
                rewardChip = if (state == AchievementStatus.RowState.claimable) null else MeText.missionReward(row.reward),
                claimAmount = if (state == AchievementStatus.RowState.claimable) row.reward else null,
                progress = if (state == AchievementStatus.RowState.inProgress) MeText.missionProgress(row) else null,
                claimedMark = if (state == AchievementStatus.RowState.claimed) MeText.claimedMark else null,
                caption = if (showsFailure) MeText.claimFailed else row.detail,
                showsFailure = showsFailure,
                fraction = row.fraction,
                isClaimed = state == AchievementStatus.RowState.claimed,
                accessibilityLabel = MeText.missionAccessibility(row),
            )
        }
    }
}
