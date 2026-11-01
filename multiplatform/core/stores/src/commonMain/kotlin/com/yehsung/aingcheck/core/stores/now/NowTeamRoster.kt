// 원본: Sources/check/CheckMenuView.swift:2229(sortedMembers) · :2271(TeamMemberLiveRow) · :2322(primaryDetail) · :2333(secondaryDetail) · Sources/check/CheckComponents.swift:75(PresenceChip)
//
// 우리 팀 전체 명단 한 줄의 값(맥 팀 패널 규칙). iOS 에는 짝이 없다 — 맥 규칙을 폰 값으로 옮겼다.
// 맥과 다른 점 하나: 맥은 낡은 판을 스스로 다시 받아 지금 시각으로 판정하지만, 폰은 받은 시각에 판정하고 다음 응답까지 유지한다([NowStore.presenceJudgedAt]).
// 그래서 주간 값은 내 상태 카드와 같은 [NowTimeMath.weekSeconds] 로 센다 — 내 줄과 카드의 숫자가 갈리면 안 된다.
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.text.StatusMessage
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus

/** 명단 한 줄. */
data class NowTeamRosterRow(
    val id: String,
    val name: String,
    val avatarURL: SwiftURL?,
    /** 센터 서버값(표시는 `CenterLabel` 한 곳). */
    val center: String?,
    /** 이미 `StatusMessage.display` 를 지난 값(null = 줄을 그리지 않는다). */
    val statusMessage: String?,
    val presence: MemberPresence,
    /** "주 3시간 05분" · 근무 중이면 "현재 25:00 · 주 3시간 05분". */
    val primaryDetail: String,
    /** 끊긴 사람만 "마지막 확인 N분 전". */
    val secondaryDetail: String?,
    /** 1인당 주간 목표를 채웠다(글자 옆 ✓). */
    val meetsWeeklyGoal: Boolean,
    /** 목표 막대 0~1. */
    val goalFraction: Double,
    val isMe: Boolean,
) {
    /** 막대 오른쪽 "62%"(맥 `TeamMemberRow.goalBar` — 반올림 · 100 상한). */
    val goalPercent: Int get() = com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero(goalFraction * 100).toInt()
}

object NowTeamRoster {
    /** 맥 `PresenceChip.label`. */
    fun presenceLabel(presence: MemberPresence): String = when (presence) {
        MemberPresence.ActiveWorking -> "근무중"
        is MemberPresence.StaleWorking -> "연결 끊김"
        MemberPresence.OffWork -> "근무종료"
    }

    /** 맥 `TeamWorkingCountChip`: 라이브 근무만 센다(연결 끊김 제외). */
    fun workingCount(rows: List<NowTeamRosterRow>): Int = rows.count { it.presence == MemberPresence.ActiveWorking }

    fun workingCountLabel(count: Int): String = "${count}명 근무중"

    /** 맥 `TeamPanel.sortedMembers`: 근무(원장 status — 끊김 포함) 먼저, 같은 무리는 이름. 이름까지 같으면 id(입력 순서가 줄을 흔들지 않게). */
    fun sorted(members: List<TeamMemberStatus>, collation: Collation): List<TeamMemberStatus> = members.sortedWith { l, r ->
        val lw = l.status == WorkStatus.working
        val rw = r.status == WorkStatus.working
        when {
            lw != rw -> if (lw) -1 else 1
            else -> collation.compare(l.name, r.name).takeIf { it != 0 } ?: l.id.compareTo(r.id)
        }
    }

    /** 맥 `TeamMemberLiveRow.primaryDetail`. */
    fun primaryDetail(weekSeconds: Int, currentSeconds: Int, presence: MemberPresence): String {
        val weekly = "주 ${MenuBarStatusFormatter.hoursMinutes(weekSeconds.toLong())}"
        return if (presence == MemberPresence.OffWork) weekly else "현재 ${MenuBarStatusFormatter.duration(currentSeconds.toLong())} · $weekly"
    }

    /** 맥 `TeamMemberLiveRow.secondaryDetail`: 끊긴 사람만, 최소 1분. */
    fun secondaryDetail(presence: MemberPresence, seen: SwiftDate?, now: SwiftDate): String? {
        if (presence !is MemberPresence.StaleWorking || seen == null) return null
        return "마지막 확인 ${maxOf(1L, (now.timeIntervalSince(seen) / 60).toLong())}분 전"
    }

    fun rows(
        members: List<TeamMemberStatus>,
        directory: List<PokeDirectoryRow>,
        myUserID: String?,
        goalSeconds: Long,
        fetchedAt: SwiftDate,
        now: SwiftDate,
        judgedAt: SwiftDate,
        collation: Collation,
    ): List<NowTeamRosterRow> {
        val directoryByID = LinkedHashMap<String, PokeDirectoryRow>()
        for (row in directory) if (row.userId !in directoryByID) directoryByID[row.userId] = row
        return sorted(members, collation).map { member ->
            val entry = directoryByID[member.id]
            val presence = member.presence(judgedAt)
            val week = NowTimeMath.weekSeconds(member, fetchedAt, now, judgedAt)
            val goal = TeamWeeklyGoal(week.toLong(), goalSeconds)
            NowTeamRosterRow(
                id = member.id,
                name = member.name,
                avatarURL = member.avatarURL ?: SwiftURL.parse(entry?.avatarUrl),
                center = entry?.center,
                statusMessage = StatusMessage.display(entry?.statusMessage),
                presence = presence,
                primaryDetail = primaryDetail(week, NowTimeMath.elapsedSeconds(member, now, judgedAt), presence),
                secondaryDetail = secondaryDetail(presence, member.lastSeenAt ?: member.updatedAt, now),
                meetsWeeklyGoal = goal.isComplete,
                goalFraction = goal.progress,
                isMe = myUserID != null && member.id == myUserID,
            )
        }
    }
}
