// 원본: Sources/CheckMobileKit/Now/NowTeamRoster.swift:1 @ 23b91326 (NowTeamRosterRow · NowTeamRoster · NowTeamRosterRules)
//
// 우리 팀 전체 명단(지금 탭 [전체 보기] → push). 값 · 순수 계산만 둔다(문구는 [NowText] · 화면은 androidApp `TeamRosterScreen`).
// 정본은 iOS 다 — 양쪽 폰이 같아야 한다. iOS 는 맥 `TeamPanel` 을 견본으로 했다: 쉬는 사람까지 전원 · 근무 중 먼저 · 그 안은 이름순 · 사람마다 주간 누적과 목표 막대.
// 다만 시간은 맥 공식이 아니라 [NowTimeMath] 로 센다 — 이 화면의 내 줄이 지금 탭 내 카드와 다른 숫자를 말하면 안 된다(끊김 판정 시각도 [NowStore.presenceJudgedAt]).
//
// 서버 요청을 더하지 않는다: 재료는 지금 탭이 이미 받아 둔 `teamMembers` · `directory` 다.
//
// ★ 차단: **명단에서 빼지 않는다.** 차단 확인 시트가 "순위판·팀 현황의 이름은 그대로 남아요"라고 약속했고 맥 팀 카드도 빼지 않는다.
//   대신 ① 그 사람이 쓴 문장(상태메시지)은 보이지 않는다 — 서버가 서로 차단한 사람을 사람 목록에서 빼므로 보통은 재료부터 없고, 방금 차단해 옛 목록을 쥔 창만
//   `hiddenPeerIDs` 가 막는다. ② 이 화면에는 말 거는 입구가 없다.
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.rules.text.StatusMessage
import com.yehsung.aingcheck.core.stores.messages.MobileRelativeTime
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus

/** 명단 한 줄의 값(시각 `now` 기준). */
data class NowTeamRosterRow(
    val id: String,
    val name: String,
    val avatarURL: SwiftURL?,
    /** 센터 서버값(표시는 `CenterLabel` 한 곳). */
    val center: String?,
    val isMe: Boolean,
    /** 근무 중인가(`status == working` — 끊긴 사람도 여기다. 맥 정렬과 같은 기준). */
    val isWorking: Boolean,
    val isStale: Boolean,
    /**
     * 근무 중이고 **시작 시각을 알 때만**: 이번 세션 경과(끊겼으면 마지막 신호에서 멈춘 값). 근무 중인데 열린 세션 행이 안 왔으면
     * (다른 팀에 열린 세션 · 부분 응답) null 이다 — 0 으로 두면 몇 시간째 일하는 사람이 "방금 시작했어요"가 된다.
     */
    val elapsedSeconds: Int?,
    /** 끊긴 줄 부제 "마지막 확인 N분 전". */
    val lastSeenAt: SwiftDate?,
    /** 이미 `StatusMessage.display` 를 지난 값(null = 줄을 그리지 않는다). */
    val statusMessage: String?,
    val weekSeconds: Int,
    /** 1인당 목표 진행(0~1). */
    val goalProgress: Double,
    val isGoalMet: Boolean,
) {
    /** 톡백 한 줄: "민트, 근무 중, 3시간 20분째, 이번 주 9시간 0분". 화면 글자와 같은 사실을 말한다(줄이 자식을 합치므로 이 문장이 전부다). */
    fun spokenSummary(now: SwiftDate): String {
        val parts = mutableListOf(name)
        if (isMe) parts += "나"
        val elapsed = elapsedSeconds
        when {
            isStale -> parts += NowText.staleLastSeen(lastSeenAt?.let { MobileRelativeTime.text(it, now) })
            isWorking -> {
                parts += NowText.teamRosterWorking
                if (elapsed != null) parts += if (elapsed < 60) NowText.teamRosterJustStarted else "${NowFormat.spokenDuration(elapsed)}째"
            }
            else -> parts += NowText.teamRosterResting
        }
        parts += "${NowText.weekPrefix} ${NowFormat.spokenDuration(weekSeconds)}"
        if (statusMessage != null) parts += "상태메시지 $statusMessage"
        return parts.joinToString(", ")
    }
}

/** 명단 전체(근무 중 · 쉬는 중 두 묶음). */
data class NowTeamRoster(
    val working: List<NowTeamRosterRow>,
    val resting: List<NowTeamRosterRow>,
) {
    val isEmpty: Boolean get() = working.isEmpty() && resting.isEmpty()
    val count: Int get() = working.size + resting.size
}

object NowTeamRosterRules {
    /** 표시 이름. 서버 이름이 비었거나 공백뿐이면 폴백 — 이니셜도 이름도 없는 빈 줄을 그리지 않는다. */
    fun displayName(raw: String): String {
        val trimmed = raw.trim()
        return trimmed.ifEmpty { NowText.teamMemberFallbackName }
    }

    /**
     * 맥 `TeamPanel.sortedMembers` 와 같은 순서: 근무 중 먼저, 그 안은 이름순(`localizedStandardCompare`).
     * 같은 이름은 id 로 고정한다 — 새로고침마다 두 줄이 자리를 바꾸지 않게.
     */
    fun compare(lhs: NowTeamRosterRow, rhs: NowTeamRosterRow, collation: Collation): Int = when {
        lhs.isWorking != rhs.isWorking -> if (lhs.isWorking) -1 else 1
        else -> collation.compare(lhs.name, rhs.name).takeIf { it != 0 } ?: lhs.id.compareTo(rhs.id)
    }

    fun build(
        members: List<TeamMemberStatus>,
        directory: List<PokeDirectoryRow>,
        hiddenPeerIDs: Set<String>,
        me: String?,
        goalHours: Int,
        fetchedAt: SwiftDate,
        now: SwiftDate,
        presenceAt: SwiftDate,
        collation: Collation,
    ): NowTeamRoster {
        val directoryByID = LinkedHashMap<String, PokeDirectoryRow>()
        for (row in directory) if (row.userId !in directoryByID) directoryByID[row.userId] = row
        val goalSeconds = maxOf(1, goalHours) * 3600
        val rows = members.map { member ->
            val entry = directoryByID[member.id]
            val isWorking = member.status == WorkStatus.working
            val isStale = isWorking && NowTimeMath.isStale(member, presenceAt)
            val week = NowTimeMath.weekSeconds(member, fetchedAt, now, presenceAt)
            NowTeamRosterRow(
                id = member.id,
                name = displayName(member.name),
                avatarURL = member.avatarURL ?: SwiftURL.parse(entry?.avatarUrl),
                center = entry?.center,
                isMe = me != null && member.id == me,
                isWorking = isWorking,
                isStale = isStale,
                elapsedSeconds = if (isWorking && member.currentSessionStartedAt != null) NowTimeMath.elapsedSeconds(member, now, presenceAt) else null,
                lastSeenAt = if (isStale) member.lastSeenAt ?: member.updatedAt else null,
                statusMessage = if (member.id in hiddenPeerIDs) null else StatusMessage.display(entry?.statusMessage),
                weekSeconds = week,
                goalProgress = TeamWeeklyGoal(week.toLong(), goalSeconds.toLong()).progress,
                isGoalMet = week >= goalSeconds,
            )
        }.sortedWith { l, r -> compare(l, r, collation) }
        return NowTeamRoster(working = rows.filter { it.isWorking }, resting = rows.filter { !it.isWorking })
    }
}
