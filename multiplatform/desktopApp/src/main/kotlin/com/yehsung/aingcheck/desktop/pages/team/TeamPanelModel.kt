// 원본: Sources/check/CheckMenuView.swift:1994-2050(TeamPanel 머리 — 팀 이름 · 근무 수 칩 · 참여코드) · 2120-2163(행 · 빈 목록 · 정렬)
//       · 2169-2177(TeamWorkingCountChip — activeWorking 만) · 2196-2262(TeamMemberLiveRow — 현재 · 주 · 마지막 확인 N분 전)
//       · CheckComponents.swift:75-92(PresenceChip 문구) · 116-126(CountChip "N명 근무중")
// W3-c2 — 팀 패널 순수 모델. 판정·포맷은 core 것만 쓴다(사본 금지): presence/currentDuration/liveWeekly/hasMetWeeklyGoal =
// core/wire TeamMemberStatus, 시간 글자 = core/rules MenuBarStatusFormatter, 이름 비교 = core/rules NaturalKoCollation(Swift
// localizedStandardCompare 골든), 진행률 = core/wire TeamWeeklyGoal.
package com.yehsung.aingcheck.desktop.pages.team

import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus

/** 한 행(맥 TeamMemberRow 인자 그대로). */
data class TeamRow(
    val id: String?,
    val name: String,
    val presence: MemberPresence,
    val presenceLabel: String,
    val primaryDetail: String,
    val secondaryDetail: String?,
    val meetsWeeklyGoal: Boolean,
    val goalFraction: Double?,
    val isMe: Boolean,
    val avatarURL: String?,
)

data class TeamPanelUi(
    val teamName: String,
    val workingCountLabel: String,
    val inviteCode: String?,
    val rows: List<TeamRow>,
)

object TeamPanelModel {
    /** 맥 2154-2163: 근무 중(status == working — presence 가 아니라 원장 상태) 먼저, 같으면 이름 localizedStandardCompare 오름. */
    val memberOrder: Comparator<TeamMemberStatus> = Comparator { l, r ->
        val lw = l.status == WorkStatus.working
        val rw = r.status == WorkStatus.working
        if (lw != rw) (if (lw) -1 else 1) else NaturalKoCollation.compare(l.name, r.name)
    }

    fun sorted(members: List<TeamMemberStatus>): List<TeamMemberStatus> = members.sortedWith(memberOrder)

    /** PresenceChip(75-84). */
    fun presenceLabel(p: MemberPresence): String = when (p) {
        MemberPresence.ActiveWorking -> "근무중"
        is MemberPresence.StaleWorking -> "연결 끊김"
        MemberPresence.OffWork -> "근무종료"
    }

    /** 2229-2237: 라이브면 현재 경과, 연결 끊김이면 동결 값, 근무 종료면 0. */
    fun displayCurrentSeconds(m: TeamMemberStatus, p: MemberPresence, now: SwiftDate): Long = when (p) {
        MemberPresence.ActiveWorking -> m.currentDurationSeconds(now)
        is MemberPresence.StaleWorking -> p.frozenDurationSeconds
        MemberPresence.OffWork -> 0
    }

    /** 2247-2254: "주 H시간 MM분" · 근무(라이브·끊김)면 "현재 MM:SS · 주 …". */
    fun primaryDetail(m: TeamMemberStatus, p: MemberPresence, now: SwiftDate): String {
        val weekly = "주 ${MenuBarStatusFormatter.hoursMinutes(m.liveWeeklyDurationSeconds(now))}"
        return when (p) {
            MemberPresence.OffWork -> weekly
            else -> "현재 ${MenuBarStatusFormatter.duration(displayCurrentSeconds(m, p, now))} · $weekly"
        }
    }

    /** 2257-2262: 연결 끊김 + lastSeenAt 이 있을 때만 "마지막 확인 N분 전"(최소 1분). */
    fun secondaryDetail(m: TeamMemberStatus, p: MemberPresence, now: SwiftDate): String? {
        if (p !is MemberPresence.StaleWorking) return null
        val seen = m.lastSeenAt ?: return null
        val minutes = maxOf(1L, (now.timeIntervalSince(seen) / 60).toLong())
        return "마지막 확인 ${minutes}분 전"
    }

    /** 2175: 라이브 근무(activeWorking)만 센다 — 연결 끊김 제외. CountChip 문구(124). */
    fun workingCount(members: List<TeamMemberStatus>, now: SwiftDate): Int =
        members.count { it.presence(now) == MemberPresence.ActiveWorking }

    fun workingCountLabel(count: Int): String = "${count}명 근무중"

    /** 빈 목록 자리(2124-2126): 이름 "팀원" · 근무종료 칩 · 부제 = 동기화 문구. */
    fun emptyRow(syncMessage: String?): TeamRow = TeamRow(
        id = null, name = "팀원", presence = MemberPresence.OffWork, presenceLabel = presenceLabel(MemberPresence.OffWork),
        primaryDetail = syncMessage.orEmpty(), secondaryDetail = null, meetsWeeklyGoal = false, goalFraction = null,
        isMe = false, avatarURL = null,
    )

    fun row(m: TeamMemberStatus, now: SwiftDate, teamGoalSeconds: Long, myUserId: String?): TeamRow {
        val p = m.presence(now)
        return TeamRow(
            id = m.id,
            name = m.name,
            presence = p,
            presenceLabel = presenceLabel(p),
            primaryDetail = primaryDetail(m, p, now),
            secondaryDetail = secondaryDetail(m, p, now),
            meetsWeeklyGoal = m.hasMetWeeklyGoal(teamGoalSeconds, now),
            goalFraction = TeamWeeklyGoal(m.liveWeeklyDurationSeconds(now), teamGoalSeconds).progress,
            isMe = myUserId != null && m.id == myUserId,
            avatarURL = m.avatarURL?.absoluteString,
        )
    }

    fun build(
        teamName: String,
        members: List<TeamMemberStatus>,
        now: SwiftDate,
        teamGoalSeconds: Long,
        myUserId: String?,
        syncMessage: String?,
        inviteCode: String?,
    ): TeamPanelUi {
        val rows = sorted(members).map { row(it, now, teamGoalSeconds, myUserId) }
        return TeamPanelUi(
            teamName = teamName,
            workingCountLabel = workingCountLabel(workingCount(members, now)),
            inviteCode = inviteCode,
            rows = rows.ifEmpty { listOf(emptyRow(syncMessage)) },
        )
    }
}
